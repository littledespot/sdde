#!/bin/sh
# Offline modes cannot evaluate credentials; fake Zig never invokes a provider.
set -eu
baseline_launcher_source=$1
baseline_launcher_tmp=$(mktemp -d "${TMPDIR:-/tmp}/sdde-baseline-launcher.XXXXXX")
trap 'rm -rf -- "$baseline_launcher_tmp"' EXIT
mkdir -p "$baseline_launcher_tmp/project with spaces/scripts" "$baseline_launcher_tmp/bin" "$baseline_launcher_tmp/outside"
cp "$baseline_launcher_source" "$baseline_launcher_tmp/project with spaces/scripts/baseline.sh"
baseline_launcher_root=$(CDPATH= cd -- "$baseline_launcher_tmp/project with spaces" && pwd -P)
export BASELINE_EXPECT_ROOT="$baseline_launcher_root"
export BASELINE_EXPECT_PATH='test/case with spaces;$literal.json'
cat > "$baseline_launcher_tmp/bin/zig" <<'PROBE'
#!/bin/sh
set -eu
[ "$PWD" = "$BASELINE_EXPECT_ROOT" ]
[ "$1" = build ] && [ "$2" = baseline ] && [ "$3" = -- ]
shift 3
case "$1" in
    --help)
        [ "$#" -eq 1 ] && [ "${BASELINE_ENV_LOADED:-no}" = no ] ;;
    prepare)
        [ "$#" -eq 11 ] && [ "${BASELINE_ENV_LOADED:-no}" = no ]
        [ "$2" = --protocol ] && [ "$3" = "$BASELINE_EXPECT_PATH" ]
        [ "$4" = --cases ] && [ "$5" = cases.json ]
        [ "$6" = --template-case ] && [ "$7" = workflow.json ]
        [ "$8" = --budget-plan ] && [ "$9" = budget.json ]
        [ "${10}" = --rubric ] && [ "${11}" = rubric.json ] ;;
    score)
        [ "$#" -eq 9 ] && [ "${BASELINE_ENV_LOADED:-no}" = no ]
        [ "$2" = --freeze ] && [ "$3" = "$BASELINE_EXPECT_PATH" ]
        [ "$4" = --cases ] && [ "$5" = cases.json ]
        [ "$6" = --acquisition ] && [ "$7" = acquisition.json ]
        [ "$8" = --assessments ] && [ "$9" = assessments.json ] ;;
    acquire)
        [ "$#" -eq 4 ] && [ "$2" = --freeze ] && [ "$3" = "$BASELINE_EXPECT_PATH" ] && [ "$4" = --live ]
        [ "$TEST_AWS_BEARER_TOKEN_BEDROCK" = "$BASELINE_EXPECT_CREDENTIAL" ] ;;
    *) exit 88 ;;
esac
exit "${BASELINE_EXIT:-0}"
PROBE
chmod +x "$baseline_launcher_tmp/bin/zig"
export PATH="$baseline_launcher_tmp/bin:$PATH"
export TEST_AWS_BEARER_TOKEN_BEDROCK=from-caller
unset BASELINE_ENV_LOADED BASELINE_EXIT
cat > "$baseline_launcher_root/.env.e2e" <<'ENV'
exit 91
ENV
cd "$baseline_launcher_tmp/outside"
sh "$baseline_launcher_root/scripts/baseline.sh" --help
sh "$baseline_launcher_root/scripts/baseline.sh" prepare --protocol "$BASELINE_EXPECT_PATH" --cases cases.json --template-case workflow.json --budget-plan budget.json --rubric rubric.json
sh "$baseline_launcher_root/scripts/baseline.sh" score --freeze "$BASELINE_EXPECT_PATH" --cases cases.json --acquisition acquisition.json --assessments assessments.json
cat > "$baseline_launcher_root/.env.e2e" <<'ENV'
export TEST_AWS_BEARER_TOKEN_BEDROCK=from-local-file
export BASELINE_ENV_LOADED=yes
ENV
export BASELINE_EXPECT_CREDENTIAL=from-local-file
sh "$baseline_launcher_root/scripts/baseline.sh" acquire --freeze "$BASELINE_EXPECT_PATH" --live
export BASELINE_EXIT=7
if sh "$baseline_launcher_root/scripts/baseline.sh" acquire --freeze "$BASELINE_EXPECT_PATH" --live; then
    exit 1
else
    [ "$?" -eq 7 ]
fi
unset BASELINE_EXIT
rm -- "$baseline_launcher_root/.env.e2e"
unset BASELINE_ENV_LOADED
export BASELINE_EXPECT_CREDENTIAL=from-caller
sh "$baseline_launcher_root/scripts/baseline.sh" acquire --freeze "$BASELINE_EXPECT_PATH" --live
