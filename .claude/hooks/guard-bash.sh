#!/bin/sh
# PreToolUse (Bash): keep live provider credentials out of the conversation and
# route billed or engine-execution commands to an explicit user decision
# (AGENTS.md "Work authorization" and "Testing expectations"). The permission
# rules in .claude/settings.json are the declarative baseline; this hook also
# matches forms those rules cannot express, such as a live step named after an
# offline one in a single `zig build` invocation.
set -u

command=$(jq -r '.tool_input.command // empty') || exit 0
[ -n "$command" ] || exit 0

decide() {
    jq -n --arg decision "$1" --arg reason "$2" \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $decision, permissionDecisionReason: $reason}}'
    exit 0
}

matches() {
    printf '%s\n' "$command" | grep -Eq "$1"
}

# .env.e2e holds live credentials; the scripts/*.sh launchers source it
# themselves. The .env.e2e.example template stays readable.
if matches '\.env\.e2e([^.[:alnum:]_-]|$)'; then
    decide deny ".env.e2e holds live provider credentials. Do not read, print, source, copy or edit it; the scripts/*.sh launchers load it themselves. Use .env.e2e.example for variable names."
fi

# Steps and launchers that can make billed model calls, and execution of the
# engine or harness binaries against a project.
live_step='(run|e2e-spec|e2e-call|evaluate-spec|provider-compatibility|baseline)'
if matches "zig[[:space:]]+build([[:space:]]+[^[:space:];&|]+)*[[:space:]]+${live_step}([[:space:];&|)]|\$)" ||
    matches 'scripts/(e2e-spec|e2e-call|provider-compatibility|baseline)\.sh' ||
    matches 'zig-out/bin/[^[:space:]/]+' ||
    matches '(^|[;&|(])[[:space:]]*sdde([[:space:]]|$)'; then
    decide ask "This command can make billed live model calls or execute the engine against a project. AGENTS.md requires explicit user approval for each such run, naming the case or target project and workflow."
fi

exit 0
