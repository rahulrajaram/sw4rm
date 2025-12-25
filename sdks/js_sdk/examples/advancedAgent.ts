#!/usr/bin/env npx tsx
/**
 * Advanced agent example demonstrating all SW4RM SDK features.
 *
 * This example shows:
 * - ActivityBuffer usage for tracking agent activities
 * - Worktree binding with policy hooks and state management
 * - Full ACK lifecycle management with all stages
 * - Message processing with type-based handlers
 * - Graceful shutdown with state preservation
 *
 * Prerequisites:
 *   - Install dependencies: `npm install`
 *   - Build the SDK: `npm run build`
 *   - SW4RM services running on default ports
 *
 * Run:
 *   npx tsx examples/advancedAgent.ts --agent-id advanced-1 --name AdvancedAgent
 *
 * Environment Variables:
 *   SW4RM_ROUTER_ADDR   - Router service address (default: localhost:50051)
 *   SW4RM_REGISTRY_ADDR - Registry service address (default: localhost:50052)
 *   DATA_DIR            - Directory for persistent state (default: ./agent_data)
 *
 * @packageDocumentation
 */

import { parseArgs } from 'node:util';
import * as fs from 'node:fs';
import * as path from 'node:path';
import {
  RegistryClient,
  RouterClient,
  WorktreeClient,
  buildEnvelope,
  MessageType,
  AckStage,
  ACKLifecycleManager,
  ActivityBuffer,
} from '../src/index.js';
import type { AgentDescriptor } from '../src/clients/registry.js';
import type { EnvelopeBuilt } from '../src/internal/envelope.js';
import type { ActivityRecord } from '../src/internal/runtime/activityBuffer.js';

// Default addresses
const DEFAULT_ROUTER_ADDR = 'localhost:50051';
const DEFAULT_REGISTRY_ADDR = 'localhost:50052';
const DEFAULT_DATA_DIR = './agent_data';

interface CliArgs {
  agentId: string;
  name: string;
  routerAddr: string;
  registryAddr: string;
  dataDir: string;
}

/**
 * Parse command line arguments.
 */
function parseCliArgs(): CliArgs {
  const { values } = parseArgs({
    options: {
      'agent-id': { type: 'string', default: process.env.AGENT_ID ?? 'advanced-1' },
      name: { type: 'string', default: process.env.AGENT_NAME ?? 'AdvancedAgent' },
      router: { type: 'string', default: process.env.SW4RM_ROUTER_ADDR ?? DEFAULT_ROUTER_ADDR },
      registry: { type: 'string', default: process.env.SW4RM_REGISTRY_ADDR ?? DEFAULT_REGISTRY_ADDR },
      'data-dir': { type: 'string', default: process.env.DATA_DIR ?? DEFAULT_DATA_DIR },
    },
  });

  return {
    agentId: values['agent-id'] as string,
    name: values.name as string,
    routerAddr: values.router as string,
    registryAddr: values.registry as string,
    dataDir: values['data-dir'] as string,
  };
}

/**
 * Message handler function type.
 */
type MessageHandler = (envelope: EnvelopeBuilt) => Promise<string>;

/**
 * Advanced agent with full SDK feature demonstration.
 *
 * This class encapsulates:
 * - Persistent activity buffer for tracking work
 * - Worktree binding with policy enforcement
 * - Full ACK lifecycle tracking
 * - Message routing by type
 */
class AdvancedAgent {
  private readonly agentId: string;
  private readonly name: string;
  private readonly dataDir: string;
  private stopRequested = false;

  // SDK components
  private registry: RegistryClient;
  private router: RouterClient;
  private worktree: WorktreeClient;
  private activityBuffer: ActivityBuffer;
  private ackManager: ACKLifecycleManager;

  // Message handlers by type
  private handlers = new Map<MessageType | number, MessageHandler>();
  private defaultHandler: MessageHandler | null = null;

  // Worktree state
  private currentBinding: { repoId: string; worktreeId: string } | null = null;

  constructor(args: CliArgs) {
    this.agentId = args.agentId;
    this.name = args.name;
    this.dataDir = args.dataDir;

    // Ensure data directory exists
    if (!fs.existsSync(this.dataDir)) {
      fs.mkdirSync(this.dataDir, { recursive: true });
    }

    // Initialize SDK components
    this.registry = new RegistryClient({ address: args.registryAddr });
    this.router = new RouterClient({ address: args.routerAddr });
    this.worktree = new WorktreeClient({ address: args.registryAddr });
    this.activityBuffer = new ActivityBuffer({ maxEntries: 1000 });
    this.ackManager = new ACKLifecycleManager();

    // Load persisted state
    this.loadState();

    // Register message handlers
    this.registerHandlers();
  }

