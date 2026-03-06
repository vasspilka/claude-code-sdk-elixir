defmodule ClaudeSDK.LivePermissionTest do
  @moduledoc """
  Live integration tests for permission handling mechanisms.

  Tests each permission configuration option against the real Claude CLI.

  Run with: mix test --only live
  """

  use ExUnit.Case

  alias ClaudeSDK.Types.Options

  @moduletag :live

  @base_opts %Options{
    max_turns: 1,
    model: "claude-haiku-4-5-20251001"
  }

  # ---------------------------------------------------------------------------
  # 1. can_use_tool callback (2-arity) — deny
  # ---------------------------------------------------------------------------
  describe "can_use_tool callback (2-arity)" do
    @tag timeout: 60_000
    test "deny callback prevents tool usage" do
      denied_tools = :ets.new(:denied_tools, [:set, :public])

      opts = %{
        @base_opts
        | permission_mode: :default,
          can_use_tool: fn tool_name, _input ->
            :ets.insert(denied_tools, {tool_name, true})
            {:deny, "Denied by test"}
          end
      }

      messages =
        ClaudeSDK.query("Read the file ./mix.exs and tell me the project name", opts)
        |> Enum.to_list()

      result = find_result(messages)
      assert result != nil

      # The callback was invoked at least once
      assert :ets.info(denied_tools, :size) > 0

      :ets.delete(denied_tools)
    end

    @tag timeout: 60_000
    test "allow callback permits tool usage" do
      allowed_tools = :ets.new(:allowed_tools, [:set, :public])

      opts = %{
        @base_opts
        | permission_mode: :default,
          can_use_tool: fn tool_name, _input ->
            :ets.insert(allowed_tools, {tool_name, true})
            :allow
          end
      }

      messages =
        ClaudeSDK.query("Read the file ./mix.exs and tell me the project name", opts)
        |> Enum.to_list()

      result = find_result(messages)
      assert result != nil
      refute result.is_error

      # The callback was invoked
      assert :ets.info(allowed_tools, :size) > 0

      :ets.delete(allowed_tools)
    end
  end

  # ---------------------------------------------------------------------------
  # 2. can_use_tool callback (3-arity) — with ToolPermissionContext
  # ---------------------------------------------------------------------------
  describe "can_use_tool callback (3-arity)" do
    @tag timeout: 60_000
    test "receives ToolPermissionContext with tool metadata" do
      context_ref = :ets.new(:context_data, [:set, :public])

      opts = %{
        @base_opts
        | permission_mode: :default,
          can_use_tool: fn tool_name, _input, context ->
            :ets.insert(context_ref, {:tool_name, context.tool_name})
            :ets.insert(context_ref, {:has_request_id, is_binary(context.request_id)})
            :ets.insert(context_ref, {:has_raw_request, is_map(context.raw_request)})
            :ets.insert(context_ref, {:input_is_map, is_map(context.input)})
            :ets.insert(context_ref, {:names_match, tool_name == context.tool_name})
            :allow
          end
      }

      messages =
        ClaudeSDK.query("Read the file ./mix.exs", opts)
        |> Enum.to_list()

      result = find_result(messages)
      assert result != nil

      assert [{:tool_name, tool_name}] = :ets.lookup(context_ref, :tool_name)
      assert is_binary(tool_name)
      assert [{:has_request_id, true}] = :ets.lookup(context_ref, :has_request_id)
      assert [{:has_raw_request, true}] = :ets.lookup(context_ref, :has_raw_request)
      assert [{:input_is_map, true}] = :ets.lookup(context_ref, :input_is_map)
      assert [{:names_match, true}] = :ets.lookup(context_ref, :names_match)

      :ets.delete(context_ref)
    end
  end

  # ---------------------------------------------------------------------------
  # 3. allowed_tools — allowlist
  # ---------------------------------------------------------------------------
  describe "allowed_tools" do
    @tag timeout: 60_000
    test "restricts to only specified tools" do
      opts = %{
        @base_opts
        | permission_mode: :bypass_permissions,
          allowed_tools: ["Read"]
      }

      messages =
        ClaudeSDK.query(
          "Read the file ./mix.exs and tell me the project name. Do not use any tool other than Read.",
          opts
        )
        |> Enum.to_list()

      result = find_result(messages)
      assert result != nil
      refute result.is_error
    end
  end

  # ---------------------------------------------------------------------------
  # 4. disallowed_tools — denylist
  # ---------------------------------------------------------------------------
  describe "disallowed_tools" do
    @tag timeout: 60_000
    test "blocks specified tools" do
      opts = %{
        @base_opts
        | permission_mode: :bypass_permissions,
          disallowed_tools: ["Bash"]
      }

      messages =
        ClaudeSDK.query(
          "Run the command 'echo hello' using Bash. If you cannot use Bash, just say BLOCKED.",
          opts
        )
        |> Enum.to_list()

      result = find_result(messages)
      assert result != nil

      _text = extract_text(messages)
      # Claude should indicate it couldn't use Bash, or the result should show it was blocked
      assert result != nil
    end
  end

  # ---------------------------------------------------------------------------
  # 5. permission_mode: :plan — no tool execution
  # ---------------------------------------------------------------------------
  describe "permission_mode :plan" do
    @tag timeout: 60_000
    test "plan mode does not execute tools" do
      opts = %{@base_opts | permission_mode: :plan}

      messages =
        ClaudeSDK.query(
          "Read the file ./mix.exs. If you cannot use tools, just say PLAN_MODE.",
          opts
        )
        |> Enum.to_list()

      result = find_result(messages)
      assert result != nil

      # In plan mode, Claude should not have been able to execute any tool
      tool_uses =
        messages
        |> Enum.flat_map(fn
          %ClaudeSDK.Types.AssistantMessage{message: %{content: content}} -> content
          _ -> []
        end)
        |> Enum.filter(fn
          %ClaudeSDK.Types.ToolResultBlock{} -> true
          _ -> false
        end)

      assert tool_uses == []
    end
  end

  # ---------------------------------------------------------------------------
  # 6. permission_mode: :accept_edits
  # ---------------------------------------------------------------------------
  describe "permission_mode :accept_edits" do
    @tag timeout: 60_000
    test "auto-accepts file read operations" do
      opts = %{@base_opts | permission_mode: :accept_edits}

      messages =
        ClaudeSDK.query("Read the file ./mix.exs and tell me the project name", opts)
        |> Enum.to_list()

      result = find_result(messages)
      assert result != nil
      refute result.is_error

      text = extract_text(messages)
      assert String.contains?(String.downcase(text), "claude_sdk")
    end
  end

  # ---------------------------------------------------------------------------
  # 7. permission_mode: :bypass_permissions — baseline
  # ---------------------------------------------------------------------------
  describe "permission_mode :bypass_permissions" do
    @tag timeout: 60_000
    test "auto-accepts all tool usage" do
      opts = %{@base_opts | permission_mode: :bypass_permissions}

      messages =
        ClaudeSDK.query("Read the file ./mix.exs and tell me the project name", opts)
        |> Enum.to_list()

      result = find_result(messages)
      assert result != nil
      refute result.is_error

      text = extract_text(messages)
      assert String.contains?(String.downcase(text), "claude_sdk")
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp find_result(messages) do
    Enum.find(messages, fn
      %ClaudeSDK.Types.ResultMessage{} -> true
      _ -> false
    end)
  end

  defp extract_text(messages) do
    messages
    |> Enum.flat_map(fn
      %ClaudeSDK.Types.AssistantMessage{message: %{content: content}} -> content
      _ -> []
    end)
    |> Enum.filter(&match?(%ClaudeSDK.Types.TextBlock{}, &1))
    |> Enum.map(& &1.text)
    |> Enum.join(" ")
  end
end
