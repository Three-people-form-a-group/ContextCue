import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AIProviderConfig } from '../ai/provider/AIProviderConfig';
import { FakeAIModelProvider } from '../ai/provider/FakeAIModelProvider';
import { OhosAIChatClient } from '../ai/provider/OhosAIChatClient';
import { ZhipuAIModelProvider } from '../ai/provider/ZhipuAIModelProvider';
import { createFileReminderRepository } from '../repository/FileReminderRepository';
import { InMemoryTimetableRepository } from '../timetable/repository/InMemoryTimetableRepository';
import { ReminderStatus, TriggerType } from '../model/ReminderEnums';
import { ReminderService } from '../service/ReminderService';
import { CreateReminderInput } from '../model/CreateReminderInput';
import { SceneCatalog } from '../location/scene/SceneCatalog';
import { LocationSceneService } from '../location/scene/LocationSceneService';
import { createPreferencesSceneStorage } from '../location/repository/PreferencesSceneStorage';
import { HarmonyLocationPlatform } from '../location/platform/HarmonyLocationPlatform';
import { HarmonyPermissionGateway, LocationPermissionManager } from '../location/platform/LocationPermissionManager';
import { LocationReminderAdapter } from '../location/trigger/LocationReminderAdapter';
import { createSystemNotificationPort, createSystemTimePort } from '../reminder/adapter/SystemAdapters';
import { ReminderAgentTimePort } from '../reminder/adapter/ReminderAgentTimePort';
import { NotifyPref } from '../common/NotifyPref';
import { TimeTriggerPort } from '../reminder/contract/TimeTriggerPort';
import { LocationTriggerPort } from '../reminder/contract/LocationTriggerPort';
import { AppServices, AppRuntimeMode, createAppServices } from './AppServices';
import { getAppServices } from './AppServiceRegistry';
import { buildDevFixtures } from './DevelopmentServices';

/**
 * 正式组装（INTEGRATED）：罗鸿程的系统时间/通知端口 + 兰铮的定位适配器与场景目录。
 * 提醒仓储已切到沙箱文件（主进程与围栏扩展共用），课表仓储仍为内存实现。
 * 凭证经本地配置注入（见《真实AI接入准备》），缺失时 AI 仍为 Fake。
 */
export function createIntegratedServices(config: AIProviderConfig | undefined,
  context: common.UIAbilityContext): AppServices {
  const now = (): number => Date.now();
  let sequence: number = 0;
  const newId = (): string => 'app-' + Date.now().toString() + '-' + (++sequence).toString();
  // 启动对账会补排 ACTIVE 的时间提醒；必须先同步载入用户开关，否则会误排已关闭的提醒
  NotifyPref.loadSync(context);

  const catalog = new SceneCatalog(createPreferencesSceneStorage(context), now, newId,
    async (sceneId: string): Promise<boolean> => {
      const all = await getAppServices().reminderService.findAll();
      if (!all.success || all.data === undefined) { return false; }
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
  const sceneService = new LocationSceneService(catalog, platform, permissionManager);
  // 新进程启动时清理上次运行遗留的系统围栏，随后由下面的 reconcileLocationReminders 重新注册。
  const recovered = platform.recoverOrphanFences().catch((): void => {});

  const aiProvider = config === undefined
    ? new FakeAIModelProvider(buildDevFixtures())
    : new ZhipuAIModelProvider(config, new OhosAIChatClient());

  // 用数组持有组合根创建出来的端口实例，供启动对账使用
  const timePorts: ReminderAgentTimePort[] = [];
  const services = createAppServices({
    mode: AppRuntimeMode.INTEGRATED,
    // 沙箱文件仓储：主进程与围栏扩展共用同一路径，进程重启后提醒仍在
    repository: createFileReminderRepository(context.filesDir),
    timetableRepository: new InMemoryTimetableRepository(),
    createTimePort: (sink): TimeTriggerPort => {
      const port = createSystemTimePort(sink);
      timePorts.push(port);
      return port;
    },
    createLocationPort: (sink): LocationTriggerPort => new LocationReminderAdapter(catalog, platform, sink, now,
      (code: string): void => { console.error('LocationAdapter error: ' + code); },
      async (expected): Promise<boolean> => {
        const current = await getAppServices().reminderService.findById(expected.id);
        return current.success && current.data !== undefined && current.data.status === ReminderStatus.ACTIVE;
      }),
    notificationPort: createSystemNotificationPort(),
    sceneResolver: catalog,
    sceneService: sceneService,
    aiProvider: aiProvider,
    now: now,
    newId: newId
  });
  hilog.info(0x0000, 'ContextCue', 'AI provider: %{public}s',
    config === undefined ? 'Fake(dev fixtures)' : 'Zhipu(GLM)');
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
  // 围栏在进程切换时会被清掉；持久化后提醒还在，必须把 ACTIVE 的地点提醒重新注册。
  // 注意：兰铮 V2 的 adapter.reconcile 落地后应替换这一段。
  recovered.then(async (): Promise<void> => {
    await reconcileLocationReminders(services.reminderService);
  }).catch((error: Object): void => {
    console.error('Location reconcile error: ' + String(error));
  });
  return services;
}

async function reconcileLocationReminders(service: ReminderService): Promise<void> {
  const all = await service.findAll();
  if (!all.success || all.data === undefined) {
    return;
  }
  for (let i = 0; i < all.data.length; i++) {
    const reminder = all.data[i];
    if (reminder.status !== ReminderStatus.ACTIVE ||
      (reminder.triggerType !== TriggerType.LOCATION && reminder.triggerType !== TriggerType.BOTH) ||
      reminder.sceneId === undefined || reminder.sceneId.trim() === '') {
      continue;
    }
    const input: CreateReminderInput = {
      content: reminder.content,
      triggerType: reminder.triggerType,
      triggerTime: reminder.triggerTime,
      sceneId: reminder.sceneId,
      sceneName: reminder.sceneName,
      locationTriggerMode: reminder.locationTriggerMode,
      source: reminder.source
    };
    const result = await service.update(reminder.id, input);
    if (!result.success) {
      // 权限/设备能力问题由用户下次进入编辑页时再处理，启动阶段不打断
      console.error('Location reminder re-register failed: ' +
        (result.error === undefined ? 'UNKNOWN' : result.error.code));
    }
  }
}
