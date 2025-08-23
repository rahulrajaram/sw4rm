#!/usr/bin/env tsx

import * as grpc from '@grpc/grpc-js';
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

// Load the scheduler proto definitions  
import protoLoader from '@grpc/proto-loader';
import { spawn } from 'node:child_process';
import path from 'node:path';
import fs from 'node:fs';

// SDK clients and helpers
import { RegistryClient, RouterClient, buildEnvelope, MessageType } from '../../../../sdks/js_sdk/src/index.ts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const schedulerProtoPath = join(__dirname, '../../../../protos/scheduler.proto');
const commonProtoPath = join(__dirname, '../../../../protos/common.proto');

interface TaskInfo {
  task_id: string;
  agent_id: string;
  priority: number;
  params: Buffer;
  content_type: string;
  scope: string;
  submitted_at: number;
}

interface ActivityEntry {
  task_id: string;
  repo_id: string;
  worktree_id: string;
  branch: string;
  description: string;
  timestamp: string;
}

class SchedulerServiceImpl {
  private tasks = new Map<string, TaskInfo>();
  private activityBuffer = new Map<string, ActivityEntry[]>();

  constructor() {
    console.log('Scheduler service initialized');
  }

  submitTask(call: grpc.ServerUnaryCall<any, any>, callback: grpc.sendUnaryData<any>): void {
    const request = call.request;
    const task_id = request.task_id || this.generateUUID();
    const current_time = Date.now();

    const taskInfo: TaskInfo = {
      task_id,
      agent_id: request.agent_id || '',
      priority: request.priority || 0,
      params: request.params || Buffer.alloc(0),
      content_type: request.content_type || '',
      scope: request.scope || '',
      submitted_at: current_time
    };

    this.tasks.set(task_id, taskInfo);
    console.log(`Submitted task ${task_id} for agent ${request.agent_id}`);

    callback(null, {
      accepted: true,
      reason: `Task ${task_id} submitted successfully`
    });
  }

  requestPreemption(call: grpc.ServerUnaryCall<any, any>, callback: grpc.sendUnaryData<any>): void {
    const request = call.request;
    console.log(`Preemption requested for task ${request.task_id} (agent ${request.agent_id}): ${request.reason}`);
    
    // For this simple implementation, we'll just acknowledge the preemption
    callback(null, { enqueued: true });
  }

  shutdownAgent(call: grpc.ServerUnaryCall<any, any>, callback: grpc.sendUnaryData<any>): void {
    const request = call.request;
    console.log(`Shutdown requested for agent ${request.agent_id}`);
    
    // Remove all tasks for this agent
    const tasksToRemove: string[] = [];
    for (const [task_id, taskInfo] of this.tasks.entries()) {
      if (taskInfo.agent_id === request.agent_id) {
        tasksToRemove.push(task_id);
      }
    }
    
    for (const task_id of tasksToRemove) {
      this.tasks.delete(task_id);
    }
    
    // Clear activity buffer for this agent
    this.activityBuffer.delete(request.agent_id);
    
    callback(null, { ok: true });
  }

  pollActivityBuffer(call: grpc.ServerUnaryCall<any, any>, callback: grpc.sendUnaryData<any>): void {
    const request = call.request;
    console.debug(`Polling activity buffer for agent ${request.agent_id}`);
    
    const entries = this.activityBuffer.get(request.agent_id) || [];
    callback(null, { entries });
  }

  purgeActivity(call: grpc.ServerUnaryCall<any, any>, callback: grpc.sendUnaryData<any>): void {
    const request = call.request;
    console.debug(`Purging activity for agent ${request.agent_id}, tasks:`, request.task_ids);
    
    const currentEntries = this.activityBuffer.get(request.agent_id) || [];
    let purgedCount = 0;
    
    if (request.task_ids.length === 0) {
      // Clear all entries
      purgedCount = currentEntries.length;
      this.activityBuffer.set(request.agent_id, []);
    } else {
      // Remove specific tasks
      const initialLength = currentEntries.length;
      const filteredEntries = currentEntries.filter(entry => 
        !request.task_ids.includes(entry.task_id)
      );
      this.activityBuffer.set(request.agent_id, filteredEntries);
      purgedCount = initialLength - filteredEntries.length;
    }
    
    callback(null, { purged: purgedCount });
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
      active_tasks: Array.from(this.tasks.keys()),
      total_tasks: this.tasks.size,
      agents_with_activity: Array.from(this.activityBuffer.keys())
    };
  }
}

