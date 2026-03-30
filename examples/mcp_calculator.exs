# In-process MCP tool — a simple calculator
#
# Run with: mix run examples/mcp_calculator.exs
#
# Prerequisites: Claude Code CLI installed and ANTHROPIC_API_KEY set.

alias ClaudeSDK.Types.Options

server =
  ClaudeSDK.create_mcp_server("calculator", "1.0", [
    %ClaudeSDK.MCP.Tool{
      name: "add",
      description: "Add two numbers",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "a" => %{"type" => "number", "description" => "First number"},
          "b" => %{"type" => "number", "description" => "Second number"}
        },
        "required" => ["a", "b"]
      },
      handler: fn %{"a" => a, "b" => b} ->
        {:ok, "#{a + b}"}
      end
    },
    %ClaudeSDK.MCP.Tool{
      name: "multiply",
      description: "Multiply two numbers",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "a" => %{"type" => "number", "description" => "First number"},
          "b" => %{"type" => "number", "description" => "Second number"}
        },
        "required" => ["a", "b"]
      },
      handler: fn %{"a" => a, "b" => b} ->
        {:ok, "#{a * b}"}
      end
    }
  ])

ClaudeSDK.query(
  "Use the calculator tools to compute (7 + 3) * 4. Show your work.",
  %Options{
    mcp_servers: [server],
    permission_mode: :bypass_permissions,
    max_turns: 5
  }
)
|> Enum.each(fn
  %ClaudeSDK.Types.AssistantMessage{message: %{content: content}} ->
    for block <- content do
      case block do
        %ClaudeSDK.Types.TextBlock{text: text} -> IO.puts(text)
        %ClaudeSDK.Types.ToolUseBlock{name: name, input: input} -> IO.puts("[tool] #{name}(#{inspect(input)})")
        _ -> :ok
      end
    end

  %ClaudeSDK.Types.ResultMessage{result: result} ->
    IO.puts("\n--- Result: #{result || "done"} ---")

  _ ->
    :ok
end)
