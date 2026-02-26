#!/usr/bin/env bash
# Mock Claude CLI for integration testing.
# Reads stdin for JSON messages, responds with canned output on stdout.
# Expects: initialize control request, then user message.

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

# Send assistant response
echo "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"The answer is 4.\"}],\"model\":\"mock-model\"},\"parent_tool_use_id\":null,\"error\":null}"

# Send result
echo "{\"type\":\"result\",\"subtype\":\"success\",\"duration_ms\":100,\"duration_api_ms\":80,\"is_error\":false,\"num_turns\":1,\"session_id\":\"mock-session\",\"total_cost_usd\":0.001,\"usage\":{\"input_tokens\":10,\"output_tokens\":5},\"result\":\"The answer is 4.\"}"

exit 0
