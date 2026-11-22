import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { Reminder } from '../../model/Reminder';
import { ReminderStatus, TriggerType } from '../../model/ReminderEnums';
import { NotifyPref } from '../../common/NotifyPref';
import { TimeTriggerPort } from '../contract/TimeTriggerPort';
import { reminderNotificationId } from './NotificationId';

/** 应用包名与入口 Ability：提醒代理需要用它拉起应用 */
const DEFAULT_BUNDLE: string = 'com.jyf.contextcue';
const DEFAULT_ABILITY: string = 'EntryAbility';

/**
 * 基于系统提醒代理（reminderAgentManager）的时间触发实现。
 *
 * 到点由**系统**弹出通知（应用被杀死也能响），不依赖应用进程存活。
 * 因此这也意味着：时间触发不会回调 `TriggerEventSink`，提醒状态不会自动变成 TRIGGERED；
 * 应用回到前台时按需自行核对。需要声明 `ohos.permission.PUBLISH_AGENT_REMINDER`。
 *
 * 映射恢复：系统返回的数字 id 与业务 id 的映射只在本次进程内缓存，因此
 * `reconcile()` 会在启动时按 `getAllValidReminders()` 对账；`cancel()` 在缓存
 * 缺失时也会按通知 id 反查系统列表，保证重启后仍能取消。
 */
export class ReminderAgentTimePort implements TimeTriggerPort {
  private bundleName: string;
  private abilityName: string;
  private systemIds: Map<string, number> = new Map<string, number>();

  constructor(bundleName: string = DEFAULT_BUNDLE, abilityName: string = DEFAULT_ABILITY) {
    this.bundleName = bundleName;
    this.abilityName = abilityName;
  }

  async schedule(reminder: Reminder): Promise<void> {
    // 应用内「时间提醒」关闭时不再排期（用户在设置里主动关掉的）
    if (!NotifyPref.enabled()) {
      return;
    }
    // 2026-11-22 组长确认：BOTH 不交给系统时间代理。
    // 系统代理只认时间，无法与地点条件做 AND；BOTH 改为「进入地点且时间已过」时
    // 由地点链路触发。代价：到点时人已经在地点内不会单独弹，见设计规范 §8。
    if (reminder.triggerType !== TriggerType.TIME) {
      return;
    }
    if (reminder.triggerTime === undefined) {
      return;
    }
    if (reminder.triggerTime <= Date.now()) {
      // 已经过去的时间不再注册，避免系统立刻弹一条历史提醒
      return;
    }
    const date: Date = new Date(reminder.triggerTime);
    const request: reminderAgentManager.ReminderRequestCalendar = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: {
        year: date.getFullYear(),
        month: date.getMonth() + 1,
        day: date.getDate(),
        hour: date.getHours(),
        minute: date.getMinutes(),
        second: 0
      },
      title: 'ContextCue 提醒',
      content: reminder.content,
      expiredContent: reminder.content,
      snoozeContent: reminder.content,
      // 与 SystemNotificationPort / 围栏扩展共用同一套通知 id：同一条提醒只覆盖，不堆叠
      notificationId: reminderNotificationId(reminder.id),
      wantAgent: {
        pkgName: this.bundleName,
        abilityName: this.abilityName,
        parameters: { 'reminderId': reminder.id }
      },
      ringDuration: 5,
      snoozeTimes: 2,
      timeInterval: 600
    };
    const id: number = await reminderAgentManager.publishReminder(request);
    this.systemIds.set(reminder.id, id);
  }

  async cancel(reminderId: string): Promise<void> {
    const systemId: number | undefined = this.systemIds.get(reminderId);
    if (systemId !== undefined) {
      try {
        await reminderAgentManager.cancelReminder(systemId);
      } finally {
        this.systemIds.delete(reminderId);
      }
      return;
    }
    // 进程重启后内存映射为空：按通知 id 反查系统里的有效提醒，
    // 把该业务提醒的所有重复排期一起取消，保证编辑/删除真的生效。
    try {
      const valid = await reminderAgentManager.getAllValidReminders();
      const expected: number = reminderNotificationId(reminderId);
      for (let i = 0; i < valid.length; i++) {
        if (valid[i].reminderReq.notificationId === expected) {
          try {
            await reminderAgentManager.cancelReminder(valid[i].reminderId);
          } catch (_) {
          }
        }
      }
    } catch (_) {
    }
  }

  /**
   * 启动对账：以当前提醒列表为准，取消无效/重复的系统提醒，补排缺失的，并恢复
   * 业务 id → 系统 id 的映射。
   *
   * 列表为空时不清理“孤儿”：内存仓储重启后会清空，此时空列表代表“未知”，
   * 不能据此取消用户已经排好的系统提醒。等提醒持久化落地后，列表可信，
   * 孤儿清理自然生效。
   */
  async reconcile(reminders: Reminder[]): Promise<void> {
    const now: number = Date.now();
    const wanted: Map<number, Reminder> = new Map<number, Reminder>();
    for (let i = 0; i < reminders.length; i++) {
      const r: Reminder = reminders[i];
      if (r.status === ReminderStatus.ACTIVE && r.triggerType === TriggerType.TIME &&
        r.triggerTime !== undefined && r.triggerTime > now) {
        wanted.set(reminderNotificationId(r.id), r);
      }
    }
    let valid: Array<reminderAgentManager.ReminderInfo> = [];
    try {
      valid = await reminderAgentManager.getAllValidReminders();
    } catch (_) {
      // 拿不到系统列表就不动现有排期，避免误删
      return;
    }
    const authoritative: boolean = reminders.length > 0;
    const kept: Map<number, number> = new Map<number, number>();
    for (let i = 0; i < valid.length; i++) {
      const info: reminderAgentManager.ReminderInfo = valid[i];
      const nid: number | undefined = info.reminderReq.notificationId;
      if (nid === undefined || !wanted.has(nid)) {
        if (authoritative) {
          try {
            await reminderAgentManager.cancelReminder(info.reminderId);
          } catch (_) {
          }
        }
        continue;
      }
      if (kept.has(nid)) {
        // 同一条提醒在系统里重复排期：保留第一个，其余取消
        try {
          await reminderAgentManager.cancelReminder(info.reminderId);
        } catch (_) {
        }
        continue;
      }
      kept.set(nid, info.reminderId);
    }
    const keptIds: number[] = Array.from(kept.keys());
    for (let i = 0; i < keptIds.length; i++) {
      const nid: number = keptIds[i];
      const r: Reminder | undefined = wanted.get(nid);
      const systemId: number | undefined = kept.get(nid);
      if (r !== undefined && systemId !== undefined) {
        this.systemIds.set(r.id, systemId);
      }
    }
    const wantedIds: number[] = Array.from(wanted.keys());
    for (let i = 0; i < wantedIds.length; i++) {
      const nid: number = wantedIds[i];
      if (kept.has(nid)) {
        continue;
      }
      const r: Reminder | undefined = wanted.get(nid);
      if (r !== undefined) {
        try {
          await this.schedule(r);
        } catch (_) {
        }
      }
    }
  }
}
