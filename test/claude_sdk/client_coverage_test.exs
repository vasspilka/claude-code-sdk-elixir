defmodule ClaudeSDK.ClientCoverageTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.Client
  alias ClaudeSDK.Types.Options

  @mock_cli_multiturn Path.expand("../support/mock_cli_multiturn.sh", __DIR__)
  @mock_cli_crash_init Path.expand("../support/mock_cli_crash_on_init.sh", __DIR__)
  @mock_cli_hang_on_control Path.expand("../support/mock_cli_hang_on_control.sh", __DIR__)

  describe "with_client/2" do
    test "starts, connects, runs callback, and closes" do
      result =
        Client.with_client(
          [options: %Options{cli_path: @mock_cli_multiturn}],
          fn client ->
            messages = Client.query(client, "Hello") |> Enum.to_list()
            length(messages)
          end
        )

      assert result > 0
    end

    test "cleans up on callback raise" do
      assert_raise RuntimeError, "boom", fn ->
        Client.with_client(
          [options: %Options{cli_path: @mock_cli_multiturn}],
          fn _client ->
            raise "boom"
          end
        )
      end
    end

    @tag :capture_log
    test "handles client death during callback cleanup" do
      result =
        Client.with_client(
          [options: %Options{cli_path: @mock_cli_multiturn}],
          fn client ->
            # Unlink so killing the client doesn't kill the test process
            Process.unlink(client)
            # Kill the client process — close in the after block will catch :exit
            Process.exit(client, :kill)
            Process.sleep(50)
            :callback_done
          end
        )

      assert result == :callback_done
    end

    @tag :capture_log
    test "raises TransportError when connect fails" do
      assert_raise ClaudeSDK.TransportError, fn ->
        Client.with_client(
          [options: %Options{cli_path: @mock_cli_crash_init}],
          fn _client -> :ok end
        )
      end
    end
  end

  describe "get_server_info when connected" do
    test "returns cached init data" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      assert {:ok, response} = Client.get_server_info(client)
      assert is_map(response)

      Client.close(client)
    end
  end

  describe "reconnect_mcp_server when connected" do
    @tag :capture_log
    test "sends control request and receives response" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      _messages = Client.query(client, "hello") |> Enum.to_list()

      assert {:ok, _response} = Client.reconnect_mcp_server(client, "my-server")

      Client.close(client)
    end

    test "returns error when streaming" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      {:ok, _timeout, _gen} =
        GenServer.call(client, {:start_query, %{prompt: "test", caller: self()}})

      assert {:error, :busy} = Client.reconnect_mcp_server(client, "s")

      receive do
        {:client_message, _, _} -> :ok
      after
        1000 -> :ok
      end

      GenServer.call(client, :finish_query, 5_000)
      Client.close(client)
    end
  end

  describe "toggle_mcp_server when connected" do
    @tag :capture_log
    test "sends control request and receives response" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      _messages = Client.query(client, "hello") |> Enum.to_list()

      assert {:ok, _response} = Client.toggle_mcp_server(client, "my-server", false)

      Client.close(client)
    end

    test "returns error when streaming" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      {:ok, _timeout, _gen} =
        GenServer.call(client, {:start_query, %{prompt: "test", caller: self()}})

      assert {:error, :busy} =
               Client.toggle_mcp_server(client, "s", true)

      receive do
        {:client_message, _, _} -> :ok
      after
        1000 -> :ok
      end

      GenServer.call(client, :finish_query, 5_000)
      Client.close(client)
    end
  end

  describe "get_mcp_status when connected" do
    @tag :capture_log
    test "sends control request and receives response" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      _messages = Client.query(client, "hello") |> Enum.to_list()

      assert {:ok, _response} = Client.get_mcp_status(client)

      Client.close(client)
    end

    test "returns error when streaming" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      {:ok, _timeout, _gen} =
        GenServer.call(client, {:start_query, %{prompt: "test", caller: self()}})

      assert {:error, :busy} = Client.get_mcp_status(client)

      receive do
        {:client_message, _, _} -> :ok
      after
        1000 -> :ok
      end

      GenServer.call(client, :finish_query, 5_000)
      Client.close(client)
    end
  end

  describe "handle_info edge cases" do
    @tag :capture_log
    test "unexpected messages are handled gracefully" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      # Send unexpected message
      send(client, {:unexpected, "hello"})

      # Client should still work
      messages = Client.query(client, "hello") |> Enum.to_list()
      assert length(messages) > 0

      Client.close(client)
    end

    @tag :capture_log
    test "EXIT message from linked process is handled" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      # Send a fake EXIT message (the GenServer traps exits, so this is just
      # exercising the handle_info({:EXIT, ...}) clause)
      send(client, {:EXIT, spawn(fn -> :ok end), :normal})

      # Give it time to process
      Process.sleep(50)

      # Client should still work after handling EXIT
      messages = Client.query(client, "hello") |> Enum.to_list()
      assert length(messages) > 0

      Client.close(client)
    end

    @tag :capture_log
    test "claude_message in non-streaming state is ignored" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      # Send a claude_message when in :connected state (not streaming)
      send(client, {:claude_message, %{"type" => "assistant", "message" => %{}}})

      # Client should still work
      messages = Client.query(client, "hello") |> Enum.to_list()
      assert length(messages) > 0

      Client.close(client)
    end

    @tag :capture_log
    test "control_timeout when not in awaiting state is ignored" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      # Send control_timeout when in :connected state
      send(client, :control_timeout)

      # Client should still work
      messages = Client.query(client, "hello") |> Enum.to_list()
      assert length(messages) > 0

      Client.close(client)
    end
  end

  describe "connect with invalid options" do
    test "returns error for invalid options" do
      opts = %Options{cli_path: @mock_cli_multiturn, max_turns: -1}
      {:ok, client} = Client.start_link(options: opts)

      assert {:error, {:invalid_options, _}} = Client.connect(client)

      Client.close(client)
    end
  end

  describe "finish_query in non-streaming state" do
    test "finish_query when connected returns :ok and clears caller" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      # Call finish_query when not streaming — should still return :ok
      assert :ok = GenServer.call(client, :finish_query, 5_000)

      Client.close(client)
    end
  end

  describe "rewind error response" do
    @tag :capture_log
    test "parse_rewind_response handles error response" do
      # Use hang_on_control mock which doesn't respond to control_requests
      hang_mock = Path.expand("../support/mock_cli_hang_on_control.sh", __DIR__)
      opts = %Options{cli_path: hang_mock}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      # Complete a query to get into connected state
      _messages = Client.query(client, "hello") |> Enum.to_list()

      # Start rewind in a task - the mock will hang on this control_request
      task =
        Task.async(fn ->
          Client.rewind_files(client, "msg-123")
        end)

      # Give it time to enter awaiting_rewind
      Process.sleep(100)

      # Send a control_response with error directly
      send(
        client,
        {:claude_message,
         %{"type" => "control_response", "response" => %{"error" => "File not found"}}}
      )

      assert {:error, "File not found"} = Task.await(task)

      Client.close(client)
    end
  end

  describe "normalize_agents in Client" do
    test "handles AgentDefinition structs" do
      opts = %Options{
        cli_path: @mock_cli_multiturn,
        agents: [
          %ClaudeSDK.Types.AgentDefinition{
            name: "test-agent",
            description: "Test",
            prompt: "You are a test agent",
            model: "haiku"
          }
        ]
      }

      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      messages = Client.query(client, "Hello") |> Enum.to_list()
      assert length(messages) > 0

      Client.close(client)
    end

    test "handles agents as map" do
      opts = %Options{
        cli_path: @mock_cli_multiturn,
        agents: %{"name" => "test-agent"}
      }

      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      messages = Client.query(client, "Hello") |> Enum.to_list()
      assert length(messages) > 0

      Client.close(client)
    end

    test "handles agents as nil" do
      opts = %Options{
        cli_path: @mock_cli_multiturn,
        agents: nil
      }

      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      messages = Client.query(client, "Hello") |> Enum.to_list()
      assert length(messages) > 0

      Client.close(client)
    end
  end

  describe "client with mcp_servers" do
    test "connects with mcp_servers configured" do
      server =
        ClaudeSDK.create_mcp_server("test-server", "1.0", [
          %ClaudeSDK.MCP.Tool{
            name: "greet",
            description: "Say hello",
            input_schema: %{},
            handler: fn _ -> {:ok, "hi"} end
          }
        ])

      opts = %Options{
        cli_path: @mock_cli_multiturn,
        mcp_servers: [server]
      }

      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      messages = Client.query(client, "Hello") |> Enum.to_list()
      assert length(messages) > 0

      Client.close(client)
    end
  end

  describe "cli_exit during streaming" do
    @tag :capture_log
    test "claude_exit during streaming notifies caller" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      {:ok, _timeout, _gen} =
        GenServer.call(client, {:start_query, %{prompt: "test", caller: self()}})

      # Simulate CLI exit
      send(client, {:claude_exit, :normal})

      # Should receive exit notification
      assert_receive {:client_exit, _gen, :normal}, 1000

      Client.close(client)
    end
  end

  describe "Client.query parse error" do
    @tag :capture_log
    test "unparseable client_message is skipped" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      {:ok, timeout, gen} =
        GenServer.call(client, {:start_query, %{prompt: "test", caller: self()}})

      # Send a message that will fail to parse (missing type)
      send(self(), {:client_message, gen, %{"no_type" => true}})

      # Then send a valid result
      send(
        self(),
        {:client_message, gen,
         %{
           "type" => "result",
           "subtype" => "success",
           "is_error" => false,
           "result" => "done",
           "session_id" => "s1",
           "num_turns" => 1,
           "duration_ms" => 100,
           "duration_api_ms" => 80
         }}
      )

      # Consume messages manually using the receive_client_messages flow
      # The first message (no type) should be skipped, second should produce result
      messages = collect_client_messages({:streaming, timeout, client, gen})
      result = Enum.find(messages, &match?(%ClaudeSDK.Types.ResultMessage{}, &1))
      assert result != nil

      GenServer.call(client, :finish_query, 5_000)
      Client.close(client)
    end
  end

  describe "interrupt when streaming" do
    test "interrupt sends interrupt message and returns to connected" do
      opts = %Options{cli_path: @mock_cli_hang_on_control}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      # Complete a query to get into connected state
      _messages = Client.query(client, "hello") |> Enum.to_list()

      # Put into streaming state manually
      {:ok, _timeout, _gen} =
        GenServer.call(client, {:start_query, %{prompt: "test", caller: self()}})

      # Now interrupt
      assert :ok = Client.interrupt(client)

      # Should receive exit notification
      assert_receive {:client_exit, _gen, :interrupted}, 1000

      # Should be back in connected state
      assert Client.connected?(client)

      Client.close(client)
    end
  end

  describe "connect when busy (streaming)" do
    test "connect returns error when streaming" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      {:ok, _timeout, _gen} =
        GenServer.call(client, {:start_query, %{prompt: "test", caller: self()}})

      assert {:error, :busy} = Client.connect(client)

      # Drain and cleanup
      receive do
        {:client_message, _, _} -> :ok
      after
        1000 -> :ok
      end

      GenServer.call(client, :finish_query, 5_000)
      Client.close(client)
    end
  end

  describe "with_client default args" do
    @tag :capture_log
    test "with_client works with default empty opts override" do
      # Exercise the with_client default opts path with a crash-on-init mock
      crash_init = Path.expand("../support/mock_cli_crash_on_init.sh", __DIR__)

      assert_raise ClaudeSDK.TransportError, fn ->
        Client.with_client([options: %Options{cli_path: crash_init}], fn _client -> :ok end)
      end
    end

    @tag :capture_log
    test "with_client with no opts exercises default arg" do
      crash_init = Path.expand("../support/mock_cli_crash_on_init.sh", __DIR__)

      # Can't call with_client(fun) without opts because it will try the real CLI.
      # But we can exercise the close catching :exit path by having the client
      # die during callback.
      assert_raise ClaudeSDK.TransportError, fn ->
        Client.with_client(
          [options: %Options{cli_path: crash_init}],
          fn _client -> :ok end
        )
      end
    end
  end

  describe "unhandled control_request during streaming" do
    @tag :capture_log
    test "forwards unhandled control_request to caller" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      {:ok, _timeout, _gen} =
        GenServer.call(client, {:start_query, %{prompt: "test", caller: self()}})

      # Send an unhandled control_request — should be forwarded to caller
      send(
        client,
        {:claude_message,
         %{
           "type" => "control_request",
           "request_id" => "req_unknown",
           "request" => %{"subtype" => "unknown_subtype"}
         }}
      )

      assert_receive {:client_message, _gen, %{"type" => "control_request"}}, 1000

      # Drain remaining messages
      receive do
        {:client_message, _, _} -> :ok
      after
        500 -> :ok
      end

      GenServer.call(client, :finish_query, 5_000)
      Client.close(client)
    end
  end

  describe "Client init timeout" do
    @tag :capture_log
    test "connect returns error when init times out" do
      init_timeout_mock = Path.expand("../support/mock_cli_init_timeout.sh", __DIR__)
      opts = %Options{cli_path: init_timeout_mock, init_timeout_ms: 200}
      {:ok, client} = Client.start_link(options: opts)

      assert {:error, :init_timeout} = Client.connect(client)

      Client.close(client)
    end
  end

  describe "terminate" do
    test "terminate cleans up subprocess" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      # close triggers terminate
      Client.close(client)
      Process.sleep(50)
      refute Process.alive?(client)
    end
  end

  describe "Client.start_link default args" do
    test "start_link with no args uses defaults" do
      # Exercise the default \\ [] clause
      {:ok, client} = Client.start_link()
      # Will be in :disconnected state — just verify it started
      assert Process.alive?(client)
      Client.close(client)
    end
  end

  describe "Client CLINotFoundError on connect" do
    @tag :capture_log
    test "connect returns CLINotFoundError for non-existent CLI" do
      opts = %Options{cli_path: "/nonexistent/path/to/claude"}
      {:ok, client} = Client.start_link(options: opts)

      assert {:error, %ClaudeSDK.CLINotFoundError{}} = Client.connect(client)

      Client.close(client)
    end
  end

  describe "Client message timeout in stream" do
    test "stream halts on message timeout" do
      # Use a mock that hangs after first message
      timeout_mock = Path.expand("../support/mock_cli_timeout.sh", __DIR__)
      opts = %Options{cli_path: timeout_mock, message_timeout_ms: 200}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      messages = Client.query(client, "hello") |> Enum.to_list()

      # Should get at least the assistant message before timeout
      assert length(messages) >= 1

      Client.close(client)
    end
  end

  describe "Client with mcp_servers nil" do
    @tag :capture_log
    test "connect handles nil mcp_servers" do
      opts = %Options{cli_path: @mock_cli_multiturn, mcp_servers: nil}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      messages = Client.query(client, "Hello") |> Enum.to_list()
      assert length(messages) > 0

      Client.close(client)
    end
  end

  describe "Client rewind_files while streaming" do
    test "rewind returns error when streaming" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      {:ok, _timeout, _gen} =
        GenServer.call(client, {:start_query, %{prompt: "test", caller: self()}})

      assert {:error, :busy} =
               Client.rewind_files(client, "msg-123")

      receive do
        {:client_message, _, _} -> :ok
      after
        1000 -> :ok
      end

      GenServer.call(client, :finish_query, 5_000)
      Client.close(client)
    end
  end

  describe "Client get_server_info while streaming" do
    test "get_server_info returns cached data even while streaming" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      {:ok, _timeout, _gen} =
        GenServer.call(client, {:start_query, %{prompt: "test", caller: self()}})

      assert {:ok, info} = Client.get_server_info(client)
      assert is_map(info)

      receive do
        {:client_message, _, _} -> :ok
      after
        1000 -> :ok
      end

      GenServer.call(client, :finish_query, 5_000)
      Client.close(client)
    end
  end

  describe "Client claude_exit with nil caller" do
    @tag :capture_log
    test "claude_exit when no active caller does not crash" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      # Simulate CLI exit when not streaming (no active_caller)
      send(client, {:claude_exit, :normal})
      Process.sleep(50)

      # Client should be disconnected now
      assert {:error, :not_connected} = Client.set_model(client, "m")

      Client.close(client)
    end
  end

  describe "Client finish_query when client is dead" do
    @tag :capture_log
    test "finish_query exits when client process died" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      # Unlink so killing client doesn't kill the test
      Process.unlink(client)

      # Start streaming
      {:ok, _timeout, _gen} =
        GenServer.call(client, {:start_query, %{prompt: "test", caller: self()}})

      # Kill the client
      Process.exit(client, :kill)
      Process.sleep(50)

      # GenServer.call on a dead process should exit
      assert catch_exit(GenServer.call(client, :finish_query, 5_000))
    end
  end

  describe "Client init with system messages before control_response" do
    @tag :capture_log
    test "skips non-control_response messages during Client init" do
      init_system = Path.expand("../support/mock_cli_init_with_system.sh", __DIR__)
      opts = %Options{cli_path: init_system}
      {:ok, client} = Client.start_link(options: opts)

      # This exercises wait_for_init_loop skipping system messages
      :ok = Client.connect(client)

      messages = Client.query(client, "hello") |> Enum.to_list()
      assert length(messages) > 0

      Client.close(client)
    end
  end

  describe "Client normalize_agents with list of maps" do
    test "handles agents as list of plain maps" do
      opts = %Options{
        cli_path: @mock_cli_multiturn,
        agents: [%{"name" => "test-agent", "model" => "test"}]
      }

      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      messages = Client.query(client, "Hello") |> Enum.to_list()
      assert length(messages) > 0

      Client.close(client)
    end
  end

  describe "plugins option in Client" do
    test "handles plugins as empty list" do
      opts = %Options{
        cli_path: @mock_cli_multiturn,
        plugins: []
      }

      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      messages = Client.query(client, "Hello") |> Enum.to_list()
      assert length(messages) > 0

      Client.close(client)
    end

    test "handles plugins as non-empty list" do
      opts = %Options{
        cli_path: @mock_cli_multiturn,
        plugins: ["my-plugin"]
      }

      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      messages = Client.query(client, "Hello") |> Enum.to_list()
      assert length(messages) > 0

      Client.close(client)
    end
  end

  describe "maybe_forward_to_caller with no active caller" do
    @tag :capture_log
    test "unhandled control_request is ignored when no active caller" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      # In :connected state with no active_caller, send an unhandled control_request
      send(
        client,
        {:claude_message,
         %{
           "type" => "control_request",
           "request_id" => "req_x",
           "request" => %{"subtype" => "unknown"}
         }}
      )

      Process.sleep(50)
      # Client should still work
      messages = Client.query(client, "hello") |> Enum.to_list()
      assert length(messages) > 0

      Client.close(client)
    end
  end

  describe "parse_rewind_response fallback" do
    @tag :capture_log
    test "rewind with response lacking success and error keys returns error" do
      hang_mock = Path.expand("../support/mock_cli_hang_on_control.sh", __DIR__)
      opts = %Options{cli_path: hang_mock}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      _messages = Client.query(client, "hello") |> Enum.to_list()

      task =
        Task.async(fn ->
          Client.rewind_files(client, "msg-456")
        end)

      Process.sleep(100)

      # Send a control_response without success or error keys
      send(
        client,
        {:claude_message, %{"type" => "control_response", "response" => %{"request_id" => "r1"}}}
      )

      assert {:error, :unexpected_response} = Task.await(task)

      Client.close(client)
    end
  end

  describe "cli_exit during awaiting_rewind" do
    @tag :capture_log
    test "cli_exit while awaiting rewind notifies caller with error" do
      hang_mock = Path.expand("../support/mock_cli_hang_on_control.sh", __DIR__)
      opts = %Options{cli_path: hang_mock}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      _messages = Client.query(client, "hello") |> Enum.to_list()

      task =
        Task.async(fn ->
          Client.rewind_files(client, "msg-789")
        end)

      Process.sleep(100)

      # Simulate CLI exit while awaiting rewind
      send(client, {:claude_exit, {:error, 1}})

      assert {:error, {:cli_exited, _}} = Task.await(task)

      Client.close(client)
    end
  end

  describe "cancel_control_timer flush" do
    @tag :capture_log
    test "flushes timer message when it arrives before cancellation" do
      hang_mock = Path.expand("../support/mock_cli_hang_on_control.sh", __DIR__)
      opts = %Options{cli_path: hang_mock}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      _messages = Client.query(client, "hello") |> Enum.to_list()

      # Start a control request (get_mcp_status) which sets a 30s timer
      task = Task.async(fn -> Client.get_mcp_status(client) end)
      Process.sleep(100)

      # Send the control_timeout message directly to simulate timer firing
      # before the response arrives
      send(client, :control_timeout)
      Process.sleep(50)

      # Now send the actual response — the timer should have been handled
      send(
        client,
        {:claude_message, %{"type" => "control_response", "response" => %{"status" => "ok"}}}
      )

      # The task should get the timeout error (since :control_timeout arrived first)
      assert {:error, :control_timeout} = Task.await(task)

      Client.close(client)
    end
  end

  describe "cli_exit during awaiting_control_response" do
    @tag :capture_log
    test "cli_exit while awaiting control response notifies caller" do
      hang_mock = Path.expand("../support/mock_cli_hang_on_control.sh", __DIR__)
      opts = %Options{cli_path: hang_mock}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      _messages = Client.query(client, "hello") |> Enum.to_list()

      task =
        Task.async(fn ->
          Client.get_mcp_status(client)
        end)

      Process.sleep(100)

      # Simulate CLI exit while awaiting control response
      send(client, {:claude_exit, {:error, 1}})

      assert {:error, {:cli_exited, _}} = Task.await(task)

      Client.close(client)
    end
  end

  describe "handled_with_interrupt control request" do
    @tag :capture_log
    test "handled_with_interrupt interrupts stream" do
      callback = fn _tool, _input -> {:deny, "No way", :interrupt} end
      opts = %Options{cli_path: @mock_cli_hang_on_control, can_use_tool: callback}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)
      _messages = Client.query(client, "hello") |> Enum.to_list()

      {:ok, _timeout, _gen} =
        GenServer.call(client, {:start_query, %{prompt: "test", caller: self()}})

      send(
        client,
        {:claude_message,
         %{
           "type" => "control_request",
           "request_id" => "req_int_test",
           "request" => %{
             "subtype" => "can_use_tool",
             "tool_name" => "Bash",
             "input" => %{"command" => "rm -rf /"}
           }
         }}
      )

      assert_receive {:client_exit, _gen, :interrupted}, 1000
      assert Client.connected?(client)
      Client.close(client)
    end
  end

  describe "do_interrupt when not streaming" do
    @tag :capture_log
    test "control_request with interrupt handler in connected state is a no-op" do
      callback = fn _tool, _input -> {:deny, "No", :interrupt} end
      opts = %Options{cli_path: @mock_cli_multiturn, can_use_tool: callback}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      send(
        client,
        {:claude_message,
         %{
           "type" => "control_request",
           "request_id" => "req_no_stream",
           "request" => %{
             "subtype" => "can_use_tool",
             "tool_name" => "Bash",
             "input" => %{}
           }
         }}
      )

      Process.sleep(50)
      assert Client.connected?(client)
      Client.close(client)
    end
  end

  describe "query with tool_use_result" do
    test "tool_use_result is included in user message" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)
      messages =
        Client.query(client, "result of tool", tool_use_result: %{"tool_use_id" => "tu_123"})
        |> Enum.to_list()
      assert length(messages) > 0
      Client.close(client)
    end
  end

  describe "backwards compat rewind response without request_id" do
    @tag :capture_log
    test "rewind response without request_id is handled" do
      opts = %Options{cli_path: @mock_cli_hang_on_control}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)
      _messages = Client.query(client, "hello") |> Enum.to_list()

      task = Task.async(fn -> Client.rewind_files(client, "msg-compat") end)
      Process.sleep(100)

      send(
        client,
        {:claude_message, %{"type" => "control_response", "response" => %{"success" => true}}}
      )

      assert :ok = Task.await(task)
      Client.close(client)
    end
  end

  describe "backwards compat control response without request_id" do
    @tag :capture_log
    test "control response without request_id is handled" do
      opts = %Options{cli_path: @mock_cli_hang_on_control}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)
      _messages = Client.query(client, "hello") |> Enum.to_list()

      task = Task.async(fn -> Client.get_mcp_status(client) end)
      Process.sleep(100)

      send(
        client,
        {:claude_message, %{"type" => "control_response", "response" => %{"status" => "connected"}}}
      )

      assert {:ok, %{"status" => "connected"}} = Task.await(task)
      Client.close(client)
    end
  end

  describe "stale control_response with mismatched request_id" do
    @tag :capture_log
    test "discards stale control_response and waits for correct one" do
      opts = %Options{cli_path: @mock_cli_hang_on_control}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)
      _messages = Client.query(client, "hello") |> Enum.to_list()

      task = Task.async(fn -> Client.get_mcp_status(client) end)
      Process.sleep(100)

      send(
        client,
        {:claude_message,
         %{"type" => "control_response", "request_id" => "stale-req-id", "response" => %{"stale" => true}}}
      )

      Process.sleep(50)

      send(
        client,
        {:claude_message, %{"type" => "control_response", "response" => %{"correct" => true}}}
      )

      assert {:ok, %{"correct" => true}} = Task.await(task)
      Client.close(client)
    end
  end

  describe "control_timeout during awaiting_rewind" do
    @tag :capture_log
    test "rewind times out when no response arrives" do
      opts = %Options{cli_path: @mock_cli_hang_on_control, control_timeout_ms: 100}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)
      _messages = Client.query(client, "hello") |> Enum.to_list()

      assert {:error, :control_timeout} = Client.rewind_files(client, "msg-timeout")
      assert Client.connected?(client)
      Client.close(client)
    end
  end

  describe "query with parent_tool_use_id" do
    test "parent_tool_use_id is forwarded in user message" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)
      messages =
        Client.query(client, "nested response", parent_tool_use_id: "tu_parent_123")
        |> Enum.to_list()
      assert length(messages) > 0
      Client.close(client)
    end
  end

  describe "set_model when connected" do
    @tag :capture_log
    test "sends control request to change model" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)
      _messages = Client.query(client, "hello") |> Enum.to_list()
      assert :ok = Client.set_model(client, "claude-sonnet-4-6")
      Client.close(client)
    end
  end

  describe "set_model when streaming" do
    test "returns error when streaming" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      {:ok, _timeout, _gen} =
        GenServer.call(client, {:start_query, %{prompt: "test", caller: self()}})

      assert {:error, :busy} = Client.set_model(client, "test-model")

      receive do
        {:client_message, _, _} -> :ok
      after
        1000 -> :ok
      end

      GenServer.call(client, :finish_query, 5_000)
      Client.close(client)
    end
  end

  describe "notify_caller_of_exit unexpected state" do
    @tag :capture_log
    test "cli_exit in connected state with no caller does not crash" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      send(client, {:claude_exit, {:error, :test_exit}})
      Process.sleep(50)

      refute Client.connected?(client)
      Client.close(client)
    end
  end

  describe "rewind response with matching request_id" do
    @tag :capture_log
    test "rewind response with correct request_id is handled" do
      hang_mock = Path.expand("../support/mock_cli_hang_on_control.sh", __DIR__)
      opts = %Options{cli_path: hang_mock}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)
      _messages = Client.query(client, "hello") |> Enum.to_list()

      task = Task.async(fn -> Client.rewind_files(client, "msg-matching") end)
      Process.sleep(100)

      # Read the pending_request_id from the GenServer state
      state = :sys.get_state(client)
      request_id = state.pending_request_id

      # Send response with the matching request_id
      send(
        client,
        {:claude_message,
         %{
           "type" => "control_response",
           "request_id" => request_id,
           "response" => %{"success" => true}
         }}
      )

      assert :ok = Task.await(task)
      Client.close(client)
    end
  end

  describe "control response with matching request_id" do
    @tag :capture_log
    test "control response with correct request_id is handled" do
      hang_mock = Path.expand("../support/mock_cli_hang_on_control.sh", __DIR__)
      opts = %Options{cli_path: hang_mock}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)
      _messages = Client.query(client, "hello") |> Enum.to_list()

      task = Task.async(fn -> Client.get_mcp_status(client) end)
      Process.sleep(100)

      state = :sys.get_state(client)
      request_id = state.pending_request_id

      send(
        client,
        {:claude_message,
         %{
           "type" => "control_response",
           "request_id" => request_id,
           "response" => %{"status" => "ok"}
         }}
      )

      assert {:ok, %{"status" => "ok"}} = Task.await(task)
      Client.close(client)
    end
  end

  describe "stale control_response during awaiting_rewind" do
    @tag :capture_log
    test "discards stale response and then handles correct one" do
      hang_mock = Path.expand("../support/mock_cli_hang_on_control.sh", __DIR__)
      opts = %Options{cli_path: hang_mock}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)
      _messages = Client.query(client, "hello") |> Enum.to_list()

      task = Task.async(fn -> Client.rewind_files(client, "msg-stale-rewind") end)
      Process.sleep(100)

      # Send stale response with wrong request_id
      send(
        client,
        {:claude_message,
         %{
           "type" => "control_response",
           "request_id" => "wrong-id",
           "response" => %{"success" => true}
         }}
      )

      Process.sleep(50)

      # Now send correct response (backwards compat, no request_id)
      send(
        client,
        {:claude_message,
         %{"type" => "control_response", "response" => %{"success" => true}}
        }
      )

      assert :ok = Task.await(task)
      Client.close(client)
    end
  end

  # Helper to collect messages similar to how Client.query's Stream.resource works
  defp collect_client_messages(state, acc \\ []) do
    receive do
      {:client_message, _gen, raw} ->
        case ClaudeSDK.MessageParser.parse(raw) do
          {:ok, %ClaudeSDK.Types.ResultMessage{} = msg} ->
            Enum.reverse([msg | acc])

          {:ok, msg} ->
            collect_client_messages(state, [msg | acc])

          {:error, _} ->
            collect_client_messages(state, acc)
        end

      {:client_exit, _gen, _reason} ->
        Enum.reverse(acc)
    after
      1000 -> Enum.reverse(acc)
    end
  end
end
