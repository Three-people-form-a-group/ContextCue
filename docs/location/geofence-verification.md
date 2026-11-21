# 地理围栏验证指南（P4）

## 结论

| 项目 | 模拟器 | 真机 |
| --- | --- | --- |
| `getCurrentLocation()` 基础定位 | 可用（在模拟器扩展面板里模拟 GPS） | 可用 |
| WGS84 坐标类型查询 | 取决于系统实现，可能为空 | 通常支持 |
| `addGnssGeofence()` GNSS 围栏 | **不可用 / 不可信** | 唯一可验收环境 |
| 围栏进入事件真实触发 | **无法验收** | 户外空旷处可行 |
| 应用被杀后通知 | 不支持（见 geofence-lifecycle.md） | 不支持（V1 限制） |

**GNSS 围栏依赖 GNSS 芯片级能力，模拟器没有真实卫星定位，无法产生可信的“进入围栏”事件。坐标、半径、权限、切换开关等前段逻辑可以在模拟器上验证，真正的围栏触发必须真机。**

华为官方文档《模拟器与真机的差异》中也标注了 Location Kit 相关能力在模拟器上的支持差异，结论与上面一致。

## 代码侧已做的适配

- `supportsWgs84()` 现在会在查询前调用 `isGnssFenceServiceSupported()`（API 26+），并在异常时返回 `false`。
- 因此在模拟器或不支持围栏的设备上，注册会稳定返回 `LOCATION_WGS84_FENCE_UNSUPPORTED`，而不是抛出难以理解的系统异常。
- 相关代码：[HarmonyLocationPlatform.ets](entry/src/main/ets/location/platform/HarmonyLocationPlatform.ets#L24-L36)

验证设备是否支持围栏，可用：

```bash
hdc shell param get const.location.support_geofence
```

返回 `true` 表示系统参数声明支持 GNSS 围栏；返回空或 `false` 时，围栏注册不应被期待成功。

## 真机验证步骤

### 准备

1. 使用支持 GNSS 围栏的手机（`const.location.support_geofence=true`）。
2. 打开系统定位开关（设置 → 位置信息）。
3. 安装 debug 版应用并授予**精确位置**。

### 选点与围栏参数

要求“室外、移动距离可控、半径足够大”：

- 半径：建议 **200 米**（在 100–5000 米合法范围内，且比定位漂移大）
- 坐标：选择你能步行 500 米以上距离的空旷路线，例如操场或校园主路
- 围栏必须在室外测试，室内 GNSS 信号差会漏触发

示例（上海人民广场附近，仅作格式示例）：

```text
center: latitude 31.2304, longitude 121.4737
radius: 200 m
```

记录该中心点，并把围栏创建在你**起始位置 500 米外**。

### 操作流程

1. 在应用内创建场景“验证点”，使用上面的坐标和 200 米半径。
2. 创建一条地点提醒，内容“围栏验证”，触发方式为进入该场景。
3. 确认创建成功（不应出现 `LOCATION_NOT_STARTED` / `LOCATION_FENCE_REGISTRATION_FAILED`）。
4. 保持应用运行，步行或骑车进入半径内。
5. 观察是否收到提醒通知。
6. 记录日志，确认回调到达。

### 日志观察

```bash
hdc shell hilog -x | Select-String -Pattern "Geofence|ContextCue|TriggerCoordinator"
```

需要看到的关键点：

1. `addGnssGeofence success`（或围栏 ID 返回）
2. `GeofenceTransition` 事件，`transitionEvent` 为进入
3. 协调器通过 `isInsideScene()` 二次校验
4. 通知发布成功，提醒状态变为 `TRIGGERED`

### 模拟“进入”的替代方式

真机也可以用系统调试手段模拟位置，但**只能验证前半段逻辑**：

- 部分系统版本提供“模拟位置”能力（系统接口，普通应用无法调用）；
- 华为手机上通常需要在**开发者选项**或使用系统工具设置模拟位置；
- 模拟位置是否触发 GNSS 围栏，取决于厂商实现，**不能作为围栏验收结论**。

如果只是想验证“事件到达后应用能正确提醒”，更可靠的方式是在 debug 版提供调试入口，手动注入一次进入事件（调用 `TriggerEventSink.onConditionChanged`），但这属于流程验证，不是围栏验证。

## 需要分别记录的结果

真机验收时应明确记录：

1. `const.location.support_geofence` 的值；
2. `getGeofenceSupportedCoordTypes()` 是否包含 WGS84；
3. 围栏注册是否返回 ID；
4. 进入后多久收到事件（通常几十秒到数分钟，取决于 GNSS 状态）；
5. 应用**在前台**时是否收到通知；
6. 应用**在后台但进程存活**时是否收到通知（本项 V1 不承诺，但需要如实记录）；
7. 应用被杀后是否收到通知（预期：否）。

## 失败排查顺序

| 现象 | 排查 |
| --- | --- |
| `LOCATION_WGS84_FENCE_UNSUPPORTED` | 设备不支持围栏或 WGS84；检查 `const.location.support_geofence` |
| `LOCATION_PERMISSION_DENIED` | 只给了模糊位置，或未授权 |
| `LOCATION_SWITCH_OFF` | 系统定位开关关闭 |
| `LOCATION_FENCE_REGISTRATION_FAILED` | 半径异常、围栏数超限（单应用约 100）、系统服务不可用 |
| 注册成功但不触发 | 在室内、未真正跨越边界、平台为模拟器、半径过小 |

## 建议的团队验收记录模板

```text
设备型号：
系统版本：
const.location.support_geofence：
WGS84 支持：是/否
中心点：lat, lng
半径：200 m
注册结果：成功/失败（围栏 ID）
前台进入触发：是/否，耗时
后台进程存活进入触发：是/否，耗时
杀进程后进入触发：否（V1 预期内）
备注：
```
