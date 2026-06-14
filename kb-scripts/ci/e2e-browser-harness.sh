#!/usr/bin/env bash
# Engineering KB E2E: API smoke + browser-harness UI smoke
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_BASE="${API_BASE:-http://localhost:8090/api}"
FRONTEND_URL="${FRONTEND_URL:-http://localhost:5174}"
ENV_FILE="${ENV_FILE:-$ROOT/deploy/.env}"
START_SERVICES="${START_SERVICES:-true}"
INGEST_IF_EMPTY="${INGEST_IF_EMPTY:-true}"

STARTED_BACKEND=false
STARTED_FRONTEND=false

log() { echo "==> $*"; }

wait_http() {
  local url="$1"
  local label="$2"
  local tries="${3:-120}"
  for ((i=1; i<=tries; i++)); do
    if curl -sf --max-time 3 "$url" >/dev/null 2>&1; then
      log "$label ready ($url)"
      return 0
    fi
    sleep 1
  done
  echo "FAIL  $label not ready: $url" >&2
  return 1
}

start_backend() {
  if curl -sf --max-time 2 "$API_BASE/health" >/dev/null 2>&1; then
    log "backend already running"
    return 0
  fi
  log "starting backend"
  if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  fi
  (
    cd "$ROOT/backend"
    nohup mvn -q spring-boot:run -Dspring-boot.run.profiles=local >"$ROOT/.e2e-backend.log" 2>&1 &
    echo $! >"$ROOT/.e2e-backend.pid"
  )
  STARTED_BACKEND=true
  wait_http "$API_BASE/health" "backend"
}

start_frontend() {
  if curl -sf --max-time 2 "$FRONTEND_URL" >/dev/null 2>&1; then
    log "frontend already running"
    return 0
  fi
  log "starting frontend"
  (
    cd "$ROOT/frontend"
    nohup npm run dev >"$ROOT/.e2e-frontend.log" 2>&1 &
    echo $! >"$ROOT/.e2e-frontend.pid"
  )
  STARTED_FRONTEND=true
  wait_http "$FRONTEND_URL" "frontend"
}

load_e2e_auth() {
  # shellcheck disable=SC1091
  source "$ROOT/ci/e2e-auth.sh"
  if [[ -n "${E2E_AUTH_TOKEN:-}" ]]; then
    log "e2e auth token acquired (${E2E_PHONE})"
  else
    log "e2e auth token not set (AUTH may be disabled)"
  fi
}

maybe_ingest() {
  if [[ "$INGEST_IF_EMPTY" != "true" ]]; then
    return 0
  fi
  local count
  local count
  if [[ -n "${E2E_AUTH_TOKEN:-}" ]]; then
    count=$(curl -sf -H "Authorization: Bearer ${E2E_AUTH_TOKEN}" "$API_BASE/projects/1/sections?limit=500" \
      | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('data',[])))")
  else
    count=$(curl -sf "$API_BASE/projects/1/sections?limit=500" \
      | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('data',[])))")
  fi
  if [[ "$count" -ge 20 ]]; then
    log "sections already ingested ($count)"
    return 0
  fi
  log "ingesting sample SDD ($count sections)"
  API_BASE="$API_BASE" "$ROOT/ci/ingest-local.sh"
}

stop_started_services() {
  if [[ "${KEEP_SERVICES:-false}" == "true" ]]; then
    return 0
  fi
  if [[ "$STARTED_BACKEND" == "true" && -f "$ROOT/.e2e-backend.pid" ]]; then
    pid=$(cat "$ROOT/.e2e-backend.pid")
    kill "$pid" 2>/dev/null || true
    rm -f "$ROOT/.e2e-backend.pid"
  fi
  if [[ "$STARTED_FRONTEND" == "true" && -f "$ROOT/.e2e-frontend.pid" ]]; then
    pid=$(cat "$ROOT/.e2e-frontend.pid")
    kill "$pid" 2>/dev/null || true
    rm -f "$ROOT/.e2e-frontend.pid"
  fi
}

trap stop_started_services EXIT

if [[ "$START_SERVICES" == "true" ]]; then
  start_backend
  start_frontend
fi

load_e2e_auth

maybe_ingest

log "API validate script"
API_BASE="$API_BASE" "$ROOT/ci/validate-fi-voucher-head.sh"

log "API smoke (python)"
E2E_AUTH_TOKEN="${E2E_AUTH_TOKEN:-}" API_BASE="$API_BASE" python3 "$ROOT/e2e/browser-harness/smoke.py"

log "browser-harness UI smoke"
if ! command -v browser-harness >/dev/null 2>&1; then
  echo "FAIL  browser-harness not found on PATH" >&2
  exit 1
fi
browser-harness < "$ROOT/e2e/browser-harness/ui_smoke.py"

log "E2E complete"