  /**
   * Load persisted state from disk.
   */
  private loadState(): void {
    const activityPath = path.join(this.dataDir, 'activity.json');
    const ackPath = path.join(this.dataDir, 'ack_state.json');
    const worktreePath = path.join(this.dataDir, 'worktree.json');

    try {
      if (fs.existsSync(activityPath)) {
        const data = JSON.parse(fs.readFileSync(activityPath, 'utf-8'));
        this.activityBuffer.fromJSON(data);
        console.log(`[State] Loaded ${data.length} activity records`);
      }
    } catch (err) {
      console.warn('[State] Failed to load activity state:', err);
    }

    try {
      if (fs.existsSync(ackPath)) {
        const data = JSON.parse(fs.readFileSync(ackPath, 'utf-8'));
        this.ackManager.fromJSON(data);
        console.log(`[State] Loaded ${data.length} ACK states`);
      }
    } catch (err) {
      console.warn('[State] Failed to load ACK state:', err);
    }

    try {
      if (fs.existsSync(worktreePath)) {
        const data = JSON.parse(fs.readFileSync(worktreePath, 'utf-8'));
        this.currentBinding = data;
        console.log(`[State] Loaded worktree binding: ${data.repoId}/${data.worktreeId}`);
      }
    } catch (err) {
      console.warn('[State] Failed to load worktree state:', err);
    }
  }

  /**
   * Save current state to disk.
   */
  private saveState(): void {
    const activityPath = path.join(this.dataDir, 'activity.json');
    const ackPath = path.join(this.dataDir, 'ack_state.json');
    const worktreePath = path.join(this.dataDir, 'worktree.json');

    try {
      fs.writeFileSync(activityPath, JSON.stringify(this.activityBuffer.toJSON(), null, 2));
      fs.writeFileSync(ackPath, JSON.stringify(this.ackManager.toJSON(), null, 2));
      if (this.currentBinding) {
        fs.writeFileSync(worktreePath, JSON.stringify(this.currentBinding, null, 2));
      } else if (fs.existsSync(worktreePath)) {
        fs.unlinkSync(worktreePath);
      }
      console.log('[State] Saved state to disk');
    } catch (err) {
      console.error('[State] Failed to save state:', err);
    }
  }

  /**
   * Register message handlers for different message types.
   */
  private registerHandlers(): void {
    // DATA messages - echo with processing info
    this.handlers.set(MessageType.DATA, this.handleData.bind(this));

    // CONTROL messages - handle commands
    this.handlers.set(MessageType.CONTROL, this.handleControl.bind(this));

    // WORKTREE_CONTROL messages - handle worktree operations
    this.handlers.set(MessageType.WORKTREE_CONTROL, this.handleWorktreeControl.bind(this));

    // Default handler for unknown types
    this.defaultHandler = this.handleUnknown.bind(this);
  }

  /**
   * Handle DATA messages - echo back with processing info.
   */
  private async handleData(envelope: EnvelopeBuilt): Promise<string> {
    const messageId = envelope.message_id;
    const payloadSize = envelope.payload?.length ?? 0;

    console.log(`[Data] Processing message ${messageId}, payload size: ${payloadSize}`);

    // Record activity
    const activity: ActivityRecord = {
      task_id: messageId,
      repo_id: this.currentBinding?.repoId ?? 'unbound',
      worktree_id: this.currentBinding?.worktreeId ?? 'unbound',
      branch: 'main',
      description: `Processed DATA message (${payloadSize} bytes)`,
      timestamp: new Date().toISOString(),
    };
    this.activityBuffer.upsert(activity);

    // Create response payload
    const responseData = {
      original_id: messageId,
      processed_at: Date.now(),
      agent_id: this.agentId,
      payload_size: payloadSize,
      worktree: this.currentBinding,
      activity_count: this.activityBuffer.list().length,
    };

    // Send echo response
    const responseEnvelope = buildEnvelope({
      producer_id: this.agentId,
      message_type: MessageType.DATA,
      content_type: 'application/json',
      payload: Buffer.from(JSON.stringify(responseData)),
      correlation_id: envelope.correlation_id,
    });

    try {
      const result = await this.router.sendMessage(responseEnvelope);
      console.log(`[Data] Echo sent: accepted=${result.accepted}`);
      return 'data_processed';
    } catch (err) {
      console.error('[Data] Echo failed:', err);
      return 'data_echo_failed';
    }
  }

