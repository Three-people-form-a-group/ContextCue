import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AIProviderConfig } from '../ai/provider/AIProviderConfig';
import { FakeAIModelProvider } from '../ai/provider/FakeAIModelProvider';
import { OhosAIChatClient } from '../ai/provider/OhosAIChatClient';
import { ZhipuAIModelProvider } from '../ai/provider/ZhipuAIModelProvider';
import { buildDevFixtures } from './DevelopmentServices';
import { createFileReminderRepository } from '../repository/FileReminderRepository';
import { createFileTimetableRepository } from '../timetable/repository/FileTimetableRepository';
import { ReminderStatus, TriggerType } from '../model/ReminderEnums';
import { ReminderService } from '../service/ReminderService';
import { CreateReminderInput } from '../model/CreateReminderInput';
import { Reminder } from '../model/Reminder';
import { SceneCatalog } from '../location/scene/SceneCatalog';
import { LocationSceneService } from '../location/scene/LocationSceneService';
import { createPreferencesSceneStorage } from '../location/repository/PreferencesSceneStorage';
import { HarmonyLocationPlatform } from '../location/platform/HarmonyLocationPlatform';
import { HarmonyPermissionGateway, LocationPermissionManager } from '../location/platform/LocationPermissionManager';
import { LocationReminderAdapter } from '../location/trigger/LocationReminderAdapter';
import { FENCE_EXTENSION_ABILITY_NAME } from '../location/platform/LocationPlatform';
import { createFileFenceRegistry } from '../location/repository/FenceRegistryStore';
import { createSystemNotificationPort, createSystemTimePort } from '../reminder/adapter/SystemAdapters';
import { ReminderAgentTimePort } from '../reminder/adapter/ReminderAgentTimePort';
import { NotifyPref } from '../common/NotifyPref';
import { TimeTriggerPort } from '../reminder/contract/TimeTriggerPort';
import { LocationTriggerPort } from '../reminder/contract/LocationTriggerPort';
import { AppServices, AppRuntimeMode, createAppServices } from './AppServices';
import { getAppServices } from './AppServiceRegistry';

/**
 * 正式组装（INTEGRATED）：罗鸿程的系统时间/通知端口、提醒与课表的文件持久化仓储、
 * 场景规则、几何传播与 LocationSceneService + 兰铮的定位适配器、场景目录与
 * V2 围栏扩展注册表。凭证经本地配置注入（见《真实AI接入准备》），缺失时 AI 仍为 Fake（开发样例可联调）。
 */

/** 回前台对账的当前实现；仅 INTEGRATED 组装时设置，开发模式保持 undefined。 */
let foregroundReconcile: (() => Promise<void>) | undefined = undefined;

/**
 * 回前台对账（EntryAbility.onForeground 调用）：用户可能刚在系统设置里打开通知授权，
 * 或定位/围栏状态有变化。把 ACTIVE 提醒的触发器与系统侧对齐：补排缺失、清理无效。
 * 投递分离后，注册失败入库的提醒也靠这里补排。失败仅记日志，下次回前台重试。
 */
export function reconcileOnAppForeground(): void {
  const reconcile = foregroundReconcile;
  if (reconcile === undefined) { return; }
  reconcile().catch((error: Object): void => {
    console.error('Foreground reconcile error: ' + String(error));
  });
}

