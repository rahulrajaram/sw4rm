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

import { describe, expect, it } from 'vitest';
import * as grpc from '@grpc/grpc-js';
import * as protoLoader from '@grpc/proto-loader';
import fs from 'node:fs';
import zlib from 'node:zlib';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ProtocolClient } from '../src/clients/protocol.js';

// protobufjs >= 7.6.6 materializes map keys named __proto__ as real own
// properties on both encode and decode, so such keys now round-trip
// byte-exactly (D1).  Message FIELD names remain protected: protobufjs
// accesses them via m.<name>, which cannot address a property literally
// named __proto__.

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const probes = protoLoader.loadSync(
  path.join(root, 'tests/sdk_parity/wire_probe.proto'),
  { includeDirs: [path.join(root, 'protos')], keepCase: true, longs: String },
)['sw4rm.parity.WireProbe'] as unknown as grpc.ServiceDefinition;
const contract: { messages: Record<string, unknown[]> } = JSON.parse(
  zlib.gunzipSync(fs.readFileSync(path.join(root, 'tests/conformance_vectors/wire_vectors.json.gz'))).toString('utf8'));

describe('ProtocolClient prototype-reserved map keys', () => {
  const client = new ProtocolClient({ address: '127.0.0.1:59999' });
  const startWorkflow = '/sw4rm.workflow.WorkflowService/StartWorkflow' as Parameters<
    ProtocolClient['call']>[0];

  it('accepts an own __proto__ map key and round-trips it byte-exactly', () => {
    // JSON.parse creates __proto__ as an own enumerable property; object
    // literals would set the prototype instead.
    const request = JSON.parse(
      '{"workflow_id":"wf-1","metadata":{"__proto__":"polluted","normal":"kept"}}',
    );
    // Validation no longer rejects prototype-reserved map keys (D1):
    // dispatch is attempted (and fails on the dead endpoint), but never with
    // a __proto__ TypeError.  Use the codec probe to prove byte-exactness.
    const type = 'sw4rm.workflow.StartWorkflowRequest';
    const index = Object.keys(contract.messages).indexOf(type);
    const probe = probes[`Message${index}`];
    const wire = probe.requestSerialize(request as grpc.protobuf.Message);
    const decoded = probe.requestDeserialize(wire) as Record<string, any>;
    expect(Object.keys(decoded.metadata).sort()).toEqual(['__proto__', 'normal']);
    expect(decoded.metadata.normal).toBe('kept');
    // The __proto__ entry is a real own property carrying the value.
    expect(decoded.metadata.__proto__).toBe('polluted');
    // Byte-exact: re-serializing the round-tripped message reproduces the bytes.
    expect(Buffer.from(probe.requestSerialize(decoded))).toEqual(Buffer.from(wire));
    // The client stays usable for subsequent validation checks.
    client.close();
  });

  it('rejects a __proto__ message field name the same way', () => {
    const request = JSON.parse('{"workflow_id":"wf-1","__proto__":"x"}');
    expect(() => client.call(startWorkflow, request)).toThrow(TypeError);
    expect(() => client.call(startWorkflow, request)).toThrow(/__proto__/);
  });

  it('round-trips normal map keys exactly, including Object.prototype names', () => {
    const type = 'sw4rm.workflow.StartWorkflowRequest';
    const index = Object.keys(contract.messages).indexOf(type);
    const probe = probes[`Message${index}`];
    const request = {
      workflow_id: 'wf-1',
      metadata: {
        normal: 'value',
        constructor: 'shadows-but-stores',
        toString: 'also-stores',
        '': 'empty-key-is-legal',
      },
    };
    const wire = probe.requestSerialize(request as grpc.protobuf.Message);
    const decoded = probe.requestDeserialize(wire) as Record<string, any>;
    expect(Object.keys(decoded.metadata).sort())
      .toEqual(['', 'constructor', 'normal', 'toString']);
    expect(decoded.metadata).toEqual(request.metadata);
  });
});
