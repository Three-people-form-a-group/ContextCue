import { AIService } from '../ai/contract/AIService';
import { DefaultAIService } from '../ai/DefaultAIService';
import { AIModelProvider } from '../ai/provider/AIModelProvider';
import { ReminderRepository } from '../repository/ReminderRepository';
import { ReminderService } from '../service/ReminderService';
import { TriggerCoordinator } from '../reminder/TriggerCoordinator';
import { TimeTriggerPort } from '../reminder/contract/TimeTriggerPort';
import { LocationTriggerPort } from '../reminder/contract/LocationTriggerPort';
import { ReminderNotificationPort } from '../reminder/contract/ReminderNotificationPort';
import { SceneResolver } from '../reminder/contract/SceneResolver';
import { LocationSceneService } from '../location/scene/LocationSceneService';
import { TriggerConditionEvent } from '../reminder/contract/TriggerConditionEvent';
import { TriggerEventSink } from '../reminder/contract/TriggerEventSink';
import { TimetableService } from '../timetable/TimetableService';
import { TimetableRepository } from '../timetable/repository/TimetableRepository';

export enum AppRuntimeMode {
  DEVELOPMENT = 'DEVELOPMENT',
  // Means dependencies are supplied by the integration entry, not that device acceptance has passed.
  INTEGRATED = 'INTEGRATED'
}

/** Page-facing services. Repository and trigger internals are deliberately not exposed here. */
export interface AppServices {
  readonly reminderService: ReminderService;
  readonly aiService: AIService;
  readonly timetableService: TimetableService;
  /** 场景列表与定位授权；开发组合没有真实定位能力，因此缺省。 */
  readonly sceneService?: LocationSceneService;
  readonly mode: AppRuntimeMode;
}

/** Integration-only configuration. Adapter factories must not emit events during construction. */
export interface AppServiceDependencies {
  mode: AppRuntimeMode;
  repository: ReminderRepository;
  timetableRepository: TimetableRepository;
  createTimePort: (sink: TriggerEventSink) => TimeTriggerPort;
  createLocationPort: (sink: TriggerEventSink) => LocationTriggerPort;
  notificationPort: ReminderNotificationPort;
  sceneResolver: SceneResolver;
  sceneService?: LocationSceneService;
  aiProvider: AIModelProvider;
  now: () => number;
  newId: () => string;
}

// Breaks the adapter -> coordinator -> service -> adapter construction cycle.
class CoordinatorEventRelay implements TriggerEventSink {
  private target?: TriggerEventSink;

  bind(target: TriggerEventSink): void { this.target = target; }

  async onConditionChanged(event: TriggerConditionEvent): Promise<void> {
    if (this.target === undefined) {
      throw new Error('APP_SERVICES_NOT_READY');
    }
    await this.target.onConditionChanged(event);
  }
}

export function createAppServices(dependencies: AppServiceDependencies): AppServices {
  const events = new CoordinatorEventRelay();
  const timePort = dependencies.createTimePort(events);
  const locationPort = dependencies.createLocationPort(events);
  const service = new ReminderService(dependencies.repository, timePort, locationPort,
    dependencies.now, dependencies.newId);
  const timetableService = new TimetableService(dependencies.timetableRepository, service, dependencies.now);
  const coordinator = new TriggerCoordinator(service, locationPort, dependencies.notificationPort, dependencies.now);
  const aiService = new DefaultAIService(dependencies.aiProvider, dependencies.sceneResolver);
  events.bind(coordinator);
  return {
    reminderService: service,
    aiService: aiService,
    timetableService: timetableService,
    sceneService: dependencies.sceneService,
    mode: dependencies.mode
  };
}
