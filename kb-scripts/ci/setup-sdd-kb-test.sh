#!/usr/bin/env bash
# 初始化本地 GitHub 测试仓 workspace/sdd-kb-test
# 远程：https://github.com/trtian/sdd-kb-test
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_REPO_DIR="${TEST_REPO_DIR:-$ROOT/workspace/sdd-kb-test}"
GITHUB_URL="${GITHUB_URL:-https://github.com/trtian/sdd-kb-test.git}"
SAMPLE_ROOT="$ROOT/SDD文档/财务凭证头SDD相关文档20260429"
SAMPLE_OPENSPEC="$SAMPLE_ROOT/openspec"
PUSH_REMOTE="${PUSH_REMOTE:-false}"

mkdir -p "$(dirname "$TEST_REPO_DIR")"

seed_from_sample() {
  echo "==> Seed openspec from sample: $SAMPLE_OPENSPEC"
  if [[ ! -d "$SAMPLE_OPENSPEC" ]]; then
    echo "ERROR: sample openspec missing: $SAMPLE_OPENSPEC" >&2
    exit 1
  fi
  mkdir -p "$TEST_REPO_DIR/openspec"
  mkdir -p "$TEST_REPO_DIR/.kb-ci"
  rsync -a --delete "$SAMPLE_OPENSPEC/" "$TEST_REPO_DIR/openspec/"
  cp "$ROOT/samples/kb.yml" "$TEST_REPO_DIR/kb.yml"
  cp "$ROOT/samples/code-capability-map.yml" "$TEST_REPO_DIR/.kb-ci/code-capability-map.yml"
  echo '{"capabilities":[],"changedFiles":[],"gitBase":"HEAD~1","gitHead":"HEAD"}' \
    > "$TEST_REPO_DIR/.kb-ci/gitnexus-scope-hints.json"
  cat > "$TEST_REPO_DIR/README.md" <<'EOF'
# sdd-kb-test

工程化知识库本地循环测试仓（OpenSpec SDD 样本）。

- `openspec/` — 财务凭证头 SDD（account-document-head-create）
- `kb.yml` — 知识库解析配置
- `.kb-ci/` — CI 范围提示与 capability 映射

由 `ci/setup-sdd-kb-test.sh` 初始化；循环验证见 `deploy/README-local-loop.md`。
EOF
}

init_git() {
  cd "$TEST_REPO_DIR"
  if [[ ! -d .git ]]; then
    git init -b main
    git config user.email "kb-local@test.dev"
    git config user.name "KB Local Loop"
  fi
  if ! git remote get-url origin >/dev/null 2>&1; then
    git remote add origin "$GITHUB_URL"
  else
    git remote set-url origin "$GITHUB_URL"
  fi
  git add -A
  if git diff --cached --quiet; then
    echo "==> Nothing to commit (already seeded)"
  else
    git commit -m "chore: seed OpenSpec SDD for KB local loop"
  fi
}

if [[ -d "$TEST_REPO_DIR/.git" ]]; then
  echo "==> Test repo exists: $TEST_REPO_DIR"
  cd "$TEST_REPO_DIR"
  git fetch origin 2>/dev/null || true
  if git rev-parse origin/main >/dev/null 2>&1; then
    git checkout main 2>/dev/null || git checkout -b main
    git pull --rebase origin main 2>/dev/null || true
  fi
  if [[ ! -d openspec/changes/specs/account-document-head-create ]]; then
    seed_from_sample
    init_git
  fi
elif git clone "$GITHUB_URL" "$TEST_REPO_DIR" 2>/dev/null; then
  echo "==> Cloned from $GITHUB_URL"
  if [[ ! -d "$TEST_REPO_DIR/openspec/changes/specs/account-document-head-create" ]]; then
    seed_from_sample
    init_git
  fi
else
  echo "==> Clone failed or repo empty — create local seed"
  mkdir -p "$TEST_REPO_DIR"
  seed_from_sample
  init_git
fi

# Ensure .kb-ci exists even after pull
mkdir -p "$TEST_REPO_DIR/.kb-ci"
if [[ ! -f "$TEST_REPO_DIR/.kb-ci/code-capability-map.yml" ]]; then
  cp "$ROOT/samples/code-capability-map.yml" "$TEST_REPO_DIR/.kb-ci/code-capability-map.yml"
fi

if [[ "$PUSH_REMOTE" == "true" ]]; then
  echo "==> Push to $GITHUB_URL"
  cd "$TEST_REPO_DIR"
  git push -u origin main || echo "WARN: push failed — run manually: cd $TEST_REPO_DIR && git push -u origin main"
fi

echo "==> Test repo ready: $TEST_REPO_DIR"
echo "    openspec: $TEST_REPO_DIR/openspec"
echo "    remote:   $GITHUB_URL"
