import { preferences } from '@kit.ArkData';
import { NoteLayout, parseLayout, serializeLayout } from './NoteLayoutModel';

/**
 * 每条提醒的文字排版（时间/标题/地点三块的位置、缩放、旋转、隐藏）。
 * 存在 preferences，键为 `layout_<id>`，只属于 UI 层。
 */
export class NoteLayoutStore {
  private static readonly STORE_NAME: string = 'contextcue_ui';
  private static readonly VERSION_KEY: string = 'layoutVersion';
  private static cache: Map<string, NoteLayout> = new Map<string, NoteLayout>();

  private static bump(): void {
    const v: number = AppStorage.get<number>(NoteLayoutStore.VERSION_KEY) ?? 1;
    AppStorage.setOrCreate<number>(NoteLayoutStore.VERSION_KEY, v + 1);
  }

  static async load(context: Context, id: string): Promise<void> {
    if (NoteLayoutStore.cache.has(id)) {
      return;
    }
    let layout: NoteLayout = NoteLayout.defaults();
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, NoteLayoutStore.STORE_NAME);
      const raw: string = await store.get(`layout_${id}`, '') as string;
      if (raw !== '') {
        layout = parseLayout(raw);
      }
    } catch (err) {
    }
    NoteLayoutStore.cache.set(id, layout);
    NoteLayoutStore.bump();
  }

  static get(id: string): NoteLayout {
    const found: NoteLayout | undefined = NoteLayoutStore.cache.get(id);
    return found === undefined ? NoteLayout.defaults() : found;
  }

  /** 序列化后的排版，便于作为 @Prop 传递（字符串一定能触发刷新） */
  static data(id: string): string {
    return serializeLayout(NoteLayoutStore.get(id));
  }

  static async save(context: Context, id: string, layout: NoteLayout): Promise<void> {
    NoteLayoutStore.cache.set(id, layout);
    NoteLayoutStore.bump();
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, NoteLayoutStore.STORE_NAME);
      await store.put(`layout_${id}`, serializeLayout(layout));
      await store.flush();
    } catch (err) {
    }
  }

  static ensureVersion(): void {
    if (AppStorage.get<number>(NoteLayoutStore.VERSION_KEY) === undefined) {
      AppStorage.setOrCreate<number>(NoteLayoutStore.VERSION_KEY, 1);
    }
  }
}
