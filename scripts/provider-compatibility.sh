#!/bin/sh
# One fresh production exchange; requires separate bounded live approval.
set -eu

compatibility_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
cd -- "$compatibility_root"

if [ "$#" -ne 1 ] || [ "$1" != "--help" ]; then
    if [ -f .env.e2e ]; then
        . ./.env.e2e
    fi
fi

exec zig build provider-compatibility -- "$@"
