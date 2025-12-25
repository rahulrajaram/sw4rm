"""Unit tests for content_types module."""
import pytest
import json
from sw4rm.content_types import (
    ContentTypeRegistry,
    get_default_registry,
    register_standard_types,
    INTENT_QUERY,
    INTENT_ACTION,
    SHARED_CONTEXT,
    SCHEDULER_SEED,
    SCHEDULER_COMMAND,
    AGENT_REPORT,
    NEGOTIATION_PROPOSAL,
    NEGOTIATION_VOTE,
    TOOL_CALL,
    TOOL_RESULT,
)
from sw4rm.shared_context import (
    SharedContext,
    SharedContextManager,
)


class TestContentTypeConstants:
    """Tests for content type constants."""

    def test_intent_query_constant(self):
        """Test INTENT_QUERY constant is properly defined."""
        assert INTENT_QUERY == "application/vnd.sw4rm.intent.query+json"

    def test_intent_action_constant(self):
        """Test INTENT_ACTION constant is properly defined."""
        assert INTENT_ACTION == "application/vnd.sw4rm.intent.action+json"

    def test_shared_context_constant(self):
        """Test SHARED_CONTEXT constant is properly defined."""
        assert SHARED_CONTEXT == "application/vnd.sw4rm.shared-context+json"

    def test_scheduler_seed_constant(self):
        """Test SCHEDULER_SEED constant matches spec."""
        assert SCHEDULER_SEED == "application/vnd.sw4rm.scheduler.seed+json;v=1"

    def test_scheduler_command_constant(self):
        """Test SCHEDULER_COMMAND constant matches spec."""
        assert SCHEDULER_COMMAND == "application/vnd.sw4rm.scheduler.command+json;v=1"

    def test_agent_report_constant(self):
        """Test AGENT_REPORT constant matches spec."""
        assert AGENT_REPORT == "application/vnd.sw4rm.agent.report+json;v=1"

    def test_negotiation_proposal_constant(self):
        """Test NEGOTIATION_PROPOSAL constant is properly defined."""
        assert NEGOTIATION_PROPOSAL == "application/vnd.sw4rm.negotiation.proposal+json"

    def test_negotiation_vote_constant(self):
        """Test NEGOTIATION_VOTE constant is properly defined."""
        assert NEGOTIATION_VOTE == "application/vnd.sw4rm.negotiation.vote+json"

    def test_tool_call_constant(self):
        """Test TOOL_CALL constant is properly defined."""
        assert TOOL_CALL == "application/vnd.sw4rm.tool.call+json"

    def test_tool_result_constant(self):
        """Test TOOL_RESULT constant is properly defined."""
        assert TOOL_RESULT == "application/vnd.sw4rm.tool.result+json"


class TestContentTypeRegistryConstruction:
    """Tests for ContentTypeRegistry constructor."""

    def test_constructor_creates_empty_registry(self):
        """Test that constructor creates an empty registry."""
        registry = ContentTypeRegistry()
        assert registry._schemas == {}

    def test_multiple_instances_are_independent(self):
        """Test that multiple registry instances are independent."""
        registry1 = ContentTypeRegistry()
        registry2 = ContentTypeRegistry()

        registry1.register("application/json", {"type": "object"})

        assert registry1.get_schema("application/json") is not None
        assert registry2.get_schema("application/json") is None


class TestContentTypeRegistryRegister:
    """Tests for ContentTypeRegistry.register method."""

    def test_register_with_schema(self):
        """Test registering a content type with a schema."""
        registry = ContentTypeRegistry()
        schema = {"type": "object", "properties": {"name": {"type": "string"}}}

        registry.register("application/json", schema)

        assert registry.get_schema("application/json") == schema

    def test_register_without_schema(self):
        """Test registering a content type without a schema."""
        registry = ContentTypeRegistry()

        registry.register("application/json")

        assert registry.get_schema("application/json") == {}

    def test_register_with_parameters_normalizes_to_base_type(self):
        """Test that registering with parameters stores under base type."""
        registry = ContentTypeRegistry()
        schema = {"type": "object"}

        registry.register("application/json;charset=utf-8", schema)

        # Should be retrievable by base type
        assert registry.get_schema("application/json") == schema

    def test_register_overwrites_existing_schema(self):
        """Test that re-registering a type overwrites the schema."""
        registry = ContentTypeRegistry()
        schema1 = {"type": "object"}
        schema2 = {"type": "array"}

        registry.register("application/json", schema1)
        registry.register("application/json", schema2)

        assert registry.get_schema("application/json") == schema2


