#!/usr/bin/env bash

# Mock CLI that reports a non-semver version string
if [ "$1" = "-v" ]; then echo "not-a-version"; exit 0; fi

set -e

read -r init_line
request_id=$(echo "$init_line" | grep -o '"request_id":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -z "$request_id" ]; then request_id="req_unknown"; fi

echo "{\"type\":\"control_response\",\"response\":{\"request_id\":\"$request_id\",\"subtype\":\"success\"}}"
echo "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"mock-session\"}"

read -r user_line
echo "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Hello.\"}],\"model\":\"mock-model\"},\"parent_tool_use_id\":null,\"error\":null}"
echo "{\"type\":\"result\",\"subtype\":\"success\",\"duration_ms\":100,\"duration_api_ms\":80,\"is_error\":false,\"num_turns\":1,\"session_id\":\"mock-session\",\"total_cost_usd\":0.001,\"usage\":{\"input_tokens\":10,\"output_tokens\":5},\"result\":\"Hello.\"}"

exit 0
