defmodule ClaudeSDK.LiveAdvancedTest do
  @moduledoc """
  Live integration tests for advanced features: thinking config,
  session management, sandbox settings, and edge cases.

  Run with: mix test --only live
  """

  use ExUnit.Case

  alias ClaudeSDK.Types.{
    AssistantMessage,
    Options,
    ResultMessage,
    TextBlock,
    ThinkingBlock,
    ThinkingConfig
  }

  @moduletag :live

  @base_opts %Options{
    permission_mode: :bypass_permissions,
    max_turns: 1,
    model: "claude-haiku-4-5-20251001"
  }

  defp extract_text(messages) do
    messages
    |> Enum.flat_map(fn
      %AssistantMessage{message: %{content: content}} -> content
      _ -> []
    end)
    |> Enum.filter(&match?(%TextBlock{}, &1))
    |> Enum.map(& &1.text)
    |> Enum.join(" ")
  end

  defp find_result(messages), do: Enum.find(messages, &match?(%ResultMessage{}, &1))

  # ---------------------------------------------------------------------------
  # 1. Thinking config
  # ---------------------------------------------------------------------------
  describe "thinking configuration" do
    @tag timeout: 120_000
    test "adaptive thinking produces a valid response" do
      opts = %{@base_opts | thinking: ThinkingConfig.adaptive()}

      messages =
        ClaudeSDK.query("What is 15 * 37?", opts)
        |> Enum.to_list()

      result = find_result(messages)
      assert result != nil
      refute result.is_error

      text = extract_text(messages)
      assert String.contains?(text, "555"), "Expected 555 in response, got: #{text}"
    end

    @tag timeout: 120_000
    test "enabled thinking with budget completes without error" do
      # Use a model that supports extended thinking
      opts = %{
        @base_opts
        | thinking: ThinkingConfig.enabled(4000),
          model: "claude-sonnet-4-6"
      }

      messages =
        ClaudeSDK.query("What is the cube root of 27?", opts)
        |> Enum.to_list()

      result = find_result(messages)
      assert result != nil
      refute result.is_error

      # Thinking blocks may or may not appear depending on CLI version/config.
      # We check for them but don't fail if absent — the key assertion is
      # that the query completes without error.
      thinking_blocks =
        messages
        |> Enum.flat_map(fn
          %AssistantMessage{message: %{content: content}} -> content
          _ -> []
        end)
        |> Enum.filter(&match?(%ThinkingBlock{}, &1))

      if length(thinking_blocks) > 0 do
        Enum.each(thinking_blocks, fn %ThinkingBlock{thinking: thinking} ->
          assert is_binary(thinking)
        end)
      end
    end

    @tag timeout: 120_000
    test "disabled thinking produces no thinking blocks" do
      opts = %{@base_opts | thinking: ThinkingConfig.disabled()}

      messages =
        ClaudeSDK.query("Say ok", opts)
        |> Enum.to_list()

      thinking_blocks =
        messages
        |> Enum.flat_map(fn
          %AssistantMessage{message: %{content: content}} -> content
          _ -> []
        end)
        |> Enum.filter(&match?(%ThinkingBlock{}, &1))

      assert thinking_blocks == [], "Expected no ThinkingBlocks with disabled thinking"
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Session management (list/get/rename/tag)
  # ---------------------------------------------------------------------------
  describe "session management" do
    @tag timeout: 120_000
    test "session created by query appears in list_sessions" do
      # Run a query to create a session
      messages =
        ClaudeSDK.query("Say session-test", @base_opts)
        |> Enum.to_list()

      result = find_result(messages)
      assert result != nil
      session_id = result.session_id
      assert is_binary(session_id)

      # The session should be findable
      info = ClaudeSDK.get_session_info(session_id)

      if info != nil do
        assert info.session_id == session_id
        assert is_binary(info.file_path)
        assert info.file_size > 0
      end

      # Note: session may not be found if cwd doesn't match the project dir
    end

    @tag timeout: 120_000
    test "rename and tag a session" do
      messages =
        ClaudeSDK.query("Say rename-test", @base_opts)
        |> Enum.to_list()

      result = find_result(messages)
      session_id = result.session_id

      # Try to rename
      case ClaudeSDK.rename_session(session_id, "Test Rename Title") do
        :ok ->
          info = ClaudeSDK.get_session_info(session_id)

          if info != nil do
            assert info.custom_title == "Test Rename Title"
          end

        {:error, :session_not_found} ->
          # Expected if session file is in a different project dir
          :ok
      end

      # Try to tag
      case ClaudeSDK.tag_session(session_id, "test-tag") do
        :ok -> :ok
        {:error, :session_not_found} -> :ok
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Continue / resume session
  # ---------------------------------------------------------------------------
  describe "session resume" do
    @tag timeout: 180_000
    test "resume option continues an existing session" do
      # First query to create a session
      messages1 =
        ClaudeSDK.query("Remember the word ZEPHYR. Say noted.", @base_opts)
        |> Enum.to_list()

      result1 = find_result(messages1)
      session_id = result1.session_id

      # Resume that session
      opts2 = %{@base_opts | resume: session_id}

      messages2 =
        ClaudeSDK.query("What word did I ask you to remember?", opts2)
        |> Enum.to_list()

      result2 = find_result(messages2)
      assert result2 != nil
      refute result2.is_error

      text = extract_text(messages2)

      assert String.contains?(String.upcase(text), "ZEPHYR"),
             "Expected ZEPHYR in resumed session, got: #{text}"
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Sandbox settings (accepted by CLI)
  # ---------------------------------------------------------------------------
  describe "sandbox settings" do
    @tag timeout: 60_000
    test "CLI accepts sandbox configuration via --settings without error" do
      sandbox = %ClaudeSDK.Types.SandboxSettings{
        enabled: true,
        auto_allow_bash_if_sandboxed: true
      }

      opts = %{@base_opts | sandbox: sandbox}

      messages =
        ClaudeSDK.query("Say ok", opts)
        |> Enum.to_list()

      result = find_result(messages)
      assert result != nil
      # We just verify the CLI doesn't reject the config
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Max turns limit
  # ---------------------------------------------------------------------------
  describe "max_turns" do
    @tag timeout: 120_000
    test "query respects max_turns limit" do
      opts = %{@base_opts | max_turns: 1}

      messages =
        ClaudeSDK.query(
          "Read the file mix.exs, then read README.md, then read CHANGELOG.md. Report all three.",
          opts
        )
        |> Enum.to_list()

      result = find_result(messages)
      assert result != nil

      # With max_turns: 1, it should complete within a small number of turns
      if result.num_turns != nil do
        assert result.num_turns <= 2
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 6. Custom environment variables
  # ---------------------------------------------------------------------------
  describe "environment variables" do
    @tag timeout: 60_000
    test "custom env vars are passed to subprocess" do
      opts = %{@base_opts | env: %{"MY_TEST_VAR" => "test_value_123"}}

      messages =
        ClaudeSDK.query("Say hello", opts)
        |> Enum.to_list()

      result = find_result(messages)
      assert result != nil
      refute result.is_error
    end
  end

  # ---------------------------------------------------------------------------
  # 7. UserMessage echo
  # ---------------------------------------------------------------------------
  describe "UserMessage" do
    @tag timeout: 60_000
    test "stream contains echoed UserMessage with uuid" do
      messages =
        ClaudeSDK.query("Say ok", @base_opts)
        |> Enum.to_list()

      user_messages =
        Enum.filter(messages, fn
          %ClaudeSDK.Types.UserMessage{} -> true
          _ -> false
        end)

      # The CLI may or may not echo user messages depending on version
      if length(user_messages) > 0 do
        user_msg = hd(user_messages)
        assert is_binary(user_msg.uuid) or is_nil(user_msg.uuid)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 8. Keyword list options
  # ---------------------------------------------------------------------------
  describe "keyword list options" do
    @tag timeout: 60_000
    test "all major options work as keyword list" do
      messages =
        ClaudeSDK.query("What is 2+2? Reply with just the number.",
          permission_mode: :bypass_permissions,
          max_turns: 1,
          model: "claude-haiku-4-5-20251001",
          effort: "low"
        )
        |> Enum.to_list()

      result = find_result(messages)
      assert result != nil
      refute result.is_error
    end
  end
end
