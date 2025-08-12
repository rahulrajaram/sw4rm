import * as grpc from '@grpc/grpc-js';
import { BaseClient, ClientOptions } from '../internal/baseClient.js';

type ConnectorServiceClient = grpc.Client & {
  RegisterProvider(req: ProviderRegisterRequest, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: ProviderRegisterResponse) => void): void;
  DescribeTools(req: DescribeToolsRequest, meta: grpc.Metadata, opts: grpc.CallOptions, cb: (err: grpc.ServiceError | null, res: DescribeToolsResponse) => void): void;
};

export interface ToolDescriptor {
  tool_name: string;
  input_schema?: string;
  output_schema?: string;
  idempotent?: boolean;
  needs_worktree?: boolean;
  default_timeout_s?: number;
  max_concurrency?: number;
  side_effects?: string;
}

export interface ProviderRegisterRequest { provider_id: string; tools: ToolDescriptor[] }
export interface ProviderRegisterResponse { ok: boolean; reason?: string }
export interface DescribeToolsRequest { provider_id: string }
export interface DescribeToolsResponse { tools: ToolDescriptor[] }

export class ConnectorClient extends BaseClient {
  private client: ConnectorServiceClient;
  constructor(opts: ClientOptions) {
    super(opts);
    this.client = this.getServiceClient<ConnectorServiceClient>('sw4rm.connector.ConnectorService');
  }

  async registerProvider(req: ProviderRegisterRequest): Promise<ProviderRegisterResponse> {
    const meta = this.metadata();
    const opts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    return this.withRetryUnary(() => new Promise<ProviderRegisterResponse>((resolve, reject) => {
      this.client.RegisterProvider(req, meta, opts, (err, res) => {
        if (err) return reject(err);
        resolve(res);
      });
    }));
  }

  async describeTools(providerId: string): Promise<ToolDescriptor[]> {
    const meta = this.metadata();
    const opts: grpc.CallOptions = { deadline: this.deadlineFromNow() };
    return this.withRetryUnary(() => new Promise<ToolDescriptor[]>((resolve, reject) => {
      this.client.DescribeTools({ provider_id: providerId }, meta, opts, (err, res) => {
        if (err) return reject(err);
        resolve(res?.tools ?? []);
      });
    }));
  }
}

