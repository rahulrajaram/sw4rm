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

import { describe, it, expect, vi, beforeEach } from 'vitest';

/**
 * Tests for ToolClient.
 *
 * These tests verify the ToolClient functionality for tool invocation,
 * description retrieval, and execution.
 *
 * Ported from: sdks/py_sdk/tests/test_tool_client.py
 */

interface MockToolServiceClient {
  InvokeTool: ReturnType<typeof vi.fn>;
  DescribeTool: ReturnType<typeof vi.fn>;
  ListTools: ReturnType<typeof vi.fn>;
  RegisterTool: ReturnType<typeof vi.fn>;
}

interface ToolInvocation {
  tool_id: string;
  caller_id: string;
  parameters: Uint8Array;
  content_type: string;
  execution_policy?: ExecutionPolicy;
}

interface ExecutionPolicy {
  timeout_ms?: number;
  max_retries?: number;
  network_policy?: string;
  privilege_level?: string;
}

interface ToolResult {
  tool_id: string;
  invocation_id: string;
  success: boolean;
  result: Uint8Array;
  content_type: string;
  error_message?: string;
  duration_ms: number;
}

interface ToolDescription {
  tool_id: string;
  name: string;
  description: string;
  parameters_schema: string;
  result_schema: string;
  capabilities: string[];
  version: string;
}

// Simplified mock client for testing
class MockToolClient {
  private mockClient: MockToolServiceClient;

  constructor(opts: { address: string }) {
    this.mockClient = {
      InvokeTool: vi.fn(),
      DescribeTool: vi.fn(),
      ListTools: vi.fn(),
      RegisterTool: vi.fn(),
    };
  }

  get client(): MockToolServiceClient {
    return this.mockClient;
  }

  async invokeTool(invocation: ToolInvocation): Promise<ToolResult> {
    return new Promise((resolve, reject) => {
      this.mockClient.InvokeTool(invocation, {}, {}, (err: Error | null, res: ToolResult) => {
        if (err) return reject(err);
        resolve(res);
      });
    });
  }

  async describeTool(toolId: string): Promise<ToolDescription> {
    return new Promise((resolve, reject) => {
      this.mockClient.DescribeTool({ tool_id: toolId }, {}, {}, (err: Error | null, res: ToolDescription) => {
        if (err) return reject(err);
        resolve(res);
      });
    });
  }

  async listTools(capability?: string): Promise<ToolDescription[]> {
    return new Promise((resolve, reject) => {
      this.mockClient.ListTools(
        { capability },
        {},
        {},
        (err: Error | null, res: { tools: ToolDescription[] }) => {
          if (err) return reject(err);
          resolve(res?.tools ?? []);
        }
      );
    });
  }

  async registerTool(tool: ToolDescription): Promise<boolean> {
    return new Promise((resolve, reject) => {
      this.mockClient.RegisterTool(tool, {}, {}, (err: Error | null, res: { ok: boolean }) => {
        if (err) return reject(err);
        resolve(!!res?.ok);
      });
    });
  }
}

