#!/usr/bin/env bash
# Mock CLI that initializes but then sends an assistant message and hangs
# (never sends a result), to test message receive timeout.
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

# Send an assistant message but NO result — then hang
echo "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Thinking...\"}],\"model\":\"mock-model\"},\"parent_tool_use_id\":null,\"error\":null}"

# Sleep forever (hang)
sleep 3600
