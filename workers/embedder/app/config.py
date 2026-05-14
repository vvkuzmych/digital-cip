import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Config:
    service_name: str = 'embedder-worker'
    stage_in: str = 'embed'
    queue_in: str = 'ingest.embed'
    exchange: str = 'ingest'

    rabbitmq_url: str = os.getenv('RABBITMQ_URL', 'amqp://guest:guest@rabbitmq:5672')

    pg_host: str = os.getenv('POSTGRES_HOST', 'postgres')
    pg_port: int = int(os.getenv('POSTGRES_PORT', '5432'))
    pg_user: str = os.getenv('POSTGRES_USER', 'cip')
    pg_password: str = os.getenv('POSTGRES_PASSWORD', 'cip')
    pg_db: str = os.getenv('POSTGRES_DB', 'cip_development')

    embedding_model: str = os.getenv('EMBEDDING_MODEL', 'sentence-transformers/all-MiniLM-L6-v2')
    embedding_dim: int = int(os.getenv('EMBEDDING_DIM', '384'))
    batch_size: int = int(os.getenv('EMBEDDING_BATCH_SIZE', '32'))

    max_retries: int = int(os.getenv('MAX_RETRIES', '5'))
    metrics_port: int = int(os.getenv('METRICS_PORT', '9102'))
    concurrency: int = int(os.getenv('WORKER_CONCURRENCY', '2'))
    log_level: str = os.getenv('LOG_LEVEL', 'info')


CONFIG = Config()
