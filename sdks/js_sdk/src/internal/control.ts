// CONTROL message helpers and content-types for CONTROL-only flows
// Custom POSIX-style normalizer to match Rust behavior (drops leading `..`)

export const CT_SCHEDULER_COMMAND_V1 = 'application/vnd.sw4rm.scheduler.command+json;v=1';
export const CT_AGENT_REPORT_V1 = 'application/vnd.sw4rm.agent.report+json;v=1';

export type SchedulerStage = 'prompt' | 'plan' | 'run';

export interface SchedulerCommandV1 {
  stage: SchedulerStage;
  // Arbitrary, strictly JSON-serializable payload for the given stage
  input?: unknown;
}

export interface AgentReportFileV1 {
  path: string;
  b64: string; // base64-encoded file content
}

export interface AgentReportV1 {
  agent_id?: string;
  stage?: string; // 'generate' | 'run' | custom
  success?: boolean;
  files?: AgentReportFileV1[];
  logs?: string[];
  error?: string;
}

// Stable JSON stringify: sorts object keys lexicographically.
function stableStringify(value: unknown): string {
  const seen = new WeakSet();
  const stringify = (val: any): any => {
    if (val === null || typeof val !== 'object') return val;
    if (seen.has(val)) throw new Error('Cycle detected in input');
    seen.add(val);
    if (Array.isArray(val)) return val.map(v => stringify(v));
    const out: Record<string, any> = {};
    for (const key of Object.keys(val).sort()) {
      const v = (val as any)[key];
      if (v === undefined) continue; // drop undefined
      out[key] = stringify(v);
    }
    return out;
  };
  return JSON.stringify(stringify(value));
}

export function encodeSchedulerCommandV1(cmd: SchedulerCommandV1): Uint8Array {
  if (!cmd || (cmd.stage !== 'prompt' && cmd.stage !== 'plan' && cmd.stage !== 'run')) {
    throw new Error('SchedulerCommandV1.stage must be one of: prompt | plan | run');
  }
  const json = stableStringify(cmd);
  return new Uint8Array(Buffer.from(json, 'utf-8'));
}

export function decodeAgentReportV1(payload: Uint8Array): AgentReportV1 {
  try {
    const s = Buffer.from(payload).toString('utf-8');
    const obj = JSON.parse(s);
    return obj as AgentReportV1;
  } catch (e) {
    throw new Error('Invalid AgentReportV1 JSON payload');
  }
}

function normalizePosixPath(p: string): string {
  const parts = p.replaceAll('\\', '/').split('/');
  const out: string[] = [];
  for (const part of parts) {
    if (!part || part === '.') continue;
    if (part === '..') { out.pop(); continue; }
    out.push(part);
  }
  return out.join('/');
}

export function normalizeReportPaths(report: AgentReportV1): AgentReportV1 {
  if (!report.files) return report;
  report.files = report.files.map(f => ({
    ...f,
    path: normalizePosixPath(f.path),
  }));
  return report;
}
