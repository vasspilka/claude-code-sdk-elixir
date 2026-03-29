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

  @behaviour ClaudeSDK.Transport

  use GenServer

  alias ClaudeSDK.Transport.{CLIDiscovery, CommandBuilder, LineBuffer}
  alias ClaudeSDK.Types.Options

  require Logger

  defstruct [:port, :caller, :caller_monitor, :buffer, :cli_path, :options]

  # Client API

  @doc """
  Start the subprocess GenServer.

  Options:
  - `:caller` — pid to send parsed messages to (default: self())
  - `:options` — `%Options{}` struct
  """
  @impl ClaudeSDK.Transport
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl ClaudeSDK.Transport
  @doc "Start the subprocess without linking to the caller."
  @spec start(keyword()) :: GenServer.on_start()
  def start(opts) do
    GenServer.start(__MODULE__, opts)
  end

  @impl ClaudeSDK.Transport
  @doc "Send a map as a JSON line to the CLI's stdin."
  @spec send_message(GenServer.server(), map()) :: :ok
  def send_message(server, message) when is_map(message) do
    GenServer.cast(server, {:send, message})
  end

  @impl ClaudeSDK.Transport
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
      {:error, e} ->
        {:stop, e}

      cli_path ->
        do_init(cli_path, caller, options)
    end
  end

  defp do_init(cli_path, caller, options) do
    # Fire-and-forget version check — don't block subprocess startup
    Task.start(fn -> check_cli_version(cli_path) end)

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

      # Monitor the caller so we stop if it dies (prevents orphaned subprocesses)
      caller_monitor = Process.monitor(caller)

      state = %__MODULE__{
        port: port,
        caller: caller,
        caller_monitor: caller_monitor,
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

  @minimum_cli_version "2.0.0"

  defp check_cli_version(cli_path) do
    case CLIDiscovery.version(cli_path) do
      {:ok, version_string} -> compare_version(version_string)
      _ -> Logger.debug("Could not determine Claude CLI version")
    end
  rescue
    _ -> Logger.debug("Could not determine Claude CLI version")
  end

  defp compare_version(version_string) do
    version =
      version_string
      |> String.trim_leading("v")
      |> String.split(".")
      |> Enum.take(3)
      |> Enum.join(".")

    if Version.compare(version, @minimum_cli_version) == :lt do
      Logger.warning(
        "Claude CLI version #{version_string} is below minimum #{@minimum_cli_version}. " <>
          "Some features may not work. Run `npm install -g @anthropic-ai/claude-code` to update."
      )
    end
  rescue
    _ -> Logger.debug("Could not parse Claude CLI version: #{version_string}")
  end

  @impl true
  def handle_cast({:send, message}, %{port: port} = state) do
    json = Jason.encode!(message) <> "\n"

    if Port.command(port, json) do
      {:noreply, state}
    else
      Logger.warning("Port.command returned false — port is closed")
      send(state.caller, {:claude_exit, {:error, :port_closed}})
      {:stop, :normal, state}
    end
  rescue
    ArgumentError ->
      Logger.warning("Port.command raised — port is closed")
      send(state.caller, {:claude_exit, {:error, :port_closed}})
      {:stop, :normal, state}
  end

  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    # When a line exceeds the Port's {:line, N} limit, it arrives as
    # one or more {:noeol, chunk} messages followed by a final {:eol, remainder}.
    # flush/2 concatenates any buffered noeol chunks with this eol remainder.
    {new_buffer, result} = LineBuffer.flush(state.buffer, line)

    case result do
      {:ok, parsed} ->
        send(state.caller, {:claude_message, parsed})

      {:error, _} ->
        full_line = if state.buffer.buffer == "", do: line, else: state.buffer.buffer <> line

        Logger.debug(
          "Skipping non-JSON line from CLI: #{inspect(String.slice(full_line, 0, 200))}"
        )
    end

    {:noreply, %{state | buffer: new_buffer}}
  end

  def handle_info({port, {:data, {:noeol, chunk}}}, %{port: port} = state) do
    # Partial line — accumulate in buffer until the final :eol arrives
    case LineBuffer.accumulate(state.buffer, chunk) do
      {:ok, new_buffer} ->
        {:noreply, %{state | buffer: new_buffer}}

      {:error, :buffer_overflow} ->
        # Buffer exceeded 10MB — the in-progress message is lost.
        # Reset buffer and continue; subsequent messages can still be processed.
        {:noreply, %{state | buffer: LineBuffer.new()}}
    end
  end

  def handle_info({port, {:exit_status, 0}}, %{port: port} = state) do
    send(state.caller, {:claude_exit, :normal})
    {:stop, :normal, state}
  end

  def handle_info({port, {:exit_status, code}}, %{port: port} = state) do
    error = ClaudeSDK.ProcessExitError.exception(exit_code: code)
    send(state.caller, {:claude_exit, {:error, error}})
    {:stop, {:cli_exit, code}, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{caller_monitor: ref} = state) do
    # Caller process died — stop to prevent orphaned subprocess
    {:stop, :normal, state}
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
