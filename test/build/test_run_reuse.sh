#!/bin/sh
# Prove test-run freshness in a throwaway Git repository. Every test run reruns by
# default, even with --seed. Under -Dreuse-test-runs a passing run is reused only
# while nothing it depends on has changed, and verify refuses the option. Runs no
# workflow or provider.
set -eu
reuse_zig=$1
reuse_fixture=$2
reuse_counted=$3
reuse_policy=$4
reuse_key_tool=$5
reuse_tmp=$(mktemp -d "${TMPDIR:-/tmp}/sdde-test-run-reuse.XXXXXX")
reuse_tmp=$(CDPATH= cd -- "$reuse_tmp" && pwd -P)
reuse_held=
# If an assertion fails while the concurrency check holds a build open, release it
# and let it finish before removing its repository.
trap 'if [ -n "$reuse_held" ]; then touch "$reuse_repo/mutating_test.release"; wait "$reuse_held" 2>/dev/null || true; fi; chmod -R u+rw -- "$reuse_tmp" 2>/dev/null || true; rm -rf -- "$reuse_tmp"' EXIT HUP INT TERM
# The user's Git configuration must not change what Git lists or how it commits,
# and a changed HOME must not move Zig's global cache.
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1
ZIG_GLOBAL_CACHE_DIR=${ZIG_GLOBAL_CACHE_DIR:-$HOME/.cache/zig}
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM ZIG_GLOBAL_CACHE_DIR
reuse_repo="$reuse_tmp/repository"
reuse_cache="$reuse_tmp/cache"
mkdir -p "$reuse_repo/build" "$reuse_repo/subdirectory"
cp "$reuse_fixture" "$reuse_repo/build.zig"
for reuse_test in counted_test late_test inherited_cwd_test mutating_test; do
    cp "$reuse_counted" "$reuse_repo/$reuse_test.zig"
done
cp "$reuse_policy" "$reuse_repo/build/"
printf '*.log\n*.mutate\n*.link\n*.hold\n*.held\n*.release\n.zig-cache/\nzig-out/\nevidence/\n' > "$reuse_repo/.gitignore"
printf 'original\n' > "$reuse_repo/data.txt"
printf 'tracked\n' > "$reuse_repo/subdirectory/keep.txt"
cd "$reuse_repo"
git -c init.templateDir= init -q
commit() {
    git -c user.name='SDDE test' -c user.email=test@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm "$1"
}
git add -A
commit baseline

build() {
    if ! "$reuse_zig" build "$@" --cache-dir "$reuse_cache" > "$reuse_tmp/output" 2>&1; then
        cat "$reuse_tmp/output" >&2
        return 1
    fi
}
reuse() {
    build "$1" -Dreuse-test-runs -Dtest-run-key="$reuse_key_tool"
}
refused() {
    if reuse "$1" 2> /dev/null; then
        printf 'test-run reuse: %s was accepted\n' "$2" >&2
        exit 1
    fi
    grep -F "$3" "$reuse_tmp/output" > /dev/null
}
runs() {
    if [ -f "$1.log" ]; then wc -l < "$1.log" | tr -d ' '; else echo 0; fi
}
expect() {
    if [ "$(runs counted_test)" -ne "$1" ]; then
        printf 'test-run reuse: expected %s runs after %s, found %s\n' "$1" "$2" "$(runs counted_test)" >&2
        exit 1
    fi
}

reuse test
expect 1 'the first opt-in run'
reuse test
expect 1 'an unchanged repository'
printf 'changed\n' > data.txt
reuse test
expect 2 'editing a tracked file'
printf 'new\n' > new.txt
reuse test
expect 3 'adding an untracked file'
rm data.txt
reuse test
expect 4 'deleting a tracked file'
printf 'changed\n' > data.txt
reuse test
# Zig keeps one result per run, so an earlier repository state is not reused.
expect 5 'returning to an earlier repository state'
printf '\377\000' > data.bin
reuse test
expect 6 'adding a binary file'
printf '\376\000' > data.bin
reuse test
expect 7 'changing binary bytes'
chmod +x data.txt
reuse test
expect 8 'setting the executable bit'
ln -s data.txt link.txt
refused test 'a symbolic link' 'SymbolicLinkTestRunInput'
expect 8 'refusing a symbolic link'
rm link.txt
mkdir -p evidence/run-1
printf 'first\n' > evidence/run-1/result.json
reuse test
expect 9 'adding a listed ignored input'
printf 'second\n' > evidence/run-1/result.json
reuse test
expect 10 'changing a listed ignored input'
printf 'unlisted\n' > evidence/unrelated.json
reuse test
expect 10 'adding an ignored file outside the listed locations'
printf 'MOCK_CREDENTIAL\n' > .env.local
chmod 000 .env.local
reuse test
expect 11 'adding an unreadable credential file, keyed without being read'
mkdir -p .git/info
printf 'local.secret\n' >> .git/info/exclude
printf 'MOCK_SECRET\n' > local.secret
chmod 000 local.secret
reuse test
expect 12 'adding an unreadable file hidden by a local exclude, keyed without being read'
git add -- data.txt data.bin new.txt
commit next
reuse test
expect 13 'a new commit'
(
    REUSE_UNLISTED=changed
    export REUSE_UNLISTED
    reuse test
)
expect 13 'an environment variable that test runs never receive'
(
    PATH="$reuse_tmp:$PATH"
    export PATH
    reuse test
)
expect 14 'a changed PATH'
(
    HOME="$reuse_tmp"
    export HOME
    reuse test
)
expect 15 'a changed HOME'
# A behaviour check: Zig already distinguishes runs from different directories,
# so this passes with or without the explicit working directory set by apply.
reuse inherited-cwd
reuse inherited-cwd
(
    cd subdirectory
    reuse inherited-cwd
)
if [ "$(runs inherited_cwd_test)" -ne 1 ] || [ "$(runs subdirectory/inherited_cwd_test)" -ne 1 ]; then
    printf 'test-run reuse: a run from another directory reused the result from the root\n' >&2
    exit 1
