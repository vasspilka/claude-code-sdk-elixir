defmodule ClaudeSDK.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.MCP.{Server, Tool}

  defp test_tools do
    [
      %Tool{
        name: "greet",
        description: "Say hello",
        input_schema: %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}},
        handler: fn args -> {:ok, "Hello, #{args["name"]}!"} end
      },
      %Tool{
        name: "add",
        description: "Add two numbers",
        input_schema: %{
          "type" => "object",
          "properties" => %{"a" => %{"type" => "number"}, "b" => %{"type" => "number"}}
        },
        handler: fn args -> {:ok, args["a"] + args["b"]} end
      }
    ]
  end

  describe "create/3" do
    test "creates server config with name, version, and tools" do
      server = Server.create("test-server", "1.0", test_tools())

      assert server.name == "test-server"
      assert server.version == "1.0"
      assert length(server.tools) == 2
    end
  end

  describe "to_cli_config/1" do
    test "converts servers to CLI-compatible config map" do
      server = Server.create("my-server", "2.0", test_tools())
      config = Server.to_cli_config([server])

      assert %{"mcpServers" => servers} = config
      assert Map.has_key?(servers, "my-server")

      server_config = servers["my-server"]
      assert server_config["type"] == "sdk"
      assert server_config["version"] == "2.0"
      assert length(server_config["tools"]) == 2
    end

    test "strips handler functions from tool configs" do
      server = Server.create("s", "1.0", test_tools())
      config = Server.to_cli_config([server])

      tool = hd(config["mcpServers"]["s"]["tools"])
      assert Map.has_key?(tool, "name")
      assert Map.has_key?(tool, "description")
      assert Map.has_key?(tool, "inputSchema")
      refute Map.has_key?(tool, "handler")
    end

    test "handles multiple servers" do
      s1 = Server.create("server-a", "1.0", [hd(test_tools())])
      s2 = Server.create("server-b", "1.0", [List.last(test_tools())])
      config = Server.to_cli_config([s1, s2])

      assert Map.has_key?(config["mcpServers"], "server-a")
      assert Map.has_key?(config["mcpServers"], "server-b")
    end

    test "preserves input schema" do
      server = Server.create("s", "1.0", test_tools())
      config = Server.to_cli_config([server])

      greet_tool = Enum.find(config["mcpServers"]["s"]["tools"], &(&1["name"] == "greet"))
      assert greet_tool["inputSchema"]["type"] == "object"
      assert Map.has_key?(greet_tool["inputSchema"]["properties"], "name")
    end
  end

  describe "build_tool_index/1" do
    test "creates lookup by {server_name, tool_name}" do
      server = Server.create("my-server", "1.0", test_tools())
      index = Server.build_tool_index([server])

      assert Map.has_key?(index, {"my-server", "greet"})
      assert Map.has_key?(index, {"my-server", "add"})
      assert %Tool{name: "greet"} = index[{"my-server", "greet"}]
    end

    test "handles multiple servers" do
      s1 = Server.create("s1", "1.0", [hd(test_tools())])
      s2 = Server.create("s2", "1.0", [List.last(test_tools())])
      index = Server.build_tool_index([s1, s2])

      assert Map.has_key?(index, {"s1", "greet"})
      assert Map.has_key?(index, {"s2", "add"})
      refute Map.has_key?(index, {"s1", "add"})
    end
  end

  describe "handle_jsonrpc/3" do
    setup do
      server = Server.create("test-server", "1.0", test_tools())
      index = Server.build_tool_index([server])
      %{index: index}
    end

    test "routes tools/call to correct handler", %{index: index} do
      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "greet", "arguments" => %{"name" => "Alice"}}
      }

      assert {:result, response} = Server.handle_jsonrpc("test-server", jsonrpc, index)
      assert response.jsonrpc_response["id"] == 1
      assert response.jsonrpc_response["result"]["isError"] == false

      [content_block] = response.jsonrpc_response["result"]["content"]
      assert content_block["type"] == "text"
      assert content_block["text"] == "Hello, Alice!"
    end

    test "returns error for unknown tool", %{index: index} do
      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 2,
        "method" => "tools/call",
        "params" => %{"name" => "nonexistent", "arguments" => %{}}
      }

      assert {:result, response} = Server.handle_jsonrpc("test-server", jsonrpc, index)
      assert response.jsonrpc_response["error"]["code"] == -32601
      assert response.jsonrpc_response["error"]["message"] =~ "Tool not found"
    end

    test "returns error for unknown server", %{index: index} do
      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 3,
        "method" => "tools/call",
        "params" => %{"name" => "greet", "arguments" => %{"name" => "Bob"}}
      }

      assert {:result, response} = Server.handle_jsonrpc("wrong-server", jsonrpc, index)
      assert response.jsonrpc_response["error"]["code"] == -32601
    end

    test "handles handler returning {:error, reason}" do
      error_tool = %Tool{
        name: "fail",
        description: "Always fails",
        input_schema: %{},
        handler: fn _args -> {:error, "Something broke"} end
      }

      server = Server.create("err-server", "1.0", [error_tool])
      index = Server.build_tool_index([server])

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 4,
        "method" => "tools/call",
        "params" => %{"name" => "fail", "arguments" => %{}}
      }

      assert {:result, response} = Server.handle_jsonrpc("err-server", jsonrpc, index)
      assert response.jsonrpc_response["result"]["isError"] == true

      [content] = response.jsonrpc_response["result"]["content"]
      assert content["text"] == "Something broke"
    end

    test "handles numeric results", %{index: index} do
      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 5,
        "method" => "tools/call",
        "params" => %{"name" => "add", "arguments" => %{"a" => 3, "b" => 4}}
      }

      assert {:result, response} = Server.handle_jsonrpc("test-server", jsonrpc, index)
      [content] = response.jsonrpc_response["result"]["content"]
      assert content["text"] == "7"
    end

    test "handles map results as JSON" do
      map_tool = %Tool{
        name: "info",
        description: "Return info",
        input_schema: %{},
        handler: fn _args -> {:ok, %{"status" => "ok"}} end
      }

      server = Server.create("map-server", "1.0", [map_tool])
      index = Server.build_tool_index([server])

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 6,
        "method" => "tools/call",
        "params" => %{"name" => "info", "arguments" => %{}}
      }

      assert {:result, response} = Server.handle_jsonrpc("map-server", jsonrpc, index)
      [content] = response.jsonrpc_response["result"]["content"]
      assert {:ok, %{"status" => "ok"}} = Jason.decode(content["text"])
    end

    test "handles tools/list method and returns registered tools", %{index: index} do
      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 7,
        "method" => "tools/list"
      }

      assert {:result, response} = Server.handle_jsonrpc("test-server", jsonrpc, index)
      tools = response.jsonrpc_response["result"]["tools"]
      assert length(tools) == 2

      tool_names = Enum.map(tools, & &1["name"]) |> Enum.sort()
      assert tool_names == ["add", "greet"]

      greet = Enum.find(tools, &(&1["name"] == "greet"))
      assert greet["description"] == "Say hello"
      assert greet["inputSchema"]["type"] == "object"
    end

    test "tools/list returns only tools for the requested server" do
      s1 = Server.create("server-a", "1.0", [hd(test_tools())])
      s2 = Server.create("server-b", "1.0", [List.last(test_tools())])
      index = Server.build_tool_index([s1, s2])

      jsonrpc = %{"jsonrpc" => "2.0", "id" => 10, "method" => "tools/list"}

      assert {:result, response} = Server.handle_jsonrpc("server-a", jsonrpc, index)
      tools = response.jsonrpc_response["result"]["tools"]
      assert length(tools) == 1
      assert hd(tools)["name"] == "greet"
    end

    test "handles unsupported methods", %{index: index} do
      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 8,
        "method" => "unknown/method"
      }

      assert {:result, response} = Server.handle_jsonrpc("test-server", jsonrpc, index)
      assert response.jsonrpc_response["error"]["code"] == -32601
    end

    test "truncates results exceeding 1MB" do
      large_tool = %Tool{
        name: "large",
        description: "Returns large data",
        input_schema: %{},
        handler: fn _args -> {:ok, String.duplicate("x", 1_100_000)} end
      }

      server = Server.create("large-server", "1.0", [large_tool])
      index = Server.build_tool_index([server])

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 9,
        "method" => "tools/call",
        "params" => %{"name" => "large", "arguments" => %{}}
      }

      assert {:result, response} = Server.handle_jsonrpc("large-server", jsonrpc, index)
      [content] = response.jsonrpc_response["result"]["content"]
      assert content["text"] =~ "truncated: result exceeded 1MB limit"
      assert byte_size(content["text"]) < 1_100_000
    end
  end
end
