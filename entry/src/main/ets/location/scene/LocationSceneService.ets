import { Scene } from '../../model/Scene';
import { LocationPlatform } from '../platform/LocationPlatform';
import { LocationPermissionManager } from '../platform/LocationPermissionManager';
import { SceneCatalog } from './SceneCatalog';

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

  constructor(catalog: SceneCatalog, platform: LocationPlatform, permission: LocationPermissionManager) {
    this.catalog = catalog;
    this.platform = platform;
    this.permission = permission;
  }

  async list(): Promise<Scene[]> {
    return this.catalog.findAll();
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
