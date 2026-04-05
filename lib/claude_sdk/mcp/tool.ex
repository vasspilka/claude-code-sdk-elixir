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
    The result may be:
    - a string (wrapped as a `text` content part, auto-truncated if large),
    - a map (JSON-encoded and wrapped as `text`),
    - a list of MCP content parts (passed through as-is — use this to return
      `image`, `resource_link`, or embedded `resource` content types).
  - `annotations` — Optional `ToolAnnotations` map included in the `tools/list`
    response. The SDK additionally injects `max_result_size_chars` (when set)
    as `_meta."anthropic/maxResultSizeChars"` so the CLI can stream large
    results without Zod annotation stripping.
  - `max_result_size_chars` — Optional integer. When set, text tool results
    longer than this are truncated and surfaced via `_meta` to the CLI.

  ## Example

      %ClaudeSDK.MCP.Tool{
        name: "get_weather",
        description: "Get current weather for a city",
        input_schema: %{
          "type" => "object",
          "properties" => %{"city" => %{"type" => "string"}},
          "required" => ["city"]
        },
        handler: fn %{"city" => city} ->
          {:ok, "Weather in \#{city}: 72F, sunny"}
        end,
        annotations: %{"readOnlyHint" => true}
      }

  ## Returning image content

      handler: fn _args ->
        {:ok, [
          %{"type" => "image", "data" => base64, "mimeType" => "image/png"}
        ]}
      end
  """

  @type handler :: (args :: map() -> {:ok, term()} | {:error, String.t()})

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          input_schema: map(),
          handler: handler(),
          annotations: map() | nil,
          max_result_size_chars: pos_integer() | nil
        }

  @enforce_keys [:name, :description, :input_schema, :handler]
  defstruct [
    :name,
    :description,
    :input_schema,
    :handler,
    :annotations,
    :max_result_size_chars
  ]
end