  /**
   * Handle CONTROL messages - execute commands.
   */
  private async handleControl(envelope: EnvelopeBuilt): Promise<string> {
    const payload = envelope.payload;
    if (!payload) {
      console.log('[Control] Empty payload');
      return 'empty_control';
    }

    try {
      const controlData = JSON.parse(Buffer.from(payload).toString('utf-8'));
      const command = controlData.command as string;

      console.log(`[Control] Command: ${command}`);

      switch (command) {
        case 'status':
          return this.handleStatusCommand();
        case 'reconcile':
          return this.handleReconcileCommand();
        case 'bind_worktree':
          return this.handleBindWorktreeCommand(controlData);
        case 'unbind_worktree':
          return this.handleUnbindWorktreeCommand();
        default:
          console.log(`[Control] Unknown command: ${command}`);
          return 'unknown_command';
      }
    } catch (err) {
      console.error('[Control] Invalid control message:', err);
      return 'invalid_control';
    }
  }

  /**
   * Handle status command - return agent state.
   */
  private handleStatusCommand(): string {
    const status = {
      agent_id: this.agentId,
      worktree: this.currentBinding,
      activity_buffer: {
        total_records: this.activityBuffer.list().length,
        recent: this.activityBuffer.recent(5),
      },
      ack_states: {
        recent: this.ackManager.recent(10),
      },
    };
    console.log(`[Status] ${JSON.stringify(status, null, 2)}`);
    return 'status_provided';
  }

  /**
   * Handle reconcile command - check for stale ACKs.
   */
  private handleReconcileCommand(): string {
    const recent = this.ackManager.recent(100);
    const stale = recent.filter((ack) => {
      const ageMs = Date.now() - new Date(ack.lastUpdateIso).getTime();
      return ageMs > 30000 && ack.stage < AckStage.FULFILLED;
    });

    console.log(`[Reconcile] Total ACK states: ${recent.length}`);
    console.log(`[Reconcile] Stale states: ${stale.length}`);

    for (const ack of stale.slice(0, 5)) {
      console.log(`[Reconcile] Stale: ${ack.messageId} stage=${ack.stage}`);
    }

    return 'reconcile_completed';
  }

  /**
   * Handle bind worktree command.
   */
  private async handleBindWorktreeCommand(data: Record<string, unknown>): Promise<string> {
    const repoId = data.repo_id as string;
    const worktreeId = data.worktree_id as string;

    if (!repoId || !worktreeId) {
      console.log('[Worktree] Missing repo_id or worktree_id');
      return 'bind_invalid_params';
    }

    try {
      const result = await this.worktree.bind(this.agentId, repoId, worktreeId);
      if (result.ok) {
        this.currentBinding = { repoId, worktreeId };
        console.log(`[Worktree] Bound to ${repoId}/${worktreeId}`);
        return 'bind_success';
      } else {
        console.log(`[Worktree] Bind failed: ${result.reason}`);
        return 'bind_failed';
      }
    } catch (err) {
      console.error('[Worktree] Bind error:', err);
      return 'bind_error';
    }
  }

  /**
   * Handle unbind worktree command.
   */
  private async handleUnbindWorktreeCommand(): Promise<string> {
    if (!this.currentBinding) {
      console.log('[Worktree] Not bound');
      return 'unbind_not_bound';
    }

    try {
      const result = await this.worktree.unbind(this.agentId);
      if (result) {
        console.log(`[Worktree] Unbound from ${this.currentBinding.repoId}/${this.currentBinding.worktreeId}`);
        this.currentBinding = null;
        return 'unbind_success';
      } else {
        console.log('[Worktree] Unbind failed');
        return 'unbind_failed';
      }
    } catch (err) {
      console.error('[Worktree] Unbind error:', err);
      return 'unbind_error';
    }
  }

  /**
   * Handle WORKTREE_CONTROL messages.
   */
  private async handleWorktreeControl(envelope: EnvelopeBuilt): Promise<string> {
    const payload = envelope.payload;
    if (!payload) {
      return 'empty_worktree_control';
    }

    try {
      const wtData = JSON.parse(Buffer.from(payload).toString('utf-8'));
      const action = wtData.action as string;

      console.log(`[WorktreeControl] Action: ${action}`);

      switch (action) {
        case 'bind':
          return this.handleBindWorktreeCommand(wtData);
        case 'unbind':
          return this.handleUnbindWorktreeCommand();
        case 'status':
          console.log(`[WorktreeControl] Current binding: ${JSON.stringify(this.currentBinding)}`);
          return 'status_provided';
        default:
          return 'unknown_worktree_action';
      }
    } catch (err) {
      console.error('[WorktreeControl] Invalid message:', err);
      return 'invalid_worktree_control';
    }
  }

