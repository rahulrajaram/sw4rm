import { spawn, spawnSync, type ChildProcess } from 'node:child_process';
import fs from 'node:fs';
import zlib from 'node:zlib';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as grpc from '@grpc/grpc-js';
import * as protoLoader from '@grpc/proto-loader';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { ProtocolClient, protocolMethods, type ProtocolRpcPath,
  type StreamingProtocolRpcPath, type UnaryProtocolRpcPath } from '../src/clients/protocol.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
type Field = { name: string; number: number; kind: string; repeated: boolean; target: string | null; map_entry: boolean };
type Vector = { id: string; type: string; value: Record<string, any>; wire_hex: string };
type Rpc = { path: ProtocolRpcPath; request: string; response: string; server_streaming: boolean };
const contract: { messages: Record<string, Field[]>; vectors: Vector[]; rpcs: Rpc[] } = JSON.parse(
  zlib.gunzipSync(fs.readFileSync(path.join(root, 'tests/conformance_vectors/wire_vectors.json.gz'))).toString('utf8'));
const vectors = new Map(contract.vectors.map(vector => [vector.id, vector]));
const python = process.env.SW4RM_TEST_PYTHON || 'python3';
const hasPython = spawnSync(python, ['-c', 'import grpc'], { stdio: 'ignore' }).status === 0;
const definitions = protoLoader.loadSync(fs.readdirSync(path.join(root, 'protos'))
  .filter(file => file.endsWith('.proto')).map(file => path.join(root, 'protos', file)),
{ keepCase: true, longs: String, enums: String, defaults: true, oneofs: true });

const probes = protoLoader.loadSync(path.join(root, 'tests/sdk_parity/wire_probe.proto'), {
  includeDirs: [path.join(root, 'protos')], keepCase: true, longs: String,
})['sw4rm.parity.WireProbe'] as grpc.ServiceDefinition;

describe('all canonical protobuf messages', () => {
  for (const vector of contract.vectors) {
    it(vector.id, () => {
      const index = Object.keys(contract.messages).indexOf(vector.type);
      const probe = probes[`Message${index}`];
      const expected = requestValue(vector.type, vector.value);
      const wire = Buffer.from(vector.wire_hex, 'hex');
      expect(probe.requestDeserialize(wire)).toEqual(expected);
      expect(probe.requestDeserialize(probe.requestSerialize(expected))).toEqual(expected);
      // Byte canonicality: re-encoding must reproduce the recorded bytes
      // exactly; the corpus writes map keys in sorted order, which matches
      // protobufjs insertion order from the JSON value (R24).
      expect(probe.requestSerialize(expected)).toEqual(wire);
    });
  }
});

function requestValue(name: string, value: Record<string, any>): Record<string, any> {
  const scalar = (field: Field, item: any): any => {
    if (field.kind === 'bytes') return Buffer.from(item, 'hex');
    if (field.kind === 'message') return requestValue(field.target!, item);
    return item;
  };
  return Object.fromEntries(contract.messages[name].filter(field => field.name in value).map(field => {
    const item = value[field.name];
    if (field.map_entry) {
      const valueField = contract.messages[field.target!].find(field => field.name === 'value')!;
      return [field.name, Object.fromEntries(Object.entries(item).map(([key, entry]) => [key, scalar(valueField, entry)]))];
    }
    return [field.name, field.repeated ? item.map((entry: any) => scalar(field, entry)) : scalar(field, item)];
  }));
}

