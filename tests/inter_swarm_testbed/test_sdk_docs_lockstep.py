import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]

EXAMPLE_READMES = [
    REPO_ROOT / "sdks" / "js_sdk" / "examples" / "README.md",
    REPO_ROOT / "sdks" / "rust_sdk" / "examples" / "README.md",
    REPO_ROOT / "sdks" / "py_sdk" / "examples" / "README.md",
    REPO_ROOT / "sdks" / "cl_sdk" / "examples" / "README.md",
    REPO_ROOT / "sdks" / "ex_sdk" / "examples" / "README.md",
]

SDK_VISIBILITY_DOCS = [
    REPO_ROOT / "documentation" / "index.md",
    REPO_ROOT / "documentation" / "README.md",
    REPO_ROOT / "documentation" / "clients" / "index.md",
    REPO_ROOT / "documentation" / "examples" / "index.md",
]

STALE_LANGUAGE_TARGETS = [
    REPO_ROOT / "sdks" / "js_sdk" / "examples" / "README.md",
    REPO_ROOT / "sdks" / "rust_sdk" / "examples" / "README.md",
    REPO_ROOT / "sdks" / "js_sdk" / "examples" / "handoffExample.ts",
    REPO_ROOT / "sdks" / "js_sdk" / "examples" / "negotiationRoomExample.ts",
    REPO_ROOT / "sdks" / "js_sdk" / "examples" / "workflowExample.ts",
    REPO_ROOT / "sdks" / "js_sdk" / "examples" / "toolStreamingExample.ts",
    REPO_ROOT / "sdks" / "js_sdk" / "examples" / "votingExample.ts",
    REPO_ROOT / "sdks" / "js_sdk" / "examples" / "secretsExample.ts",
    REPO_ROOT / "sdks" / "rust_sdk" / "examples" / "handoff.rs",
    REPO_ROOT / "sdks" / "rust_sdk" / "examples" / "negotiation_room.rs",
    REPO_ROOT / "sdks" / "rust_sdk" / "examples" / "workflow.rs",
    REPO_ROOT / "sdks" / "rust_sdk" / "examples" / "tool_streaming.rs",
    REPO_ROOT / "sdks" / "rust_sdk" / "examples" / "voting.rs",
    REPO_ROOT / "sdks" / "rust_sdk" / "examples" / "secrets.rs",
    REPO_ROOT / "documentation" / "quickstart" / "index.md",
]

SDK_LABELS = [
    "Python",
    "JavaScript/TypeScript",
    "Rust",
    "Common Lisp",
    "Elixir",
]

FORBIDDEN_SNIPPETS = [
    "not yet implemented",
    "to be migrated here soon",
    "See Phase 2.",
    "See Phase 3.",
    "IMPLEMENTATION_PLAN.md",
    "../../QUICKSTART.md",
]


def test_example_readmes_exist_for_all_public_sdks() -> None:
    missing = [str(path.relative_to(REPO_ROOT)) for path in EXAMPLE_READMES if not path.exists()]
    assert not missing, f"missing example README files: {missing}"


def test_public_docs_name_all_five_sdks() -> None:
    for path in SDK_VISIBILITY_DOCS:
        text = path.read_text(encoding="utf-8")
        missing = [label for label in SDK_LABELS if label not in text]
        assert not missing, f"{path.relative_to(REPO_ROOT)} is missing SDK labels: {missing}"


def test_stale_example_and_quickstart_language_removed() -> None:
    for path in STALE_LANGUAGE_TARGETS:
        text = path.read_text(encoding="utf-8")
        for snippet in FORBIDDEN_SNIPPETS:
            assert snippet not in text, f"{path.relative_to(REPO_ROOT)} still contains stale snippet: {snippet}"


def test_js_advanced_agent_uses_worktree_endpoint() -> None:
    path = REPO_ROOT / "sdks" / "js_sdk" / "examples" / "advancedAgent.ts"
    text = path.read_text(encoding="utf-8")
    assert "SW4RM_WORKTREE_ADDR" in text
    assert "this.worktree = new WorktreeClient({ address: args.worktreeAddr });" in text


