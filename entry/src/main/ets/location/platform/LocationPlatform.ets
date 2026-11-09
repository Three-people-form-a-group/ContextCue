import { Scene } from '../../model/Scene';

export interface LocationFix {
  latitude: number;
  longitude: number;
  accuracy: number;
  occurredAt: number;
}

export interface LocationPlatform {
  checkReady(): Promise<void>;
  getCurrentPosition(): Promise<LocationFix>;
  addFence(scene: Scene, enter: () => void, error: (code: string) => void): Promise<number>;
  removeFence(id: number): Promise<void>;
}
