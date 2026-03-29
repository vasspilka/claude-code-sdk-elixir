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

  describe "permission callback timeout" do
    @tag :capture_log
    test "permission callback that hangs times out" do
      callback = fn _tool, _input -> Process.sleep(:infinity) end

      handlers =
        ControlRouter.build_handlers(%{
          can_use_tool: callback,
          mcp_tool_index: %{},
          hook_timeout_ms: 100
        })

      raw = %{
        "type" => "control_request",
        "request_id" => "req_perm_timeout",
        "request" => %{
          "subtype" => "can_use_tool",
          "tool_name" => "Bash",
          "input" => %{}
        }
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.response.allowed == false
      assert response.response.reason =~ "timed out"
    end
  end

  describe "permission callback exception" do
    @tag :capture_log
    test "permission callback that raises returns deny" do
      callback = fn _tool, _input -> raise "callback crash" end
      handlers = ControlRouter.build_handlers(%{can_use_tool: callback, mcp_tool_index: %{}})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_perm_raise",
        "request" => %{
          "subtype" => "can_use_tool",
          "tool_name" => "Bash",
          "input" => %{}
        }
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.response.allowed == false
      assert response.response.reason =~ "error"
    end
  end

  describe "permission callback process crash" do
    @tag :capture_log
    test "permission callback that exits abnormally returns deny" do
      callback = fn _tool, _input -> Process.exit(self(), :kill) end
      handlers = ControlRouter.build_handlers(%{can_use_tool: callback, mcp_tool_index: %{}})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_perm_crash",
        "request" => %{
          "subtype" => "can_use_tool",
          "tool_name" => "Bash",
          "input" => %{}
        }
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.response.allowed == false
      assert response.response.reason =~ "crashed"
    end
  end

  describe "deny_and_interrupt" do
    test "handler returning {:deny, reason, :interrupt} produces handled_with_interrupt" do
      callback = fn _tool, _input -> {:deny, "Stop right now", :interrupt} end
      handlers = ControlRouter.build_handlers(%{can_use_tool: callback, mcp_tool_index: %{}})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_interrupt",
        "request" => %{
          "subtype" => "can_use_tool",
          "tool_name" => "Bash",
          "input" => %{}
        }
      }

      {:handled_with_interrupt, response} = ControlRouter.dispatch(raw, handlers)
      assert response.response.allowed == false
      assert response.response.reason == "Stop right now"
    end
  end

  describe "normalize_allow_opts with keyword list" do
    test "keyword list is converted to map with camelCase keys" do
      callback = fn _tool, _input ->
        {:allow, [updated_input: %{"cmd" => "safe_ls"}, updated_permissions: ["Read"]]}
      end

      handlers = ControlRouter.build_handlers(%{can_use_tool: callback, mcp_tool_index: %{}})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_kw",
        "request" => %{
          "subtype" => "can_use_tool",
          "tool_name" => "Bash",
          "input" => %{}
        }
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.response.allowed == true
      assert response.response.updatedInput == %{"cmd" => "safe_ls"}
      assert response.response.updatedPermissions == ["Read"]
    end
  end

  describe "normalize_allow_opts with string keys" do
    test "string keys are passed through" do
      callback = fn _tool, _input ->
        {:allow, %{"updatedInput" => %{"cmd" => "ls"}, "custom_key" => "value"}}
      end

      handlers = ControlRouter.build_handlers(%{can_use_tool: callback, mcp_tool_index: %{}})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_str_keys",
        "request" => %{
          "subtype" => "can_use_tool",
          "tool_name" => "Bash",
          "input" => %{}
        }
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.response.allowed == true
    end
  end

  describe "hook callback list with non-function entry" do
    @tag :capture_log
    test "non-function entries in list are skipped" do
      hooks = %{"PreToolUse" => ["not a function", fn _input -> {:ok, %{valid: true}} end]}

      handlers =
        ControlRouter.build_handlers(%{can_use_tool: nil, mcp_tool_index: %{}, hooks: hooks})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_mixed_list",
        "request" => %{
          "subtype" => "hook_callback",
          "hook_event" => "PreToolUse",
          "hook_input" => %{}
        }
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.response.valid == true
    end
  end

  describe "hook callback returning non-result value" do
    test "non-result hook callback returns in list are handled" do
      hooks = %{
        "PreToolUse" => [
          fn _input -> {:ok, %{first: true}} end,
          fn _input -> :unexpected_atom end
        ]
      }

      handlers =
        ControlRouter.build_handlers(%{can_use_tool: nil, mcp_tool_index: %{}, hooks: hooks})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_non_result",
        "request" => %{
          "subtype" => "hook_callback",
          "hook_event" => "PreToolUse",
          "hook_input" => %{}
        }
      }

      {:handled, _response} = ControlRouter.dispatch(raw, handlers)
    end
  end

  describe "normalize_hook_result catch-all" do
    test "unexpected hook result falls through to empty result" do
      hooks = %{"PreToolUse" => fn _input -> {:something, :weird} end}

      handlers =
        ControlRouter.build_handlers(%{can_use_tool: nil, mcp_tool_index: %{}, hooks: hooks})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_weird_hook",
        "request" => %{
          "subtype" => "hook_callback",
          "hook_event" => "PreToolUse",
          "hook_input" => %{}
        }
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.response == %{request_id: "req_weird_hook"}
    end
  end

  describe "MCP handler with missing request fields" do
    test "handles missing server_name and jsonrpc_message gracefully" do
      tool = %ClaudeSDK.MCP.Tool{
        name: "t",
        description: "d",
        input_schema: %{},
        handler: fn _ -> {:ok, "ok"} end
      }

      server = ClaudeSDK.MCP.Server.create("s", "1.0", [tool])
      tool_index = ClaudeSDK.MCP.Server.build_tool_index([server])

      handlers =
        ControlRouter.build_handlers(%{
          can_use_tool: nil,
          mcp_tool_index: tool_index,
          mcp_servers: [server]
        })

      raw = %{
        "type" => "control_request",
        "request_id" => "req_mcp_missing",
        "request" => %{"subtype" => "mcp_message"}
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.type == "control_response"
    end
  end

  describe "raw handler returning :allow" do
    test "bare :allow from raw handler is normalized" do
      handler = fn _request -> :allow end
      handlers = %{"can_use_tool" => handler}

      raw = %{
        "type" => "control_request",
        "request_id" => "req_raw_allow",
        "request" => %{"subtype" => "can_use_tool", "tool_name" => "Read"}
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.response.allowed == true
    end
  end

  describe "raw handler returning :deny" do
    test "bare :deny from raw handler is normalized" do
      handler = fn _request -> :deny end
      handlers = %{"can_use_tool" => handler}

      raw = %{
        "type" => "control_request",
        "request_id" => "req_raw_deny",
        "request" => %{"subtype" => "can_use_tool", "tool_name" => "Bash"}
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.response.allowed == false
      assert response.response.reason == "Permission denied"
    end
  end

  describe "hook callback process exit" do
    @tag :capture_log
    test "hook callback that exits abnormally returns empty result" do
      hooks = %{"PreToolUse" => fn _input -> Process.exit(self(), :kill) end}

      handlers =
        ControlRouter.build_handlers(%{can_use_tool: nil, mcp_tool_index: %{}, hooks: hooks})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_hook_exit",
        "request" => %{
          "subtype" => "hook_callback",
          "hook_event" => "PreToolUse",
          "hook_input" => %{}
        }
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.type == "control_response"
      assert response.response == %{request_id: "req_hook_exit"}
    end
  end

  describe "hook list with non-result in accumulator chain" do
    test "when first callback returns non-result, second result takes over" do
      hooks = %{
        "PreToolUse" => [
          fn _input -> "not a standard return" end,
          fn _input -> {:ok, %{second: true}} end
        ]
      }

      handlers =
        ControlRouter.build_handlers(%{can_use_tool: nil, mcp_tool_index: %{}, hooks: hooks})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_nonresult_acc",
        "request" => %{
          "subtype" => "hook_callback",
          "hook_event" => "PreToolUse",
          "hook_input" => %{}
        }
      }

      {:handled, _response} = ControlRouter.dispatch(raw, handlers)
    end
  end

  describe "hook returning {:result, map} directly" do
    test "hook callback returning {:result, map} is passed through" do
      hooks = %{"PreToolUse" => fn _input -> {:result, %{direct_result: true}} end}

      handlers =
        ControlRouter.build_handlers(%{can_use_tool: nil, mcp_tool_index: %{}, hooks: hooks})

      raw = %{
        "type" => "control_request",
        "request_id" => "req_direct_result",
        "request" => %{
          "subtype" => "hook_callback",
          "hook_event" => "PreToolUse",
          "hook_input" => %{}
        }
      }

      {:handled, response} = ControlRouter.dispatch(raw, handlers)
      assert response.response.direct_result == true
    end
  end
end
