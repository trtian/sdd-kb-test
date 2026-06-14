#!/usr/bin/env bash
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:8090/api}"
PROJECT_ID="${PROJECT_ID:-1}"
PAYLOAD="${1:-$(cd "$(dirname "$0")/.." && pwd)/samples/supersede-fi-hotfix-example.json}"

BODY=$(python3 -c "
import json
with open('$PAYLOAD') as f:
    d = json.load(f)
print(json.dumps({'actions': d['actions']}))
")

echo "==> POST supersede ($PAYLOAD)"
curl -sf -X POST "$API_BASE/projects/$PROJECT_ID/sections/supersede" \
  -H 'Content-Type: application/json' \
  -d "$BODY" | python3 -m json.tool
