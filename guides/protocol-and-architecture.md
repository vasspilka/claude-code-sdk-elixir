# Protocol & Architecture

This guide explains how the SDK communicates with the Claude Code CLI under the hood. Understanding this protocol is useful for debugging, building custom integrations, or simply knowing what happens when you call `ClaudeSDK.query/2`.

## Overview

The SDK spawns the Claude Code CLI as a child process and communicates over **stdin/stdout** using **NDJSON** (newline-delimited JSON). Each line is a self-contained JSON object representing a message. The protocol is **bidirectional** -- both sides can send messages at any time during a session.

```
Your App
  |
  v
ClaudeSDK (Elixir)
  |
  v
Subprocess GenServer
  |
  v
Erlang Port (stdin/stdout pipes)
  |
  v
Claude Code CLI (OS process)
```

## Spawning the CLI

The SDK does **not** use a shell. It spawns the CLI binary directly via Erlang's `Port.open/2` with `:spawn_executable`, which calls the OS-level `execve` -- no `/bin/sh`, no command string parsing, no injection risk.

```elixir
# What happens inside Transport.Subprocess
port = Port.open({:spawn_executable, cli_path}, [
  :binary,
  :exit_status,
  {:line, 1_048_576},   # 1MB line buffer
  {:args, args},         # CLI arguments as a list
  {:env, charlist_env},  # environment variables
  {:cd, working_dir}     # working directory
])
```

The CLI is always launched with these base flags:

```
--output-format stream-json --input-format stream-json --verbose
```

This tells the CLI to speak NDJSON on both stdin and stdout rather than its normal interactive terminal mode.

### CLI Discovery

Before spawning, the SDK locates the `claude` binary by:

1. Using `Options.cli_path` if explicitly provided
2. Searching `$PATH` via `System.find_executable/1`
3. Checking known install locations (`~/.npm/bin/claude`, `/usr/local/bin/claude`, etc.)

If the binary isn't found, a `CLINotFoundError` is raised.

## The NDJSON Transport

Communication uses newline-delimited JSON -- one JSON object per `\n`-terminated line. The implementation is minimal:

- **Sending**: `Jason.encode!(message) <> "\n"` piped to stdin via `Port.command/2`
- **Receiving**: The Erlang Port delivers lines as `{port, {:data, {:eol, line}}}` messages. Each line is decoded with `Jason.decode/1`.

For lines exceeding the 1MB port buffer, data arrives as one or more `{:noeol, chunk}` fragments followed by a final `{:eol, remainder}`. The `ClaudeSDK.Transport.LineBuffer` module accumulates these before parsing.

There's a 10MB safety limit on the buffer to prevent runaway output from consuming memory.

## Protocol Phases

A complete session flows through these phases:

### Phase 1: Initialization Handshake

After spawning, the SDK sends an `initialize` control request and waits for a response:

**SDK -> CLI** (stdin):

```json
{
  "type": "control_request",
  "request_id": "req_abc123",
  "request": {
    "subtype": "initialize",
    "hooks": null,
    "agents": null
  }
}
```

**CLI -> SDK** (stdout):

```json
{
  "type": "control_response",
  "request_id": "req_abc123",
  "response": {}
}
```

The SDK blocks up to 30 seconds (configurable via `init_timeout_ms`) waiting for this response. Any non-`control_response` messages that arrive during this window are discarded. If the CLI exits or the timeout is reached, initialization fails.

### Phase 2: User Message

Once initialized, the SDK sends the user's prompt:

**SDK -> CLI**:

```json
{
  "type": "user",
  "session_id": null,
  "message": {"role": "user", "content": "What is 2+2?"},
  "parent_tool_use_id": null
}
```

The `session_id` is `null` for new sessions. For resumed sessions, it contains the session ID from a previous `ResultMessage`.

### Phase 3: Streaming Response

The CLI streams back messages as it works. Each message is a single NDJSON line:

#### Assistant text

```json
{
  "type": "assistant",
  "message": {
    "content": [{"type": "text", "text": "2+2 equals 4."}],
    "model": "claude-sonnet-4-6"
  }
}
```

#### Tool use (Claude wants to call a tool)

