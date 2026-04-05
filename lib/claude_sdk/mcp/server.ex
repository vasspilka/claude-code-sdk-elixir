defmodule ClaudeSDK.MCP.Server do
  @moduledoc """
  Manages in-process MCP server configurations.

  Provides functions to create server configs, generate CLI-compatible
  configurations, build tool lookup indexes, and handle JSONRPC messages
  from the CLI.

  Most users should use `ClaudeSDK.create_mcp_server/3` rather than calling
  this module directly.

  ## Example

      server = ClaudeSDK.create_mcp_server("my-tools", "1.0", [
        %ClaudeSDK.MCP.Tool{
          name: "greet",
          description: "Greet a user by name",
          input_schema: %{
            "type" => "object",
            "properties" => %{"name" => %{"type" => "string"}},
            "required" => ["name"]
          },
          handler: fn %{"name" => name} -> {:ok, "Hello, \#{name}!"} end
        }
      ])

      ClaudeSDK.query("Greet Alice", %ClaudeSDK.Types.Options{mcp_servers: [server]})
      |> Enum.each(&IO.inspect/1)
  """

  require Logger

  alias ClaudeSDK.MCP.Tool

  @doc """
  Create an MCP server configuration.

  Returns a map containing the server name, version, tools, and tool handlers.
  """
  @spec create(String.t(), String.t(), [Tool.t()]) :: map()
  def create(name, version, tools)
      when is_binary(name) and is_binary(version) and is_list(tools) do
    %{
      name: name,
      version: version,
      tools: tools
    }
  end

  @doc """
  Convert a list of server configs to a CLI-compatible MCP config map.

  Strips handler functions and builds the config structure expected by
  the `--mcp-config` CLI flag, with `type: "sdk"` for each server.
  """
  @spec to_cli_config([map()]) :: map()
  def to_cli_config(servers) when is_list(servers) do
    mcpServers =
      Map.new(servers, fn server ->
        # The CLI only accepts {"type": "sdk", "name": "<name>"} for SDK servers.
        # Tools and version are NOT sent in the config — the CLI discovers tools
        # at runtime via mcp_message control requests (tools/list, tools/call).
        config = %{
          "type" => "sdk",
          "name" => server.name
        }

        {server.name, config}
      end)

    %{"mcpServers" => mcpServers}
  end

  @doc """
  Build a tool lookup index from server configs.

  Returns a map of `{server_name, tool_name} => Tool.t()` for fast dispatch
  and tool listing.
  """
  @spec build_tool_index([map()]) :: %{{String.t(), String.t()} => Tool.t()}
  def build_tool_index(servers) when is_list(servers) do
    Enum.reduce(servers, %{}, fn server, acc ->
      Enum.reduce(server.tools, acc, fn tool, inner_acc ->
        key = {server.name, tool.name}

        if Map.has_key?(inner_acc, key) do
          Logger.error(
            "MCP tool name collision: tool #{inspect(tool.name)} on server " <>
              "#{inspect(server.name)} is already registered — overwriting previous definition. " <>
              "The previous tool handler will be shadowed."
          )
        end

        Map.put(inner_acc, key, tool)
      end)
    end)
  end

  @doc """
  Handle a JSONRPC message for a specific MCP server.

  Supports three methods:

  - `tools/call` — dispatches the call to the matching tool handler and returns
    the handler result (or a tool-not-found error).
  - `tools/list` — returns the list of tools registered for the given server.
  - Any other method — returns a JSONRPC "method not supported" error.

  Always returns a `{:result, response_map}` tuple with the JSONRPC response.
  """
  @spec handle_jsonrpc(String.t(), map(), map()) :: {:result, map()}
  def handle_jsonrpc(
        server_name,
        %{"method" => "tools/call", "id" => id, "params" => params},
        tool_index
      ) do
    tool_name = params["name"] || ""
    arguments = params["arguments"] || %{}

    case Map.get(tool_index, {server_name, tool_name}) do
      nil ->
        {:result,
         %{
           mcp_response: %{
             "jsonrpc" => "2.0",
             "id" => id,
             "error" => %{
               "code" => -32601,
               "message" => "Tool not found: #{tool_name}"
             }
           }
         }}

      %Tool{handler: handler, input_schema: schema} ->
        case validate_arguments(arguments, schema) do
          {:error, validation_error} ->
            {:result,
             %{
               mcp_response: %{
                 "jsonrpc" => "2.0",
                 "id" => id,
                 "result" => %{
                   "content" => [
                     %{"type" => "text", "text" => "Validation error: #{validation_error}"}
                   ],
                   "isError" => true
                 }
               }
             }}

          :ok ->
            try do
              case handler.(arguments) do
                {:ok, result} ->
                  content = format_result(result)

                  {:result,
                   %{
                     mcp_response: %{
                       "jsonrpc" => "2.0",
                       "id" => id,
                       "result" => %{
                         "content" => content,
                         "isError" => false
                       }
                     }
                   }}

                {:error, reason} ->
                  {:result,
                   %{
                     mcp_response: %{
                       "jsonrpc" => "2.0",
                       "id" => id,
                       "result" => %{
                         "content" => [%{"type" => "text", "text" => to_string(reason)}],
                         "isError" => true
                       }
                     }
                   }}
              end
            rescue
              e ->
                Logger.warning(
                  "MCP tool handler for #{tool_name} raised: #{Exception.message(e)}"
                )

                {:result,
                 %{
                   mcp_response: %{
                     "jsonrpc" => "2.0",
                     "id" => id,
                     "result" => %{
                       "content" => [
                         %{
                           "type" => "text",
                           "text" => "Tool handler error: internal error"
                         }
                       ],
                       "isError" => true
                     }
                   }
                 }}
            end
        end
    end
  end

  def handle_jsonrpc(server_name, %{"method" => "tools/list", "id" => id}, tool_index) do
    tools =
      tool_index
      |> Enum.filter(fn {{sn, _}, _} -> sn == server_name end)
      |> Enum.map(fn {{_, _}, tool} ->
        %{
          "name" => tool.name,
          "description" => tool.description,
          "inputSchema" => tool.input_schema
        }
      end)

    {:result,
     %{
       message: %{
         "jsonrpc" => "2.0",
         "id" => id,
         "result" => %{"tools" => tools}
       }
     }}
  end

  def handle_jsonrpc(server_name, %{"method" => "initialize", "id" => id}, tool_index) do
    # Find the server version from the tool index keys
    version =
      tool_index
      |> Enum.find_value("1.0", fn {{sn, _}, _} ->
        if sn == server_name, do: "1.0"
      end)

    {:result,
     %{
       message: %{
         "jsonrpc" => "2.0",
         "id" => id,
         "result" => %{
           "protocolVersion" => "2025-11-25",
           "capabilities" => %{"tools" => %{}},
           "serverInfo" => %{"name" => server_name, "version" => version}
         }
       }
     }}
  end

  def handle_jsonrpc(_server_name, %{"id" => id}, _tool_index) do
    {:result,
     %{
       message: %{
         "jsonrpc" => "2.0",
         "id" => id,
         "error" => %{
           "code" => -32601,
           "message" => "Method not supported"
         }
       }
     }}
  end

  # JSONRPC notifications (no "id" field) are valid — they don't expect a response.
  # Return an empty result so the ControlRouter sends a benign response back.
  def handle_jsonrpc(_server_name, %{"method" => _method}, _tool_index) do
    {:result, %{}}
  end

  # Catch-all for other messages (e.g. MCP protocol handshake messages)
  def handle_jsonrpc(_server_name, _message, _tool_index) do
    Logger.debug("Received unrecognized JSONRPC message (no 'id' or 'method' field)")
    {:result, %{}}
  end

  # Basic validation of tool arguments against the tool's input schema.
  # Checks required fields and top-level types without a full JSON Schema library.
  defp validate_arguments(_arguments, nil), do: :ok

  defp validate_arguments(arguments, schema) when is_map(schema) and is_map(arguments) do
    with :ok <- validate_required_fields(arguments, schema) do
      validate_property_types(arguments, schema)
    end
  end

  defp validate_arguments(_arguments, _schema), do: :ok

  defp validate_required_fields(arguments, schema) do
    required = Map.get(schema, "required", [])

    missing =
      Enum.reject(required, fn field ->
        Map.has_key?(arguments, field)
      end)

    if missing == [] do
      :ok
    else
      {:error, "missing required fields: #{Enum.join(missing, ", ")}"}
    end
  end

  defp validate_property_types(arguments, schema) do
    properties = Map.get(schema, "properties", %{})

    error =
      Enum.find_value(arguments, fn {key, value} ->
        case Map.get(properties, key) do
          nil -> nil
          prop_schema -> check_type(key, value, Map.get(prop_schema, "type"))
        end
      end)

    if error, do: {:error, error}, else: :ok
  end

  defp check_type(_key, _value, nil), do: nil
  defp check_type(_key, value, "string") when is_binary(value), do: nil
  defp check_type(_key, value, "number") when is_number(value), do: nil
  defp check_type(_key, value, "integer") when is_integer(value), do: nil
  defp check_type(_key, value, "boolean") when is_boolean(value), do: nil
  defp check_type(_key, value, "object") when is_map(value), do: nil
  defp check_type(_key, value, "array") when is_list(value), do: nil
  defp check_type(_key, _value, "null"), do: nil

  defp check_type(key, value, expected_type) do
    "field #{inspect(key)} expected type #{expected_type}, got #{inspect_type(value)}"
  end

  defp inspect_type(v) when is_binary(v), do: "string"
  defp inspect_type(v) when is_integer(v), do: "integer"
  defp inspect_type(v) when is_float(v), do: "number"
  defp inspect_type(v) when is_boolean(v), do: "boolean"
  defp inspect_type(v) when is_map(v), do: "object"
  defp inspect_type(v) when is_list(v), do: "array"
  defp inspect_type(nil), do: "null"
  defp inspect_type(_), do: "unknown"

  # 1 MB size limit for MCP results
  @max_result_bytes 1_048_576

  defp format_result(result) when is_binary(result) do
    [%{"type" => "text", "text" => maybe_truncate(result)}]
  end

  defp format_result(result) when is_list(result), do: result

  defp format_result(result) when is_map(result) do
    text = Jason.encode!(result)
    [%{"type" => "text", "text" => maybe_truncate(text)}]
  end

  defp format_result(result) do
    text = inspect(result)
    [%{"type" => "text", "text" => maybe_truncate(text)}]
  end

  defp maybe_truncate(text) when byte_size(text) > @max_result_bytes do
    original_size = byte_size(text)

    Logger.warning("MCP tool result truncated: #{original_size} bytes exceeds 1MB limit")

    truncated = truncate_utf8_safe(text, @max_result_bytes)
    truncated <> "\n... [truncated: result exceeded 1MB limit]"
  end

  defp maybe_truncate(text), do: text

  # Truncate to at most max_bytes while preserving valid UTF-8.
  # binary_part/3 can split a multi-byte codepoint; this trims any
  # trailing incomplete bytes so the result is always valid UTF-8.
  defp truncate_utf8_safe(text, max_bytes) do
    raw = binary_part(text, 0, max_bytes)

    case :unicode.characters_to_binary(raw) do
      {:incomplete, valid, _} -> valid
      {:error, valid, _} -> valid
      valid when is_binary(valid) -> valid
    end
  end
end
