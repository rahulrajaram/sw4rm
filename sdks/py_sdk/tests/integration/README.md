# SW4RM Protocol SDK - Integration Tests

This directory contains integration tests for the SW4RM Protocol Python SDK. These tests verify that multiple components work correctly together and simulate real-world usage scenarios.

## Overview

Integration tests differ from unit tests in that they:
- Test multiple components working together
- Simulate complete workflows (e.g., agent lifecycle, negotiation flows)
- Use mock gRPC servers to test client-server interactions
- Verify end-to-end behavior without requiring a real deployment

## Test Organization

### Test Files

- **`conftest.py`**: Pytest fixtures and configuration
  - Mock gRPC server setup
  - Client fixtures (SchedulerClient, WorktreeClient, etc.)
  - Skip markers for conditional test execution
  - Test environment helpers

- **`test_client_integration.py`**: Client integration tests
  - SchedulerClient with mock server
  - WorktreeClient with mock server
  - ToolClient with mock server
  - NegotiationClient with mock server
  - ActivityClient with mock server
  - Cross-client integration scenarios

- **`test_full_workflow.py`**: Complete workflow tests
  - Agent lifecycle: INITIALIZING → RUNNABLE → SCHEDULED → RUNNING → COMPLETED
  - Task submission and completion
  - Preemption flows
  - Activity buffer operations

- **`test_negotiation_flow.py`**: Multi-agent negotiation tests
  - Negotiation setup with multiple agents
  - Proposal → vote → decision flow
  - Negotiation timeout handling
  - HITL escalation triggers
  - Complex negotiation scenarios

## Running Integration Tests

### Run All Integration Tests

```bash
# From the repository root
pytest tests/integration/

# With verbose output
pytest tests/integration/ -v

# With coverage
pytest tests/integration/ --cov=sw4rm --cov-report=html
```

### Run Specific Test Files

```bash
# Run only client integration tests
pytest tests/integration/test_client_integration.py

# Run only workflow tests
pytest tests/integration/test_full_workflow.py

# Run only negotiation flow tests
pytest tests/integration/test_negotiation_flow.py
```

### Run Specific Test Classes or Methods

```bash
# Run a specific test class
pytest tests/integration/test_full_workflow.py::TestAgentLifecycle

# Run a specific test method
pytest tests/integration/test_client_integration.py::TestSchedulerClientIntegration::test_submit_task_integration

# Run tests matching a pattern
pytest tests/integration/ -k "preemption"
```

## Mock Server vs Real Server

### Default: Mock Server Mode

By default, all integration tests run with **mock gRPC servers**. This means:
- No real SW4RM Protocol server is required
- Tests use `unittest.mock.MagicMock` to simulate server responses
- Tests are fast and isolated
- Tests can run in CI/CD environments

### Optional: Real Server Mode

To run tests against a **real gRPC server** (when available):

```bash
# Set environment variable to enable real server tests
export SW4RM_INTEGRATION_SERVER=true

# Optionally configure server connection
export SW4RM_SERVER_HOST=localhost
export SW4RM_SERVER_PORT=50051

# Run tests
pytest tests/integration/
```

Tests marked with `@pytest.mark.requires_server` will only run when `SW4RM_INTEGRATION_SERVER=true`.

## Environment Variables

### Required (for real server tests)

- `SW4RM_INTEGRATION_SERVER`: Set to `true` to enable real server tests
  - Default: Not set (mock mode)
  - Example: `export SW4RM_INTEGRATION_SERVER=true`

### Optional (for real server tests)

- `SW4RM_SERVER_HOST`: Server hostname
  - Default: `localhost`
  - Example: `export SW4RM_SERVER_HOST=server.example.com`

- `SW4RM_SERVER_PORT`: Server port
  - Default: `50051`
  - Example: `export SW4RM_SERVER_PORT=9090`

- `SW4RM_SERVER_TIMEOUT`: Request timeout in seconds
  - Default: `30`
  - Example: `export SW4RM_SERVER_TIMEOUT=60`

## Protobuf Stubs

