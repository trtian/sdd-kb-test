# 实施任务拆解 - 凭证头创建

> **定位**：单一 Capability 的 AI 编码引擎执行单元
>
> **⚠️ 边界声明**：本任务清单仅服务于当前 Capability（account-document-head-create），严禁跨模块任务。
>
> **【质量红线】颗粒度必须达到"AI能在5分钟内实现"；且拆解的任务和验证逻辑必须 100% 覆盖 spec 和 design

---

## 1. 任务总览

### 1.1 关联文档

| 文档 | 路径 | 说明 |
|-----|------|------|
| 全局契约 | `openspec/specs/overview.md` | 全局约束基线 |
| 业务意图 | `proposal.md` | 变更背景 |
| 技术契约 | `specs/account-document-head-create/spec.md` | 当前能力规格（14 需求项，42 场景） |
| 技术方案 | `specs/account-document-head-create/design.md` | 当前能力设计（4 个关键算法） |

### 1.2 实现范围

- 新建 `AccountDocumentHeadBizService` 接口（1 个方法：`create`）
- 新建 `AccountDocumentHeadBizServiceImpl` 实现类（含 preFillValidate / fillHeadFields / postFillValidate / save 四步流程）
- 覆盖 14 个需求项的全部 42 个场景

### 1.3 技术栈

- 语言：Java 17
- 框架：Spring Boot 3.2.5 + MyBatis-Plus 3.5.5
- 依赖：DocumentNumberUtil（dev-SNAPSHOT）、Hutool 5.8.25、Lombok 1.18.22

---

## 2. 任务执行拓扑图

> **⚠️ 依赖管理**：任务必须按层级执行，每层任务可并行，跨层必须等待前置完成

### 2.0 测试策略

**当前测试策略**：`测试驱动`

| 策略 | 说明 | 拓扑结构 |
|--------|------|------------|
| 测试驱动 | 测试先行 | 测试骨架 → 实现代码 → 测试验证 |

### 2.1 拓扑图

