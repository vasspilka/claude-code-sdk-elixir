# Getting Started

This guide walks you through installing the SDK, running your first query, and understanding what comes back.

## Prerequisites

You need two things:

1. **Elixir ~> 1.17** installed
2. **Claude Code CLI** installed and on your PATH:

```bash
npm install -g @anthropic-ai/claude-code
```

Verify it works:

```bash
claude --version
```

## Installation

Add `claude_sdk` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:claude_sdk, "~> 0.1.0"}
  ]
end
```

Then fetch:

```bash
mix deps.get
```

## Your First Query

The simplest way to use the SDK is `ClaudeSDK.query/2`. It spawns a CLI subprocess, sends your prompt, streams back the response, and cleans up.

> For how this works under the hood, see [Protocol & Architecture](protocol-and-architecture.md).

```elixir
ClaudeSDK.query("What is pattern matching in Elixir?")
|> Enum.each(&IO.inspect/1)
```

This returns a stream of typed Elixir structs. You'll see output like:

```elixir
%ClaudeSDK.Types.AssistantMessage{
  type: :assistant,
  message: %{
    content: [%ClaudeSDK.Types.TextBlock{type: :text, text: "Pattern matching is..."}],
    model: "claude-sonnet-4-6"
  }
}

%ClaudeSDK.Types.ResultMessage{
  type: :result,
  subtype: "success",
  result: "Pattern matching is...",
  session_id: "abc-123-...",
  num_turns: 1,
  total_cost_usd: 0.01
}
```

## Understanding the Output

Every query stream contains a sequence of messages, always ending with a `ResultMessage`:

| Message | What it is |
|---|---|
| `AssistantMessage` | Claude's response. Contains content blocks: `TextBlock` (text), `ThinkingBlock` (reasoning), `ToolUseBlock` (tool calls), `ToolResultBlock` (tool output) |
| `ResultMessage` | Always last. Contains `session_id`, cost, duration, and the final text result |
| `UserMessage` | Echo of your prompt with a `uuid` (useful for rewind) |

### Extracting just the text

```elixir
alias ClaudeSDK.Types.{AssistantMessage, TextBlock}

ClaudeSDK.query("Hello!")
|> Enum.flat_map(fn
  %AssistantMessage{message: %{content: blocks}} ->
    for %TextBlock{text: text} <- blocks, do: text
  _ ->
    []
end)
|> Enum.join()
|> IO.puts()
```

### Getting the final result

```elixir
alias ClaudeSDK.Types.ResultMessage

result =
  ClaudeSDK.query("What is 2+2?")
  |> Enum.find(&match?(%ResultMessage{}, &1))

IO.puts(result.result)          # "4"
IO.puts(result.session_id)      # "session_abc123"
IO.puts(result.total_cost_usd)  # 0.003
```

## Adding Options

Pass an `%Options{}` struct to control model, permissions, limits, and more:

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
ClaudeSDK.query("Hello", model: "claude-sonnet-4-6", max_turns: 1)
|> Enum.to_list()
```

## Permission Modes

By default, the CLI will ask for permission before using tools (reading files, running commands). In the SDK, you control this with `permission_mode`:

| Mode | Behavior |
|---|---|
| `:default` | CLI asks for each tool use (via control requests) |
| `:accept_edits` | Auto-approve file edits, ask for others |
| `:plan` | Read-only -- no file modifications |
| `:bypass_permissions` | Auto-approve everything (use for automation) |

For programmatic use, you'll typically want either `:bypass_permissions` or a `can_use_tool` callback:

```elixir
ClaudeSDK.query("Read my files", %Options{
  can_use_tool: fn tool_name, _input ->
    if tool_name in ["Read", "Glob", "Grep"],
      do: :allow,
      else: {:deny, "Only read-only tools permitted"}
  end
})
|> Enum.each(&IO.inspect/1)
```

## Next Steps

- **[Multi-turn Conversations](multi-turn-conversations.md)** -- Keep a conversation going across multiple queries with `ClaudeSDK.Client`
- **[MCP Servers](mcp-servers.md)** -- Define custom tools that Claude can call during queries
- **[Protocol & Architecture](protocol-and-architecture.md)** -- Understand the NDJSON protocol and subprocess communication
- **`ClaudeSDK.Types.Options`** -- All available configuration options
