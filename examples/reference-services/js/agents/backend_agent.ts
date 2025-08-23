#!/usr/bin/env tsx
// moved to agents/

// Backend agent for the client_server_llm demo (JS)
// Mirrors Python behavior: registers as "backend", listens for CONTROL
// scheduler commands (generate/run), invokes `claude` CLI, writes files under
// ./generated_app/backend, and starts the backend server on run.

import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import fs from 'node:fs';

import {
  RegistryClient,
  RouterClient,
  buildEnvelope,
  MessageType,
} from '../../../../sdks/js_sdk/src/index.ts';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const ROOT = __dirname; // examples/reference-services/js/client_server_llm
const GEN_ROOT = path.join(ROOT, 'generated_app', 'backend');
const SESSION_FILE = path.join(ROOT, '.backend_session_id');

// --- logging helpers ---
const COLOR_RESET = '\u001b[0m';
const COLOR = '\u001b[36m'; // cyan for backend
const GREEN = '\u001b[32m';
const RED = '\u001b[31m';
function supportsColor(): boolean {
  try { return process.stdout.isTTY && !process.env.NO_COLOR; } catch { return false; }
}
function tag(): string { return supportsColor() ? `${COLOR}[backend]${COLOR_RESET}` : '[backend]'; }
function log(msg: string) { console.log(`${tag()} ${msg}`); }
function logSuccess(msg: string) { console.log(supportsColor() ? `${tag()} ${GREEN}${msg}${COLOR_RESET}` : `${tag()} ${msg}`); }
function logError(msg: string) { console.error(supportsColor() ? `${tag()} ${RED}${msg}${COLOR_RESET}` : `${tag()} ${msg}`); }

function ensureWorkspace() {
  fs.mkdirSync(path.join(ROOT, 'generated_app'), { recursive: true });
  fs.mkdirSync(GEN_ROOT, { recursive: true });
}

function ts(): string { return new Date().toISOString().replace(/\..+$/, ''); }

function readSessionId(): string | undefined {
  try { return fs.existsSync(SESSION_FILE) ? fs.readFileSync(SESSION_FILE, 'utf8').trim() : undefined; } catch { return undefined; }
}
function writeSessionId(sid: string) {
  try { fs.writeFileSync(SESSION_FILE, sid, 'utf8'); } catch {}
}

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

async function runClaude(prompt: string): Promise<any> {
  log(`${ts()} claude prompt (first 400):\n${prompt.slice(0, 400)}`);
  const cli = process.env.CLAUDE_CLI || 'claude';
  const args = ['-p', prompt, '--output-format', 'stream-json', '--verbose'];
  const sid = readSessionId();
  if (sid && SESSION_READY) { args.push('--session-id', sid); }
  log(`LLM invoke: cli=${cli} pass_sid=${Boolean(sid && SESSION_READY)} sid=${sid || '-'}`);

  return await new Promise((resolve) => {
    const proc = spawn(cli, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let textBuf = '';
    let resultObj: any | undefined;
    let seenSession: string | undefined;
    let lastResultText = '';
    const onLine = (line: string) => {
      line = line.trim();
      if (!line) return;
      try {
        const obj = JSON.parse(line);
        const typ = obj?.type;
        if (typ === 'content_block_delta') {
          const delta = obj?.delta;
          if (delta?.type === 'text_delta' && typeof delta?.text === 'string') textBuf += delta.text;
        } else if (typ === 'content_block_start') {
          const cb = obj?.content_block;
          if (cb?.type === 'text' && typeof cb?.text === 'string' && cb.text) textBuf += cb.text;
        } else if (typ === 'message_delta') {
          const pj = obj?.delta?.partial_json;
          if (typeof pj === 'string') textBuf += pj;
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
            resultObj = res;
            try { lastResultText = JSON.stringify(res); } catch { lastResultText = ''; }
          }
        }
      } catch {}
    };
    proc.stdout?.on('data', (buf: Buffer) => {
      const s = buf.toString('utf8');
      for (const line of s.split(/\r?\n/)) onLine(line);
    });
    proc.on('close', () => {
      const fullText = textBuf.trim();
      if (!resultObj && fullText) resultObj = extractFirstJsonObject(fullText) ?? {};
      if ((lastResultText || fullText).includes('Invalid API key')) {
        logError('Claude CLI reports Invalid API key. Run `claude login` and retry.');
      }
      const excerpt = (lastResultText || fullText || '').slice(0, 400);
      log(`${ts()} claude session=${seenSession || '-'}, result_excerpt (first 400):\n${excerpt}`);
      if (seenSession) SESSION_READY = true;
      resolve(resultObj ?? {});
    });
    proc.on('error', () => {
      logError('claude CLI not found on PATH. Please install and authenticate it.');
      resolve({});
    });
  });
}

