defmodule ClaudeSDK.ClientRewindTest do
  use ExUnit.Case

  alias ClaudeSDK.Client
  alias ClaudeSDK.Types.Options

  @mock_cli_path Path.expand("../support/mock_cli_rewind.sh", __DIR__)

  describe "rewind_files/2" do
    test "sends rewind request and receives success response" do
      opts = %Options{
        cli_path: @mock_cli_path,
        enable_file_checkpointing: true
      }

      {:ok, client} = Client.start_link(options: opts)
      :ok = Client.connect(client)

      # First do a query to have something to rewind to
      _messages = Client.query(client, "First turn") |> Enum.to_list()

      # Rewind
      assert :ok = Client.rewind_files(client, "msg_001")

      # Can still query after rewind
      messages = Client.query(client, "After rewind") |> Enum.to_list()

      result =
        Enum.find(messages, fn
          %ClaudeSDK.Types.ResultMessage{} -> true
          _ -> false
        end)

      assert result != nil

      Client.close(client)
    end

    test "rewind before connect returns error" do
      opts = %Options{cli_path: @mock_cli_path, enable_file_checkpointing: true}
      {:ok, client} = Client.start_link(options: opts)

      assert {:error, {:invalid_state, :disconnected}} =
               Client.rewind_files(client, "msg_001")

      Client.close(client)
    end
  end
end
