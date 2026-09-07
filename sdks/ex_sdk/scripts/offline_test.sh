#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../../.." && pwd)
sw4rm_network_mode=bridge
if [ -n "${SW4RM_WIRE_TARGET:-}" ]; then
  # The optional fixture is bound to the host loopback interface.
  sw4rm_network_mode=host
fi

# The image and all dependency artifacts are local. --pull never prevents an
# accidental registry access. Dependency artifacts must already exist locally.
exec docker run --rm --pull never \
  --network "$sw4rm_network_mode" --env SW4RM_WIRE_TARGET \
  -v "$repo_root:/workspace" \
  -w /workspace \
  elixir:1.16 \
  sh -lc '
    pa=""
    for dep_ebin in /workspace/sdks/ex_sdk/_build/test/lib/*/ebin; do
      pa="$pa -pa $dep_ebin"
    done
    exec elixir $pa /workspace/sdks/ex_sdk/scripts/offline_test.exs "$@"
  ' sw4rm-offline "$@"
