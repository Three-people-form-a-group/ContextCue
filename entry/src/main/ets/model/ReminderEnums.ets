export enum TriggerType {
  TIME = 'TIME',
  LOCATION = 'LOCATION',
  BOTH = 'BOTH'
}

export enum ReminderSource {
  MANUAL = 'MANUAL',
  AI = 'AI',
  TIMETABLE = 'TIMETABLE'
}

export enum ReminderStatus {
  ACTIVE = 'ACTIVE',
  TRIGGERED = 'TRIGGERED',
  COMPLETED = 'COMPLETED',
  DISABLED = 'DISABLED'
}

export enum LocationTriggerMode {
  ENTER = 'ENTER',
  EXIT = 'EXIT'
}
