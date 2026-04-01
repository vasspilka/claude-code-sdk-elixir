# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `ClaudeSDK.Sessions.get_session_transcript/2` — get the full unfiltered JSONL transcript for a session, including tool results, control requests, and system messages (useful for sub-agent introspection)
- `ClaudeSDK.get_session_transcript/2` top-level delegate
- `ClaudeSDK.Sessions.delete_session/2` — delete a session by removing its JSONL file
- `ClaudeSDK.Sessions.fork_session/2` — fork a session by copying its transcript to a new session ID, with optional `up_to_message_uuid` truncation
- `ClaudeSDK.delete_session/2` and `ClaudeSDK.fork_session/2` top-level delegates
- CLI version warning forwarded to caller process as `{:claude_version_warning, warning}` message (previously fire-and-forget log only)
- Example scripts under `examples/` — quick_start, multi_turn, mcp_calculator, permission_callback, session_management, structured_output

### Fixed

- `CLAUDE_CODE_ENTRYPOINT` env var corrected from `cli-elixir` to `sdk-elixir`
- `CLAUDE_AGENT_SDK_VERSION` env var now included in subprocess environment

## [0.3.0] - 2026-03-30

### Added

- `ClaudeSDK.Transport` behaviour — pluggable transport abstraction with `start_link/1`, `start/1`, `send_message/2`, and `stop/1` callbacks
- `transport_module` option in `Options` (default: `ClaudeSDK.Transport.Subprocess`) — allows swapping the transport for testing or alternative communication channels
- `Client.disconnect/1` — stops the CLI subprocess while keeping the Client GenServer alive for later reconnection via `connect/1`
- `Client.query/3` now accepts `parent_tool_use_id` and `tool_use_result` keyword options for nested tool interaction flows, matching the Python SDK's `ClaudeSDKClient.query()`
- `ProcessExitError` exception — wraps non-zero CLI exit codes with `message` and `exit_code` fields, replacing raw exit code tuples
- `{:deny, reason, :interrupt}` permission callback return value — denies a tool AND interrupts the active conversation
- `{:allow, updated_permissions: [String.t()]}` permission callback option — allows granting additional permissions alongside input modifications
- `permission_suggestions` field on `ToolPermissionContext` — populated from CLI request for richer permission UI decisions
- MCP servers now respond to `initialize` JSONRPC requests with protocol version, capabilities, and server info
- MCP tool argument validation — tool arguments are validated against the tool's input schema (required fields + top-level type checking) before the handler is called

### Changed

- `Client.set_model/2`, `Client.set_permission_mode/2`, and `Client.stop_task/2` are now blocking — they wait for CLI acknowledgment instead of being fire-and-forget
- `Client.interrupt/1` now sends a proper `control_request` with `request_id` instead of a bare `{type: "interrupt"}` message, matching the CLI protocol
- All subprocess communication in `ClaudeSDK` and `Client` routes through the configured `transport_module` instead of hardcoded `Subprocess` calls
- `Internal.safe_stop_subprocess/1` uses generic `GenServer.stop/2` instead of transport-specific `Subprocess.stop/1`
- SDK version fallback uses compile-time module attribute instead of runtime `MixProject.project()` call
- Permission callbacks now execute with a timeout (uses `hook_timeout_ms`, default 30s) — hanging callbacks are killed and return `{:deny, "Permission callback timed out"}`
- `extra_args` now rejects `--permission-mode`, `--output-format`, `--input-format`, and `--permission-prompt-tool` to prevent bypassing SDK-managed flags
- MCP response key changed from `jsonrpc_response` to `mcp_response`/`message`, and incoming MCP messages read from `request["message"]` with fallback to `request["jsonrpc_message"]`

### Fixed

