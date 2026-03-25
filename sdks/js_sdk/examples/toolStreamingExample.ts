#!/usr/bin/env npx tsx
/**
 * Tool Streaming Example for SW4RM Protocol.
 *
 * This example demonstrates:
 * - Streaming tool calls using ToolClient.callStream()
 * - How to handle streaming frames progressively via async generators
 * - Cancellation handling with ToolClient.cancel()
 * - Frame types: PROGRESS, OUTPUT, RESULT, ERROR, CANCELLED
 * - StreamingToolHandler for aggregating results from a stream
 *
 * The real ToolClient (in ../src/clients/tool.ts) requires a live gRPC
 * endpoint. This file uses local mock classes that mirror the SDK's
 * public interface so the example runs without any external service.
 *
 * Prerequisites:
 *   - Install dependencies: `npm install`
 *
 * Run:
 *   npx tsx examples/toolStreamingExample.ts
 *
 * Execution mode:
 *   - Local mock-backed demo. No external services are required.
 *     MockToolProvider simulates streaming tools and cancellation; the
 *     real ToolClient would be a drop-in replacement on a live cluster.
 *
 * @packageDocumentation
 */

// ============================================================================
// Local Type Definitions (mirror ../src/clients/tool.ts shapes)
// ============================================================================

/**
 * Execution policy attached to a tool call.
 * Mirrors the real ExecutionPolicy from the SDK.
 */
interface ExecutionPolicy {
  timeoutMs?: number;
  maxRetries?: number;
  worktreeRequired?: boolean;
  networkPolicy?: string;
  privilegeLevel?: string;
}

/**
 * Request to execute a tool.
 * Mirrors the real ToolCall interface from the SDK (adapted for mock use).
 */
interface ToolCall {
  callId: string;
  toolName: string;
  providerId?: string;
  args: Record<string, unknown>;
  worktreeId?: string;
  policy?: ExecutionPolicy;
  stream?: boolean;
}

/**
 * A single frame in a streaming tool response.
 * Mirrors the real ToolFrame interface from the SDK.
 */
interface ToolFrame {
  callId: string;
  frameNo: number;
  final: boolean;
  frameType: FrameType;
  data: Record<string, unknown>;
  timestampMs: number;
}

/**
 * Result returned by a cancellation request.
 */
interface CancelResult {
  callId: string;
  success: boolean;
  message: string;
}

// ============================================================================
// FrameType Enum
// ============================================================================

/**
 * Types of frames that can appear in a streaming tool response.
 */
enum FrameType {
  /** Progress update carrying percentage and status message. */
  PROGRESS = 1,
  /** Partial output data emitted during execution. */
  OUTPUT = 2,
  /** Final result frame — the stream ends after this. */
  RESULT = 3,
  /** An error occurred during execution. */
  ERROR = 4,
  /** The tool call was cancelled by the caller. */
  CANCELLED = 5,
}

// ============================================================================
// MockToolProvider
// ============================================================================

/**
 * Mock tool provider for demonstration.
 *
 * Simulates various tools with streaming responses via async generators.
 * In production this would be replaced by a gRPC call through ToolClient.
 */
class MockToolProvider {
  private _activeCalls = new Map<string, boolean>();
  private _cancelRequested = new Set<string>();

  /**
   * Execute a tool call and yield frames as the tool runs.
   *
   * @param call - The tool call to execute.
   * @yields ToolFrame objects in sequence order.
   */
  async *callStream(call: ToolCall): AsyncGenerator<ToolFrame> {
    this._activeCalls.set(call.callId, true);
    this._cancelRequested.delete(call.callId);

    try {
      if (call.toolName === 'file_search') {
        yield* this._fileSearchStream(call);
      } else if (call.toolName === 'code_analysis') {
        yield* this._codeAnalysisStream(call);
      } else if (call.toolName === 'long_computation') {
        yield* this._longComputationStream(call);
      } else {
        yield this._makeFrame(call.callId, 0, FrameType.ERROR, true, {
          error: `Unknown tool: ${call.toolName}`,
        });
      }
    } finally {
      this._activeCalls.delete(call.callId);
    }
  }

