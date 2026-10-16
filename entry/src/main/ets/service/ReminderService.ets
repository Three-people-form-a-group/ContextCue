import { CreateReminderInput } from '../model/CreateReminderInput';
import { OperationError, OperationResult } from '../model/OperationResult';
import { Reminder } from '../model/Reminder';
import { LocationTriggerMode, ReminderStatus, TriggerType } from '../model/ReminderEnums';
import { validateCreateReminderInput } from '../model/ReminderModelRules';
import { ReminderRepository } from '../repository/ReminderRepository';
import { TimeTriggerPort } from '../reminder/contract/TimeTriggerPort';
import { LocationTriggerPort } from '../reminder/contract/LocationTriggerPort';

function serviceError(code: string, message: string, retryable: boolean): OperationError {
  return { code: code, message: message, retryable: retryable };
}

function usesTime(reminder: Reminder): boolean {
  return reminder.triggerType === TriggerType.TIME || reminder.triggerType === TriggerType.BOTH;
}

function usesLocation(reminder: Reminder): boolean {
  return reminder.triggerType === TriggerType.LOCATION || reminder.triggerType === TriggerType.BOTH;
}

export class ReminderService {
  private repository: ReminderRepository;
  private timePort: TimeTriggerPort;
  private locationPort: LocationTriggerPort;
  private now: () => number;
  private newId: () => string;

  constructor(repository: ReminderRepository, timePort: TimeTriggerPort, locationPort: LocationTriggerPort,
    now: () => number, newId: () => string) {
    this.repository = repository;
    this.timePort = timePort;
    this.locationPort = locationPort;
    this.now = now;
    this.newId = newId;
  }

  async create(input: CreateReminderInput): Promise<OperationResult<Reminder>> {
    const createdAt = this.now();
    const validation = validateCreateReminderInput(input, createdAt);
    if (validation.length > 0) {
      return { success: false, error: validation[0] };
    }

    const reminder: Reminder = {
      id: this.newId(),
      content: input.content.trim(),
      triggerType: input.triggerType,
      triggerTime: input.triggerTime,
      sceneId: input.sceneId === undefined ? undefined : input.sceneId.trim(),
      sceneName: input.sceneName,
      locationTriggerMode: input.triggerType === TriggerType.TIME ? undefined :
        (input.locationTriggerMode === undefined ? LocationTriggerMode.ENTER : input.locationTriggerMode),
      status: ReminderStatus.ACTIVE,
      source: input.source,
      createdAt: createdAt
    };

    try {
      await this.register(reminder);
    } catch (_) {
      await this.cleanup(reminder);
      return { success: false, error: serviceError('TRIGGER_REGISTRATION_ERROR', '触发条件注册失败', true) };
    }

    try {
      await this.repository.save(reminder);
      return { success: true, data: reminder };
    } catch (_) {
      await this.cleanup(reminder);
      return { success: false, error: serviceError('REPOSITORY_ERROR', '提醒保存失败', true) };
    }
  }

  async findById(id: string): Promise<OperationResult<Reminder>> {
    try {
      const reminder = await this.repository.findById(id);
      if (reminder === undefined) {
        return { success: false, error: serviceError('REMINDER_NOT_FOUND', '提醒不存在', false) };
      }
      return { success: true, data: reminder };
    } catch (_) {
      return { success: false, error: serviceError('REPOSITORY_ERROR', '提醒读取失败', true) };
    }
  }

  async findAll(): Promise<OperationResult<Reminder[]>> {
    try {
      return { success: true, data: await this.repository.findAll() };
    } catch (_) {
      return { success: false, error: serviceError('REPOSITORY_ERROR', '提醒列表读取失败', true) };
    }
  }

  private async register(reminder: Reminder): Promise<void> {
    if (usesTime(reminder)) {
      await this.timePort.schedule(reminder);
    }
    if (usesLocation(reminder)) {
      await this.locationPort.register(reminder);
    }
  }

  private async cleanup(reminder: Reminder): Promise<boolean> {
    let success = true;
    if (usesTime(reminder)) {
      try {
        await this.timePort.cancel(reminder.id);
      } catch (_) {
        success = false;
      }
    }
    if (usesLocation(reminder)) {
      try {
        await this.locationPort.unregister(reminder.id);
      } catch (_) {
        success = false;
      }
    }
    return success;
  }
}
