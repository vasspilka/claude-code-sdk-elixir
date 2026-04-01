# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Elixir SDK (`claude_sdk`) wrapping the Claude Code CLI as a subprocess. Communicates via NDJSON over stdin/stdout. Requires Elixir ~> 1.17 and a working `claude` CLI installation.

## Commands

```bash
mix deps.get              # Install dependencies
mix test                  # Run unit tests (excludes live tests)
mix test --include live   # Run all tests including live CLI tests
mix test test/claude_sdk/client_test.exs          # Run a single test file
mix test test/claude_sdk/client_test.exs:42       # Run a specific test line
mix format                # Format code
mix format --check-formatted  # Check formatting
mix docs                  # Generate documentation
```

**Important**: Live tests (tagged `@tag :live`) require a real Claude CLI and will make API calls. They are excluded by default via `test_helper.exs`.

**Important**: Do not pipe `mix test` output (e.g., `mix test | cat`) — this causes hangs.

## Architecture

### Two Usage Patterns

1. **Stateless `ClaudeSDK.query/2`** — spawns a subprocess per call, returns a `Stream` of typed message structs. Uses `Stream.resource/3` internally.

2. **Stateful `ClaudeSDK.Client`** — GenServer keeping a single subprocess alive for multi-turn conversations. State machine: `:disconnected` → `:connected` → `:streaming` → `:connected`. Does not support concurrent queries on the same Client instance.

### Transport Layer

`ClaudeSDK.Transport` behaviour defines the contract (start, send_message, stop). Default implementation is `Transport.Subprocess` which wraps an Erlang Port. Messages flow: **Erlang Port → Subprocess GenServer → caller process** (or Client GenServer).

- `Transport.CommandBuilder` — builds the CLI command with flags from `Options`
- `Transport.CLIDiscovery` — locates the `claude` binary
- `Transport.LineBuffer` — handles partial line buffering from the Port

### Message Flow

Raw JSON from CLI → `MessageParser.parse/1` → typed structs (`AssistantMessage`, `ResultMessage`, `SystemMessage`, `StreamEvent`, etc.). Content blocks within messages are parsed into `TextBlock`, `ThinkingBlock`, `ToolUseBlock`, `ToolResultBlock`.

### Control Requests

The CLI sends `control_request` messages for permission checks and MCP interactions. `ControlRouter` dispatches these to handler functions built from `Options` fields (`can_use_tool`, `mcp_servers`, `hooks`). Responses are sent back via stdin.

### Sessions

`ClaudeSDK.Sessions` reads/writes Claude Code session JSONL files directly from `~/.claude/projects/` — no running subprocess needed. Provides listing, messages, rename, tag, delete, and fork.

### MCP (Model Context Protocol)

In-process MCP servers can be defined with `ClaudeSDK.MCP.Server` and `ClaudeSDK.MCP.Tool`, then passed via `Options.mcp_servers`. Server configs: `StdioServerConfig`, `SSEServerConfig`, `HttpServerConfig`.

## Key Types

- `ClaudeSDK.Types.Options` — all configuration (model, max_turns, permission_mode, system_prompt, session_id, timeouts, MCP servers, etc.)
- Permission modes: `:default`, `:plan`, `:bypass_permissions`, `:dont_ask`
- `can_use_tool` callback: `(tool_name, input) -> :allow | {:deny, reason}`

## Test Support

Test support modules live in `test/support/` (loaded via `elixirc_paths(:test)` in mix.exs). Tests are organized by module with separate `*_coverage_test.exs` files for edge cases.

## Dependencies

Minimal: only `jason` (JSON) at runtime, `ex_doc` (dev only).

## HEEX/HTML Note

When working on HEEX or HTML in this project, use `{elixir}` instead of `<%= elixir %>`.
