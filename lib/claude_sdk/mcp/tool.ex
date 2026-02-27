defmodule ClaudeSDK.MCP.Tool do
  @moduledoc """
  Defines an MCP tool that can be hosted in-process.

  The `handler` function receives the tool arguments and returns
  `{:ok, result}` or `{:error, reason}`.
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
