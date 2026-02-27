defmodule ClaudeSDK.MCP.Tool do
  @moduledoc """
  Defines an MCP tool that can be hosted in-process.

  Tools are registered with an MCP server via `ClaudeSDK.create_mcp_server/3`
  and become callable by the Claude CLI during a query.

  ## Fields

  - `name` — Tool name as it appears to the CLI (e.g. `"lookup_user"`).
  - `description` — Human-readable description shown to the model.
  - `input_schema` — JSON Schema map describing the expected arguments.
  - `handler` — Function `(args :: map()) -> {:ok, result} | {:error, reason}`.
    The result can be a string, map (JSON-encoded automatically), or a list
    of MCP content parts.

  ## Example

      %ClaudeSDK.MCP.Tool{
        name: "get_weather",
        description: "Get current weather for a city",
        input_schema: %{
          "type" => "object",
          "properties" => %{
            "city" => %{"type" => "string"}
          },
          "required" => ["city"]
        },
        handler: fn %{"city" => city} ->
          {:ok, "Weather in \#{city}: 72F, sunny"}
        end
      }
  """

  @type handler :: (args :: map() -> {:ok, term()} | {:error, String.t()})

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          input_schema: map(),
          handler: handler()
        }

  @enforce_keys [:name, :description, :input_schema, :handler]
  defstruct [:name, :description, :input_schema, :handler]
end