class TestContentTypeRegistryGetSchema:
    """Tests for ContentTypeRegistry.get_schema method."""

    def test_get_schema_returns_registered_schema(self):
        """Test getting a registered schema."""
        registry = ContentTypeRegistry()
        schema = {"type": "object"}

        registry.register("application/json", schema)

        assert registry.get_schema("application/json") == schema

    def test_get_schema_returns_none_for_unregistered_type(self):
        """Test getting an unregistered schema returns None."""
        registry = ContentTypeRegistry()

        assert registry.get_schema("application/xml") is None

    def test_get_schema_with_parameters_normalizes_to_base_type(self):
        """Test that get_schema normalizes content type with parameters."""
        registry = ContentTypeRegistry()
        schema = {"type": "object"}

        registry.register("application/json", schema)

        # Should retrieve by content type with parameters
        assert registry.get_schema("application/json;charset=utf-8") == schema


class TestContentTypeRegistryValidate:
    """Tests for ContentTypeRegistry.validate method."""

    def test_validate_succeeds_with_matching_schema(self):
        """Test validation succeeds with valid payload."""
        registry = ContentTypeRegistry()
        schema = {
            "type": "object",
            "properties": {"name": {"type": "string"}},
            "required": ["name"],
        }

        registry.register("application/json", schema)
        payload = json.dumps({"name": "Alice"}).encode("utf-8")

        assert registry.validate("application/json", payload) is True

    def test_validate_fails_with_missing_required_field(self):
        """Test validation fails when required field is missing."""
        registry = ContentTypeRegistry()
        schema = {
            "type": "object",
            "properties": {"name": {"type": "string"}},
            "required": ["name"],
        }

        registry.register("application/json", schema)
        payload = json.dumps({"age": 30}).encode("utf-8")

        assert registry.validate("application/json", payload) is False

    def test_validate_fails_with_wrong_type(self):
        """Test validation fails with wrong data type."""
        registry = ContentTypeRegistry()
        schema = {"type": "object"}

        registry.register("application/json", schema)
        payload = json.dumps([1, 2, 3]).encode("utf-8")  # Array instead of object

        assert registry.validate("application/json", payload) is False

    def test_validate_succeeds_with_no_schema_registered(self):
        """Test validation succeeds when no schema is registered (permissive)."""
        registry = ContentTypeRegistry()
        payload = json.dumps({"anything": "goes"}).encode("utf-8")

        assert registry.validate("application/unknown", payload) is True

    def test_validate_fails_with_invalid_json(self):
        """Test validation fails with invalid JSON."""
        registry = ContentTypeRegistry()
        schema = {"type": "object"}

        registry.register("application/json", schema)
        payload = b"not valid json"

        assert registry.validate("application/json", payload) is False

    def test_validate_with_nested_properties(self):
        """Test validation with nested object properties."""
        registry = ContentTypeRegistry()
        schema = {
            "type": "object",
            "properties": {
                "user": {
                    "type": "object",
                    "properties": {"name": {"type": "string"}},
                    "required": ["name"],
                }
            },
            "required": ["user"],
        }

        registry.register("application/json", schema)

        # Valid payload
        valid_payload = json.dumps({"user": {"name": "Alice"}}).encode("utf-8")
        assert registry.validate("application/json", valid_payload) is True

        # Invalid payload (missing nested required field)
        invalid_payload = json.dumps({"user": {"age": 30}}).encode("utf-8")
        assert registry.validate("application/json", invalid_payload) is False


