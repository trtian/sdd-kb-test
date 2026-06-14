#!/usr/bin/env bash
# 在 CI 业务代码仓运行：索引 GitNexus（可选）+ git diff → capability 范围 JSON
# 输出默认：$CI_PROJECT_DIR/.kb-ci/gitnexus-scope-hints.json
set -euo pipefail

CODE_REPO="${CODE_REPO:-${CI_PROJECT_DIR:-.}}"
OUTPUT="${OUTPUT:-$CODE_REPO/.kb-ci/gitnexus-scope-hints.json}"
GIT_BASE="${GIT_BASE:-HEAD~1}"
GIT_HEAD="${GIT_HEAD:-HEAD}"
MAP_FILE="${CODE_CAPABILITY_MAP:-$(cd "$(dirname "$0")/.." && pwd)/samples/code-capability-map.yml}"
RUN_GITNEXUS="${RUN_GITNEXUS:-true}"

mkdir -p "$(dirname "$OUTPUT")"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

cd "$CODE_REPO"

echo "==> git diff $GIT_BASE..$GIT_HEAD"
git diff --name-only "$GIT_BASE" "$GIT_HEAD" > "$WORKDIR/changed.txt" || true

GITNEXUS_SYMBOLS="$WORKDIR/symbols.json"
echo "[]" > "$GITNEXUS_SYMBOLS"

if [[ "$RUN_GITNEXUS" == "true" ]] && command -v npx >/dev/null 2>&1; then
  echo "==> GitNexus index (CI 加速器，不进知识库)"
  if npx gitnexus status 2>/dev/null | grep -qi "indexed\|up to date"; then
    echo "    index present"
  else
    npx gitnexus analyze 2>/dev/null || echo "    warn: gitnexus analyze skipped/failed" >&2
  fi
  # 若 CLI 支持 detect-changes，可在此追加；MVP 用 git diff + 路径映射
fi

export CHANGED_FILES_LIST="$WORKDIR/changed.txt"
export GITNEXUS_SYMBOLS_FILE="$GITNEXUS_SYMBOLS"
export CODE_CAPABILITY_MAP="$MAP_FILE"
export GIT_BASE="$GIT_BASE"
export GIT_HEAD="$GIT_HEAD"

python3 "$(dirname "$0")/map-code-scope.py" > "$OUTPUT"
echo "==> wrote $OUTPUT"
cat "$OUTPUT"
