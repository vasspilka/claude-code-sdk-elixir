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

  ## Concurrency

  The Client does not support concurrent queries. Each Client instance processes
  one query at a time. Calling `query/2` while another query is streaming will
  return `{:error, {:invalid_state, :streaming}}`. For parallel workloads, use
  separate Client instances.

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
  alias ClaudeSDK.Internal
  alias ClaudeSDK.Transport.Subprocess
  alias ClaudeSDK.Types.Options

  require Logger

  @default_init_timeout 30_000

  defstruct [
    :options,
    :subprocess,
    :control_handlers,
    :session_id,
    :active_caller,
    :control_timer,
    :caller_monitor,
    :server_info,
    state: :disconnected,
    query_gen: 0
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

  Note: This is fire-and-forget — the request is sent but no acknowledgment
  is awaited. If the CLI rejects the model change, no error is returned.
  """
  @spec set_model(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def set_model(client, model) when is_binary(model) do
    GenServer.call(client, {:set_model, model})
  end

  @doc """
  Change the permission mode mid-session.

  Can only be called when the client is in `:connected` state (not streaming).

  Note: This is fire-and-forget — the request is sent but no acknowledgment
  is awaited. If the CLI rejects the mode change, no error is returned.
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
  Get CLI server info cached from the initialization handshake.

  Returns the server info map received during `connect/1`. Available in any
  state except `:disconnected`.
  """
  @spec get_server_info(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def get_server_info(client) do
    GenServer.call(client, :get_server_info)
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
  Add an MCP server to the running session.

  Accepts a server name and a config map (matching `McpServerConfig` structure).
  Can only be called when the client is in `:connected` state.
  """
  @spec add_mcp_server(GenServer.server(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def add_mcp_server(client, server_name, config)
      when is_binary(server_name) and is_map(config) do
    GenServer.call(client, {:add_mcp_server, server_name, config}, @default_init_timeout)
  end

  @doc """
  Remove an MCP server from the running session by name.

  Can only be called when the client is in `:connected` state.
  """
  @spec remove_mcp_server(GenServer.server(), String.t()) :: {:ok, map()} | {:error, term()}
  def remove_mcp_server(client, server_name) when is_binary(server_name) do
    GenServer.call(client, {:remove_mcp_server, server_name}, @default_init_timeout)
  end

  @doc """
  Check whether the client is connected and ready for queries.
  """
  @spec connected?(GenServer.server()) :: boolean()
  def connected?(client) do
    GenServer.call(client, :connected?)
  catch
    :exit, _ -> false
  end

  @doc """
  Stop a running subtask by its task ID.

  Can only be called when the client is in `:connected` state.
  """
  @spec stop_task(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def stop_task(client, task_id) when is_binary(task_id) do
    GenServer.call(client, {:stop_task, task_id})
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
    case start_link(opts) do
      {:ok, client} ->
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

      {:error, reason} ->
        raise ClaudeSDK.TransportError,
          reason: reason,
          message: "Failed to start client: #{inspect(reason)}"
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

  def handle_call(:connected?, _from, state) do
    {:reply, state.state == :connected, state}
  end

  def handle_call({:start_query, prompt, caller}, _from, %{state: :connected} = state) do
    user_message = %{
      type: "user",
      session_id: state.session_id || state.options.session_id,
      message: %{role: "user", content: prompt},
      parent_tool_use_id: nil
    }

    Subprocess.send_message(state.subprocess, user_message)

    new_gen = state.query_gen + 1
    message_timeout = state.options.message_timeout_ms
    monitor = if is_pid(caller), do: Process.monitor(caller)

    {:reply, {:ok, message_timeout, new_gen},
     %{
       state
       | state: :streaming,
         active_caller: caller,
         query_gen: new_gen,
         caller_monitor: monitor
     }}
  end

  def handle_call({:start_query, _prompt, _caller}, _from, %{state: s} = state) do
    {:reply, {:error, state_error(s)}, state}
  end

  def handle_call(:finish_query, _from, %{state: :streaming} = state) do
    demonitor_caller(state)
    {:reply, :ok, %{state | state: :connected, active_caller: nil, caller_monitor: nil}}
  end

  def handle_call(:finish_query, _from, state) do
    demonitor_caller(state)
    {:reply, :ok, %{state | active_caller: nil, caller_monitor: nil}}
  end

  def handle_call({:rewind_files, user_message_id}, from, %{state: :connected} = state) do
    request_id = Internal.generate_request_id()

    rewind_request = %{
      type: "control_request",
      request_id: request_id,
      request: %{
        subtype: "rewind_files",
        user_message_id: user_message_id
      }
    }

    Subprocess.send_message(state.subprocess, rewind_request)

    timer = Process.send_after(self(), :control_timeout, control_timeout(state))
    {:noreply, %{state | state: :awaiting_rewind, active_caller: from, control_timer: timer}}
  end

  def handle_call({:rewind_files, _}, _from, %{state: s} = state) do
    {:reply, {:error, state_error(s)}, state}
  end

  def handle_call(:interrupt, _from, %{state: :streaming} = state) do
    interrupt_msg = %{type: "interrupt"}
    Subprocess.send_message(state.subprocess, interrupt_msg)

    if state.active_caller && is_pid(state.active_caller) do
      send(state.active_caller, {:client_exit, state.query_gen, :interrupted})
    end

    demonitor_caller(state)
    {:reply, :ok, %{state | state: :connected, active_caller: nil, caller_monitor: nil}}
  end

  def handle_call(:interrupt, _from, state) do
    {:reply, {:error, state_error(state.state)}, state}
  end

  def handle_call({:stop_task, task_id}, _from, %{state: :connected} = state) do
    control_msg = %{
      type: "control_request",
      request_id: Internal.generate_request_id(),
      request: %{subtype: "stop_task", task_id: task_id}
    }

    Subprocess.send_message(state.subprocess, control_msg)
    {:reply, :ok, state}
  end

  def handle_call({:stop_task, _}, _from, %{state: s} = state) do
    {:reply, {:error, state_error(s)}, state}
  end

  def handle_call({:set_model, model}, _from, %{state: :connected} = state) do
    control_msg = %{
      type: "control_request",
      request_id: Internal.generate_request_id(),
      request: %{subtype: "set_model", model: model}
    }

    Subprocess.send_message(state.subprocess, control_msg)
    {:reply, :ok, state}
  end

  def handle_call({:set_model, _model}, _from, %{state: s} = state) do
    {:reply, {:error, state_error(s)}, state}
  end

  def handle_call({:set_permission_mode, mode}, _from, %{state: :connected} = state) do
    control_msg = %{
      type: "control_request",
      request_id: Internal.generate_request_id(),
      request: %{subtype: "set_permission_mode", mode: to_string(mode)}
    }

    Subprocess.send_message(state.subprocess, control_msg)
    {:reply, :ok, state}
  end

  def handle_call({:set_permission_mode, _mode}, _from, %{state: s} = state) do
    {:reply, {:error, state_error(s)}, state}
  end

  # -- Control request handlers (all follow the same send-and-await pattern) --

  def handle_call(:get_mcp_status, from, %{state: :connected} = state),
    do: send_control_and_await(%{subtype: "get_mcp_status"}, from, state)

  def handle_call(:get_mcp_status, _from, %{state: s} = state),
    do: {:reply, {:error, state_error(s)}, state}

  def handle_call(:get_server_info, _from, %{state: :disconnected} = state),
    do: {:reply, {:error, :not_connected}, state}

  def handle_call(:get_server_info, _from, state),
    do: {:reply, {:ok, state.server_info || %{}}, state}

  def handle_call({:reconnect_mcp_server, server_name}, from, %{state: :connected} = state),
    do:
      send_control_and_await(
        %{subtype: "reconnect_mcp_server", server_name: server_name},
        from,
        state
      )

  def handle_call({:reconnect_mcp_server, _}, _from, %{state: s} = state),
    do: {:reply, {:error, state_error(s)}, state}

  def handle_call({:toggle_mcp_server, server_name, enabled}, from, %{state: :connected} = state),
    do:
      send_control_and_await(
        %{subtype: "toggle_mcp_server", server_name: server_name, enabled: enabled},
        from,
        state
      )

  def handle_call({:toggle_mcp_server, _, _}, _from, %{state: s} = state),
    do: {:reply, {:error, state_error(s)}, state}

  def handle_call({:add_mcp_server, server_name, config}, from, %{state: :connected} = state),
    do:
      send_control_and_await(
        %{subtype: "add_mcp_server", server_name: server_name, config: config},
        from,
        state
      )

  def handle_call({:add_mcp_server, _, _}, _from, %{state: s} = state),
    do: {:reply, {:error, state_error(s)}, state}

  def handle_call({:remove_mcp_server, server_name}, from, %{state: :connected} = state),
    do:
      send_control_and_await(
        %{subtype: "remove_mcp_server", server_name: server_name},
        from,
        state
      )

  def handle_call({:remove_mcp_server, _}, _from, %{state: s} = state),
    do: {:reply, {:error, state_error(s)}, state}

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
    demonitor_caller(state)

    if state.active_caller do
      send(state.active_caller, {:client_message, state.query_gen, raw})
    end

    {:noreply, %{state | state: :connected, session_id: session_id, caller_monitor: nil}}
  end

  def handle_info({:claude_message, raw}, %{state: :streaming} = state) do
    if state.active_caller do
      send(state.active_caller, {:client_message, state.query_gen, raw})
    end

    {:noreply, state}
  end

  def handle_info({:claude_message, _raw}, state) do
    Logger.debug("Dropping message in #{state.state} state (no active stream)")
    {:noreply, state}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{caller_monitor: ref, state: :streaming} = state
      )
      when is_reference(ref) do
    # Stream consumer died — recover to :connected so the Client isn't stuck
    Logger.debug("Stream consumer process died, returning to :connected state")
    {:noreply, %{state | state: :connected, active_caller: nil, caller_monitor: nil}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # Stale monitor message after caller was already cleared; ignore
    {:noreply, state}
  end

  def handle_info({:claude_exit, reason}, state) do
    cancel_control_timer(state)
    demonitor_caller(state)
    notify_caller_of_exit(state.active_caller, state.state, reason, state.query_gen)

    {:noreply,
     %{
       state
       | state: :disconnected,
         subprocess: nil,
         active_caller: nil,
         control_timer: nil,
         caller_monitor: nil
     }}
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
      Internal.safe_stop_subprocess(state.subprocess)
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
    control_handlers = Internal.build_control_handlers(opts)

    case Subprocess.start_link(caller: self(), options: opts) do
      {:ok, pid} ->
        Subprocess.send_message(pid, Internal.build_init_request(opts))

        init_timeout = opts.init_timeout_ms

        case Internal.wait_for_init_response(init_timeout) do
          {:ok, server_info, _buffered_messages} ->
            {:ok,
             %{
               state
               | state: :connected,
                 subprocess: pid,
                 control_handlers: control_handlers,
                 server_info: server_info
             }}

          {:error, reason} ->
            Internal.safe_stop_subprocess(pid)
            {:error, reason}
        end

      {:error, %ClaudeSDK.CLINotFoundError{} = e} ->
        {:error, e}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_query(client, prompt) do
    case GenServer.call(client, {:start_query, prompt, self()}) do
      {:ok, message_timeout, gen} -> {:streaming, message_timeout, client, gen}
      {:error, reason} -> raise ClaudeSDK.QueryError, reason: reason
    end
  end

  defp receive_client_messages(:halt, _client), do: {:halt, :done}

  defp receive_client_messages({:streaming, message_timeout, client, gen}, _client) do
    receive do
      {:client_message, ^gen, raw} ->
        case ClaudeSDK.MessageParser.parse(raw) do
          {:ok, %ClaudeSDK.Types.ResultMessage{} = msg} ->
            {[msg], :halt}

          {:ok, msg} ->
            {[msg], {:streaming, message_timeout, client, gen}}

          {:error, _} ->
            {[], {:streaming, message_timeout, client, gen}}
        end

      {:client_exit, ^gen, _reason} ->
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

  defp state_error(:disconnected), do: :not_connected
  defp state_error(:connected), do: :not_streaming
  defp state_error(:streaming), do: :busy
  defp state_error(:awaiting_rewind), do: :busy
  defp state_error(:awaiting_control_response), do: :busy
  defp state_error(other), do: {:invalid_state, other}

  defp control_timeout(%{options: opts}) do
    opts.control_timeout_ms
  end

  defp maybe_forward_to_caller(raw, %{active_caller: caller, query_gen: gen})
       when is_pid(caller) do
    send(caller, {:client_message, gen, raw})
  end

  defp maybe_forward_to_caller(_raw, _state), do: :ok

  defp send_control_and_await(request_fields, from, state) do
    request_id = Internal.generate_request_id()

    control_msg = %{
      type: "control_request",
      request_id: request_id,
      request: request_fields
    }

    Subprocess.send_message(state.subprocess, control_msg)
    timer = Process.send_after(self(), :control_timeout, control_timeout(state))

    {:noreply,
     %{state | state: :awaiting_control_response, active_caller: from, control_timer: timer}}
  end

  defp parse_rewind_response(%{"response" => %{"success" => true}}), do: :ok
  defp parse_rewind_response(%{"response" => %{"error" => error}}), do: {:error, error}

  defp parse_rewind_response(other) do
    Logger.warning("Unexpected rewind response format: #{inspect(other)}")
    {:error, :unexpected_response}
  end

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

  defp demonitor_caller(%{caller_monitor: ref}) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
  end

  defp demonitor_caller(_state), do: :ok

  # Notify the active caller about subprocess exit, handling both
  # pid callers (streaming) and GenServer.reply tuples (awaiting states).
  defp notify_caller_of_exit(nil, _state, _reason, _gen), do: :ok

  defp notify_caller_of_exit(caller, _state, reason, gen) when is_pid(caller) do
    send(caller, {:client_exit, gen, reason})
  rescue
    ArgumentError -> :ok
  end

  defp notify_caller_of_exit(caller, state, reason, _gen)
       when state in [:awaiting_rewind, :awaiting_control_response] do
    GenServer.reply(caller, {:error, {:cli_exited, reason}})
  rescue
    ArgumentError -> :ok
  end

  defp notify_caller_of_exit(caller, state, reason, _gen) do
    Logger.warning(
      "Unexpected caller state in notify_caller_of_exit: " <>
        "caller=#{inspect(caller)}, state=#{inspect(state)}, reason=#{inspect(reason)}"
    )

    :ok
  end
end
