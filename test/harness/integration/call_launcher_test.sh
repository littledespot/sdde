#!/bin/sh
# Offline launcher checks with fake Zig; no workflow or provider is invoked.
set -eu
call_launcher_source=$1
call_launcher_tmp=$(mktemp -d "${TMPDIR:-/tmp}/sdde-call-launcher.XXXXXX")
call_launcher_tmp=$(CDPATH= cd -- "$call_launcher_tmp" && pwd -P)
call_launcher_cleanup() {
    call_launcher_status=$?
    trap - EXIT HUP INT TERM
    rm -f -- "$call_launcher_tmp/project with spaces/scripts/e2e-call.sh" \
        "$call_launcher_tmp/project with spaces/.env.e2e" \
        "$call_launcher_tmp/local-env-saved" "$call_launcher_tmp/bin/zig"
    rmdir -- "$call_launcher_tmp/project with spaces/scripts" \
        "$call_launcher_tmp/project with spaces" "$call_launcher_tmp/bin" \
        "$call_launcher_tmp/outside" "$call_launcher_tmp"
    exit "$call_launcher_status"
}
trap call_launcher_cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$call_launcher_tmp/project with spaces/scripts" \
    "$call_launcher_tmp/bin" "$call_launcher_tmp/outside"
cp "$call_launcher_source" "$call_launcher_tmp/project with spaces/scripts/e2e-call.sh"
cat > "$call_launcher_tmp/bin/zig" <<'PROBE'
#!/bin/sh
set -eu
[ "$PWD" = "$CALL_LAUNCHER_EXPECT_ROOT" ]
[ "$1" = build ] && [ "$2" = e2e-call ] && [ "$3" = -- ]
shift 3
if [ "$#" -eq 0 ]; then
    exit 2
fi
if [ "$#" -eq 1 ] && [ "$1" = --help ]; then
    [ "${CALL_LAUNCHER_ENV_LOADED:-no}" = no ]
    exit 0
fi
[ "$TEST_AWS_BEARER_TOKEN_BEDROCK" = "$CALL_LAUNCHER_EXPECT_CREDENTIAL" ]
if [ "$1" = --help ]; then
    [ "$CALL_LAUNCHER_ENV_LOADED" = yes ]
    [ "$#" -eq 2 ] && [ "$2" = --unknown ]
    exit 2
fi
[ "$#" -eq 10 ] || [ "$#" -eq 12 ]
[ "$1" = --run ] && [ "$2" = "$CALL_LAUNCHER_EXPECT_RUN" ]
[ "$3" = --workflow ] && [ "$4" = spec-generation ]
[ "$5" = --call ] && [ "$6" = 12 ]
[ "$7" = --model ] && [ "$8" = "$CALL_LAUNCHER_EXPECT_MODEL" ]
[ "$9" = --reasoning-effort ] && [ "${10}" = high ]
shift 10
if [ "$#" -ne 0 ]; then
    [ "$1" = --repeats ] && [ "$2" = 3 ]
fi
exit "${CALL_LAUNCHER_EXIT:-0}"
PROBE
chmod +x "$call_launcher_tmp/bin/zig"
export PATH="$call_launcher_tmp/bin:$PATH"
export CALL_LAUNCHER_EXPECT_ROOT="$call_launcher_tmp/project with spaces"
export CALL_LAUNCHER_EXPECT_RUN='zig-out/e2e-spec/run with spaces/$capture'
export CALL_LAUNCHER_EXPECT_MODEL='registered-model:0;$literal'
export CALL_LAUNCHER_EXPECT_CREDENTIAL=from-local-file
export TEST_AWS_BEARER_TOKEN_BEDROCK=from-caller
unset CALL_LAUNCHER_ENV_LOADED CALL_LAUNCHER_EXIT

# A failing environment file proves help does not evaluate it at all.
cat > "$CALL_LAUNCHER_EXPECT_ROOT/.env.e2e" <<'ENV'
exit 91
ENV
cd "$call_launcher_tmp/outside"
sh "$CALL_LAUNCHER_EXPECT_ROOT/scripts/e2e-call.sh" --help
cat > "$CALL_LAUNCHER_EXPECT_ROOT/.env.e2e" <<'ENV'
export TEST_AWS_BEARER_TOKEN_BEDROCK=from-local-file
export CALL_LAUNCHER_ENV_LOADED=yes
ENV
if sh "$CALL_LAUNCHER_EXPECT_ROOT/scripts/e2e-call.sh"; then
    exit 1
else
    [ "$?" -eq 2 ]
fi
if sh "$CALL_LAUNCHER_EXPECT_ROOT/scripts/e2e-call.sh" --help --unknown; then
    exit 1
else
    [ "$?" -eq 2 ]
fi
set -- --run "$CALL_LAUNCHER_EXPECT_RUN" --workflow spec-generation --call 12 \
    --model "$CALL_LAUNCHER_EXPECT_MODEL" --reasoning-effort high
sh "$CALL_LAUNCHER_EXPECT_ROOT/scripts/e2e-call.sh" "$@"
sh "$CALL_LAUNCHER_EXPECT_ROOT/scripts/e2e-call.sh" "$@" --repeats 3
export CALL_LAUNCHER_EXIT=7
if sh "$CALL_LAUNCHER_EXPECT_ROOT/scripts/e2e-call.sh" "$@"; then
    exit 1
else
    [ "$?" -eq 7 ]
fi
unset CALL_LAUNCHER_EXIT
mv "$CALL_LAUNCHER_EXPECT_ROOT/.env.e2e" "$call_launcher_tmp/local-env-saved"
export CALL_LAUNCHER_EXPECT_CREDENTIAL=from-caller
sh "$CALL_LAUNCHER_EXPECT_ROOT/scripts/e2e-call.sh" "$@"
sh "$CALL_LAUNCHER_EXPECT_ROOT/scripts/e2e-call.sh" --help
