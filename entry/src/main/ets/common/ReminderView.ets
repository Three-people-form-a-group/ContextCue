import { Reminder } from '../model/Reminder';
import { LocationTriggerMode, ReminderSource, ReminderStatus, TriggerType } from '../model/ReminderEnums';

/**
 * 提醒的展示派生文案（纯 UI，不改变任何字段语义）。
 * 数据本身一律使用公共 model/Reminder，这里只负责把它翻译成界面上的字。
 */
export function formatClockText(epochMs: number | undefined): string {
  if (epochMs === undefined || epochMs <= 0) {
    return '时间待定';
  }
  const d: Date = new Date(epochMs);
  const h: number = d.getHours();
  const m: number = d.getMinutes();
  const hText: string = h < 10 ? `0${h}` : `${h}`;
  const mText: string = m < 10 ? `0${m}` : `${m}`;
  return `${hText}:${mText}`;
}

export function reminderPrimaryText(r: Reminder): string {
  if (r.triggerType === TriggerType.LOCATION) {
    return r.sceneName !== undefined && r.sceneName !== '' ? r.sceneName : '地点待定';
  }
  return formatClockText(r.triggerTime);
}

export function reminderTimeText(r: Reminder): string {
  if (r.triggerType === TriggerType.LOCATION) {
    return '—';
  }
  return formatClockText(r.triggerTime);
}

export function reminderTypeText(r: Reminder): string {
  if (r.triggerType === TriggerType.BOTH) {
    return '时间+地点';
  }
  if (r.triggerType === TriggerType.LOCATION) {
    return '地点提醒';
  }
  return '时间提醒';
}

export function reminderSourceText(r: Reminder): string {
  return r.source === ReminderSource.AI ? 'AI 解析' : '手动创建';
}

export function reminderStatusText(r: Reminder): string {
  if (r.status === ReminderStatus.TRIGGERED) {
    return '已触发';
  }
  if (r.status === ReminderStatus.COMPLETED) {
    return '已完成';
  }
  if (r.status === ReminderStatus.DISABLED) {
    return '已禁用';
  }
  return '进行中';
}

export function reminderLocationText(r: Reminder): string {
  const scene: string = r.sceneName === undefined ? '' : r.sceneName;
  if (scene === '') {
    return '未设置';
  }
  const mode: string = r.locationTriggerMode === LocationTriggerMode.EXIT ? '离开时' : '进入时';
  return `${scene}（${mode}）`;
}

/** 触发方式文案，由真实 locationTriggerMode 派生（V1 仅 ENTER 可用）。 */
export function reminderLocationModeText(r: Reminder): string {
  return r.locationTriggerMode === LocationTriggerMode.EXIT ? '离开场景时触发' : '进入场景时触发';
}

export function isCompleted(r: Reminder): boolean {
  return r.status === ReminderStatus.COMPLETED;
}

/** 待办：还没完成、也还没被禁用（TRIGGERED 表示通知已发，但仍然待办） */
export function isPending(r: Reminder): boolean {
  return r.status === ReminderStatus.ACTIVE || r.status === ReminderStatus.TRIGGERED;
}

export function isLocationOnly(r: Reminder): boolean {
  return r.triggerType === TriggerType.LOCATION;
}

export function isDualFocus(r: Reminder): boolean {
  return r.triggerType === TriggerType.BOTH;
}

export function hasLocation(r: Reminder): boolean {
  return r.triggerType !== TriggerType.TIME;
}

/** ForEach 渲染键：时间/状态/内容变化时强制重建，避免复用旧组件。 */
export function reminderRenderKey(r: Reminder): string {
  const t: string = r.triggerTime === undefined ? 'x' : `${r.triggerTime}`;
  return `${r.id}-${t}-${r.status}-${r.content}`;
}
