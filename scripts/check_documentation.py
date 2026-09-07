#!/usr/bin/env python3
"""Small, offline documentation contract checks.

The checker intentionally validates only contracts which can be established
from files in this repository.  It does not execute examples, start services,
or fetch links from the network.
"""

from __future__ import annotations

import argparse
import ast
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Optional, Union


@dataclass(frozen=True)
class Issue:
    path: Path
    line: int
    kind: str
    message: str

    def __str__(self) -> str:
        return f"{self.path}:{self.line}: {self.kind}: {self.message}"


_FENCE_RE = re.compile(r"^\s*```([^\s`]*)\s*$")
_LINK_RE = re.compile(r"!?\[[^\]]*\]\(\s*(<[^>]+>|[^\s)]+)", re.MULTILINE)
_REF_RE = re.compile(r"^\s*\[[^\]]+\]:\s*(<[^>]+>|\S+)", re.MULTILINE)
_EXTERNAL_RE = re.compile(r"^(?:[a-z][a-z0-9+.-]*:|//)", re.IGNORECASE)
_FIELD_RE = re.compile(
    r"^(?:(?:optional|required|repeated)\s+)?"
    r"(?P<type>[.A-Za-z_][\w.]*(?:\s*<[^>]+>)?)\s+"
    r"(?P<name>[A-Za-z_]\w*)\s*=\s*(?P<tag>-?\d+)\s*(?:\[|;|$)"
)
_MAP_FIELD_RE = re.compile(
    r"^map\s*<(?P<key>[.A-Za-z_]\w*),\s*(?P<value>[.A-Za-z_]\w*)>\s+"
    r"(?P<name>[A-Za-z_]\w*)\s*=\s*(?P<tag>-?\d+)"
)
_ENUM_VALUE_RE = re.compile(r"^(?P<name>[A-Z][A-Z0-9_]*)\s*=\s*(?P<value>-?\d+)")

# These are deliberately narrow.  An extension draft may describe a future
# schema, so it is not evidence about the current public protobuf surface.
_PROTECTED_NAMES = (
    "SW4-007",
    "SW4-014",
    "SW4-015",
)


def _relative(path: Path, root: Path) -> Path:
    try:
        return path.relative_to(root)
    except ValueError:
        return path


def _markdown_files(root: Path) -> list[Path]:
    files = ([root / "README.md"] if (root / "README.md").is_file() else [])
    files.extend(sorted((root / "documentation").rglob("*.md")))
    return [path for path in files if not _is_protected(path, root)]


def _is_protected(path: Path, root: Path) -> bool:
    rel = _relative(path, root).as_posix()
    return any(name in Path(rel).name for name in _PROTECTED_NAMES)


def _is_versioned_or_extension(path: Path, root: Path) -> bool:
    rel = _relative(path, root).as_posix()
    return rel.startswith("documentation/protocol/extensions/") or bool(
        re.search(r"(?:^|/)(?:v\d+(?:\.\d+)*|histor(?:y|ical)|legacy)(?:[-_.]|/)", rel, re.I)
    )


def _line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def _target_path(raw: str) -> str:
    target = raw.strip()
    if target.startswith("<") and ">" in target:
        target = target[1 : target.index(">")]
    return target


def check_local_links(root: Path) -> list[Issue]:
    issues: list[Issue] = []
    for path in _markdown_files(root):
        text = path.read_text(encoding="utf-8")
        matches = list(_LINK_RE.finditer(text)) + list(_REF_RE.finditer(text))
        seen: set[tuple[int, str]] = set()
        for match in matches:
            target = _target_path(match.group(1))
            if not target or target.startswith("#") or _EXTERNAL_RE.match(target):
                continue
            target = target.split("#", 1)[0].split("?", 1)[0]
            if not target:
                continue
            candidate = (root / target.lstrip("/")) if target.startswith("/") else path.parent / target
            candidate = candidate.resolve()
            key = (_line_number(text, match.start()), target)
            if key in seen:
                continue
            seen.add(key)
            if not candidate.is_file() and not candidate.is_dir():
                issues.append(
                    Issue(
                        _relative(path, root),
                        key[0],
                        "link",
                        f"local link target does not exist: {target}",
                    )
                )
    return issues


