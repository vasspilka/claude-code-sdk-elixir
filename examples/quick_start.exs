# Quick Start — single stateless query
#
# Run with: mix run examples/quick_start.exs
#
# Prerequisites: Claude Code CLI installed and ANTHROPIC_API_KEY set.

alias ClaudeSDK.Types.Options

ClaudeSDK.query("What is pattern matching in Elixir? Answer in 2 sentences.", %Options{
  permission_mode: :bypass_permissions,
  max_turns: 1
})
|> Enum.each(fn
  %ClaudeSDK.Types.AssistantMessage{message: %{content: content}} ->
    for block <- content do
      case block do
        %ClaudeSDK.Types.TextBlock{text: text} -> IO.puts(text)
        _ -> :ok
      end
    end

  %ClaudeSDK.Types.ResultMessage{result: result} ->
    IO.puts("\n--- Done (#{result || "no result text"}) ---")

  _other ->
    :ok
end)
