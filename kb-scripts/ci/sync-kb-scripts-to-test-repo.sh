#!/usr/bin/env bash
# 将工程化知识库 CI/Skills 同步到 sdd-kb-test（GitHub Actions 自包含，无需 ENGINEERING_KB_SCRIPTS secret）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-$ROOT/workspace/sdd-kb-test/kb-scripts}"

mkdir -p "$TARGET"

rsync -a --delete \
  --exclude '.git' \
  "$ROOT/ci/" "$TARGET/ci/"

for s in opsx-kb-cli opsx-kb-ingest opsx-kb-gitnexus-verify opsx-kb-retrieve; do
  mkdir -p "$TARGET/skills/$s"
  rsync -a "$ROOT/skills/$s/" "$TARGET/skills/$s/"
done

cp "$ROOT/samples/code-capability-map.yml" "$TARGET/samples/code-capability-map.yml" 2>/dev/null || true

echo "Synced kb-scripts → $TARGET"
