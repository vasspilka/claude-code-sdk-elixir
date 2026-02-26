defmodule ClaudeSDK.Types.Options do
  @moduledoc """
  Configuration options for a ClaudeSDK query.

  Maps to CLI arguments and environment variables.
  """

  @type permission_mode :: :default | :accept_edits | :plan | :bypass_permissions

  @type t :: %__MODULE__{
          # CLI path override (nil = auto-discover)
          cli_path: String.t() | nil,

          # Prompt options
          system_prompt: String.t() | nil,
          append_system_prompt: String.t() | nil,

          # Model options
          model: String.t() | nil,
          fallback_model: String.t() | nil,

          # Tool configuration
          tools: [String.t()] | :default | nil,
          allowed_tools: [String.t()] | nil,
          disallowed_tools: [String.t()] | nil,

          # Limits
          max_turns: pos_integer() | nil,
          max_budget_usd: float() | nil,
          max_thinking_tokens: pos_integer() | nil,

          # Permission mode
          permission_mode: permission_mode() | nil,

          # Session management
          continue: boolean(),
          resume: String.t() | nil,
          fork_session: boolean(),
          session_id: String.t(),

          # Working directory
          cwd: String.t() | nil,
          add_dirs: [String.t()],

          # Streaming
          include_partial_messages: boolean(),

          # Effort level
          effort: String.t() | nil,

          # Structured output
          json_schema: map() | nil,

          # Settings
          settings: map() | nil,
          setting_sources: [String.t()] | nil,

          # MCP configuration
          mcp_config: map() | String.t() | nil,

          # Plugin directories
          plugin_dirs: [String.t()],

          # Hooks (sent via initialize, not CLI args)
          hooks: map(),

          # Agents (sent via initialize, not CLI args)
          agents: map(),

          # Environment variables
          env: map(),

          # Extra CLI args (escape hatch)
          extra_args: [String.t()]
        }

  defstruct cli_path: nil,
            system_prompt: nil,
            append_system_prompt: nil,
            model: nil,
            fallback_model: nil,
            tools: nil,
            allowed_tools: nil,
            disallowed_tools: nil,
            max_turns: nil,
            max_budget_usd: nil,
            max_thinking_tokens: nil,
            permission_mode: nil,
            continue: false,
            resume: nil,
            fork_session: false,
            session_id: "default",
            cwd: nil,
            add_dirs: [],
            include_partial_messages: false,
            effort: nil,
            json_schema: nil,
            settings: nil,
            setting_sources: nil,
            mcp_config: nil,
            plugin_dirs: [],
            hooks: %{},
            agents: %{},
            env: %{},
            extra_args: []
end
