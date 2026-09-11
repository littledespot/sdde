#!/bin/sh
# Unit test of launcher environment/argument handling. Makes no provider calls.
set -eu
launcher_source=$1
launcher_tmp=$(mktemp -d "${TMPDIR:-/tmp}/sdde-e2e-launcher.XXXXXX")
launcher_tmp=$(CDPATH= cd -- "$launcher_tmp" && pwd -P)
trap 'rm -rf -- "$launcher_tmp"' EXIT HUP INT TERM
mkdir -p "$launcher_tmp/project/scripts" "$launcher_tmp/bin" "$launcher_tmp/outside"
cp "$launcher_source" "$launcher_tmp/project/scripts/e2e-spec.sh"
cat > "$launcher_tmp/bin/zig" <<'PROBE'
#!/bin/sh
set -eu
[ "$1" = build ] && [ "$2" = e2e-spec ] && [ "$3" = -- ]
shift 3
if [ "$1" = --help ]; then
    [ "${LAUNCHER_ENV_LOADED:-no}" = no ]
else
    [ "$1" = --case ] && [ "$#" -eq 2 ]
    [ "$TEST_EVALUATION_PROVIDER" = bedrock ]
    [ "$TEST_EVALUATION_MODEL" = "$LAUNCHER_EXPECT_MODEL" ]
    [ "$PWD" = "$LAUNCHER_EXPECT_ROOT" ]
    [ "$2" = "$LAUNCHER_EXPECT_CASE" ]
fi
exit "${LAUNCHER_EXIT:-0}"
PROBE
chmod +x "$launcher_tmp/bin/zig"
export PATH="$launcher_tmp/bin:$PATH"
export LAUNCHER_EXPECT_ROOT="$launcher_tmp/project"
export LAUNCHER_EXPECT_CASE=test/e2e/wf-001-hello-world/node-vitest/workflow.case.json
export LAUNCHER_EXPECT_MODEL=from-local-file
export TEST_EVALUATION_MODEL=from-caller
export TEST_EVALUATION_PROVIDER=invalid-caller
cat > "$launcher_tmp/project/.env.e2e" <<'ENV'
export TEST_EVALUATION_PROVIDER=bedrock
export TEST_EVALUATION_MODEL=from-local-file
export LAUNCHER_ENV_LOADED=yes
ENV
cd "$launcher_tmp/outside"
sh "$launcher_tmp/project/scripts/e2e-spec.sh"
sh "$launcher_tmp/project/scripts/e2e-spec.sh" --help
export LAUNCHER_EXPECT_CASE=another/workflow.case.json
sh "$launcher_tmp/project/scripts/e2e-spec.sh" --case another/workflow.case.json
export LAUNCHER_EXIT=7
if sh "$launcher_tmp/project/scripts/e2e-spec.sh" --case another/workflow.case.json; then
    exit 1
else
    [ "$?" -eq 7 ]
fi
unset LAUNCHER_EXIT
mv "$launcher_tmp/project/.env.e2e" "$launcher_tmp/local-env-saved"
export TEST_EVALUATION_PROVIDER=bedrock
export TEST_EVALUATION_MODEL=from-caller
export LAUNCHER_EXPECT_MODEL=from-caller
sh "$launcher_tmp/project/scripts/e2e-spec.sh" --case another/workflow.case.json
