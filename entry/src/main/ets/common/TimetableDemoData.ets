/**
 * 课程表 UI 演示数据（第一轮专用）。
 *
 * 仅用于验证周视图布局、课程块密度与详情弹层，不属于任何正式模型：
 *   · 不进入 timetable/ 后端，也不进入公共 model/；
 *   · 字段形状对齐《课程表功能说明》里的 CourseDraft，便于后续换成真实数据；
 *   · 接入 TimetableService 后整体删除本文件。
 */
export class DemoCourse {
  readonly id: string;
  readonly name: string;
  readonly teacher: string;
  readonly location: string;
  /** 1=周一 … 7=周日 */
  readonly dayOfWeek: number;
  /** "HH:mm" */
  readonly startTime: string;
  readonly endTime: string;
  /** 上课周次 */
  readonly weeks: number[];
  /** 课程块配色序号（0-3），仅用于演示 */
  readonly tone: number;

  constructor(id: string, name: string, teacher: string, location: string, dayOfWeek: number,
    startTime: string, endTime: string, weeks: number[], tone: number) {
    this.id = id;
    this.name = name;
    this.teacher = teacher;
    this.location = location;
    this.dayOfWeek = dayOfWeek;
    this.startTime = startTime;
    this.endTime = endTime;
    this.weeks = weeks;
    this.tone = tone;
  }
}

function weekRange(start: number, end: number): number[] {
  const out: number[] = [];
  for (let w = start; w <= end; w++) {
    out.push(w);
  }
  return out;
}

export class TimetableDemoData {
  static readonly SEMESTER_NAME: string = '2026-2027 学年第一学期';
  /** 演示用「当前周」 */
  static readonly CURRENT_WEEK: number = 8;
  static readonly TOTAL_WEEKS: number = 16;

  static readonly EMPTY_COURSE: DemoCourse =
    new DemoCourse('', '', '', '', 1, '00:00', '00:00', [], 0);

  static readonly COURSES: DemoCourse[] = [
    new DemoCourse('c1', '高等数学', '张老师', '教三-401', 1, '08:00', '09:40', weekRange(1, 16), 0),
    new DemoCourse('c2', '大学英语', '李老师', '外语楼-203', 1, '10:00', '11:40', weekRange(1, 16), 1),
    new DemoCourse('c3', '数据结构', '王老师', '计算机楼-305', 2, '14:00', '15:40', weekRange(1, 16), 2),
    // 与 c3 在 15:00-15:40 重叠，用于验证同列重叠时的分栏排版
    new DemoCourse('c4', '人工智能导论', '陈老师', '计算机楼-201', 2, '15:00', '16:40', weekRange(1, 16), 3),
    new DemoCourse('c5', '线性代数', '赵老师', '教二-102', 3, '08:00', '09:40', weekRange(1, 8), 4),
    new DemoCourse('c6', '体育', '孙老师', '体育馆', 3, '16:00', '17:40', weekRange(1, 16), 5),
    new DemoCourse('c7', '操作系统', '刘老师', '计算机楼-401', 4, '10:00', '11:40', weekRange(1, 16), 1),
    new DemoCourse('c8', '大学物理', '周老师', '理科楼-201', 5, '08:00', '09:40', weekRange(1, 16), 2),
    // 只在第 9 周之后出现，用于验证切周
    new DemoCourse('c9', '程序设计实验', '吴老师', '实验楼-502', 5, '14:00', '16:30', weekRange(9, 16), 3),
    new DemoCourse('c10', '马克思主义原理', '郑老师', '教一-305', 6, '10:00', '11:40', weekRange(1, 16), 4)
  ];
}
