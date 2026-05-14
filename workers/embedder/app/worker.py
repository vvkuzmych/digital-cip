from datetime import datetime, timezone

from pika.adapters.blocking_connection import BlockingChannel

from .config import CONFIG
from .consumer import PermanentError, TransientError, run_consumer
from .db import (
    already_processed,
    fetch_chunks_without_embedding,
    fetch_document,
    record_event,
    record_processed,
    update_document,
    write_embeddings,
)
from .embeddings import embed_batch
from .logger import LOG
from .metrics import CHUNKS_EMBEDDED, start_metrics_server


def handle(envelope: dict, _channel: BlockingChannel) -> None:
    message_id = envelope['message_id']
    document_id = envelope['document_id']

    if already_processed(message_id):
        LOG.info('message.duplicate.skipped', extra={
            'event': 'message.duplicate', 'message_id': message_id,
        })
        return

    document = fetch_document(document_id)
    if not document:
        raise PermanentError(f'document {document_id} not found')

    if document['status'] in ('embedded', 'failed'):
        LOG.info('document.terminal.skipped', extra={
            'event': 'document.terminal', 'status': document['status'],
            'document_id': document_id,
        })
        return

    try:
        update_document(document_id, status='embedding')
        record_event(document_id, stage='embed', from_state=document['status'],
                     to_state='embedding', message='Embedding started')

        chunks = fetch_chunks_without_embedding(document_id)
        if not chunks:
            now = datetime.now(timezone.utc).isoformat()
            update_document(document_id, status='embedded', embedded_at=now)
            record_event(document_id, stage='embed', from_state='embedding',
                         to_state='embedded', message='Already embedded; nothing to do')
            record_processed(message_id=message_id, idempotency_key=envelope['idempotency_key'],
                             document_id=document_id, consumer=CONFIG.service_name,
                             result={'embedded': 0})
            return

        texts = [c['content'] for c in chunks]
        vectors = embed_batch(texts)
        rows = [(c['id'], v) for c, v in zip(chunks, vectors)]
        write_embeddings(rows)
        CHUNKS_EMBEDDED.inc(len(rows))

        now = datetime.now(timezone.utc).isoformat()
        update_document(document_id, status='embedded', embedded_at=now)
        record_event(document_id, stage='embed', from_state='embedding',
                     to_state='embedded',
                     message=f'Embedded {len(rows)} chunks',
                     payload={'chunks': len(rows)})

        record_processed(
            message_id=message_id,
            idempotency_key=envelope['idempotency_key'],
            document_id=document_id,
            consumer=CONFIG.service_name,
            result={'embedded': len(rows)},
        )

        LOG.info('document.embedded', extra={
            'event': 'document.embedded',
            'document_id': document_id, 'chunks': len(rows),
        })

    except PermanentError as e:
        now = datetime.now(timezone.utc).isoformat()
        update_document(document_id, status='failed',
                        failure_reason=str(e), failed_at=now)
        record_event(document_id, stage='embed', from_state='embedding',
                     to_state='failed', message=str(e))
        raise
    except Exception as e:
        LOG.exception('embed.transient.error')
        record_event(document_id, stage='embed', from_state='embedding',
                     to_state='embedding', message=f'transient: {e}')
        raise TransientError(str(e)) from e


def main() -> None:
    start_metrics_server()
    LOG.info('worker.booted', extra={
        'event': 'worker.booted', 'service': CONFIG.service_name,
        'metrics_port': CONFIG.metrics_port,
    })
    run_consumer(queue=CONFIG.queue_in, stage='embed', handler=handle)


if __name__ == '__main__':
    main()