class TestContentTypeRegistryParseContentType:
    """Tests for ContentTypeRegistry.parse_content_type method."""

    def test_parse_simple_content_type(self):
        """Test parsing a simple content type without parameters."""
        registry = ContentTypeRegistry()

        base_type, params = registry.parse_content_type("application/json")

        assert base_type == "application/json"
        assert params == {}

    def test_parse_content_type_with_single_parameter(self):
        """Test parsing content type with one parameter."""
        registry = ContentTypeRegistry()

        base_type, params = registry.parse_content_type("application/json;charset=utf-8")

        assert base_type == "application/json"
        assert params == {"charset": "utf-8"}

    def test_parse_content_type_with_multiple_parameters(self):
        """Test parsing content type with multiple parameters."""
        registry = ContentTypeRegistry()

        base_type, params = registry.parse_content_type(
            "application/json;charset=utf-8;boundary=xyz"
        )

        assert base_type == "application/json"
        assert params == {"charset": "utf-8", "boundary": "xyz"}

    def test_parse_content_type_with_version_parameter(self):
        """Test parsing SW4RM content type with version parameter."""
        registry = ContentTypeRegistry()

        base_type, params = registry.parse_content_type(
            "application/vnd.sw4rm.scheduler.seed+json;v=1"
        )

        assert base_type == "application/vnd.sw4rm.scheduler.seed+json"
        assert params == {"v": "1"}

    def test_parse_content_type_with_parameter_without_value(self):
        """Test parsing content type with flag parameter (no value)."""
        registry = ContentTypeRegistry()

        base_type, params = registry.parse_content_type("application/json;flag")

        assert base_type == "application/json"
        assert params == {"flag": ""}

    def test_parse_content_type_with_whitespace(self):
        """Test parsing handles whitespace around parameters."""
        registry = ContentTypeRegistry()

        base_type, params = registry.parse_content_type(
            "application/json ; charset = utf-8 ; v = 1"
        )

        assert base_type == "application/json"
        assert params == {"charset": "utf-8", "v": "1"}


class TestContentTypeRegistryGetIntent:
    """Tests for ContentTypeRegistry.get_intent method."""

    def test_get_intent_from_scheduler_seed(self):
        """Test extracting intent from scheduler.seed content type."""
        registry = ContentTypeRegistry()

        intent = registry.get_intent(SCHEDULER_SEED)

        assert intent == "scheduler.seed"

    def test_get_intent_from_scheduler_command(self):
        """Test extracting intent from scheduler.command content type."""
        registry = ContentTypeRegistry()

        intent = registry.get_intent(SCHEDULER_COMMAND)

        assert intent == "scheduler.command"

    def test_get_intent_from_agent_report(self):
        """Test extracting intent from agent.report content type."""
        registry = ContentTypeRegistry()

        intent = registry.get_intent(AGENT_REPORT)

        assert intent == "agent.report"

    def test_get_intent_from_negotiation_proposal(self):
        """Test extracting intent from negotiation.proposal content type."""
        registry = ContentTypeRegistry()

        intent = registry.get_intent(NEGOTIATION_PROPOSAL)

        assert intent == "negotiation.proposal"

    def test_get_intent_from_intent_query(self):
        """Test extracting intent from intent.query content type."""
        registry = ContentTypeRegistry()

        intent = registry.get_intent(INTENT_QUERY)

        assert intent == "intent.query"

    def test_get_intent_returns_none_for_non_sw4rm_type(self):
        """Test get_intent returns None for standard content types."""
        registry = ContentTypeRegistry()

        intent = registry.get_intent("application/json")

        assert intent is None

    def test_get_intent_returns_none_for_invalid_sw4rm_type(self):
        """Test get_intent returns None for malformed SW4RM types."""
        registry = ContentTypeRegistry()

        intent = registry.get_intent("application/vnd.sw4rm.invalid")

        assert intent is None


