# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ClaudeSDK is an Elixir SDK that wraps the Claude Code CLI as a subprocess, communicating via stdin/stdout using newline-delimited JSON (NDJSON). It provides both a stateless streaming API (`ClaudeSDK.query/2`) and a stateful multi-turn client (`ClaudeSDK.Client`).

Only runtime dependency is `jason` for JSON encoding/decoding. Requires Elixir ~> 1.17.

## Commands

```bash
mix deps.get              # Install dependencies
mix test                  # Run tests (excludes :live tests by default)
mix test test/claude_sdk/message_parser_test.exs  # Run a single test file
mix test test/claude_sdk/message_parser_test.exs:15  # Run a specific test at line
mix test --include live   # Include integration tests (requires real Claude CLI)
mix format                # Format code
mix format --check-formatted  # Check formatting without changes
```

Live tests (tagged `@tag :live`) require the Claude CLI installed and are excluded by default via `test/test_helper.exs`.

## Architecture

### Two Usage Patterns

- **`ClaudeSDK.query/2`** — Stateless, single-turn. Uses `Stream.resource/3` to spawn a subprocess, stream messages, and auto-cleanup. Each call creates and destroys a subprocess.
- **`ClaudeSDK.Client`** — Stateful GenServer keeping one subprocess alive across multiple `query/2` calls. Supports session persistence, file checkpointing, rewind, mid-session model/permission changes, MCP management, and sub-agent task control. State machine: `:disconnected` → `:connected` → `:streaming` → `:awaiting_rewind` → `:awaiting_control_response`.

### Public API Surface

#### `ClaudeSDK` (stateless)

- `query/2` — send prompt, get stream of typed messages
- `create_mcp_server/3` — create in-process MCP server config
- Session delegates: `list_sessions/1`, `get_session_info/2`, `get_session_messages/2`, `get_session_transcript/2`, `rename_session/3`, `tag_session/3`, `delete_session/2`, `fork_session/2`

#### `ClaudeSDK.Client` (stateful GenServer)

Lifecycle:
- `start_link/1`, `connect/1`, `connect!/1`, `close/1`, `with_client/2`
- `disconnect/1` — stop subprocess, keep GenServer alive for reconnection
- `connected?/1` — check connection state

Queries:
- `query/3` — send prompt, get stream; supports `parent_tool_use_id` and `tool_use_result` options
- `interrupt/1` — cancel active streaming query

Mid-session control (all require `:connected` state, block until CLI acknowledges):
- `set_model/2`, `set_permission_mode/2`
- `rewind_files/2` — rewind to file checkpoint (requires `enable_file_checkpointing: true`)
- `get_mcp_status/1`, `get_context_usage/1`, `get_server_info/1`
- `reconnect_mcp_server/2`, `toggle_mcp_server/3`, `add_mcp_server/3`, `remove_mcp_server/2`
- `stop_task/2` — stop a running sub-agent task

#### `ClaudeSDK.Sessions` (JSONL file introspection, no running subprocess needed)

- `list_sessions/1` — scan project dir, extract metadata from head/tail of JSONL
- `get_session_info/2`, `get_session_messages/2`, `get_session_transcript/2`
- `rename_session/3`, `tag_session/3` — append metadata entries (with Unicode sanitization)
- `delete_session/2`, `fork_session/2` — file-level operations with path traversal protection

### Module Layout

- **`ClaudeSDK`** (`lib/claude_sdk.ex`) — Main entry point. Stateless query, MCP server creation, session delegates.
- **`ClaudeSDK.Client`** (`lib/claude_sdk/client.ex`) — Multi-turn GenServer with state machine. Forwards messages between subprocess and caller process.
- **`ClaudeSDK.Sessions`** (`lib/claude_sdk/sessions.ex`) — Session JSONL file introspection: list, info, messages, transcript, rename, tag, delete, fork.
- **`ClaudeSDK.ControlRouter`** (`lib/claude_sdk/control_router.ex`) — Dispatches `control_request` messages by subtype (`can_use_tool`, `mcp_message`, `hook_callback`). Returns `{:handled, response}`, `{:handled_with_interrupt, response}`, or `{:unhandled, request}`. Handlers run in spawned processes with configurable timeouts.
- **`ClaudeSDK.MCP.Server`** (`lib/claude_sdk/mcp/server.ex`) — In-process MCP server creation, JSONRPC tool dispatch (tools/call, tools/list, initialize), argument validation, and result formatting (with 1MB truncation).
- **`ClaudeSDK.MCP.Tool`** (`lib/claude_sdk/mcp/tool.ex`) — Tool definition struct with handler callback.
- **`ClaudeSDK.MCP.StdioServerConfig`**, **`SSEServerConfig`**, **`HttpServerConfig`** (`lib/claude_sdk/mcp/server_config.ex`) — Typed config structs for external MCP servers.
- **`ClaudeSDK.MessageParser`** (`lib/claude_sdk/message_parser.ex`) — Parses raw JSON maps into typed message structs. Unknown types preserved for forward compatibility.
- **`ClaudeSDK.Internal`** (`lib/claude_sdk/internal.ex`) — Shared init logic, request ID generation, subprocess cleanup.
- **`ClaudeSDK.Transport`** (`lib/claude_sdk/transport.ex`) — Behaviour with `@callback` specs: `start_link/1`, `start/1`, `send_message/2`, `stop/1`. Custom transports must send `{:claude_message, map()}` and `{:claude_exit, reason}` to the caller.
- **`ClaudeSDK.Transport.Subprocess`** (`lib/claude_sdk/transport/subprocess.ex`) — Default transport. GenServer wrapping an Erlang Port. Monitors caller, handles line buffering, version checks.
- **`ClaudeSDK.Transport.CommandBuilder`** (`lib/claude_sdk/transport/command_builder.ex`) — Converts `Options` struct into CLI argument list and environment variables.
- **`ClaudeSDK.Transport.CLIDiscovery`** (`lib/claude_sdk/transport/cli_discovery.ex`) — Finds the `claude` binary via PATH or known install locations.
- **`ClaudeSDK.Transport.LineBuffer`** (`lib/claude_sdk/transport/line_buffer.ex`) — Accumulates partial line data for NDJSON parsing. 10MB overflow protection.

