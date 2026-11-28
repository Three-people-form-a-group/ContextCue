# 地理围栏验证指南（P4）

> 状态：**计划已就绪，真机执行尚未完成**。本文件里的"预期"不是实测结论；执行后请把实测结果填进第五节并更新本行状态。

## 一、结论（当前认知）

| 项目 | 模拟器 | 真机 | 本模块代码是否已就绪 |
| --- | --- | --- | --- |
| `getCurrentLocation()` 基础定位 | 可用（模拟器扩展面板模拟 GPS） | 可用 | 是 |
| WGS84 坐标类型查询 | 取决于系统实现，可能为空 | 通常支持 | 是（API 26 守卫 + try/catch） |
| `addGnssGeofence()` GNSS 围栏 | **不可用 / 不可信** | 唯一可验收环境 | 是 |
| 围栏进入事件真实触发 | **无法验收** | 户外空旷处可行 | 是 |
| 应用被杀后通知 | 不支持 | **待真机验证**（V2 围栏扩展路径已实现） | 是，等实地结果 |

**GNSS 围栏依赖芯片级能力，模拟器没有真实卫星定位，无法产生可信的"进入围栏"事件。坐标、半径、权限、开关、映射落盘等前段逻辑可以在模拟器上验证，真正的围栏触发必须真机。**

## 二、代码侧已做的适配

- `supportsWgs84()` 先调 `isGnssFenceServiceSupported()`（API 26+），并在异常时返回 `false`；模拟器上稳定返回 `LOCATION_WGS84_FENCE_UNSUPPORTED` 而不是难懂的系统异常。
- 配了围栏扩展时，围栏请求带 `fenceExtensionAbilityName = 'LocationFenceAbility'`；进程内 `geofenceTransitionCallback` 仍必填但**故意空转**，避免双弹。
- 围栏 ID 与提醒 ID 的持久映射写入 `${filesDir}/fence_registry.json`（原子写、fail closed）。
- 相关代码：[HarmonyLocationPlatform.ets](entry/src/main/ets/location/platform/HarmonyLocationPlatform.ets)、[FenceAbility.ets](entry/src/main/ets/location/extension/FenceAbility.ets)、[FenceRegistryStore.ets](entry/src/main/ets/location/repository/FenceRegistryStore.ets)

验证设备是否支持围栏：

```bash
hdc shell param get const.location.support_geofence
```

返回 `true` 表示系统参数声明支持 GNSS 围栏；返回空或 `false` 时不要期待注册成功。

## 三、真机验证步骤

### 准备

1. 支持 GNSS 围栏的手机（`const.location.support_geofence=true`）。
2. 打开系统定位开关（设置 → 位置信息）。
3. 安装 debug 版应用（当前 `assembleHap` 未配签名，安装前需要签名配置，属账号侧工作）。
4. 授予**精确位置**，并允许通知。

### 选点与围栏参数

要求"室外、移动距离可控、半径足够大"：

- 半径：建议 **200 米**（合法范围 100–5000 米，且大于定位漂移）
- 坐标：选择能步行 500 米以上的空旷路线，例如操场或校园主路
- 必须在室外；室内 GNSS 信号差会漏触发

示例（仅作格式示例，不要照抄为验收点）：

```text
center: latitude 31.2304, longitude 121.4737
radius: 200 m
```

把围栏创建在你**起始位置 500 米外**，然后走进去。

### 步骤 A：进程存活（前台/后台）

1. 应用内创建场景"验证点"，用上面的坐标和 200 米半径。
2. 创建地点提醒，内容"围栏验证"，触发方式为进入该场景。
3. 确认创建成功（不应出现 `LOCATION_NOT_STARTED` / `LOCATION_FENCE_REGISTRATION_FAILED`）。
4. 保持应用运行，步行进入半径内。
5. 确认收到通知；回到应用确认提醒状态为 `TRIGGERED`、围栏已删除。
6. 再把应用切到后台（不杀进程），重复一次。

### 步骤 B：杀掉应用后跨围栏（V2 核心验收）

这一条同时验证两件事：**V2 场景能不能弹** + **"不需要后台定位权限"的论断是否成立**。

1. 确认提醒仍是 `ACTIVE` 且围栏已注册（应用内看到提醒存在）。
2. 完全杀掉应用进程：
   ```bash
   hdc shell aa force-stop com.jyf.contextcue
   ```
   或从最近任务里划掉，然后 `hdc shell ps -ef | findstr contextcue` 确认进程已不存在。
