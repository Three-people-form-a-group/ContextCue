import { notificationManager } from '@kit.NotificationKit';
// NotificationRequest.slotType 的字段类型声明在旧模块 @ohos.notification 里（SDK 类型分裂），
// 只能用旧枚举赋值；弃用警告可接受，待 SDK 统一后迁移。
import notification from '@ohos.notification';
import { WantAgent, wantAgent } from '@kit.AbilityKit';
import { Reminder } from '../../model/Reminder';
import { ReminderNotificationPort } from '../contract/ReminderNotificationPort';
import { reminderNotificationId } from './NotificationId';

const DEFAULT_BUNDLE: string = 'com.jyf.contextcue';
const DEFAULT_ABILITY: string = 'EntryAbility';

/**
 * 基于 notificationManager 的系统通知实现。
 *
 * 只在应用内检测到触发条件（例如地点进入）时调用；时间提醒由
 * `ReminderAgentTimePort` 交给系统提醒代理，不走这里。
 *
 * 约定：通知能力被用户关闭时**抛错**，让 TriggerCoordinator 放弃把提醒标成
 * TRIGGERED——不能假装通知已经发出。
 */
export class SystemNotificationPort implements ReminderNotificationPort {
  private bundleName: string;
  private abilityName: string;

  constructor(bundleName: string = DEFAULT_BUNDLE, abilityName: string = DEFAULT_ABILITY) {
    this.bundleName = bundleName;
    this.abilityName = abilityName;
  }

  /** 业务 id → 32 位通知 id（同一提醒重复通知会覆盖，而不是堆叠） */
  private notificationId(reminderId: string): number {
    return reminderNotificationId(reminderId);
  }

  async notify(reminder: Reminder): Promise<void> {
    if (!notificationManager.isNotificationEnabledSync()) {
      throw new Error('NOTIFICATION_DISABLED');
    }
    const requestCode: number = this.notificationId(reminder.id);
    const agentInfo: wantAgent.WantAgentInfo = {
      wants: [{
        bundleName: this.bundleName,
        abilityName: this.abilityName,
        parameters: { 'reminderId': reminder.id }
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: requestCode,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    const agent: WantAgent = await wantAgent.getWantAgent(agentInfo);
    const request: notificationManager.NotificationRequest = {
      id: requestCode,
      wantAgent: agent,
      // 服务类通知：允许横幅/声音，按用户的对应开关生效
      slotType: notification.SlotType.SERVICE_INFORMATION,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: 'ContextCue 提醒',
          text: reminder.content
        }
      }
    };
    await notificationManager.publish(request);
  }
}
