defmodule ClaudeSDK.LiveClientOperationsTest do
  @moduledoc """
  Live integration tests for Client mid-session operations.

  Tests set_model, set_permission_mode, get_server_info, get_mcp_status,
  interrupt, with_client, and connected? against the real CLI.

  Run with: mix test --only live
  """

  use ExUnit.Case

  alias ClaudeSDK.Client
  alias ClaudeSDK.Types.{AssistantMessage, Options, ResultMessage, TextBlock}

  @moduletag :live

  @base_opts %Options{
    permission_mode: :bypass_permissions,
    max_turns: 1,
    model: "claude-haiku-4-5-20251001"
  }

  defp extract_text(messages) do
    messages
    |> Enum.flat_map(fn
      %AssistantMessage{message: %{content: content}} -> content
      _ -> []
    end)
    |> Enum.filter(&match?(%TextBlock{}, &1))
    |> Enum.map(& &1.text)
    |> Enum.join(" ")
  end

  defp find_result(messages), do: Enum.find(messages, &match?(%ResultMessage{}, &1))

  # ---------------------------------------------------------------------------
  # 1. with_client convenience wrapper
  # ---------------------------------------------------------------------------
  describe "with_client/2" do
    @tag timeout: 120_000
    test "auto-connects, runs callback, and cleans up" do
      result =
        Client.with_client([options: @base_opts], fn client ->
          assert Client.connected?(client)

          messages =
            Client.query(client, "Say ok")
            |> Enum.to_list()

          find_result(messages)
        end)

      assert %ResultMessage{} = result
      refute result.is_error
    end

    @tag timeout: 120_000
    test "cleans up even when callback raises" do
      assert_raise RuntimeError, "intentional", fn ->
        Client.with_client([options: @base_opts], fn _client ->
          raise "intentional"
        end)
      end

      # If we get here without hanging, cleanup worked
    end
  end

  # ---------------------------------------------------------------------------
  # 2. get_server_info
  # ---------------------------------------------------------------------------
  describe "get_server_info/1" do
    @tag timeout: 120_000
    test "returns server info after connect" do
      Client.with_client([options: @base_opts], fn client ->
        {:ok, info} = Client.get_server_info(client)
        assert is_map(info)
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # 3. get_mcp_status
  # ---------------------------------------------------------------------------
  describe "get_mcp_status/1" do
    @tag timeout: 120_000
    test "returns MCP status map" do
      Client.with_client([options: @base_opts], fn client ->
        {:ok, status} = Client.get_mcp_status(client)
        assert is_map(status)
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # 4. set_model mid-session
  # ---------------------------------------------------------------------------
  describe "set_model/2" do
    @tag timeout: 180_000
    test "changes model mid-session without error" do
      Client.with_client([options: @base_opts], fn client ->
        # First query with haiku
        messages1 = Client.query(client, "Say A") |> Enum.to_list()
        assert find_result(messages1) != nil

        # Switch model (fire-and-forget)
        assert :ok = Client.set_model(client, "claude-haiku-4-5-20251001")

        # Second query should still work
        messages2 = Client.query(client, "Say B") |> Enum.to_list()
        result2 = find_result(messages2)
        assert result2 != nil
        refute result2.is_error
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # 5. set_permission_mode mid-session
  # ---------------------------------------------------------------------------
  describe "set_permission_mode/2" do
    @tag timeout: 120_000
    test "changes permission mode mid-session" do
      Client.with_client([options: @base_opts], fn client ->
        assert :ok = Client.set_permission_mode(client, :bypass_permissions)
        messages = Client.query(client, "Say ok") |> Enum.to_list()
        assert find_result(messages) != nil
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # 6. connected? reflects state
  # ---------------------------------------------------------------------------
  describe "connected?/1" do
    @tag timeout: 120_000
    test "returns true after connect, false after close" do
      {:ok, client} = Client.start_link(options: @base_opts)
      refute Client.connected?(client)

      :ok = Client.connect(client)
      assert Client.connected?(client)

      Client.close(client)
      # After close, the process is dead
      refute Client.connected?(client)
    end
  end

  # ---------------------------------------------------------------------------
  # 7. Multi-turn with streaming text extraction
  # ---------------------------------------------------------------------------
  describe "multi-turn text extraction" do
    @tag timeout: 180_000
    test "text from multiple turns is independently extractable" do
      Client.with_client([options: @base_opts], fn client ->
        messages1 = Client.query(client, "Say exactly: ALPHA") |> Enum.to_list()
        text1 = extract_text(messages1)
        assert String.contains?(text1, "ALPHA"), "Turn 1 should contain ALPHA, got: #{text1}"

        messages2 = Client.query(client, "Say exactly: BETA") |> Enum.to_list()
        text2 = extract_text(messages2)
        assert String.contains?(text2, "BETA"), "Turn 2 should contain BETA, got: #{text2}"
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # 8. Query while not connected
  # ---------------------------------------------------------------------------
  describe "error states" do
    @tag timeout: 60_000
    test "query before connect raises QueryError" do
      {:ok, client} = Client.start_link(options: @base_opts)

      assert_raise ClaudeSDK.QueryError, fn ->
        Client.query(client, "hello") |> Enum.to_list()
      end

      Client.close(client)
    end
  end
end
