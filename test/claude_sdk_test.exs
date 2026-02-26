defmodule ClaudeSDKTest do
  use ExUnit.Case

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
end
