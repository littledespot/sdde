#!/bin/sh
# Check integration-command reporting with a fake build; runs no workflow or provider.
set -eu
integration_source=$1
integration_tmp=$(mktemp -d "${TMPDIR:-/tmp}/sdde-integration-script.XXXXXX")
integration_tmp=$(CDPATH= cd -- "$integration_tmp" && pwd -P)
trap 'rm -rf -- "$integration_tmp"' EXIT HUP INT TERM
mkdir -p "$integration_tmp/project with spaces/scripts" "$integration_tmp/bin" "$integration_tmp/outside"
cp "$integration_source" "$integration_tmp/project with spaces/scripts/test-integration.sh"
cat > "$integration_tmp/bin/zig" <<'PROBE'
#!/bin/sh
set -eu
[ "$PWD" = "$INTEGRATION_EXPECT_ROOT" ]
[ "$#" -eq 4 ]
[ "$1" = build ] && [ "$2" = test-integration ]
[ "$3" = --summary ] && [ "$4" = all ]
printf 'captured build stdout\n'
printf 'expected workflow run.failed\nfailed command: simulated test command\n' >&2
if [ "$INTEGRATION_EXIT" -eq 0 ]; then
    printf 'Build Summary: 4/4 steps succeeded; 84/84 tests passed\n' >&2
else
    printf 'actual build or test diagnostic\n' >&2
fi
exit "$INTEGRATION_EXIT"
PROBE
chmod +x "$integration_tmp/bin/zig"
export PATH="$integration_tmp/bin:$PATH"
export INTEGRATION_EXPECT_ROOT="$integration_tmp/project with spaces"
cd "$integration_tmp/outside"

export INTEGRATION_EXIT=0
sh "$INTEGRATION_EXPECT_ROOT/scripts/test-integration.sh" > "$integration_tmp/success" 2> "$integration_tmp/stderr"
[ ! -s "$integration_tmp/stderr" ]
grep -Fx 'Integration tests PASSED.' "$integration_tmp/success" > /dev/null
grep -Fx 'Build Summary: 4/4 steps succeeded; 84/84 tests passed' "$integration_tmp/success" > /dev/null
if grep -E 'run.failed|failed command:|captured build stdout|FAILED' "$integration_tmp/success"; then
    exit 1
fi
integration_success_log=$(sed -n 's/^Full log: //p' "$integration_tmp/success")
grep -Fx 'expected workflow run.failed' "$integration_success_log" > /dev/null
grep -Fx 'failed command: simulated test command' "$integration_success_log" > /dev/null
grep -Fx 'captured build stdout' "$integration_success_log" > /dev/null

for INTEGRATION_EXIT in 1 7 130; do
    export INTEGRATION_EXIT
    if sh "$INTEGRATION_EXPECT_ROOT/scripts/test-integration.sh" > "$integration_tmp/failure" 2> "$integration_tmp/stderr"; then
        exit 1
    else
        [ "$?" -eq "$INTEGRATION_EXIT" ]
    fi
    grep -Fx "Integration tests FAILED (exit $INTEGRATION_EXIT)." "$integration_tmp/stderr" > /dev/null
    grep -Fx 'actual build or test diagnostic' "$integration_tmp/stderr" > /dev/null
    grep -Fx 'captured build stdout' "$integration_tmp/stderr" > /dev/null
    if grep -E 'PASSED|steps succeeded' "$integration_tmp/failure" "$integration_tmp/stderr"; then
        exit 1
    fi
    integration_failure_log=$(sed -n 's/^Full log: //p' "$integration_tmp/failure")
    [ "$integration_failure_log" != "$integration_success_log" ]
    grep -Fx 'actual build or test diagnostic' "$integration_failure_log" > /dev/null
done
