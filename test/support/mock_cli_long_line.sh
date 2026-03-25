#!/usr/bin/env bash

# Handle version check
if [ "$1" = "-v" ]; then echo "99.0.0"; exit 0; fi
# Mock CLI that outputs a line exceeding the Port's {:line, 1_048_576} limit.
# This triggers the :noeol handling path in Subprocess.
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

# Read the user message
read -r user_line

# Build a JSON line >1MB using printf to avoid shell limits.
# Write the opening JSON, then a long text block, then closing JSON, then newline.
# All written without a newline until the end, so it's one logical line.
{
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"'
  # Write 1.1M 'a' characters using dd for efficiency
  dd if=/dev/zero bs=1100000 count=1 2>/dev/null | tr '\0' 'a'
  printf '"}],"model":"mock-model"},"parent_tool_use_id":null,"error":null}\n'
}

# Send result
echo "{\"type\":\"result\",\"subtype\":\"success\",\"duration_ms\":100,\"duration_api_ms\":80,\"is_error\":false,\"num_turns\":1,\"session_id\":\"mock-session\",\"total_cost_usd\":0.001,\"usage\":{\"input_tokens\":10,\"output_tokens\":5},\"result\":\"Done.\"}"

exit 0
