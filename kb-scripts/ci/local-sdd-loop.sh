#!/usr/bin/env bash
# 本地 SDD-KB 全链路：测试仓 → ingest → graph → search → 迭代 → validate
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_BASE="${API_BASE:-http://localhost:8090/api}"
TENANT_KEY="${TENANT_KEY:-team-erp-fi}"
PROJECT_KEY="${PROJECT_KEY:-klerp3-fi}"
TEST_REPO_DIR="${TEST_REPO_DIR:-$ROOT/workspace/sdd-kb-test}"
SDD_PATH="${SDD_PATH:-$TEST_REPO_DIR/openspec}"
SKIP_GRAPH="${SKIP_GRAPH:-false}"
GRAPH_REBUILD="${GRAPH_REBUILD:-skip}"  # incremental | full | skip（默认 skip，不 rebuild）
SKIP_ITERATION="${SKIP_ITERATION:-false}"
SKIP_SUPERSEDE="${SKIP_SUPERSEDE:-false}"
GRAPH_REBUILD_TIMEOUT="${GRAPH_REBUILD_TIMEOUT:-600}"
INGEST_TIMEOUT="${INGEST_TIMEOUT:-900}"

# shellcheck disable=SC1091
source "$ROOT/ci/e2e-auth.sh"
AUTH=()
if [[ -n "${E2E_AUTH_TOKEN:-}" ]]; then
  AUTH=(-H "Authorization: Bearer ${E2E_AUTH_TOKEN}")
fi

AGE_OK="False"

pass=0
fail=0
step() { echo ""; echo "==> [$((pass + fail + 1))] $*"; }
ok()   { echo "PASS  $*"; pass=$((pass + 1)); }
bad()  { echo "FAIL  $*"; fail=$((fail + 1)); }

ingest_json_body() {
  SDD_PATH="$1" GIT_COMMIT="$2" python3 -c 'import json,os; print(json.dumps({"sourcePath": os.environ["SDD_PATH"], "gitCommit": os.environ["GIT_COMMIT"], "headingLevel": 4}))'
}

resolve_project_id() {
  curl -sf ${AUTH[@]+"${AUTH[@]}"} "$API_BASE/tenants/$TENANT_KEY/projects" \
    | python3 -c "
import json,sys
for p in json.load(sys.stdin).get('data',[]):
    if p.get('projectKey')=='$PROJECT_KEY':
        print(p['id']); break
"
}

step "Setup test repo (sdd-kb-test)"
"$ROOT/ci/setup-sdd-kb-test.sh"
export TEST_REPO_DIR SDD_PATH

step "Health check"
if curl -sf --max-time 10 "$API_BASE/health" >/dev/null; then
  ok "backend UP at $API_BASE"
else
  bad "backend down — run: ./ci/run-backend.sh"
  exit 1
fi

PROJECT_ID="$(resolve_project_id)"
if [[ -z "$PROJECT_ID" ]]; then
  bad "project $PROJECT_KEY not found under tenant $TENANT_KEY"
  exit 1
fi
ok "project_id=$PROJECT_ID"

step "Wire repo_path to test clone"
curl -sf -X PUT "$API_BASE/tenants/$TENANT_KEY/projects/$PROJECT_ID" \
  ${AUTH[@]+"${AUTH[@]}"} \
  -H 'Content-Type: application/json' \
  -d "$(REPO_PATH="$TEST_REPO_DIR" python3 -c 'import json,os; print(json.dumps({"repoPath": os.environ["REPO_PATH"]}))')" \
  >/dev/null
ok "repo_path=$TEST_REPO_DIR"

step "Ingest from $SDD_PATH"
GIT_COMMIT="$(cd "$TEST_REPO_DIR" && git rev-parse HEAD)"
export GIT_COMMIT SDD_PATH
INGEST_BODY=$(ingest_json_body "$SDD_PATH" "$GIT_COMMIT")
INGEST_RESULT=$(curl -sf --max-time "$INGEST_TIMEOUT" -X POST "$API_BASE/projects/$PROJECT_ID/ingest" \
  ${AUTH[@]+"${AUTH[@]}"} \
  -H 'Content-Type: application/json' \
  -d "$INGEST_BODY")
