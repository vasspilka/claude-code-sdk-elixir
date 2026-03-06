defmodule ClaudeSDK.Client do
  @moduledoc """
  Stateful multi-turn client for the Claude CLI.

  Unlike `ClaudeSDK.query/2` which spawns a subprocess per call,
  the Client keeps a single subprocess alive across multiple queries,
  enabling multi-turn conversations with session persistence.

  ## Quick Start

  Use `with_client/2` for automatic connection and cleanup:

      alias ClaudeSDK.Types.Options

      ClaudeSDK.Client.with_client(
        [options: %Options{permission_mode: :bypass_permissions}],
        fn client ->
          ClaudeSDK.Client.query(client, "What is 2+2?")
          |> Enum.each(&IO.inspect/1)

          ClaudeSDK.Client.query(client, "Now multiply that by 3")
          |> Enum.each(&IO.inspect/1)
        end
      )

  ## Manual Lifecycle

  For more control, manage the connection yourself. You must call
  `connect/1` before sending queries:

      {:ok, client} = ClaudeSDK.Client.start_link(options: %Options{})
      :ok = ClaudeSDK.Client.connect(client)

      ClaudeSDK.Client.query(client, "What is 2+2?")
      |> Enum.each(&IO.inspect/1)

      ClaudeSDK.Client.query(client, "Now multiply that by 3")
      |> Enum.each(&IO.inspect/1)

      ClaudeSDK.Client.close(client)

  ## State Machine

  The client transitions through these states:

  - `:disconnected` -- initial state after `start_link/1`
  - `:connected` -- after `connect/1` succeeds; ready for queries
  - `:streaming` -- while a `query/2` stream is active
  - `:awaiting_rewind` -- while a `rewind_files/2` request is pending
  - `:awaiting_control_response` -- while a control request (MCP status, etc.) is pending
  """

  use GenServer

  alias ClaudeSDK.ControlRouter
  alias ClaudeSDK.Transport.Subprocess
  alias ClaudeSDK.Types.Options

  require Logger

  # 30s is generous for CLI startup + initialize handshake
  @default_init_timeout 30_000
  # 120s allows for extended thinking and large responses;
  # override via Options.message_timeout_ms for longer operations
  @default_message_timeout 120_000
  # 30s for control request/response round-trips (rewind, MCP status, etc.)
  @default_control_timeout 30_000

  defstruct [
    :options,
    :subprocess,
    :control_handlers,
    :session_id,
    :active_caller,
    :control_timer,
    state: :disconnected
  ]

  # Client API

  @doc """
  Start a new Client process.

  ## Options

  - `:options` — `%Options{}` struct (default: `%Options{}`)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Connect to the CLI subprocess and perform initialization handshake.

  Must be called before `query/2`.
  """
  @spec connect(GenServer.server()) :: :ok | {:error, term()}
  def connect(client) do
    GenServer.call(client, :connect, @default_init_timeout + 5_000)
  end

  @doc """
  Send a prompt and return a stream of typed messages.

  The subprocess stays alive after the stream completes, allowing
  subsequent queries in the same session.
  """
  @spec query(GenServer.server(), String.t()) :: Enumerable.t()
  def query(client, prompt) when is_binary(prompt) do
    Stream.resource(
      fn -> start_query(client, prompt) end,
      fn state -> receive_client_messages(state, client) end,
      fn _state -> finish_query(client) end
    )
  end

  @doc """
  Rewind files to the state they were in at a given user message.

  Requires `enable_file_checkpointing: true` in Options.
  Only available on the Client (not stateless `query/2`).
  """
  @spec rewind_files(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def rewind_files(client, user_message_id) when is_binary(user_message_id) do
    GenServer.call(client, {:rewind_files, user_message_id}, @default_init_timeout)
  end

  @doc """
  Interrupt the current streaming operation.

  Sends an interrupt signal to cancel the active query. The stream will
  receive a completion signal and the client returns to `:connected` state.
  """
  @spec interrupt(GenServer.server()) :: :ok | {:error, term()}
  def interrupt(client) do
    GenServer.call(client, :interrupt)
  end

  @doc """
  Change the model mid-session.

  Can only be called when the client is in `:connected` state (not streaming).
  """
  @spec set_model(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def set_model(client, model) when is_binary(model) do
    GenServer.call(client, {:set_model, model})
  end

  @doc """
  Change the permission mode mid-session.

  Can only be called when the client is in `:connected` state (not streaming).
  """
  @spec set_permission_mode(GenServer.server(), atom()) :: :ok | {:error, term()}
  def set_permission_mode(client, mode) when is_atom(mode) do
    GenServer.call(client, {:set_permission_mode, mode})
  end

  @doc """
  Get MCP server connection status.

  Returns a status map from the CLI. Can only be called when connected.
  """
  @spec get_mcp_status(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def get_mcp_status(client) do
    GenServer.call(client, :get_mcp_status, @default_init_timeout)
  end

  @doc """
  Get CLI server info.

  Returns a server info map from the CLI. Can only be called when connected.
  """
  @spec get_server_info(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def get_server_info(client) do
    GenServer.call(client, :get_server_info, @default_init_timeout)
  end

  @doc """
  Reconnect a failed MCP server by name.

  Can only be called when the client is in `:connected` state.
  """
  @spec reconnect_mcp_server(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def reconnect_mcp_server(client, server_name) when is_binary(server_name) do
    GenServer.call(client, {:reconnect_mcp_server, server_name}, @default_init_timeout)
  end

  @doc """
  Enable or disable an MCP server by name.

  Can only be called when the client is in `:connected` state.
  """
  @spec toggle_mcp_server(GenServer.server(), String.t(), boolean()) :: :ok | {:error, term()}
  def toggle_mcp_server(client, server_name, enabled)
      when is_binary(server_name) and is_boolean(enabled) do
    GenServer.call(client, {:toggle_mcp_server, server_name, enabled}, @default_init_timeout)
  end

  @doc """
  Close the client and stop the subprocess.
  """
  @spec close(GenServer.server()) :: :ok
  def close(client) do
    GenServer.stop(client, :normal)
  end

  @doc """
  Start a client, run a function, and ensure cleanup.

  Equivalent to Python SDK's `async with ClaudeSDKClient() as client:`.
  Starts the client, connects it, runs the callback, and closes it —
  even if the callback raises.

  ## Example

      ClaudeSDK.Client.with_client(
        [options: %Options{permission_mode: :bypass_permissions}],
        fn client ->
          ClaudeSDK.Client.query(client, "Hello") |> Enum.to_list()
        end
      )
  """
  @spec with_client(keyword(), (GenServer.server() -> result)) :: result when result: var
  def with_client(opts \\ [], fun) when is_function(fun, 1) do
    {:ok, client} = start_link(opts)

    try do
      case connect(client) do
        :ok -> fun.(client)
        {:error, reason} -> raise ClaudeSDK.TransportError, reason: reason
      end
    after
      try do
        close(client)
      catch
        :exit, _ -> :ok
      end
    end
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    options = Keyword.get(opts, :options, %Options{})

    state = %__MODULE__{
      options: options,
      state: :disconnected
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:connect, _from, %{state: :disconnected} = state) do
    case do_connect(state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:connect, _from, %{state: :connected} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:connect, _from, state) do
    {:reply, {:error, :busy}, state}
  end

  def handle_call({:start_query, prompt, caller}, _from, %{state: :connected} = state) do
    user_message = %{
      type: "user",
      session_id: state.session_id || state.options.session_id,
      message: %{role: "user", content: prompt},
      parent_tool_use_id: nil
    }

    Subprocess.send_message(state.subprocess, user_message)

    message_timeout = state.options.message_timeout_ms || @default_message_timeout
    {:reply, {:ok, message_timeout}, %{state | state: :streaming, active_caller: caller}}
  end

  def handle_call({:start_query, _prompt, _caller}, _from, %{state: s} = state) do
    {:reply, {:error, {:invalid_state, s}}, state}
  end

  def handle_call(:finish_query, _from, %{state: :streaming} = state) do
    {:reply, :ok, %{state | state: :connected, active_caller: nil}}
  end

  def handle_call(:finish_query, _from, state) do
    {:reply, :ok, %{state | active_caller: nil}}
  end

  def handle_call({:rewind_files, user_message_id}, from, %{state: :connected} = state) do
    request_id = ClaudeSDK.generate_request_id()

    rewind_request = %{
      type: "control_request",
      request_id: request_id,
      request: %{
        subtype: "rewind_files",
        user_message_id: user_message_id
      }
    }

    Subprocess.send_message(state.subprocess, rewind_request)

    timer = Process.send_after(self(), :control_timeout, @default_control_timeout)
    {:noreply, %{state | state: :awaiting_rewind, active_caller: from, control_timer: timer}}
  end

  def handle_call({:rewind_files, _}, _from, %{state: s} = state) do
    {:reply, {:error, {:invalid_state, s}}, state}
  end

  def handle_call(:interrupt, _from, %{state: :streaming} = state) do
    interrupt_msg = %{type: "interrupt"}
    Subprocess.send_message(state.subprocess, interrupt_msg)

    if state.active_caller && is_pid(state.active_caller) do
      send(state.active_caller, {:client_exit, :interrupted})
    end

    {:reply, :ok, %{state | state: :connected, active_caller: nil}}
  end

  def handle_call(:interrupt, _from, state) do
    {:reply, {:error, {:invalid_state, state.state}}, state}
  end

  def handle_call({:set_model, model}, _from, %{state: :connected} = state) do
    control_msg = %{
      type: "control_request",
      request_id: ClaudeSDK.generate_request_id(),
      request: %{subtype: "set_model", model: model}
    }

    Subprocess.send_message(state.subprocess, control_msg)
    {:reply, :ok, state}
  end

  def handle_call({:set_model, _model}, _from, %{state: s} = state) do
    {:reply, {:error, {:invalid_state, s}}, state}
  end

  def handle_call({:set_permission_mode, mode}, _from, %{state: :connected} = state) do
    control_msg = %{
      type: "control_request",
      request_id: ClaudeSDK.generate_request_id(),
      request: %{subtype: "set_permission_mode", mode: to_string(mode)}
    }

    Subprocess.send_message(state.subprocess, control_msg)
    {:reply, :ok, state}
  end

  def handle_call({:set_permission_mode, _mode}, _from, %{state: s} = state) do
    {:reply, {:error, {:invalid_state, s}}, state}
  end

  def handle_call(:get_mcp_status, from, %{state: :connected} = state) do
    request_id = ClaudeSDK.generate_request_id()

    control_msg = %{
      type: "control_request",
      request_id: request_id,
      request: %{subtype: "get_mcp_status"}
    }

    Subprocess.send_message(state.subprocess, control_msg)

    timer = Process.send_after(self(), :control_timeout, @default_control_timeout)

    {:noreply,
     %{state | state: :awaiting_control_response, active_caller: from, control_timer: timer}}
  end

  def handle_call(:get_mcp_status, _from, %{state: s} = state) do
    {:reply, {:error, {:invalid_state, s}}, state}
  end

  def handle_call(:get_server_info, from, %{state: :connected} = state) do
    request_id = ClaudeSDK.generate_request_id()

    control_msg = %{
      type: "control_request",
      request_id: request_id,
      request: %{subtype: "get_server_info"}
    }

    Subprocess.send_message(state.subprocess, control_msg)

    timer = Process.send_after(self(), :control_timeout, @default_control_timeout)

    {:noreply,
     %{state | state: :awaiting_control_response, active_caller: from, control_timer: timer}}
  end

  def handle_call(:get_server_info, _from, %{state: s} = state) do
    {:reply, {:error, {:invalid_state, s}}, state}
  end

  def handle_call({:reconnect_mcp_server, server_name}, from, %{state: :connected} = state) do
    request_id = ClaudeSDK.generate_request_id()

    control_msg = %{
      type: "control_request",
      request_id: request_id,
      request: %{subtype: "reconnect_mcp_server", server_name: server_name}
    }

    Subprocess.send_message(state.subprocess, control_msg)

    timer = Process.send_after(self(), :control_timeout, @default_control_timeout)

    {:noreply,
     %{state | state: :awaiting_control_response, active_caller: from, control_timer: timer}}
  end

  def handle_call({:reconnect_mcp_server, _}, _from, %{state: s} = state) do
    {:reply, {:error, {:invalid_state, s}}, state}
  end

  def handle_call({:toggle_mcp_server, server_name, enabled}, from, %{state: :connected} = state) do
    request_id = ClaudeSDK.generate_request_id()

    control_msg = %{
      type: "control_request",
      request_id: request_id,
      request: %{subtype: "toggle_mcp_server", server_name: server_name, enabled: enabled}
    }

    Subprocess.send_message(state.subprocess, control_msg)

    timer = Process.send_after(self(), :control_timeout, @default_control_timeout)

    {:noreply,
     %{state | state: :awaiting_control_response, active_caller: from, control_timer: timer}}
  end

  def handle_call({:toggle_mcp_server, _, _}, _from, %{state: s} = state) do
    {:reply, {:error, {:invalid_state, s}}, state}
  end

  @impl true
  def handle_info({:claude_message, %{"type" => "control_request"} = raw}, state) do
    case ControlRouter.dispatch(raw, state.control_handlers) do
      {:handled, response} ->
        Subprocess.send_message(state.subprocess, response)
        {:noreply, state}

      {:unhandled, _} ->
        maybe_forward_to_caller(raw, state)
        {:noreply, state}
    end
  end

  def handle_info(
        {:claude_message, %{"type" => "control_response"} = raw},
        %{state: :awaiting_rewind} = state
      ) do
    cancel_control_timer(state)
    GenServer.reply(state.active_caller, parse_rewind_response(raw))
    {:noreply, %{state | state: :connected, active_caller: nil, control_timer: nil}}
  end

  def handle_info(
        {:claude_message, %{"type" => "control_response"} = raw},
        %{state: :awaiting_control_response} = state
      ) do
    cancel_control_timer(state)
    response = raw["response"] || %{}
    GenServer.reply(state.active_caller, {:ok, response})
    {:noreply, %{state | state: :connected, active_caller: nil, control_timer: nil}}
  end

  def handle_info({:claude_message, %{"type" => "result"} = raw}, %{state: :streaming} = state) do
    session_id = raw["session_id"] || state.session_id

    if state.active_caller do
      send(state.active_caller, {:client_message, raw})
    end

    {:noreply, %{state | state: :connected, session_id: session_id}}
  end

  def handle_info({:claude_message, raw}, %{state: :streaming} = state) do
    if state.active_caller do
      send(state.active_caller, {:client_message, raw})
    end

    {:noreply, state}
  end

  def handle_info({:claude_message, _raw}, state) do
    {:noreply, state}
  end

  def handle_info({:claude_exit, reason}, state) do
    cancel_control_timer(state)
    notify_caller_of_exit(state.active_caller, state.state, reason)

    {:noreply,
     %{state | state: :disconnected, subprocess: nil, active_caller: nil, control_timer: nil}}
  end

  def handle_info(:control_timeout, %{state: awaiting} = state)
      when awaiting in [:awaiting_rewind, :awaiting_control_response] do
    GenServer.reply(state.active_caller, {:error, :control_timeout})
    {:noreply, %{state | state: :connected, active_caller: nil, control_timer: nil}}
  end

  def handle_info(:control_timeout, state) do
    # Timer fired after response already arrived; ignore
    {:noreply, state}
  end

  def handle_info({:EXIT, _pid, _reason}, state) do
    # Subprocess exited — already handled via {:claude_exit, _} messages
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.debug("Client received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    cancel_control_timer(state)

    if is_pid(state.subprocess) do
      safe_stop(state.subprocess)
    end

    :ok
  end

  # Private

  defp do_connect(state) do
    opts = state.options

    case Options.validate(opts) do
      :ok -> do_connect_validated(state)
      {:error, reason} -> {:error, {:invalid_options, reason}}
    end
  end

  defp do_connect_validated(state) do
    opts = state.options

    mcp_tool_index =
      case opts.mcp_servers do
        [] -> %{}
        nil -> %{}
        servers -> ClaudeSDK.MCP.Server.build_tool_index(servers)
      end

    handler_opts = %{
      can_use_tool: opts.can_use_tool,
      mcp_tool_index: mcp_tool_index
    }

    control_handlers = ControlRouter.build_handlers(handler_opts)

    case Subprocess.start_link(caller: self(), options: opts) do
      {:ok, pid} ->
        init_request = %{
          type: "control_request",
          request_id: ClaudeSDK.generate_request_id(),
          request: %{
            subtype: "initialize",
            hooks: opts.hooks,
            agents: normalize_agents(opts.agents)
          }
        }

        Subprocess.send_message(pid, init_request)

        init_timeout = opts.init_timeout_ms || @default_init_timeout

        case wait_for_init(init_timeout) do
          :ok ->
            {:ok,
             %{state | state: :connected, subprocess: pid, control_handlers: control_handlers}}

          {:error, reason} ->
            safe_stop(pid)
            {:error, reason}
        end

      {:error, %ClaudeSDK.CLINotFoundError{} = e} ->
        {:error, e}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp wait_for_init(timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    wait_for_init_loop(deadline)
  end

  defp wait_for_init_loop(deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:claude_message, %{"type" => "control_response"}} ->
        :ok

      {:claude_message, %{"type" => _}} ->
        # Skip non-control_response messages (system, etc.)
        wait_for_init_loop(deadline)

      {:claude_exit, reason} ->
        {:error, {:cli_exited, reason}}
    after
      remaining -> {:error, :init_timeout}
    end
  end

  defp start_query(client, prompt) do
    case GenServer.call(client, {:start_query, prompt, self()}) do
      {:ok, message_timeout} -> {:streaming, message_timeout, client}
      {:error, reason} -> raise ClaudeSDK.QueryError, reason: reason
    end
  end

  defp receive_client_messages(:halt, _client), do: {:halt, :done}

  defp receive_client_messages({:streaming, message_timeout, client}, _client) do
    receive do
      {:client_message, raw} ->
        case ClaudeSDK.MessageParser.parse(raw) do
          {:ok, %ClaudeSDK.Types.ResultMessage{} = msg} ->
            {[msg], :halt}

          {:ok, msg} ->
            {[msg], {:streaming, message_timeout, client}}

          {:error, _} ->
            {[], {:streaming, message_timeout, client}}
        end

      {:client_exit, _reason} ->
        {:halt, :done}
    after
      message_timeout ->
        {:halt, :timeout}
    end
  end

  defp finish_query(client) do
    try do
      GenServer.call(client, :finish_query, 5_000)
    catch
      :exit, _ -> :ok
    end
  end

  defp maybe_forward_to_caller(raw, %{active_caller: caller}) when is_pid(caller) do
    send(caller, {:client_message, raw})
  end

  defp maybe_forward_to_caller(_raw, _state), do: :ok

  defp parse_rewind_response(%{"response" => %{"success" => true}}), do: :ok
  defp parse_rewind_response(%{"response" => %{"error" => error}}), do: {:error, error}
  defp parse_rewind_response(_), do: :ok

  defp cancel_control_timer(%{control_timer: ref}) when is_reference(ref) do
    Process.cancel_timer(ref)
    # Flush the timeout message if it already arrived
    receive do
      :control_timeout -> :ok
    after
      0 -> :ok
    end
  end

  defp cancel_control_timer(_state), do: :ok

  # Notify the active caller about subprocess exit, handling both
  # pid callers (streaming) and GenServer.reply tuples (awaiting states).
  defp safe_stop(pid) do
    if Process.alive?(pid), do: Subprocess.stop(pid)
  catch
    :exit, _ -> :ok
  end

  defp notify_caller_of_exit(nil, _state, _reason), do: :ok

  defp notify_caller_of_exit(caller, _state, reason) when is_pid(caller) do
    send(caller, {:client_exit, reason})
  rescue
    ArgumentError -> :ok
  end

  defp notify_caller_of_exit(caller, state, reason)
       when state in [:awaiting_rewind, :awaiting_control_response] do
    GenServer.reply(caller, {:error, {:cli_exited, reason}})
  rescue
    ArgumentError -> :ok
  end

  defp notify_caller_of_exit(caller, state, reason) do
    Logger.warning(
      "Unexpected caller state in notify_caller_of_exit: " <>
        "caller=#{inspect(caller)}, state=#{inspect(state)}, reason=#{inspect(reason)}"
    )

    :ok
  end

  defp normalize_agents(agents) when is_list(agents) do
    Enum.map(agents, fn
      %ClaudeSDK.Types.AgentDefinition{} = agent ->
        ClaudeSDK.Types.AgentDefinition.to_map(agent)

      agent when is_map(agent) ->
        agent
    end)
  end

  defp normalize_agents(agents) when is_map(agents), do: agents
  defp normalize_agents(_), do: %{}
end
