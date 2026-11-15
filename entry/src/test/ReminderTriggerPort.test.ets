import { describe, it, expect } from '@ohos/hypium';
import { Reminder } from '../main/ets/model/Reminder';
import { ReminderSource, ReminderStatus, TriggerType } from '../main/ets/model/ReminderEnums';
import { TimeTriggerPort } from '../main/ets/reminder/contract/TimeTriggerPort';
import { LocationTriggerPort } from '../main/ets/reminder/contract/LocationTriggerPort';

class TestTimePort implements TimeTriggerPort {
  scheduled?: Reminder;
  cancelledId?: string;

  async schedule(reminder: Reminder): Promise<void> {
    this.scheduled = reminder;
  }

  async cancel(reminderId: string): Promise<void> {
    this.cancelledId = reminderId;
  }
}

class TestLocationPort implements LocationTriggerPort {
  registered?: Reminder;
  unregisteredId?: string;
  queriedSceneId?: string;

  async register(reminder: Reminder): Promise<void> {
    this.registered = reminder;
  }

  async unregister(reminderId: string): Promise<void> {
    this.unregisteredId = reminderId;
  }

  async isInsideScene(sceneId: string): Promise<boolean> {
    this.queriedSceneId = sceneId;
    return sceneId === 'scene-1';
  }
}

export default function reminderTriggerPortTest() {
  describe('reminderTriggerPortTest', () => {
    it('keeps trigger adapter contracts independent from HarmonyOS APIs', 0, async () => {
      const reminder: Reminder = {
        id: 'r-1', content: '带电脑', triggerType: TriggerType.BOTH,
        triggerTime: 2000, sceneId: 'scene-1', status: ReminderStatus.ACTIVE,
        source: ReminderSource.MANUAL, createdAt: 1000
      };
      const time: TimeTriggerPort = new TestTimePort();
      const location: LocationTriggerPort = new TestLocationPort();
      await time.schedule(reminder);
      await location.register(reminder);
      expect((time as TestTimePort).scheduled?.id).assertEqual('r-1');
      expect((location as TestLocationPort).registered?.sceneId).assertEqual('scene-1');
      expect(await location.isInsideScene('scene-1')).assertTrue();
      await time.cancel('r-1');
      await location.unregister('r-1');
      expect((time as TestTimePort).cancelledId).assertEqual('r-1');
      expect((location as TestLocationPort).unregisteredId).assertEqual('r-1');
    });
  });
}
