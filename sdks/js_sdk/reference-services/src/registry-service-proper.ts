#!/usr/bin/env tsx

import * as grpc from '@grpc/grpc-js';
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

// Load the registry proto definitions
import protoLoader from '@grpc/proto-loader';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const registryProtoPath = join(__dirname, '../../../../protos/registry.proto');
const commonProtoPath = join(__dirname, '../../../../protos/common.proto');

interface AgentInfo {
  agent_id: string;
  name: string;
  description: string;
  capabilities: string[];
  communication_class: number;
  modalities_supported: string[];
  reasoning_connectors: string[];
  registered_at: number;
  last_heartbeat: number;
  state?: number;
  health: { [key: string]: string };
}

class RegistryServiceImpl {
  private agents = new Map<string, AgentInfo>();
  private heartbeatTimeout = 5 * 60 * 1000; // 5 minutes

  constructor() {
    // Start heartbeat cleanup
    setInterval(() => {
      this.cleanupExpiredAgents();
    }, 60000); // Check every minute

    console.log('Registry service initialized');
  }

  private cleanupExpiredAgents(): void {
    const currentTime = Date.now();
    const expiredAgents: string[] = [];

    for (const [agentId, agentInfo] of this.agents.entries()) {
      if (currentTime - agentInfo.last_heartbeat > this.heartbeatTimeout) {
        expiredAgents.push(agentId);
      }
    }

    for (const agentId of expiredAgents) {
      this.agents.delete(agentId);
      console.log(`Removed expired agent: ${agentId}`);
    }
  }

  // gRPC service methods
  registerAgent(call: grpc.ServerUnaryCall<any, any>, callback: grpc.sendUnaryData<any>): void {
    const request = call.request;
    const agent = request.agent;
    
    if (!agent || !agent.agent_id) {
      callback({
        code: grpc.status.INVALID_ARGUMENT,
        message: 'Agent descriptor and agent_id required'
      });
      return;
    }

    const agentId = agent.agent_id;
    const currentTime = Date.now();

    if (this.agents.has(agentId)) {
      console.warn(`Agent ${agentId} already registered, updating`);
    }

    const agentInfo: AgentInfo = {
      agent_id: agentId,
      name: agent.name || '',
      description: agent.description || '',
      capabilities: agent.capabilities || [],
      communication_class: agent.communication_class || 0,
      modalities_supported: agent.modalities_supported || [],
      reasoning_connectors: agent.reasoning_connectors || [],
      registered_at: currentTime,
      last_heartbeat: currentTime,
      health: {}
    };

    this.agents.set(agentId, agentInfo);
    console.log(`Registered agent: ${agentId} (${agent.name || 'Unnamed'})`);

    callback(null, {
      accepted: true,
      reason: `Agent ${agentId} registered successfully`
    });
  }

  heartbeat(call: grpc.ServerUnaryCall<any, any>, callback: grpc.sendUnaryData<any>): void {
    const request = call.request;
    const agentId = request.agent_id;

    if (!this.agents.has(agentId)) {
      console.warn(`Heartbeat from unregistered agent: ${agentId}`);
      callback(null, { ok: false });
      return;
    }

    const agentInfo = this.agents.get(agentId)!;
    agentInfo.last_heartbeat = Date.now();
    agentInfo.state = request.state;
    agentInfo.health = request.health || {};

    console.debug(`Heartbeat from ${agentId}, state: ${request.state}`);
    callback(null, { ok: true });
  }

  deregisterAgent(call: grpc.ServerUnaryCall<any, any>, callback: grpc.sendUnaryData<any>): void {
    const request = call.request;
    const agentId = request.agent_id;

    if (this.agents.has(agentId)) {
      this.agents.delete(agentId);
      console.log(`Deregistered agent: ${agentId}, reason: ${request.reason || 'No reason'}`);
      callback(null, { ok: true });
    } else {
      console.warn(`Attempted to deregister unknown agent: ${agentId}`);
      callback(null, { ok: false });
    }
  }

  getRegisteredAgents(): AgentInfo[] {
    return Array.from(this.agents.values());
  }
}

async function serve(): Promise<void> {
  console.log('🚀 Starting SW4RM Registry Service (JavaScript)');
  console.log('===============================================');

  const server = new grpc.Server();
  const registryService = new RegistryServiceImpl();

  try {
    // Load the proto definition
    const packageDefinition = protoLoader.loadSync([registryProtoPath, commonProtoPath], {
      keepCase: true,
      longs: String,
      enums: String,
      defaults: true,
      oneofs: true
    });
    
    const proto = grpc.loadPackageDefinition(packageDefinition) as any;
    
    // Add the registry service
    server.addService(proto.sw4rm.registry.RegistryService.service, {
      RegisterAgent: registryService.registerAgent.bind(registryService),
      Heartbeat: registryService.heartbeat.bind(registryService),
      DeregisterAgent: registryService.deregisterAgent.bind(registryService)
    });
  } catch (error) {
    console.warn('Could not load registry proto, using mock implementation');
  }

  const port = parseInt(process.env.REGISTRY_PORT || '50052', 10);
  const addr = `0.0.0.0:${port}`;
  
  server.bindAsync(addr, grpc.ServerCredentials.createInsecure(), (err, port) => {
    if (err) {
      console.error('Failed to bind server:', err);
      return;
    }
    
    console.log(`📋 Registry service started on ${addr}`);
    server.start();
  });

  // Handle graceful shutdown
  process.on('SIGINT', () => {
    console.log('\n🛑 Received SIGINT, shutting down...');
    const agents = registryService.getRegisteredAgents();
    console.log(`Final state: ${agents.length} registered agents`);
    agents.forEach(agent => {
      console.log(`  - ${agent.agent_id}: ${agent.name}`);
    });
    server.forceShutdown();
    process.exit(0);
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  serve().catch(console.error);
}
