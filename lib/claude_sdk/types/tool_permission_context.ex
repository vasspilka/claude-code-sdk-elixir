defmodule ClaudeSDK.Types.ToolPermissionContext do
  @moduledoc """
  Context provided to `can_use_tool` permission callbacks.

  Matches the Python SDK's `ToolPermissionContext`, providing additional
  metadata about the tool use request beyond just the tool name and input.

  ## Fields

  - `tool_name` — Name of the tool being requested (e.g. `"Bash"`, `"Read"`).
  - `input` — Map of arguments passed to the tool.
  - `request_id` — The control request ID for this permission check.
  - `raw_request` — The full raw request map from the CLI.

  ## Example

  The `can_use_tool` callback can accept either 2 args (tool_name, input)
  for backwards compatibility, or 3 args (tool_name, input, context) for
  access to the full context:

      # Simple callback (backwards compatible)
      can_use_tool: fn tool_name, _input ->
        if tool_name == "Bash", do: {:deny, "No bash"}, else: :allow
      end

      # Context-aware callback
      can_use_tool: fn tool_name, input, context ->
        Logger.info("Permission check \#{context.request_id} for \#{tool_name}")
        :allow
      end
  """

  @type t :: %__MODULE__{
          tool_name: String.t(),
          input: map(),
          request_id: String.t(),
          raw_request: map()
        }

  defstruct tool_name: "",
            input: %{},
            request_id: "",
            raw_request: %{}
end
