# Structured output — get JSON matching a schema
#
# Run with: mix run examples/structured_output.exs
#
# Prerequisites: Claude Code CLI installed and ANTHROPIC_API_KEY set.

alias ClaudeSDK.Types.Options

schema = %{
  "type" => "object",
  "properties" => %{
    "name" => %{"type" => "string"},
    "pros" => %{"type" => "array", "items" => %{"type" => "string"}},
    "cons" => %{"type" => "array", "items" => %{"type" => "string"}},
    "rating" => %{"type" => "number", "minimum" => 1, "maximum" => 10}
  },
  "required" => ["name", "pros", "cons", "rating"]
}

ClaudeSDK.query(
  "Rate the Elixir programming language as a JSON object with name, pros, cons, and rating (1-10).",
  %Options{
    json_schema: schema,
    permission_mode: :bypass_permissions,
    max_turns: 1
  }
)
|> Enum.each(fn
  %ClaudeSDK.Types.ResultMessage{result: result} when is_binary(result) ->
    case Jason.decode(result) do
      {:ok, data} -> IO.inspect(data, label: "Structured output")
      _ -> IO.puts(result)
    end

  _ ->
    :ok
end)