SECTIONS=$(echo "$INGEST_RESULT" | python3 -c "
import json,sys
j=json.load(sys.stdin).get('data',{})
print(j.get('sectionsNew',0)+j.get('sectionsUpdated',0))
")
if [[ "$SECTIONS" != "0" ]]; then
  ok "ingested sections=$SECTIONS commit=${GIT_COMMIT:0:8}"
else
  echo "$INGEST_RESULT" | head -c 400
  bad "ingest returned unexpected result"
fi

if [[ "$SKIP_GRAPH" == "true" || "$GRAPH_REBUILD" == "skip" ]]; then
  echo "==> Graph: skipped (SKIP_GRAPH or GRAPH_REBUILD=skip)"
elif [[ "$GRAPH_REBUILD" == "full" ]]; then
  step "Graph status + full rebuild (timeout ${GRAPH_REBUILD_TIMEOUT}s)"
  GSTATUS=$(curl -sf ${AUTH[@]+"${AUTH[@]}"} "$API_BASE/projects/$PROJECT_ID/graph/status")
  AGE_OK=$(echo "$GSTATUS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('ageOperational',False))")
  if [[ "$AGE_OK" == "True" ]]; then
    ok "AGE operational"
  else
    echo "WARN  AGE not operational — graphNetwork may be empty"
  fi
  REBUILD=$(curl -sf --max-time "$GRAPH_REBUILD_TIMEOUT" -X POST \
    "$API_BASE/projects/$PROJECT_ID/graph/rebuild" \
    ${AUTH[@]+"${AUTH[@]}"})
  REL=$(echo "$REBUILD" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('relations','?'))")
  ok "graph full rebuild relations=$REL"
else
  step "Graph status (incremental — ingest 已自动 syncIngestedSection)"
  GSTATUS=$(curl -sf ${AUTH[@]+"${AUTH[@]}"} "$API_BASE/projects/$PROJECT_ID/graph/status")
  AGE_OK=$(echo "$GSTATUS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',{}).get('ageOperational',False))")
  if [[ "$AGE_OK" == "True" ]]; then
    ok "AGE operational (incremental sync on ingest, no full rebuild)"
  else
    echo "WARN  AGE not operational — graphNetwork falls back to relation_table"
  fi
fi

step "Search smoke + graphNetwork"
SEARCH=$(curl -sf --max-time 120 -X POST "$API_BASE/projects/$PROJECT_ID/search" \
  ${AUTH[@]+"${AUTH[@]}"} \
  -H 'Content-Type: application/json' \
  -d '{"query":"需求项：汇率自动计算"}')
HAS_HITS=$(echo "$SEARCH" | python3 -c "
import json,sys
d=json.load(sys.stdin)
hits=(d.get('data') or {}).get('hits', [])
print('yes' if hits else 'no')
")
GRAPH_NET=$(echo "$SEARCH" | python3 -c "
import json,sys
d=json.load(sys.stdin)
hits=(d.get('data') or {}).get('hits', [])
for h in hits[:3]:
    gn=h.get('graphNetwork')
    if gn and gn.get('nodes'):
        print('yes'); break
else:
    print('no')
")
if [[ "$HAS_HITS" == "yes" ]]; then
  ok "search returned hits"
else
  bad "search no hits for 汇率自动计算"
fi
if [[ "$GRAPH_NET" == "yes" ]]; then
  ok "graphNetwork present on top hits"
elif [[ "$AGE_OK" == "True" ]]; then
  echo "WARN  AGE 已开但 graphNetwork 空 — 可试 GRAPH_REBUILD=full ./ci/local-sdd-loop.sh"
  bad "graphNetwork missing despite AGE operational"
else
  bad "graphNetwork missing"
fi

if [[ "$SKIP_ITERATION" != "true" ]]; then
  step "Iteration: patch SDD → commit → re-ingest"
  SPEC="$SDD_PATH/changes/specs/account-document-head-create/spec.md"
  MARKER="kb-loop-iteration-marker"
  if ! grep -q "$MARKER" "$SPEC" 2>/dev/null; then
    {
      printf '\n##### 场景：本地循环迭代验证（%s）\n' "$MARKER"
      printf '%s\n' '- **当** 运行 ci/local-sdd-loop.sh'
      printf '%s\n' '- **预期** 本场景被 ingest 并可检索'
    } >> "$SPEC"
    cd "$TEST_REPO_DIR"
    git add "$SPEC"
    git commit -m "test: add KB loop iteration scenario ($MARKER)"
    ok "committed SDD patch"
  else
    ok "iteration marker already present — skip patch"
  fi

  GIT_COMMIT2="$(cd "$TEST_REPO_DIR" && git rev-parse HEAD)"
  curl -sf --max-time "$INGEST_TIMEOUT" -X POST "$API_BASE/projects/$PROJECT_ID/ingest" \
    ${AUTH[@]+"${AUTH[@]}"} \
    -H 'Content-Type: application/json' \
    -d "$(ingest_json_body "$SDD_PATH" "$GIT_COMMIT2")" \
    >/dev/null
  ok "re-ingest commit=${GIT_COMMIT2:0:8}"

  ITER_SEARCH=$(curl -sf --max-time 120 -X POST "$API_BASE/projects/$PROJECT_ID/search" \
    ${AUTH[@]+"${AUTH[@]}"} \
    -H 'Content-Type: application/json' \
    -d '{"query":"本地循环迭代验证"}')
  ITER_HIT=$(echo "$ITER_SEARCH" | python3 -c "
import json,sys
hits=(json.load(sys.stdin).get('data') or {}).get('hits', [])
print('yes' if hits else 'no')
")
  if [[ "$ITER_HIT" == "yes" ]]; then
    ok "iteration scenario searchable"
  else
    bad "iteration scenario not found after re-ingest"
  fi
fi

if [[ "$SKIP_SUPERSEDE" != "true" ]]; then
  step "CI pipeline slice (scope hints + conflict suggest)"
  CODE_REPO="$TEST_REPO_DIR" RUN_GITNEXUS="${RUN_GITNEXUS:-false}" \
    ENGINEERING_KB_API="$API_BASE" ENGINEERING_KB_PROJECT_ID="$PROJECT_ID" \
    ENGINEERING_KB_TOKEN="${E2E_AUTH_TOKEN:-}" \
    SKIP_VALIDATE=true APPLY_SUPERSEDE="" \
    "$ROOT/ci/kb-ci-pipeline.sh" || bad "kb-ci-pipeline failed"
  ok "kb-ci-pipeline completed"
fi

step "Validate retrieval (fi-voucher-head)"
if API_BASE="$API_BASE" PROJECT_ID="$PROJECT_ID" "$ROOT/ci/validate-fi-voucher-head.sh"; then
  ok "validate-fi-voucher-head"
else
  bad "validate-fi-voucher-head"
fi

echo ""
echo "========================================"
echo "Local SDD loop summary: $pass passed, $fail failed"
echo "Test repo:  $TEST_REPO_DIR"
echo "Remote:     https://github.com/trtian/sdd-kb-test"
if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
echo "ALL PASS"
