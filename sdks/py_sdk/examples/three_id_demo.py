#!/usr/bin/env python3
"""Demo: Three-ID Envelope Model

Demonstrates the three distinct identifiers in the SW4RM envelope model:
1. message_id - per-attempt identifier (changes on retry)
2. correlation_id - workflow/session identifier (stable across related messages)
3. idempotency_token - operation identifier (stable across retries for deduplication)
"""

from sw4rm import constants as C
from sw4rm.envelope import (
    build_envelope,
    update_envelope_state,
    is_terminal_state,
    compute_deterministic_hash,
    make_idempotency_token,
)
from sw4rm.activity_buffer import ActivityBuffer


def demo_basic_envelope_lifecycle():
    """Show envelope state lifecycle."""
    print("\n=== Envelope State Lifecycle ===")

    env = build_envelope(
        producer_id="agent-writer",
        message_type=C.TOOL_CALL,
        payload=b'{"tool": "file_write", "path": "/tmp/test.txt"}'
    )

    print(f"1. Created envelope: message_id={env['message_id'][:8]}...")
    print(f"   Initial state: {env['state']} (CREATED)")
    print(f"   Terminal? {is_terminal_state(env['state'])}")

    update_envelope_state(env, C.PENDING)
    print(f"\n2. Sent to router: state={env['state']} (PENDING)")
    print(f"   Terminal? {is_terminal_state(env['state'])}")

    update_envelope_state(env, C.RUNNING_ENVELOPE)
    print(f"\n3. Agent processing: state={env['state']} (RUNNING)")
    print(f"   Terminal? {is_terminal_state(env['state'])}")

    update_envelope_state(env, C.FULFILLED_ENVELOPE)
    print(f"\n4. Completed: state={env['state']} (FULFILLED)")
    print(f"   Terminal? {is_terminal_state(env['state'])}")


def demo_three_id_semantics():
    """Demonstrate the three-ID model."""
    print("\n\n=== Three-ID Model ===")

    # Define operation parameters (what makes this operation unique)
    operation_params = {
        "tool": "git_commit",
        "repo": "myproject",
        "files": ["main.py", "tests.py"],
        "message": "Fix bug #123"
    }

    # Generate stable idempotency token
    op_hash = compute_deterministic_hash(operation_params)
    idem_token = make_idempotency_token("agent-dev", "git_commit", op_hash)

    print(f"Operation: {operation_params}")
    print(f"Idempotency token: {idem_token}")

    # First attempt
    workflow_id = "feature-branch-work-123"
    env1 = build_envelope(
        producer_id="agent-dev",
        message_type=C.TOOL_CALL,
        correlation_id=workflow_id,
        idempotency_token=idem_token,
        retry_count=0
    )

    print(f"\nAttempt 1:")
    print(f"  message_id: {env1['message_id'][:16]}... (unique per attempt)")
    print(f"  correlation_id: {env1['correlation_id']} (workflow scope)")
    print(f"  idempotency_token: {env1['idempotency_token']} (operation scope)")
    print(f"  retry_count: {env1['retry_count']}")

    # Simulate retry (e.g., timeout)
    env2 = build_envelope(
        producer_id="agent-dev",
        message_type=C.TOOL_CALL,
        correlation_id=workflow_id,  # SAME - same workflow
        idempotency_token=idem_token,  # SAME - same operation
        retry_count=1  # INCREMENTED
    )

    print(f"\nAttempt 2 (retry):")
    print(f"  message_id: {env2['message_id'][:16]}... (NEW - different attempt)")
    print(f"  correlation_id: {env2['correlation_id']} (SAME - same workflow)")
    print(f"  idempotency_token: {env2['idempotency_token']} (SAME - same operation)")
    print(f"  retry_count: {env2['retry_count']}")

    print(f"\nComparison:")
    print(f"  message_id changed? {env1['message_id'] != env2['message_id']}")
    print(f"  correlation_id stable? {env1['correlation_id'] == env2['correlation_id']}")
    print(f"  idempotency_token stable? {env1['idempotency_token'] == env2['idempotency_token']}")