function writeBackendFiles(resultObj: any, fallbackPrompt: string): string[] {
  fs.mkdirSync(GEN_ROOT, { recursive: true });
  const files = (resultObj && Array.isArray(resultObj.files)) ? resultObj.files : undefined;
  const written: string[] = [];
  if (files) {
    for (const f of files) {
      try {
        const relRaw = String(f?.path ?? 'unknown.txt');
        const norm = relRaw.replaceAll('\\\\', '/').replace(/^\/+/, '');
        let parts = norm.split('/').filter(p => p && p !== '.' && p !== '..');
        if (parts[0] === 'generated_app') parts = parts.slice(1);
        if (parts[0] === 'backend') parts = parts.slice(1);
        if (parts.length === 0) parts = ['unknown.txt'];
        const outPath = path.join(GEN_ROOT, ...parts);
        fs.mkdirSync(path.dirname(outPath), { recursive: true });
        const encoding = String(f?.encoding || '').toLowerCase();
        if (f?.content_b64 || encoding === 'base64') {
          const b64 = String(f?.content_b64 || f?.content || '');
          const buf = Buffer.from(b64, 'base64');
          fs.writeFileSync(outPath, buf);
        } else {
          const text = typeof f?.content === 'string' ? f.content : '';
          fs.writeFileSync(outPath, text, 'utf8');
        }
        if (f?.executable === true) {
          try { fs.chmodSync(outPath, 0o755); } catch {}
        }
        written.push(path.relative(GEN_ROOT, outPath));
      } catch {}
    }
    return written;
  }
  // Minimal fallback app (Python-parity: server on :8000)
  const serverPy = `#!/usr/bin/env python3
from http.server import HTTPServer, BaseHTTPRequestHandler
import json

class Handler(BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()
    def do_GET(self):
        if self.path == '/hello':
            body = json.dumps({'message':'hello'}).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type','application/json; charset=utf-8')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404); self.end_headers()

if __name__ == '__main__':
    HTTPServer(('0.0.0.0', 8000), Handler).serve_forever()
`;
  fs.writeFileSync(path.join(GEN_ROOT, 'server.py'), serverPy, 'utf8');
  fs.writeFileSync(path.join(GEN_ROOT, 'PROMPT.txt'), fallbackPrompt ?? '', 'utf8');
  return ['server.py', 'PROMPT.txt'];
}

