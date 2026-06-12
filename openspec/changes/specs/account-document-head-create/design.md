# 局部技术实现方案 - 凭证头创建

> **定位**：单一 Capability 的业务维度技术实现方案
>
> **⚠️ 边界声明**：本设计仅服务于当前 Capability（account-document-head-create），严禁越权设计或覆盖其他模块逻辑。
>
> **【质量红线】专注"本业务如何落地"；严禁写入全局中间件或框架选型；必须为任务拆解提供足够局部细节

---

## 1. 字段完整性追溯表

> **⛔ 核心红线**：用户在 Spec 中输入的所有字段必须在此表中体现，严禁无故丢弃！

### 1.1 字段映射表

| 序号 | 用户输入字段（S/4） | 设计输出字段（实体） | 字段类型 | 状态 | 理由说明 |
|-----|-------------------|---------------------|---------|------|---------|
| 1 | BLDAT（凭证日期） | `documentDate` | `Date` | ✅ 保留 | 用户输入，必填 |
| 2 | BUDAT（过账日期） | `postingDate` | `Date` | ✅ 保留 | 用户输入，必填，默认当前日期 |
| 3 | BLART（凭证类型） | `docType` | `String` | ✅ 保留 | 用户选择，必填，默认 SA |
| 4 | BUKRS（公司代码） | `companyCode` | `String` | ✅ 保留 | 用户选择，必填 |
| 5 | WWERT（换算日期） | `translationDate` | `Date` | ✅ 保留 | 选填，默认 = postingDate |
| 6 | GJAHR（过账年度） | `fiscalYear` | `String` | ✅ 保留 | 自动计算，从 postingDate 提取 |
| 7 | MONAT（过账期间） | `fiscalPeriod` | `String` | ✅ 保留 | 自动计算，从 postingDate 提取 |
| 8 | WAERS（货币） | `currencyKey` | `String` | ✅ 保留 | 用户输入，必填 |
| 9 | KURSF（汇率） | `exchangeRate` | `BigDecimal` | ✅ 保留 | 自动计算 |
| 10 | BELNR（凭证编号） | `documentNumber` | `String` | ⚠️ 待确认 | 自动生成；实体中字段名需确认（可能为 `documentId`） |
| 11 | BKTXT（凭证抬头文本） | `documentHeaderText` | `String` | ✅ 保留 | 用户输入，选填（受凭证类型联动） |
| 12 | NUMPG（页数） | `invoicePageCount` | `String` | ✅ 保留 | 用户输入，选填 |
| 13 | XBLNR（参照） | `referenceDocumentNumber` | `String` | ✅ 保留 | 用户输入，选填（受凭证类型联动） |
| 14 | AWTYP（参考类型） | `referenceProcess` | `String` | ✅ 保留 | 自动填充 "BKPF" |
| 15 | AWKEY（参考关键字） | `referenceKey` | `String` | ✅ 保留 | 自动填充 documentNumber+companyCode+fiscalYear |
| 16 | BVORG（往来凭证编号） | `numberofCrossCompanyCode` | `String` | ❌ 移除 | 跨公司记账逻辑，需求明确本次不考虑 |

**状态说明**：
- ✅ 保留：字段名和类型与用户输入一致
- ⚠️ 待确认：字段名需在实现时确认实体中的实际名称
- ❌ 移除：字段被移除（必须有充分理由且经用户确认）

### 1.2 完整性自检

- **用户输入字段总数**：16 个
- **设计输出字段总数**：15 个（1 个明确移除）
- **差异说明**：`BVORG（往来凭证编号）` 属于跨公司记账逻辑，需求文档明确"本次先不考虑此逻辑"，在 `create` 方法中不处理
- **完整性确认**：[x] 已确认所有字段都有对应处理

---

## 2. 现有代码锚点

> **⚠️ 重要**：大多数需求是在已有系统上改造/扩展，不是从零开始。

### 2.1 需修改的现有文件

