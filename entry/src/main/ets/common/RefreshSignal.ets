/**
 * 提醒数据变更信号。
 *
 * ReminderService 不是 ArkUI 响应式状态，页面在「创建/编辑/完成/删除」成功后
 * 抬高这个版本号，其他页面监听它并按需重新查询服务。
 * 这里只传数字，不承载任何提醒数据。
 */
export class RefreshSignal {
  static readonly KEY: string = 'ccDataVersion';

  static ensure(): void {
    if (AppStorage.get<number>(RefreshSignal.KEY) === undefined) {
      AppStorage.setOrCreate<number>(RefreshSignal.KEY, 0);
    }
  }

  static bump(): void {
    const v: number = AppStorage.get<number>(RefreshSignal.KEY) ?? 0;
    AppStorage.setOrCreate<number>(RefreshSignal.KEY, v + 1);
  }
}