  /**
   * Request cancellation of an active tool call.
   *
   * @param callId - The call to cancel.
   * @returns A CancelResult indicating whether cancellation was registered.
   */
  cancel(callId: string): CancelResult {
    if (!this._activeCalls.has(callId)) {
      return {
        callId,
        success: false,
        message: 'Call not found or already completed',
      };
    }
    this._cancelRequested.add(callId);
    return { callId, success: true, message: 'Cancellation requested' };
  }

  private _isCancelled(callId: string): boolean {
    return this._cancelRequested.has(callId);
  }

  private _makeFrame(
    callId: string,
    frameNo: number,
    frameType: FrameType,
    final: boolean,
    data: Record<string, unknown>
  ): ToolFrame {
    return {
      callId,
      frameNo,
      final,
      frameType,
      data,
      timestampMs: Date.now(),
    };
  }

  private async *_fileSearchStream(call: ToolCall): AsyncGenerator<ToolFrame> {
    const pattern = (call.args['pattern'] as string) ?? '*';
    const directory = (call.args['directory'] as string) ?? '/';

    const files = [
      `${directory}/file1.ts`,
      `${directory}/file2.ts`,
      `${directory}/subdir/file3.ts`,
      `${directory}/subdir/file4.ts`,
      `${directory}/subdir/deep/file5.ts`,
    ];

    for (let i = 0; i < files.length; i++) {
      if (this._isCancelled(call.callId)) {
        yield this._makeFrame(call.callId, i, FrameType.CANCELLED, true, {
          message: 'Search cancelled by user',
          filesFound: i,
        });
        return;
      }

      // Progress frame
      yield this._makeFrame(call.callId, i * 2, FrameType.PROGRESS, false, {
        percentage: Math.floor(((i + 1) / files.length) * 100),
        status: `Searching... found ${i + 1} files`,
      });

      // Output frame for the discovered file
      yield this._makeFrame(call.callId, i * 2 + 1, FrameType.OUTPUT, false, {
        file: files[i],
        matchesPattern: pattern === '*' || files[i].includes(pattern.replace('*', '')),
      });

      // Simulate I/O delay
      await new Promise((r) => setTimeout(r, 10));
    }

    // Final result
    yield this._makeFrame(call.callId, files.length * 2, FrameType.RESULT, true, {
      totalFiles: files.length,
      pattern,
      directory,
    });
  }

  private async *_codeAnalysisStream(call: ToolCall): AsyncGenerator<ToolFrame> {
    const _code = call.args['code'] as string;

    const analysisSteps: Array<[string, string]> = [
      ['syntax', 'Checking syntax...'],
      ['imports', 'Analyzing imports...'],
      ['types', 'Checking type annotations...'],
      ['complexity', 'Computing complexity...'],
      ['security', 'Scanning for vulnerabilities...'],
    ];

    const stepResults: Record<string, Record<string, unknown>> = {
      syntax: { valid: true, errors: [] },
      imports: { count: 3, external: ['fs', 'path', 'crypto'] },
      types: { coverage: 0.85, missing: ['return type on line 5'] },
      complexity: { cyclomatic: 4, cognitive: 3 },
      security: { issues: 0, warnings: 1 },
    };

    const results: Record<string, unknown> = {};

    for (let i = 0; i < analysisSteps.length; i++) {
      const [stepName, statusMsg] = analysisSteps[i];

      if (this._isCancelled(call.callId)) {
        yield this._makeFrame(call.callId, i * 2, FrameType.CANCELLED, true, {
          message: 'Analysis cancelled',
          completedSteps: Object.keys(results),
        });
        return;
      }

      // Progress frame
      yield this._makeFrame(call.callId, i * 2, FrameType.PROGRESS, false, {
        percentage: Math.floor(((i + 1) / analysisSteps.length) * 100),
        status: statusMsg,
        currentStep: stepName,
      });

      // Simulate analysis work
      await new Promise((r) => setTimeout(r, 15));

      results[stepName] = stepResults[stepName];

      // Output frame for completed step
      yield this._makeFrame(call.callId, i * 2 + 1, FrameType.OUTPUT, false, {
        step: stepName,
        result: stepResults[stepName],
      });
    }

    // Final result
    yield this._makeFrame(call.callId, analysisSteps.length * 2, FrameType.RESULT, true, {
      summary: 'Analysis complete',
      overallScore: 8.5,
      results,
    });
  }

