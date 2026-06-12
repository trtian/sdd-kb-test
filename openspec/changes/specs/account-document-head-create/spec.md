# spec.md - 能力规格定义

> **定位**：凭证头创建（account-document-head-create）的技术规格定义
>
> **【质量红线】严禁描述模糊；约束必须量化；缺失必要参数时 opsx-check 必须报错拦截
>
>> **【格式要求】** 需求项使用 `####`（4个#），场景必须使用 `#####`（5个#）

---

## 1. 需求规格（官方格式）

### 新增需求

#### 需求项：填充前必填字段校验
系统必须在执行字段填充前，校验凭证头的必填字段均非空，任一缺失则抛出 `BusinessException` 并终止流程。

##### 场景：所有必填字段均已提供
- **当** `documentDate`、`postingDate`、`docType`、`companyCode`、`currencyKey` 均非空
- **预期** 校验通过，继续执行后续步骤

##### 场景：凭证日期为空
- **当** `documentDate` 为 `null`
- **预期** 抛出 `BusinessException("凭证日期不能为空")`，流程终止

##### 场景：过账日期为空
- **当** `postingDate` 为 `null`
- **预期** 抛出 `BusinessException("过账日期不能为空")`，流程终止

##### 场景：凭证类型为空
- **当** `docType` 为 `null` 或空字符串
- **预期** 抛出 `BusinessException("凭证类型不能为空")`，流程终止

##### 场景：公司代码为空
- **当** `companyCode` 为 `null` 或空字符串
- **预期** 抛出 `BusinessException("公司代码不能为空")`，流程终止

##### 场景：货币为空
- **当** `currencyKey` 为 `null` 或空字符串
- **预期** 抛出 `BusinessException("货币不能为空")`，流程终止

---

#### 需求项：填充前外键存在性校验
系统必须在填充前校验 `companyCode`、`docType`、`currencyKey` 在对应主数据表中存在，任一不存在则抛出 `BusinessException`。

##### 场景：公司代码存在
- **当** 查询 `CompanyCode` 表，`companyCode = head.companyCode` 返回非空记录
- **预期** 校验通过

##### 场景：公司代码不存在
- **当** 查询 `CompanyCode` 表，`companyCode = head.companyCode` 返回 `null`
- **预期** 抛出 `BusinessException("公司代码不存在: {companyCode}")`

##### 场景：凭证类型存在
- **当** 查询 `DocumentType` 表，`docType = head.docType` 返回非空记录
- **预期** 校验通过

##### 场景：凭证类型不存在
- **当** 查询 `DocumentType` 表，`docType = head.docType` 返回 `null`
- **预期** 抛出 `BusinessException("凭证类型不存在: {docType}")`

##### 场景：货币存在
- **当** 查询 `Currency` 表，`currencyKey = head.currencyKey` 返回非空记录
- **预期** 校验通过

##### 场景：货币不存在
- **当** 查询 `Currency` 表，`currencyKey = head.currencyKey` 返回 `null`
- **预期** 抛出 `BusinessException("货币不存在: {currencyKey}")`

---

#### 需求项：凭证类型联动校验（抬头文本与参照必输）
系统必须根据 `DocumentType` 配置的 `isDocHdrText` 和 `isRefNum` 标记，校验 `documentHeaderText` 和 `referenceDocumentNumber` 是否必填。

##### 场景：凭证类型要求抬头文本必填且已提供
- **当** `DocumentType.isDocHdrText = "X"` 且 `documentHeaderText` 非空
- **预期** 校验通过

##### 场景：凭证类型要求抬头文本必填但未提供
- **当** `DocumentType.isDocHdrText = "X"` 且 `documentHeaderText` 为空
- **预期** 抛出 `BusinessException("当前凭证类型要求凭证抬头文本为必填")`

##### 场景：凭证类型不要求抬头文本必填
- **当** `DocumentType.isDocHdrText != "X"`
- **预期** 不校验 `documentHeaderText`，无论其是否为空均通过

