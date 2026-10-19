import { describe, it, expect } from '@ohos/hypium';
import { AIParsedReminder } from '../main/ets/ai/model/AIParsedReminder';
import { mapAIParsedReminder } from '../main/ets/ai/mapper/ReminderMapper';
import { LocationTriggerMode, ReminderSource, TriggerType } from '../main/ets/model/ReminderEnums';
import { SceneCandidate } from '../main/ets/reminder/contract/SceneResolver';

export default function reminderMapperTest() {
  describe('reminderMapperTest', () => {
    it('maps time to shared AI creation input without scene fields', 0, () => {
      const parsed: AIParsedReminder = { content: ' 带电脑 ', triggerType: 'TIME', triggerTime: 2000, sceneName: null, ambiguous: false };
      const draft = mapAIParsedReminder(parsed);
      expect(draft.content).assertEqual('带电脑');
      expect(draft.triggerType).assertEqual(TriggerType.TIME);
      expect(draft.source).assertEqual(ReminderSource.AI);
      expect(draft.sceneId).assertUndefined();
    });
    it('maps resolved location to stable scene ID and ENTER', 0, () => {
      const parsed: AIParsedReminder = { content: '带电脑', triggerType: 'BOTH', triggerTime: 2000, sceneName: '实验室', ambiguous: false };
      const scene: SceneCandidate = { id: 'lab-1', name: '实验室' };
      const draft = mapAIParsedReminder(parsed, scene);
      expect(draft.triggerType).assertEqual(TriggerType.BOTH);
      expect(draft.sceneId).assertEqual('lab-1');
      expect(draft.sceneName).assertEqual('实验室');
      expect(draft.locationTriggerMode).assertEqual(LocationTriggerMode.ENTER);
    });
  });
}
