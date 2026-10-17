#!/bin/sh
# Offline preparation/scoring never evaluate a local credential file.
set -eu

baseline_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
cd -- "$baseline_root"
if [ "${1-}" = acquire ]; then
    if [ -f .env.e2e ]; then
        . ./.env.e2e
    fi
fi
exec zig build baseline -- "$@"
