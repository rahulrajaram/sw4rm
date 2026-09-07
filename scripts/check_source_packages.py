#!/usr/bin/env python3
"""Qualify Lisp/Elixir source entrypoints outside the checkout using local dependencies.

This verifies source package layouts; it does not build or certify Hex metadata.
No dependency, compiler, image or tool is downloaded or installed.
"""
from __future__ import annotations

import gzip
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def check_lisp(quicklisp: Path) -> None:
    if not quicklisp.is_file():
        raise ValueError(f"Existing Quicklisp setup not found: {quicklisp}")
    with tempfile.TemporaryDirectory(prefix="sw4rm-lisp-source-") as temporary:
        isolated = Path(temporary)
        source = ROOT / 'sdks/cl_sdk'
        shutil.copytree(source / 'src', isolated / 'src')
        shutil.copyfile(source / 'sw4rm-sdk.asd', isolated / 'sw4rm-sdk.asd')
        script = isolated / 'check.lisp'
        with gzip.open(ROOT / 'tests/conformance_vectors/wire_vectors.json.gz', 'rt') as handle:
            contract = json.load(handle)
        rpc_count = len(contract['rpcs'])
        script.write_text('''(require :asdf)
(push (truename ".") asdf:*central-registry*)
(asdf:load-system :sw4rm-sdk)
(assert (equal (truename ".") (asdf:system-source-directory :sw4rm-sdk)))
(assert (= RPC_COUNT (length (sw4rm-sdk:protocol-rpc-paths))))
(assert (fboundp 'sw4rm-sdk:call-protocol-rpc))
(assert (fboundp 'sw4rm-sdk:compute-idempotency-token))
(format t "Isolated Lisp source package: all RPC_COUNT RPC bindings loaded~%")
'''.replace('RPC_COUNT', str(rpc_count)))
        subprocess.run(['sbcl', '--non-interactive', '--load', str(quicklisp.resolve()),
                        '--load', str(script)], cwd=isolated, check=True, timeout=120)


def check_elixir() -> None:
    with tempfile.TemporaryDirectory(prefix="sw4rm-elixir-source-") as temporary:
        isolated = Path(temporary)
        shutil.copytree(ROOT / 'sdks/ex_sdk/lib', isolated / 'lib')
        shutil.copyfile(ROOT / 'sdks/ex_sdk/mix.exs', isolated / 'mix.exs')
        (isolated / 'check.exs').write_text('''File.mkdir!("/compiled")
Code.prepend_path("/compiled")
{:ok, _, []} = Kernel.ParallelCompiler.compile_to_path(Path.wildcard("/sdk/lib/**/*.ex"), "/compiled")
contract = "/contract.json.gz" |> File.read!() |> :zlib.gunzip() |> Jason.decode!()
for rpc <- contract["rpcs"] do
  ["", "sw4rm." <> service, method] = String.split(rpc["path"], "/")
  module = Module.concat([Sw4rm.Proto | Enum.map(String.split(service, "."), &Macro.camelize/1)] ++ [Stub])
  Code.ensure_loaded!(module)
  true = function_exported?(module, method |> Macro.underscore() |> String.to_existing_atom(), 3)
end
IO.puts("Isolated Elixir source package: all #{length(contract["rpcs"])} RPC bindings loaded")
''')
        # Only cached dependency beams are mounted; exclude the old SDK itself.
        command = '''set -eu
pa=""
for dep in /deps/*/ebin; do
  case "$dep" in */sw4rm_sdk/ebin) continue ;; esac
  pa="$pa -pa $dep"
done
exec elixir $pa /sdk/check.exs
'''
        subprocess.run(['docker', 'run', '--rm', '--pull', 'never', '--network', 'none',
                        '-v', f'{isolated}:/sdk:ro',
                        '-v', f'{ROOT / "sdks/ex_sdk/_build/test/lib"}:/deps:ro',
                        '-v', f'{ROOT / "tests/conformance_vectors/wire_vectors.json.gz"}:/contract.json.gz:ro',
                        'elixir:1.16', 'sh', '-c', command], check=True, timeout=120)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('sdk', choices=['lisp', 'elixir'])
    parser.add_argument('--quicklisp', type=Path, default=Path.home() / 'quicklisp/setup.lisp')
    args = parser.parse_args()
    if args.sdk == 'lisp':
        check_lisp(args.quicklisp)
    else:
        check_elixir()


if __name__ == '__main__':
    main()
