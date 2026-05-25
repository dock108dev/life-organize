#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verify-common.sh"

ROOT_DIR="$(script_root)"
BACKEND_DIR="$ROOT_DIR/Backend"
VENV_DIR="${BACKEND_VENV:-$BACKEND_DIR/.venv}"
PYTHON_BIN="${BACKEND_PYTHON:-python3}"
COVERAGE_XML="${BACKEND_COVERAGE_XML:-$BACKEND_DIR/coverage.xml}"
SMOKE_URL="${BACKEND_SMOKE_URL:-http://127.0.0.1:${API_PORT:-8787}/healthz}"
RUFF_VERSION="${BACKEND_RUFF_VERSION:-0.14.8}"
RUN_SMOKE=0
SMOKE_ONLY=0

usage() {
  cat <<'EOF'
Usage: Scripts/verify-backend.sh [--with-smoke|smoke]

Runs backend lint, bytecode compilation, and pytest coverage. Backend Docker
smoke is opt-in with --with-smoke, or can be run by itself with the smoke
subcommand.

Overrides:
  BACKEND_PYTHON        Python executable used to create the virtualenv.
  BACKEND_VENV          Backend virtualenv path.
  BACKEND_RUFF_VERSION  Ruff version installed for linting.
  BACKEND_SMOKE_URL     Health URL checked by backend Docker smoke.
  API_PORT              Local backend smoke host port.
EOF
}

while (($# > 0)); do
  case "$1" in
    --with-smoke)
      RUN_SMOKE=1
      ;;
    smoke)
      RUN_SMOKE=1
      SMOKE_ONLY=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
  shift
done

print_config() {
  printf 'Backend verification configuration:\n'
  printf '  BACKEND_PYTHON=%s\n' "$PYTHON_BIN"
  printf '  BACKEND_VENV=%s\n' "$VENV_DIR"
  printf '  BACKEND_COVERAGE_XML=%s\n' "$COVERAGE_XML"
  printf '  BACKEND_RUFF_VERSION=%s\n' "$RUFF_VERSION"
  printf '  BACKEND_SMOKE_URL=%s\n' "$SMOKE_URL"
  printf '  API_PORT=%s\n' "${API_PORT:-8787}"
  printf '  Failure artifact: %s\n' "$COVERAGE_XML"
}

ensure_venv() {
  if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    run "$PYTHON_BIN" -m venv "$VENV_DIR"
  fi
  run "$VENV_DIR/bin/python" -m pip install --upgrade pip
  run "$VENV_DIR/bin/python" -m pip install -r "$BACKEND_DIR/requirements.txt" "ruff==$RUFF_VERSION"
}

run_backend_checks() {
  cd "$BACKEND_DIR"
  ensure_venv
  run "$VENV_DIR/bin/python" -m ruff check app tests infra/scripts
  run "$VENV_DIR/bin/python" -m compileall app tests infra/scripts
  run "$VENV_DIR/bin/python" -m pytest tests
}

run_backend_smoke() {
  cd "$ROOT_DIR"
  run env BACKEND_SMOKE_URL="$SMOKE_URL" "$ROOT_DIR/Backend/infra/scripts/docker_smoke.sh"
}

print_config

if [[ "$SMOKE_ONLY" -eq 0 ]]; then
  run_backend_checks
fi

if [[ "$RUN_SMOKE" -eq 1 ]]; then
  run_backend_smoke
fi
