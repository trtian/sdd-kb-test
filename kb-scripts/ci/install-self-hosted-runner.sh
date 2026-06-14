#!/usr/bin/env bash
# 在本机注册 GitHub Actions self-hosted runner（测试验证用）
# 用法: ./ci/install-self-hosted-runner.sh [repo] [runner-name]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_SLUG="${1:-trtian/sdd-kb-test}"
RUNNER_NAME="${2:-$(hostname -s | tr ' ' '-')-kb-local}"
RUNNER_ROOT="${RUNNER_ROOT:-$HOME/actions-runners/sdd-kb-test}"
RUNNER_VERSION="${RUNNER_VERSION:-v2.335.1}"
ARCH="$(uname -m)"
case "$ARCH" in
  arm64) RUNNER_ARCH="osx-arm64" ;;
  x86_64) RUNNER_ARCH="osx-x64" ;;
  *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;;
esac

if ! command -v gh >/dev/null; then
  echo "ERROR: gh CLI required — run: gh auth login" >&2
  exit 1
fi

echo "==> Repo: $REPO_SLUG"
echo "==> Runner dir: $RUNNER_ROOT"
echo "==> Labels: self-hosted, macOS, kb-local"

mkdir -p "$RUNNER_ROOT"
cd "$RUNNER_ROOT"

if [[ ! -f ./config.sh ]]; then
  TAR="actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION#v}.tar.gz"
  URL="https://github.com/actions/runner/releases/download/${RUNNER_VERSION}/${TAR}"
  echo "==> Download $URL"
  curl -fsSL -o "$TAR" "$URL"
  tar xzf "$TAR"
  rm -f "$TAR"
fi

TOKEN="$(gh api "repos/${REPO_SLUG}/actions/runners/registration-token" --method POST --jq .token)"
./config.sh \
  --url "https://github.com/${REPO_SLUG}" \
  --token "$TOKEN" \
  --name "$RUNNER_NAME" \
  --labels "self-hosted,macOS,kb-local" \
  --unattended \
  --replace

cat <<EOF

==> Runner configured.

Start (foreground, 测试用 — 继承 CC Switch ~/.claude/settings.json):
  cd "$RUNNER_ROOT" && ./run.sh

或安装为 macOS 服务（开机自启）:
  cd "$RUNNER_ROOT" && ./svc.sh install && ./svc.sh start

前提:
  - KB 后端: $ROOT/ci/run-backend.sh  (http://127.0.0.1:8090/api)
  - claude CLI + CC Switch 已配置
  - 仓库 workflow 使用 runs-on: [self-hosted, macOS, kb-local]

验证 runner 在线:
  gh api repos/${REPO_SLUG}/actions/runners --jq '.runners[] | {name, status, labels}'

EOF
