defmodule ClaudeSDK.Types.Options do
  @moduledoc """
  Configuration options for a ClaudeSDK query.

  Maps to CLI arguments and environment variables passed to the Claude Code
  subprocess. Can be passed as a struct to `ClaudeSDK.query/2` or as the
  `:options` keyword to `ClaudeSDK.Client.start_link/1`.

  ## Examples

      # Minimal — all defaults
      ClaudeSDK.query("Hello")

      # With options
      ClaudeSDK.query("Explain GenServers", %Options{
        model: "claude-sonnet-4-20250514",
        system_prompt: "You are a concise Elixir tutor.",
        max_turns: 3,
        permission_mode: :bypass_permissions
      })

      # As keyword list (converted to struct internally)
      ClaudeSDK.query("Hello", max_turns: 1, permission_mode: :bypass_permissions)

  ## Fields

  ### Prompt

  - `system_prompt` — Override the default system prompt entirely.
  - `append_system_prompt` — Append text to the default system prompt.

  ### Model

  - `model` — Model identifier (e.g. `"claude-sonnet-4-20250514"`).
  - `fallback_model` — Fallback if the primary model is unavailable.

  ### Tool Configuration

  - `tools` — Tool set: `:default` for built-in tools, or a list of tool name strings.
  - `allowed_tools` — Allowlist of tool names. Only these tools may be used.
  - `disallowed_tools` — Denylist of tool names. These tools are blocked.
  - `can_use_tool` — Callback invoked for each tool call. Receives `(tool_name, input)`
    and must return `:allow`, `{:allow, updated_input}`, or `{:deny, reason}`.

  ### Limits

  - `max_turns` — Maximum number of agentic turns before stopping.
  - `max_budget_usd` — Maximum spend in USD for the query.
  - `max_thinking_tokens` — Maximum tokens allocated for extended thinking.

  ### Permissions

  - `permission_mode` — One of `:default`, `:accept_edits`, `:plan`, or `:bypass_permissions`.

  ### Session Management

  - `session_id` — Session identifier (default: `"default"`).
  - `continue` — If `true`, continue the most recent session.
  - `resume` — Resume a specific session by its ID string.
  - `fork_session` — If `true`, fork the current session instead of continuing it.

  ### Working Directory

  - `cwd` — Working directory for the CLI subprocess (default: current dir).
  - `add_dirs` — Additional directories to make available to the CLI.

  ### Streaming

  - `include_partial_messages` — If `true`, include partial streaming messages.

  ### Structured Output

  - `json_schema` — JSON Schema map. When set, the CLI returns structured JSON
    matching this schema in the `ResultMessage.result` field.

  ### MCP (Model Context Protocol)

  - `mcp_servers` — List of in-process MCP server configs created via
    `ClaudeSDK.create_mcp_server/3`. These tools are callable by the CLI.
  - `mcp_config` — Path to an external MCP config file, or a config map.

  ### File Checkpointing

  - `enable_file_checkpointing` — If `true`, the CLI checkpoints file state
    at each user message, enabling `ClaudeSDK.Client.rewind_files/2`.

  ### Miscellaneous

  - `cli_path` — Override the CLI binary path (auto-discovered by default).
  - `effort` — Effort level string.
  - `settings` — Map of CLI settings to override.
  - `setting_sources` — List of setting source paths.
  - `plugin_dirs` — List of plugin directory paths.
  - `hooks` — Hook configuration map (sent via initialize, not as CLI args).
  - `agents` — Agent configuration map (sent via initialize, not as CLI args).
  - `env` — Extra environment variables as a map of string key-value pairs.
  - `extra_args` — Escape hatch: additional raw CLI argument strings.
  """

  @type permission_mode :: :default | :accept_edits | :plan | :bypass_permissions

  @type can_use_tool_callback ::
          (tool_name :: String.t(), input :: map() ->
             :allow | {:allow, map()} | {:deny, String.t()})

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

          # Permission callback
          can_use_tool: can_use_tool_callback() | nil,

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

          # In-process MCP servers
          mcp_servers: [map()],

          # Plugin directories
          plugin_dirs: [String.t()],

          # Hooks (sent via initialize, not CLI args)
          hooks: map(),

          # Agents (sent via initialize, not CLI args)
          agents: map(),

          # Environment variables
          env: map(),

          # File checkpointing
          enable_file_checkpointing: boolean(),

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
            can_use_tool: nil,
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
            mcp_servers: [],
            plugin_dirs: [],
            hooks: %{},
            agents: %{},
            env: %{},
            enable_file_checkpointing: false,
            extra_args: []
end
