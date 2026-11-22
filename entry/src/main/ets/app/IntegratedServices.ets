import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
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
import { FENCE_EXTENSION_ABILITY_NAME } from '../location/platform/LocationPlatform';
import { createFileFenceRegistry } from '../location/repository/FenceRegistryStore';
import { ReminderService } from '../service/ReminderService';
import { createSystemNotificationPort, createSystemTimePort } from '../reminder/adapter/SystemAdapters';
import { TimeTriggerPort } from '../reminder/contract/TimeTriggerPort';
import { LocationTriggerPort } from '../reminder/contract/LocationTriggerPort';
import { AppServices, AppRuntimeMode, createAppServices } from './AppServices';
import { getAppServices } from './AppServiceRegistry';
import { buildDevFixtures } from './DevelopmentServices';

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
  // Durable fenceId <-> reminderId registry, shared with the fence extension process.
  const fenceRegistry = createFileFenceRegistry(context.filesDir);
  // 新进程启动时只清理"没有持久映射"的孤儿围栏；有映射的围栏保留给围栏扩展投递。
  platform.recoverOrphanFences(fenceRegistry).catch((): void => {});

  let locationAdapter: LocationReminderAdapter | undefined = undefined;

  const aiProvider = config === undefined
    ? new FakeAIModelProvider(buildDevFixtures())
    : new ZhipuAIModelProvider(config, new OhosAIChatClient());

  const services = createAppServices({
    mode: AppRuntimeMode.INTEGRATED,
    repository: new InMemoryReminderRepository(),
    timetableRepository: new InMemoryTimetableRepository(),
    createTimePort: (sink): TimeTriggerPort => createSystemTimePort(sink),
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
  return services;
}

async function reconcileFences(adapter: LocationReminderAdapter, service: ReminderService): Promise<void> {
  const all = await service.findAll();
  if (!all.success || all.data === undefined) { return; }
  await adapter.reconcile(all.data);
}
