defmodule ClaudeSDK.Types.ToolPermissionContext do
  @moduledoc """
  Context provided to `can_use_tool` permission callbacks.

  Matches the Python SDK's `ToolPermissionContext`, providing additional
  metadata about the tool use request beyond just the tool name and input.

  ## Fields

  - `tool_name` — Name of the tool being requested (e.g. `"Bash"`, `"Read"`).
  - `input` — Map of arguments passed to the tool.
  - `request_id` — The control request ID for this permission check.
  - `permission_suggestions` — Suggested permissions from the CLI (may be nil).
  - `raw_request` — The full raw request map from the CLI.

  ## Example

  The `can_use_tool` callback can accept either 2 args (tool_name, input)
  for backwards compatibility, or 3 args (tool_name, input, context) for
  access to the full context:

      # Simple callback (backwards compatible)
      can_use_tool: fn tool_name, _input ->
        if tool_name == "Bash", do: {:deny, "No bash"}, else: :allow
      end

      # Context-aware callback with dynamic permission updates
      can_use_tool: fn tool_name, input, context ->
        Logger.info("Permission check \#{context.request_id} for \#{tool_name}")

        # Allow and auto-approve this tool for future calls
        {:allow, updated_permissions: ["Read", "Glob"]}
      end

  ## Permission Results

  Callbacks can return:

  - `:allow` — permit the tool use
  - `{:allow, opts}` — permit with options:
    - `updated_input: map()` — modified tool input to use instead
    - `updated_permissions: [String.t()]` — tools to auto-approve going forward
  - `:deny` — deny with default message
  - `{:deny, reason}` — deny with a custom reason string
  - `{:deny, reason, :interrupt}` — deny and interrupt the active conversation
  """

  @type t :: %__MODULE__{
          tool_name: String.t(),
          input: map(),
          request_id: String.t(),
          permission_suggestions: list() | nil,
          raw_request: map()
        }

  defstruct tool_name: "",
            input: %{},
            request_id: "",
            permission_suggestions: nil,
            raw_request: %{}
end
