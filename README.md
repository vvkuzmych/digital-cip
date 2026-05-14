# Digital Content Infrastructure Platform (digital-cip)

Local-first ingestion pipeline for documents. A pragmatic, AWS-free implementation
of the same distributed patterns you'd build on top of S3 / SQS / Step Functions:

| Cloud (AWS)         | Local equivalent here                  |
| ------------------- | -------------------------------------- |
| S3                  | MinIO (S3-compatible object storage)   |
| SQS / SNS           | RabbitMQ (topics, DLX, retry queues)   |
| Step Functions      | Document state machine (in PostgreSQL) |
| ECS / Lambda        | Containerized workers (Go + Python)    |
| CloudWatch / X-Ray  | Prometheus + Grafana + structured logs |
| ElastiCache         | Redis (cache, rate-limit, idempotency) |

## High-level architecture

```
        ┌─────────┐    HTTP/JSON     ┌──────────────────┐
client ─► Rails API ───────────────► PostgreSQL (+pgvector)
        └────┬────┘                  ▲   ▲     ▲     ▲
             │  upload                │   │     │     │
             ▼                        │   │     │     │
        ┌─────────┐                   │   │     │     │
        │  MinIO  │ ◄── reads/writes ─┘   │     │     │
        └─────────┘                       │     │     │
             │                            │     │     │
             ▼                            │     │     │
        ┌──────────┐  ingest.ocr   ┌──────┴───┐ │     │
        │ RabbitMQ │ ────────────► │ OCR (py) │ │     │
        │          │ ◄──ack/nack── └────┬─────┘ │     │
        │          │                    │       │     │
        │          │  ingest.chunk      ▼  ┌────┴─────┐
        │          │ ─────────────────────►│ Chunker  │
        │          │ ◄──ack/nack───────────│   (Go)   │
        │          │                        └────┬─────┘
        │          │  ingest.embed              ▼
        │          │ ────────────────────►┌──────────┐
        │          │ ◄────────────────────│ Embedder │
        └──────────┘                       │  (py)    │
                                           └──────────┘
```

All messages carry an `idempotency_key`; workers verify state in PostgreSQL before
performing work, so duplicate delivery is safe. Failed messages go through a
delayed retry queue (RabbitMQ DLX with TTL) up to N times, then to a dead-letter
queue for inspection.

## Components

