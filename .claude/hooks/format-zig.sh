#!/bin/sh
# PostToolUse (Edit|Write): run the pinned `zig fmt` on an edited repository
# Zig file. A parse failure exits 2 so Claude sees the error at once; the
# authoritative check remains `zig build lint`.
set -u

file=$(jq -r '.tool_input.file_path // empty') || exit 0
case "$file" in
    *.zig) ;;
    *) exit 0 ;;
esac

project=${CLAUDE_PROJECT_DIR:-$(pwd -P)}
case "$file" in
    "$project"/zig-pkg/* | "$project"/.zig-cache/* | "$project"/zig-out/*) exit 0 ;;
    "$project"/*) ;;
    *) exit 0 ;;
esac
[ -f "$file" ] || exit 0

# Another formatter release could disagree with the pinned lint step.
command -v zig >/dev/null 2>&1 || exit 0
[ "$(zig version)" = "$(cat "$project/.zigversion")" ] || exit 0

if ! output=$(zig fmt "$file" 2>&1); then
    printf 'zig fmt could not format %s:\n%s\n' "$file" "$output" >&2
    exit 2
fi
exit 0