describe.skipIf(!hasPython)('canonical wire RPC contract', () => {
  let child: ChildProcess;
  let client: ProtocolClient;
  beforeAll(async () => {
    child = spawn(python, [path.join(root, 'tests/sdk_parity/wire_contract_server.py')], {
      cwd: root, env: { ...process.env, PYTHONPATH: path.join(root, 'sdks/py_sdk') },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    const port = await new Promise<number>((resolve, reject) => {
      let output = ''; let stderr = '';
      const timer = setTimeout(() => { child.kill('SIGKILL'); reject(new Error(`wire server timeout: ${stderr}`)); }, 10_000);
      child.stderr!.on('data', chunk => { stderr += chunk.toString(); });
      child.stdout!.on('data', chunk => {
        output += chunk.toString();
        for (const line of output.split('\n')) {
          try { const ready = JSON.parse(line); if (ready.ready) { clearTimeout(timer); resolve(ready.port); } } catch { /* partial line */ }
        }
      });
      child.once('error', error => { clearTimeout(timer); reject(error); });
      child.once('exit', code => { clearTimeout(timer); reject(new Error(`wire server exited ${code}: ${stderr}`)); });
    });
    client = new ProtocolClient({ address: `127.0.0.1:${port}`, deadlineMs: 3000 });
  }, 15_000);
  afterAll(async () => {
    client?.close();
    if (child && child.exitCode === null && child.signalCode === null) {
      await new Promise<void>(resolve => {
        const timer = setTimeout(() => { child.kill('SIGKILL'); resolve(); }, 2000);
        child.once('exit', () => { clearTimeout(timer); resolve(); });
        child.kill('SIGTERM');
      });
    }
  });

  for (const rpc of contract.rpcs) {
    for (const variant of ['sample', 'edge']) {
      it(`${rpc.path}:${variant}`, async () => {
        const vector = vectors.get(`${rpc.request}:${variant}`)!;
        const request = requestValue(rpc.request, vector.value);
        const metadata = new grpc.Metadata(); metadata.set('sw4rm-vector', variant);
        const [, service, method] = rpc.path.split('/');
        const definition = (definitions[service] as grpc.ServiceDefinition)[method];
        // Decode expected responses independently through the shipped loader.
        const expected = (v: string) => definition.responseDeserialize(Buffer.from(vectors.get(`${rpc.response}:${v}`)!.wire_hex, 'hex'));
        if (rpc.server_streaming) {
          const stream = client.stream(rpc.path as StreamingProtocolRpcPath, request, {}, metadata);
          const responses: unknown[] = [];
          for await (const response of stream) responses.push(response);
          expect(responses).toEqual([expected('sample'), expected('edge')]);
        } else {
          expect(await client.call(rpc.path as UnaryProtocolRpcPath, request, {}, metadata)).toEqual(expected(variant));
        }
      });
    }
  }
  it('exposes precisely the canonical RPC inventory', () => {
    expect(Object.keys(protocolMethods).sort()).toEqual(contract.rpcs.map(rpc => rpc.path).sort());
  });
  it('preserves grpc errors', async () => {
    const metadata = new grpc.Metadata(); metadata.set('sw4rm-error', '1');
    await expect(client.call('/sw4rm.router.RouterService/SendMessage', {}, {}, metadata)).rejects.toMatchObject({ code: grpc.status.INVALID_ARGUMENT });
  });
  it('rejects precision loss and out-of-range integer fields before dispatch', () => {
    expect(() => client.call('/sw4rm.router.RouterService/AckDelivery', { seq: Number.MAX_SAFE_INTEGER + 1 })).toThrow(/safe integer/);
    expect(() => client.call('/sw4rm.router.RouterService/AckDelivery', { seq: '9223372036854775808' })).toThrow(/outside int64/);
    expect(() => client.call('/sw4rm.handoff.HandoffService/RequestHandoff', { budget: { deadline_epoch_ms: '-1' } })).toThrow(/outside uint64/);
    expect(() => client.call('/sw4rm.handoff.HandoffService/RequestHandoff', { budget: { deadline_epoch_ms: 2 ** 54 } })).toThrow(/safe integer/);
    expect(() => client.call('/sw4rm.handoff.HandoffService/RequestHandoff', { typo: true })).toThrow(/Unknown/);
  });
});
