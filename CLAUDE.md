# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Elixir SDK for the Claude Code CLI. Wraps the CLI as a subprocess and communicates via stdin/stdout using newline-delimited JSON (NDJSON). Provides a streaming interface (`Stream.resource/3`) that yields typed message structs.

**Hex package name:** `claude_agent_sdk` | **App name:** `:claude_sdk` | **Elixir:** ~> 1.17

## Commands

```bash
mix compile          # Build
mix test             # Run all tests (69 tests)
mix test path/to/test.exs                    # Run single test file
mix test path/to/test.exs --only tag:value   # Run tagged tests
mix format --check-formatted                 # Check formatting
mix format                                   # Auto-format
```

## Architecture

Entry point: `ClaudeSDK.query(prompt, opts)` returns a lazy `Stream` of typed message structs.

### Message flow

```
ClaudeSDK.query/2
  → CLIDiscovery.find_cli!/1        (locates claude binary)
  → CommandBuilder.build_args/env   (Options struct → CLI flags + env vars)
  → Subprocess.start_link/1         (GenServer wrapping Erlang Port)
  → sends initialize control_request via stdin, waits for control_response
  → sends user message via stdin
  → Stream yields parsed messages until process exits
```

### Key modules

| Module | Role |
|--------|------|
| `ClaudeSDK` | Public API, stream orchestration via `Stream.resource/3` |
| `Transport.Subprocess` | GenServer managing CLI Port, receives async output |
| `Transport.LineBuffer` | Accumulates partial NDJSON chunks into complete lines |
| `Transport.CommandBuilder` | Maps `Options` struct to CLI args and env vars |
| `Transport.CLIDiscovery` | Finds/validates the `claude` binary on PATH |
| `MessageParser` | Dispatches on `"type"` field → typed structs, skips unknowns for forward compat |
| `Types.Options` | Config struct (model, tools, permissions, limits, session, MCP, etc.) |
| `Types.Messages` | AssistantMessage, UserMessage, SystemMessage, ResultMessage, StreamEvent, ControlRequest/Response |
| `Types.ContentBlocks` | TextBlock, ThinkingBlock, ToolUseBlock, ToolResultBlock |
| `Errors` | CLINotFoundError, TransportError, ProtocolError, TimeoutError |

### Testing

Tests use a mock CLI script (`test/support/mock_cli.sh`) that simulates the NDJSON protocol for integration tests. Fixtures live in `test/support/fixtures.ex`. Only dependency is `jason` for JSON.
