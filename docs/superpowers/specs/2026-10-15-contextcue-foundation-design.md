# ContextCue 公共架构与 AI 模块基础设计

## 1. 文档目的

本文档定义 ContextCue 第一阶段的公共领域模型、模块边界、依赖方向和三人协作接口。设计目标是在不提前实现完整 UI、时间调度或地理围栏的前提下，让三个功能分支能够独立开发并通过稳定契约集成。

本设计以当前 `feature-ai` 分支上的 Empty Ability 工程为基线。工程兼容 HarmonyOS 6.1.1（API 24），运行目标为 phone，当前入口为 `EntryAbility`，页面只有 `pages/Index`。

## 2. 第一阶段范围

第一阶段包含：

- 手动创建时间、地点、时间加地点提醒。
- 使用自然语言解析提醒内容、时间、地点和触发类型。
- 对 AI 结果进行结构、语义和必填字段校验。
- 统一保存、查询、更新、完成、启停和删除 Reminder。
- 通过时间和地点模块报告触发条件，并由统一入口决定是否发送系统通知。

第一阶段明确不包含：

- 预测用户未来可能遗忘的事项。
- AI 自动替用户修正不确定信息并直接创建提醒。
- 在 AI 模块中实现页面、时间调度、地理围栏或通知能力。
- 在当前阶段拆分独立 HAR/HAP 业务模块。

## 3. 架构决策

采用“公共领域层 + 功能模块”的单 entry 模块结构。

- 公共领域层维护唯一的 Reminder 数据格式、创建输入、仓储契约和业务入口。
- AI、页面、时间和定位代码分别位于独立目录。
- 页面只调用服务，不直接访问仓储。
- AI 只输出经过校验的创建输入，不直接保存 Reminder。
- 时间与地点模块只管理各自的系统能力和条件事件，不分别决定联合提醒的最终通知。
- HarmonyOS 具体系统 API 必须在实现阶段以 API 24 工程中的实际 SDK 声明为准；未经核对的 API 不进入设计契约。

依赖方向如下：

```text
pages ───────────────→ AIService / ReminderService
ai ──────────────────→ model
ReminderService ─────→ ReminderRepository
ReminderService ─────→ TimeTriggerPort / LocationTriggerPort
time / location ─────→ TriggerEventSink
TriggerCoordinator ──→ ReminderNotificationPort
```

公共 `model` 和接口层不得依赖 ArkUI 页面或具体 HarmonyOS 系统能力。

## 4. 建议目录

```text
entry/src/main/ets/
├─ model/
│  ├─ Reminder.ets
│  ├─ ReminderEnums.ets
│  ├─ CreateReminderInput.ets
│  └─ OperationResult.ets
├─ repository/
│  └─ ReminderRepository.ets
├─ service/
│  └─ ReminderService.ets
├─ ai/
│  ├─ contract/AIService.ets
│  ├─ model/AIParseResult.ets
│  ├─ provider/AIModelProvider.ets
│  ├─ parser/AIResponseParser.ets
│  ├─ validator/AIParseValidator.ets
│  └─ mapper/ReminderMapper.ets
├─ reminder/
│  ├─ contract/
│  │  ├─ TimeTriggerPort.ets
│  │  ├─ LocationTriggerPort.ets
│  │  ├─ SceneResolver.ets
│  │  ├─ TriggerEventSink.ets
│  │  └─ ReminderNotificationPort.ets
│  ├─ TriggerCoordinator.ets
│  ├─ time/
│  └─ notification/
├─ location/
│  ├─ model/
│  ├─ service/
│  └─ adapter/
├─ pages/
├─ entryability/
└─ entrybackupability/
```

单元测试目录按相同模块名称组织，例如 `src/test/ai`、`src/test/service` 和 `src/test/repository`。

## 5. 统一 Reminder 模型

### 5.1 枚举

```ts
export enum TriggerType {
  TIME = 'TIME',
  LOCATION = 'LOCATION',
  BOTH = 'BOTH'
}

export enum ReminderSource {
  MANUAL = 'MANUAL',
  AI = 'AI'
}
```

### 5.2 持久化实体

```ts
export interface Reminder {
  id: string
  content: string
  triggerType: TriggerType
  triggerTime?: number
  sceneId?: string
  sceneName?: string
  enabled: boolean
  completed: boolean
  source: ReminderSource
  createdAt: number
}
```

`triggerTime` 和 `createdAt` 使用 Unix Epoch 毫秒值。相对时间解析必须显式使用解析上下文中的当前时间与时区，避免字符串格式和设备时区产生隐式差异。

`sceneId` 是定位模块的稳定引用；`sceneName` 是用于展示和 AI 匹配的名称快照。经纬度、半径和围栏参数不进入 Reminder，由定位模块持有。

### 5.3 创建输入

```ts
export interface CreateReminderInput {
  content: string
  triggerType: TriggerType
  triggerTime?: number
  sceneId?: string
  sceneName?: string
  source: ReminderSource
}
```

