import { Reminder } from '../../model/Reminder';

export interface LocationTriggerPort {
  register(reminder: Reminder): Promise<void>;
  unregister(reminderId: string): Promise<void>;
  isInsideScene(sceneId: string): Promise<boolean>;
}
