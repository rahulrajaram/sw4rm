import * as grpc from '@grpc/grpc-js';
import { BaseClient, type ClientOptions } from '../internal/baseClient.js';
import { protocolMethods, protocolMessageFields } from './protocolMethods.js';

export { protocolMethods } from './protocolMethods.js';
export type ProtocolRpcPath = keyof typeof protocolMethods;
export type UnaryProtocolRpcPath = {
  [Path in ProtocolRpcPath]: (typeof protocolMethods)[Path]['serverStreaming'] extends false ? Path : never
}[ProtocolRpcPath];
export type StreamingProtocolRpcPath = Exclude<ProtocolRpcPath, UnaryProtocolRpcPath>;
export type ProtocolMessage = Record<string, unknown>;

type WireField = { name: string; kind: string; target: string | null; repeated: boolean; map_entry: boolean;
  enum_values: readonly string[] };
const messageFields: Readonly<Record<string, readonly WireField[]>> = protocolMessageFields;

// Keys that a plain-property map assignment would redirect to the object
// prototype instead of storing.  protobufjs >= 7.6.6 materializes map keys
// named __proto__ as real own properties (util.makeProp) on both encode and
// decode, so map keys now round-trip byte-exactly (D1).  Message FIELD names
// are still guarded: protobufjs accesses them via m.<name>, which cannot
// address a property literally named __proto__.
const ObjectPrototypeKeys: ReadonlySet<string> = new Set(['__proto__']);

function validateInteger(field: WireField, value: unknown, path: string): void {
  const wide = field.kind.endsWith('64');
  if ((typeof value !== 'number' && !(wide && typeof value === 'string'))
      || (typeof value === 'number' && !Number.isSafeInteger(value))
      || (typeof value === 'string' && !/^-?\d+$/.test(value))) {
    throw new TypeError(`${path} requires ${wide ? 'a decimal string or safe integer' : 'an integer'}`);
  }
  const number = BigInt(value);
  const bits = wide ? 64n : 32n;
  const unsigned = field.kind.startsWith('u');
  const min = unsigned ? 0n : -(1n << (bits - 1n));
  const max = unsigned ? (1n << bits) - 1n : (1n << (bits - 1n)) - 1n;
  if (number < min || number > max) throw new RangeError(`${path} is outside ${field.kind}`);
}

