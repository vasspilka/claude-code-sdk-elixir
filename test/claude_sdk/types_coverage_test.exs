defmodule ClaudeSDK.TypesCoverageTest do
  use ExUnit.Case, async: true

  describe "ThinkingConfig" do
    alias ClaudeSDK.Types.ThinkingConfig

    test "adaptive/0 creates adaptive config without budget" do
      config = ThinkingConfig.adaptive()
      assert config.type == "adaptive"
      assert config.budget_tokens == nil
    end

    test "adaptive/1 creates adaptive config with budget" do
      config = ThinkingConfig.adaptive(10_000)
      assert config.type == "adaptive"
      assert config.budget_tokens == 10_000
    end

    test "enabled/1 creates enabled config with budget" do
      config = ThinkingConfig.enabled(8_000)
      assert config.type == "enabled"
      assert config.budget_tokens == 8_000
    end

    test "disabled/0 creates disabled config" do
      config = ThinkingConfig.disabled()
      assert config.type == "disabled"
      assert config.budget_tokens == nil
    end

    test "to_map/1 without budget_tokens" do
      config = ThinkingConfig.disabled()
      map = ThinkingConfig.to_map(config)
      assert map == %{"type" => "disabled"}
      refute Map.has_key?(map, "budget_tokens")
    end

    test "to_map/1 with budget_tokens" do
      config = ThinkingConfig.adaptive(5000)
      map = ThinkingConfig.to_map(config)
      assert map == %{"type" => "adaptive", "budget_tokens" => 5000}
    end
  end

  describe "SandboxSettings" do
    alias ClaudeSDK.Types.SandboxSettings

    test "to_map/1 with defaults" do
      settings = %SandboxSettings{}
      map = SandboxSettings.to_map(settings)
      assert map.enabled == false
      assert map.autoAllowBashIfSandboxed == false
      refute Map.has_key?(map, :excludedCommands)
      refute Map.has_key?(map, :network)
    end

    test "to_map/1 with all fields" do
      settings = %SandboxSettings{
        enabled: true,
        auto_allow_bash_if_sandboxed: true,
        excluded_commands: ["rm", "kill"],
        network: "deny"
      }

      map = SandboxSettings.to_map(settings)
      assert map.enabled == true
      assert map.autoAllowBashIfSandboxed == true
      assert map[:excludedCommands] == ["rm", "kill"]
      assert map[:network] == "deny"
    end

    test "to_map/1 with empty excluded_commands" do
      settings = %SandboxSettings{excluded_commands: []}
      map = SandboxSettings.to_map(settings)
      refute Map.has_key?(map, :excludedCommands)
    end
  end

  describe "AgentDefinition" do
    alias ClaudeSDK.Types.AgentDefinition

    test "to_map/1 with required fields only" do
      agent = %AgentDefinition{
        name: "test",
        description: "Test agent",
        prompt: "You are a test"
      }

      map = AgentDefinition.to_map(agent)
      assert map.name == "test"
      assert map.description == "Test agent"
      assert map.prompt == "You are a test"
      refute Map.has_key?(map, :model)
      refute Map.has_key?(map, :tools)
    end

    test "to_map/1 with all optional fields" do
      agent = %AgentDefinition{
        name: "test",
        description: "Test agent",
        prompt: "You are a test",
        model: "claude-sonnet-4-20250514",
        tools: ["Read", "Write"],
        allowed_tools: ["Read"],
        disallowed_tools: ["Bash"],
        max_turns: 5
      }

      map = AgentDefinition.to_map(agent)
      assert map.model == "claude-sonnet-4-20250514"
      assert map.tools == ["Read", "Write"]
      assert map.allowed_tools == ["Read"]
      assert map.disallowed_tools == ["Bash"]
      assert map.max_turns == 5
    end
  end
end