Some tests require generated protobuf stubs. If you get errors about missing protobuf modules:

```bash
# Generate protobuf stubs
make protos

# Or manually with protoc
protoc --python_out=. --grpc_python_out=. protos/*.proto
```

Tests marked with `@pytest.mark.requires_protos` will be skipped if protobuf stubs are not available.

## Test Fixtures

### Client Fixtures

Available client fixtures with mock stubs:

```python
def test_example(scheduler_client, worktree_client, tool_client):
    """Example test using client fixtures."""
    # All clients are pre-configured with mock stubs
    response = scheduler_client.submit_task("agent-1", "task-123")
    assert response.acknowledged
```

Available fixtures:
- `scheduler_client`: SchedulerClient with mock stub
- `worktree_client`: WorktreeClient with mock stub
- `tool_client`: ToolClient with mock stub
- `negotiation_client`: NegotiationClient with mock stub
- `activity_client`: ActivityClient with mock stub

### Mock Stub Fixtures

Low-level stub fixtures for custom configuration:

```python
def test_custom_response(scheduler_client, mock_scheduler_stub):
    """Example test with custom mock response."""
    # Configure custom response
    custom_response = MagicMock()
    custom_response.acknowledged = True
    custom_response.custom_field = "custom_value"
    mock_scheduler_stub.SubmitTask.return_value = custom_response

    # Use client
    response = scheduler_client.submit_task("agent-1", "task-123")
    assert response.custom_field == "custom_value"
```

Available stub fixtures:
- `mock_scheduler_stub`: Mock SchedulerService stub
- `mock_worktree_stub`: Mock WorktreeService stub
- `mock_tool_stub`: Mock ToolService stub
- `mock_negotiation_stub`: Mock NegotiationService stub
- `mock_activity_stub`: Mock ActivityService stub

### Helper Fixtures

- `mock_grpc_channel`: Mock gRPC channel
- `mock_server_config`: Server configuration dictionary
- `agent_states`: Track agent states in workflow tests
- `task_registry`: Track submitted tasks in workflow tests

## Writing Integration Tests

### Basic Integration Test

```python
def test_task_workflow(scheduler_client, mock_scheduler_stub):
    """Test complete task workflow."""
    # Arrange - configure mock responses
    submit_response = MagicMock()
    submit_response.acknowledged = True
    mock_scheduler_stub.SubmitTask.return_value = submit_response

    poll_response = MagicMock()
    entry = MagicMock()
    entry.task_id = "task-123"
    entry.state = "COMPLETED"
    poll_response.entries = [entry]
    mock_scheduler_stub.PollActivityBuffer.return_value = poll_response

    # Act - execute workflow
    submit_resp = scheduler_client.submit_task("agent-1", "task-123")
    poll_resp = scheduler_client.poll_activity_buffer("agent-1")

    # Assert - verify behavior
    assert submit_resp.acknowledged
    assert poll_resp.entries[0].state == "COMPLETED"
```

### Multi-Client Integration Test

```python
def test_multi_client_workflow(
    scheduler_client, worktree_client,
    mock_scheduler_stub, mock_worktree_stub
):
    """Test workflow using multiple clients."""
    # Configure mocks
    bind_response = MagicMock()
    bind_response.acknowledged = True
    mock_worktree_stub.Bind.return_value = bind_response

    submit_response = MagicMock()
    submit_response.acknowledged = True
    mock_scheduler_stub.SubmitTask.return_value = submit_response

    # Execute workflow
    bind_resp = worktree_client.bind("agent-1", "repo-1", "worktree-1")
    submit_resp = scheduler_client.submit_task("agent-1", "task-123")

    # Verify
    assert bind_resp.acknowledged
    assert submit_resp.acknowledged
```

### Error Handling Tests

```python
import grpc
import pytest

def test_error_handling(scheduler_client, mock_scheduler_stub):
    """Test client handles gRPC errors."""
    # Configure mock to raise error
    mock_scheduler_stub.SubmitTask.side_effect = grpc.RpcError()

    # Verify error is raised
    with pytest.raises(grpc.RpcError):
        scheduler_client.submit_task("agent-1", "task-123")
```

