import { CreateReminderInput } from './CreateReminderInput';
import { OperationError } from './OperationResult';
import { LocationTriggerMode, ReminderStatus, TriggerType } from './ReminderEnums';

function inputError(code: string, message: string, field: string): OperationError {
  return { code: code, message: message, field: field, retryable: false };
}

export function validateCreateReminderInput(input: CreateReminderInput, now: number): OperationError[] {
  const errors: OperationError[] = [];

  if (input.content.trim().length === 0) {
    errors.push(inputError('EMPTY_CONTENT', '提醒内容不能为空', 'content'));
  }

  if (input.triggerType === TriggerType.TIME) {
    if (input.sceneId !== undefined) {
      errors.push(inputError('INCONSISTENT_TRIGGER_FIELDS', '时间提醒不能包含地点 ID', 'sceneId'));
    }
    if (input.sceneName !== undefined) {
      errors.push(inputError('INCONSISTENT_TRIGGER_FIELDS', '时间提醒不能包含地点名称', 'sceneName'));
    }
    if (input.locationTriggerMode !== undefined) {
      errors.push(inputError('INCONSISTENT_TRIGGER_FIELDS', '时间提醒不能包含地点触发方式', 'locationTriggerMode'));
    }
  } else if (input.triggerType === TriggerType.LOCATION && input.triggerTime !== undefined) {
    errors.push(inputError('INCONSISTENT_TRIGGER_FIELDS', '地点提醒不能包含触发时间', 'triggerTime'));
  }

  if (input.triggerType === TriggerType.TIME || input.triggerType === TriggerType.BOTH) {
    if (input.triggerTime === undefined) {
      errors.push(inputError('MISSING_TRIGGER_TIME', '请选择触发时间', 'triggerTime'));
    } else if (!Number.isFinite(input.triggerTime)) {
      errors.push(inputError('INVALID_TRIGGER_TIME', '触发时间无效', 'triggerTime'));
    } else if (input.triggerTime < now) {
      errors.push(inputError('PAST_TRIGGER_TIME', '触发时间不能早于当前时间', 'triggerTime'));
    }
  }

  if (input.triggerType === TriggerType.LOCATION || input.triggerType === TriggerType.BOTH) {
    if (input.sceneId === undefined || input.sceneId.trim().length === 0) {
      errors.push(inputError('MISSING_SCENE_ID', '请选择有效地点', 'sceneId'));
    }
    if (input.locationTriggerMode === LocationTriggerMode.EXIT) {
      errors.push(inputError('UNSUPPORTED_LOCATION_TRIGGER_MODE', '当前版本不支持离开地点触发', 'locationTriggerMode'));
    }
  }

  return errors;
}

export function canTransitionReminderStatus(current: ReminderStatus, next: ReminderStatus): boolean {
  if (current === next) {
    return true;
  }
  if (current === ReminderStatus.ACTIVE) {
    return next === ReminderStatus.TRIGGERED || next === ReminderStatus.COMPLETED || next === ReminderStatus.DISABLED;
  }
  if (current === ReminderStatus.DISABLED) {
    return next === ReminderStatus.ACTIVE || next === ReminderStatus.COMPLETED;
  }
  if (current === ReminderStatus.TRIGGERED) {
    return next === ReminderStatus.COMPLETED;
  }
  return false;
}
