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
  WorkflowClient,
  WorkflowDefinition,
  WorkflowNode,
  NodeStatus,
  TriggerType,
  WorkflowStatus,
  WorkflowValidationError,
  WorkflowCycleError,
} from '../src/clients/workflow.js';

describe('WorkflowClient', () => {
  let client: WorkflowClient;

  beforeEach(() => {
    client = new WorkflowClient();
  });

  describe('createWorkflow', () => {
    it('should create a simple workflow', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'simple-workflow',
        nodes: {
          'node-1': {
            nodeId: 'node-1',
            agentId: 'agent-1',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      const workflowId = await client.createWorkflow(definition);
      expect(workflowId).toBe('simple-workflow');

      const retrieved = await client.getWorkflowDefinition('simple-workflow');
      expect(retrieved).not.toBeNull();
      expect(retrieved?.workflowId).toBe('simple-workflow');
    });

    it('should create workflow with dependencies', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'dep-workflow',
        nodes: {
          'produce': {
            nodeId: 'produce',
            agentId: 'producer',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: { artifact: 'produced_artifact' },
            metadata: {},
          },
          'review': {
            nodeId: 'review',
            agentId: 'reviewer',
            dependencies: ['produce'],
            triggerType: TriggerType.DEPENDENCY,
            inputMapping: { artifact: 'produced_artifact' },
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      const workflowId = await client.createWorkflow(definition);
      expect(workflowId).toBe('dep-workflow');

      const retrieved = await client.getWorkflowDefinition('dep-workflow');
      expect(retrieved?.nodes['review'].dependencies).toContain('produce');
    });

    it('should set createdAt timestamp', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'ts-workflow',
        nodes: {
          'node-1': {
            nodeId: 'node-1',
            agentId: 'agent-1',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      await client.createWorkflow(definition);

      const retrieved = await client.getWorkflowDefinition('ts-workflow');
      expect(retrieved?.createdAt).toBeDefined();
      expect(typeof retrieved?.createdAt).toBe('string');
    });

    it('should reject duplicate workflow ID', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'dup-workflow',
        nodes: {
          'node-1': {
            nodeId: 'node-1',
            agentId: 'agent-1',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      await client.createWorkflow(definition);

      await expect(client.createWorkflow(definition)).rejects.toThrow(
        WorkflowValidationError
      );
    });

    it('should reject invalid dependency reference', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'invalid-dep',
        nodes: {
          'node-1': {
            nodeId: 'node-1',
            agentId: 'agent-1',
            dependencies: ['nonexistent'],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      await expect(client.createWorkflow(definition)).rejects.toThrow(
        WorkflowValidationError
      );
    });

    it('should detect self-dependency', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'self-dep',
        nodes: {
          'node-1': {
            nodeId: 'node-1',
            agentId: 'agent-1',
            dependencies: ['node-1'],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      await expect(client.createWorkflow(definition)).rejects.toThrow(
        WorkflowCycleError
      );
    });
  });

  describe('cycle detection', () => {
    it('should detect simple 2-node cycle', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'cycle-2',
        nodes: {
          'a': {
            nodeId: 'a',
            agentId: 'agent-a',
            dependencies: ['b'],
            triggerType: TriggerType.DEPENDENCY,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
          'b': {
            nodeId: 'b',
            agentId: 'agent-b',
            dependencies: ['a'],
            triggerType: TriggerType.DEPENDENCY,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      await expect(client.createWorkflow(definition)).rejects.toThrow(
        WorkflowCycleError
      );
    });

    it('should detect complex cycle in larger graph', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'cycle-complex',
        nodes: {
          'a': {
            nodeId: 'a',
            agentId: 'agent-a',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
          'b': {
            nodeId: 'b',
            agentId: 'agent-b',
            dependencies: ['a'],
            triggerType: TriggerType.DEPENDENCY,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
          'c': {
            nodeId: 'c',
            agentId: 'agent-c',
            dependencies: ['b'],
            triggerType: TriggerType.DEPENDENCY,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
          'd': {
            nodeId: 'd',
            agentId: 'agent-d',
            dependencies: ['c'],
            triggerType: TriggerType.DEPENDENCY,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
          'e': {
            nodeId: 'e',
            agentId: 'agent-e',
            dependencies: ['d', 'b'], // Creates cycle: b -> c -> d -> e -> b
            triggerType: TriggerType.DEPENDENCY,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      // Add the cycle-creating dependency
      definition.nodes['b'].dependencies.push('e');

      await expect(client.createWorkflow(definition)).rejects.toThrow(
        WorkflowCycleError
      );
    });

    it('should accept valid DAG (diamond shape)', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'valid-dag',
        nodes: {
          'a': {
            nodeId: 'a',
            agentId: 'agent-a',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
          'b': {
            nodeId: 'b',
            agentId: 'agent-b',
            dependencies: ['a'],
            triggerType: TriggerType.DEPENDENCY,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
          'c': {
            nodeId: 'c',
            agentId: 'agent-c',
            dependencies: ['a'],
            triggerType: TriggerType.DEPENDENCY,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
          'd': {
            nodeId: 'd',
            agentId: 'agent-d',
            dependencies: ['b', 'c'],
            triggerType: TriggerType.DEPENDENCY,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      const workflowId = await client.createWorkflow(definition);
      expect(workflowId).toBe('valid-dag');
    });
  });

  describe('startWorkflow', () => {
    it('should start a workflow instance', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'start-test',
        nodes: {
          'node-1': {
            nodeId: 'node-1',
            agentId: 'agent-1',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      await client.createWorkflow(definition);

      const instance = await client.startWorkflow('start-test');

      expect(instance.workflowId).toBe('start-test');
      expect(instance.status).toBe(WorkflowStatus.RUNNING);
      expect(instance.instanceId).toBeDefined();
      expect(instance.startedAt).toBeDefined();
    });

    it('should initialize node states based on dependencies', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'node-states',
        nodes: {
          'root': {
            nodeId: 'root',
            agentId: 'agent-root',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
          'child': {
            nodeId: 'child',
            agentId: 'agent-child',
            dependencies: ['root'],
            triggerType: TriggerType.DEPENDENCY,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      await client.createWorkflow(definition);
      const instance = await client.startWorkflow('node-states');

      // Root node should be READY (no dependencies)
      expect(instance.nodeStates['root'].status).toBe(NodeStatus.READY);

      // Child node should be PENDING (has dependencies)
      expect(instance.nodeStates['child'].status).toBe(NodeStatus.PENDING);
    });

    it('should accept initial workflow data', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'initial-data',
        nodes: {
          'node-1': {
            nodeId: 'node-1',
            agentId: 'agent-1',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      await client.createWorkflow(definition);

      const initialData = JSON.stringify({ config: 'test', value: 42 });
      const instance = await client.startWorkflow(
        'initial-data',
        initialData
      );

      expect(instance.workflowData).toBe(initialData);
    });

    it('should accept metadata', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'metadata-test',
        nodes: {
          'node-1': {
            nodeId: 'node-1',
            agentId: 'agent-1',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      await client.createWorkflow(definition);

      const metadata = { user: 'test-user', env: 'staging' };
      const instance = await client.startWorkflow(
        'metadata-test',
        undefined,
        metadata
      );

      expect(instance.metadata).toEqual(metadata);
    });

    it('should reject starting non-existent workflow', async () => {
      await expect(client.startWorkflow('nonexistent')).rejects.toThrow(
        WorkflowValidationError
      );
    });
  });

  describe('getWorkflowStatus', () => {
    it('should return workflow instance status', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'status-test',
        nodes: {
          'node-1': {
            nodeId: 'node-1',
            agentId: 'agent-1',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      await client.createWorkflow(definition);
      const instance = await client.startWorkflow('status-test');

      const status = await client.getWorkflowStatus(instance.instanceId);
      expect(status.instanceId).toBe(instance.instanceId);
      expect(status.status).toBe(WorkflowStatus.RUNNING);
    });

    it('should reject getting status for non-existent instance', async () => {
      await expect(client.getWorkflowStatus('nonexistent')).rejects.toThrow(
        WorkflowValidationError
      );
    });
  });

  describe('updateNodeState', () => {
    it('should update node status', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'update-test',
        nodes: {
          'node-1': {
            nodeId: 'node-1',
            agentId: 'agent-1',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      await client.createWorkflow(definition);
      const instance = await client.startWorkflow('update-test');

      await client.updateNodeState(
        instance.instanceId,
        'node-1',
        NodeStatus.RUNNING
      );

      const status = await client.getWorkflowStatus(instance.instanceId);
      expect(status.nodeStates['node-1'].status).toBe(NodeStatus.RUNNING);
      expect(status.nodeStates['node-1'].startedAt).toBeDefined();
    });

    it('should set timestamps on terminal states', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'timestamps-test',
        nodes: {
          'node-1': {
            nodeId: 'node-1',
            agentId: 'agent-1',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      await client.createWorkflow(definition);
      const instance = await client.startWorkflow('timestamps-test');

      await client.updateNodeState(
        instance.instanceId,
        'node-1',
        NodeStatus.COMPLETED
      );

      const status = await client.getWorkflowStatus(instance.instanceId);
      expect(status.nodeStates['node-1'].completedAt).toBeDefined();
    });

    it('should update dependent nodes when node completes', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'deps-update',
        nodes: {
          'a': {
            nodeId: 'a',
            agentId: 'agent-a',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
          'b': {
            nodeId: 'b',
            agentId: 'agent-b',
            dependencies: ['a'],
            triggerType: TriggerType.DEPENDENCY,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      await client.createWorkflow(definition);
      const instance = await client.startWorkflow('deps-update');

      // Initially b is PENDING
      expect(instance.nodeStates['b'].status).toBe(NodeStatus.PENDING);

      // Complete node a
      await client.updateNodeState(
        instance.instanceId,
        'a',
        NodeStatus.COMPLETED
      );

      const status = await client.getWorkflowStatus(instance.instanceId);

      // Now b should be READY
      expect(status.nodeStates['b'].status).toBe(NodeStatus.READY);
    });

    it('should only update dependent when all deps are complete', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'multi-deps',
        nodes: {
          'a': {
            nodeId: 'a',
            agentId: 'agent-a',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
          'b': {
            nodeId: 'b',
            agentId: 'agent-b',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
          'c': {
            nodeId: 'c',
            agentId: 'agent-c',
            dependencies: ['a', 'b'],
            triggerType: TriggerType.DEPENDENCY,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      await client.createWorkflow(definition);
      const instance = await client.startWorkflow('multi-deps');

      // Complete only node a
      await client.updateNodeState(
        instance.instanceId,
        'a',
        NodeStatus.COMPLETED
      );

      let status = await client.getWorkflowStatus(instance.instanceId);
      // c should still be PENDING (b not complete)
      expect(status.nodeStates['c'].status).toBe(NodeStatus.PENDING);

      // Complete node b
      await client.updateNodeState(
        instance.instanceId,
        'b',
        NodeStatus.COMPLETED
      );

      status = await client.getWorkflowStatus(instance.instanceId);
      // Now c should be READY
      expect(status.nodeStates['c'].status).toBe(NodeStatus.READY);
    });

    it('should mark workflow as COMPLETED when all nodes complete', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'complete-test',
        nodes: {
          'node-1': {
            nodeId: 'node-1',
            agentId: 'agent-1',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      await client.createWorkflow(definition);
      const instance = await client.startWorkflow('complete-test');

      await client.updateNodeState(
        instance.instanceId,
        'node-1',
        NodeStatus.COMPLETED
      );

      const status = await client.getWorkflowStatus(instance.instanceId);
      expect(status.status).toBe(WorkflowStatus.COMPLETED);
      expect(status.completedAt).toBeDefined();
    });

    it('should mark workflow as FAILED when any node fails', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'fail-test',
        nodes: {
          'node-1': {
            nodeId: 'node-1',
            agentId: 'agent-1',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      await client.createWorkflow(definition);
      const instance = await client.startWorkflow('fail-test');

      await client.updateNodeState(
        instance.instanceId,
        'node-1',
        NodeStatus.FAILED,
        undefined,
        'Simulated error'
      );

      const status = await client.getWorkflowStatus(instance.instanceId);
      expect(status.status).toBe(WorkflowStatus.FAILED);
      expect(status.nodeStates['node-1'].error).toBe('Simulated error');
    });

    it('should store node output data', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'output-test',
        nodes: {
          'node-1': {
            nodeId: 'node-1',
            agentId: 'agent-1',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      await client.createWorkflow(definition);
      const instance = await client.startWorkflow('output-test');

      const outputData = JSON.stringify({ result: 'success', count: 42 });
      await client.updateNodeState(
        instance.instanceId,
        'node-1',
        NodeStatus.COMPLETED,
        outputData
      );

      const status = await client.getWorkflowStatus(instance.instanceId);
      expect(status.nodeStates['node-1'].output).toBe(outputData);
    });
  });

  describe('cancelWorkflow', () => {
    it('should cancel a running workflow', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'cancel-test',
        nodes: {
          'node-1': {
            nodeId: 'node-1',
            agentId: 'agent-1',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      await client.createWorkflow(definition);
      const instance = await client.startWorkflow('cancel-test');

      await client.cancelWorkflow(instance.instanceId);

      const status = await client.getWorkflowStatus(instance.instanceId);
      expect(status.status).toBe(WorkflowStatus.CANCELLED);
      expect(status.completedAt).toBeDefined();
    });

    it('should mark pending nodes as SKIPPED', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'cancel-skip',
        nodes: {
          'a': {
            nodeId: 'a',
            agentId: 'agent-a',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
          'b': {
            nodeId: 'b',
            agentId: 'agent-b',
            dependencies: ['a'],
            triggerType: TriggerType.DEPENDENCY,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      await client.createWorkflow(definition);
      const instance = await client.startWorkflow('cancel-skip');

      await client.cancelWorkflow(instance.instanceId);

      const status = await client.getWorkflowStatus(instance.instanceId);
      expect(status.nodeStates['a'].status).toBe(NodeStatus.SKIPPED);
      expect(status.nodeStates['b'].status).toBe(NodeStatus.SKIPPED);
    });

    it('should reject cancelling already completed workflow', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'cancel-complete',
        nodes: {
          'node-1': {
            nodeId: 'node-1',
            agentId: 'agent-1',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      await client.createWorkflow(definition);
      const instance = await client.startWorkflow('cancel-complete');

      await client.updateNodeState(
        instance.instanceId,
        'node-1',
        NodeStatus.COMPLETED
      );

      await expect(client.cancelWorkflow(instance.instanceId)).rejects.toThrow(
        WorkflowValidationError
      );
    });
  });

  describe('updateWorkflowData', () => {
    it('should update shared workflow data', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'data-update',
        nodes: {
          'node-1': {
            nodeId: 'node-1',
            agentId: 'agent-1',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      await client.createWorkflow(definition);
      const instance = await client.startWorkflow('data-update');

      const newData = JSON.stringify({ updated: true, value: 123 });
      await client.updateWorkflowData(instance.instanceId, newData);

      const status = await client.getWorkflowStatus(instance.instanceId);
      expect(status.workflowData).toBe(newData);
    });
  });

  describe('listWorkflowInstances', () => {
    it('should list all instances of a workflow', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'list-test',
        nodes: {
          'node-1': {
            nodeId: 'node-1',
            agentId: 'agent-1',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      await client.createWorkflow(definition);

      const instance1 = await client.startWorkflow('list-test');
      const instance2 = await client.startWorkflow('list-test');
      const instance3 = await client.startWorkflow('list-test');

      const instances = await client.listWorkflowInstances('list-test');
      expect(instances).toHaveLength(3);
      expect(instances.map((i) => i.instanceId).sort()).toEqual(
        [instance1.instanceId, instance2.instanceId, instance3.instanceId].sort()
      );
    });

    it('should return empty array for workflow with no instances', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'no-instances',
        nodes: {
          'node-1': {
            nodeId: 'node-1',
            agentId: 'agent-1',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: {},
          },
        },
        metadata: {},
      };

      await client.createWorkflow(definition);

      const instances = await client.listWorkflowInstances('no-instances');
      expect(instances).toEqual([]);
    });

    it('should return empty array for non-existent workflow', async () => {
      const instances = await client.listWorkflowInstances('nonexistent');
      expect(instances).toEqual([]);
    });
  });

  describe('getWorkflowDefinition', () => {
    it('should return null for non-existent workflow', async () => {
      const definition = await client.getWorkflowDefinition('nonexistent');
      expect(definition).toBeNull();
    });

    it('should return workflow definition', async () => {
      const definition: WorkflowDefinition = {
        workflowId: 'get-def',
        nodes: {
          'node-1': {
            nodeId: 'node-1',
            agentId: 'agent-1',
            dependencies: [],
            triggerType: TriggerType.MANUAL,
            inputMapping: {},
            outputMapping: {},
            metadata: { key: 'value' },
          },
        },
        metadata: { workflow: 'metadata' },
      };

      await client.createWorkflow(definition);

      const retrieved = await client.getWorkflowDefinition('get-def');
      expect(retrieved?.nodes['node-1'].metadata).toEqual({ key: 'value' });
      expect(retrieved?.metadata).toEqual({ workflow: 'metadata' });
    });
  });
});