  /**
   * Handle unknown message types.
   */
  private async handleUnknown(envelope: EnvelopeBuilt): Promise<string> {
    console.log(`[Unknown] Received message type: ${envelope.message_type}`);
    return 'unknown_handled';
  }

  /**
   * Register the agent with the registry.
   */
  async register(): Promise<boolean> {
    const descriptor: AgentDescriptor = {
      agent_id: this.agentId,
      name: this.name,
      description: 'Advanced agent demonstrating full SW4RM SDK capabilities',
      capabilities: ['echo', 'control', 'worktree', 'persistence', 'ack_lifecycle'],
      communication_class: 'STANDARD',
      modalities_supported: ['application/json', 'text/plain'],
      reasoning_connectors: [],
    };

    try {
      const result = await this.registry.registerAgent(descriptor);
      console.log(`[Register] Accepted: ${result.accepted}, Reason: ${result.reason ?? 'none'}`);
      return result.accepted;
    } catch (err) {
      console.error('[Register] Failed:', err);
      return false;
    }
  }

  /**
   * Process a single incoming message.
   */
  private async processMessage(envelope: EnvelopeBuilt): Promise<void> {
    const messageId = envelope.message_id;
    const messageType = envelope.message_type;

    console.log(`[Process] Received: type=${messageType} id=${messageId}`);

    // Mark as received
    this.ackManager.mark(messageId, AckStage.RECEIVED);

    // Find handler
    const handler = this.handlers.get(messageType as MessageType) ?? this.defaultHandler;
    if (!handler) {
      console.log(`[Process] No handler for type ${messageType}`);
      this.ackManager.mark(messageId, AckStage.REJECTED, 'no_handler');
      return;
    }

    // Execute handler
    try {
      this.ackManager.mark(messageId, AckStage.READ);
      const result = await handler(envelope);
      this.ackManager.mark(messageId, AckStage.FULFILLED, result);
      console.log(`[Process] Completed: ${result}`);
    } catch (err) {
      console.error('[Process] Handler failed:', err);
      this.ackManager.mark(messageId, AckStage.FAILED, String(err));
    }
  }

  /**
   * Run the main message processing loop.
   */
  async run(): Promise<void> {
    console.log(`[Run] Starting message loop for ${this.agentId}`);

    const stream = this.router.streamIncoming(this.agentId);

    stream.on('data', async (item: { msg: EnvelopeBuilt }) => {
      if (this.stopRequested) return;
      await this.processMessage(item.msg);
    });

    stream.on('error', (err: Error) => {
      console.error('[Run] Stream error:', err.message);
    });

    stream.on('end', () => {
      console.log('[Run] Stream ended');
    });

    // Keep running
    await new Promise(() => {});
  }

  /**
   * Graceful shutdown.
   */
  async shutdown(): Promise<void> {
    if (this.stopRequested) return;
    this.stopRequested = true;

    console.log('[Shutdown] Starting graceful shutdown...');

    // Save state
    console.log('[Shutdown] Saving state...');
    this.saveState();

    // Deregister
    try {
      console.log('[Shutdown] Deregistering agent...');
      await this.registry.deregisterAgent(this.agentId, 'graceful_shutdown');
    } catch (err) {
      console.error('[Shutdown] Deregister failed:', err);
    }

    // Show final status
    console.log('[Shutdown] Final state:');
    console.log(`  Activity buffer: ${this.activityBuffer.list().length} records`);
    console.log(`  Worktree: ${JSON.stringify(this.currentBinding)}`);
    console.log('[Shutdown] Complete');
  }
}

/**
 * Main entry point.
 */
async function main(): Promise<number> {
  const args = parseCliArgs();

  console.log('[Main] Advanced Agent starting...');
  console.log(`[Main] Agent ID: ${args.agentId}`);
  console.log(`[Main] Data directory: ${args.dataDir}`);

  const agent = new AdvancedAgent(args);

  // Setup signal handlers
  const shutdown = async () => {
    await agent.shutdown();
    process.exit(0);
  };

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);

  // Register and run
  if (!(await agent.register())) {
    console.error('[Main] Registration failed, exiting');
    return 1;
  }

  console.log('[Main] Agent ready, starting message loop');

  try {
    await agent.run();
  } catch (err) {
    console.error('[Main] Error:', err);
    await agent.shutdown();
    return 1;
  }

  return 0;
}

// Entry point
main().catch((err) => {
  console.error('[Fatal] Unhandled error:', err);
  process.exit(1);
});
