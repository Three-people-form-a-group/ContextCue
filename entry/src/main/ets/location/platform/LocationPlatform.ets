import { Scene } from '../../model/Scene';

/** Must match module.extensionAbilities[type="fence"].name in entry/src/main/module.json5. */
export const FENCE_EXTENSION_ABILITY_NAME: string = 'LocationFenceAbility';

export interface LocationFix {
  latitude: number;
  longitude: number;
  accuracy: number;
  occurredAt: number;
}

/**
 * Where a fence event is delivered.
 *
 * When a fence request carries a delivery, the system starts the named
 * FenceExtensionAbility even if this app process is dead, so the extension owns delivery and the
 * in-process callback must stay silent. Without a delivery the in-process callback is the only
 * receiver and events die with the process.
 */
export interface FenceDelivery {
  /** entry/src/main/module.json5 -> module.extensionAbilities[type="fence"].name */
  fenceExtensionAbilityName: string;
}

/** One durable fenceId <-> reminderId pair. */
export interface FenceMapping {
  fenceId: number;
  reminderId: string;
  /** Reservation written before the extension publishes, so a repeated event cannot notify twice. */
  lastDeliveredAt?: number;
}

/**
 * Durable fence registry shared by the UI process and the fence extension process.
 * Every method is async because the backing store is on disk (see FileFenceRegistry).
 */
export interface FenceRegistry {
  save(fenceId: number, reminderId: string): Promise<void>;
  find(fenceId: number): Promise<FenceMapping | undefined>;
  findByReminder(reminderId: string): Promise<FenceMapping | undefined>;
  remove(fenceId: number): Promise<void>;
  removeByReminder(reminderId: string): Promise<void>;
  /** Extension-side de-dup reservation, written before the notification is published. */
  markDelivered(fenceId: number, at: number): Promise<void>;
  /** Releases a reservation after a failed publish so the next crossing may notify again. */
  clearDelivered(fenceId: number): Promise<void>;
  list(): Promise<FenceMapping[]>;
}

export interface LocationPlatform {
  checkReady(): Promise<void>;
  getCurrentPosition(): Promise<LocationFix>;
  addFence(scene: Scene, enter: () => void, error: (code: string) => void,
    delivery?: FenceDelivery): Promise<number>;
  removeFence(id: number): Promise<void>;
  /** Fence ids the system currently holds for this app, regardless of who registered them. */
  activeFenceIds(): Promise<number[]>;
  /**
   * Deletes system fences that no durable mapping claims. A fence that still has a mapping is kept
   * because the extension may need it after this process dies; reminder-level accounting happens in
   * LocationReminderAdapter.reconcile().
   */
  recoverOrphanFences(registry: FenceRegistry): Promise<void>;
}