```json
{
  "type": "assistant",
  "message": {
    "content": [{
      "type": "tool_use",
      "id": "tu_abc123",
      "name": "Read",
      "input": {"file_path": "/path/to/file.ex"}
    }]
  }
}
```

#### Tool result (CLI executed the tool)

```json
{
  "type": "assistant",
  "message": {
    "content": [{
      "type": "tool_result",
      "tool_use_id": "tu_abc123",
      "content": "file contents here...",
      "is_error": false
    }]
  }
}
```

An `AssistantMessage` can contain multiple content blocks in a single message -- for example, a `ThinkingBlock` followed by a `TextBlock` followed by a `ToolUseBlock`.

#### Stream events (partial deltas)

When `include_partial_messages: true` is set, the CLI also emits incremental content as it generates:

```json
{
  "type": "stream_event",
  "event": {
    "type": "content_block_delta",
    "delta": {"text": "2+2"}
  }
}
```

### Phase 4: Control Requests (Bidirectional)

This is what makes the protocol interesting. Mid-stream, the **CLI can ask the SDK** for decisions. The SDK must respond before the CLI continues.

#### Permission check

**CLI -> SDK**: "Can Claude use this tool?"

```json
{
  "type": "control_request",
  "request_id": "req_xyz789",
  "request": {
    "subtype": "can_use_tool",
    "tool_name": "Bash",
    "input": {"command": "rm -rf /tmp/test"}
  }
}
```

**SDK -> CLI**: Response from your `can_use_tool` callback:

```json
{
  "type": "control_response",
  "request_id": "req_xyz789",
  "response": {"allowed": false, "reason": "Destructive commands not permitted"}
}
```

#### MCP tool call

**CLI -> SDK**: "Route this to the MCP server":

```json
{
  "type": "control_request",
  "request_id": "req_mcp001",
  "request": {
    "subtype": "mcp_message",
    "server_name": "my-tools",
    "jsonrpc_message": {
      "method": "tools/call",
      "params": {"name": "lookup_user", "arguments": {"user_id": "123"}}
    }
  }
}
```

**SDK -> CLI**: Result from your MCP tool handler:

```json
{
  "type": "control_response",
  "request_id": "req_mcp001",
  "response": {
    "jsonrpc_response": {
      "result": {"content": [{"type": "text", "text": "{\"name\":\"Alice\"}"}]}
    }
  }
}
```

#### Hook callbacks

```json
{
  "type": "control_request",
  "request_id": "req_hook01",
  "request": {
    "subtype": "hook_callback",
    "hook_event": "PreToolUse",
    "hook_input": {"tool_name": "Bash", "input": {"command": "mix test"}}
  }
}
```

The `ClaudeSDK.ControlRouter` dispatches these by subtype to registered handlers. If no handler is registered, unhandled control requests are forwarded to the caller as regular stream messages.

### Phase 5: Result

The stream ends with a result message:

```json
{
  "type": "result",
  "subtype": "success",
  "session_id": "session_abc123",
  "duration_ms": 4500,
  "duration_api_ms": 3200,
  "num_turns": 3,
  "total_cost_usd": 0.02,
  "is_error": false,
  "usage": {"input_tokens": 1500, "output_tokens": 800},
  "result": "The answer is 4."
}
```

When the SDK sees `type: "result"`, the stream terminates. For the stateless `query/2`, the subprocess is cleaned up. For the `Client`, the subprocess stays alive for the next turn.

### Phase 6: Next Turn (Client Only)

With `ClaudeSDK.Client`, the subprocess remains running after the result. To send a follow-up, go back to Phase 2 -- send another `user` message on the same stdin pipe. The CLI keeps the full conversation history in memory.

## Message Flow Diagram

