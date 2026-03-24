defmodule ClaudeSDK.LiveAgentDefinitionTest do
  @moduledoc """
  Live integration tests verifying the CLI accepts agent definitions.

  Agent definitions are config we serialize and send TO the CLI via the
  initialize control request. The CLI doesn't return them back, so we
  verify:
  1. The CLI init handshake succeeds (doesn't reject the config)
  2. The CLI produces a valid, non-error response
  3. The server_info is available after init with agents

  Note on `skills`: These are identifiers referencing SKILL.md files the
  CLI discovers from plugin directories. We can verify the CLI accepts the
  field without error, but cannot verify skill loading without creating
  actual SKILL.md files in the test environment.

  Run with: mix test --only live
  """

  use ExUnit.Case

  alias ClaudeSDK.Client
  alias ClaudeSDK.Types.{AgentDefinition, AssistantMessage, Options, ResultMessage, TextBlock}

  @moduletag :live

  @base_opts %Options{
    permission_mode: :bypass_permissions,
    max_turns: 1,
    model: "claude-haiku-4-5-20251001"
  }

  defp extract_text(messages) do
    messages
    |> Enum.flat_map(fn
      %AssistantMessage{message: %{content: content}} -> content
      _ -> []
    end)
    |> Enum.filter(&match?(%TextBlock{}, &1))
    |> Enum.map(& &1.text)
    |> Enum.join(" ")
  end

  defp find_result(messages), do: Enum.find(messages, &match?(%ResultMessage{}, &1))

  defp assert_successful_query(messages, context) do
    result = find_result(messages)
    assert result != nil, "No ResultMessage received for #{context}"
    refute result.is_error, "CLI rejected config for #{context}: #{inspect(result.result)}"
    assert is_binary(result.session_id), "Expected session_id for #{context}"
    assert String.length(extract_text(messages)) > 0, "Expected non-empty response for #{context}"
    result
  end

  describe "CLI accepts agent definitions via stateless query" do
    @tag timeout: 120_000
    test "basic agent (name, description, prompt)" do
      agents = [
        %AgentDefinition{
          name: "greeter",
          description: "A simple greeting agent",
          prompt: "You are a greeter."
        }
      ]

      ClaudeSDK.query("Say hi", %{@base_opts | agents: agents})
      |> Enum.to_list()
      |> assert_successful_query("basic agent")
    end

    @tag timeout: 120_000
    test "agent with model and tools" do
      agents = [
        %AgentDefinition{
          name: "reader",
          description: "Reads files",
          prompt: "You are a file reader.",
          model: "haiku",
          tools: ["Read", "Glob"]
        }
      ]

      ClaudeSDK.query("Say ok", %{@base_opts | agents: agents})
      |> Enum.to_list()
      |> assert_successful_query("agent with model/tools")
    end

    @tag timeout: 120_000
    test "agent with skills field (CLI accepts without error)" do
      # Skills reference SKILL.md files from plugin dirs. These names likely
      # don't match real files, but the CLI should accept the field without
      # crashing — unknown skills are silently ignored.
      agents = [
        %AgentDefinition{
          name: "researcher",
          description: "Searches codebase",
          prompt: "You are a research assistant.",
          skills: ["nonexistent-skill-a", "nonexistent-skill-b"]
        }
      ]

      ClaudeSDK.query("Say ok", %{@base_opts | agents: agents})
      |> Enum.to_list()
      |> assert_successful_query("agent with skills")
    end

    @tag timeout: 120_000
    test "agent with memory field" do
      agents = [
        %AgentDefinition{
          name: "memo-agent",
          description: "Agent with memory",
          prompt: "You are an agent with project memory.",
          memory: "project"
        }
      ]

      ClaudeSDK.query("Say ok", %{@base_opts | agents: agents})
      |> Enum.to_list()
      |> assert_successful_query("agent with memory")
    end

    @tag timeout: 120_000
    test "agent with mcp_servers field" do
      agents = [
        %AgentDefinition{
          name: "mcp-agent",
          description: "Agent with MCP",
          prompt: "You are an agent.",
          mcp_servers: %{
            "test-server" => %{
              "type" => "stdio",
              "command" => "echo",
              "args" => ["hello"]
            }
          }
        }
      ]

      ClaudeSDK.query("Say ok", %{@base_opts | agents: agents})
      |> Enum.to_list()
      |> assert_successful_query("agent with mcp_servers")
    end

    @tag timeout: 120_000
    test "agent with all fields populated" do
      agents = [
        %AgentDefinition{
          name: "full-agent",
          description: "Fully configured agent",
          prompt: "You are a full agent.",
          model: "haiku",
          tools: ["Read", "Glob"],
          allowed_tools: ["Read"],
          disallowed_tools: ["Bash"],
          max_turns: 3,
          skills: ["nonexistent-skill"],
          memory: "user",
          mcp_servers: %{
            "echo-srv" => %{"type" => "stdio", "command" => "echo", "args" => ["test"]}
          }
        }
      ]

      ClaudeSDK.query("Say ok", %{@base_opts | agents: agents})
      |> Enum.to_list()
      |> assert_successful_query("fully-populated agent")
    end
  end

  describe "CLI accepts agent definitions via stateful Client" do
    @tag timeout: 180_000
    test "init handshake succeeds and server_info is available" do
      agents = [
        %AgentDefinition{
          name: "helper",
          description: "A helpful assistant",
          prompt: "You are a concise helper.",
          memory: "project"
        }
      ]

      opts = %{@base_opts | agents: agents}

      Client.with_client([options: opts], fn client ->
        # connect() succeeded — the CLI accepted our agent config
        # during the initialize handshake
        assert Client.connected?(client)

        {:ok, server_info} = Client.get_server_info(client)
        assert is_map(server_info), "Expected server_info map after init with agents"

        messages =
          Client.query(client, "What is 2+2? Reply with just the number.")
          |> Enum.to_list()

        result = assert_successful_query(messages, "Client with agents")
        text = extract_text(messages)
        assert String.contains?(text, "4"), "Expected '4' in response, got: #{text}"

        # Verify result has expected metadata
        assert is_number(result.duration_ms) or is_nil(result.duration_ms)
        assert is_integer(result.num_turns) or is_nil(result.num_turns)
      end)
    end
  end
end