无。本次为全新实现，不修改任何已有文件。

### 2.2 需新建的文件

| 文件路径（建议） | 类/模块名 | 职责 | 继承/实现 | 说明 |
|------------|----------|------|---------|------|
| `klerp-fi-all/klerp-fi/src/main/java/com/cnpc/erp/fi/account/bizservice/AccountDocumentHeadBizService.java` | `AccountDocumentHeadBizService` | 业务接口定义 | 纯接口 | 定义 `create(AccountDocumentHead)` 方法签名 |
| `klerp-fi-all/klerp-fi/src/main/java/com/cnpc/erp/fi/account/bizservice/impl/AccountDocumentHeadBizServiceImpl.java` | `AccountDocumentHeadBizServiceImpl` | 核心业务逻辑实现 | `extends ServiceImpl<AccountDocumentHeadMapper, AccountDocumentHead>` + `implements AccountDocumentHeadBizService, AccountDocumentHeadService` | 包含 preFillValidate / fillHeadFields / postFillValidate / save |

### 2.3 现有逻辑约束

| 约束项 | 当前现状 | 对本设计的影响 | 应对策略 |
|-------|---------|-------------|--------|
| 七层调用链路 | Controller → Feign → Provider → BizService → Service → Mapper → DB | BizServiceImpl 是业务逻辑唯一归宿，Provider 仅做 DTO↔Entity 转换 | 遵循 |
| 事务边界 | Provider 层 `@Transactional`，BizServiceImpl 写操作 `@Transactional` | `create` 方法必须标注 `@Transactional(rollbackFor = Exception.class)` | 遵循 |
| 异常处理 | 统一 `log.error(msg, e)` + `BusinessException` 包装 | 所有 catch 块必须记录完整堆栈并抛出 BusinessException | 遵循 |
| 查询构建 | 必须使用 `LambdaQueryWrapper` | 所有数据库查询使用 LambdaQueryWrapper | 遵循 |
| 依赖注入 | Provider/BizServiceImpl 使用 `@Autowired` 字段注入 | 依赖通过 `@Autowired` 注入 | 遵循 |
| 实体字段命名 | `CompanyCode.currency`（非 `currencyKey`）、`CompanyCode.postingPeriodVarnt`（非 `OPVAR`）、`DocumentType.prpsdRateExchRateType`（非 `exchangeRateType`） | 查询时需使用实际实体字段名 | 适配 |

---

## 3. 局部前端设计

> 本 Capability 为纯后端实现，无前端组件。前端凭证创建页面由建模平台生成，不在本设计范围内。

---

## 4. 局部后端接口设计

> 仅针对当前 Capability 的接口设计

### 4.1 接口清单

| 接口名称 | 路径 | 方法 | 说明 |
|---------|------|------|------|
| create | BizService 方法（非 HTTP 接口） | Java 方法调用 | 凭证头创建，由 Provider 层调用 |

### 4.2 接口详细设计

#### 方法：create

**基本信息**：
- 类：`AccountDocumentHeadBizServiceImpl`
- 方法签名：`public AccountDocumentHead create(AccountDocumentHead head)`
- 注解：`@Override` + `@Transactional(rollbackFor = Exception.class)`
- 调用方：Provider 层（DTO→Entity 转换后调用）

**请求参数**：

| 参数名 | 类型 | 必填 | 说明 | 约束 |
|-------|------|------|------|------|
| head | `AccountDocumentHead` | 是 | 凭证头实体，含用户输入的字段值 | 至少含 documentDate、postingDate、docType、companyCode、currencyKey |

**响应结构**：
```java
// 返回已持久化的 AccountDocumentHead 对象（含自增 ID 和自动填充的字段）
```

**业务逻辑**（四步流程）：

```
1. preFillValidate(head)     → 填充前校验
2. fillHeadFields(head)      → 字段填充
3. postFillValidate(head)    → 填充后校验
4. this.save(head)           → 持久化
```

---

## 5. 局部数据模型

