import { fileIo as fs } from '@kit.CoreFileKit';
import { OccurrenceRecord, StoredTimetable } from '../model/TimetableTypes';
import { TimetableRepository } from './TimetableRepository';

interface TimetableDocument {
  version: number;
  timetable: StoredTimetable | null;
  occurrences: OccurrenceRecord[];
}

export const TIMETABLE_STORAGE_FILENAME: string = 'timetable.json';

/**
 * 文件版课表仓储。课表与“课表→提醒”的台账放在同一份文档里：
 * 两者必须一起原子替换，否则崩溃后会留下“新课表 + 旧台账”的不一致。
 *
 * 只有主进程访问，不需要跨进程锁；进程内串行 + 临时文件 + fsync + rename 即可。
 * 数据损坏时 fail closed，交给上层报 TIMETABLE_STORE_ERROR。
 */
export class FileTimetableRepository implements TimetableRepository {
  private baseDir: string;
  private gate: Promise<void> = Promise.resolve();

  constructor(baseDir: string) {
    this.baseDir = baseDir;
  }

  private filePath(): string {
    return `${this.baseDir}/${TIMETABLE_STORAGE_FILENAME}`;
  }

  private async exclusive<T>(action: () => T): Promise<T> {
    const previous = this.gate;
    let release: () => void = () => {};
    this.gate = new Promise<void>((resolve: () => void) => {
      release = resolve;
    });
    await previous;
    try {
      return action();
    } finally {
      release();
    }
  }

  private readDocument(): TimetableDocument {
    const path: string = this.filePath();
    if (!fs.accessSync(path)) {
      return { version: 1, timetable: null, occurrences: [] };
    }
    const raw: string = fs.readTextSync(path);
    if (raw.trim() === '') {
      throw new Error('TIMETABLE_STORAGE_INVALID');
    }
    let document: TimetableDocument;
    try {
      document = JSON.parse(raw) as TimetableDocument;
    } catch (_) {
      throw new Error('TIMETABLE_STORAGE_INVALID');
    }
    if (document === null || document.version !== 1 || !Array.isArray(document.occurrences)) {
      throw new Error('TIMETABLE_STORAGE_INVALID');
    }
    if (document.timetable !== null) {
      const timetable = document.timetable;
      if (typeof timetable !== 'object' || typeof timetable.id !== 'string' ||
        typeof timetable.semesterName !== 'string' || typeof timetable.anchorDate !== 'string' ||
        !Number.isFinite(timetable.anchorWeek) || !Array.isArray(timetable.courses)) {
        throw new Error('TIMETABLE_STORAGE_INVALID');
      }
    }
    const occurrences: OccurrenceRecord[] = [];
    for (const item of document.occurrences) {
      if (item === null || typeof item.key !== 'string' || item.key.trim() === '' ||
        typeof item.reminderId !== 'string' || item.reminderId.trim() === '' ||
        typeof item.courseId !== 'string' || !Number.isFinite(item.week)) {
        throw new Error('TIMETABLE_STORAGE_INVALID');
      }
      occurrences.push({
        key: item.key,
        reminderId: item.reminderId,
        week: item.week,
        courseId: item.courseId
      });
    }
    return { version: 1, timetable: document.timetable, occurrences: occurrences };
  }

  private writeDocument(document: TimetableDocument): void {
    const path: string = this.filePath();
    const tempPath: string = `${path}.tmp`;
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
      throw new Error('TIMETABLE_STORAGE_WRITE_FAILED');
    }
  }

  async save(timetable: StoredTimetable, occurrences: OccurrenceRecord[]): Promise<void> {
    await this.exclusive((): void => {
      this.writeDocument({ version: 1, timetable: timetable, occurrences: occurrences });
    });
  }

  async find(): Promise<StoredTimetable | undefined> {
    const document = this.readDocument();
    return document.timetable === null ? undefined : document.timetable;
  }

  async findOccurrences(): Promise<OccurrenceRecord[]> {
    return this.readDocument().occurrences;
  }

  async clear(): Promise<void> {
    await this.exclusive((): void => {
      try {
        fs.unlinkSync(this.filePath());
      } catch (_) {
      }
    });
  }
}

export function createFileTimetableRepository(baseDir: string): FileTimetableRepository {
  return new FileTimetableRepository(baseDir);
}