##### 场景：凭证类型要求参照必填且已提供
- **当** `DocumentType.isRefNum = "X"` 且 `referenceDocumentNumber` 非空
- **预期** 校验通过

##### 场景：凭证类型要求参照必填但未提供
- **当** `DocumentType.isRefNum = "X"` 且 `referenceDocumentNumber` 为空
- **预期** 抛出 `BusinessException("当前凭证类型要求参照为必填")`

##### 场景：凭证类型不要求参照必填
- **当** `DocumentType.isRefNum != "X"`
- **预期** 不校验 `referenceDocumentNumber`，无论其是否为空均通过

---

#### 需求项：过账年度和期间自动填充
系统必须根据 `postingDate` 和公司代码的会计年度变式，自动计算并填充 `fiscalYear` 和 `fiscalPeriod`。

##### 场景：公历年确定期间
- **当** `postingDate = 2026-04-28`，公司代码的 `FiscalYearVariant.calYearPeriod = "X"`
- **预期** `fiscalYear = "2026"`，`fiscalPeriod = "04"`

##### 场景：非公历年场景（默认月份）
- **当** `postingDate = 2026-04-28`，公司代码的 `FiscalYearVariant.calYearPeriod != "X"` 或 `FiscalYearVariant` 不存在
- **预期** `fiscalYear = "2026"`，`fiscalPeriod = "04"`（默认按公历月份处理）

##### 场景：跨年日期
- **当** `postingDate = 2026-01-15`
- **预期** `fiscalYear = "2026"`，`fiscalPeriod = "01"`

---

#### 需求项：凭证编号自动生成
系统必须通过公共组件 `DocumentNumberUtil.getDocumentNumberStr(NumberParams)` 生成凭证编号，参数从凭证头和凭证类型配置中获取。

##### 场景：正常生成凭证编号
- **当** `DocumentType.numberRange` 有值，`fiscalYear` 已计算，`companyCode` 已提供
- **预期** 调用 `DocumentNumberUtil.getDocumentNumberStr(params)` 返回非空编号字符串，赋值给 `documentNumber`

##### 场景：凭证类型未配置号段
- **当** `DocumentType.numberRange` 为 `null` 或空
- **预期** `DocumentNumberUtil` 内部处理或抛出异常，由调用方捕获并包装为 `BusinessException`

##### 场景：编号生成参数构建
- **当** 构建 `NumberParams`
- **预期** `client = head.client`，`numRangeObject = "RF_BELEG"`（常量），`numRangeSubject = head.companyCode`，`code = DocumentType.numberRange`，`toFiscalYear = head.fiscalYear`，`outerNumber = null`

---

#### 需求项：换算日期默认值填充
系统必须在 `translationDate` 为空时，默认取 `postingDate` 的值。

##### 场景：换算日期为空
- **当** `translationDate` 为 `null`
- **预期** `translationDate` 被设置为 `postingDate` 的值

##### 场景：换算日期已提供
- **当** `translationDate` 非空
- **预期** 保持原值不变

---

#### 需求项：汇率自动计算
系统必须根据凭证货币与公司代码本位币的关系，自动计算并填充 `exchangeRate`。

##### 场景：凭证货币等于本位币
- **当** `currencyKey == CompanyCode.currencyKey`
- **预期** `exchangeRate = 1`（`BigDecimal.ONE`），不可更改

##### 场景：凭证货币不等于本位币，汇率存在
- **当** `currencyKey != CompanyCode.currencyKey`，查询 `ExchangeRate` 表：`exchangeRateType` 取自 `DocumentType.exchangeRateType`（为空默认 "M"），`fromCurrency = CompanyCode.currencyKey`，`toCurrency = head.currencyKey`，`exchangeRateValidFrom <= translationDate`，按 `exchangeRateValidFrom DESC LIMIT 1` 取最晚记录
- **预期** `exchangeRate` 被设置为查询到的 `directExchangeRate` 值

