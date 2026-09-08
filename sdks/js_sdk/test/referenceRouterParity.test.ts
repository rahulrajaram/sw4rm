import { spawn, spawnSync, type ChildProcessWithoutNullStreams } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { RouterClient, type StreamItem } from '../src/clients/router.js';

type Ready = { ready: true; port: number; agent: string; message_id: string };

const sdkDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repoRoot = path.resolve(sdkDir, '../..');
const pythonCommand = process.env.SW4RM_TEST_PYTHON
  || (process.env.VIRTUAL_ENV ? path.join(process.env.VIRTUAL_ENV, 'bin/python') : 'python3');
const pythonHasGrpc = spawnSync(pythonCommand, ['-c', 'import grpc'], { stdio: 'ignore' }).status === 0;

async function startReferenceRouter(dbPath: string): Promise<{
  ready: Ready;
  process: ChildProcessWithoutNullStreams;
}> {
  const python = pythonCommand;
  const pythonPath = [
    path.join(repoRoot, 'sdks/py_sdk'),
    path.join(repoRoot, 'sdks/py_sdk/reference-services/hive'),
    process.env.PYTHONPATH,
  ].filter(Boolean).join(path.delimiter);
  const child = spawn(
    python,
    [path.join(repoRoot, 'tests/sdk_parity/reference_router_server.py'), '--db', dbPath],
    { cwd: repoRoot, env: { ...process.env, PYTHONPATH: pythonPath } },
  );

  let output = '';
  let errorOutput = '';
  const ready = await new Promise<Ready>((resolve, reject) => {
    const startupTimer = setTimeout(() => { child.kill('SIGKILL'); reject(new Error('reference router startup timeout')); }, 10_000);
    const onOutput = (chunk: Buffer) => {
      output += chunk.toString();
      for (const line of output.split('\n')) {
        try {
          const value = JSON.parse(line) as Ready;
          if (value.ready) {
            clearTimeout(startupTimer);
            resolve(value);
            return;
          }
        } catch {
          // The Python fixture emits warnings on stderr, never readiness data.
        }
      }
    };
    child.stdout.on('data', onOutput);
    child.stderr.on('data', (chunk: Buffer) => { errorOutput += chunk.toString(); });
    child.once('error', (error) => { clearTimeout(startupTimer); reject(error); });
    child.once('exit', (code, signal) => { clearTimeout(startupTimer); reject(new Error(`reference router exited (${code ?? signal}): ${output}\n${errorOutput}`)); });
  });
  return { ready, process: child };
}

async function stopReferenceRouter(child: ChildProcessWithoutNullStreams): Promise<void> {
  if (child.exitCode !== null || child.signalCode !== null) return;
  await new Promise<void>((resolve) => {
    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      resolve();
    }, 2_000);
    child.once('exit', () => {
      clearTimeout(timer);
      resolve();
    });
    child.kill('SIGTERM');
  });
}

function nextStreamItem(stream: NodeJS.EventEmitter): Promise<StreamItem> {
  return new Promise((resolve, reject) => {
    stream.once('data', resolve);
    stream.once('error', reject);
  });
}

describe('JS client against Python reference Router', () => {
  const test = pythonHasGrpc ? it : it.skip;
  test('enforces recipient ownership and exactly-once delivery ACK release', async () => {
    const stateDir = fs.mkdtempSync(path.join(os.tmpdir(), 'sw4rm-js-py-router-'));
    const dbPath = path.join(stateDir, 'router.sqlite3');
    let child: ChildProcessWithoutNullStreams | undefined;
    try {
      const started = await startReferenceRouter(dbPath);
      child = started.process;
      const router = new RouterClient({ address: `127.0.0.1:${started.ready.port}`, deadlineMs: 500 });
      const stream = router.streamIncoming(started.ready.agent);
      const item = await nextStreamItem(stream);
      expect(item.msg.message_id).toBe(started.ready.message_id);
      expect(item.seq).toMatch(/^\d+$/);

      await expect(router.ackDelivery('other-agent', item.seq, item.msg.message_id)).resolves.toEqual({ recorded: false });
      await expect(router.ackDelivery(started.ready.agent, item.seq, item.msg.message_id)).resolves.toEqual({ recorded: true });
      await expect(router.ackDelivery(started.ready.agent, item.seq, item.msg.message_id)).resolves.toEqual({ recorded: false });
      stream.cancel();

      // An explicit stream deadline makes an empty queue end in a
      // bounded DEADLINE_EXCEEDED error and does not leave a live server.
      const empty = router.streamIncoming(started.ready.agent, undefined, { deadline: Date.now() + 500 });
      await expect(new Promise<void>((resolve, reject) => {
        empty.once('end', resolve);
        empty.once('error', (error) => reject(error));
      })).rejects.toMatchObject({ code: 4 });
      empty.cancel();
    } finally {
      if (child) await stopReferenceRouter(child);
      fs.rmSync(stateDir, { recursive: true, force: true });
    }
  }, 15_000);
});