- **Control response request_id correlation** — Client now matches `request_id` on incoming `control_response` messages against the pending request. Stale responses (e.g. from a timed-out request) are discarded instead of being attributed to a new request. Backwards-compatible with older CLI versions that omit `request_id`.
- **Port.command failure handling** — `Subprocess` now checks the return value of `Port.command/2` and rescues `ArgumentError`. On failure, the caller is notified with `{:claude_exit, {:error, :port_closed}}` and the GenServer stops gracefully, instead of silently losing messages.
- **Subprocess caller monitoring** — `Subprocess` now monitors its caller process and stops automatically if the caller dies, preventing orphaned CLI subprocesses
- **Stale mailbox flushing** — `Client.query/3` now flushes stale `{:client_message, gen, _}` messages from the caller's mailbox after each query, preventing unbounded mailbox growth
- `active_caller` now cleared on result message in streaming state (previously leaked stale reference)
- Unicode sanitization added to `Sessions.rename_session/3` and `Sessions.tag_session/3` — NFKC normalization and dangerous Unicode stripping (format, private-use, unassigned codepoints), matching Python SDK's `_sanitize_unicode()`
- Clarified `output_format` docs — `output_format: :json` and `json_schema` share the same underlying CLI flag and are mutually exclusive
- Removed TOCTOU race in `Internal.safe_stop_subprocess/1` — `Process.alive?` check before `GenServer.stop` was redundant since the `catch :exit` already handles dead processes
- `setting_sources` values now validated — must be `"user"`, `"project"`, or `"local"` (catches typos early, matching Python SDK validation)
- `LineBuffer.accumulate/2` now returns `{:error, :buffer_overflow}` instead of silently resetting on overflow

### Improved

- 156 new tests: Client disconnect/reconnect, blocking control operations, interrupt states, caller monitor recovery, ControlRouter hooks (arity-1/2, lists, crashes, timeouts), LineBuffer edge cases, Sessions CRUD with unicode sanitization, MCP server config validation
- All 16 mock CLI scripts now handle `-v` flag for version checking

## [0.2.1] - 2026-03-25

### Added

- `log_file` option for capturing CLI log output (maps to `--log-file`), replacing the need for `extra_args`
- `hook_timeout_ms` option (default 30s) — hook callbacks are now executed with a timeout via `Task.async`/`Task.yield`; hanging hooks no longer block the stream
- MCP tool name collision warning — `build_tool_index` now logs a warning when two servers register the same tool name

### Changed

- **Breaking:** `session_id` default changed from `"default"` to `nil` — the CLI now auto-generates session IDs instead of all queries sharing a single `"default"` session. Set `session_id` explicitly to preserve the old behavior.
- `Subprocess.send_message/2` changed from `GenServer.call` to `GenServer.cast` to prevent potential deadlock when the subprocess mailbox is backed up

### Fixed

- MCP server CLI config now only sends `type` and `name` (CLI discovers tools at runtime via control requests)
- Hook callback result merging accumulates `{:result, map}` values instead of last-write-wins
- `receive_messages` preserves state through halt for proper stream cleanup
- `--thinking` CLI flag now sends plain string (`enabled`/`adaptive`/`disabled`) with separate `--max-thinking-tokens` flag
- `--sandbox` merged into `--settings` instead of being passed as a separate CLI flag
- MCP tool handlers wrapped in try/rescue to return error results instead of crashing
- Added catch-all clauses for JSONRPC notifications and unrecognized messages
- Validation preventing both `json_schema` and `output_format` from being set simultaneously
- Unified line buffer handling in `Subprocess` — `:eol` and `:noeol` Port messages now both route through `LineBuffer` instead of using two parallel buffering paths

### Improved

- Expanded test coverage for hooks, MCP error handling, options validation, and command builder
- Added live integration test suites for streaming, client operations, MCP, and advanced features

## [0.2.0] - 2026-03-24

### Added

