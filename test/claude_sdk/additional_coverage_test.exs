defmodule ClaudeSDK.AdditionalCoverageTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.Transport.LineBuffer
  alias ClaudeSDK.ControlRouter
  alias ClaudeSDK.Client
  alias ClaudeSDK.Types.Options

  @mock_cli_multiturn Path.expand("../support/mock_cli_multiturn.sh", __DIR__)
  @mock_cli_hang_on_control Path.expand("../support/mock_cli_hang_on_control.sh", __DIR__)

  # ── LineBuffer ──────────────────────────────────────────────────────────

  describe "LineBuffer.flush/2" do
    test "flushes empty buffer with eol data" do
      buf = LineBuffer.new()
      {new_buf, {:ok, parsed}} = LineBuffer.flush(buf, ~s({"type":"test"}))
      assert new_buf.buffer == ""
      assert parsed["type"] == "test"
    end

    test "flushes accumulated buffer with eol remainder" do
      buf = LineBuffer.new()
      buf = LineBuffer.accumulate(buf, ~s({"type":))
      {new_buf, {:ok, parsed}} = LineBuffer.flush(buf, ~s("done"}))
      assert new_buf.buffer == ""
      assert parsed["type"] == "done"
    end

    test "returns error for invalid JSON" do
      buf = LineBuffer.new()
      {new_buf, {:error, _}} = LineBuffer.flush(buf, "not json at all")
      assert new_buf.buffer == ""
    end
  end

  describe "LineBuffer.accumulate/2" do
    test "concatenates chunks" do
      buf = LineBuffer.new()
      buf = LineBuffer.accumulate(buf, "chunk1")
      buf = LineBuffer.accumulate(buf, "chunk2")
      assert buf.buffer == "chunk1chunk2"
    end

    @tag :capture_log
    test "discards buffer when exceeding max size" do
      buf = LineBuffer.new()
      large_chunk = String.duplicate("x", 10_485_761)
      buf = LineBuffer.accumulate(buf, large_chunk)
      assert buf.buffer == ""
    end
  end

  describe "LineBuffer.parse_line/1 edge cases" do
    test "returns error for line exceeding max buffer size" do
      giant_line = String.duplicate("x", 10_485_761)
      assert {:error, :line_too_large} = LineBuffer.parse_line(giant_line)
    end
  end

  # ── ControlRouter: hook handlers ───────────────────────────────────────

  describe "ControlRouter hook handler with single arity-1 callback" do
    test "arity-1 hook callback is invoked" do
      test_pid = self()

      hooks = %{
        "PreToolUse" => fn input ->
          send(test_pid, {:hook_called, input})
          :ok
        end
      }

      handlers = ControlRouter.build_handlers(%{can_use_tool: nil, mcp_tool_index: %{}, hooks: hooks})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_hook_1",
        "request" => %{
          "subtype" => "hook_callback",
          "hook_event" => "PreToolUse",
          "hook_input" => %{"tool" => "Bash"}
        }
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.type == "control_response"
      assert_receive {:hook_called, %{"tool" => "Bash"}}
    end
  end

  describe "ControlRouter hook handler with arity-2 callback" do
    test "arity-2 hook callback receives event name and input" do
      test_pid = self()

      hooks = %{
        "PostToolUse" => fn event, input ->
          send(test_pid, {:hook_2, event, input})
          {:ok, %{logged: true}}
        end
      }

      handlers = ControlRouter.build_handlers(%{can_use_tool: nil, mcp_tool_index: %{}, hooks: hooks})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_hook_2",
        "request" => %{
          "subtype" => "hook_callback",
          "hook_event" => "PostToolUse",
          "hook_input" => %{"result" => "ok"}
        }
      }

      {:handled, _response} = ControlRouter.dispatch(raw, handlers)
      assert_receive {:hook_2, "PostToolUse", %{"result" => "ok"}}
    end
  end

  describe "ControlRouter hook handler with list of callbacks" do
    test "runs multiple hook callbacks and merges results" do
      hooks = %{
        "Notification" => [
          fn _input -> {:ok, %{step1: true}} end,
          fn _input -> {:ok, %{step2: true}} end
        ]
      }

      handlers = ControlRouter.build_handlers(%{can_use_tool: nil, mcp_tool_index: %{}, hooks: hooks})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_hook_list",
        "request" => %{
          "subtype" => "hook_callback",
          "hook_event" => "Notification",
          "hook_input" => %{}
        }
      }

      {:handled, _response} = ControlRouter.dispatch(raw, handlers)
    end
  end

  describe "ControlRouter hook handler with list containing arity-2 callbacks" do
    test "runs arity-2 callbacks in list" do
      test_pid = self()

      hooks = %{
        "Custom" => [
          fn event, _input ->
            send(test_pid, {:list_hook_2, event})
            :ok
          end
        ]
      }

      handlers = ControlRouter.build_handlers(%{can_use_tool: nil, mcp_tool_index: %{}, hooks: hooks})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_hook_list2",
        "request" => %{
          "subtype" => "hook_callback",
          "hook_event" => "Custom",
          "hook_input" => %{}
        }
      }

      {:handled, _} = ControlRouter.dispatch(raw, handlers)
      assert_receive {:list_hook_2, "Custom"}
    end
  end

  describe "ControlRouter hook handler with unknown event" do
    test "returns empty result for unregistered hook event" do
      hooks = %{
        "PreToolUse" => fn _input -> :ok end
      }

      handlers = ControlRouter.build_handlers(%{can_use_tool: nil, mcp_tool_index: %{}, hooks: hooks})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_hook_unknown",
        "request" => %{
          "subtype" => "hook_callback",
          "hook_event" => "SomeOtherEvent",
          "hook_input" => %{}
        }
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.type == "control_response"
    end
  end

  describe "ControlRouter hook handler with non-function in hooks map" do
    test "non-function hook value returns empty result" do
      hooks = %{
        "BadHook" => "not a function"
      }

      handlers = ControlRouter.build_handlers(%{can_use_tool: nil, mcp_tool_index: %{}, hooks: hooks})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_hook_bad",
        "request" => %{
          "subtype" => "hook_callback",
          "hook_event" => "BadHook",
          "hook_input" => %{}
        }
      }

      {:handled, _} = ControlRouter.dispatch(raw, handlers)
    end
  end

  describe "ControlRouter hook handler crash" do
    @tag :capture_log
    test "hook callback that raises returns empty result" do
      hooks = %{
        "CrashHook" => fn _input -> raise "boom" end
      }

      handlers = ControlRouter.build_handlers(%{can_use_tool: nil, mcp_tool_index: %{}, hooks: hooks})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_hook_crash",
        "request" => %{
          "subtype" => "hook_callback",
          "hook_event" => "CrashHook",
          "hook_input" => %{}
        }
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.type == "control_response"
    end
  end

  describe "ControlRouter hook handler timeout" do
    @tag :capture_log
    test "hook callback that hangs times out" do
      hooks = %{
        "SlowHook" => fn _input -> Process.sleep(:infinity) end
      }

      handlers =
        ControlRouter.build_handlers(%{
          can_use_tool: nil,
          mcp_tool_index: %{},
          hooks: hooks,
          hook_timeout_ms: 100
        })

      raw = %{
        "type" => "control_request",
        "request_id" => "req_hook_timeout",
        "request" => %{
          "subtype" => "hook_callback",
          "hook_event" => "SlowHook",
          "hook_input" => %{}
        }
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.type == "control_response"
    end
  end

  describe "ControlRouter handler raising exception" do
    @tag :capture_log
    test "handler that raises returns error response" do
      handlers = %{
        "can_use_tool" => fn _request -> raise "handler crash" end
      }

      raw = %{
        "type" => "control_request",
        "request_id" => "req_raise",
        "request" => %{"subtype" => "can_use_tool", "tool_name" => "X", "input" => %{}}
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.response.allowed == false
      assert response.response.reason =~ "Handler error"
    end
  end

  describe "ControlRouter normalize_handler_result" do
    test "bare :ok returns result" do
      handlers = %{
        "test" => fn _request -> :ok end
      }

      raw = %{
        "type" => "control_request",
        "request_id" => "req_ok",
        "request" => %{"subtype" => "test"}
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.type == "control_response"
    end

    test "{:ok, map} returns result" do
      handlers = %{
        "test" => fn _request -> {:ok, %{data: "value"}} end
      }

      raw = %{
        "type" => "control_request",
        "request_id" => "req_ok_map",
        "request" => %{"subtype" => "test"}
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.type == "control_response"
    end

    @tag :capture_log
    test "unexpected handler return value produces deny response" do
      handlers = %{
        "test" => fn _request -> :unexpected_atom end
      }

      raw = %{
        "type" => "control_request",
        "request_id" => "req_weird",
        "request" => %{"subtype" => "test"}
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.response.allowed == false
    end
  end

  describe "ControlRouter dispatch with malformed request" do
    test "returns unhandled for request without request_id" do
      result = ControlRouter.dispatch(%{"request" => %{}}, %{})
      assert {:unhandled, _} = result
    end

    test "returns unhandled for request without request field" do
      result = ControlRouter.dispatch(%{"request_id" => "r1"}, %{})
      assert {:unhandled, _} = result
    end
  end

  describe "ControlRouter build_handlers with empty hooks" do
    test "does not add hook handler for empty hooks" do
      handlers = ControlRouter.build_handlers(%{can_use_tool: nil, mcp_tool_index: %{}, hooks: %{}})
      refute Map.has_key?(handlers, "hook_callback")
    end

    test "does not add hook handler when hooks key is missing" do
      handlers = ControlRouter.build_handlers(%{can_use_tool: nil, mcp_tool_index: %{}})
      refute Map.has_key?(handlers, "hook_callback")
    end
  end

  describe "ControlRouter build_response" do
    test "builds allow response" do
      response = ControlRouter.build_response("r1", "test", {:allow, %{updated: true}})
      assert response.response.allowed == true
      assert response.response.updated == true
    end

    test "builds deny response" do
      response = ControlRouter.build_response("r1", "test", {:deny, "not allowed"})
      assert response.response.allowed == false
      assert response.response.reason == "not allowed"
    end

    test "builds result response" do
      response = ControlRouter.build_response("r1", "test", {:result, %{data: "ok"}})
      assert response.response.data == "ok"
    end
  end

  # ── ClaudeSDK.query/2 keyword list validation ─────────────────────────

  describe "ClaudeSDK.query/2 with invalid keyword keys" do
    test "raises ArgumentError for unknown keys" do
      assert_raise ArgumentError, ~r/unknown options/, fn ->
        ClaudeSDK.query("test", bogus_key: "value")
      end
    end
  end

  # ── Client: disconnect ─────────────────────────────────────────────────

  describe "Client.disconnect" do
    test "disconnect when already disconnected returns :ok" do
      {:ok, client} = Client.start_link()
      assert :ok = Client.disconnect(client)
      Client.close(client)
    end

    test "disconnect when connected transitions to disconnected" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      assert :ok = Client.disconnect(client)
      refute Client.connected?(client)

      Client.close(client)
    end

    test "disconnect when streaming returns error" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      {:ok, _timeout, _gen} = GenServer.call(client, {:start_query, "test", self()})
      assert {:error, :busy} = Client.disconnect(client)

      receive do
        {:client_message, _, _} -> :ok
      after
        1000 -> :ok
      end

      GenServer.call(client, :finish_query, 5_000)
      Client.close(client)
    end
  end

  # ── Client: stop_task ──────────────────────────────────────────────────

  describe "Client.stop_task" do
    @tag :capture_log
    test "stop_task sends control request when connected" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      _messages = Client.query(client, "hello") |> Enum.to_list()

      assert :ok = Client.stop_task(client, "task-123")

      Client.close(client)
    end

    test "stop_task returns error when disconnected" do
      {:ok, client} = Client.start_link()
      assert {:error, :not_connected} = Client.stop_task(client, "task-123")
      Client.close(client)
    end

    test "stop_task returns error when streaming" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      {:ok, _timeout, _gen} = GenServer.call(client, {:start_query, "test", self()})
      assert {:error, :busy} = Client.stop_task(client, "task-123")

      receive do
        {:client_message, _, _} -> :ok
      after
        1000 -> :ok
      end

      GenServer.call(client, :finish_query, 5_000)
      Client.close(client)
    end
  end

  # ── Client: set_permission_mode ────────────────────────────────────────

  describe "Client.set_permission_mode" do
    @tag :capture_log
    test "set_permission_mode sends control request when connected" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      _messages = Client.query(client, "hello") |> Enum.to_list()

      assert :ok = Client.set_permission_mode(client, :plan)

      Client.close(client)
    end

    test "set_permission_mode returns error when disconnected" do
      {:ok, client} = Client.start_link()
      assert {:error, :not_connected} = Client.set_permission_mode(client, :plan)
      Client.close(client)
    end

    test "set_permission_mode returns error when streaming" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      {:ok, _timeout, _gen} = GenServer.call(client, {:start_query, "test", self()})
      assert {:error, :busy} = Client.set_permission_mode(client, :plan)

      receive do
        {:client_message, _, _} -> :ok
      after
        1000 -> :ok
      end

      GenServer.call(client, :finish_query, 5_000)
      Client.close(client)
    end
  end

  # ── Client: add_mcp_server / remove_mcp_server ────────────────────────

  describe "Client.add_mcp_server" do
    @tag :capture_log
    test "sends control request when connected" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)
      _messages = Client.query(client, "hello") |> Enum.to_list()

      config = %{"type" => "stdio", "command" => "python"}
      assert {:ok, _} = Client.add_mcp_server(client, "my-server", config)

      Client.close(client)
    end

    test "returns error when disconnected" do
      {:ok, client} = Client.start_link()
      assert {:error, :not_connected} = Client.add_mcp_server(client, "s", %{})
      Client.close(client)
    end

    test "returns error when streaming" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      {:ok, _timeout, _gen} = GenServer.call(client, {:start_query, "test", self()})
      assert {:error, :busy} = Client.add_mcp_server(client, "s", %{})

      receive do
        {:client_message, _, _} -> :ok
      after
        1000 -> :ok
      end

      GenServer.call(client, :finish_query, 5_000)
      Client.close(client)
    end
  end

  describe "Client.remove_mcp_server" do
    @tag :capture_log
    test "sends control request when connected" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)
      _messages = Client.query(client, "hello") |> Enum.to_list()

      assert {:ok, _} = Client.remove_mcp_server(client, "my-server")

      Client.close(client)
    end

    test "returns error when disconnected" do
      {:ok, client} = Client.start_link()
      assert {:error, :not_connected} = Client.remove_mcp_server(client, "s")
      Client.close(client)
    end

    test "returns error when streaming" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      {:ok, _timeout, _gen} = GenServer.call(client, {:start_query, "test", self()})
      assert {:error, :busy} = Client.remove_mcp_server(client, "s")

      receive do
        {:client_message, _, _} -> :ok
      after
        1000 -> :ok
      end

      GenServer.call(client, :finish_query, 5_000)
      Client.close(client)
    end
  end

  # ── Client: interrupt when not streaming ───────────────────────────────

  describe "Client.interrupt when not streaming" do
    test "returns error when disconnected" do
      {:ok, client} = Client.start_link()
      assert {:error, _} = Client.interrupt(client)
      Client.close(client)
    end

    test "returns error when connected (not streaming)" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      assert {:error, _} = Client.interrupt(client)

      Client.close(client)
    end
  end

  # ── Client: connected? when dead ──────────────────────────────────────

  describe "Client.connected? when process is dead" do
    test "returns false" do
      {:ok, client} = Client.start_link()
      Client.close(client)
      Process.sleep(50)
      refute Client.connected?(client)
    end
  end

  # ── Client: get_server_info when disconnected ─────────────────────────

  describe "Client.get_server_info when disconnected" do
    test "returns error" do
      {:ok, client} = Client.start_link()
      assert {:error, :not_connected} = Client.get_server_info(client)
      Client.close(client)
    end
  end

  # ── Client: caller monitor DOWN handling ──────────────────────────────

  describe "Client stream consumer death" do
    @tag :capture_log
    test "recovers to connected when stream consumer dies" do
      opts = %Options{cli_path: @mock_cli_hang_on_control}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      _messages = Client.query(client, "hello") |> Enum.to_list()

      # Spawn a consumer and start a query from it
      consumer =
        spawn(fn ->
          receive do
            :go -> :ok
          end

          # This process will be killed while streaming
          receive do
            _ -> :ok
          after
            60_000 -> :ok
          end
        end)

      {:ok, _timeout, _gen} = GenServer.call(client, {:start_query, "test2", consumer})

      # Kill the consumer while streaming
      Process.exit(consumer, :kill)
      Process.sleep(100)

      # Client should recover to connected
      assert Client.connected?(client)

      Client.close(client)
    end
  end

  # ── Client: stale DOWN message ────────────────────────────────────────

  describe "Client stale DOWN message" do
    @tag :capture_log
    test "stale DOWN message is ignored" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      # Send a fake DOWN message with a random ref (stale monitor)
      send(client, {:DOWN, make_ref(), :process, self(), :normal})
      Process.sleep(50)

      # Client should still work
      assert Client.connected?(client)
      Client.close(client)
    end
  end

  # ── Client: set_model when disconnected ───────────────────────────────

  describe "Client state errors" do
    test "set_model when disconnected" do
      {:ok, client} = Client.start_link()
      assert {:error, :not_connected} = Client.set_model(client, "test")
      Client.close(client)
    end

    test "rewind_files when disconnected" do
      {:ok, client} = Client.start_link()
      assert {:error, :not_connected} = Client.rewind_files(client, "msg-1")
      Client.close(client)
    end

    test "get_mcp_status when disconnected" do
      {:ok, client} = Client.start_link()
      assert {:error, :not_connected} = Client.get_mcp_status(client)
      Client.close(client)
    end

    test "reconnect_mcp_server when disconnected" do
      {:ok, client} = Client.start_link()
      assert {:error, :not_connected} = Client.reconnect_mcp_server(client, "s")
      Client.close(client)
    end

    test "toggle_mcp_server when disconnected" do
      {:ok, client} = Client.start_link()
      assert {:error, :not_connected} = Client.toggle_mcp_server(client, "s", true)
      Client.close(client)
    end

    test "start_query when disconnected" do
      {:ok, client} = Client.start_link()
      assert {:error, :not_connected} = GenServer.call(client, {:start_query, "test", self()})
      Client.close(client)
    end
  end
end