async function main() {
  ensureWorkspace();

  const ROUTER_HOST = process.env.ROUTER_HOST || 'localhost';
  const ROUTER_PORT = Number(process.env.ROUTER_PORT || '50051');
  const REGISTRY_HOST = process.env.REGISTRY_HOST || 'localhost';
  const REGISTRY_PORT = Number(process.env.REGISTRY_PORT || '50052');

  const router = new RouterClient({ address: `${ROUTER_HOST}:${ROUTER_PORT}` });
  const registry = new RegistryClient({ address: `${REGISTRY_HOST}:${REGISTRY_PORT}` });

  const agentId = 'backend';
  try {
    await registry.registerAgent({
      agent_id: agentId,
      name: 'Backend Agent',
      description: 'Generates backend server',
      capabilities: ['backend'],
      communication_class: 'COMMUNICATION_CLASS_UNSPECIFIED',
      modalities_supported: [],
      reasoning_connectors: [],
    });
  } catch {}

  // Heartbeats
  setInterval(() => {
    registry.heartbeat(agentId, 'AGENT_STATE_UNSPECIFIED', { role: 'backend' }).catch(() => {});
  }, 30_000);

  log('waiting for commands…');
  const processed = new Set<string>();
  const stream = router.streamIncoming(agentId);
  stream.on('data', async (item: any) => {
    const msg = item?.msg;
    if (!msg) return;
    const ct = String(msg.content_type || '');
    if (ct !== 'application/vnd.sw4rm.scheduler.command+json;v=1') return;
    let cmd: any = {};
    try { cmd = JSON.parse(Buffer.from(msg.payload || new Uint8Array()).toString('utf8')); } catch {}
    const to = cmd?.to; if (to && to !== agentId) return;
    const stage = cmd?.stage;
    const params = cmd?.params || cmd?.input || {};
    const corr = String(msg.correlation_id || '');
    const key = JSON.stringify([corr, stage, params]);
    if (processed.has(key)) { log(`duplicate command ignored ${key}`); return; }

    if (stage === 'generate') {
      const prompt = String(params?.prompt || '');
      log('generate: invoking claude…');
      const resultObj = await runClaude(prompt);
      const filesWritten = writeBackendFiles(resultObj, prompt);
      const report = { schema_version: 1, stage: 'generate', status: 'ok', files: filesWritten };
      const env = buildEnvelope({
        producer_id: agentId,
        message_type: MessageType.NOTIFICATION,
        content_type: 'application/vnd.sw4rm.agent.report+json;v=1',
        payload: Buffer.from(JSON.stringify(report), 'utf8'),
        correlation_id: corr,
      });
      await router.sendMessage(env).catch(() => {});
      const preview = filesWritten.slice(0, 5).join(', ') + (filesWritten.length > 5 ? '…' : '');
      logSuccess(`completed generate: status=ok files=${filesWritten.length} [${preview}]`);
      processed.add(key);
    } else if (stage === 'run') {
      const suggested = String(params?.cmd || '');
      const llmPrompt = (
        'You are the backend run orchestrator. A suggested command was provided. ' +
        'Return JSON ONLY as {"run_cmd": string}. Execution cwd is ./generated_app. ' +
        "Use 'cd backend && python3 server.py'. Do NOT include 'generated_app' in paths.\n\n" +
        `Suggested: ${JSON.stringify(suggested)}`
      );
      log('run: invoking claude to confirm command…');
      const resultObj = await runClaude(llmPrompt);
      const cmdline = (resultObj && typeof resultObj.run_cmd === 'string' && resultObj.run_cmd) || suggested;
      const baseDir = path.join(ROOT, 'generated_app');
      const logPath = path.join(GEN_ROOT, 'service.log');
      let status = 'ok';
      let info: any = { cmd: cmdline };
      try {
        const out = fs.createWriteStream(logPath, { flags: 'a' });
        const child = spawn(cmdline, { cwd: baseDir, shell: true, stdio: ['ignore', out, out] });
        fs.writeFileSync(path.join(GEN_ROOT, '.service.pid'), String(child.pid), 'utf8');
        info.pid = child.pid;
      } catch (e: any) {
        status = 'error';
        info.error = String(e?.message || e);
      }
      const report = { schema_version: 1, stage: 'run', status, info };
      const env = buildEnvelope({
        producer_id: agentId,
        message_type: MessageType.NOTIFICATION,
        content_type: 'application/vnd.sw4rm.agent.report+json;v=1',
        payload: Buffer.from(JSON.stringify(report), 'utf8'),
        correlation_id: corr,
      });
      await router.sendMessage(env).catch(() => {});
      if (status === 'ok') logSuccess(`completed run: started pid=${info.pid} cmd='${cmdline}'`);
      else logError(`completed run: failed error='${info.error || ''}' cmd='${cmdline}'`);
      processed.add(key);
    }
  });
  stream.on('error', (err: any) => { logError(`stream error: ${err?.message || String(err)}`); });
  stream.on('end', () => { log('stream ended'); });
}

main().catch(err => { logError(String(err?.stack || err)); process.exit(1); });
