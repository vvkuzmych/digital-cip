import json
from contextlib import contextmanager
from typing import Any, Iterator, Optional, Sequence

import psycopg
from pgvector.psycopg import register_vector
from psycopg.rows import dict_row

from .config import CONFIG
from .logger import LOG


def _connection():
    conn = psycopg.connect(
        host=CONFIG.pg_host,
        port=CONFIG.pg_port,
        user=CONFIG.pg_user,
        password=CONFIG.pg_password,
        dbname=CONFIG.pg_db,
        autocommit=False,
        row_factory=dict_row,
    )
    register_vector(conn)
    return conn


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
            (message_id, idempotency_key, 'embed', document_id, consumer, json.dumps(result or {})),
        )


def fetch_document(document_id: int) -> Optional[dict[str, Any]]:
    with transaction() as conn, conn.cursor() as cur:
        cur.execute('SELECT id, status FROM documents WHERE id = %s', (document_id,))
        return cur.fetchone()


def fetch_chunks_without_embedding(document_id: int) -> list[dict[str, Any]]:
    with transaction() as conn, conn.cursor() as cur:
        cur.execute(
            '''
            SELECT id, position, content
            FROM document_chunks
            WHERE document_id = %s AND embedding IS NULL
            ORDER BY position
            ''',
            (document_id,),
        )
        return cur.fetchall()


def write_embeddings(rows: Sequence[tuple[int, list[float]]]) -> None:
    if not rows:
        return
    with transaction() as conn, conn.cursor() as cur:
        cur.executemany(
            'UPDATE document_chunks SET embedding = %s, updated_at = NOW() WHERE id = %s',
            [(embedding, chunk_id) for chunk_id, embedding in rows],
        )


def update_document(
    document_id: int,
    *,
    status: str,
    embedded_at: Optional[str] = None,
    failure_reason: Optional[str] = None,
    failed_at: Optional[str] = None,
) -> None:
    fields = ['status = %s']
    values: list[Any] = [status]
    if embedded_at is not None:
        fields.append('embedded_at = %s')
        values.append(embedded_at)
    if failure_reason is not None:
        fields.append('failure_reason = %s')
        values.append(failure_reason)
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
    from_state: Optional[str],
    to_state: str,
    message: Optional[str] = None,
    payload: Optional[dict[str, Any]] = None,
) -> None:
    with transaction() as conn, conn.cursor() as cur:
        cur.execute(
            '''
            INSERT INTO processing_events
                (document_id, stage, from_state, to_state, actor, message, payload, created_at)
            VALUES (%s, %s, %s, %s, 'system', %s, %s, NOW())
            ''',
            (document_id, stage, from_state, to_state, message, json.dumps(payload or {})),
        )
