package worker

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	amqplib "github.com/rabbitmq/amqp091-go"

	"github.com/digital-cip/chunker/internal/amqp"
	"github.com/digital-cip/chunker/internal/chunk"
	"github.com/digital-cip/chunker/internal/config"
	"github.com/digital-cip/chunker/internal/db"
	"github.com/digital-cip/chunker/internal/log"
	"github.com/digital-cip/chunker/internal/metrics"
)

type Envelope struct {
	MessageID      string                 `json:"message_id"`
	IdempotencyKey string                 `json:"idempotency_key"`
	TraceID        string                 `json:"trace_id"`
	Stage          string                 `json:"stage"`
	DocumentID     int64                  `json:"document_id"`
	TenantID       string                 `json:"tenant_id"`
	Attempt        int                    `json:"attempt"`
	PublishedAt    string                 `json:"published_at"`
	Payload        map[string]any         `json:"payload"`
}

var (
	ErrPermanent = errors.New("permanent")
	ErrTransient = errors.New("transient")
)

type Worker struct {
	Cfg  config.Config
	DB   *db.Pool
	AMQP *amqp.Client
}

func Run(ctx context.Context, w *Worker) error {
	msgs, err := w.AMQP.Ch.Consume(w.Cfg.QueueIn, "chunker", false, false, false, false, nil)
	if err != nil {
		return err
	}

	log.L.Info("worker.starting", "queue", w.Cfg.QueueIn, "stage", "chunk")

	for {
		select {
		case <-ctx.Done():
			log.L.Info("worker.shutdown")
			return nil
		case d, ok := <-msgs:
			if !ok {
				return errors.New("amqp channel closed")
			}
			w.handle(ctx, d)
		}
	}
}

func (w *Worker) handle(ctx context.Context, d amqplib.Delivery) {
	metrics.InFlight.WithLabelValues("chunk").Inc()
	started := time.Now()
	defer func() {
		metrics.Duration.WithLabelValues("chunk").Observe(time.Since(started).Seconds())
		metrics.InFlight.WithLabelValues("chunk").Dec()
	}()

	var env Envelope
	if err := json.Unmarshal(d.Body, &env); err != nil {
		log.L.Error("envelope.invalid", "error", err.Error())
		metrics.Failed.WithLabelValues("chunk", "invalid_envelope").Inc()
		_ = d.Ack(false)
		return
	}
	if env.Attempt == 0 {
		env.Attempt = 1
	}

	log.L.Info("message.received", "stage", "chunk", "message_id", env.MessageID,
		"document_id", env.DocumentID, "attempt", env.Attempt)

	err := w.process(ctx, env)
	switch {
	case err == nil:
		metrics.Processed.WithLabelValues("chunk").Inc()
		_ = d.Ack(false)
		log.L.Info("message.acked", "message_id", env.MessageID, "document_id", env.DocumentID)
	case errors.Is(err, ErrPermanent):
		metrics.Failed.WithLabelValues("chunk", "permanent").Inc()
		log.L.Error("message.failed.permanent", "error", err.Error(), "message_id", env.MessageID)
		_ = d.Ack(false)
	default:
		if env.Attempt >= w.Cfg.MaxRetries {
			metrics.Failed.WithLabelValues("chunk", "exhausted").Inc()
			log.L.Error("message.failed.exhausted", "error", err.Error(),
				"message_id", env.MessageID, "attempt", env.Attempt)
			if pubErr := w.publishDLQ(env, d); pubErr != nil {
				log.L.Error("dlq.publish.error", "error", pubErr.Error())
			}
			_ = d.Ack(false)
			return
		}
		env.Attempt++
		metrics.Retried.WithLabelValues("chunk").Inc()
		log.L.Warn("message.retry", "error", err.Error(),
			"message_id", env.MessageID, "attempt", env.Attempt)
		if pubErr := w.publishRetry(env); pubErr != nil {
			log.L.Error("retry.publish.error", "error", pubErr.Error())
		}
		_ = d.Ack(false)
	}
}

