# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ClaudeSDK is an Elixir SDK that wraps the Claude Code CLI as a subprocess, communicating via stdin/stdout using newline-delimited JSON (NDJSON). It provides both a stateless streaming API (`ClaudeSDK.query/2`) and a stateful multi-turn client (`ClaudeSDK.Client`).

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
- **`ClaudeSDK.Client`** — Stateful GenServer keeping one subprocess alive across multiple `query/2` calls. Supports session persistence, file checkpointing, and rewind. State machine: `:disconnected` → `:connected` → `:streaming` → `:awaiting_rewind`.

### Module Layout

- **`ClaudeSDK`** (`lib/claude_sdk.ex`) — Main entry point. Orchestrates subprocess lifecycle, initialization handshake, and message streaming.
- **`ClaudeSDK.Client`** (`lib/claude_sdk/client.ex`) — Multi-turn GenServer. Forwards messages between subprocess and caller process.
- **`ClaudeSDK.ControlRouter`** (`lib/claude_sdk/control_router.ex`) — Dispatches `control_request` messages by subtype (`can_use_tool`, `mcp_message`). Returns `{:handled, response}` or `{:unhandled, request}`.
- **`ClaudeSDK.MCP.Server`** (`lib/claude_sdk/mcp/server.ex`) — In-process MCP server creation, JSONRPC tool dispatch, and result formatting.
- **`ClaudeSDK.MCP.Tool`** (`lib/claude_sdk/mcp/tool.ex`) — Tool definition struct with handler callback.
- **`ClaudeSDK.MessageParser`** (`lib/claude_sdk/message_parser.ex`) — Parses raw JSON maps into typed message structs. Unknown types are preserved for forward compatibility.
- **`ClaudeSDK.Transport.Subprocess`** (`lib/claude_sdk/transport/subprocess.ex`) — GenServer wrapping an Erlang Port. Sends/receives NDJSON via stdin/stdout.
- **`ClaudeSDK.Transport.CommandBuilder`** (`lib/claude_sdk/transport/command_builder.ex`) — Converts `Options` struct into CLI argument list and environment variables.
- **`ClaudeSDK.Transport.CLIDiscovery`** (`lib/claude_sdk/transport/cli_discovery.ex`) — Finds the `claude` binary via PATH or known install locations.
- **`ClaudeSDK.Transport.LineBuffer`** (`lib/claude_sdk/transport/line_buffer.ex`) — Accumulates partial line data for NDJSON parsing.

### Types (`lib/claude_sdk/types/`)

- **`Options`** — Config struct mapping to CLI flags (model, permissions, MCP, session, limits, etc.)
- **`Messages`** — AssistantMessage, UserMessage, SystemMessage, ResultMessage, StreamEvent, ControlRequest/Response
- **`ContentBlocks`** — TextBlock, ThinkingBlock, ToolUseBlock, ToolResultBlock

### Message Flow

1. Subprocess spawned, `initialize` control_request sent
2. Wait for `control_response` (30s timeout)
3. Send `user` message with prompt
4. Receive stream of messages; `control_request` messages are intercepted and dispatched via ControlRouter
5. Stream halts on `ResultMessage` or subprocess exit (120s message timeout)

### Testing Approach

Tests use mock CLI shell scripts (`test/support/mock_cli*.sh`) that emit predefined NDJSON responses. Test fixtures are defined in `test/support/fixtures.ex`. This makes tests fast and deterministic without requiring the real CLI.

## Conventions

- All public functions have `@spec` type annotations
- Only runtime dependency is `jason` for JSON encoding/decoding
- Handler callbacks return `:allow | {:allow, map()} | {:deny, String.t()} | {:result, map()}`
- Caller processes receive messages via `{:claude_message, map()}` (subprocess) or `{:client_message, map()}` (Client)
- Elixir ~> 1.17 required
