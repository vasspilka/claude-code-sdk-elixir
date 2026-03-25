#!/usr/bin/env bash

# Handle version check
if [ "$1" = "-v" ]; then echo "99.0.0"; exit 0; fi
# Mock CLI that reads the init request but never responds (hangs).
# Used to test init timeout.
set -e

# Read the initialize control request but never respond
read -r init_line

# Hang forever
sleep 3600
