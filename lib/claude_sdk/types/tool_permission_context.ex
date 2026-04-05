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
      alias ClaudeSDK.Types.PermissionUpdate, as: PU

      can_use_tool: fn tool_name, input, context ->
        Logger.info("Permission check \#{context.request_id} for \#{tool_name}")

        # Allow and auto-approve Read + Glob for the rest of this session
        {:allow,
         updated_permissions: [
           PU.add_rules(
             [%{tool_name: "Read"}, %{tool_name: "Glob"}],
             :allow,
             :session
           )
         ]}
      end

  ## Permission Results

  Callbacks can return:

  - `:allow` — permit the tool use
  - `{:allow, opts}` — permit with options:
    - `updated_input: map()` — modified tool input to use instead
    - `updated_permissions: [map()]` — list of structured permission updates.
      Use `ClaudeSDK.Types.PermissionUpdate` constructors (`add_rules/3`,
      `set_mode/1`, `add_directories/2`, etc.) to build these, or pass raw
      maps in the shape the CLI expects.
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
