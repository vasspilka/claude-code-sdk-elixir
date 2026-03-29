defmodule ClaudeSDK.Transport.SubprocessCoverageTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.Transport.Subprocess
  alias ClaudeSDK.Types.Options

  @mock_cli_path Path.expand("../../support/mock_cli.sh", __DIR__)

  describe "start/1 (non-linked)" do
    test "starts a subprocess without linking" do
      {:ok, pid} = Subprocess.start(caller: self(), options: %Options{cli_path: @mock_cli_path})
      assert Process.alive?(pid)
      Subprocess.stop(pid)
    end
  end

  describe "non-JSON lines" do
    @tag :capture_log
    test "skips non-JSON lines from CLI" do
      # The subprocess sends non-JSON lines to caller via debug logging
      # We test this by sending a message directly to the subprocess
      {:ok, pid} = Subprocess.start(caller: self(), options: %Options{cli_path: @mock_cli_path})

      # Send the init message and wait for response
      Subprocess.send_message(pid, %{
        type: "control_request",
        request_id: "req_test",
        request: %{subtype: "initialize"}
      })

      # Should receive control_response
      assert_receive {:claude_message, %{"type" => "control_response"}}, 5000

      Subprocess.stop(pid)
    end
  end

  describe "unexpected handle_info messages" do
    @tag :capture_log
    test "handles unexpected messages gracefully" do
      {:ok, pid} = Subprocess.start(caller: self(), options: %Options{cli_path: @mock_cli_path})

      # Send an unexpected message
      send(pid, {:unexpected, "data"})

      # Process should still be alive
      Process.sleep(50)
      assert Process.alive?(pid)

      Subprocess.stop(pid)
    end
  end

  describe "non-zero exit status" do
    @tag :capture_log
    test "sends {:claude_exit, {:error, code}} for non-zero exit" do
      # Create a script that exits with code 1
      script_path = Path.join(System.tmp_dir!(), "mock_cli_exit_1.sh")

      File.write!(script_path, """
      #!/usr/bin/env bash
      read -r init_line
      echo '{"type":"control_response","response":{}}'
      exit 1
      """)

      File.chmod!(script_path, 0o755)

      {:ok, pid} = Subprocess.start(caller: self(), options: %Options{cli_path: script_path})

      Subprocess.send_message(pid, %{
        type: "control_request",
        request_id: "req_test",
        request: %{subtype: "initialize"}
      })

      assert_receive {:claude_message, %{"type" => "control_response"}}, 5000
      assert_receive {:claude_exit, {:error, %ClaudeSDK.ProcessExitError{exit_code: 1}}}, 5000

      File.rm(script_path)
    end
  end

  describe "CLI not found" do
    test "returns CLINotFoundError for non-existent path" do
      result =
        Subprocess.start(caller: self(), options: %Options{cli_path: "/nonexistent/claude"})

      assert {:error, %ClaudeSDK.CLINotFoundError{}} = result
    end
  end

  describe "non-JSON lines from CLI" do
    @mock_cli_nonjson Path.expand("../../support/mock_cli_nonjson.sh", __DIR__)

    @tag :capture_log
    test "non-JSON lines are skipped and valid JSON is still processed" do
      {:ok, pid} =
        Subprocess.start(caller: self(), options: %Options{cli_path: @mock_cli_nonjson})

      Subprocess.send_message(pid, %{
        type: "control_request",
        request_id: "req_test",
        request: %{subtype: "initialize"}
      })

      # Should receive control_response (non-JSON lines skipped)
      assert_receive {:claude_message, %{"type" => "control_response"}}, 5000

      Subprocess.send_message(pid, %{
        type: "user",
        session_id: "default",
        message: %{role: "user", content: "hello"},
        parent_tool_use_id: nil
      })

      # Should receive assistant and result despite non-JSON lines
      assert_receive {:claude_message, %{"type" => "assistant"}}, 5000
      assert_receive {:claude_message, %{"type" => "result"}}, 5000

      Subprocess.stop(pid)
    end
  end

  describe "noeol handling (lines exceeding Port line limit)" do
    @mock_cli_long_line Path.expand("../../support/mock_cli_long_line.sh", __DIR__)

    test "handles chunked lines that exceed Port {:line, N} limit" do
      {:ok, pid} =
        Subprocess.start(caller: self(), options: %Options{cli_path: @mock_cli_long_line})

      Subprocess.send_message(pid, %{
        type: "control_request",
        request_id: "req_test",
        request: %{subtype: "initialize"}
      })

      assert_receive {:claude_message, %{"type" => "control_response"}}, 5000

      Subprocess.send_message(pid, %{
        type: "user",
        session_id: "default",
        message: %{role: "user", content: "hello"},
        parent_tool_use_id: nil
      })

      # Should receive the long assistant message (assembled from noeol chunks)
      assert_receive {:claude_message, %{"type" => "assistant"}}, 10_000
      # And the result
      assert_receive {:claude_message, %{"type" => "result"}}, 5000

      # Process may have already exited after sending result
      try do
        if Process.alive?(pid), do: Subprocess.stop(pid)
      catch
        :exit, _ -> :ok
      end
    end
  end

  describe "terminate" do
    test "terminates gracefully when port is open" do
      {:ok, pid} = Subprocess.start(caller: self(), options: %Options{cli_path: @mock_cli_path})
      assert Process.alive?(pid)
      Subprocess.stop(pid)
      Process.sleep(50)
      refute Process.alive?(pid)
    end
  end

  describe "caller death monitoring" do
    test "subprocess stops when caller process dies" do
      test_pid = self()

      caller =
        spawn(fn ->
          {:ok, sub_pid} =
            Subprocess.start(caller: self(), options: %Options{cli_path: @mock_cli_path})

          send(test_pid, {:sub_pid, sub_pid})

          receive do
            :stop -> :ok
          after
            5000 -> :ok
          end
        end)

      sub_pid =
        receive do
          {:sub_pid, pid} -> pid
        after
          5000 -> flunk("Subprocess not started")
        end

      assert Process.alive?(sub_pid)
      Process.exit(caller, :kill)
      Process.sleep(100)
      refute Process.alive?(sub_pid)
    end
  end

  describe "start_link" do
    test "starts a linked subprocess" do
      {:ok, pid} =
        Subprocess.start_link(caller: self(), options: %Options{cli_path: @mock_cli_path})

      assert Process.alive?(pid)
      Subprocess.stop(pid)
    end
  end
end
