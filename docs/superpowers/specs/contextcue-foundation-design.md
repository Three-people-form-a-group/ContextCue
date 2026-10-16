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
AIService ───────────→ SceneResolver
ReminderService ─────→ ReminderRepository
ReminderService ─────→ TimeTriggerPort / LocationTriggerPort
time / location ─────→ TriggerEventSink
TriggerCoordinator ──→ ReminderNotificationPort
TriggerCoordinator ──→ ReminderService
```

公共 `model` 和接口层不得依赖 ArkUI 页面或具体 HarmonyOS 系统能力。

`AIService` 依赖 `SceneResolver` 只用于把 AI 解析出的 `sceneName` 解析为稳定的 `sceneId`，不表示 AI 模块负责地点业务实现。`TriggerCoordinator` 依赖 `ReminderService` 只用于在通知成功后完成状态更新，不表示协调器可以绕过服务直接改写 Reminder。

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

`TRIGGERED` 表示条件已满足且通知发送成功，`COMPLETED` 表示用户主动确认事项已经完成，两者不得合并。

`LocationTriggerMode` 同时保留 `ENTER` 和 `EXIT`，两者都属于公共模型字段，不得删除。ContextCue V1 的正式实现和验收只支持 `ENTER`：

- `LOCATION` + `ENTER`：支持。
- `BOTH` + `ENTER`：支持。
- `LOCATION` + `EXIT`：公共模型可以表达，但 V1 不允许正式激活。
- `BOTH` + `EXIT`：公共模型可以表达，但 V1 不允许正式激活，其准确语义留到未来实现 `EXIT` 时再定义。

如果 V1 的 `CreateReminderInput` 显式传入 `locationTriggerMode = EXIT`，`ReminderService` 必须返回稳定的业务错误 `UNSUPPORTED_LOCATION_TRIGGER_MODE`（或语义等价的错误码），并且不得注册任何 Trigger。不要让 `EXIT` 预留能力变成当前版本的半实现功能。`EXIT` 仅作为公共模型和后续扩展能力预留，不要求地点模块负责人在 V1 阶段完成正式 `EXIT` 触发实现，也不因此增加地点模块第一阶段工作量。

`LOCATION` 和 `BOTH` 在 V1 中的正式语义只基于 `ENTER`。对于 `BOTH`，V1 的正式语义仍然是：时间条件满足，并且用户当前位于目标 Scene，或在时间条件打开后进入目标 Scene；V1 不定义 `BOTH` + `EXIT` 的语义。对于 `BOTH` 当前地点条件是否满足，仍然需要能够正确判断用户当前是否位于 Scene 中，通过 `LocationTriggerPort.isInsideScene(sceneId)` 解决，不要求先实现 `EXIT` 业务提醒。

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
- `ReminderService` 在构造正式 Reminder 前，对 `content` 和存在的 `sceneId` 去除首尾空白；仓储保存规范化后的值。
- 字段组合必须与 `triggerType` 一致，违反组合一致性时返回 `INCONSISTENT_TRIGGER_FIELDS`，并在 `field` 中标明冗余字段：
  - `TIME` 不得携带地点触发字段（`sceneId`、`sceneName`、`locationTriggerMode`）。
  - `LOCATION` 不得携带 `triggerTime`。
  - `BOTH` 必须同时具有时间与地点两类字段。
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

Reminder 只通过 `sceneId` 引用 Scene，并保留 `sceneName` 作为显示快照。

`Scene.ets` 仅定义跨模块使用的最小公共数据结构，由贾宇璠负责维护公共结构本身；Scene 的正式仓储、`SceneService`、地点增删改查、定位、地图选点、地理围栏和其他 Scene 业务实现均由兰铮负责。定义公共 Scene 数据结构不代表组长负责 Scene 业务模块实现。

单位与取值约定：`latitude` 取值范围 `[-90, 90]`，`longitude` 取值范围 `[-180, 180]`，`radius` 单位为米且必须大于 `0`，`createdAt` 为 Unix Epoch 毫秒值。这些是公共数据结构的语义约定；Scene 数据的校验、写入与维护由地点模块负责，Stage 1 不实现 Scene 校验、Scene 增删改查或地点业务。

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

创建输入校验返回稳定错误码：`EMPTY_CONTENT`、`INCONSISTENT_TRIGGER_FIELDS`、`MISSING_TRIGGER_TIME`、`INVALID_TRIGGER_TIME`、`PAST_TRIGGER_TIME`、`MISSING_SCENE_ID` 和 `UNSUPPORTED_LOCATION_TRIGGER_MODE`。

校验按稳定顺序累积错误，不在遇到第一个错误时立即返回：content → 字段组合一致性 → time → scene → location trigger mode。TIME 和 BOTH 的 `triggerTime` 必须是有限数值（`NaN`、`Infinity` 和 `-Infinity` 均返回 `INVALID_TRIGGER_TIME`）且不得早于 `now`；LOCATION 和 BOTH 的 `sceneId` 去除首尾空白后不得为空；`TIME` 携带地点字段或 `LOCATION` 携带 `triggerTime` 时返回 `INCONSISTENT_TRIGGER_FIELDS`。地点创建输入可以省略 `locationTriggerMode`，由 ReminderService 在正式创建时统一补为 `ENTER`；V1 中显式传入 `EXIT` 时返回 `UNSUPPORTED_LOCATION_TRIGGER_MODE`，并且不得注册 Trigger。

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

服务端代理只是未来真实 AI Provider 阶段的安全方案候选。当前公共模型阶段、Repository / Service 阶段、Fake AI 阶段和第一次 `develop` 集成阶段均不创建服务器项目，不实现 Node.js / Java / Python 后端，不增加微服务，也不为此提前建立 `backend` 目录。只有进入真实 AI Provider 接入时，才根据课程剩余时间、部署成本、HarmonyOS 上架要求和 API 供应商安全要求单独确定最终方案。

### 6.4 地点解析与 SceneResolver 的关系

AI 只能从自然语言中得到地点名称，例如 `sceneName = "实验室"`，而地点提醒和联合触发需要稳定的 `sceneId`。因此 AIService 在解析后必须通过 `SceneResolver` 完成地点解析：

```text
AIService
  → AI Provider / AIResponseParser
  → 得到 sceneName
  → SceneResolver.resolveByName(sceneName)
