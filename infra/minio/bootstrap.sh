#!/bin/sh
set -eu

ENDPOINT='http://minio:9000'
BUCKET="${MINIO_BUCKET:-documents}"
USER="${MINIO_ROOT_USER:-minio}"
PASSWORD="${MINIO_ROOT_PASSWORD:-minio12345}"

echo '[minio-bootstrap] waiting for minio to accept credentials...'
until mc alias set local "$ENDPOINT" "$USER" "$PASSWORD" >/dev/null 2>&1; do
  sleep 1
done

echo "[minio-bootstrap] ensuring bucket ${BUCKET}"
mc mb --ignore-existing "local/${BUCKET}"

mc anonymous set download "local/${BUCKET}" || true

echo '[minio-bootstrap] done'
