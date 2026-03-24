defmodule ClaudeSDK.Internal do
  @moduledoc false

  @doc false
  @spec generate_request_id() :: String.t()
  def generate_request_id do
    "req_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  @doc false
  @spec sdk_version() :: String.t()
  def sdk_version do
    case :application.get_key(:claude_sdk, :vsn) do
      {:ok, vsn} -> List.to_string(vsn)
      :undefined -> ClaudeSDK.MixProject.project()[:version]
    end
  end

  @doc false
  @spec normalize_agents(list() | map() | term()) :: list() | map()
  def normalize_agents(agents) when is_list(agents) do
    Enum.map(agents, fn
      %ClaudeSDK.Types.AgentDefinition{} = agent ->
        ClaudeSDK.Types.AgentDefinition.to_map(agent)

      agent when is_map(agent) ->
        agent
    end)
  end

  def normalize_agents(agents) when is_map(agents), do: agents
  def normalize_agents(_), do: []

  @doc false
  @spec maybe_put_plugins(map(), list() | nil) :: map()
  def maybe_put_plugins(request, nil), do: request
  def maybe_put_plugins(request, []), do: request

  def maybe_put_plugins(request, plugins) when is_list(plugins),
    do: Map.put(request, :plugins, plugins)

  @doc false
  @spec build_init_request(ClaudeSDK.Types.Options.t()) :: map()
  def build_init_request(%ClaudeSDK.Types.Options{} = opts) do
    %{
      type: "control_request",
      request_id: generate_request_id(),
      request:
        %{
          subtype: "initialize",
          hooks: opts.hooks,
          agents: normalize_agents(opts.agents)
        }
        |> maybe_put_plugins(opts.plugins)
    }
  end

  @doc false
  @spec build_mcp_tool_index([map()] | nil) :: map()
  def build_mcp_tool_index([]), do: %{}
  def build_mcp_tool_index(nil), do: %{}

  def build_mcp_tool_index(servers) when is_list(servers) do
    ClaudeSDK.MCP.Server.build_tool_index(servers)
  end

  @doc false
  @spec build_control_handlers(ClaudeSDK.Types.Options.t()) :: map()
  def build_control_handlers(%ClaudeSDK.Types.Options{} = opts) do
    mcp_tool_index = build_mcp_tool_index(opts.mcp_servers)

    handler_opts = %{
      can_use_tool: opts.can_use_tool,
      mcp_tool_index: mcp_tool_index,
      hooks: opts.hooks
    }

    ClaudeSDK.ControlRouter.build_handlers(handler_opts)
  end

  @doc false
  @spec wait_for_init_response(pos_integer()) :: :ok | {:error, term()}
  def wait_for_init_response(timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    wait_for_init_loop(deadline)
  end

  defp wait_for_init_loop(deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:claude_message, %{"type" => "control_response", "response" => %{"error" => error}}} ->
        {:error, {:init_failed, error}}

      {:claude_message, %{"type" => "control_response"}} ->
        :ok

      {:claude_message, %{"type" => _}} ->
        wait_for_init_loop(deadline)

      {:claude_exit, reason} ->
        {:error, {:cli_exited, reason}}
    after
      remaining -> {:error, :init_timeout}
    end
  end

  @doc false
  @spec safe_stop_subprocess(pid()) :: :ok
  def safe_stop_subprocess(pid) do
    if Process.alive?(pid), do: ClaudeSDK.Transport.Subprocess.stop(pid)
    :ok
  catch
    :exit, _ -> :ok
  end
end
