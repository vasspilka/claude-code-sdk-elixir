defmodule ClaudeSDK.Types.PermissionUpdate do
  @moduledoc """
  Structured permission updates returned from a `can_use_tool` callback.

  When a permission callback returns `{:allow, updated_permissions: [...]}`, the
  CLI expects each entry to be a tagged map describing a rule/mode/directory
  mutation — not a bare tool-name string. This module provides typed
  constructors that produce those maps in the shape the CLI expects.

  Maps to the Python SDK's `PermissionUpdate` union. Values are passed through
  the control-response unchanged; keys are already camelCased for the CLI.

  ## Behavior values

  Most constructors accept a `behavior` of `:allow`, `:deny`, or `:ask`
  (matching the CLI's permission rule behaviors).

  ## Destination values

  Directory/rule destinations scope the update:

  - `:user` — user-global settings
  - `:project` — project settings
  - `:local_settings` — local (machine) settings
  - `:session` — in-memory for the current session only

  ## Examples

      alias ClaudeSDK.Types.PermissionUpdate, as: PU

      # Allow Read + Glob for the remainder of this session
      {:allow,
       updated_permissions: [
         PU.add_rules([%{tool_name: "Read"}, %{tool_name: "Glob"}], :allow, :session)
       ]}

      # Switch the permission mode
      {:allow, updated_permissions: [PU.set_mode("acceptEdits")]}

      # Grant read access to an additional directory for this session
      {:allow, updated_permissions: [PU.add_directories(["/tmp/work"], :session)]}
  """

  @type behavior :: :allow | :deny | :ask
  @type destination :: :user | :project | :local_settings | :session
  @type rule :: map()

  @doc """
  Append permission rules to the given destination without replacing existing ones.
  """
  @spec add_rules([rule()], behavior(), destination()) :: map()
  def add_rules(rules, behavior, destination) when is_list(rules) do
    %{
      "type" => "addRules",
      "rules" => rules,
      "behavior" => encode_behavior(behavior),
      "destination" => encode_destination(destination)
    }
  end

  @doc """
  Replace all rules at the destination for the given behavior.
  """
  @spec replace_rules([rule()], behavior(), destination()) :: map()
  def replace_rules(rules, behavior, destination) when is_list(rules) do
    %{
      "type" => "replaceRules",
      "rules" => rules,
      "behavior" => encode_behavior(behavior),
      "destination" => encode_destination(destination)
    }
  end

  @doc """
  Remove specific rules from the destination.
  """
  @spec remove_rules([rule()], behavior(), destination()) :: map()
  def remove_rules(rules, behavior, destination) when is_list(rules) do
    %{
      "type" => "removeRules",
      "rules" => rules,
      "behavior" => encode_behavior(behavior),
      "destination" => encode_destination(destination)
    }
  end

  @doc """
  Change the active permission mode.

  `mode` accepts the CLI string form (`"default"`, `"acceptEdits"`, `"plan"`,
  `"bypassPermissions"`, `"dontAsk"`) or the snake_case atom which is converted.
  """
  @spec set_mode(String.t() | atom()) :: map()
  def set_mode(mode), do: %{"type" => "setMode", "mode" => encode_mode(mode)}

  @doc """
  Grant the CLI additional directory access for the given destination.
  """
  @spec add_directories([String.t()], destination()) :: map()
  def add_directories(dirs, destination) when is_list(dirs) do
    %{
      "type" => "addDirectories",
      "directories" => dirs,
      "destination" => encode_destination(destination)
    }
  end

  @doc """
  Remove directory access at the destination.
  """
  @spec remove_directories([String.t()], destination()) :: map()
  def remove_directories(dirs, destination) when is_list(dirs) do
    %{
      "type" => "removeDirectories",
      "directories" => dirs,
      "destination" => encode_destination(destination)
    }
  end

  # ── encoders ────────────────────────────────────────────────────────────

  defp encode_behavior(:allow), do: "allow"
  defp encode_behavior(:deny), do: "deny"
  defp encode_behavior(:ask), do: "ask"
  defp encode_behavior(b) when is_binary(b), do: b

  defp encode_destination(:user), do: "userSettings"
  defp encode_destination(:project), do: "projectSettings"
  defp encode_destination(:local_settings), do: "localSettings"
  defp encode_destination(:session), do: "session"
  defp encode_destination(d) when is_binary(d), do: d

  defp encode_mode(:default), do: "default"
  defp encode_mode(:accept_edits), do: "acceptEdits"
  defp encode_mode(:plan), do: "plan"
  defp encode_mode(:bypass_permissions), do: "bypassPermissions"
  defp encode_mode(:dont_ask), do: "dontAsk"
  defp encode_mode(m) when is_binary(m), do: m
end
