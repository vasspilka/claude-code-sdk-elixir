# ClaudeSDK

An Elixir SDK that wraps the [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) as a subprocess, communicating via stdin/stdout using newline-delimited JSON. It provides both a stateless streaming API and a stateful multi-turn client.

## Features

- **Stateless streaming** — `ClaudeSDK.query/2` spawns a subprocess per call, streams messages, and cleans up automatically
- **Stateful multi-turn** — `ClaudeSDK.Client` keeps a single subprocess alive across multiple queries with session persistence and rewind
- **MCP server support** — Define in-process MCP tools with `ClaudeSDK.MCP.Server`
- **Control request routing** — Automatic handling of tool approval and MCP messages via `ClaudeSDK.ControlRouter`
- **Typed messages** — All Claude responses are parsed into typed structs

## Prerequisites

The [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) must be installed and available in your PATH.

## Installation

Add `claude_sdk` to your list of dependencies in `mix.exs`:

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
ClaudeSDK.query("Explain pattern matching in Elixir", %ClaudeSDK.Types.Options{})
|> Enum.each(fn message ->
  IO.inspect(message)
end)
```

### Multi-turn client

```elixir
{:ok, client} = ClaudeSDK.Client.start_link(options: %ClaudeSDK.Types.Options{})

ClaudeSDK.Client.query(client, "What is the capital of France?")
# Receive messages via {:client_message, message} in your process mailbox

ClaudeSDK.Client.query(client, "And what about Germany?")
```

## Documentation

Full documentation is available on [HexDocs](https://hexdocs.pm/claude_sdk).

## License

MIT — see [LICENSE](LICENSE) for details.
