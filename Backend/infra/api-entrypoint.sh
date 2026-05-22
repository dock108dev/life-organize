#!/usr/bin/env bash
set -euo pipefail

environment="${ENVIRONMENT:-development}"

if [[ "${environment}" == "production" || "${environment}" == "staging" ]]; then
  : "${DATABASE_URL:?DATABASE_URL must be set for ${environment}.}"
  : "${OPENAI_API_KEY:?OPENAI_API_KEY must be set for ${environment}.}"
  : "${LIFE_ORGANIZE_ADMIN_API_KEY:?LIFE_ORGANIZE_ADMIN_API_KEY must be set for ${environment}.}"
  : "${DEVICE_TOKEN_SIGNING_SECRET:?DEVICE_TOKEN_SIGNING_SECRET must be set for ${environment}.}"
fi

if [[ "${RUN_MIGRATIONS:-false}" == "true" ]]; then
  alembic -c /app/alembic.ini upgrade head
fi

exec "$@"
