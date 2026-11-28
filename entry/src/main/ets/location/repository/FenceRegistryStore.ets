import { fileIo as fs } from '@kit.CoreFileKit';
import { FenceMapping, FenceRegistry } from '../platform/LocationPlatform';

/**
 * Durable fence registry shared by the UI process and the fence extension process.
 *
 * Both processes live in the same hap, so they see the same filesDir. Reads are lock free because
 * the file is replaced with rename, so a reader always sees a complete document. Read-modify-write
 * operations take a cross-process lock directory (`fence_registry.json.lock`, mkdir is atomic) so
 * the main process and the fence extension cannot overwrite each other's updates; without it the
 * last writer wins and either loses a delivered marker (duplicate notification) or loses a mapping
 * (NOT_MAPPED). The writer still uses temp file + fsync + rename, and every write failure is fail
 * closed: the instance stops trusting its own state instead of silently dropping a fence record.
 */
export const FENCE_REGISTRY_FILE_NAME: string = 'fence_registry.json';
export const FENCE_REGISTRY_VERSION: number = 1;

/** Codes are documented in docs/location/error-codes.md. */
export const FENCE_REGISTRY_WRITE_FAILED: string = 'FENCE_REGISTRY_WRITE_FAILED';
export const FENCE_REGISTRY_BUSY: string = 'FENCE_REGISTRY_BUSY';
export const FENCE_REGISTRY_REQUIRES_RECOVERY: string = 'FENCE_REGISTRY_REQUIRES_RECOVERY';
export const FENCE_REGISTRY_CORRUPT: string = 'FENCE_REGISTRY_CORRUPT';
export const FENCE_HANDLER_NOT_FOUND: string = 'FENCE_HANDLER_NOT_FOUND';

/** A lock older than this is treated as a crashed process and removed. */
const LOCK_STALE_MS: number = 5000;
/** 80 * 25ms ≈ 2s, same budget as FileReminderRepository. */
const LOCK_ATTEMPTS: number = 80;
const LOCK_RETRY_MS: number = 25;

interface FenceDocument {
  version: number;
  fences: FenceMapping[];
}

function fail(code: string): Error {
  return new Error(code);
}

function copy(mapping: FenceMapping): FenceMapping {
  const clone: FenceMapping = { fenceId: mapping.fenceId, reminderId: mapping.reminderId };
  if (mapping.lastDeliveredAt !== undefined) {
    clone.lastDeliveredAt = mapping.lastDeliveredAt;
  }
  return clone;
}

function validate(text: string): FenceMapping[] {
  let doc: FenceDocument;
  try {
    doc = JSON.parse(text) as FenceDocument;
  } catch (error) {
    throw fail(FENCE_REGISTRY_CORRUPT);
  }
  if (doc === null || doc === undefined || doc.version !== FENCE_REGISTRY_VERSION) {
    throw fail(FENCE_REGISTRY_CORRUPT);
  }
  const raw: FenceMapping[] = doc.fences;
  if (!Array.isArray(raw)) {
    throw fail(FENCE_REGISTRY_CORRUPT);
  }
  const result: FenceMapping[] = [];
  const seenFences: Map<number, boolean> = new Map<number, boolean>();
  const seenReminders: Map<string, boolean> = new Map<string, boolean>();
  for (let index = 0; index < raw.length; index++) {
    const item: FenceMapping = raw[index];
    if (item === null || item === undefined) {
      throw fail(FENCE_REGISTRY_CORRUPT);
    }
    if (typeof item.fenceId !== 'number' || !Number.isInteger(item.fenceId) || item.fenceId < 0) {
      throw fail(FENCE_REGISTRY_CORRUPT);
    }
    if (typeof item.reminderId !== 'string' || item.reminderId.length === 0) {
      throw fail(FENCE_REGISTRY_CORRUPT);
    }
    if (item.lastDeliveredAt !== undefined &&
      (typeof item.lastDeliveredAt !== 'number' || !Number.isFinite(item.lastDeliveredAt))) {
      throw fail(FENCE_REGISTRY_CORRUPT);
    }
    if (seenFences.has(item.fenceId) || seenReminders.has(item.reminderId)) {
      throw fail(FENCE_REGISTRY_CORRUPT);
    }
    seenFences.set(item.fenceId, true);
    seenReminders.set(item.reminderId, true);
    result.push(copy(item));
  }
  return result;
}

