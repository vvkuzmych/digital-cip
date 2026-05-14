import json
from contextlib import contextmanager
from typing import Any, Iterator, Optional

import psycopg
from psycopg.rows import dict_row

from .config import CONFIG
from .logger import LOG


def _connection():
    return psycopg.connect(
        host=CONFIG.pg_host,
        port=CONFIG.pg_port,
        user=CONFIG.pg_user,
        password=CONFIG.pg_password,
        dbname=CONFIG.pg_db,
        autocommit=False,
        row_factory=dict_row,
    )


@contextmanager
def transaction() -> Iterator[psycopg.Connection]:
    conn = _connection()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        LOG.exception('db.transaction.rolled_back')
        raise
    finally:
        conn.close()


def already_processed(message_id: str) -> bool:
    with transaction() as conn, conn.cursor() as cur:
        cur.execute('SELECT 1 FROM processed_messages WHERE message_id = %s', (message_id,))
        return cur.fetchone() is not None


def record_processed(
    *,
    message_id: str,
    idempotency_key: str,
    stage: str,
    document_id: int,
    consumer: str,
    result: Optional[dict[str, Any]] = None,
) -> None:
    with transaction() as conn, conn.cursor() as cur:
        cur.execute(
            '''
            INSERT INTO processed_messages
                (message_id, idempotency_key, stage, document_id, consumer, result, processed_at)
            VALUES (%s, %s, %s, %s, %s, %s, NOW())
            ON CONFLICT (message_id) DO NOTHING
            ''',
            (message_id, idempotency_key, stage, document_id, consumer, json.dumps(result or {})),
        )


def fetch_document(document_id: int) -> Optional[dict[str, Any]]:
    with transaction() as conn, conn.cursor() as cur:
        cur.execute('SELECT * FROM documents WHERE id = %s', (document_id,))
        return cur.fetchone()


def update_document_status(
    document_id: int,
    *,
    status: str,
    raw_text: Optional[str] = None,
    failure_reason: Optional[str] = None,
    ocr_completed_at: Optional[str] = None,
    failed_at: Optional[str] = None,
) -> None:
    fields = ['status = %s']
    values: list[Any] = [status]
    if raw_text is not None:
        fields.append('raw_text = %s')
        values.append(raw_text)
    if failure_reason is not None:
        fields.append('failure_reason = %s')
        values.append(failure_reason)
    if ocr_completed_at is not None:
        fields.append('ocr_completed_at = %s')
        values.append(ocr_completed_at)
    if failed_at is not None:
        fields.append('failed_at = %s')
        values.append(failed_at)
    fields.append('updated_at = NOW()')
    values.append(document_id)

    with transaction() as conn, conn.cursor() as cur:
        cur.execute(
            f'UPDATE documents SET {", ".join(fields)} WHERE id = %s',
            tuple(values),
        )


def record_event(
    document_id: int,
    *,
    stage: str,
    to_state: str,
    from_state: Optional[str],
    message: Optional[str] = None,
    payload: Optional[dict[str, Any]] = None,
    actor: str = 'system',
) -> None:
    with transaction() as conn, conn.cursor() as cur:
        cur.execute(
            '''
            INSERT INTO processing_events
                (document_id, stage, from_state, to_state, actor, message, payload, created_at)
            VALUES (%s, %s, %s, %s, %s, %s, %s, NOW())
            ''',
            (document_id, stage, from_state, to_state, actor, message, json.dumps(payload or {})),
        )
