defmodule ClaudeSDK.Client do
  @moduledoc """
  Stateful multi-turn client for the Claude CLI.

  Unlike `ClaudeSDK.query/2` which spawns a subprocess per call,
  the Client keeps a single subprocess alive across multiple queries,
  enabling multi-turn conversations with session persistence.

  ## Usage

      {:ok, client} = ClaudeSDK.Client.start_link(options: %Options{
        permission_mode: :bypass_permissions
      })

      # First turn
      ClaudeSDK.Client.query(client, "What is 2+2?")
      |> Enum.each(&IO.inspect/1)

      # Second turn (same session)
      ClaudeSDK.Client.query(client, "Now multiply that by 3")
      |> Enum.each(&IO.inspect/1)

      ClaudeSDK.Client.close(client)
  """

  use GenServer

  alias ClaudeSDK.ControlRouter
  alias ClaudeSDK.Transport.Subprocess
  alias ClaudeSDK.Types.Options

  require Logger

  @init_timeout 30_000

  defstruct [
    :options,
    :subprocess,
    :control_handlers,
    :session_id,
    :active_caller,
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
    GenServer.call(client, :connect, @init_timeout + 5_000)
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
    GenServer.call(client, {:rewind_files, user_message_id}, @init_timeout)
  end

  @doc """
  Close the client and stop the subprocess.
  """
  @spec close(GenServer.server()) :: :ok
  def close(client) do
    GenServer.stop(client, :normal)
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
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

    {:reply, :ok, %{state | state: :streaming, active_caller: caller}}
  end

  def handle_call({:start_query, _prompt, _caller}, _from, %{state: s} = state) do
    {:reply, {:error, {:invalid_state, s}}, state}
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

    {:noreply, %{state | state: :awaiting_rewind, active_caller: from}}
  end

  def handle_call({:rewind_files, _}, _from, %{state: s} = state) do
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
    GenServer.reply(state.active_caller, parse_rewind_response(raw))
    {:noreply, %{state | state: :connected, active_caller: nil}}
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
    if state.active_caller && is_pid(state.active_caller) do
      send(state.active_caller, {:client_exit, reason})
    end

    {:noreply, %{state | state: :disconnected, subprocess: nil}}
  end

  def handle_info(msg, state) do
    Logger.debug("Client received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{subprocess: pid}) when is_pid(pid) do
    if Process.alive?(pid) do
      Subprocess.stop(pid)
    end

    :ok
  rescue
    _ -> :ok
  end

  def terminate(_reason, _state), do: :ok

  # Private

  defp do_connect(state) do
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
            agents: opts.agents
          }
        }

        Subprocess.send_message(pid, init_request)

        case wait_for_init() do
          :ok ->
            {:ok,
             %{state | state: :connected, subprocess: pid, control_handlers: control_handlers}}

          {:error, reason} ->
            Subprocess.stop(pid)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp wait_for_init do
    receive do
      {:claude_message, %{"type" => "control_response"}} ->
        :ok

      {:claude_message, %{"type" => "system"}} ->
        receive do
          {:claude_message, %{"type" => "control_response"}} -> :ok
        after
          @init_timeout -> {:error, :init_timeout}
        end
    after
      @init_timeout -> {:error, :init_timeout}
    end
  end

  defp start_query(client, prompt) do
    case GenServer.call(client, {:start_query, prompt, self()}) do
      :ok -> :streaming
      {:error, reason} -> raise "Failed to start query: #{inspect(reason)}"
    end
  end

  defp receive_client_messages(:halt, _client), do: {:halt, :done}

  defp receive_client_messages(:streaming, _client) do
    receive do
      {:client_message, raw} ->
        case ClaudeSDK.MessageParser.parse(raw) do
          {:ok, %ClaudeSDK.Types.ResultMessage{} = msg} ->
            {[msg], :halt}

          {:ok, msg} ->
            {[msg], :streaming}

          {:error, _} ->
            {[], :streaming}
        end

      {:client_exit, _reason} ->
        {:halt, :done}
    after
      120_000 ->
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
end
