defmodule ClaudeSDK.Transport.LineBuffer do
  @moduledoc """
  Accumulates partial data from a Port and extracts complete JSON messages.

  This is an internal module used by `ClaudeSDK.Transport.Subprocess`.
  You do not need to use it directly.

  The Claude CLI sends newline-delimited JSON (NDJSON). Data may arrive in
  partial chunks, so we buffer until we have complete lines, then attempt
  JSON parsing on each.
  """

  @type t :: %__MODULE__{buffer: String.t()}

  defstruct buffer: ""

  @doc "Create a new empty line buffer."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Append data to the buffer and extract any complete JSON messages.

  Returns `{updated_buffer, parsed_messages}` where `parsed_messages` is a
  list of decoded maps (in order received).

  Lines that are not valid JSON are logged and skipped.
  """
  @spec append(t(), String.t()) :: {t(), [map()]}
  def append(%__MODULE__{buffer: buf} = _state, data) when is_binary(data) do
    full = buf <> data
    {remaining, messages} = extract_lines(full)
    {%__MODULE__{buffer: remaining}, messages}
  end

  @doc """
  Parse a single complete line as JSON.

  Returns `{:ok, map}` or `{:error, reason}`.
  """
  @spec parse_line(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_line(line) do
    trimmed = String.trim(line)

    if trimmed == "" do
      {:error, :empty}
    else
      Jason.decode(trimmed)
    end
  end

  defp extract_lines(data) do
    case String.split(data, "\n", parts: 2) do
      [only] ->
        # No newline found — everything stays in buffer
        {only, []}

      [line, rest] ->
        case parse_line(line) do
          {:ok, parsed} ->
            {remaining, more} = extract_lines(rest)
            {remaining, [parsed | more]}

          {:error, _} ->
            # Skip non-JSON lines (e.g. stderr leaking, empty lines)
            extract_lines(rest)
        end
    end
  end
end
