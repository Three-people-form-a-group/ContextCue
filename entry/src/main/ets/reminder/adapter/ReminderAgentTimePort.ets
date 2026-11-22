import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { Reminder } from '../../model/Reminder';
import { TriggerType } from '../../model/ReminderEnums';
import { NotifyPref } from '../../common/NotifyPref';
import { TimeTriggerPort } from '../contract/TimeTriggerPort';

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
 * 限制：`reminderId`（系统返回的数字 id）与业务 id 的映射只在本次进程内有效；
 * 进程重启后无法据此取消旧提醒，需在应用启动时按系统有效提醒列表对账（后续接入）。
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
      wantAgent: {
        pkgName: this.bundleName,
        abilityName: this.abilityName
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
    if (systemId === undefined) {
      return;
    }
    try {
      await reminderAgentManager.cancelReminder(systemId);
    } finally {
      this.systemIds.delete(reminderId);
    }
  }
}