fi
reuse late
reuse late
if [ "$(runs late_test)" -ne 2 ]; then
    printf 'test-run reuse: a test run added after the wiring was reused\n' >&2
    exit 1
fi
# A tracked file edited while a keyed run executes fails the build. Reverting the
# edit afterwards must still not reuse the run, because the change is recorded.
cp data.txt "$reuse_tmp/data.saved"
reuse mutating
# The trigger is ignored, so it isn't keyed; a listed file makes the run execute.
# After the revert the repository matches the key captured for that build, so
# only the recorded change can force the rerun.
printf 'bump\n' > bump.txt
touch mutating_test.mutate
refused mutating 'a tracked file edited during the build' 'Repository files changed while opt-in test runs were executing'
rm mutating_test.mutate
cp "$reuse_tmp/data.saved" data.txt
reuse mutating
if [ "$(runs mutating_test)" -ne 3 ]; then
    printf 'test-run reuse: a run whose inputs changed during the build was reused after the change was reverted\n' >&2
    exit 1
fi
# A confirmation that fails with an error records nothing, so only the run's
# pending mark can force the rerun once the repository matches its key again.
printf 'bump again\n' > bump.txt
touch mutating_test.link
refused mutating 'a run whose confirmation failed' 'SymbolicLinkTestRunInput'
rm mutating_test.link mid-build-link.txt
# A build of the same run under another identity confirms only its own mark, so
# the original identity's unconfirmed result must still rerun.
(
    PATH="$reuse_tmp:$PATH"
    export PATH
    reuse mutating
)
reuse mutating
if [ "$(runs mutating_test)" -ne 6 ]; then
    printf 'test-run reuse: a run whose confirmation failed was reused after another build confirmed the same run\n' >&2
    exit 1
fi
# Only one opt-in build at a time may use a cache; a second fails before running.
printf 'bump for the held build\n' > bump.txt
touch mutating_test.hold
"$reuse_zig" build mutating -Dreuse-test-runs -Dtest-run-key="$reuse_key_tool" --cache-dir "$reuse_cache" > "$reuse_tmp/held-output" 2>&1 &
reuse_held=$!
reuse_waited=0
while [ ! -f mutating_test.held ]; do
    reuse_waited=$((reuse_waited + 1))
    if [ "$reuse_waited" -gt 600 ]; then
        cat "$reuse_tmp/held-output" >&2
        printf 'test-run reuse: the held build never started its run\n' >&2
        exit 1
    fi
    sleep 0.1
done
refused test 'a concurrent opt-in build' 'AnotherOptInTestRunBuildIsRunning'
touch mutating_test.release
if ! wait "$reuse_held"; then
    cat "$reuse_tmp/held-output" >&2
    exit 1
fi
rm mutating_test.hold mutating_test.held mutating_test.release
reuse_held=
expect 15 'a refused concurrent opt-in build'
build test
expect 16 'a default run after the recorded change'
build test
expect 17 'a second default run'
build test --seed 1
build test --seed 1
expect 19 'two default runs with the same explicit seed'
# A changed input would make any run that started execute, so the count proves
# the refused verify ran nothing.
printf 'before refused verify\n' > data.txt
refused verify 'verify with -Dreuse-test-runs' "'verify' always runs every test fresh"
expect 19 'a refused opt-in verify'
build verify --seed 1
build verify --seed 1
expect 21 'two fresh verify runs with the same explicit seed'
