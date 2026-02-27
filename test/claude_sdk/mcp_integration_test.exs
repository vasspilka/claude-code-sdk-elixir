defmodule ClaudeSDK.MCPIntegrationTest do
  use ExUnit.Case

  alias ClaudeSDK.MCP.Tool
  alias ClaudeSDK.Types.Options

  @mock_cli_path Path.expand("../support/mock_cli_mcp.sh", __DIR__)

  describe "MCP server integration" do
    test "MCP tool call is handled and stream completes" do
      server =
        ClaudeSDK.create_mcp_server("test-server", "1.0", [
          %Tool{
            name: "greet",
            description: "Say hello",
            input_schema: %{
              "type" => "object",
              "properties" => %{"name" => %{"type" => "string"}}
            },
            handler: fn args -> {:ok, "Hello, #{args["name"]}!"} end
          }
        ])

      opts = %Options{
        cli_path: @mock_cli_path,
        mcp_servers: [server]
      }

      messages =
        ClaudeSDK.query("test mcp", opts)
        |> Enum.to_list()

      # Should have assistant message and result (control_request was handled internally)
      assistant =
        Enum.find(messages, fn
          %ClaudeSDK.Types.AssistantMessage{} -> true
          _ -> false
        end)

      assert assistant != nil
      [text_block | _] = assistant.message.content
      assert text_block.text == "MCP tool executed."

      result =
        Enum.find(messages, fn
          %ClaudeSDK.Types.ResultMessage{} -> true
          _ -> false
        end)

      assert result != nil
    end

    test "MCP tool error is returned as isError response" do
      server =
        ClaudeSDK.create_mcp_server("test-server", "1.0", [
          %Tool{
            name: "greet",
            description: "Say hello",
            input_schema: %{},
            handler: fn _args -> {:error, "Tool broke"} end
          }
        ])

      opts = %Options{
        cli_path: @mock_cli_path,
        mcp_servers: [server]
      }

      # Should still complete without crashing
      messages =
        ClaudeSDK.query("test mcp error", opts)
        |> Enum.to_list()

      assert length(messages) > 0
    end
  end
end