def _strip_proto_comment(line: str) -> str:
    return line.split("//", 1)[0].strip()


def _parse_proto(path: Path) -> tuple[dict[str, dict[str, tuple[str, int]]], dict[str, dict[str, int]]]:
    messages: dict[str, dict[str, tuple[str, int]]] = {}
    enums: dict[str, dict[str, int]] = {}
    stack: list[tuple[str, str, int]] = []
    depth = 0
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = _strip_proto_comment(raw)
        if not line:
            depth += raw.count("{") - raw.count("}")
            while stack and depth < stack[-1][2]:
                stack.pop()
            continue
        declaration = re.match(r"(?:message|enum)\s+(\w+)\s*\{", line)
        if declaration:
            kind = "message" if line.startswith("message") else "enum"
            name = declaration.group(1)
            entry_depth = depth + 1
            stack.append((kind, name, entry_depth))
            if kind == "message":
                messages.setdefault(name, {})
            else:
                enums.setdefault(name, {})
        elif stack:
            kind, name, entry_depth = stack[-1]
            content = line.rstrip(";").strip()
            field = _MAP_FIELD_RE.match(content) or _FIELD_RE.match(content)
            if kind == "message" and field:
                if "key" in field.groupdict():
                    field_type = f"map<{field.group('key')},{field.group('value')}>"
                else:
                    field_type = field.group("type").replace(" ", "")
                messages[name][field.group("name")] = (field_type, int(field.group("tag")))
            elif kind == "enum":
                value = _ENUM_VALUE_RE.match(content)
                if value:
                    enums[name][value.group("name")] = int(value.group("value"))
        depth += raw.count("{") - raw.count("}")
        while stack and depth < stack[-1][2]:
            stack.pop()
    return messages, enums


def _normal_type(value: str) -> str:
    return value.strip().lstrip(".").split(".")[-1]


def _proto_blocks(text: str) -> Iterable[tuple[int, str, str]]:
    lines = text.splitlines()
    active: Optional[tuple[int, str]] = None
    body: list[str] = []
    for number, line in enumerate(lines, 1):
        fence = _FENCE_RE.match(line)
        if fence and active is None:
            language = fence.group(1).lower()
            if language in {"proto", "protobuf"}:
                active = (number, language)
                body = []
            continue
        if fence and active is not None:
            yield active[0], active[1], "\n".join(body)
            active = None
            body = []
            continue
        if active is not None:
            body.append(line)


def _snippet_is_illustrative(text: str, start: int, body: str = "") -> bool:
    before = text.splitlines()[: max(0, start - 1)][-8:]
    marker = " ".join(before + body.splitlines()[:2]).lower()
    return bool(re.search(r"\b(?:illustrative|custom schema|pseudocode|not canonical|for illustration)\b", marker))


def _snippet_declarations(body: str) -> tuple[list[tuple[str, dict[str, tuple[str, int]]]], list[tuple[str, dict[str, int]]]]:
    messages: list[tuple[str, dict[str, tuple[str, int]]]] = []
    enums: list[tuple[str, dict[str, int]]] = []
    lines = body.splitlines()
    # Reuse the same small parser as .proto files by writing no temporary file.
    stack: list[tuple[str, str, int]] = []
    depth = 0
    for raw in lines:
        line = _strip_proto_comment(raw)
        if not line:
            depth += raw.count("{") - raw.count("}")
            while stack and depth < stack[-1][2]:
                stack.pop()
            continue
        declaration = re.match(r"(?:message|enum)\s+(\w+)\s*\{", line)
        if declaration:
            kind = "message" if line.startswith("message") else "enum"
            name = declaration.group(1)
            stack.append((kind, name, depth + 1))
            if kind == "message":
                messages.append((name, {}))
            else:
                enums.append((name, {}))
        elif stack:
            kind, name, _ = stack[-1]
            content = line.rstrip(";").strip()
            field = _MAP_FIELD_RE.match(content) or _FIELD_RE.match(content)
            if kind == "message" and field:
                field_type = (
                    f"map<{field.group('key')},{field.group('value')}>"
                    if "key" in field.groupdict()
                    else field.group("type").replace(" ", "")
                )
                for existing_name, fields in reversed(messages):
                    if existing_name == name:
                        fields[field.group("name")] = (field_type, int(field.group("tag")))
                        break
            elif kind == "enum":
                value = _ENUM_VALUE_RE.match(content)
                if value:
                    for existing_name, values in reversed(enums):
                        if existing_name == name:
                            values[value.group("name")] = int(value.group("value"))
                            break
        depth += raw.count("{") - raw.count("}")
        while stack and depth < stack[-1][2]:
            stack.pop()
    return messages, enums


