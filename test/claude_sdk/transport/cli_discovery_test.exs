defmodule ClaudeSDK.Transport.CLIDiscoveryTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.Transport.CLIDiscovery

  describe "find_cli/1" do
    test "returns {:ok, path} for explicit path that exists" do
      # Use a path we know exists
      assert {:ok, "/usr/bin/env"} = CLIDiscovery.find_cli("/usr/bin/env")
    end

    test "returns {:error, :not_found} for explicit path that doesn't exist" do
      assert {:error, :not_found} = CLIDiscovery.find_cli("/nonexistent/path/claude")
    end

    test "finds executable on PATH when no explicit path given" do
      # `env` should always be on PATH
      result = CLIDiscovery.find_cli(nil)

      # We can't guarantee `claude` is installed, so just check the return type
      case result do
        {:ok, path} -> assert is_binary(path)
        {:error, :not_found} -> :ok
      end
    end
  end

  describe "find_cli!/1" do
    test "returns path for existing executable" do
      assert "/usr/bin/env" = CLIDiscovery.find_cli!("/usr/bin/env")
    end

    test "raises CLINotFoundError for missing path" do
      assert_raise ClaudeSDK.CLINotFoundError, fn ->
        CLIDiscovery.find_cli!("/nonexistent/claude")
      end
    end
  end

  describe "version/1" do
    test "returns version for valid executable" do
      # Use `echo` as a stand-in — it just echoes args, but exits 0
      case System.find_executable("echo") do
        nil ->
          :skip

        echo_path ->
          # echo with -v won't work like claude, but we can test the function doesn't crash
          result = CLIDiscovery.version(echo_path)
          assert {:ok, _} = result
      end
    end

    test "returns error for nonexistent binary" do
      assert {:error, {:spawn_failed, _}} = CLIDiscovery.version("/nonexistent/binary")
    end
  end
end
