#!/usr/bin/env bash

# Handle version check
if [ "$1" = "-v" ]; then echo "99.0.0"; exit 0; fi
# Mock CLI that crashes immediately during initialization (before sending control_response).
exit 1
