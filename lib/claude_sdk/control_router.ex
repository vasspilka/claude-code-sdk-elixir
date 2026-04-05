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

  @type permission_result ::
          :allow
          | {:allow, map() | keyword()}
          | :deny
          | {:deny, String.t()}
          | {:deny, String.t(), :interrupt}

  @type handler ::
          (map() ->
             permission_result()
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
  @spec dispatch(map(), handler_registry()) ::
          {:handled, map()} | {:handled_with_interrupt, map()} | {:unhandled, map()}
  def dispatch(%{"request_id" => request_id, "request" => request} = raw, handlers)
      when is_binary(request_id) and is_map(request) do
    subtype = request["subtype"]
    start = System.monotonic_time()

    result =
      case Map.get(handlers, subtype) do
        nil ->
          {:unhandled, raw}

        handler when is_function(handler, 1) ->
          dispatch_with_handler(handler, request_id, request, subtype)
      end

    duration = System.monotonic_time() - start
    outcome = dispatch_outcome(result)

    ClaudeSDK.Telemetry.control_request_stop(duration, %{
      subtype: subtype || "",
      outcome: outcome
    })

    result
  end

  def dispatch(raw, _handlers), do: {:unhandled, raw}

  defp dispatch_outcome({:handled, _}), do: :handled
  defp dispatch_outcome({:handled_with_interrupt, _}), do: :handled_with_interrupt
  defp dispatch_outcome({:unhandled, _}), do: :unhandled

  defp dispatch_with_handler(handler, request_id, request, subtype) do
    try do
      # Include request_id in the request so handlers can access it
      # (e.g. ToolPermissionContext needs the envelope's request_id)
      enriched_request = Map.put_new(request, "request_id", request_id)
      result = normalize_handler_result(handler.(enriched_request))

      case result do
        {:deny_and_interrupt, reason} ->
          response = build_response(request_id, subtype, {:deny, reason})
          {:handled_with_interrupt, response}

        {tag, _} when tag in [:allow, :deny, :result] ->
          response = build_response(request_id, subtype, result)
          {:handled, response}

        other ->
          Logger.warning("Handler for #{subtype} returned unexpected value: #{inspect(other)}")

          {:handled, build_deny_response(request_id, "Invalid handler response")}
      end
    rescue
      e ->
        Logger.warning("Handler for #{subtype} raised: #{Exception.message(e)}")

        {:handled, build_error_response(request_id)}
    end
  end

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
      response: Map.put(payload, :request_id, request_id)
    }
  end

  # Private

  defp maybe_add_permission_handler(handlers, %{can_use_tool: nil}), do: handlers

  defp maybe_add_permission_handler(handlers, %{can_use_tool: callback} = opts)
       when is_function(callback, 2) or is_function(callback, 3) do
    permission_timeout = Map.get(opts, :hook_timeout_ms, 30_000)

    handler = fn request ->
      tool_name = request["tool_name"] || ""
      input = request["input"] || %{}

      callback_fn = fn ->
        if is_function(callback, 3) do
          context = %ClaudeSDK.Types.ToolPermissionContext{
            tool_name: tool_name,
            input: input,
            request_id: request["request_id"] || "",
            permission_suggestions: request["permission_suggestions"],
            raw_request: request
          }

          callback.(tool_name, input, context)
        else
          callback.(tool_name, input)
        end
      end

      result = run_permission_callback(callback_fn, permission_timeout)

      case result do
        :allow ->
          {:allow, %{}}

        {:allow, opts} when is_map(opts) or is_list(opts) ->
          {:allow, normalize_allow_opts(opts)}

        :deny ->
          {:deny, "Permission denied"}

        {:deny, reason, :interrupt} when is_binary(reason) ->
          {:deny_and_interrupt, reason}

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

  defp maybe_add_mcp_handler(handlers, %{mcp_tool_index: tool_index, mcp_servers: servers})
       when is_list(servers) and length(servers) > 0 do
    handler = fn request ->
      server_name = request["server_name"] || ""
      jsonrpc = request["message"] || request["jsonrpc_message"] || %{}

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

  defp run_single_hook_callback(callback, hook_event, hook_input, timeout) do
    run_with_timeout(fn -> callback.(hook_input) end, timeout, hook_event)
  end

  defp run_single_hook_callback_2(callback, hook_event, hook_input, timeout) do
    run_with_timeout(fn -> callback.(hook_event, hook_input) end, timeout, hook_event)
  end

  defp run_permission_callback(fun, timeout) do
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
        result

      {^ref, {:error, message}} ->
        Process.demonitor(monitor_ref, [:flush])
        Logger.warning("can_use_tool callback raised: #{message}")
        {:deny, "Permission callback error"}

      {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
        Logger.warning("can_use_tool callback exited: #{inspect(reason)}")
        {:deny, "Permission callback crashed"}
    after
      timeout ->
        Process.demonitor(monitor_ref, [:flush])
        Process.exit(pid, :kill)
        Logger.warning("can_use_tool callback timed out after #{timeout}ms")
        {:deny, "Permission callback timed out"}
    end
  end

  defp run_with_timeout(fun, timeout, hook_event) do
    caller = self()
    ref = make_ref()
    start = System.monotonic_time()

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

    {outcome, return} =
      receive do
        {^ref, {:ok, result}} ->
          Process.demonitor(monitor_ref, [:flush])
          {:ok, normalize_hook_result(result)}

        {^ref, {:error, message}} ->
          Process.demonitor(monitor_ref, [:flush])
          Logger.warning("Hook callback raised: #{message}")
          {:crash, {:result, %{}}}

        {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
          Logger.warning("Hook callback exited: #{inspect(reason)}")
          {:crash, {:result, %{}}}
      after
        timeout ->
          Process.demonitor(monitor_ref, [:flush])
          Process.exit(pid, :kill)
          Logger.warning("Hook callback timed out after #{timeout}ms")
          {:timeout, {:result, %{}}}
      end

    duration = System.monotonic_time() - start

    ClaudeSDK.Telemetry.hook_callback_stop(duration, %{
      event: hook_event,
      outcome: outcome
    })

    return
  end

  defp normalize_hook_result(:ok), do: {:result, %{}}
  defp normalize_hook_result({:ok, result}) when is_map(result), do: {:result, result}
  defp normalize_hook_result({:result, result}) when is_map(result), do: {:result, result}
  defp normalize_hook_result(_), do: {:result, %{}}

  defp normalize_handler_result(:allow), do: {:allow, %{}}
  defp normalize_handler_result(:deny), do: {:deny, "Permission denied"}
  defp normalize_handler_result(:ok), do: {:result, %{}}
  defp normalize_handler_result({:ok, map}) when is_map(map), do: {:result, map}
  defp normalize_handler_result({:deny_and_interrupt, _} = result), do: result
  defp normalize_handler_result(other), do: other

  # Convert snake_case permission opts to camelCase keys expected by the CLI.
  # Unknown keys are passed through for forward compatibility with new CLI features.
  defp normalize_allow_opts(opts) when is_list(opts), do: normalize_allow_opts(Map.new(opts))

  defp normalize_allow_opts(opts) when is_map(opts) do
    snake_to_camel = %{
      updated_input: :updatedInput,
      updated_permissions: :updatedPermissions
    }

    Enum.reduce(opts, %{}, fn {key, value}, acc ->
      normalized_key = Map.get(snake_to_camel, key, key)
      Map.put(acc, normalized_key, value)
    end)
  end

  defp build_error_response(request_id) do
    %{
      type: "control_response",
      request_id: request_id,
      response: %{allowed: false, reason: "Handler error: internal error"}
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