3. 离开围栏 500 米外，再步行进入。
4. 观察：
   - 是否收到通知（预期：收到，这是 V2 的目标）；
   - `hdc shell hilog -x | Select-String -Pattern "ContextCue fence|FenceExtension|LocationFenceAbility"` 是否出现扩展进程日志；
   - 重启应用后提醒状态是否为 `TRIGGERED`（而不是仍 `ACTIVE`）；
   - 是否**只**收到一条通知（不要两条）。
5. 如果没收到，按第六节排查，并**重点记录是否与后台定位权限有关**（这一条的结论要写回 [permission-guide.md](docs/location/permission-guide.md)）。

### 步骤 C：权限弹窗全流程

1. 全新安装（清数据）后首次创建地点提醒，确认同时弹出**模糊定位 + 精确定位**两项请求。
2. 只授予模糊定位 → 预期失败并返回 `LOCATION_PERMISSION_DENIED`，且**不提供"重试"主按钮**。
3. 到系统设置改成精确位置 → 回到应用重新创建 → 应成功。
4. 关闭系统定位总开关 → 预期 `LOCATION_SWITCH_OFF`；打开后重试 → 应成功。
5. 关闭应用通知权限 → 进程存活路径预期 `NOTIFICATION_DISABLED`（提醒保持 `ACTIVE`）；扩展路径同样放弃投递。

### 步骤 D：WGS84 与围栏数量上限

1. WGS84：注册一条围栏成功后，从日志/调试接口确认 `getGeofenceSupportedCoordTypes()` 是否包含 `WGS84`。
2. 上限实测：循环创建地点提醒（每条 1 个围栏），从 1 条加到注册开始失败，记录**成功注册的最大条数**与失败时的错误码（预期 `LOCATION_FENCE_REGISTRATION_FAILED`）。官方参考值约 100。

### 日志观察

```bash
hdc shell hilog -x | Select-String -Pattern "Geofence|ContextCue|LocationFenceAbility|TriggerCoordinator"
```

需要看到的关键点：

1. `addGnssGeofence` 成功（围栏 ID 返回），`fenceExtensionAbilityName` 已带上；
2. 进入事件（`transitionEvent` 为进入）；
3. 进程存活时：协调器 `isInsideScene()` 二次校验 → 通知 → 状态 `TRIGGERED`；
4. 进程被杀时：`ContextCue fence <id>: DELIVERED` 或 `SKIPPED <outcome>` 日志；
5. `fence_registry.json` 里对应条目被清掉。

### 模拟"进入"的替代方式

真机也可用系统的模拟位置能力，但**只能验证前半段逻辑**；模拟位置是否触发 GNSS 围栏取决于厂商实现，不能作为验收结论。若只想验证"事件到达后能正确提醒"，可以在 debug 版注入一次进入事件（`TriggerEventSink.onConditionChanged`），但那属于流程验证，不是围栏验证。

## 四、需要分别记录的结果

1. `const.location.support_geofence` 的值；
2. `getGeofenceSupportedCoordTypes()` 是否包含 WGS84；
3. 围栏注册是否返回 ID；
4. 进入后多久收到事件（通常几十秒到数分钟）；
5. 前台进入是否收到通知；
6. 后台且进程存活是否收到通知；
7. **杀进程后是否收到通知**（V2 目标）、扩展进程日志是否出现、重启后状态是否 `TRIGGERED`、是否只有一条通知；
8. 权限弹窗两项是否都出现；只给模糊时的错误码与 UI 表现；
9. 围栏数量上限实测值。

## 五、实测记录（待填）

```text
执行日期：
执行人：
设备型号：
系统版本：
const.location.support_geofence：
WGS84 支持：是/否
中心点：lat, lng
半径：200 m
注册结果：成功/失败（围栏 ID）
前台进入触发：是/否，耗时
后台进程存活进入触发：是/否，耗时
杀进程后进入触发：是/否，耗时
  扩展进程日志：有/无（摘一行）
  重启后提醒状态：TRIGGERED / 其它
  通知条数：1 / 其它
权限弹窗（模糊+精确）：是/否
只给模糊位置：错误码，UI 是否只给"去设置"
通知权限关闭：错误码与提醒状态
围栏数量上限：成功 N 条，失败错误码
是否需要后台定位权限：需要 / 不需要（依据）
备注：
```

