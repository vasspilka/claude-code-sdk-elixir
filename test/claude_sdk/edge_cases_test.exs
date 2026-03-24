defmodule ClaudeSDK.EdgeCasesTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.Client
  alias ClaudeSDK.Types.Options

  @mock_cli_crash_init Path.expand("../support/mock_cli_crash_on_init.sh", __DIR__)
  @mock_cli_crash_mid Path.expand("../support/mock_cli_crash_mid_stream.sh", __DIR__)
  @mock_cli_exit_no_result Path.expand("../support/mock_cli_exit_zero_no_result.sh", __DIR__)
  @mock_cli_multiturn Path.expand("../support/mock_cli_multiturn.sh", __DIR__)
  @mock_cli_crash_on_rewind Path.expand("../support/mock_cli_crash_on_rewind.sh", __DIR__)
  @mock_cli_hang_on_control Path.expand("../support/mock_cli_hang_on_control.sh", __DIR__)

  describe "CLI crash during initialization" do
    @tag :capture_log
    test "stateless query raises TransportError when CLI crashes before control_response" do
      assert_raise ClaudeSDK.TransportError, ~r/CLI exited during initialization/, fn ->
        ClaudeSDK.query("hello", %Options{cli_path: @mock_cli_crash_init})
        |> Enum.to_list()
      end
    end

    @tag :capture_log
    test "Client.connect returns error when CLI crashes before control_response" do
      opts = %Options{cli_path: @mock_cli_crash_init}
      {:ok, client} = Client.start_link(options: opts)

      assert {:error, {:cli_exited, _}} = Client.connect(client)

      Client.close(client)
    end
  end

  describe "CLI crash mid-stream" do
    @tag :capture_log
    test "stateless query stream ends when CLI crashes mid-stream" do
      messages =
        ClaudeSDK.query("hello", %Options{cli_path: @mock_cli_crash_mid})
        |> Enum.to_list()

      # Should get the assistant message before the crash
      assistant =
        Enum.find(messages, fn
          %ClaudeSDK.Types.AssistantMessage{} -> true
          _ -> false
        end)

      assert assistant != nil
    end

    @tag :capture_log
    test "Client stream ends when CLI crashes mid-stream" do
      opts = %Options{cli_path: @mock_cli_crash_mid}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      messages = Client.query(client, "hello") |> Enum.to_list()

      assistant =
        Enum.find(messages, fn
          %ClaudeSDK.Types.AssistantMessage{} -> true
          _ -> false
        end)

      assert assistant != nil

      Client.close(client)
    end
  end

  describe "CLI exit without result" do
    @tag :capture_log
    test "stateless query stream ends gracefully on clean exit without result" do
      messages =
        ClaudeSDK.query("hello", %Options{cli_path: @mock_cli_exit_no_result})
        |> Enum.to_list()

      assistant =
        Enum.find(messages, fn
          %ClaudeSDK.Types.AssistantMessage{} -> true
          _ -> false
        end)

      assert assistant != nil
    end
  end

  describe "Client state recovery" do
    @tag :capture_log
    test "Client returns to connected state after stream completes" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      # Complete a query
      _messages = Client.query(client, "hello") |> Enum.to_list()

      # Should be able to set_model (requires :connected state)
      assert :ok = Client.set_model(client, "new-model")

      Client.close(client)
    end

    @tag :capture_log
    test "Client returns to connected state after second query" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      # Two queries
      _messages1 = Client.query(client, "first") |> Enum.to_list()
      _messages2 = Client.query(client, "second") |> Enum.to_list()

      # Should still be :connected
      assert :ok = Client.set_model(client, "new-model")

      Client.close(client)
    end
  end

  describe "Port.open failure" do
    test "Subprocess returns error for non-existent CLI binary" do
      opts = %Options{cli_path: "/nonexistent/path/to/claude"}

      assert_raise ClaudeSDK.CLINotFoundError, fn ->
        ClaudeSDK.query("hello", opts) |> Enum.to_list()
      end
    end
  end

  describe "Client control timeout" do
    @tag :capture_log
    test "control_timeout returns error and transitions back to connected" do
      # Use a mock that hangs on control requests (never responds)
      opts = %Options{cli_path: @mock_cli_hang_on_control}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      # Complete a query so we're in :connected state
      _messages = Client.query(client, "hello") |> Enum.to_list()

      # Spawn a task that calls get_mcp_status — the mock will NOT respond,
      # so it blocks in :awaiting_control_response state
      task =
        Task.async(fn ->
          Client.get_mcp_status(client)
        end)

      # Give the GenServer time to enter :awaiting_control_response
      Process.sleep(50)

      # Send :control_timeout directly (simulating the 30s timer firing)
      send(client, :control_timeout)

      # The call should return with timeout error
      assert {:error, :control_timeout} = Task.await(task)

      # Client should be back in :connected state
      assert :ok = Client.set_model(client, "new-model")

      Client.close(client)
    end
  end

  describe "CLI crash during awaiting_rewind" do
    @tag :capture_log
    test "Client returns error when CLI crashes while awaiting rewind response" do
      opts = %Options{cli_path: @mock_cli_crash_on_rewind}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      # Complete a query
      _messages = Client.query(client, "hello") |> Enum.to_list()

      # Rewind should fail because the mock crashes after receiving the rewind request
      assert {:error, {:cli_exited, _}} = Client.rewind_files(client, "msg-123")

      # Client should be in :disconnected state now — set_model requires :connected
      assert {:error, :not_connected} = Client.set_model(client, "new-model")

      Client.close(client)
    end
  end

  describe "rewind happy path" do
    @tag :capture_log
    test "rewind_files succeeds and returns to connected state" do
      opts = %Options{cli_path: @mock_cli_multiturn}
      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      assert :ok = Client.rewind_files(client, "msg-123")

      # After rewind, should be back in connected state
      assert :ok = Client.set_model(client, "new-model")

      Client.close(client)
    end
  end
end
