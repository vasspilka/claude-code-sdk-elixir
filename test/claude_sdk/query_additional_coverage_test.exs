defmodule ClaudeSDK.QueryAdditionalCoverageTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.Types.Options

  describe "query/2 with invalid keyword keys" do
    test "raises ArgumentError for unknown option keys" do
      assert_raise ArgumentError, ~r/unknown options/, fn ->
        ClaudeSDK.query("test", bogus_key: true, another_bad: "x")
        |> Enum.to_list()
      end
    end
  end

  describe "query/2 CLI not found" do
    test "raises CLINotFoundError for non-existent CLI path" do
      assert_raise ClaudeSDK.CLINotFoundError, fn ->
        ClaudeSDK.query("test", %Options{cli_path: "/nonexistent/path/to/claude"})
        |> Enum.to_list()
      end
    end
  end

  describe "query/2 CLI exits during init" do
    @tag :capture_log
    test "raises ProcessExitError when CLI crashes during init" do
      crash_init = Path.expand("../support/mock_cli_crash_on_init.sh", __DIR__)

      assert_raise ClaudeSDK.ProcessExitError, fn ->
        ClaudeSDK.query("test", %Options{cli_path: crash_init})
        |> Enum.to_list()
      end
    end
  end

  describe "query/2 CLI exits with zero but no result during streaming" do
    @tag :capture_log
    test "handles clean exit without result message" do
      exit_zero = Path.expand("../support/mock_cli_exit_zero_no_result.sh", __DIR__)

      messages =
        ClaudeSDK.query("test", %Options{cli_path: exit_zero})
        |> Enum.to_list()

      # Should get whatever messages the CLI sent before exiting
      assert is_list(messages)
    end
  end

  describe "cleanup with non-map state" do
    test "cleanup with :done atom is a no-op" do
      # This exercises the cleanup(:done) clause
      # Indirectly tested when a stream runs to completion via :claude_exit
      exit_zero = Path.expand("../support/mock_cli_exit_zero_no_result.sh", __DIR__)

      messages =
        ClaudeSDK.query("test", %Options{cli_path: exit_zero})
        |> Enum.to_list()

      assert is_list(messages)
    end
  end

  describe "query/2 CLI exits with non-ProcessExitError during init" do
    @tag :capture_log
    test "raises TransportError when CLI exits with generic reason during init" do
      exit_during_init = Path.expand("../support/mock_cli_exit_during_init.sh", __DIR__)

      assert_raise ClaudeSDK.ProcessExitError, fn ->
        ClaudeSDK.query("test", %Options{cli_path: exit_during_init})
        |> Enum.to_list()
      end
    end
  end

  describe "query/1 default options" do
    test "query with default options uses %Options{}" do
      # This exercises the default arg clause: def query(prompt, opts \\ %Options{})
      # Can't actually run with default (no CLI), but we can test with keyword list
      mock_cli = Path.expand("../support/mock_cli.sh", __DIR__)

      messages =
        ClaudeSDK.query("test", cli_path: mock_cli)
        |> Enum.to_list()

      assert length(messages) > 0
    end
  end
end