export class FileFenceRegistry implements FenceRegistry {
  private path: string;
  private tail: Promise<void> = Promise.resolve();
  private uncertain: boolean = false;

  constructor(filesDir: string) {
    this.path = `${filesDir}/${FENCE_REGISTRY_FILE_NAME}`;
  }

  save(fenceId: number, reminderId: string): Promise<void> {
    return this.mutate((mappings: FenceMapping[]): FenceMapping[] => {
      const next: FenceMapping[] = [];
      for (let index = 0; index < mappings.length; index++) {
        const item = mappings[index];
        // A fence id and a reminder id each address exactly one pair.
        if (item.fenceId === fenceId || item.reminderId === reminderId) {
          continue;
        }
        next.push(copy(item));
      }
      next.push({ fenceId: fenceId, reminderId: reminderId });
      return next;
    });
  }

  find(fenceId: number): Promise<FenceMapping | undefined> {
    return this.readOnly((mappings: FenceMapping[]): FenceMapping | undefined => {
      for (let index = 0; index < mappings.length; index++) {
        if (mappings[index].fenceId === fenceId) {
          return copy(mappings[index]);
        }
      }
      return undefined;
    });
  }

  findByReminder(reminderId: string): Promise<FenceMapping | undefined> {
    return this.readOnly((mappings: FenceMapping[]): FenceMapping | undefined => {
      for (let index = 0; index < mappings.length; index++) {
        if (mappings[index].reminderId === reminderId) {
          return copy(mappings[index]);
        }
      }
      return undefined;
    });
  }

  remove(fenceId: number): Promise<void> {
    return this.mutate((mappings: FenceMapping[]): FenceMapping[] => {
      const next: FenceMapping[] = [];
      for (let index = 0; index < mappings.length; index++) {
        if (mappings[index].fenceId !== fenceId) {
          next.push(copy(mappings[index]));
        }
      }
      return next;
    });
  }

  removeByReminder(reminderId: string): Promise<void> {
    return this.mutate((mappings: FenceMapping[]): FenceMapping[] => {
      const next: FenceMapping[] = [];
      for (let index = 0; index < mappings.length; index++) {
        if (mappings[index].reminderId !== reminderId) {
          next.push(copy(mappings[index]));
        }
      }
      return next;
    });
  }

  markDelivered(fenceId: number, at: number): Promise<void> {
    return this.mutate((mappings: FenceMapping[]): FenceMapping[] => {
      const next: FenceMapping[] = [];
      let found: boolean = false;
      for (let index = 0; index < mappings.length; index++) {
        const item = mappings[index];
        if (item.fenceId === fenceId) {
          found = true;
          const updated: FenceMapping = { fenceId: item.fenceId, reminderId: item.reminderId };
          updated.lastDeliveredAt = at;
          next.push(updated);
        } else {
          next.push(copy(item));
        }
      }
      if (!found) {
        throw fail(FENCE_HANDLER_NOT_FOUND);
      }
      return next;
    });
  }

  clearDelivered(fenceId: number): Promise<void> {
    return this.mutate((mappings: FenceMapping[]): FenceMapping[] => {
      const next: FenceMapping[] = [];
      for (let index = 0; index < mappings.length; index++) {
        const item = mappings[index];
        if (item.fenceId === fenceId) {
          // Dropping the reservation is best effort: a vanished entry needs no release.
          next.push({ fenceId: item.fenceId, reminderId: item.reminderId });
        } else {
          next.push(copy(item));
        }
      }
      return next;
    });
  }

  /**
   * Recovery entry: replace the document with an empty one.
   *
   * A corrupt or previously untrusted document must still be recoverable, so this deliberately
   * skips read()/ensureTrusted() and starts from a clean file. Only a failed write leaves the
   * instance untrusted again. Reminder data (reminders.json) is not touched.
   */
  clear(): Promise<void> {
    return this.enqueue((): Promise<void> => {
      return this.locked((): Promise<void> => {
        this.uncertain = false;
        return this.write([]);
      });
    });
  }

  list(): Promise<FenceMapping[]> {
    return this.readOnly((mappings: FenceMapping[]): FenceMapping[] => {
      const result: FenceMapping[] = [];
      for (let index = 0; index < mappings.length; index++) {
        result.push(copy(mappings[index]));
      }
      return result;
    });
  }

