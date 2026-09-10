#!/bin/sh
# Run the development-only Spec E2E harness from this checkout.
set -eu

spec_e2e_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
cd -- "$spec_e2e_root"

if [ "$#" -eq 0 ]; then
    set -- --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json
fi

exec zig build e2e-spec -- "$@"
