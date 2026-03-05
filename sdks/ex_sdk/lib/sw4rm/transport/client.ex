defmodule Sw4rm.Transport.Client do
  @moduledoc """
  `__using__` macro providing shared plumbing for all 13 service clients.

  Injects channel_manager ref, timeout, retry config, and helper functions.
  """

  defmacro __using__(opts) do
    service_module = Keyword.fetch!(opts, :service)
    timeout_service = Keyword.get(opts, :timeout_service)

    resolve_timeout_ast =
      if timeout_service do
        quote do
          defp resolve_timeout(rpc_name, opts) do
            override = Keyword.get(opts, :timeout)
            profile = Sw4rm.TimeoutProfiles.profile_for_rpc(unquote(timeout_service), rpc_name)

            cond do
              is_nil(override) && profile ->
                Sw4rm.TimeoutProfiles.effective_timeout(profile)

              is_nil(override) ->
                Sw4rm.Constants.default_timeout_ms()

              profile ->
                Sw4rm.TimeoutProfiles.effective_timeout(profile, override)

              true ->
                override
            end
          end
        end
      else
        quote do
          defp resolve_timeout(_rpc_name, opts) do
            Keyword.get(opts, :timeout, Sw4rm.Constants.default_timeout_ms())
          end
        end
      end

    quote do
      alias Sw4rm.Transport.{ChannelManager, Retry}

      @service_module unquote(service_module)

      unquote(resolve_timeout_ast)

      @doc false
      def unary_call(endpoint, rpc_name, request, opts \\ []) do
        timeout = resolve_timeout(rpc_name, opts)
        channel_manager = Keyword.get(opts, :channel_manager, Sw4rm.Transport.ChannelManager)
        retry_opts = Keyword.get(opts, :retry, [])

        call_fn = fn ->
          with {:ok, channel} <- ChannelManager.get_channel(channel_manager, endpoint) do
            grpc_opts = [timeout: timeout]

            try do
              case apply(@service_module.Stub, rpc_name, [channel, request, grpc_opts]) do
                {:ok, response} ->
                  {:ok, response}

                {:error, %GRPC.RPCError{status: 14} = e} ->
                  {:error,
                   Sw4rm.Error.RPCUnavailable.exception(
                     message: "Service unavailable: #{inspect(e)}",
                     endpoint: endpoint
                   )}

                {:error, %GRPC.RPCError{status: 4} = e} ->
                  {:error,
                   Sw4rm.Error.RPCTimeout.exception(
                     message: "Deadline exceeded: #{inspect(e)}",
                     timeout_ms: timeout
                   )}

                {:error, reason} ->
                  {:error,
                   Sw4rm.Error.RPC.exception(
                     message: "RPC error: #{inspect(reason)}",
                     details: inspect(reason)
                   )}
              end
            rescue
              e ->
                {:error,
                 Sw4rm.Error.RPC.exception(
                   message: "RPC exception: #{Exception.message(e)}",
                   details: inspect(e)
                 )}
            end
          end
        end

        Retry.with_retry(retry_opts, call_fn)
      end

      @doc false
      def server_stream(endpoint, rpc_name, request, opts \\ []) do
        timeout = resolve_timeout(rpc_name, opts)
        channel_manager = Keyword.get(opts, :channel_manager, Sw4rm.Transport.ChannelManager)

        with {:ok, channel} <- ChannelManager.get_channel(channel_manager, endpoint) do
          grpc_opts = [timeout: timeout]

          try do
            case apply(@service_module.Stub, rpc_name, [channel, request, grpc_opts]) do
              {:ok, stream} ->
                {:ok, stream}

              {:error, reason} ->
                {:error,
                 Sw4rm.Error.RPC.exception(
                   message: "Stream error: #{inspect(reason)}",
                   details: inspect(reason)
                 )}
            end
          rescue
            e ->
              {:error,
               Sw4rm.Error.RPC.exception(
                 message: "Stream exception: #{Exception.message(e)}",
                 details: inspect(e)
               )}
          end
        end
      end
    end
  end
end
