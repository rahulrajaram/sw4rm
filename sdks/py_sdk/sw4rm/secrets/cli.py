from __future__ import annotations

import argparse
import json
import sys
from typing import Any

from .backend import Secrets
from .errors import SecretError, SecretNotFound
from .factory import select_backend
from .resolver import Resolver
from .types import Scope, SecretKey, SecretValue


def _print_json(data: Any) -> None:
    print(json.dumps(data, indent=2))


def _cmd_set(args: argparse.Namespace) -> int:
    backend, name = select_backend(args.backend)
    secrets = Secrets(backend)
    scope = Scope(None if args.global_scope else args.scope)
    value_str = args.value
    if value_str is None and args.stdin:
        value_str = sys.stdin.read().rstrip("\n")
    if value_str is None:
        print("error: no value provided; use --value or --stdin", file=sys.stderr)
        return 2
    try:
        secrets.set(scope, SecretKey(args.key), SecretValue(value_str))
        if args.json:
            _print_json({"ok": True, "backend": name, "scope": scope.label(), "key": args.key})
        else:
            print(f"stored secret: scope={scope.label()} key={args.key} (backend={name})")
        return 0
    except Exception as e:
        print(f"error: {e}", file=sys.stderr)
        return 1


def _cmd_get(args: argparse.Namespace) -> int:
    backend, name = select_backend(args.backend)
    secrets = Secrets(backend)
    scope = Scope(None if args.global_scope else args.scope)
    resolver = Resolver(backend)
    try:
        value, source = resolver.resolve(SecretKey(args.key), scope, explicit=None, env_var=args.env_var)
        if args.json:
            _print_json({
                "ok": True,
                "value": value,
                "source": source.value,
                "backend": name,
                "scope": scope.label(),
                "key": args.key,
            })
        else:
            print(value)
        # Warn if env override shadowed stored secret and warnings enabled
        if source.value == "env" and not args.no_warn:
            print(
                f"warning: environment variable {args.env_var} overrode stored secret",
                file=sys.stderr,
            )
        return 0
    except SecretNotFound as e:
        print(str(e), file=sys.stderr)
        return 4
    except Exception as e:
        print(f"error: {e}", file=sys.stderr)
        return 1


def _cmd_list(args: argparse.Namespace) -> int:
    backend, name = select_backend(args.backend)
    secrets = Secrets(backend)
    scope = None if args.all_scopes else (Scope(None) if args.global_scope else Scope(args.scope))
    data = secrets.list(scope=scope)
    if args.json:
        items = [
            {"scope": s or "global", "key": k, "value": v if args.include_values else None}
            for (s, k), v in sorted(data.items())
        ]
        _print_json({"backend": name, "items": items})
    else:
        for (s, k), v in sorted(data.items()):
            prefix = (s or "global")
            if args.include_values:
                print(f"{prefix}:{k}=***")
            else:
                print(f"{prefix}:{k}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="sw4rm-secret", description="Manage SW4RM secrets")
    sub = p.add_subparsers(dest="cmd", required=True)

    common_scope = argparse.ArgumentParser(add_help=False)
    g = common_scope.add_mutually_exclusive_group()
    g.add_argument("--scope", help="hive scope name", default=None)
    g.add_argument("--global", dest="global_scope", action="store_true", help="use global scope")
    common_scope.add_argument(
        "--backend",
        choices=["auto", "file", "keyring"],
        help="secrets backend (default from SW4RM_SECRETS_BACKEND or auto)",
        default=None,
    )

    # set
    p_set = sub.add_parser("set", parents=[common_scope], help="store a secret")
    p_set.add_argument("--key", required=True, help="secret key (e.g. provider.anthropic.api_key)")
    v = p_set.add_mutually_exclusive_group(required=False)
    v.add_argument("--value", help="secret value")
    v.add_argument("--stdin", action="store_true", help="read value from stdin")
    p_set.add_argument("--json", action="store_true", help="output JSON")
    p_set.set_defaults(func=_cmd_set)

    # get
    p_get = sub.add_parser("get", parents=[common_scope], help="retrieve a secret")
    p_get.add_argument("--key", required=True)
    p_get.add_argument("--env-var", help="environment variable name to check before store")
    p_get.add_argument("--no-warn", action="store_true", help="suppress env override warning")
    p_get.add_argument("--json", action="store_true", help="output JSON")
    p_get.set_defaults(func=_cmd_get)

    # list
    p_list = sub.add_parser("list", parents=[common_scope], help="list secrets")
    p_list.add_argument("--all-scopes", action="store_true", help="list across all scopes")
    p_list.add_argument("--include-values", action="store_true", help="include values in JSON output or masked in text")
    p_list.add_argument("--json", action="store_true", help="output JSON")
    p_list.set_defaults(func=_cmd_list)

    return p


def main(argv: list[str] | None = None) -> int:
    try:
        parser = build_parser()
        args = parser.parse_args(argv)
        return int(args.func(args))
    except SecretError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
