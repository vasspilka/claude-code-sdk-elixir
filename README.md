# ClaudeSDK

[![Hex.pm](https://img.shields.io/hexpm/v/claude_sdk.svg)](https://hex.pm/packages/claude_sdk)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/claude_sdk)
[![License](https://img.shields.io/hexpm/l/claude_sdk.svg)](LICENSE)

An Elixir SDK that wraps the [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) as a subprocess, communicating via stdin/stdout using newline-delimited JSON. It provides both a stateless streaming API and a stateful multi-turn client. Designed for feature parity with the official [Python Claude Code SDK](https://github.com/anthropics/claude-code-sdk-python).

## Features

- **Stateless streaming** -- `ClaudeSDK.query/2` spawns a subprocess per call, streams typed messages, and cleans up automatically
- **Stateful multi-turn** -- `ClaudeSDK.Client` keeps a single subprocess alive across multiple queries with session persistence and rewind
- **MCP server support** -- Define in-process MCP tools that Claude can call during a query
- **Permission callbacks** -- Control which tools Claude can use with `can_use_tool`
- **Typed messages** -- All CLI responses are parsed into typed Elixir structs
- **Structured output** -- Get JSON responses matching a schema via `json_schema`
- **Session management** -- Resume, continue, fork, list, rename, and tag sessions
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

See the [Multi-turn Conversations](multi-turn-conversations.md) guide for session persistence, resuming, rewind, and more.

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
| `RateLimitEvent` | Rate limit information changes from the API |
| `TaskStartedMessage` | Emitted when a subtask begins |
| `TaskProgressMessage` | Progress updates during subtask execution |
| `TaskNotificationMessage` | Emitted when a subtask completes or fails |

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

See the [MCP Servers](mcp-servers.md) guide for multiple tools, error handling, debugging, and external servers.

## Tool Configuration

By default the CLI uses its built-in tool set. You can customize which tools are available:

```elixir
alias ClaudeSDK.Types.Options

# Explicitly select the tool set (`:default` or a list of tool name strings)
ClaudeSDK.query("Help me code", %Options{tools: ["Read", "Glob", "Grep", "Bash"]})

# Or keep defaults but filter with allow/deny lists
ClaudeSDK.query("Help me code", %Options{
  allowed_tools: ["Read", "Glob", "Grep"],
  disallowed_tools: ["Bash"]
})
|> Enum.each(&IO.inspect/1)
```

Use `allowed_tools` to restrict to a specific set, `disallowed_tools` to block specific tools, or `tools` to replace the default tool set entirely.

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

## Output Format

`output_format` is a separate option from `json_schema`. While `json_schema` constrains the model's text response, `output_format` controls the CLI's output structure. When set, the parsed result is available in `ResultMessage.structured_output`:

```elixir
alias ClaudeSDK.Types.{Options, ResultMessage}

ClaudeSDK.query("Summarize this project", %Options{
  output_format: %{
    "type" => "object",
    "properties" => %{
      "summary" => %{"type" => "string"},
      "key_files" => %{"type" => "array", "items" => %{"type" => "string"}}
    }
  },
  permission_mode: :bypass_permissions
})
|> Enum.find(&match?(%ResultMessage{}, &1))
|> then(fn %ResultMessage{structured_output: output} -> output end)
```

## Session Management

```elixir
alias ClaudeSDK.Types.Options

# Resume a specific session by ID
ClaudeSDK.query("Follow up", %Options{resume: "session_abc123"})

# Continue the most recent session
ClaudeSDK.query("Follow up on that", %Options{continue: true})

# Fork a session (branch off without modifying the original)
ClaudeSDK.query("Try a different approach", %Options{fork_session: true})

# List and inspect sessions
sessions = ClaudeSDK.list_sessions()
messages = ClaudeSDK.get_session_messages("abc123")
ClaudeSDK.rename_session("abc123", "Auth refactor discussion")
```

See the [Multi-turn Conversations](multi-turn-conversations.md) guide for the full session lifecycle.

## Thinking Configuration

Control extended thinking with the `ClaudeSDK.Types.ThinkingConfig` helpers:

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
  %StreamEvent{event: %{"type" => "content_block_delta", "delta" => %{"text" => text}}} ->
    IO.write(text)

  %StreamEvent{event: %{"type" => "content_block_start"}} ->
    :ok  # new block started

  %StreamEvent{event: %{"type" => "content_block_stop"}} ->
    IO.puts("")  # block finished

  _other ->
    :ok
end)
```

The `event` map follows the Claude API streaming format. Common event types include `"content_block_start"`, `"content_block_delta"`, and `"content_block_stop"`.

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

## Sandbox

Run the CLI in a sandboxed environment to restrict filesystem and network access:

```elixir
alias ClaudeSDK.Types.{Options, SandboxSettings}

ClaudeSDK.query("Analyze this code", %Options{
  sandbox: %SandboxSettings{
    enabled: true,
    auto_allow_bash_if_sandboxed: true,
    network: "deny",
    excluded_commands: ["git"]
  },
  permission_mode: :bypass_permissions
})
|> Enum.each(&IO.inspect/1)
```

You can also pass a raw map: `sandbox: %{enabled: true, network: "deny"}`.

## Hooks

Hooks are shell commands that run in response to CLI lifecycle events (e.g., before/after tool calls, on notifications). They are passed via the `hooks` option and sent during initialization:

```elixir
alias ClaudeSDK.Types.Options

ClaudeSDK.query("Make changes to the code", %Options{
  hooks: %{
    "PreToolUse" => [
      %{
        "matcher" => "Bash",
        "hooks" => [%{"type" => "command", "command" => "echo 'About to run bash'"}]
      }
    ],
    "PostToolUse" => [
      %{
        "matcher" => "Write",
        "hooks" => [%{"type" => "command", "command" => "mix format"}]
      }
    ]
  }
})
|> Enum.each(&IO.inspect/1)
```

See the [Claude Code hooks documentation](https://docs.anthropic.com/en/docs/claude-code/hooks) for the full hook specification.

## Error Handling

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

## Configuration Reference

All options available in `ClaudeSDK.Types.Options`:

| Option | Description |
|--------|-------------|
| **Prompt** | |
| `system_prompt` | Override the default system prompt |
| `append_system_prompt` | Append to the default system prompt |
| **Model** | |
| `model` | Model identifier (e.g. `"claude-sonnet-4-6"`) |
| `fallback_model` | Fallback model if the primary is unavailable |
| **Tools** | |
| `tools` | Tool set: `:default` or a list of tool name strings |
| `allowed_tools` | Allowlist of tool names |
| `disallowed_tools` | Denylist of tool names |
| `can_use_tool` | Permission callback function (arity-2 or arity-3) |
| `permission_prompt_tool_name` | Custom name for the permission prompt tool (default: `"stdio"`) |
| **Limits** | |
| `max_turns` | Maximum agentic turns |
| `max_budget_usd` | Spend limit in USD |
| `max_thinking_tokens` | Maximum tokens for extended thinking |
| **Permissions** | |
| `permission_mode` | `:default`, `:accept_edits`, `:plan`, or `:bypass_permissions` |
| **Session** | |
| `session_id` | Session identifier (default: `"default"`) |
| `continue` | Continue the most recent session |
| `resume` | Resume a specific session by ID |
| `fork_session` | Fork the current session (branch off) |
| **Streaming** | |
| `include_partial_messages` | Enable `StreamEvent` partial deltas |
| **Thinking** | |
| `thinking` | Extended thinking config (`ThinkingConfig` or map) |
| `effort` | Effort level: `"low"`, `"medium"`, `"high"`, `"max"` |
| **Structured Output** | |
| `json_schema` | JSON Schema for constraining the model's text response |
| `output_format` | JSON Schema for CLI-level structured output (populates `structured_output`) |
| **MCP** | |
| `mcp_servers` | In-process MCP server configs (via `create_mcp_server/3`) |
| `mcp_config` | Path to external MCP config file, or a config map |
| **Sandbox** | |
| `sandbox` | `%SandboxSettings{}` or raw map for sandbox configuration |
| **File Checkpointing** | |
| `enable_file_checkpointing` | Enable file rewind support (Client only) |
| **Agents** | |
| `agents` | Custom subagent definitions (`[%AgentDefinition{}]` or raw map) |
| **Working Directory** | |
| `cwd` | Working directory for the subprocess |
| `add_dirs` | Additional directories to make available to the CLI |
| **Environment** | |
| `env` | Extra environment variables for the subprocess |
| **Hooks & Plugins** | |
| `hooks` | Lifecycle hook commands (map keyed by event name) |
| `plugins` | List of plugin configuration maps |
| `plugin_dirs` | List of plugin directory paths |
| **Settings** | |
| `settings` | Map of CLI settings to override |
| `setting_sources` | List of setting source paths |
| **Beta & Identity** | |
| `betas` | List of beta feature flag strings |
| `user` | User identifier string |
| **Timeouts** | |
| `init_timeout_ms` | Initialization timeout (default: 30s) |
| `message_timeout_ms` | Message receive timeout (default: 120s) |
| `control_timeout_ms` | Control request/response timeout (default: 30s) |
| **Advanced** | |
| `cli_path` | Override the auto-discovered CLI binary path |
| `extra_args` | Escape hatch: additional raw CLI argument strings |

## Guides

- **[Getting Started](getting-started.md)** -- Installation, first query, understanding the output
- **[Multi-turn Conversations](multi-turn-conversations.md)** -- Client lifecycle, sessions, rewind, concurrency
- **[MCP Servers](mcp-servers.md)** -- In-process tools, error handling, debugging, external servers
- **[Protocol & Architecture](protocol-and-architecture.md)** -- NDJSON protocol, Erlang Ports, message flow, internals

## Testing

```bash
mix test                         # Run all tests (excludes :live tests)
mix test --include live          # Include integration tests (requires real CLI)
```

Tests use mock CLI shell scripts in `test/support/` that emit predefined NDJSON responses. See the [Protocol & Architecture](protocol-and-architecture.md) guide to understand the message format.

## Troubleshooting

### CLI not found

If you get `CLINotFoundError`, the Claude CLI is not installed or not on your PATH:

```bash
npm install -g @anthropic-ai/claude-code
```

You can also point to a specific binary with `%Options{cli_path: "/path/to/claude"}`.

### Timeouts

The SDK enforces two timeouts:

- **Initialization** (default 30s) -- the CLI must complete its handshake within this window. Increase with `init_timeout_ms`.
- **Message inactivity** (default 120s) -- if no message arrives within this window during streaming, the query ends with a timeout result. Increase with `message_timeout_ms` for long-running operations.

```elixir
ClaudeSDK.query("Complex task", %Options{
  init_timeout_ms: 60_000,
  message_timeout_ms: 300_000
})
```

### No CLI logs / stderr

Erlang ports only capture stdout. CLI stderr output (logs, warnings) is not captured by the SDK. To capture CLI logs, redirect them to a file:

```elixir
ClaudeSDK.query("Hello", %Options{
  extra_args: ["--log-file", "/tmp/claude.log"]
})
```

### Concurrent queries on Client

`ClaudeSDK.Client` does not support concurrent queries -- calling `query/2` while another is streaming will return `{:error, {:invalid_state, :streaming}}`. Use separate Client instances for parallel workloads.

## Documentation

Full API documentation is available on [HexDocs](https://hexdocs.pm/claude_sdk).

## License

MIT -- see [LICENSE](LICENSE) for details.
