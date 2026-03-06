defmodule ClaudeSDK.MessageParserTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.MessageParser

  alias ClaudeSDK.Types.{
    AssistantMessage,
    ControlRequest,
    ControlResponse,
    ResultMessage,
    StreamEvent,
    SystemMessage,
    TextBlock,
    ThinkingBlock,
    ToolResultBlock,
    ToolUseBlock,
    UserMessage
  }

  alias ClaudeSDK.Test.Fixtures

  describe "parse/1 — assistant messages" do
    test "parses assistant message with text and thinking blocks" do
      assert {:ok, %AssistantMessage{} = msg} =
               MessageParser.parse(Fixtures.assistant_message_json())

      assert msg.type == :assistant
      assert msg.message.model == "claude-sonnet-4-20250514"
      assert length(msg.message.content) == 2

      [text_block, thinking_block] = msg.message.content
      assert %TextBlock{text: "Hello! 2+2 equals 4."} = text_block

      assert %ThinkingBlock{thinking: "The user asked about addition.", signature: "sig_abc"} =
               thinking_block
    end

    test "parses assistant message with tool_use block" do
      assert {:ok, %AssistantMessage{} = msg} =
               MessageParser.parse(Fixtures.assistant_with_tool_use_json())

      [_text, tool_use] = msg.message.content

      assert %ToolUseBlock{
               id: "toolu_01abc",
               name: "Read",
               input: %{"file_path" => "/tmp/test.txt"}
             } = tool_use
    end

    test "handles missing content gracefully" do
      raw = %{"type" => "assistant", "message" => %{}}

      assert {:ok, %AssistantMessage{message: %{content: [], model: nil}}} =
               MessageParser.parse(raw)
    end

    test "preserves parent_tool_use_id" do
      raw = %{
        "type" => "assistant",
        "message" => %{"content" => []},
        "parent_tool_use_id" => "toolu_parent"
      }

      assert {:ok, %AssistantMessage{parent_tool_use_id: "toolu_parent"}} =
               MessageParser.parse(raw)
    end
  end

  describe "parse/1 — user messages" do
    test "parses user message" do
      assert {:ok, %UserMessage{} = msg} = MessageParser.parse(Fixtures.user_message_json())

      assert msg.type == :user
      assert msg.message.role == :user
      assert msg.message.content == "What is 2+2?"
      assert msg.session_id == "test-session"
      assert msg.uuid == "msg-123"
    end
  end

  describe "parse/1 — system messages" do
    test "parses system message" do
      assert {:ok, %SystemMessage{} = msg} = MessageParser.parse(Fixtures.system_message_json())

      assert msg.type == :system
      assert msg.subtype == "init"
      assert msg.data["session_id"] == "test-session"
    end
  end

  describe "parse/1 — result messages" do
    test "parses result message with all fields" do
      assert {:ok, %ResultMessage{} = msg} = MessageParser.parse(Fixtures.result_message_json())

      assert msg.type == :result
      assert msg.subtype == "success"
      assert msg.duration_ms == 1500
      assert msg.duration_api_ms == 1200
      assert msg.is_error == false
      assert msg.num_turns == 1
      assert msg.session_id == "test-session"
      assert msg.total_cost_usd == 0.003
      assert msg.usage == %{"input_tokens" => 100, "output_tokens" => 50}
      assert msg.result == "2+2 equals 4."
    end

    test "handles minimal result message" do
      raw = %{"type" => "result", "subtype" => "error", "is_error" => true}

      assert {:ok, %ResultMessage{subtype: "error", is_error: true}} = MessageParser.parse(raw)
    end
  end

  describe "parse/1 — stream events" do
    test "parses stream event" do
      assert {:ok, %StreamEvent{} = msg} = MessageParser.parse(Fixtures.stream_event_json())

      assert msg.type == :stream_event
      assert msg.uuid == "evt-456"
      assert msg.session_id == "test-session"
      assert msg.event["type"] == "content_block_delta"
    end
  end

  describe "parse/1 — control messages" do
    test "parses control request" do
      assert {:ok, %ControlRequest{} = msg} = MessageParser.parse(Fixtures.control_request_json())

      assert msg.type == :control_request
      assert msg.request_id == "req_abc123"
      assert msg.request["subtype"] == "can_use_tool"
    end

    test "parses control response" do
      assert {:ok, %ControlResponse{} = msg} =
               MessageParser.parse(Fixtures.control_response_json())

      assert msg.type == :control_response
      assert msg.response["subtype"] == "success"
    end
  end

  describe "parse/1 — unknown and missing types" do
    test "returns raw map for unknown type (forward compatibility)" do
      raw = %{"type" => "alien", "data" => "hello"}
      assert {:ok, ^raw} = MessageParser.parse(raw)
    end

    test "returns error for missing type" do
      assert {:error, :missing_type} = MessageParser.parse(%{"data" => "no type"})
    end
  end

  describe "parse!/1" do
    test "returns struct on success" do
      assert %AssistantMessage{} = MessageParser.parse!(Fixtures.assistant_message_json())
    end

    test "raises ProtocolError on failure" do
      assert_raise ClaudeSDK.ProtocolError, fn ->
        MessageParser.parse!(%{"no_type" => true})
      end
    end
  end

  describe "parse/1 — task messages" do
    test "parses TaskStartedMessage" do
      raw = Fixtures.task_started_json()

      assert {:ok, %ClaudeSDK.Types.TaskStartedMessage{} = msg} = MessageParser.parse(raw)

      assert msg.type == :task_started
      assert msg.task_id == "task-001"
      assert msg.description == "Analyzing code structure"
      assert msg.uuid == "msg-task-001"
      assert msg.session_id == "test-session"
      assert msg.tool_use_id == "toolu_task_01"
      assert msg.task_type == "agent"
    end

    test "parses TaskProgressMessage" do
      raw = Fixtures.task_progress_json()

      assert {:ok, %ClaudeSDK.Types.TaskProgressMessage{} = msg} = MessageParser.parse(raw)

      assert msg.type == :task_progress
      assert msg.task_id == "task-001"
      assert msg.description == "Reading files"
      assert msg.usage == %{"total_tokens" => 5000, "tool_uses" => 3, "duration_ms" => 2500}
      assert msg.uuid == "msg-task-002"
      assert msg.session_id == "test-session"
      assert msg.last_tool_name == "Read"
    end

    test "parses TaskNotificationMessage" do
      raw = Fixtures.task_notification_json()

      assert {:ok, %ClaudeSDK.Types.TaskNotificationMessage{} = msg} = MessageParser.parse(raw)

      assert msg.type == :task_notification
      assert msg.task_id == "task-001"
      assert msg.status == "completed"
      assert msg.output_file == "/tmp/task-output.json"
      assert msg.summary == "Successfully analyzed 5 files"
      assert msg.usage == %{"total_tokens" => 15000, "tool_uses" => 8, "duration_ms" => 10000}
    end

    test "parses TaskStartedMessage with minimal fields" do
      raw = %{"type" => "task_started", "task_id" => "t1"}

      assert {:ok, %ClaudeSDK.Types.TaskStartedMessage{task_id: "t1", description: nil}} =
               MessageParser.parse(raw)
    end

    test "parses TaskNotificationMessage with failed status" do
      raw = %{
        "type" => "task_notification",
        "task_id" => "t2",
        "status" => "failed",
        "summary" => "Task encountered an error"
      }

      assert {:ok, %ClaudeSDK.Types.TaskNotificationMessage{status: "failed"}} =
               MessageParser.parse(raw)
    end
  end

  describe "parse/1 — ResultMessage with structured_output" do
    test "parses structured_output field when present" do
      raw = Fixtures.result_with_structured_output_json()

      assert {:ok, %ResultMessage{} = msg} = MessageParser.parse(raw)

      assert msg.structured_output == %{"answer" => "42"}
      assert msg.result == ~s({"answer": "42"})
    end

    test "structured_output is nil when not present" do
      raw = Fixtures.result_message_json()

      assert {:ok, %ResultMessage{} = msg} = MessageParser.parse(raw)

      assert msg.structured_output == nil
    end
  end

  describe "content block parsing" do
    test "parses tool_result blocks" do
      raw = %{
        "type" => "assistant",
        "message" => %{
          "content" => [
            %{
              "type" => "tool_result",
              "tool_use_id" => "toolu_01x",
              "content" => "file contents here",
              "is_error" => false
            }
          ]
        }
      }

      assert {:ok, %AssistantMessage{message: %{content: [block]}}} = MessageParser.parse(raw)

      assert %ToolResultBlock{
               tool_use_id: "toolu_01x",
               content: "file contents here",
               is_error: false
             } = block
    end

    test "preserves unknown block types as raw maps" do
      raw = %{
        "type" => "assistant",
        "message" => %{
          "content" => [%{"type" => "future_type", "data" => "something"}]
        }
      }

      assert {:ok, %AssistantMessage{message: %{content: [block]}}} = MessageParser.parse(raw)
      assert %{"type" => "future_type", "data" => "something"} = block
    end
  end
end
