# sdd-kb-test

工程化知识库 **GitHub 闭环测试仓**（OpenSpec SDD + 模拟 Java 代码 + 自包含 `kb-scripts/`）。

## 仓库

https://github.com/trtian/sdd-kb-test

**当前状态**：本地已含 Agent-only PR 工作流；远程需 `git push` 后 Actions 才生效（需 `gh auth login`）。

## 一键开真实 PR（本地）

```bash
# 1. 登录 GitHub（只需一次）
gh auth login
gh auth setup-git

# 2. 开 PR（同步 kb-scripts → feature 分支 → push → gh pr create）
cd 工程化知识库
./ci/github-open-test-pr.sh
```

## GitHub Actions

| Workflow | 触发 | 作用 |
|----------|------|------|
| `kb-pr-check.yml` | pull_request | gather 工具链 → **Claude Agent 裁决**（必须） |
| `kb-merge-ingest.yml` | push main | ingest + validate（需 KB API） |

架构说明：`kb-pr-check.yml`（仓根 manifest）。

### Secrets（Settings → Secrets and variables → Actions）

| Name | PR check | Merge ingest | 说明 |
|------|----------|--------------|------|
| `ANTHROPIC_API_KEY` | **必填** | — | Claude Code CLI；无则 PR job 失败 |
| `ENGINEERING_KB_API` | 推荐 | **必填** | KB 公网 URL，如 `https://<ngrok>/api` |
| `ENGINEERING_KB_PROJECT_ID` | 可选 | 可选 | 默认 `1` |
| `ENGINEERING_KB_TOKEN` | 可选 | 可选 | local 账号 login token |

- PR 检查 **无规则 fallback、无 offline approve**；`kb-pr-gather.sh` 在 KB 不可达时仍产出 artifact，由 Agent 裁决。
- Merge ingest 在缺少 `ENGINEERING_KB_API` 时 **明确失败**（不静默 skip）。

### 暴露本地 KB 给 GitHub（示例 ngrok）

```bash
./ci/run-backend.sh
ngrok http 8090
# Secret ENGINEERING_KB_API = https://xxxx.ngrok-free.app/api
```

## 目录

```text
openspec/          # SDD
src/               # 模拟业务代码
kb-scripts/        # 同步自工程化知识库 ci + skills
.kb-ci/            # CI 产物（本地，勿提交）
kb-pr-check.yml    # PR 流水线 manifest
kb.yml
```

同步脚本：`工程化知识库/ci/sync-kb-scripts-to-test-repo.sh`