- **api/** — Rails 8 API. Accepts uploads, persists `Document` records,
  publishes `ingest.ocr` messages, exposes status/search endpoints, runs the
  state machine.
- **workers/ocr/** — Python worker. Pulls files from MinIO, runs Tesseract OCR,
  writes raw text back, publishes `ingest.chunk`.
- **workers/chunker/** — Go worker. Splits text into overlapping chunks,
  persists `document_chunks`, publishes `ingest.embed`.
- **workers/embedder/** — Python worker. Generates embeddings with
  `sentence-transformers`, writes vectors into pgvector.
- **infra/** — RabbitMQ definitions, Postgres bootstrap, Prometheus + Grafana
  configuration.

## Quick start

```bash
cp .env.example .env
# Rails is published on host port 3040 by default (avoids clashes with a local app on 3000).
# To use 3000 instead, set API_HTTP_PORT=3000 in .env.
make up           # docker compose up -d
make migrate      # rails db:create db:migrate
make seed         # optional
make smoke        # upload a sample PDF and watch it flow through

# UIs (Rails/Grafana host ports: API_HTTP_PORT default 3040, GRAFANA_HTTP_PORT default 3010)
open http://localhost:3040          # Rails API
open http://localhost:15672         # RabbitMQ (guest / guest)
open http://localhost:9001          # MinIO (minio / minio12345)
open http://localhost:3010          # Grafana (admin / admin; default 3010)
open http://localhost:9090          # Prometheus
```

## Troubleshooting `ERR_CONNECTION_REFUSED`

The browser only reaches a service if **Docker is up** and you use the **host port** Compose published (not always 3000).

1. From the `digital-cip` directory: `make doctor` — prints `docker compose ps` and curls `http://localhost:<API_HTTP_PORT>/healthz`.
2. Print URLs: `make urls` (defaults: API **3040**, Grafana **3010**).
3. If the API container is **exited** or **unhealthy**: `make logs SERVICE=api` (first boot can take a while while gems install).
4. After changing `api/Gemfile` or `api/Gemfile.lock`, run **`make bundle`** then **`docker compose up -d api`** so the named bundle volume picks up new gems.

## API surface

```
POST   /api/v1/documents              upload (multipart) → 202 + document_id
GET    /api/v1/documents/:id          status + metadata
GET    /api/v1/documents/:id/chunks   chunks (paginated)
POST   /api/v1/documents/:id/retry    re-enqueue failed document
GET    /healthz                       liveness
GET    /readyz                        readiness (db, queue, storage)
GET    /metrics                       Prometheus metrics
```

## Document state machine

```
        ┌──────────┐
        │ uploaded │
        └────┬─────┘
             │ enqueue ingest.ocr
             ▼
   ┌──────────────────┐  fail (N retries) ┌──────────┐
   │ ocr_processing   │ ─────────────────►│  failed  │
   └────┬─────────────┘                   └──────────┘
        │ ok
        ▼
   ┌──────────────────┐
   │  ocr_completed   │
   └────┬─────────────┘
        │ enqueue ingest.chunk
        ▼
   ┌──────────────────┐  fail ┌──────────┐
   │     chunking     │ ─────►│  failed  │
   └────┬─────────────┘       └──────────┘
        │ ok
        ▼
   ┌──────────────────┐
   │     chunked      │
   └────┬─────────────┘
        │ enqueue ingest.embed
        ▼
   ┌──────────────────┐  fail ┌──────────┐
   │    embedding     │ ─────►│  failed  │
   └────┬─────────────┘       └──────────┘
        │ ok
        ▼
   ┌──────────────────┐
   │     embedded     │  (terminal success)
   └──────────────────┘
```

Every transition is recorded in `processing_events` for auditability.

## Retries & idempotency

- Each published message carries a UUID `message_id` and a stable
  `idempotency_key` (`document_id:stage`).
- Workers consult `processed_messages` before committing side-effects.
- On NACK, RabbitMQ moves the message into `ingest.<stage>.retry` (TTL = 5s,
  10s, 30s, ...). When TTL expires, the broker republishes it to the original
  queue. After `max_retries` failures it lands in `ingest.<stage>.dlq`.

## Observability

- Every worker exposes `/metrics` (Prometheus) on its own port:
  - API:      same host port as Rails (`API_HTTP_PORT`, default `3040`) → `/metrics`
  - OCR:      `http://localhost:9100/metrics`
  - Chunker:  `http://localhost:9101/metrics`
  - Embedder: `http://localhost:9102/metrics`
  - RabbitMQ: `http://localhost:15692/metrics`
- All processes emit JSON logs with `trace_id`, `document_id`, `stage`.
- Grafana ships with a pre-provisioned dashboard at
  `http://localhost:3010/d/ingestion` (or `http://localhost:${GRAFANA_HTTP_PORT}/d/ingestion` if you override it).

## Repository layout

```
digital-cip/
├── docker-compose.yml          # whole stack
├── Makefile                    # task shortcuts
├── api/                        # Rails 8 API (publisher + state machine)
├── workers/
│   ├── ocr/                    # Python worker: PDF/image -> text
│   ├── chunker/                # Go worker: text -> overlapping chunks
│   └── embedder/               # Python worker: chunks -> pgvector
├── infra/
│   ├── postgres/init.sql       # enables pgvector
│   ├── rabbitmq/definitions.json   # exchanges, queues, DLX, retry
│   ├── minio/bootstrap.sh
│   ├── prometheus/prometheus.yml
│   └── grafana/                # provisioned datasource + dashboard
├── scripts/smoke.sh            # end-to-end smoke test
└── docs/architecture.md        # deeper design notes
```

See [`docs/architecture.md`](docs/architecture.md) for deeper notes.
