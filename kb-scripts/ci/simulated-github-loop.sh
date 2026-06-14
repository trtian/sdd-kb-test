#!/usr/bin/env bash
# 模拟完整 GitHub 闭环（本地一键，可见 pipeline-state.json + 后台流水线页）
# SDD+代码 → PR 分析 → merge 入库 → validate（无 AGE rebuild）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CODE_REPO="${CODE_REPO:-$ROOT/workspace/sdd-kb-test}"
KB_SCRIPTS="$ROOT"
API_BASE="${ENGINEERING_KB_API:-http://localhost:8090/api}"
PROJECT_ID="${ENGINEERING_KB_PROJECT_ID:-1}"
STATE_FILE="$CODE_REPO/.kb-ci/pipeline-state.json"
RUN_ID="run-$(date +%Y%m%d%H%M%S)"

mkdir -p "$CODE_REPO/.kb-ci"

write_stage() {
  local id="$1" label="$2" status="$3"
  local extra="${4:-{}}"
  python3 -c "
import json, os, datetime
path=os.environ['STATE_FILE']
run_id=os.environ['RUN_ID']
stages=[]
if os.path.isfile(path):
    try: stages=json.load(open(path)).get('stages',[])
    except: pass
stages=[s for s in stages if s.get('id')!=os.environ['SID']]
stages.append({
  'id': os.environ['SID'],
  'label': os.environ['SLABEL'],
  'status': os.environ['SSTATUS'],
  'at': datetime.datetime.utcnow().isoformat()+'Z',
  'extra': json.loads(os.environ.get('SEXTRA','{}'))
})
doc={'runId': run_id, 'updatedAt': datetime.datetime.utcnow().isoformat()+'Z', 'repo': os.path.basename(os.environ['CODE_REPO']), 'stages': stages}
json.dump(doc, open(path,'w'), ensure_ascii=False, indent=2)
" SID="$id" SLABEL="$label" SSTATUS="$status" SEXTRA="$extra" STATE_FILE="$STATE_FILE" RUN_ID="$RUN_ID" CODE_REPO="$CODE_REPO"
  echo "  stage $id → $status"
}

echo "========================================"
echo " Simulated GitHub KB Closed Loop"
echo " repo: $CODE_REPO"
echo " run:  $RUN_ID"
echo "========================================"

write_stage "sdd-dev" "SDD + 代码开发" "running" '{}'
# 小改：代码注释 + SDD 场景
JAVA="$CODE_REPO/src/main/java/com/klerp/fi/account/document/head/AccountDocumentHeadService.java"
STAMP="$(date +%H%M%S)"
if ! grep -q "pipeline-loop-$STAMP" "$JAVA" 2>/dev/null; then
  echo "// pipeline-loop-$STAMP: simulated dev change" >> "$JAVA"
  cd "$CODE_REPO" && git add -A && git commit -m "feat: simulated dev change $STAMP" >/dev/null || true
fi
write_stage "sdd-dev" "SDD + 代码开发" "success" "{\"commit\":\"$(git -C "$CODE_REPO" rev-parse --short HEAD)\"}"

write_stage "pr-open" "打开 PR（模拟）" "success" '{"branch":"feature/simulated"}'

write_stage "pr-analyze" "PR 分析 (Skills + claude)" "running" '{}'
CLAUDE_PR="${CLAUDE_PR:-false}" CODE_REPO="$CODE_REPO" ENGINEERING_KB_SCRIPTS="$KB_SCRIPTS" \
  ENGINEERING_KB_API="$API_BASE" ENGINEERING_KB_PROJECT_ID="$PROJECT_ID" \
  GIT_BASE="HEAD~1" GIT_HEAD="HEAD" \
  bash "$ROOT/ci/kb-pr-analyze.sh"
VERDICT=$(python3 -c "import json; print(json.load(open('$CODE_REPO/.kb-ci/kb-gitnexus-verify.json')).get('verdict','?'))")
write_stage "pr-analyze" "PR 分析 (Skills + claude)" "success" "{\"verifyVerdict\":\"$VERDICT\"}"

write_stage "merge" "合并 main（模拟）" "success" '{}'

# shellcheck disable=SC1091
source "$ROOT/ci/e2e-auth.sh"

write_stage "ingest" "入库 + 增量 sync" "running" '{}'
if ! curl -sf --max-time 5 "$API_BASE/health" >/dev/null; then
  write_stage "ingest" "入库" "failed" '{"error":"backend down"}'
  echo "WARN backend down — start ./ci/run-backend.sh and re-run merge stage only"
  exit 1
fi
CODE_REPO="$CODE_REPO" ENGINEERING_KB_API="$API_BASE" ENGINEERING_KB_PROJECT_ID="$PROJECT_ID" \
  RUN_GITNEXUS=false SKIP_VALIDATE=true APPLY_SUPERSEDE="" \
  bash "$ROOT/ci/kb-ci-pipeline.sh"
AUTH_H=()
if [[ -n "${E2E_AUTH_TOKEN:-}" ]]; then AUTH_H=(-H "Authorization: Bearer ${E2E_AUTH_TOKEN}"); fi
JOB_ID=$(curl -sf "${AUTH_H[@]+"${AUTH_H[@]}"}" "$API_BASE/projects/$PROJECT_ID/ingest/jobs" 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin).get('data',[]); print(d[0]['id'] if d else '')" 2>/dev/null || echo "")
write_stage "ingest" "入库 + 增量 sync" "success" "{\"ingestJobId\":\"$JOB_ID\"}"

write_stage "validate" "检索验证" "running" '{}'
if API_BASE="$API_BASE" PROJECT_ID="$PROJECT_ID" bash "$ROOT/ci/validate-fi-voucher-head.sh"; then
  write_stage "validate" "检索验证" "success" '{}'
else
  write_stage "validate" "检索验证" "failed" '{}'
  exit 1
fi

echo ""
echo "ALL PASS — pipeline state: $STATE_FILE"
echo "View in admin UI: 闭环流水线 page (project id=$PROJECT_ID)"
