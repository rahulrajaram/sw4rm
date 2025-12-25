#!/usr/bin/env python3
"""
Tool Streaming Example for SW4RM Protocol.

This example demonstrates:
- Streaming tool calls using ToolClient.call_stream()
- How to handle streaming frames progressively
- Cancellation handling with ToolClient.cancel()
- Frame types: PROGRESS, OUTPUT, RESULT, ERROR

Prerequisites:
  - Generate protobuf stubs: `make protos`
  - Install deps: `python -m pip install -e ".[dev]"`
  - Optional: Running Tool service on localhost:50054

Run:
  python examples/tool_streaming_example.py
"""
from __future__ import annotations

import json
import time
import uuid
import threading
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Generator, Optional, Callable


# ---------------------------------------------------------------------------
# Frame Types and Data Structures
# ---------------------------------------------------------------------------

class FrameType(Enum):
    """Types of frames in a streaming tool response."""
    PROGRESS = 1      # Progress update (percentage, status message)
    OUTPUT = 2        # Partial output data
    RESULT = 3        # Final result
    ERROR = 4         # Error occurred
    CANCELLED = 5     # Tool call was cancelled


@dataclass
class ToolFrame:
    """A single frame in a streaming tool response.

    Attributes:
        call_id: Unique identifier for the tool call
        frame_type: Type of this frame
        sequence: Sequence number for ordering
        data: Frame payload (varies by type)
        timestamp_ms: When the frame was generated
    """
    call_id: str
    frame_type: FrameType
    sequence: int
    data: dict[str, Any]
    timestamp_ms: int = field(default_factory=lambda: int(time.time() * 1000))


@dataclass
class ToolCall:
    """Request to execute a tool.

    Attributes:
        call_id: Unique identifier for this call
        tool_name: Name of the tool to execute
        provider_id: ID of the provider offering this tool
        args: Arguments to pass to the tool
        worktree_id: Optional worktree context
        timeout_ms: Maximum execution time
    """
    call_id: str
    tool_name: str
    provider_id: str
    args: dict[str, Any]
    worktree_id: Optional[str] = None
    timeout_ms: int = 30000


@dataclass
class CancelResult:
    """Result of a cancellation request.

    Attributes:
        call_id: The call that was cancelled
        success: Whether cancellation succeeded
        message: Additional information
    """
    call_id: str
    success: bool
    message: str


# ---------------------------------------------------------------------------
# Mock Tool Provider
# ---------------------------------------------------------------------------

