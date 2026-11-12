import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

/**
 * 便签涂鸦的笔迹存储。
 *
 * 每条提醒一份笔迹，存成文件（preferences 单值有 8KB 限制，笔画多了放不下）：
 *   <filesDir>/doodle_<id>.txt
 * 格式： stroke;stroke;...
 *   stroke = color|width|x1,y1 x2,y2 ...   （坐标是 0~1 的归一化值，换尺寸也不变形）
 *
 * 只属于 UI 层，不进入公共 Reminder 模型。
 */
export class DoodleStore {
  /** 内存缓存：id → 序列化后的笔迹，供列表里的便签直接绘制 */
  private static cache: Map<string, string> = new Map<string, string>();

  private static filePath(context: Context, id: string): string {
    return `${context.filesDir}/doodle_${id}.txt`;
  }

  static get(id: string): string {
    const cached: string | undefined = DoodleStore.cache.get(id);
    return cached === undefined ? '' : cached;
  }

  static has(id: string): boolean {
    const cached: string | undefined = DoodleStore.cache.get(id);
    return cached !== undefined && cached !== '';
  }

  /** 启动时把常用条目读进缓存（读不到就当没有） */
  static load(context: Context, id: string): void {
    try {
      const path: string = DoodleStore.filePath(context, id);
      if (!fs.accessSync(path)) {
        return;
      }
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(path);
      const buffer = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buffer);
      fs.closeSync(file);
      const text: string = new util.TextDecoder().decodeToString(new Uint8Array(buffer));
      DoodleStore.cache.set(id, text);
    } catch (err) {
      // 读失败按空笔迹处理
    }
  }

  static save(context: Context, id: string, data: string): void {
    DoodleStore.cache.set(id, data);
    try {
      const path: string = DoodleStore.filePath(context, id);
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, data);
      fs.closeSync(file);
    } catch (err) {
      // 写失败只影响重启后的保留
    }
  }

  static clear(context: Context, id: string): void {
    DoodleStore.cache.set(id, '');
    try {
      const path: string = DoodleStore.filePath(context, id);
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (err) {
    }
  }
}
