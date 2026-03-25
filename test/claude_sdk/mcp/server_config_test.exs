defmodule ClaudeSDK.MCP.ServerConfigTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.MCP.{StdioServerConfig, SSEServerConfig, HttpServerConfig}

  describe "StdioServerConfig" do
    test "to_map with command only" do
      config = %StdioServerConfig{command: "python"}
      result = StdioServerConfig.to_map(config)

      assert result == %{"type" => "stdio", "command" => "python"}
    end

    test "to_map with command and args" do
      config = %StdioServerConfig{command: "npx", args: ["-y", "server-fs", "/tmp"]}
      result = StdioServerConfig.to_map(config)

      assert result == %{
               "type" => "stdio",
               "command" => "npx",
               "args" => ["-y", "server-fs", "/tmp"]
             }
    end

    test "to_map with command, args, and env" do
      config = %StdioServerConfig{
        command: "node",
        args: ["server.js"],
        env: %{"NODE_ENV" => "production", "PORT" => "3000"}
      }

      result = StdioServerConfig.to_map(config)

      assert result["type"] == "stdio"
      assert result["command"] == "node"
      assert result["args"] == ["server.js"]
      assert result["env"] == %{"NODE_ENV" => "production", "PORT" => "3000"}
    end

    test "to_map omits empty args and env" do
      config = %StdioServerConfig{command: "python", args: [], env: %{}}
      result = StdioServerConfig.to_map(config)

      assert result == %{"type" => "stdio", "command" => "python"}
      refute Map.has_key?(result, "args")
      refute Map.has_key?(result, "env")
    end

    test "to_map with args but empty env" do
      config = %StdioServerConfig{command: "python", args: ["script.py"], env: %{}}
      result = StdioServerConfig.to_map(config)

      assert result == %{"type" => "stdio", "command" => "python", "args" => ["script.py"]}
      refute Map.has_key?(result, "env")
    end

    test "to_map with env but empty args" do
      config = %StdioServerConfig{command: "python", args: [], env: %{"KEY" => "val"}}
      result = StdioServerConfig.to_map(config)

      assert result == %{"type" => "stdio", "command" => "python", "env" => %{"KEY" => "val"}}
      refute Map.has_key?(result, "args")
    end

    test "default struct values" do
      config = %StdioServerConfig{command: "test"}
      assert config.type == "stdio"
      assert config.args == []
      assert config.env == %{}
    end
  end

  describe "SSEServerConfig" do
    test "to_map with url only" do
      config = %SSEServerConfig{url: "http://localhost:8080/mcp"}
      result = SSEServerConfig.to_map(config)

      assert result == %{"type" => "sse", "url" => "http://localhost:8080/mcp"}
    end

    test "to_map with url and headers" do
      config = %SSEServerConfig{
        url: "http://localhost:8080/mcp",
        headers: %{"Authorization" => "Bearer token123"}
      }

      result = SSEServerConfig.to_map(config)

      assert result == %{
               "type" => "sse",
               "url" => "http://localhost:8080/mcp",
               "headers" => %{"Authorization" => "Bearer token123"}
             }
    end

    test "to_map omits empty headers" do
      config = %SSEServerConfig{url: "http://localhost/mcp", headers: %{}}
      result = SSEServerConfig.to_map(config)

      assert result == %{"type" => "sse", "url" => "http://localhost/mcp"}
      refute Map.has_key?(result, "headers")
    end

    test "default struct values" do
      config = %SSEServerConfig{url: "http://example.com"}
      assert config.type == "sse"
      assert config.headers == %{}
    end
  end

  describe "HttpServerConfig" do
    test "to_map with url only" do
      config = %HttpServerConfig{url: "http://localhost:9090/mcp"}
      result = HttpServerConfig.to_map(config)

      assert result == %{"type" => "http", "url" => "http://localhost:9090/mcp"}
    end

    test "to_map with url and headers" do
      config = %HttpServerConfig{
        url: "http://localhost:9090/mcp",
        headers: %{"X-API-Key" => "secret"}
      }

      result = HttpServerConfig.to_map(config)

      assert result == %{
               "type" => "http",
               "url" => "http://localhost:9090/mcp",
               "headers" => %{"X-API-Key" => "secret"}
             }
    end

    test "to_map omits empty headers" do
      config = %HttpServerConfig{url: "http://localhost/mcp", headers: %{}}
      result = HttpServerConfig.to_map(config)

      assert result == %{"type" => "http", "url" => "http://localhost/mcp"}
      refute Map.has_key?(result, "headers")
    end

    test "default struct values" do
      config = %HttpServerConfig{url: "http://example.com"}
      assert config.type == "http"
      assert config.headers == %{}
    end
  end
end