  private async *_longComputationStream(call: ToolCall): AsyncGenerator<ToolFrame> {
    const iterations = (call.args['iterations'] as number) ?? 10;
    let accumulated = 0;

    for (let i = 0; i < iterations; i++) {
      if (this._isCancelled(call.callId)) {
        yield this._makeFrame(call.callId, i, FrameType.CANCELLED, true, {
          message: 'Computation cancelled',
          completedIterations: i,
          partialResult: accumulated,
        });
        return;
      }

      // Simulate computation work
      await new Promise((r) => setTimeout(r, 20));
      accumulated += i * i;

      yield this._makeFrame(call.callId, i, FrameType.PROGRESS, false, {
        percentage: Math.floor(((i + 1) / iterations) * 100),
        status: `Computing iteration ${i + 1}/${iterations}`,
        intermediateResult: accumulated,
      });
    }

    yield this._makeFrame(call.callId, iterations, FrameType.RESULT, true, {
      finalResult: accumulated,
      iterationsCompleted: iterations,
    });
  }
}

// ============================================================================
// MockToolClient (mirrors real ToolClient API)
// ============================================================================

/**
 * Mock ToolClient that wraps MockToolProvider.
 *
 * This mirrors the public API of the real sw4rm ToolClient. The real
 * client's callStream() returns a grpc.ClientReadableStream; here we
 * return an AsyncGenerator so the consumer code is identical in shape.
 */
class MockToolClient {
  private _provider: MockToolProvider;

  constructor(provider: MockToolProvider) {
    this._provider = provider;
  }

  /**
   * Execute a streaming tool call.
   *
   * @param call - The tool call request.
   * @returns An async generator of ToolFrame objects.
   */
  callStream(call: ToolCall): AsyncGenerator<ToolFrame> {
    return this._provider.callStream(call);
  }

  /**
   * Cancel an active tool call.
   *
   * @param callId - The call ID to cancel.
   * @returns A CancelResult.
   */
  cancel(callId: string): CancelResult {
    return this._provider.cancel(callId);
  }
}

// ============================================================================
// StreamingToolHandler
// ============================================================================

type ProgressCallback = (data: Record<string, unknown>) => void;
type OutputCallback = (data: Record<string, unknown>) => void;
type ToolErrorCallback = (data: Record<string, unknown>) => void;

/**
 * Helper for processing streaming tool responses.
 *
 * Aggregates output frames, tracks the latest progress, stores the
 * final result, and dispatches to optional callbacks on each frame.
 */
class StreamingToolHandler {
  readonly outputs: Array<Record<string, unknown>> = [];
  lastProgress: Record<string, unknown> | null = null;
  result: Record<string, unknown> | null = null;
  cancelled = false;

  private _onProgress?: ProgressCallback;
  private _onOutput?: OutputCallback;
  private _onError?: ToolErrorCallback;

  constructor(opts?: {
    onProgress?: ProgressCallback;
    onOutput?: OutputCallback;
    onError?: ToolErrorCallback;
  }) {
    this._onProgress = opts?.onProgress;
    this._onOutput = opts?.onOutput;
    this._onError = opts?.onError;
  }

  /**
   * Consume all frames from the async generator and return the final result.
   *
   * @param stream - The async generator of ToolFrame objects.
   * @returns The final result data, or null if cancelled or an error occurred.
   */
  async processStream(stream: AsyncGenerator<ToolFrame>): Promise<Record<string, unknown> | null> {
    for await (const frame of stream) {
      this._handleFrame(frame);
      if (frame.final) {
        break;
      }
    }
    return this.result;
  }

  /**
   * Handle a single frame, updating internal state and invoking callbacks.
   *
   * @param frame - The frame to handle.
   */
  handleFrame(frame: ToolFrame): void {
    this._handleFrame(frame);
  }

