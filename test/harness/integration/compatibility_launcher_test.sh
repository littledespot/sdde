#!/bin/sh
# Fake Zig proves argument/environment forwarding; it cannot invoke a provider.
set -eu
compatibility_launcher_source=$1
compatibility_launcher_tmp=$(mktemp -d "${TMPDIR:-/tmp}/sdde-compatibility-launcher.XXXXXX")
trap 'rm -rf -- "$compatibility_launcher_tmp"' EXIT
mkdir -p "$compatibility_launcher_tmp/project with spaces/scripts" "$compatibility_launcher_tmp/bin" "$compatibility_launcher_tmp/outside"
cp "$compatibility_launcher_source" "$compatibility_launcher_tmp/project with spaces/scripts/provider-compatibility.sh"
compatibility_launcher_root=$(CDPATH= cd -- "$compatibility_launcher_tmp/project with spaces" && pwd -P)
export COMPATIBILITY_EXPECT_ROOT="$compatibility_launcher_root"
export COMPATIBILITY_EXPECT_CASE='test/case with spaces;$literal.json'
cat > "$compatibility_launcher_tmp/bin/zig" <<'PROBE'
#!/bin/sh
set -eu
[ "$PWD" = "$COMPATIBILITY_EXPECT_ROOT" ]
[ "$1" = build ] && [ "$2" = provider-compatibility ] && [ "$3" = -- ]
shift 3
if [ "$#" -eq 1 ] && [ "$1" = --help ]; then
    [ "${COMPATIBILITY_ENV_LOADED:-no}" = no ]
    exit 0
fi
[ "$#" -eq 3 ] && [ "$1" = --case ] && [ "$2" = "$COMPATIBILITY_EXPECT_CASE" ] && [ "$3" = --live ]
[ "$TEST_AWS_BEARER_TOKEN_BEDROCK" = "$COMPATIBILITY_EXPECT_CREDENTIAL" ]
exit "${COMPATIBILITY_EXIT:-0}"
PROBE
chmod +x "$compatibility_launcher_tmp/bin/zig"
export PATH="$compatibility_launcher_tmp/bin:$PATH"
export TEST_AWS_BEARER_TOKEN_BEDROCK=from-caller
unset COMPATIBILITY_ENV_LOADED COMPATIBILITY_EXIT
cat > "$compatibility_launcher_root/.env.e2e" <<'ENV'
exit 91
ENV
cd "$compatibility_launcher_tmp/outside"
sh "$compatibility_launcher_root/scripts/provider-compatibility.sh" --help
cat > "$compatibility_launcher_root/.env.e2e" <<'ENV'
export TEST_AWS_BEARER_TOKEN_BEDROCK=from-local-file
export COMPATIBILITY_ENV_LOADED=yes
ENV
export COMPATIBILITY_EXPECT_CREDENTIAL=from-local-file
sh "$compatibility_launcher_root/scripts/provider-compatibility.sh" --case "$COMPATIBILITY_EXPECT_CASE" --live
export COMPATIBILITY_EXIT=7
if sh "$compatibility_launcher_root/scripts/provider-compatibility.sh" --case "$COMPATIBILITY_EXPECT_CASE" --live; then
    exit 1
else
    [ "$?" -eq 7 ]
fi
unset COMPATIBILITY_EXIT
rm -- "$compatibility_launcher_root/.env.e2e"
unset COMPATIBILITY_ENV_LOADED
export COMPATIBILITY_EXPECT_CREDENTIAL=from-caller
sh "$compatibility_launcher_root/scripts/provider-compatibility.sh" --case "$COMPATIBILITY_EXPECT_CASE" --live
sh "$compatibility_launcher_root/scripts/provider-compatibility.sh" --help
