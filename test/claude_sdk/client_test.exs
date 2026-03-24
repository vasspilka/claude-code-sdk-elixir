defmodule ClaudeSDK.ClientTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.Client
  alias ClaudeSDK.Types.Options

  @mock_cli_path Path.expand("../support/mock_cli_multiturn.sh", __DIR__)

  describe "lifecycle" do
    test "start_link, connect, query, close" do
      opts = %Options{cli_path: @mock_cli_path}
      {:ok, client} = Client.start_link(options: opts)

      assert :ok = Client.connect(client)

      messages =
        Client.query(client, "Hello")
        |> Enum.to_list()

      assert length(messages) > 0

      result =
        Enum.find(messages, fn
          %ClaudeSDK.Types.ResultMessage{} -> true
          _ -> false
        end)

      assert result != nil
      assert result.session_id == "mock-session-1"

      Client.close(client)
    end

    test "multiple queries maintain session" do
      opts = %Options{cli_path: @mock_cli_path}
      {:ok, client} = Client.start_link(options: opts)

      :ok = Client.connect(client)

      # First query
      messages1 = Client.query(client, "First") |> Enum.to_list()

      result1 =
        Enum.find(messages1, fn
          %ClaudeSDK.Types.ResultMessage{} -> true
          _ -> false
        end)

      assert result1.session_id == "mock-session-1"

      # Second query
      messages2 = Client.query(client, "Second") |> Enum.to_list()

      result2 =
        Enum.find(messages2, fn
          %ClaudeSDK.Types.ResultMessage{} -> true
          _ -> false
        end)

      assert result2.session_id == "mock-session-2"

      Client.close(client)
    end

    test "connect is idempotent" do
      opts = %Options{cli_path: @mock_cli_path}
      {:ok, client} = Client.start_link(options: opts)

      assert :ok = Client.connect(client)
      assert :ok = Client.connect(client)

      Client.close(client)
    end

    test "query before connect returns error" do
      opts = %Options{cli_path: @mock_cli_path}
      {:ok, client} = Client.start_link(options: opts)

      assert_raise ClaudeSDK.QueryError, ~r/Failed to start query/, fn ->
        Client.query(client, "Hello") |> Enum.to_list()
      end

      Client.close(client)
    end
  end

  describe "multi-turn messages" do
    test "each turn gets assistant message and result" do
      opts = %Options{cli_path: @mock_cli_path}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      for turn <- 1..3 do
        messages = Client.query(client, "Turn #{turn}") |> Enum.to_list()

        assistant =
          Enum.find(messages, fn
            %ClaudeSDK.Types.AssistantMessage{} -> true
            _ -> false
          end)

        assert assistant != nil
        [text] = assistant.message.content
        assert text.text == "Turn #{turn} response."

        result =
          Enum.find(messages, fn
            %ClaudeSDK.Types.ResultMessage{} -> true
            _ -> false
          end)

        assert result != nil
        assert result.num_turns == turn
      end

      Client.close(client)
    end
  end

  describe "dynamic control operations" do
    test "interrupt returns error when not streaming" do
      opts = %Options{cli_path: @mock_cli_path}
      {:ok, client} = Client.start_link(options: opts)

      assert {:error, :not_connected} = Client.interrupt(client)

      :ok = Client.connect(client)
      assert {:error, :not_streaming} = Client.interrupt(client)

      Client.close(client)
    end

    test "set_model returns error when not connected" do
      opts = %Options{cli_path: @mock_cli_path}
      {:ok, client} = Client.start_link(options: opts)

      assert {:error, :not_connected} =
               Client.set_model(client, "claude-sonnet-4-20250514")

      Client.close(client)
    end

    test "set_model succeeds when connected" do
      opts = %Options{cli_path: @mock_cli_path}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      assert :ok = Client.set_model(client, "claude-sonnet-4-20250514")

      Client.close(client)
    end

    test "set_permission_mode returns error when not connected" do
      opts = %Options{cli_path: @mock_cli_path}
      {:ok, client} = Client.start_link(options: opts)

      assert {:error, :not_connected} =
               Client.set_permission_mode(client, :bypass_permissions)

      Client.close(client)
    end

    test "set_permission_mode succeeds when connected" do
      opts = %Options{cli_path: @mock_cli_path}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      assert :ok = Client.set_permission_mode(client, :bypass_permissions)

      Client.close(client)
    end

    test "get_mcp_status returns error when not connected" do
      opts = %Options{cli_path: @mock_cli_path}
      {:ok, client} = Client.start_link(options: opts)

      assert {:error, :not_connected} = Client.get_mcp_status(client)

      Client.close(client)
    end

    test "reconnect_mcp_server returns error when not connected" do
      opts = %Options{cli_path: @mock_cli_path}
      {:ok, client} = Client.start_link(options: opts)

      assert {:error, :not_connected} =
               Client.reconnect_mcp_server(client, "my-server")

      Client.close(client)
    end

    test "toggle_mcp_server returns error when not connected" do
      opts = %Options{cli_path: @mock_cli_path}
      {:ok, client} = Client.start_link(options: opts)

      assert {:error, :not_connected} =
               Client.toggle_mcp_server(client, "my-server", false)

      Client.close(client)
    end

    test "set_model returns error when streaming (via GenServer call)" do
      # Test the GenServer state machine directly:
      # When state is :streaming, set_model should return {:error, :busy}
      opts = %Options{cli_path: @mock_cli_path}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      # Put the client into :streaming state by calling start_query
      assert {:ok, _timeout, _gen} =
               GenServer.call(client, {:start_query, "test prompt", self()})

      # Now set_model should fail because we're streaming
      assert {:error, :busy} =
               Client.set_model(client, "claude-sonnet-4-20250514")

      # Clean up: drain messages and finish
      receive do
        {:client_message, _, _} -> :ok
      after
        1000 -> :ok
      end

      GenServer.call(client, :finish_query, 5_000)
      Client.close(client)
    end

    test "set_permission_mode returns error when streaming (via GenServer call)" do
      opts = %Options{cli_path: @mock_cli_path}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      assert {:ok, _timeout, _gen} =
               GenServer.call(client, {:start_query, "test prompt", self()})

      assert {:error, :busy} =
               Client.set_permission_mode(client, :plan)

      receive do
        {:client_message, _, _} -> :ok
      after
        1000 -> :ok
      end

      GenServer.call(client, :finish_query, 5_000)
      Client.close(client)
    end
  end

  describe "with permission callback" do
    @mock_cli_permission_path Path.expand("../support/mock_cli_permission.sh", __DIR__)

    test "permission callback is invoked through client" do
      test_pid = self()

      opts = %Options{
        cli_path: @mock_cli_permission_path,
        can_use_tool: fn tool, _input ->
          send(test_pid, {:permission_check, tool})
          {:deny, "Denied by test"}
        end
      }

      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      messages = Client.query(client, "test") |> Enum.to_list()

      assert_receive {:permission_check, "Bash"}
      assert length(messages) > 0

      Client.close(client)
    end
  end
end
