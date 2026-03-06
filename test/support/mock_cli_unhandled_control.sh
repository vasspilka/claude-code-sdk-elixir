#!/usr/bin/env bash
# Mock CLI that sends a control_request with an unknown subtype during streaming.
# Tests the unhandled control_request -> parse -> forward path.
set -e

# Read the initialize control request
read -r init_line

request_id=$(echo "$init_line" | grep -o '"request_id":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -z "$request_id" ]; then
  request_id="req_unknown"
fi

# Send control response for initialization
echo "{\"type\":\"control_response\",\"response\":{\"request_id\":\"$request_id\",\"subtype\":\"success\"}}"

# Read user message
read -r user_line

# Send an unhandled control_request (no handler registered for "some_unknown_subtype")
echo "{\"type\":\"control_request\",\"request_id\":\"req_unhandled\",\"request\":{\"subtype\":\"some_unknown_subtype\",\"data\":\"test\"}}"

# Send assistant message
echo "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Done.\"}],\"model\":\"mock-model\"},\"parent_tool_use_id\":null,\"error\":null}"

# Send result
echo "{\"type\":\"result\",\"subtype\":\"success\",\"duration_ms\":100,\"duration_api_ms\":80,\"is_error\":false,\"num_turns\":1,\"session_id\":\"mock-session\",\"total_cost_usd\":0.001,\"usage\":{\"input_tokens\":10,\"output_tokens\":5},\"result\":\"Done.\"}"

exit 0
