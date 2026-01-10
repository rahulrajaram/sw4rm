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

import { describe, it, expect, beforeEach } from 'vitest';
import {
  ActivityBuffer,
  MaxEntriesStrategy,
  type ActivityRecord,
  type BufferStrategy,
} from '../src/internal/runtime/activityBuffer.js';

/**
 * Tests for ActivityBuffer.
 *
 * These tests verify the ActivityBuffer functionality for tracking
 * agent activity records with FIFO eviction.
 *
 * Ported from: sdks/py_sdk/tests/test_activity_buffer.py
 */

function createRecord(taskId: string, timestamp?: string): ActivityRecord {
  return {
    task_id: taskId,
    repo_id: 'repo-1',
    worktree_id: 'wt-1',
    branch: 'main',
    description: `Activity for ${taskId}`,
    timestamp: timestamp ?? new Date().toISOString(),
  };
}

describe('ActivityBuffer', () => {
  describe('construction', () => {
    it('should initialize with default options', () => {
      const buffer = new ActivityBuffer();
      expect(buffer).toBeDefined();
      expect(buffer.list()).toEqual([]);
    });

    it('should initialize with custom maxEntries', () => {
      const buffer = new ActivityBuffer({ maxEntries: 10 });
      expect(buffer).toBeDefined();
    });

    it('should initialize with custom strategy', () => {
      const strategy = new MaxEntriesStrategy();
      const buffer = new ActivityBuffer({ strategy });
      expect(buffer).toBeDefined();
    });
  });

  describe('upsert', () => {
    let buffer: ActivityBuffer;

    beforeEach(() => {
      buffer = new ActivityBuffer({ maxEntries: 3 });
    });

    it('should add new record', () => {
      const record = createRecord('task-1');
      buffer.upsert(record);

      const list = buffer.list();
      expect(list).toHaveLength(1);
      expect(list[0].task_id).toBe('task-1');
    });

    it('should update existing record', () => {
      buffer.upsert(createRecord('task-1', '2024-01-01T00:00:00Z'));
      buffer.upsert({
        ...createRecord('task-1', '2024-01-01T00:01:00Z'),
        description: 'Updated activity',
      });

      const list = buffer.list();
      expect(list).toHaveLength(1);
      expect(list[0].description).toBe('Updated activity');
    });

    it('should prune oldest records when exceeding maxEntries', () => {
      // Add 4 records to buffer with maxEntries=3
      buffer.upsert(createRecord('task-1', '2024-01-01T00:00:00Z'));
      buffer.upsert(createRecord('task-2', '2024-01-01T00:01:00Z'));
      buffer.upsert(createRecord('task-3', '2024-01-01T00:02:00Z'));
      buffer.upsert(createRecord('task-4', '2024-01-01T00:03:00Z'));

      const list = buffer.list();
      expect(list).toHaveLength(3);

      // Oldest (task-1) should be evicted
      const taskIds = list.map((r) => r.task_id);
      expect(taskIds).not.toContain('task-1');
      expect(taskIds).toContain('task-2');
      expect(taskIds).toContain('task-3');
      expect(taskIds).toContain('task-4');
    });
  });

  describe('remove', () => {
    let buffer: ActivityBuffer;

    beforeEach(() => {
      buffer = new ActivityBuffer();
      buffer.upsert(createRecord('task-1'));
      buffer.upsert(createRecord('task-2'));
      buffer.upsert(createRecord('task-3'));
    });

    it('should remove existing record', () => {
      buffer.remove('task-2');

      const list = buffer.list();
      expect(list).toHaveLength(2);

      const taskIds = list.map((r) => r.task_id);
      expect(taskIds).not.toContain('task-2');
    });

    it('should handle removal of non-existent record', () => {
      buffer.remove('nonexistent');

      // Should not throw, buffer unchanged
      expect(buffer.list()).toHaveLength(3);
    });
  });

  describe('list', () => {
    it('should return records sorted by timestamp', () => {
      const buffer = new ActivityBuffer();

      buffer.upsert(createRecord('task-2', '2024-01-01T00:01:00Z'));
      buffer.upsert(createRecord('task-1', '2024-01-01T00:00:00Z'));
      buffer.upsert(createRecord('task-3', '2024-01-01T00:02:00Z'));

      const list = buffer.list();
      expect(list[0].task_id).toBe('task-1');
      expect(list[1].task_id).toBe('task-2');
      expect(list[2].task_id).toBe('task-3');
    });

    it('should return empty array when buffer is empty', () => {
      const buffer = new ActivityBuffer();
      expect(buffer.list()).toEqual([]);
    });
  });

  describe('recent', () => {
    let buffer: ActivityBuffer;

    beforeEach(() => {
      buffer = new ActivityBuffer();
      for (let i = 0; i < 10; i++) {
        buffer.upsert(createRecord(`task-${i}`, `2024-01-01T00:0${i}:00Z`));
      }
    });

    it('should return most recent records', () => {
      const recent = buffer.recent(3);
      expect(recent).toHaveLength(3);

      // Most recent should be task-7, task-8, task-9
      expect(recent[0].task_id).toBe('task-7');
      expect(recent[1].task_id).toBe('task-8');
      expect(recent[2].task_id).toBe('task-9');
    });

    it('should use default limit of 50', () => {
      const recent = buffer.recent();
      expect(recent).toHaveLength(10); // All records, since we only have 10
    });

    it('should return all records if limit exceeds count', () => {
      const recent = buffer.recent(100);
      expect(recent).toHaveLength(10);
    });
  });

  describe('reconcile', () => {
    let buffer: ActivityBuffer;

    beforeEach(() => {
      buffer = new ActivityBuffer();
      buffer.upsert(createRecord('task-1'));
      buffer.upsert(createRecord('task-2'));
      buffer.upsert(createRecord('task-3'));
    });

    it('should remove records not in known task IDs', () => {
      const knownTaskIds = new Set(['task-1', 'task-3']);
      buffer.reconcile(knownTaskIds);

      const list = buffer.list();
      expect(list).toHaveLength(2);

      const taskIds = list.map((r) => r.task_id);
      expect(taskIds).toContain('task-1');
      expect(taskIds).toContain('task-3');
      expect(taskIds).not.toContain('task-2');
    });

    it('should handle empty known task IDs', () => {
      buffer.reconcile(new Set());

      expect(buffer.list()).toHaveLength(0);
    });

    it('should keep all records if all are known', () => {
      const knownTaskIds = new Set(['task-1', 'task-2', 'task-3']);
      buffer.reconcile(knownTaskIds);

      expect(buffer.list()).toHaveLength(3);
    });
  });

  describe('toJSON / fromJSON', () => {
    it('should serialize to JSON', () => {
      const buffer = new ActivityBuffer();
      buffer.upsert(createRecord('task-1', '2024-01-01T00:00:00Z'));
      buffer.upsert(createRecord('task-2', '2024-01-01T00:01:00Z'));

      const json = buffer.toJSON();
      expect(json).toHaveLength(2);
      expect(json[0].task_id).toBe('task-1');
      expect(json[1].task_id).toBe('task-2');
    });

    it('should deserialize from JSON', () => {
      const records: ActivityRecord[] = [
        createRecord('task-1', '2024-01-01T00:00:00Z'),
        createRecord('task-2', '2024-01-01T00:01:00Z'),
      ];

      const buffer = new ActivityBuffer();
      buffer.fromJSON(records);

      expect(buffer.list()).toHaveLength(2);
      expect(buffer.list()[0].task_id).toBe('task-1');
    });

    it('should clear existing records when deserializing', () => {
      const buffer = new ActivityBuffer();
      buffer.upsert(createRecord('existing'));

      buffer.fromJSON([createRecord('new-task')]);

      expect(buffer.list()).toHaveLength(1);
      expect(buffer.list()[0].task_id).toBe('new-task');
    });

    it('should prune after deserializing if exceeds maxEntries', () => {
      const buffer = new ActivityBuffer({ maxEntries: 2 });

      const records: ActivityRecord[] = [
        createRecord('task-1', '2024-01-01T00:00:00Z'),
        createRecord('task-2', '2024-01-01T00:01:00Z'),
        createRecord('task-3', '2024-01-01T00:02:00Z'),
      ];

      buffer.fromJSON(records);

      expect(buffer.list()).toHaveLength(2);
      // Oldest should be evicted
      const taskIds = buffer.list().map((r) => r.task_id);
      expect(taskIds).not.toContain('task-1');
    });
  });

  describe('MaxEntriesStrategy', () => {
    it('should return records as-is when under limit', () => {
      const strategy = new MaxEntriesStrategy();
      const records: ActivityRecord[] = [
        createRecord('task-1'),
        createRecord('task-2'),
      ];

      const pruned = strategy.prune(records, 3);
      expect(pruned).toEqual(records);
    });

    it('should drop oldest when at limit', () => {
      const strategy = new MaxEntriesStrategy();
      const records: ActivityRecord[] = [
        createRecord('task-1', '2024-01-01T00:00:00Z'),
        createRecord('task-2', '2024-01-01T00:01:00Z'),
        createRecord('task-3', '2024-01-01T00:02:00Z'),
      ];

      const pruned = strategy.prune(records, 2);
      expect(pruned).toHaveLength(2);
      expect(pruned[0].task_id).toBe('task-2');
      expect(pruned[1].task_id).toBe('task-3');
    });

    it('should handle empty records', () => {
      const strategy = new MaxEntriesStrategy();
      const pruned = strategy.prune([], 10);
      expect(pruned).toEqual([]);
    });
  });

  describe('integration', () => {
    it('should support full buffer lifecycle', () => {
      const buffer = new ActivityBuffer({ maxEntries: 5 });

      // Add records
      for (let i = 0; i < 3; i++) {
        buffer.upsert(createRecord(`task-${i}`, `2024-01-01T00:0${i}:00Z`));
      }
      expect(buffer.list()).toHaveLength(3);

      // Update a record
      buffer.upsert({
        ...createRecord('task-1', '2024-01-01T00:01:00Z'),
        description: 'Updated',
      });
      expect(buffer.list()).toHaveLength(3);

      // Add more to trigger pruning
      buffer.upsert(createRecord('task-3', '2024-01-01T00:03:00Z'));
      buffer.upsert(createRecord('task-4', '2024-01-01T00:04:00Z'));
      buffer.upsert(createRecord('task-5', '2024-01-01T00:05:00Z'));
      buffer.upsert(createRecord('task-6', '2024-01-01T00:06:00Z'));

      // Should have pruned oldest
      expect(buffer.list()).toHaveLength(5);

      // Serialize and deserialize
      const json = buffer.toJSON();
      const newBuffer = new ActivityBuffer({ maxEntries: 5 });
      newBuffer.fromJSON(json);
      expect(newBuffer.list()).toHaveLength(5);

      // Reconcile
      newBuffer.reconcile(new Set(['task-3', 'task-4', 'task-5']));
      expect(newBuffer.list()).toHaveLength(3);
    });

    it('should maintain FIFO order during complex operations', () => {
      const buffer = new ActivityBuffer({ maxEntries: 3 });

      // Add in order
      buffer.upsert(createRecord('a', '2024-01-01T00:00:00Z'));
      buffer.upsert(createRecord('b', '2024-01-01T00:01:00Z'));
      buffer.upsert(createRecord('c', '2024-01-01T00:02:00Z'));

      // Trigger eviction
      buffer.upsert(createRecord('d', '2024-01-01T00:03:00Z'));

      // 'a' should be evicted (oldest)
      let list = buffer.list();
      expect(list.map((r) => r.task_id)).toEqual(['b', 'c', 'd']);

      // Add another
      buffer.upsert(createRecord('e', '2024-01-01T00:04:00Z'));

      // 'b' should be evicted
      list = buffer.list();
      expect(list.map((r) => r.task_id)).toEqual(['c', 'd', 'e']);
    });
  });
});
