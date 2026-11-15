import { OccurrenceRecord, StoredTimetable } from '../model/TimetableTypes';
import { TimetableRepository } from './TimetableRepository';

/** 开发与验证用内存实现：应用重启后数据不保留，不能当作最终持久化。 */
export class InMemoryTimetableRepository implements TimetableRepository {
  private timetable: StoredTimetable | undefined = undefined;
  private occurrences: OccurrenceRecord[] = [];

  async save(timetable: StoredTimetable, occurrences: OccurrenceRecord[]): Promise<void> {
    this.timetable = timetable;
    this.occurrences = occurrences;
  }

  async find(): Promise<StoredTimetable | undefined> {
    return this.timetable;
  }

  async findOccurrences(): Promise<OccurrenceRecord[]> {
    return this.occurrences;
  }

  async clear(): Promise<void> {
    this.timetable = undefined;
    this.occurrences = [];
  }
}
