import { ReminderCardData } from '../components/ReminderCard';
import { MockReminderData } from './MockReminderData';

/**
 * 临时 UI 数据源（过渡层，非团队公共业务层）。
 *
 * 设计要点：
 *   · 数据本身存放在**进程内静态字段**中，页面直接读取，不经过 AppStorage 的对象序列化；
 *   · 只把**数字版本号**放进 AppStorage —— 数字状态的跨组件同步最可靠；
 *   · 任何写入都会递增版本号，页面监听版本号后重新读取数据。
 *
 * 边界：只存 UI 展示类型 ReminderCardData；不落盘、不参与调度、不发送通知。
 * 正式 ReminderService 接入后整体删除。
 */
export class UiReminderStore {
  /** 版本号在 AppStorage 中的键 */
  static readonly KEY_VERSION: string = 'uiReminderVersion';

  private static active: ReminderCardData[] = MockReminderData.TODAY_ACTIVE.slice();
  private static done: ReminderCardData[] = MockReminderData.TODAY_DONE.slice();

  static getVersion(): number {
    const v: number | undefined = AppStorage.get<number>(UiReminderStore.KEY_VERSION);
    return v === undefined ? 0 : v;
  }

  static getActive(): ReminderCardData[] {
    return UiReminderStore.active;
  }

  static getDone(): ReminderCardData[] {
    return UiReminderStore.done;
  }

  /**
   * 按真实时间升序排列；没有时间的条目排在末尾并保持原有相对顺序。
   * 修改时间后，列表顺序会随之改变。
   */
  static sortedActive(): ReminderCardData[] {
    const timed: ReminderCardData[] = [];
    const untimed: ReminderCardData[] = [];
    for (let i = 0; i < UiReminderStore.active.length; i++) {
      const item: ReminderCardData = UiReminderStore.active[i];
      if (item.triggerTime === undefined) {
        untimed.push(item);
      } else {
        timed.push(item);
      }
    }
    timed.sort((a: ReminderCardData, b: ReminderCardData) => {
      const ta: number | undefined = a.triggerTime;
      const tb: number | undefined = b.triggerTime;
      const va: number = ta === undefined ? 0 : ta;
      const vb: number = tb === undefined ? 0 : tb;
      return va - vb;
    });
    return timed.concat(untimed);
  }

  static findById(id: string): ReminderCardData | undefined {
    for (let i = 0; i < UiReminderStore.active.length; i++) {
      if (UiReminderStore.active[i].id === id) {
        return UiReminderStore.active[i];
      }
    }
    for (let i = 0; i < UiReminderStore.done.length; i++) {
      if (UiReminderStore.done[i].id === id) {
        return UiReminderStore.done[i];
      }
    }
    return undefined;
  }

  /** 用同 id 的记录替换；不存在则作为新建追加到 active。 */
  static upsert(next: ReminderCardData): void {
    let replaced: boolean = false;

    for (let i = 0; i < UiReminderStore.active.length; i++) {
      if (UiReminderStore.active[i].id === next.id) {
        UiReminderStore.active[i] = next;
        replaced = true;
      }
    }
    if (!replaced) {
      for (let i = 0; i < UiReminderStore.done.length; i++) {
        if (UiReminderStore.done[i].id === next.id) {
          UiReminderStore.done[i] = next;
          replaced = true;
        }
      }
    }
    if (!replaced) {
      UiReminderStore.active.push(next);
    }

    // 只通知版本号：数字状态的刷新最可靠
    AppStorage.setOrCreate<number>(UiReminderStore.KEY_VERSION, UiReminderStore.getVersion() + 1);
  }
}
