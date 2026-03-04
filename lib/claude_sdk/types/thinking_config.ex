defmodule ClaudeSDK.Types.ThinkingConfig do
  @moduledoc """
  Typed configuration for extended thinking mode.

  Matches the Python SDK's thinking config types (`ThinkingConfigAdaptive`,
  `ThinkingConfigEnabled`, `ThinkingConfigDisabled`).

  ## Variants

  - `type: "adaptive"` — Adaptive thinking with optional budget.
  - `type: "enabled"` — Always-on thinking with required budget.
  - `type: "disabled"` — Thinking disabled.

  ## Fields

  - `type` — One of `"adaptive"`, `"enabled"`, or `"disabled"`.
  - `budget_tokens` — Token budget for thinking (required for `"enabled"`, optional for `"adaptive"`).

  ## Examples

      # Adaptive thinking
      %ThinkingConfig{type: "adaptive", budget_tokens: 10_000}

      # Always-on thinking
      %ThinkingConfig{type: "enabled", budget_tokens: 8_000}

      # Disabled
      %ThinkingConfig{type: "disabled"}

  ## Convenience Constructors

      ThinkingConfig.adaptive()
      ThinkingConfig.adaptive(10_000)
      ThinkingConfig.enabled(8_000)
      ThinkingConfig.disabled()
  """

  @type t :: %__MODULE__{
          type: String.t(),
          budget_tokens: pos_integer() | nil
        }

  @enforce_keys [:type]
  defstruct [:type, :budget_tokens]

  @doc "Create an adaptive thinking config with an optional token budget."
  @spec adaptive(pos_integer() | nil) :: t()
  def adaptive(budget_tokens \\ nil) do
    %__MODULE__{type: "adaptive", budget_tokens: budget_tokens}
  end

  @doc "Create an enabled thinking config with a required token budget."
  @spec enabled(pos_integer()) :: t()
  def enabled(budget_tokens) when is_integer(budget_tokens) and budget_tokens > 0 do
    %__MODULE__{type: "enabled", budget_tokens: budget_tokens}
  end

  @doc "Create a disabled thinking config."
  @spec disabled() :: t()
  def disabled do
    %__MODULE__{type: "disabled"}
  end

  @doc """
  Convert a ThinkingConfig to a map suitable for JSON encoding.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = config) do
    base = %{"type" => config.type}

    case config.budget_tokens do
      nil -> base
      tokens -> Map.put(base, "budget_tokens", tokens)
    end
  end
end
