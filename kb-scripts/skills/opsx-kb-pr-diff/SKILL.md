---
name: opsx-kb-pr-diff
description: Analyzes pull request git diff for OpenSpec SDD and code changes, maps to capabilities, and emits search queries for KB verification. Use in PR CI before opsx-kb-gitnexus-verify and opsx-kb-pr-review. Outputs pr-diff-analysis.json for claude -p agent.
---

# PR Diff 分析 Skill

PR 阶段 **第一步 diff 结构化**（脚本为主，Agent 读产物）。

## 何时用

- GitHub `pull_request` / 本地 `kb-pr-analyze.sh`
- 在 **opsx-kb-gitnexus-verify** 之前

## 执行

```bash
# diff 由 kb-pr-analyze.sh 生成：.kb-ci/pr-diff.patch
node skills/opsx-kb-pr-diff/scripts/analyze-diff.cjs \
  --diff-path=workspace/sdd-kb-test/.kb-ci/pr-diff.patch \
  --code-repo=workspace/sdd-kb-test \
  --scope-hints-path=workspace/sdd-kb-test/.kb-ci/gitnexus-scope-hints.json
```

## 输出 `pr-diff-analysis.json`

| 字段 | 含义 |
|------|------|
| `files` | PR 变更文件列表 |
| `headingChanges` | OpenSpec `####/#####` 增删 |
| `searchQueries` | 供 verify 动态检索的 query 列表 |
| `capabilities` | 影响的 capability |
| `diffVerdict` | `pass` / `warn`（仅改代码未改 SDD） |

## Agent（claude -p）用法

将以下文件一并喂给 `opsx-kb-pr-review`：

- `pr-diff.patch`
- `pr-diff-analysis.json`
- `gitnexus-scope-hints.json`
- `kb-gitnexus-verify.json`

## CI 配置

见测试仓 `kb-pr-check.yml`（Skills 链顺序）。
