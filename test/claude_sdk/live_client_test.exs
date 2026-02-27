defmodule ClaudeSDK.LiveClientTest do
  @moduledoc """
  Live integration tests for the stateful Client GenServer.

  Run with: mix test --only live
  """

  use ExUnit.Case

  alias ClaudeSDK.Client
  alias ClaudeSDK.Types.Options

  @moduletag :live

  describe "client lifecycle" do
    @tag timeout: 120_000
    test "connect, query, and close" do
      opts = %Options{
        permission_mode: :bypass_permissions,
        max_turns: 1,
        model: "claude-haiku-4-5-20251001"
      }

      {:ok, client} = Client.start_link(options: opts)
      assert :ok = Client.connect(client)

      messages =
        Client.query(client, "Reply with exactly: clienttest")
        |> Enum.to_list()

      assert length(messages) >= 1

      result =
        Enum.find(messages, fn
          %ClaudeSDK.Types.ResultMessage{} -> true
          _ -> false
        end)

      assert result != nil
      refute result.is_error

      Client.close(client)
    end

    @tag timeout: 180_000
    test "multi-turn conversation maintains context" do
      opts = %Options{
        permission_mode: :bypass_permissions,
        max_turns: 1,
        model: "claude-haiku-4-5-20251001"
      }

      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      # First turn: establish a fact
      _messages1 =
        Client.query(client, "Remember this secret code: XRAY42. Just say 'noted'.")
        |> Enum.to_list()

      # Second turn: recall the fact
      messages2 =
        Client.query(client, "What was the secret code I told you?")
        |> Enum.to_list()

      text =
        messages2
        |> Enum.flat_map(fn
          %ClaudeSDK.Types.AssistantMessage{message: %{content: content}} -> content
          _ -> []
        end)
        |> Enum.filter(&match?(%ClaudeSDK.Types.TextBlock{}, &1))
        |> Enum.map(& &1.text)
        |> Enum.join(" ")

      assert String.contains?(text, "XRAY42"),
             "Expected response to contain 'XRAY42', got: #{text}"

      Client.close(client)
    end
  end
end
