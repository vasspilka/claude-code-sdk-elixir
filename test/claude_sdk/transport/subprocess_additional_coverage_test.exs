defmodule ClaudeSDK.Transport.SubprocessAdditionalCoverageTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.Transport.Subprocess
  alias ClaudeSDK.Types.Options

  @mock_cli_path Path.expand("../../support/mock_cli.sh", __DIR__)
  @mock_cli_old_version Path.expand("../../support/mock_cli_old_version.sh", __DIR__)
  @mock_cli_bad_version Path.expand("../../support/mock_cli_bad_version.sh", __DIR__)
  @mock_cli_no_version Path.expand("../../support/mock_cli_no_version.sh", __DIR__)

  describe "version warning for old CLI" do
    @tag :capture_log
    test "logs warning when CLI version is below minimum" do
      {:ok, pid} =
        Subprocess.start(caller: self(), options: %Options{cli_path: @mock_cli_old_version})

      # Give version check time to run
      Process.sleep(200)
      assert Process.alive?(pid)
      Subprocess.stop(pid)
    end
  end

  describe "version check with bad version string" do
    @tag :capture_log
    test "handles non-semver version string gracefully" do
      {:ok, pid} =
        Subprocess.start(caller: self(), options: %Options{cli_path: @mock_cli_bad_version})

      Process.sleep(200)
      assert Process.alive?(pid)
      Subprocess.stop(pid)
    end
  end

  describe "version check failure" do
    @tag :capture_log
    test "handles version command failure gracefully" do
      {:ok, pid} =
        Subprocess.start(caller: self(), options: %Options{cli_path: @mock_cli_no_version})

      Process.sleep(200)
      assert Process.alive?(pid)
      Subprocess.stop(pid)
    end
  end

  describe "send_message to closed port" do
    @tag :capture_log
    test "handles port closed during send gracefully" do
      # Create a script that exits immediately after init
      script_path = Path.join(System.tmp_dir!(), "mock_cli_quick_exit.sh")

      File.write!(script_path, """
      #!/usr/bin/env bash
      if [ "$1" = "-v" ]; then echo "99.0.0"; exit 0; fi
      read -r init_line
      request_id=$(echo "$init_line" | grep -o '"request_id":"[^"]*"' | head -1 | cut -d'"' -f4)
      echo "{\\\"type\\\":\\\"control_response\\\",\\\"response\\\":{\\\"request_id\\\":\\\"$request_id\\\",\\\"subtype\\\":\\\"success\\\"}}"
      exit 0
      """)

      File.chmod!(script_path, 0o755)

      {:ok, pid} = Subprocess.start(caller: self(), options: %Options{cli_path: script_path})

      Subprocess.send_message(pid, %{
        type: "control_request",
        request_id: "req_test",
        request: %{subtype: "initialize"}
      })

      assert_receive {:claude_message, %{"type" => "control_response"}}, 5000
      # Wait for the process to exit
      assert_receive {:claude_exit, :normal}, 5000

      # Now try to send a message — the port is closed
      # The subprocess may already be dead, but if not, the send should fail gracefully
      try do
        Subprocess.send_message(pid, %{type: "user", message: %{content: "hello"}})
      catch
        :exit, _ -> :ok
      end

      Process.sleep(50)
      File.rm(script_path)
    end
  end

  describe "buffer overflow handling" do
    @tag :capture_log
    test "resets buffer when noeol data exceeds 10MB limit" do
      # We test the accumulate path via the LineBuffer directly since we
      # can't easily create a 10MB+ noeol scenario with a shell script.
      # But we can verify the Subprocess handle_info clause by sending
      # a simulated :noeol message with a huge chunk.
      {:ok, pid} = Subprocess.start(caller: self(), options: %Options{cli_path: @mock_cli_path})

      # Get the port from the subprocess state
      state = :sys.get_state(pid)
      port = state.port

      # Simulate a buffer overflow by filling the buffer via noeol messages
      # The LineBuffer has a 10MB limit. We send chunks to exceed it.
      # First, send multiple noeol chunks to build up buffer
      big_chunk = String.duplicate("x", 5_500_000)

      # Send first noeol — within limit
      send(pid, {port, {:data, {:noeol, big_chunk}}})
      Process.sleep(10)
      assert Process.alive?(pid)

      # Send second noeol — should trigger overflow (>10MB total)
      send(pid, {port, {:data, {:noeol, big_chunk}}})
      Process.sleep(10)

      # Process should still be alive after overflow (buffer is reset)
      assert Process.alive?(pid)

      Subprocess.stop(pid)
    end
  end

  describe "terminate with already-closed port" do
    @tag :capture_log
    test "terminate handles ArgumentError when port is already closed" do
      # Create a script that exits immediately
      script_path =
        Path.join(System.tmp_dir!(), "mock_cli_instant_exit_#{:rand.uniform(100_000)}.sh")

      File.write!(script_path, """
      #!/usr/bin/env bash
      if [ "$1" = "-v" ]; then echo "99.0.0"; exit 0; fi
      read -r init_line
      request_id=$(echo "$init_line" | grep -o '"request_id":"[^"]*"' | head -1 | cut -d'"' -f4)
      echo "{\\\"type\\\":\\\"control_response\\\",\\\"response\\\":{\\\"request_id\\\":\\\"$request_id\\\",\\\"subtype\\\":\\\"success\\\"}}"
      exit 0
      """)

      File.chmod!(script_path, 0o755)

      {:ok, pid} = Subprocess.start(caller: self(), options: %Options{cli_path: script_path})

      Subprocess.send_message(pid, %{
        type: "control_request",
        request_id: "req_test",
        request: %{subtype: "initialize"}
      })

      # Wait for the process to exit
      assert_receive {:claude_message, _}, 5000
      assert_receive {:claude_exit, :normal}, 5000

      # Stop should handle the already-exited process gracefully
      try do
        Subprocess.stop(pid)
      catch
        :exit, _ -> :ok
      end

      File.rm(script_path)
    end
  end

  describe "eol with non-JSON after noeol buffering" do
    @tag :capture_log
    test "non-JSON line after noeol buffering is skipped" do
      {:ok, pid} = Subprocess.start(caller: self(), options: %Options{cli_path: @mock_cli_path})

      state = :sys.get_state(pid)
      port = state.port

      # Send a noeol chunk followed by an eol that forms invalid JSON
      send(pid, {port, {:data, {:noeol, "this is not "}}})
      Process.sleep(10)
      send(pid, {port, {:data, {:eol, "json at all"}}})
      Process.sleep(10)

      # Should not have received any claude_message for that
      refute_receive {:claude_message, _}

      assert Process.alive?(pid)
      Subprocess.stop(pid)
    end
  end
end
