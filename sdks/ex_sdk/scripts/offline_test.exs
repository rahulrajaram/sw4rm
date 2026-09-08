#!/usr/bin/env elixir

# Run the Elixir suite without Mix, Hex, or dependency resolution. The caller
# must provide the cached dependency ebin directories on the code path (the
# companion offline_test.sh does this through the existing local _build tree).
Code.compiler_options(ignore_module_conflict: true)

sdk_root = Path.expand("..", __DIR__)

source_files = Path.wildcard(Path.join(sdk_root, "lib/**/*.ex"))

compiled_path =
  Path.join(System.tmp_dir!(), "sw4rm-offline-#{System.unique_integer([:positive])}")

File.mkdir!(compiled_path)
Code.prepend_path(compiled_path)

case Kernel.ParallelCompiler.compile_to_path(source_files, compiled_path) do
  {:ok, _modules, _warnings} -> :ok
  {:error, errors, _warnings} -> raise "SDK compilation failed: #{inspect(errors)}"
end

case Sw4rm.Application.start(:normal, []) do
  {:ok, _pid} -> :ok
  {:error, {:already_started, _pid}} -> :ok
  {:error, reason} -> raise "failed to start SDK application: #{inspect(reason)}"
end

ExUnit.start()

patterns =
  case System.argv() do
    [] -> ["test/**/*_test.exs"]
    selected -> selected
  end

files =
  Enum.flat_map(patterns, fn pattern ->
    expanded = Path.expand(pattern, sdk_root)

    unless String.starts_with?(expanded, Path.join(sdk_root, "test") <> "/"),
      do: raise("test selector must stay inside the SDK test directory")

    case Path.wildcard(expanded) do
      [] -> raise "test selector matched no files: #{pattern}"
      matches -> matches
    end
  end)

files |> Enum.uniq() |> Enum.each(&Code.require_file/1)

result = ExUnit.run()
File.rm_rf!(compiled_path)
System.halt(if(result.failures == 0, do: 0, else: 1))
