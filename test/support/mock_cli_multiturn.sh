#!/usr/bin/env bash
# Mock CLI that stays alive across multiple user messages.
# Sends a result per turn but does not exit until stdin closes.

set -e

# Read the initialize control request
read -r init_line

# Extract request_id from the initialize request
request_id=$(echo "$init_line" | grep -o '"request_id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$request_id" ]; then
  request_id="req_unknown"
fi

# Send control response for initialization
echo "{\"type\":\"control_response\",\"response\":{\"request_id\":\"$request_id\",\"subtype\":\"success\"}}"

# Send system init message
echo "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"mock-session\"}"

turn=0

# Read user messages in a loop
while read -r user_line; do
  turn=$((turn + 1))

  # Check if it's a control_request (e.g. rewind) vs user message
  msg_type=$(echo "$user_line" | grep -o '"type":"[^"]*"' | head -1 | cut -d'"' -f4)

  if [ "$msg_type" = "control_request" ]; then
    # Extract request_id for the control request
    ctrl_req_id=$(echo "$user_line" | grep -o '"request_id":"[^"]*"' | head -1 | cut -d'"' -f4)
    echo "{\"type\":\"control_response\",\"response\":{\"request_id\":\"$ctrl_req_id\",\"success\":true}}" 2>/dev/null
    continue
  fi

  # Send assistant response for this turn
  echo "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Turn $turn response.\"}],\"model\":\"mock-model\"},\"parent_tool_use_id\":null,\"error\":null}" 2>/dev/null || true

  # Send result
  echo "{\"type\":\"result\",\"subtype\":\"success\",\"duration_ms\":100,\"duration_api_ms\":80,\"is_error\":false,\"num_turns\":$turn,\"session_id\":\"mock-session-$turn\",\"total_cost_usd\":0.001,\"usage\":{\"input_tokens\":10,\"output_tokens\":5},\"result\":\"Turn $turn done.\"}" 2>/dev/null || true
done

exit 0
