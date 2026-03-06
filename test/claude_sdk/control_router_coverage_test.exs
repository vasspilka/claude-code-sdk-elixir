defmodule ClaudeSDK.ControlRouterCoverageTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.ControlRouter

  describe "3-arity can_use_tool callback" do
    test "invokes callback with tool_name, input, and context" do
      test_pid = self()

      callback = fn tool_name, input, context ->
        send(test_pid, {:called_3, tool_name, input, context})
        :allow
      end

      handlers = ControlRouter.build_handlers(%{can_use_tool: callback, mcp_tool_index: %{}})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_3arity",
        "request" => %{
          "subtype" => "can_use_tool",
          "tool_name" => "Bash",
          "input" => %{"command" => "ls"},
          "request_id" => "inner_req_id"
        }
      }

      {:handled, _response} = ControlRouter.dispatch(raw, handlers)

      assert_receive {:called_3, "Bash", %{"command" => "ls"}, context}
      assert %ClaudeSDK.Types.ToolPermissionContext{} = context
      assert context.tool_name == "Bash"
      assert context.input == %{"command" => "ls"}
      assert context.request_id == "inner_req_id"
      assert context.raw_request == raw["request"]
    end
  end

  describe "deny with non-string reason" do
    @tag :capture_log
    test "converts non-string deny reason to string" do
      callback = fn _tool, _input -> {:deny, :forbidden} end
      handlers = ControlRouter.build_handlers(%{can_use_tool: callback, mcp_tool_index: %{}})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_atom_deny",
        "request" => %{
          "subtype" => "can_use_tool",
          "tool_name" => "Bash",
          "input" => %{}
        }
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.response.allowed == false
      assert response.response.reason == "forbidden"
    end
  end

  describe "unexpected callback return" do
    @tag :capture_log
    test "returns deny for unexpected callback return value" do
      callback = fn _tool, _input -> {:something, :unexpected} end
      handlers = ControlRouter.build_handlers(%{can_use_tool: callback, mcp_tool_index: %{}})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_unexpected",
        "request" => %{
          "subtype" => "can_use_tool",
          "tool_name" => "Bash",
          "input" => %{}
        }
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.response.allowed == false
      assert response.response.reason =~ "invalid"
    end
  end

  describe "non-function can_use_tool" do
    test "ignores non-function can_use_tool value" do
      handlers =
        ControlRouter.build_handlers(%{can_use_tool: "not a function", mcp_tool_index: %{}})

      assert handlers == %{}
    end
  end

  describe "missing request fields in permission handler" do
    test "handles missing tool_name and input gracefully" do
      callback = fn tool_name, input ->
        assert tool_name == ""
        assert input == %{}
        :allow
      end

      handlers = ControlRouter.build_handlers(%{can_use_tool: callback, mcp_tool_index: %{}})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_missing",
        "request" => %{
          "subtype" => "can_use_tool"
        }
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.response.allowed == true
    end
  end
end
