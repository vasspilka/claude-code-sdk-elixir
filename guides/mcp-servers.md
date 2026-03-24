# MCP Servers

This guide covers how to define in-process MCP (Model Context Protocol) tools that Claude can call during queries. This lets you give Claude access to your application's data and functionality without exposing it as a separate service.

## How It Works

When you define an MCP server with tools, the SDK:

1. Tells the CLI about your tools via `--mcp-config` at startup (tool names, descriptions, schemas)
2. Claude sees these tools and can decide to call them
3. The CLI sends a `control_request` with subtype `"mcp_message"` to the SDK
4. The SDK's `ClaudeSDK.ControlRouter` dispatches to your handler function
5. Your handler returns a result, which is sent back to the CLI
6. Claude sees the result and continues its response

All of this happens in-process -- no HTTP servers, no stdio pipes to manage. Your tools are just Elixir functions.

## Defining a Tool

A tool needs four things: a name, description, input schema, and handler function.

```elixir
%ClaudeSDK.MCP.Tool{
  name: "lookup_user",
  description: "Look up a user by their ID",
  input_schema: %{
    "type" => "object",
    "properties" => %{
      "user_id" => %{"type" => "string", "description" => "The user's ID"}
    },
    "required" => ["user_id"]
  },
  handler: fn %{"user_id" => id} ->
    case MyApp.Users.get(id) do
      {:ok, user} -> {:ok, %{name: user.name, email: user.email}}
      {:error, :not_found} -> {:error, "User #{id} not found"}
    end
  end
}
```

### Handler return values

| Return | What happens |
|---|---|
| `{:ok, string}` | Sent as text content |
| `{:ok, map}` | JSON-encoded and sent as text content |
| `{:ok, list}` | Sent as-is (must be MCP content parts) |
| `{:error, string}` | Sent as an error result to Claude |

### Input schema

