# Multi-turn Conversations

This guide covers how to maintain conversation context across multiple queries using `ClaudeSDK.Client`, how sessions work, and how to resume conversations later -- even from the Claude Code terminal.

## The Problem

`ClaudeSDK.query/2` spawns a new subprocess for each call. The subprocess dies when the stream ends, taking the conversation history with it. If you call `query/2` twice, the second call has no memory of the first.

## The Client

`ClaudeSDK.Client` solves this by keeping a single CLI subprocess alive. Each `query/2` call sends a new user message to the same process, and the CLI maintains the full conversation in memory.

```elixir
alias ClaudeSDK.Client
alias ClaudeSDK.Types.Options

Client.with_client([options: %Options{permission_mode: :bypass_permissions}], fn client ->
  # First turn
  Client.query(client, "What is the capital of France?")
  |> Enum.each(&IO.inspect/1)

  # Second turn -- Claude remembers the first
  Client.query(client, "And what about Germany?")
  |> Enum.each(&IO.inspect/1)

  # Third turn -- full conversation is in context
  Client.query(client, "Which of those two cities is older?")
  |> Enum.each(&IO.inspect/1)
end)
```

`with_client/2` handles connection setup and teardown. The subprocess starts when you connect and stops when the callback returns (or raises).

## Client Lifecycle

### Automatic (recommended)

`with_client/2` manages everything:

```elixir
Client.with_client([options: %Options{}], fn client ->
  # client is connected and ready
  Client.query(client, "Hello") |> Enum.to_list()
end)
# client is closed, subprocess is stopped
```

### Manual

For more control, manage the lifecycle yourself:

```elixir
{:ok, client} = Client.start_link(options: %Options{})
:ok = Client.connect(client)

# Use it...
Client.query(client, "Hello") |> Enum.to_list()
Client.query(client, "Follow up") |> Enum.to_list()

# Clean up
Client.close(client)
```

### Under a Supervisor

The Client is a GenServer and can live in your supervision tree:

```elixir
children = [
  {ClaudeSDK.Client, options: %Options{permission_mode: :bypass_permissions}}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

After starting, call `Client.connect/1` before sending queries.

## How Context is Maintained

The conversation context lives **inside the CLI subprocess**, not in the SDK. When you call `Client.query/2`, the SDK sends a simple user message:

```json
{"type": "user", "session_id": "abc-123", "message": {"role": "user", "content": "Your prompt"}}
```

The CLI appends this to its internal conversation history and generates a response considering all prior turns. The SDK doesn't re-send previous messages -- it just sends the new one.

## Session IDs

Every conversation has a `session_id`. It appears in:

- `ResultMessage.session_id` -- at the end of each query
- `UserMessage.session_id` -- echoed back when you send a message

The Client captures the `session_id` from the first result and sends it along with subsequent messages automatically.

## Resuming Conversations

Sessions are persisted to disk by the CLI. You can resume a previous conversation in three ways:

### 1. New Client with session_id

```elixir
# Previous conversation returned session_id "abc-123"
Client.with_client(
  [options: %Options{session_id: "abc-123", permission_mode: :bypass_permissions}],
  fn client ->
    Client.query(client, "Continue where we left off")
    |> Enum.each(&IO.inspect/1)
  end
)
```

### 2. Stateless query with resume

```elixir
ClaudeSDK.query("Follow up on that", %Options{resume: "abc-123"})
|> Enum.each(&IO.inspect/1)
```

### 3. Continue the most recent session

```elixir
ClaudeSDK.query("Continue", %Options{continue: true})
|> Enum.each(&IO.inspect/1)
```

### 4. From the Claude Code terminal

Sessions created by the SDK are regular CLI sessions. Resume them interactively:

```bash
claude --resume abc-123
```

This works both ways -- sessions started in the terminal can be resumed via the SDK.

## Forking Sessions

Fork creates a branch of an existing conversation without modifying the original:

```elixir
Client.with_client(
  [options: %Options{session_id: "abc-123", fork_session: true}],
  fn client ->
    # This is a new session branched from abc-123
    Client.query(client, "Let's try a different approach")
    |> Enum.each(&IO.inspect/1)
  end
)
```

## Accumulating Conversation State

The SDK streams messages forward -- it doesn't provide a method to retrieve the full conversation history from the CLI. If you need the history for your own purposes (UI display, logging, analysis), accumulate it yourself:

```elixir
alias ClaudeSDK.Types.{AssistantMessage, ResultMessage, UserMessage}

