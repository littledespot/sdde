#!/bin/sh
# PreToolUse (Bash): keep live provider credentials out of the conversation,
# route billed or engine-execution commands to an explicit user decision
# (AGENTS.md "Commands" owns that list), and approve Python only when it makes
# no external calls. The permission rules in .claude/settings.json are the
# declarative baseline and name the same steps; this hook also matches what
# those rules miss, such as a live step inside `sh -c` or behind `env`. The
# Spec launcher is the one step this hook alone gates, because a settings ask
# rule would also prompt for the runs the user approved through /live-e2e.
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

# The live-e2e approval records hold the user's word; only the hooks write
# them. One command that can't write a file (no redirect, chain, substitution
# or second line) may still read them; find's writing and executing actions
# stay with the settings ask rules.
if matches 'live-e2e-approvals'; then
    store_read=no
    case $command in
        *[\;\&\|\<\>\`\$]* | *'
'*) ;;
        'find '* | 'ls '* | 'cat '* | 'head '* | 'tail '* | 'wc '* | 'grep '* | 'jq '* | 'diff '*)
            store_read=yes
            ;;
    esac
    [ "$store_read" = yes ] ||
        decide deny "The live-e2e approval records hold the user's approval of live runs; only the hooks write them."
fi

# One Spec launcher run the user approved through /live-e2e runs without
# another prompt; live-e2e-approval.py checks the exact command and counts it.
case $command in
    './scripts/e2e-spec.sh --case '*)
        if printf '%s' "$input" | python3 -I "$(dirname "$0")/live-e2e-approval.py" consume; then
            decide allow "The user approved this live Spec run through /live-e2e."
        fi
        ;;
esac

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
