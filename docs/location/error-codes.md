# 地点错误码语义与可重试性（P5）

## 一、五个错误码速查

| 错误码 | 谁抛出的 | 含义 | 用户能自己修好吗 | 可重试 | UI 建议 |
| --- | --- | --- | --- | --- | --- |
| `LOCATION_NOT_STARTED` | `LocationReminderAdapter` | 适配器还没启动就调用了地点相关方法 | 能（重新操作即可） | 是（通常自动消失） | 正常不出现；出现则提示“请重试”，并重新创建一次 |
| `LOCATION_PERMISSION_DENIED` | `LocationPermissionManager` | 没给精确位置权限（只给模糊也算） | 能，但要去设置里改 | **否**（直接重试必然失败） | 引导去设置开启“精确位置” |
| `LOCATION_SWITCH_OFF` | `LocationPermissionManager` | 系统定位总开关关了 | 能 | 是（但必须先开开关） | 引导打开定位开关，回来再点重试 |
| `LOCATION_WGS84_FENCE_UNSUPPORTED` | `HarmonyLocationPlatform.checkReady()` | 设备/模拟器不支持 GNSS 围栏或 WGS84 | **不能** | **否** | 明确告知“此设备不支持地点提醒”，建议改用时间提醒 |
| `LOCATION_FENCE_REGISTRATION_FAILED` | `LocationReminderAdapter.register()` | 围栏真的没加上（半径异常、围栏超限、系统服务异常等） | 一般不能，可能能 | 是 | 提示“地点围栏注册失败，请稍后重试” |

## 二、逐个说明

### `LOCATION_NOT_STARTED`

- **语义**：适配器处于未启动状态，却有人在用地点能力。
- **V1 现状**：`register()` 已经会懒启动（P0 修复），所以创建地点提醒时基本不会再看到它。
- **谁还会抛**：`isInsideScene()` 仍要求已启动。正常流程里第一次注册成功后就已启动。
- **可重试**：是，而且通常“再操作一次就好了”。
- **UI**：不需要专门文案，归入“请重试”即可。如果反复出现，说明是集成问题，要升级给开发排查。

### `LOCATION_PERMISSION_DENIED`

- **语义**：精确位置权限没拿到。只给了“模糊位置”也会走这个分支，因为围栏需要精确坐标。
- **可重试**：**否**。用户什么都不改，再点一次还是失败。
- **UI**：不要放“重试”主按钮，放“去设置”更合适。处理顺序：
  1. 提示需要精确位置；
  2. 引导到系统设置打开；
  3. 返回应用后重新触发一次创建。

### `LOCATION_SWITCH_OFF`

- **语义**：权限可能有，但系统定位总开关是关的。
- **可重试**：逻辑上是“先修再试”。重试本身不危险，但用户不打开开关就永远不会成功。
- **UI**：提示“请打开系统定位”，提供“去设置”，并在用户回到应用时自动重试一次；不要把重试做成无限循环。

### `LOCATION_WGS84_FENCE_UNSUPPORTED`

- **语义**：当前设备不能做 GNSS 围栏，或不支持 WGS84 坐标类型。典型场景：
  - 跑在模拟器上；
  - 设备没有 GNSS 围栏能力（`const.location.support_geofence` 不是 `true`）。
- **可重试**：**否**。这是设备能力问题，重试永远不会成功。
- **UI**：必须诚实地告诉用户“这台设备不支持地点提醒”，并建议改用时间提醒。**不要**显示成“加载失败”之类的可重试错误。

### `LOCATION_FENCE_REGISTRATION_FAILED`

- **语义**：`addGnssGeofence()` 调用失败。常见原因：
  - 半径不合法（我们已在场景层拦截 100–5000 米，正常不会触发）；
  - 围栏数量超限（单应用约 100 个）；
  - 定位服务暂时不可用；
  - 系统侧异常。
- **可重试**：**是**。这类失败多数是临时的。
- **注意**：原始异常被有意包装成这个码，避免把系统错误码直接暴露给 UI。如果需要排查具体原因，要看 hilog。

## 三、为什么需要这次改动

之前 `ReminderService` 把所有注册异常都吞成：

```ts
{ code: 'TRIGGER_REGISTRATION_ERROR', message: '触发条件注册失败', retryable: true }
```

问题：
- 用户看到“触发条件注册失败，可重试”，但如果是**权限没给**或**设备不支持**，重试一百次也没用；
- UI 无法区分“去设置”和“再试一次”两种完全不同的交互。

现在链路是：

```text
LocationReminderAdapter / HarmonyLocationPlatform 抛稳定码
  → ReminderService.registrationError() 映射成同码的 OperationError
  → 页面拿到 error.code 和 error.retryable
```

映射表在 [ReminderService.ets](entry/src/main/ets/service/ReminderService.ets#L14-L48)，测试在 [ReminderService.test.ets](entry/src/test/ReminderService.test.ets#L444-L472)。

未识别的异常仍然返回 `TRIGGER_REGISTRATION_ERROR`（可重试），保持向后兼容。

## 四、UI 处理建议

```ts
switch (error.code) {
  case 'LOCATION_PERMISSION_DENIED':
    // 按钮：去设置（不要放重试）
    break;
  case 'LOCATION_SWITCH_OFF':
    // 按钮：去设置；回到应用后自动重试一次
    break;
  case 'LOCATION_WGS84_FENCE_UNSUPPORTED':
    // 提示：此设备不支持地点提醒，可改用时间提醒
    break;
  case 'LOCATION_NOT_STARTED':
  case 'LOCATION_FENCE_REGISTRATION_FAILED':
  case 'TRIGGER_REGISTRATION_ERROR':
    // 按钮：重试
    break;
  default:
    // 按 error.retryable 决定是否显示重试
}
```

原则：**`retryable: false` 就绝不提供“重试”按钮**，否则用户会陷入反复失败。

## 五、其余相关错误码（附带）

| 错误码 | 含义 | 可重试 |
| --- | --- | --- |
| `LOCATION_INVALID_REGISTRATION` | 提醒数据不满足地点注册条件（缺 sceneId、状态不对等） | 否 |
| `LOCATION_UNREGISTER_BEFORE_REPLACE` | 同一提醒换场景重建时未先注销 | 否（先删除再建） |
| `LOCATION_FIX_UNUSABLE` | 当前位置过期/精度不够 | 是 |
| `LOCATION_FIX_UNCERTAIN` | 当前位置离边界太近，无法判定 | 是（换个位置再试） |
| `LOCATION_STOP_CLEANUP_FAILED` | 停止服务时清理围栏失败 | 是 |
| `LOCATION_REMINDER_NOT_COMMITTED` | 事件到达时提醒还没保存完 | 内部码，用户不可见 |
| `SCENE_NOT_FOUND` | 场景已被删除 | 否（重新选择） |

## 六、验证

```text
Tests run: 177, Failure: 0, Error: 0, Pass: 177
```

新增用例 `surfaces stable location registration codes with retry guidance` 覆盖了权限拒绝、定位关闭、围栏注册失败、设备不支持四种情况，断言错误码与 `retryable` 都正确。