### Types (`lib/claude_sdk/types/`)

- **`Options`** — 52-field config struct mapping to CLI flags. Covers: model, prompts, tools, permissions (`can_use_tool` callback), limits, sessions, MCP, hooks, agents, thinking, structured output, sandbox, plugins, effort, betas, timeouts, transport module.
- **`Messages`** — AssistantMessage, UserMessage, SystemMessage, ResultMessage, StreamEvent, ControlRequest/Response, TaskStartedMessage, TaskProgressMessage, TaskNotificationMessage, RateLimitEvent
- **`ContentBlocks`** — TextBlock, ThinkingBlock, ToolUseBlock, ToolResultBlock
- **`AgentDefinition`** — Sub-agent definition with name, description, prompt, model, tools, allowed/disallowed_tools, max_turns, skills, memory scope, mcp_servers
- **`ThinkingConfig`** — Adaptive/enabled/disabled with optional budget_tokens
- **`SandboxSettings`** — Bash sandbox controls (enabled, network, violations, nested)
- **`ToolPermissionContext`** — Context passed to arity-3 permission callbacks (tool_name, input, request_id, permission_suggestions, raw_request)

### Error Types

- `CLINotFoundError` — CLI binary not found/executable
- `TransportError` — Port/subprocess communication failure
- `ProtocolError` — Malformed JSON from CLI
- `QueryError` — Invalid Client state for operation
- `ProcessExitError` — Non-zero CLI exit code (with `exit_code` field)
- `TimeoutError` — Init or message timeout exceeded (with `timeout_ms` field)

### Control Request Flow

1. Subprocess spawned, `initialize` control_request sent (includes hooks and agent definitions)
2. Wait for `control_response` (configurable timeout, default 30s). Messages received during init are buffered and replayed.
3. Send `user` message with prompt
4. Receive stream of messages:
   - `control_request` messages are intercepted and dispatched via ControlRouter to registered handlers (`can_use_tool`, `mcp_message`, `hook_callback`)
   - `control_cancel_request` messages are acknowledged and discarded (handlers run synchronously with timeouts)
   - All other messages are parsed into typed structs and yielded to the stream
5. Stream halts on `ResultMessage` or subprocess exit (configurable timeout, default 120s)
6. Control requests from the SDK (set_model, rewind_files, get_mcp_status, etc.) use `request_id` correlation with stale response detection

### Permission Callbacks

- Arity-2: `fn tool_name, input -> :allow | {:allow, opts} | :deny | {:deny, reason} end`
- Arity-3: `fn tool_name, input, %ToolPermissionContext{} -> ... end`
- Additional returns: `{:allow, updated_input: map, updated_permissions: [String.t()]}`, `{:deny, reason, :interrupt}`
- Run with timeout (`hook_timeout_ms`, default 30s) via `spawn_monitor` + `Process.exit(:kill)`

### Hook Callbacks

Hooks are keyed by event name (e.g. `"PreToolUse"`, `"PostToolUse"`, `"Notification"`) in `Options.hooks`. Values can be:
- Single arity-1 function `fn hook_input -> :ok | {:ok, result_map} end`
- Single arity-2 function `fn hook_event, hook_input -> ... end`
- List of callbacks (results merged)

Run with timeout, killed on hang. Dispatched via `ControlRouter` on `hook_callback` control requests.

### Testing Approach

Tests use mock CLI shell scripts (`test/support/mock_cli*.sh`) that emit predefined NDJSON responses. Test fixtures are defined in `test/support/fixtures.ex`. This makes tests fast and deterministic without requiring the real CLI. 42 test files, 640+ tests covering edge cases (crashes, timeouts, stale messages, buffer overflow, state recovery).

## Conventions

- All public functions have `@spec` type annotations
- All 42 modules have `@moduledoc`
- Handler callbacks return `:allow | {:allow, map()} | :deny | {:deny, String.t()} | {:deny, String.t(), :interrupt} | {:result, map()}`
- Caller processes receive messages via `{:claude_message, map()}` (subprocess) or `{:client_message, gen, map()}` (Client, with generation counter for stale detection)
- Permission modes: `:default`, `:accept_edits`, `:plan`, `:bypass_permissions`, `:dont_ask`
- `transport_module` in Options allows swapping the transport (must implement `ClaudeSDK.Transport` behaviour)
