import { AIParsedReminder } from '../model/AIParsedReminder';
import { CreateReminderInput } from '../../model/CreateReminderInput';
import { LocationTriggerMode, ReminderSource, TriggerType } from '../../model/ReminderEnums';
import { SceneCandidate } from '../../reminder/contract/SceneResolver';

export function mapAIParsedReminder(parsed: AIParsedReminder, scene?: SceneCandidate): CreateReminderInput {
  const input: CreateReminderInput = {
    content: parsed.content.trim(),
    triggerType: parsed.triggerType as TriggerType,
    source: ReminderSource.AI
  };
  if (parsed.triggerType === TriggerType.TIME || parsed.triggerType === TriggerType.BOTH) {
    input.triggerTime = parsed.triggerTime as number;
  }
  if (parsed.triggerType === TriggerType.LOCATION || parsed.triggerType === TriggerType.BOTH) {
    input.sceneId = scene?.id.trim();
    input.sceneName = scene?.name.trim();
    input.locationTriggerMode = LocationTriggerMode.ENTER;
  }
  return input;
}