  private _handleFrame(frame: ToolFrame): void {
    switch (frame.frameType) {
      case FrameType.PROGRESS:
        this.lastProgress = frame.data;
        this._onProgress?.(frame.data);
        break;

      case FrameType.OUTPUT:
        this.outputs.push(frame.data);
        this._onOutput?.(frame.data);
        break;

      case FrameType.RESULT:
        this.result = frame.data;
        break;

      case FrameType.ERROR:
        this._onError?.(frame.data);
        break;

      case FrameType.CANCELLED:
        this.cancelled = true;
        this.result = frame.data;
        break;
    }
  }
}

// ============================================================================
// Scenario 1: Streaming File Search
// ============================================================================

/**
 * Demonstrate streaming file search with progress updates.
 */
async function demoFileSearch(): Promise<void> {
  console.log('\n' + '='.repeat(60));
  console.log('SCENARIO 1: Streaming File Search');
  console.log('='.repeat(60));

  const provider = new MockToolProvider();
  const client = new MockToolClient(provider);

  const callId = `call-file-${Date.now()}`;

  const handler = new StreamingToolHandler({
    onProgress: (data) => {
      console.log(`  Progress: ${data['percentage']}% - ${data['status']}`);
    },
    onOutput: (data) => {
      if (data['matchesPattern']) {
        console.log(`  Found: ${data['file']}`);
      }
    },
  });

  console.log('\nExecuting file search...');

  const stream = client.callStream({
    callId,
    toolName: 'file_search',
    providerId: 'filesystem-provider',
    args: { pattern: '*.ts', directory: '/project' },
  });

  const result = await handler.processStream(stream);

  console.log('\nSearch complete.');
  console.log(`  Total files found: ${result?.['totalFiles']}`);
  console.log(`  Pattern: ${result?.['pattern']}`);
}

// ============================================================================
// Scenario 2: Streaming Code Analysis
// ============================================================================

/**
 * Demonstrate streaming code analysis with step-by-step output.
 */
async function demoCodeAnalysis(): Promise<void> {
  console.log('\n' + '='.repeat(60));
  console.log('SCENARIO 2: Streaming Code Analysis');
  console.log('='.repeat(60));

  const provider = new MockToolProvider();
  const client = new MockToolClient(provider);

  const codeSample = `
async function authenticate(token: string): Promise<User> {
  const decoded = jwt.verify(token, SECRET_KEY);
  return await UserService.findById(decoded.userId);
}
`;

  console.log(`\nAnalyzing code:\n${codeSample}`);

  const handler = new StreamingToolHandler({
    onProgress: (data) => {
      const pct = String(data['percentage']).padStart(3, ' ');
      console.log(`  [${pct}%] ${data['status']}`);
    },
    onOutput: (data) => {
      console.log(`         ${data['step']}: ${JSON.stringify(data['result'])}`);
    },
  });

  const stream = client.callStream({
    callId: `call-analysis-${Date.now()}`,
    toolName: 'code_analysis',
    providerId: 'analyzer-provider',
    args: { code: codeSample },
  });

  const result = await handler.processStream(stream);

  console.log('\nAnalysis complete.');
  console.log(`  Overall score: ${result?.['overallScore']}/10`);
}

// ============================================================================
// Scenario 3: Cancellation
// ============================================================================

/**
 * Demonstrate cancelling a long-running tool call after a few iterations.
 */
async function demoCancellation(): Promise<void> {
  console.log('\n' + '='.repeat(60));
  console.log('SCENARIO 3: Cancellation Handling');
  console.log('='.repeat(60));

  const provider = new MockToolProvider();
  const client = new MockToolClient(provider);

  const callId = `call-compute-${Date.now()}`;

  const handler = new StreamingToolHandler({
    onProgress: (data) => {
      console.log(`  Progress: ${data['percentage']}% - ${data['status']}`);
    },
  });

  console.log('\nStarting long computation (will cancel after 3 frames)...');

  const stream = client.callStream({
    callId,
    toolName: 'long_computation',
    providerId: 'compute-provider',
    args: { iterations: 20 },
  });

  let framesReceived = 0;

  for await (const frame of stream) {
    handler.handleFrame(frame);
    framesReceived++;

    if (framesReceived >= 3 && !handler.cancelled) {
      console.log('\n  Requesting cancellation...');
      const cancelResult = client.cancel(callId);
      console.log(`  Cancel result: ${cancelResult.message}`);
    }

    if (frame.final) {
      break;
    }
  }

  if (handler.cancelled) {
    console.log('\nComputation was cancelled.');
    console.log(`  Completed iterations: ${handler.result?.['completedIterations'] ?? 0}`);
    console.log(`  Partial result: ${handler.result?.['partialResult'] ?? 'N/A'}`);
  }
}