class MockToolProvider:
    """Mock tool provider for demonstration.

    Simulates various tools with streaming responses.
    In production, this would be a gRPC service.
    """

    def __init__(self):
        """Initialize the mock tool provider."""
        self._active_calls: dict[str, bool] = {}  # call_id -> is_running
        self._cancel_events: dict[str, threading.Event] = {}

    def call_stream(self, call: ToolCall) -> Generator[ToolFrame, None, None]:
        """Execute a tool with streaming response.

        Args:
            call: The tool call request

        Yields:
            ToolFrame objects as the tool executes
        """
        self._active_calls[call.call_id] = True
        self._cancel_events[call.call_id] = threading.Event()

        try:
            if call.tool_name == "file_search":
                yield from self._file_search_stream(call)
            elif call.tool_name == "code_analysis":
                yield from self._code_analysis_stream(call)
            elif call.tool_name == "long_computation":
                yield from self._long_computation_stream(call)
            else:
                yield ToolFrame(
                    call_id=call.call_id,
                    frame_type=FrameType.ERROR,
                    sequence=0,
                    data={"error": f"Unknown tool: {call.tool_name}"}
                )
        finally:
            self._active_calls.pop(call.call_id, None)
            self._cancel_events.pop(call.call_id, None)

    def cancel(self, call_id: str) -> CancelResult:
        """Cancel an active tool call.

        Args:
            call_id: The call to cancel

        Returns:
            Result indicating whether cancellation succeeded
        """
        if call_id not in self._active_calls:
            return CancelResult(
                call_id=call_id,
                success=False,
                message="Call not found or already completed"
            )

        if call_id in self._cancel_events:
            self._cancel_events[call_id].set()
            return CancelResult(
                call_id=call_id,
                success=True,
                message="Cancellation requested"
            )

        return CancelResult(
            call_id=call_id,
            success=False,
            message="Unable to cancel"
        )

    def _check_cancelled(self, call_id: str) -> bool:
        """Check if a call has been cancelled."""
        if call_id in self._cancel_events:
            return self._cancel_events[call_id].is_set()
        return False

    def _file_search_stream(self, call: ToolCall) -> Generator[ToolFrame, None, None]:
        """Simulate file search with streaming results."""
        pattern = call.args.get("pattern", "*")
        directory = call.args.get("directory", "/")

        # Simulate finding files
        files = [
            f"{directory}/file1.py",
            f"{directory}/file2.py",
            f"{directory}/subdir/file3.py",
            f"{directory}/subdir/file4.py",
            f"{directory}/subdir/deep/file5.py",
        ]

        for i, file_path in enumerate(files):
            if self._check_cancelled(call.call_id):
                yield ToolFrame(
                    call_id=call.call_id,
                    frame_type=FrameType.CANCELLED,
                    sequence=i,
                    data={"message": "Search cancelled by user", "files_found": i}
                )
                return

            # Progress update
            yield ToolFrame(
                call_id=call.call_id,
                frame_type=FrameType.PROGRESS,
                sequence=i * 2,
                data={
                    "percentage": int((i + 1) / len(files) * 100),
                    "status": f"Searching... found {i + 1} files"
                }
            )

            # Output frame with found file
            yield ToolFrame(
                call_id=call.call_id,
                frame_type=FrameType.OUTPUT,
                sequence=i * 2 + 1,
                data={"file": file_path, "matches_pattern": pattern in file_path or pattern == "*"}
            )

            time.sleep(0.1)  # Simulate search time

        # Final result
        yield ToolFrame(
            call_id=call.call_id,
            frame_type=FrameType.RESULT,
            sequence=len(files) * 2,
            data={
                "total_files": len(files),
                "pattern": pattern,
                "directory": directory
            }
        )

    def _code_analysis_stream(self, call: ToolCall) -> Generator[ToolFrame, None, None]:
        """Simulate code analysis with streaming output."""
        code = call.args.get("code", "")

        analysis_steps = [
            ("syntax", "Checking syntax..."),
            ("imports", "Analyzing imports..."),
            ("types", "Checking type hints..."),
            ("complexity", "Computing complexity..."),
            ("security", "Scanning for vulnerabilities..."),
        ]

        results = {}

        for i, (step_name, status) in enumerate(analysis_steps):
            if self._check_cancelled(call.call_id):
                yield ToolFrame(
                    call_id=call.call_id,
                    frame_type=FrameType.CANCELLED,
                    sequence=i * 2,
                    data={"message": "Analysis cancelled", "completed_steps": list(results.keys())}
                )
                return

            # Progress
            yield ToolFrame(
                call_id=call.call_id,
                frame_type=FrameType.PROGRESS,
                sequence=i * 2,
                data={
                    "percentage": int((i + 1) / len(analysis_steps) * 100),
                    "status": status,
                    "current_step": step_name
                }
            )

            time.sleep(0.15)  # Simulate analysis time

            # Step result
            step_result = {
                "syntax": {"valid": True, "errors": []},
                "imports": {"count": 3, "external": ["json", "typing"]},
                "types": {"coverage": 0.85, "missing": ["return type on line 5"]},
                "complexity": {"cyclomatic": 4, "cognitive": 3},
                "security": {"issues": 0, "warnings": 1},
            }

            results[step_name] = step_result[step_name]

            yield ToolFrame(
                call_id=call.call_id,
                frame_type=FrameType.OUTPUT,
                sequence=i * 2 + 1,
                data={"step": step_name, "result": step_result[step_name]}
            )

        # Final result
        yield ToolFrame(
            call_id=call.call_id,
            frame_type=FrameType.RESULT,
            sequence=len(analysis_steps) * 2,
            data={
                "summary": "Analysis complete",
                "overall_score": 8.5,
                "results": results
            }
        )

    def _long_computation_stream(self, call: ToolCall) -> Generator[ToolFrame, None, None]:
        """Simulate a long-running computation that can be cancelled."""
        iterations = call.args.get("iterations", 10)

        accumulated = 0

        for i in range(iterations):
            if self._check_cancelled(call.call_id):
                yield ToolFrame(
                    call_id=call.call_id,
                    frame_type=FrameType.CANCELLED,
                    sequence=i,
                    data={
                        "message": "Computation cancelled",
                        "completed_iterations": i,
                        "partial_result": accumulated
                    }
                )
                return

            # Simulate computation
            time.sleep(0.2)
            accumulated += i * i

            yield ToolFrame(
                call_id=call.call_id,
                frame_type=FrameType.PROGRESS,
                sequence=i,
                data={
                    "percentage": int((i + 1) / iterations * 100),
                    "status": f"Computing iteration {i + 1}/{iterations}",
                    "intermediate_result": accumulated
                }
            )

        yield ToolFrame(
            call_id=call.call_id,
            frame_type=FrameType.RESULT,
            sequence=iterations,
            data={
                "final_result": accumulated,
                "iterations_completed": iterations
            }
        )


# ---------------------------------------------------------------------------
# Mock Tool Client (mirrors real ToolClient API)
# ---------------------------------------------------------------------------

