#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT}/.env"
  set +a
fi

API_URL="${API_URL:-http://localhost:${API_HTTP_PORT:-3040}}"
SAMPLE="${SAMPLE:-./scripts/sample.txt}"

if [[ ! -f "$SAMPLE" ]]; then
  cat > "$SAMPLE" <<'EOF'
Roos Fleet Services — sample document.

This is a synthetic test document used to exercise the digital-cip ingestion
pipeline end to end. It contains a few paragraphs of plain English so that the
OCR step is essentially a passthrough on text, the chunker can split it into
multiple windows, and the embedder has something interesting to vectorise.

The pipeline should classify, OCR, chunk and embed this document, then mark it
as `embedded` in PostgreSQL. The Grafana ingestion dashboard should show the
event flow as it happens.

You can replace this file with a real PDF or image to test the Tesseract path.
EOF
fi

echo '[smoke] uploading sample...'
RESPONSE=$(curl -sS -X POST "${API_URL}/api/v1/documents" \
  -F "file=@${SAMPLE};type=text/plain" \
  -F 'title=smoke test')

DOC_ID=$(printf '%s' "$RESPONSE" | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
echo "[smoke] document id: ${DOC_ID}"

ATTEMPT=0
MAX=60
STATUS=''
while (( ATTEMPT < MAX )); do
  STATUS=$(curl -sS "${API_URL}/api/v1/documents/${DOC_ID}" \
    | python3 -c 'import json,sys;print(json.load(sys.stdin)["status"])')
  echo "[smoke] attempt $((ATTEMPT+1)): status=${STATUS}"
  if [[ "$STATUS" == 'embedded' || "$STATUS" == 'failed' ]]; then
    break
  fi
  sleep 2
  ATTEMPT=$((ATTEMPT+1))
done

if [[ "$STATUS" == 'embedded' ]]; then
  echo '[smoke] ✓ document reached embedded'
  exit 0
else
  echo "[smoke] ✗ final status: ${STATUS}"
  curl -sS "${API_URL}/api/v1/documents/${DOC_ID}" | python3 -m json.tool
  exit 1
fi
