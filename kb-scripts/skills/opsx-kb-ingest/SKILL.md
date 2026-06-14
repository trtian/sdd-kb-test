---
name: opsx-kb-ingest
description: Guides CI or local ingest of OpenSpec SDD markdown into Engineering KB with section manifest, embeddings, and graph sync. Use after merge to main, when refreshing kb_section_manifest, or when wiring GitNexus scope hints for conflict/supersede detection.
---

# 工程知识库入库（CI / 本地）

将 SDD Markdown 按 **#### 需求项 + ##### 场景** 切片入库，维护 logical/revision ID 与 Manifest 状态。

## Workflow

```
Task Progress:
- [ ] Step 1: 确认 kb.yml / openspec 路径
- [ ] Step 2:（CI）GitNexus 范围提示
- [ ] Step 3: ingest
- [ ] Step 4: graph rebuild（AGE 开启时）
- [ ] Step 5: conflict-suggest → 可选 supersede
- [ ] Step 6: validate 检索冒烟
```

## Step 1: 路径与配置

- OpenSpec 根目录：`<repo>/openspec`
- 解析规则：`samples/kb.yml`（`scenario_heading: 5`）

## Step 2: GitNexus 范围（CI）

```bash
CODE_REPO=. RUN_GITNEXUS=false ci/gitnexus-scope-hints.sh
# → .kb-ci/gitnexus-scope-hints.json
```

专项 Skill：**opsx-kb-gitnexus-ci**

## Step 3: ingest

**统一 CLI（推荐）**：

```bash
./bin/kb ingest \
  --source-path=workspace/sdd-kb-test/openspec \
  --git-commit="$(git -C workspace/sdd-kb-test rev-parse HEAD)" \
  --git-branch=main \
  --scope-hints-path=workspace/sdd-kb-test/.kb-ci/gitnexus-scope-hints.json
```

**CI 一键**：

```bash
ci/kb-ci-pipeline.sh
```

**本地脚本**：

```bash
ci/ingest-local.sh
SDD_PATH=workspace/sdd-kb-test/openspec ci/ingest-local.sh
```

## Step 4: graph rebuild

```bash
./bin/kb graph rebuild
```

入库后 `SectionGraphService` 会增量 sync；全量 rebuild 用于 AGE 与 manifest 对齐。

## Step 5: supersede

```bash
ci/apply-supersede.sh samples/supersede-fi-hotfix-example.json
```

正式环境由 CI `claude -p`（`ci/claude-supersede.prompt.md`）产出 actions。

## Step 6: validate

```bash
ci/validate-fi-voucher-head.sh
```

## 环境变量

```env
ENGINEERING_KB_API=http://localhost:8090/api
ENGINEERING_KB_PROJECT_ID=1
CODE_REPO=                        # kb-ci-pipeline 业务仓路径
SDD_PATH=                         # ingest-local 覆盖
```

## 禁止

- 不得把 Java 源码或 `.gitnexus/` 整库 ingest 进 PostgreSQL
- GitNexus 仅作 CI 加速器，不进知识库