> 仅针对当前 Capability 的数据设计，遵循 overview.md 的全局约定

### 5.1 数据表设计

#### 表名：account_document_head（BKPF 对应）

本 Capability 仅执行 **INSERT** 操作，不涉及表结构变更。

**涉及的核心字段**（仅列出本 Capability 写入的字段）：

| 字段名（实体） | 数据类型 | 必填 | 默认值 | 说明 | 索引 |
|-------|---------|------|--------|------|------|
| id | Long | 是 | 自动生成 | 主键 | PK |
| documentDate | Date | 是 | - | 凭证日期 | - |
| postingDate | Date | 是 | - | 过账日期 | - |
| docType | String(2) | 是 | - | 凭证类型 | - |
| companyCode | String(4) | 是 | - | 公司代码 | - |
| translationDate | Date | 否 | =postingDate | 换算日期 | - |
| fiscalYear | String(4) | 是 | - | 过账年度 | - |
| fiscalPeriod | String(2) | 是 | - | 过账期间 | - |
| currencyKey | String(5) | 是 | - | 货币 | - |
| exchangeRate | BigDecimal | 是 | - | 汇率 | - |
| documentNumber | String(10) | 是 | - | 凭证编号 | UNIQUE(companyCode, fiscalYear) |
| documentHeaderText | String(25) | 否 | - | 凭证抬头文本 | - |
| invoicePageCount | String(3) | 否 | - | 页数 | - |
| referenceDocumentNumber | String(16) | 否 | - | 参照 | - |
| referenceProcess | String(5) | 否 | "BKPF" | 参考类型 | - |
| referenceKey | String(20) | 否 | - | 参考关键字 | - |

**索引设计**：
- 主键索引：id
- 唯一索引：(companyCode, documentNumber, fiscalYear) — 用于填充后唯一性校验

### 5.2 缓存设计

| 缓存 Key 模式 | 数据类型 | 过期时间 | 更新策略 | 说明 |
|--------------|---------|---------|---------|------|
| 由 `DocumentNumberUtil` 内部管理 | - | - | - | 凭证编号号段缓存，本模块不直接操作 |

### 5.3 数据流转图

```
[用户输入 5 个必填字段]
       │
       ▼
[preFillValidate] ──查──▶ CompanyCode / DocumentType / Currency
       │
       ▼
[fillHeadFields]
  ├── fillFiscalYearAndPeriod ──查──▶ CompanyCode / FiscalYearVariant
  ├── generateDocumentNumber  ──调──▶ DocumentNumberUtil（Redis）
  ├── translationDate 默认值
  ├── fillExchangeRate        ──查──▶ CompanyCode / DocumentType / ExchangeRate
  └── referenceProcess / referenceKey
       │
       ▼
[postFillValidate]
  ├── documentNumber 非空
  ├── 唯一性校验              ──查──▶ AccountDocumentHead（DB）
  └── validatePostingPeriod   ──查──▶ CompanyCode / AllowedPostingPeriod
       │
       ▼
[this.save(head)] ──写──▶ account_document_head（DB）
       │
       ▼
[返回 AccountDocumentHead]
```

---

## 6. 模块内部逻辑

### 6.1 核心流程

```
create(head)
  │
  ├─ 1. preFillValidate(head)
  │     ├─ 1.1 必填字段非空：documentDate, postingDate, docType, companyCode, currencyKey
  │     ├─ 1.2 外键存在性：CompanyCode, DocumentType, Currency
  │     └─ 1.3 凭证类型联动：isDocHdrText → documentHeaderText 必填, isRefNum → referenceDocumentNumber 必填
  │
  ├─ 2. fillHeadFields(head)
  │     ├─ 2.1 fillFiscalYearAndPeriod(head)  ← 先算年度/期间（编号依赖 fiscalYear）
  │     ├─ 2.2 generateDocumentNumber(head)   ← DocumentNumberUtil
  │     ├─ 2.3 translationDate 默认 = postingDate
  │     ├─ 2.4 fillExchangeRate(head)         ← 本位币=1，外币查 TCURR
  │     ├─ 2.5 referenceProcess = "BKPF"
  │     └─ 2.6 referenceKey = documentNumber + companyCode + fiscalYear
  │
  ├─ 3. postFillValidate(head)
  │     ├─ 3.1 documentNumber 非空
  │     ├─ 3.2 凭证编号唯一性（DB 兜底）
  │     └─ 3.3 validatePostingPeriod(head)    ← T001B 三组期间范围
  │
  └─ 4. this.save(head)
```

