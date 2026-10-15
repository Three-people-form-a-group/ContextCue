import {
  LocationTriggerMode,
  ReminderSource,
  TriggerType
} from './ReminderEnums';

export interface CreateReminderInput {
  content: string;
  triggerType: TriggerType;
  triggerTime?: number;
  sceneId?: string;
  sceneName?: string;
  locationTriggerMode?: LocationTriggerMode;
  source: ReminderSource;
}
