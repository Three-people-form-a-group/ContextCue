import { notificationManager } from '@kit.NotificationKit';
// NotificationRequest.slotType 的字段类型只由旧模块声明（SDK 类型分裂），与 SystemNotificationPort 保持一致。
import notification from '@ohos.notification';
import { WantAgent, wantAgent } from '@kit.AbilityKit';

export const FENCE_NOTIFICATION_TITLE: string = 'ContextCue 提醒';
const DEFAULT_BUNDLE: string = 'com.jyf.contextcue';
const DEFAULT_ABILITY: string = 'EntryAbility';

/**
 * 业务 id → 32 位通知 id。算法与 SystemNotificationPort.notificationId 完全相同：
 * 同一提醒无论由主进程还是围栏扩展发出，都是同一条通知（覆盖，不堆叠）。
 */
export function fenceNotificationId(reminderId: string): number {
  let hash: number = 0;
  for (let i = 0; i < reminderId.length; i++) {
    hash = (hash * 31 + reminderId.charCodeAt(i)) | 0;
  }
  return Math.abs(hash) % 100000 + 1000;
}

export interface FenceNotifier {
  publish(reminderId: string, content: string): Promise<void>;
}

/**
 * 围栏扩展进程里的通知发送。点击通知时通过 wantAgent 拉起 EntryAbility，并携带 reminderId；
 * 主进程 EntryAbility.onNewWant 负责跳转到对应提醒详情。ID 与主进程算法一致，不堆叠。
 */
export class SystemFenceNotifier implements FenceNotifier {
  async publish(reminderId: string, content: string): Promise<void> {
    if (!notificationManager.isNotificationEnabledSync()) {
      throw new Error('NOTIFICATION_DISABLED');
    }
    const requestCode: number = fenceNotificationId(reminderId);
    // 点击后进入的提醒详情由主进程按参数路由；字段名必须与 EntryAbility.routeFromWant 一致。
    const parameters: Record<string, Object> = { 'reminderId': reminderId };
    const agentInfo: wantAgent.WantAgentInfo = {
      wants: [{
        bundleName: DEFAULT_BUNDLE,
        abilityName: DEFAULT_ABILITY,
        parameters: parameters
      }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: requestCode,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    const agent: WantAgent = await wantAgent.getWantAgent(agentInfo);
    const request: notificationManager.NotificationRequest = {
      id: requestCode,
      wantAgent: agent,
      slotType: notification.SlotType.SERVICE_INFORMATION,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: FENCE_NOTIFICATION_TITLE,
          text: content
        }
      }
    };
    await notificationManager.publish(request);
  }
}
