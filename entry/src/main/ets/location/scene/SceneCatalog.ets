import { Scene } from '../../model/Scene';
import { SceneCandidate, SceneResolveResult, SceneResolveStatus, SceneResolver } from '../../reminder/contract/SceneResolver';
import { validateCoordinates } from '../geometry/LocationGeometry';
import { TextStorage } from '../repository/TextStorage';

export interface SceneInput {
  name: string;
  latitude: number;
  longitude: number;
  radius: number;
}

interface SceneDocument {
  version: number;
  scenes: Scene[];
}

// A GNSS fix is not room-level precise. Below 100 m, normal drift can cross the boundary
// repeatedly; above 5 km the "scene" stops describing a place the user is actually visiting.
export const SCENE_MIN_RADIUS_METERS: number = 100;
export const SCENE_MAX_RADIUS_METERS: number = 5000;

function validateInput(input: SceneInput): void {
  if (typeof input.name !== 'string' || input.name.trim().length === 0 || input.name.trim().length > 100) {
    throw new Error('SCENE_INVALID_NAME');
  }
  validateCoordinates(input.latitude, input.longitude);
  if (!Number.isFinite(input.radius) || input.radius < SCENE_MIN_RADIUS_METERS ||
    input.radius > SCENE_MAX_RADIUS_METERS) {
    throw new Error('LOCATION_INVALID_RADIUS');
  }
}

function copyScene(scene: Scene): Scene {
  return { id: scene.id, name: scene.name, latitude: scene.latitude, longitude: scene.longitude,
    radius: scene.radius, createdAt: scene.createdAt };
}

/** One shared instance per process. All writes, reservations and reads are serialized. */
export class SceneCatalog implements SceneResolver {
  private gate: Promise<void> = Promise.resolve();
  private reservations: Map<string, Set<string>> = new Map<string, Set<string>>();

  private storage: TextStorage;
  private now: () => number;
  private newId: () => string;
  private hasReminderReference: (sceneId: string) => Promise<boolean>;

  constructor(storage: TextStorage, now: () => number, newId: () => string,
    hasReminderReference: (sceneId: string) => Promise<boolean>) {
    this.storage = storage;
    this.now = now;
    this.newId = newId;
    this.hasReminderReference = hasReminderReference;
  }

  private async exclusive<T>(action: () => Promise<T>): Promise<T> {
    const previous = this.gate;
    let release: () => void = () => {};
    this.gate = new Promise<void>((resolve: () => void) => { release = resolve; });
    await previous;
    try { return await action(); } finally { release(); }
  }

  private async load(): Promise<Scene[]> {
    const raw = await this.storage.read();
    if (raw === undefined) { return []; }
    const document = JSON.parse(raw) as SceneDocument;
    if (document === null || document.version !== 1 || !Array.isArray(document.scenes)) {
      throw new Error('SCENE_STORAGE_INVALID');
    }
    const ids = new Set<string>();
    for (const scene of document.scenes) {
      if (scene === null || typeof scene.id !== 'string' || scene.id.trim().length === 0 ||
        ids.has(scene.id) || !Number.isFinite(scene.createdAt) || scene.createdAt < 0) {
        throw new Error('SCENE_STORAGE_INVALID');
      }
      validateInput({ name: scene.name, latitude: scene.latitude, longitude: scene.longitude, radius: scene.radius });
      ids.add(scene.id);
    }
    return document.scenes;
  }

  private async save(scenes: Scene[]): Promise<void> {
    const document: SceneDocument = { version: 1, scenes: scenes };
    await this.storage.write(JSON.stringify(document));
  }

  async create(input: SceneInput): Promise<Scene> {
    // Copy before awaiting so callers cannot change the validation input mid-operation.
    const draft: SceneInput = { name: input.name, latitude: input.latitude, longitude: input.longitude, radius: input.radius };
    validateInput(draft);
    // Duplicate names are intentional: two "图书馆" can be different places. resolveByName()
    // reports AMBIGUOUS and the AI flow asks the user to choose instead of guessing.
    return this.exclusive(async (): Promise<Scene> => {
      const scenes = await this.load();
      const id = this.newId();
      const at = this.now();
      if (id.trim().length === 0 || scenes.some((scene: Scene) => scene.id === id) || !Number.isFinite(at) || at < 0) {
        throw new Error('SCENE_INVALID_ID_OR_CLOCK');
      }
      const scene: Scene = { id: id, name: draft.name.trim(), latitude: draft.latitude,
        longitude: draft.longitude, radius: draft.radius, createdAt: at };
      scenes.push(scene);
      await this.save(scenes);
      return copyScene(scene);
    });
  }

  async findAll(): Promise<Scene[]> {
    return this.exclusive(async (): Promise<Scene[]> => (await this.load()).map(copyScene));
  }

  async findById(id: string): Promise<Scene | undefined> {
    const scenes = await this.findAll();
    return scenes.find((scene: Scene) => scene.id === id);
  }

