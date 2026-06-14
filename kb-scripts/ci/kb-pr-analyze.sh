#!/usr/bin/env bash
# PR 全链路：gather（工具脚本）→ agent（AI 裁决，必须）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ENGINEERING_KB_API="${ENGINEERING_KB_API:-http://localhost:8090/api}"
"$ROOT/ci/kb-pr-gather.sh"
"$ROOT/ci/kb-pr-agent.sh"
echo "==> PR analyze complete (Agent-driven)"