def check_proto_snippets(root: Path) -> list[Issue]:
    canonical_messages: dict[str, dict[str, tuple[str, int]]] = {}
    canonical_enums: dict[str, dict[str, int]] = {}
    for path in sorted((root / "protos").glob("*.proto")):
        messages, enums = _parse_proto(path)
        canonical_messages.update(messages)
        canonical_enums.update(enums)

    issues: list[Issue] = []
    for path in _markdown_files(root):
        if _is_versioned_or_extension(path, root):
            continue
        text = path.read_text(encoding="utf-8")
        for start, _language, body in _proto_blocks(text):
            if _snippet_is_illustrative(text, start, body):
                continue
            messages, enums = _snippet_declarations(body)
            for name, fields in messages:
                if name not in canonical_messages:
                    continue  # A local/custom schema is valid documentation.
                canonical = canonical_messages[name]
                for field_name, (field_type, tag) in fields.items():
                    expected = canonical.get(field_name)
                    if expected is None:
                        line = start + next(
                            (index for index, line_text in enumerate(body.splitlines(), 1) if field_name in line_text),
                            1,
                        )
                        issues.append(
                            Issue(
                                _relative(path, root),
                                line,
                                "protobuf",
                                f"{name}.{field_name} is not present in the canonical definition",
                            )
                        )
                        continue
                    expected_type, expected_tag = expected
                    if _normal_type(field_type) != _normal_type(expected_type) or tag != expected_tag:
                        line = start + next(
                            (index for index, line_text in enumerate(body.splitlines(), 1) if field_name in line_text),
                            1,
                        )
                        issues.append(
                            Issue(
                                _relative(path, root),
                                line,
                                "protobuf",
                                f"{name}.{field_name} is {field_type} = {tag}; canonical definition is {expected_type} = {expected_tag}",
                            )
                        )
            for name, values in enums:
                if name not in canonical_enums:
                    continue
                canonical = canonical_enums[name]
                for value_name, value in values.items():
                    expected = canonical.get(value_name)
                    if expected is not None and value != expected:
                        line = start + next(
                            (index for index, line_text in enumerate(body.splitlines(), 1) if value_name in line_text),
                            1,
                        )
                        issues.append(
                            Issue(
                                _relative(path, root),
                                line,
                                "protobuf",
                                f"{name}.{value_name} is {value}; canonical definition is {expected}",
                            )
                        )
    return issues


def _is_negative_claim(context: str) -> bool:
    return bool(
        re.search(
            r"\b(?:no|not|never|cannot|can't|does\s+not|do\s+not|without|isn't|is\s+not|alone\s+doesn't|alone\s+does\s+not|may\s+repeat)\b",
            context,
            re.I,
        )
    )