- `output_format` option for CLI-level structured output (populates `ResultMessage.structured_output`)
- `hooks` option for lifecycle hook commands (before/after tool calls, notifications)
- `sandbox` option with `SandboxSettings` for restricted filesystem/network access
- `allowed_tools` / `disallowed_tools` options for tool filtering (replaces `tool_filter`)
- Hook callback support in `ControlRouter` (arity-1 and arity-2 callbacks, lists of callbacks)
- Internal module extracting shared initialization logic from `ClaudeSDK` and `Client`
- Troubleshooting section in README
- `ClaudeSDK.Sessions` module — `list_sessions/1`, `get_session_messages/2`, `get_session_info/2`, `rename_session/3`, `tag_session/3`
- `Client.stop_task/2` for stopping running subtasks
- `Client.connected?/1` to query connection state
- `Client.add_mcp_server/3` and `Client.remove_mcp_server/2` for dynamic MCP server management
- `RateLimitEvent` message type and parser
- `usage` field on `AssistantMessage` and `stop_reason` on `ResultMessage`
- Configurable `control_timeout_ms` option (default 30s)
- Caller process monitoring — Client self-heals to `:connected` when the stream consumer dies
- Server info cached from init handshake; `get_server_info/1` no longer requires a CLI round-trip
- CLI version check on subprocess init (warns if < 2.0.0)
- `AgentDefinition`: `skills`, `memory`, `mcp_servers` fields with validation (model must be sonnet/opus/haiku/inherit, memory must be user/project/local)
- `SandboxSettings`: `ignore_violations`, `enable_weaker_nested_sandbox` fields
- `StdioServerConfig`, `SSEServerConfig`, `HttpServerConfig` typed MCP server config structs
- Init handshake buffers messages received before `control_response` and replays them into the stream
- Dedicated guides: Getting Started, Multi-Turn Conversations, MCP Servers, Protocol & Architecture

### Fixed

- `output_format` bare map silently dropped in `CommandBuilder`
- Interrupt race condition via `query_gen` counter on client messages
- Rewind response catch-all silently returning `:ok` for unknown formats
- Init response now validated for errors during handshake
- Unknown keyword keys in `query/2` rejected to catch typos
- `extract_lines` now uses proper tail recursion with accumulator
- SDK version read from `mix.exs` instead of hardcoded fallback
- `permission_prompt_tool_name` mutual exclusivity validation with `can_use_tool` restored (matching Python SDK)
- `SandboxSettings.allow_unsandboxed_commands` changed from `[String.t()]` to `boolean()` matching Python SDK
- Dead `{:client_exit, _reason}` 2-tuple pattern removed from Client stream consumer
- Redundant `timeout || fallback` expressions removed (struct defaults are always present)
- CLI version check made non-blocking (fire-and-forget via `Task.start`)
- Session ID validation to prevent path traversal in `Sessions`

### Improved

- Expanded test coverage across core modules (including 15 AgentDefinition + 7 live integration tests)
- Comprehensive README rewrite with new sections for output format, sandbox, hooks, and full configuration reference
- README restructured — detailed content moved to dedicated guides under `guides/`
- Simplified `ClaudeSDK` and `Client` by extracting common logic into `Internal`
- `CommandBuilder` now supports `output_format` flag and `permission_prompt_tool_name`
- `Options` validation for `can_use_tool` callback arity
- Internal state names in errors replaced with semantic atoms (`:not_connected`, `:not_streaming`, `:busy`)
- `send_control_and_await` helper extracted to deduplicate control request boilerplate
- `ControlRouter` normalizes handler return values (`:allow`, `:deny`, `:ok` → tuples)
- Session metadata reads streamed instead of loading entire JSONL files
- Dropped messages in non-streaming client states logged at debug level
- Actual `elapsed_ms` reported in timeout `ResultMessage`s

## [0.1.0] - 2025-06-01

### Added

#### Core API

- `ClaudeSDK.query/2` — stateless, single-turn streaming API with automatic subprocess lifecycle management via `Stream.resource/3`. Accepts prompts with an optional `%Options{}` struct or keyword list.
- `ClaudeSDK.Client` — stateful multi-turn GenServer client that keeps a single subprocess alive across multiple queries. Supports a managed state machine (`:disconnected` -> `:connected` -> `:streaming` -> `:awaiting_rewind` -> `:awaiting_control_response`).
- `ClaudeSDK.Client.with_client/2` — convenience wrapper for automatic connection setup and teardown, similar to Python SDK's context manager pattern.

#### MCP (Model Context Protocol)