### 6.2 关键算法

#### 6.2.1 过账年度和期间计算

```java
private void fillFiscalYearAndPeriod(AccountDocumentHead head) {
    Date postingDate = head.getPostingDate();
    Calendar cal = Calendar.getInstance();
    cal.setTime(postingDate);

    // 过账年度：取 postingDate 的年份
    int year = cal.get(Calendar.YEAR);
    head.setFiscalYear(String.valueOf(year));

    // 过账期间：根据公司代码的会计年度变式确定
    CompanyCode cc = getCompanyCode(head.getCompanyCode());
    String periv = cc.getFiscalYearVariant();  // T001-PERIV

    FiscalYearVariant fyv = getFiscalYearVariant(periv);
    if (fyv != null && "X".equals(fyv.getCalYearPeriod())) {
        // 公历年确定期间：月份即期间
        int month = cal.get(Calendar.MONTH) + 1;
        head.setFiscalPeriod(String.format("%02d", month));
    } else {
        // 非公历年场景暂默认按公历月份处理
        int month = cal.get(Calendar.MONTH) + 1;
        head.setFiscalPeriod(String.format("%02d", month));
    }
}
```

**数据来源**：
- `postingDate`：入参 `head.getPostingDate()`
- `CompanyCode.fiscalYearVariant`：查 CompanyCode 表
- `FiscalYearVariant.calYearPeriod`：查 FiscalYearVariant 表

**数据去脉**：
- 写入 `head.fiscalYear`、`head.fiscalPeriod`

**边界情况**：
- `FiscalYearVariant` 不存在 → 默认按公历月份处理
- 跨年日期（如 2026-01-15）→ fiscalYear="2026", fiscalPeriod="01"

#### 6.2.2 凭证编号生成

```java
private static final String NUM_RANGE_OBJECT_FI = "RF_BELEG";

private String generateDocumentNumber(AccountDocumentHead head) {
    DocumentType dt = getDocumentType(head.getDocType());
    String numberRange = dt.getNumberRange();  // T003-NUMKR

    NumberParams params = NumberParams.builder()
            .client(head.getClient())
            .numRangeObject(NUM_RANGE_OBJECT_FI)       // "RF_BELEG"
            .numRangeSubject(head.getCompanyCode())     // 公司代码
            .code(numberRange)                          // 号段编号
            .toFiscalYear(head.getFiscalYear())         // 会计年度
            .outerNumber(null)                          // 手工记账无外部编号
            .build();

    return DocumentNumberUtil.getDocumentNumberStr(params);
}
```

**数据来源**：
- `head.client`：入参
- `head.companyCode`：入参
- `head.fiscalYear`：步骤 2.1 已计算
- `DocumentType.numberRange`：查 DocumentType 表

**数据去脉**：
- 返回值写入 `head.documentNumber`

**边界情况**：
- `DocumentType.numberRange` 为空 → `DocumentNumberUtil` 内部处理或抛异常，调用方捕获包装为 `BusinessException`

#### 6.2.3 汇率计算