class MockToolClient:
    """Mock ToolClient for demonstration.

    This mirrors the API of the real sw4rm.clients.tool.ToolClient.
    """

    def __init__(self, provider: MockToolProvider):
        """Initialize with a tool provider.

        Args:
            provider: The tool provider to use
        """
        self._provider = provider

    def call_stream(self, call: dict) -> Generator[ToolFrame, None, None]:
        """Execute a streaming tool call.

        Args:
            call: Dictionary with ToolCall fields

        Yields:
            ToolFrame objects
        """
        tool_call = ToolCall(
            call_id=call.get("call_id", str(uuid.uuid4())),
            tool_name=call["tool_name"],
            provider_id=call.get("provider_id", "default"),
            args=call.get("args", {}),
            worktree_id=call.get("worktree_id"),
            timeout_ms=call.get("timeout_ms", 30000)
        )
        return self._provider.call_stream(tool_call)

    def cancel(self, call: dict) -> CancelResult:
        """Cancel a tool call.

        Args:
            call: Dictionary with at minimum call_id

        Returns:
            CancelResult
        """
        return self._provider.cancel(call["call_id"])


# ---------------------------------------------------------------------------
# Streaming Handler Utilities
# ---------------------------------------------------------------------------

class StreamingToolHandler:
    """Helper for handling streaming tool responses.

    Provides utilities for processing frames, aggregating results,
    and handling cancellation.
    """

    def __init__(
        self,
        on_progress: Optional[Callable[[dict], None]] = None,
        on_output: Optional[Callable[[dict], None]] = None,
        on_error: Optional[Callable[[dict], None]] = None
    ):
        """Initialize the handler with callbacks.

        Args:
            on_progress: Called for each PROGRESS frame
            on_output: Called for each OUTPUT frame
            on_error: Called for ERROR frames
        """
        self.on_progress = on_progress
        self.on_output = on_output
        self.on_error = on_error
        self.outputs: list[dict] = []
        self.last_progress: Optional[dict] = None
        self.result: Optional[dict] = None
        self.cancelled = False

    def process_stream(self, frames: Generator[ToolFrame, None, None]) -> Optional[dict]:
        """Process all frames from a stream.

        Args:
            frames: Generator of ToolFrame objects

        Returns:
            The final result data, or None if cancelled/error
        """
        for frame in frames:
            self._handle_frame(frame)

            if frame.frame_type in (FrameType.RESULT, FrameType.ERROR, FrameType.CANCELLED):
                break

        return self.result

    def _handle_frame(self, frame: ToolFrame) -> None:
        """Handle a single frame."""
        if frame.frame_type == FrameType.PROGRESS:
            self.last_progress = frame.data
            if self.on_progress:
                self.on_progress(frame.data)

        elif frame.frame_type == FrameType.OUTPUT:
            self.outputs.append(frame.data)
            if self.on_output:
                self.on_output(frame.data)

        elif frame.frame_type == FrameType.RESULT:
            self.result = frame.data

        elif frame.frame_type == FrameType.ERROR:
            if self.on_error:
                self.on_error(frame.data)

        elif frame.frame_type == FrameType.CANCELLED:
            self.cancelled = True
            self.result = frame.data


# ---------------------------------------------------------------------------
# Example Scenarios
# ---------------------------------------------------------------------------

def demo_file_search():
    """Demonstrate streaming file search with progress updates."""
    print("\n" + "=" * 60)
    print("SCENARIO 1: Streaming File Search")
    print("=" * 60)

    provider = MockToolProvider()
    client = MockToolClient(provider)

    call_id = str(uuid.uuid4())

    def on_progress(data):
        print(f"  Progress: {data['percentage']}% - {data['status']}")

    def on_output(data):
        if data.get("matches_pattern"):
            print(f"  Found: {data['file']}")

    handler = StreamingToolHandler(on_progress=on_progress, on_output=on_output)

    print("\nExecuting file search...")
    frames = client.call_stream({
        "call_id": call_id,
        "tool_name": "file_search",
        "provider_id": "filesystem-provider",
        "args": {
            "pattern": "*.py",
            "directory": "/project"
        }
    })

    result = handler.process_stream(frames)

    print(f"\nSearch complete!")
    print(f"  Total files found: {result['total_files']}")
    print(f"  Pattern: {result['pattern']}")


