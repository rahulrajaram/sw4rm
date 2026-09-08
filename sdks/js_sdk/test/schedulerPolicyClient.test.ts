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
 * Tests binding the real SchedulerPolicyClient to the loaded proto service
 * definitions. The gRPC channel is never connected: the internal service
 * client's RPC methods are stubbed per test, but the method surface and the
 * dispatched RPC names must match `scheduler_policy.proto` exactly, so a
 * client that drifts from the canonical protos fails here.
 */

import { SchedulerPolicyClient } from '../src/clients/schedulerPolicy.js';

const FQN = 'sw4rm.scheduler.SchedulerPolicyService';

function serviceDefinition(client: SchedulerPolicyClient): { rpcNames: string[] } {
  // BaseClient holds the loaded PackageDefinition root; resolve the service
  // definition the same way getServiceClient does.
  let ns: any = (client as unknown as { root: any }).root;
  for (const part of FQN.split('.')) ns = ns?.[part];
  expect(ns, `service definition not loaded for ${FQN}`).toBeTruthy();
  return { rpcNames: Object.keys(ns.service).sort() };
}

function stubInnerRpc(
  client: SchedulerPolicyClient,
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

describe('SchedulerPolicyClient proto binding', () => {
  it('dispatches every RPC defined by scheduler_policy.proto', async () => {
    const client = new SchedulerPolicyClient({ address: '127.0.0.1:59999' });
    const { rpcNames } = serviceDefinition(client);
    expect(rpcNames).toEqual([
      'GetEffectivePolicy',
      'GetNegotiationPolicy',
      'HitlAction',
      'ListPolicyProfiles',
      'SetNegotiationPolicy',
      'SetPolicyProfiles',
      'SubmitEvaluation',
    ]);

    const calls = stubInnerRpc(client, rpcNames, { ok: true });

    await client.setNegotiationPolicy({ max_rounds: 5 });
    await client.getNegotiationPolicy();
    await client.setPolicyProfiles([]);
    await client.listPolicyProfiles();
    await client.getEffectivePolicy('neg-1');
    await client.submitEvaluation('neg-1', { confidence_score: 0.9 });
    await client.hitlAction('neg-1', 'approve', 'looks good');

    expect(calls.map((c) => c.rpc).sort()).toEqual(rpcNames);
  });

  it('sends canonical request shapes', async () => {
    const client = new SchedulerPolicyClient({ address: '127.0.0.1:59999' });
    const { rpcNames } = serviceDefinition(client);
    const calls = stubInnerRpc(client, rpcNames, { ok: true });

    await client.setNegotiationPolicy({ max_rounds: 5 });
    await client.getNegotiationPolicy();
    await client.getEffectivePolicy('neg-1');
    await client.submitEvaluation('neg-1', { confidence_score: 0.9 });
    await client.hitlAction('neg-1', 'approve', 'looks good');

    expect(calls.find((c) => c.rpc === 'SetNegotiationPolicy')!.req).toEqual({
      policy: { max_rounds: 5 },
    });
    expect(calls.find((c) => c.rpc === 'GetNegotiationPolicy')!.req).toEqual({});
    expect(calls.find((c) => c.rpc === 'GetEffectivePolicy')!.req).toEqual({
      negotiation_id: 'neg-1',
    });
    expect(calls.find((c) => c.rpc === 'SubmitEvaluation')!.req).toEqual({
      negotiation_id: 'neg-1',
      report: { confidence_score: 0.9 },
    });
    expect(calls.find((c) => c.rpc === 'HitlAction')!.req).toEqual({
      negotiation_id: 'neg-1',
      action: 'approve',
      rationale: 'looks good',
    });
  });

  it('propagates the RPC response', async () => {
    const client = new SchedulerPolicyClient({ address: '127.0.0.1:59999' });
    const { rpcNames } = serviceDefinition(client);
    stubInnerRpc(client, rpcNames, { ok: true, reason: 'because' });

    const res = await client.setNegotiationPolicy({});
    expect(res).toEqual({ ok: true, reason: 'because' });
  });
});
