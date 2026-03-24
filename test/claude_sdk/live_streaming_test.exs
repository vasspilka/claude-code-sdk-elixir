defmodule ClaudeSDK.LiveStreamingTest do
  @moduledoc """
  Live integration tests for streaming behavior.

  Tests that the SDK correctly streams messages from the real CLI,
  including partial messages (StreamEvent), content blocks, and
  proper stream termination.

  Run with: mix test --only live
  """

  use ExUnit.Case

  alias ClaudeSDK.Types.{
    AssistantMessage,
    Options,
    ResultMessage,
    StreamEvent,
    SystemMessage,
    TextBlock,
    UserMessage
  }

  @moduletag :live

  @base_opts %Options{
    permission_mode: :bypass_permissions,
    max_turns: 1,
    model: "claude-haiku-4-5-20251001"
  }

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

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
  # 1. Stream yields correct message type sequence
  # ---------------------------------------------------------------------------
  describe "message type sequence" do
    @tag timeout: 60_000
    test "stream contains SystemMessage, AssistantMessage, and ends with ResultMessage" do
      messages = ClaudeSDK.query("Say hello", @base_opts) |> Enum.to_list()

      types =
        Enum.map(messages, fn
          %SystemMessage{} -> :system
          %UserMessage{} -> :user
          %AssistantMessage{} -> :assistant
          %ResultMessage{} -> :result
          %StreamEvent{} -> :stream_event
          other -> {:other, other}
        end)

      # Must end with result
      assert List.last(types) == :result

      # Must have at least one assistant message
      assert :assistant in types
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Partial messages / StreamEvent
  # ---------------------------------------------------------------------------
  describe "partial messages (StreamEvent)" do
    @tag timeout: 60_000
    test "include_partial_messages produces StreamEvent messages" do
      opts = %{@base_opts | include_partial_messages: true}

      messages = ClaudeSDK.query("Say hello world", opts) |> Enum.to_list()

      stream_events =
        Enum.filter(messages, fn
          %StreamEvent{} -> true
          _ -> false
        end)

      assert length(stream_events) > 0, "Expected at least one StreamEvent with partial messages"

      # Each StreamEvent should have an event map
      Enum.each(stream_events, fn %StreamEvent{event: event} ->
        assert is_map(event), "StreamEvent.event should be a map"
      end)
    end

    @tag timeout: 60_000
    test "stream events include content_block_delta with text" do
      opts = %{@base_opts | include_partial_messages: true}

      messages = ClaudeSDK.query("Say the word apple", opts) |> Enum.to_list()

      deltas =
        messages
        |> Enum.filter(fn
          %StreamEvent{event: %{"type" => "content_block_delta"}} -> true
          _ -> false
        end)

      # We should get at least one text delta
      assert length(deltas) > 0, "Expected content_block_delta events"
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Lazy stream consumption (Enum.take, early termination)
  # ---------------------------------------------------------------------------
  describe "lazy stream consumption" do
    @tag timeout: 60_000
    test "Enum.take works without hanging or leaking" do
      opts = %{@base_opts | include_partial_messages: true}

      # Take only first 3 messages — should not hang
      messages =
        ClaudeSDK.query("Tell me a long story about a dragon", opts)
        |> Enum.take(3)

      assert length(messages) == 3
    end

    @tag timeout: 60_000
    test "Enum.find stops after first match" do
      result =
        ClaudeSDK.query("Say hi", @base_opts)
        |> Enum.find(&match?(%AssistantMessage{}, &1))

      assert %AssistantMessage{} = result
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Structured output (json_schema)
  # ---------------------------------------------------------------------------
  describe "structured output" do
    @tag timeout: 120_000
    test "json_schema query completes without error" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "color" => %{"type" => "string"},
          "hex" => %{"type" => "string"}
        },
        "required" => ["color", "hex"]
      }

      opts = %{@base_opts | json_schema: schema, max_turns: 3}

      messages =
        ClaudeSDK.query("Give me one color and its hex code. Respond as JSON.", opts)
        |> Enum.to_list()

      result = find_result(messages)
      assert result != nil
      refute result.is_error
    end
  end

  # ---------------------------------------------------------------------------
  # 5. System prompt
  # ---------------------------------------------------------------------------
  describe "system prompt variations" do
    @tag timeout: 60_000
    test "append_system_prompt adds to default prompt" do
      opts = %{
        @base_opts
        | append_system_prompt: "Always end your response with the word ENDMARK."
      }

      messages = ClaudeSDK.query("Say something short", opts) |> Enum.to_list()
      text = extract_text(messages)

      assert String.contains?(String.downcase(text), "endmark"),
             "Expected ENDMARK in response, got: #{text}"
    end
  end

  # ---------------------------------------------------------------------------
  # 6. ResultMessage metadata
  # ---------------------------------------------------------------------------
  describe "ResultMessage metadata" do
    @tag timeout: 60_000
    test "result contains session_id, duration, num_turns" do
      messages = ClaudeSDK.query("Say ok", @base_opts) |> Enum.to_list()
      result = find_result(messages)

      assert result != nil
      assert is_binary(result.session_id)
      assert is_number(result.duration_ms) or is_nil(result.duration_ms)
      assert is_integer(result.num_turns) or is_nil(result.num_turns)
      assert result.subtype in ["success", "error"]
    end

    @tag timeout: 60_000
    test "result contains usage map" do
      messages = ClaudeSDK.query("Say ok", @base_opts) |> Enum.to_list()
      result = find_result(messages)

      assert is_map(result.usage)
    end
  end

  # ---------------------------------------------------------------------------
  # 7. AssistantMessage metadata
  # ---------------------------------------------------------------------------
  describe "AssistantMessage content" do
    @tag timeout: 60_000
    test "assistant message contains model identifier" do
      messages = ClaudeSDK.query("Say ok", @base_opts) |> Enum.to_list()

      assistant =
        Enum.find(messages, fn
          %AssistantMessage{} -> true
          _ -> false
        end)

      assert assistant != nil
      assert is_binary(assistant.message.model) or is_nil(assistant.message.model)
    end
  end

  # ---------------------------------------------------------------------------
  # 8. Effort levels
  # ---------------------------------------------------------------------------
  describe "effort levels" do
    @tag timeout: 60_000
    test "effort low produces a response" do
      opts = %{@base_opts | effort: "low"}
      messages = ClaudeSDK.query("What is 1+1?", opts) |> Enum.to_list()
      result = find_result(messages)

      assert result != nil
      refute result.is_error
    end
  end

  # ---------------------------------------------------------------------------
  # 9. Error handling
  # ---------------------------------------------------------------------------
  describe "error handling" do
    test "CLINotFoundError raised for invalid cli_path" do
      opts = %{@base_opts | cli_path: "/nonexistent/path/to/claude"}

      assert_raise ClaudeSDK.CLINotFoundError, fn ->
        ClaudeSDK.query("hello", opts) |> Enum.to_list()
      end
    end
  end
end
