#!/usr/bin/env tsx

import * as grpc from '@grpc/grpc-js';
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

// Load the router proto definitions
import protoLoader from '@grpc/proto-loader';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const routerProtoPath = join(__dirname, '../../../../protos/router.proto');
const commonProtoPath = join(__dirname, '../../../../protos/common.proto');

interface MessageInfo {
  message_id: string;
  producer_id: string;
  message_type: number;
  content_type: string;
  payload_size: number;
  timestamp: number;
  correlation_id: string;
  sequence_number: number;
}

class RouterServiceImpl {
  private agentStreams = new Map<string, grpc.ServerWritableStream<any, any>>();
  private messageLog: MessageInfo[] = [];

  constructor() {
    console.log('Router service initialized');
  }

  // gRPC service methods
  sendMessage(call: grpc.ServerUnaryCall<any, any>, callback: grpc.sendUnaryData<any>): void {
    const request = call.request;
    const envelope = request.msg;
    
    if (!envelope) {
      callback({
        code: grpc.status.INVALID_ARGUMENT,
        message: 'Message envelope required'
      });
      return;
    }

    const messageId = envelope.message_id || this.generateUUID();
    const producerId = envelope.producer_id || '';
    const currentTime = Date.now();

    // Log the message
    const messageInfo: MessageInfo = {
      message_id: messageId,
      producer_id: producerId,
      message_type: envelope.message_type || 0,
      content_type: envelope.content_type || '',
      payload_size: envelope.payload ? envelope.payload.length : 0,
      timestamp: currentTime,
      correlation_id: envelope.correlation_id || '',
      sequence_number: envelope.sequence_number || 0
    };

    this.messageLog.push(messageInfo);

    // ACK messages are routed like any other message so original
    // producers can observe acknowledgements on their inbound stream.
    if (envelope.message_type === 5) {
      console.log(`Received ACK message ${messageId} from ${producerId}`);
    }

    // Route to all agents except sender
    const targetAgents = Array.from(this.agentStreams.keys()).filter(
      agentId => agentId !== producerId
    );

    let deliveredCount = 0;

    for (const agentId of targetAgents) {
      const stream = this.agentStreams.get(agentId);
      if (stream && !stream.destroyed) {
        try {
          stream.write({ msg: envelope });
          deliveredCount++;
          console.debug(`Routed message ${messageId} to ${agentId}`);
        } catch (error) {
          console.warn(`Failed to route message ${messageId} to ${agentId}:`, error);
          this.agentStreams.delete(agentId);
        }
      }
    }

    if (deliveredCount > 0) {
      console.log(`Message ${messageId} delivered to ${deliveredCount} agents`);
      callback(null, {
        accepted: true,
        reason: `Message delivered to ${deliveredCount} recipients`
      });
    } else {
      console.warn(`No recipients found for message ${messageId}`);
      callback(null, {
        accepted: false,
        reason: 'No recipients available'
      });
    }
  }

  streamIncoming(call: grpc.ServerWritableStream<any, any>): void {
    const request = call.request;
    const agentId = request.agent_id;

    if (!agentId) {
      call.emit('error', {
        code: grpc.status.INVALID_ARGUMENT,
        message: 'Agent ID required'
      });
      return;
    }

    console.log(`Starting message stream for agent: ${agentId}`);

    // Store the stream for this agent
    this.agentStreams.set(agentId, call);

    // Handle stream events
    call.on('cancelled', () => {
      console.log(`Stream cancelled for agent: ${agentId}`);
      this.agentStreams.delete(agentId);
    });

    call.on('error', (error: any) => {
      console.error(`Stream error for agent ${agentId}:`, error);
      this.agentStreams.delete(agentId);
    });

    call.on('close', () => {
      console.log(`Stream closed for agent: ${agentId}`);
      this.agentStreams.delete(agentId);
    });
  }

  private generateUUID(): string {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
      const r = Math.random() * 16 | 0;
      const v = c === 'x' ? r : (r & 0x3 | 0x8);
      return v.toString(16);
    });
  }

  getStatus(): any {
    return {
      active_agents: Array.from(this.agentStreams.keys()),
      total_messages: this.messageLog.length,
      active_streams: this.agentStreams.size
    };
  }

  getRecentMessages(limit: number = 10): MessageInfo[] {
    return this.messageLog.slice(-limit);
  }
}

async function serve(): Promise<void> {
  console.log('🚀 Starting SW4RM Router Service (JavaScript)');
  console.log('==============================================');

  const server = new grpc.Server();
  const routerService = new RouterServiceImpl();

  try {
    // Load the proto definition
    const packageDefinition = protoLoader.loadSync([routerProtoPath, commonProtoPath], {
      keepCase: true,
      longs: String,
      enums: String,
      defaults: true,
      oneofs: true
    });
    
    const proto = grpc.loadPackageDefinition(packageDefinition) as any;
    
    // Add the router service
    server.addService(proto.sw4rm.router.RouterService.service, {
      SendMessage: routerService.sendMessage.bind(routerService),
      StreamIncoming: routerService.streamIncoming.bind(routerService)
    });
  } catch (error) {
    console.warn('Could not load router proto, using mock implementation');
  }
  
  const port = parseInt(process.env.ROUTER_PORT || '50051', 10);
  const addr = `0.0.0.0:${port}`;
  
  server.bindAsync(addr, grpc.ServerCredentials.createInsecure(), (err, port) => {
    if (err) {
      console.error('Failed to bind server:', err);
      return;
    }
    
    console.log(`🔀 Router service started on ${addr}`);
    server.start();
  });

  // Handle graceful shutdown
  process.on('SIGINT', () => {
    console.log('\n🛑 Received SIGINT, shutting down...');
    const status = routerService.getStatus();
    console.log('Final state:', status);
    const recentMessages = routerService.getRecentMessages(5);
    recentMessages.forEach(msg => {
      console.log(`  Recent message: ${msg.message_id} from ${msg.producer_id}`);
    });
    server.forceShutdown();
    process.exit(0);
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  serve().catch(console.error);
}
