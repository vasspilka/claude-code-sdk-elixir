defmodule ClaudeSDK.PermissionTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.Types.Options

  @mock_cli_path Path.expand("../support/mock_cli_permission.sh", __DIR__)

  describe "permission callback integration" do
    test "deny callback produces 'Tool was denied' response" do
      opts = %Options{
        cli_path: @mock_cli_path,
        can_use_tool: fn _tool, _input ->
          {:deny, "Not allowed"}
        end
      }

      messages =
        ClaudeSDK.query("test permission deny", opts)
        |> Enum.to_list()

      # Find the assistant message
      assistant =
        Enum.find(messages, fn
          %ClaudeSDK.Types.AssistantMessage{} -> true
          _ -> false
        end)

      assert assistant != nil
      [text_block | _] = assistant.message.content
      assert text_block.text == "Tool was denied."
    end

    test "allow callback produces 'Tool was allowed' response" do
      opts = %Options{
        cli_path: @mock_cli_path,
        can_use_tool: fn _tool, _input ->
          :allow
        end
      }

      messages =
        ClaudeSDK.query("test permission allow", opts)
        |> Enum.to_list()

      assistant =
        Enum.find(messages, fn
          %ClaudeSDK.Types.AssistantMessage{} -> true
          _ -> false
        end)

      assert assistant != nil
      [text_block | _] = assistant.message.content
      assert text_block.text == "Tool was allowed."
    end

    test "stream completes with ResultMessage" do
      opts = %Options{
        cli_path: @mock_cli_path,
        can_use_tool: fn _tool, _input -> :allow end
      }

      messages =
        ClaudeSDK.query("test", opts)
        |> Enum.to_list()

      result =
        Enum.find(messages, fn
          %ClaudeSDK.Types.ResultMessage{} -> true
          _ -> false
        end)

      assert result != nil
      assert result.session_id == "mock-session"
    end
  end
end
