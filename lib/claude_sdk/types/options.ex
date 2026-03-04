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

  ### Thinking

  - `thinking` — Thinking mode configuration map. Keys: `"type"` (`"adaptive"`, `"enabled"`,
    or `"disabled"`) and optionally `"budget_tokens"` (integer).

  ### Output Format

  - `output_format` — JSON Schema map for structured output format. Maps to `--output-format` JSON.

  ### Sandbox

  - `sandbox` — Sandbox configuration map. Maps to `--sandbox` JSON.

  ### Plugins

  - `plugins` — List of plugin configuration maps.

  ### Betas

  - `betas` — List of beta feature flag strings. Each maps to a repeated `--beta` flag.

  ### User

  - `user` — User identifier string. Maps to `--user`.

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

  ### Timeouts

  - `init_timeout_ms` — Timeout in ms for the initialization handshake (default: 30_000).
  - `message_timeout_ms` — Timeout in ms for receiving messages during streaming (default: 120_000).

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

          # Thinking mode
          thinking: map() | nil,

          # Structured output
          json_schema: map() | nil,
          output_format: map() | nil,

          # Settings
          settings: map() | nil,
          setting_sources: [String.t()] | nil,

          # Sandbox
          sandbox: map() | nil,

          # Plugins
          plugins: [map()] | nil,

          # Beta feature flags
          betas: [String.t()] | nil,

          # User identifier
          user: String.t() | nil,

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

          # Timeouts
          init_timeout_ms: pos_integer(),
          message_timeout_ms: pos_integer(),

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
            thinking: nil,
            json_schema: nil,
            output_format: nil,
            settings: nil,
            setting_sources: nil,
            sandbox: nil,
            plugins: nil,
            betas: nil,
            user: nil,
            mcp_config: nil,
            mcp_servers: [],
            plugin_dirs: [],
            hooks: %{},
            agents: %{},
            env: %{},
            enable_file_checkpointing: false,
            init_timeout_ms: 30_000,
            message_timeout_ms: 120_000,
            extra_args: []

  @valid_permission_modes [nil, :default, :accept_edits, :plan, :bypass_permissions]
  @valid_efforts [nil, "low", "medium", "high", "max"]

  @doc """
  Validate an Options struct, returning `:ok` or `{:error, reason}`.

  Checks:
  - `max_turns` must be a positive integer or nil
  - `max_budget_usd` must be a positive number or nil
  - `permission_mode` must be one of: nil, :default, :accept_edits, :plan, :bypass_permissions
  - `effort` must be one of: nil, "low", "medium", "high", "max"
  """
  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{} = opts) do
    with :ok <- validate_max_turns(opts.max_turns),
         :ok <- validate_max_budget_usd(opts.max_budget_usd),
         :ok <- validate_permission_mode(opts.permission_mode),
         :ok <- validate_effort(opts.effort) do
      :ok
    end
  end

  defp validate_max_turns(nil), do: :ok
  defp validate_max_turns(n) when is_integer(n) and n > 0, do: :ok

  defp validate_max_turns(n),
    do: {:error, "max_turns must be a positive integer, got: #{inspect(n)}"}

  defp validate_max_budget_usd(nil), do: :ok
  defp validate_max_budget_usd(n) when is_number(n) and n > 0, do: :ok

  defp validate_max_budget_usd(n),
    do: {:error, "max_budget_usd must be a positive number, got: #{inspect(n)}"}

  defp validate_permission_mode(mode) when mode in @valid_permission_modes, do: :ok

  defp validate_permission_mode(mode),
    do:
      {:error,
       "permission_mode must be one of #{inspect(@valid_permission_modes)}, got: #{inspect(mode)}"}

  defp validate_effort(effort) when effort in @valid_efforts, do: :ok

  defp validate_effort(effort),
    do: {:error, "effort must be one of #{inspect(@valid_efforts)}, got: #{inspect(effort)}"}
end