```java
private void fillExchangeRate(AccountDocumentHead head) {
    CompanyCode cc = getCompanyCode(head.getCompanyCode());
    String localCurrency = cc.getCurrency();  // T001-WAERS（注意：实体字段名为 currency）

    // 本位币场景：汇率固定为 1
    if (localCurrency.equals(head.getCurrencyKey())) {
        head.setExchangeRate(BigDecimal.ONE);
        return;
    }

    // 外币场景：查汇率表
    DocumentType dt = getDocumentType(head.getDocType());
    String rateType = dt.getPrpsdRateExchRateType();  // T003-KURST（注意：实体字段名）
    if (StringUtils.isBlank(rateType)) {
        rateType = "M";  // 默认汇率类型
    }

    // 换算日期（用于取有效汇率）
    Date transDate = head.getTranslationDate();
    if (transDate == null) {
        transDate = head.getPostingDate();
    }

    // 查询最晚有效汇率
    LambdaQueryWrapper<ExchangeRate> lqw = new LambdaQueryWrapper<>();
    lqw.eq(ExchangeRate::getExchangeRateType, rateType)
       .eq(ExchangeRate::getFromCurrency, localCurrency)
       .eq(ExchangeRate::getToCurrency, head.getCurrencyKey())
       .le(ExchangeRate::getExchangeRateValidFrom, transDate)
       .orderByDesc(ExchangeRate::getExchangeRateValidFrom)
       .last("LIMIT 1");
    ExchangeRate rate = exchangeRateService.getOne(lqw);

    if (rate == null) {
        throw new BusinessException("未找到汇率: " + localCurrency + " -> " + head.getCurrencyKey());
    }

    head.setExchangeRate(rate.getDirectExchangeRate());  // TCURR-UKURS
}
```

**数据来源**：
- `CompanyCode.currency`：查 CompanyCode 表（本位币）
- `DocumentType.prpsdRateExchRateType`：查 DocumentType 表（汇率类型）
- `ExchangeRate` 表：fromCurrency=本位币, toCurrency=凭证货币, validFrom<=换算日期

**数据去脉**：
- 写入 `head.exchangeRate`

**边界情况**：
- 本位币=凭证货币 → exchangeRate=1，不查表
- 汇率类型为空 → 默认 "M"
- 汇率表无匹配 → 抛 BusinessException
- 多条汇率记录 → 取 exchangeRateValidFrom 最晚的

#### 6.2.4 过账日期账期校验

```java
private void validatePostingPeriod(AccountDocumentHead head) {
    CompanyCode cc = getCompanyCode(head.getCompanyCode());
    String postingPeriodVariant = cc.getPostingPeriodVarnt();  // T001-OPVAR（注意：实体字段名）

    LambdaQueryWrapper<AllowedPostingPeriod> lqw = new LambdaQueryWrapper<>();
    lqw.eq(AllowedPostingPeriod::getCompanyCode, postingPeriodVariant);
    List<AllowedPostingPeriod> periods = allowedPostingPeriodService.list(lqw);

    if (CollectionUtils.isEmpty(periods)) {
        return;  // 无配置则不校验
    }

    Calendar cal = Calendar.getInstance();
    cal.setTime(head.getPostingDate());
    int year = cal.get(Calendar.YEAR);
    int month = cal.get(Calendar.MONTH) + 1;

    boolean inRange = false;
    for (AllowedPostingPeriod period : periods) {
        inRange = inRange || isInPeriodRange(period, year, month);
    }

    if (!inRange) {
        throw new BusinessException("输入的记账日期未打开");
    }
}

private boolean isInPeriodRange(AllowedPostingPeriod period, int year, int month) {
    return isInRange(period.getFromFiscalYear1(), period.getFromPeriod1(),
                     period.getToFiscalYear1(), period.getToPeriod1(), year, month)
        || isInRange(period.getFromFiscalYear2(), period.getFromPeriod2(),
                     period.getToFiscalYear2(), period.getToPeriod2(), year, month)
        || isInRange(period.getFromFiscalYear3(), period.getFromPeriod3(),
                     period.getToFiscalYear3(), period.getToPeriod3(), year, month);
}

private boolean isInRange(String fromYear, String fromPeriod,
                          String toYear, String toPeriod, int year, int month) {
    if (StringUtils.isBlank(fromYear) || StringUtils.isBlank(fromPeriod)) {
        return false;
    }
    int fy = Integer.parseInt(fromYear);
    int fp = Integer.parseInt(fromPeriod);
    int ty = Integer.parseInt(toYear);
    int tp = Integer.parseInt(toPeriod);

    int fromVal = fy * 100 + fp;
    int toVal = ty * 100 + tp;
    int curVal = year * 100 + month;

    return curVal >= fromVal && curVal <= toVal;
}
```

