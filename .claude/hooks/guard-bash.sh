#!/bin/sh
# PreToolUse (Bash): keep live provider credentials out of the conversation,
# route billed or engine-execution commands to an explicit user decision
# (AGENTS.md "Commands" owns that list), and approve Python only when it makes
# no external calls. The permission rules in .claude/settings.json are the
# declarative baseline and name the same steps; this hook also matches what
# those rules miss, such as a live step inside `sh -c` or behind `env`.
set -u

input=$(cat)
if ! command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty'); then
    # A hook that fails lets the command run, so an input this hook can't read
    # goes to the user. jq may be what is missing, so this doesn't use decide.
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"guard-bash.sh could not read this command (is jq installed?), so its credential and live-step checks did not run."}}'
    exit 0
fi
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
# engine or harness binaries against a project. A step counts wherever a
# `zig build` invocation names it, quoted or not.
live_step='(run|e2e-spec|e2e-call|evaluate-spec|provider-compatibility|baseline)'
if matches "zig[[:space:]]+build([[:space:]]+[^[:space:];&|]+)*[[:space:]]+[\"']?${live_step}([^[:alnum:]_-]|\$)" ||
    matches 'scripts/(e2e-spec|e2e-call|provider-compatibility|baseline)\.sh' ||
    matches 'zig-out/bin/[^[:space:]/]+' ||
    matches '(^|[;&|(])[[:space:]]*sdde([[:space:]]|$)'; then
    decide ask "This command can make billed live model calls or execute the engine against a project. AGENTS.md requires explicit user approval for each such run, naming the case or target project and workflow."
fi

# offline-python.py approves Python it reads in full and finds offline, puts
# Python it finds making an external call to the user, and leaves every other
# Python command to the permission mode.
if matches '(^|[;&|(])[[:space:]]*([[:alpha:]_][[:alnum:]_]*=[^[:space:]]*[[:space:]]+)*([^[:space:]]*/)?python3?([[:space:]]|$)'; then
    printf '%s' "$input" | python3 -I "$(dirname "$0")/offline-python.py" ||
        decide ask "The offline Python check failed, so this Python command needs approval."
fi

exit 0
