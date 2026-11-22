import { notificationManager } from '@kit.NotificationKit';
// NotificationRequest.slotType 的字段类型只由旧模块声明（SDK 类型分裂），与 SystemNotificationPort 保持一致。
import notification from '@ohos.notification';

export const FENCE_NOTIFICATION_TITLE: string = 'ContextCue 提醒';

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
 * 围栏扩展进程里的通知发送。点击路由（wantAgent）不在本模块职责内，由通知负责人统一接入；
 * 这里先保证「弹得出、ID 与主进程一致、用户关掉通知时抛错」。
 */
export class SystemFenceNotifier implements FenceNotifier {
  async publish(reminderId: string, content: string): Promise<void> {
    if (!notificationManager.isNotificationEnabledSync()) {
      throw new Error('NOTIFICATION_DISABLED');
    }
    const request: notificationManager.NotificationRequest = {
      id: fenceNotificationId(reminderId),
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
