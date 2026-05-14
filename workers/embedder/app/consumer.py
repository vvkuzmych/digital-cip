import json
import signal
import time
from typing import Callable

import pika
from pika.adapters.blocking_connection import BlockingChannel
from pika.exceptions import AMQPConnectionError
from tenacity import retry, stop_after_attempt, wait_exponential

from .config import CONFIG
from .logger import LOG
from .metrics import DURATION, FAILED, IN_FLIGHT, PROCESSED, RETRIED


class PermanentError(Exception):
    """Do not retry; mark message as failed."""


class TransientError(Exception):
    """Retry via DLX."""


@retry(
    reraise=True,
    stop=stop_after_attempt(20),
    wait=wait_exponential(multiplier=1, max=10),
)
def _connect() -> pika.BlockingConnection:
    params = pika.URLParameters(CONFIG.rabbitmq_url)
    params.heartbeat = 30
    params.blocked_connection_timeout = 60
    return pika.BlockingConnection(params)


def run_consumer(
    *,
    queue: str,
    stage: str,
    handler: Callable[[dict, BlockingChannel], dict | None],
) -> None:
    connection = _connect()
    channel = connection.channel()
    channel.basic_qos(prefetch_count=CONFIG.concurrency)

    shutdown = {'flag': False}

    def stop(*_):
        LOG.info('worker.shutdown.requested')
        shutdown['flag'] = True
        try:
            channel.stop_consuming()
        except Exception:
            pass

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    def on_message(ch: BlockingChannel, method, properties, body: bytes) -> None:
        IN_FLIGHT.labels(stage=stage).inc()
        started = time.monotonic()
        envelope: dict = {}
        try:
            envelope = json.loads(body)
            message_id = envelope.get('message_id', properties.message_id)
            attempt = envelope.get('attempt', 1)

            LOG.info('message.received', extra={
                'event': 'message.received', 'stage': stage,
                'message_id': message_id, 'document_id': envelope.get('document_id'),
                'attempt': attempt,
            })

            handler(envelope, ch)
            ch.basic_ack(delivery_tag=method.delivery_tag)
            PROCESSED.labels(stage=stage).inc()
        except PermanentError as e:
            FAILED.labels(stage=stage, reason='permanent').inc()
            LOG.error('message.failed.permanent', extra={
                'event': 'message.failed.permanent', 'stage': stage, 'reason': str(e),
            })
            ch.basic_ack(delivery_tag=method.delivery_tag)
        except TransientError as e:
            attempt = envelope.get('attempt', 1)
            if attempt >= CONFIG.max_retries:
                FAILED.labels(stage=stage, reason='exhausted').inc()
                LOG.error('message.failed.exhausted', extra={
                    'event': 'message.failed.exhausted', 'stage': stage,
                    'reason': str(e), 'attempt': attempt,
                })
                ch.basic_publish(
                    exchange='ingest.dlx',
                    routing_key=f'ingest.{stage}.dlq',
                    body=body,
                    properties=properties,
                )
                ch.basic_ack(delivery_tag=method.delivery_tag)
            else:
                RETRIED.labels(stage=stage).inc()
                envelope['attempt'] = attempt + 1
                LOG.warning('message.retry', extra={
                    'event': 'message.retry', 'stage': stage,
                    'reason': str(e), 'attempt': envelope['attempt'],
                })
                ch.basic_publish(
                    exchange='ingest.retry',
                    routing_key=f'ingest.{stage}.retry',
                    body=json.dumps(envelope).encode('utf-8'),
                    properties=pika.BasicProperties(
                        content_type='application/json',
                        delivery_mode=2,
                        message_id=properties.message_id,
                        headers={**(properties.headers or {}), 'x-attempt': envelope['attempt']},
                    ),
                )
                ch.basic_ack(delivery_tag=method.delivery_tag)
        except Exception as e:
            FAILED.labels(stage=stage, reason='unhandled').inc()
            LOG.exception('message.failed.unhandled', extra={
                'event': 'message.failed.unhandled', 'stage': stage, 'error': str(e),
            })
            try:
                ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)
            except Exception:
                pass
        finally:
            DURATION.labels(stage=stage).observe(time.monotonic() - started)
            IN_FLIGHT.labels(stage=stage).dec()

    channel.basic_consume(queue=queue, on_message_callback=on_message, auto_ack=False)
    LOG.info('worker.starting', extra={'event': 'worker.starting', 'queue': queue, 'stage': stage})

    while not shutdown['flag']:
        try:
            channel.start_consuming()
            break
        except AMQPConnectionError:
            LOG.warning('amqp.disconnect.retrying')
            time.sleep(2)
            connection = _connect()
            channel = connection.channel()
            channel.basic_qos(prefetch_count=CONFIG.concurrency)
            channel.basic_consume(queue=queue, on_message_callback=on_message, auto_ack=False)

    try:
        connection.close()
    except Exception:
        pass
