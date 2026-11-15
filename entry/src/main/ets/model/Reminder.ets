import {
  LocationTriggerMode,
  ReminderSource,
  ReminderStatus,
  TriggerType
} from './ReminderEnums';

export interface Reminder {
  id: string;
  content: string;
  triggerType: TriggerType;
  triggerTime?: number;
  sceneId?: string;
  sceneName?: string;
  locationTriggerMode?: LocationTriggerMode;
  status: ReminderStatus;
  source: ReminderSource;
  createdAt: number;
  triggeredAt?: number;
  completedAt?: number;
}