```

解析结果按以下规则处理：

- `RESOLVED`：自动补充 `sceneId`；如果其余字段也明确，可以给出 `READY`。
- `AMBIGUOUS`：进入 `NEEDS_CONFIRMATION`。
- `NOT_FOUND`：进入 `NEEDS_CONFIRMATION`。

`SceneResolver` 的接口由贾宇璠在 `reminder/contract/SceneResolver.ets` 中定义；`SceneResolver` 的正式地点数据查询实现由兰铮负责。`feature-ai` 阶段如果需要测试，只允许使用 Fake / Mock `SceneResolver`。贾宇璠不因此负责 `SceneRepository`、`SceneService` 或任何地点正式实现。

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

`save()` 采用 upsert 语义：如果 `reminder.id` 尚不存在，则创建记录；如果相同 `id` 已存在，则更新已有记录。V1 不新增 `insert()` / `update()` 两套额外接口，当前 `save()` 足够。

仓储只负责数据读写，不负责 AI 解析、调度、围栏或通知。仓储也不负责判断 Reminder 状态转换是否合法、是否允许启用、是否允许完成、是否应该注册时间任务或地点任务。这些业务规则由 `ReminderService` 与 `ReminderModelRules` 负责。

当前公共服务阶段使用内存仓储验证流程；它不承诺进程重启后的持久化。后续正式持久化适配器仍遵守同一个 Repository 契约。

### 7.2 ReminderService

ReminderService 是创建和修改 Reminder 的唯一公共入口，职责包括：

- 校验 CreateReminderInput。
- 生成 ID、创建时间和生命周期默认值。
- 保存 Reminder。
- 根据变化同步时间与地点触发端口。
- 更新、启用、禁用、用户完成和删除提醒。
- 维护 `ACTIVE`、`TRIGGERED`、`COMPLETED` 和 `DISABLED` 生命周期。
- 在仓储或触发端口失败时返回明确错误，不静默吞掉异常。

页面、AI、时间和定位模块都不得绕过 ReminderService 直接修改 Reminder 状态。`TriggerCoordinator` 同样不得直接操作 `ReminderRepository` 修改状态，它只能在通知成功后通过 `ReminderService` 提供的状态更新能力把 Reminder 从 `ACTIVE` 更新为 `TRIGGERED` 并记录 `triggeredAt`。为此不新增 `ReminderStateManager`、`LifecycleService`、`StateMachineService`、`CommandBus` 或其他额外架构层。

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

V1 的 Service 错误码固定为 `REMINDER_NOT_FOUND`、`INVALID_STATUS_TRANSITION`（不可重试），以及 `REPOSITORY_ERROR`、`TRIGGER_REGISTRATION_ERROR`、`TRIGGER_CLEANUP_ERROR`（可重试）。输入字段错误继续使用 `ReminderModelRules` 的现有错误码。

### 7.3 创建/启用与 Trigger 注册的一致性

创建或启用 Reminder 是一个完整业务操作。只有同时满足下面两点，`ReminderService` 才能向上层报告“创建/启用成功”：

1. Reminder 数据成功持久化。
2. 当前 `TriggerType` 所需要的正式 Trigger 注册全部成功。

按类型的要求如下：

- `TIME`：需要时间 Trigger 注册成功。
- `LOCATION`：需要地点 Trigger 注册成功。
- `BOTH`：需要时间和地点两个 Trigger 都注册成功。

如果其中任一步失败，不得让 Reminder 最终保持为“看起来 `ACTIVE` 但实际上不会触发”的状态，必须执行必要的补偿或回滚：如果前面已经成功注册了部分 Trigger，而后续步骤失败，应取消已完成的注册，并向调用方返回可恢复错误。本规范不要求引入数据库事务系统或复杂事务框架。补偿自身也可能失败；本阶段只能尽力恢复并返回可重试错误，不能声称已完全一致，后续正式适配器仍需设计残留 Trigger 的恢复机制。

创建顺序固定为：校验输入、在内存中构造最终 ACTIVE Reminder、注册所需 Trigger、最后只调用一次 `repository.save(ACTIVE Reminder)`。注册失败时取消此前成功的注册且不写仓储；最终保存失败时取消本次注册，失败的创建不得留下临时 DISABLED 记录。`DISABLED` 仅表示真实提醒被禁用，不作为创建过程中的过渡状态。

### 7.4 Reminder 生命周期与 Trigger 同步规则

Reminder 的 Trigger 注册状态必须跟随 `status` 变化，并且只能由 `ReminderService` 执行；时间模块和地点模块只提供 `schedule` / `cancel` 与 `register` / `unregister`，不修改 Reminder 状态。

- 创建并进入 `ACTIVE`：`TIME` / `BOTH` 调用 `TimeTriggerPort.schedule`，`LOCATION` / `BOTH` 调用 `LocationTriggerPort.register`。
- 重新启用（`DISABLED` → `ACTIVE`）：按当前条件重新注册。
- 禁用（`ACTIVE` → `DISABLED`）：必须 `cancel` 时间调度并 `unregister` 地点监听。
- 用户完成（→ `COMPLETED`）：必须 `cancel` 并 `unregister`，终态不保留任何 Trigger 注册。
- 触发成功（→ `TRIGGERED`）：通知已经发送，先保存 `TRIGGERED` 和 `triggeredAt`，再 `cancel` 时间调度并 `unregister` 地点监听；Reminder 记录保留，等待用户确认完成。清理失败时不得回写 ACTIVE；返回可重试的清理错误，并携带已持久化的 TRIGGERED Reminder 供调用方识别。一次性提醒不得保留第二次触发的注册。
- 编辑：先按旧条件 `cancel` / `unregister`，再按新条件注册；`TriggerType` 改变时同时清理另一类注册。
- 删除：先 `cancel` / `unregister`，再删除仓储记录；清理失败时不得报告删除成功，返回可恢复错误。
- 普通创建、启用、禁用、完成、编辑或删除中的注册/清理失败，不得报告目标操作成功，必须返回明确错误（见第 9 节）。通知已发送后的 `TRIGGERED` 状态是唯一例外：一旦状态保存成功，即使清理失败也保留已通知事实。
- 对已经取消或从未注册的 `reminderId`，`cancel` 和 `unregister` 必须可安全重复调用（幂等 no-op），使禁用、完成、触发、编辑和删除路径可以无条件清理。

相同状态请求是真正的幂等 no-op：成功返回当前 Reminder，不再次保存、不注册或清理 Trigger，也不改写 `triggeredAt` / `completedAt`。

同一个 `ReminderService` 实例必须按 Reminder ID 串行执行创建、状态变更、编辑、删除及触发清理，以免异步端口调用期间较旧的 ACTIVE 快照覆盖后续 TRIGGERED 或 COMPLETED 状态。不同 ID 可以并行。此进程内保证不替代后续持久化适配器的跨进程并发控制；集成时应共享同一服务实例。

因此 TRIGGERED 已保存但清理失败时，不通过再次调用 `markTriggered` 重试；`ReminderService.retryTriggerCleanup(id)` 是单独的可重试清理入口，只清理残留 Trigger，不发送通知、不修改状态或时间戳。Stage 2 不实现后台自动重试。

ACTIVE Reminder 编辑按“校验新输入 → 保留 id、createdAt 和状态构造新实体 → 清理旧 Trigger → 注册新 Trigger → 最后保存新实体”的顺序执行。失败时取消已注册的新 Trigger、尽可能恢复旧 Trigger；旧仓储记录不得被新实体覆盖，也不得报告编辑成功。

同步规则只规定调用顺序与失败语义，不新增调度机制或其他架构层。

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

`SceneResolveResult` 区分唯一匹配、多个候选和未找到三种结果；只有 `RESOLVED` 能够自动补充 `sceneId`，其余结果进入用户确认流程。

`LocationTriggerMode.EXIT` 只在公共模型中预留：V1 的事件协议只实现 `ENTER` 语义，`LocationTriggerPort` 与 `TriggerConditionEvent` 不区分进入和离开，地点模块只在用户进入目标 Scene 时上报条件满足。V1 正式实现和验收只支持 `ENTER`，`LOCATION` + `EXIT` 与 `BOTH` + `EXIT` 都不允许正式激活，显式传入 `EXIT` 时 `ReminderService` 返回 `UNSUPPORTED_LOCATION_TRIGGER_MODE` 并且不注册任何 Trigger。

协调器不得把一次历史进入事件永久视为地点条件满足，在时间条件到达时可通过 `isInsideScene(sceneId)` 重新确认用户当前是否位于 Scene 中。

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

触发事件到状态更新的流程固定为：

```text
TriggerConditionEvent
  ↓
