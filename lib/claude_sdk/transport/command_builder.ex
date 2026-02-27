defmodule ClaudeSDK.Transport.CommandBuilder do
  @moduledoc """
  Maps a `ClaudeSDK.Types.Options` struct to CLI argument list.
  """

  alias ClaudeSDK.Types.Options

  @base_args ["--output-format", "stream-json", "--input-format", "stream-json", "--verbose"]

  @permission_mode_map %{
    default: "default",
    accept_edits: "acceptEdits",
    plan: "plan",
    bypass_permissions: "bypassPermissions"
  }

  @doc """
  Build the full argument list for the CLI subprocess.
  """
  @spec build_args(Options.t()) :: [String.t()]
  def build_args(%Options{} = opts) do
    @base_args
    |> maybe_add("--system-prompt", opts.system_prompt)
    |> maybe_add("--append-system-prompt", opts.append_system_prompt)
    |> maybe_add("--model", opts.model)
    |> maybe_add("--fallback-model", opts.fallback_model)
    |> add_tools(opts.tools)
    |> maybe_add_list("--allowed-tools", opts.allowed_tools)
    |> maybe_add_list("--disallowed-tools", opts.disallowed_tools)
    |> maybe_add("--max-turns", opts.max_turns)
    |> maybe_add("--max-budget-usd", opts.max_budget_usd)
    |> maybe_add("--max-thinking-tokens", opts.max_thinking_tokens)
    |> add_permission_mode(opts.permission_mode)
    |> add_permission_prompt_tool(opts.can_use_tool)
    |> maybe_add_flag("--continue", opts.continue)
    |> maybe_add("--resume", opts.resume)
    |> maybe_add_flag("--fork-session", opts.fork_session)
    |> maybe_add_flag("--include-partial-messages", opts.include_partial_messages)
    |> maybe_add("--effort", opts.effort)
    |> add_json_opt("--json-schema", opts.json_schema)
    |> add_json_opt("--settings", opts.settings)
    |> maybe_add_list("--setting-sources", opts.setting_sources)
    |> add_mcp_config(opts.mcp_config)
    |> add_sdk_mcp_servers(opts.mcp_servers)
    |> add_repeated("--add-dir", opts.add_dirs)
    |> add_repeated("--plugin-dir", opts.plugin_dirs)
    |> Kernel.++(opts.extra_args)
  end

  @doc """
  Build the environment variables map for the subprocess.
  """
  @spec build_env(Options.t()) :: [{String.t(), String.t()}]
  def build_env(%Options{} = opts) do
    base = [
      {"CLAUDE_CODE_ENTRYPOINT", "sdk-elixir"},
      {"CLAUDE_AGENT_SDK_VERSION", "0.1.0"}
    ]

    base
    |> maybe_add_checkpointing_env(opts.enable_file_checkpointing)
    |> Kernel.++(Enum.map(opts.env, fn {k, v} -> {to_string(k), to_string(v)} end))
  end

  # Private helpers

  defp add_permission_prompt_tool(args, nil), do: args

  defp add_permission_prompt_tool(args, callback) when is_function(callback, 2) do
    args ++ ["--permission-prompt-tool", "stdio"]
  end

  defp add_sdk_mcp_servers(args, []), do: args
  defp add_sdk_mcp_servers(args, nil), do: args

  defp add_sdk_mcp_servers(args, servers) when is_list(servers) do
    cli_config = ClaudeSDK.MCP.Server.to_cli_config(servers)
    args ++ ["--mcp-config", Jason.encode!(cli_config)]
  end

  defp maybe_add_checkpointing_env(env, false), do: env
  defp maybe_add_checkpointing_env(env, nil), do: env

  defp maybe_add_checkpointing_env(env, true) do
    env ++ [{"CLAUDE_CODE_ENABLE_SDK_FILE_CHECKPOINTING", "true"}]
  end

  defp maybe_add(args, _flag, nil), do: args
  defp maybe_add(args, flag, value), do: args ++ [flag, to_string(value)]

  defp maybe_add_flag(args, _flag, false), do: args
  defp maybe_add_flag(args, flag, true), do: args ++ [flag]

  defp maybe_add_list(args, _flag, nil), do: args
  defp maybe_add_list(args, _flag, []), do: args
  defp maybe_add_list(args, flag, items), do: args ++ [flag, Enum.join(items, ",")]

  defp add_tools(args, nil), do: args
  defp add_tools(args, :default), do: args ++ ["--tools", "default"]
  defp add_tools(args, tools) when is_list(tools), do: args ++ ["--tools", Enum.join(tools, ",")]

  defp add_permission_mode(args, nil), do: args

  defp add_permission_mode(args, mode) do
    case Map.get(@permission_mode_map, mode) do
      nil -> args
      value -> args ++ ["--permission-mode", value]
    end
  end

  defp add_json_opt(args, _flag, nil), do: args
  defp add_json_opt(args, flag, map) when is_map(map), do: args ++ [flag, Jason.encode!(map)]

  defp add_mcp_config(args, nil), do: args
  defp add_mcp_config(args, config) when is_binary(config), do: args ++ ["--mcp-config", config]

  defp add_mcp_config(args, config) when is_map(config),
    do: args ++ ["--mcp-config", Jason.encode!(config)]

  defp add_repeated(args, _flag, []), do: args

  defp add_repeated(args, flag, items),
    do: Enum.reduce(items, args, fn item, acc -> acc ++ [flag, item] end)
end
