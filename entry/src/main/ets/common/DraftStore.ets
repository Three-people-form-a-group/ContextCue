import { preferences } from '@kit.ArkData';

/** 未完成的编辑草稿（只属于 UI 层） */
export class ReminderDraft {
  readonly title: string;
  readonly timeMs: number;
  readonly triggerType: string;
  readonly sceneName: string;
  /** 最近一次保存时间，用于草稿箱排序 */
  readonly updatedAt: number;

  constructor(title: string, timeMs: number, triggerType: string, sceneName: string, updatedAt: number) {
    this.title = title;
    this.timeMs = timeMs;
    this.triggerType = triggerType;
    this.sceneName = sceneName;
    this.updatedAt = updatedAt;
  }
}

/** 草稿箱里的一行：键 + 草稿 */
export class DraftItem {
  readonly key: string;
  readonly draft: ReminderDraft;

  constructor(key: string, draft: ReminderDraft) {
    this.key = key;
    this.draft = draft;
  }
}

/**
 * 草稿存储：存在 preferences（键 `drafts`，格式 `key|title|timeMs|type|scene;...`），
 * 重启后仍能恢复。标题和地点用 encodeURIComponent 转义，避免分隔符冲突。
 */
export class DraftStore {
  private static readonly STORE_NAME: string = 'contextcue_ui';
  private static readonly KEY: string = 'drafts';
  private static readonly VERSION_KEY: string = 'draftVersion';

  private static map: Map<string, ReminderDraft> = new Map<string, ReminderDraft>();
  private static loaded: boolean = false;

  static async init(context: Context): Promise<void> {
    if (DraftStore.loaded) {
      return;
    }
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, DraftStore.STORE_NAME);
      const raw: string = await store.get(DraftStore.KEY, '') as string;
      DraftStore.parse(raw);
    } catch (err) {
      // 读不到就当没有草稿
    }
    DraftStore.loaded = true;
    if (AppStorage.get<number>(DraftStore.VERSION_KEY) === undefined) {
      AppStorage.setOrCreate<number>(DraftStore.VERSION_KEY, 1);
    }
  }

  private static bump(): void {
    const current: number = AppStorage.get<number>(DraftStore.VERSION_KEY) ?? 1;
    AppStorage.setOrCreate<number>(DraftStore.VERSION_KEY, current + 1);
  }

  private static parse(raw: string): void {
    if (raw === '') {
      return;
    }
    const parts: string[] = raw.split(';');
    for (let i = 0; i < parts.length; i++) {
      const fields: string[] = parts[i].split('|');
      if (fields.length < 5) {
        continue;
      }
      DraftStore.map.set(fields[0], new ReminderDraft(
        decodeURIComponent(fields[1]),
        parseInt(fields[2], 10),
        fields[3],
        decodeURIComponent(fields[4]),
        fields.length >= 6 ? parseInt(fields[5], 10) : 0
      ));
    }
  }

  private static serialize(): string {
    let out: string = '';
    DraftStore.map.forEach((draft: ReminderDraft, key: string) => {
      if (out !== '') {
        out += ';';
      }
      out += `${key}|${encodeURIComponent(draft.title)}|${draft.timeMs}|${draft.triggerType}|` +
        `${encodeURIComponent(draft.sceneName)}|${draft.updatedAt}`;
    });
    return out;
  }

  static get(key: string): ReminderDraft | undefined {
    return DraftStore.map.get(key);
  }

  /** 全部草稿，按最近保存倒序 */
  static all(): DraftItem[] {
    const list: DraftItem[] = [];
    DraftStore.map.forEach((draft: ReminderDraft, key: string) => {
      list.push(new DraftItem(key, draft));
    });
    list.sort((a: DraftItem, b: DraftItem) => b.draft.updatedAt - a.draft.updatedAt);
    return list;
  }

  static count(): number {
    return DraftStore.map.size;
  }

  static async save(context: Context, key: string, draft: ReminderDraft): Promise<void> {
    DraftStore.map.set(key, draft);
    DraftStore.bump();
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, DraftStore.STORE_NAME);
      await store.put(DraftStore.KEY, DraftStore.serialize());
      await store.flush();
    } catch (err) {
    }
  }

  static async clear(context: Context, key: string): Promise<void> {
    DraftStore.map.delete(key);
    DraftStore.bump();
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, DraftStore.STORE_NAME);
      await store.put(DraftStore.KEY, DraftStore.serialize());
      await store.flush();
    } catch (err) {
    }
  }
}
