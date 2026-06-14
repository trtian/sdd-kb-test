#!/usr/bin/env bash
# 工程知识库 CI 全链路（在业务代码仓 job 中调用，或拆成多 job）
# 1. GitNexus 范围提示  2. SDD ingest  3. 冲突建议  4.（可选）supersede  5. validate
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ENGINEERING_KB_API="${ENGINEERING_KB_API:-http://localhost:8090/api}"
API_BASE="$ENGINEERING_KB_API"
PROJECT_ID="${ENGINEERING_KB_PROJECT_ID:-1}"
if [[ -z "${ENGINEERING_KB_TOKEN:-}" && -f "$ROOT/ci/e2e-auth.sh" ]]; then
  # shellcheck source=/dev/null
  source "$ROOT/ci/e2e-auth.sh"
  export ENGINEERING_KB_TOKEN="${ENGINEERING_KB_TOKEN:-${E2E_AUTH_TOKEN:-}}"
fi
CODE_REPO="${CODE_REPO:-${CI_PROJECT_DIR:-.}}"
SDD_PATH="${SDD_PATH:-$CODE_REPO/openspec}"
GIT_COMMIT="${GIT_COMMIT:-${CI_COMMIT_SHA:-local}}"
GIT_BRANCH="${GIT_BRANCH:-${CI_COMMIT_REF_NAME:-main}}"
CI_PASSED="${CI_PASSED:-true}"
SCOPE_JSON="${SCOPE_JSON:-$CODE_REPO/.kb-ci/gitnexus-scope-hints.json}"
APPLY_SUPERSEDE="${APPLY_SUPERSEDE:-}"
CLAUDE_SUPERSEDE="${CLAUDE_SUPERSEDE:-false}"

echo "==> [1/5] GitNexus scope hints (code repo: $CODE_REPO)"
RUN_GITNEXUS="${RUN_GITNEXUS:-true}" OUTPUT="$SCOPE_JSON" \
  "$ROOT/ci/gitnexus-scope-hints.sh"

echo "==> [2/5] Ingest SDD"
node "$ROOT/skills/opsx-kb-ingest/scripts/ingest.cjs" \
  --project-id="$PROJECT_ID" \
  --source-path="$SDD_PATH" \
  --git-commit="$GIT_COMMIT" \
  --git-branch="$GIT_BRANCH" \
  --ci-passed="$CI_PASSED" \
  --scope-hints-path="$SCOPE_JSON"

echo "==> [3/5] Conflict supersede suggestions"
mkdir -p "$CODE_REPO/.kb-ci"
if ! node "$ROOT/skills/opsx-kb-ingest/scripts/conflict-suggest.cjs" \
  --project-id="$PROJECT_ID" \
  --scope-hints-path="$SCOPE_JSON" \
  --git-commit="$GIT_COMMIT" > "$CODE_REPO/.kb-ci/supersede-suggestions.json"; then
  echo '{"ok":false,"mode":"conflict-tool-error","suggestions":[]}' > "$CODE_REPO/.kb-ci/supersede-suggestions.json"
fi
cat "$CODE_REPO/.kb-ci/supersede-suggestions.json"

if [[ "$CLAUDE_SUPERSEDE" == "true" ]] && command -v claude >/dev/null 2>&1; then
  echo "==> [4/5] claude -p supersede (optional)"
  claude -p "$(cat "$ROOT/ci/claude-supersede.prompt.md")" \
    --append-system-prompt "Read $CODE_REPO/.kb-ci/supersede-suggestions.json and output JSON actions only." \
    > "$CODE_REPO/.kb-ci/claude-supersede-actions.json" || true
  if [[ -f "$CODE_REPO/.kb-ci/claude-supersede-actions.json" ]]; then
    APPLY_SUPERSEDE="$CODE_REPO/.kb-ci/claude-supersede-actions.json"
  fi
fi

if [[ -n "$APPLY_SUPERSEDE" && -f "$APPLY_SUPERSEDE" ]]; then
  echo "==> [4/5] Apply supersede from $APPLY_SUPERSEDE"
  BODY=$(python3 -c "import json; d=json.load(open('$APPLY_SUPERSEDE')); print(json.dumps({'actions': d.get('actions', d)}))")
  curl -sf -X POST "$API_BASE/projects/$PROJECT_ID/sections/supersede" \
    -H 'Content-Type: application/json' -d "$BODY"
  echo ""
fi

if [[ "${SKIP_VALIDATE:-false}" != "true" ]]; then
  echo "==> [5/5] Validate retrieval"
  API_BASE="$API_BASE" "$ROOT/ci/validate-fi-voucher-head.sh"
fi

echo "==> Done."
