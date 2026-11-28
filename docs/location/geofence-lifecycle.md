# 地点围栏生命周期（V2：进程被杀也能提醒）

## 一、结论

地点提醒现在有两条投递路径，按进程是否存活分工：

| 场景 | 谁投递 | 结果 |
| --- | --- | --- |
| 应用进程存活（前台/后台） | 主进程 `LocationReminderAdapter` → `TriggerCoordinator` | 校验位置与提醒状态后弹通知、更新提醒状态 |
| 应用进程被杀 | 系统拉起 `LocationFenceAbility`（`FenceExtensionAbility`） | 查持久映射 → 读持久提醒 → 门控 → 弹通知 → 标记 `TRIGGERED` → 清围栏 |

两条路径共用同一套去重依据（持久映射里的保留位）和同一个通知 ID 算法，所以**同一次跨越不会弹两条通知**。

> 注意：这里说的"能弹"依赖两件事——系统围栏服务可用，以及提醒数据已经持久化。提醒持久化仓储由仓储负责人提供，接口见 [FenceReminderSource.ets](entry/src/main/ets/location/extension/FenceReminderSource.ets)。**在该仓储落地前，扩展会拒绝投递（`FENCE_REMINDER_STORE_UNAVAILABLE`），不会误弹。**

## 二、为什么以前不支持，现在怎么做

V1 只挂 `geofenceTransitionCallback`，这个回调运行在应用进程里。进程被杀后回调没有接收者，事件不补发，所以"被杀后不提醒"。现在不靠回调，而是让系统在围栏事件发生时拉起围栏扩展进程：

```text
主进程 register()
  ├─ addGnssGeofence(request{fenceExtensionAbilityName: 'LocationFenceAbility', geofenceTransitionCallback})
  └─ FenceRegistry.save(fenceId, reminderId)      ← 先落映射，再算注册成功

进程被杀后用户进入围栏
  └─ 系统启动 LocationFenceAbility.onFenceStatusChange(transition)
       ├─ geofenceId → FenceRegistry.find() → reminderId
       ├─ 持久提醒仓储 findById(reminderId)
       ├─ decideFenceDelivery()：状态/类型/模式/BOTH 时间/是否已投递
       ├─ FenceRegistry.markDelivered()          ← 先占位，失败就不弹（fail closed）
       ├─ notificationManager.publish()           ← 通知 ID 与主进程同一套 hash
       ├─ 持久仓储 save(status = TRIGGERED)
       └─ removeGnssGeofence + FenceRegistry.removeByReminder()
```

### V1 遗留的三个问题，逐条对应

| V1 风险 | V2 处理 |
| --- | --- |
| 重复通知 | 通知 ID 用 `fenceNotificationId()`，与 `SystemNotificationPort.notificationId()` 完全相同的 hash，同一条提醒只会覆盖；投递前先写保留位 `lastDeliveredAt`，重复事件直接跳过 |
| `BOTH` 绕过 | `decideFenceDelivery()` 里 `BOTH` 必须在 `now >= triggerTime` 时才放行，否则 `TIME_NOT_REACHED` |
| 状态不更新 | 扩展通过持久仓储把提醒写成 `TRIGGERED`（含 `triggeredAt`），不在扩展里维护私有副本 |

另外：配了扩展后，`geofenceTransitionCallback` 在进程内**故意空转**（`HarmonyLocationPlatform.addFence` 首行直接 return）。这个字段是必填的，不能省；空转是为了在"回调与扩展同时触发"的设备上不双弹。真机是否同时触发，按 [geofence-verification.md](docs/location/geofence-verification.md) 记录。

## 三、持久映射（fence_registry.json）

位置：`${context.filesDir}/fence_registry.json`，主进程与扩展进程同一个 hap、同一个 `filesDir`，所以两边看到的是同一份。

```json
{ "version": 1, "fences": [ { "fenceId": 7, "reminderId": "r-1", "lastDeliveredAt": 1766000000000 } ] }
```

| 字段 | 含义 |
| --- | --- |
| `fenceId` | `addGnssGeofence()` 返回的系统围栏 ID |
| `reminderId` | 这条围栏属于哪条提醒 |
| `lastDeliveredAt` | 投递保留位。有值表示"已经为这次跨越投递过"，扩展据此去重；发布失败时会被清掉 |

写入规则：

