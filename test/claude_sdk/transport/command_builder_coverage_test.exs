defmodule ClaudeSDK.Transport.CommandBuilderCoverageTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.Transport.CommandBuilder
  alias ClaudeSDK.Types.Options

  describe "permission_prompt_tool" do
    test "can_use_tool auto-configures --permission-prompt-tool stdio" do
      callback = fn _tool, _input -> :allow end

      args = CommandBuilder.build_args(%Options{can_use_tool: callback})

      idx = Enum.find_index(args, &(&1 == "--permission-prompt-tool"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "stdio"
    end

    test "permission_prompt_tool_name alone sets custom tool name" do
      args =
        CommandBuilder.build_args(%Options{
          permission_prompt_tool_name: "my-custom-tool"
        })

      idx = Enum.find_index(args, &(&1 == "--permission-prompt-tool"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "my-custom-tool"
    end

    test "neither set produces no --permission-prompt-tool flag" do
      args = CommandBuilder.build_args(%Options{})

      refute Enum.member?(args, "--permission-prompt-tool")
    end
  end

  describe "ThinkingConfig struct" do
    test "adds --thinking as plain string and --max-thinking-tokens from ThinkingConfig struct" do
      config = %ClaudeSDK.Types.ThinkingConfig{type: "adaptive", budget_tokens: 5000}
      args = CommandBuilder.build_args(%Options{thinking: config})

      idx = Enum.find_index(args, &(&1 == "--thinking"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "adaptive"

      tokens_idx = Enum.find_index(args, &(&1 == "--max-thinking-tokens"))
      assert tokens_idx != nil
      assert Enum.at(args, tokens_idx + 1) == "5000"
    end

    test "thinking disabled does not add --max-thinking-tokens" do
      config = %ClaudeSDK.Types.ThinkingConfig{type: "disabled"}
      args = CommandBuilder.build_args(%Options{thinking: config})

      idx = Enum.find_index(args, &(&1 == "--thinking"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "disabled"

      refute Enum.any?(args, &(&1 == "--max-thinking-tokens"))
    end
  end

  describe "SandboxSettings struct" do
    test "sandbox is merged into --settings from SandboxSettings struct" do
      settings = %ClaudeSDK.Types.SandboxSettings{enabled: true, network: "deny"}
      args = CommandBuilder.build_args(%Options{sandbox: settings})

      refute "--sandbox" in args

      idx = Enum.find_index(args, &(&1 == "--settings"))
      assert idx != nil
      {:ok, parsed} = Jason.decode(Enum.at(args, idx + 1))
      assert parsed["sandbox"]["enabled"] == true
      assert parsed["sandbox"]["network"] == "deny"
    end
  end

  describe "setting_sources" do
    test "adds --setting-sources as comma-separated list" do
      args =
        CommandBuilder.build_args(%Options{
          setting_sources: ["/path/to/settings1.json", "/path/to/settings2.json"]
        })

      idx = Enum.find_index(args, &(&1 == "--setting-sources"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "/path/to/settings1.json,/path/to/settings2.json"
    end
  end

  describe "3-arity can_use_tool callback" do
    test "adds --permission-prompt-tool for 3-arity callback" do
      callback = fn _tool, _input, _context -> :allow end
      args = CommandBuilder.build_args(%Options{can_use_tool: callback})

      idx = Enum.find_index(args, &(&1 == "--permission-prompt-tool"))
      assert idx != nil
      assert Enum.at(args, idx + 1) == "stdio"
    end
  end

  describe "nil checkpointing env" do
    test "omits checkpointing env var when nil" do
      env = CommandBuilder.build_env(%Options{enable_file_checkpointing: nil})

      refute Enum.any?(env, fn {k, _} ->
               k == "CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING"
             end)
    end
  end

  describe "empty list edge cases" do
    test "omits --allowed-tools when empty list" do
      args = CommandBuilder.build_args(%Options{allowed_tools: []})
      refute "--allowed-tools" in args
    end

    test "omits --disallowed-tools when empty list" do
      args = CommandBuilder.build_args(%Options{disallowed_tools: []})
      refute "--disallowed-tools" in args
    end
  end

  describe "unknown permission mode" do
    test "omits --permission-mode for unknown mode atom" do
      args = CommandBuilder.build_args(%Options{permission_mode: :nonexistent})
      refute "--permission-mode" in args
    end
  end

  describe "tools nil" do
    test "omits --tools when nil" do
      args = CommandBuilder.build_args(%Options{tools: nil})
      refute "--tools" in args
    end
  end
end
