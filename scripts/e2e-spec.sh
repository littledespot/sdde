#!/bin/sh
# Run the development-only Spec E2E harness from this checkout.
set -eu

spec_e2e_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
cd -- "$spec_e2e_root"

# The development launcher owns local test-environment setup. Help stays usable
# without evaluating a credential file; direct Zig invocations use the caller's
# environment. A local file intentionally replaces values for names it exports.
if [ "$#" -ne 1 ] || [ "$1" != "--help" ]; then
    if [ -f .env.e2e ]; then
        . ./.env.e2e
    fi
fi

if [ "$#" -eq 0 ]; then
    set -- --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json
fi

exec zig build e2e-spec -- "$@"
