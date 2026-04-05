defmodule ClaudeSDK do
  @moduledoc """
  Elixir SDK for the Claude Code CLI.

  Wraps the Claude Code CLI as a subprocess, communicating via stdin/stdout
  using newline-delimited JSON. Provides a streaming interface for sending
  prompts and receiving typed message structs.

  ## Basic Usage

      ClaudeSDK.query("What is 2+2?")
      |> Enum.each(&IO.inspect/1)

  ## With Options

      ClaudeSDK.query("Explain this code", %ClaudeSDK.Types.Options{
        model: "claude-sonnet-4-6",
        max_turns: 3,
        permission_mode: :bypass_permissions
      })
      |> Enum.each(fn
        %ClaudeSDK.Types.AssistantMessage{} = msg -> handle_assistant(msg)
        %ClaudeSDK.Types.ResultMessage{} = msg -> handle_result(msg)
        _ -> :ok
      end)

  ## Permission Callbacks

      ClaudeSDK.query("Read my files", %ClaudeSDK.Types.Options{
        can_use_tool: fn tool_name, _input ->
          if tool_name in ["Read", "Glob"], do: :allow, else: {:deny, "Not permitted"}
        end
      })
      |> Enum.each(&IO.inspect/1)

  ## In-Process MCP Servers

      server = ClaudeSDK.create_mcp_server("my-tools", "1.0", [
        %ClaudeSDK.MCP.Tool{
          name: "greet",
          description: "Say hello",
          input_schema: %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}},
          handler: fn args -> {:ok, "Hello, \#{args["name"]}!"} end
        }
      ])

      ClaudeSDK.query("Use the greet tool", %ClaudeSDK.Types.Options{mcp_servers: [server]})
      |> Enum.each(&IO.inspect/1)

  ## See Also

  - `ClaudeSDK.Client` — stateful multi-turn conversations with session persistence
  - `ClaudeSDK.Types.Options` — all available configuration options
  - `ClaudeSDK.MCP.Tool` — defining custom MCP tools
  """

  require Logger

  alias ClaudeSDK.ControlRouter
  alias ClaudeSDK.Internal
  alias ClaudeSDK.MessageParser
  alias ClaudeSDK.Types.Options

  @doc """
  Send a prompt to the Claude CLI and return a stream of typed messages.

  The stream yields message structs (AssistantMessage, SystemMessage, etc.)
  and terminates when a ResultMessage is received or the subprocess exits.

  Control requests (e.g. permission checks, MCP messages) are intercepted
  and handled automatically when callbacks are configured.

  ## Parameters

  - `prompt` — the user message string
  - `opts` — `%Options{}` struct or keyword list of options

  ## Returns

  An `Enumerable.t()` of parsed message structs.

  ## Stream Lifecycle

  The returned stream is **lazy** — the CLI subprocess is not spawned until
  the stream is consumed (e.g. via `Enum.each/2`, `Enum.to_list/1`, or
  `Stream.run/1`). This means:

  - **No side effects until consumption** — calling `query/2` alone does nothing.
  - **Partial consumption** — if you stop consuming early (e.g. `Enum.take/2`),
    the subprocess is cleaned up automatically via `Stream.resource/3`'s after
    callback. However, the CLI may have already performed work (tool calls,
    file edits) before the stream was halted.
  - **Single consumption** — each stream can only be consumed once. Consuming
    it again spawns a new subprocess and a new CLI session.
  - **Cleanup** — the subprocess is always stopped when the stream finishes,
    whether by natural completion, early halt, or error.
  """
  @spec query(String.t(), Options.t() | keyword()) :: Enumerable.t()
  def query(prompt, opts \\ %Options{})

  def query(prompt, opts) when is_list(opts) do
    valid_keys = Map.keys(%Options{}) -- [:__struct__]
    invalid_keys = Keyword.keys(opts) -- valid_keys

    if invalid_keys != [] do
      raise ArgumentError,
            "unknown options #{inspect(invalid_keys)}. Valid options: #{inspect(valid_keys)}"
    end

    query(prompt, struct(Options, opts))
  end

  def query(prompt, %Options{} = opts) do
    case Options.validate(opts) do
      :ok ->
        Stream.resource(
          fn -> start_subprocess(prompt, opts) end,
          &receive_messages/1,
          &cleanup/1
        )

      {:error, reason} ->
        raise ArgumentError, reason
    end
  end

  @doc """
  Create an in-process MCP server configuration.

  Returns a server config map that can be passed in `Options.mcp_servers`.
  """
  @spec create_mcp_server(String.t(), String.t(), [ClaudeSDK.MCP.Tool.t()]) :: map()
  def create_mcp_server(name, version, tools) do
    ClaudeSDK.MCP.Server.create(name, version, tools)
  end

  @doc """
  List available sessions. See `ClaudeSDK.Sessions.list_sessions/1`.
  """
  @spec list_sessions(keyword()) :: [ClaudeSDK.Sessions.session_info()]
  defdelegate list_sessions(opts \\ []), to: ClaudeSDK.Sessions

  @doc """
  Get info for a single session. See `ClaudeSDK.Sessions.get_session_info/2`.
  """
  @spec get_session_info(String.t(), keyword()) :: ClaudeSDK.Sessions.session_info() | nil
  defdelegate get_session_info(session_id, opts \\ []), to: ClaudeSDK.Sessions

  @doc """
  Get conversation messages for a session. See `ClaudeSDK.Sessions.get_session_messages/2`.
  """
  @spec get_session_messages(String.t(), keyword()) :: [ClaudeSDK.Sessions.session_message()]
  defdelegate get_session_messages(session_id, opts \\ []), to: ClaudeSDK.Sessions

  @doc """
  Get the full unfiltered transcript for a session. See `ClaudeSDK.Sessions.get_session_transcript/2`.
  """
  @spec get_session_transcript(String.t(), keyword()) :: [map()]
  defdelegate get_session_transcript(session_id, opts \\ []), to: ClaudeSDK.Sessions

  @doc """
  Rename a session. See `ClaudeSDK.Sessions.rename_session/3`.
  """
  @spec rename_session(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  defdelegate rename_session(session_id, title, opts \\ []), to: ClaudeSDK.Sessions

  @doc """
  Tag a session. See `ClaudeSDK.Sessions.tag_session/3`.
  """
  @spec tag_session(String.t(), String.t() | nil, keyword()) :: :ok | {:error, term()}
  defdelegate tag_session(session_id, tag, opts \\ []), to: ClaudeSDK.Sessions

  @doc """
  Delete a session. See `ClaudeSDK.Sessions.delete_session/2`.
  """
  @spec delete_session(String.t(), keyword()) :: :ok | {:error, term()}
  defdelegate delete_session(session_id, opts \\ []), to: ClaudeSDK.Sessions

  @doc """
  Fork a session. See `ClaudeSDK.Sessions.fork_session/2`.
  """
  @spec fork_session(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  defdelegate fork_session(session_id, opts \\ []), to: ClaudeSDK.Sessions

  @doc false
  defdelegate generate_request_id, to: ClaudeSDK.Internal

  # Stream.resource start_fun: spawn subprocess and send initialization + prompt
  defp start_subprocess(prompt, opts) do
    control_handlers = Internal.build_control_handlers(opts)
    transport_mod = opts.transport_module

    {:ok, pid} =
      case transport_mod.start(caller: self(), options: opts) do
        {:ok, pid} ->
          {:ok, pid}

        {:error, %ClaudeSDK.CLINotFoundError{} = e} ->
          raise e

        {:error, reason} ->
          raise ClaudeSDK.TransportError, reason: reason
      end

    transport_mod.send_message(pid, Internal.build_init_request(opts))

    init_timeout = opts.init_timeout_ms

    case Internal.wait_for_init_response(init_timeout) do
      {:ok, _server_info, buffered_messages} ->
        # Replay messages received during init so they appear in the stream
        for msg <- buffered_messages, do: send(self(), {:claude_message, msg})
        :ok

      {:error, {:cli_exited, {:error, %ClaudeSDK.ProcessExitError{} = e}}} ->
        raise e

      {:error, {:cli_exited, reason}} ->
        raise ClaudeSDK.TransportError,
          reason: reason,
          message: "CLI exited during initialization: #{inspect(reason)}"

      {:error, :init_timeout} ->
        Internal.safe_stop_subprocess(pid)
        raise ClaudeSDK.TimeoutError, timeout_ms: init_timeout
    end

    ClaudeSDK.Telemetry.query_start()

    # Send the user prompt
    user_message = %{
      type: "user",
      session_id: opts.session_id,
      message: %{role: "user", content: prompt},
      parent_tool_use_id: nil
    }

    transport_mod.send_message(pid, user_message)

    message_timeout = opts.message_timeout_ms

    %{
      subprocess: pid,
      transport_module: transport_mod,
      control_handlers: control_handlers,
      message_timeout: message_timeout,
      on_stderr: opts.on_stderr,
      started_at: System.monotonic_time(:millisecond)
    }
  end

  # Stream.resource next_fun: receive and parse messages
  defp receive_messages({:halt, state}), do: {:halt, state}
  defp receive_messages(:halt), do: {:halt, :done}

  defp receive_messages(
         %{
           subprocess: pid,
           transport_module: transport_mod,
           control_handlers: handlers,
           message_timeout: message_timeout
         } =
           state
       ) do
    receive do
      {:claude_message, %{"type" => "control_request"} = raw} ->
        case ControlRouter.dispatch(raw, handlers) do
          {:handled, response} ->
            transport_mod.send_message(pid, response)
            {[], state}

          {:handled_with_interrupt, response} ->
            transport_mod.send_message(pid, response)

            interrupt_msg = %{
              type: "control_request",
              request_id: Internal.generate_request_id(),
              request: %{subtype: "interrupt"}
            }

            transport_mod.send_message(pid, interrupt_msg)
            {:halt, state}

          {:unhandled, _} ->
            case MessageParser.parse(raw) do
              {:ok, msg} ->
                {[msg], state}

              {:error, reason} ->
                Logger.warning("Failed to parse control_request message: #{inspect(reason)}")
                {[], state}
            end
        end

      {:claude_message, %{"type" => "control_cancel_request"}} ->
        # CLI cancelling an inflight handler; already completed synchronously — skip
        {[], state}

      {:claude_message, raw} ->
        case MessageParser.parse(raw) do
          {:ok, %ClaudeSDK.Types.ResultMessage{} = msg} ->
            {[msg], {:halt, state}}

          {:ok, msg} ->
            {[msg], state}

          {:error, reason} ->
            Logger.warning("Failed to parse message: #{inspect(reason)}")
            {[], state}
        end

      {:claude_stderr, line} ->
        case state[:on_stderr] do
          callback when is_function(callback) -> callback.(line)
          _ -> Logger.debug("CLI stderr: #{String.slice(line, 0, 200)}")
        end

        {[], state}

      {:claude_buffer_overflow, bytes} ->
        Logger.warning("LineBuffer overflow: #{bytes} bytes lost — a large message was dropped")
        {[], state}

      {:claude_exit, _reason} ->
        {:halt, :done}
    after
      message_timeout ->
        timeout_seconds = div(message_timeout, 1000)
        elapsed_ms = System.monotonic_time(:millisecond) - state.started_at

        timeout_result = %ClaudeSDK.Types.ResultMessage{
          subtype: "error",
          is_error: true,
          result: "Message receive timeout after #{timeout_seconds}s",
          duration_ms: elapsed_ms,
          duration_api_ms: nil,
          num_turns: nil,
          session_id: nil
        }

        {[timeout_result], :halt}
    end
  end

  # Stream.resource after_fun: clean up subprocess
  defp cleanup(:done), do: :ok

  defp cleanup(%{subprocess: pid}) do
    Internal.safe_stop_subprocess(pid)
  end

  defp cleanup(_), do: :ok
end