  private async requireMutable(id: string): Promise<void> {
    const pins = this.reservations.get(id);
    if ((pins !== undefined && pins.size > 0) || await this.hasReminderReference(id)) {
      throw new Error('SCENE_IN_USE');
    }
  }

  /**
   * 只改名称，坐标和半径保持原值。被提醒引用时也允许：
   * 名称只是展示和 AI 匹配用，围栏依赖的是 sceneId 与坐标。
   */
  async rename(id: string, name: string): Promise<Scene> {
    const trimmed: string = name.trim();
    if (trimmed.length === 0 || trimmed.length > 100) {
      throw new Error('SCENE_INVALID_NAME');
    }
    return this.exclusive(async (): Promise<Scene> => {
      const scenes = await this.load();
      const index = scenes.findIndex((scene: Scene) => scene.id === id);
      if (index < 0) { throw new Error('SCENE_NOT_FOUND'); }
      const current: Scene = scenes[index];
      const next: Scene = { id: id, name: trimmed, latitude: current.latitude,
        longitude: current.longitude, radius: current.radius, createdAt: current.createdAt };
      scenes[index] = next;
      await this.save(scenes);
      return copyScene(next);
    });
  }

  /**
   * 修改名称/坐标/半径，且允许场景已被提醒引用。
   *
   * 调用方必须负责把该场景下已注册的围栏重新注册，否则系统围栏仍使用旧圆心/旧半径。
   * 与 `update` 的区别只在于跳过 `requireMutable`；名称、坐标、半径仍走同一套校验。
   */
  async updateGeometry(id: string, input: SceneInput): Promise<Scene> {
    const draft: SceneInput = { name: input.name, latitude: input.latitude, longitude: input.longitude, radius: input.radius };
    validateInput(draft);
    return this.exclusive(async (): Promise<Scene> => {
      const scenes = await this.load();
      const index = scenes.findIndex((scene: Scene) => scene.id === id);
      if (index < 0) { throw new Error('SCENE_NOT_FOUND'); }
      const next: Scene = { id: id, name: draft.name.trim(), latitude: draft.latitude,
        longitude: draft.longitude, radius: draft.radius, createdAt: scenes[index].createdAt };
      scenes[index] = next;
      await this.save(scenes);
      return copyScene(next);
    });
  }

  async update(id: string, input: SceneInput): Promise<Scene> {
    const draft: SceneInput = { name: input.name, latitude: input.latitude, longitude: input.longitude, radius: input.radius };
    validateInput(draft);
    return this.exclusive(async (): Promise<Scene> => {
      const scenes = await this.load();
      const index = scenes.findIndex((scene: Scene) => scene.id === id);
      if (index < 0) { throw new Error('SCENE_NOT_FOUND'); }
      await this.requireMutable(id);
      const next: Scene = { id: id, name: draft.name.trim(), latitude: draft.latitude,
        longitude: draft.longitude, radius: draft.radius, createdAt: scenes[index].createdAt };
      scenes[index] = next;
      await this.save(scenes);
      return copyScene(next);
    });
  }

  async delete(id: string): Promise<void> {
    await this.exclusive(async (): Promise<void> => {
      const scenes = await this.load();
      if (!scenes.some((scene: Scene) => scene.id === id)) { return; }
      await this.requireMutable(id);
      await this.save(scenes.filter((scene: Scene) => scene.id !== id));
    });
  }

  async acquire(sceneId: string, reminderId: string): Promise<Scene> {
    return this.exclusive(async (): Promise<Scene> => {
      const scenes = await this.load();
      const scene = scenes.find((item: Scene) => item.id === sceneId);
      if (scene === undefined) { throw new Error('SCENE_NOT_FOUND'); }
      let pins = this.reservations.get(sceneId);
      if (pins === undefined) { pins = new Set<string>(); this.reservations.set(sceneId, pins); }
      pins.add(reminderId);
      return copyScene(scene);
    });
  }

  async release(sceneId: string, reminderId: string): Promise<void> {
    await this.exclusive(async (): Promise<void> => {
      const pins = this.reservations.get(sceneId);
      pins?.delete(reminderId);
      if (pins?.size === 0) { this.reservations.delete(sceneId); }
    });
  }

  async resolveByName(sceneName: string): Promise<SceneResolveResult> {
    const name = sceneName.trim();
    const scenes = await this.findAll();
    const candidates: SceneCandidate[] = scenes.filter((scene: Scene) => name.length > 0 && scene.name.trim() === name)
      .map((scene: Scene): SceneCandidate => ({ id: scene.id, name: scene.name }));
    if (candidates.length === 1) {
      return { status: SceneResolveStatus.RESOLVED, match: candidates[0], candidates: candidates };
    }
    return { status: candidates.length > 1 ? SceneResolveStatus.AMBIGUOUS : SceneResolveStatus.NOT_FOUND,
      candidates: candidates };
  }
}