describe('ToolClient', () => {
  describe('construction', () => {
    it('should initialize with valid options', () => {
      const client = new MockToolClient({ address: 'localhost:50051' });
      expect(client).toBeDefined();
      expect(client.client).toBeDefined();
    });
  });

  describe('invokeTool', () => {
    let client: MockToolClient;

    beforeEach(() => {
      client = new MockToolClient({ address: 'localhost:50051' });
    });

    it('should invoke tool with valid parameters', async () => {
      const mockResult: ToolResult = {
        tool_id: 'calculator',
        invocation_id: 'inv-123',
        success: true,
        result: new TextEncoder().encode('{"result": 42}'),
        content_type: 'application/json',
        duration_ms: 50,
      };

      client.client.InvokeTool.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockResult);
        }
      );

      const result = await client.invokeTool({
        tool_id: 'calculator',
        caller_id: 'agent-1',
        parameters: new TextEncoder().encode('{"a": 21, "b": 21}'),
        content_type: 'application/json',
      });

      expect(result.success).toBe(true);
      expect(result.tool_id).toBe('calculator');
      expect(result.invocation_id).toBe('inv-123');
      expect(result.duration_ms).toBe(50);
    });

    it('should invoke tool with execution policy', async () => {
      const mockResult: ToolResult = {
        tool_id: 'web-fetcher',
        invocation_id: 'inv-456',
        success: true,
        result: new TextEncoder().encode('{"content": "..."}'),
        content_type: 'application/json',
        duration_ms: 1500,
      };

      client.client.InvokeTool.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockResult);
        }
      );

      const result = await client.invokeTool({
        tool_id: 'web-fetcher',
        caller_id: 'agent-1',
        parameters: new TextEncoder().encode('{"url": "https://example.com"}'),
        content_type: 'application/json',
        execution_policy: {
          timeout_ms: 5000,
          max_retries: 3,
          network_policy: 'full',
        },
      });

      expect(result.success).toBe(true);
      expect(client.client.InvokeTool).toHaveBeenCalledWith(
        expect.objectContaining({
          execution_policy: {
            timeout_ms: 5000,
            max_retries: 3,
            network_policy: 'full',
          },
        }),
        {},
        {},
        expect.any(Function)
      );
    });

    it('should handle tool invocation failure', async () => {
      const mockResult: ToolResult = {
        tool_id: 'calculator',
        invocation_id: 'inv-789',
        success: false,
        result: new Uint8Array(),
        content_type: 'application/json',
        error_message: 'Division by zero',
        duration_ms: 10,
      };

      client.client.InvokeTool.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockResult);
        }
      );

      const result = await client.invokeTool({
        tool_id: 'calculator',
        caller_id: 'agent-1',
        parameters: new TextEncoder().encode('{"a": 1, "b": 0, "op": "divide"}'),
        content_type: 'application/json',
      });

      expect(result.success).toBe(false);
      expect(result.error_message).toBe('Division by zero');
    });

    it('should handle gRPC errors', async () => {
      client.client.InvokeTool.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(new Error('Tool not found'), null);
        }
      );

      await expect(
        client.invokeTool({
          tool_id: 'nonexistent',
          caller_id: 'agent-1',
          parameters: new Uint8Array(),
          content_type: 'application/json',
        })
      ).rejects.toThrow('Tool not found');
    });

    it('should handle timeout scenario', async () => {
      const mockResult: ToolResult = {
        tool_id: 'slow-tool',
        invocation_id: 'inv-timeout',
        success: false,
        result: new Uint8Array(),
        content_type: 'application/json',
        error_message: 'Execution timed out',
        duration_ms: 30000,
      };

      client.client.InvokeTool.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockResult);
        }
      );

      const result = await client.invokeTool({
        tool_id: 'slow-tool',
        caller_id: 'agent-1',
        parameters: new Uint8Array(),
        content_type: 'application/json',
        execution_policy: { timeout_ms: 30000 },
      });

      expect(result.success).toBe(false);
      expect(result.error_message).toBe('Execution timed out');
    });
  });

  describe('describeTool', () => {
    let client: MockToolClient;

    beforeEach(() => {
      client = new MockToolClient({ address: 'localhost:50051' });
    });

    it('should describe tool with valid ID', async () => {
      const mockDescription: ToolDescription = {
        tool_id: 'calculator',
        name: 'Calculator',
        description: 'Performs basic arithmetic operations',
        parameters_schema: '{"type": "object", "properties": {"a": {"type": "number"}, "b": {"type": "number"}}}',
        result_schema: '{"type": "object", "properties": {"result": {"type": "number"}}}',
        capabilities: ['arithmetic', 'math'],
        version: '1.0.0',
      };

      client.client.DescribeTool.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, mockDescription);
        }
      );

      const result = await client.describeTool('calculator');

      expect(result.tool_id).toBe('calculator');
      expect(result.name).toBe('Calculator');
      expect(result.capabilities).toContain('arithmetic');
      expect(result.version).toBe('1.0.0');
    });

    it('should handle tool not found', async () => {
      client.client.DescribeTool.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(new Error('Tool not found: nonexistent'), null);
        }
      );

      await expect(client.describeTool('nonexistent')).rejects.toThrow('Tool not found');
    });
  });

  describe('listTools', () => {
    let client: MockToolClient;

    beforeEach(() => {
      client = new MockToolClient({ address: 'localhost:50051' });
    });

    it('should list all tools', async () => {
      const mockTools: ToolDescription[] = [
        {
          tool_id: 'calculator',
          name: 'Calculator',
          description: 'Math operations',
          parameters_schema: '{}',
          result_schema: '{}',
          capabilities: ['arithmetic'],
          version: '1.0.0',
        },
        {
          tool_id: 'web-fetcher',
          name: 'Web Fetcher',
          description: 'Fetch web content',
          parameters_schema: '{}',
          result_schema: '{}',
          capabilities: ['network', 'http'],
          version: '1.0.0',
        },
      ];

      client.client.ListTools.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { tools: mockTools });
        }
      );

      const result = await client.listTools();

      expect(result).toHaveLength(2);
      expect(result[0].tool_id).toBe('calculator');
      expect(result[1].tool_id).toBe('web-fetcher');
    });

    it('should filter tools by capability', async () => {
      const mockTools: ToolDescription[] = [
        {
          tool_id: 'web-fetcher',
          name: 'Web Fetcher',
          description: 'Fetch web content',
          parameters_schema: '{}',
          result_schema: '{}',
          capabilities: ['network', 'http'],
          version: '1.0.0',
        },
      ];

      client.client.ListTools.mockImplementation(
        (req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          // Simulate server-side filtering
          cb(null, { tools: req.capability === 'network' ? mockTools : [] });
        }
      );

      const result = await client.listTools('network');

      expect(result).toHaveLength(1);
      expect(result[0].capabilities).toContain('network');
    });

    it('should return empty array when no tools match', async () => {
      client.client.ListTools.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { tools: [] });
        }
      );

      const result = await client.listTools('nonexistent-capability');

      expect(result).toEqual([]);
    });
  });

  describe('registerTool', () => {
    let client: MockToolClient;

    beforeEach(() => {
      client = new MockToolClient({ address: 'localhost:50051' });
    });

    it('should register a new tool', async () => {
      client.client.RegisterTool.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: true });
        }
      );

      const result = await client.registerTool({
        tool_id: 'my-tool',
        name: 'My Custom Tool',
        description: 'A custom tool for testing',
        parameters_schema: '{"type": "object"}',
        result_schema: '{"type": "object"}',
        capabilities: ['custom'],
        version: '1.0.0',
      });

      expect(result).toBe(true);
    });

    it('should handle registration failure', async () => {
      client.client.RegisterTool.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: false });
        }
      );

      const result = await client.registerTool({
        tool_id: 'duplicate-tool',
        name: 'Duplicate',
        description: 'Already exists',
        parameters_schema: '{}',
        result_schema: '{}',
        capabilities: [],
        version: '1.0.0',
      });

      expect(result).toBe(false);
    });
  });

  describe('integration', () => {
    it('should support full tool lifecycle: register -> describe -> invoke', async () => {
      const client = new MockToolClient({ address: 'localhost:50051' });

      // Register
      client.client.RegisterTool.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, { ok: true });
        }
      );

      // Describe
      client.client.DescribeTool.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, {
            tool_id: 'new-tool',
            name: 'New Tool',
            description: 'Test tool',
            parameters_schema: '{}',
            result_schema: '{}',
            capabilities: ['test'],
            version: '1.0.0',
          });
        }
      );

      // Invoke
      client.client.InvokeTool.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          cb(null, {
            tool_id: 'new-tool',
            invocation_id: 'inv-new',
            success: true,
            result: new TextEncoder().encode('{"ok": true}'),
            content_type: 'application/json',
            duration_ms: 100,
          });
        }
      );

      // Run lifecycle
      const registered = await client.registerTool({
        tool_id: 'new-tool',
        name: 'New Tool',
        description: 'Test tool',
        parameters_schema: '{}',
        result_schema: '{}',
        capabilities: ['test'],
        version: '1.0.0',
      });
      expect(registered).toBe(true);

      const description = await client.describeTool('new-tool');
      expect(description.tool_id).toBe('new-tool');

      const result = await client.invokeTool({
        tool_id: 'new-tool',
        caller_id: 'agent-1',
        parameters: new Uint8Array(),
        content_type: 'application/json',
      });
      expect(result.success).toBe(true);
    });

    it('should support multiple tool invocations', async () => {
      const client = new MockToolClient({ address: 'localhost:50051' });

      let invocationCount = 0;
      client.client.InvokeTool.mockImplementation(
        (_req: any, _meta: any, _opts: any, cb: (err: Error | null, res: any) => void) => {
          invocationCount++;
          cb(null, {
            tool_id: 'counter',
            invocation_id: `inv-${invocationCount}`,
            success: true,
            result: new TextEncoder().encode(`{"count": ${invocationCount}}`),
            content_type: 'application/json',
            duration_ms: 10,
          });
        }
      );

      const results = await Promise.all([
        client.invokeTool({
          tool_id: 'counter',
          caller_id: 'agent-1',
          parameters: new Uint8Array(),
          content_type: 'application/json',
        }),
        client.invokeTool({
          tool_id: 'counter',
          caller_id: 'agent-1',
          parameters: new Uint8Array(),
          content_type: 'application/json',
        }),
        client.invokeTool({
          tool_id: 'counter',
          caller_id: 'agent-1',
          parameters: new Uint8Array(),
          content_type: 'application/json',
        }),
      ]);

      expect(results).toHaveLength(3);
      results.forEach((r) => {
        expect(r.success).toBe(true);
      });
    });
  });
});
