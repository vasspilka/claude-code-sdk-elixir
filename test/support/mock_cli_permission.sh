#!/usr/bin/env bash

# Handle version check
if [ "$1" = "-v" ]; then echo "99.0.0"; exit 0; fi
# Mock CLI that sends a can_use_tool control_request and reads the response.
# Used for permission callback integration tests.

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

# Read the user message
read -r user_line

# Send a can_use_tool control request
echo "{\"type\":\"control_request\",\"request_id\":\"req_perm_001\",\"request\":{\"subtype\":\"can_use_tool\",\"tool_name\":\"Bash\",\"input\":{\"command\":\"rm -rf /\"}}}"

# Read the permission response from SDK
read -r perm_response

# Check if allowed or denied
allowed=$(echo "$perm_response" | grep -o '"allowed":true' || true)

if [ -n "$allowed" ]; then
  echo "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Tool was allowed.\"}],\"model\":\"mock-model\"},\"parent_tool_use_id\":null,\"error\":null}" 2>/dev/null || true
else
  echo "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Tool was denied.\"}],\"model\":\"mock-model\"},\"parent_tool_use_id\":null,\"error\":null}" 2>/dev/null || true
fi

# Send result
echo "{\"type\":\"result\",\"subtype\":\"success\",\"duration_ms\":100,\"duration_api_ms\":80,\"is_error\":false,\"num_turns\":1,\"session_id\":\"mock-session\",\"total_cost_usd\":0.001,\"usage\":{\"input_tokens\":10,\"output_tokens\":5},\"result\":\"Done.\"}" 2>/dev/null || true

exit 0
