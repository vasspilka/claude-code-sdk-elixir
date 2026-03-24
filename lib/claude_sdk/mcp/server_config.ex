defmodule ClaudeSDK.MCP.StdioServerConfig do
  @moduledoc """
  Configuration for an external MCP server communicating over stdio.

  The CLI will spawn the command and communicate via stdin/stdout.

  ## Fields

  - `command` — The command to execute (e.g. `"npx"`, `"python"`).
  - `args` — List of arguments to pass to the command.
  - `env` — Environment variables for the subprocess.

  ## Example

      %StdioServerConfig{
        command: "npx",
        args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
        env: %{"NODE_ENV" => "production"}
      }
  """

  @type t :: %__MODULE__{
          type: String.t(),
          command: String.t(),
          args: [String.t()],
          env: map()
        }

  @enforce_keys [:command]
  defstruct type: "stdio",
            command: "",
            args: [],
            env: %{}

  @doc "Convert to a map suitable for CLI MCP config."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = config) do
    base = %{"type" => "stdio", "command" => config.command}

    base
    |> maybe_put("args", non_empty_list(config.args))
    |> maybe_put("env", non_empty_map(config.env))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp non_empty_list([]), do: nil
  defp non_empty_list(list), do: list

  defp non_empty_map(map) when map_size(map) == 0, do: nil
  defp non_empty_map(map), do: map
end

defmodule ClaudeSDK.MCP.SSEServerConfig do
  @moduledoc """
  Configuration for an external MCP server communicating over Server-Sent Events.

  ## Fields

  - `url` — The SSE endpoint URL.
  - `headers` — Optional HTTP headers for authentication.

  ## Example

      %SSEServerConfig{
        url: "http://localhost:8080/mcp",
        headers: %{"Authorization" => "Bearer token"}
      }
  """

  @type t :: %__MODULE__{
          type: String.t(),
          url: String.t(),
          headers: map()
        }

  @enforce_keys [:url]
  defstruct type: "sse",
            url: "",
            headers: %{}

  @doc "Convert to a map suitable for CLI MCP config."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = config) do
    base = %{"type" => "sse", "url" => config.url}

    if map_size(config.headers) > 0,
      do: Map.put(base, "headers", config.headers),
      else: base
  end
end

defmodule ClaudeSDK.MCP.HttpServerConfig do
  @moduledoc """
  Configuration for an external MCP server communicating over HTTP.

  ## Fields

  - `url` — The HTTP endpoint URL.
  - `headers` — Optional HTTP headers for authentication.

  ## Example

      %HttpServerConfig{
        url: "http://localhost:8080/mcp",
        headers: %{"Authorization" => "Bearer token"}
      }
  """

  @type t :: %__MODULE__{
          type: String.t(),
          url: String.t(),
          headers: map()
        }

  @enforce_keys [:url]
  defstruct type: "http",
            url: "",
            headers: %{}

  @doc "Convert to a map suitable for CLI MCP config."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = config) do
    base = %{"type" => "http", "url" => config.url}

    if map_size(config.headers) > 0,
      do: Map.put(base, "headers", config.headers),
      else: base
  end
end
