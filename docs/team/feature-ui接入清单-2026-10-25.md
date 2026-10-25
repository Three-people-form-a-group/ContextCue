# feature-ui 接入公共层清单（2026-10-25）

写给：罗鸿程。整理：贾宇璠。目的：feature-ui 当前基于初始工程 `fc0c892` 开发，`feature-ai` 上的公共模型、`ReminderService` 和触发契约在你的分支上还不存在；这份清单说明合并后如何把 UI 从临时数据层切到公共层。只涉及数据来源替换，不要求改动页面视觉结构。

## 一、合并情况（已预演）

用 `git merge-tree` 对 `feature-ai` 和 `origin/feature-ui` 做了只读合并预演：**两分支唯一冲突文件是 `.gitignore`**（双方各自补了 `local.properties`、`.hvigor/` 等条目，手工合并去重即可），其余文件零冲突。合并方向和时机由组长在集成阶段统一安排，你不需要自己动 develop。

## 二、替换映射表

| feature-ui 现状 | 接入后 | 说明 |
| --- | --- | --- |
| `common/UiReminderSemantics.ets` | `model/ReminderEnums.ets` | 你的枚举字符串值与公共枚举完全一致，直接替换 import 后删除本文件 |
| `common/UiReminderStore.ets` | `getAppServices().reminderService` | 从 `app/AppServiceRegistry.ets` 导入；启动入口已组装，页面不再维护静态数组，也不直接访问仓储 |
| `common/MockReminderData.ets` | （删除） | 首屏列表改为渲染 `ReminderService.findAll()` 的结果 |
| `ReminderCardData`（ReminderCard.ets 内） | `model/Reminder.ets` | 卡片字段直接映射 Reminder；展示时区分 `TRIGGERED`（已通知）和 `COMPLETED`（已完成），两者不能混用 |
| `ReminderDetailNavParam.data`（传整卡数据） | 只传 `reminder.id` | 详情页用 `ReminderService.findById(id)` 查询；`RouterConstants.ets` 本身保留 |
| `ReminderEditNavParam` + 表单提交 | 组装 `CreateReminderInput` 调 `ReminderService.create` | `id`、`status`、`createdAt`、`triggeredAt`、`completedAt` 一律由服务生成，页面不写；创建失败按 `OperationResult.error.code` 提示 |
| `common/UiTimeInputParser.ets` | **保留** | 纯输入解析（中文时间写法 → Epoch 毫秒），产出的时间戳直接进 `CreateReminderInput.triggerTime`；它不做业务校验，最终以服务校验为准 |

## 三、接入 AI 入口（按你的页面规划做）

服务获取、开发模式限制和正式适配方式见 [服务组装与页面接入说明](服务组装与页面接入说明-2026-10-25.md)。当前可接真实服务 CRUD，但内存数据不持久化，也不会自动触发或发送通知；页面须展示开发联调提示。默认 Fake AI 未配置样例，不会对任意输入返回成功结果。

- 页面只依赖 `AIService.parseReminder(text, context)`，不要接触 `AIModelProvider` 和内部解析文件。
- 调用顺序见《AI模块联调说明-2026-10-23.md》"页面接入顺序"：`READY` 展示 `draft` 供用户确认 → 确认后调 `ReminderService.create(draft)` 并再次检查 `success`（等待期间时间可能已过期）；`NEEDS_CONFIRMATION` 让用户补充或修改；`FAILED` 按 `issues[].retryable` 决定是否允许重试。
- `context` 使用 `{ now: Date.now(), timeZone: 'Asia/Shanghai', locale: 'zh-CN' }`（时区后续可从系统设置读取）。
- 解析本身不保存提醒、不注册触发器；只有 `create` 成功才产生正式 Reminder。

## 四、注意事项

- 不要直接访问 `ReminderRepository`；启用、禁用、完成、编辑、删除都走 `ReminderService` 对应方法。
- `TriggerType`、`LocationTriggerMode` 用公共枚举；V1 只用 `ENTER`，不要把预留的 `EXIT` 当成已支持功能。
- 你用 Navigation 单入口导航、不注册 `main_pages.json` 的做法可以保留。
- `common/` 目录目前不在《公共接口清单》的所有权表里，建议在群里确认 `common/**` 归你（UI 内部代码），避免后续归属模糊。
- 组长在 `app/AppBootstrap.ets` 统一选择依赖，由 `app/AppServices.ets` 组装服务和协调器；`EntryAbility.ets` 已负责启动初始化。页面不修改这些集成文件。
- 现有 `InMemoryReminderRepository` 重启不保留数据，属预期行为，不要为了持久化自行改仓储实现。
