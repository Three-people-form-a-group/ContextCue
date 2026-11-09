import { preferences } from '@kit.ArkData';

/**
 * 两种界面模式。
 *   minimal 极简：冷灰白 + 近黑，单一配色，无拼贴装饰；
 *   journal 手账：拼贴、票根、胶带、纸张。
 *
 * 模式存在 HarmonyOS 的 preferences 里，重启后保留。
 * 这是纯 UI 层的偏好，不涉及公共业务模型。
 */
export class UiMode {
  static readonly MINIMAL: string = 'minimal';
  static readonly JOURNAL: string = 'journal';

  /** AppStorage 键名，页面用 @StorageLink 订阅 */
  static readonly KEY: string = 'uiMode';

  private static readonly STORE_NAME: string = 'contextcue_ui';

  /** 应用启动时调用一次：读回上次选择的模式 */
  static async init(context: Context): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, UiMode.STORE_NAME);
      const saved: string = await store.get(UiMode.KEY, UiMode.JOURNAL) as string;
      AppStorage.setOrCreate<string>(UiMode.KEY, saved);
    } catch (err) {
      AppStorage.setOrCreate<string>(UiMode.KEY, UiMode.JOURNAL);
    }
  }

  /** 切换模式：先更新界面，再落盘 */
  static async setMode(context: Context, mode: string): Promise<void> {
    AppStorage.setOrCreate<string>(UiMode.KEY, mode);
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, UiMode.STORE_NAME);
      await store.put(UiMode.KEY, mode);
      await store.flush();
    } catch (err) {
      // 落盘失败不影响本次会话，下次启动会回到上一次成功的模式
    }
  }

  static isMinimal(mode: string): boolean {
    return mode === UiMode.MINIMAL;
  }
}
