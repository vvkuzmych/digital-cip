import json
from datetime import datetime, timezone

import pika
from pika.adapters.blocking_connection import BlockingChannel

from .config import CONFIG
from .consumer import PermanentError, TransientError, run_consumer
from .db import (
    already_processed,
    fetch_document,
    record_event,
    record_processed,
    update_document_status,
)
from .logger import LOG
from .metrics import start_metrics_server
from .ocr import extract_text
from .storage import download_object


def _publish_next(channel: BlockingChannel, envelope: dict, next_payload: dict) -> None:
    channel.basic_publish(
        exchange='ingest',
        routing_key='ingest.chunk',
        body=json.dumps({
            'message_id': envelope['message_id'] + ':chunk',
            'idempotency_key': f"{envelope['document_id']}:chunk",
            'trace_id': envelope.get('trace_id'),
            'stage': 'chunk',
            'document_id': envelope['document_id'],
            'tenant_id': envelope.get('tenant_id'),
            'attempt': 1,
            'published_at': datetime.now(timezone.utc).isoformat(),
            'payload': next_payload,
        }).encode('utf-8'),
        properties=pika.BasicProperties(
            content_type='application/json',
            delivery_mode=2,
            headers={
                'x-idempotency-key': f"{envelope['document_id']}:chunk",
                'x-attempt': 1,
                'x-stage': 'chunk',
                'x-document-id': envelope['document_id'],
            },
        ),
    )
    LOG.info('next.published', extra={
        'event': 'message.published', 'routing_key': 'ingest.chunk',
        'document_id': envelope['document_id'],
    })


def handle(envelope: dict, _channel: BlockingChannel) -> dict | None:
    message_id = envelope['message_id']
    document_id = envelope['document_id']

    if already_processed(message_id):
        LOG.info('message.duplicate.skipped', extra={
            'event': 'message.duplicate', 'message_id': message_id,
        })
        return None

    document = fetch_document(document_id)
    if not document:
        raise PermanentError(f'document {document_id} not found')

    if document['status'] in ('embedded', 'failed'):
        LOG.info('document.terminal.skipped', extra={
            'event': 'document.terminal', 'status': document['status'],
            'document_id': document_id,
        })
        return None

    object_key = envelope['payload'].get('object_key') or document['object_key']

    try:
        update_document_status(document_id, status='ocr_processing')
        record_event(document_id, stage='ocr', from_state=document['status'],
                     to_state='ocr_processing', message='OCR started')

        blob = download_object(object_key)
        if not blob:
            raise PermanentError('object body empty')

        text, meta = extract_text(blob, document.get('content_type'))
        if not text or not text.strip():
            raise PermanentError('OCR produced empty text')

        update_document_status(
            document_id,
            status='ocr_completed',
            raw_text=text,
            ocr_completed_at=datetime.now(timezone.utc).isoformat(),
        )
        record_event(document_id, stage='ocr', from_state='ocr_processing',
                     to_state='ocr_completed',
                     message=f'OCR done ({meta.get("pages", 1)} pages, {len(text)} chars)',
                     payload=meta)

        record_processed(
            message_id=message_id,
            idempotency_key=envelope['idempotency_key'],
            stage='ocr',
            document_id=document_id,
            consumer=CONFIG.service_name,
            result={'chars': len(text), **meta},
        )

        return {'publish_next': {'object_key': object_key}}

    except PermanentError as e:
        update_document_status(
            document_id,
            status='failed',
            failure_reason=str(e),
            failed_at=datetime.now(timezone.utc).isoformat(),
        )
        record_event(document_id, stage='ocr', from_state='ocr_processing',
                     to_state='failed', message=str(e))
        raise
    except Exception as e:
        LOG.exception('ocr.transient.error')
        record_event(document_id, stage='ocr', from_state='ocr_processing',
                     to_state='ocr_processing', message=f'transient: {e}')
        raise TransientError(str(e)) from e


def main() -> None:
    start_metrics_server()
    LOG.info('worker.booted', extra={
        'event': 'worker.booted', 'service': CONFIG.service_name,
        'metrics_port': CONFIG.metrics_port,
    })
    run_consumer(
        queue=CONFIG.queue_in,
        stage='ocr',
        handler=handle,
        publish_next=_publish_next,
    )


if __name__ == '__main__':
    main()
