import { preferences } from '@kit.ArkData';
import { PaperStyle } from './PaperStyle';

/**
 * 每条事项选的纸张。
 *
 * 存在 preferences 里（键 `papers`，格式 `id|paper;id|paper`），
 * 只属于 UI 层，不进入公共 Reminder 模型。
 * 变更时把 AppStorage 的 `paperVersion` 加一，今日页据此重绘。
 */
export class PaperStore {
  private static readonly STORE_NAME: string = 'contextcue_ui';
  private static readonly KEY: string = 'papers';
  private static readonly HIDDEN_KEY: string = 'hiddenText';
  private static readonly VERSION_KEY: string = 'paperVersion';

  private static map: Map<string, string> = new Map<string, string>();
  /** 该条事项是否隐藏系统文字（留白给用户手写） */
  private static hidden: Map<string, boolean> = new Map<string, boolean>();
  private static loaded: boolean = false;

  static async init(context: Context): Promise<void> {
    if (PaperStore.loaded) {
      return;
    }
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, PaperStore.STORE_NAME);
      const raw: string = await store.get(PaperStore.KEY, '') as string;
      PaperStore.parse(raw);
      const hiddenRaw: string = await store.get(PaperStore.HIDDEN_KEY, '') as string;
      PaperStore.parseHidden(hiddenRaw);
    } catch (err) {
      // 读不到就用默认分配，不影响使用
    }
    PaperStore.loaded = true;
    AppStorage.setOrCreate<number>(PaperStore.VERSION_KEY, 1);
  }

  private static parse(raw: string): void {
    if (raw === '') {
      return;
    }
    const parts: string[] = raw.split(';');
    for (let i = 0; i < parts.length; i++) {
      const pair: string[] = parts[i].split('|');
      if (pair.length === 2 && pair[0] !== '' && pair[1] !== '') {
        PaperStore.map.set(pair[0], pair[1]);
      }
    }
  }

  private static parseHidden(raw: string): void {
    if (raw === '') {
      return;
    }
    const ids: string[] = raw.split(';');
    for (let i = 0; i < ids.length; i++) {
      if (ids[i] !== '') {
        PaperStore.hidden.set(ids[i], true);
      }
    }
  }

  private static serializeHidden(): string {
    let out: string = '';
    PaperStore.hidden.forEach((flag: boolean, id: string) => {
      if (out !== '') {
        out += ';';
      }
      out += id;
    });
    return out;
  }

  static isTextHidden(id: string): boolean {
    return PaperStore.hidden.get(id) === true;
  }

  static async setTextHidden(context: Context, id: string, hidden: boolean): Promise<void> {
    if (hidden) {
      PaperStore.hidden.set(id, true);
    } else {
      PaperStore.hidden.delete(id);
    }
    const current: number = AppStorage.get<number>(PaperStore.VERSION_KEY) ?? 1;
    AppStorage.setOrCreate<number>(PaperStore.VERSION_KEY, current + 1);
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, PaperStore.STORE_NAME);
      await store.put(PaperStore.HIDDEN_KEY, PaperStore.serializeHidden());
      await store.flush();
    } catch (err) {
    }
  }

  private static serialize(): string {
    let out: string = '';
    PaperStore.map.forEach((paper: string, id: string) => {
      if (out !== '') {
        out += ';';
      }
      out += `${id}|${paper}`;
    });
    return out;
  }

  static paperOf(id: string): string {
    const found: string | undefined = PaperStore.map.get(id);
    return found === undefined ? PaperStyle.defaultFor(id) : found;
  }

  static async setPaper(context: Context, id: string, paper: string): Promise<void> {
    PaperStore.map.set(id, paper);
    const current: number = AppStorage.get<number>(PaperStore.VERSION_KEY) ?? 1;
    AppStorage.setOrCreate<number>(PaperStore.VERSION_KEY, current + 1);
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, PaperStore.STORE_NAME);
      await store.put(PaperStore.KEY, PaperStore.serialize());
      await store.flush();
    } catch (err) {
      // 落盘失败仅在本次会话内生效
    }
  }
}
