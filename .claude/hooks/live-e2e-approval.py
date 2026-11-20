"""Hook helper for the user's approval of a set of live Spec runs.

record (UserPromptSubmit, and PostToolUse on Skill): the user's next message ends any
earlier approval. A typed `/live-e2e <case>... [--repeat <n>] [--no-evaluate]`, or a
live-e2e Skill call the user confirmed at its prompt, records the runs it names: each
case's workflow.case.json path and how many runs of it remain. A case is a path or a name
contained in exactly one case path. Any argument that doesn't parse, or a second
`--repeat`, records nothing.

consume (from guard-bash.sh): exits 0 and counts one run only for exactly
`./scripts/e2e-spec.sh --case <path>` from the repository root, with a run of that path
remaining; otherwise exits 1, and the guard asks.

record prints nothing, because UserPromptSubmit output would enter the conversation.
"""
import fcntl
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
APPROVALS = os.path.join(ROOT, ".claude", "live-e2e-approvals")
CASE_FILE = "workflow.case.json"
LAUNCHER = "./scripts/e2e-spec.sh --case "
SESSION = re.compile(r"[A-Za-z0-9-]+")
CASE_PATH = re.compile(r"test/e2e/[A-Za-z0-9_./-]+/workflow\.case\.json")
COUNT = re.compile(r"[1-9][0-9]*")


def valid_case(path):
    return (isinstance(path, str) and CASE_PATH.fullmatch(path) is not None
            and ".." not in path and os.path.isfile(os.path.join(ROOT, path)))


def case_paths():
    found = []
    for directory, _, names in os.walk(os.path.join(ROOT, "test", "e2e")):
        if CASE_FILE in names:
            found.append(os.path.relpath(os.path.join(directory, CASE_FILE), ROOT))
    return found


def parse(arguments):
    """Return {case path: runs} for a /live-e2e argument string, or None."""
    paths = case_paths()
    tokens = arguments.split()
    repeat, cases, i = None, [], 0
    while i < len(tokens):
        token = tokens[i]
        if token == "--repeat":
            if repeat is not None or i + 1 == len(tokens) or not COUNT.fullmatch(tokens[i + 1]):
                return None
            repeat, i = int(tokens[i + 1]), i + 2
            continue
        if token != "--no-evaluate":
            name = token.removeprefix("./")
            named = [name] if name in paths else [path for path in paths if name in path]
            if len(named) != 1 or not valid_case(named[0]):
                return None
            cases.append(named[0])
        i += 1
    if not cases:
        return None
    runs = {}
    for path in cases:
        runs[path] = runs.get(path, 0) + (repeat or 1)
    return runs


def locked():
    """Hold the store's lock until the returned file closes, so concurrent hooks never
    count the same remaining run twice."""
    os.makedirs(APPROVALS, exist_ok=True)
    lock = open(os.path.join(APPROVALS, ".lock"), "a")
    fcntl.flock(lock, fcntl.LOCK_EX)
    return lock


def save(approval, runs):
    os.makedirs(APPROVALS, exist_ok=True)
    pending = approval + ".pending"
    with open(pending, "w", encoding="utf-8") as out:
        json.dump({"runs": runs}, out)
    os.replace(pending, approval)


def record(hook, approval):
    with locked():
        replace(hook, approval)


def replace(hook, approval):
    arguments = None
    if hook.get("hook_event_name") == "UserPromptSubmit":
        try:
            os.remove(approval)
        except FileNotFoundError:
            pass
        except OSError as error:
            # Exit 2 blocks the message, so an approval that can't end never outlives it.
            print(f"Could not end the earlier live-run approval: {error}", file=sys.stderr)
            sys.exit(2)
        prompt = hook.get("prompt")
        typed = re.fullmatch(r"/live-e2e(\s.*)?", prompt, re.DOTALL) if isinstance(prompt, str) else None
        if typed:
            arguments = typed[1] or ""
    elif hook.get("hook_event_name") == "PostToolUse" and hook.get("tool_name") == "Skill":
        tool_input = hook.get("tool_input")
        if isinstance(tool_input, dict) and tool_input.get("skill") == "live-e2e":
            arguments = tool_input.get("args") or ""
    runs = parse(arguments) if isinstance(arguments, str) else None
    if runs:
        save(approval, runs)


def consume(hook, approval):
    command = (hook.get("tool_input") or {}).get("command")
    cwd = hook.get("cwd")
    if (not isinstance(command, str) or not command.startswith(LAUNCHER)
            or not isinstance(cwd, str) or os.path.realpath(cwd) != os.path.realpath(ROOT)):
        return False
    path = command[len(LAUNCHER):]
    if not valid_case(path) or not os.path.isfile(approval):
        return False
    with locked():
        return count(approval, path)


def count(approval, path):
    try:
        with open(approval, encoding="utf-8") as source:
            runs = json.load(source)["runs"]
    except (OSError, ValueError, KeyError, TypeError):
        return False
    if not isinstance(runs, dict):
        return False
    left = runs.get(path)
    if type(left) is not int or left < 1:
        return False
    runs[path] = left - 1
    runs = {key: value for key, value in runs.items() if value}
    if runs:
        save(approval, runs)
    else:
        os.remove(approval)
    return True


def main():
    mode = sys.argv[1] if len(sys.argv) == 2 else None
    refuse = 1 if mode == "consume" else 0
    try:
        hook = json.load(sys.stdin)
    except ValueError:
        sys.exit(refuse)
    session = hook.get("session_id") if isinstance(hook, dict) else None
    if not isinstance(session, str) or not SESSION.fullmatch(session):
        sys.exit(refuse)
    approval = os.path.join(APPROVALS, session)
    if mode == "record":
        record(hook, approval)
    elif mode == "consume":
        sys.exit(0 if consume(hook, approval) else 1)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
