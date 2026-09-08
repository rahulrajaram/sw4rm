from __future__ import annotations

import importlib.util
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("check_documentation", ROOT / "scripts/check_documentation.py")
assert SPEC and SPEC.loader
checker = importlib.util.module_from_spec(SPEC)
sys.modules["check_documentation"] = checker
SPEC.loader.exec_module(checker)


PROTO = """syntax = \"proto3\";
message Envelope {
  string message_id = 1;
  uint64 sequence_number = 2;
}
enum State {
  UNKNOWN = 0;
  READY = 1;
}
"""

CURRENT = """# Current API

[reference](reference.md)

```protobuf
message Envelope {
  string message_id = 1;
  uint64 sequence_number = 2;
}
enum State {
  UNKNOWN = 0;
  READY = 1;
}
```
"""


def make_repo(tmp_path: Path, body: str = CURRENT) -> Path:
    (tmp_path / "protos").mkdir()
    (tmp_path / "documentation").mkdir()
    (tmp_path / "protos/common.proto").write_text(PROTO, encoding="utf-8")
    (tmp_path / "README.md").write_text("[docs](documentation/current.md)\n", encoding="utf-8")
    (tmp_path / "documentation/current.md").write_text(body, encoding="utf-8")
    (tmp_path / "documentation/reference.md").write_text("reference\n", encoding="utf-8")
    return tmp_path


def kinds(issues: list[object]) -> set[str]:
    return {issue.kind for issue in issues}


def test_current_contract_passes(tmp_path: Path) -> None:
    assert checker.check_documentation(make_repo(tmp_path)) == []


def test_mutated_local_link_fails(tmp_path: Path) -> None:
    repo = make_repo(tmp_path, CURRENT.replace("reference.md", "missing.md"))
    issues = checker.check_documentation(repo)
    assert "link" in kinds(issues)
    assert any("missing.md" in issue.message for issue in issues)


def test_mutated_protobuf_tag_or_type_fails(tmp_path: Path) -> None:
    body = CURRENT.replace("uint64 sequence_number = 2", "string sequence_number = 9")
    issues = checker.check_documentation(make_repo(tmp_path, body))
    assert "protobuf" in kinds(issues)
    assert any("sequence_number" in issue.message for issue in issues)


def test_mutated_protobuf_unknown_field_fails(tmp_path: Path) -> None:
    body = CURRENT.replace("  uint64 sequence_number = 2;", "  uint64 sequence_number = 2;\n  string undocumented = 3;")
    issues = checker.check_documentation(make_repo(tmp_path, body))
    assert any(issue.kind == "protobuf" and "undocumented" in issue.message for issue in issues)


def test_mutated_exactly_once_claim_fails(tmp_path: Path) -> None:
    body = CURRENT + "\nThe idempotency token enables exactly-once delivery.\n"
    issues = checker.check_documentation(make_repo(tmp_path, body))
    assert "claim" in kinds(issues)


def test_negative_token_caveat_is_allowed(tmp_path: Path) -> None:
    body = CURRENT + "\nA token alone does not provide exactly-once external effects.\n"
    assert not [issue for issue in checker.check_documentation(make_repo(tmp_path, body)) if issue.kind == "claim"]


def test_negative_configurable_exactly_once_caveat_is_allowed(tmp_path: Path) -> None:
    body = CURRENT + "\nThe reference router does not implement configurable exactly-once delivery.\n"
    assert not [issue for issue in checker.check_documentation(make_repo(tmp_path, body)) if issue.kind == "claim"]


def test_extension_draft_is_excluded_from_proto_contract(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    draft_dir = repo / "documentation/protocol/extensions"
    draft_dir.mkdir(parents=True)
    (draft_dir / "SW4-007-draft.md").write_text(
        "```protobuf\nmessage Envelope {\n  string message_id = 99;\n}\n```\n",
        encoding="utf-8",
    )
    assert not [issue for issue in checker.check_proto_snippets(repo) if "SW4-007" in str(issue.path)]


def test_illustrative_known_schema_is_allowed(tmp_path: Path) -> None:
    repo = make_repo(
        tmp_path,
        """The following is an illustrative custom schema.

```protobuf
message Envelope {
  string message_id = 99;
}
```
""",
    )
    assert not [issue for issue in checker.check_proto_snippets(repo) if issue.kind == "protobuf"]


def test_first_agent_python_unknown_keyword_fails(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    (repo / "documentation/first-agent.md").write_text(
        "```python\nrouter.send_message(envelope=message, unsupported=True)\n```\n",
        encoding="utf-8",
    )
    issues = checker.check_documentation(repo)
    assert "python" in kinds(issues)


def test_first_agent_python_unknown_first_party_import_fails(tmp_path: Path) -> None:
    repo = make_repo(tmp_path)
    (repo / "sdks/py_sdk/sw4rm/clients").mkdir(parents=True)
    (repo / "sdks/py_sdk/sw4rm/clients/registry.py").write_text("", encoding="utf-8")
    (repo / "documentation/first-agent.md").write_text(
        "```python\nfrom sw4rm.clients.missing import Client\n```\n",
        encoding="utf-8",
    )
    issues = checker.check_documentation(repo)
    assert any(issue.kind == "python" and "import" in issue.message for issue in issues)
