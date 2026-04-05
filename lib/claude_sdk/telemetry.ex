defmodule ClaudeSDK.Telemetry do
  @moduledoc """
  Telemetry events emitted by the Claude SDK.

  The SDK uses `:telemetry` to emit events at key points in the subprocess
  and query lifecycle. Attach handlers to observe SDK behavior without
  modifying application code.

  ## Events

  ### `[:claude_sdk, :subprocess, :start]`

  Emitted when a CLI subprocess is spawned.

  - Measurements: `%{system_time: integer()}`
  - Metadata: `%{cli_path: String.t()}`

  ### `[:claude_sdk, :subprocess, :stop]`

  Emitted when a CLI subprocess exits.

  - Measurements: `%{system_time: integer()}`
  - Metadata: `%{reason: :normal | {:error, term()}}`

  ### `[:claude_sdk, :message, :received]`

  Emitted for each parsed message received from the CLI.

  - Measurements: `%{system_time: integer()}`
  - Metadata: `%{type: String.t()}`

  ### `[:claude_sdk, :query, :start]`

  Emitted when a query begins (prompt sent to CLI).

  - Measurements: `%{system_time: integer()}`
  - Metadata: `%{}`

  ### `[:claude_sdk, :query, :stop]`

  Emitted when a query completes (ResultMessage received).

  - Measurements: `%{duration: integer()}` (monotonic nanoseconds)
  - Metadata: `%{}`

  ## Example

      :telemetry.attach_many(
        "claude-sdk-logger",
        [
          [:claude_sdk, :subprocess, :start],
          [:claude_sdk, :subprocess, :stop],
          [:claude_sdk, :message, :received]
        ],
        fn event, measurements, metadata, _config ->
          IO.inspect({event, measurements, metadata}, label: "claude_sdk telemetry")
        end,
        nil
      )
  """

  @doc false
  def subprocess_start(metadata \\ %{}) do
    :telemetry.execute(
      [:claude_sdk, :subprocess, :start],
      %{system_time: System.system_time()},
      metadata
    )
  end

  @doc false
  def subprocess_stop(metadata \\ %{}) do
    :telemetry.execute(
      [:claude_sdk, :subprocess, :stop],
      %{system_time: System.system_time()},
      metadata
    )
  end

  @doc false
  def message_received(metadata \\ %{}) do
    :telemetry.execute(
      [:claude_sdk, :message, :received],
      %{system_time: System.system_time()},
      metadata
    )
  end

  @doc false
  def query_start(metadata \\ %{}) do
    :telemetry.execute(
      [:claude_sdk, :query, :start],
      %{system_time: System.system_time()},
      metadata
    )
  end

  @doc false
  def query_stop(duration, metadata \\ %{}) do
    :telemetry.execute(
      [:claude_sdk, :query, :stop],
      %{duration: duration},
      metadata
    )
  end
end
