#!/usr/bin/env bash

# Handle version check
if [ "$1" = "-v" ]; then echo "99.0.0"; exit 0; fi
# Mock CLI that initializes successfully, handles one query,
# but crashes when it receives a rewind/control request after streaming.
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

# Read the first user message
read -r user_line

# Send assistant response + result
echo "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Response.\"}],\"model\":\"mock-model\"},\"parent_tool_use_id\":null,\"error\":null}"
echo "{\"type\":\"result\",\"subtype\":\"success\",\"duration_ms\":100,\"duration_api_ms\":80,\"is_error\":false,\"num_turns\":1,\"session_id\":\"mock-session-1\",\"total_cost_usd\":0.001,\"usage\":{\"input_tokens\":10,\"output_tokens\":5},\"result\":\"Done.\"}"

# Read the next message (should be a rewind control_request) then crash
read -r rewind_line
exit 1
