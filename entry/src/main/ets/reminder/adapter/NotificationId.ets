/**
 * 业务提醒 id → 系统通知 id。
 *
 * 主进程通知、系统时间代理、围栏扩展必须用同一套算法：同一条提醒无论由哪个进程
 * 发出，都落在同一个通知 id 上，用户看到的是覆盖而不是堆叠。
 */
export function reminderNotificationId(reminderId: string): number {
  let hash: number = 0;
  for (let i = 0; i < reminderId.length; i++) {
    hash = (hash * 31 + reminderId.charCodeAt(i)) | 0;
  }
  return Math.abs(hash) % 100000 + 1000;
}
