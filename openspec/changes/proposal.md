---
# 【用户选择配置】
mode: "full"           # full=每个能力域独立文档(specs/<capability>/*)
test-strategy: "tdd"   # tdd=测试先行
---

# proposal.md - 业务意图与上下文总览

> **定位**：变更的业务意图（Why）与上下文总览

---

## 1. 需求背景

### 1.1 现状问题

- 当前 `klerp-fi-all` 模块中，凭证头（BKPF）的 `AccountDocumentHeadBizServiceImpl` 已被删除（git status 显示 staged delete），凭证创建的核心业务逻辑缺失
- 凭证头的16个字段（凭证日期、过账日期、凭证类型、公司代码、货币、汇率、凭证编号等）的填充、校验、联动逻辑均未实现
- 凭证编号生成缺乏统一的分布式并发安全机制

### 1.2 业务诉求

- 实现手工记账场景下凭证头的完整创建流程：**填充前校验 → 字段填充 → 填充后校验 → 持久化**
- 凭证编号通过公共组件 `DocumentNumberUtil` 生成，基于 Redis + Redisson 保证分布式并发安全
- 汇率根据公司代码本位币与凭证货币自动计算（本位币=1，外币查 TCURR 表）
- 过账日期需校验是否在公司代码的允许记账期间内（T001B 三组期间范围）

---

## 2. 业务目标

| 目标维度 | 具体描述 | 验收标准 |
|---------|---------|---------|
| 功能目标 | 实现凭证头 create 方法，覆盖16个字段的填充与校验 | 手工记账场景下凭证头可正确创建并持久化 |
| 质量目标 | 凭证编号分布式唯一、汇率计算正确、账期校验准确 | 单元测试覆盖所有校验分支和填充逻辑 |
| 体验目标 | 异常场景给出明确的中文错误提示 | 所有 BusinessException 包含可读的错误描述 |

---

## 3. 能力分解

### 3.1 新增能力

- `account-document-head-create`: 凭证头创建——包含填充前校验（必填/外键存在性/凭证类型联动）、字段填充（凭证编号/过账年度期间/汇率/换算日期/参考类型/参考关键字）、填充后校验（编号唯一性/账期校验）、持久化

### 3.2 修改能力

- 无（本次为全新实现，不涉及已有能力的修改）

---

## 4. 影响范围

### 4.1 涉及模块

- [x] `klerp-fi-all/klerp-fi`：新建 `AccountDocumentHeadBizServiceImpl`（核心业务逻辑）
- [x] `klerp-fi-all/klerp-fi`：新建 `AccountDocumentHeadBizService`（业务接口）
- [x] `klerp-data-all/klerp-fi-data`：已有 `AccountDocumentHead` 实体，只读不修改
- [x] `klerp-data-all/klerp-org-data`：已有 `CompanyCode`、`ControllingAreaAssignment` 实体，只读
- [x] `klerp-data-all/klerp-common-data`：已有 `DocumentType`、`AllowedPostingPeriod`、`FiscalYearVariant`、`ExchangeRate`、`Currency` 实体，只读

### 4.2 依赖关系

```
[DocumentNumberUtil(公共组件)] --> [凭证编号生成] --> [凭证头 create]
[CompanyCode / DocumentType / Currency] --> [填充前校验]
[FiscalYearVariant / ExchangeRate / AllowedPostingPeriod] --> [字段填充 + 填充后校验]
```

### 4.3 数据影响

- 数据库表变更：无（仅写入 BKPF 对应表，表已存在）
- 接口变更：新建 `AccountDocumentHeadBizService` 接口，新增 `create(AccountDocumentHead)` 方法
- 配置变更：`DocumentNumberUtil` 需在应用启动时完成 `init()` 初始化

---

## 5. 约束与假设

### 5.1 业务约束

- 本次仅实现**手工记账**场景（`referenceProcess = "BKPF"`），其他业务来源后续补充
- 往来凭证编号（`numberofCrossCompanyCode`）本次不处理
- 科目类型校验、贸易伙伴逻辑、字段状态组、起息日等属于行项目级别，不在凭证头范围内

### 5.2 技术约束

- 凭证编号生成依赖 `DocumentNumberUtil` 公共组件（`com.cnpc.common.customizesupport.sequence`）
- 所有查询必须使用 `LambdaQueryWrapper`，禁止字符串拼接 SQL
- 异常统一转换为 `BusinessException`，日志记录完整堆栈
- Provider 层方法必须标注 `@Transactional(rollbackFor = Exception.class)`

### 5.3 前置依赖

- [x] `DocumentNumberUtil` 公共组件：已可用（jar 包已引入）
- [x] BKPF 及相关配置表：已在数据库中创建
- [x] 实体类与 Service/Mapper：已由建模平台生成

---

## 6. 风险评估

| 风险项 | 概率 | 影响 | 应对策略 |
|-------|------|------|---------|
| 凭证编号重复（Redis 号段与 DB 不一致） | 低 | 高 | postFillValidate 中 DB 唯一性兜底校验 |
| 汇率表无数据导致创建失败 | 中 | 中 | 明确抛出 BusinessException，提示运维配置汇率 |
| 账期配置缺失导致校验跳过 | 低 | 低 | 无配置时跳过校验（不阻塞），后续可加强 |

---

## 7. 相关文档

- 需求文档：`ds/财务凭证头.md`
- 技术设计：`ds/财务凭证头-技术设计.md`
- 架构分析：`arch.md`
- S/4 字段映射：`ds/财务凭证头.md` 末尾对照表

---

> **质量红线检查清单**
> - [x] 逻辑链路已闭环（preFillValidate → fillHeadFields → postFillValidate → save）
> - [x] 受影响模块已明确（仅 klerp-fi-all/klerp-fi 新建文件）
> - [x] 依赖关系已梳理（公共组件 + 8张配置表）
> - [x] 能力分解章节已明确列出所有能力（1个能力域：account-document-head-create）
