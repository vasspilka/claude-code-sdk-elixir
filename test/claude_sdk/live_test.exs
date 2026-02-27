defmodule ClaudeSDK.LiveTest do
  @moduledoc """
  Integration tests against the real Claude CLI.

  These tests are excluded by default. Run them with:

      mix test --only live

  Requirements:
  - `claude` CLI installed and on PATH
  - Valid authentication (API key or claude.ai token)
  - Internet access
  """

  use ExUnit.Case

  alias ClaudeSDK.Types.Options

  @moduletag :live

  describe "basic query" do
    @tag timeout: 60_000
    test "sends prompt and receives response" do
      opts = %Options{
        permission_mode: :bypass_permissions,
        max_turns: 1,
        model: "claude-haiku-4-5-20251001"
      }

      messages =
        ClaudeSDK.query("Reply with exactly one word: pineapple", opts)
        |> Enum.to_list()

      assert length(messages) >= 2

      # Should have at least one AssistantMessage
      assistant_messages =
        Enum.filter(messages, fn
          %ClaudeSDK.Types.AssistantMessage{} -> true
          _ -> false
        end)

      assert length(assistant_messages) >= 1

      # Should end with ResultMessage
      last = List.last(messages)
      assert %ClaudeSDK.Types.ResultMessage{} = last
      refute last.is_error
      assert is_binary(last.session_id)
    end

    @tag timeout: 60_000
    test "receives SystemMessage with init subtype" do
      opts = %Options{
        permission_mode: :bypass_permissions,
        max_turns: 1,
        model: "claude-haiku-4-5-20251001"
      }

      messages =
        ClaudeSDK.query("Say ok", opts)
        |> Enum.to_list()

      system_msgs =
        Enum.filter(messages, fn
          %ClaudeSDK.Types.SystemMessage{subtype: "init"} -> true
          _ -> false
        end)

      assert length(system_msgs) >= 1
    end

    @tag timeout: 60_000
    test "parses text content blocks" do
      opts = %Options{
        permission_mode: :bypass_permissions,
        max_turns: 1,
        model: "claude-haiku-4-5-20251001"
      }

      messages =
        ClaudeSDK.query("Reply with exactly: test123", opts)
        |> Enum.to_list()

      text_blocks =
        messages
        |> Enum.flat_map(fn
          %ClaudeSDK.Types.AssistantMessage{message: %{content: content}} -> content
          _ -> []
        end)
        |> Enum.filter(fn
          %ClaudeSDK.Types.TextBlock{} -> true
          _ -> false
        end)

      assert length(text_blocks) >= 1

      all_text =
        text_blocks
        |> Enum.map(& &1.text)
        |> Enum.join(" ")

      assert String.contains?(String.downcase(all_text), "test123")
    end
  end

  describe "options" do
    @tag timeout: 60_000
    test "system_prompt is respected" do
      opts = %Options{
        permission_mode: :bypass_permissions,
        max_turns: 1,
        model: "claude-haiku-4-5-20251001",
        system_prompt: "You must always respond with exactly the word BANANA and nothing else."
      }

      messages =
        ClaudeSDK.query("What is your favorite fruit?", opts)
        |> Enum.to_list()

      text =
        messages
        |> Enum.flat_map(fn
          %ClaudeSDK.Types.AssistantMessage{message: %{content: content}} -> content
          _ -> []
        end)
        |> Enum.filter(&match?(%ClaudeSDK.Types.TextBlock{}, &1))
        |> Enum.map(& &1.text)
        |> Enum.join(" ")

      assert String.contains?(String.downcase(text), "banana")
    end

    @tag timeout: 60_000
    test "result includes usage and cost" do
      opts = %Options{
        permission_mode: :bypass_permissions,
        max_turns: 1,
        model: "claude-haiku-4-5-20251001"
      }

      messages =
        ClaudeSDK.query("Say hi", opts)
        |> Enum.to_list()

      result =
        Enum.find(messages, fn
          %ClaudeSDK.Types.ResultMessage{} -> true
          _ -> false
        end)

      assert result != nil
      assert is_map(result.usage)
      assert is_number(result.total_cost_usd) or is_nil(result.total_cost_usd)
      assert is_number(result.duration_ms) or is_nil(result.duration_ms)
    end
  end

  describe "keyword opts" do
    @tag timeout: 60_000
    test "accepts keyword list options" do
      messages =
        ClaudeSDK.query("Say ok",
          permission_mode: :bypass_permissions,
          max_turns: 1,
          model: "claude-haiku-4-5-20251001"
        )
        |> Enum.to_list()

      result =
        Enum.find(messages, fn
          %ClaudeSDK.Types.ResultMessage{} -> true
          _ -> false
        end)

      assert result != nil
      refute result.is_error
    end
  end
end
