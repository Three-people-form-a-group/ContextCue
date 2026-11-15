import { describe, it, expect } from '@ohos/hypium';
import { SceneCatalog } from '../../main/ets/location/scene/SceneCatalog';
import { TextStorage } from '../../main/ets/location/repository/TextStorage';
import { SceneResolveStatus } from '../../main/ets/reminder/contract/SceneResolver';

class MemoryTextStorage implements TextStorage {
  value: string | undefined = undefined;
  fail: boolean = false;
  async read(): Promise<string | undefined> {
    if (this.fail) { throw new Error('STORAGE_FAILED'); }
    return this.value;
  }
  async write(value: string): Promise<void> {
    if (this.fail) { throw new Error('STORAGE_FAILED'); }
    this.value = value;
  }
}

export default function sceneCatalogTest() {
  describe('SceneCatalog', () => {
    it('persists_and_resolves_unique_name_across_instances', 0, async () => {
      const storage = new MemoryTextStorage();
      const catalog = new SceneCatalog(storage, () => 1000, () => 'scene-1', async () => false);
      const scene = await catalog.create({ name: ' 实验室 ', latitude: 31, longitude: 121, radius: 100 });
      expect(scene.name).assertEqual('实验室');
      const restored = new SceneCatalog(storage, () => 2000, () => 'scene-2', async () => false);
      const result = await restored.resolveByName(' 实验室 ');
      expect(result.status).assertEqual(SceneResolveStatus.RESOLVED);
      expect(result.match?.id).assertEqual('scene-1');
      expect((await restored.findById('scene-1'))?.createdAt).assertEqual(1000);
    });
    it('returns_ambiguous_and_not_found_without_guessing', 0, async () => {
      let sequence: number = 0;
      const catalog = new SceneCatalog(new MemoryTextStorage(), () => 1000,
        () => 'scene-' + (++sequence), async () => false);
      await catalog.create({ name: '学校', latitude: 31, longitude: 121, radius: 100 });
      await catalog.create({ name: '学校', latitude: 32, longitude: 120, radius: 100 });
      const result = await catalog.resolveByName('学校');
      expect(result.status).assertEqual(SceneResolveStatus.AMBIGUOUS);
      expect(result.candidates.length).assertEqual(2);
      expect(result.match === undefined).assertTrue();
      expect((await catalog.resolveByName('')).status).assertEqual(SceneResolveStatus.NOT_FOUND);
      expect((await catalog.resolveByName('商店')).status).assertEqual(SceneResolveStatus.NOT_FOUND);
    });
    it('updates_and_deletes_unreferenced_scene', 0, async () => {
      const catalog = new SceneCatalog(new MemoryTextStorage(), () => 1000, () => 's', async () => false);
      await catalog.create({ name: '家', latitude: 31, longitude: 121, radius: 100 });
      await catalog.update('s', { name: '新家', latitude: 32, longitude: 120, radius: 200 });
      expect((await catalog.findById('s'))?.name).assertEqual('新家');
      expect((await catalog.findById('s'))?.createdAt).assertEqual(1000);
      await catalog.delete('s');
      expect((await catalog.findAll()).length).assertEqual(0);
    });
    it('blocks_mutation_while_registered_or_referenced', 0, async () => {
      let referenced: boolean = false;
      const catalog = new SceneCatalog(new MemoryTextStorage(), () => 1000, () => 's', async () => referenced);
      await catalog.create({ name: '家', latitude: 31, longitude: 121, radius: 100 });
      await catalog.acquire('s', 'r');
      let blocked: boolean = false;
      try { await catalog.delete('s'); } catch (_) { blocked = true; }
      expect(blocked).assertTrue();
      await catalog.release('s', 'r');
      referenced = true;
      blocked = false;
      try { await catalog.update('s', { name: '新家', latitude: 31, longitude: 121, radius: 100 }); }
      catch (_) { blocked = true; }
      expect(blocked).assertTrue();
      expect((await catalog.findById('s'))?.name).assertEqual('家');
    });
    it('does_not_hide_storage_failure_or_corrupt_data', 0, async () => {
      const storage = new MemoryTextStorage();
      const catalog = new SceneCatalog(storage, () => 1000, () => 's', async () => false);
      storage.fail = true;
      let failed: boolean = false;
      try { await catalog.resolveByName('家'); } catch (_) { failed = true; }
      expect(failed).assertTrue();
      storage.fail = false;
      storage.value = '{"version":1,"scenes":[{"id":"bad"}]}';
      failed = false;
      try { await catalog.findAll(); } catch (_) { failed = true; }
      expect(failed).assertTrue();
      expect(storage.value).assertEqual('{"version":1,"scenes":[{"id":"bad"}]}');
    });
    it('rejects_invalid_scene_and_preserves_existing_data_on_failed_write', 0, async () => {
      const storage = new MemoryTextStorage();
      const catalog = new SceneCatalog(storage, () => 1000, () => 's', async () => false);
      let failed: boolean = false;
      try { await catalog.create({ name: ' ', latitude: 91, longitude: 121, radius: 0 }); }
      catch (_) { failed = true; }
      expect(failed).assertTrue();
      await catalog.create({ name: '家', latitude: 31, longitude: 121, radius: 100 });
      const saved = storage.value;
      storage.fail = true;
      failed = false;
      try { await catalog.delete('s'); } catch (_) { failed = true; }
      expect(failed).assertTrue();
      expect(storage.value).assertEqual(saved);
    });
  });
}
