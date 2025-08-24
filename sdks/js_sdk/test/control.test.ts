import { describe, it, expect } from 'vitest';
import { CT_SCHEDULER_COMMAND_V1, CT_AGENT_REPORT_V1, encodeSchedulerCommandV1, decodeAgentReportV1, normalizeReportPaths } from '../src/internal/control.js';

describe('CONTROL helpers', () => {
  it('encodes scheduler command as stable JSON bytes', () => {
    const bytes = encodeSchedulerCommandV1({ stage: 'run', input: { b: 2, a: 1 } });
    const s = new TextDecoder().decode(bytes);
    // Keys should be sorted lexicographically
    expect(s).toBe('{"input":{"a":1,"b":2},"stage":"run"}');
    expect(CT_SCHEDULER_COMMAND_V1).toContain('application/vnd.sw4rm.scheduler.command+json');
  });

  it('decodes agent report and normalizes paths', () => {
    const reportJson = JSON.stringify({ files: [ { path: '..\\gen//app/./src/main.ts', b64: '' } ] });
    const report = decodeAgentReportV1(new TextEncoder().encode(reportJson));
    const normalized = normalizeReportPaths(report);
    expect(normalized.files?.[0].path).toBe('gen/app/src/main.ts');
    expect(CT_AGENT_REPORT_V1).toContain('application/vnd.sw4rm.agent.report+json');
  });
});