手动 UI 和 AI 都提交同一个 `CreateReminderInput`。`id`、`createdAt`、`enabled` 和 `completed` 由 `ReminderService` 统一生成，避免不同入口产生不同默认值。

### 5.4 数据不变量

- `content` 去除首尾空白后不能为空。
- `TIME` 必须包含有效的 `triggerTime`。
- `LOCATION` 在激活前必须包含可用的 `sceneId`。
- `BOTH` 在激活前必须同时包含 `triggerTime` 和可用的 `sceneId`。
- 只有 `sceneName` 而没有可解析 `sceneId` 的 AI 结果必须进入用户确认流程。
- 已完成提醒必须处于禁用状态，即 `completed === true` 时 `enabled === false`。
- 无法确认的过去时间不自动改写为未来时间。
- 任何未通过校验的输入都不得写入 ReminderRepository。

## 6. AI 模块

### 6.1 服务契约

```ts
export interface AIParseContext {
  now: number
  timeZone: string
  locale: string
}

export interface AIService {
  parseReminder(text: string, context: AIParseContext): Promise<AIParseOutcome>
}
```

页面负责传入用户文本和解析上下文。AIService 负责调用供应商抽象、解析严格 JSON、校验字段并映射为公共创建输入。

### 6.2 解析结果

```ts
export enum AIParseStatus {
  READY = 'READY',
  NEEDS_CONFIRMATION = 'NEEDS_CONFIRMATION',
  FAILED = 'FAILED'
}

export interface AIParseOutcome {
  status: AIParseStatus
  draft?: CreateReminderInput
  issues: AIParseIssue[]
}

export interface AIParseIssue {
  code: AIParseIssueCode
  field?: string
  message: string
  retryable: boolean
}
```

- `READY`：字段完整且语义明确，允许用户确认后交给 ReminderService。
- `NEEDS_CONFIRMATION`：内容可部分解析，但存在歧义、缺失或未解析地点。
- `FAILED`：网络、供应商调用或响应解析失败，不产生可保存提醒。

`AIParseIssueCode` 至少包括：`NETWORK_ERROR`、`PROVIDER_ERROR`、`INVALID_JSON`、`MISSING_FIELD`、`INVALID_TIME`、`UNRESOLVED_LOCATION` 和 `AMBIGUOUS_RESULT`。`retryable` 只表示同一输入是否值得重试，不表示允许绕过用户确认。

### 6.3 供应商解耦

`AIModelProvider` 是唯一接触具体模型请求和响应的接口。AIService 不引用供应商名称，页面不引用 AIModelProvider。开发初期使用 Fake/Mock Provider 验证流程，真实 Provider 在公共模型稳定后单独接入。

任何固定 API Key、Secret 或 Token 都不得进入 ArkTS 源码、资源文件或 Git。生产接入优先使用服务端代理或短期凭证；本地开发配置也必须在忽略列表中，并通过 Provider 的配置入口注入。

## 7. Reminder 服务与仓储

### 7.1 Repository

ReminderRepository 提供异步 CRUD 契约，隐藏具体持久化技术：

```ts
export interface ReminderRepository {
  save(reminder: Reminder): Promise<void>
  findById(id: string): Promise<Reminder | undefined>
  findAll(): Promise<Reminder[]>
  deleteById(id: string): Promise<boolean>
}
```

仓储只负责数据读写，不负责 AI 解析、调度、围栏或通知。

### 7.2 ReminderService

ReminderService 是创建和修改 Reminder 的唯一公共入口，职责包括：

- 校验 CreateReminderInput。
- 生成 ID、创建时间和生命周期默认值。
- 保存 Reminder。
- 根据变化同步时间与地点触发端口。
- 完成、启停和删除提醒。
- 在仓储或触发端口失败时返回明确错误，不静默吞掉异常。

页面、AI、时间和定位模块都不得绕过 ReminderService 直接修改 Reminder 状态。

公共操作统一使用以下结果形状，避免页面依赖异常文本：

```ts
export interface OperationError {
  code: string
  message: string
  field?: string
  retryable: boolean
}

export interface OperationResult<T> {
  success: boolean
  data?: T
  error?: OperationError
}
```

## 8. 时间、地点与联合触发

时间和定位实现分别通过公共端口接入。最小契约如下，具体 HarmonyOS 对象不得泄漏到这些接口中：

```ts
export enum TriggerCondition {
  TIME = 'TIME',
  LOCATION = 'LOCATION'
}

export interface TriggerConditionEvent {
  reminderId: string
  condition: TriggerCondition
  satisfied: boolean
  occurredAt: number
}

export interface TimeTriggerPort {
  schedule(reminder: Reminder): Promise<void>
  cancel(reminderId: string): Promise<void>
}

export interface LocationTriggerPort {
  register(reminder: Reminder): Promise<void>
  unregister(reminderId: string): Promise<void>
  isInsideScene(sceneId: string): Promise<boolean>
}

export enum SceneResolveStatus {
  RESOLVED = 'RESOLVED',
  AMBIGUOUS = 'AMBIGUOUS',
  NOT_FOUND = 'NOT_FOUND'
}

export interface SceneCandidate {
  id: string
  name: string
}

export interface SceneResolveResult {
  status: SceneResolveStatus
  match?: SceneCandidate
  candidates: SceneCandidate[]
}

export interface SceneResolver {
  resolveByName(sceneName: string): Promise<SceneResolveResult>
}

export interface TriggerEventSink {
  onConditionChanged(event: TriggerConditionEvent): Promise<void>
}

export interface ReminderNotificationPort {
  notify(reminder: Reminder): Promise<void>
}
```

