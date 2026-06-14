# sdd-kb-test

工程化知识库 **GitHub 闭环测试仓**（OpenSpec SDD + 模拟 Java 代码 + 自包含 `kb-scripts/`）。

## 仓库

https://github.com/trtian/sdd-kb-test

## 测试模式：Self-hosted Runner（本机）

PR / merge workflow 使用 **`runs-on: [self-hosted, macOS, kb-local]`**，在本机跑 Agent + localhost KB，无需 GitHub Secrets 里的 API Key。

### 1. 安装 runner（只需一次）

```bash
cd 工程化知识库
./ci/run-backend.sh                    # KB 后端
./ci/install-self-hosted-runner.sh     # 注册 runner
cd ~/actions-runners/sdd-kb-test && ./run.sh   # 前台运行（测试用）
```

### 2. 推送 workflow 并开 PR

```bash
gh auth login && gh auth setup-git
./ci/github-open-test-pr.sh
```

GitHub 开 PR 后 → 本机 runner 拉 job → `kb-pr-gather` → `claude -p`（CC Switch）→ PR comment。

## GitHub Actions

| Workflow | 触发 | Runner |
|----------|------|--------|
| `kb-pr-check.yml` | pull_request → main | self-hosted macOS |
| `kb-merge-ingest.yml` | push main | self-hosted macOS |

前提：本机 `claude` CLI（CC Switch）、KB `http://127.0.0.1:8090/api`、runner 进程 `./run.sh` 在跑。

## 目录

```text
openspec/          # SDD
src/               # 模拟业务代码
kb-scripts/        # 同步自工程化知识库 ci + skills
.kb-ci/            # CI 产物（本地，勿提交）
kb-pr-check.yml    # PR 流水线 manifest
```

同步：`工程化知识库/ci/sync-kb-scripts-to-test-repo.sh`
