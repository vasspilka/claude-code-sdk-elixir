defmodule ClaudeSDK.QueryCoverageTest do
  use ExUnit.Case

  alias ClaudeSDK.Types.{AssistantMessage, Options, ResultMessage}

  @mock_cli_timeout Path.expand("../support/mock_cli_timeout.sh", __DIR__)
  @mock_cli_init_timeout Path.expand("../support/mock_cli_init_timeout.sh", __DIR__)
  @mock_cli_bad_json Path.expand("../support/mock_cli_bad_json.sh", __DIR__)
  @mock_cli_unhandled Path.expand("../support/mock_cli_unhandled_control.sh", __DIR__)
  @mock_cli_init_system Path.expand("../support/mock_cli_init_with_system.sh", __DIR__)
  @mock_cli_path Path.expand("../support/mock_cli.sh", __DIR__)

  describe "query/2 with keyword list options" do
    test "accepts keyword list and converts to Options struct" do
      messages =
        ClaudeSDK.query("test", cli_path: @mock_cli_path)
        |> Enum.to_list()

      assert length(messages) > 0
      result = Enum.find(messages, &match?(%ResultMessage{}, &1))
      assert result != nil
    end
  end

  describe "query/2 with invalid options" do
    test "raises ArgumentError for invalid max_turns" do
      assert_raise ArgumentError, ~r/max_turns/, fn ->
        ClaudeSDK.query("test", %Options{cli_path: @mock_cli_path, max_turns: -1})
        |> Enum.to_list()
      end
    end

    test "raises ArgumentError for invalid permission_mode" do
      assert_raise ArgumentError, ~r/permission_mode/, fn ->
        ClaudeSDK.query("test", %Options{cli_path: @mock_cli_path, permission_mode: :invalid})
        |> Enum.to_list()
      end
    end

    test "raises ArgumentError for invalid effort" do
      assert_raise ArgumentError, ~r/effort/, fn ->
        ClaudeSDK.query("test", %Options{cli_path: @mock_cli_path, effort: "turbo"})
        |> Enum.to_list()
      end
    end
  end

  describe "message receive timeout" do
    test "returns timeout ResultMessage when no message arrives within timeout" do
      opts = %Options{
        cli_path: @mock_cli_timeout,
        message_timeout_ms: 200
      }

      messages = ClaudeSDK.query("test", opts) |> Enum.to_list()

      # Should get the assistant message + a timeout result
      timeout_result = List.last(messages)
      assert %ResultMessage{} = timeout_result
      assert timeout_result.is_error == true
      assert timeout_result.result =~ "timeout"
    end
  end

  describe "init timeout" do
    test "raises TimeoutError when CLI never responds to init" do
      opts = %Options{
        cli_path: @mock_cli_init_timeout,
        init_timeout_ms: 200
      }

      assert_raise ClaudeSDK.TimeoutError, ~r/timed out/, fn ->
        ClaudeSDK.query("test", opts) |> Enum.to_list()
      end
    end
  end

  describe "init with system message before control_response" do
    test "skips non-control_response messages during init" do
      opts = %Options{cli_path: @mock_cli_init_system}

      messages = ClaudeSDK.query("test", opts) |> Enum.to_list()
      result = Enum.find(messages, &match?(%ResultMessage{}, &1))
      assert result != nil
    end
  end

  describe "unknown message types during streaming" do
    @tag :capture_log
    test "unknown types are parsed and yielded" do
      opts = %Options{cli_path: @mock_cli_bad_json}

      messages = ClaudeSDK.query("test", opts) |> Enum.to_list()

      # Should get assistant + unknown type error + result
      assert Enum.any?(messages, &match?(%AssistantMessage{}, &1))
      assert Enum.any?(messages, &match?(%ResultMessage{}, &1))
    end
  end

  describe "unhandled control_request during streaming" do
    test "unhandled control_request is parsed and yielded as message" do
      opts = %Options{cli_path: @mock_cli_unhandled}

      messages = ClaudeSDK.query("test", opts) |> Enum.to_list()

      # The unhandled control_request should be parsed as a ControlRequest struct
      control = Enum.find(messages, &match?(%ClaudeSDK.Types.ControlRequest{}, &1))
      assert control != nil
      assert control.request["subtype"] == "some_unknown_subtype"

      # Stream should still complete with result
      result = Enum.find(messages, &match?(%ResultMessage{}, &1))
      assert result != nil
    end
  end

  describe "cleanup paths" do
    test "cleanup with :done is a no-op" do
      # This is covered implicitly when streams complete normally,
      # but let's verify the happy path completes cleanly
      opts = %Options{cli_path: @mock_cli_path}
      messages = ClaudeSDK.query("test", opts) |> Enum.to_list()
      assert length(messages) > 0
    end
  end

  describe "normalize_agents" do
    test "query works with agents as list of maps" do
      opts = %Options{
        cli_path: @mock_cli_path,
        agents: [%{"name" => "test-agent", "model" => "test"}]
      }

      messages = ClaudeSDK.query("test", opts) |> Enum.to_list()
      assert length(messages) > 0
    end

    test "query works with agents as list of AgentDefinition structs" do
      opts = %Options{
        cli_path: @mock_cli_path,
        agents: [
          %ClaudeSDK.Types.AgentDefinition{
            name: "test-agent",
            description: "A test agent",
            prompt: "You are a test agent",
            model: "test-model"
          }
        ]
      }

      messages = ClaudeSDK.query("test", opts) |> Enum.to_list()
      assert length(messages) > 0
    end

    test "query works with agents as map" do
      opts = %Options{
        cli_path: @mock_cli_path,
        agents: %{"name" => "test-agent"}
      }

      messages = ClaudeSDK.query("test", opts) |> Enum.to_list()
      assert length(messages) > 0
    end

    test "query works with agents as nil" do
      opts = %Options{
        cli_path: @mock_cli_path,
        agents: nil
      }

      messages = ClaudeSDK.query("test", opts) |> Enum.to_list()
      assert length(messages) > 0
    end
  end

  describe "build_mcp_tool_index" do
    test "query works with nil mcp_servers" do
      opts = %Options{
        cli_path: @mock_cli_path,
        mcp_servers: nil
      }

      messages = ClaudeSDK.query("test", opts) |> Enum.to_list()
      assert length(messages) > 0
    end
  end

  describe "create_mcp_server/3" do
    test "delegates to MCP.Server.create" do
      server =
        ClaudeSDK.create_mcp_server("test", "1.0", [
          %ClaudeSDK.MCP.Tool{
            name: "tool1",
            description: "A tool",
            input_schema: %{},
            handler: fn _ -> {:ok, "ok"} end
          }
        ])

      assert server.name == "test"
      assert server.version == "1.0"
    end
  end

  describe "generate_request_id/0" do
    test "returns a string starting with req_" do
      id = ClaudeSDK.generate_request_id()
      assert is_binary(id)
      assert String.starts_with?(id, "req_")
    end
  end
end
