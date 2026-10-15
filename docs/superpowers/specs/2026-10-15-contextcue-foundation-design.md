# ContextCue 公共架构与 AI 模块开发规范 v1.0

## 1. 文档目的

本文档定义 ContextCue 第一阶段的公共领域模型、模块边界、依赖方向和三人协作接口。设计目标是在不提前实现完整 UI、时间调度或地理围栏的前提下，让三个功能分支能够独立开发并通过稳定契约集成。

本设计以当前 `feature-ai` 分支上的 Empty Ability 工程为基线。工程兼容 HarmonyOS 6.1.1（API 24），运行目标为 phone，当前入口为 `EntryAbility`，页面只有 `pages/Index`。

## 2. 第一阶段范围

第一阶段包含：

- 手动创建时间、地点、时间加地点提醒。
- 使用自然语言解析提醒内容、时间、地点和触发类型。
- 对 AI 结果进行结构、语义和必填字段校验。
- 统一保存、查询、更新、启用、禁用、触发、完成和删除 Reminder。
- 通过时间和地点模块报告触发条件，并由统一入口决定是否发送系统通知。

第一阶段明确不包含：

- 预测用户未来可能遗忘的事项。
- AI 自动替用户修正不确定信息并直接创建提醒。
- 在 AI 模块中实现页面、时间调度、地理围栏或通知能力。
- 在当前阶段拆分独立 HAR/HAP 业务模块。
- 每日、每周、工作日或其他复杂重复规则。

第一阶段所有 Reminder 均为一次性提醒，一个 Reminder 最多成功触发一次。周期提醒需要在后续单独设计 `RepeatRule`。

## 3. 架构决策

采用“公共领域层 + 功能模块”的单 entry 模块结构。

- 公共领域层维护唯一的 Reminder 数据格式、创建输入、仓储契约和业务入口。
- AI、页面、时间和定位代码分别位于独立目录。
- 页面只调用服务，不直接访问仓储。
- AI 只输出经过校验的创建输入，不直接保存 Reminder。
- 时间与地点模块只管理各自的系统能力和条件事件，TIME、LOCATION 和 BOTH 的最终通知都由 TriggerCoordinator 决定。
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
│  ├─ Scene.ets
│  ├─ OperationResult.ets
│  └─ ReminderModelRules.ets
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
│  ├─ repository/
│  ├─ service/
│  └─ adapter/
├─ pages/
├─ components/
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

export enum ReminderStatus {
  ACTIVE = 'ACTIVE',
  TRIGGERED = 'TRIGGERED',
  COMPLETED = 'COMPLETED',
  DISABLED = 'DISABLED'
}

