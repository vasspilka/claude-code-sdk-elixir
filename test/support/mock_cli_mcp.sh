#!/usr/bin/env bash

# Handle version check
if [ "$1" = "-v" ]; then echo "99.0.0"; exit 0; fi
# Mock CLI that sends an mcp_message control_request with JSONRPC.
# Used for MCP integration tests.

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

# Send an MCP message control request with a tools/call JSONRPC
echo "{\"type\":\"control_request\",\"request_id\":\"req_mcp_001\",\"request\":{\"subtype\":\"mcp_message\",\"server_name\":\"test-server\",\"jsonrpc_message\":{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"greet\",\"arguments\":{\"name\":\"World\"}}}}}"

# Read the MCP response from SDK
read -r mcp_response

# Send assistant response
echo "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"MCP tool executed.\"}],\"model\":\"mock-model\"},\"parent_tool_use_id\":null,\"error\":null}"

# Send result
echo "{\"type\":\"result\",\"subtype\":\"success\",\"duration_ms\":100,\"duration_api_ms\":80,\"is_error\":false,\"num_turns\":1,\"session_id\":\"mock-session\",\"total_cost_usd\":0.001,\"usage\":{\"input_tokens\":10,\"output_tokens\":5},\"result\":\"Done.\"}"

exit 0