async function serve(): Promise<void> {
  console.log('🚀 Starting SW4RM Scheduler Service (JavaScript)');
  console.log('================================================');

  const server = new grpc.Server();
  const schedulerService = new SchedulerServiceImpl();

  try {
    // Load the proto definition
    const packageDefinition = protoLoader.loadSync([schedulerProtoPath, commonProtoPath], {
      keepCase: true,
      longs: String,
      enums: String,
      defaults: true,
      oneofs: true
    });
    
    const proto = grpc.loadPackageDefinition(packageDefinition) as any;
    
    // Add the scheduler service
    server.addService(proto.sw4rm.scheduler.SchedulerService.service, {
      SubmitTask: schedulerService.submitTask.bind(schedulerService),
      RequestPreemption: schedulerService.requestPreemption.bind(schedulerService),
      ShutdownAgent: schedulerService.shutdownAgent.bind(schedulerService),
      PollActivityBuffer: schedulerService.pollActivityBuffer.bind(schedulerService),
      PurgeActivity: schedulerService.purgeActivity.bind(schedulerService)
    });
  } catch (error) {
    console.warn('Could not load scheduler proto, using mock implementation');
  }

  const port = parseInt(process.env.SCHEDULER_PORT || '50053', 10);
  const addr = `0.0.0.0:${port}`;
  
  server.bindAsync(addr, grpc.ServerCredentials.createInsecure(), (err, port) => {
    if (err) {
      console.error('Failed to bind server:', err);
      return;
    }
    
    console.log(`⏱️  Scheduler service started on ${addr}`);
    server.start();
  });

  // Handle graceful shutdown
  process.on('SIGINT', () => {
    console.log('\n🛑 Received SIGINT, shutting down...');
    const status = schedulerService.getStatus();
    console.log('Final state:', status);
    server.forceShutdown();
    process.exit(0);
  });

  // Kick off CONTROL orchestrator (non-blocking)
  orchestrateControlFlow().catch(err => console.error('scheduler control loop error:', err));
}

if (import.meta.url === `file://${process.argv[1]}`) {
  serve().catch(console.error);
}

// ---- CONTROL orchestration below ----

const DEMO_ROOT = path.resolve(path.join(__dirname, '..', 'agents'));
const SCHED_SESSION_FILE = path.join(DEMO_ROOT, '.scheduler_session_id');

function readSessionId(): string | undefined {
  try { return fs.existsSync(SCHED_SESSION_FILE) ? fs.readFileSync(SCHED_SESSION_FILE, 'utf8').trim() : undefined; } catch { return undefined; }
}
function writeSessionId(sid: string) { try { fs.writeFileSync(SCHED_SESSION_FILE, sid, 'utf8'); } catch {} }

let SESSION_READY = false;

function extractFirstJsonObject(text: string): any | undefined {
  const s = (text || '').trim();
  if (!s) return undefined;
  try { const obj = JSON.parse(s); if (obj && typeof obj === 'object') return obj; } catch {}
  if (s.startsWith('```')) {
    const lines = s.split(/\r?\n/);
    let inner = lines.slice(1).join('\n');
    if (inner.trim().endsWith('```')) inner = inner.split(/\r?\n/).slice(0, -1).join('\n');
    try { const obj = JSON.parse(inner); if (obj && typeof obj === 'object') return obj; } catch {}
  }
  const start = s.indexOf('{');
  if (start !== -1) {
    let depth = 0;
    for (let i = start; i < s.length; i++) {
      const ch = s[i];
      if (ch === '{') depth++;
      else if (ch === '}') { depth--; if (depth === 0) { try { return JSON.parse(s.slice(start, i + 1)); } catch {} break; } }
    }
  }
  return undefined;
}

