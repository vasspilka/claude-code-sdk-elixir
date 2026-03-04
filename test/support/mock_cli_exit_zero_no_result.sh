#!/usr/bin/env bash
# Mock CLI that initializes and responds but exits cleanly without sending a result.
set -e

read -r init_line
request_id=$(echo "$init_line" | grep -o '"request_id":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -z "$request_id" ]; then
  request_id="req_unknown"
fi

echo "{\"type\":\"control_response\",\"response\":{\"request_id\":\"$request_id\",\"subtype\":\"success\"}}"

read -r user_line

echo "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Response without result.\"}],\"model\":\"mock-model\"},\"parent_tool_use_id\":null,\"error\":null}"

exit 0