##### 场景：凭证货币不等于本位币，汇率不存在
- **当** `currencyKey != CompanyCode.currencyKey`，查询 `ExchangeRate` 表无匹配记录
- **预期** 抛出 `BusinessException("未找到汇率: {localCurrency} -> {currencyKey}")`

##### 场景：凭证类型未配置汇率类型
- **当** `DocumentType.exchangeRateType` 为空
- **预期** 汇率类型默认使用 `"M"`

---

#### 需求项：参考类型和参考关键字自动填充
系统必须在手工记账场景下，自动填充 `referenceProcess = "BKPF"`，`referenceKey = documentNumber + companyCode + fiscalYear`。

##### 场景：手工记账凭证
- **当** 凭证通过 `create` 方法创建
- **预期** `referenceProcess = "BKPF"`，`referenceKey = "{documentNumber}{companyCode}{fiscalYear}"`

---

#### 需求项：填充后凭证编号非空校验
系统必须在字段填充完成后，校验 `documentNumber` 非空。

##### 场景：凭证编号已生成
- **当** `documentNumber` 非空
- **预期** 校验通过

##### 场景：凭证编号生成失败
- **当** `documentNumber` 为 `null` 或空字符串
- **预期** 抛出 `BusinessException("凭证编号生成失败")`

---

#### 需求项：填充后凭证编号唯一性校验（DB 兜底）
系统必须在保存前，查询数据库确认 `documentNumber + companyCode + fiscalYear` 组合未被占用。

##### 场景：凭证编号未被占用
- **当** 查询 `AccountDocumentHead` 表，`documentNumber = head.documentNumber AND companyCode = head.companyCode AND fiscalYear = head.fiscalYear`，`count = 0`
- **预期** 校验通过

##### 场景：凭证编号已被占用
- **当** 查询 `AccountDocumentHead` 表，`documentNumber = head.documentNumber AND companyCode = head.companyCode AND fiscalYear = head.fiscalYear`，`count > 0`
- **预期** 抛出 `BusinessException("凭证编号已存在: {documentNumber}")`

---

#### 需求项：填充后过账日期账期校验
系统必须在保存前，校验 `postingDate` 是否在公司代码的允许记账期间范围内。

##### 场景：过账日期在允许期间内
- **当** `postingDate = 2026-04-28`，`AllowedPostingPeriod` 表中存在记录满足 `(fromFiscalYear1, fromPeriod1) <= (2026, 04) <= (toFiscalYear1, toPeriod1)` 或第二组、第三组范围满足
- **预期** 校验通过

##### 场景：过账日期不在任何允许期间内
- **当** `postingDate = 2026-04-28`，三组期间范围均不包含该日期
- **预期** 抛出 `BusinessException("输入的记账日期未打开")`

##### 场景：公司代码未配置允许记账期间
- **当** `AllowedPostingPeriod` 表中无匹配记录
- **预期** 跳过校验（不阻塞流程）

##### 场景：期间范围边界值
- **当** `postingDate` 恰好等于 `fromFiscalYear + fromPeriod` 或 `toFiscalYear + toPeriod` 的边界
- **预期** 边界值包含在范围内，校验通过

---

#### 需求项：凭证头持久化
系统必须在所有校验通过后，将凭证头保存到数据库。

##### 场景：正常保存
- **当** 所有校验通过，调用 `this.save(head)`
- **预期** 凭证头记录写入 `AccountDocumentHead` 对应表，返回已持久化的 `AccountDocumentHead` 对象（含自增 ID）

##### 场景：保存时数据库异常
- **当** `this.save(head)` 抛出数据库异常
- **预期** 事务回滚，异常向上传播为 `BusinessException`，日志记录完整堆栈

---

#### 需求项：create 方法事务边界
系统必须确保 `create` 方法的整个执行过程在同一个数据库事务中。

##### 场景：事务正常提交
- **当** 所有步骤执行成功
- **预期** 事务提交，凭证头数据持久化

##### 场景：任一步骤失败则事务回滚
- **当** 填充前校验、字段填充、填充后校验、持久化任一步骤抛出异常
- **预期** 事务回滚，数据库中不产生脏数据

