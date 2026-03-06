# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - Unreleased

### Added

- `output_format` option for CLI-level structured output (populates `ResultMessage.structured_output`)
- `hooks` option for lifecycle hook commands (before/after tool calls, notifications)
- `sandbox` option with `SandboxSettings` for restricted filesystem/network access
- `allowed_tools` / `disallowed_tools` options for tool filtering (replaces `tool_filter`)
- Hook callback support in `ControlRouter` (arity-1 and arity-2 callbacks, lists of callbacks)
- `ClaudeSDK.Internal` module extracting shared initialization logic from `ClaudeSDK` and `Client`
- Troubleshooting section in README

### Improved

- Expanded test coverage across core modules
- Comprehensive README rewrite with new sections for output format, sandbox, hooks, and full configuration reference
- Simplified `ClaudeSDK` and `Client` by extracting common logic into `Internal`
- `CommandBuilder` now supports `output_format` flag
- `Options` validation for `can_use_tool` callback arity

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
