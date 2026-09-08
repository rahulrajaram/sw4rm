// Shared run-command policy for the reference agents (campaign R2).
//
// The run stage used to execute message-derived strings through a shell
// spawn with an unmediated fallback to the raw suggestion. This
// module replaces that with:
//   - an argv allowlist (no shell anywhere),
//   - strict validation of every argument,
//   - fail-closed behavior when LLM confirmation is unavailable or its output
//     is unusable (the raw suggestion is never executed),
//   - an explicit operator-confirmation flag required before any spawn.
//
// Legacy single-string commands are accepted only when they survive a strict
// tokenizer plus the same allowlist — shell compounds like
// "cd backend && python3 server.py" are rejected, never re-interpreted.

export const ALLOWED_INTERPRETERS: ReadonlySet<string> = new Set([
  'python3',
  'python',
  'node',
  'npm',
  'npx',
]);

// Characters that make an argument shell- or path-hostile. The argv form is
// executed without a shell, so these are rejected defensively (and make
// legacy string parsing fail closed rather than approximate).
const FORBIDDEN = /[;&|`$<>(){}*"'\n\r\\]/;
const MAX_ARGV_LENGTH = 16;
const MAX_ARG_LENGTH = 512;

export type RunArgv = { ok: true; argv: string[] };
export type RunRejection = { ok: false; error: string };
export type RunResolution = RunArgv | RunRejection;

export function validateRunArgv(argv: unknown): RunResolution {
  if (!Array.isArray(argv) || argv.length === 0) {
    return { ok: false, error: 'run command must be a non-empty argv array' };
  }
  if (argv.length > MAX_ARGV_LENGTH) {
    return { ok: false, error: `run command exceeds ${MAX_ARGV_LENGTH} arguments` };
  }
  for (const raw of argv) {
    if (typeof raw !== 'string' || raw.length === 0) {
      return { ok: false, error: 'run command arguments must be non-empty strings' };
    }
    if (raw.length > MAX_ARG_LENGTH) {
      return { ok: false, error: `run command argument too long: ${raw.slice(0, 32)}…` };
    }
    if (FORBIDDEN.test(raw)) {
      return { ok: false, error: `run command argument contains forbidden characters: ${JSON.stringify(raw)}` };
    }
    if (raw.startsWith('/')) {
      return { ok: false, error: `absolute paths are not allowed in run commands: ${JSON.stringify(raw)}` };
    }
    if (raw === '..' || raw.startsWith('../') || raw.includes('/../') || raw.endsWith('/..')) {
      return { ok: false, error: `path traversal is not allowed in run commands: ${JSON.stringify(raw)}` };
    }
  }
  const interpreter = argv[0];
  if (!ALLOWED_INTERPRETERS.has(interpreter)) {
    return {
      ok: false,
      error: `interpreter ${JSON.stringify(interpreter)} is not in the allowlist (${[...ALLOWED_INTERPRETERS].join(', ')})`,
    };
  }
  return { ok: true, argv: argv as string[] };
}

export function parseRunCommand(raw: string): RunResolution {
  const cmd = typeof raw === 'string' ? raw.trim() : '';
  if (!cmd) return { ok: false, error: 'run command is empty' };
  if (FORBIDDEN.test(cmd)) {
    return { ok: false, error: 'run command contains forbidden characters (shell compounds are rejected)' };
  }
  return validateRunArgv(cmd.split(/\s+/).filter(part => part.length > 0));
}

export function validateRunCmdString(raw: string): RunResolution {
  return parseRunCommand(raw);
}

export interface RunStageParams {
  cmd?: unknown;
  cmd_argv?: unknown;
  confirm?: unknown;
}

export interface RunStageDeps {
  /** LLM confirmation callback (mockable in tests). */
  runClaude: (prompt: string) => Promise<any>;
  /** Process spawner (mockable in tests); MUST NOT be given a shell option. */
  spawnFn: (
    program: string,
    args: string[],
    options: { cwd: string; stdio: ['ignore', unknown, unknown] },
  ) => { pid?: number };
  baseDir: string;
  logPath: string;
  writePid: (pid: string) => void;
  appendLog: () => unknown;
}

export interface RunStageResult {
  status: 'ok' | 'error';
  info: Record<string, unknown>;
}

/**
 * Execute the confirmed run stage, or fail closed. Never spawns a shell and
 * never falls back to the raw suggestion when LLM confirmation is missing.
 */
export async function executeRunStage(
  params: RunStageParams,
  deps: RunStageDeps,
): Promise<RunStageResult> {
  if (params.confirm !== true) {
    return { status: 'error', info: { error: 'run_not_confirmed' } };
  }

  let resolution: RunResolution;
  if (params.cmd_argv !== undefined) {
    resolution = validateRunArgv(params.cmd_argv);
    if (!resolution.ok) return { status: 'error', info: { error: resolution.error } };
  } else if (typeof params.cmd === 'string' && params.cmd.trim()) {
    // Confirm-then-run: the LLM reviews the suggestion and returns the argv.
    // Any failure is terminal — the raw suggestion is never executed.
    const suggested = params.cmd;
    let resultObj: any;
    try {
      resultObj = await deps.runClaude(buildConfirmationPrompt(suggested));
    } catch {
      return { status: 'error', info: { error: 'llm_confirmation_unavailable', cmd: suggested } };
    }
    const runCmd = resultObj && typeof resultObj.run_cmd === 'string' ? resultObj.run_cmd : undefined;
    if (!runCmd) {
      return { status: 'error', info: { error: 'llm_confirmation_unavailable', cmd: suggested } };
    }
    resolution = validateRunCmdString(runCmd);
    if (!resolution.ok) return { status: 'error', info: { error: resolution.error, cmd: runCmd } };
  } else {
    return { status: 'error', info: { error: 'no_run_command' } };
  }

  const argv = (resolution as RunArgv).argv;
  try {
    const out = deps.appendLog();
    const child = deps.spawnFn(argv[0], argv.slice(1), {
      cwd: deps.baseDir,
      stdio: ['ignore', out, out] as ['ignore', unknown, unknown],
    });
    deps.writePid(String(child.pid ?? ''));
    return { status: 'ok', info: { cmd: argv.join(' '), argv, pid: child.pid } };
  } catch (e: any) {
    return { status: 'error', info: { error: String(e?.message || e), argv } };
  }
}

export function buildConfirmationPrompt(suggested: string): string {
  return (
    'You are the run orchestrator. A suggested command was provided. ' +
    'Return JSON ONLY as {"run_cmd": string}. Execution cwd is ./generated_app. ' +
    'The command must be a single program with arguments (no shell compounds, no cd). ' +
    `Suggested: ${JSON.stringify(suggested)}`
  );
}
