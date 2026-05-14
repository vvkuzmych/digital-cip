# Architecture notes

## Why these choices

- **PostgreSQL with pgvector** keeps documents, chunks and vectors in one ACID
  store. A single transaction can move a document between states and write
  audit rows, which is exactly what AWS Step Functions buys you in the cloud.
- **RabbitMQ** is the SQS analogue. It supports per-message TTL via the
  Dead-Letter Exchange pattern, which gives us free exponential back-off
  without pulling in a scheduler. Topic exchanges let one publisher target
  several stages via routing keys (`ingest.ocr`, `ingest.chunk`,
  `ingest.embed`).
- **MinIO** is wire-compatible with S3, so the same `aws-sdk` clients used in
  the cloud version work unchanged. Buckets are created on boot from
  `infra/minio/bootstrap.sh`.
- **Redis** is used by the API for rate-limiting and idempotency caches, and
  by workers as a fast lookup for "have I seen this `message_id` recently?".
- **Sentence-transformers** running locally gives us deterministic embeddings
  without any cloud round-trip; swap the model name to plug a different
  provider in.

## Message shape

Every ingestion message uses the same envelope:

```json
{
  "message_id":     "01J9Q...",       // ULID, unique per publish
  "idempotency_key":"doc_42:chunk",   // stable per (document, stage)
  "trace_id":       "...",            // for log correlation
  "stage":          "chunk",
  "document_id":    42,
  "payload": {                        // stage-specific
    "object_key":   "raw/42.pdf",
    "tenant_id":    "default"
  },
  "attempt":        1,
  "published_at":   "2025-01-01T00:00:00Z"
}
```

## Exchanges and queues

For each stage `S` in `{ocr, chunk, embed}`:

| Object                       | Type               | Notes                                      |
| ---------------------------- | ------------------ | ------------------------------------------ |
| `ingest` (exchange)          | topic              | publisher writes to this                   |
| `ingest.S`                   | queue              | bound with routing key `ingest.S`          |
| `ingest.S.retry`             | queue (TTL=5s+)    | DLX target on NACK; expires back to main   |
| `ingest.S.dlq`               | queue              | terminal failures after max retries        |

A worker that fails publishes the message to `ingest.S.retry` with `attempt+1`
in the headers. Once `attempt > MAX_RETRIES`, it goes to `ingest.S.dlq`
instead.

## Failure semantics

- **Transient** failure (network, 5xx from an external service) — NACK with
  requeue=false, ends up in retry queue. After back-off, RabbitMQ replays the
  message.
- **Permanent** failure (corrupt PDF, OCR returns empty after N attempts) —
  worker marks the document `failed`, records the reason in
  `processing_events`, sends the message to DLQ.

## Idempotency

We use two layers:

1. **At the message level** — `processed_messages(message_id PK)` table. If a
   worker sees a `message_id` it already processed, it ACKs without doing
   work. Cleaned up after 30 days.
2. **At the state level** — every state transition is guarded. The chunker
   refuses to operate on a document not in `ocr_completed` (or `chunking`,
   for resumption). This makes the pipeline safe to replay.

## Local development tips

- `make logs SERVICE=ocr-worker` tails one container.
- `make psql` drops you into the app database.
- `make rabbit-purge` empties all queues (useful when iterating).
- `make smoke` uploads a known PDF and polls until it reaches `embedded`.
