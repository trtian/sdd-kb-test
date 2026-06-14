#!/usr/bin/env bash
# 将 .kb-ci Agent 产物整理为本地可读报告（Markdown + JSON）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CODE_REPO="${CODE_REPO:-$ROOT/workspace/sdd-kb-test}"
KB_SCRIPTS="${ENGINEERING_KB_SCRIPTS:-$ROOT}"
OUT_DIR="$CODE_REPO/.kb-ci"
STAMP="${REPORT_STAMP:-$(date +%Y%m%d%H%M%S)}"
REPORT_DIR="${REPORT_DIR:-$ROOT/deploy/agent-reviews}"
REPORT_JSON="$REPORT_DIR/pr-agent-review-${STAMP}.json"
REPORT_MD="$REPORT_DIR/pr-agent-review-${STAMP}.md"

mkdir -p "$REPORT_DIR"

if [[ ! -f "$OUT_DIR/pr-review.json" ]]; then
  echo "==> No pr-review.json — running gather + agent..."
  export CODE_REPO ENGINEERING_KB_SCRIPTS="$KB_SCRIPTS"
  export GIT_BASE="${GIT_BASE:-origin/main}"
  export GIT_HEAD="${GIT_HEAD:-HEAD}"
  bash "$KB_SCRIPTS/ci/kb-pr-gather.sh"
  bash "$KB_SCRIPTS/ci/kb-pr-agent.sh"
fi

cp "$OUT_DIR/pr-review.json" "$REPORT_JSON"
[[ -f "$OUT_DIR/pr-review.raw.txt" ]] && cp "$OUT_DIR/pr-review.raw.txt" "$REPORT_DIR/pr-agent-review-${STAMP}.raw.txt"

python3 - <<PY
import json
from pathlib import Path
from datetime import datetime, timezone

out_dir = Path("$OUT_DIR")
report_md = Path("$REPORT_MD")
review = json.loads((out_dir / "pr-review.json").read_text(encoding="utf-8"))

def load(name):
    p = out_dir / name
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else None

diff_a = load("pr-diff-analysis.json")
verify = load("kb-gitnexus-verify.json")
supersede = load("supersede-suggestions.json")
scope = load("gitnexus-scope-hints.json")

lines = [
    "# PR Agent 审查报告",
    "",
    f"- 生成时间: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC",
    f"- 代码仓: \`$CODE_REPO\`",
    f"- JSON: \`$REPORT_JSON\`",
    "",
    "## 裁决",
    "",
    f"- **verdict**: \`{review.get('verdict', '?')}\`",
    f"- **mode**: {review.get('mode', '?')}",
    f"- **confidence**: {review.get('confidence', '?')}",
    "",
    f"**summary**: {review.get('summary', '')}",
    "",
]

for title, key in [("SDD 问题", "sddIssues"), ("代码 vs Spec 缺口", "codeVsSpecGaps"), ("建议动作", "recommendedActions")]:
    items = review.get(key) or []
    lines += [f"## {title}", ""]
    if items:
        lines += [f"- {x}" for x in items]
    else:
        lines += ["- （无）"]
    lines.append("")

lines += [
    f"- **supersedeRecommended**: {review.get('supersedeRecommended', False)}",
    "",
    "## 工具链摘要",
    "",
]
if diff_a:
    lines += [
        f"- diffVerdict: `{diff_a.get('diffVerdict', '?')}`",
        f"- filesChanged: {diff_a.get('filesChanged', diff_a.get('stats', {}).get('filesChanged', '?'))}",
        f"- sddChanged: {diff_a.get('sddChanged', '?')}",
        f"- codeChanged: {diff_a.get('codeChanged', '?')}",
        "",
    ]
if verify:
    lines += [
        f"- kb-verify verdict: `{verify.get('verdict', '?')}`",
        f"- evidenceLevel: {verify.get('evidenceLevel', '?')}",
        "",
    ]
if scope and scope.get("changedFiles"):
    lines += ["### 变更文件", ""] + [f"- `{f}`" for f in scope["changedFiles"][:20]] + [""]

lines += ["## 完整 pr-review.json", "", "```json", json.dumps(review, ensure_ascii=False, indent=2), "```", ""]
report_md.write_text("\n".join(lines), encoding="utf-8")
print(report_md)
PY

echo "==> Report: $REPORT_MD"
echo "==> JSON:   $REPORT_JSON"
