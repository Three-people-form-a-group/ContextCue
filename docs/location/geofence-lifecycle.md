# 地点围栏生命周期与 V1 限制

## 结论

**V1 只在 ContextCue 进程存活时处理地点围栏事件；应用被彻底关闭（进程被杀）后，进入围栏不会收到提醒。**

这里不是"围栏没有注册成功"，而是围栏事件回到应用的那条路断了：

1. `addGnssGeofence()` 注册的围栏由系统侧保存，进程退出后围栏本身仍在。
2. 当前只使用 `geofenceTransitionCallback` 接收事件，这个回调运行在应用进程里。
3. 进程被杀后回调没有接收者，事件不会补发，也不会写入磁盘。
4. 应用下次启动时，`recoverOrphanFences()` 会主动删除这些遗留围栏，避免它们变成"永远无人处理"的孤儿。
5. 当前 `ReminderRepository` 是内存实现，进程死亡后提醒数据本身也不存在，所以即使补发事件也无法可靠地恢复成一条提醒。

因此"被杀后弹通知"不是加一行代码就能补齐的能力。

## 为什么不直接挂 `notifications`

`GnssGeofenceRequest` 确实支持 `notifications`，系统可以在应用不在时直接发通知。但 V1 刻意没有使用，原因是它绕过了 `TriggerCoordinator`：

- 地点提醒需要由协调器再次校验当前位置、提醒状态和场景版本；系统通知无法做这些校验。
- `BOTH` 提醒还要求"到达时间点并且进入地点"，直接在围栏请求里挂通知会在时间未到时误弹。
- 应用存活时，系统通知和协调器通知会重复弹出。
- 系统通知不会把提醒标记为 `TRIGGERED`，用户点开后应用状态仍可能是 `ACTIVE`。

同理，`FenceExtensionAbility`（API 14+）或 `fenceExtensionAbilityName`（API 23+）也不是简单开关：它需要持久化的围栏映射和事件队列、可跨进程读取的提醒数据、去重规则，以及点击通知后的页面路由。这些属于 V2 能力，不在本次范围内。

## 用户可见文案（UI 使用）

建议在地点提醒创建/详情/权限引导处显示：

> 地点提醒需要 ContextCue 保持运行。应用被系统或用户彻底关闭后，进入地点不会弹出提醒。

不要承诺"后台一定能触发"：即使进程还在，系统冻结、定位开关关闭、GNSS 信号差或围栏服务不可用也可能延迟或漏掉事件。

## 本次涉及的工程改动

- `entry/src/main/ets/location/platform/HarmonyLocationPlatform.ets`
  - 在围栏请求处注释说明为什么不挂通知/扩展。
  - 在 `recoverOrphanFences()` 上说明进程死亡期间的事件不会补发。
- `entry/src/test/location/LocationPlatform.test.ets`
  - 保留并强化"围栏请求不带 notifications"的断言，防止以后误加导致重复通知。
- `entry/src/main/module.json5`
  - **不新增** `FenceExtensionAbility`、`extensionAbilities` 或后台定位权限。当前能力不需要它们。

## V2 若要支持"被杀也能弹"

至少需要同时完成：

1. 提醒数据持久化（进程重启后可读）。
2. 围栏 ID ↔ 提醒 ID 的持久化映射。
3. 选择系统 `notifications` 或 `FenceExtensionAbility`，并定义去重/补发策略。
4. 处理 `BOTH` 条件，避免时间未到就误弹。
5. 真机杀掉进程后的验收：注册围栏 → 强制停止应用 → 移动进入围栏 → 检查通知是否出现，并确认点击后状态正确。

在此之前，验收口径按本文的"明确不支持"执行。
