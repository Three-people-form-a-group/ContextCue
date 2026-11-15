import { FakeAIModelProvider } from '../ai/provider/FakeAIModelProvider';
import { AIProviderConfig } from '../ai/provider/AIProviderConfig';
import { OhosAIChatClient } from '../ai/provider/OhosAIChatClient';
import { ZhipuAIModelProvider } from '../ai/provider/ZhipuAIModelProvider';
import { Reminder } from '../model/Reminder';
import { InMemoryReminderRepository } from '../repository/InMemoryReminderRepository';
import { InMemoryTimetableRepository } from '../timetable/repository/InMemoryTimetableRepository';
import { TimeTriggerPort } from '../reminder/contract/TimeTriggerPort';
import { LocationTriggerPort } from '../reminder/contract/LocationTriggerPort';
import { ReminderNotificationPort } from '../reminder/contract/ReminderNotificationPort';
import { SceneResolver, SceneResolveResult, SceneResolveStatus } from '../reminder/contract/SceneResolver';
import { TriggerEventSink } from '../reminder/contract/TriggerEventSink';
import { AppServices, AppRuntimeMode, createAppServices } from './AppServices';

// Development-only no-op registration: supports page CRUD, never schedules a system reminder.
class DevelopmentTimePort implements TimeTriggerPort {
  async schedule(_reminder: Reminder): Promise<void> {}
  async cancel(_id: string): Promise<void> {}
}

class DevelopmentLocationPort implements LocationTriggerPort, SceneResolver {
  async register(_reminder: Reminder): Promise<void> {}
  async unregister(_id: string): Promise<void> {}
  async isInsideScene(_sceneId: string): Promise<boolean> { return false; }
  async resolveByName(_sceneName: string): Promise<SceneResolveResult> {
    return { status: SceneResolveStatus.NOT_FOUND, candidates: [] };
  }
}

class UnavailableNotificationPort implements ReminderNotificationPort {
  async notify(_reminder: Reminder): Promise<void> {
    // Never claim a real notification was delivered by a placeholder.
    throw new Error('SYSTEM_NOTIFICATION_NOT_CONNECTED');
  }
}

/**
 * Development composition: volatile data, no triggers/notifications.
 * config 提供时注入阶段性真实 Provider（智谱 GLM）；缺省保持 Fake。
 */
export function createDevelopmentServices(config?: AIProviderConfig): AppServices {
  const location = new DevelopmentLocationPort();
  let sequence = 0;
  return createAppServices({
    mode: AppRuntimeMode.DEVELOPMENT,
    repository: new InMemoryReminderRepository(),
    timetableRepository: new InMemoryTimetableRepository(),
    createTimePort: (_sink: TriggerEventSink): TimeTriggerPort => new DevelopmentTimePort(),
    createLocationPort: (_sink: TriggerEventSink): LocationTriggerPort => location,
    notificationPort: new UnavailableNotificationPort(),
    sceneResolver: location,
    // No canned interpretation of arbitrary input. Unknown input returns a non-retryable provider error.
    aiProvider: config === undefined
      ? new FakeAIModelProvider(new Map<string, string>())
      : new ZhipuAIModelProvider(config, new OhosAIChatClient()),
    now: () => Date.now(),
    newId: () => 'dev-' + Date.now().toString() + '-' + (++sequence).toString()
  });
}