// ============================================================================
// Scenario 4: Error Handling
// ============================================================================

/**
 * Demonstrate error handling when calling an unknown tool.
 */
async function demoErrorHandling(): Promise<void> {
  console.log('\n' + '='.repeat(60));
  console.log('SCENARIO 4: Error Handling');
  console.log('='.repeat(60));

  const provider = new MockToolProvider();
  const client = new MockToolClient(provider);

  const handler = new StreamingToolHandler({
    onError: (data) => {
      console.log(`  ERROR: ${data['error']}`);
    },
  });

  console.log('\nCalling unknown tool...');

  const stream = client.callStream({
    callId: `call-unknown-${Date.now()}`,
    toolName: 'nonexistent_tool',
    providerId: 'unknown-provider',
    args: {},
  });

  const result = await handler.processStream(stream);
  console.log(`  Result: ${JSON.stringify(result)}`);
}

// ============================================================================
// Scenario 5: Real API Reference
// ============================================================================

/**
 * Print a reference snippet showing how to use the real ToolClient.
 * No execution — informational only.
 */
function demoRealApiUsage(): void {
  console.log('\n' + '='.repeat(60));
  console.log('REAL API USAGE (Reference Only)');
  console.log('='.repeat(60));

  console.log(`
To use the real ToolClient with a running Tool service:

  import * as grpc from '@grpc/grpc-js';
  import { ToolClient } from '../src/clients/tool.js';

  // Connect to the tool service
  const client = new ToolClient({
    host: 'localhost',
    port: 50054,
    credentials: grpc.credentials.createInsecure(),
  });

  // Execute a streaming tool call
  const callId = \`call-\${Date.now()}\`;
  const stream = client.callStream({
    call_id: callId,
    tool_name: 'file_search',
    provider_id: 'fs-provider',
    content_type: 'application/json',
    args: Buffer.from(JSON.stringify({ pattern: '*.ts', directory: '/src' })),
    stream: true,
  });

  // Consume the gRPC ClientReadableStream
  stream.on('data', (frame: ToolFrame) => {
    // frame_no  — sequence number
    // final     — true on the last frame
    // data      — raw Uint8Array payload
    console.log(\`Frame \${frame.frame_no}: final=\${frame.final}\`);
    if (frame.final) {
      console.log('Result:', Buffer.from(frame.data).toString('utf8'));
    }
  });

  stream.on('error', (err) => console.error('Stream error:', err));
  stream.on('end', () => console.log('Stream ended'));

  // Cancel if needed (before stream ends)
  await client.cancel({
    call_id: callId,
    tool_name: 'file_search',
    content_type: 'application/json',
    args: new Uint8Array(),
  });
`);
}

// ============================================================================
// Main
// ============================================================================

async function main(): Promise<number> {
  console.log('SW4RM Tool Streaming Example');
  console.log('='.repeat(60));
  console.log('This demonstrates streaming tool calls with progress,');
  console.log('output frames, cancellation, and error handling.\n');

  await demoFileSearch();
  await demoCodeAnalysis();
  await demoCancellation();
  await demoErrorHandling();
  demoRealApiUsage();

  console.log('\n' + '='.repeat(60));
  console.log('ALL STREAMING SCENARIOS COMPLETED');
  console.log('='.repeat(60));

  console.log('\nKey takeaways:');
  console.log('1. Use callStream() for tools that produce incremental output');
  console.log('2. FrameType values: PROGRESS=1, OUTPUT=2, RESULT=3, ERROR=4, CANCELLED=5');
  console.log('3. Register onProgress and onOutput callbacks for real-time display');
  console.log('4. Call cancel() to abort long-running operations mid-stream');
  console.log('5. The CANCELLED frame carries partial results accumulated so far');
  console.log('6. The ERROR frame is terminal — no RESULT follows an error');

  return 0;
}

main().catch((err) => {
  console.error('[Fatal] Unhandled error:', err);
  process.exit(1);
});
