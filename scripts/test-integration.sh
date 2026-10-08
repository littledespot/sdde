#!/bin/sh
# Run offline workflow, harness and launcher integration tests from this checkout.
set -eu

integration_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
cd -- "$integration_root"

mkdir -p "$integration_root/.zig-cache"
integration_log=$(mktemp "$integration_root/.zig-cache/test-integration.XXXXXX")
printf 'Running offline integration tests...\nFull log: %s\n' "$integration_log"

if zig build test-integration --summary all "$@" > "$integration_log" 2>&1; then
    sed -n '/^Build Summary:/p' "$integration_log"
    printf 'Integration tests PASSED.\n'
else
    integration_status=$?
    cat "$integration_log" >&2
    printf 'Integration tests FAILED (exit %s).\nFull log: %s\n' "$integration_status" "$integration_log" >&2
    exit "$integration_status"
fi