# ---------------------------------------------------------------------------
# Phase 12 verification harnesses
# ---------------------------------------------------------------------------

JS_NEW_EXAMPLES = [
    "examples/toolStreamingExample.ts",
    "examples/votingExample.ts",
    "examples/secretsExample.ts",
]


def test_js_new_examples_type_check() -> None:
    """Verify that all new JS examples pass TypeScript type checking."""
    result = subprocess.run(
        [
            "npx", "tsc", "--noEmit",
            "--target", "ES2022",
            "--module", "NodeNext",
            "--moduleResolution", "NodeNext",
            "--lib", "ES2022",
            "--types", "node",
        ] + JS_NEW_EXAMPLES,
        cwd=str(REPO_ROOT / "sdks" / "js_sdk"),
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"JS type check failed:\n{result.stdout}\n{result.stderr}"


def test_rust_examples_cargo_check() -> None:
    """Verify that all Rust examples compile."""
    result = subprocess.run(
        ["cargo", "check", "--examples"],
        cwd=str(REPO_ROOT / "sdks" / "rust_sdk"),
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, f"Rust cargo check failed:\n{result.stdout}\n{result.stderr}"


def test_python_secrets_example_runs() -> None:
    """Verify that the Python secrets example runs to completion."""
    result = subprocess.run(
        ["/home/rahul/311/bin/python", "sdks/py_sdk/examples/secrets_example.py"],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Python secrets example failed:\n{result.stdout}\n{result.stderr}"


def test_new_example_files_exist() -> None:
    """Verify all Phase 12 example files exist on disk."""
    expected_files = [
        REPO_ROOT / "sdks" / "js_sdk" / "examples" / "toolStreamingExample.ts",
        REPO_ROOT / "sdks" / "js_sdk" / "examples" / "votingExample.ts",
        REPO_ROOT / "sdks" / "js_sdk" / "examples" / "secretsExample.ts",
        REPO_ROOT / "sdks" / "rust_sdk" / "examples" / "tool_streaming.rs",
        REPO_ROOT / "sdks" / "rust_sdk" / "examples" / "voting.rs",
        REPO_ROOT / "sdks" / "rust_sdk" / "examples" / "secrets.rs",
        REPO_ROOT / "sdks" / "py_sdk" / "examples" / "secrets_example.py",
        REPO_ROOT / "sdks" / "ex_sdk" / "examples" / "activity_walkthrough.exs",
        REPO_ROOT / "sdks" / "ex_sdk" / "examples" / "workflow.exs",
    ]
    missing = [str(p.relative_to(REPO_ROOT)) for p in expected_files if not p.exists()]
    assert not missing, f"missing Phase 12 example files: {missing}"


def test_docs_matrix_covers_new_examples() -> None:
    """Verify the shared docs matrix references all new example files."""
    matrix_path = REPO_ROOT / "documentation" / "examples" / "index.md"
    text = matrix_path.read_text(encoding="utf-8")
    expected_refs = [
        "toolStreamingExample.ts",
        "votingExample.ts",
        "secretsExample.ts",
        "tool_streaming.rs",
        "voting.rs",
        "secrets.rs",
        "secrets_example.py",
        "activity_walkthrough.exs",
        "workflow.exs",
    ]
    missing = [ref for ref in expected_refs if ref not in text]
    assert not missing, f"docs matrix missing references: {missing}"


def test_elixir_hitl_documented_as_service_backed() -> None:
    """Verify Elixir HITL is documented as service-backed only."""
    readme = (REPO_ROOT / "sdks" / "ex_sdk" / "examples" / "README.md").read_text(encoding="utf-8")
    assert "service-backed" in readme.lower() or "Sw4rm.Clients.Hitl" in readme, \
        "Elixir README must document HITL as service-backed"
    matrix = (REPO_ROOT / "documentation" / "examples" / "index.md").read_text(encoding="utf-8")
    assert "service-backed only" in matrix, \
        "docs matrix must show Elixir HITL as service-backed only"
