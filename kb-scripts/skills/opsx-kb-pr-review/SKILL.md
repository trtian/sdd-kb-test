---
name: opsx-kb-pr-review
description: Mandatory AI Agent PR review using claude -p after tooling scripts gather artifacts. Orchestrates opsx-kb-pr-diff, opsx-kb-gitnexus-verify, and KB conflict hints. Final approve/block is Agent-only — no rule-based fallback in CI. Use on pull_request events or ci/kb-pr-analyze.sh.
---

# PR 审查 Agent（claude -p，必须）

## 架构（v2）

```text
kb-pr-gather.sh     → 工具脚本，只产 artifact（不裁决）
kb-pr-agent.sh      → claude -p + 本 Skill + 关联 Skills（唯一裁决）
kb-pr-analyze.sh    → gather + agent
```

**禁止**：生产 CI 用 Python 规则拼 `approve/block`（`ALLOW_RULE_FALLBACK` 仅本地调试）。

## GitHub PR 自动审核

**是自动触发**。`pull_request` 事件 → `.github/workflows/kb-pr-check.yml`：

1. `kb-pr-gather.sh`
2. `kb-pr-agent.sh`（需 Secret `ANTHROPIC_API_KEY`）
3. 自动 `gh pr comment` 贴 Agent 结论

配置见仓库根 `kb-pr-check.yml`。

## 本地

```bash
export ANTHROPIC_API_KEY=...
./ci/kb-pr-analyze.sh
# 或
./ci/kb-pr-gather.sh && ./ci/kb-pr-agent.sh
```

## Agent 读取的 Skills（注入 system prompt）

- opsx-kb-pr-diff
- opsx-kb-gitnexus-verify
- opsx-kb-retrieve
- opsx-kb-pr-review

## Agent 输入文件（`.kb-ci/`）

| 文件 | 来源 |
|------|------|
| pr-diff.patch | git diff |
| pr-diff-analysis.json | opsx-kb-pr-diff |
| gitnexus-scope-hints.json | opsx-kb-gitnexus-ci |
| supersede-suggestions.json | opsx-kb-ingest |
| kb-gitnexus-verify.json | opsx-kb-gitnexus-verify |

## 输出

`pr-review.json` — `verdict`: approve | request_changes | block

Prompt：`ci/claude-pr-review.prompt.md`
