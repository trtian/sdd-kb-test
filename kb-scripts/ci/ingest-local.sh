#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_BASE="${API_BASE:-http://localhost:8090/api}"
if [[ -f "$ROOT/ci/e2e-auth.sh" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/ci/e2e-auth.sh"
fi
AUTH_HEADER=()
if [[ -n "${E2E_AUTH_TOKEN:-}" ]]; then
  AUTH_HEADER=(-H "Authorization: Bearer ${E2E_AUTH_TOKEN}")
fi
TENANT_KEY="${TENANT_KEY:-team-erp-fi}"
PROJECT_KEY="${PROJECT_KEY:-klerp3-fi}"
SDD_PATH="${SDD_PATH:-$ROOT/SDD文档/财务凭证头SDD相关文档20260429/openspec}"
GIT_COMMIT="${GIT_COMMIT:-local-sample}"

echo "==> API health"
curl -sf "$API_BASE/health" | head -c 200
echo ""

echo "==> Resolve project id"
PROJECTS=$(curl -sf ${AUTH_HEADER[@]+"${AUTH_HEADER[@]}"} "$API_BASE/tenants/$TENANT_KEY/projects")
PROJECT_ID=$(echo "$PROJECTS" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for p in d.get('data',[]):
    if p.get('projectKey')=='$PROJECT_KEY':
        print(p['id']); break
")
if [ -z "$PROJECT_ID" ]; then
  echo "Project $PROJECT_KEY not found. Start backend with profile local first." >&2
  exit 1
fi
echo "Project id: $PROJECT_ID"

echo "==> Ingest from $SDD_PATH"
export SDD_PATH GIT_COMMIT
INGEST_BODY=$(python3 -c "import json, os; print(json.dumps({'sourcePath': os.environ['SDD_PATH'], 'gitCommit': os.environ['GIT_COMMIT'], 'headingLevel': 4}))")
curl -sf -X POST "$API_BASE/projects/$PROJECT_ID/ingest" \
  ${AUTH_HEADER[@]+"${AUTH_HEADER[@]}"} \
  -H 'Content-Type: application/json' \
  -d "$INGEST_BODY"
echo ""
echo "Done."