def demo_code_analysis():
    """Demonstrate streaming code analysis with step-by-step output."""
    print("\n" + "=" * 60)
    print("SCENARIO 2: Streaming Code Analysis")
    print("=" * 60)

    provider = MockToolProvider()
    client = MockToolClient(provider)

    code_sample = '''
def calculate_total(items):
    total = 0
    for item in items:
        total += item.price * item.quantity
    return total
'''

    print(f"\nAnalyzing code:\n{code_sample}")

    def on_progress(data):
        print(f"  [{data['percentage']:3d}%] {data['status']}")

    def on_output(data):
        step = data['step']
        result = data['result']
        print(f"         {step}: {json.dumps(result)}")

    handler = StreamingToolHandler(on_progress=on_progress, on_output=on_output)

    frames = client.call_stream({
        "call_id": str(uuid.uuid4()),
        "tool_name": "code_analysis",
        "provider_id": "analyzer-provider",
        "args": {"code": code_sample}
    })

    result = handler.process_stream(frames)

    print(f"\nAnalysis complete!")
    print(f"  Overall score: {result['overall_score']}/10")


def demo_cancellation():
    """Demonstrate cancelling a long-running tool call."""
    print("\n" + "=" * 60)
    print("SCENARIO 3: Cancellation Handling")
    print("=" * 60)

    provider = MockToolProvider()
    client = MockToolClient(provider)

    call_id = str(uuid.uuid4())

    def on_progress(data):
        print(f"  Progress: {data['percentage']}% - {data['status']}")

    handler = StreamingToolHandler(on_progress=on_progress)

    # Start long computation in background
    frames_gen = client.call_stream({
        "call_id": call_id,
        "tool_name": "long_computation",
        "provider_id": "compute-provider",
        "args": {"iterations": 20}
    })

    print("\nStarting long computation (will cancel after 3 iterations)...")

    frames_received = 0
    for frame in frames_gen:
        handler._handle_frame(frame)
        frames_received += 1

        # Cancel after receiving a few frames
        if frames_received >= 3:
            print("\n  Requesting cancellation...")
            cancel_result = client.cancel({"call_id": call_id})
            print(f"  Cancel result: {cancel_result.message}")

        if frame.frame_type in (FrameType.RESULT, FrameType.ERROR, FrameType.CANCELLED):
            break

    if handler.cancelled:
        print(f"\nComputation was cancelled!")
        print(f"  Completed iterations: {handler.result.get('completed_iterations', 0)}")
        print(f"  Partial result: {handler.result.get('partial_result', 'N/A')}")


def demo_error_handling():
    """Demonstrate error handling for unknown tools."""
    print("\n" + "=" * 60)
    print("SCENARIO 4: Error Handling")
    print("=" * 60)

    provider = MockToolProvider()
    client = MockToolClient(provider)

    def on_error(data):
        print(f"  ERROR: {data['error']}")

    handler = StreamingToolHandler(on_error=on_error)

    print("\nCalling unknown tool...")
    frames = client.call_stream({
        "call_id": str(uuid.uuid4()),
        "tool_name": "nonexistent_tool",
        "provider_id": "unknown-provider",
        "args": {}
    })

    result = handler.process_stream(frames)
    print(f"  Result: {result}")


def demo_real_api_usage():
    """Show how to use the real ToolClient API (requires running service)."""
    print("\n" + "=" * 60)
    print("REAL API USAGE (Reference Only)")
    print("=" * 60)

    print("""
To use the real ToolClient with a running Tool service:

    import grpc
    from sw4rm.clients.tool import ToolClient

    # Connect to tool service
    channel = grpc.insecure_channel("localhost:50054")
    client = ToolClient(channel)

    # Execute streaming tool call
    call_id = str(uuid.uuid4())
    for frame in client.call_stream({
        "call_id": call_id,
        "tool_name": "file_search",
        "provider_id": "fs-provider",
        "args": {"pattern": "*.py", "directory": "/src"}
    }):
        frame_type = frame.frame_type  # FrameType enum from proto
        data = frame.data              # Frame payload

        if frame_type == 1:  # PROGRESS
            print(f"Progress: {frame.progress_pct}%")
        elif frame_type == 2:  # OUTPUT
            print(f"Output: {frame.output_chunk}")
        elif frame_type == 3:  # RESULT
            print(f"Done: {frame.result}")
            break

    # Cancel if needed
    client.cancel({"call_id": call_id})
""")


def main() -> int:
    """Run all streaming tool examples."""
    print("\nSW4RM Tool Streaming Example")
    print("=" * 60)
    print("This demonstrates streaming tool calls with progress and cancellation\n")

    # Run demo scenarios
    demo_file_search()
    demo_code_analysis()
    demo_cancellation()
    demo_error_handling()
    demo_real_api_usage()

    print("\n" + "=" * 60)
    print("ALL STREAMING SCENARIOS COMPLETED")
    print("=" * 60)
    print("\nKey takeaways:")
    print("1. Use call_stream() for tools that produce incremental output")
    print("2. Frame types: PROGRESS, OUTPUT, RESULT, ERROR, CANCELLED")
    print("3. Register callbacks for on_progress and on_output events")
    print("4. Use cancel() to abort long-running operations")
    print("5. Check for CANCELLED frame type in your stream handler")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