The `input_schema` follows [JSON Schema](https://json-schema.org/) format. Claude uses this to understand what arguments to pass. Be specific with descriptions -- they help Claude use the tool correctly.

```elixir
input_schema: %{
  "type" => "object",
  "properties" => %{
    "query" => %{
      "type" => "string",
      "description" => "SQL query to execute. Must be a SELECT statement."
    },
    "limit" => %{
      "type" => "integer",
      "description" => "Maximum rows to return",
      "default" => 100
    }
  },
  "required" => ["query"]
}
```

## Creating a Server

Bundle tools into a server with `ClaudeSDK.create_mcp_server/3`:

```elixir
server = ClaudeSDK.create_mcp_server("my-app", "1.0", [
  %ClaudeSDK.MCP.Tool{
    name: "lookup_user",
    description: "Look up a user by ID",
    input_schema: %{
      "type" => "object",
      "properties" => %{"user_id" => %{"type" => "string"}},
      "required" => ["user_id"]
    },
    handler: fn %{"user_id" => id} ->
      {:ok, %{name: "Alice", id: id}}
    end
  },
  %ClaudeSDK.MCP.Tool{
    name: "list_orders",
    description: "List recent orders for a user",
    input_schema: %{
      "type" => "object",
      "properties" => %{
        "user_id" => %{"type" => "string"},
        "limit" => %{"type" => "integer"}
      },
      "required" => ["user_id"]
    },
    handler: fn args ->
      user_id = args["user_id"]
      limit = args["limit"] || 10
      orders = MyApp.Orders.list(user_id, limit: limit)
      {:ok, orders}
    end
  }
])
```

The first argument is the server name (how it appears to the CLI), the second is a version string, and the third is the list of tools.

## Using with query/2

Pass the server in `Options.mcp_servers`:

```elixir
alias ClaudeSDK.Types.Options

ClaudeSDK.query("Find user 123 and show their recent orders", %Options{
  mcp_servers: [server],
  permission_mode: :bypass_permissions
})
|> Enum.each(&IO.inspect/1)
```

Claude will see the tools, decide to call `lookup_user` and `list_orders`, and incorporate the results into its response.

## Using with Client

MCP servers work the same way with the multi-turn Client:

```elixir
alias ClaudeSDK.Client
alias ClaudeSDK.Types.Options

Client.with_client(
  [options: %Options{mcp_servers: [server], permission_mode: :bypass_permissions}],
  fn client ->
    Client.query(client, "Look up user 123") |> Enum.each(&IO.inspect/1)

    # Tools remain available across turns
    Client.query(client, "Now show their orders") |> Enum.each(&IO.inspect/1)
  end
)
```

## Multiple Servers

You can register multiple servers. Each server's tools are namespaced by server name:

```elixir
users_server = ClaudeSDK.create_mcp_server("users", "1.0", [
  %ClaudeSDK.MCP.Tool{name: "get_user", ...}
])

orders_server = ClaudeSDK.create_mcp_server("orders", "1.0", [
  %ClaudeSDK.MCP.Tool{name: "list_orders", ...},
  %ClaudeSDK.MCP.Tool{name: "get_order", ...}
])

ClaudeSDK.query("...", %Options{mcp_servers: [users_server, orders_server]})
```

## Error Handling in Handlers

If your handler raises an exception, the `ClaudeSDK.ControlRouter` catches it and returns a deny response. Claude will see the error but the SDK won't crash:

```elixir
handler: fn args ->
  # If this raises, Claude gets an error message
  result = some_operation_that_might_fail(args)
  {:ok, result}
end
```

For expected errors, return `{:error, reason}` explicitly:

```elixir
handler: fn %{"user_id" => id} ->
  case MyApp.Users.get(id) do
    {:ok, user} -> {:ok, format_user(user)}
    {:error, :not_found} -> {:error, "User #{id} not found"}
    {:error, :forbidden} -> {:error, "Access denied for user #{id}"}
  end
end
```

Claude can see error messages and adjust its approach -- for example, trying a different ID or asking the user for clarification.

## Result Size Limits

MCP tool results are capped at 1MB. Results exceeding this limit are truncated with a warning. If your tool returns large data, consider:

- Paginating results
- Returning summaries instead of full records
- Filtering to relevant fields

## External MCP Servers

In addition to in-process servers, you can point the CLI at external MCP servers using `mcp_config`:

```elixir
# Path to an MCP config file
ClaudeSDK.query("...", %Options{
  mcp_config: "/path/to/mcp-config.json"
})

# Or inline as a map
ClaudeSDK.query("...", %Options{
  mcp_config: %{
    "mcpServers" => %{
      "my-server" => %{
        "command" => "node",
        "args" => ["/path/to/server.js"]
      }
    }
  }
})
```

External servers run as separate processes managed by the CLI. In-process servers (via `mcp_servers`) are generally simpler since they're just Elixir functions in your application.

## Debugging

To see what's happening with MCP tool calls, watch for `ToolUseBlock` and `ToolResultBlock` in the stream:

```elixir
alias ClaudeSDK.Types.{AssistantMessage, ToolUseBlock, ToolResultBlock}

ClaudeSDK.query("Use my tools", %Options{mcp_servers: [server]})
|> Enum.each(fn
  %AssistantMessage{message: %{content: blocks}} ->
    Enum.each(blocks, fn
      %ToolUseBlock{name: name, input: input} ->
        IO.puts("[MCP call] #{name}: #{inspect(input)}")

      %ToolResultBlock{tool_use_id: id, content: content, is_error: err} ->
        status = if err, do: "ERROR", else: "OK"
        IO.puts("[MCP result #{status}] #{id}: #{String.slice(to_string(content), 0, 200)}")

      _ -> :ok
    end)

  _ -> :ok
end)
```

### MCP status (Client only)

Check whether MCP servers are connected:

```elixir
{:ok, status} = Client.get_mcp_status(client)
IO.inspect(status)
```

Reconnect a failed server:

```elixir
Client.reconnect_mcp_server(client, "my-app")
```

Toggle a server on/off:

```elixir
Client.toggle_mcp_server(client, "my-app", false)  # disable
Client.toggle_mcp_server(client, "my-app", true)   # re-enable
```

## Protocol Details

Under the hood, MCP tool calls flow through the NDJSON protocol as control requests. See the [Protocol & Architecture](protocol-and-architecture.md) guide for the full message format. In short:

1. CLI sends `control_request` with `subtype: "mcp_message"` containing a JSONRPC payload
2. SDK dispatches to the tool handler via the tool index (keyed by `{server_name, tool_name}`)
3. SDK sends `control_response` with the JSONRPC result back to stdin
4. CLI continues with the tool result in context
