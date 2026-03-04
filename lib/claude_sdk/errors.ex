defmodule ClaudeSDK.CLINotFoundError do
  @moduledoc """
  Raised when the Claude CLI binary cannot be found.

  This typically means the CLI is not installed. Install it with:

      npm install -g @anthropic-ai/claude-code

  You can also set `cli_path` in `%Options{}` to point to a specific binary.

  ## Fields

  - `message` — Human-readable error message.
  """
  defexception [:message]

  @impl true
  def exception(opts) do
    path = Keyword.get(opts, :path)

    message =
      if path do
        "Claude CLI not found at #{path}. Install it with: npm install -g @anthropic-ai/claude-code"
      else
        "Claude CLI not found on PATH. Install it with: npm install -g @anthropic-ai/claude-code"
      end

    %__MODULE__{message: message}
  end
end

defmodule ClaudeSDK.TransportError do
  @moduledoc """
  Raised when subprocess communication fails.

  Covers failures in the Erlang Port layer: the subprocess crashed,
  stdin/stdout pipe broke, or the Port could not be opened.

  ## Fields

  - `message` — Human-readable error message.
  - `reason` — The underlying error term.
  """
  defexception [:message, :reason]

  @impl true
  def exception(opts) do
    reason = Keyword.get(opts, :reason, :unknown)
    message = Keyword.get(opts, :message, "Transport error: #{inspect(reason)}")
    %__MODULE__{message: message, reason: reason}
  end
end

defmodule ClaudeSDK.ProtocolError do
  @moduledoc """
  Raised when the CLI sends a malformed or unexpected message.

  This indicates a mismatch between the SDK and CLI protocol versions,
  or corrupted data on the NDJSON stream.

  ## Fields

  - `message` — Human-readable error message.
  - `raw_data` — The raw data that could not be parsed.
  """
  defexception [:message, :raw_data]

  @impl true
  def exception(opts) do
    raw_data = Keyword.get(opts, :raw_data)
    message = Keyword.get(opts, :message, "Protocol error: unexpected message format")
    %__MODULE__{message: message, raw_data: raw_data}
  end
end

defmodule ClaudeSDK.QueryError do
  @moduledoc """
  Raised when starting a query fails.

  This can happen when the Client is in an invalid state (e.g. not connected,
  already streaming) or the subprocess rejects the query.

  ## Fields

  - `message` — Human-readable error message.
  - `reason` — The underlying error term.
  """
  defexception [:message, :reason]

  @impl true
  def exception(opts) do
    reason = Keyword.get(opts, :reason, :unknown)
    message = Keyword.get(opts, :message, "Failed to start query: #{inspect(reason)}")
    %__MODULE__{message: message, reason: reason}
  end
end

defmodule ClaudeSDK.TimeoutError do
  @moduledoc """
  Raised when a CLI operation times out.

  The SDK enforces two timeouts: a 30-second initialization handshake timeout
  and a 120-second inactivity timeout during streaming.

  ## Fields

  - `message` — Human-readable error message.
  - `timeout_ms` — The timeout duration that was exceeded, in milliseconds.
  """
  defexception [:message, :timeout_ms]

  @impl true
  def exception(opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms)
    message = Keyword.get(opts, :message, "Operation timed out after #{timeout_ms}ms")
    %__MODULE__{message: message, timeout_ms: timeout_ms}
  end
end