export enum LocationTriggerMode {
  ENTER = 'ENTER',
  EXIT = 'EXIT'
}
```

`TRIGGERED` 表示条件已满足且通知发送成功，`COMPLETED` 表示用户主动确认事项已经完成，两者不得合并。第一阶段地点提醒可以优先实现 `ENTER`，公共模型同时保留 `EXIT`。

### 5.2 持久化实体

```ts
export interface Reminder {
  id: string
  content: string
  triggerType: TriggerType
  triggerTime?: number
  sceneId?: string
  sceneName?: string
  locationTriggerMode?: LocationTriggerMode
  status: ReminderStatus
  source: ReminderSource
  createdAt: number
  triggeredAt?: number
  completedAt?: number
}
```

`triggerTime`、`createdAt`、`triggeredAt` 和 `completedAt` 使用 Unix Epoch 毫秒值。相对时间解析必须显式使用解析上下文中的当前时间与时区，避免字符串格式和设备时区产生隐式差异。

`sceneId` 是定位模块的稳定引用；`sceneName` 是用于展示和 AI 匹配的名称快照。经纬度、半径和围栏参数不进入 Reminder，由定位模块持有。

### 5.3 创建输入

```ts
export interface CreateReminderInput {
  content: string
  triggerType: TriggerType
  triggerTime?: number
  sceneId?: string
  sceneName?: string
  locationTriggerMode?: LocationTriggerMode
  source: ReminderSource
}
```

手动 UI 和 AI 都提交同一个 `CreateReminderInput`。`id`、`status`、`createdAt`、`triggeredAt` 和 `completedAt` 由 `ReminderService` 统一生成或维护，避免不同入口产生不同默认值。

### 5.4 数据不变量

- `content` 去除首尾空白后不能为空。
- `TIME` 必须包含有效的 `triggerTime`。
- `LOCATION` 在激活前必须包含可用的 `sceneId`。
- `BOTH` 在激活前必须同时包含 `triggerTime` 和可用的 `sceneId`。
- 存在地点条件时，正式 Reminder 必须包含 `locationTriggerMode`；创建输入缺省时由 ReminderService 统一补为 `ENTER`。
- 只有 `sceneName` 而没有可解析 `sceneId` 的 AI 结果必须进入用户确认流程。
- 无法确认的过去时间不自动改写为未来时间。
- 任何未通过校验的输入都不得写入 ReminderRepository。

### 5.5 Scene 公共模型

```ts
export interface Scene {
  id: string
  name: string
  latitude: number
  longitude: number
  radius: number
  createdAt: number
}
```

Reminder 只通过 `sceneId` 引用 Scene，并保留 `sceneName` 作为显示快照。Scene 的正式仓储、权限、定位、围栏和管理实现由地点模块负责人完成。

### 5.6 纯逻辑模型规则

阶段 1 增加 `model/ReminderModelRules.ets`，让模型不变量可以在 ReminderService 出现前被单元测试，并由后续 ReminderService 直接复用：

```ts
export function validateCreateReminderInput(
  input: CreateReminderInput,
  now: number
): OperationError[]

