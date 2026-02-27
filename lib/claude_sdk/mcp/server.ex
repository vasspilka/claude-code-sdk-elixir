defmodule ClaudeSDK.MCP.Server do
  @moduledoc """
  Manages in-process MCP server configurations.

  Provides functions to create server configs, generate CLI-compatible
  configurations, build tool lookup indexes, and handle JSONRPC messages
  from the CLI.
  """

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
        tools =
          Enum.map(server.tools, fn tool ->
            %{
              "name" => tool.name,
              "description" => tool.description,
              "inputSchema" => tool.input_schema
            }
          end)

        config = %{
          "type" => "sdk",
          "version" => server.version,
          "tools" => tools
        }

        {server.name, config}
      end)

    %{"mcpServers" => mcpServers}
  end

  @doc """
  Build a tool handler lookup index from server configs.

  Returns a map of `{server_name, tool_name} => handler` for fast dispatch.
  """
  @spec build_tool_index([map()]) :: %{{String.t(), String.t()} => Tool.handler()}
  def build_tool_index(servers) when is_list(servers) do
    for server <- servers,
        tool <- server.tools,
        into: %{} do
      {{server.name, tool.name}, tool.handler}
    end
  end

  @doc """
  Handle a JSONRPC message for a specific MCP server.

  Routes `tools/call` methods to the appropriate tool handler and returns
  a `{:result, response_map}` tuple with the JSONRPC response.
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
           jsonrpc_response: %{
             "jsonrpc" => "2.0",
             "id" => id,
             "error" => %{
               "code" => -32601,
               "message" => "Tool not found: #{tool_name}"
             }
           }
         }}

      handler when is_function(handler, 1) ->
        case handler.(arguments) do
          {:ok, result} ->
            content = format_result(result)

            {:result,
             %{
               jsonrpc_response: %{
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
               jsonrpc_response: %{
                 "jsonrpc" => "2.0",
                 "id" => id,
                 "result" => %{
                   "content" => [%{"type" => "text", "text" => to_string(reason)}],
                   "isError" => true
                 }
               }
             }}
        end
    end
  end

  def handle_jsonrpc(_server_name, %{"method" => "tools/list", "id" => id}, _tool_index) do
    {:result,
     %{
       jsonrpc_response: %{
         "jsonrpc" => "2.0",
         "id" => id,
         "result" => %{"tools" => []}
       }
     }}
  end

  def handle_jsonrpc(_server_name, %{"id" => id}, _tool_index) do
    {:result,
     %{
       jsonrpc_response: %{
         "jsonrpc" => "2.0",
         "id" => id,
         "error" => %{
           "code" => -32601,
           "message" => "Method not supported"
         }
       }
     }}
  end

  defp format_result(result) when is_binary(result) do
    [%{"type" => "text", "text" => result}]
  end

  defp format_result(result) when is_list(result), do: result

  defp format_result(result) when is_map(result) do
    [%{"type" => "text", "text" => Jason.encode!(result)}]
  end

  defp format_result(result) do
    [%{"type" => "text", "text" => inspect(result)}]
  end
end
