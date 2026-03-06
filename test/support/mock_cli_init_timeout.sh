#!/usr/bin/env bash
# Mock CLI that reads the init request but never responds (hangs).
# Used to test init timeout.
set -e

# Read the initialize control request but never respond
read -r init_line

# Hang forever
sleep 3600
