import { Reminder } from '../../model/Reminder';
import { createFileReminderRepository, FileReminderRepository } from '../../repository/FileReminderRepository';
import { FenceReminderStore } from './FenceReminderStore';

/**
 * Single wiring point between the fence extension and the persistent reminder repository.
 *
 * 持久化仓储（罗鸿程的 FileReminderRepository，原子写 + 跨进程锁目录）已落地：
 * 主进程与围栏扩展进程共用同一沙箱路径（filesDir），本函数直接返回它——
 * FileReminderRepository 的 findById / save 形状与 FenceReminderStore 一致，
 * 且 save 落盘后才 resolve，满足扩展的持久化要求。
 * 「状态更新永远走持久仓储，绝不私存副本」的 V1 规则在此生效。
 */
export function createFenceReminderStore(filesDir: string): FenceReminderStore {
  const repository: FileReminderRepository = createFileReminderRepository(filesDir);
  return new PersistentFenceReminderStore(repository);
}

/** 细粒度适配器：只向扩展暴露 findById / save，隐藏仓储的其余方法。 */
class PersistentFenceReminderStore implements FenceReminderStore {
  private readonly repository: FileReminderRepository;

  constructor(repository: FileReminderRepository) {
    this.repository = repository;
  }

  async findById(id: string): Promise<Reminder | undefined> {
    return this.repository.findById(id);
  }

  async save(reminder: Reminder): Promise<void> {
    await this.repository.save(reminder);
  }
}