---

## 2. 技术契约（SDD 扩展）

### 2.1 接口定义

#### 接口基本信息
- **类名**：`AccountDocumentHeadBizServiceImpl`
- **父类**：`ServiceImpl<AccountDocumentHeadMapper, AccountDocumentHead>`
- **实现接口**：`AccountDocumentHeadBizService`, `AccountDocumentHeadService`
- **注解**：`@Service`、`@Primary`、`@Slf4j`

#### 核心方法签名

```java
@Override
@Transactional(rollbackFor = Exception.class)
public AccountDocumentHead create(AccountDocumentHead head);
```

#### 依赖注入清单

| 依赖 | 类型 | 用途 |
|------|------|------|
| `accountDocumentHeadService` | `AccountDocumentHeadService` | 基础 CRUD |
| `companyCodeService` | `CompanyCodeService` | 公司代码查询 |
| `documentTypeService` | `DocumentTypeService` | 凭证类型查询 |
| `allowedPostingPeriodService` | `AllowedPostingPeriodService` | 允许记账期间查询 |
| `fiscalYearVariantService` | `FiscalYearVariantService` | 会计年度变式查询 |
| `exchangeRateService` | `ExchangeRateService` | 汇率查询 |
| `currencyService` | `CurrencyService` | 货币查询 |
| `controllingAreaAssignmentService` | `ControllingAreaAssignmentService` | 成本控制范围查询 |
| `convertor` | `EntityOrRefObj2Dto4SimplePropConvertor` | DTO 转换 |

#### 错误码定义

| 错误码 | 含义 | 触发条件 |
|-------|------|----------|
| - | 凭证日期不能为空 | `documentDate == null` |
| - | 过账日期不能为空 | `postingDate == null` |
| - | 凭证类型不能为空 | `docType` 为空 |
| - | 公司代码不能为空 | `companyCode` 为空 |
| - | 货币不能为空 | `currencyKey` 为空 |
| - | 公司代码不存在: {code} | CompanyCode 表无匹配 |
| - | 凭证类型不存在: {type} | DocumentType 表无匹配 |
| - | 货币不存在: {currency} | Currency 表无匹配 |
| - | 当前凭证类型要求凭证抬头文本为必填 | `isDocHdrText = "X"` 且 `documentHeaderText` 为空 |
| - | 当前凭证类型要求参照为必填 | `isRefNum = "X"` 且 `referenceDocumentNumber` 为空 |
| - | 凭证编号生成失败 | `documentNumber` 为空 |
| - | 凭证编号已存在: {number} | DB 唯一性校验失败 |
| - | 未找到汇率: {from} -> {to} | ExchangeRate 表无匹配 |
| - | 输入的记账日期未打开 | 过账日期不在允许期间内 |

---

## 3. 物理约束

### 3.1 性能约束

| 指标 | 约束值 | 说明 |
|------|-------|------|
| 响应时间 | < 500 毫秒 (P99) | 单次 create 调用，含编号生成 + 多表查询 + 持久化 |
| 吞吐量 | > 50 QPS | 单实例 |
| 并发数 | 最大 100 | 依赖 DocumentNumberUtil 分布式流保证编号唯一 |

### 3.2 资源约束

| 资源 | 限制 | 说明 |
|------|------|------|
| 内存 | < 256 MB | 单次调用内存占用 |
| 数据库连接 | 每次调用 ≤ 8 次查询 | 含 CompanyCode、DocumentType、Currency、FiscalYearVariant、ExchangeRate、AllowedPostingPeriod、唯一性检查、保存 |

### 3.3 超时配置

- 数据库查询超时：30 秒（MyBatis-Plus 默认）
- DocumentNumberUtil 调用超时：5 秒（Redis 操作）
- 总超时：60 秒

---

## 4. 影响模块

### 4.1 内部依赖

