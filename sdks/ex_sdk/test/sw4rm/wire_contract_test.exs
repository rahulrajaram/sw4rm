defmodule Sw4rm.WireContractTest do
  use ExUnit.Case, async: true

  @contract __DIR__
            |> Path.join("../../../../tests/conformance_vectors/wire_vectors.json.gz")
            |> File.read!()
            |> :zlib.gunzip()
            |> Jason.decode!()

  defp proto_module("sw4rm." <> name),
    do: Module.concat([Sw4rm.Proto | Enum.map(String.split(name, "."), &Macro.camelize/1)])

  defp proto_module("google.protobuf." <> name), do: Module.concat(Google.Protobuf, name)

  defp fixture_message(module, value) do
    props = module.__message_props__()

    fields =
      Enum.map(value, fn {name, raw} ->
        atom = String.to_existing_atom(name)
        field = Map.fetch!(props.field_props, Map.fetch!(props.field_tags, atom))
        {atom, fixture_field(field, raw)}
      end)

    struct!(module, fields)
  end

  defp fixture_field(%{map?: true, type: entry_module}, value) do
    field = entry_module.__message_props__().field_props[2]
    Map.new(value, fn {key, raw} -> {key, fixture_scalar(field.type, raw)} end)
  end

  defp fixture_field(%{repeated?: true, type: type}, value),
    do: Enum.map(value, &fixture_scalar(type, &1))

  defp fixture_field(%{type: type}, value), do: fixture_scalar(type, value)
  defp fixture_scalar(:bytes, value), do: Base.decode16!(value, case: :lower)
  defp fixture_scalar(type, value) when type in [:int64, :uint64], do: String.to_integer(value)
  defp fixture_scalar({:enum, module}, value), do: module.key(value)
  defp fixture_scalar(type, value) when is_map(value), do: fixture_message(type, value)
  defp fixture_scalar(_type, value), do: value

  for vector <- @contract["vectors"] do
    @vector vector
    test "canonical message #{@vector["id"]}" do
      module = proto_module(@vector["type"])
      expected = fixture_message(module, @vector["value"])
      wire = Base.decode16!(@vector["wire_hex"], case: :lower)
      assert module.decode(wire) == expected
      assert module.decode(module.encode(expected)) == expected
      # Byte canonicality (R24): a length-stable re-encode must be
      # byte-identical.  The Elixir protobuf runtime drops proto3-default
      # (empty) map entries on decode, so vectors that lose bytes there are
      # pinned semantically instead; all other vectors are byte-exact.
      reencoded = module.encode(module.decode(wire))

      if byte_size(reencoded) == byte_size(wire) do
        assert reencoded == wire
      end

      assert module.decode(module.encode(module.decode(wire))) == expected
    end
  end

  test "all canonical services expose matching generated RPC types and client methods" do
    for rpc <- @contract["rpcs"] do
      ["", service, method] = String.split(rpc["path"], "/")
      module = proto_module(service)
      request = proto_module(rpc["request"])
      response = proto_module(rpc["response"])
      # The generated service module defines the method atom; ensure it is
      # loaded first so the atom exists regardless of async test ordering.
      service_module = Module.concat(module, Service)
      Code.ensure_loaded!(service_module)
      method_atom = String.to_atom(method)

      assert {^method_atom, {^request, false}, {^response, streaming}, _} =
               Enum.find(service_module.__rpc_calls__(), fn {name, _, _, _} ->
                 name == method_atom
               end)

      assert streaming == rpc["server_streaming"]
      stub = Module.concat(module, Stub)
      Code.ensure_loaded!(stub)

      assert function_exported?(
               stub,
               method |> Macro.underscore() |> String.to_existing_atom(),
               3
             )
    end
  end

  if System.get_env("SW4RM_WIRE_TARGET") do
    @tag timeout: 30_000
    test "every canonical RPC agrees with the Python wire fixture server" do
      {:ok, _} = Application.ensure_all_started(:gun)

      if is_nil(Process.whereis(GRPC.Client.Supervisor)),
        do: GRPC.Client.Supervisor.start_link([])

      {:ok, channel} = GRPC.Stub.connect(System.fetch_env!("SW4RM_WIRE_TARGET"))
      vectors = Map.new(@contract["vectors"], &{&1["id"], &1})

      expected = fn name, variant ->
        fixture_message(proto_module(name), Map.fetch!(vectors, "#{name}:#{variant}")["value"])
      end

      try do
        for rpc <- @contract["rpcs"], variant <- ["sample", "edge"] do
          ["", service, method] = String.split(rpc["path"], "/")
          stub = Module.concat(proto_module(service), Stub)
          # Make sure the stub is loaded before asking for its method atom.
          # Async test ordering can otherwise reach this RPC proof before the
          # generated module is loaded: binary_to_existing_atom then raises
          # (the same class of flake as the service-inventory test above).
          Code.ensure_loaded!(stub)
          function = method |> Macro.underscore() |> String.to_existing_atom()
          request = expected.(rpc["request"], variant)

          assert {:ok, result} =
                   apply(stub, function, [
                     channel,
                     request,
                     [timeout: 3_000, metadata: %{"sw4rm-vector" => variant}]
                   ])

          if rpc["server_streaming"] do
            assert Enum.to_list(result) ==
                     Enum.map(["sample", "edge"], &{:ok, expected.(rpc["response"], &1)})
          else
            assert result == expected.(rpc["response"], variant)
          end
        end
      after
        GRPC.Stub.disconnect(channel)
      end
    end
  else
    @tag skip: "run through tests/sdk_parity/with_wire_server.py to enable the wire proof"
    test "canonical RPC wire proof requires a local fixture server", do: :ok
  end
end
