export enum TriggerCondition {
  TIME = 'TIME',
  LOCATION = 'LOCATION'
}

export interface TriggerConditionEvent {
  reminderId: string;
  condition: TriggerCondition;
  satisfied: boolean;
  occurredAt: number;
}
