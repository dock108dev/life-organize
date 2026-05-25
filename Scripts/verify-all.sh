#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verify-common.sh"

ROOT_DIR="$(script_root)"
RUN_BACKEND_SMOKE=0
RUN_PRODUCTION_SMOKE=0
PRODUCTION_SMOKE_URL="${PRODUCTION_SMOKE_URL:-https://life.dock108.dev/healthz}"

usage() {
  cat <<'EOF'
Usage: Scripts/verify-all.sh [--with-backend-smoke] [--with-production-smoke]

Runs the local full gate in order: backend checks, iOS tests and coverage,
screenshot comparison, then optional smoke checks.

Overrides:
  IOS_DESTINATION       Simulator destination for iOS tests.
  IOS_RESULT_BUNDLE     iOS test xcresult path.
  BACKEND_SMOKE_URL     Health URL checked by backend Docker smoke.
  PRODUCTION_SMOKE_URL  Production health URL checked by production smoke.
EOF
}

while (($# > 0)); do
  case "$1" in
    --with-backend-smoke)
      RUN_BACKEND_SMOKE=1
      ;;
    --with-production-smoke)
      RUN_PRODUCTION_SMOKE=1
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

printf 'Full verification configuration:\n'
printf '  IOS_DESTINATION=%s\n' "${IOS_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2}"
printf '  IOS_RESULT_BUNDLE=%s\n' "${IOS_RESULT_BUNDLE:-BuildArtifacts/LifeOrganizeTests.xcresult}"
printf '  BACKEND_SMOKE_URL=%s\n' "${BACKEND_SMOKE_URL:-http://127.0.0.1:${API_PORT:-8787}/healthz}"
printf '  PRODUCTION_SMOKE_URL=%s\n' "$PRODUCTION_SMOKE_URL"
printf '  Screenshot failure artifacts: BuildArtifacts/ScreenshotTests.xcresult, BuildArtifacts/screenshots/actual, BuildArtifacts/screenshots/diff\n'

cd "$ROOT_DIR"

run "$ROOT_DIR/Scripts/verify-backend.sh"
run "$ROOT_DIR/Scripts/verify-ios.sh"
run "$ROOT_DIR/Scripts/screenshots/run-screenshot-tests.sh" compare

if [[ "$RUN_BACKEND_SMOKE" -eq 1 ]]; then
  run "$ROOT_DIR/Scripts/verify-backend.sh" smoke
fi

if [[ "$RUN_PRODUCTION_SMOKE" -eq 1 ]]; then
  run curl --fail --show-error --silent "$PRODUCTION_SMOKE_URL"
fi
