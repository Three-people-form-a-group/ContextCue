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

// Stable location codes end up as operation codes so pages can tell the user what to fix.
// TRIGGER_REGISTRATION_ERROR.retryable is meaningless for these: permission denial and an
// unsupported device never succeed by pressing "retry" again.
const LOCATION_OPERATION_ERRORS: Map<string, OperationError> = new Map<string, OperationError>();

function registerLocationOperationError(code: string, message: string, retryable: boolean): void {
  LOCATION_OPERATION_ERRORS.set(code, { code: code, message: message, retryable: retryable });
}

registerLocationOperationError('LOCATION_PERMISSION_DENIED', '未获得精确位置权限，请到设置中开启后重试', false);
registerLocationOperationError('LOCATION_SWITCH_OFF', '系统定位开关未开启，请开启后重试', true);
registerLocationOperationError('LOCATION_WGS84_FENCE_UNSUPPORTED', '当前设备不支持地理围栏提醒', false);
registerLocationOperationError('LOCATION_FENCE_REGISTRATION_FAILED', '地点围栏注册失败，请稍后重试', true);
registerLocationOperationError('LOCATION_NOT_STARTED', '定位服务尚未启动，请重试', true);
registerLocationOperationError('LOCATION_INVALID_REGISTRATION', '地点提醒参数不完整', false);
registerLocationOperationError('LOCATION_UNREGISTER_BEFORE_REPLACE', '请先删除原地点提醒再重新创建', false);
registerLocationOperationError('LOCATION_FIX_UNUSABLE', '当前位置不可用，请稍后重试', true);
registerLocationOperationError('LOCATION_FIX_UNCERTAIN', '当前位置靠近地点边界，请靠近或远离一些后重试', true);
registerLocationOperationError('LOCATION_STOP_CLEANUP_FAILED', '地点围栏清理失败，请稍后重试', true);
// V2 围栏持久映射相关（扩展进程与主进程共用同一份映射文件）
registerLocationOperationError('FENCE_REGISTRY_WRITE_FAILED', '地点提醒记录保存失败，请稍后重试', true);
registerLocationOperationError('FENCE_REGISTRY_REQUIRES_RECOVERY', '地点提醒记录状态异常，请重启应用后重试', true);
registerLocationOperationError('FENCE_REGISTRY_CORRUPT', '地点提醒记录已损坏，请重启应用后重试', true);
registerLocationOperationError('FENCE_HANDLER_NOT_FOUND', '地点围栏与提醒的对应关系已失效，请重新创建提醒', true);
registerLocationOperationError('SCENE_NOT_FOUND', '地点不存在，请重新选择', false);

function locationErrorCode(error: Object | undefined): string {
  if (error === undefined) { return ''; }
  const message = error instanceof Error ? error.message : String(error);
  return message.trim();
}

/** Maps an adapter failure to the closest stable code. Unknown failures stay retryable. */
function registrationError(error: Object | undefined): OperationError {
  const code = locationErrorCode(error);
  const known = LOCATION_OPERATION_ERRORS.get(code);
  if (known !== undefined) {
    return { code: known.code, message: known.message, retryable: known.retryable };
  }
  return serviceError('TRIGGER_REGISTRATION_ERROR', '触发条件注册失败', true);
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
    // 回到 ACTIVE 表示重新待办：清掉上一次的触发/完成时间；
    // 离开 COMPLETED（撤销完成）时 completedAt 也必须清掉，否则会残留。
    triggeredAt: status === ReminderStatus.TRIGGERED ? at
      : (status === ReminderStatus.ACTIVE ? undefined : reminder.triggeredAt),
    completedAt: status === ReminderStatus.COMPLETED ? at : undefined
  };
}

