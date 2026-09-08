defmodule Sw4rm.RouterReferenceIntegrationTest do
  use ExUnit.Case, async: false

  alias Sw4rm.Proto.Router

  @moduletag :reference_integration
  @moduletag timeout: 20_000

  # The fixture is intentionally opt-in: the normal SDK suite stays hermetic,
  # while CI or a developer with the Python SDK can prove the generated Elixir
  # bindings on the wire with SW4RM_RUN_REFERENCE_INTEGRATION=1.
  if System.get_env("SW4RM_RUN_REFERENCE_INTEGRATION") == "1" do
    test "streams seq and releases it through AckDelivery" do
      state_dir =
        Path.join(System.tmp_dir!(), "sw4rm-ex-py-router-#{System.unique_integer([:positive])}")

      File.mkdir_p!(state_dir)
      db_path = Path.join(state_dir, "router.sqlite3")
      {port, os_pid} = start_reference_router(db_path)
      grpc_target = "127.0.0.1:#{port}"
      endpoint = "http://#{grpc_target}"

      try do
        ensure_grpc_supervisor()
        {:ok, channel} = GRPC.Stub.connect(grpc_target)
        request = %Router.StreamRequest{agent_id: "consumer-1"}

        {:ok, replies} =
          Router.RouterService.Stub.stream_incoming(channel, request, timeout: 5_000)

        [{:ok, item}] = Enum.take(replies, 1)

        assert item.msg.message_id == "js-parity-message"
        assert item.msg.payload == ~s({"source":"python-reference"})
        assert is_integer(item.seq) and item.seq > 0

        {:ok, wrong_agent} =
          Router.RouterService.Stub.ack_delivery(
            channel,
            %Router.DeliveryAckRequest{
              agent_id: "other-agent",
              seq: item.seq,
              message_id: item.msg.message_id
            },
            timeout: 5_000
          )

        assert wrong_agent.recorded == false

        manager = start_channel_manager()

        {:ok, acknowledged} =
          Sw4rm.Clients.Router.ack_delivery(
            "consumer-1",
            item.seq,
            endpoint: endpoint,
            message_id: item.msg.message_id,
            channel_manager: manager
          )

        assert acknowledged.recorded == true

        {:ok, duplicate} =
          Router.RouterService.Stub.ack_delivery(
            channel,
            %Router.DeliveryAckRequest{agent_id: "consumer-1", seq: item.seq},
            timeout: 5_000
          )

        assert duplicate.recorded == false
      after
        stop_reference_router(os_pid)
        File.rm_rf(state_dir)
      end
    end
  else
    @tag skip: "set SW4RM_RUN_REFERENCE_INTEGRATION=1 to run against Python fixture"
    test "reference router integration is opt-in", do: :ok
  end

  defp start_channel_manager do
    {:ok, pid} = Sw4rm.Transport.ChannelManager.start_link(name: nil)
    pid
  end

  defp ensure_grpc_supervisor do
    {:ok, _apps} = Application.ensure_all_started(:gun)

    case Process.whereis(GRPC.Client.Supervisor) do
      nil ->
        {:ok, _pid} = GRPC.Client.Supervisor.start_link([])
        :ok

      pid when is_pid(pid) ->
        :ok
    end
  end

  defp start_reference_router(db_path) do
    repo_root = Path.expand("../../../..", __DIR__)
    python = System.get_env("SW4RM_TEST_PYTHON", "python3")
    python = System.find_executable(python) || raise "Python executable not found"
    fixture = Path.join(repo_root, "tests/sdk_parity/reference_router_server.py")

    python_path =
      [
        Path.join(repo_root, "sdks/py_sdk"),
        Path.join(repo_root, "sdks/py_sdk/reference-services/hive"),
        System.get_env("PYTHONPATH")
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(":")

    port =
      Port.open({:spawn_executable, python}, [
        :binary,
        :exit_status,
        {:args, [fixture, "--db", db_path]},
        {:env, [{~c"PYTHONPATH", String.to_charlist(python_path)}, {~c"PYTHONUNBUFFERED", ~c"1"}]}
      ])

    {ready_port, os_pid} = await_ready(port, "")
    {ready_port, os_pid}
  end

  defp await_ready(port, output) do
    receive do
      {^port, {:data, data}} ->
        combined = output <> data

        case Enum.find(String.split(combined, "\n"), &String.starts_with?(&1, "{")) do
          nil ->
            await_ready(port, combined)

          line ->
            ready = Jason.decode!(line)
            {ready["port"], port_os_pid(port)}
        end

      {^port, {:exit_status, status}} ->
        raise "reference router exited before readiness (status #{status}): #{output}"
    after
      10_000 -> raise "reference router readiness timeout: #{output}"
    end
  end

  defp port_os_pid(port) do
    {:os_pid, os_pid} = Port.info(port, :os_pid)
    os_pid
  end

  defp stop_reference_router(os_pid) do
    {_output, status} =
      System.cmd("kill", ["-TERM", Integer.to_string(os_pid)], stderr_to_stdout: true)

    assert status == 0
  end
end
