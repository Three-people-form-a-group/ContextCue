# 定位权限清单与后台定位结论

## 一、结论

| 权限 | 是否声明 | UI 是否请求 | 用途 |
| --- | --- | --- | --- |
| `ohos.permission.APPROXIMATELY_LOCATION` | 是 | 是 | 模糊定位，精确位置权限的前置条件 |
| `ohos.permission.LOCATION` | 是 | 是 | 精确位置；判断是否进入场景、计算距离 |
| `ohos.permission.LOCATION_IN_BACKGROUND` | **否** | **否** | 后台主动取位置。地点提醒的两条投递路径都不需要它 |

**UI 只需要请求两个权限：`APPROXIMATELY_LOCATION` 和 `LOCATION`。**

被杀后仍能提醒（围栏扩展投递）**不需要**后台定位权限：围栏由系统托管，进入判断由系统完成，扩展进程只处理"事件已发生"之后的逻辑，不主动持续取位置。

> 当前口径：**结论是"不需要"，真机验证前按暂定结论执行。** 验证步骤见 [geofence-verification.md](docs/location/geofence-verification.md) 的"杀进程验收"。若真机实测扩展投递失败且日志显示与后台定位相关，再补权限声明与"始终允许"流程（见第三节）。

## 二、为什么围栏本身不需要后台定位权限

`addGnssGeofence()` 是系统托管的围栏，不是应用自己持续订阅位置：

- 注册接口要求的是 `LOCATION` + `APPROXIMATELY_LOCATION`，官方 API 标注中没有 `LOCATION_IN_BACKGROUND`。
- 围栏的进出判断由系统完成，应用只在回调（或围栏扩展）里收到事件。
- 后台定位权限解决的是"应用在后台主动调用 `getCurrentLocation()` / 持续定位"，不是"系统能不能生成围栏事件"。

## 三、边界：哪一步会用到主动定位

| 路径 | 是否主动取位置 | 说明 |
| --- | --- | --- |
| 主进程回调 → `isInsideScene()` | 是（`getCurrentLocation()`） | 应用在后台执行这步时，严格说需要后台定位权限。当前不接受这个成本：后台/锁屏场景是否触发以真机记录为准 |
| 围栏扩展 `LocationFenceAbility` | **否** | 只读持久数据 + 弹通知，不取位置，所以不需要后台定位权限 |

如果以后要正式支持"后台且进程存活时也可靠二次校验位置"，需要补：

- `module.json5` 增加 `LOCATION_IN_BACKGROUND`；
- UI 增加"去设置允许始终定位"的引导（先前台授权，再 `requestPermissionOnSetting()` 或引导到系统设置）；
- 更新隐私说明与商店审核材料；
- 真机验证锁屏/后台场景。

多一个后台权限会带来隐私说明、商店审核和用户理解成本，所以不做提前申请。

## 四、权限申请顺序

1. 用户点击创建地点提醒，或进入地点场景管理。
2. 调用 `LocationPermissionManager.request()`。
3. 系统弹窗同时请求 `APPROXIMATELY_LOCATION` + `LOCATION`。
4. 用户必须授予**精确位置**；只给模糊位置时视为不可用，因为围栏需要精确坐标。
5. 权限通过后，再调用 `SceneCatalog.create()` 或 `ReminderService.create()`。
6. 若用户拒绝，不要继续注册围栏，提示去设置开启精确位置和定位开关。

真机需要完整走一遍两项弹窗（精确 + 模糊），并记录用户只给模糊时的表现，见 [geofence-verification.md](docs/location/geofence-verification.md)。

当前实现中：

- 声明位置：[module.json5](entry/src/main/module.json5#L17-L49)
- 权限原因文案：[string.json](entry/src/main/resources/base/element/string.json)
- 运行时申请：[LocationPermissionManager.ets](entry/src/main/ets/location/platform/LocationPermissionManager.ets)

## 五、和"被杀后提醒"的关系

- 被杀后提醒靠 `FenceExtensionAbility` + 持久映射 + 持久提醒仓储，见 [geofence-lifecycle.md](docs/location/geofence-lifecycle.md)。
- 它**不依赖** `LOCATION_IN_BACKGROUND`，也不依赖应用进程存活。
- 但**依赖通知权限**：用户关闭通知时扩展会放弃投递（`NOTIFICATION_DISABLED`），提醒不会被标成已触发。UI 引导里要把"允许通知"和"开启定位"一起说清楚。
- 不要向用户承诺"授权后台定位就能被杀后提醒"——这两件事没有因果关系。
