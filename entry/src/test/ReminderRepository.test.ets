import { describe, it, expect } from '@ohos/hypium';
import { InMemoryReminderRepository } from '../main/ets/repository/InMemoryReminderRepository';
import { Reminder } from '../main/ets/model/Reminder';
import { ReminderSource, ReminderStatus, TriggerType } from '../main/ets/model/ReminderEnums';

function sampleReminder(): Reminder {
  return {
    id: 'r-1', content: '带电脑', triggerType: TriggerType.TIME,
    triggerTime: 2000, status: ReminderStatus.ACTIVE,
    source: ReminderSource.MANUAL, createdAt: 1000
  };
}

export default function reminderRepositoryTest() {
  describe('reminderRepositoryTest', () => {
    it('inserts and upserts without duplicating a reminder', 0, async () => {
      const repository = new InMemoryReminderRepository();
      const reminder = sampleReminder();
      await repository.save(reminder);
      reminder.content = '带充电器';
      await repository.save(reminder);
      const all = await repository.findAll();
      expect(all.length).assertEqual(1);
      expect(all[0].content).assertEqual('带充电器');
    });

    it('returns undefined for a missing id and reports deletion truthfully', 0, async () => {
      const repository = new InMemoryReminderRepository();
      expect(await repository.findById('missing')).assertUndefined();
      expect(await repository.deleteById('missing')).assertFalse();
      await repository.save(sampleReminder());
      expect(await repository.deleteById('r-1')).assertTrue();
      expect(await repository.findById('r-1')).assertUndefined();
      expect((await repository.findAll()).length).assertEqual(0);
    });

    it('requires save before mutations of original or returned objects take effect', 0, async () => {
      const repository = new InMemoryReminderRepository();
      const original = sampleReminder();
      await repository.save(original);
      original.content = 'mutated original';
      expect((await repository.findById('r-1'))?.content).assertEqual('带电脑');
      const found = await repository.findById('r-1');
      if (found !== undefined) {
        found.content = 'mutated read';
      }
      expect((await repository.findById('r-1'))?.content).assertEqual('带电脑');
      const listed = await repository.findAll();
      listed[0].content = 'mutated list';
      expect((await repository.findById('r-1'))?.content).assertEqual('带电脑');
    });
  });
}