export class ReminderService {
  private repository: ReminderRepository;
  private timePort: TimeTriggerPort;
  private locationPort: LocationTriggerPort;
  private now: () => number;
  private newId: () => string;
  private mutationGates: Map<string, Promise<void>> = new Map<string, Promise<void>>();

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
    return this.serialize(reminder.id, () => this.createRegistered(reminder));
  }

  private async createRegistered(reminder: Reminder): Promise<OperationResult<Reminder>> {
    try {
      if (await this.repository.findById(reminder.id) !== undefined) {
        return { success: false, error: serviceError('REPOSITORY_ERROR', '提醒 ID 已存在', true) };
      }
    } catch (_) {
      return { success: false, error: serviceError('REPOSITORY_ERROR', '提醒 ID 检查失败', true) };
    }

    try {
      await this.register(reminder);
    } catch (error) {
      await this.cleanup(reminder);
      return { success: false, error: registrationError(error) };
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
    return this.serialize(id, () => this.transition(id, ReminderStatus.ACTIVE));
  }

  async disable(id: string): Promise<OperationResult<Reminder>> {
    return this.serialize(id, () => this.transition(id, ReminderStatus.DISABLED));
  }

  async complete(id: string): Promise<OperationResult<Reminder>> {
    return this.serialize(id, () => this.transition(id, ReminderStatus.COMPLETED));
  }

  /**
   * 场景改名级联（D2 决策）：把引用该场景的所有提醒的 sceneName 快照更新为新名称。
   * 只改展示快照，不触碰触发注册（围栏不依赖名称）；返回更新的提醒数量。
   * 由 LocationSceneService.updateScene 在名称变化时调用。
   */
  async renameSceneReminders(sceneId: string, sceneName: string): Promise<OperationResult<number>> {
    const trimmed = sceneName.trim();
    if (trimmed.length === 0) {
      return { success: false, error: serviceError('SCENE_NAME_EMPTY', '场景名称不能为空', false) };
    }
    let updated = 0;
    const all = await this.repository.findAll();
    for (let index = 0; index < all.length; index++) {
      const reminder = all[index];
      if (reminder.sceneId !== sceneId || reminder.sceneName === trimmed) { continue; }
      await this.serialize<boolean>(reminder.id, async (): Promise<OperationResult<boolean>> => {
        const current = await this.repository.findById(reminder.id);
        if (current === undefined || current.sceneId !== sceneId || current.sceneName === trimmed) {
          return { success: true, data: false };
        }
        const renamed: Reminder = {
          id: current.id, content: current.content, triggerType: current.triggerType,
          triggerTime: current.triggerTime, sceneId: current.sceneId, sceneName: trimmed,
          locationTriggerMode: current.locationTriggerMode, status: current.status,
          source: current.source, createdAt: current.createdAt,
          triggeredAt: current.triggeredAt, completedAt: current.completedAt
        };
        try {
          await this.repository.save(renamed);
          updated++;
          return { success: true, data: true };
        } catch (_) {
          return { success: false, error: serviceError('REPOSITORY_ERROR', '提醒保存失败', true) };
        }
      });
    }
    return { success: true, data: updated };
  }

  async markTriggered(id: string, occurredAt: number): Promise<OperationResult<Reminder>> {
    return this.serialize(id, () => this.markTriggeredInternal(id, occurredAt));
  }

  async processActiveTrigger(id: string, occurredAt: number,
    action: (reminder: Reminder) => Promise<boolean>): Promise<OperationResult<Reminder>> {
    return this.serialize(id, () => this.processActiveTriggerInternal(id, occurredAt, action));
  }

  private async processActiveTriggerInternal(id: string, occurredAt: number,
    action: (reminder: Reminder) => Promise<boolean>): Promise<OperationResult<Reminder>> {
    const loaded = await this.findById(id);
    if (!loaded.success || loaded.data === undefined) {
      return { success: false, error: loaded.error };
    }
    if (loaded.data.status !== ReminderStatus.ACTIVE) {
      return { success: true, data: loaded.data };
    }
    if (!(await action(loaded.data))) {
      return { success: true, data: loaded.data };
    }
    return this.markTriggeredInternal(id, occurredAt);
  }

  private async markTriggeredInternal(id: string, occurredAt: number): Promise<OperationResult<Reminder>> {
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
    return this.serialize(id, () => this.retryTriggerCleanupInternal(id));
  }

  private async retryTriggerCleanupInternal(id: string): Promise<OperationResult<Reminder>> {
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

  async update(id: string, input: CreateReminderInput): Promise<OperationResult<Reminder>> {
    return this.serialize(id, () => this.updateInternal(id, input));
  }

  private async updateInternal(id: string, input: CreateReminderInput): Promise<OperationResult<Reminder>> {
    const validation = validateCreateReminderInput(input, this.now());
    if (validation.length > 0) {
      return { success: false, error: validation[0] };
    }
    const loaded = await this.findById(id);
    if (!loaded.success || loaded.data === undefined) {
      return { success: false, error: loaded.error };
    }
    const current = loaded.data;
    if (current.status !== ReminderStatus.ACTIVE && current.status !== ReminderStatus.DISABLED) {
      return { success: false, error: serviceError('INVALID_STATUS_TRANSITION', '已触发或完成的提醒不能编辑', false) };
    }
    const next: Reminder = {
      id: current.id,
      content: input.content.trim(),
      triggerType: input.triggerType,
      triggerTime: input.triggerTime,
      sceneId: input.sceneId === undefined ? undefined : input.sceneId.trim(),
      sceneName: input.sceneName,
      locationTriggerMode: input.triggerType === TriggerType.TIME ? undefined :
        (input.locationTriggerMode === undefined ? LocationTriggerMode.ENTER : input.locationTriggerMode),
      status: current.status,
      source: input.source,
      createdAt: current.createdAt,
      triggeredAt: current.triggeredAt,
      completedAt: current.completedAt
    };

    if (current.status === ReminderStatus.ACTIVE) {
      if (!(await this.cleanupAll(current))) {
        await this.restore(current);
        return { success: false, error: serviceError('TRIGGER_CLEANUP_ERROR', '旧触发器清理失败', true) };
      }
      try {
        await this.register(next);
      } catch (error) {
        await this.cleanup(next);
        await this.restore(current);
        const failure = registrationError(error);
        // 稳定码的文案已经面向用户，不要再套“注册失败”这种开发口吻
        return { success: false, error: { code: failure.code,
          message: failure.code === 'TRIGGER_REGISTRATION_ERROR' ? '新触发条件注册失败：' + failure.message : failure.message,
          retryable: failure.retryable } };
      }
    }

    try {
      await this.repository.save(next);
      return { success: true, data: next };
    } catch (_) {
      if (current.status === ReminderStatus.ACTIVE) {
        await this.cleanup(next);
        await this.restore(current);
      }
      return { success: false, error: serviceError('REPOSITORY_ERROR', '提醒编辑保存失败', true) };
    }
  }

  async delete(id: string): Promise<OperationResult<boolean>> {
    return this.serialize(id, () => this.deleteInternal(id));
  }

  private async deleteInternal(id: string): Promise<OperationResult<boolean>> {
    const loaded = await this.findById(id);
    if (!loaded.success || loaded.data === undefined) {
      return { success: false, error: loaded.error };
    }
    const current = loaded.data;
    if (!(await this.cleanupAll(current))) {
      if (current.status === ReminderStatus.ACTIVE) {
        await this.restore(current);
      }
      return { success: false, error: serviceError('TRIGGER_CLEANUP_ERROR', '触发器清理失败', true) };
    }
    try {
      const deleted = await this.repository.deleteById(id);
      if (!deleted) {
        if (current.status === ReminderStatus.ACTIVE) {
          await this.restore(current);
        }
        return { success: false, error: serviceError('REPOSITORY_ERROR', '提醒删除失败', true) };
      }
      return { success: true, data: true };
    } catch (_) {
      if (current.status === ReminderStatus.ACTIVE) {
        await this.restore(current);
      }
      return { success: false, error: serviceError('REPOSITORY_ERROR', '提醒删除失败', true) };
    }
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
      const active = withStatus(current, ReminderStatus.ACTIVE);
      try {
        await this.register(active);
      } catch (error) {
        await this.cleanup(active);
        return { success: false, error: registrationError(error) };
      }
      try {
        await this.repository.save(active);
        return { success: true, data: active };
      } catch (_) {
        await this.cleanup(active);
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

  private async serialize<T>(id: string, action: () => Promise<OperationResult<T>>): Promise<OperationResult<T>> {
    const previous = this.mutationGates.get(id);
    let releaseGate: () => void = () => {};
    const gate: Promise<void> = new Promise<void>((resolve: () => void) => {
      releaseGate = resolve;
    });
    this.mutationGates.set(id, gate);
    if (previous !== undefined) {
      await previous;
    }
    try {
      return await action();
    } finally {
      releaseGate();
      if (this.mutationGates.get(id) === gate) {
        this.mutationGates.delete(id);
      }
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
