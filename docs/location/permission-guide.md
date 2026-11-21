# 定位权限清单与后台定位结论

## 结论

| 权限 | V1 是否声明 | UI 是否请求 | 用途 |
| --- | --- | --- | --- |
| `ohos.permission.APPROXIMATELY_LOCATION` | 是 | 是 | 模糊定位，精确位置权限的前置条件 |
| `ohos.permission.LOCATION` | 是 | 是 | 精确位置；判断是否进入场景、计算距离 |
| `ohos.permission.LOCATION_IN_BACKGROUND` | **否** | **否** | 后台主动取位置；V1 不支持后台承诺，也不影响被杀后通知 |

**UI 只需要请求两个权限：`APPROXIMATELY_LOCATION` 和 `LOCATION`。**

## 为什么 GNSS 围栏本身不需要后台定位权限

`addGnssGeofence()` 是系统托管的围栏，不是应用自己持续订阅位置：

- 注册接口要求的是 `LOCATION` + `APPROXIMATELY_LOCATION`，官方 API 标注中没有 `LOCATION_IN_BACKGROUND`。
- 围栏的进出判断由系统完成，应用只在回调里收到事件。
- 后台定位权限解决的是“应用在后台主动调用 `getCurrentLocation()` / 持续定位”的问题，不是“系统能不能生成围栏事件”。

所以只注册围栏、只接收回调，不需要 `LOCATION_IN_BACKGROUND`。

## 但有一个边界要说明

当前回调后还会调用 `isInsideScene()` → `getCurrentLocation()` 再校验一次位置。如果应用在**后台**执行这个主动定位，严格来说需要后台定位权限。

V1 仍然不申请它，原因：

1. V1 已明确不支持“被杀后提醒”，也不承诺后台一定触发；申请后仍不能解决进程死亡。
2. `LOCATION_IN_BACKGROUND` 不能只靠普通权限弹窗完成：官方流程是先申请前台定位，成功后再引导用户去系统“设置”里授予后台位置权限，或调用 `requestPermissionOnSetting()`。
3. 多一个后台权限会带来额外的隐私说明、商店审核和用户理解成本。
4. 如果以后要正式支持后台，应该和持久化、通知去重一起做，而不是只加一行声明。

如果后续要支持“应用在后台但进程存活时也能可靠校验位置”，需要补：

- `module.json5` 增加 `LOCATION_IN_BACKGROUND`；
- UI 增加“去设置允许始终定位”的引导；
- 更新隐私说明；
- 真机验证锁屏/后台场景。

## 权限申请顺序

1. 用户点击创建地点提醒，或进入地点场景管理。
2. 调用 `LocationPermissionManager.request()`。
3. 系统弹窗同时请求 `APPROXIMATELY_LOCATION` + `LOCATION`。
4. 用户必须授予**精确位置**；只给模糊位置时视为不可用，因为围栏需要精确坐标。
5. 权限通过后，再调用 `SceneCatalog.create()` 或 `ReminderService.create()`。
6. 若用户拒绝，不要继续注册围栏，提示去设置开启精确位置和定位开关。

当前实现中：

- 声明位置：[module.json5](entry/src/main/module.json5#L13-L35)
- 权限原因文案：[string.json](entry/src/main/resources/base/element/string.json#L16-L19)
- 运行时申请：[LocationPermissionManager.ets](entry/src/main/ets/location/platform/LocationPermissionManager.ets#L33-L41)

## 和 P1 的关系

`LOCATION_IN_BACKGROUND` **不会**让被杀的进程收到围栏通知。要在被杀后通知，仍然需要 P1 文档里说的持久化 + `notifications` / `FenceExtensionAbility` 改造。不要向用户承诺“授权后台定位就能被杀后提醒”。
