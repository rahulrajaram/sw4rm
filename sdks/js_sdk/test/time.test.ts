import { describe, it, expect } from 'vitest';
import { msToDuration, durationToMs } from '../src/internal/time.js';

describe('time helpers', () => {
  it('round trips ms ↔ Duration', () => {
    const d = msToDuration(1234);
    expect(durationToMs(d)).toBe(1234);
  });
});

