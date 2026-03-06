defmodule ClaudeSDK.FixturesCoverageTest do
  use ExUnit.Case, async: true

  alias ClaudeSDK.Test.Fixtures

  describe "fixture functions produce valid JSON" do
    test "can_use_tool_request_json" do
      json = Fixtures.can_use_tool_request_json()
      assert json["type"] == "control_request"
      assert json["request"]["subtype"] == "can_use_tool"
      assert json["request"]["tool_name"] == "Bash"
    end

    test "mcp_message_request_json" do
      json = Fixtures.mcp_message_request_json()
      assert json["type"] == "control_request"
      assert json["request"]["subtype"] == "mcp_message"
      assert json["request"]["server_name"] == "test-server"
    end

    test "rewind_request_json" do
      json = Fixtures.rewind_request_json()
      assert json["type"] == "control_request"
      assert json["request"]["subtype"] == "rewind_files"
    end

    test "rewind_response_json" do
      json = Fixtures.rewind_response_json()
      assert json["type"] == "control_response"
      assert json["response"]["success"] == true
    end

    test "to_json_line encodes and adds newline" do
      fixture = %{"type" => "test"}
      line = Fixtures.to_json_line(fixture)
      assert String.ends_with?(line, "\n")
      assert {:ok, %{"type" => "test"}} = Jason.decode(String.trim(line))
    end

    test "result_with_structured_output_json" do
      json = Fixtures.result_with_structured_output_json()
      assert json["type"] == "result"
      assert json["structured_output"] == %{"answer" => "42"}
    end
  end
end
