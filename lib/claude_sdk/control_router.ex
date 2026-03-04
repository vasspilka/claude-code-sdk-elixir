defmodule ClaudeSDK.ControlRouter do
  @moduledoc """
  Routes `control_request` messages to registered handler functions.

  Handlers are keyed by the request `subtype` field. When a control_request
  arrives during streaming, the router dispatches it to the matching handler,
  which returns a response to send back to the CLI via stdin.
  """

  require Logger

  @type handler :: (map() -> {:allow, map()} | {:deny, String.t()} | {:result, map()})
  @type handler_registry :: %{String.t() => handler()}

  @doc """
  Build handler registry from Options fields.

  Inspects `can_use_tool` and `mcp_servers` to register the appropriate
  control_request handlers.
  """
  @spec build_handlers(map()) :: handler_registry()
  def build_handlers(opts) do
    %{}
    |> maybe_add_permission_handler(opts)
    |> maybe_add_mcp_handler(opts)
  end

  @doc """
  Dispatch a raw control_request map to the matching handler.

  Returns `{:handled, response_map}` if a handler matches and produces a
  response, or `{:unhandled, request}` if no handler is registered for
  the request subtype.
  """
  @spec dispatch(map(), handler_registry()) :: {:handled, map()} | {:unhandled, map()}
  def dispatch(%{"request_id" => request_id, "request" => request} = raw, handlers) do
    subtype = request["subtype"]

    case Map.get(handlers, subtype) do
      nil ->
        {:unhandled, raw}

      handler when is_function(handler, 1) ->
        try do
          case handler.(request) do
            {tag, _} = result when tag in [:allow, :deny, :result] ->
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
       when is_function(callback, 2) do
    handler = fn request ->
      tool_name = request["tool_name"] || ""
      input = request["input"] || %{}

      case callback.(tool_name, input) do
        :allow -> {:allow, %{}}
        {:allow, permissions} when is_map(permissions) -> {:allow, permissions}
        :deny -> {:deny, "Permission denied"}
        {:deny, reason} when is_binary(reason) -> {:deny, reason}
        {:deny, reason} -> {:deny, to_string(reason)}
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
