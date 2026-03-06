# ClaudeSDK

[![Hex.pm](https://img.shields.io/hexpm/v/claude_sdk.svg)](https://hex.pm/packages/claude_sdk)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/claude_sdk)
[![License](https://img.shields.io/hexpm/l/claude_sdk.svg)](LICENSE)

An Elixir SDK that wraps the [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) as a subprocess, communicating via stdin/stdout using newline-delimited JSON. It provides both a stateless streaming API and a stateful multi-turn client. Designed for feature parity with the official [Python Claude Code SDK](https://github.com/anthropics/claude-code-sdk-python).

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Quick Start](#quick-start)
  - [Single query](#single-query)
  - [With options](#with-options)
  - [Multi-turn client](#multi-turn-client)
  - [File Checkpointing and Rewind](#file-checkpointing-and-rewind)
- [Client Features](#client-features)
- [Message Types](#message-types)
- [Permission Callbacks](#permission-callbacks)
- [Tool Filtering](#tool-filtering)
- [MCP Servers](#mcp-servers)
- [Structured Output](#structured-output)
- [Session Management](#session-management)
- [Thinking Configuration](#thinking-configuration)
- [Effort Levels](#effort-levels)
- [Partial Messages / StreamEvent](#partial-messages--streamevent)
- [Environment Variables](#environment-variables)
- [Agent Definitions](#agent-definitions)
- [Error Handling](#error-handling)
- [Supervision Tree](#supervision-tree)
- [Configuration Reference](#configuration-reference)
- [Architecture](#architecture)
- [Testing](#testing)
- [Documentation](#documentation)
- [License](#license)

## Features

- **Stateless streaming** -- `ClaudeSDK.query/2` spawns a subprocess per call, streams typed messages, and cleans up automatically
- **Stateful multi-turn** -- `ClaudeSDK.Client` keeps a single subprocess alive across multiple queries with session persistence and rewind
- **MCP server support** -- Define in-process MCP tools that Claude can call during a query
- **Permission callbacks** -- Control which tools Claude can use with `can_use_tool`
- **Typed messages** -- All CLI responses are parsed into typed Elixir structs
- **Structured output** -- Get JSON responses matching a schema via `json_schema`
- **Session management** -- Resume, continue, or fork conversation sessions
- **File checkpointing** -- Rewind file changes to any point in the conversation

## Prerequisites

The [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) must be installed and available in your PATH:

```bash
npm install -g @anthropic-ai/claude-code
```

## Installation

Add `claude_sdk` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:claude_sdk, "~> 0.1.0"}
  ]
end
```

## Quick Start

### Single query

```elixir
ClaudeSDK.query("Explain pattern matching in Elixir")
|> Enum.each(&IO.inspect/1)
```

### With options

```elixir
alias ClaudeSDK.Types.Options

ClaudeSDK.query("Explain GenServers", %Options{
  model: "claude-sonnet-4-6",
  system_prompt: "You are a concise Elixir tutor.",
  max_turns: 3,
  permission_mode: :bypass_permissions
})
|> Enum.each(&IO.inspect/1)
```

Options can also be passed as a keyword list:

```elixir
ClaudeSDK.query("Hello", max_turns: 1, permission_mode: :bypass_permissions)
|> Enum.to_list()
```

Note: the default `session_id` is `"default"`, meaning all queries share a session unless you explicitly set a different one.

### Multi-turn client

The `Client` keeps a subprocess alive across multiple queries. Use `with_client/2` for automatic connection and cleanup:

```elixir
alias ClaudeSDK.Client
alias ClaudeSDK.Types.Options

Client.with_client([options: %Options{permission_mode: :bypass_permissions}], fn client ->
  Client.query(client, "What is the capital of France?")
  |> Enum.each(&IO.inspect/1)

  # Second turn -- same session, remembers context
  Client.query(client, "And what about Germany?")
  |> Enum.each(&IO.inspect/1)
end)
```

Or manage the lifecycle manually:

```elixir
{:ok, client} = Client.start_link(options: %Options{})
:ok = Client.connect(client)

Client.query(client, "What is 2+2?") |> Enum.each(&IO.inspect/1)
Client.query(client, "Now multiply that by 3") |> Enum.each(&IO.inspect/1)

Client.close(client)
```

### File Checkpointing and Rewind

With the multi-turn client, you can rewind file changes to a previous point:

```elixir
alias ClaudeSDK.Client
alias ClaudeSDK.Types.{Options, UserMessage}

Client.with_client(
  [options: %Options{enable_file_checkpointing: true, permission_mode: :bypass_permissions}],
  fn client ->
    # Collect the user message UUID from the stream
    messages =
      Client.query(client, "Add a new function to lib/my_app.ex")
      |> Enum.to_list()

    user_msg = Enum.find(messages, &match?(%UserMessage{}, &1))

    # Later, rewind all file changes back to this point
    :ok = Client.rewind_files(client, user_msg.uuid)
  end
)
```

## Client Features

The multi-turn client supports additional mid-session operations:

```elixir
alias ClaudeSDK.Client

# Change model or permission mode mid-session
Client.set_model(client, "claude-sonnet-4-6")
Client.set_permission_mode(client, :bypass_permissions)

# Interrupt a running query
Client.interrupt(client)

# MCP server management
{:ok, status} = Client.get_mcp_status(client)
Client.reconnect_mcp_server(client, "my-server")
Client.toggle_mcp_server(client, "my-server", false)

# Server info
{:ok, info} = Client.get_server_info(client)
```

## Message Types

Both `ClaudeSDK.query/2` and `ClaudeSDK.Client.query/2` return a stream of typed structs:

| Struct | Description |
|--------|-------------|
| `AssistantMessage` | Response containing `TextBlock`, `ThinkingBlock`, and/or `ToolUseBlock` content blocks |
| `ResultMessage` | Final message with cost, timing, session ID, and the text result. Always last in the stream |
| `UserMessage` | Echo of the user message. Contains a `uuid` for use with `rewind_files/2` |
| `SystemMessage` | CLI lifecycle notifications (init, heartbeat) |
| `StreamEvent` | Partial content deltas (only with `include_partial_messages: true`) |
| `ControlRequest` | Permission checks or MCP calls. Handled automatically when callbacks are configured |
| `TaskStartedMessage` | Emitted when a subtask begins |
| `TaskProgressMessage` | Progress updates during subtask execution |
| `TaskNotificationMessage` | Emitted when a subtask completes or fails |

### Extracting text from responses

```elixir
alias ClaudeSDK.Types.{AssistantMessage, ResultMessage, TextBlock, ThinkingBlock, ToolUseBlock}

ClaudeSDK.query("Hello")
|> Enum.each(fn
  %AssistantMessage{message: %{content: blocks}} ->
    Enum.each(blocks, fn
      %TextBlock{text: text} -> IO.puts(text)
      %ThinkingBlock{thinking: thought} -> IO.puts("[thinking] #{thought}")
      %ToolUseBlock{name: name, input: input} -> IO.puts("[tool] #{name}: #{inspect(input)}")
      _ -> :ok
    end)

  %ResultMessage{result: result, total_cost_usd: cost} ->
    IO.puts("Done: #{result} (cost: $#{cost})")

  _ -> :ok
end)
```

## Permission Callbacks

Control which tools Claude can use with the `can_use_tool` option:

```elixir
ClaudeSDK.query("Read and summarize my files", %ClaudeSDK.Types.Options{
  can_use_tool: fn tool_name, _input ->
    if tool_name in ["Read", "Glob", "Grep"],
      do: :allow,
      else: {:deny, "Only read-only tools are permitted"}
  end
})
|> Enum.each(&IO.inspect/1)
```

The callback also supports an arity-3 form with a `ToolPermissionContext` for additional metadata:

```elixir
can_use_tool: fn tool_name, _input, context ->
  Logger.info("Permission check #{context.request_id} for #{tool_name}")
  :allow
end
```

Return values: `:allow`, `{:allow, updated_input_map}`, `:deny`, or `{:deny, reason}`.

## Tool Filtering

Control which tools are available without writing a callback:

```elixir
alias ClaudeSDK.Types.Options

# Only allow specific tools
ClaudeSDK.query("Help me code", %Options{
  allowed_tools: ["Read", "Glob", "Grep"],
  disallowed_tools: ["Bash"]
})
|> Enum.each(&IO.inspect/1)
```

## MCP Servers

Define in-process MCP tools that Claude can call during a query:

```elixir
server = ClaudeSDK.create_mcp_server("my-tools", "1.0", [
  %ClaudeSDK.MCP.Tool{
    name: "lookup_user",
    description: "Look up a user by ID",
    input_schema: %{
      "type" => "object",
      "properties" => %{"user_id" => %{"type" => "string"}},
      "required" => ["user_id"]
    },
    handler: fn %{"user_id" => id} ->
      {:ok, %{name: "Alice", id: id, email: "alice@example.com"}}
    end
  }
])

ClaudeSDK.query("Find user 123", %ClaudeSDK.Types.Options{mcp_servers: [server]})
|> Enum.each(&IO.inspect/1)
```

Tool handlers return `{:ok, result}` or `{:error, reason}`. Results can be strings, maps (JSON-encoded automatically), or lists of MCP content parts.

## Structured Output

Get responses as structured JSON matching a schema:

```elixir
alias ClaudeSDK.Types.{Options, ResultMessage}

ClaudeSDK.query("List 3 programming languages and their creators", %Options{
  json_schema: %{
    "type" => "object",
    "properties" => %{
      "languages" => %{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "properties" => %{
            "name" => %{"type" => "string"},
            "creator" => %{"type" => "string"}
          }
        }
      }
    }
  },
  permission_mode: :bypass_permissions
})
|> Enum.find(&match?(%ResultMessage{}, &1))
|> then(fn %ResultMessage{result: json_string} -> Jason.decode!(json_string) end)
```

## Session Management

```elixir
alias ClaudeSDK.Types.Options

# Continue the most recent session
ClaudeSDK.query("Follow up on that", %Options{continue: true})

# Resume a specific session by ID
ClaudeSDK.query("Follow up", %Options{resume: "session_abc123"})

# Fork a session (branch off without modifying the original)
ClaudeSDK.query("Try a different approach", %Options{fork_session: true})

# Use a custom session ID (default is "default")
ClaudeSDK.query("Hello", %Options{session_id: "my-project-session"})
```

## Thinking Configuration

Control extended thinking with the `ThinkingConfig` helpers:

```elixir
alias ClaudeSDK.Types.{Options, ThinkingConfig}

# Adaptive -- model decides when to think
ClaudeSDK.query("Solve this", %Options{thinking: ThinkingConfig.adaptive(10_000)})

# Always-on thinking with a token budget
ClaudeSDK.query("Complex problem", %Options{thinking: ThinkingConfig.enabled(8_000)})

# Disable thinking
ClaudeSDK.query("Quick answer", %Options{thinking: ThinkingConfig.disabled()})
```

## Effort Levels

Control how much effort the model puts into a response:

```elixir
alias ClaudeSDK.Types.Options

ClaudeSDK.query("Quick answer", %Options{effort: "low"})
ClaudeSDK.query("Deep analysis", %Options{effort: "max"})
```

Valid values: `"low"`, `"medium"`, `"high"`, `"max"`.

## Partial Messages / StreamEvent

Setting `include_partial_messages: true` enables `StreamEvent` messages in the stream. These contain partial content deltas as the model generates its response, useful for real-time UI updates:

```elixir
alias ClaudeSDK.Types.{Options, StreamEvent}

ClaudeSDK.query("Tell me a story", %Options{include_partial_messages: true})
|> Enum.each(fn
  %StreamEvent{} = event -> IO.write(inspect(event))
  _other -> :ok
end)
```

## Environment Variables

Pass extra environment variables to the CLI subprocess:

```elixir
alias ClaudeSDK.Types.Options

ClaudeSDK.query("Hello", %Options{
  env: %{"ANTHROPIC_API_KEY" => "sk-..."}
})
|> Enum.each(&IO.inspect/1)
```

## Agent Definitions

Define custom subagents that Claude can spawn during tool use:

```elixir
alias ClaudeSDK.Types.{AgentDefinition, Options}

agents = [
  %AgentDefinition{
    name: "researcher",
    description: "Searches codebase for relevant information",
    prompt: "You are a research assistant. Find relevant code and documentation.",
    tools: ["Read", "Glob", "Grep"]
  }
]

ClaudeSDK.query("Research how auth works in this codebase", %Options{agents: agents})
|> Enum.each(&IO.inspect/1)
```

## Error Handling

The SDK defines typed exceptions for different failure modes:

| Exception | When |
|-----------|------|
| `CLINotFoundError` | Claude CLI not installed or not on PATH |
| `TimeoutError` | Initialization or message timeout exceeded |
| `TransportError` | Subprocess communication failure |
| `ProtocolError` | Malformed message from CLI |
| `QueryError` | Client query failed (wrong state, not connected, etc.) |

```elixir
try do
  ClaudeSDK.query("Hello") |> Enum.to_list()
rescue
  e in ClaudeSDK.CLINotFoundError ->
    IO.puts(e.message)

  e in ClaudeSDK.TimeoutError ->
    IO.puts("Timed out after #{e.timeout_ms}ms")

  e in ClaudeSDK.TransportError ->
    IO.puts("Transport error: #{inspect(e.reason)}")
end
```

## Supervision Tree

`ClaudeSDK.Client` is a GenServer and can be placed directly in a supervision tree:

```elixir
children = [
  {ClaudeSDK.Client, options: %ClaudeSDK.Types.Options{permission_mode: :bypass_permissions}}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

After starting under a supervisor, call `Client.connect/1` to initiate the subprocess, then use `Client.query/2` as normal.

## Configuration Reference

Key options are listed below. See `ClaudeSDK.Types.Options` for the complete list of configuration options.

| Option | Description |
|--------|-------------|
| `model` | Model identifier (e.g. `"claude-sonnet-4-6"`) |
| `system_prompt` | Override the default system prompt |
| `append_system_prompt` | Append to the default system prompt |
| `max_turns` | Maximum agentic turns |
| `max_budget_usd` | Spend limit in USD |
| `permission_mode` | `:default`, `:accept_edits`, `:plan`, or `:bypass_permissions` |
| `can_use_tool` | Permission callback function |
| `allowed_tools` | Allowlist of tool names |
| `disallowed_tools` | Denylist of tool names |
| `effort` | Effort level: `"low"`, `"medium"`, `"high"`, `"max"` |
| `mcp_servers` | In-process MCP server configs |
| `json_schema` | JSON Schema for structured output |
| `thinking` | Extended thinking configuration |
| `session_id` | Session identifier (default: `"default"`) |
| `continue` | Continue the most recent session |
| `resume` | Resume a specific session by ID |
| `env` | Extra environment variables for the subprocess |
| `cwd` | Working directory for the subprocess |
| `sandbox` | Sandbox configuration |
| `agents` | Custom subagent definitions |
| `include_partial_messages` | Enable `StreamEvent` partial deltas |
| `enable_file_checkpointing` | Enable file rewind support |
| `init_timeout_ms` | Initialization timeout (default: 30s) |
| `message_timeout_ms` | Message receive timeout (default: 120s) |

## Architecture

The SDK communicates with the Claude Code CLI via an Erlang Port, exchanging newline-delimited JSON (NDJSON) over stdin/stdout:

```
Your App --> ClaudeSDK --> Subprocess (Erlang Port) --> Claude CLI
                               |
                          LineBuffer (NDJSON parsing)
                               |
                          MessageParser (typed structs)
                               |
                          ControlRouter (auto-handles permission & MCP requests)
                               |
                          Stream of typed messages back to your app
```

- **`ClaudeSDK.query/2`** spawns a fresh subprocess per call using `Stream.resource/3`
- **`ClaudeSDK.Client`** is a GenServer that keeps one subprocess alive across calls
- **Control requests** (tool permissions, MCP calls) are intercepted and handled automatically when callbacks are configured; unhandled requests are forwarded to the stream

## Testing

Tests use mock CLI shell scripts in `test/support/` (e.g. `mock_cli_multiturn.sh`, `mock_cli_rewind.sh`) that emit predefined NDJSON responses. This makes the test suite fast and deterministic without requiring the real Claude CLI.

```bash
mix test                         # Run all tests (excludes :live tests)
mix test --include live          # Include integration tests (requires real CLI)
```

Live tests (tagged `@tag :live`) hit the real Claude CLI and are excluded by default. To add your own mock-based tests, create a shell script that writes NDJSON to stdout and point the `:cli_path` option at it.

## Documentation

Full API documentation is available on [HexDocs](https://hexdocs.pm/claude_sdk).

## License

MIT -- see [LICENSE](LICENSE) for details.