export function createIntegratedServices(config: AIProviderConfig | undefined,
  context: common.UIAbilityContext): AppServices {
  const now = (): number => Date.now();
  let sequence: number = 0;
  const newId = (): string => 'app-' + Date.now().toString() + '-' + (++sequence).toString();

  const catalog = new SceneCatalog(createPreferencesSceneStorage(context), now, newId,
    async (sceneId: string): Promise<boolean> => {
      const all = await getAppServices().reminderService.findAll();
      // 读不到引用关系时按"仍被引用"处理，宁可拒绝改名/删除，也不要留下悬空围栏
      if (!all.success || all.data === undefined) { return true; }
      let found: boolean = false;
      for (let i = 0; i < all.data.length; i++) {
        const reminder = all.data[i];
        // 已完成/已触发的提醒不再占用场景：场景可以改名或删除，
        // 取消完成时由用户重新选择地点（编辑页会先显示原来的名称）。
        if (reminder.sceneId === sceneId &&
          (reminder.status === ReminderStatus.ACTIVE || reminder.status === ReminderStatus.DISABLED)) {
          found = true;
          break;
        }
      }
      return found;
    });
  const permissionManager = new LocationPermissionManager(new HarmonyPermissionGateway(context));
  const platform = new HarmonyLocationPlatform(permissionManager);
  // Durable fenceId <-> reminderId registry, shared with the fence extension process.
  const fenceRegistry = createFileFenceRegistry(context.filesDir);
  const sceneService = new LocationSceneService(catalog, platform, permissionManager,
    async (sceneId: string, sceneName: string): Promise<void> => {
      await getAppServices().reminderService.renameSceneReminders(sceneId, sceneName);
    });
  // 新进程启动时只清理"没有持久映射"的孤儿围栏；有映射的围栏保留给围栏扩展投递。
  platform.recoverOrphanFences(fenceRegistry).catch((): void => {});

  let locationAdapter: LocationReminderAdapter | undefined = undefined;

  const aiProvider = config === undefined
    ? new FakeAIModelProvider(buildDevFixtures())
    : new ZhipuAIModelProvider(config, new OhosAIChatClient());

  // 用数组持有组合根创建出来的端口实例，供启动对账使用
  const timePorts: ReminderAgentTimePort[] = [];
  const services = createAppServices({
    mode: AppRuntimeMode.INTEGRATED,
    // 沙箱文件仓储：主进程与围栏扩展共用同一路径，进程重启后提醒仍在
    repository: createFileReminderRepository(context.filesDir),
    // 课表与“课表→提醒”台账放在同一份文件里，重启后仍能级联删除/避免重复生成
    timetableRepository: createFileTimetableRepository(context.filesDir),
    createTimePort: (sink): TimeTriggerPort => {
      const port = createSystemTimePort(sink);
      timePorts.push(port);
      return port;
    },
    createLocationPort: (sink): LocationTriggerPort => {
      const adapter = new LocationReminderAdapter(catalog, platform, sink, now,
        (code: string): void => { console.error('LocationAdapter error: ' + code); },
        async (expected): Promise<boolean> => {
          const current = await getAppServices().reminderService.findById(expected.id);
          return current.success && current.data !== undefined && current.data.status === ReminderStatus.ACTIVE;
        }, fenceRegistry, { fenceExtensionAbilityName: FENCE_EXTENSION_ABILITY_NAME });
      locationAdapter = adapter;
      return adapter;
    },
    notificationPort: createSystemNotificationPort(),
    sceneResolver: catalog,
    sceneService: sceneService,
    aiProvider: aiProvider,
    now: now,
    newId: newId
  });
  hilog.info(0x0000, 'ContextCue', 'AI provider: %{public}s',
    config === undefined ? 'Fake(dev fixtures)' : 'Zhipu(GLM)');

  const adapter = locationAdapter;
  if (adapter !== undefined) {
    // Startup accounting: keep fences whose reminder is still an ACTIVE location reminder, drop the
    // rest, and restore fences whose mapping was lost. Best effort; the next start retries.
    reconcileFences(adapter, services.reminderService).catch((error: Object): void => {
      console.error('Location reconcile error: ' + String(error));
    });
  }
  // 场景半径/坐标变化后，把该场景下 ACTIVE 的地点提醒重新注册到新围栏
  sceneService.setGeometrySync(async (sceneId: string): Promise<boolean> => {
    return await syncActiveLocationRemindersForScene(services.reminderService, sceneId);
  });
  const port: ReminderAgentTimePort | undefined = timePorts.length > 0 ? timePorts[0] : undefined;
  if (port !== undefined) {
    // 启动对账：取消无效/重复的系统时间提醒，补排 ACTIVE，并恢复业务 id → 系统 id 的映射。
    // 列表为空（内存仓储刚重启）时只保留系统排期，不清理孤儿，见 ReminderAgentTimePort.reconcile。
    services.reminderService.findAll().then(async (all) => {
      if (all.success && all.data !== undefined) {
        await port.reconcile(all.data);
      }
    }).catch((error: Object): void => {
      console.error('Time reconcile error: ' + String(error));
    });
  }
  foregroundReconcile = async (): Promise<void> => {
    const current = getAppServices();
    if (current === undefined) { return; }
    const all = await current.reminderService.findAll();
    if (!all.success || all.data === undefined) { return; }
    const reconcileAdapter = locationAdapter;
    if (reconcileAdapter !== undefined) {
      await reconcileAdapter.reconcile(all.data);
    }
    const reconcilePort = timePorts.length > 0 ? timePorts[0] : undefined;
    if (reconcilePort !== undefined) {
      await reconcilePort.reconcile(all.data);
    }
  };
  return services;
}

function reminderInput(reminder: Reminder): CreateReminderInput {
  return {
    content: reminder.content,
    triggerType: reminder.triggerType,
    triggerTime: reminder.triggerTime,
    sceneId: reminder.sceneId,
    sceneName: reminder.sceneName,
    locationTriggerMode: reminder.locationTriggerMode,
    source: reminder.source
  };
}

function isActiveLocationReminder(reminder: Reminder): boolean {
  return reminder.status === ReminderStatus.ACTIVE &&
    (reminder.triggerType === TriggerType.LOCATION || reminder.triggerType === TriggerType.BOTH) &&
    reminder.sceneId !== undefined && reminder.sceneId.trim() !== '';
}

async function reconcileFences(adapter: LocationReminderAdapter, service: ReminderService): Promise<void> {
  const all = await service.findAll();
  if (!all.success || all.data === undefined) { return; }
  await adapter.reconcile(all.data);
}
async function syncActiveLocationRemindersForScene(service: ReminderService, sceneId: string): Promise<boolean> {
  const all = await service.findAll();
  if (!all.success || all.data === undefined) {
    return false;
  }
  let synced: boolean = true;
  for (let i = 0; i < all.data.length; i++) {
    const reminder = all.data[i];
    if (!isActiveLocationReminder(reminder) || reminder.sceneId !== sceneId) {
      continue;
    }
    const result = await service.update(reminder.id, reminderInput(reminder));
    if (!result.success) {
      synced = false;
      console.error('Scene geometry sync failed: ' +
        (result.error === undefined ? 'UNKNOWN' : result.error.code));
    }
  }
  return synced;
}

