defmodule ClaudeSDK.Transport do
  @moduledoc """
  Behaviour for Claude CLI transport implementations.

  The transport is responsible for spawning a Claude CLI process (or equivalent),
  sending JSON messages to it, and forwarding parsed responses back to the caller
  process.

  The default implementation is `ClaudeSDK.Transport.Subprocess`, which uses an
  Erlang Port to communicate with the CLI over stdin/stdout. Custom transports
  can be used for testing or alternative communication channels.

  ## Message Contract

  Implementations must send the following messages to the `:caller` process
  (provided via the `:caller` keyword in `start_link/1` / `start/1`):

  - `{:claude_message, map()}` — a parsed JSON message from the CLI
  - `{:claude_exit, :normal | {:error, integer()}}` — the CLI process exited

  ## Options

  Both `start_link/1` and `start/1` receive a keyword list with:

  - `:caller` — pid to send messages to (default: `self()`)
  - `:options` — `%ClaudeSDK.Types.Options{}` struct with configuration
  """

  @type start_opts :: [
          caller: pid(),
          options: ClaudeSDK.Types.Options.t()
        ]

  @doc "Start the transport linked to the calling process."
  @callback start_link(start_opts()) :: GenServer.on_start()

  @doc "Start the transport without linking to the calling process."
  @callback start(start_opts()) :: GenServer.on_start()

  @doc "Send a JSON-encodable map to the CLI's stdin."
  @callback send_message(GenServer.server(), map()) :: :ok

  @doc "Gracefully stop the transport."
  @callback stop(GenServer.server()) :: :ok
end
