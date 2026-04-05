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

  # 10 MB — generous default to catch runaway output without rejecting large tool results
  @default_max_buffer_bytes 10_485_760

  @type t :: %__MODULE__{buffer: String.t(), max_bytes: pos_integer()}

  defstruct buffer: "", max_bytes: @default_max_buffer_bytes

  @doc "Create a new empty line buffer with a configurable byte cap."
  @spec new(pos_integer()) :: t()
  def new(max_bytes \\ @default_max_buffer_bytes) when is_integer(max_bytes) and max_bytes > 0,
    do: %__MODULE__{max_bytes: max_bytes}

  @doc "Returns the default max buffer size in bytes."
  @spec default_max_bytes() :: pos_integer()
  def default_max_bytes, do: @default_max_buffer_bytes

  @doc """
  Accumulate a partial chunk (from a Port `:noeol` message).

  Returns `{:ok, updated_buffer}` on success, or `{:error, :buffer_overflow}`
  if the accumulated data exceeds the buffer's `max_bytes` limit. On overflow
  the buffer is reset (the in-progress message is lost) and an error-level log
  is emitted.
  """
  @spec accumulate(t(), String.t()) :: {:ok, t()} | {:error, :buffer_overflow}
  def accumulate(%__MODULE__{buffer: buf, max_bytes: max_bytes} = state, chunk)
      when is_binary(chunk) do
    full = buf <> chunk

    if byte_size(full) > max_bytes do
      Logger.error(
        "LineBuffer exceeded #{format_mb(max_bytes)} limit " <>
          "(#{byte_size(full)} bytes), discarding buffer — data has been lost"
      )

      {:error, :buffer_overflow}
    else
      {:ok, %{state | buffer: full}}
    end
  end

  @doc """
  Flush the buffer with the final `:eol` remainder and parse the complete line.

  Concatenates any buffered partial data with the `:eol` remainder, attempts
  JSON parsing, and resets the buffer.

  Returns `{new_buffer, {:ok, parsed_map} | {:error, reason}}`.
  """
  @spec flush(t(), String.t()) :: {t(), {:ok, map()} | {:error, term()}}
  def flush(%__MODULE__{buffer: buf, max_bytes: max_bytes}, eol_data)
      when is_binary(eol_data) do
    full_line = if buf == "", do: eol_data, else: buf <> eol_data
    {new(max_bytes), parse_line(full_line, max_bytes)}
  end

  @doc """
  Append data to the buffer and extract any complete JSON messages.

  Returns `{updated_buffer, parsed_messages}` where `parsed_messages` is a
  list of decoded maps (in order received).

  Lines that are not valid JSON are logged and skipped.
  """
  @spec append(t(), String.t()) :: {t(), [map()]}
  def append(%__MODULE__{buffer: buf, max_bytes: max_bytes} = state, data)
      when is_binary(data) do
    full = buf <> data

    if byte_size(full) > max_bytes do
      Logger.error(
        "LineBuffer exceeded #{format_mb(max_bytes)} limit " <>
          "(#{byte_size(full)} bytes), discarding buffer — data has been lost"
      )

      {%{state | buffer: ""}, []}
    else
      {remaining, messages} = extract_lines(full, max_bytes)
      {%{state | buffer: remaining}, messages}
    end
  end

  @doc """
  Parse a single complete line as JSON.

  Returns `{:ok, map}` or `{:error, reason}`.
  """
  @spec parse_line(String.t(), pos_integer()) :: {:ok, map()} | {:error, term()}
  def parse_line(line, max_bytes \\ @default_max_buffer_bytes) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" -> {:error, :empty}
      byte_size(trimmed) > max_bytes -> {:error, :line_too_large}
      true -> Jason.decode(trimmed)
    end
  end

  defp extract_lines(data, max_bytes) do
    extract_lines(data, max_bytes, [])
  end

  defp extract_lines(data, max_bytes, acc) do
    case String.split(data, "\n", parts: 2) do
      [only] ->
        # No newline found — everything stays in buffer
        {only, Enum.reverse(acc)}

      [line, rest] ->
        case parse_line(line, max_bytes) do
          {:ok, parsed} ->
            extract_lines(rest, max_bytes, [parsed | acc])

          {:error, _} ->
            # Skip non-JSON lines (e.g. stderr leaking, empty lines)
            extract_lines(rest, max_bytes, acc)
        end
    end
  end

  defp format_mb(bytes) when bytes >= 1_048_576, do: "#{div(bytes, 1_048_576)}MB"
  defp format_mb(bytes), do: "#{bytes}B"
end
