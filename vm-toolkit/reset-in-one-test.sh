#!/bin/bash

# Wrapper: the reset-in-one test script lives under tests/ now.
# This wrapper forwards to the new location for back-compat.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/tests/reset-in-one-test.sh" "$@"