class TestGlobalDefaultRegistry:
    """Tests for global default registry functions."""

    def test_get_default_registry_returns_singleton(self):
        """Test that get_default_registry returns the same instance."""
        registry1 = get_default_registry()
        registry2 = get_default_registry()

        assert registry1 is registry2

    def test_register_standard_types_with_default_registry(self):
        """Test registering standard types with default registry."""
        registry = ContentTypeRegistry()
        register_standard_types(registry)

        # Verify some standard types are registered
        assert registry.get_schema(SCHEDULER_SEED) is not None
        assert registry.get_schema(SCHEDULER_COMMAND) is not None
        assert registry.get_schema(AGENT_REPORT) is not None

    def test_register_standard_types_without_argument_uses_default(self):
        """Test register_standard_types without argument uses global registry."""
        # This is a behavioral test - we can't easily verify it uses the global
        # registry without side effects, but we can ensure it doesn't crash
        register_standard_types()


class TestSchedulerSeedValidation:
    """Tests for validating scheduler.seed payloads."""

    def test_valid_scheduler_seed_payload(self):
        """Test validating a valid scheduler seed payload."""
        registry = ContentTypeRegistry()
        register_standard_types(registry)

        payload = json.dumps({"seed": "task-123"}).encode("utf-8")

        assert registry.validate(SCHEDULER_SEED, payload) is True

    def test_invalid_scheduler_seed_payload_missing_seed(self):
        """Test validation fails when seed field is missing."""
        registry = ContentTypeRegistry()
        register_standard_types(registry)

        payload = json.dumps({"task": "123"}).encode("utf-8")

        assert registry.validate(SCHEDULER_SEED, payload) is False


class TestSchedulerCommandValidation:
    """Tests for validating scheduler.command payloads."""

    def test_valid_scheduler_command_payload(self):
        """Test validating a valid scheduler command payload."""
        registry = ContentTypeRegistry()
        register_standard_types(registry)

        payload = json.dumps({
            "schema_version": 1,
            "to": "agent-1",
            "stage": "generate",
            "params": {"model": "gpt-4"},
        }).encode("utf-8")

        assert registry.validate(SCHEDULER_COMMAND, payload) is True

    def test_invalid_scheduler_command_missing_to(self):
        """Test validation fails when 'to' field is missing."""
        registry = ContentTypeRegistry()
        register_standard_types(registry)

        payload = json.dumps({
            "schema_version": 1,
            "stage": "generate",
            "params": {},
        }).encode("utf-8")

        assert registry.validate(SCHEDULER_COMMAND, payload) is False


class TestAgentReportValidation:
    """Tests for validating agent.report payloads."""

    def test_valid_agent_report_payload(self):
        """Test validating a valid agent report payload."""
        registry = ContentTypeRegistry()
        register_standard_types(registry)

        payload = json.dumps({
            "schema_version": 1,
            "stage": "generate",
            "status": "ok",
            "logs": "Generation completed successfully",
        }).encode("utf-8")

        assert registry.validate(AGENT_REPORT, payload) is True

    def test_invalid_agent_report_missing_status(self):
        """Test validation fails when status field is missing."""
        registry = ContentTypeRegistry()
        register_standard_types(registry)

        payload = json.dumps({
            "schema_version": 1,
            "stage": "generate",
        }).encode("utf-8")

        assert registry.validate(AGENT_REPORT, payload) is False


class TestNegotiationProposalValidation:
    """Tests for validating negotiation.proposal payloads."""

    def test_valid_negotiation_proposal_payload(self):
        """Test validating a valid negotiation proposal payload."""
        registry = ContentTypeRegistry()
        register_standard_types(registry)

        payload = json.dumps({
            "artifact_type": "requirements",
            "artifact_id": "req-123",
            "producer_id": "agent-producer",
            "artifact": {"requirements": ["feat-1", "feat-2"]},
            "requested_critics": ["critic-1", "critic-2"],
        }).encode("utf-8")

        assert registry.validate(NEGOTIATION_PROPOSAL, payload) is True

    def test_invalid_negotiation_proposal_missing_artifact(self):
        """Test validation fails when artifact field is missing."""
        registry = ContentTypeRegistry()
        register_standard_types(registry)

        payload = json.dumps({
            "artifact_type": "requirements",
            "artifact_id": "req-123",
            "producer_id": "agent-producer",
            "requested_critics": ["critic-1"],
        }).encode("utf-8")

        assert registry.validate(NEGOTIATION_PROPOSAL, payload) is False


