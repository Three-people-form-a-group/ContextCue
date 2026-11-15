import { geoLocationManager } from '@kit.LocationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Scene } from '../../model/Scene';
import { LocationFix, LocationPlatform } from './LocationPlatform';
import { LocationPermissionManager } from './LocationPermissionManager';

/** The native boundary is replaceable in unit tests; device behavior is verified separately. */
export interface LocationNativeApi {
  current(): Promise<geoLocationManager.Location>;
  supportsWgs84(): boolean;
  active(): Promise<Map<number, geoLocationManager.Geofence>>;
  add(request: geoLocationManager.GnssGeofenceRequest): Promise<number>;
  remove(id: number): Promise<void>;
}

export class HarmonyLocationApi implements LocationNativeApi {
  async current(): Promise<geoLocationManager.Location> {
    const request: geoLocationManager.CurrentLocationRequest = {
      priority: geoLocationManager.LocationRequestPriority.ACCURACY,
      timeoutMs: 10000, maxAccuracy: 100
    };
    return geoLocationManager.getCurrentLocation(request);
  }
  supportsWgs84(): boolean {
    return geoLocationManager.getGeofenceSupportedCoordTypes().includes(geoLocationManager.CoordinateSystemType.WGS84);
  }
  async add(request: geoLocationManager.GnssGeofenceRequest): Promise<number> {
    return geoLocationManager.addGnssGeofence(request);
  }
  async remove(id: number): Promise<void> { await geoLocationManager.removeGnssGeofence(id); }
  async active(): Promise<Map<number, geoLocationManager.Geofence>> {
    return geoLocationManager.getActiveGeoFences();
  }
}

export class HarmonyLocationPlatform implements LocationPlatform {
  private permission: LocationPermissionManager;
  private native: LocationNativeApi;

  constructor(permission: LocationPermissionManager, native: LocationNativeApi = new HarmonyLocationApi()) {
    this.permission = permission;
    this.native = native;
  }

  async checkReady(): Promise<void> {
    await this.permission.checkReady();
    if (!this.native.supportsWgs84()) { throw new Error('LOCATION_WGS84_FENCE_UNSUPPORTED'); }
  }

  async getCurrentPosition(): Promise<LocationFix> {
    await this.permission.checkReady();
    const location = await this.native.current();
    return { latitude: location.latitude, longitude: location.longitude,
      accuracy: location.accuracy, occurredAt: location.timeStamp };
  }

  async addFence(scene: Scene, enter: () => void, error: (code: string) => void): Promise<number> {
    await this.checkReady();
    const request: geoLocationManager.GnssGeofenceRequest = {
      geofence: { latitude: scene.latitude, longitude: scene.longitude, radius: scene.radius,
        coordinateSystemType: geoLocationManager.CoordinateSystemType.WGS84,
        // Positive millisecond lifetime. No undocumented negative/zero "forever" value.
        expiration: Number.MAX_SAFE_INTEGER },
      monitorTransitionEvents: [geoLocationManager.GeofenceTransitionEvent.GEOFENCE_TRANSITION_EVENT_ENTER],
      geofenceTransitionCallback: (failure: BusinessError, transition: geoLocationManager.GeofenceTransition): void => {
        if (failure !== undefined && failure !== null && failure.code !== 0) {
          error('LOCATION_NATIVE_CALLBACK_FAILED');
          return;
        }
        if (transition !== undefined && transition !== null &&
          transition.transitionEvent === geoLocationManager.GeofenceTransitionEvent.GEOFENCE_TRANSITION_EVENT_ENTER) {
          enter();
        }
      }
    };
    // Deliberately omit notifications: only TriggerCoordinator can send the final notification.
    return this.native.add(request);
  }

  async removeFence(id: number): Promise<void> { await this.native.remove(id); }

  /** V1 owns all GNSS fences in this app. Call once on a fresh process, before registering reminders. */
  async recoverOrphanFences(): Promise<void> {
    await this.checkReady();
    const fences = await this.native.active();
    for (const id of fences.keys()) { await this.native.remove(id); }
  }
}
