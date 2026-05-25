#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

export ENVIRONMENT="${ENVIRONMENT:-development}"
export IMAGE_TAG="${IMAGE_TAG:-smoke-local}"
export POSTGRES_DB="${POSTGRES_DB:-lifeorganize}"
export POSTGRES_USER="${POSTGRES_USER:-lifeorganize}"
export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-lifeorganize}"
export POSTGRES_PORT="${POSTGRES_PORT:-55433}"
export API_PORT="${API_PORT:-8787}"
export BACKEND_SMOKE_URL="${BACKEND_SMOKE_URL:-http://127.0.0.1:${API_PORT}/healthz}"
export OPENAI_API_KEY="${OPENAI_API_KEY:-}"
export LIFE_ORGANIZE_ADMIN_API_KEY="${LIFE_ORGANIZE_ADMIN_API_KEY:-}"
export DEVICE_TOKEN_SIGNING_SECRET="${DEVICE_TOKEN_SIGNING_SECRET:-development-device-token-secret}"

run() {
  printf '\n==> %s\n' "$*"
  "$@"
}

run_capture() {
  printf '\n==> %s\n' "$*" >&2
  "$@"
}

cleanup() {
  docker compose --profile dev down -v --remove-orphans || true
}

cd "$COMPOSE_DIR"
trap cleanup EXIT

printf 'Backend Docker smoke configuration:\n'
printf '  BACKEND_SMOKE_URL=%s\n' "$BACKEND_SMOKE_URL"
printf '  API_PORT=%s\n' "$API_PORT"
printf '  Compose directory: %s\n' "$COMPOSE_DIR"

run docker compose --profile dev down -v --remove-orphans
run docker compose --profile dev build api
run docker compose --profile dev up -d postgres
run docker compose --profile dev run --rm migrate
run docker compose --profile dev run --rm migrate

version="$(run_capture docker compose --profile dev exec -T postgres \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "select version_num from alembic_version;")"
test "$version" = "20260522_000001"

tables="$(run_capture docker compose --profile dev exec -T postgres \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc \
  "select table_name from information_schema.tables where table_schema = 'public' order by table_name;")"
for table in ai_request_logs alembic_version device_clients; do
  grep -qx "$table" <<<"$tables"
done

indexes="$(run_capture docker compose --profile dev exec -T postgres \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc \
  "select indexname from pg_indexes where schemaname = 'public' and tablename in ('device_clients', 'ai_request_logs') order by indexname;")"
for index in ix_ai_request_logs_created_at ix_ai_request_logs_token_hash ix_device_clients_token_hash; do
  grep -qx "$index" <<<"$indexes"
done

run docker compose --profile dev up -d api

for _ in $(seq 1 30); do
  if docker inspect lifeorganize-api --format='{{.State.Health.Status}}' 2>/dev/null | grep -q healthy; then
    break
  fi

  status="$(docker inspect lifeorganize-api --format='{{.State.Status}}' 2>/dev/null || echo missing)"
  if [[ "$status" == "exited" || "$status" == "missing" ]]; then
    docker logs lifeorganize-api --tail=120 2>/dev/null || true
    exit 1
  fi

  sleep 2
done

final_status="$(docker inspect lifeorganize-api --format='{{.State.Health.Status}}' 2>/dev/null || echo unknown)"
if [[ "$final_status" != "healthy" ]]; then
  docker logs lifeorganize-api --tail=120 2>/dev/null || true
  exit 1
fi

response="$(run_capture curl --fail --show-error --silent "$BACKEND_SMOKE_URL")"
test "$response" = '{"ok":true}'