def check_claims(root: Path) -> list[Issue]:
    issues: list[Issue] = []
    exact_once = re.compile(r"exactly[- ]once", re.I)
    for path in _markdown_files(root):
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()
        for index, line in enumerate(lines):
            lower = line.lower()
            if re.search(r"\bstatus\s*:\s*production\s+ready\b", lower):
                issues.append(Issue(_relative(path, root), index + 1, "claim", "unsupported 'Status: Production Ready' claim"))
            claim_context = " ".join(lines[max(0, index - 1) : min(len(lines), index + 2)])
            if exact_once.search(line) and re.search(r"\bconfigurable\b", claim_context, re.I):
                if not _is_negative_claim(claim_context):
                    issues.append(Issue(_relative(path, root), index + 1, "claim", "configurable exactly-once behavior is not a supported contract"))

            window = " ".join(lines[max(0, index - 2) : min(len(lines), index + 3)])
            if exact_once.search(line) and re.search(r"\b(?:idempotency[_ ]token|deduplication[_ ]token)\b", window, re.I):
                if re.search(r"\b(?:enables|guarantees?|ensures?|provides?|processing\s+is|via)\b", line, re.I) and not _is_negative_claim(window):
                    issues.append(Issue(_relative(path, root), index + 1, "claim", "a token alone cannot guarantee exactly-once external effects"))
    return issues


_PYTHON_CALLS: dict[str, set[str]] = {
    "register": {"agent"},
    "send_message": {"envelope"},
    "ack_delivery": {"agent_id", "seq", "message_id", "permanent_failure"},
    "build_envelope": {"producer_id", "message_type", "content_type", "payload", "idempotency_token", "correlation_id"},
}


def _local_python_module_exists(root: Path, module: str) -> bool:
    """Resolve first-party imports without importing or executing them."""
    if not module == "sw4rm" and not module.startswith("sw4rm."):
        return True
    package_root = root / "sdks" / "py_sdk"
    parts = module.split(".")
    candidate = package_root.joinpath(*parts)
    return (candidate.with_suffix(".py")).is_file() or (candidate / "__init__.py").is_file()


def check_first_agent_python(root: Path) -> list[Issue]:
    issues: list[Issue] = []
    for path in _markdown_files(root):
        if "first-agent" not in path.name.lower():
            continue
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()
        active: Optional[tuple[int, list[str]]] = None
        for number, line in enumerate(lines, 1):
            fence = _FENCE_RE.match(line)
            if fence and active is None and fence.group(1).lower() in {"python", "py"}:
                active = (number, [])
                continue
            if fence and active is not None:
                start, body = active
                source = "\n".join(body)
                try:
                    tree = ast.parse(source, filename=str(path))
                except SyntaxError as error:
                    issues.append(Issue(_relative(path, root), start + (error.lineno or 1), "python", f"example does not parse: {error.msg}"))
                else:
                    for node in ast.walk(tree):
                        module = node.module if isinstance(node, ast.ImportFrom) else None
                        if isinstance(node, ast.ImportFrom) and node.level == 0 and module and not _local_python_module_exists(root, module):
                            issues.append(Issue(_relative(path, root), start + (node.lineno or 1), "python", f"first-party import does not exist: {module}"))
                        if isinstance(node, ast.Import):
                            for alias in node.names:
                                if not _local_python_module_exists(root, alias.name):
                                    issues.append(Issue(_relative(path, root), start + (node.lineno or 1), "python", f"first-party import does not exist: {alias.name}"))
                    for node in ast.walk(tree):
                        if not isinstance(node, ast.Call):
                            continue
                        function = node.func.attr if isinstance(node.func, ast.Attribute) else node.func.id if isinstance(node.func, ast.Name) else ""
                        allowed = _PYTHON_CALLS.get(function)
                        if allowed is None:
                            continue
                        unknown = [keyword.arg for keyword in node.keywords if keyword.arg and keyword.arg not in allowed]
                        if unknown:
                            issues.append(Issue(_relative(path, root), start + (node.lineno or 1), "python", f"{function} has unknown keyword(s): {', '.join(unknown)}"))
                active = None
                continue
            if active is not None:
                active[1].append(line)
    return issues


def check_documentation(root: Union[Path, str]) -> list[Issue]:
    root = Path(root).resolve()
    return check_local_links(root) + check_proto_snippets(root) + check_claims(root) + check_first_agent_python(root)


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1], help="repository root")
    args = parser.parse_args(argv)
    issues = check_documentation(args.root)
    for issue in issues:
        print(issue)
    if issues:
        print(f"documentation contract failed: {len(issues)} issue(s)", file=sys.stderr)
        return 1
    print("documentation contract passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
