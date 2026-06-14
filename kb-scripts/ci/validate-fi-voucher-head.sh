#!/usr/bin/env bash
# 财务凭证头 OpenSpec 样本 — 检索冒烟测试（对齐 案例-工程状态有效性-财务凭证头.md）
set -euo pipefail

API_BASE="${API_BASE:-http://localhost:8090/api}"
PROJECT_ID="${PROJECT_ID:-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -f "$ROOT/ci/e2e-auth.sh" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT/ci/e2e-auth.sh"
fi
AUTH_HEADER=()
if [[ -n "${E2E_AUTH_TOKEN:-}" ]]; then
  AUTH_HEADER=(-H "Authorization: Bearer ${E2E_AUTH_TOKEN}")
fi

pass=0
fail=0

check_top_hit() {
  local name="$1"
  local query="$2"
  local expect_file="$3"   # e.g. spec.md
  local expect_heading="$4" # substring in headingPath
  local optional="${5:-}"

  local top
  top=$(curl -sf --max-time 120 -X POST "$API_BASE/projects/$PROJECT_ID/search" \
    ${AUTH_HEADER[@]+"${AUTH_HEADER[@]}"} \
    -H 'Content-Type: application/json' \
    -d "$(python3 -c "import json; print(json.dumps({'query': '''$query'''}))")" \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)
payload=d.get('data') or {}
hits=payload.get('hits', payload if isinstance(payload, list) else [])
if not hits:
    print('NO_HITS'); sys.exit(0)
h=hits[0]
print(h.get('sourcePath','').split('/')[-1], '|', h.get('headingPath',''), '|', h.get('logicalSectionId','')[-40:])
")

  if [[ "$top" == NO_HITS* ]]; then
    echo "FAIL  $name — no hits for: $query"
    fail=$((fail + 1))
    return
  fi

  if [[ "$top" == *"$expect_file"* && "$top" == *"$expect_heading"* ]]; then
    echo "PASS  $name — $top"
    pass=$((pass + 1))
  elif [[ -n "$optional" ]]; then
    echo "WARN  $name — expected [$expect_file + $expect_heading], got: $top"
    echo "      query: $query"
  else
    echo "FAIL  $name — expected [$expect_file + $expect_heading], got: $top"
    echo "      query: $query"
    fail=$((fail + 1))
  fi
}

echo "==> health"
curl -sf --max-time 15 "$API_BASE/health" >/dev/null

echo "==> section count"
count=$(curl -sf --max-time 60 ${AUTH_HEADER[@]+"${AUTH_HEADER[@]}"} "$API_BASE/projects/$PROJECT_ID/sections?limit=500" \
  | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('data',[])))")
echo "sections: $count"
if [[ "$count" -lt 20 ]]; then
  echo "WARN  expected ~29 sections after ingest; run ci/ingest-local.sh first"
fi

echo ""
echo "==> retrieval checks (use 需求项 / design 标题词，FTS 更稳)"
check_top_hit "spec-汇率" "需求项：汇率自动计算" "spec.md" "汇率自动计算"
check_top_hit "spec-必填" "需求项：填充前必填字段校验" "spec.md" "填充前必填字段校验"
check_top_hit "design-账期" "6.2.4 过账日期账期校验" "design.md" "6.2.4 过账日期账期校验"
check_top_hit "design-编号" "6.2.2 凭证编号生成" "design.md" "6.2.2 凭证编号生成"

echo ""
echo "==> known gap (optional — embedding / heading boost)"
check_top_hit "nl-凭证日期" "凭证日期不能为空" "spec.md" "填充前必填字段校验" "optional"

echo ""
echo "Summary: $pass passed, $fail failed (required checks only)"
if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