## 六、失败排查顺序

| 现象 | 排查 |
| --- | --- |
| `LOCATION_WGS84_FENCE_UNSUPPORTED` | 设备不支持围栏或 WGS84；查 `const.location.support_geofence` |
| `LOCATION_PERMISSION_DENIED` | 只给了模糊位置，或未授权 |
| `LOCATION_SWITCH_OFF` | 系统定位开关关闭 |
| `LOCATION_FENCE_REGISTRATION_FAILED` | 半径异常、围栏超限、系统服务异常 |
| `FENCE_REGISTRY_WRITE_FAILED` / `FENCE_REGISTRY_REQUIRES_RECOVERY` | 沙箱写入失败或上次写坏；重启应用后重试，仍失败要查存储权限与剩余空间 |
| 注册成功但不触发 | 室内、未真正跨越边界、模拟器、半径过小、围栏服务被系统限制 |
| 被杀后不弹、扩展日志也没有 | 系统没拉起扩展：核对 `module.json5` 的 `type: "fence"` 与 `fenceExtensionAbilityName` 是否一致；再确认系统版本是否支持扩展围栏 |
| 被杀后扩展日志有 `NOT_MAPPED` | 映射缺失：检查 `fence_registry.json` 是否被清、fenceId 是否对应本次围栏 |
| 被杀后扩展日志有 `STORE_FAILED` / `FENCE_REMINDER_STORE_UNAVAILABLE` | 持久提醒仓储还没接线（见 [FenceReminderSource.ets](entry/src/main/ets/location/extension/FenceReminderSource.ets)） |
| 弹出两条通知 | 说明回调与扩展同时投递；确认 `delivery` 是否真的传进了 `addFence`，以及两条通知 id 是否一致 |
| 重启后提醒仍 `ACTIVE` | 扩展里 `store.save(TRIGGERED)` 失败；看 `STATE_UPDATE_FAILED` 日志 |

## 七、待真机确认的问题（合并前补充）

> 以下全部是**待验证**项，当前没有任何真机结论；不要在 UI 或文档里当成已成立的事实。

| 问题 | 预期 | 观察点 |
| --- | --- | --- |
| 进程内 callback 与围栏扩展会不会同时投递 | 只会有一条通知：配了扩展时进程内 callback 故意空转，且两条路径共用同一通知 ID + 保留位 | 步骤 A/B 各走一次，数通知条数；看 hilog 是否同时出现协调器投递与 `ContextCue fence ... DELIVERED` |
| 杀进程后进入围栏 | 扩展被系统拉起并投递，重启应用后提醒为 `TRIGGERED` | 步骤 B，重点确认扩展进程日志与 `fence_registry.json` 条目被清 |
| `BOTH` 提醒：时间到达前 / 后进入围栏 | 时间未到：地点事件不投递（`SKIPPED`），到点后由时间侧投递一次；时间已过：进入围栏正常投递 | 各建一条 `BOTH` 提醒，分别在时间点前后跨越，确认只提醒一次 |
| 重复进出围栏 | 提醒触发后围栏与映射被删，不再重复提醒；注销/重建后再次进入才会重新提醒 | 同一围栏多次进出，确认通知不累计、提醒状态只变一次 |
| 关闭通知权限 | 进程存活：`NOTIFICATION_DISABLED`，提醒保持 `ACTIVE`；扩展路径放弃投递并写日志，不假装成功 | 系统设置关闭通知后重复步骤 A/B，核对错误码与提醒状态 |
| 主进程对账与扩展进程同时写映射 | 跨进程锁目录生效：不丢 `lastDeliveredAt`（不重复弹）、不丢映射（不出现 `NOT_MAPPED`）；拿不到锁的一方得到可重试的 `FENCE_REGISTRY_BUSY`，文件保持不变 | 在扩展处理跨越的同时触发主进程 `reconcile`（或删除提醒），重复若干次后检查 `fence_registry.json` 是否两条更新都在；必要时临时在锁内加 sleep 放大窗口 |

真机执行后把结果填进第五节，并把上面的“预期”替换成实测结论；在此之前对外沟通只能说“代码路径已就绪，待真机验证”。
