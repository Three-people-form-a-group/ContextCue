import { CreateReminderInput } from '../model/CreateReminderInput';
import { OperationError, OperationResult } from '../model/OperationResult';
import { Reminder } from '../model/Reminder';
import { LocationTriggerMode, ReminderStatus, TriggerType } from '../model/ReminderEnums';
import { canTransitionReminderStatus, validateCreateReminderInput } from '../model/ReminderModelRules';
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

function withStatus(reminder: Reminder, status: ReminderStatus, at?: number): Reminder {
  return {
    id: reminder.id, content: reminder.content, triggerType: reminder.triggerType,
    triggerTime: reminder.triggerTime, sceneId: reminder.sceneId, sceneName: reminder.sceneName,
    locationTriggerMode: reminder.locationTriggerMode, status: status, source: reminder.source,
    createdAt: reminder.createdAt,
    triggeredAt: status === ReminderStatus.TRIGGERED ? at : reminder.triggeredAt,
    completedAt: status === ReminderStatus.COMPLETED ? at : reminder.completedAt
  };
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

  async enable(id: string): Promise<OperationResult<Reminder>> {
    return this.transition(id, ReminderStatus.ACTIVE);
  }

  async disable(id: string): Promise<OperationResult<Reminder>> {
    return this.transition(id, ReminderStatus.DISABLED);
  }

  async complete(id: string): Promise<OperationResult<Reminder>> {
    return this.transition(id, ReminderStatus.COMPLETED);
  }

  async markTriggered(id: string, occurredAt: number): Promise<OperationResult<Reminder>> {
    const loaded = await this.findById(id);
    if (!loaded.success || loaded.data === undefined) {
      return { success: false, error: loaded.error };
    }
    const current = loaded.data;
    if (current.status === ReminderStatus.TRIGGERED) {
      return { success: true, data: current };
    }
    if (!canTransitionReminderStatus(current.status, ReminderStatus.TRIGGERED)) {
      return { success: false, error: serviceError('INVALID_STATUS_TRANSITION', '当前状态不能标记为已触发', false) };
    }
    const next = withStatus(current, ReminderStatus.TRIGGERED, occurredAt);
    try {
      await this.repository.save(next);
    } catch (_) {
      return { success: false, error: serviceError('REPOSITORY_ERROR', '已通知状态保存失败', true) };
    }
    if (!(await this.cleanupAll(current))) {
      return { success: false, data: next, error: serviceError('TRIGGER_CLEANUP_ERROR', '提醒已触发，但触发器清理失败', true) };
    }
    return { success: true, data: next };
  }

  async retryTriggerCleanup(id: string): Promise<OperationResult<Reminder>> {
    const loaded = await this.findById(id);
    if (!loaded.success || loaded.data === undefined) {
      return { success: false, error: loaded.error };
    }
    if (loaded.data.status !== ReminderStatus.TRIGGERED) {
      return { success: false, error: serviceError('INVALID_STATUS_TRANSITION', '仅已触发提醒可以重试清理', false) };
    }
    if (!(await this.cleanupAll(loaded.data))) {
      return { success: false, data: loaded.data, error: serviceError('TRIGGER_CLEANUP_ERROR', '触发器清理失败', true) };
    }
    return { success: true, data: loaded.data };
  }

  private async transition(id: string, target: ReminderStatus): Promise<OperationResult<Reminder>> {
    const loaded = await this.findById(id);
    if (!loaded.success || loaded.data === undefined) {
      return { success: false, error: loaded.error };
    }
    const current = loaded.data;
    if (current.status === target) {
      return { success: true, data: current };
    }
    if (!canTransitionReminderStatus(current.status, target)) {
      return { success: false, error: serviceError('INVALID_STATUS_TRANSITION', '提醒状态不能这样转换', false) };
    }
    if (target === ReminderStatus.ACTIVE) {
      const input: CreateReminderInput = {
        content: current.content, triggerType: current.triggerType, triggerTime: current.triggerTime,
        sceneId: current.sceneId, sceneName: current.sceneName,
        locationTriggerMode: current.locationTriggerMode, source: current.source
      };
      const validation = validateCreateReminderInput(input, this.now());
      if (validation.length > 0) {
        return { success: false, error: validation[0] };
      }
      try {
        await this.register(current);
      } catch (_) {
        await this.cleanup(current);
        return { success: false, error: serviceError('TRIGGER_REGISTRATION_ERROR', '触发条件注册失败', true) };
      }
      const active = withStatus(current, ReminderStatus.ACTIVE);
      try {
        await this.repository.save(active);
        return { success: true, data: active };
      } catch (_) {
        await this.cleanup(current);
        return { success: false, error: serviceError('REPOSITORY_ERROR', '提醒状态保存失败', true) };
      }
    }

    if (!(await this.cleanupAll(current))) {
      if (current.status === ReminderStatus.ACTIVE) {
        await this.restore(current);
      }
      return { success: false, error: serviceError('TRIGGER_CLEANUP_ERROR', '触发器清理失败', true) };
    }
    const next = withStatus(current, target, target === ReminderStatus.COMPLETED ? this.now() : undefined);
    try {
      await this.repository.save(next);
      return { success: true, data: next };
    } catch (_) {
      if (current.status === ReminderStatus.ACTIVE) {
        await this.restore(current);
      }
      return { success: false, error: serviceError('REPOSITORY_ERROR', '提醒状态保存失败', true) };
    }
  }

  private async restore(reminder: Reminder): Promise<void> {
    try {
      await this.register(reminder);
    } catch (_) {
      // The original repository state is retained; adapters require an external retry if restoration fails.
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

  private async cleanupAll(reminder: Reminder): Promise<boolean> {
    let success = true;
    try {
      await this.timePort.cancel(reminder.id);
    } catch (_) {
      success = false;
    }
    try {
      await this.locationPort.unregister(reminder.id);
    } catch (_) {
      success = false;
    }
    return success;
  }
}