def demo_deduplication():
    """Demonstrate deduplication using idempotency tokens."""
    print("\n\n=== Deduplication via Idempotency Tokens ===")

    buffer = ActivityBuffer(max_items=100, dedup_window_s=3600)

    # Operation parameters
    op_params = {
        "action": "deploy",
        "service": "api-gateway",
        "version": "2.1.0"
    }

    # Generate idempotency token
    op_hash = compute_deterministic_hash(op_params)
    token = make_idempotency_token("agent-deployer", "deploy", op_hash)

    print(f"Deploy operation: {op_params}")
    print(f"Token: {token}")

    # First request arrives
    env1 = build_envelope(
        producer_id="agent-deployer",
        message_type=C.DATA,
        idempotency_token=token,
        state=C.RUNNING_ENVELOPE
    )
    rec1 = buffer.record_incoming(env1)
    print(f"\nRequest 1 received: message_id={rec1.message_id[:16]}...")
    print(f"  State: {rec1.state} (RUNNING)")

    # Duplicate request arrives (network retry, etc.)
    print("\nDuplicate request arrives (same idempotency token)...")
    existing = buffer.get_by_idempotency_token(token)

    if existing:
        print(f"  DUPLICATE DETECTED!")
        print(f"  Existing message_id: {existing.message_id[:16]}...")
        print(f"  Existing state: {existing.state}")

        if is_terminal_state(existing.state):
            print("  Operation already completed - return cached result")
        else:
            print("  Operation still in progress - reject duplicate")
    else:
        print("  No duplicate found - would process normally")

    # Mark first operation as complete
    buffer.update_state(rec1.message_id, C.FULFILLED_ENVELOPE)
    print(f"\nOperation completed: state updated to {C.FULFILLED_ENVELOPE}")

    # Another duplicate check
    existing = buffer.get_by_idempotency_token(token)
    if existing:
        print(f"\nLate duplicate arrives...")
        print(f"  Found completed operation: state={existing.state}")
        if is_terminal_state(existing.state):
            print("  Return cached result to duplicate request")


def demo_workflow_correlation():
    """Demonstrate workflow correlation via correlation_id."""
    print("\n\n=== Workflow Correlation ===")

    buffer = ActivityBuffer(max_items=100)
    workflow_id = "user-onboarding-456"

    print(f"Workflow: {workflow_id}")
    print("Steps:")

    # Step 1: Create user account
    env1 = build_envelope(
        producer_id="agent-auth",
        message_type=C.TOOL_CALL,
        correlation_id=workflow_id,
        payload=b'{"action": "create_user", "email": "user@example.com"}'
    )
    rec1 = buffer.record_incoming(env1)
    print(f"\n  1. Create user: message_id={rec1.message_id[:16]}...")
    print(f"     correlation_id: {rec1.correlation_id}")

    # Step 2: Send welcome email
    env2 = build_envelope(
        producer_id="agent-comms",
        message_type=C.TOOL_CALL,
        correlation_id=workflow_id,  # SAME workflow
        payload=b'{"action": "send_email", "template": "welcome"}'
    )
    rec2 = buffer.record_incoming(env2)
    print(f"\n  2. Send email: message_id={rec2.message_id[:16]}...")
    print(f"     correlation_id: {rec2.correlation_id}")

    # Step 3: Create initial data
    env3 = build_envelope(
        producer_id="agent-data",
        message_type=C.TOOL_CALL,
        correlation_id=workflow_id,  # SAME workflow
        payload=b'{"action": "init_workspace"}'
    )
    rec3 = buffer.record_incoming(env3)
    print(f"\n  3. Init workspace: message_id={rec3.message_id[:16]}...")
    print(f"     correlation_id: {rec3.correlation_id}")

    print(f"\nAll messages share correlation_id: {workflow_id}")
    print(f"Each has unique message_id for per-attempt tracking")


if __name__ == "__main__":
    print("=" * 60)
    print("SW4RM Three-ID Envelope Model Demo")
    print("=" * 60)

    demo_basic_envelope_lifecycle()
    demo_three_id_semantics()
    demo_deduplication()
    demo_workflow_correlation()

    print("\n" + "=" * 60)
    print("Demo complete!")
    print("=" * 60)
