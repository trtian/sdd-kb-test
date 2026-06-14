---
name: opsx-kb-gitnexus-verify
description: Compares Engineering KB current SDD retrieval results against business code using GitNexus scope hints and path mapping. Use after KB search or in PR CI to verify code matches current valid spec rules. Outputs structured verdict JSON for opsx-kb-pr-review or claude -p.
---

# KB + GitNexus 代码校验

**用途**：知识库检索到的 **current** SDD 规则，与业务代码仓实际实现做比对（非 opsx-check）。

## Workflow

```
- [ ] Step 1: 确保 KB 已 ingest current sections
- [ ] Step 2: 生成 scope hints（git diff / GitNexus）
- [ ] Step 3: 运行 verify CLI
- [ ] Step 4: 根据 verdict 决定 PR / 开发下一步
```

## Step 2: Scope hints

```bash
CODE_REPO=workspace/sdd-kb-test ci/gitnexus-scope-hints.sh
```

## Step 3: Verify

```bash
node skills/opsx-kb-gitnexus-verify/scripts/verify.cjs \
  --question="需求项：填充前必填字段校验" \
  --code-repo=workspace/sdd-kb-test \
  --scope-hints-path=workspace/sdd-kb-test/.kb-ci/gitnexus-scope-hints.json
```

## 输出字段

| 字段 | 含义 |
|------|------|
| `evidenceLevel` | 须为 `CURRENT_EVIDENCE` 才可作依据 |
| `topHit` | 权威 SDD 切片溯源 |
| `codeCompare.matched` | 代码中出现的规则短语 |
| `codeCompare.missing` | SDD 要求但代码未命中 |
| `verdict` | `pass` / `warn` / `fail` |

## 与 GitNexus 分工

| 组件 | 职责 |
|------|------|
| GitNexus | CI 代码索引 + diff 符号（不进 KB 库） |
| **本 Skill** | KB current 规则 ↔ 代码文本/路径比对 |
| opsx-kb-pr-review | 汇总 verify + diff → claude -p 结论 |

## CI 集成

`ci/kb-pr-analyze.sh` 第 3 步自动调用，产出 `.kb-ci/kb-gitnexus-verify.json`。
