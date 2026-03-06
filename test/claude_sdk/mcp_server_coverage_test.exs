defmodule ClaudeSDK.MCP.ServerCoverageTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.MCP.{Server, Tool}

  describe "format_result with list" do
    test "returns list result as-is" do
      tool = %Tool{
        name: "list_tool",
        description: "Returns a list",
        input_schema: %{},
        handler: fn _args ->
          {:ok, [%{"type" => "text", "text" => "item1"}, %{"type" => "text", "text" => "item2"}]}
        end
      }

      server = Server.create("test-server", "1.0", [tool])
      index = Server.build_tool_index([server])

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "list_tool", "arguments" => %{}}
      }

      assert {:result, response} = Server.handle_jsonrpc("test-server", jsonrpc, index)
      content = response.jsonrpc_response["result"]["content"]
      assert length(content) == 2
      assert hd(content)["text"] == "item1"
    end
  end

  describe "format_result with non-standard types" do
    test "inspects atom results" do
      tool = %Tool{
        name: "atom_tool",
        description: "Returns an atom",
        input_schema: %{},
        handler: fn _args -> {:ok, :hello_world} end
      }

      server = Server.create("test-server", "1.0", [tool])
      index = Server.build_tool_index([server])

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "atom_tool", "arguments" => %{}}
      }

      assert {:result, response} = Server.handle_jsonrpc("test-server", jsonrpc, index)
      [content] = response.jsonrpc_response["result"]["content"]
      assert content["text"] == ":hello_world"
    end

    test "inspects tuple results" do
      tool = %Tool{
        name: "tuple_tool",
        description: "Returns a tuple",
        input_schema: %{},
        handler: fn _args -> {:ok, {1, 2, 3}} end
      }

      server = Server.create("test-server", "1.0", [tool])
      index = Server.build_tool_index([server])

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "tuple_tool", "arguments" => %{}}
      }

      assert {:result, response} = Server.handle_jsonrpc("test-server", jsonrpc, index)
      [content] = response.jsonrpc_response["result"]["content"]
      assert content["text"] == "{1, 2, 3}"
    end

    test "inspects integer results" do
      tool = %Tool{
        name: "int_tool",
        description: "Returns an integer",
        input_schema: %{},
        handler: fn _args -> {:ok, 42} end
      }

      server = Server.create("test-server", "1.0", [tool])
      index = Server.build_tool_index([server])

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "int_tool", "arguments" => %{}}
      }

      assert {:result, response} = Server.handle_jsonrpc("test-server", jsonrpc, index)
      [content] = response.jsonrpc_response["result"]["content"]
      assert content["text"] == "42"
    end
  end

  describe "handle_jsonrpc with missing params fields" do
    test "handles missing name in params" do
      tool = %Tool{
        name: "greet",
        description: "Say hello",
        input_schema: %{},
        handler: fn _args -> {:ok, "hi"} end
      }

      server = Server.create("test-server", "1.0", [tool])
      index = Server.build_tool_index([server])

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{}
      }

      # Missing "name" -> tool_name is "" -> not found
      assert {:result, response} = Server.handle_jsonrpc("test-server", jsonrpc, index)
      assert response.jsonrpc_response["error"]["code"] == -32601
    end

    test "handles missing arguments in params" do
      tool = %Tool{
        name: "greet",
        description: "Say hello",
        input_schema: %{},
        handler: fn args -> {:ok, "Hello, #{args["name"] || "world"}!"} end
      }

      server = Server.create("test-server", "1.0", [tool])
      index = Server.build_tool_index([server])

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "greet"}
      }

      # Missing "arguments" -> defaults to %{}
      assert {:result, response} = Server.handle_jsonrpc("test-server", jsonrpc, index)
      [content] = response.jsonrpc_response["result"]["content"]
      assert content["text"] == "Hello, world!"
    end
  end
end
