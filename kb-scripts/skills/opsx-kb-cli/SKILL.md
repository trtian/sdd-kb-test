---
name: opsx-kb-cli
description: Unified CLI for Engineering KB — search, ingest, graph rebuild, section manifest, and local loop verification. Use when exposing KB retrieval to agents/scripts, running kb search/ingest/graph from terminal, or validating the SDD-KB pipeline end-to-end.
---

# Engineering KB CLI

对外 CLI 入口，封装检索、入库、AGE 图、全链路循环。

## Quick start

```bash
chmod +x bin/kb
./bin/kb health
./bin/kb search --question="需求项：汇率自动计算"
./bin/kb ingest --source-path=workspace/sdd-kb-test/openspec --git-commit="$(git -C workspace/sdd-kb-test rev-parse HEAD)"
./bin/kb graph rebuild
./bin/kb loop --skip-graph   # 快速冒烟；去掉 skip 跑完整 AGE
```

## 环境变量

| 变量 | 默认 | 说明 |
|------|------|------|
| `ENGINEERING_KB_API` | `http://localhost:8090/api` | API 根路径 |
| `ENGINEERING_KB_PROJECT_ID` | `1` | 项目 ID |
| `ENGINEERING_KB_TOKEN` | — | Bearer；缺省则尝试 login |
| `E2E_PHONE` / `E2E_PASSWORD` | local 账号 | `auth login` 用 |

## 命令

### search

检索 `status=current` 的 SDD Section，Top 命中含 `graphNetwork`（AGE 开启时）。

```bash
./bin/kb search --question="凭证日期不能为空" --project-id=1
```

输出 JSON：`evidenceLevel`、`hits[]`（含溯源字段 + graphNetwork）。

### ingest

按 OpenSpec `####`/`#####` 切片入库。

```bash
./bin/kb ingest \
  --source-path=/abs/path/openspec \
  --git-commit=abc123 \
  --git-branch=main \
  --scope-hints-path=.kb-ci/gitnexus-scope-hints.json
```

### graph

```bash
./bin/kb graph status
./bin/kb graph rebuild          # 可能 5–10 分钟（RDS AGE）
./bin/kb graph network --logical-id=klerp3-fi:account-document-head-create:exchange-rate-calc
```

### loop

调用 `ci/local-sdd-loop.sh`，对接 GitHub 测试仓 [sdd-kb-test](https://github.com/trtian/sdd-kb-test)。

```bash
./bin/kb loop
./bin/kb loop --skip-graph --skip-iteration
```

## Agent 使用规范

1. **开发依据**：仅 `evidenceLevel=CURRENT_EVIDENCE` 的命中可作实现依据
2. **溯源必填**：`logicalSectionId`、`sourcePath`、`headingPath`、`gitCommit`
3. **图关系**：检查 `graphNetwork.source=age` 的 supersede/父子边
4. **NO_CURRENT_EVIDENCE**：不得编造规则；仅引用 `historicalHints`

## 脚本位置

- CLI：`skills/opsx-kb-cli/scripts/kb.cjs`
- 共享 HTTP 客户端：`skills/opsx-kb-cli/scripts/lib/client.cjs`
- 入口：`bin/kb`

## 相关 Skill

| Skill | 场景 |
|-------|------|
| opsx-kb-retrieve | Agent 检索回答模板 |
| opsx-kb-ingest | CI/本地入库流程 |
| opsx-kb-local-loop | 测试仓 + 迭代验证 |
| opsx-kb-gitnexus-ci | GitNexus 范围提示 |

详细本地环境见 [deploy/README-local-loop.md](../../deploy/README-local-loop.md)。