class TestNegotiationVoteValidation:
    """Tests for validating negotiation.vote payloads."""

    def test_valid_negotiation_vote_payload(self):
        """Test validating a valid negotiation vote payload."""
        registry = ContentTypeRegistry()
        register_standard_types(registry)

        payload = json.dumps({
            "artifact_id": "req-123",
            "critic_id": "critic-1",
            "score": 8.5,
            "passed": True,
            "strengths": ["Well-defined", "Clear acceptance criteria"],
            "weaknesses": ["Missing edge cases"],
            "recommendations": ["Add error handling specs"],
        }).encode("utf-8")

        assert registry.validate(NEGOTIATION_VOTE, payload) is True

    def test_invalid_negotiation_vote_missing_score(self):
        """Test validation fails when score field is missing."""
        registry = ContentTypeRegistry()
        register_standard_types(registry)

        payload = json.dumps({
            "artifact_id": "req-123",
            "critic_id": "critic-1",
            "passed": True,
            "strengths": [],
            "weaknesses": [],
            "recommendations": [],
        }).encode("utf-8")

        assert registry.validate(NEGOTIATION_VOTE, payload) is False


class TestSharedContextConstruction:
    """Tests for SharedContext dataclass."""

    def test_shared_context_creation(self):
        """Test creating a SharedContext instance."""
        ctx = SharedContext(
            context_id="ctx-1",
            version="1",
            data={"key": "value"},
        )

        assert ctx.context_id == "ctx-1"
        assert ctx.version == "1"
        assert ctx.data == {"key": "value"}
        assert ctx.locked_by is None
        assert ctx.created_at is not None
        assert ctx.updated_at is not None

    def test_shared_context_to_dict(self):
        """Test converting SharedContext to dictionary."""
        ctx = SharedContext(
            context_id="ctx-1",
            version="1",
            data={"key": "value"},
        )

        result = ctx.to_dict()

        assert result["context_id"] == "ctx-1"
        assert result["version"] == "1"
        assert result["data"] == {"key": "value"}
        assert result["locked_by"] is None

    def test_shared_context_from_dict(self):
        """Test reconstructing SharedContext from dictionary."""
        data = {
            "context_id": "ctx-1",
            "version": "2",
            "data": {"key": "value"},
            "locked_by": "agent-1",
            "created_at": "2025-01-01T00:00:00",
            "updated_at": "2025-01-01T01:00:00",
        }

        ctx = SharedContext.from_dict(data)

        assert ctx.context_id == "ctx-1"
        assert ctx.version == "2"
        assert ctx.data == {"key": "value"}
        assert ctx.locked_by == "agent-1"


class TestSharedContextManagerCreate:
    """Tests for SharedContextManager.create method."""

    def test_create_new_context(self):
        """Test creating a new shared context."""
        manager = SharedContextManager()

        ctx = manager.create("ctx-1", {"step": 1})

        assert ctx.context_id == "ctx-1"
        assert ctx.version == "1"
        assert ctx.data == {"step": 1}
        assert ctx.locked_by is None

    def test_create_duplicate_context_raises_error(self):
        """Test creating a duplicate context raises ValueError."""
        manager = SharedContextManager()
        manager.create("ctx-1", {})

        with pytest.raises(ValueError, match="already exists"):
            manager.create("ctx-1", {})

    def test_create_makes_copy_of_data(self):
        """Test that create makes a copy of the data dict."""
        manager = SharedContextManager()
        original_data = {"key": "value"}

        ctx = manager.create("ctx-1", original_data)
        original_data["key"] = "modified"

        assert ctx.data["key"] == "value"  # Should not be affected


