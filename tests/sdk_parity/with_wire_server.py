"""Run a local SDK proof command with an ephemeral canonical fixture server."""
import os
import subprocess
import sys

from wire_contract_server import serve


def main():
    command = sys.argv[1:]
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        raise SystemExit("Usage: with_wire_server.py -- <SDK proof command> [args...]")
    with serve() as port:
        return subprocess.run(command, env={**os.environ, "SW4RM_WIRE_TARGET": f"127.0.0.1:{port}"},
                              timeout=300, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
