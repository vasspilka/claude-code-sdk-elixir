defmodule ClaudeSDK.ErrorsTest do
  use ExUnit.Case, async: true

  describe "CLINotFoundError" do
    test "with explicit path" do
      error = ClaudeSDK.CLINotFoundError.exception(path: "/custom/path/claude")
      assert error.message =~ "/custom/path/claude"
      assert error.message =~ "npm install"
    end

    test "without path (nil)" do
      error = ClaudeSDK.CLINotFoundError.exception(path: nil)
      assert error.message =~ "not found on PATH"
      assert error.message =~ "npm install"
    end

    test "without path key" do
      error = ClaudeSDK.CLINotFoundError.exception([])
      assert error.message =~ "not found on PATH"
    end
  end

  describe "TransportError" do
    test "with reason" do
      error = ClaudeSDK.TransportError.exception(reason: :connection_refused)
      assert error.message =~ "connection_refused"
      assert error.reason == :connection_refused
    end

    test "with custom message" do
      error =
        ClaudeSDK.TransportError.exception(reason: :timeout, message: "Custom transport error")

      assert error.message == "Custom transport error"
      assert error.reason == :timeout
    end

    test "with default reason" do
      error = ClaudeSDK.TransportError.exception([])
      assert error.reason == :unknown
    end
  end

  describe "ProtocolError" do
    test "with raw data" do
      error = ClaudeSDK.ProtocolError.exception(raw_data: "garbage data")
      assert error.message =~ "Protocol error"
      assert error.raw_data == "garbage data"
    end

    test "with custom message" do
      error =
        ClaudeSDK.ProtocolError.exception(message: "Bad format", raw_data: %{"bad" => true})

      assert error.message == "Bad format"
      assert error.raw_data == %{"bad" => true}
    end
  end

  describe "QueryError" do
    test "with reason" do
      error = ClaudeSDK.QueryError.exception(reason: {:invalid_state, :disconnected})
      assert error.message =~ "Failed to start query"
      assert error.reason == {:invalid_state, :disconnected}
    end

    test "with custom message" do
      error = ClaudeSDK.QueryError.exception(reason: :busy, message: "Client is busy")
      assert error.message == "Client is busy"
      assert error.reason == :busy
    end
  end

  describe "ProcessExitError" do
    test "with exit code only" do
      error = ClaudeSDK.ProcessExitError.exception(exit_code: 1)
      assert error.message =~ "exited with status 1"
      assert error.exit_code == 1
      assert error.stderr == ""
    end

    test "with exit code and stderr" do
      error = ClaudeSDK.ProcessExitError.exception(exit_code: 2, stderr: "Error: segfault")
      assert error.message =~ "exited with status 2"
      assert error.message =~ "Stderr:"
      assert error.message =~ "Error: segfault"
      assert error.exit_code == 2
      assert error.stderr == "Error: segfault"
    end

    test "with empty stderr does not include Stderr section" do
      error = ClaudeSDK.ProcessExitError.exception(exit_code: 1, stderr: "")
      refute error.message =~ "Stderr:"
    end

    test "with custom message overrides default" do
      error =
        ClaudeSDK.ProcessExitError.exception(
          exit_code: 1,
          stderr: "some error",
          message: "Custom crash"
        )

      assert error.message == "Custom crash"
      assert error.stderr == "some error"
    end
  end

  describe "TimeoutError" do
    test "with timeout_ms" do
      error = ClaudeSDK.TimeoutError.exception(timeout_ms: 30_000)
      assert error.message =~ "30000"
      assert error.timeout_ms == 30_000
    end

    test "with custom message" do
      error = ClaudeSDK.TimeoutError.exception(timeout_ms: 5000, message: "Init timed out")
      assert error.message == "Init timed out"
      assert error.timeout_ms == 5000
    end
  end
end
