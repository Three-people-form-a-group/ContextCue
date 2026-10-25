import { FakeAIModelProvider } from '../ai/provider/FakeAIModelProvider';
import { Reminder } from '../model/Reminder';
import { InMemoryReminderRepository } from '../repository/InMemoryReminderRepository';
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

/** Explicit development composition: volatile data, no triggers/notifications, no real AI. */
export function createDevelopmentServices(): AppServices {
  const location = new DevelopmentLocationPort();
  let sequence = 0;
  return createAppServices({
    mode: AppRuntimeMode.DEVELOPMENT,
    repository: new InMemoryReminderRepository(),
    createTimePort: (_sink: TriggerEventSink): TimeTriggerPort => new DevelopmentTimePort(),
    createLocationPort: (_sink: TriggerEventSink): LocationTriggerPort => location,
    notificationPort: new UnavailableNotificationPort(),
    sceneResolver: location,
    // No canned interpretation of arbitrary input. Unknown input returns a non-retryable provider error.
    aiProvider: new FakeAIModelProvider(new Map<string, string>()),
    now: () => Date.now(),
    newId: () => 'dev-' + Date.now().toString() + '-' + (++sequence).toString()
  });
}
