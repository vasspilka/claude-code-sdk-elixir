defmodule ClaudeSDK.Transport.LineBuffer do
  @moduledoc """
  Accumulates partial data from a Port and extracts complete JSON messages.

  This is an internal module used by `ClaudeSDK.Transport.Subprocess`.
  You do not need to use it directly.

  The Claude CLI sends newline-delimited JSON (NDJSON). Data may arrive in
  partial chunks, so we buffer until we have complete lines, then attempt
  JSON parsing on each.
  """

  require Logger

  # 10 MB — generous limit to catch runaway output without rejecting large tool results
  @max_buffer_bytes 10_485_760

  @type t :: %__MODULE__{buffer: String.t()}

  defstruct buffer: ""

  @doc "Create a new empty line buffer."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Accumulate a partial chunk (from a Port `:noeol` message).

  Returns `{:ok, updated_buffer}` on success, or `{:error, :buffer_overflow}`
  if the accumulated data exceeds the 10MB limit. On overflow the buffer is
  reset (the in-progress message is lost) and an error-level log is emitted.
  """
  @spec accumulate(t(), String.t()) :: {:ok, t()} | {:error, :buffer_overflow}
  def accumulate(%__MODULE__{buffer: buf}, chunk) when is_binary(chunk) do
    full = buf <> chunk

    if byte_size(full) > @max_buffer_bytes do
      Logger.error(
        "LineBuffer exceeded #{div(@max_buffer_bytes, 1_048_576)}MB limit " <>
          "(#{byte_size(full)} bytes), discarding buffer — data has been lost"
      )

      {:error, :buffer_overflow}
    else
      {:ok, %__MODULE__{buffer: full}}
    end
  end

  @doc """
  Flush the buffer with the final `:eol` remainder and parse the complete line.

  Concatenates any buffered partial data with the `:eol` remainder, attempts
  JSON parsing, and resets the buffer.

  Returns `{new_buffer, {:ok, parsed_map} | {:error, reason}}`.
  """
  @spec flush(t(), String.t()) :: {t(), {:ok, map()} | {:error, term()}}
  def flush(%__MODULE__{buffer: buf}, eol_data) when is_binary(eol_data) do
    full_line = if buf == "", do: eol_data, else: buf <> eol_data
    {new(), parse_line(full_line)}
  end

  @doc """
  Append data to the buffer and extract any complete JSON messages.

  Returns `{updated_buffer, parsed_messages}` where `parsed_messages` is a
  list of decoded maps (in order received).

  Lines that are not valid JSON are logged and skipped.
  """
  @spec append(t(), String.t()) :: {t(), [map()]}
  def append(%__MODULE__{buffer: buf} = _state, data) when is_binary(data) do
    full = buf <> data

    if byte_size(full) > @max_buffer_bytes do
      Logger.error(
        "LineBuffer exceeded #{div(@max_buffer_bytes, 1_048_576)}MB limit " <>
          "(#{byte_size(full)} bytes), discarding buffer — data has been lost"
      )

      {%__MODULE__{buffer: ""}, []}
    else
      {remaining, messages} = extract_lines(full)
      {%__MODULE__{buffer: remaining}, messages}
    end
  end

  @doc """
  Parse a single complete line as JSON.

  Returns `{:ok, map}` or `{:error, reason}`.
  """
  @spec parse_line(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_line(line) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" -> {:error, :empty}
      byte_size(trimmed) > @max_buffer_bytes -> {:error, :line_too_large}
      true -> Jason.decode(trimmed)
    end
  end

  defp extract_lines(data) do
    extract_lines(data, [])
  end

  defp extract_lines(data, acc) do
    case String.split(data, "\n", parts: 2) do
      [only] ->
        # No newline found — everything stays in buffer
        {only, Enum.reverse(acc)}

      [line, rest] ->
        case parse_line(line) do
          {:ok, parsed} ->
            extract_lines(rest, [parsed | acc])

          {:error, _} ->
            # Skip non-JSON lines (e.g. stderr leaking, empty lines)
            extract_lines(rest, acc)
        end
    end
  end
end
