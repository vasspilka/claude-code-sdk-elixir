defmodule ClaudeSDK.Transport.CLIDiscoveryCoverageTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.Transport.CLIDiscovery

  describe "find_cli/1" do
    test "returns {:ok, path} for existing explicit path" do
      assert {:ok, "/usr/bin/env"} = CLIDiscovery.find_cli("/usr/bin/env")
    end

    test "returns {:error, :not_found} for non-existent explicit path" do
      assert {:error, :not_found} = CLIDiscovery.find_cli("/nonexistent/path/to/claude")
    end
  end

  describe "find_cli/0 default arg" do
    test "finds claude on PATH" do
      assert {:ok, path} = CLIDiscovery.find_cli()
      assert is_binary(path)
    end
  end

  describe "find_cli!/0 default arg" do
    test "finds claude on PATH" do
      path = CLIDiscovery.find_cli!()
      assert is_binary(path)
    end
  end

  describe "find_cli!/1" do
    test "returns path for existing file" do
      assert "/usr/bin/env" = CLIDiscovery.find_cli!("/usr/bin/env")
    end

    test "raises CLINotFoundError for non-existent explicit path" do
      assert_raise ClaudeSDK.CLINotFoundError, ~r/not found at/, fn ->
        CLIDiscovery.find_cli!("/nonexistent/path/to/claude")
      end
    end
  end


  describe "version/1" do
    test "returns error for non-existent binary" do
      assert {:error, {:spawn_failed, _}} = CLIDiscovery.version("/nonexistent/binary")
    end

    test "returns error for binary that exits non-zero" do
      # /usr/bin/false always exits with 1
      result = CLIDiscovery.version("/usr/bin/false")
      assert {:error, {:exit_code, 1, _}} = result
    end

    test "returns version for a valid command" do
      # Use bash --version as a proxy since we can't guarantee claude is installed
      script_path = Path.join(System.tmp_dir!(), "mock_version.sh")

      File.write!(script_path, """
      #!/usr/bin/env bash
      if [ "$1" = "-v" ]; then
        echo "1.0.0"
        exit 0
      fi
      exit 1
      """)

      File.chmod!(script_path, 0o755)

      assert {:ok, "1.0.0"} = CLIDiscovery.version(script_path)

      File.rm(script_path)
    end
  end
end