## Continuous Integration

Integration tests are designed to run in CI/CD environments:

### GitHub Actions Example

```yaml
name: Integration Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          pip install -e .
          pip install pytest pytest-cov

      - name: Run integration tests
        run: pytest tests/integration/ -v --cov=sw4rm
```

### GitLab CI Example

```yaml
integration-tests:
  stage: test
  image: python:3.11
  script:
    - pip install -e .
    - pip install pytest pytest-cov
    - pytest tests/integration/ -v --cov=sw4rm
  coverage: '/TOTAL.*\s+(\d+%)$/'
```

## Test Coverage

Check integration test coverage:

```bash
# Run with coverage report
pytest tests/integration/ --cov=sw4rm --cov-report=term-missing

# Generate HTML coverage report
pytest tests/integration/ --cov=sw4rm --cov-report=html
open htmlcov/index.html
```

## Debugging Integration Tests

### Verbose Output

```bash
# Show test names and PASS/FAIL
pytest tests/integration/ -v

# Show even more detail (test output, etc.)
pytest tests/integration/ -vv

# Show print statements
pytest tests/integration/ -s
```

### Run Specific Tests

```bash
# Run only failed tests from last run
pytest tests/integration/ --lf

# Run failed tests first, then rest
pytest tests/integration/ --ff

# Stop on first failure
pytest tests/integration/ -x
```

### Debug with pdb

```python
def test_debug_example(scheduler_client):
    """Example test with debugger."""
    import pdb; pdb.set_trace()  # Breakpoint
    response = scheduler_client.submit_task("agent-1", "task-123")
    assert response.acknowledged
```

Or use pytest's built-in debugger:

```bash
# Drop into pdb on failure
pytest tests/integration/ --pdb

# Drop into pdb on first failure
pytest tests/integration/ -x --pdb
```

## Common Issues

### Issue: Protobuf stubs not found

**Error:** `ModuleNotFoundError: No module named 'sw4rm.protos.scheduler_pb2'`

**Solution:**
```bash
make protos
# Or
python -m grpc_tools.protoc --python_out=. --grpc_python_out=. protos/*.proto
```

### Issue: Import errors

**Error:** `ImportError: cannot import name 'SchedulerClient'`

**Solution:**
```bash
# Install package in development mode
pip install -e .

# Or add to PYTHONPATH
export PYTHONPATH="${PYTHONPATH}:$(pwd)"
```

### Issue: Tests hang or timeout

**Cause:** Attempting to connect to real server when not available

**Solution:**
```bash
# Ensure mock mode (do not set SW4RM_INTEGRATION_SERVER)
unset SW4RM_INTEGRATION_SERVER

# Run tests
pytest tests/integration/
```

## Best Practices

1. **Use Fixtures**: Leverage pytest fixtures for common setup
2. **Mock External Dependencies**: Use mocks for gRPC stubs
3. **Test Workflows**: Focus on complete user workflows
4. **Clear Assertions**: Use descriptive assertions with helpful messages
5. **Isolate Tests**: Each test should be independent
6. **Document Tests**: Add docstrings explaining the workflow
7. **Handle Errors**: Test both success and error paths
8. **Keep Tests Fast**: Integration tests should complete quickly

## Contributing

When adding new integration tests:

1. Follow existing test patterns and structure
2. Add tests to appropriate test file or create new file
3. Use existing fixtures when possible
4. Add new fixtures to `conftest.py` if needed
5. Update this README if adding new test categories
6. Ensure tests pass in mock mode (no real server required)
7. Add appropriate skip markers if tests require special setup

## Additional Resources

- [Pytest Documentation](https://docs.pytest.org/)
- [unittest.mock Documentation](https://docs.python.org/3/library/unittest.mock.html)
- [gRPC Python Documentation](https://grpc.io/docs/languages/python/)
- [SW4RM Protocol Specification](../../docs/)

## Support

For questions or issues with integration tests:
- Check this README
- Review existing test examples
- Check the main project documentation
- Open an issue on the project repository
