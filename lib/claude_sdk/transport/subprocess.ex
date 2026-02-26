defmodule ClaudeSDK.Transport.Subprocess do
  @moduledoc """
  GenServer wrapping an OS Port for the Claude CLI subprocess.

  Spawns the CLI, sends JSON messages via stdin, receives JSON responses
  via stdout, parses them, and forwards to the caller process.
  """

  use GenServer

  alias ClaudeSDK.Transport.{CLIDiscovery, CommandBuilder, LineBuffer}
  alias ClaudeSDK.Types.Options

  require Logger

  defstruct [:port, :caller, :buffer, :cli_path, :options]

  # Client API

  @doc """
  Start the subprocess GenServer.

  Options:
  - `:caller` — pid to send parsed messages to (default: self())
  - `:options` — `%Options{}` struct
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Send a map as a JSON line to the CLI's stdin."
  @spec send_message(GenServer.server(), map()) :: :ok
  def send_message(server, message) when is_map(message) do
    GenServer.call(server, {:send, message})
  end

  @doc "Gracefully stop the subprocess."
  @spec stop(GenServer.server()) :: :ok
  def stop(server) do
    GenServer.stop(server, :normal)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    caller = Keyword.get(opts, :caller, self())
    options = Keyword.get(opts, :options, %Options{})

    cli_path = CLIDiscovery.find_cli!(options.cli_path)
    args = CommandBuilder.build_args(options)
    env = CommandBuilder.build_env(options)

    # Erlang's open_port expects charlists for env keys/values and cd path
    charlist_env = Enum.map(env, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)
    cd = String.to_charlist(options.cwd || File.cwd!())

    port_opts = [
      :binary,
      :exit_status,
      {:line, 1_048_576},
      {:args, args},
      {:env, charlist_env},
      {:cd, cd}
    ]

    port = Port.open({:spawn_executable, cli_path}, port_opts)

    state = %__MODULE__{
      port: port,
      caller: caller,
      buffer: LineBuffer.new(),
      cli_path: cli_path,
      options: options
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:send, message}, _from, %{port: port} = state) do
    json = Jason.encode!(message) <> "\n"
    Port.command(port, json)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    case LineBuffer.parse_line(line) do
      {:ok, parsed} ->
        send(state.caller, {:claude_message, parsed})
        {:noreply, state}

      {:error, _} ->
        Logger.debug("Skipping non-JSON line from CLI: #{inspect(line)}")
        {:noreply, state}
    end
  end

  def handle_info({port, {:data, {:noeol, chunk}}}, %{port: port} = state) do
    # Partial line — accumulate in buffer
    {new_buffer, messages} = LineBuffer.append(state.buffer, chunk)

    for msg <- messages do
      send(state.caller, {:claude_message, msg})
    end

    {:noreply, %{state | buffer: new_buffer}}
  end

  def handle_info({port, {:exit_status, 0}}, %{port: port} = state) do
    send(state.caller, {:claude_exit, :normal})
    {:stop, :normal, state}
  end

  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    send(state.caller, {:claude_exit, {:error, code}})
    {:stop, {:cli_exit, code}, state}
  end

  def handle_info(msg, state) do
    Logger.debug("Subprocess received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{port: port}) do
    if Port.info(port) != nil do
      Port.close(port)
    end

    :ok
  rescue
    _ -> :ok
  end
end
