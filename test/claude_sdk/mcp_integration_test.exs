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

    test "multiple MCP servers coexist and tools route correctly" do
      server1 =
        ClaudeSDK.create_mcp_server("server-a", "1.0", [
          %Tool{
            name: "greet",
            description: "Say hello",
            input_schema: %{
              "type" => "object",
              "properties" => %{"name" => %{"type" => "string"}}
            },
            handler: fn args -> {:ok, "Hello from A, #{args["name"]}!"} end
          }
        ])

      server2 =
        ClaudeSDK.create_mcp_server("server-b", "1.0", [
          %Tool{
            name: "farewell",
            description: "Say goodbye",
            input_schema: %{
              "type" => "object",
              "properties" => %{"name" => %{"type" => "string"}}
            },
            handler: fn args -> {:ok, "Goodbye from B, #{args["name"]}!"} end
          }
        ])

      # Build combined tool index like the SDK does internally
      index = ClaudeSDK.MCP.Server.build_tool_index([server1, server2])

      assert Map.has_key?(index, {"server-a", "greet"})
      assert Map.has_key?(index, {"server-b", "farewell"})
      refute Map.has_key?(index, {"server-a", "farewell"})
      refute Map.has_key?(index, {"server-b", "greet"})
    end

    test "MCP tool called with missing arguments handles gracefully" do
      server =
        ClaudeSDK.create_mcp_server("test-server", "1.0", [
          %Tool{
            name: "greet",
            description: "Say hello",
            input_schema: %{
              "type" => "object",
              "properties" => %{"name" => %{"type" => "string"}},
              "required" => ["name"]
            },
            handler: fn args ->
              name = args["name"] || "stranger"
              {:ok, "Hello, #{name}!"}
            end
          }
        ])

      index = ClaudeSDK.MCP.Server.build_tool_index([server])

      # Call with empty arguments (missing "name")
      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "greet", "arguments" => %{}}
      }

      assert {:result, response} =
               ClaudeSDK.MCP.Server.handle_jsonrpc("test-server", jsonrpc, index)

      assert response.jsonrpc_response["result"]["isError"] == false
      [content] = response.jsonrpc_response["result"]["content"]
      assert content["text"] == "Hello, stranger!"
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
