# Permission callbacks — control which tools Claude can use
#
# Run with: mix run examples/permission_callback.exs
#
# Prerequisites: Claude Code CLI installed and ANTHROPIC_API_KEY set.

alias ClaudeSDK.Types.Options

# Allow read-only tools, deny write operations
opts = %Options{
  can_use_tool: fn tool_name, input, _context ->
    IO.puts("[permission] Tool request: #{tool_name}")

    cond do
      tool_name in ["Read", "Glob", "Grep"] ->
        IO.puts("[permission] Allowed: #{tool_name}")
        :allow

      tool_name == "Write" ->
        IO.puts("[permission] Denied: #{tool_name}")
        {:deny, "Write operations are not permitted in this session"}

      tool_name == "Edit" ->
        IO.puts("[permission] Denied: #{tool_name}")
        {:deny, "Edit operations are not permitted in this session"}

      tool_name == "Bash" ->
        command = input["command"] || ""

        if String.starts_with?(command, "ls") or String.starts_with?(command, "cat") do
          IO.puts("[permission] Allowed safe bash: #{command}")
          :allow
        else
          IO.puts("[permission] Denied bash: #{command}")
          {:deny, "Only ls and cat commands are allowed"}
        end

      true ->
        IO.puts("[permission] Denied unknown tool: #{tool_name}")
        {:deny, "Tool not in allowlist"}
    end
  end,
  max_turns: 3
}

ClaudeSDK.query("List the files in the current directory", opts)
|> Enum.each(fn
  %ClaudeSDK.Types.AssistantMessage{message: %{content: content}} ->
    for %ClaudeSDK.Types.TextBlock{text: text} <- content, do: IO.puts(text)

  %ClaudeSDK.Types.ResultMessage{} ->
    IO.puts("\n--- Done ---")

  _ ->
    :ok
end)