`SceneResolveResult` 区分唯一匹配、多个候选和未找到三种结果；只有 `RESOLVED` 能够自动补充 `sceneId`，其余结果进入用户确认流程。地点事件必须同时上报进入和离开状态，协调器不得把一次历史进入事件永久视为地点条件满足；在时间条件到达时可通过 `isInsideScene` 重新确认当前状态。

`BOTH` 固定为 AND 语义，并使用以下规则：

- 时间条件在 `triggerTime` 到达后打开，并保持为已满足。
- 地点条件表示用户当前处于目标场景，或在时间条件打开后进入目标场景。
- 如果用户在 `triggerTime` 到达时已经位于目标场景，协调器可立即触发。
- 如果时间到达时用户不在目标场景，则等待之后进入目标场景再触发。
- 位置在时间到达前曾经满足、但到达时已经离开，不视为联合条件满足。
- 每个 Reminder 最多发送一次最终通知，成功触发后由统一服务更新完成或禁用状态。

因此时间模块和定位模块不能各自直接发送 `BOTH` 通知。二者只上报条件事件，最终决定由统一 TriggerCoordinator 完成。

## 9. 错误处理

错误按边界分类：

- AI 基础设施错误：允许重试，不创建 Reminder。
- AI 内容错误：返回用户确认状态，并标明问题字段。
- Reminder 输入错误：由 ReminderService 拒绝并返回字段级错误。
- Repository 错误：保留原状态，不报告创建成功。
- 时间或位置注册错误：Reminder 不得表现为已成功启用；服务返回可恢复错误。
- 通知错误：不把 Reminder 标记为已完成或已禁用；返回可重试错误并记录脱敏日志。自动重试频率不属于本次公共基础实现。

日志不得输出凭证、完整供应商请求头或其他敏感配置。

## 10. 团队所有权

| 路径或文件 | 主要所有者 | 协作规则 |
|---|---|---|
| `model/**`、`repository/**`、`service/**` | 贾宇璠 | 公共契约，变更前同步并由组长合并 |
| `ai/**` | 贾宇璠 | 不包含 UI、时间或定位实现 |
| `pages/**`、`reminder/time/**` | 罗鸿程 | 通过公共服务和端口接入 |
| `location/**` | 兰铮 | 不直接修改 ReminderRepository |
| `reminder/contract/**`、`reminder/TriggerCoordinator.ets` | 公共，贾宇璠审核 | 接口变更需通知三人 |
| `EntryAbility.ets` | 集成入口 | 仅在整合阶段集中修改 |
| `module.json5`、根与 entry 的构建配置 | 公共配置 | 权限或依赖按独立 PR 修改 |
| `main_pages.json` | UI 主导、集成审核 | 避免多人同时编辑 |
| `oh-package-lock.json5` | 公共生成文件 | 仅随明确依赖变更提交 |

资源名称使用功能前缀，例如 `ai_`、`location_`、`reminder_`，降低公共资源文件中的命名冲突。

## 11. Git 与本地文件

- `main` 保持稳定，功能开发进入各自 feature 分支，再合并到 `develop`。
- 不重写共享分支历史，不替其他成员修改其 feature 分支。
- `.hvigor/`、`local.properties`、构建产物和包含本地凭证的配置不得提交。
- 当前根 `.gitignore` 尚未覆盖 `.hvigor/` 和 `local.properties`，应在公共基础阶段作为独立的小修改补齐。

## 12. 验证策略

每个实现阶段完成后执行：

1. 对新增纯逻辑模块运行本地单元测试。
2. 对模型不变量、AI 解析错误和 Service 结果建立成功与失败用例。
3. 使用当前 DevEco SDK 执行 debug `assembleHap`。
4. 检查 Git 状态，确保无密钥、本地配置或生成文件进入提交。

当前基线已通过 ArkTS 编译和 `assembleHap`，可生成 `entry-default-unsigned.hap`。因未配置签名，产物为未签名 HAP。

## 13. 小步实施顺序

1. 建立公共 Reminder、创建输入、结果类型和数据校验。
2. 建立 ReminderRepository 与 ReminderService 契约，并使用内存实现验证业务流程。
3. 建立 AIService、Fake Provider、解析、校验和映射流程，不调用真实 API。
4. 建立时间、地点、触发事件和通知端口，供另外两位成员并行实现。
5. 在 Fake Provider 和公共接口稳定后，再设计真实 AI Provider 和安全配置。
6. 最后在 `develop` 上完成 UI、AI、时间、定位和通知的集成验证。