- **原子写**：写临时文件 → `fsync` → `rename`，不会出现半个 JSON。
- **跨进程锁**：所有“读—改—写”都先抢锁目录 `${filesDir}/fence_registry.json.lock`（`mkdirSync` 天生是“不存在才创建”的原子操作，`FileReminderRepository` 用同一套模式）。每隔 25ms 重试、最多约 2 秒；超过 5 秒的锁视为崩溃遗留并自动清理；仍拿不到则抛 `FENCE_REGISTRY_BUSY`（可重试），此时文件未被改动。读操作不抢锁：`rename` 保证读到的永远是完整版本。
- **fail closed**：读失败或写失败后置 `uncertain`，后续操作抛 `FENCE_REGISTRY_REQUIRES_RECOVERY` / `FENCE_REGISTRY_WRITE_FAILED`，不猜文件内容（与 `PreferencesSceneStorage` 的 uncertain 处理同风格）。
- **文档损坏**：抛 `FENCE_REGISTRY_CORRUPT`（版本号不对、字段缺失、fenceId/reminderId 重复）。
- **写失败必须回滚**：`register()` 里 `addFence` 成功后先 `save` 映射，`save` 失败会删掉刚建的围栏并释放场景引用。

## 四、启动对账

进程每次启动做两件事，顺序不能反：

1. `HarmonyLocationPlatform.recoverOrphanFences(registry)` —— **只删"没有映射"的围栏**。有映射的围栏保留，因为它们可能要交给扩展投递。映射是唯一权威，不看提醒状态。
2. `LocationReminderAdapter.reconcile(activeReminders)` —— 提醒级对账：
   - 映射存在但提醒已删除/不再是 ACTIVE 地点提醒 → 删围栏 + 删映射 + 清内存注册；
   - 提醒仍应提醒但没有映射 → 重新注册，补回围栏；
   - 有映射但本进程没有注册：
     - **配了扩展** → 直接沿用（扩展负责投递）；
     - **没配扩展**（V1 模式）→ 先删旧围栏、删映射，再重新注册，因为进程内回调必须由活进程重新挂上。

`stop()` 只清进程内注册，**故意不删持久映射和系统围栏**，否则被杀之后扩展就没有围栏可用了。

## 五、删除提醒的顺序

`remove()` 是"**先删映射、再删围栏**"：

- 映射是重启后找到围栏的唯一途径。顺序反了（先删围栏、再删映射）一旦第二步失败，就会留下"围栏已不存在、映射删不掉"的幻影记录，永远不可重试。
- 现在这条路失败时会把映射回写再抛错，下一次调用可以继续删；最坏情况只留下一个无主的围栏，由下次启动的对账清掉。

进程重启后内存里没有 registrations，`unregister(reminderId)` 通过持久映射找到 `fenceId` 再删——**重启后删除是真的删除**（V1 里这一支直接 return，属于假删除）。

## 六、用户可见文案（UI 使用）

可以承诺：

> 应用被关闭后，进入地点仍会收到提醒（需要允许通知、保持系统定位开启）。

仍然不要承诺"一定准时"：系统冻结、定位开关关闭、GNSS 信号差、围栏服务不可用都可能延迟或漏掉事件；用户关掉通知权限时扩展会直接放弃投递（`NOTIFICATION_DISABLED`），不会假装成功。

## 七、本模块负责与不负责

| 项 | 归属 |
| --- | --- |
| 围栏请求、持久映射、扩展进程门控与投递、启动对账 | 本模块（location） |
| 提醒持久化仓储 `createPersistentReminderRepository(baseDir)` | 仓储负责人；本模块只在 [FenceReminderSource.ets](entry/src/main/ets/location/extension/FenceReminderSource.ets) 接一行 |
| 通知点击路由（wantAgent） | 本模块已给扩展通知挂 `wantAgent`（`EntryAbility` + `reminderId` 参数，requestCode 复用通知 ID）；主进程 `EntryAbility.onNewWant` 跳详情由提交 `0351cf5` 提供，合并后生效 |
| 时间提醒对账、签名与 AGC 配置 | 不在本模块 |

## 八、验收口径

1. 进程存活：进入围栏 → 协调器通知一次、提醒变 `TRIGGERED`、围栏被删（现有 200 条单测覆盖）。
2. 进程被杀：按 [geofence-verification.md](docs/location/geofence-verification.md) 的"杀进程验收"执行，同时验证"不需要后台定位权限"这一结论。
3. 两条路同时可用时，同一次跨越只允许一条通知（靠保留位 + 同一通知 ID）。
