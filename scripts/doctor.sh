#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

API_PORT="${API_HTTP_PORT:-3040}"
GRAF_PORT="${GRAFANA_HTTP_PORT:-3010}"

echo '=== digital-cip doctor ==='
echo ''
echo 'Expected URLs (from .env or defaults):'
echo "  Rails API:     http://localhost:${API_PORT}/"
echo "  Health:        http://localhost:${API_PORT}/healthz"
echo "  Grafana:       http://localhost:${GRAF_PORT}/"
echo "  RabbitMQ UI:   http://localhost:15672/"
echo "  MinIO console: http://localhost:9001/"
echo ''

if ! command -v docker >/dev/null 2>&1; then
  echo 'docker: not found in PATH'
  exit 1
fi

echo '--- docker compose ps ---'
docker compose ps -a 2>/dev/null || docker-compose ps -a 2>/dev/null || true
echo ''

echo "--- curl http://localhost:${API_PORT}/healthz ---"
if curl -sfS --connect-timeout 2 "http://localhost:${API_PORT}/healthz" >/dev/null; then
  echo 'OK — API responds.'
else
  echo 'FAILED — connection refused or no HTTP response.'
  echo 'Common fixes:'
  echo '  1. Start stack: make up'
  echo '  2. Use port '"${API_PORT}"' in the browser (not 3000 unless API_HTTP_PORT=3000).'
  echo '  3. If api is restarting: make logs SERVICE=api'
fi
