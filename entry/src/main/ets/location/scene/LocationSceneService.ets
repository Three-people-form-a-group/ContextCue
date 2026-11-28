import { Scene } from '../../model/Scene';
import { LocationPlatform } from '../platform/LocationPlatform';
import { LocationPermissionManager } from '../platform/LocationPermissionManager';
import { SceneCatalog, SceneInput } from './SceneCatalog';

/** 页面可直接展示的定位状态：只覆盖创建场景需要的权限与开关。 */
export enum SceneLocationState {
  READY = 'READY',
  PERMISSION_DENIED = 'PERMISSION_DENIED',
  LOCATION_OFF = 'LOCATION_OFF'
}

function errorCode(error: Object | undefined): string {
  if (error === undefined) { return ''; }
  return (error instanceof Error ? error.message : String(error)).trim();
}

/** updateScene 的结果：场景已写入，但关联提醒可能因为权限等原因没能重新注册。 */
export interface SceneUpdateResult {
  scene: Scene;
  remindersSynced: boolean;
}

/** 组合根注入：把该场景下的 ACTIVE 地点提醒按新几何重新注册，返回是否全部成功。 */
export type SceneGeometrySync = (sceneId: string) => Promise<boolean>;

/**
 * 页面可用的地点能力：列出场景、申请定位权限、用当前位置创建场景。
 *
 * 页面不应该直接依赖围栏、原生定位或权限网关；这里只做组合。
 * 创建场景只要求定位可用，不要求设备支持 GNSS 围栏——设备是否支持围栏
 * 在真正注册地点提醒时才需要判断。
 */
export class LocationSceneService {
  private catalog: SceneCatalog;
  private platform: LocationPlatform;
  private permission: LocationPermissionManager;
  private geometrySync?: SceneGeometrySync;

  constructor(catalog: SceneCatalog, platform: LocationPlatform, permission: LocationPermissionManager) {
    this.catalog = catalog;
    this.platform = platform;
    this.permission = permission;
  }

  /** 组合根在 ReminderService 就绪后注入；服务本身不直接依赖提醒仓储。 */
  setGeometrySync(sync: SceneGeometrySync): void {
    this.geometrySync = sync;
  }

  async list(): Promise<Scene[]> {
    return this.catalog.findAll();
  }

  /**
   * 只改名称和半径，坐标保持场景原值。
   *
   * - 未被提醒引用：普通 update。
   * - 被引用但只改名：允许，围栏不依赖名称。
   * - 被引用且半径变化：允许写入新几何，并通知组合根把该场景的 ACTIVE 地点提醒
   *   重新注册，否则系统围栏仍按旧半径/旧圆心触发。
   */
  async updateScene(id: string, name: string, radius: number): Promise<SceneUpdateResult> {
    const scene = await this.catalog.findById(id);
    if (scene === undefined) {
      throw new Error('SCENE_NOT_FOUND');
    }
    const radiusChanged: boolean = scene.radius !== radius;
    const input: SceneInput = {
      name: name,
      latitude: scene.latitude,
      longitude: scene.longitude,
      radius: radius
    };
    try {
      const updated = await this.catalog.update(id, input);
      return { scene: updated, remindersSynced: true };
    } catch (error) {
      const code: string = errorCode(error);
      if (code !== 'SCENE_IN_USE') {
        throw error as Error;
      }
      if (!radiusChanged) {
        const renamed = await this.catalog.rename(id, name);
        return { scene: renamed, remindersSynced: true };
      }
      const updated = await this.catalog.updateGeometry(id, input);
      let synced: boolean = true;
      if (this.geometrySync !== undefined) {
        try {
          synced = await this.geometrySync(id);
        } catch (_) {
          synced = false;
        }
      }
      return { scene: updated, remindersSynced: synced };
    }
  }

  /** 被提醒引用时 SceneCatalog 会抛 SCENE_IN_USE。 */
  async deleteScene(id: string): Promise<void> {
    await this.catalog.delete(id);
  }

  async state(): Promise<SceneLocationState> {
    try {
      await this.permission.checkReady();
      return SceneLocationState.READY;
    } catch (error) {
      return errorCode(error) === 'LOCATION_SWITCH_OFF'
        ? SceneLocationState.LOCATION_OFF
        : SceneLocationState.PERMISSION_DENIED;
    }
  }

  /** 弹出系统授权；被拒绝时抛出 LOCATION_PERMISSION_DENIED / LOCATION_SWITCH_OFF。 */
  async requestPermission(): Promise<void> {
    await this.permission.request();
  }

  /**
   * 以当前位置为中心创建场景。精度差于半径时不保存：
   * 用户会反复越过边界，产生重复触发。
   */
  async createHere(name: string, radius: number): Promise<Scene> {
    await this.permission.request();
    const fix = await this.platform.getCurrentPosition();
    if (!Number.isFinite(fix.latitude) || !Number.isFinite(fix.longitude) ||
      !Number.isFinite(fix.accuracy) || fix.accuracy < 0 || fix.accuracy > radius) {
      throw new Error('LOCATION_FIX_UNUSABLE');
    }
    return this.catalog.create({
      name: name,
      latitude: fix.latitude,
      longitude: fix.longitude,
      radius: radius
    });
  }
}
