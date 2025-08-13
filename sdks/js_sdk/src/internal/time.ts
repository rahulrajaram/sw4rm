// google.protobuf.Duration helpers (ms <-> {seconds,nanos})

export type Duration = { seconds: number | string; nanos?: number };

export function msToDuration(ms: number): Duration {
  if (!Number.isFinite(ms)) throw new Error('msToDuration: ms must be finite');
  const secs = Math.trunc(ms / 1000);
  const nanos = Math.trunc((ms % 1000) * 1e6);
  return { seconds: secs, nanos };
}

export function durationToMs(d: Duration | undefined | null): number | undefined {
  if (!d) return undefined;
  const seconds = typeof d.seconds === 'string' ? parseInt(d.seconds, 10) : d.seconds ?? 0;
  const nanos = d.nanos ?? 0;
  return Math.trunc(seconds * 1000 + nanos / 1e6);
}

