defmodule ClaudeSDK.Transport.Subprocess do
  @moduledoc """
  GenServer wrapping an OS Port for the Claude CLI subprocess.

  This is an internal transport module used by `ClaudeSDK.query/2` and
  `ClaudeSDK.Client`. You do not need to use it directly.

  Spawns the CLI, sends JSON messages via stdin, receives JSON responses
  via stdout, parses them, and forwards to the caller process.

  ## Stderr Handling

  Erlang ports with `{:line, N}` only capture stdout. Stderr output from the
  CLI is not captured. To capture CLI logs, use the `--log-file` option via
  `Options.extra_args: ["--log-file", "/path/to/log"]`, or provide a shell
  wrapper that redirects stderr.
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

  @doc "Start the subprocess without linking to the caller."
  @spec start(keyword()) :: GenServer.on_start()
  def start(opts) do
    GenServer.start(__MODULE__, opts)
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

    cli_path =
      try do
        CLIDiscovery.find_cli!(options.cli_path)
      rescue
        e in ClaudeSDK.CLINotFoundError -> {:error, e}
      end

    case cli_path do
      {:error, e} -> {:stop, e}
      cli_path -> do_init(cli_path, caller, options)
    end
  end

  defp do_init(cli_path, caller, options) do
    args = CommandBuilder.build_args(options)
    env = CommandBuilder.build_env(options)

    # Erlang's open_port expects charlists for env keys/values and cd path.
    # {Key, false} unsets an env var in the subprocess.
    charlist_env =
      Enum.map(env, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    # Always unset CLAUDECODE to allow the SDK to spawn the CLI from within
    # a Claude Code session (e.g. when developing/testing the SDK itself).
    charlist_env = [{~c"CLAUDECODE", false} | charlist_env]

    cd = String.to_charlist(options.cwd || File.cwd!())

    port_opts = [
      :binary,
      :exit_status,
      {:line, 1_048_576},
      {:args, args},
      {:env, charlist_env},
      {:cd, cd}
    ]

    try do
      port = Port.open({:spawn_executable, cli_path}, port_opts)

      state = %__MODULE__{
        port: port,
        caller: caller,
        buffer: LineBuffer.new(),
        cli_path: cli_path,
        options: options
      }

      {:ok, state}
    rescue
      e in [ErlangError, ArgumentError, SystemLimitError] ->
        {:stop, Exception.message(e)}
    end
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
    ArgumentError -> :ok
  end
end
