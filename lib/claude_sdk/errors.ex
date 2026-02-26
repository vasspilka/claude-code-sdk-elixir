defmodule ClaudeSDK.CLINotFoundError do
  @moduledoc "Raised when the Claude CLI binary cannot be found."
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
  @moduledoc "Raised when subprocess communication fails."
  defexception [:message, :reason]

  @impl true
  def exception(opts) do
    reason = Keyword.get(opts, :reason, :unknown)
    message = Keyword.get(opts, :message, "Transport error: #{inspect(reason)}")
    %__MODULE__{message: message, reason: reason}
  end
end

defmodule ClaudeSDK.ProtocolError do
  @moduledoc "Raised when the CLI sends a malformed or unexpected message."
  defexception [:message, :raw_data]

  @impl true
  def exception(opts) do
    raw_data = Keyword.get(opts, :raw_data)
    message = Keyword.get(opts, :message, "Protocol error: unexpected message format")
    %__MODULE__{message: message, raw_data: raw_data}
  end
end

defmodule ClaudeSDK.TimeoutError do
  @moduledoc "Raised when a CLI operation times out."
  defexception [:message, :timeout_ms]

  @impl true
  def exception(opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms)
    message = Keyword.get(opts, :message, "Operation timed out after #{timeout_ms}ms")
    %__MODULE__{message: message, timeout_ms: timeout_ms}
  end
end