  private mutate(change: (mappings: FenceMapping[]) => FenceMapping[]): Promise<void> {
    return this.enqueue((): Promise<void> => {
      // Read and write must be one critical section across processes, otherwise the main process
      // and the fence extension can each write back a version missing the other's change.
      return this.locked((): Promise<void> => {
        const current = this.read();
        const next = change(current);
        return this.write(next);
      });
    });
  }

  private readOnly<T>(select: (mappings: FenceMapping[]) => T): Promise<T> {
    // No lock: rename replacement guarantees a complete document, so readers never see a torn
    // state and never block writers.
    return this.enqueue((): Promise<T> => {
      return Promise.resolve(select(this.read()));
    });
  }

  private async locked<T>(action: () => Promise<T>): Promise<T> {
    await this.acquireLock();
    try {
      return await action();
    } finally {
      this.releaseLock();
    }
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }

  private lockPath(): string {
    return `${this.path}.lock`;
  }

  /**
   * Cross-process mutual exclusion with a lock directory: mkdir is atomic "create if absent", which
   * plain file OpenMode lacks. Contention is expected but short, so wait ~2s; a lock older than 5s
   * is a dead process's leftover and is removed. On timeout nothing is mutated.
   */
  private async acquireLock(): Promise<void> {
    const lockPath: string = this.lockPath();
    for (let attempt = 0; attempt < LOCK_ATTEMPTS; attempt++) {
      try {
        fs.mkdirSync(lockPath);
        return;
      } catch (_) {
        try {
          const stat = fs.statSync(lockPath);
          if (Date.now() - stat.mtime * 1000 > LOCK_STALE_MS) {
            fs.rmdirSync(lockPath);
            continue;
          }
        } catch (ignored) {
          // The holder released between mkdir and stat; retry immediately.
          continue;
        }
        await this.sleep(LOCK_RETRY_MS);
      }
    }
    throw fail(FENCE_REGISTRY_BUSY);
  }

  private releaseLock(): void {
    try {
      fs.rmdirSync(this.lockPath());
    } catch (ignored) {
      // Already gone (stale cleanup by another process) or the directory never appeared.
    }
  }

  private enqueue<T>(op: () => Promise<T>): Promise<T> {
    const result: Promise<T> = this.tail.then((): Promise<T> => op());
    this.tail = result.then((): void => {
    }, (): void => {
    });
    return result;
  }

  /** Fail closed: after an unreadable/writable state we never guess what the document holds. */
  private ensureTrusted(): void {
    if (this.uncertain) {
      throw fail(FENCE_REGISTRY_REQUIRES_RECOVERY);
    }
  }

  private read(): FenceMapping[] {
    this.ensureTrusted();
    let exists: boolean = false;
    try {
      exists = fs.accessSync(this.path);
    } catch (error) {
      this.uncertain = true;
      throw fail(FENCE_REGISTRY_REQUIRES_RECOVERY);
    }
    if (!exists) {
      return [];
    }
    let text: string = '';
    try {
      text = fs.readTextSync(this.path);
    } catch (error) {
      this.uncertain = true;
      throw fail(FENCE_REGISTRY_REQUIRES_RECOVERY);
    }
    if (text.trim().length === 0) {
      return [];
    }
    return validate(text);
  }

  private write(mappings: FenceMapping[]): Promise<void> {
    this.ensureTrusted();
    const doc: FenceDocument = { version: FENCE_REGISTRY_VERSION, fences: mappings };
    const content = JSON.stringify(doc);
    const temp = `${this.path}.tmp`;
    try {
      const file = fs.openSync(temp, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, content);
        fs.fsyncSync(file.fd);
      } finally {
        fs.closeSync(file);
      }
      fs.renameSync(temp, this.path);
    } catch (error) {
      this.uncertain = true;
      try {
        if (fs.accessSync(temp)) {
          fs.unlinkSync(temp);
        }
      } catch (ignored) {
        // The temp file is disposable; a stuck one is overwritten by the next write.
      }
      throw fail(FENCE_REGISTRY_WRITE_FAILED);
    }
    return Promise.resolve();
  }
}

export function createFileFenceRegistry(filesDir: string): FenceRegistry {
  return new FileFenceRegistry(filesDir);
}
