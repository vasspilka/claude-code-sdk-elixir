defmodule ClaudeSDK.Test.Fixtures do
  @moduledoc "JSON message fixtures for testing."

  def assistant_message_json do
    %{
      "type" => "assistant",
      "message" => %{
        "content" => [
          %{"type" => "text", "text" => "Hello! 2+2 equals 4."},
          %{
            "type" => "thinking",
            "thinking" => "The user asked about addition.",
            "signature" => "sig_abc"
          }
        ],
        "model" => "claude-sonnet-4-20250514"
      },
      "parent_tool_use_id" => nil,
      "error" => nil
    }
  end

  def assistant_with_tool_use_json do
    %{
      "type" => "assistant",
      "message" => %{
        "content" => [
          %{"type" => "text", "text" => "Let me read that file."},
          %{
            "type" => "tool_use",
            "id" => "toolu_01abc",
            "name" => "Read",
            "input" => %{"file_path" => "/tmp/test.txt"}
          }
        ],
        "model" => "claude-sonnet-4-20250514"
      },
      "parent_tool_use_id" => nil,
      "error" => nil
    }
  end

  def user_message_json do
    %{
      "type" => "user",
      "message" => %{
        "role" => "user",
        "content" => "What is 2+2?"
      },
      "session_id" => "test-session",
      "uuid" => "msg-123",
      "parent_tool_use_id" => nil
    }
  end

  def system_message_json do
    %{
      "type" => "system",
      "subtype" => "init",
      "session_id" => "test-session"
    }
  end

  def result_message_json do
    %{
      "type" => "result",
      "subtype" => "success",
      "duration_ms" => 1500,
      "duration_api_ms" => 1200,
      "is_error" => false,
      "num_turns" => 1,
      "session_id" => "test-session",
      "total_cost_usd" => 0.003,
      "usage" => %{"input_tokens" => 100, "output_tokens" => 50},
      "result" => "2+2 equals 4."
    }
  end

  def stream_event_json do
    %{
      "type" => "stream_event",
      "uuid" => "evt-456",
      "session_id" => "test-session",
      "event" => %{
        "type" => "content_block_delta",
        "delta" => %{"text" => "Hello"}
      },
      "parent_tool_use_id" => nil
    }
  end

  def control_request_json do
    %{
      "type" => "control_request",
      "request_id" => "req_abc123",
      "request" => %{
        "subtype" => "can_use_tool",
        "tool_name" => "Read",
        "input" => %{"file_path" => "/etc/passwd"}
      }
    }
  end

  def control_response_json do
    %{
      "type" => "control_response",
      "response" => %{
        "request_id" => "req_abc123",
        "subtype" => "success"
      }
    }
  end

  @doc "Encode a fixture as a JSON line (with trailing newline)."
  def to_json_line(fixture) do
    Jason.encode!(fixture) <> "\n"
  end
end
