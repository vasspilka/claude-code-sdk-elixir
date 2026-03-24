defmodule ClaudeSDK.MessageParser do
  @moduledoc """
  Parses raw JSON maps from the CLI into typed message structs.

  This module is used internally by `ClaudeSDK.query/2` and `ClaudeSDK.Client`.
  You do not need to call it directly -- messages are automatically parsed
  before they appear in the stream.

  Routes on the `"type"` field and delegates content block parsing
  for assistant messages.
  """

  alias ClaudeSDK.Types.{
    AssistantMessage,
    ControlRequest,
    ControlResponse,
    RateLimitEvent,
    ResultMessage,
    StreamEvent,
    SystemMessage,
    TaskNotificationMessage,
    TaskProgressMessage,
    TaskStartedMessage,
    TextBlock,
    ThinkingBlock,
    ToolResultBlock,
    ToolUseBlock,
    UserMessage
  }

  @type parsed_message ::
          AssistantMessage.t()
          | UserMessage.t()
          | SystemMessage.t()
          | ResultMessage.t()
          | StreamEvent.t()
          | ControlRequest.t()
          | ControlResponse.t()
          | TaskStartedMessage.t()
          | TaskProgressMessage.t()
          | TaskNotificationMessage.t()
          | RateLimitEvent.t()

  @doc """
  Parse a raw JSON map into a typed message struct.

  Returns `{:ok, struct}` or `{:error, reason}`.
  """
  @spec parse(map()) :: {:ok, parsed_message()} | {:error, term()}
  def parse(%{"type" => "assistant"} = raw), do: {:ok, parse_assistant(raw)}
  def parse(%{"type" => "user"} = raw), do: {:ok, parse_user(raw)}
  def parse(%{"type" => "system"} = raw), do: {:ok, parse_system(raw)}
  def parse(%{"type" => "result"} = raw), do: {:ok, parse_result(raw)}
  def parse(%{"type" => "stream_event"} = raw), do: {:ok, parse_stream_event(raw)}
  def parse(%{"type" => "control_request"} = raw), do: {:ok, parse_control_request(raw)}
  def parse(%{"type" => "control_response"} = raw), do: {:ok, parse_control_response(raw)}
  def parse(%{"type" => "rate_limit"} = raw), do: {:ok, parse_rate_limit(raw)}
  def parse(%{"type" => "task_started"} = raw), do: {:ok, parse_task_started(raw)}
  def parse(%{"type" => "task_progress"} = raw), do: {:ok, parse_task_progress(raw)}
  def parse(%{"type" => "task_notification"} = raw), do: {:ok, parse_task_notification(raw)}
  def parse(%{"type" => _type} = raw), do: {:ok, raw}
  def parse(_), do: {:error, :missing_type}

  @doc "Parse or raise on failure."
  @spec parse!(map()) :: parsed_message()
  def parse!(raw) do
    case parse(raw) do
      {:ok, msg} ->
        msg

      {:error, reason} ->
        raise ClaudeSDK.ProtocolError, message: "Parse failed: #{inspect(reason)}", raw_data: raw
    end
  end

  # Assistant message

  defp parse_assistant(raw) do
    message = raw["message"] || %{}
    content = parse_content_blocks(message["content"] || [])

    %AssistantMessage{
      message: %{content: content, model: message["model"]},
      parent_tool_use_id: raw["parent_tool_use_id"],
      error: raw["error"],
      usage: message["usage"] || raw["usage"]
    }
  end

  # User message

  defp parse_user(raw) do
    message = raw["message"] || %{}

    %UserMessage{
      message: %{role: :user, content: message["content"] || ""},
      session_id: raw["session_id"] || "default",
      uuid: raw["uuid"],
      parent_tool_use_id: raw["parent_tool_use_id"]
    }
  end

  # System message

  defp parse_system(raw) do
    %SystemMessage{
      subtype: raw["subtype"] || "",
      data: Map.drop(raw, ["type", "subtype"])
    }
  end

  # Result message

  defp parse_result(raw) do
    %ResultMessage{
      subtype: raw["subtype"] || "success",
      duration_ms: raw["duration_ms"],
      duration_api_ms: raw["duration_api_ms"],
      is_error: raw["is_error"] || false,
      num_turns: raw["num_turns"],
      session_id: raw["session_id"],
      total_cost_usd: raw["total_cost_usd"],
      usage: raw["usage"] || %{},
      result: raw["result"],
      structured_output: raw["structured_output"],
      stop_reason: raw["stop_reason"]
    }
  end

  # Stream event

  defp parse_stream_event(raw) do
    %StreamEvent{
      uuid: raw["uuid"],
      session_id: raw["session_id"],
      event: raw["event"] || %{},
      parent_tool_use_id: raw["parent_tool_use_id"]
    }
  end

  # Control request

  defp parse_control_request(raw) do
    request = raw["request"]

    %ControlRequest{
      request_id: raw["request_id"] || "",
      request: if(is_map(request), do: request, else: %{})
    }
  end

  # Control response

  defp parse_control_response(raw) do
    %ControlResponse{
      response: raw["response"] || %{}
    }
  end

  # Rate limit event

  defp parse_rate_limit(raw) do
    %RateLimitEvent{
      rate_limit: Map.drop(raw, ["type"])
    }
  end

  # Task started

  defp parse_task_started(raw) do
    %TaskStartedMessage{
      task_id: raw["task_id"],
      description: raw["description"],
      uuid: raw["uuid"],
      session_id: raw["session_id"],
      tool_use_id: raw["tool_use_id"],
      task_type: raw["task_type"]
    }
  end

  # Task progress

  defp parse_task_progress(raw) do
    %TaskProgressMessage{
      task_id: raw["task_id"],
      description: raw["description"],
      usage: raw["usage"] || %{},
      uuid: raw["uuid"],
      session_id: raw["session_id"],
      last_tool_name: raw["last_tool_name"]
    }
  end

  # Task notification

  defp parse_task_notification(raw) do
    %TaskNotificationMessage{
      task_id: raw["task_id"],
      status: raw["status"],
      output_file: raw["output_file"],
      summary: raw["summary"],
      usage: raw["usage"] || %{}
    }
  end

  # Content block parsing

  defp parse_content_blocks(blocks) when is_list(blocks) do
    Enum.map(blocks, &parse_content_block/1)
  end

  defp parse_content_blocks(_), do: []

  defp parse_content_block(%{"type" => "text"} = block) do
    %TextBlock{text: block["text"] || ""}
  end

  defp parse_content_block(%{"type" => "thinking"} = block) do
    %ThinkingBlock{
      thinking: block["thinking"] || "",
      signature: block["signature"]
    }
  end

  defp parse_content_block(%{"type" => "tool_use"} = block) do
    %ToolUseBlock{
      id: block["id"] || "",
      name: block["name"] || "",
      input: block["input"] || %{}
    }
  end

  defp parse_content_block(%{"type" => "tool_result"} = block) do
    %ToolResultBlock{
      tool_use_id: block["tool_use_id"] || "",
      content: block["content"] || "",
      is_error: block["is_error"] || false
    }
  end

  defp parse_content_block(block) do
    # Unknown block type — return as-is for forward compatibility
    block
  end
end
