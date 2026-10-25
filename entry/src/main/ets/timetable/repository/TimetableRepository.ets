import { OccurrenceRecord, StoredTimetable } from '../model/TimetableTypes';

/**
 * 课程表内部仓储契约。V1 每个用户只有一张课程表；
 * 正式持久化适配器（RelationalStore 等）后续按同一契约替换内存实现。
 */
export interface TimetableRepository {
  save(timetable: StoredTimetable, occurrences: OccurrenceRecord[]): Promise<void>;
  find(): Promise<StoredTimetable | undefined>;
  findOccurrences(): Promise<OccurrenceRecord[]>;
  clear(): Promise<void>;
}
