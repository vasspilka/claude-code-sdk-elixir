defmodule ClaudeSDK.Transport.CLIDiscoveryCoverageTest do
  use ExUnit.Case

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

  describe "find_cli(nil) when claude is not on PATH" do
    test "falls through to search_known_locations" do
      # Temporarily set PATH to empty to ensure claude is not found via find_executable
      original_path = System.get_env("PATH")

      try do
        System.put_env("PATH", "/nonexistent_dir_for_test")
        # This will try System.find_executable("claude") -> nil,
        # then search_known_locations which checks /usr/local/bin/claude etc.
        # Since those likely don't exist either, we expect :not_found
        result = CLIDiscovery.find_cli(nil)

        case result do
          {:ok, path} ->
            # One of the known locations exists (unlikely but valid)
            assert File.exists?(path)

          {:error, :not_found} ->
            # Expected path when claude isn't in known locations
            assert true
        end
      after
        System.put_env("PATH", original_path)
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
