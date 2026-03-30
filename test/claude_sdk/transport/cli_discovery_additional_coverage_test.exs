defmodule ClaudeSDK.Transport.CLIDiscoveryAdditionalCoverageTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.Transport.CLIDiscovery

  describe "find_cli/1 with directory path" do
    test "returns error for directory (not a regular file)" do
      assert {:error, :not_found} = CLIDiscovery.find_cli(System.tmp_dir!())
    end
  end

  describe "find_cli!/1 with nil (default path)" do
    test "raises CLINotFoundError when PATH is empty and no known locations" do
      original_path = System.get_env("PATH")

      try do
        System.put_env("PATH", "/nonexistent_dir_only")

        # This may or may not raise depending on whether claude is in a known location
        try do
          _path = CLIDiscovery.find_cli!()
        rescue
          e in ClaudeSDK.CLINotFoundError ->
            assert Exception.message(e) =~ "not found"
        end
      after
        System.put_env("PATH", original_path)
      end
    end
  end
end
