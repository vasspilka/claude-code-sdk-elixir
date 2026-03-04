defmodule ClaudeSDK.Types.SandboxSettings do
  @moduledoc """
  Typed sandbox configuration for the CLI subprocess.

  Matches the Python SDK's `SandboxSettings` struct for controlling sandbox
  behavior of the CLI.

  ## Fields

  - `enabled` — Whether sandbox mode is enabled (default: `false`).
  - `auto_allow_bash_if_sandboxed` — Automatically allow bash tool if sandboxed (default: `false`).
  - `excluded_commands` — List of commands to exclude from sandboxing.
  - `network` — Network access setting: `"allow"`, `"deny"`, or `nil` for default.

  ## Example

      %SandboxSettings{
        enabled: true,
        auto_allow_bash_if_sandboxed: true,
        network: "deny"
      }
  """

  @type t :: %__MODULE__{
          enabled: boolean(),
          auto_allow_bash_if_sandboxed: boolean(),
          excluded_commands: [String.t()],
          network: String.t() | nil
        }

  defstruct enabled: false,
            auto_allow_bash_if_sandboxed: false,
            excluded_commands: [],
            network: nil

  @doc """
  Convert a SandboxSettings to a map suitable for JSON encoding.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = settings) do
    %{
      enabled: settings.enabled,
      autoAllowBashIfSandboxed: settings.auto_allow_bash_if_sandboxed
    }
    |> maybe_put(:excludedCommands, non_empty_list(settings.excluded_commands))
    |> maybe_put(:network, settings.network)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp non_empty_list([]), do: nil
  defp non_empty_list(list), do: list
end
