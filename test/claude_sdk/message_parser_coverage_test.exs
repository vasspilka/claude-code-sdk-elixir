defmodule ClaudeSDK.MessageParserCoverageTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.MessageParser

  describe "parse!/1" do
    test "returns parsed message on success" do
      raw = %{"type" => "system", "subtype" => "init"}
      msg = MessageParser.parse!(raw)
      assert msg.type == :system
      assert msg.subtype == "init"
    end

    test "raises ProtocolError on failure" do
      assert_raise ClaudeSDK.ProtocolError, ~r/Parse failed/, fn ->
        MessageParser.parse!(%{})
      end
    end

    test "returns raw map for unknown type (forward compatibility)" do
      raw = %{"type" => "totally_unknown", "data" => "something"}
      assert ^raw = MessageParser.parse!(raw)
    end
  end

  describe "parse unknown content block types" do
    test "unknown content block type is returned as-is" do
      raw = %{
        "type" => "assistant",
        "message" => %{
          "content" => [
            %{"type" => "text", "text" => "hello"},
            %{"type" => "future_block_type", "data" => "something"}
          ],
          "model" => "test"
        }
      }

      {:ok, msg} = MessageParser.parse(raw)
      [text_block, unknown_block] = msg.message.content
      assert %ClaudeSDK.Types.TextBlock{} = text_block
      assert unknown_block == %{"type" => "future_block_type", "data" => "something"}
    end
  end

  describe "parse tool_result content block" do
    test "parses tool_result block" do
      raw = %{
        "type" => "assistant",
        "message" => %{
          "content" => [
            %{
              "type" => "tool_result",
              "tool_use_id" => "toolu_123",
              "content" => "File contents here",
              "is_error" => false
            }
          ],
          "model" => "test"
        }
      }

      {:ok, msg} = MessageParser.parse(raw)
      [block] = msg.message.content
      assert %ClaudeSDK.Types.ToolResultBlock{} = block
      assert block.tool_use_id == "toolu_123"
      assert block.content == "File contents here"
      assert block.is_error == false
    end
  end

  describe "parse content blocks edge cases" do
    test "non-list content is converted to empty list" do
      raw = %{
        "type" => "assistant",
        "message" => %{
          "content" => "a plain string instead of list",
          "model" => "test"
        }
      }

      {:ok, msg} = MessageParser.parse(raw)
      assert msg.message.content == []
    end
  end

  describe "parse control_response" do
    test "parses control_response message" do
      raw = %{
        "type" => "control_response",
        "response" => %{"request_id" => "req_123", "subtype" => "success"}
      }

      {:ok, msg} = MessageParser.parse(raw)
      assert %ClaudeSDK.Types.ControlResponse{} = msg
      assert msg.response["request_id"] == "req_123"
    end
  end

  describe "parse result with structured_output" do
    test "parses structured_output field" do
      raw = %{
        "type" => "result",
        "subtype" => "success",
        "duration_ms" => 100,
        "duration_api_ms" => 80,
        "is_error" => false,
        "num_turns" => 1,
        "session_id" => "s1",
        "result" => ~s({"answer":"42"}),
        "structured_output" => %{"answer" => "42"}
      }

      {:ok, msg} = MessageParser.parse(raw)
      assert msg.structured_output == %{"answer" => "42"}
    end
  end
end