func (w *Worker) process(ctx context.Context, env Envelope) error {
	if env.DocumentID == 0 {
		return fmt.Errorf("%w: missing document_id", ErrPermanent)
	}

	if seen, err := w.DB.AlreadyProcessed(ctx, env.MessageID); err != nil {
		return fmt.Errorf("%w: idempotency check failed: %v", ErrTransient, err)
	} else if seen {
		log.L.Info("message.duplicate.skipped", "message_id", env.MessageID)
		return nil
	}

	doc, err := w.DB.FetchDocument(ctx, env.DocumentID)
	if err != nil {
		return fmt.Errorf("%w: fetch: %v", ErrTransient, err)
	}
	if doc == nil {
		return fmt.Errorf("%w: document not found", ErrPermanent)
	}
	if doc.Status == "embedded" || doc.Status == "failed" {
		log.L.Info("document.terminal.skipped", "document_id", doc.ID, "status", doc.Status)
		return nil
	}
	if doc.RawText == "" {
		return fmt.Errorf("%w: document has no raw_text", ErrPermanent)
	}

	if err := w.DB.UpdateStatus(ctx, doc.ID, "chunking", nil, nil, nil); err != nil {
		return fmt.Errorf("%w: status update: %v", ErrTransient, err)
	}
	_ = w.DB.RecordEvent(ctx, doc.ID, "chunk", doc.Status, "chunking", "Chunking started", nil)

	pieces := chunk.Split(doc.RawText, w.Cfg.ChunkSize, w.Cfg.ChunkOverlap)
	if len(pieces) == 0 {
		reason := "no chunks produced"
		now := time.Now().UTC()
		_ = w.DB.UpdateStatus(ctx, doc.ID, "failed", nil, &reason, &now)
		_ = w.DB.RecordEvent(ctx, doc.ID, "chunk", "chunking", "failed", reason, nil)
		return fmt.Errorf("%w: %s", ErrPermanent, reason)
	}

	rows := make([]db.ChunkRow, 0, len(pieces))
	for i, p := range pieces {
		rows = append(rows, db.ChunkRow{
			Position:   i,
			Content:    p,
			TokenCount: chunk.ApproxTokenCount(p),
			Metadata:   map[string]any{},
		})
	}
	if err := w.DB.InsertChunks(ctx, doc.ID, rows); err != nil {
		return fmt.Errorf("%w: insert chunks: %v", ErrTransient, err)
	}

	now := time.Now().UTC()
	if err := w.DB.UpdateStatus(ctx, doc.ID, "chunked", &now, nil, nil); err != nil {
		return fmt.Errorf("%w: status update: %v", ErrTransient, err)
	}
	_ = w.DB.RecordEvent(ctx, doc.ID, "chunk", "chunking", "chunked",
		fmt.Sprintf("Created %d chunks", len(rows)),
		map[string]any{"chunks": len(rows)})

	if err := w.DB.RecordProcessed(ctx, env.MessageID, env.IdempotencyKey, "chunk",
		w.Cfg.ServiceName, doc.ID, map[string]any{"chunks": len(rows)}); err != nil {
		log.L.Warn("processed_messages.insert.error", "error", err.Error())
	}

	return w.publishNext(env, len(rows))
}

func (w *Worker) publishNext(env Envelope, chunkCount int) error {
	next := Envelope{
		MessageID:      uuid.NewString(),
		IdempotencyKey: fmt.Sprintf("%d:embed", env.DocumentID),
		TraceID:        env.TraceID,
		Stage:          "embed",
		DocumentID:     env.DocumentID,
		TenantID:       env.TenantID,
		Attempt:        1,
		PublishedAt:    time.Now().UTC().Format(time.RFC3339),
		Payload:        map[string]any{"chunks": chunkCount},
	}
	body, _ := json.Marshal(next)
	return w.AMQP.Ch.PublishWithContext(context.Background(),
		w.Cfg.Exchange, w.Cfg.RoutingKeyOut, false, false,
		amqplib.Publishing{
			ContentType:  "application/json",
			DeliveryMode: amqplib.Persistent,
			MessageId:    next.MessageID,
			Body:         body,
			Headers: amqplib.Table{
				"x-idempotency-key": next.IdempotencyKey,
				"x-attempt":         int32(1),
				"x-stage":           "embed",
				"x-document-id":     env.DocumentID,
			},
		})
}

func (w *Worker) publishRetry(env Envelope) error {
	body, _ := json.Marshal(env)
	return w.AMQP.Ch.PublishWithContext(context.Background(),
		w.Cfg.RetryExchange, "ingest.chunk.retry", false, false,
		amqplib.Publishing{
			ContentType:  "application/json",
			DeliveryMode: amqplib.Persistent,
			MessageId:    env.MessageID,
			Body:         body,
			Headers: amqplib.Table{
				"x-attempt": int32(env.Attempt),
				"x-stage":   "chunk",
			},
		})
}

func (w *Worker) publishDLQ(env Envelope, d amqplib.Delivery) error {
	return w.AMQP.Ch.PublishWithContext(context.Background(),
		w.Cfg.DLXExchange, "ingest.chunk.dlq", false, false,
		amqplib.Publishing{
			ContentType:  "application/json",
			DeliveryMode: amqplib.Persistent,
			MessageId:    env.MessageID,
			Body:         d.Body,
			Headers:      d.Headers,
		})
}
