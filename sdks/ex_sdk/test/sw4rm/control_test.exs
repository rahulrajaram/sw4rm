defmodule Sw4rm.ControlTest do
  use ExUnit.Case, async: true

  alias Sw4rm.Control
  alias Sw4rm.Control.{SchedulerCommand, AgentReport, ReportFile}

  describe "content types" do
    test "scheduler command content type" do
      assert Control.content_type_scheduler_command() ==
               "application/vnd.sw4rm.scheduler.command+json;v=1"
    end

    test "agent report content type" do
      assert Control.content_type_agent_report() ==
               "application/vnd.sw4rm.agent.report+json;v=1"
    end
  end

  describe "SchedulerCommand" do
    test "new/2 creates command" do
      cmd = SchedulerCommand.new(:prompt, %{"task" => "analyze"})
      assert cmd.stage == :prompt
      assert cmd.input == %{"task" => "analyze"}
    end

    test "new/1 defaults input to nil" do
      cmd = SchedulerCommand.new(:run)
      assert cmd.stage == :run
      assert cmd.input == nil
    end

    test "rejects invalid stage" do
      assert_raise FunctionClauseError, fn ->
        SchedulerCommand.new(:invalid)
      end
    end

    test "to_map/1 round-trips through from_map/1" do
      cmd = SchedulerCommand.new(:plan, %{"goal" => "refactor"})
      map = SchedulerCommand.to_map(cmd)
      assert map == %{"stage" => "plan", "input" => %{"goal" => "refactor"}}

      decoded = SchedulerCommand.from_map(map)
      assert decoded.stage == :plan
      assert decoded.input == %{"goal" => "refactor"}
    end

    test "to_map omits nil input" do
      cmd = SchedulerCommand.new(:prompt)
      map = SchedulerCommand.to_map(cmd)
      refute Map.has_key?(map, "input")
    end
  end

  describe "AgentReport" do
    test "to_map/1 encodes report" do
      report = %AgentReport{
        agent_id: "agent-1",
        stage: "run",
        success: true,
        files: [%ReportFile{path: "src/main.ex", b64: "aGVsbG8="}],
        logs: "all good",
        error: nil
      }

      map = AgentReport.to_map(report)
      assert map["agent_id"] == "agent-1"
      assert map["success"] == true
      assert length(map["files"]) == 1
      assert hd(map["files"])["path"] == "src/main.ex"
      refute Map.has_key?(map, "error")
    end

    test "from_map/1 decodes report" do
      map = %{
        "agent_id" => "agent-2",
        "stage" => "plan",
        "success" => false,
        "error" => "failed to plan",
        "files" => [%{"path" => "a.ex", "b64" => "Zm9v"}]
      }

      report = AgentReport.from_map(map)
      assert report.agent_id == "agent-2"
      assert report.success == false
      assert report.error == "failed to plan"
      assert length(report.files) == 1
      assert hd(report.files).path == "a.ex"
    end

    test "from_map handles nil files" do
      report = AgentReport.from_map(%{"agent_id" => "a1"})
      assert report.files == nil
    end
  end
end
