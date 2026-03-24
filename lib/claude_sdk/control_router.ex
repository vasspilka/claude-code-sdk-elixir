defmodule ClaudeSDK.ControlRouter do
  @moduledoc """
  Routes `control_request` messages to registered handler functions.

  This module is used internally by `ClaudeSDK.query/2` and `ClaudeSDK.Client`.
  You do not need to interact with it directly unless building custom integrations.

  Handlers are keyed by the request `subtype` field. When a control_request
  arrives during streaming, the router dispatches it to the matching handler,
  which returns a response to send back to the CLI via stdin.
  """

  require Logger

  @type handler ::
          (map() ->
             :allow
             | {:allow, map()}
             | :deny
             | {:deny, String.t()}
             | {:result, map()}
             | :ok
             | {:ok, map()})
  @type handler_registry :: %{String.t() => handler()}

  @doc """
  Build handler registry from Options fields.

  Inspects `can_use_tool`, `mcp_servers`, and `hooks` to register the
  appropriate control_request handlers.
  """
  @spec build_handlers(map()) :: handler_registry()
  def build_handlers(opts) do
    %{}
    |> maybe_add_permission_handler(opts)
    |> maybe_add_mcp_handler(opts)
    |> maybe_add_hook_handler(opts)
  end

  @doc """
  Dispatch a raw control_request map to the matching handler.

  Returns `{:handled, response_map}` if a handler matches and produces a
  response, or `{:unhandled, request}` if no handler is registered for
  the request subtype.
  """
  @spec dispatch(map(), handler_registry()) :: {:handled, map()} | {:unhandled, map()}
  def dispatch(%{"request_id" => request_id, "request" => request} = raw, handlers)
      when is_binary(request_id) and is_map(request) do
    subtype = request["subtype"]

    case Map.get(handlers, subtype) do
      nil ->
        {:unhandled, raw}

      handler when is_function(handler, 1) ->
        try do
          result = normalize_handler_result(handler.(request))

          case result do
            {tag, _} when tag in [:allow, :deny, :result] ->
              response = build_response(request_id, subtype, result)
              {:handled, response}

            other ->
              Logger.warning(
                "Handler for #{subtype} returned unexpected value: #{inspect(other)}"
              )

              {:handled, build_deny_response(request_id, "Invalid handler response")}
          end
        rescue
          e ->
            Logger.warning("Handler for #{subtype} raised: #{Exception.message(e)}")

            {:handled, build_error_response(request_id, Exception.message(e))}
        end
    end
  end

  def dispatch(raw, _handlers), do: {:unhandled, raw}

  @doc """
  Build a control_response map from a handler result.
  """
  @spec build_response(
          String.t(),
          String.t(),
          {:allow, map()} | {:deny, String.t()} | {:result, map()}
        ) :: map()
  def build_response(request_id, _subtype, {:allow, permissions}) do
    %{
      type: "control_response",
      request_id: request_id,
      response: Map.merge(%{allowed: true}, permissions)
    }
  end

  def build_response(request_id, _subtype, {:deny, reason}) do
    %{
      type: "control_response",
      request_id: request_id,
      response: %{allowed: false, reason: reason}
    }
  end

  def build_response(request_id, _subtype, {:result, payload}) do
    %{
      type: "control_response",
      request_id: request_id,
      response: payload
    }
  end

  # Private

  defp maybe_add_permission_handler(handlers, %{can_use_tool: nil}), do: handlers

  defp maybe_add_permission_handler(handlers, %{can_use_tool: callback})
       when is_function(callback, 2) or is_function(callback, 3) do
    handler = fn request ->
      tool_name = request["tool_name"] || ""
      input = request["input"] || %{}

      result =
        if is_function(callback, 3) do
          context = %ClaudeSDK.Types.ToolPermissionContext{
            tool_name: tool_name,
            input: input,
            request_id: request["request_id"] || "",
            raw_request: request
          }

          callback.(tool_name, input, context)
        else
          callback.(tool_name, input)
        end

      case result do
        :allow ->
          {:allow, %{}}

        {:allow, permissions} when is_map(permissions) ->
          {:allow, permissions}

        :deny ->
          {:deny, "Permission denied"}

        {:deny, reason} when is_binary(reason) ->
          {:deny, reason}

        {:deny, reason} ->
          {:deny, to_string(reason)}

        unexpected ->
          Logger.warning(
            "can_use_tool callback returned unexpected value: #{inspect(unexpected)}"
          )

          {:deny, "Permission callback returned invalid value"}
      end
    end

    Map.put(handlers, "can_use_tool", handler)
  end

  defp maybe_add_permission_handler(handlers, _opts), do: handlers

  defp maybe_add_mcp_handler(handlers, %{mcp_tool_index: tool_index})
       when map_size(tool_index) > 0 do
    handler = fn request ->
      server_name = request["server_name"] || ""
      jsonrpc = request["jsonrpc_message"] || %{}

      ClaudeSDK.MCP.Server.handle_jsonrpc(server_name, jsonrpc, tool_index)
    end

    Map.put(handlers, "mcp_message", handler)
  end

  defp maybe_add_mcp_handler(handlers, _opts), do: handlers

  defp maybe_add_hook_handler(handlers, %{hooks: hooks} = opts)
       when is_map(hooks) and map_size(hooks) > 0 do
    timeout = Map.get(opts, :hook_timeout_ms, 30_000)

    handler = fn request ->
      hook_event = request["hook_event"] || ""
      hook_input = request["hook_input"] || %{}

      case Map.get(hooks, hook_event) do
        nil ->
          {:result, %{}}

        hook_callbacks when is_list(hook_callbacks) ->
          run_hook_callbacks(hook_callbacks, hook_event, hook_input, timeout)

        hook_callback when is_function(hook_callback, 1) ->
          run_single_hook_callback(hook_callback, hook_event, hook_input, timeout)

        hook_callback when is_function(hook_callback, 2) ->
          run_single_hook_callback_2(hook_callback, hook_event, hook_input, timeout)

        _ ->
          {:result, %{}}
      end
    end

    Map.put(handlers, "hook_callback", handler)
  end

  defp maybe_add_hook_handler(handlers, _opts), do: handlers

  defp run_hook_callbacks(callbacks, hook_event, hook_input, timeout) do
    Enum.reduce(callbacks, {:result, %{}}, fn callback, acc ->
      result =
        cond do
          is_function(callback, 1) ->
            run_single_hook_callback(callback, hook_event, hook_input, timeout)

          is_function(callback, 2) ->
            run_single_hook_callback_2(callback, hook_event, hook_input, timeout)

          true ->
            {:result, %{}}
        end

      case {acc, result} do
        {{:result, prev}, {:result, next}} -> {:result, Map.merge(prev, next)}
        {_, latest} -> latest
      end
    end)
  end

  defp run_single_hook_callback(callback, _hook_event, hook_input, timeout) do
    run_with_timeout(fn -> callback.(hook_input) end, timeout)
  end

  defp run_single_hook_callback_2(callback, hook_event, hook_input, timeout) do
    run_with_timeout(fn -> callback.(hook_event, hook_input) end, timeout)
  end

  defp run_with_timeout(fun, timeout) do
    caller = self()
    ref = make_ref()

    {pid, monitor_ref} =
      spawn_monitor(fn ->
        try do
          result = fun.()
          send(caller, {ref, {:ok, result}})
        rescue
          e ->
            send(caller, {ref, {:error, Exception.message(e)}})
        end
      end)

    receive do
      {^ref, {:ok, result}} ->
        Process.demonitor(monitor_ref, [:flush])
        normalize_hook_result(result)

      {^ref, {:error, message}} ->
        Process.demonitor(monitor_ref, [:flush])
        Logger.warning("Hook callback raised: #{message}")
        {:result, %{}}

      {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
        Logger.warning("Hook callback exited: #{inspect(reason)}")
        {:result, %{}}
    after
      timeout ->
        Process.demonitor(monitor_ref, [:flush])
        Process.exit(pid, :kill)
        Logger.warning("Hook callback timed out after #{timeout}ms")
        {:result, %{}}
    end
  end

  defp normalize_hook_result(:ok), do: {:result, %{}}
  defp normalize_hook_result({:ok, result}) when is_map(result), do: {:result, result}
  defp normalize_hook_result({:result, result}) when is_map(result), do: {:result, result}
  defp normalize_hook_result(_), do: {:result, %{}}

  defp normalize_handler_result(:allow), do: {:allow, %{}}
  defp normalize_handler_result(:deny), do: {:deny, "Permission denied"}
  defp normalize_handler_result(:ok), do: {:result, %{}}
  defp normalize_handler_result({:ok, map}) when is_map(map), do: {:result, map}
  defp normalize_handler_result(other), do: other

  defp build_error_response(request_id, message) do
    %{
      type: "control_response",
      request_id: request_id,
      response: %{allowed: false, reason: "Handler error: #{message}"}
    }
  end

  defp build_deny_response(request_id, reason) do
    %{
      type: "control_response",
      request_id: request_id,
      response: %{allowed: false, reason: reason}
    }
  end
end
