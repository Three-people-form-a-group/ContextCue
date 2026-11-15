import { common } from '@kit.AbilityKit';
import { AIProviderConfig } from '../ai/provider/AIProviderConfig';
import { FakeAIModelProvider } from '../ai/provider/FakeAIModelProvider';
import { OhosAIChatClient } from '../ai/provider/OhosAIChatClient';
import { ZhipuAIModelProvider } from '../ai/provider/ZhipuAIModelProvider';
import { InMemoryReminderRepository } from '../repository/InMemoryReminderRepository';
import { InMemoryTimetableRepository } from '../timetable/repository/InMemoryTimetableRepository';
import { ReminderStatus } from '../model/ReminderEnums';
import { SceneCatalog } from '../location/scene/SceneCatalog';
import { createPreferencesSceneStorage } from '../location/repository/PreferencesSceneStorage';
import { HarmonyLocationPlatform } from '../location/platform/HarmonyLocationPlatform';
import { HarmonyPermissionGateway, LocationPermissionManager } from '../location/platform/LocationPermissionManager';
import { LocationReminderAdapter } from '../location/trigger/LocationReminderAdapter';
import { createSystemNotificationPort, createSystemTimePort } from '../reminder/adapter/SystemAdapters';
import { TimeTriggerPort } from '../reminder/contract/TimeTriggerPort';
import { LocationTriggerPort } from '../reminder/contract/LocationTriggerPort';
import { AppServices, AppRuntimeMode, createAppServices } from './AppServices';
import { getAppServices } from './AppServiceRegistry';

/**
 * 正式组装（INTEGRATED）：罗鸿程的系统时间/通知端口 + 兰铮的定位适配器与场景目录。
 * 由组长在整合阶段切换；仓储仍为内存实现（持久化另行接入）。
 * 凭证经本地配置注入（见《真实AI接入准备》），缺失时 AI 仍为 Fake。
 */
export function createIntegratedServices(config: AIProviderConfig | undefined,
  context: common.UIAbilityContext): AppServices {
  const now = (): number => Date.now();
  let sequence: number = 0;
  const newId = (): string => 'app-' + Date.now().toString() + '-' + (++sequence).toString();

  const catalog = new SceneCatalog(createPreferencesSceneStorage(context), now, newId,
    async (sceneId: string): Promise<boolean> => {
      const all = await getAppServices().reminderService.findAll();
      if (!all.success || all.data === undefined) { return false; }
      let found: boolean = false;
      for (let i = 0; i < all.data.length; i++) {
        if (all.data[i].sceneId === sceneId) { found = true; break; }
      }
      return found;
    });
  const permissionManager = new LocationPermissionManager(new HarmonyPermissionGateway(context));
  const platform = new HarmonyLocationPlatform(permissionManager);
  // 新进程启动时清理上次运行遗留的系统围栏（兰铮适配器的约定：仅在干净进程调用一次）
  platform.recoverOrphanFences().catch((): void => {});

  const aiProvider = config === undefined
    ? new FakeAIModelProvider(new Map<string, string>())
    : new ZhipuAIModelProvider(config, new OhosAIChatClient());

  return createAppServices({
    mode: AppRuntimeMode.INTEGRATED,
    repository: new InMemoryReminderRepository(),
    timetableRepository: new InMemoryTimetableRepository(),
    createTimePort: (sink): TimeTriggerPort => createSystemTimePort(sink),
    createLocationPort: (sink): LocationTriggerPort => new LocationReminderAdapter(catalog, platform, sink, now,
      (code: string): void => { console.error('LocationAdapter error: ' + code); },
      async (expected): Promise<boolean> => {
        const current = await getAppServices().reminderService.findById(expected.id);
        return current.success && current.data !== undefined && current.data.status === ReminderStatus.ACTIVE;
      }),
    notificationPort: createSystemNotificationPort(),
    sceneResolver: catalog,
    aiProvider: aiProvider,
    now: now,
    newId: newId
  });
}
