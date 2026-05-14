from prometheus_client import Counter, Gauge, Histogram, start_http_server

from .config import CONFIG

PROCESSED = Counter(
    'worker_messages_processed_total',
    'Messages processed by the worker',
    ['stage'],
)

FAILED = Counter(
    'worker_messages_failed_total',
    'Messages that failed processing',
    ['stage', 'reason'],
)

RETRIED = Counter(
    'worker_messages_retried_total',
    'Messages retried via DLX',
    ['stage'],
)

IN_FLIGHT = Gauge(
    'worker_in_flight',
    'Messages currently being processed',
    ['stage'],
)

DURATION = Histogram(
    'worker_processing_seconds',
    'Time spent processing a single message',
    ['stage'],
)


def start_metrics_server() -> None:
    start_http_server(CONFIG.metrics_port)