export function canTransitionReminderStatus(
  current: ReminderStatus,
  next: ReminderStatus
): boolean
```

创建输入校验返回稳定错误码：`EMPTY_CONTENT`、`MISSING_TRIGGER_TIME`、`INVALID_TRIGGER_TIME`、`PAST_TRIGGER_TIME` 和 `MISSING_SCENE_ID`。TIME 和 BOTH 的 `triggerTime` 必须是有限数值且不得早于 `now`；LOCATION 和 BOTH 的 `sceneId` 去除首尾空白后不得为空。地点创建输入可以省略 `locationTriggerMode`，由 ReminderService 在正式创建时统一补为 `ENTER`。

状态转换规则如下：

- 相同状态允许作为幂等操作。
- `ACTIVE` 可以进入 `TRIGGERED`、`COMPLETED` 或 `DISABLED`。
- `DISABLED` 可以重新进入 `ACTIVE`，也可以由用户标记为 `COMPLETED`。
- `TRIGGERED` 只能进入 `COMPLETED`。
- `COMPLETED` 是终态，不能重新激活、禁用或触发。

模型规则只判断纯领域条件，不读写仓储、不注册系统任务，也不调用 HarmonyOS API。

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
- 更新、启用、禁用、用户完成和删除提醒。
- 维护 `ACTIVE`、`TRIGGERED`、`COMPLETED` 和 `DISABLED` 生命周期。
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

TIME、LOCATION 和 BOTH 三种提醒都必须统一经过 TriggerCoordinator，时间模块和地点模块只上报条件变化，不得直接决定或发送最终通知。

`BOTH` 固定为 AND 语义，并使用以下规则：

- 时间条件在 `triggerTime` 到达后打开，并保持为已满足。
- 地点条件表示用户当前处于目标场景，或在时间条件打开后进入目标场景。
- 如果用户在 `triggerTime` 到达时已经位于目标场景，协调器可立即触发。
- 如果时间到达时用户不在目标场景，则等待之后进入目标场景再触发。
- 位置在时间到达前曾经满足、但到达时已经离开，不视为联合条件满足。
- 每个 Reminder 最多发送一次最终通知，通知成功后状态从 `ACTIVE` 更新为 `TRIGGERED` 并记录 `triggeredAt`。

通知成功不等于用户完成事项，不能自动更新为 `COMPLETED`。只有用户主动确认完成后，ReminderService 才把状态更新为 `COMPLETED` 并记录 `completedAt`。

因此时间模块和定位模块不能各自直接发送 TIME、LOCATION 或 BOTH 通知。三种类型的最终决定都由统一 TriggerCoordinator 完成。

## 9. 错误处理

错误按边界分类：

- AI 基础设施错误：允许重试，不创建 Reminder。
- AI 内容错误：返回用户确认状态，并标明问题字段。
- Reminder 输入错误：由 ReminderService 拒绝并返回字段级错误。
- Repository 错误：保留原状态，不报告创建成功。
- 时间或位置注册错误：Reminder 不得表现为已成功启用；服务返回可恢复错误。
- 通知错误：不得把 Reminder 标记为 `TRIGGERED`；返回可重试错误并记录脱敏日志。自动重试频率不属于本次公共基础实现。

日志不得输出凭证、完整供应商请求头或其他敏感配置。

## 10. 团队所有权

| 路径或文件 | 主要所有者 | 协作规则 |
|---|---|---|
| `model/**`、`repository/**`、`service/**` | 贾宇璠 | 公共契约，变更前同步并由组长合并 |
| `ai/**` | 贾宇璠 | 不包含 UI、时间或定位实现 |
| `pages/**`、`components/**`、`reminder/time/**`、`reminder/notification/**` | 罗鸿程 | 通过公共服务和端口接入；负责正式时间调度和通知实现 |
| `location/**` | 兰铮 | 负责 Scene、定位和围栏正式实现；不直接修改 ReminderRepository |
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

## 12. 实现职责限制

组长在 `feature-ai` 上正式实现的范围为：

- `model/**`
- `repository/**`
- `service/**`
- `ai/**`
- `reminder/contract/**`
- `reminder/TriggerCoordinator.ets`
- 为接口验证所需的 Fake、Mock、Stub 和测试

以下内容只允许定义公共接口或测试替身，不由组长实现正式 HarmonyOS 能力：

- 完整 ArkUI 页面和组件
- 时间调度系统能力
- HarmonyOS Notification 具体实现
- 定位权限、Location Kit、地理围栏和后台地点事件
- Scene 正式仓储与管理实现

对应正式实现分别由 UI/时间/通知负责人和地点负责人在各自 feature 分支完成。

## 13. 验证策略

每个实现阶段完成后执行：

1. 对新增纯逻辑模块运行本地单元测试。
2. 对模型不变量、AI 解析错误和 Service 结果建立成功与失败用例。
3. 使用当前 DevEco SDK 执行 debug `assembleHap`。
4. 检查 Git 状态，确保无密钥、本地配置或生成文件进入提交。

当前基线已通过 ArkTS 编译和 `assembleHap`，可生成 `entry-default-unsigned.hap`。因未配置签名，产物为未签名 HAP。

## 14. 小步实施顺序

1. 建立 TriggerType、ReminderSource、ReminderStatus、LocationTriggerMode、Reminder、Scene、CreateReminderInput、OperationResult 和纯逻辑模型规则，并编写模型测试。
2. 建立 ReminderRepository 与 ReminderService 契约，并使用内存实现验证业务流程。
3. 建立 AIService、Fake Provider、解析、校验和映射流程，不调用真实 API。
4. 建立时间、地点、触发事件和通知端口，供另外两位成员并行实现。
5. 在 Fake Provider 和公共接口稳定后，再设计真实 AI Provider 和安全配置。
6. 最后在 `develop` 上完成 UI、AI、时间、定位和通知的集成验证。
