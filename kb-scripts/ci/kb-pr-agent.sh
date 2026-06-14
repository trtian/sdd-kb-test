#!/usr/bin/env bash
# PR 阶段 Step B：AI Agent 裁决（必须）— claude -p + Skills 文档
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CODE_REPO="${CODE_REPO:-${CI_PROJECT_DIR:-.}}"
CODE_REPO="$(cd "$CODE_REPO" 2>/dev/null && pwd || echo "$CODE_REPO")"
if [[ -d "$CODE_REPO/kb-scripts/ci" ]]; then
  KB_SCRIPTS="${ENGINEERING_KB_SCRIPTS:-$CODE_REPO/kb-scripts}"
else
  KB_SCRIPTS="${ENGINEERING_KB_SCRIPTS:-$ROOT}"
fi
OUT_DIR="$CODE_REPO/.kb-ci"
ALLOW_RULE_FALLBACK="${ALLOW_RULE_FALLBACK:-false}"
if [[ "${CI:-}" == "true" || "${GITHUB_ACTIONS:-}" == "true" ]]; then
  if [[ "$ALLOW_RULE_FALLBACK" == "true" ]]; then
    echo "ERROR: ALLOW_RULE_FALLBACK forbidden in CI — PR review is Agent-only" >&2
    exit 1
  fi
  ALLOW_RULE_FALLBACK=false
fi

skill_block() {
  local name="$1"
  local f="$KB_SCRIPTS/skills/$name/SKILL.md"
  if [[ -f "$f" ]]; then
    echo "=== Skill: $name ==="
    cat "$f"
    echo ""
  fi
}

if [[ ! -f "$OUT_DIR/pr-diff-analysis.json" ]]; then
  echo "ERROR: run kb-pr-gather.sh first" >&2
  exit 1
fi

AGENT_SKILLS=$(skill_block opsx-kb-pr-diff; skill_block opsx-kb-gitnexus-verify; skill_block opsx-kb-pr-review; skill_block opsx-kb-retrieve)

run_claude_agent() {
  local raw="$OUT_DIR/pr-review.raw.txt"
  claude -p "$(cat "$KB_SCRIPTS/ci/claude-pr-review.prompt.md")" \
    --append-system-prompt "$(cat <<EOF
You are the PR review Agent. Follow the Skills below. Tools already ran; do NOT re-run scripts.
Read these files in $OUT_DIR:
- pr-diff.patch
- pr-diff-analysis.json
- gitnexus-scope-hints.json
- supersede-suggestions.json
- kb-gitnexus-verify.json

$AGENT_SKILLS

Output ONLY valid JSON for pr-review.json schema in the user prompt. No markdown, no code fences, no prose.
EOF
)" > "$raw"
  python3 - <<'PY'
import json, re, sys
from pathlib import Path
raw_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
text = raw_path.read_text(encoding="utf-8").strip()
for candidate in (text,):
    try:
        obj = json.loads(candidate)
        out_path.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")
        sys.exit(0)
    except json.JSONDecodeError:
        pass
m = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.S)
if m:
    obj = json.loads(m.group(1))
    out_path.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")
    sys.exit(0)
m = re.search(r"\{.*\}", text, re.S)
if m:
    obj = json.loads(m.group(0))
    out_path.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")
    sys.exit(0)
print("ERROR: could not parse Agent JSON from claude output", file=sys.stderr)
sys.exit(1)
PY
  "$raw" "$OUT_DIR/pr-review.json"
}

echo "==> [agent] Claude PR review (opsx-kb-pr-review) — REQUIRED"

if command -v claude >/dev/null 2>&1; then
  if run_claude_agent; then
    echo "==> Agent completed → $OUT_DIR/pr-review.json"
    cat "$OUT_DIR/pr-review.json"
    exit 0
  fi
  echo "WARN claude -p failed" >&2
fi

if [[ "$ALLOW_RULE_FALLBACK" == "true" ]]; then
  echo "WARN ALLOW_RULE_FALLBACK=true — dev only, not for production" >&2
  python3 -c "
import json
from pathlib import Path
p=Path('$OUT_DIR/pr-review.json')
p.write_text(json.dumps({
  'ok': False,
  'mode': 'rule-fallback-blocked-in-prod',
  'verdict': 'block',
  'summary': 'Claude Agent unavailable — configure claude CLI + ANTHROPIC_API_KEY',
  'confidence': 0
}, ensure_ascii=False, indent=2))
"
  cat "$OUT_DIR/pr-review.json"
  exit 1
fi

echo "ERROR: AI Agent required. Install: claude CLI + ANTHROPIC_API_KEY" >&2
echo "  brew install claude-code  # or npm i -g @anthropic-ai/claude-code" >&2
echo "  export ANTHROPIC_API_KEY=..." >&2
echo "  Dev escape hatch: ALLOW_RULE_FALLBACK=true (not for CI)" >&2
exit 1