```
SDK (Elixir)                              CLI (subprocess)
    |                                          |
    |--- control_request: initialize --------->|
    |<-- control_response ---------------------|
    |                                          |
    |--- user message ------------------------>|
    |                                          |
    |<-- assistant (thinking) -----------------|
    |<-- assistant (text) ---------------------|
    |<-- assistant (tool_use: Read) -----------|
    |<-- assistant (tool_result) --------------|
    |<-- assistant (tool_use: Bash) -----------|
    |<-- control_request: can_use_tool --------|
    |--- control_response: allowed ----------->|
    |<-- assistant (tool_result) --------------|
    |<-- assistant (text: final answer) -------|
    |<-- result -------------------------------|
    |                                          |
    |--- user message (turn 2) --------------->|  (Client only)
    |          ... repeats ...                 |
```

## Internal Architecture

### Subprocess GenServer

`ClaudeSDK.Transport.Subprocess` is a GenServer that owns the Erlang Port. It:

1. **Sends** messages by JSON-encoding and writing to stdin via `Port.command/2`
2. **Receives** stdout data as Erlang messages in its mailbox (`{port, {:data, ...}}`)
3. **Parses** complete lines as JSON and forwards them as `{:claude_message, map}` to the caller process
4. **Detects** process exit via `{port, {:exit_status, code}}` and sends `{:claude_exit, reason}`

### Message Parser

Every raw JSON map from the CLI passes through `ClaudeSDK.MessageParser.parse/1`, which routes on the `"type"` field and returns typed Elixir structs:

| JSON `type` field | Elixir struct |
|---|---|
| `"assistant"` | `ClaudeSDK.Types.AssistantMessage` (with `ClaudeSDK.Types.TextBlock`, `ClaudeSDK.Types.ThinkingBlock`, `ClaudeSDK.Types.ToolUseBlock`, `ClaudeSDK.Types.ToolResultBlock` content) |
| `"user"` | `ClaudeSDK.Types.UserMessage` |
| `"system"` | `ClaudeSDK.Types.SystemMessage` |
| `"result"` | `ClaudeSDK.Types.ResultMessage` |
| `"stream_event"` | `ClaudeSDK.Types.StreamEvent` |
| `"control_request"` | `ClaudeSDK.Types.ControlRequest` |
| `"control_response"` | `ClaudeSDK.Types.ControlResponse` |
| `"task_started"` | `ClaudeSDK.Types.TaskStartedMessage` |
| `"task_progress"` | `ClaudeSDK.Types.TaskProgressMessage` |
| `"task_notification"` | `ClaudeSDK.Types.TaskNotificationMessage` |
| Unknown types | Passed through as raw maps (forward compatibility) |

### Control Router

`ClaudeSDK.ControlRouter` sits between the subprocess and the caller. When a `control_request` arrives:

1. It checks for a registered handler matching the request's `subtype`
2. If found, calls the handler and sends the response back to stdin
3. If not found, forwards the raw message to the caller's stream

Handlers are built from your `Options` at connection time:

- `can_use_tool` callback -> `"can_use_tool"` handler
- `mcp_servers` -> `"mcp_message"` handler
- `hooks` -> `"hook_callback"` handler

### Stateless vs Stateful

| | `ClaudeSDK.query/2` | `ClaudeSDK.Client` |
|---|---|---|
| Subprocess lifetime | One per call | One across all calls |
| Implementation | `Stream.resource/3` | GenServer |
| State | Caller's process mailbox | GenServer state |
| Session continuity | Via `session_id` option (disk reload) | Automatic (in-memory) |
| Multi-turn overhead | Subprocess spawn + session reload per turn | Single message send |

## Timeouts

The SDK enforces three timeouts:

| Timeout | Default | Configurable via | What happens |
|---|---|---|---|
| Initialization | 30s | `init_timeout_ms` | `TimeoutError` raised |
| Message inactivity | 120s | `message_timeout_ms` | Stream ends with error `ResultMessage` |
| Control request | 30s | `control_timeout_ms` | `{:error, :control_timeout}` returned (Client only) |

## Session Persistence

The CLI persists sessions to disk (in `~/.claude/projects/`). This means:

- Sessions started via the SDK can be resumed in the Claude Code terminal with `claude --resume <session_id>`
- Sessions started in the terminal can be resumed via the SDK with `%Options{resume: "session_id"}`
- The CLI doesn't distinguish between SDK and terminal sessions -- they're the same format

The `session_id` is returned in every `ResultMessage` and in `UserMessage` structs during streaming.
