defmodule ClaudeSDK.Types.SandboxSettings do
  @moduledoc """
  Typed sandbox configuration for the CLI subprocess.

  Matches the Python SDK's `SandboxSettings` struct for controlling sandbox
  behavior of the CLI.

  ## Fields

  - `enabled` — Whether sandbox mode is enabled (default: `false`).
  - `auto_allow_bash_if_sandboxed` — Automatically allow bash tool if sandboxed (default: `false`).
  - `excluded_commands` — List of commands to exclude from sandboxing.
  - `allow_unsandboxed_commands` — Whether to allow commands to run unsandboxed (default: `false`).
  - `network` — Network access config: `"allow"`, `"deny"`, or a map with detailed settings.
  - `ignore_violations` — Map of violation types to ignore (e.g. `%{"network" => true}`).
  - `enable_weaker_nested_sandbox` — Allow weaker sandbox for nested operations (default: `false`).

  ## Example

      %SandboxSettings{
        enabled: true,
        auto_allow_bash_if_sandboxed: true,
        network: "deny",
        ignore_violations: %{"network" => true}
      }
  """

  @type t :: %__MODULE__{
          enabled: boolean(),
          auto_allow_bash_if_sandboxed: boolean(),
          excluded_commands: [String.t()],
          allow_unsandboxed_commands: boolean(),
          network: String.t() | map() | nil,
          ignore_violations: map() | nil,
          enable_weaker_nested_sandbox: boolean()
        }

  defstruct enabled: false,
            auto_allow_bash_if_sandboxed: false,
            excluded_commands: [],
            allow_unsandboxed_commands: false,
            network: nil,
            ignore_violations: nil,
            enable_weaker_nested_sandbox: false

  @doc """
  Convert a SandboxSettings to a map suitable for JSON encoding.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = settings) do
    %{
      enabled: settings.enabled,
      autoAllowBashIfSandboxed: settings.auto_allow_bash_if_sandboxed,
      enableWeakerNestedSandbox: settings.enable_weaker_nested_sandbox,
      allowUnsandboxedCommands: settings.allow_unsandboxed_commands
    }
    |> maybe_put(:excludedCommands, non_empty_list(settings.excluded_commands))
    |> maybe_put(:network, settings.network)
    |> maybe_put(:ignoreViolations, settings.ignore_violations)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp non_empty_list([]), do: nil
  defp non_empty_list(list), do: list
end
