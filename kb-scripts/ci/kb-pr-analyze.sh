#!/usr/bin/env bash
# PR 阶段：GitNexus 范围 → 冲突建议 →（可选）claude -p PR 审查 → GitNexus+KB 校验
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CODE_REPO="${CODE_REPO:-${CI_PROJECT_DIR:-.}}"
if [[ -d "$CODE_REPO/kb-scripts/ci" ]]; then
  KB_SCRIPTS="${ENGINEERING_KB_SCRIPTS:-$CODE_REPO/kb-scripts}"
else
  KB_SCRIPTS="${ENGINEERING_KB_SCRIPTS:-$ROOT}"
fi
API_BASE="${ENGINEERING_KB_API:-http://localhost:8090/api}"
PROJECT_ID="${ENGINEERING_KB_PROJECT_ID:-1}"
GIT_BASE="${GIT_BASE:-HEAD~1}"
GIT_HEAD="${GIT_HEAD:-HEAD}"
CLAUDE_PR="${CLAUDE_PR:-true}"
OUT_DIR="$CODE_REPO/.kb-ci"
mkdir -p "$OUT_DIR"

echo "==> [PR-1] GitNexus scope hints"
CODE_REPO="$CODE_REPO" GIT_BASE="$GIT_BASE" GIT_HEAD="$GIT_HEAD" \
  OUTPUT="$OUT_DIR/gitnexus-scope-hints.json" \
  RUN_GITNEXUS="${RUN_GITNEXUS:-false}" \
  "$KB_SCRIPTS/ci/gitnexus-scope-hints.sh"

echo "==> [PR-2] Conflict suggestions"
node "$KB_SCRIPTS/skills/opsx-kb-ingest/scripts/conflict-suggest.cjs" \
  --project-id="$PROJECT_ID" \
  --scope-hints-path="$OUT_DIR/gitnexus-scope-hints.json" \
  --git-commit="${GITHUB_SHA:-$(git -C "$CODE_REPO" rev-parse HEAD)}" \
  > "$OUT_DIR/supersede-suggestions.json"
cat "$OUT_DIR/supersede-suggestions.json"

echo "==> [PR-3] KB + GitNexus verify (rule retrieval vs code)"
node "$KB_SCRIPTS/skills/opsx-kb-gitnexus-verify/scripts/verify.cjs" \
  --project-id="$PROJECT_ID" \
  --code-repo="$CODE_REPO" \
  --scope-hints-path="$OUT_DIR/gitnexus-scope-hints.json" \
  --question="需求项：填充前必填字段校验" \
  > "$OUT_DIR/kb-gitnexus-verify.json"
cat "$OUT_DIR/kb-gitnexus-verify.json"

echo "==> [PR-4] Claude PR review (optional)"
PR_DIFF="$OUT_DIR/pr-diff.patch"
git -C "$CODE_REPO" diff "$GIT_BASE" "$GIT_HEAD" > "$PR_DIFF" || true

if [[ "$CLAUDE_PR" == "true" ]] && command -v claude >/dev/null 2>&1; then
  claude -p "$(cat "$KB_SCRIPTS/ci/claude-pr-review.prompt.md")" \
    --append-system-prompt "Read files: $OUT_DIR/gitnexus-scope-hints.json $OUT_DIR/supersede-suggestions.json $OUT_DIR/kb-gitnexus-verify.json $PR_DIFF — output JSON only." \
    > "$OUT_DIR/pr-review.json" || echo '{"ok":false,"error":"claude failed"}' > "$OUT_DIR/pr-review.json"
else
  python3 -c "
import json
from pathlib import Path
hints=json.loads(Path('$OUT_DIR/gitnexus-scope-hints.json').read_text())
sugg=json.loads(Path('$OUT_DIR/supersede-suggestions.json').read_text())
verify=json.loads(Path('$OUT_DIR/kb-gitnexus-verify.json').read_text())
out={
  'ok': True,
  'mode': 'rule-based-fallback',
  'summary': 'claude unavailable — see kb-gitnexus-verify and supersede-suggestions',
  'verifyVerdict': verify.get('verdict'),
  'conflictCount': len(sugg.get('suggestions') or sugg.get('items') or []),
  'changedCapabilities': hints.get('capabilities') or hints.get('matchedCapabilities') or []
}
Path('$OUT_DIR/pr-review.json').write_text(json.dumps(out, ensure_ascii=False, indent=2))
"
fi
cat "$OUT_DIR/pr-review.json"

echo "==> PR analyze done → $OUT_DIR"
