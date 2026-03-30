# Multi-turn conversation using the stateful Client
#
# Run with: mix run examples/multi_turn.exs
#
# Prerequisites: Claude Code CLI installed and ANTHROPIC_API_KEY set.

alias ClaudeSDK.Client
alias ClaudeSDK.Types.Options

Client.with_client(
  [options: %Options{permission_mode: :bypass_permissions, max_turns: 1}],
  fn client ->
    IO.puts("=== Turn 1 ===")

    Client.query(client, "Pick a random number between 1 and 100. Just say the number.")
    |> Enum.each(fn
      %ClaudeSDK.Types.AssistantMessage{message: %{content: content}} ->
        for %ClaudeSDK.Types.TextBlock{text: text} <- content, do: IO.puts(text)

      _ ->
        :ok
    end)

    IO.puts("\n=== Turn 2 ===")

    Client.query(client, "Now double that number.")
    |> Enum.each(fn
      %ClaudeSDK.Types.AssistantMessage{message: %{content: content}} ->
        for %ClaudeSDK.Types.TextBlock{text: text} <- content, do: IO.puts(text)

      _ ->
        :ok
    end)
  end
)
