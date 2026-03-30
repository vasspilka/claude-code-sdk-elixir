defmodule ClaudeSDK.ClientAdditionalCoverageTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.Client
  alias ClaudeSDK.Types.Options

  @mock_cli_multiturn Path.expand("../support/mock_cli_multiturn.sh", __DIR__)
  @mock_cli_hang_on_control Path.expand("../support/mock_cli_hang_on_control.sh", __DIR__)

  describe "disconnect" do
    test "disconnect when already disconnected returns :ok" do
      {:ok, client} = Client.start_link(options: %Options{cli_path: @mock_cli_multiturn})

      assert :ok = Client.disconnect(client)

      Client.close(client)
    end

    test "disconnect when connected returns :ok and transitions to disconnected" do
      {:ok, client} = Client.start_link(options: %Options{cli_path: @mock_cli_multiturn})
      :ok = Client.connect(client)

      assert :ok = Client.disconnect(client)
      refute Client.connected?(client)

      Client.close(client)
    end

    @tag :capture_log
    test "disconnect when streaming returns error" do
      {:ok, client} = Client.start_link(options: %Options{cli_path: @mock_cli_multiturn})
      :ok = Client.connect(client)

      {:ok, _timeout, _gen} =
        GenServer.call(client, {:start_query, %{prompt: "test", caller: self()}})

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

  describe "reconnect after disconnect" do
    test "can reconnect after disconnecting" do
      {:ok, client} = Client.start_link(options: %Options{cli_path: @mock_cli_multiturn})
      :ok = Client.connect(client)

      messages1 = Client.query(client, "First") |> Enum.to_list()
      assert length(messages1) > 0

      :ok = Client.disconnect(client)
      refute Client.connected?(client)

      :ok = Client.connect(client)
      assert Client.connected?(client)

      messages2 = Client.query(client, "Second") |> Enum.to_list()
      assert length(messages2) > 0

      Client.close(client)
    end
  end

  describe "get_server_info" do
    test "returns error when disconnected" do
      {:ok, client} = Client.start_link(options: %Options{cli_path: @mock_cli_multiturn})

      assert {:error, :not_connected} = Client.get_server_info(client)

      Client.close(client)
    end
  end

  describe "stop_task" do
    test "returns error when not connected" do
      {:ok, client} = Client.start_link(options: %Options{cli_path: @mock_cli_multiturn})

      assert {:error, :not_connected} = Client.stop_task(client, "task-123")

      Client.close(client)
    end

    test "returns error when streaming" do
      {:ok, client} = Client.start_link(options: %Options{cli_path: @mock_cli_multiturn})
      :ok = Client.connect(client)

      {:ok, _timeout, _gen} =
        GenServer.call(client, {:start_query, %{prompt: "test", caller: self()}})

      assert {:error, :busy} = Client.stop_task(client, "task-123")

      receive do
        {:client_message, _, _} -> :ok
      after
        1000 -> :ok
      end

      GenServer.call(client, :finish_query, 5_000)
      Client.close(client)
    end

    @tag :capture_log
    test "succeeds when connected" do
      {:ok, client} = Client.start_link(options: %Options{cli_path: @mock_cli_multiturn})
      :ok = Client.connect(client)
      _messages = Client.query(client, "hello") |> Enum.to_list()

      assert :ok = Client.stop_task(client, "task-123")

      Client.close(client)
    end
  end

  describe "add_mcp_server" do
    test "returns error when not connected" do
      {:ok, client} = Client.start_link(options: %Options{cli_path: @mock_cli_multiturn})

      assert {:error, :not_connected} =
               Client.add_mcp_server(client, "srv", %{"type" => "stdio"})

      Client.close(client)
    end

    test "returns error when streaming" do
      {:ok, client} = Client.start_link(options: %Options{cli_path: @mock_cli_multiturn})
      :ok = Client.connect(client)

      {:ok, _timeout, _gen} =
        GenServer.call(client, {:start_query, %{prompt: "test", caller: self()}})

      assert {:error, :busy} = Client.add_mcp_server(client, "srv", %{})

      receive do
        {:client_message, _, _} -> :ok
      after
        1000 -> :ok
      end

      GenServer.call(client, :finish_query, 5_000)
      Client.close(client)
    end

    @tag :capture_log
    test "succeeds when connected" do
      {:ok, client} = Client.start_link(options: %Options{cli_path: @mock_cli_multiturn})
      :ok = Client.connect(client)
      _messages = Client.query(client, "hello") |> Enum.to_list()

      assert {:ok, _} = Client.add_mcp_server(client, "new-srv", %{"type" => "stdio"})

      Client.close(client)
    end
  end

  describe "remove_mcp_server" do
    test "returns error when not connected" do
      {:ok, client} = Client.start_link(options: %Options{cli_path: @mock_cli_multiturn})

      assert {:error, :not_connected} = Client.remove_mcp_server(client, "srv")

      Client.close(client)
    end

    test "returns error when streaming" do
      {:ok, client} = Client.start_link(options: %Options{cli_path: @mock_cli_multiturn})
      :ok = Client.connect(client)

      {:ok, _timeout, _gen} =
        GenServer.call(client, {:start_query, %{prompt: "test", caller: self()}})

      assert {:error, :busy} = Client.remove_mcp_server(client, "srv")

      receive do
        {:client_message, _, _} -> :ok
      after
        1000 -> :ok
      end

      GenServer.call(client, :finish_query, 5_000)
      Client.close(client)
    end

    @tag :capture_log
    test "succeeds when connected" do
      {:ok, client} = Client.start_link(options: %Options{cli_path: @mock_cli_multiturn})
      :ok = Client.connect(client)
      _messages = Client.query(client, "hello") |> Enum.to_list()

      assert {:ok, _} = Client.remove_mcp_server(client, "some-srv")

      Client.close(client)
    end
  end

  describe "connected? on dead process" do
    test "returns false when process is dead" do
      {:ok, client} = Client.start_link(options: %Options{cli_path: @mock_cli_multiturn})
      Process.unlink(client)
      Process.exit(client, :kill)
      Process.sleep(50)

      refute Client.connected?(client)
    end
  end

  describe "with_client start_link failure" do
    @tag :capture_log
    test "raises TransportError when start_link returns error" do
      # The only way start_link fails is with invalid GenServer options,
      # which is hard to trigger. But we can test the connect failure path.
      crash_init = Path.expand("../support/mock_cli_crash_on_init.sh", __DIR__)

      assert_raise ClaudeSDK.TransportError, fn ->
        Client.with_client(
          [options: %Options{cli_path: crash_init}],
          fn _client -> :ok end
        )
      end
    end
  end

  describe "stale DOWN message" do
    @tag :capture_log
    test "stale DOWN message when not streaming is ignored" do
      {:ok, client} = Client.start_link(options: %Options{cli_path: @mock_cli_multiturn})
      :ok = Client.connect(client)

      # Send a fake DOWN message with a random ref
      send(client, {:DOWN, make_ref(), :process, self(), :normal})
      Process.sleep(50)

      assert Client.connected?(client)
      Client.close(client)
    end
  end

  describe "caller death during streaming" do
    @tag :capture_log
    test "recovers to connected when stream consumer dies" do
      {:ok, client} = Client.start_link(options: %Options{cli_path: @mock_cli_hang_on_control})
      :ok = Client.connect(client)
      _messages = Client.query(client, "hello") |> Enum.to_list()

      # Start a query from a separate process that will die
      caller =
        spawn(fn ->
          {:ok, _timeout, _gen} =
            GenServer.call(client, {:start_query, %{prompt: "test", caller: self()}})

          # Wait to be killed
          receive do
            :stop -> :ok
          after
            5000 -> :ok
          end
        end)

      Process.sleep(100)
      # Kill the caller
      Process.exit(caller, :kill)
      Process.sleep(100)

      # Client should recover to connected
      assert Client.connected?(client)
      Client.close(client)
    end
  end

  describe "rewind when not connected" do
    test "returns error" do
      {:ok, client} = Client.start_link(options: %Options{cli_path: @mock_cli_multiturn})

      assert {:error, :not_connected} = Client.rewind_files(client, "msg-123")

      Client.close(client)
    end
  end

  describe "state_error coverage" do
    test "all state error mappings are exercised" do
      {:ok, client} = Client.start_link(options: %Options{cli_path: @mock_cli_multiturn})

      # :disconnected -> :not_connected
      assert {:error, :not_connected} = Client.interrupt(client)
      assert {:error, :not_connected} = Client.set_model(client, "m")
      assert {:error, :not_connected} = Client.set_permission_mode(client, :plan)
      assert {:error, :not_connected} = Client.get_mcp_status(client)
      assert {:error, :not_connected} = Client.reconnect_mcp_server(client, "s")
      assert {:error, :not_connected} = Client.toggle_mcp_server(client, "s", true)
      assert {:error, :not_connected} = Client.add_mcp_server(client, "s", %{})
      assert {:error, :not_connected} = Client.remove_mcp_server(client, "s")
      assert {:error, :not_connected} = Client.stop_task(client, "t")

      :ok = Client.connect(client)

      # :connected -> :not_streaming (for interrupt)
      assert {:error, :not_streaming} = Client.interrupt(client)

      Client.close(client)
    end
  end

  describe "notify_caller_of_exit with pid caller during streaming" do
    @tag :capture_log
    test "notifies pid caller when CLI exits during streaming" do
      {:ok, client} =
        Client.start_link(options: %Options{cli_path: @mock_cli_hang_on_control})

      :ok = Client.connect(client)
      _messages = Client.query(client, "hello") |> Enum.to_list()

      {:ok, _timeout, _gen} =
        GenServer.call(client, {:start_query, %{prompt: "test", caller: self()}})

      # claude_exit should notify the PID caller
      send(client, {:claude_exit, {:error, :test}})

      assert_receive {:client_exit, _gen, {:error, :test}}, 1000

      Client.close(client)
    end
  end

  describe "with_client close rescue path" do
    @tag :capture_log
    test "close rescue catches exceptions during cleanup" do
      # Exercise the rescue branch in with_client's after block.
      # Kill the client during the callback so close raises.
      result =
        Client.with_client(
          [options: %Options{cli_path: @mock_cli_multiturn}],
          fn client ->
            Process.unlink(client)
            Process.exit(client, :kill)
            Process.sleep(50)
            :done
          end
        )

      assert result == :done
    end
  end

  describe "stale control_response during awaiting_rewind" do
    @tag :capture_log
    test "discards stale response with mismatched request_id during rewind" do
      {:ok, client} = Client.start_link(options: %Options{cli_path: @mock_cli_hang_on_control})
      :ok = Client.connect(client)
      _messages = Client.query(client, "hello") |> Enum.to_list()

      task = Task.async(fn -> Client.rewind_files(client, "msg-stale") end)
      Process.sleep(100)

      # Send stale response with wrong request_id while in awaiting_rewind
      send(
        client,
        {:claude_message,
         %{
           "type" => "control_response",
           "request_id" => "wrong-req-id",
           "response" => %{"success" => true}
         }}
      )

      Process.sleep(50)

      # Now send correct response (without request_id for backwards compat)
      send(
        client,
        {:claude_message, %{"type" => "control_response", "response" => %{"success" => true}}}
      )

      assert :ok = Task.await(task)
      Client.close(client)
    end
  end

  describe "connect with generic transport error (not CLINotFoundError)" do
    @tag :capture_log
    test "connect returns error for generic transport failure" do
      # The mock_cli_crash_on_init exits with code 1, which gives a ProcessExitError
      crash_init = Path.expand("../support/mock_cli_crash_on_init.sh", __DIR__)
      opts = %Options{cli_path: crash_init}
      {:ok, client} = Client.start_link(options: opts)

      assert {:error, %ClaudeSDK.ProcessExitError{}} = Client.connect(client)

      Client.close(client)
    end
  end

  describe "disconnect when in awaiting_rewind state" do
    @tag :capture_log
    test "returns busy error when awaiting rewind" do
      {:ok, client} = Client.start_link(options: %Options{cli_path: @mock_cli_hang_on_control})
      :ok = Client.connect(client)
      _messages = Client.query(client, "hello") |> Enum.to_list()

      # Start rewind (will hang)
      task = Task.async(fn -> Client.rewind_files(client, "msg-test") end)
      Process.sleep(100)

      # Try to disconnect while awaiting rewind
      assert {:error, :busy} = Client.disconnect(client)

      # Clean up: send timeout to unblock
      send(client, :control_timeout)
      Task.await(task, 5000)

      Client.close(client)
    end
  end

  describe "disconnect when in awaiting_control_response state" do
    @tag :capture_log
    test "returns busy error when awaiting control response" do
      {:ok, client} = Client.start_link(options: %Options{cli_path: @mock_cli_hang_on_control})
      :ok = Client.connect(client)
      _messages = Client.query(client, "hello") |> Enum.to_list()

      # Start MCP status check (will hang)
      task = Task.async(fn -> Client.get_mcp_status(client) end)
      Process.sleep(100)

      # Try to disconnect while awaiting control response
      assert {:error, :busy} = Client.disconnect(client)

      # Clean up
      send(client, :control_timeout)
      Task.await(task, 5000)

      Client.close(client)
    end
  end

  describe "set_model when awaiting_rewind" do
    @tag :capture_log
    test "returns busy error" do
      {:ok, client} = Client.start_link(options: %Options{cli_path: @mock_cli_hang_on_control})
      :ok = Client.connect(client)
      _messages = Client.query(client, "hello") |> Enum.to_list()

      task = Task.async(fn -> Client.rewind_files(client, "msg-test") end)
      Process.sleep(100)

      assert {:error, :busy} = Client.set_model(client, "m")

      send(client, :control_timeout)
      Task.await(task, 5000)

      Client.close(client)
    end
  end
end
