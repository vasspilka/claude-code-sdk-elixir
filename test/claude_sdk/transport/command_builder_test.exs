defmodule ClaudeSDK.Transport.CommandBuilderTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.Transport.CommandBuilder
  alias ClaudeSDK.Types.Options

  describe "build_args/1" do
    test "includes base args for default options" do
      args = CommandBuilder.build_args(%Options{})

      assert "--output-format" in args
      assert "stream-json" in args
      assert "--input-format" in args
      assert "--verbose" in args
    end

    test "adds --model when set" do
      args = CommandBuilder.build_args(%Options{model: "claude-sonnet-4-20250514"})

      assert_flag(args, "--model", "claude-sonnet-4-20250514")
    end

    test "adds --system-prompt when set" do
      args = CommandBuilder.build_args(%Options{system_prompt: "You are helpful."})

      assert_flag(args, "--system-prompt", "You are helpful.")
    end

    test "adds --append-system-prompt when set" do
      args = CommandBuilder.build_args(%Options{append_system_prompt: "Be concise."})

      assert_flag(args, "--append-system-prompt", "Be concise.")
    end

    test "adds --max-turns when set" do
      args = CommandBuilder.build_args(%Options{max_turns: 5})

      assert_flag(args, "--max-turns", "5")
    end

    test "adds --max-budget-usd when set" do
      args = CommandBuilder.build_args(%Options{max_budget_usd: 1.5})

      assert_flag(args, "--max-budget-usd", "1.5")
    end

    test "adds --max-thinking-tokens when set" do
      args = CommandBuilder.build_args(%Options{max_thinking_tokens: 10_000})

      assert_flag(args, "--max-thinking-tokens", "10000")
    end

    test "adds --permission-mode with correct mapping" do
      assert_flag(
        CommandBuilder.build_args(%Options{permission_mode: :default}),
        "--permission-mode",
        "default"
      )

      assert_flag(
        CommandBuilder.build_args(%Options{permission_mode: :accept_edits}),
        "--permission-mode",
        "acceptEdits"
      )

      assert_flag(
        CommandBuilder.build_args(%Options{permission_mode: :bypass_permissions}),
        "--permission-mode",
        "bypassPermissions"
      )

      assert_flag(
        CommandBuilder.build_args(%Options{permission_mode: :plan}),
        "--permission-mode",
        "plan"
      )
    end

    test "adds --continue flag when true" do
      args = CommandBuilder.build_args(%Options{continue: true})
      assert "--continue" in args
    end

    test "omits --continue flag when false" do
      args = CommandBuilder.build_args(%Options{continue: false})
      refute "--continue" in args
    end

    test "adds --resume with session ID" do
      args = CommandBuilder.build_args(%Options{resume: "session-abc"})

      assert_flag(args, "--resume", "session-abc")
    end

    test "adds --fork-session flag when true" do
      args = CommandBuilder.build_args(%Options{fork_session: true})
      assert "--fork-session" in args
    end

    test "adds --include-partial-messages flag when true" do
      args = CommandBuilder.build_args(%Options{include_partial_messages: true})
      assert "--include-partial-messages" in args
    end

    test "adds --effort when set" do
      args = CommandBuilder.build_args(%Options{effort: "high"})
      assert_flag(args, "--effort", "high")
    end

    test "adds --tools as comma-separated list" do
      args = CommandBuilder.build_args(%Options{tools: ["Read", "Write", "Bash"]})
      assert_flag(args, "--tools", "Read,Write,Bash")
    end

    test "adds --tools as 'default' for :default" do
      args = CommandBuilder.build_args(%Options{tools: :default})
      assert_flag(args, "--tools", "default")
    end

    test "adds --allowed-tools as comma-separated list" do
      args = CommandBuilder.build_args(%Options{allowed_tools: ["Read"]})
      assert_flag(args, "--allowed-tools", "Read")
    end

    test "adds --disallowed-tools as comma-separated list" do
      args = CommandBuilder.build_args(%Options{disallowed_tools: ["Bash"]})
      assert_flag(args, "--disallowed-tools", "Bash")
    end

    test "adds --json-schema as encoded JSON" do
      schema = %{"type" => "object", "properties" => %{"answer" => %{"type" => "string"}}}
      args = CommandBuilder.build_args(%Options{json_schema: schema})

      idx = Enum.find_index(args, &(&1 == "--json-schema"))
      assert idx != nil
      assert {:ok, ^schema} = Jason.decode(Enum.at(args, idx + 1))
    end

    test "adds --settings as encoded JSON" do
      settings = %{"key" => "value"}
      args = CommandBuilder.build_args(%Options{settings: settings})

      idx = Enum.find_index(args, &(&1 == "--settings"))
      assert idx != nil
      assert {:ok, ^settings} = Jason.decode(Enum.at(args, idx + 1))
    end

    test "adds --mcp-config as string path" do
      args = CommandBuilder.build_args(%Options{mcp_config: "/path/to/config.json"})
      assert_flag(args, "--mcp-config", "/path/to/config.json")
    end

    test "adds --mcp-config as encoded JSON map" do
      config = %{"servers" => %{}}
      args = CommandBuilder.build_args(%Options{mcp_config: config})

      idx = Enum.find_index(args, &(&1 == "--mcp-config"))
      assert idx != nil
      assert {:ok, ^config} = Jason.decode(Enum.at(args, idx + 1))
    end

    test "adds repeated --add-dir flags" do
      args = CommandBuilder.build_args(%Options{add_dirs: ["/dir1", "/dir2"]})

      pairs = chunk_flags(args, "--add-dir")
      assert ["/dir1", "/dir2"] = pairs
    end

    test "adds repeated --plugin-dir flags" do
      args = CommandBuilder.build_args(%Options{plugin_dirs: ["/p1"]})

      pairs = chunk_flags(args, "--plugin-dir")
      assert ["/p1"] = pairs
    end

    test "appends extra_args at the end" do
      args = CommandBuilder.build_args(%Options{extra_args: ["--custom", "val"]})

      assert List.last(args) == "val"
      assert Enum.at(args, -2) == "--custom"
    end

    test "omits nil options" do
      args = CommandBuilder.build_args(%Options{})

      refute "--model" in args
      refute "--system-prompt" in args
      refute "--max-turns" in args
      refute "--permission-mode" in args
      refute "--resume" in args
    end
  end

  describe "build_env/1" do
    test "includes SDK entrypoint and version" do
      env = CommandBuilder.build_env(%Options{})

      assert {"CLAUDE_CODE_ENTRYPOINT", "sdk-elixir"} in env
      assert {"CLAUDE_AGENT_SDK_VERSION", "0.1.0"} in env
    end

    test "includes user-provided env vars" do
      env = CommandBuilder.build_env(%Options{env: %{"MY_KEY" => "my_val"}})

      assert {"MY_KEY", "my_val"} in env
    end

    test "converts atom keys and values to strings" do
      env = CommandBuilder.build_env(%Options{env: %{foo: :bar}})

      assert {"foo", "bar"} in env
    end
  end

  # Helpers

  defp assert_flag(args, flag, value) do
    idx = Enum.find_index(args, &(&1 == flag))
    assert idx != nil, "Expected flag #{flag} in args: #{inspect(args)}"
    assert Enum.at(args, idx + 1) == value
  end

  defp chunk_flags(args, flag) do
    args
    |> Enum.chunk_every(2, 1)
    |> Enum.filter(fn
      [^flag, _val] -> true
      _ -> false
    end)
    |> Enum.map(fn [_, val] -> val end)
  end
end
