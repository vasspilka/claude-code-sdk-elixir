#!/usr/bin/env bash

# Mock CLI that exits with a non-standard reason during init (after reading init but before responding)
if [ "$1" = "-v" ]; then echo "99.0.0"; exit 0; fi

read -r init_line
# Exit without sending control_response — simulates CLI crashing during init
exit 42
