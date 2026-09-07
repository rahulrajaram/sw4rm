// Copyright 2025 Rahul Rajaram
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import { describe, it, expect } from 'vitest';

/**
 * Tests binding the real ReasoningClient to the loaded proto service
 * definitions. The gRPC channel is never connected: the internal service
 * client's RPC methods are stubbed per test, but the method surface and the
 * dispatched RPC names must match `reasoning.proto` exactly, so a client
 * that drifts from the canonical protos fails here.
 */

import { ReasoningClient } from '../src/clients/reasoning.js';

const FQN = 'sw4rm.reasoning.ReasoningProxy';

function serviceDefinition(client: ReasoningClient): { rpcNames: string[] } {
  let ns: any = (client as unknown as { root: any }).root;
  for (const part of FQN.split('.')) ns = ns?.[part];
  expect(ns, `service definition not loaded for ${FQN}`).toBeTruthy();
  return { rpcNames: Object.keys(ns.service).sort() };
}

function stubInnerRpc(
  client: ReasoningClient,
  names: string[],
  response: unknown,
): Array<{ rpc: string; req: any }> {
  const calls: Array<{ rpc: string; req: any }> = [];
  const inner = (client as unknown as { client: Record<string, any> }).client;
  for (const name of names) {
    inner[name] = (
      req: any,
      _meta: unknown,
      _opts: unknown,
      cb: (err: null, res: unknown) => void,
    ) => {
      calls.push({ rpc: name, req });
      cb(null, response);
    };
  }
  return calls;
}

describe('ReasoningClient proto binding', () => {
  it('dispatches every RPC defined by reasoning.proto', async () => {
    const client = new ReasoningClient({ address: '127.0.0.1:59999' });
    const { rpcNames } = serviceDefinition(client);
    expect(rpcNames).toEqual(['CheckParallelism', 'EvaluateDebate', 'Summarize']);

    const calls = stubInnerRpc(client, rpcNames, { confidence_score: 0.5 });

    await client.checkParallelism('scope-a', 'scope-b');
    await client.evaluateDebate('neg-1', 'proposal-a', 'proposal-b', 'HIGH');
    await client.summarize('session-1', [
      { kind: 'turn', content: 'hello', seq: 1, at: '2026-01-01T00:00:00Z' },
    ]);

    expect(calls.map((c) => c.rpc).sort()).toEqual(rpcNames);
  });

  it('sends canonical request shapes', async () => {
    const client = new ReasoningClient({ address: '127.0.0.1:59999' });
    const { rpcNames } = serviceDefinition(client);
    const calls = stubInnerRpc(client, rpcNames, {
      summary: 's',
      tokens: 12,
      cost_cents: 0.3,
      model: 'm',
    });

    await client.summarize(
      'session-1',
      [{ kind: 'turn', content: 'hello', seq: 1, at: '2026-01-01T00:00:00Z' }],
      256,
      'brief',
    );

    const summarizeCall = calls.find((c) => c.rpc === 'Summarize');
    expect(summarizeCall!.req).toEqual({
      session_id: 'session-1',
      segments: [
        { kind: 'turn', content: 'hello', seq: 1, at: '2026-01-01T00:00:00Z' },
      ],
      max_tokens: 256,
      mode: 'brief',
    });
  });

  it('propagates the Summarize response', async () => {
    const client = new ReasoningClient({ address: '127.0.0.1:59999' });
    const { rpcNames } = serviceDefinition(client);
    stubInnerRpc(client, rpcNames, {
      summary: 'the gist',
      tokens: 12,
      cost_cents: 0.3,
      model: 'test-model',
    });

    const res = await client.summarize('session-1', []);
    expect(res).toEqual({
      summary: 'the gist',
      tokens: 12,
      cost_cents: 0.3,
      model: 'test-model',
    });
  });
});