async function runClaudeStreamJson(prompt: string): Promise<any> {
  console.log(`[scheduler] claude prompt (first 400)\n${prompt.slice(0, 400)}`);
  const cli = process.env.CLAUDE_CLI || 'claude';
  const args = ['-p', prompt, '--output-format', 'stream-json', '--verbose'];
  const sid = readSessionId();
  if (sid && SESSION_READY) { args.push('--session-id', sid); }
  console.log(`[scheduler] LLM invoke: cli=${cli} pass_sid=${Boolean(sid && SESSION_READY)} sid=${sid || '-'}`);
  return await new Promise((resolve) => {
    const proc = spawn(cli, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let textBuf = '';
    let resultObj: any | undefined;
    let seenSession: string | undefined;
    let lastResultText = '';
    const onLine = (line: string) => {
      line = line.trim(); if (!line) return;
      try {
        const obj = JSON.parse(line);
        const typ = obj?.type;
        if (typ === 'content_block_delta') {
          const delta = obj?.delta; if (delta?.type === 'text_delta' && typeof delta?.text === 'string') textBuf += delta.text;
        } else if (typ === 'content_block_start') {
          const cb = obj?.content_block; if (cb?.type === 'text' && typeof cb?.text === 'string' && cb.text) textBuf += cb.text;
        } else if (typ === 'message_delta') {
          const pj = obj?.delta?.partial_json; if (typeof pj === 'string') textBuf += pj;
        }
        if (typ === 'result') {
          if (typeof obj?.session_id === 'string') { seenSession = obj.session_id; writeSessionId(seenSession); }
          const res = obj?.result;
          if (typeof res === 'string') {
            let s = res.trim();
            if (s.startsWith('```')) { s = s.split(/\r?\n/).slice(1).join('\n'); if (s.trim().endsWith('```')) s = s.split(/\r?\n/).slice(0, -1).join('\n'); }
            lastResultText = s;
            const parsed = extractFirstJsonObject(s);
            if (parsed && typeof parsed === 'object') resultObj = parsed;
          } else if (res && typeof res === 'object') {
            resultObj = res; try { lastResultText = JSON.stringify(res); } catch { lastResultText = ''; }
          }
        }
      } catch {}
    };
    proc.stdout?.on('data', (buf: Buffer) => { const s = buf.toString('utf8'); for (const line of s.split(/\r?\n/)) onLine(line); });
    proc.on('close', () => {
      const fullText = textBuf.trim();
      if (!resultObj && fullText) resultObj = extractFirstJsonObject(fullText) ?? {};
      if ((lastResultText || fullText).includes('Invalid API key')) { console.error('[scheduler] Claude CLI: Invalid API key. Run `claude login`.'); }
      const excerpt = (lastResultText || fullText || '').slice(0, 400);
      console.log(`[scheduler] claude session=${seenSession || '-'}, result_excerpt (first 400)\n${excerpt}`);
      if (seenSession) SESSION_READY = true;
      resolve(resultObj ?? {});
    });
    proc.on('error', () => { console.error('[scheduler] claude CLI not found on PATH'); resolve({}); });
  });
}

async function orchestrateControlFlow(): Promise<void> {
  // Create clients
  const ROUTER_HOST = process.env.ROUTER_HOST || 'localhost';
  const ROUTER_PORT = Number(process.env.ROUTER_PORT || '50051');
  const REGISTRY_HOST = process.env.REGISTRY_HOST || 'localhost';
  const REGISTRY_PORT = Number(process.env.REGISTRY_PORT || '50052');
  const router = new RouterClient({ address: `${ROUTER_HOST}:${ROUTER_PORT}` });
  const registry = new RegistryClient({ address: `${REGISTRY_HOST}:${REGISTRY_PORT}` });

  const agentId = 'scheduler';
  try {
    await registry.registerAgent({
      agent_id: agentId,
      name: 'Scheduler',
      description: 'CONTROL orchestrator',
      capabilities: ['scheduler'],
      communication_class: 'COMMUNICATION_CLASS_UNSPECIFIED',
      modalities_supported: [],
      reasoning_connectors: [],
    });
  } catch {}

  // Heartbeats
  setInterval(() => { registry.heartbeat(agentId, 'AGENT_STATE_UNSPECIFIED', { role: 'scheduler' }).catch(()=>{}); }, 30_000);

  console.log('[scheduler] waiting for CONTROL...');
  const stream = router.streamIncoming(agentId);
  stream.on('data', async (item: any) => {
    try {
      const msg = item?.msg; if (!msg) return;
      if (String(msg.content_type) !== 'application/vnd.sw4rm.scheduler.command+json;v=1') return;
      const body = JSON.parse(Buffer.from(msg.payload || new Uint8Array()).toString('utf8'));
      const stage: string = body?.stage || '';
      const params: any = body?.params || body?.input || {};
      const corr: string = String(msg.correlation_id || '');

      if (stage === 'prompt' || stage === 'plan') {
        const userText = String(params?.prompt || '');
        const planObj = await runClaudeStreamJson(userText);
        const backendPrompt = typeof planObj?.backend === 'string' ? planObj.backend : '';
        const frontendPrompt = typeof planObj?.frontend === 'string' ? planObj.frontend : '';
        if (!backendPrompt && !frontendPrompt) {
          console.warn('[scheduler] plan parse produced no prompts');
          return;
        }
        // Fan-out generate
        const mk = (to: string, prompt: string) => ({ schema_version: 1, to, stage: 'generate', params: { prompt } });
        const send = async (to: string, cmd: any) => {
          const env = buildEnvelope({
            producer_id: agentId, message_type: MessageType.CONTROL,
            content_type: 'application/vnd.sw4rm.scheduler.command+json;v=1',
            payload: Buffer.from(JSON.stringify(cmd), 'utf-8'), correlation_id: corr,
          });
          await router.sendMessage(env).catch(()=>{});
        };
        if (backendPrompt) await send('backend', mk('backend', backendPrompt));
        if (frontendPrompt) await send('frontend', mk('frontend', frontendPrompt));
        console.log('[scheduler] dispatched generate to agents');
      } else if (stage === 'run') {
        let commands = params?.commands;
        if (!commands) {
          // Ask LLM for canonical commands JSON ONLY {"commands": { backend:{run_cmd}, frontend:{run_cmd} }}
          const guidance = params?.prompt || '';
          const runPrompt =
            'Return JSON ONLY as {"commands": { backend: { run_cmd }, frontend: { run_cmd } } }.' +
            'Execution cwd for agents is ./generated_app. Do not prefix with generated_app. ' +
            'Backend should use "cd backend && python3 server.py"; Frontend should use "cd frontend && python3 -m http.server 5173".\n\n' +
            (guidance ? `Guidance: ${JSON.stringify(guidance)}` : '');
          const runObj = await runClaudeStreamJson(runPrompt);
          commands = runObj?.commands;
        }
        if (!commands) { console.warn('[scheduler] no commands derived for run'); return; }
        const backendCmd = String(commands?.backend?.run_cmd || 'cd backend && python3 server.py');
        const frontendCmd = String(commands?.frontend?.run_cmd || 'cd frontend && python3 -m http.server 5173');
        const mkRun = (to: string, cmd: string) => ({ schema_version: 1, to, stage: 'run', params: { cmd } });
        const send = async (to: string, cmd: any) => {
          const env = buildEnvelope({
            producer_id: agentId, message_type: MessageType.CONTROL,
            content_type: 'application/vnd.sw4rm.scheduler.command+json;v=1',
            payload: Buffer.from(JSON.stringify(cmd), 'utf-8'), correlation_id: corr,
          });
          await router.sendMessage(env).catch(()=>{});
        };
        await send('backend', mkRun('backend', backendCmd));
        await send('frontend', mkRun('frontend', frontendCmd));
        console.log('[scheduler] dispatched run commands to agents');
      }
    } catch (e: any) {
      console.warn('[scheduler] control handling error:', e?.message || e);
    }
  });
  stream.on('error', err => console.warn('[scheduler] stream error', err?.message || err));
  stream.on('end', () => console.log('[scheduler] stream ended'));
}
