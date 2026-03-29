defmodule ClaudeSDKTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.Types.{AssistantMessage, Options, ResultMessage, SystemMessage, TextBlock}

  @mock_cli_path Path.expand("support/mock_cli.sh", __DIR__)

  describe "query/2 with mock CLI" do
    test "streams messages and terminates on result" do
      opts = %Options{cli_path: @mock_cli_path}
      messages = ClaudeSDK.query("What is 2+2?", opts) |> Enum.to_list()

      # Should receive: system init, assistant, result
      types = Enum.map(messages, & &1.type)

      assert :system in types
      assert :assistant in types
      assert :result in types

      # Verify assistant content
      assistant = Enum.find(messages, &match?(%AssistantMessage{}, &1))
      assert assistant != nil
      [%TextBlock{text: text}] = assistant.message.content
      assert text == "The answer is 4."

      # Verify result
      result = Enum.find(messages, &match?(%ResultMessage{}, &1))
      assert result != nil
      assert result.is_error == false
      assert result.result == "The answer is 4."
    end

    test "system message has correct subtype" do
      opts = %Options{cli_path: @mock_cli_path}
      messages = ClaudeSDK.query("test", opts) |> Enum.to_list()

      system = Enum.find(messages, &match?(%SystemMessage{}, &1))
      assert system.subtype == "init"
    end

    test "result message includes cost and usage" do
      opts = %Options{cli_path: @mock_cli_path}
      messages = ClaudeSDK.query("test", opts) |> Enum.to_list()

      result = Enum.find(messages, &match?(%ResultMessage{}, &1))
      assert result.total_cost_usd == 0.001
      assert result.usage["input_tokens"] == 10
      assert result.usage["output_tokens"] == 5
    end
  end

  describe "Internal.wait_for_init_response" do
    test "returns error when control_response contains error" do
      # Send an error control_response to self before calling wait
      send(
        self(),
        {:claude_message,
         %{
           "type" => "control_response",
           "response" => %{"error" => "initialization failed"}
         }}
      )

      assert {:error, {:init_failed, "initialization failed"}} =
               ClaudeSDK.Internal.wait_for_init_response(1000)
    end

    test "returns ok with empty map when control_response has no response field" do
      send(self(), {:claude_message, %{"type" => "control_response"}})

      assert {:ok, %{}, []} = ClaudeSDK.Internal.wait_for_init_response(1000)
    end

    test "buffers non-control_response messages during init" do
      send(self(), {:claude_message, %{"type" => "system", "data" => "init"}})

      send(
        self(),
        {:claude_message,
         %{
           "type" => "control_response",
           "response" => %{"session_id" => "s1"}
         }}
      )

      assert {:ok, %{"session_id" => "s1"}, [%{"type" => "system", "data" => "init"}]} =
               ClaudeSDK.Internal.wait_for_init_response(1000)
    end
  end
end
