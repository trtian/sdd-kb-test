#!/usr/bin/env bash
# 增量验收：SDD 小改 → re-ingest → AGE syncIngestedSection → search(graphNetwork)
# 不做：全量 rebuild、测试仓初始化、validate 全量冒烟
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_BASE="${API_BASE:-http://localhost:8090/api}"
TENANT_KEY="${TENANT_KEY:-team-erp-fi}"
PROJECT_KEY="${PROJECT_KEY:-klerp3-fi}"
TEST_REPO_DIR="${TEST_REPO_DIR:-$ROOT/workspace/sdd-kb-test}"
SDD_PATH="${SDD_PATH:-$TEST_REPO_DIR/openspec}"
INGEST_TIMEOUT="${INGEST_TIMEOUT:-900}"

# shellcheck disable=SC1091
source "$ROOT/ci/e2e-auth.sh"
AUTH=()
if [[ -n "${E2E_AUTH_TOKEN:-}" ]]; then
  AUTH=(-H "Authorization: Bearer ${E2E_AUTH_TOKEN}")
fi

pass=0
fail=0
ok()  { echo "PASS  $*"; pass=$((pass + 1)); }
bad() { echo "FAIL  $*"; fail=$((fail + 1)); exit 1; }

ingest_json_body() {
  SDD_PATH="$1" GIT_COMMIT="$2" python3 -c 'import json,os; print(json.dumps({"sourcePath": os.environ["SDD_PATH"], "gitCommit": os.environ["GIT_COMMIT"], "headingLevel": 4}))'
}

echo "==> [1] Health"
curl -sf --max-time 10 "$API_BASE/health" >/dev/null || bad "backend down — ./ci/run-backend.sh"
ok "backend UP"

PROJECT_ID=$(curl -sf ${AUTH[@]+"${AUTH[@]}"} "$API_BASE/tenants/$TENANT_KEY/projects" \
  | python3 -c "
import json,sys
for p in json.load(sys.stdin).get('data',[]):
    if p.get('projectKey')=='$PROJECT_KEY':
        print(p['id']); break
")
[[ -n "$PROJECT_ID" ]] || bad "project $PROJECT_KEY not found"
ok "project_id=$PROJECT_ID"

echo "==> [2] AGE status (no rebuild)"
AGE_OK=$(curl -sf ${AUTH[@]+"${AUTH[@]}"} "$API_BASE/projects/$PROJECT_ID/graph/status" \
  | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('ageOperational',False))")
[[ "$AGE_OK" == "True" ]] || bad "AGE not operational"
ok "AGE operational"

echo "==> [3] Incremental patch + commit"
SPEC="$SDD_PATH/changes/specs/account-document-head-create/spec.md"
[[ -f "$SPEC" ]] || bad "spec missing — run ci/setup-sdd-kb-test.sh once"
STAMP="$(date +%Y%m%d%H%M%S)"
MARKER="kb-incr-${STAMP}"
QUERY="增量AGE验证-${STAMP}"
{
  printf '\n##### 场景：%s（%s）\n' "$QUERY" "$MARKER"
  printf '%s\n' '- **当** 运行 ci/local-sdd-incremental.sh'
  printf '%s\n' '- **预期** ingest 增量写入 AGE 且可检索'
} >> "$SPEC"
cd "$TEST_REPO_DIR"
git add "$SPEC"
git commit -m "test: incremental AGE verify ($MARKER)" >/dev/null
GIT_COMMIT="$(git rev-parse HEAD)"
ok "committed ${GIT_COMMIT:0:8} marker=$MARKER"

echo "==> [4] Re-ingest (incremental syncIngestedSection)"
RESULT=$(curl -sf --max-time "$INGEST_TIMEOUT" -X POST "$API_BASE/projects/$PROJECT_ID/ingest" \
  ${AUTH[@]+"${AUTH[@]}"} \
  -H 'Content-Type: application/json' \
  -d "$(ingest_json_body "$SDD_PATH" "$GIT_COMMIT")")
NEW=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('sectionsNew',0))")
UPD=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('sectionsUpdated',0))")
TOTAL=$((NEW + UPD))
[[ "$TOTAL" -gt 0 ]] || bad "ingest returned sectionsNew=0 sectionsUpdated=0"
ok "ingest new=$NEW updated=$UPD"

echo "==> [5] Search + graphNetwork (expect source=age when AGE path hits)"
SEARCH=$(curl -sf --max-time 120 -X POST "$API_BASE/projects/$PROJECT_ID/search" \
  ${AUTH[@]+"${AUTH[@]}"} \
  -H 'Content-Type: application/json' \
  -d "$(QUERY="$QUERY" python3 -c 'import json,os; print(json.dumps({"query": os.environ["QUERY"]}))')")
python3 -c "
import json,sys
d=json.load(sys.stdin)
hits=(d.get('data') or {}).get('hits', [])
if not hits:
    print('NO_HITS'); sys.exit(1)
h=hits[0]
gn=h.get('graphNetwork') or {}
src=gn.get('source','')
nodes=len(gn.get('nodes') or [])
print(f'hit={h.get(\"headingPath\",\"\")[:40]} graph_source={src} nodes={nodes}')
sys.exit(0 if nodes > 0 else 1)
" <<< "$SEARCH" || bad "search miss or empty graphNetwork"
GRAPH_SRC=$(echo "$SEARCH" | python3 -c "
import json,sys
hits=(json.load(sys.stdin).get('data') or {}).get('hits', [])
gn=(hits[0].get('graphNetwork') or {}) if hits else {}
print(gn.get('source','none'))
")
ok "search hit graph_source=$GRAPH_SRC"

LOGICAL_ID=$(echo "$SEARCH" | python3 -c "
import json,sys
d=json.load(sys.stdin)
hits=(d.get('data') or {}).get('hits', [])
q=sys.argv[1] if len(sys.argv)>1 else ''
for h in hits:
    if q and q in (h.get('headingPath') or ''):
        print(h.get('logicalSectionId','')); break
else:
    print(hits[0].get('logicalSectionId','') if hits else '')
" "$QUERY")

if [[ -n "$LOGICAL_ID" ]]; then
  echo "==> [6] AGE network API (direct, no rebuild)"
  NET=$(curl -sf --max-time 60 ${AUTH[@]+"${AUTH[@]}"} \
    "$API_BASE/projects/$PROJECT_ID/graph/sections/$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$LOGICAL_ID")/network?depth=2")
  AGE_NET=$(echo "$NET" | python3 -c "
import json,sys
d=json.load(sys.stdin).get('data') or {}
src=d.get('source','')
nodes=len(d.get('nodes') or [])
edges=len(d.get('edges') or [])
print(f'{src}|{nodes}|{edges}')
")
  IFS='|' read -r NET_SRC NET_NODES NET_EDGES <<< "$AGE_NET"
  if [[ "$NET_NODES" -gt 0 ]]; then
    ok "AGE network API source=$NET_SRC nodes=$NET_NODES edges=$NET_EDGES"
  else
    echo "WARN  AGE network API empty for $LOGICAL_ID (search may use relation_table)"
  fi
fi

echo ""
echo "========================================"
echo "Incremental AGE loop: $pass passed, $fail failed"
echo "Query: $QUERY"
if [[ "$GRAPH_SRC" == "age" ]]; then
  echo "AGE incremental sync: CONFIRMED (graphNetwork source=age)"
else
  echo "AGE incremental sync: graph via $GRAPH_SRC (relation_table fallback; AGE query empty for anchor)"
fi
echo "ALL PASS"