class TestSharedContextManagerGet:
    """Tests for SharedContextManager.get method."""

    def test_get_existing_context(self):
        """Test retrieving an existing context."""
        manager = SharedContextManager()
        manager.create("ctx-1", {"key": "value"})

        ctx = manager.get("ctx-1")

        assert ctx is not None
        assert ctx.context_id == "ctx-1"
        assert ctx.data == {"key": "value"}

    def test_get_nonexistent_context_returns_none(self):
        """Test retrieving a nonexistent context returns None."""
        manager = SharedContextManager()

        ctx = manager.get("nonexistent")

        assert ctx is None


class TestSharedContextManagerUpdate:
    """Tests for SharedContextManager.update method."""

    def test_update_with_correct_version(self):
        """Test updating a context with the correct version."""
        manager = SharedContextManager()
        manager.create("ctx-1", {"count": 0})

        ctx = manager.update("ctx-1", {"count": 1}, "1")

        assert ctx.version == "2"
        assert ctx.data == {"count": 1}

    def test_update_with_wrong_version_raises_error(self):
        """Test updating with wrong version raises ValueError."""
        manager = SharedContextManager()
        manager.create("ctx-1", {"count": 0})
        manager.update("ctx-1", {"count": 1}, "1")

        with pytest.raises(ValueError, match="Version conflict"):
            manager.update("ctx-1", {"count": 2}, "1")

    def test_update_nonexistent_context_raises_error(self):
        """Test updating a nonexistent context raises ValueError."""
        manager = SharedContextManager()

        with pytest.raises(ValueError, match="not found"):
            manager.update("nonexistent", {}, "1")

    def test_update_locked_context_raises_error(self):
        """Test updating a locked context raises ValueError."""
        manager = SharedContextManager()
        manager.create("ctx-1", {})
        manager.lock("ctx-1", "agent-1")

        with pytest.raises(ValueError, match="is locked"):
            manager.update("ctx-1", {}, "1")

    def test_update_increments_version_sequentially(self):
        """Test that updates increment version sequentially."""
        manager = SharedContextManager()
        manager.create("ctx-1", {})

        ctx = manager.update("ctx-1", {}, "1")
        assert ctx.version == "2"

        ctx = manager.update("ctx-1", {}, "2")
        assert ctx.version == "3"

        ctx = manager.update("ctx-1", {}, "3")
        assert ctx.version == "4"


class TestSharedContextManagerLock:
    """Tests for SharedContextManager.lock method."""

    def test_lock_unlocked_context(self):
        """Test acquiring a lock on an unlocked context."""
        manager = SharedContextManager()
        manager.create("ctx-1", {})

        success = manager.lock("ctx-1", "agent-1")

        assert success is True
        ctx = manager.get("ctx-1")
        assert ctx.locked_by == "agent-1"

    def test_lock_already_locked_by_same_agent(self):
        """Test locking a context already locked by same agent (idempotent)."""
        manager = SharedContextManager()
        manager.create("ctx-1", {})
        manager.lock("ctx-1", "agent-1")

        success = manager.lock("ctx-1", "agent-1")

        assert success is True

    def test_lock_already_locked_by_different_agent(self):
        """Test locking a context already locked by different agent fails."""
        manager = SharedContextManager()
        manager.create("ctx-1", {})
        manager.lock("ctx-1", "agent-1")

        success = manager.lock("ctx-1", "agent-2")

        assert success is False

    def test_lock_nonexistent_context_raises_error(self):
        """Test locking a nonexistent context raises ValueError."""
        manager = SharedContextManager()

        with pytest.raises(ValueError, match="not found"):
            manager.lock("nonexistent", "agent-1")


