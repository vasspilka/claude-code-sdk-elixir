#!/usr/bin/env bash

# Handle version check
if [ "$1" = "-v" ]; then echo "99.0.0"; exit 0; fi
# Mock CLI that handles rewind_files control_request.
# Stays alive across turns like mock_cli_multiturn.sh.

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

# Read messages in a loop
while read -r line; do
  msg_type=$(echo "$line" | grep -o '"type":"[^"]*"' | head -1 | cut -d'"' -f4)

  if [ "$msg_type" = "control_request" ]; then
    ctrl_req_id=$(echo "$line" | grep -o '"request_id":"[^"]*"' | head -1 | cut -d'"' -f4)
    subtype=$(echo "$line" | grep -o '"subtype":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ "$subtype" = "rewind_files" ]; then
      echo "{\"type\":\"control_response\",\"response\":{\"request_id\":\"$ctrl_req_id\",\"success\":true}}" 2>/dev/null || true
    else
      echo "{\"type\":\"control_response\",\"response\":{\"request_id\":\"$ctrl_req_id\",\"subtype\":\"success\"}}" 2>/dev/null || true
    fi
    continue
  fi

  turn=$((turn + 1))

  # Send assistant response
  echo "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Turn $turn response.\"}],\"model\":\"mock-model\"},\"parent_tool_use_id\":null,\"error\":null}" 2>/dev/null || true

  # Send result
  echo "{\"type\":\"result\",\"subtype\":\"success\",\"duration_ms\":100,\"duration_api_ms\":80,\"is_error\":false,\"num_turns\":$turn,\"session_id\":\"mock-session-$turn\",\"total_cost_usd\":0.001,\"usage\":{\"input_tokens\":10,\"output_tokens\":5},\"result\":\"Turn $turn done.\"}" 2>/dev/null || true
done

exit 0
