#!/usr/bin/env bash

# Handle version check
if [ "$1" = "-v" ]; then echo "99.0.0"; exit 0; fi
# Mock CLI that outputs non-JSON (stderr) lines and then exits with non-zero status.
# Used to test stderr accumulation in ProcessExitError.

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

# Output stderr-like diagnostic lines (non-JSON, so they get accumulated)
echo "Error: Cannot connect to API"
echo "Traceback: auth_handler.js:42"
echo "Fatal: unrecoverable error, shutting down"

# Exit with non-zero status
exit 1
