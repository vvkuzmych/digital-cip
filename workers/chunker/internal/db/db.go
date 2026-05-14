package db

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/digital-cip/chunker/internal/config"
)

type Pool struct{ *pgxpool.Pool }

func New(ctx context.Context, cfg config.Config) (*Pool, error) {
	dsn := fmt.Sprintf(
		"host=%s port=%d user=%s password=%s dbname=%s sslmode=disable",
		cfg.PGHost, cfg.PGPort, cfg.PGUser, cfg.PGPassword, cfg.PGDB,
	)
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		return nil, err
	}
	return &Pool{Pool: pool}, nil
}

type Document struct {
	ID          int64
	TenantID    string
	Status      string
	ContentType string
	RawText     string
	ObjectKey   string
}

func (p *Pool) FetchDocument(ctx context.Context, id int64) (*Document, error) {
	row := p.QueryRow(ctx,
		`SELECT id, tenant_id, status, content_type, COALESCE(raw_text, ''), object_key
		 FROM documents WHERE id = $1`, id)
	var d Document
	if err := row.Scan(&d.ID, &d.TenantID, &d.Status, &d.ContentType, &d.RawText, &d.ObjectKey); err != nil {
		if err == pgx.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &d, nil
}

func (p *Pool) AlreadyProcessed(ctx context.Context, messageID string) (bool, error) {
	row := p.QueryRow(ctx, `SELECT 1 FROM processed_messages WHERE message_id = $1`, messageID)
	var one int
	if err := row.Scan(&one); err != nil {
		if err == pgx.ErrNoRows {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

func (p *Pool) RecordProcessed(ctx context.Context, messageID, idemKey, stage, consumer string, documentID int64, result map[string]any) error {
	js, _ := json.Marshal(result)
	_, err := p.Exec(ctx, `
		INSERT INTO processed_messages
			(message_id, idempotency_key, stage, document_id, consumer, result, processed_at)
		VALUES ($1, $2, $3, $4, $5, $6, NOW())
		ON CONFLICT (message_id) DO NOTHING`,
		messageID, idemKey, stage, documentID, consumer, string(js))
	return err
}

func (p *Pool) RecordEvent(ctx context.Context, documentID int64, stage, fromState, toState, message string, payload map[string]any) error {
	js, _ := json.Marshal(payload)
	_, err := p.Exec(ctx, `
		INSERT INTO processing_events
			(document_id, stage, from_state, to_state, actor, message, payload, created_at)
		VALUES ($1, $2, $3, $4, 'system', $5, $6, NOW())`,
		documentID, stage, fromState, toState, message, string(js))
	return err
}

func (p *Pool) UpdateStatus(ctx context.Context, documentID int64, status string, chunkedAt *time.Time, failureReason *string, failedAt *time.Time) error {
	_, err := p.Exec(ctx, `
		UPDATE documents
		SET status = $2,
		    chunked_at = COALESCE($3, chunked_at),
		    failure_reason = COALESCE($4, failure_reason),
		    failed_at = COALESCE($5, failed_at),
		    updated_at = NOW()
		WHERE id = $1`,
		documentID, status, chunkedAt, failureReason, failedAt)
	return err
}

func (p *Pool) InsertChunks(ctx context.Context, documentID int64, chunks []ChunkRow) error {
	tx, err := p.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, `DELETE FROM document_chunks WHERE document_id = $1`, documentID); err != nil {
		return err
	}

	batch := &pgx.Batch{}
	for _, c := range chunks {
		md, _ := json.Marshal(c.Metadata)
		batch.Queue(`INSERT INTO document_chunks (document_id, position, content, token_count, metadata, created_at, updated_at)
		             VALUES ($1, $2, $3, $4, $5, NOW(), NOW())`,
			documentID, c.Position, c.Content, c.TokenCount, string(md))
	}

	br := tx.SendBatch(ctx, batch)
	for range chunks {
		if _, err := br.Exec(); err != nil {
			br.Close()
			return err
		}
	}
	if err := br.Close(); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

type ChunkRow struct {
	Position   int
	Content    string
	TokenCount int
	Metadata   map[string]any
}