class TestSharedContextManagerUnlock:
    """Tests for SharedContextManager.unlock method."""

    def test_unlock_locked_context_by_owner(self):
        """Test unlocking a context by the agent that locked it."""
        manager = SharedContextManager()
        manager.create("ctx-1", {})
        manager.lock("ctx-1", "agent-1")

        success = manager.unlock("ctx-1", "agent-1")

        assert success is True
        ctx = manager.get("ctx-1")
        assert ctx.locked_by is None

    def test_unlock_locked_context_by_different_agent(self):
        """Test unlocking a context by a different agent fails."""
        manager = SharedContextManager()
        manager.create("ctx-1", {})
        manager.lock("ctx-1", "agent-1")

        success = manager.unlock("ctx-1", "agent-2")

        assert success is False
        ctx = manager.get("ctx-1")
        assert ctx.locked_by == "agent-1"  # Still locked

    def test_unlock_unlocked_context(self):
        """Test unlocking an already unlocked context returns False."""
        manager = SharedContextManager()
        manager.create("ctx-1", {})

        success = manager.unlock("ctx-1", "agent-1")

        assert success is False

    def test_unlock_nonexistent_context_raises_error(self):
        """Test unlocking a nonexistent context raises ValueError."""
        manager = SharedContextManager()

        with pytest.raises(ValueError, match="not found"):
            manager.unlock("nonexistent", "agent-1")


class TestSharedContextManagerDelete:
    """Tests for SharedContextManager.delete method."""

    def test_delete_existing_context(self):
        """Test deleting an existing context."""
        manager = SharedContextManager()
        manager.create("ctx-1", {})

        success = manager.delete("ctx-1")

        assert success is True
        assert manager.get("ctx-1") is None

    def test_delete_nonexistent_context(self):
        """Test deleting a nonexistent context returns False."""
        manager = SharedContextManager()

        success = manager.delete("nonexistent")

        assert success is False


class TestSharedContextManagerListContexts:
    """Tests for SharedContextManager.list_contexts method."""

    def test_list_contexts_empty(self):
        """Test listing contexts when manager is empty."""
        manager = SharedContextManager()

        contexts = manager.list_contexts()

        assert contexts == []

    def test_list_contexts_multiple(self):
        """Test listing multiple contexts."""
        manager = SharedContextManager()
        manager.create("ctx-1", {})
        manager.create("ctx-2", {})
        manager.create("ctx-3", {})

        contexts = sorted(manager.list_contexts())

        assert contexts == ["ctx-1", "ctx-2", "ctx-3"]


class TestSharedContextManagerClear:
    """Tests for SharedContextManager.clear method."""

    def test_clear_removes_all_contexts(self):
        """Test that clear removes all contexts."""
        manager = SharedContextManager()
        manager.create("ctx-1", {})
        manager.create("ctx-2", {})

        manager.clear()

        assert manager.list_contexts() == []


class TestSharedContextIntegration:
    """Integration tests for shared context workflow."""

    def test_concurrent_update_workflow(self):
        """Test concurrent update scenario with optimistic locking."""
        manager = SharedContextManager()
        ctx = manager.create("workflow-1", {"step": 1, "status": "running"})

        # Agent A reads context (version 1)
        ctx_a = manager.get("workflow-1")
        assert ctx_a.version == "1"

        # Agent B reads context (version 1)
        ctx_b = manager.get("workflow-1")
        assert ctx_b.version == "1"

        # Agent A updates successfully
        ctx_a = manager.update("workflow-1", {"step": 2, "status": "running"}, "1")
        assert ctx_a.version == "2"

        # Agent B tries to update with stale version - should fail
        with pytest.raises(ValueError, match="Version conflict"):
            manager.update("workflow-1", {"step": 2, "status": "completed"}, "1")

        # Agent B refreshes and updates with correct version
        ctx_b = manager.get("workflow-1")
        ctx_b = manager.update("workflow-1", {"step": 3, "status": "completed"}, "2")
        assert ctx_b.version == "3"

    def test_lock_update_unlock_workflow(self):
        """Test lock-update-unlock workflow."""
        manager = SharedContextManager()
        manager.create("resource-1", {"count": 0})

        # Agent locks the resource
        assert manager.lock("resource-1", "agent-1") is True

        # Update fails while locked
        with pytest.raises(ValueError, match="is locked"):
            manager.update("resource-1", {"count": 1}, "1")

        # Unlock the resource
        assert manager.unlock("resource-1", "agent-1") is True

        # Update succeeds after unlock
        ctx = manager.update("resource-1", {"count": 1}, "1")
        assert ctx.version == "2"
