#!/usr/bin/env bash
# Source after API_BASE is set. Exports E2E_AUTH_TOKEN when login succeeds.
E2E_PHONE="${E2E_PHONE:-18758284088}"
E2E_PASSWORD="${E2E_PASSWORD:-123456}"

e2e_fetch_auth_token() {
  local api="${API_BASE:-http://localhost:8090/api}"
  local body
  body=$(E2E_PHONE="$E2E_PHONE" E2E_PASSWORD="$E2E_PASSWORD" python3 -c '
import json, os
print(json.dumps({"phone": os.environ["E2E_PHONE"], "password": os.environ["E2E_PASSWORD"]}))
')
  curl -sf --max-time 15 -X POST "$api/auth/login" \
    -H 'Content-Type: application/json' \
    -d "$body" \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('data',{}).get('token',''))" 2>/dev/null || true
}

if [[ -z "${E2E_AUTH_TOKEN:-}" ]]; then
  E2E_AUTH_TOKEN="$(e2e_fetch_auth_token)"
  export E2E_AUTH_TOKEN
fi
