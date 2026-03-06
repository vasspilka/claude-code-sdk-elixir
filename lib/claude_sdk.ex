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
  alias ClaudeSDK.MessageParser
  alias ClaudeSDK.Transport.Subprocess
  alias ClaudeSDK.Types.Options

  # 30s is generous for CLI startup + initialize handshake
  @default_init_timeout 30_000
  # 120s allows for extended thinking and large responses;
  # override via Options.message_timeout_ms for longer operations
  @default_message_timeout 120_000

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
  """
  @spec query(String.t(), Options.t() | keyword()) :: Enumerable.t()
  def query(prompt, opts \\ %Options{})

  def query(prompt, opts) when is_list(opts) do
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

  @doc false
  defdelegate generate_request_id, to: ClaudeSDK.Internal

  # Stream.resource start_fun: spawn subprocess and send initialization + prompt
  defp start_subprocess(prompt, opts) do
    # Build MCP tool index if mcp_servers are configured
    mcp_tool_index = build_mcp_tool_index(opts.mcp_servers)

    # Build handler registry for control_request dispatch
    handler_opts = %{
      can_use_tool: opts.can_use_tool,
      mcp_tool_index: mcp_tool_index
    }

    control_handlers = ControlRouter.build_handlers(handler_opts)

    {:ok, pid} =
      case Subprocess.start(caller: self(), options: opts) do
        {:ok, pid} ->
          {:ok, pid}

        {:error, %ClaudeSDK.CLINotFoundError{} = e} ->
          raise e

        {:error, reason} ->
          raise ClaudeSDK.TransportError, reason: reason
      end

    # Send initialize control request
    init_request = %{
      type: "control_request",
      request_id: generate_request_id(),
      request:
        %{
          subtype: "initialize",
          hooks: opts.hooks,
          agents: normalize_agents(opts.agents)
        }
        |> maybe_put_plugins(opts.plugins)
    }

    Subprocess.send_message(pid, init_request)

    init_timeout = opts.init_timeout_ms || @default_init_timeout

    # Wait for control_response acknowledging initialization.
    # Skip any non-control_response messages (e.g. system messages) that
    # the CLI may send before the handshake completes.
    wait_for_init_response(pid, init_timeout)

    # Send the user prompt
    user_message = %{
      type: "user",
      session_id: opts.session_id,
      message: %{role: "user", content: prompt},
      parent_tool_use_id: nil
    }

    Subprocess.send_message(pid, user_message)

    message_timeout = opts.message_timeout_ms || @default_message_timeout
    %{subprocess: pid, control_handlers: control_handlers, message_timeout: message_timeout}
  end

  # Stream.resource next_fun: receive and parse messages
  defp receive_messages(:halt), do: {:halt, :done}

  defp receive_messages(
         %{subprocess: pid, control_handlers: handlers, message_timeout: message_timeout} = state
       ) do
    receive do
      {:claude_message, %{"type" => "control_request"} = raw} ->
        case ControlRouter.dispatch(raw, handlers) do
          {:handled, response} ->
            Subprocess.send_message(pid, response)
            {[], state}

          {:unhandled, _} ->
            case MessageParser.parse(raw) do
              {:ok, msg} ->
                {[msg], state}

              {:error, reason} ->
                Logger.warning("Failed to parse control_request message: #{inspect(reason)}")
                {[], state}
            end
        end

      {:claude_message, raw} ->
        case MessageParser.parse(raw) do
          {:ok, %ClaudeSDK.Types.ResultMessage{} = msg} ->
            {[msg], :halt}

          {:ok, msg} ->
            {[msg], state}

          {:error, reason} ->
            Logger.warning("Failed to parse message: #{inspect(reason)}")
            {[], state}
        end

      {:claude_exit, _reason} ->
        {:halt, :done}
    after
      message_timeout ->
        timeout_seconds = div(message_timeout, 1000)

        timeout_result = %ClaudeSDK.Types.ResultMessage{
          subtype: "error",
          is_error: true,
          result: "Message receive timeout after #{timeout_seconds}s",
          duration_ms: 0,
          duration_api_ms: 0,
          num_turns: 0,
          session_id: nil
        }

        {[timeout_result], :halt}
    end
  end

  # Stream.resource after_fun: clean up subprocess
  defp cleanup(:done), do: :ok

  defp cleanup(%{subprocess: pid}) do
    if Process.alive?(pid) do
      Subprocess.stop(pid)
    end
  end

  defp cleanup(_), do: :ok

  defp wait_for_init_response(pid, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout

    wait_for_init_loop(pid, deadline, timeout)
  end

  defp wait_for_init_loop(pid, deadline, original_timeout) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:claude_message, %{"type" => "control_response"}} ->
        :ok

      {:claude_message, %{"type" => _}} ->
        # Skip non-control_response messages (system, etc.)
        wait_for_init_loop(pid, deadline, original_timeout)

      {:claude_exit, reason} ->
        raise ClaudeSDK.TransportError,
          reason: reason,
          message: "CLI exited during initialization: #{inspect(reason)}"
    after
      remaining ->
        Subprocess.stop(pid)
        raise ClaudeSDK.TimeoutError, timeout_ms: original_timeout
    end
  end

  defp normalize_agents(agents) when is_list(agents) do
    Enum.map(agents, fn
      %ClaudeSDK.Types.AgentDefinition{} = agent ->
        ClaudeSDK.Types.AgentDefinition.to_map(agent)

      agent when is_map(agent) ->
        agent
    end)
  end

  defp normalize_agents(agents) when is_map(agents), do: agents
  defp normalize_agents(_), do: %{}

  defp maybe_put_plugins(request, nil), do: request
  defp maybe_put_plugins(request, []), do: request

  defp maybe_put_plugins(request, plugins) when is_list(plugins),
    do: Map.put(request, :plugins, plugins)

  defp build_mcp_tool_index([]), do: %{}
  defp build_mcp_tool_index(nil), do: %{}

  defp build_mcp_tool_index(servers) when is_list(servers) do
    ClaudeSDK.MCP.Server.build_tool_index(servers)
  end
end