- [x] `klerp-fi-all/klerp-fi`：新建 `AccountDocumentHeadBizServiceImpl`、`AccountDocumentHeadBizService`
- [x] `klerp-data-all/klerp-fi-data`：已有 `AccountDocumentHead` 实体，只读
- [x] `klerp-data-all/klerp-org-data`：已有 `CompanyCode`、`ControllingAreaAssignment` 实体，只读
- [x] `klerp-data-all/klerp-common-data`：已有 `DocumentType`、`AllowedPostingPeriod`、`FiscalYearVariant`、`ExchangeRate`、`Currency` 实体，只读

### 4.2 外部依赖

| 组件类型 | 组件名称 | 版本 | 用途 | 降级策略 |
|---------|---------|------|------|---------|
| 框架 | Spring Boot | 3.2.5 | 应用框架 | - |
| 框架 | MyBatis-Plus | 3.5.5 | ORM | - |
| 数据库 | MySQL | 8.3.0 | 持久化存储 | - |
| 缓存 | Redis（Redisson） | - | 凭证编号分布式流 | 无降级，编号生成强依赖 |
| 公共组件 | common-dev（DocumentNumberUtil） | dev-SNAPSHOT | 凭证编号生成 | 无降级，编号生成强依赖 |
| 工具库 | Hutool | 5.8.25 | 日期/字符串工具 | - |
| 工具库 | Lombok | 1.18.22 | 代码简化 | - |

### 4.3 数据存储

- [x] 数据库（MySQL 8.3.0）：`account_document_head` 表（BKPF 对应），INSERT 操作
- [x] 缓存（Redis）：`DocumentNumberUtil` 内部使用，Key 模式由组件管理

---

## 5. 安全与合规

### 5.1 权限要求

- 认证方式：由框架层统一处理，本模块不单独实现
- 授权范围：凭证创建权限由上层 Controller/Provider 控制

### 5.2 数据安全

- 敏感字段：无（凭证头字段均为业务数据，不涉及密码/密钥）
- 加密要求：不适用

### 5.3 审计要求

- 日志记录：异常时必须 `log.error(msg, e)` 记录完整堆栈
- 操作追踪：凭证创建后自动记录 `createTime`、`createBy`（由 BaseEntity 自动填充）

---

## 6. 兼容性

### 6.1 接口兼容性

- 是否向后兼容：是（新建类，不影响已有代码）
- 版本控制策略：不适用

### 6.2 数据兼容性

- 数据迁移方案：不适用（无表结构变更）
- 回滚策略：事务自动回滚，无需额外处理

---

> **质量红线检查清单**
> - [x] 每个需求项至少有一个场景（共 14 个需求项，42 个场景）
> - [x] 使用「必须」强制要求，而非「应该」「可以」
> - [x] 所有接口参数已量化（类型、必填、范围、示例）
> - [x] 物理约束已量化（并发、超时、性能指标）
> - [x] 错误码已定义（12 个错误场景）
> - [x] **技术选型已包含版本信息**（Spring Boot 3.2.5、MyBatis-Plus 3.5.5、MySQL 8.3.0、Hutool 5.8.25、Lombok 1.18.22）
> - [x] 若跳过 proposal.md，影响范围已在此补齐（不适用，已有 proposal.md）

##### 场景：本地循环迭代验证（kb-loop-iteration-marker）
- **当** 运行 ci/local-sdd-loop.sh
- **预期** 本场景被 ingest 并可检索

##### 场景：增量AGE验证-20260612235554（kb-incr-20260612235554）
- **当** 运行 ci/local-sdd-incremental.sh
- **预期** ingest 增量写入 AGE 且可检索

##### 场景：增量AGE验证-20260613000925（kb-incr-20260613000925）
- **当** 运行 ci/local-sdd-incremental.sh
- **预期** ingest 增量写入 AGE 且可检索

##### 场景：增量AGE验证-20260613003923（kb-incr-20260613003923）
- **当** 运行 ci/local-sdd-incremental.sh
- **预期** ingest 增量写入 AGE 且可检索