Client.with_client([options: %Options{permission_mode: :bypass_permissions}], fn client ->
  history = []

  # Turn 1
  messages_1 = Client.query(client, "What is 2+2?") |> Enum.to_list()
  history = history ++ [%{role: :user, content: "What is 2+2?"}] ++ messages_1

  # Turn 2
  messages_2 = Client.query(client, "Multiply that by 3") |> Enum.to_list()
  history = history ++ [%{role: :user, content: "Multiply that by 3"}] ++ messages_2

  # Now `history` has the full conversation for your use
  history
end)
```

## Session Introspection

List and inspect sessions stored on disk without a running subprocess:

```elixir
# List sessions for the current directory
sessions = ClaudeSDK.list_sessions()

# List with filters
sessions = ClaudeSDK.list_sessions(directory: "/path/to/project", limit: 10)

# Get conversation history for a specific session
messages = ClaudeSDK.get_session_messages("abc-123")

# Annotate sessions
ClaudeSDK.rename_session("abc-123", "Auth refactor discussion")
ClaudeSDK.tag_session("abc-123", "v1.0-release")
```

## Mid-Session Operations

The Client supports several operations between queries:

```elixir
# Change model
Client.set_model(client, "claude-sonnet-4-6")

# Change permission mode
Client.set_permission_mode(client, :bypass_permissions)

# Interrupt a running query (from another process)
Client.interrupt(client)

# Check connection state
Client.connected?(client)

# Stop a running subtask
Client.stop_task(client, "task-id-123")

# MCP server management
{:ok, status} = Client.get_mcp_status(client)
Client.reconnect_mcp_server(client, "my-server")
Client.toggle_mcp_server(client, "my-server", false)

# Server info
{:ok, info} = Client.get_server_info(client)
```

These can only be called when the Client is in `:connected` state (not streaming).

## File Checkpointing and Rewind

With `enable_file_checkpointing: true`, the CLI snapshots file state at each turn. You can rewind files to any previous point using the `UserMessage.uuid`:

```elixir
alias ClaudeSDK.Types.{Options, UserMessage}

Client.with_client(
  [options: %Options{enable_file_checkpointing: true, permission_mode: :bypass_permissions}],
  fn client ->
    # First turn -- make some changes
    messages = Client.query(client, "Refactor the auth module") |> Enum.to_list()

    # Capture the user message UUID
    user_msg = Enum.find(messages, &match?(%UserMessage{}, &1))

    # Second turn -- make more changes
    Client.query(client, "Now add logging") |> Enum.to_list()

    # Undo turn 2's file changes, rewind to the state after turn 1
    :ok = Client.rewind_files(client, user_msg.uuid)
  end
)
```

Rewind only affects files on disk -- the conversation history is not modified.

## Concurrency

A single Client processes one query at a time. Calling `query/2` while another is streaming returns `{:error, {:invalid_state, :streaming}}`.

For parallel workloads, use separate Client instances:

```elixir
tasks =
  Enum.map(prompts, fn prompt ->
    Task.async(fn ->
      Client.with_client([options: %Options{permission_mode: :bypass_permissions}], fn client ->
        Client.query(client, prompt) |> Enum.to_list()
      end)
    end)
  end)

results = Task.await_many(tasks, 120_000)
```

## State Machine

The Client transitions through these states:

```
:disconnected  -->  :connected  <-->  :streaming
                        |
                        +--->  :awaiting_rewind
                        |
                        +--->  :awaiting_control_response
```

- `:disconnected` -- initial state, before `connect/1`
- `:connected` -- ready for queries or mid-session operations
- `:streaming` -- a `query/2` is active
- `:awaiting_rewind` -- a `rewind_files/2` request is pending
- `:awaiting_control_response` -- an MCP status or server info request is pending
