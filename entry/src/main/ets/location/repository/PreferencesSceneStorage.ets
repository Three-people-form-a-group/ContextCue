import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { TextStorage } from './TextStorage';

export interface ScenePreferences {
  get(): Promise<string>;
  put(value: string): Promise<void>;
  flush(): Promise<void>;
}

class HarmonyScenePreferences implements ScenePreferences {
  private preferences: preferences.Preferences;
  constructor(store: preferences.Preferences) { this.preferences = store; }
  async get(): Promise<string> {
    const value = await this.preferences.get('scenes', '');
    if (typeof value !== 'string') { throw new Error('SCENE_STORAGE_INVALID'); }
    return value;
  }
  async put(value: string): Promise<void> { await this.preferences.put('scenes', value); }
  async flush(): Promise<void> { await this.preferences.flush(); }
}

/** A failed flush makes subsequent reads fail closed until process restart/recovery. */
export class PreferencesSceneStorage implements TextStorage {
  private open: () => Promise<ScenePreferences>;
  private store?: Promise<ScenePreferences>;
  private uncertain: boolean = false;

  constructor(open: () => Promise<ScenePreferences>) { this.open = open; }

  static fromContext(context: common.UIAbilityContext): PreferencesSceneStorage {
    return new PreferencesSceneStorage(async (): Promise<ScenePreferences> => {
      return new HarmonyScenePreferences(await preferences.getPreferences(context, { name: 'contextcue_location_v1' }));
    });
  }

  private async getStore(): Promise<ScenePreferences> {
    if (this.uncertain) { throw new Error('SCENE_STORAGE_REQUIRES_RECOVERY'); }
    if (this.store === undefined) { this.store = this.open(); }
    try { return await this.store; }
    catch (_) { this.store = undefined; throw new Error('SCENE_STORAGE_OPEN_FAILED'); }
  }

  async read(): Promise<string | undefined> {
    const value = await (await this.getStore()).get();
    return value.length === 0 ? undefined : value;
  }

  async write(value: string): Promise<void> {
    const store = await this.getStore();
    try {
      await store.put(value);
      await store.flush();
    } catch (_) {
      // The OS may have persisted some data. Never expose the cache as a confirmed commit.
      this.uncertain = true;
      throw new Error('SCENE_STORAGE_WRITE_FAILED');
    }
  }
}