TriggerCoordinator
  ↓
判断 TIME / LOCATION / BOTH 是否满足
  ↓
ReminderNotificationPort.notify(reminder)
  ↓
通知成功
  ↓
通过 ReminderService 提供的状态更新能力
  ↓
ACTIVE → TRIGGERED，并记录 triggeredAt
  ↓
ReminderRepository
```

如果通知失败，不得把 Reminder 更新为 `TRIGGERED`。TriggerCoordinator 不直接写 `ReminderRepository`，状态变更统一由 `ReminderService` 完成。

进程重启与条件恢复：TriggerCoordinator 不应只依赖进程内临时变量保存条件状态。在应用/进程重新启动、系统恢复或 TriggerCoordinator 重建后：

- TIME 条件：可通过 `currentTime >= reminder.triggerTime` 重新计算。
- LOCATION 条件：可通过 `LocationTriggerPort.isInsideScene(sceneId)` 重新确认当前状态。
- 历史 TIME 事件丢失不应导致 Reminder 永远无法触发。
- 历史 LOCATION ENTER 事件也不能永久当作当前仍然在 Scene 中。
- 对于 `BOTH`，恢复时应根据当前时间和当前地点重新判断是否满足。

当前阶段不实现复杂持久化状态机，只需要把这条恢复原则写入公共架构规范。

## 9. 错误处理

错误按边界分类：

- AI 基础设施错误：允许重试，不创建 Reminder。
- AI 内容错误：返回用户确认状态，并标明问题字段。
- Reminder 输入错误：由 ReminderService 拒绝并返回字段级错误。
- Repository 错误：保留原状态，不报告创建成功。
- 时间或位置注册错误：Reminder 不得表现为已成功启用；服务返回可恢复错误。
- 触发清理错误：禁用、完成、编辑或删除不得报告目标操作成功，返回可恢复错误；`TRIGGERED` 状态保存成功后的清理错误返回失败结果，但保留 TRIGGERED 和已通知事实，不能回滚成 ACTIVE。
- 通知错误：不得把 Reminder 标记为 `TRIGGERED`；返回可重试错误并记录脱敏日志。自动重试频率不属于本次公共基础实现。

如果通知已成功、但保存 `TRIGGERED` 本身失败，Service 返回 `REPOSITORY_ERROR`，无法仅靠本阶段的内存仓储保证跨进程去重。后续 TriggerCoordinator 与通知适配器集成时必须设计恢复或去重策略，不能把一次失败的状态保存解释为“通知未发出”。

日志不得输出凭证、完整供应商请求头或其他敏感配置。

## 10. 团队所有权

三人固定分工，不重新分配：

- 贾宇璠：公共架构设计、顶层公共 `model/**`、`ReminderRepository`、`ReminderService`、AI 模块、`reminder/contract/**`、`TriggerCoordinator`、必要的 Fake / Mock / Stub、公共业务规则、最终模块整合、GitHub PR 审核与代码集成。不负责完整 ArkUI 页面、时间调度系统能力、HarmonyOS Notification 具体实现、Location Kit、定位权限、地理围栏、后台地点事件、`SceneRepository`、`SceneService`、Scene 正式增删改查、地图选点和地点业务正式实现。
- 罗鸿程：`pages/**`、`components/**`、`reminder/time/**`、`reminder/notification/**`、UI 和交互、时间提醒正式实现、HarmonyOS Notification 正式实现。
- 兰铮：`location/**`、Scene 正式管理、`SceneRepository` / `SceneService`、定位权限、Location Kit、`SceneResolver` 正式实现、`LocationTriggerPort` 正式实现、Geofence、后台地点事件、地点真机测试。

| 路径或文件 | 主要所有者 | 协作规则 |
|---|---|---|
| `model/**` | 贾宇璠 | 跨模块公共领域模型；变更前同步并由组长合并 |
| `location/model/**` | 兰铮 | 地点模块内部模型；不放入顶层 `model/**` |
| `reminder/time/**` 内仅供时间模块使用的内部模型 | 罗鸿程 | 时间模块内部模型；不放入顶层 `model/**` |
| `repository/**`、`service/**` | 贾宇璠 | 公共契约，变更前同步并由组长合并 |
| `ai/**` | 贾宇璠 | 不包含 UI、时间或定位实现，不实现正式 HarmonyOS 系统能力 |
| `pages/**`、`components/**`、`reminder/time/**`、`reminder/notification/**` | 罗鸿程 | 通过公共服务和端口接入；负责正式时间调度和通知实现 |
| `location/**` | 兰铮 | 负责 Scene、定位和围栏正式实现，以及 `LocationTriggerPort` 与 `SceneResolver` 的正式实现；不直接修改 ReminderRepository；V1 只支持 ENTER 触发，EXIT 仅保留模型字段且不允许激活 |
| `reminder/contract/**`、`reminder/TriggerCoordinator.ets` | 公共，贾宇璠审核 | 接口变更需通知三人 |
| `EntryAbility.ets` | 集成入口 | 仅在整合阶段集中修改 |
| `module.json5`、根与 entry 的构建配置 | 公共配置 | 权限或依赖按独立 PR 修改 |
| `main_pages.json` | UI 主导、集成审核 | 避免多人同时编辑 |
| `oh-package-lock.json5` | 公共生成文件 | 仅随明确依赖变更提交 |

资源名称使用功能前缀，例如 `ai_`、`location_`、`reminder_`，降低公共资源文件中的命名冲突。

只有真正跨模块共享的数据结构才放到顶层 `model/**`。模块内部实现细节应放在各自模块目录中，由模块负责人维护。`entry/src/main/ets/model/**` 表示跨模块公共领域模型，`entry/src/main/ets/location/model/**` 表示地点模块内部模型；如果后续 `reminder/time` 内部存在仅供时间模块使用的内部模型，同样归罗鸿程，不属于公共 `model`。

## 11. Git 与本地文件

- `main` 保持稳定，功能开发进入各自 feature 分支，再合并到 `develop`。
- 不重写共享分支历史，不替其他成员修改其 feature 分支。
- `.hvigor/`、`local.properties`、构建产物和包含本地凭证的配置不得提交。
- 在公共基础阶段检查根 `.gitignore` 是否已经覆盖 `.hvigor/`、`local.properties`、构建产物以及本地凭证文件；如果尚未覆盖，则补充后再提交，并作为独立的小修改处理。

## 12. 实现职责限制

组长在 `feature-ai` 上正式实现的范围为：

- `model/**` 中的跨模块公共领域模型与公共契约
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

对应正式实现分别由 UI/时间/通知负责人和地点负责人在各自 feature 分支完成。贾宇璠只负责定义公共接口或 Fake / Mock / Stub，正式实现由对应成员在其 feature 分支完成。`feature-ai` 当前阶段不实现 UI、时间调度、Notification、定位与地理围栏的正式能力，也不实现 Scene 的正式仓储和管理功能。`SceneResolver` 的接口由贾宇璠定义，其正式地点数据查询实现归兰铮，`feature-ai` 阶段只允许使用 Fake / Mock `SceneResolver`；`LocationTriggerPort` 正式实现归兰铮，`TimeTriggerPort` 与 Notification 正式实现归罗鸿程。

## 13. 验证策略

每个实现阶段完成后执行：

1. 对新增纯逻辑模块运行本地单元测试。
2. 对模型不变量、AI 解析错误和 Service 结果建立成功与失败用例。
3. 使用当前 DevEco SDK 执行 debug `assembleHap`。
4. 检查 Git 状态，确保无密钥、本地配置或生成文件进入提交。

基线验证记录：截至本文档生成时，当前基线已通过 ArkTS 编译和 debug `assembleHap`，可生成 `entry-default-unsigned.hap`（产物位于 `entry/build/default/outputs/default/`）。因未配置签名，产物为未签名 HAP。后续每个阶段仍需重新执行 ArkTS 编译和 debug `assembleHap` 验证，以实际命令结果为准，不得仅根据代码判断成功。

## 14. 小步实施顺序

1. 建立公共 Model、枚举、CreateReminderInput、OperationResult 和 ReminderModelRules，并完成测试。
2. 建立 ReminderRepository 与 ReminderService，并使用内存实现验证公共业务流程。
3. 建立 AIService、Fake AI Provider、Parser、Validator、Mapper，不调用真实 API。
4. 建立 TimeTriggerPort、LocationTriggerPort、SceneResolver、TriggerEventSink、ReminderNotificationPort 等公共接口。
5. 实现并测试 TriggerCoordinator 的 TIME、LOCATION、BOTH 公共触发逻辑。
6. 公共模型和接口达到稳定状态后，冻结公共契约，允许罗鸿程和兰铮分别在 feature-ui、feature-location 上实现正式时间/通知和地点模块。
7. 在 `develop` 上完成第一次完整集成，使用 Fake AI 也可以，目标是验证 UI → CreateReminderInput → ReminderService → Repository → Time / Location → TriggerCoordinator → Notification 整条业务链可以工作。
8. 只有第一次完整业务链稳定后，再接入真实 AI Provider 和安全配置。
9. 最后进行完整功能测试、真机验证、UI 优化和上架准备。

不在 Fake AI 刚完成后立即开发真实 AI Provider。