**数据来源**：
- `CompanyCode.postingPeriodVarnt`：查 CompanyCode 表
- `AllowedPostingPeriod` 表：三组 (fromFiscalYear, fromPeriod) → (toFiscalYear, toPeriod)

**数据去脉**：
- 校验通过则继续，失败则抛 BusinessException

**边界情况**：
- 无配置 → 跳过校验
- 边界值（恰好等于 from 或 to）→ 包含在范围内
- 某组范围的 fromYear/fromPeriod 为空 → 该组视为无效，跳过

---

## 7. 外部依赖与集成

> **⚠️ 必填**：列出本 Capability 依赖的所有外部系统、服务和基础设施。

### 7.1 外部服务依赖

| 依赖服务 | 用途 | 调用方式 | 超时设置 | 失败影响 | 降级方案 |
|---------|------|---------|---------|---------|--------|
| Redis（Redisson） | 凭证编号分布式流 | `DocumentNumberUtil` 内部 SDK 调用 | 5 秒 | 阻塞，凭证创建失败 | 无降级，编号生成强依赖 |

### 7.2 第三方 API / SDK

| 名称 | 版本/文档链接 | 用途 | 鉴权方式 | 费用/限流 | 备注 |
|------|-------------|------|---------|----------|------|
| common-dev（DocumentNumberUtil） | dev-SNAPSHOT | 凭证编号生成 | 无 | 无 | jar 包已引入，需在启动时 `init()` |

### 7.3 中间件 & 基础设施

| 组件 | 用途 | 使用方式 | 关键配置 | 备注 |
|------|------|---------|---------|------|
| MySQL | 凭证头持久化 + 配置表查询 | MyBatis-Plus | 数据源配置 | 8.3.0 |
| Redis | 凭证编号号段缓存 | Redisson（通过 DocumentNumberUtil） | 连接配置 | 版本待确认 |

### 7.4 内部跨模块依赖

> 本 Capability 需要调用项目内其他模块的能力（注意：仅声明依赖，不设计对方逻辑）

| 依赖模块 | 调用接口/方法 | 输入 | 预期输出 | 当前状态 |
|---------|-------------|------|---------|--------|
| klerp-data-all/klerp-fi-data | `AccountDocumentHeadMapper` / `AccountDocumentHeadService` | Entity 对象 | 基础 CRUD | 已有 |
| klerp-data-all/klerp-org-data | `CompanyCodeService.getOne(lqw)` | companyCode | CompanyCode 实体 | 已有 |
| klerp-data-all/klerp-org-data | `ControllingAreaAssignmentService.getOne(lqw)` | companyCode | ControllingAreaAssignment 实体 | 已有 |
| klerp-data-all/klerp-common-data | `DocumentTypeService.getOne(lqw)` | docType | DocumentType 实体 | 已有 |
| klerp-data-all/klerp-common-data | `AllowedPostingPeriodService.list(lqw)` | postingPeriodVariant | List\<AllowedPostingPeriod\> | 已有 |
| klerp-data-all/klerp-common-data | `FiscalYearVariantService.getOne(lqw)` | periv | FiscalYearVariant 实体 | 已有 |
| klerp-data-all/klerp-common-data | `ExchangeRateService.getOne(lqw)` | rateType, from, to, date | ExchangeRate 实体 | 已有 |
| klerp-data-all/klerp-common-data | `CurrencyService.getOne(lqw)` | currencyKey | Currency 实体 | 已有 |

