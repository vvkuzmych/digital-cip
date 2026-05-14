import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Config:
    service_name: str = 'ocr-worker'
    stage_in: str = 'ocr'
    stage_out: str = 'chunk'
    queue_in: str = 'ingest.ocr'
    routing_key_out: str = 'ingest.chunk'
    exchange: str = 'ingest'

    rabbitmq_url: str = os.getenv('RABBITMQ_URL', 'amqp://guest:guest@rabbitmq:5672')

    pg_host: str = os.getenv('POSTGRES_HOST', 'postgres')
    pg_port: int = int(os.getenv('POSTGRES_PORT', '5432'))
    pg_user: str = os.getenv('POSTGRES_USER', 'cip')
    pg_password: str = os.getenv('POSTGRES_PASSWORD', 'cip')
    pg_db: str = os.getenv('POSTGRES_DB', 'cip_development')

    minio_endpoint: str = os.getenv('MINIO_ENDPOINT', 'http://minio:9000')
    minio_access_key: str = os.getenv('MINIO_ROOT_USER', 'minio')
    minio_secret_key: str = os.getenv('MINIO_ROOT_PASSWORD', 'minio12345')
    minio_bucket: str = os.getenv('MINIO_BUCKET', 'documents')
    minio_region: str = os.getenv('MINIO_REGION', 'us-east-1')

    ocr_lang: str = os.getenv('OCR_LANG', 'eng')
    ocr_dpi: int = int(os.getenv('OCR_DPI', '200'))

    max_retries: int = int(os.getenv('MAX_RETRIES', '5'))
    metrics_port: int = int(os.getenv('METRICS_PORT', '9100'))
    concurrency: int = int(os.getenv('WORKER_CONCURRENCY', '2'))
    log_level: str = os.getenv('LOG_LEVEL', 'info')


CONFIG = Config()
