defmodule ClaudeSDK.Types.AgentDefinition do
  @moduledoc """
  Definition for a custom subagent.

  Matches the Python SDK's `AgentDefinition` struct for defining custom agents
  that can be spawned by the CLI during tool use.

  ## Fields

  - `name` — Unique agent name identifier.
  - `description` — Human-readable description of what the agent does.
  - `prompt` — System prompt for the agent.
  - `model` — Model shorthand for this agent (optional). Valid values:
    `"sonnet"`, `"opus"`, `"haiku"`, or `"inherit"` (use the parent's model).
  - `tools` — List of tool name strings available to the agent (optional).
  - `allowed_tools` — Allowlist of tool names (optional).
  - `disallowed_tools` — Denylist of tool names (optional).
  - `max_turns` — Maximum number of agentic turns (optional).
  - `skills` — List of skill identifiers to auto-load for this agent (optional).
    Each string must match the name of a `SKILL.md` file discovered from
    `.claude/skills/`, `~/.claude/skills/`, or directories added via `add_dirs`
    / `plugin_dirs`. Unknown names are silently ignored by the CLI.
  - `memory` — Controls where the agent reads/writes persistent memory (optional).
    Valid values:
    - `"user"` — user-level memory stored in `~/.claude/`, persists across all projects.
    - `"project"` — project-level memory, shared across git worktrees of the same repo.
    - `"local"` — memory local to the current working environment only.
    - `nil` — no memory scope; the agent does not load persistent settings.
  - `mcp_servers` — MCP server configuration map for this agent (optional).
    Keys are server names, values are server config maps (matching `McpServerConfig`
    structure, e.g. `%{"type" => "stdio", "command" => "...", "args" => [...]}`).

  ## Example

      %AgentDefinition{
        name: "designer",
        description: "Creates frontend interfaces",
        prompt: "You are a frontend design assistant.",
        model: "sonnet",
        tools: ["Read", "Write", "Glob"],
        skills: ["frontend-design"],
        memory: "project"
      }
  """

  @valid_memory_scopes ["user", "project", "local"]
  @valid_models ["sonnet", "opus", "haiku", "inherit"]

  @type memory_scope :: String.t()
  @type agent_model :: String.t()

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          prompt: String.t(),
          model: agent_model() | nil,
          tools: [String.t()] | nil,
          allowed_tools: [String.t()] | nil,
          disallowed_tools: [String.t()] | nil,
          max_turns: pos_integer() | nil,
          skills: [String.t()] | nil,
          memory: memory_scope() | nil,
          mcp_servers: map() | nil
        }

  @enforce_keys [:name, :description, :prompt]
  defstruct [
    :name,
    :description,
    :prompt,
    :model,
    :tools,
    :allowed_tools,
    :disallowed_tools,
    :max_turns,
    :skills,
    :memory,
    :mcp_servers
  ]

  @doc """
  Validate an AgentDefinition, returning `:ok` or `{:error, reason}`.

  Checks:
  - `memory` must be nil or one of: `"user"`, `"project"`, `"local"`
  - `model` must be nil or one of: `"sonnet"`, `"opus"`, `"haiku"`, `"inherit"`
  - `max_turns` must be nil or a positive integer
  """
  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{} = agent) do
    with :ok <- validate_memory(agent.memory),
         :ok <- validate_model(agent.model),
         :ok <- validate_max_turns(agent.max_turns) do
      :ok
    end
  end

  @doc """
  Convert an AgentDefinition to a map suitable for the CLI protocol.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = agent) do
    %{
      name: agent.name,
      description: agent.description,
      prompt: agent.prompt
    }
    |> maybe_put(:model, agent.model)
    |> maybe_put(:tools, agent.tools)
    |> maybe_put(:allowed_tools, agent.allowed_tools)
    |> maybe_put(:disallowed_tools, agent.disallowed_tools)
    |> maybe_put(:max_turns, agent.max_turns)
    |> maybe_put(:skills, agent.skills)
    |> maybe_put(:memory, agent.memory)
    |> maybe_put(:mcpServers, agent.mcp_servers)
  end

  defp validate_memory(nil), do: :ok
  defp validate_memory(scope) when scope in @valid_memory_scopes, do: :ok

  defp validate_memory(scope),
    do:
      {:error,
       "agent memory must be one of #{inspect(@valid_memory_scopes)}, got: #{inspect(scope)}"}

  defp validate_model(nil), do: :ok
  defp validate_model(model) when model in @valid_models, do: :ok

  defp validate_model(model),
    do: {:error, "agent model must be one of #{inspect(@valid_models)}, got: #{inspect(model)}"}

  defp validate_max_turns(nil), do: :ok
  defp validate_max_turns(n) when is_integer(n) and n > 0, do: :ok

  defp validate_max_turns(n),
    do: {:error, "agent max_turns must be a positive integer, got: #{inspect(n)}"}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
