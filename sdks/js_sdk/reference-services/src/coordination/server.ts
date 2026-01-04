#!/usr/bin/env tsx

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

/**
 * SW4RM Coordination Services Server.
 *
 * This module provides a unified gRPC server that hosts all three coordination
 * services:
 * - HandoffService
 * - WorkflowService
 * - NegotiationRoomService
 *
 * All services run on the same port and can be accessed by any SDK client
 * (Python, Rust, TypeScript).
 *
 * Usage:
 *   # Run with default settings (port 50060)
 *   npx tsx src/coordination/server.ts
 *
 *   # Run with custom port
 *   npx tsx src/coordination/server.ts --port 50061
 *
 * Environment variables:
 *   COORDINATION_PORT: gRPC server port (default: 50060)
 */

import * as grpc from '@grpc/grpc-js';
import * as protoLoader from '@grpc/proto-loader';
import { Command } from 'commander';
import path from 'path';
import { fileURLToPath } from 'url';

import { HandoffServiceImpl } from './handoff-service.js';
import { WorkflowServiceImpl } from './workflow-service.js';
import { NegotiationRoomServiceImpl } from './negotiation-room-service.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Proto paths
const PROTO_DIR = path.resolve(__dirname, '../../../../../protos');

const DEFAULT_PORT = 50060;

interface ServerOptions {
  port: number;
  verbose: boolean;
}

/**
 * Load a proto file and return the gRPC package definition.
 */
function loadProto(protoName: string): grpc.GrpcObject {
  const protoPath = path.join(PROTO_DIR, `${protoName}.proto`);

  const packageDefinition = protoLoader.loadSync(protoPath, {
    keepCase: true,
    longs: String,
    enums: String,
    defaults: true,
    oneofs: true,
    includeDirs: [PROTO_DIR],
  });

  return grpc.loadPackageDefinition(packageDefinition);
}

/**
 * Coordination server class that hosts all three services.
 */
export class CoordinationServer {
  private server: grpc.Server;
  public handoffService: HandoffServiceImpl;
  public workflowService: WorkflowServiceImpl;
  public negotiationRoomService: NegotiationRoomServiceImpl;
  private port: number;

  constructor(options: ServerOptions) {
    this.port = options.port;
    this.server = new grpc.Server();

    // Initialize services
    this.handoffService = new HandoffServiceImpl();
    this.workflowService = new WorkflowServiceImpl();
    this.negotiationRoomService = new NegotiationRoomServiceImpl();

    // Load proto definitions and register services
    try {
      this.registerServices();
    } catch (error) {
      console.error('Failed to register services:', error);
      throw error;
    }
  }

  private registerServices(): void {
    // Load Handoff proto
    const handoffProto = loadProto('handoff') as any;
    const HandoffService = handoffProto.sw4rm?.handoff?.HandoffService;
    if (HandoffService) {
      this.server.addService(HandoffService.service, this.handoffService.getHandlers());
      console.log('  - HandoffService registered');
    } else {
      console.warn('  - HandoffService: proto not found, skipping');
    }

    // Load Workflow proto
    const workflowProto = loadProto('workflow') as any;
    const WorkflowService = workflowProto.sw4rm?.workflow?.WorkflowService;
    if (WorkflowService) {
      this.server.addService(WorkflowService.service, this.workflowService.getHandlers());
      console.log('  - WorkflowService registered');
    } else {
      console.warn('  - WorkflowService: proto not found, skipping');
    }

    // Load NegotiationRoom proto
    const negotiationRoomProto = loadProto('negotiation_room') as any;
    const NegotiationRoomService = negotiationRoomProto.sw4rm?.negotiation_room?.NegotiationRoomService;
    if (NegotiationRoomService) {
      this.server.addService(
        NegotiationRoomService.service,
        this.negotiationRoomService.getHandlers()
      );
      console.log('  - NegotiationRoomService registered');
    } else {
      console.warn('  - NegotiationRoomService: proto not found, skipping');
    }
  }

  /**
   * Start the gRPC server.
   */
  start(): Promise<void> {
    return new Promise((resolve, reject) => {
      const address = `0.0.0.0:${this.port}`;

      this.server.bindAsync(
        address,
        grpc.ServerCredentials.createInsecure(),
        (error, port) => {
          if (error) {
            reject(error);
            return;
          }

          console.log(`Coordination server started on ${address}`);
          resolve();
        }
      );
    });
  }

  /**
   * Stop the gRPC server gracefully.
   */
  stop(): Promise<void> {
    return new Promise((resolve) => {
      console.log('Stopping server...');
      this.server.tryShutdown(() => {
        console.log('Server stopped');
        resolve();
      });
    });
  }

  /**
   * Force shutdown the server.
   */
  forceShutdown(): void {
    this.server.forceShutdown();
    console.log('Server force shutdown');
  }

  /**
   * Clear all service state (for testing).
   */
  clearAll(): void {
    this.handoffService.clearAll();
    this.workflowService.clearAll();
    this.negotiationRoomService.clearAll();
    console.log('All service state cleared');
  }
}

/**
 * Parse command line arguments.
 */
function parseArgs(): ServerOptions {
  const program = new Command();

  program
    .name('coordination-server')
    .description('SW4RM Coordination Services Server')
    .option(
      '-p, --port <number>',
      'Port to listen on',
      String(process.env.COORDINATION_PORT || DEFAULT_PORT)
    )
    .option('-v, --verbose', 'Enable verbose logging', false)
    .parse(process.argv);

  const opts = program.opts();

  return {
    port: parseInt(opts.port, 10),
    verbose: opts.verbose,
  };
}

/**
 * Main entry point.
 */
async function main(): Promise<void> {
  console.log('Starting SW4RM Coordination Services (TypeScript)');
  console.log('=================================================');

  const options = parseArgs();

  const server = new CoordinationServer(options);

  // Handle graceful shutdown
  process.on('SIGINT', async () => {
    console.log('\nReceived SIGINT, shutting down...');
    await server.stop();
    process.exit(0);
  });

  process.on('SIGTERM', async () => {
    console.log('\nReceived SIGTERM, shutting down...');
    await server.stop();
    process.exit(0);
  });

  try {
    console.log('Registering services:');
    await server.start();
  } catch (error) {
    console.error('Failed to start server:', error);
    process.exit(1);
  }
}

// Run if executed directly
if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch(console.error);
}

export { main };
