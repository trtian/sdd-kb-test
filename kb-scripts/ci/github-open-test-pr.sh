#!/usr/bin/env bash
# 在 sdd-kb-test 上：同步脚本 → feature 分支 → push → 开真实 GitHub PR
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="${TEST_REPO_DIR:-$ROOT/workspace/sdd-kb-test}"
REMOTE="${GITHUB_REMOTE:-origin}"
BASE_BRANCH="${BASE_BRANCH:-main}"
FEATURE_PREFIX="${FEATURE_PREFIX:-feat/kb-loop}"

"$ROOT/ci/sync-kb-scripts-to-test-repo.sh" "$REPO/kb-scripts"
"$ROOT/ci/setup-sdd-kb-test.sh" 2>/dev/null || true

cd "$REPO"
STAMP="$(date +%Y%m%d%H%M%S)"
BRANCH="${FEATURE_PREFIX}-${STAMP}"

git checkout "$BASE_BRANCH" 2>/dev/null || git checkout -b "$BASE_BRANCH"
git add -A
if ! git diff --cached --quiet; then
  git commit -m "chore: sync kb-scripts and repo layout for GitHub PR loop"
fi

git checkout -b "$BRANCH"

# PR 变更：SDD 场景 + 代码注释
SPEC="openspec/changes/specs/account-document-head-create/spec.md"
MARKER="github-pr-${STAMP}"
if ! grep -q "$MARKER" "$SPEC" 2>/dev/null; then
  {
    printf '\n##### 场景：GitHub PR 闭环验证（%s）\n' "$MARKER"
    printf '%s\n' '- **当** PR merge 后触发 kb-merge-ingest workflow'
    printf '%s\n' '- **预期** 入库后可检索本场景'
  } >> "$SPEC"
fi
JAVA="src/main/java/com/klerp/fi/account/document/head/AccountDocumentHeadService.java"
mkdir -p "$(dirname "$JAVA")"
touch "$JAVA"
echo "// github-pr-loop-$STAMP" >> "$JAVA"

git add -A
git commit -m "feat: GitHub PR loop test ($MARKER)"

echo "==> Push branch $BRANCH"
git push -u "$REMOTE" "$BRANCH"

echo "==> Create Pull Request"
if command -v gh >/dev/null 2>&1; then
  gh pr create \
    --base "$BASE_BRANCH" \
    --head "$BRANCH" \
    --title "test: KB closed loop PR ($STAMP)" \
    --body "$(cat <<EOF
## 工程化知识库闭环测试 PR

- SDD 场景 marker: \`$MARKER\`
- PR Check workflow: \`.github/workflows/kb-pr-check.yml\`
- Merge 后: \`kb-merge-ingest.yml\`

### GitHub Secrets（仓库 Settings → Secrets）

| Secret | 示例 |
|--------|------|
| \`ENGINEERING_KB_API\` | 公网可达 KB API，如 ngrok \`https://xxx.ngrok.io/api\` |
| \`ENGINEERING_KB_PROJECT_ID\` | \`1\` |
| \`ENGINEERING_KB_TOKEN\` | 可选 Bearer |

本地 KB 仅 localhost 时，PR job 中 verify 需公网 URL 或 self-hosted runner。

EOF
)"
  gh pr view --web 2>/dev/null || gh pr view
else
  echo "Install gh CLI and run: gh pr create --base $BASE_BRANCH --head $BRANCH"
fi

echo ""
echo "Done. Branch: $BRANCH"
echo "Repo: https://github.com/trtian/sdd-kb-test"
