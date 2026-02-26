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
        model: "claude-sonnet-4-20250514",
        max_turns: 3,
        permission_mode: :bypass_permissions
      })
      |> Enum.each(fn
        %ClaudeSDK.Types.AssistantMessage{} = msg -> handle_assistant(msg)
        %ClaudeSDK.Types.ResultMessage{} = msg -> handle_result(msg)
        _ -> :ok
      end)
  """

  alias ClaudeSDK.MessageParser
  alias ClaudeSDK.Transport.Subprocess
  alias ClaudeSDK.Types.Options

  @init_timeout 30_000

  @doc """
  Send a prompt to the Claude CLI and return a stream of typed messages.

  The stream yields message structs (AssistantMessage, SystemMessage, etc.)
  and terminates when a ResultMessage is received or the subprocess exits.

  ## Parameters

  - `prompt` — the user message string
  - `opts` — `%Options{}` struct or keyword list of options

  ## Returns

  An `Enumerable.t()` of parsed message structs.
  """
  @spec query(String.t(), Options.t() | keyword()) :: Enumerable.t()
  def query(prompt, opts \\ %Options{})

  def query(prompt, opts) when is_list(opts) do
    query(prompt, struct(Options, opts))
  end

  def query(prompt, %Options{} = opts) do
    Stream.resource(
      fn -> start_subprocess(prompt, opts) end,
      &receive_messages/1,
      &cleanup/1
    )
  end

  # Stream.resource start_fun: spawn subprocess and send initialization + prompt
  defp start_subprocess(prompt, opts) do
    {:ok, pid} = Subprocess.start_link(caller: self(), options: opts)

    # Send initialize control request
    init_request = %{
      type: "control_request",
      request_id: generate_request_id(),
      request: %{
        subtype: "initialize",
        hooks: opts.hooks,
        agents: opts.agents
      }
    }

    Subprocess.send_message(pid, init_request)

    # Wait for control_response acknowledging initialization
    receive do
      {:claude_message, %{"type" => "control_response"}} ->
        :ok

      {:claude_message, %{"type" => "system"}} ->
        # Some CLI versions send system init before control_response
        receive do
          {:claude_message, %{"type" => "control_response"}} -> :ok
        after
          @init_timeout ->
            Subprocess.stop(pid)
            raise ClaudeSDK.TimeoutError, timeout_ms: @init_timeout
        end
    after
      @init_timeout ->
        Subprocess.stop(pid)
        raise ClaudeSDK.TimeoutError, timeout_ms: @init_timeout
    end

    # Send the user prompt
    user_message = %{
      type: "user",
      session_id: opts.session_id,
      message: %{role: "user", content: prompt},
      parent_tool_use_id: nil
    }

    Subprocess.send_message(pid, user_message)

    pid
  end

  # Stream.resource next_fun: receive and parse messages
  defp receive_messages(:halt), do: {:halt, :done}

  defp receive_messages(pid) do
    receive do
      {:claude_message, raw} ->
        case MessageParser.parse(raw) do
          {:ok, %ClaudeSDK.Types.ResultMessage{} = msg} ->
            # Result means we're done — emit it and halt
            {[msg], :halt}

          {:ok, msg} ->
            {[msg], pid}

          {:error, _reason} ->
            # Skip unparseable messages, continue receiving
            {[], pid}
        end

      {:claude_exit, _reason} ->
        {:halt, :done}
    after
      120_000 ->
        {:halt, :timeout}
    end
  end

  # Stream.resource after_fun: clean up subprocess
  defp cleanup(:done), do: :ok
  defp cleanup(:timeout), do: :ok

  defp cleanup(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      Subprocess.stop(pid)
    end
  end

  defp cleanup(_), do: :ok

  defp generate_request_id do
    "req_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
