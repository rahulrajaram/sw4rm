import fsp from 'node:fs/promises';
import path from 'node:path';

export interface PersistenceBackend {
  saveActivity(records: any[]): Promise<void>;
  loadActivity(): Promise<any[]>;
  saveAcks(states: any[]): Promise<void>;
  loadAcks(): Promise<any[]>;
}

export class JSONFilePersistence implements PersistenceBackend {
  private activityFile: string;
  private acksFile: string;

  constructor(private baseDir: string) {
    this.activityFile = path.join(baseDir, 'activity.json');
    this.acksFile = path.join(baseDir, 'acks.json');
  }

  private async safeWrite(file: string, data: string) {
    await fsp.mkdir(path.dirname(file), { recursive: true });
    const tmp = `${file}.tmp-${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
    let handle: Awaited<ReturnType<typeof fsp.open>> | undefined;
    try {
      handle = await fsp.open(tmp, 'w');
      await handle.writeFile(data, 'utf8');
      await handle.sync();
      await handle.close();
      handle = undefined;
      await fsp.rename(tmp, file);
      const dir = await fsp.open(path.dirname(file), 'r');
      try {
        await dir.sync();
      } finally {
        await dir.close();
      }
    } catch (error) {
      if (handle) await handle.close().catch(() => undefined);
      await fsp.unlink(tmp).catch(() => undefined);
      throw error;
    }
  }

  async saveActivity(records: any[]): Promise<void> {
    const payload = JSON.stringify(records, null, 2);
    await this.safeWrite(this.activityFile, payload);
  }

  async loadActivity(): Promise<any[]> {
    try {
      const buf = await fsp.readFile(this.activityFile, 'utf8');
      return JSON.parse(buf);
    } catch (e: any) {
      if (e?.code === 'ENOENT') return [];
      throw e;
    }
  }

  async saveAcks(states: any[]): Promise<void> {
    const payload = JSON.stringify(states, null, 2);
    await this.safeWrite(this.acksFile, payload);
  }

  async loadAcks(): Promise<any[]> {
    try {
      const buf = await fsp.readFile(this.acksFile, 'utf8');
      return JSON.parse(buf);
    } catch (e: any) {
      if (e?.code === 'ENOENT') return [];
      throw e;
    }
  }
}
