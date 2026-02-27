defmodule ClaudeSDK.ControlRouterTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.ControlRouter

  describe "build_handlers/1" do
    test "returns empty registry when no callbacks configured" do
      handlers = ControlRouter.build_handlers(%{can_use_tool: nil, mcp_tool_index: %{}})
      assert handlers == %{}
    end

    test "registers can_use_tool handler when callback provided" do
      callback = fn _tool, _input -> :allow end
      handlers = ControlRouter.build_handlers(%{can_use_tool: callback, mcp_tool_index: %{}})

      assert Map.has_key?(handlers, "can_use_tool")
      assert is_function(handlers["can_use_tool"], 1)
    end

    test "registers mcp_message handler when tool index is non-empty" do
      tool_index = %{{"server", "tool"} => fn _args -> {:ok, "result"} end}
      handlers = ControlRouter.build_handlers(%{can_use_tool: nil, mcp_tool_index: tool_index})

      assert Map.has_key?(handlers, "mcp_message")
    end

    test "does not register mcp_message handler when tool index is empty" do
      handlers = ControlRouter.build_handlers(%{can_use_tool: nil, mcp_tool_index: %{}})

      refute Map.has_key?(handlers, "mcp_message")
    end

    test "registers both handlers when both configured" do
      callback = fn _tool, _input -> :allow end
      tool_index = %{{"server", "tool"} => fn _args -> {:ok, "result"} end}

      handlers =
        ControlRouter.build_handlers(%{can_use_tool: callback, mcp_tool_index: tool_index})

      assert Map.has_key?(handlers, "can_use_tool")
      assert Map.has_key?(handlers, "mcp_message")
    end
  end

  describe "dispatch/2" do
    test "returns {:unhandled, request} when no handler matches" do
      raw = %{
        "type" => "control_request",
        "request_id" => "req_001",
        "request" => %{"subtype" => "unknown_type"}
      }

      assert {:unhandled, ^raw} = ControlRouter.dispatch(raw, %{})
    end

    test "returns {:handled, response} when handler matches" do
      handler = fn _request -> {:allow, %{}} end
      handlers = %{"can_use_tool" => handler}

      raw = %{
        "type" => "control_request",
        "request_id" => "req_001",
        "request" => %{"subtype" => "can_use_tool", "tool_name" => "Read"}
      }

      assert {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.type == "control_response"
      assert response.request_id == "req_001"
      assert response.response.allowed == true
    end

    test "returns {:unhandled, raw} for malformed messages without request_id" do
      assert {:unhandled, %{}} = ControlRouter.dispatch(%{}, %{})
    end

    test "dispatches deny results correctly" do
      handler = fn _request -> {:deny, "Not permitted"} end
      handlers = %{"can_use_tool" => handler}

      raw = %{
        "type" => "control_request",
        "request_id" => "req_002",
        "request" => %{"subtype" => "can_use_tool", "tool_name" => "Bash"}
      }

      assert {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.response.allowed == false
      assert response.response.reason == "Not permitted"
    end

    test "dispatches result payloads correctly" do
      handler = fn _request -> {:result, %{data: "hello"}} end
      handlers = %{"mcp_message" => handler}

      raw = %{
        "type" => "control_request",
        "request_id" => "req_003",
        "request" => %{"subtype" => "mcp_message"}
      }

      assert {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.response == %{data: "hello"}
    end
  end

  describe "build_response/3" do
    test "builds allow response" do
      response = ControlRouter.build_response("req_1", "can_use_tool", {:allow, %{}})

      assert response == %{
               type: "control_response",
               request_id: "req_1",
               response: %{allowed: true}
             }
    end

    test "builds allow response with extra permissions" do
      response =
        ControlRouter.build_response("req_1", "can_use_tool", {:allow, %{temporary: true}})

      assert response.response.allowed == true
      assert response.response.temporary == true
    end

    test "builds deny response" do
      response = ControlRouter.build_response("req_1", "can_use_tool", {:deny, "Forbidden"})

      assert response == %{
               type: "control_response",
               request_id: "req_1",
               response: %{allowed: false, reason: "Forbidden"}
             }
    end

    test "builds result response" do
      payload = %{jsonrpc_response: %{"id" => 1, "result" => "ok"}}
      response = ControlRouter.build_response("req_1", "mcp_message", {:result, payload})

      assert response == %{
               type: "control_response",
               request_id: "req_1",
               response: payload
             }
    end
  end

  describe "permission callback integration" do
    test "can_use_tool handler invokes callback with tool_name and input" do
      test_pid = self()

      callback = fn tool_name, input ->
        send(test_pid, {:called, tool_name, input})
        :allow
      end

      handlers = ControlRouter.build_handlers(%{can_use_tool: callback, mcp_tool_index: %{}})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_test",
        "request" => %{
          "subtype" => "can_use_tool",
          "tool_name" => "Bash",
          "input" => %{"command" => "ls"}
        }
      }

      {:handled, _response} = ControlRouter.dispatch(raw, handlers)

      assert_receive {:called, "Bash", %{"command" => "ls"}}
    end

    test "callback returning {:deny, reason} produces deny response" do
      callback = fn _tool, _input -> {:deny, "Dangerous command"} end
      handlers = ControlRouter.build_handlers(%{can_use_tool: callback, mcp_tool_index: %{}})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_deny",
        "request" => %{
          "subtype" => "can_use_tool",
          "tool_name" => "Bash",
          "input" => %{}
        }
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.response.allowed == false
      assert response.response.reason == "Dangerous command"
    end

    test "callback returning {:allow, permissions} merges permissions" do
      callback = fn _tool, _input -> {:allow, %{temporary: true}} end
      handlers = ControlRouter.build_handlers(%{can_use_tool: callback, mcp_tool_index: %{}})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_perm",
        "request" => %{
          "subtype" => "can_use_tool",
          "tool_name" => "Read",
          "input" => %{}
        }
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.response.allowed == true
      assert response.response.temporary == true
    end
  end
end
