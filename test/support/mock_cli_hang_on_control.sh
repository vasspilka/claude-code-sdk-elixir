#!/usr/bin/env bash
# Mock CLI that initializes and handles queries but hangs on control requests
# (does not respond to rewind/mcp/model control_requests after streaming).
set -e

# Read the initialize control request
read -r init_line

request_id=$(echo "$init_line" | grep -o '"request_id":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -z "$request_id" ]; then
  request_id="req_unknown"
fi

# Send control response for initialization
echo "{\"type\":\"control_response\",\"response\":{\"request_id\":\"$request_id\",\"subtype\":\"success\"}}"

# Send system init message
echo "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"mock-session\"}"

# Read user messages in a loop
while read -r user_line; do
  msg_type=$(echo "$user_line" | grep -o '"type":"[^"]*"' | head -1 | cut -d'"' -f4)

  if [ "$msg_type" = "control_request" ]; then
    # Deliberately do NOT respond — hang until stdin closes
    # Keep reading to stay alive
    while read -r discard_line; do
      :
    done
    exit 0
  fi

  # Send assistant response + result for user messages
  echo "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Response.\"}],\"model\":\"mock-model\"},\"parent_tool_use_id\":null,\"error\":null}"
  echo "{\"type\":\"result\",\"subtype\":\"success\",\"duration_ms\":100,\"duration_api_ms\":80,\"is_error\":false,\"num_turns\":1,\"session_id\":\"mock-session\",\"total_cost_usd\":0.001,\"usage\":{\"input_tokens\":10,\"output_tokens\":5},\"result\":\"Done.\"}"
done

exit 0