```
┌─────────────────────────────────────────────────────────────┐
│  层级 1：测试骨架（无依赖，可并行）                             │
│  ┌──────────────────┐  ┌──────────────────┐                  │
│  │ TASK-01-TEST     │  │ TASK-02-TEST     │                  │
│  │ BizService 接口   │  │ BizServiceImpl   │                  │
│  │ 测试骨架          │  │ 测试骨架          │                  │
│  └────────┬─────────┘  └────────┬─────────┘                  │
│           │                     │                             │
│           v                     v                             │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  层级 2：实现代码（依赖层级 1）                           │ │
│  │  ┌──────────────────┐  ┌──────────────────┐             │ │
│  │  │ TASK-03-IMPL     │  │ TASK-04-IMPL     │             │ │
│  │  │ BizService 接口   │  │ BizServiceImpl   │             │ │
│  │  │ 依赖: 01        │  │ 依赖: 02        │             │ │
│  │  └────────┬─────────┘  └────────┬─────────┘             │ │
│  │           │                     │                        │ │
│  │           v                     v                        │ │
│  │  ┌─────────────────────────────────────────────────────┐│ │
│  │  │  层级 3：测试验证（依赖层级 2）                      ││ │
│  │  │  ┌──────────────────┐                               ││ │
│  │  │  │ TASK-05-VERIFY   │                               ││ │
│  │  │  │ 运行全部测试      │                               ││ │
│  │  │  │ 依赖: 03, 04    │                               ││ │
│  │  │  └──────────────────┘                               ││ │
│  │  └─────────────────────────────────────────────────────┘│ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 层级汇总

| 层级 | 任务列表 | 可并行 | 前置依赖 |
|-----|---------|-------|--------|
| 层级 1 | TASK-01-TEST, TASK-02-TEST | ✅ 是 | 无 |
| 层级 2 | TASK-03-IMPL, TASK-04-IMPL | ✅ 是 | 层级 1 |
| 层级 3 | TASK-05-VERIFY | - | 层级 2 |

---

## 3. 原子任务清单

### [TASK-01-TEST] AccountDocumentHeadBizService 接口测试骨架

- **类型**: 测试-骨架
- **依赖**: 无
- **状态**: [x] 已完成

#### 任务描述
创建 `AccountDocumentHeadBizServiceTest` 测试类骨架，定义 `create` 方法的测试用例结构（Mock 依赖、准备测试数据），暂不实现断言逻辑。

#### 输入
- spec.md 第 1 章（14 个需求项）
- design.md 第 4.2 节（create 方法签名）

#### 输出
- `klerp-fi-all/klerp-fi/src/test/java/com/cnpc/erp/fi/account/bizservice/AccountDocumentHeadBizServiceTest.java`

#### 实现步骤
1. 创建测试类，添加 `@ExtendWith(MockitoExtension.class)` 和 `@Mock` 注解
2. Mock 8 个 Service 依赖（companyCodeService、documentTypeService、currencyService、fiscalYearVariantService、exchangeRateService、allowedPostingPeriodService、accountDocumentHeadService、controllingAreaAssignmentService）
3. 定义测试方法骨架（共 14 个测试方法，对应 14 个需求项）：
   - `testPreFillValidate_AllRequiredFieldsProvided`
   - `testPreFillValidate_MissingDocumentDate`
   - `testPreFillValidate_MissingPostingDate`
   - `testPreFillValidate_MissingDocType`
   - `testPreFillValidate_MissingCompanyCode`
   - `testPreFillValidate_MissingCurrencyKey`
   - `testPreFillValidate_CompanyCodeNotFound`
   - `testPreFillValidate_DocumentTypeNotFound`
   - `testPreFillValidate_CurrencyNotFound`
   - `testPreFillValidate_DocHdrTextRequired`
   - `testPreFillValidate_RefNumRequired`
   - `testFillHeadFields_FiscalYearAndPeriod`
   - `testFillHeadFields_DocumentNumber`
   - `testFillHeadFields_ExchangeRate_LocalCurrency`
   - `testFillHeadFields_ExchangeRate_ForeignCurrency`
   - `testFillHeadFields_ExchangeRate_NotFound`
   - `testFillHeadFields_TranslationDateDefault`
   - `testFillHeadFields_ReferenceProcessAndKey`
   - `testPostFillValidate_DocumentNumberEmpty`
   - `testPostFillValidate_DocumentNumberDuplicate`
   - `testPostFillValidate_PostingPeriodInRange`
   - `testPostFillValidate_PostingPeriodOutOfRange`
   - `testPostFillValidate_PostingPeriodNoConfig`
   - `testCreate_Success`
   - `testCreate_TransactionRollback`
4. 每个测试方法添加 `@Test` 注解和 `@DisplayName` 中文描述
5. 准备 `createValidHead()` 辅助方法，构造合法的 `AccountDocumentHead` 对象

#### 验收标准
- [ ] 测试类编译通过（即使测试运行为红色）
- [ ] 25 个测试方法骨架已定义，覆盖 spec.md 全部 14 个需求项
- [ ] Mock 依赖声明完整（8 个 Service）
- [ ] 辅助方法 `createValidHead()` 可构造合法凭证头

#### 关联设计
- spec.md 章节：1. 需求规格（全部 14 个需求项）
- design.md 章节：4.2 接口详细设计

---

### [TASK-02-TEST] AccountDocumentHeadBizServiceImpl 单元测试骨架

- **类型**: 测试-骨架
- **依赖**: 无
- **状态**: [x] 已完成

#### 任务描述
创建 `AccountDocumentHeadBizServiceImplTest` 测试类骨架，针对 BizServiceImpl 内部的私有方法（preFillValidate、fillFiscalYearAndPeriod、generateDocumentNumber、fillExchangeRate、validatePostingPeriod）定义测试结构。

#### 输入
- design.md 第 6.2 节（4 个关键算法伪代码）
- design.md 第 6.1 节（核心流程）

#### 输出
- `klerp-fi-all/klerp-fi/src/test/java/com/cnpc/erp/fi/account/bizservice/impl/AccountDocumentHeadBizServiceImplTest.java`

#### 实现步骤
1. 创建测试类，使用 `@InjectMocks` 注入 `AccountDocumentHeadBizServiceImpl`
2. Mock 8 个 Service 依赖
3. 定义内部方法测试骨架：
   - `testFillFiscalYearAndPeriod_CalendarYear`
   - `testFillFiscalYearAndPeriod_NonCalendarYear`
   - `testGenerateDocumentNumber_Success`
   - `testGenerateDocumentNumber_NoNumberRange`
   - `testFillExchangeRate_LocalCurrency`
   - `testFillExchangeRate_ForeignCurrency`
   - `testFillExchangeRate_RateNotFound`
   - `testFillExchangeRate_DefaultRateType`
   - `testValidatePostingPeriod_InRange`
   - `testValidatePostingPeriod_OutOfRange`
   - `testValidatePostingPeriod_NoConfig`
   - `testValidatePostingPeriod_BoundaryValue`
4. 使用反射或 `@VisibleForTesting` 方式暴露私有方法供测试

#### 验收标准
- [ ] 测试类编译通过
- [ ] 12 个测试方法骨架覆盖 4 个关键算法的所有边界情况
- [ ] Mock 依赖完整

#### 关联设计
- spec.md 章节：需求项 4-11（字段填充与校验）
- design.md 章节：6.2 关键算法

---

### [TASK-03-IMPL] AccountDocumentHeadBizService 接口

- **类型**: 接口层
- **依赖**: TASK-01-TEST
- **状态**: [x] 已完成

#### 任务描述
创建 `AccountDocumentHeadBizService` 接口，定义 `create(AccountDocumentHead head)` 方法签名。

#### 输入
- design.md 第 2.2 节（需新建的文件）
- design.md 第 4.2 节（create 方法签名）

#### 输出
- `klerp-fi-all/klerp-fi/src/main/java/com/cnpc/erp/fi/account/bizservice/AccountDocumentHeadBizService.java`

#### 实现步骤
1. 创建接口文件，包路径 `com.cnpc.erp.fi.account.bizservice`
2. 定义方法签名：`AccountDocumentHead create(AccountDocumentHead head)`
3. 添加必要的 import（`AccountDocumentHead`）

#### 验收标准
- [ ] 接口编译通过
- [ ] 方法签名与 design.md 一致
- [ ] 包路径符合项目规范

#### 关联设计
- spec.md 章节：2.1 接口定义
- design.md 章节：2.2 需新建的文件、4.2 接口详细设计

---

### [TASK-04-IMPL] AccountDocumentHeadBizServiceImpl 实现

- **类型**: 接口层
- **依赖**: TASK-02-TEST, TASK-03-IMPL
- **状态**: [x] 已完成

#### 任务描述
创建 `AccountDocumentHeadBizServiceImpl` 类，实现凭证头创建的完整四步流程。这是本 Capability 的核心实现任务，包含类定义、依赖注入、create 入口方法、preFillValidate、fillHeadFields（含 4 个子算法）、postFillValidate、辅助查询方法。

#### 输入
- design.md 第 2.2 节（类定义和依赖注入清单）
- design.md 第 6.1 节（核心流程）
- design.md 第 6.2 节（4 个关键算法伪代码）
- design.md 第 2.3 节（实体字段命名差异约束）

#### 输出
- `klerp-fi-all/klerp-fi/src/main/java/com/cnpc/erp/fi/account/bizservice/impl/AccountDocumentHeadBizServiceImpl.java`

#### 实现步骤

**步骤 1：类定义与依赖注入**
1. 创建类，添加 `@Service`、`@Primary`、`@Slf4j` 注解
2. 继承 `ServiceImpl<AccountDocumentHeadMapper, AccountDocumentHead>`
3. 实现 `AccountDocumentHeadBizService`、`AccountDocumentHeadService`
4. 使用 `@Autowired` 注入 8 个 Service + `EntityOrRefObj2Dto4SimplePropConvertor`
5. 定义常量 `NUM_RANGE_OBJECT_FI = "RF_BELEG"`

**步骤 2：create 入口方法**
```java
@Override
@Transactional(rollbackFor = Exception.class)
public AccountDocumentHead create(AccountDocumentHead head) {
    preFillValidate(head);
    fillHeadFields(head);
    postFillValidate(head);
    this.save(head);
    return head;
}
```

**步骤 3：preFillValidate 方法**
- 3.1 必填字段非空校验（documentDate、postingDate、docType、companyCode、currencyKey）
- 3.2 外键存在性校验（CompanyCode、DocumentType、Currency）
- 3.3 凭证类型联动校验（isDocHdrText → documentHeaderText 必填，isRefNum → referenceDocumentNumber 必填）
- 注意：使用实际实体字段名（`CompanyCode.currency` 而非 `currencyKey`，`DocumentType.prpsdRateExchRateType` 而非 `exchangeRateType`）

**步骤 4：fillHeadFields 方法**
- 4.1 `fillFiscalYearAndPeriod(head)` — 先计算年度/期间（编号依赖 fiscalYear）
- 4.2 `head.setDocumentNumber(generateDocumentNumber(head))` — 生成凭证编号
- 4.3 `translationDate` 默认 = `postingDate`
- 4.4 `fillExchangeRate(head)` — 计算汇率
- 4.5 `head.setReferenceProcess("BKPF")`
- 4.6 `head.setReferenceKey(documentNumber + companyCode + fiscalYear)`

**步骤 5：postFillValidate 方法**
- 5.1 documentNumber 非空校验
- 5.2 凭证编号唯一性（DB 兜底，查 AccountDocumentHead 表）
- 5.3 `validatePostingPeriod(head)` — 账期校验

**步骤 6：辅助查询方法**
- `getCompanyCode(String)` — LambdaQueryWrapper 查询
- `getDocumentType(String)` — LambdaQueryWrapper 查询
- `getCurrency(String)` — LambdaQueryWrapper 查询
- `getFiscalYearVariant(String)` — LambdaQueryWrapper 查询

#### 验收标准
- [ ] 类编译通过，所有注解正确
- [ ] create 方法四步流程完整（preFillValidate → fillHeadFields → postFillValidate → save）
- [ ] 必填字段校验覆盖 5 个字段（documentDate、postingDate、docType、companyCode、currencyKey）
- [ ] 外键存在性校验覆盖 3 张表（CompanyCode、DocumentType、Currency）
- [ ] 凭证类型联动校验覆盖 2 个标记（isDocHdrText、isRefNum）
- [ ] 过账年度/期间计算正确（公历年场景）
- [ ] 凭证编号通过 DocumentNumberUtil 生成，参数构建正确
- [ ] 汇率计算覆盖本位币和外币两种场景
- [ ] 填充后校验覆盖编号非空、唯一性、账期三组范围
- [ ] 所有查询使用 LambdaQueryWrapper
- [ ] 所有异常抛出 BusinessException，日志记录完整堆栈
- [ ] 实体字段名使用实际名称（currency、postingPeriodVarnt、prpsdRateExchRateType）

#### 关联设计
- spec.md 章节：1. 需求规格（全部 14 个需求项）
- design.md 章节：2.2、4.2、6.1、6.2

---

### [TASK-05-VERIFY] 运行测试验证

- **类型**: 测试-验证
- **依赖**: TASK-03-IMPL, TASK-04-IMPL
- **状态**: [x] 已完成

#### 任务描述
完善 TASK-01-TEST 和 TASK-02-TEST 中的测试骨架，填充具体的 Mock 行为和断言逻辑，运行全部测试并确保通过。

#### 输入
- TASK-01-TEST 输出的测试骨架
- TASK-02-TEST 输出的测试骨架
- TASK-03-IMPL 输出的接口
- TASK-04-IMPL 输出的实现类

#### 输出
- 完善后的 `AccountDocumentHeadBizServiceTest.java`（含完整断言）
- 完善后的 `AccountDocumentHeadBizServiceImplTest.java`（含完整断言）

#### 实现步骤
1. 完善 TASK-01-TEST 的 25 个测试方法：
   - 为每个测试方法设置 Mock 行为（`when(...).thenReturn(...)`）
   - 添加具体断言（`assertThrows`、`assertEquals`、`assertNotNull`）
   - 异常场景验证异常消息内容
2. 完善 TASK-02-TEST 的 12 个测试方法：
   - 使用反射调用私有方法
   - 验证字段填充结果
   - 验证边界情况处理
3. 运行 `mvn test -pl klerp-fi-all/klerp-fi` 确保全部通过
4. 检查测试覆盖率（目标：行覆盖率 > 80%）

#### 验收标准
- [ ] 全部 37 个测试用例通过（25 + 12）
- [ ] 异常场景的异常消息与 spec.md 定义一致
- [ ] 边界值测试覆盖（空值、零值、边界值）
- [ ] 测试覆盖率 > 80%

#### 关联设计
- spec.md 章节：全部 14 个需求项 + 42 个场景
- design.md 章节：全部章节

---

## 4. 验证方式

### 4.1 单元测试要求

| 任务 ID | 测试类型 | 测试场景 | 断言内容 |
|--------|---------|---------|---------|
| TASK-01-TEST | 接口测试 | 25 个场景（覆盖 14 个需求项） | 返回值/异常类型/异常消息 |
| TASK-02-TEST | 内部方法测试 | 12 个场景（覆盖 4 个关键算法） | 字段值/异常消息 |
| TASK-05-VERIFY | 回归验证 | 全部 37 个用例 | 全部通过 |

### 4.2 集成测试场景

| 场景 | 前置条件 | 操作步骤 | 预期结果 |
|-----|---------|---------|---------|
| 完整创建流程 | 数据库有 CompanyCode/DocumentType/Currency/ExchangeRate 数据 | 调用 create 方法传入合法凭证头 | 凭证头持久化，返回含 ID 的对象 |
| 事务回滚 | 模拟 save 时数据库异常 | 调用 create 方法 | 事务回滚，数据库无脏数据 |

### 4.3 手动验证清单

- [ ] 启动 erp-business（8221），确认 DocumentNumberUtil 初始化成功
- [ ] 通过 Swagger/Knife4j 调用凭证创建接口，验证端到端流程
- [ ] 检查数据库 account_document_head 表，确认字段值正确

---

## 5. 外部依赖

| 依赖项 | 类型 | 提供方 | 状态 | 备注 |
|-------|------|-------|------|------|
| DocumentNumberUtil | 公共组件 | common-dev jar | ✅ 就绪 | 需启动时 init() |
| AccountDocumentHead 实体 | 数据层 | klerp-data-all | ✅ 就绪 | 147 个字段 |
| CompanyCode 实体/Service | 数据层 | klerp-data-all/klerp-org-data | ✅ 就绪 | 字段名 currency（非 currencyKey） |
| DocumentType 实体/Service | 数据层 | klerp-data-all/klerp-common-data | ✅ 就绪 | 字段名 prpsdRateExchRateType |
| ExchangeRate 实体/Service | 数据层 | klerp-data-all/klerp-common-data | ✅ 就绪 | |
| AllowedPostingPeriod 实体/Service | 数据层 | klerp-data-all/klerp-common-data | ✅ 就绪 | |
| FiscalYearVariant 实体/Service | 数据层 | klerp-data-all/klerp-common-data | ✅ 就绪 | |
| Currency 实体/Service | 数据层 | klerp-data-all/klerp-common-data | ✅ 就绪 | |

---

## 6. 代码规范

### 6.1 命名规范

- 类名：大驼峰（`AccountDocumentHeadBizServiceImpl`）
- 方法名：小驼峰，动词开头（`preFillValidate`、`fillHeadFields`）
- 变量名：小驼峰，名词（`companyCodeService`）
- 常量名：全大写下划线（`NUM_RANGE_OBJECT_FI`）

### 6.2 代码风格

- 缩进：4 空格
- 依赖注入：`@Autowired` 字段注入
- 查询构建：`LambdaQueryWrapper`
- 异常处理：`log.error(msg, e)` + `throw new BusinessException(msg, e)`

### 6.3 日志规范

- 日志级别：异常使用 `log.error`
- 日志格式：`log.error(e.getMessage(), e)`（保留完整堆栈）
- 敏感信息处理：不输出密码/密钥

---

## 7. 交付物

### 7.1 代码文件

| 文件路径 | 说明 | 对应任务 |
|---------|------|---------|
| `klerp-fi-all/klerp-fi/src/main/java/com/cnpc/erp/fi/account/bizservice/AccountDocumentHeadBizService.java` | 业务接口 | TASK-03-IMPL |
| `klerp-fi-all/klerp-fi/src/main/java/com/cnpc/erp/fi/account/bizservice/impl/AccountDocumentHeadBizServiceImpl.java` | 核心实现 | TASK-04-IMPL |

### 7.2 测试文件

| 文件路径 | 说明 | 对应任务 |
|---------|------|---------|
| `klerp-fi-all/klerp-fi/src/test/java/com/cnpc/erp/fi/account/bizservice/AccountDocumentHeadBizServiceTest.java` | 接口测试 | TASK-01-TEST, TASK-05-VERIFY |
| `klerp-fi-all/klerp-fi/src/test/java/com/cnpc/erp/fi/account/bizservice/impl/AccountDocumentHeadBizServiceImplTest.java` | 内部方法测试 | TASK-02-TEST, TASK-05-VERIFY |

### 7.3 文档更新

- [x] spec.md 已创建
- [x] design.md 已创建
- [x] tasks.md 已创建

---

> **质量红线检查清单**
> - [x] 每个任务颗粒度符合"5分钟可实现"标准（5 个任务，每个聚焦单一职责）
> - [x] 任务清单 100% 覆盖 spec.md 定义（14 个需求项 → 37 个测试用例）
> - [x] 任务清单 100% 覆盖 design.md 定义（4 个关键算法 → 12 个内部方法测试）
> - [x] 每个任务都有明确的验收标准（共 5 个任务，每个 4-12 条验收标准）
> - [x] 每个任务都有对应的单元测试要求（TASK-01/02 测试骨架，TASK-05 测试验证）
> - [x] **依赖拓扑已明确**（3 层拓扑：测试骨架 → 实现 → 验证）
> - [x] **任务执行拓扑图已绘制**（层级关系清晰，可并行标注）
> - [x] 无循环依赖
