import { preferences } from '@kit.ArkData';

/**
 * 「到点提醒」应用内开关。
 *
 * 和系统通知权限不同：系统权限由用户在系统设置里给，
 * 这个开关决定我们是否把提醒排进系统提醒代理（关掉就完全不打扰）。
 * 端口需要同步读取，所以内存里留一份镜像，启动时从 preferences 载入。
 */
export class NotifyPref {
  private static readonly STORE_NAME: string = 'contextcue_ui';
  private static readonly KEY: string = 'notifyEnabled';
  private static current: boolean = true;

  /** 供提醒代理端口同步判断 */
  static enabled(): boolean {
    return NotifyPref.current;
  }

  static async load(context: Context): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, NotifyPref.STORE_NAME);
      NotifyPref.current = await store.get(NotifyPref.KEY, true) as boolean;
    } catch (_) {
    }
  }

  static async save(context: Context, value: boolean): Promise<void> {
    NotifyPref.current = value;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, NotifyPref.STORE_NAME);
      await store.put(NotifyPref.KEY, value);
      await store.flush();
    } catch (_) {
    }
  }
}
