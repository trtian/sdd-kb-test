#!/usr/bin/env bash
# PR 阶段 Step A：仅收集 artifact（脚本 = 工具，不做最终裁决）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CODE_REPO="${CODE_REPO:-${CI_PROJECT_DIR:-.}}"
CODE_REPO="$(cd "$CODE_REPO" 2>/dev/null && pwd || echo "$CODE_REPO")"
if [[ -d "$CODE_REPO/kb-scripts/ci" ]]; then
  KB_SCRIPTS="${ENGINEERING_KB_SCRIPTS:-$CODE_REPO/kb-scripts}"
else
  KB_SCRIPTS="${ENGINEERING_KB_SCRIPTS:-$ROOT}"
fi
export ENGINEERING_KB_API="${ENGINEERING_KB_API:-http://localhost:8090/api}"
API_BASE="$ENGINEERING_KB_API"
PROJECT_ID="${ENGINEERING_KB_PROJECT_ID:-1}"
if [[ -z "${ENGINEERING_KB_TOKEN:-}" && -f "$KB_SCRIPTS/ci/e2e-auth.sh" ]]; then
  # shellcheck source=/dev/null
  source "$KB_SCRIPTS/ci/e2e-auth.sh"
  export ENGINEERING_KB_TOKEN="${ENGINEERING_KB_TOKEN:-${E2E_AUTH_TOKEN:-}}"
fi
GIT_BASE="${GIT_BASE:-HEAD~1}"
GIT_HEAD="${GIT_HEAD:-HEAD}"
OUT_DIR="$CODE_REPO/.kb-ci"
mkdir -p "$OUT_DIR"

PR_DIFF="$OUT_DIR/pr-diff.patch"
git -C "$CODE_REPO" diff "$GIT_BASE" "$GIT_HEAD" > "$PR_DIFF" || true

echo "==> [gather-1] GitNexus scope (tool → opsx-kb-gitnexus-ci)"
CODE_REPO="$CODE_REPO" GIT_BASE="$GIT_BASE" GIT_HEAD="$GIT_HEAD" \
  OUTPUT="$OUT_DIR/gitnexus-scope-hints.json" \
  RUN_GITNEXUS="${RUN_GITNEXUS:-false}" \
  "$KB_SCRIPTS/ci/gitnexus-scope-hints.sh"

echo "==> [gather-2] Diff structure (tool → opsx-kb-pr-diff)"
node "$KB_SCRIPTS/skills/opsx-kb-pr-diff/scripts/analyze-diff.cjs" \
  --diff-path="$PR_DIFF" \
  --code-repo="$CODE_REPO" \
  --scope-hints-path="$OUT_DIR/gitnexus-scope-hints.json" \
  > "$OUT_DIR/pr-diff-analysis.json"

echo "==> [gather-3] KB conflict hints (tool → opsx-kb-ingest)"
if curl -sf --max-time 8 "$API_BASE/health" >/dev/null 2>&1; then
  if ! node "$KB_SCRIPTS/skills/opsx-kb-ingest/scripts/conflict-suggest.cjs" \
    --project-id="$PROJECT_ID" \
    --scope-hints-path="$OUT_DIR/gitnexus-scope-hints.json" \
    --git-commit="${GITHUB_SHA:-$(git -C "$CODE_REPO" rev-parse HEAD)}" \
    > "$OUT_DIR/supersede-suggestions.json" 2>/dev/null; then
    echo '{"ok":false,"mode":"conflict-tool-error","suggestions":[],"hint":"Agent may proceed without supersede hints"}' \
      > "$OUT_DIR/supersede-suggestions.json"
  fi
else
  echo '{"ok":true,"mode":"kb-unreachable","suggestions":[],"hint":"Agent must note KB offline"}' \
    > "$OUT_DIR/supersede-suggestions.json"
fi

echo "==> [gather-4] KB retrieve + code scan (tool → opsx-kb-gitnexus-verify)"
PRIMARY_Q=$(python3 -c "import json; print(json.load(open('$OUT_DIR/pr-diff-analysis.json')).get('searchQueries',['需求项：填充前必填字段校验'])[0])")
if curl -sf --max-time 8 "$API_BASE/health" >/dev/null 2>&1; then
  node "$KB_SCRIPTS/skills/opsx-kb-gitnexus-verify/scripts/verify.cjs" \
    --project-id="$PROJECT_ID" \
    --code-repo="$CODE_REPO" \
    --scope-hints-path="$OUT_DIR/gitnexus-scope-hints.json" \
    --diff-analysis-path="$OUT_DIR/pr-diff-analysis.json" \
    --question="$PRIMARY_Q" \
    > "$OUT_DIR/kb-gitnexus-verify.json"
else
  python3 -c "
import json
from pathlib import Path
diff=json.loads(Path('$OUT_DIR/pr-diff-analysis.json').read_text())
Path('$OUT_DIR/kb-gitnexus-verify.json').write_text(json.dumps({
  'ok': True, 'mode': 'kb-unreachable', 'verdict': 'unknown',
  'question': diff.get('searchQueries',[''])[0],
  'hint': 'KB API down — Agent decides using diff + patch only'
}, ensure_ascii=False, indent=2))
"
fi

echo "==> Artifacts ready in $OUT_DIR"
ls -la "$OUT_DIR"/*.json "$PR_DIFF" 2>/dev/null || true
