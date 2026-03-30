# Session management — list, inspect, rename, tag, fork, and delete sessions
#
# Run with: mix run examples/session_management.exs
#
# This example works with existing sessions on disk (no API key needed).

# List recent sessions
sessions = ClaudeSDK.list_sessions(limit: 5)

if sessions == [] do
  IO.puts("No sessions found. Run a query first to create one.")
else
  IO.puts("Recent sessions:")

  for session <- sessions do
    title = session.custom_title || session.first_prompt || "(untitled)"
    tag = if session.tag, do: " [#{session.tag}]", else: ""
    IO.puts("  #{session.session_id} — #{title}#{tag}")
  end

  # Inspect the most recent session
  latest = hd(sessions)
  IO.puts("\nMessages in #{latest.session_id}:")

  messages = ClaudeSDK.get_session_messages(latest.session_id, limit: 4)

  for msg <- messages do
    content =
      case msg.message do
        %{"content" => c} when is_binary(c) -> String.slice(c, 0, 80)
        _ -> "(structured content)"
      end

    IO.puts("  [#{msg.type}] #{content}")
  end

  # Fork the latest session
  case ClaudeSDK.fork_session(latest.session_id) do
    {:ok, new_id} ->
      IO.puts("\nForked to new session: #{new_id}")
      # Clean up the fork
      ClaudeSDK.delete_session(new_id)
      IO.puts("Cleaned up forked session.")

    {:error, reason} ->
      IO.puts("\nFork failed: #{inspect(reason)}")
  end
end
