import { TriggerConditionEvent } from './TriggerConditionEvent';

export interface TriggerEventSink {
  onConditionChanged(event: TriggerConditionEvent): Promise<void>;
}
