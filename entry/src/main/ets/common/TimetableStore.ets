import { DemoCourse, TimetableDemoData } from './TimetableDemoData';
import { SectionSchedule } from './SectionSchedule';

/**
 * 课表 UI 的进程内数据源。
 *
 * 为什么需要它：课表组件在「切到列表 / 切 Tab / 从详情返回」时会重新创建，
 * 组件内的 @State 会跟着重置成演示数据——表现就是「改完再点回来，改动没了」。
 * 把课程和作息放到模块级，组件重建后仍能读到最新数据。
 *
 * 边界：这只解决「App 运行期间的丢失」。
 * 杀进程重启后依然回到演示数据，真正的持久化要等接入 TimetableService。
 * 公共层已有 timetable/TimetableService，但尚未通过 app/AppServices 暴露给页面；
 * 在其接入组合根之前，课表仍用这份 UI 侧驻留数据，接入后整体替换。
 */
export class TimetableStore {
  private static courseList: DemoCourse[] = TimetableDemoData.COURSES.slice();
  private static scheduleConfig: SectionSchedule = SectionSchedule.regular();

  static courses(): DemoCourse[] {
    return TimetableStore.courseList.slice();
  }

  static schedule(): SectionSchedule {
    return TimetableStore.scheduleConfig;
  }

  static setSchedule(schedule: SectionSchedule): void {
    TimetableStore.scheduleConfig = schedule;
  }

  /** 按 id 覆盖或追加 */
  static save(course: DemoCourse): void {
    const next: DemoCourse[] = [];
    let replaced: boolean = false;
    for (let i = 0; i < TimetableStore.courseList.length; i++) {
      if (TimetableStore.courseList[i].id === course.id) {
        next.push(course);
        replaced = true;
      } else {
        next.push(TimetableStore.courseList[i]);
      }
    }
    if (!replaced) {
      next.push(course);
    }
    TimetableStore.courseList = next;
  }

  static remove(id: string): void {
    const next: DemoCourse[] = [];
    for (let i = 0; i < TimetableStore.courseList.length; i++) {
      if (TimetableStore.courseList[i].id !== id) {
        next.push(TimetableStore.courseList[i]);
      }
    }
    TimetableStore.courseList = next;
  }
}
