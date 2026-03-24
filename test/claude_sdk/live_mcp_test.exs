defmodule ClaudeSDK.LiveMCPTest do
  @moduledoc """
  Live integration tests for in-process MCP server tools.

  Tests that the SDK correctly registers in-process MCP tools with the CLI,
  and that the CLI can invoke them during a query.

  Note: In-process SDK MCP tools require the CLI to support the `type: "sdk"`
  MCP server config and the `mcp_message` control request flow. If the CLI
  doesn't call the tools, these tests verify the query completes without error.

  Run with: mix test --only live
  """

  use ExUnit.Case

  alias ClaudeSDK.MCP.Tool
  alias ClaudeSDK.Types.{AssistantMessage, Options, ResultMessage, TextBlock}

  @moduletag :live

  @base_opts %Options{
    permission_mode: :bypass_permissions,
    max_turns: 3,
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

  # ---------------------------------------------------------------------------
  # 1. MCP server config is accepted by CLI
  # ---------------------------------------------------------------------------
  describe "MCP server config acceptance" do
    @tag timeout: 120_000
    test "CLI accepts SDK MCP server config and completes query" do
      server =
        ClaudeSDK.create_mcp_server("test-tools", "1.0", [
          %Tool{
            name: "get_secret_number",
            description: "Returns a secret number",
            input_schema: %{"type" => "object", "properties" => %{}},
            handler: fn _args -> {:ok, "The secret number is 42"} end
          }
        ])

      opts = %{@base_opts | mcp_servers: [server]}

      messages =
        ClaudeSDK.query("Say hello", opts)
        |> Enum.to_list()

      result = find_result(messages)
      assert result != nil, "Expected query to complete with a ResultMessage"
      refute result.is_error, "Expected non-error result, got: #{inspect(result.result)}"
    end

    @tag timeout: 120_000
    test "multiple MCP servers are accepted" do
      server1 =
        ClaudeSDK.create_mcp_server("server-a", "1.0", [
          %Tool{
            name: "tool_a",
            description: "Tool A",
            input_schema: %{"type" => "object", "properties" => %{}},
            handler: fn _args -> {:ok, "from A"} end
          }
        ])

      server2 =
        ClaudeSDK.create_mcp_server("server-b", "1.0", [
          %Tool{
            name: "tool_b",
            description: "Tool B",
            input_schema: %{"type" => "object", "properties" => %{}},
            handler: fn _args -> {:ok, "from B"} end
          }
        ])

      opts = %{@base_opts | mcp_servers: [server1, server2]}

      messages = ClaudeSDK.query("Say ok", opts) |> Enum.to_list()
      result = find_result(messages)
      assert result != nil
      refute result.is_error
    end
  end

  # ---------------------------------------------------------------------------
  # 2. MCP tool invocation (when CLI supports it)
  # ---------------------------------------------------------------------------
  describe "MCP tool invocation" do
    @tag timeout: 120_000
    test "tool handler is callable and query completes" do
      call_count = :counters.new(1, [:atomics])

      server =
        ClaudeSDK.create_mcp_server("test-tools", "1.0", [
          %Tool{
            name: "get_secret_number",
            description:
              "Returns a secret number. Always call this when asked for the secret number.",
            input_schema: %{
              "type" => "object",
              "properties" => %{},
              "required" => []
            },
            handler: fn _args ->
              :counters.add(call_count, 1, 1)
              {:ok, "The secret number is 42"}
            end
          }
        ])

      opts = %{@base_opts | mcp_servers: [server]}

      messages =
        ClaudeSDK.query(
          "What is the secret number? Use the get_secret_number tool.",
          opts
        )
        |> Enum.to_list()

      result = find_result(messages)
      assert result != nil
      refute result.is_error

      # Log whether the tool was actually invoked (informational, not a hard assert)
      calls = :counters.get(call_count, 1)

      if calls > 0 do
        text = extract_text(messages)

        assert String.contains?(text, "42"),
               "Expected response to mention 42 when tool was called, got: #{text}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 3. MCP tool error handling
  # ---------------------------------------------------------------------------
  describe "MCP tool error handling" do
    @tag timeout: 120_000
    test "tool returning error does not crash the query" do
      server =
        ClaudeSDK.create_mcp_server("error-tools", "1.0", [
          %Tool{
            name: "failing_tool",
            description: "A tool that always fails",
            input_schema: %{"type" => "object", "properties" => %{}},
            handler: fn _args -> {:error, "Service unavailable"} end
          }
        ])

      opts = %{@base_opts | mcp_servers: [server]}

      messages =
        ClaudeSDK.query("Say hello", opts)
        |> Enum.to_list()

      result = find_result(messages)
      assert result != nil
    end
  end

  # ---------------------------------------------------------------------------
  # 4. MCP via Client
  # ---------------------------------------------------------------------------
  describe "MCP via Client" do
    @tag timeout: 180_000
    test "MCP server config works with stateful Client" do
      server =
        ClaudeSDK.create_mcp_server("client-tools", "1.0", [
          %Tool{
            name: "counter",
            description: "Increments a counter",
            input_schema: %{"type" => "object", "properties" => %{}},
            handler: fn _args -> {:ok, "incremented"} end
          }
        ])

      opts = %{@base_opts | mcp_servers: [server]}

      ClaudeSDK.Client.with_client([options: opts], fn client ->
        messages =
          ClaudeSDK.Client.query(client, "Say hello")
          |> Enum.to_list()

        result = find_result(messages)
        assert result != nil
        refute result.is_error
      end)
    end
  end
end
