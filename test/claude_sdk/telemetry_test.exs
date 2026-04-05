defmodule ClaudeSDK.TelemetryTest do
  use ExUnit.Case, async: false

  alias ClaudeSDK.Telemetry

  setup do
    handler_id = "telemetry-test-#{System.unique_integer([:positive])}"
    test_pid = self()

    events = [
      [:claude_sdk, :subprocess, :start],
      [:claude_sdk, :subprocess, :stop],
      [:claude_sdk, :message, :received],
      [:claude_sdk, :query, :start],
      [:claude_sdk, :query, :stop],
      [:claude_sdk, :control_request, :stop],
      [:claude_sdk, :mcp_tool, :stop],
      [:claude_sdk, :hook_callback, :stop]
    ]

    :telemetry.attach_many(
      handler_id,
      events,
      fn event, measurements, metadata, _ ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  test "subprocess_start/1 emits event with system_time and metadata" do
    Telemetry.subprocess_start(%{cli_path: "/usr/bin/claude"})

    assert_receive {:telemetry, [:claude_sdk, :subprocess, :start], %{system_time: t},
                    %{cli_path: "/usr/bin/claude"}}

    assert is_integer(t)
  end

  test "subprocess_start/0 defaults metadata to empty map" do
    Telemetry.subprocess_start()
    assert_receive {:telemetry, [:claude_sdk, :subprocess, :start], _, %{}}
  end

  test "subprocess_stop/1 emits event" do
    Telemetry.subprocess_stop(%{reason: :normal})

    assert_receive {:telemetry, [:claude_sdk, :subprocess, :stop], %{system_time: _},
                    %{reason: :normal}}
  end

  test "subprocess_stop/0 defaults metadata to empty map" do
    Telemetry.subprocess_stop()
    assert_receive {:telemetry, [:claude_sdk, :subprocess, :stop], _, %{}}
  end

  test "message_received/1 emits event" do
    Telemetry.message_received(%{type: "assistant"})

    assert_receive {:telemetry, [:claude_sdk, :message, :received], %{system_time: _},
                    %{type: "assistant"}}
  end

  test "message_received/0 defaults metadata to empty map" do
    Telemetry.message_received()
    assert_receive {:telemetry, [:claude_sdk, :message, :received], _, %{}}
  end

  test "query_start/1 emits event" do
    Telemetry.query_start()
    assert_receive {:telemetry, [:claude_sdk, :query, :start], %{system_time: _}, %{}}
  end

  test "query_stop/2 emits event with duration" do
    Telemetry.query_stop(1_234, %{foo: :bar})

    assert_receive {:telemetry, [:claude_sdk, :query, :stop], %{duration: 1_234}, %{foo: :bar}}
  end

  test "query_stop/1 defaults metadata to empty map" do
    Telemetry.query_stop(500)
    assert_receive {:telemetry, [:claude_sdk, :query, :stop], %{duration: 500}, %{}}
  end

  test "control_request_stop/2 emits event" do
    Telemetry.control_request_stop(42, %{subtype: "can_use_tool", outcome: :handled})

    assert_receive {:telemetry, [:claude_sdk, :control_request, :stop], %{duration: 42},
                    %{subtype: "can_use_tool", outcome: :handled}}
  end

  test "control_request_stop/1 defaults metadata to empty map" do
    Telemetry.control_request_stop(1)
    assert_receive {:telemetry, [:claude_sdk, :control_request, :stop], %{duration: 1}, %{}}
  end

  test "mcp_tool_stop/2 emits event" do
    Telemetry.mcp_tool_stop(7, %{server: "srv", tool: "t", outcome: :ok})

    assert_receive {:telemetry, [:claude_sdk, :mcp_tool, :stop], %{duration: 7},
                    %{server: "srv", tool: "t", outcome: :ok}}
  end

  test "mcp_tool_stop/1 defaults metadata to empty map" do
    Telemetry.mcp_tool_stop(2)
    assert_receive {:telemetry, [:claude_sdk, :mcp_tool, :stop], %{duration: 2}, %{}}
  end

  test "hook_callback_stop/2 emits event" do
    Telemetry.hook_callback_stop(9, %{event: "PreToolUse", outcome: :ok})

    assert_receive {:telemetry, [:claude_sdk, :hook_callback, :stop], %{duration: 9},
                    %{event: "PreToolUse", outcome: :ok}}
  end

  test "hook_callback_stop/1 defaults metadata to empty map" do
    Telemetry.hook_callback_stop(3)
    assert_receive {:telemetry, [:claude_sdk, :hook_callback, :stop], %{duration: 3}, %{}}
  end
end
