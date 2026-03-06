defmodule ClaudeSDK.Types.AgentDefinition do
  @moduledoc """
  Definition for a custom subagent.

  Matches the Python SDK's `AgentDefinition` struct for defining custom agents
  that can be spawned by the CLI during tool use.

  ## Fields

  - `name` — Unique agent name identifier.
  - `description` — Human-readable description of what the agent does.
  - `prompt` — System prompt for the agent.
  - `model` — Model identifier to use for this agent (optional).
  - `tools` — List of tool name strings available to the agent (optional).
  - `allowed_tools` — Allowlist of tool names (optional).
  - `disallowed_tools` — Denylist of tool names (optional).
  - `max_turns` — Maximum number of agentic turns (optional).

  ## Example

      %AgentDefinition{
        name: "researcher",
        description: "Searches codebase for relevant information",
        prompt: "You are a research assistant. Find relevant code and docs.",
        model: "claude-sonnet-4-6",
        tools: ["Read", "Glob", "Grep"]
      }
  """

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          prompt: String.t(),
          model: String.t() | nil,
          tools: [String.t()] | nil,
          allowed_tools: [String.t()] | nil,
          disallowed_tools: [String.t()] | nil,
          max_turns: pos_integer() | nil
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
    :max_turns
  ]

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
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