### 7.5 环境 & 权限要求

| 依赖项 | 说明 | 获取方式 |
|-------|------|--------|
| 数据库连接 | account_document_head 表 INSERT 权限 | 数据源配置 |
| Redis 连接 | DocumentNumberUtil 需要 RedissonClient | 应用配置 |
| DocumentNumberUtil 初始化 | 启动时调用 `init(RedissonClient, ...)` | 配置类或启动监听器 |

---

## 8. 异常处理

### 8.1 异常分类

| 异常类型 | 触发条件 | 处理策略 | 用户感知 |
|---------|---------|---------|---------|
| 参数校验异常 | 必填字段为空 | 抛出 `BusinessException("XXX不能为空")` | 明确的中文错误提示 |
| 外键不存在 | CompanyCode/DocumentType/Currency 查不到 | 抛出 `BusinessException("XXX不存在: {value}")` | 明确的中文错误提示 |
| 凭证类型联动 | isDocHdrText/isRefNum 要求必填但未提供 | 抛出 `BusinessException("当前凭证类型要求XXX为必填")` | 明确的中文错误提示 |
| 编号生成失败 | DocumentNumberUtil 返回空或异常 | 抛出 `BusinessException("凭证编号生成失败")` | 明确的中文错误提示 |
| 编号重复 | DB 唯一性校验失败 | 抛出 `BusinessException("凭证编号已存在: {number}")` | 明确的中文错误提示 |
| 汇率缺失 | ExchangeRate 表无匹配 | 抛出 `BusinessException("未找到汇率: {from} -> {to}")` | 明确的中文错误提示 |
| 账期未打开 | postingDate 不在允许期间内 | 抛出 `BusinessException("输入的记账日期未打开")` | 明确的中文错误提示 |
| 数据库异常 | save 失败 | 事务回滚，`log.error(msg, e)` + 抛出 `BusinessException` | 系统错误提示 |

### 8.2 重试与降级

- 重试次数：0（本模块不做重试，由调用方决定）
- 降级策略：无（凭证创建为关键业务，失败即终止）

---

## 9. 局部配置

### 9.1 业务配置

| 配置项 | 配置 Key | 默认值 | 说明 |
|-------|---------|-------|------|
| 编号范围对象 | 常量 `NUM_RANGE_OBJECT_FI` | `"RF_BELEG"` | FI 凭证编号对象 |
| 默认汇率类型 | 常量 | `"M"` | 凭证类型未配置汇率类型时的默认值 |
| 参考类型 | 常量 | `"BKPF"` | 手工记账凭证的参考交易类型 |

### 9.2 开关配置

| 开关 | 用途 | 默认状态 |
|-----|------|---------|
| 无 | - | - |

---

> **质量红线检查清单**
> - [x] **现有代码锚点已标注**：需新建 2 个文件（BizService 接口 + BizServiceImpl），无需修改已有文件
> - [x] **现有约束已识别**：七层调用链路、事务边界、异常处理、查询构建、依赖注入、实体字段命名差异
> - [x] **字段完整性**：字段追溯表已完成，16 个输入字段中 15 个保留、1 个明确移除（BVORG）
> - [x] **边界遵守**：无越权设计其他 Capability 的逻辑
> - [x] **全局遵守**：遵循 overview.md 的数据字典和接口规范
> - [x] 前端设计已完成：纯后端，无前端组件
> - [x] 后端接口已完成：create 方法四步流程 + 4 个关键算法伪代码
> - [x] 数据模型已完成：account_document_head 表 16 个字段 + 唯一索引
> - [x] **外部依赖已明确**：Redis、DocumentNumberUtil、8 个内部跨模块依赖
> - [x] **环境权限已确认**：数据库 INSERT 权限、Redis 连接、DocumentNumberUtil 初始化
> - [x] 异常处理策略已定义：8 类异常 + 处理策略
> - [x] 包含足够的局部细节支持任务拆解
