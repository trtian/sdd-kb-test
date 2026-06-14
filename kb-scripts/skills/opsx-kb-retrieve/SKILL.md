---
name: opsx-kb-retrieve
description: Retrieves current-valid SDD sections from Engineering KB with mandatory citation and graphNetwork context. Use when implementing code, answering spec questions, or needing authoritative engineering facts with status=current. Do not use for MM/CO business term explanations — use opsx-knowledge (RAGFlow) instead.
---

# 工程知识库检索（SDD 事实层）

从 Engineering KB 检索 **current** Section，作为开发实现依据。

## 与 opsx-knowledge 分工

| Skill | 用途 |
|-------|------|
| **opsx-kb-retrieve** | 当前有效 SDD 工程事实 |
| **opsx-knowledge** | MM/CO 业务名词（RAGFlow） |

## Workflow

```
Task Progress:
- [ ] Step 1: 确认 ENGINEERING_KB_API 可达（./bin/kb health）
- [ ] Step 2: 执行检索 CLI
- [ ] Step 3: 检查 evidenceLevel
- [ ] Step 4: 输出带溯源的回答
- [ ] Step 5:（可选）GitNexus 校验代码实现
```

### Step 1: 健康检查

```bash
./bin/kb health
```

### Step 2: 检索

**推荐（统一 CLI）**：

```bash
./bin/kb search --question="汇率反向查表规则是什么" --project-id=1
```

**Skill 脚本（兼容）**：

```bash
node skills/opsx-kb-retrieve/scripts/search.cjs --question="汇率反向查表规则是什么"
```

### Step 3: 检查 evidenceLevel

| 值 | 行为 |
|----|------|
| `CURRENT_EVIDENCE` | 可作为开发依据 |
| `NO_CURRENT_EVIDENCE` | **禁止**编造当前规则；仅引用 `historicalHints` |

### Step 4: 回答模板

每条命中必须列出：

- `logicalSectionId` / `sectionRevisionId`
- `sourcePath` + `headingPath`
- `status`、`evidenceRole`（应为 `current_fact`）
- `gitCommit`、`sliceKind`、`rrfScore`
- `graphNetwork`（若存在）：supersede / 父子 / capability；`source=age` 来自 Apache AGE

```markdown
📎 工程知识库（current_fact，开发依据）：
- 规则：...
- 来源：`{sourcePath}` → `{headingPath}`
- logical: `{logicalSectionId}` | revision: `{sectionRevisionId}` | commit: `{gitCommit}`
- 关系网：{graphNetwork.nodes.length} nodes（source=age）

说明：evidenceLevel=NO_CURRENT_EVIDENCE 时不可作为实现依据。
```

### Step 5: 代码二次校验

对 citation 中的类名/方法，用 **GitNexus** 做实现校验。

## 环境变量

```env
ENGINEERING_KB_API=http://localhost:8090/api
ENGINEERING_KB_PROJECT_ID=1
ENGINEERING_KB_TOKEN=          # 可选，缺省自动 login
```

## 故障排查

| 现象 | 处理 |
|------|------|
| 无命中 | 先 `./bin/kb ingest` 或 `ci/ingest-local.sh` |
| graphNetwork 空 | `./bin/kb graph rebuild` |
| 401 | `./bin/kb auth login` 并 export token |
