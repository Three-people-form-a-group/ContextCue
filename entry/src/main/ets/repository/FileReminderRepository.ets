import { fileIo as fs } from '@kit.CoreFileKit';
import { Reminder } from '../model/Reminder';
import { ReminderRepository } from './ReminderRepository';

interface ReminderDocument {
  version: number;
  reminders: Reminder[];
}

/** 主进程与围栏扩展进程共用同一份文件（同一应用沙箱）。 */
export const REMINDER_STORAGE_FILENAME: string = 'reminders.json';

function copyReminder(reminder: Reminder): Reminder {
  return {
    id: reminder.id,
    content: reminder.content,
    triggerType: reminder.triggerType,
    triggerTime: reminder.triggerTime,
    sceneId: reminder.sceneId,
    sceneName: reminder.sceneName,
    locationTriggerMode: reminder.locationTriggerMode,
    status: reminder.status,
    source: reminder.source,
    createdAt: reminder.createdAt,
    triggeredAt: reminder.triggeredAt,
    completedAt: reminder.completedAt
  };
}

/**
 * 文件版提醒仓储。
 *
 * - 读：文件通过 rename 原子替换，读到的永远是完整版本，因此不加锁。
 * - 写：进程内串行 + 跨进程锁目录（reminders.json.lock），整份文档写入临时文件、
 *   fsync 后 rename 覆盖，满足“save 落盘后才 resolve”。
 * - 锁超过 5 秒视为崩溃遗留，自动清理；等待约 2 秒仍拿不到锁则报
 *   REMINDER_STORAGE_BUSY，交给上层按可重试处理。
 * - 数据损坏时 fail closed（REMINDER_STORAGE_INVALID），不静默清空。
 *
 * 围栏扩展的 FenceReminderStore 只需要 findById / save，本类可以直接作为
 * createFenceReminderStore() 的返回值使用。
 */
export class FileReminderRepository implements ReminderRepository {
  private baseDir: string;
  private gate: Promise<void> = Promise.resolve();

  constructor(baseDir: string) {
    this.baseDir = baseDir;
  }

  private filePath(): string {
    return `${this.baseDir}/${REMINDER_STORAGE_FILENAME}`;
  }

  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }

  private async acquireLock(): Promise<void> {
    // 用目录做锁：mkdir 天然是“不存在才创建”的原子操作（文件 OpenMode 没有 O_EXCL）
    const lockPath: string = `${this.filePath()}.lock`;
    for (let attempt = 0; attempt < 80; attempt++) {
      try {
        fs.mkdirSync(lockPath);
        return;
      } catch (_) {
        try {
          const stat = fs.statSync(lockPath);
          if (Date.now() - stat.mtime * 1000 > 5000) {
            // 上一个进程崩溃留下的锁，清掉后立即重试
            fs.rmdirSync(lockPath);
            continue;
          }
        } catch (_) {
          // 锁刚好被释放
          continue;
        }
        await this.sleep(25);
      }
    }
    throw new Error('REMINDER_STORAGE_BUSY');
  }

  private releaseLock(): void {
    try {
      fs.rmdirSync(`${this.filePath()}.lock`);
    } catch (_) {
    }
  }

  private async exclusive<T>(action: () => T): Promise<T> {
    const previous = this.gate;
    let release: () => void = () => {};
    this.gate = new Promise<void>((resolve: () => void) => {
      release = resolve;
    });
    await previous;
    try {
      await this.acquireLock();
      try {
        return action();
      } finally {
        this.releaseLock();
      }
    } finally {
      release();
    }
  }

  private readAll(): Reminder[] {
    const path: string = this.filePath();
    if (!fs.accessSync(path)) {
      return [];
    }
    const raw: string = fs.readTextSync(path);
    if (raw.trim() === '') {
      throw new Error('REMINDER_STORAGE_INVALID');
    }
    let document: ReminderDocument;
    try {
      document = JSON.parse(raw) as ReminderDocument;
    } catch (_) {
      throw new Error('REMINDER_STORAGE_INVALID');
    }
    if (document === null || document.version !== 1 || !Array.isArray(document.reminders)) {
      throw new Error('REMINDER_STORAGE_INVALID');
    }
    const ids = new Set<string>();
    const reminders: Reminder[] = [];
    for (const reminder of document.reminders) {
      if (reminder === null || typeof reminder.id !== 'string' || reminder.id.trim() === '' ||
        ids.has(reminder.id) || !Number.isFinite(reminder.createdAt) || reminder.createdAt < 0) {
        throw new Error('REMINDER_STORAGE_INVALID');
      }
      ids.add(reminder.id);
      reminders.push(copyReminder(reminder));
    }
    return reminders;
  }

  private writeAll(reminders: Reminder[]): void {
    const path: string = this.filePath();
    const tempPath: string = `${path}.tmp`;
    const document: ReminderDocument = { version: 1, reminders: reminders };
    try {
      const file = fs.openSync(tempPath,
        fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      try {
        fs.writeSync(file.fd, JSON.stringify(document));
        fs.fsyncSync(file.fd);
      } finally {
        fs.closeSync(file);
      }
      fs.renameSync(tempPath, path);
    } catch (_) {
      try {
        fs.unlinkSync(tempPath);
      } catch (_) {
      }
      throw new Error('REMINDER_STORAGE_WRITE_FAILED');
    }
  }

  async save(reminder: Reminder): Promise<void> {
    await this.exclusive((): void => {
      const all: Reminder[] = this.readAll();
      const index: number = all.findIndex((item: Reminder) => item.id === reminder.id);
      if (index >= 0) {
        all[index] = copyReminder(reminder);
      } else {
        all.push(copyReminder(reminder));
      }
      this.writeAll(all);
    });
  }

  async findById(id: string): Promise<Reminder | undefined> {
    const all: Reminder[] = this.readAll();
    return all.find((item: Reminder) => item.id === id);
  }

  async findAll(): Promise<Reminder[]> {
    return this.readAll();
  }

  async deleteById(id: string): Promise<boolean> {
    return await this.exclusive((): boolean => {
      const all: Reminder[] = this.readAll();
      const next: Reminder[] = all.filter((item: Reminder) => item.id !== id);
      if (next.length === all.length) {
        return false;
      }
      this.writeAll(next);
      return true;
    });
  }
}

/** 组合根与围栏扩展共用的工厂：两者传入同一个 filesDir 即可共享数据。 */
export function createFileReminderRepository(baseDir: string): FileReminderRepository {
  return new FileReminderRepository(baseDir);
}
