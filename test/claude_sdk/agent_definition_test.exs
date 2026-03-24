defmodule ClaudeSDK.AgentDefinitionTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.Types.AgentDefinition

  describe "validate/1" do
    test "passes with all nil optional fields" do
      agent = %AgentDefinition{name: "a", description: "d", prompt: "p"}
      assert :ok = AgentDefinition.validate(agent)
    end

    test "passes with valid memory scopes" do
      for scope <- ["user", "project", "local"] do
        agent = %AgentDefinition{name: "a", description: "d", prompt: "p", memory: scope}
        assert :ok = AgentDefinition.validate(agent), "expected #{scope} to be valid"
      end
    end

    test "rejects invalid memory scope" do
      agent = %AgentDefinition{name: "a", description: "d", prompt: "p", memory: "banana"}
      assert {:error, msg} = AgentDefinition.validate(agent)
      assert msg =~ "agent memory must be one of"
      assert msg =~ "banana"
    end

    test "passes with valid model values" do
      for model <- ["sonnet", "opus", "haiku", "inherit"] do
        agent = %AgentDefinition{name: "a", description: "d", prompt: "p", model: model}
        assert :ok = AgentDefinition.validate(agent), "expected model #{model} to be valid"
      end
    end

    test "rejects invalid model" do
      agent = %AgentDefinition{name: "a", description: "d", prompt: "p", model: "gpt-4"}
      assert {:error, msg} = AgentDefinition.validate(agent)
      assert msg =~ "agent model must be one of"
      assert msg =~ "gpt-4"
    end

    test "rejects non-positive max_turns" do
      agent = %AgentDefinition{name: "a", description: "d", prompt: "p", max_turns: 0}
      assert {:error, msg} = AgentDefinition.validate(agent)
      assert msg =~ "max_turns must be a positive integer"
    end

    test "passes with valid max_turns" do
      agent = %AgentDefinition{name: "a", description: "d", prompt: "p", max_turns: 10}
      assert :ok = AgentDefinition.validate(agent)
    end
  end

  describe "normalize_agents raises on invalid agents" do
    test "raises ArgumentError for invalid memory scope" do
      agents = [
        %AgentDefinition{name: "bad", description: "d", prompt: "p", memory: "global"}
      ]

      assert_raise ArgumentError, ~r/invalid agent definition "bad"/, fn ->
        ClaudeSDK.Internal.normalize_agents(agents)
      end
    end

    test "raises ArgumentError for invalid model" do
      agents = [
        %AgentDefinition{name: "bad", description: "d", prompt: "p", model: "turbo"}
      ]

      assert_raise ArgumentError, ~r/invalid agent definition "bad"/, fn ->
        ClaudeSDK.Internal.normalize_agents(agents)
      end
    end

    test "passes through valid agents" do
      agents = [
        %AgentDefinition{
          name: "good",
          description: "d",
          prompt: "p",
          memory: "project",
          model: "haiku"
        }
      ]

      result = ClaudeSDK.Internal.normalize_agents(agents)
      assert [%{name: "good", memory: "project", model: "haiku"}] = result
    end

    test "passes through raw maps without validation" do
      agents = [%{name: "raw", description: "d", prompt: "p", memory: "anything"}]
      result = ClaudeSDK.Internal.normalize_agents(agents)
      assert [%{memory: "anything"}] = result
    end
  end

  describe "to_map/1" do
    test "includes all set fields with correct values" do
      agent = %AgentDefinition{
        name: "test-agent",
        description: "Test agent",
        prompt: "You are a test agent.",
        model: "haiku",
        tools: ["Read"],
        allowed_tools: ["Read", "Glob"],
        disallowed_tools: ["Bash"],
        max_turns: 5,
        skills: ["code-review"],
        memory: "user",
        mcp_servers: %{"srv" => %{"type" => "stdio", "command" => "echo"}}
      }

      map = AgentDefinition.to_map(agent)

      assert map.name == "test-agent"
      assert map.description == "Test agent"
      assert map.prompt == "You are a test agent."
      assert map.model == "haiku"
      assert map.tools == ["Read"]
      assert map.allowed_tools == ["Read", "Glob"]
      assert map.disallowed_tools == ["Bash"]
      assert map.max_turns == 5
      assert map.skills == ["code-review"]
      assert map.memory == "user"
      assert map.mcpServers == %{"srv" => %{"type" => "stdio", "command" => "echo"}}
    end

    test "omits nil optional fields" do
      agent = %AgentDefinition{
        name: "minimal",
        description: "Minimal agent",
        prompt: "You are minimal."
      }

      map = AgentDefinition.to_map(agent)

      assert map.name == "minimal"
      assert map.description == "Minimal agent"
      assert map.prompt == "You are minimal."

      refute Map.has_key?(map, :model)
      refute Map.has_key?(map, :tools)
      refute Map.has_key?(map, :allowed_tools)
      refute Map.has_key?(map, :disallowed_tools)
      refute Map.has_key?(map, :max_turns)
      refute Map.has_key?(map, :skills)
      refute Map.has_key?(map, :memory)
      refute Map.has_key?(map, :mcpServers)
    end

    test "preserves empty lists (not treated as nil)" do
      agent = %AgentDefinition{
        name: "with-empties",
        description: "Agent with empty lists",
        prompt: "Test.",
        tools: [],
        skills: []
      }

      map = AgentDefinition.to_map(agent)

      assert map.tools == []
      assert map.skills == []
    end

    test "output is JSON-encodable with correct camelCase keys" do
      agent = %AgentDefinition{
        name: "json-test",
        description: "JSON test",
        prompt: "Test.",
        model: "haiku",
        skills: ["a", "b"],
        memory: "project",
        mcp_servers: %{"s" => %{"type" => "stdio", "command" => "echo"}}
      }

      map = AgentDefinition.to_map(agent)
      assert {:ok, json} = Jason.encode(map)
      assert {:ok, decoded} = Jason.decode(json)

      assert decoded["name"] == "json-test"
      assert decoded["skills"] == ["a", "b"]
      assert decoded["memory"] == "project"
      assert decoded["mcpServers"]["s"]["type"] == "stdio"
    end
  end
end
