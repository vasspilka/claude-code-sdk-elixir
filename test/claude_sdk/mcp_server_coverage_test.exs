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
      content = response["result"]["content"]
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
      [content] = response["result"]["content"]
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
      [content] = response["result"]["content"]
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
      [content] = response["result"]["content"]
      assert content["text"] == "42"
    end
  end

  describe "truncate_utf8_safe edge cases" do
    @tag :capture_log
    test "truncation splitting a multi-byte codepoint produces valid UTF-8" do
      # Build a >1MB string that ends with multi-byte characters (emoji = 4 bytes each)
      padding = String.duplicate("a", 1_048_570)
      # Add enough emoji to push over 1MB; truncation will split mid-codepoint
      emoji_tail = String.duplicate("🎉", 10)
      large_string = padding <> emoji_tail

      tool = %Tool{
        name: "utf8_tool",
        description: "Returns multi-byte data",
        input_schema: %{},
        handler: fn _args -> {:ok, large_string} end
      }

      server = Server.create("utf8-server", "1.0", [tool])
      index = Server.build_tool_index([server])

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "utf8_tool", "arguments" => %{}}
      }

      assert {:result, response} = Server.handle_jsonrpc("utf8-server", jsonrpc, index)
      [content] = response["result"]["content"]
      assert content["text"] =~ "truncated: result exceeded 1MB limit"
      # Result must be valid UTF-8
      assert String.valid?(content["text"])
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
      assert response["error"]["code"] == -32601
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
      [content] = response["result"]["content"]
      assert content["text"] == "Hello, world!"
    end
  end

  describe "handle_jsonrpc notifications (no id field)" do
    test "JSONRPC notification (method but no id) returns empty result" do
      assert {:result, %{}} =
               Server.handle_jsonrpc("s", %{"method" => "notifications/initialized"}, %{})
    end

    test "catch-all for messages without id or method returns empty result" do
      assert {:result, %{}} = Server.handle_jsonrpc("s", %{"some" => "data"}, %{})
    end
  end

  describe "handler exception" do
    @tag :capture_log
    test "handler that raises returns isError response" do
      tool = %Tool{
        name: "crasher",
        description: "Raises",
        input_schema: %{},
        handler: fn _args -> raise "kaboom" end
      }

      server = Server.create("s", "1.0", [tool])
      index = Server.build_tool_index([server])

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "crasher", "arguments" => %{}}
      }

      assert {:result, response} = Server.handle_jsonrpc("s", jsonrpc, index)
      assert response["result"]["isError"] == true
      [content] = response["result"]["content"]
      assert content["text"] =~ "Tool handler error"
    end
  end

  describe "type validation" do
    setup do
      make_tool = fn schema ->
        tool = %Tool{
          name: "typed",
          description: "d",
          input_schema: schema,
          handler: fn _args -> {:ok, "ok"} end
        }

        server = Server.create("s", "1.0", [tool])
        Server.build_tool_index([server])
      end

      %{make_tool: make_tool}
    end

    test "integer arg passed as string type fails", %{make_tool: make_tool} do
      index =
        make_tool.(%{"type" => "object", "properties" => %{"x" => %{"type" => "string"}}})

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "typed", "arguments" => %{"x" => 42}}
      }

      assert {:result, resp} = Server.handle_jsonrpc("s", jsonrpc, index)
      assert resp["result"]["isError"] == true
      [content] = resp["result"]["content"]
      assert content["text"] =~ "expected type string, got integer"
    end

    test "string arg passed as integer type fails", %{make_tool: make_tool} do
      index =
        make_tool.(%{"type" => "object", "properties" => %{"x" => %{"type" => "integer"}}})

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "typed", "arguments" => %{"x" => "hello"}}
      }

      assert {:result, resp} = Server.handle_jsonrpc("s", jsonrpc, index)
      assert resp["result"]["isError"] == true
      [content] = resp["result"]["content"]
      assert content["text"] =~ "expected type integer, got string"
    end

    test "string arg passed as number type fails", %{make_tool: make_tool} do
      index =
        make_tool.(%{"type" => "object", "properties" => %{"x" => %{"type" => "number"}}})

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "typed", "arguments" => %{"x" => "hello"}}
      }

      assert {:result, resp} = Server.handle_jsonrpc("s", jsonrpc, index)
      assert resp["result"]["isError"] == true
      [content] = resp["result"]["content"]
      assert content["text"] =~ "expected type number, got string"
    end

    test "string arg passed as boolean type fails", %{make_tool: make_tool} do
      index =
        make_tool.(%{"type" => "object", "properties" => %{"x" => %{"type" => "boolean"}}})

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "typed", "arguments" => %{"x" => "yes"}}
      }

      assert {:result, resp} = Server.handle_jsonrpc("s", jsonrpc, index)
      assert resp["result"]["isError"] == true
      [content] = resp["result"]["content"]
      assert content["text"] =~ "expected type boolean, got string"
    end

    test "string arg passed as object type fails", %{make_tool: make_tool} do
      index =
        make_tool.(%{"type" => "object", "properties" => %{"x" => %{"type" => "object"}}})

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "typed", "arguments" => %{"x" => "hello"}}
      }

      assert {:result, resp} = Server.handle_jsonrpc("s", jsonrpc, index)
      assert resp["result"]["isError"] == true
      [content] = resp["result"]["content"]
      assert content["text"] =~ "expected type object, got string"
    end

    test "string arg passed as array type fails", %{make_tool: make_tool} do
      index =
        make_tool.(%{"type" => "object", "properties" => %{"x" => %{"type" => "array"}}})

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "typed", "arguments" => %{"x" => "hello"}}
      }

      assert {:result, resp} = Server.handle_jsonrpc("s", jsonrpc, index)
      assert resp["result"]["isError"] == true
      [content] = resp["result"]["content"]
      assert content["text"] =~ "expected type array, got string"
    end

    test "correct types pass validation", %{make_tool: make_tool} do
      index =
        make_tool.(%{
          "type" => "object",
          "properties" => %{
            "s" => %{"type" => "string"},
            "n" => %{"type" => "number"},
            "i" => %{"type" => "integer"},
            "b" => %{"type" => "boolean"},
            "o" => %{"type" => "object"},
            "a" => %{"type" => "array"}
          }
        })

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{
          "name" => "typed",
          "arguments" => %{
            "s" => "hello",
            "n" => 3.14,
            "i" => 42,
            "b" => true,
            "o" => %{},
            "a" => [1, 2]
          }
        }
      }

      assert {:result, resp} = Server.handle_jsonrpc("s", jsonrpc, index)
      assert resp["result"]["isError"] == false
    end

    test "null type always passes", %{make_tool: make_tool} do
      index =
        make_tool.(%{"type" => "object", "properties" => %{"x" => %{"type" => "null"}}})

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "typed", "arguments" => %{"x" => "anything"}}
      }

      assert {:result, resp} = Server.handle_jsonrpc("s", jsonrpc, index)
      assert resp["result"]["isError"] == false
    end

    test "property not in schema is ignored", %{make_tool: make_tool} do
      index =
        make_tool.(%{
          "type" => "object",
          "properties" => %{"known" => %{"type" => "string"}}
        })

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{
          "name" => "typed",
          "arguments" => %{"known" => "ok", "unknown" => 42}
        }
      }

      assert {:result, resp} = Server.handle_jsonrpc("s", jsonrpc, index)
      assert resp["result"]["isError"] == false
    end

    test "property without type in schema is ignored", %{make_tool: make_tool} do
      index =
        make_tool.(%{
          "type" => "object",
          "properties" => %{"x" => %{"description" => "no type"}}
        })

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "typed", "arguments" => %{"x" => 42}}
      }

      assert {:result, resp} = Server.handle_jsonrpc("s", jsonrpc, index)
      assert resp["result"]["isError"] == false
    end
  end

  describe "format_result with map" do
    test "map result is JSON-encoded" do
      tool = %Tool{
        name: "map_tool",
        description: "Returns a map",
        input_schema: %{},
        handler: fn _args -> {:ok, %{"key" => "value"}} end
      }

      server = Server.create("s", "1.0", [tool])
      index = Server.build_tool_index([server])

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "map_tool", "arguments" => %{}}
      }

      assert {:result, resp} = Server.handle_jsonrpc("s", jsonrpc, index)
      [content] = resp["result"]["content"]
      decoded = Jason.decode!(content["text"])
      assert decoded == %{"key" => "value"}
    end
  end

  describe "tool name collision" do
    @tag :capture_log
    test "logs warning on duplicate tool name" do
      tool1 = %Tool{
        name: "dup",
        description: "d1",
        input_schema: %{},
        handler: fn _ -> {:ok, "1"} end
      }

      tool2 = %Tool{
        name: "dup",
        description: "d2",
        input_schema: %{},
        handler: fn _ -> {:ok, "2"} end
      }

      server = Server.create("s", "1.0", [tool1, tool2])
      index = Server.build_tool_index([server])
      assert Map.has_key?(index, {"s", "dup"})
    end
  end

  describe "unsupported method" do
    test "returns method not supported for unknown method with id" do
      jsonrpc = %{"jsonrpc" => "2.0", "id" => 99, "method" => "resources/list"}
      assert {:result, resp} = Server.handle_jsonrpc("s", jsonrpc, %{})
      assert resp["error"]["code"] == -32601
      assert resp["error"]["message"] == "Method not supported"
    end
  end

  describe "tools/list filtering" do
    test "lists tools for specific server only" do
      tool_a = %Tool{
        name: "a",
        description: "Tool A",
        input_schema: %{"type" => "object"},
        handler: fn _ -> {:ok, "a"} end
      }

      tool_b = %Tool{
        name: "b",
        description: "Tool B",
        input_schema: %{"type" => "object"},
        handler: fn _ -> {:ok, "b"} end
      }

      server1 = Server.create("s1", "1.0", [tool_a])
      server2 = Server.create("s2", "1.0", [tool_b])
      index = Server.build_tool_index([server1, server2])

      jsonrpc = %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}
      assert {:result, resp} = Server.handle_jsonrpc("s1", jsonrpc, index)
      tools = resp["result"]["tools"]
      assert length(tools) == 1
      assert hd(tools)["name"] == "a"
    end
  end

  describe "validate_arguments with nil schema" do
    test "nil schema skips validation" do
      tool = %Tool{
        name: "no_schema",
        description: "No schema",
        input_schema: nil,
        handler: fn _args -> {:ok, "ok"} end
      }

      server = Server.create("s", "1.0", [tool])
      index = Server.build_tool_index([server])

      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "no_schema", "arguments" => %{"anything" => 123}}
      }

      assert {:result, resp} = Server.handle_jsonrpc("s", jsonrpc, index)
      assert resp["result"]["isError"] == false
    end
  end

  describe "inspect_type coverage" do
    setup do
      make_string_tool = fn ->
        tool = %Tool{
          name: "t",
          description: "d",
          input_schema: %{
            "type" => "object",
            "properties" => %{"x" => %{"type" => "string"}}
          },
          handler: fn _args -> {:ok, "ok"} end
        }

        server = Server.create("s", "1.0", [tool])
        Server.build_tool_index([server])
      end

      %{index: make_string_tool.()}
    end

    test "float value reports as number", %{index: index} do
      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "t", "arguments" => %{"x" => 3.14}}
      }

      assert {:result, resp} = Server.handle_jsonrpc("s", jsonrpc, index)
      assert resp["result"]["isError"] == true
      [content] = resp["result"]["content"]
      assert content["text"] =~ "got number"
    end

    test "boolean value reports as boolean", %{index: index} do
      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "t", "arguments" => %{"x" => true}}
      }

      assert {:result, resp} = Server.handle_jsonrpc("s", jsonrpc, index)
      assert resp["result"]["isError"] == true
      [content] = resp["result"]["content"]
      assert content["text"] =~ "got boolean"
    end

    test "map value reports as object", %{index: index} do
      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "t", "arguments" => %{"x" => %{"nested" => true}}}
      }

      assert {:result, resp} = Server.handle_jsonrpc("s", jsonrpc, index)
      assert resp["result"]["isError"] == true
      [content] = resp["result"]["content"]
      assert content["text"] =~ "got object"
    end

    test "list value reports as array", %{index: index} do
      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "t", "arguments" => %{"x" => [1, 2, 3]}}
      }

      assert {:result, resp} = Server.handle_jsonrpc("s", jsonrpc, index)
      assert resp["result"]["isError"] == true
      [content] = resp["result"]["content"]
      assert content["text"] =~ "got array"
    end

    test "nil value reports as null", %{index: index} do
      jsonrpc = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "t", "arguments" => %{"x" => nil}}
      }

      assert {:result, resp} = Server.handle_jsonrpc("s", jsonrpc, index)
      assert resp["result"]["isError"] == true
      [content] = resp["result"]["content"]
      assert content["text"] =~ "got null"
    end
  end
end