function validateMessage(name: string, message: ProtocolMessage, prefix = name, depth = 0): void {
  if (depth > 32 || message === null || typeof message !== 'object' || Array.isArray(message)) {
    throw new TypeError(`${prefix} requires a bounded message object`);
  }
  const fields = messageFields[name];
  for (const [key, value] of Object.entries(message)) {
    if (ObjectPrototypeKeys.has(key)) {
      throw new TypeError(
        `${prefix} field '${key}' is a prototype-reserved key and cannot round-trip through the wire codec`,
      );
    }
    const field = fields.find(field => field.name === key);
    if (!field) throw new TypeError(`Unknown ${name} field: ${key}`);
    if (value === undefined || value === null) continue;
    const path = `${prefix}.${key}`;
    const scalar = (field: WireField, item: unknown, at: string): void => {
      if (field.kind === 'message') validateMessage(field.target!, item as ProtocolMessage, at, depth + 1);
      else if (['int32', 'uint32', 'int64', 'uint64'].includes(field.kind)) validateInteger(field, item, at);
      else if (field.kind === 'enum') {
        if (typeof item === 'number') validateInteger({ ...field, kind: 'int32' }, item, at);
        else if (typeof item !== 'string' || !field.enum_values.includes(item)) {
          throw new TypeError(`${at} requires an enum name or int32 value`);
        }
      } else if (field.kind === 'bytes' && !(item instanceof Uint8Array)) {
        throw new TypeError(`${at} requires bytes`);
      } else if (field.kind === 'string' && typeof item !== 'string') {
        throw new TypeError(`${at} requires a string`);
      } else if (field.kind === 'bool' && typeof item !== 'boolean') {
        throw new TypeError(`${at} requires a boolean`);
      } else if (['float', 'double'].includes(field.kind) && typeof item !== 'number') {
        throw new TypeError(`${at} requires a number`);
      }
    };
    if (field.map_entry) {
      if (typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${path} requires a map object`);
      const valueField = messageFields[field.target!].find(field => field.name === 'value')!;
      for (const [mapKey, item] of Object.entries(value)) {
        // Map keys named __proto__ are ordinary own properties here: the
        // caller constructed them via JSON.parse / Object.fromEntries /
        // Object.defineProperty (an object literal would set the prototype
        // instead).  protobufjs >= 7.6.6 preserves them on the wire (D1).
        scalar(valueField, item, `${path}.${mapKey}`);
      }
    } else if (field.repeated) {
      if (!Array.isArray(value)) throw new TypeError(`${path} requires an array`);
      value.forEach((item, index) => scalar(field, item, `${path}[${index}]`));
    } else scalar(field, value, path);
  }
}

/** Canonical wire access, separate from the local handoff/workflow helpers.
 *
 * Requests use proto field names, Buffer bytes, and decimal strings for 64-bit
 * integers. Responses preserve 64-bit integers as strings. Calls are dispatched
 * once; applications decide whether an uncertain effect may be retried.
 */
export class ProtocolClient extends BaseClient {
  private readonly serviceClients = new Map<string, grpc.Client>();

  constructor(options: ClientOptions) {
    super(options);
  }

  private resolve(path: ProtocolRpcPath, streaming: boolean): { client: grpc.Client; method: string } {
    const definition = protocolMethods[path];
    if (!definition) throw new Error(`Unknown canonical SW4RM RPC: ${path}`);
    if (definition.serverStreaming !== streaming) {
      throw new Error(`${path} requires ${definition.serverStreaming ? 'stream' : 'call'}`);
    }
    const [, service, method] = path.split('/');
    let client = this.serviceClients.get(service);
    if (!client) {
      client = this.getServiceClient<grpc.Client>(service);
      this.serviceClients.set(service, client);
    }
    return { client, method };
  }

  call<Response extends ProtocolMessage = ProtocolMessage>(
    path: UnaryProtocolRpcPath,
    request: ProtocolMessage,
    options: grpc.CallOptions = {},
    metadata?: grpc.Metadata,
  ): Promise<Response> {
    if (protocolMethods[path]) validateMessage(protocolMethods[path].request, request);
    const { client, method } = this.resolve(path, false);
    const invoke = (client as unknown as Record<string, (
      request: ProtocolMessage, metadata: grpc.Metadata, options: grpc.CallOptions,
      callback: (error: grpc.ServiceError | null, response: Response) => void,
    ) => grpc.ClientUnaryCall>)[method];
    return new Promise((resolve, reject) => {
      invoke.call(client, request, this.metadata(metadata),
        { deadline: this.deadlineFromNow(), ...options },
        (error, response) => error ? reject(error) : resolve(response));
    });
  }

  stream<Response extends ProtocolMessage = ProtocolMessage>(
    path: StreamingProtocolRpcPath,
    request: ProtocolMessage,
    options: grpc.CallOptions = {},
    metadata?: grpc.Metadata,
  ): grpc.ClientReadableStream<Response> {
    if (protocolMethods[path]) validateMessage(protocolMethods[path].request, request);
    const { client, method } = this.resolve(path, true);
    const invoke = (client as unknown as Record<string, (
      request: ProtocolMessage, metadata: grpc.Metadata, options: grpc.CallOptions,
    ) => grpc.ClientReadableStream<Response>>)[method];
    return invoke.call(client, request, this.metadata(metadata),
      { deadline: this.deadlineFromNow(), ...options });
  }

  close(): void {
    for (const client of this.serviceClients.values()) client.close();
    this.serviceClients.clear();
  }
}