- `ClaudeSDK.create_mcp_server/3` — create in-process MCP server configurations with custom tool definitions.
- `ClaudeSDK.MCP.Tool` — struct for defining MCP tools with name, description, input schema, and handler callback.
- `ClaudeSDK.MCP.Server` — JSONRPC-based tool dispatch and result formatting for in-process MCP servers.

#### Permission Callbacks

- `can_use_tool` option with support for both arity-2 `(tool_name, input)` and arity-3 `(tool_name, input, %ToolPermissionContext{})` callbacks.
- Callbacks return `:allow`, `{:allow, updated_input}`, `:deny`, or `{:deny, reason}` for fine-grained tool approval.

#### Typed Message Structs

- `AssistantMessage` — assistant responses with typed content blocks.
- `UserMessage` — user input messages.
- `SystemMessage` — system-level notifications.
- `ResultMessage` — final result with session ID, duration, turn count, and optional structured output.
- `StreamEvent` — real-time streaming events for partial updates.
- `ControlRequest` / `ControlResponse` — internal control protocol messages.
- `TaskStartedMessage`, `TaskProgressMessage`, `TaskNotificationMessage` — task lifecycle tracking.

#### Typed Content Blocks

- `TextBlock` — plain text content.
- `ThinkingBlock` — extended thinking / chain-of-thought content.
- `ToolUseBlock` — tool invocation with name and input.
- `ToolResultBlock` — tool execution results.

#### Configuration

- `ClaudeSDK.Types.Options` — comprehensive configuration struct mapping to CLI flags, covering model selection, prompts, tool configuration, limits, permissions, session management, MCP, and more.
- Structured output via `json_schema` option for schema-constrained JSON responses.
- Extended thinking configuration via `ThinkingConfig` (adaptive, enabled, disabled modes with optional budget).
- Session management options: `continue`, `resume`, `fork_session`, and `session_id`.
- File checkpointing via `enable_file_checkpointing` for use with `Client.rewind_files/2`.
- Custom agent definitions via `AgentDefinition` struct.
- Sandbox configuration via `SandboxSettings` struct.
- `ToolPermissionContext` providing server name and MCP server URI context to permission callbacks.

#### Client Mid-Session Operations

- `Client.set_model/2` — change the model during an active session.
- `Client.set_permission_mode/2` — change permission mode mid-session.
- `Client.interrupt/1` — cancel an active streaming query.
- `Client.rewind_files/2` — rewind files to a previous checkpoint (requires file checkpointing).
- `Client.get_mcp_status/1` — query MCP server connection status.
- `Client.get_server_info/1` — query CLI server info.
- `Client.reconnect_mcp_server/2` — reconnect a failed MCP server.
- `Client.toggle_mcp_server/3` — enable or disable an MCP server.

#### Transport Layer

- NDJSON (newline-delimited JSON) transport via Erlang Port subprocess.
- `Transport.Subprocess` — GenServer wrapping an Erlang Port for stdin/stdout communication.
- `Transport.CommandBuilder` — converts `Options` struct into CLI argument list and environment variables.
- `Transport.CLIDiscovery` — automatic Claude CLI binary discovery via PATH lookup with fallback to known install locations.
- `Transport.LineBuffer` — accumulates partial line data for reliable NDJSON parsing.

#### Control Request Routing

- `ControlRouter` — dispatches `control_request` messages by subtype (`can_use_tool`, `mcp_message`).
- Automatic interception and handling of control requests during streaming.

#### Error Types

- `CLINotFoundError` — raised when the Claude CLI binary cannot be located.
- `TimeoutError` — raised on initialization or message receive timeout.
- `TransportError` — raised on subprocess communication failures.
- `ProtocolError` — raised on unexpected protocol-level issues.
- `QueryError` — raised on query-level failures (e.g., invalid client state).

#### Other

- `MessageParser` — parses raw JSON maps into typed message structs with forward-compatible handling of unknown message types.
- Only runtime dependency: `jason` for JSON encoding/decoding.
- Elixir ~> 1.17 required.
