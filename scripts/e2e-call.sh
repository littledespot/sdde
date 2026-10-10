#!/bin/sh
# Test one captured model call through the development-only diagnostic harness.
set -eu

call_e2e_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
cd -- "$call_e2e_root"

# Match the full-workflow launcher: help never evaluates the credential file,
# and an optional local file replaces values for names it exports.
if [ "$#" -ne 1 ] || [ "$1" != "--help" ]; then
    if [ -f .env.e2e ]; then
        . ./.env.e2e
    fi
fi

exec zig build e2e-call -- "$@"
