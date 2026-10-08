#!/bin/sh
# Run offline workflow, harness and launcher integration tests from this checkout.
set -eu

integration_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
cd -- "$integration_root"

exec zig build test-integration "$@"
