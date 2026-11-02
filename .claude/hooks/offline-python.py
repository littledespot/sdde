"""PreToolUse (Bash) helper for guard-bash.sh: approve Python that makes no external calls.

guard-bash.sh pipes the hook input here, after its own checks, for a command that runs
python or python3. A command shaped

    [cd DIR &&] python[3] [options] (SCRIPT | -c CODE | -m MODULE | - <<'EOF' ... EOF) [ARGS]
        [| head|tail|sort|uniq|wc|cut|grep|jq ...]

is approved when Python can parse everything it runs and none of it, nor any local module it
imports, reaches the network, starts another program, loads code dynamically or imports a
module outside the standard library. Every other Python command is put to the user, with
the reason.
"""
import ast
import json
import os
import re
import sys
import warnings

# Standard-library modules, and dotted prefixes, that reach the network, start programs or
# load code at runtime.
EXTERNAL = frozenset({
    "asyncio", "builtins", "ctypes", "ensurepip", "ftplib", "http", "idlelib", "imaplib",
    "importlib", "logging.handlers", "multiprocessing", "poplib", "pty", "pydoc", "runpy",
    "smtplib", "socket", "socketserver", "ssl", "subprocess", "urllib.request",
    "urllib.robotparser", "venv", "webbrowser", "wsgiref", "xmlrpc", "zipimport",
})
DYNAMIC = frozenset({"__import__", "eval", "exec"})
# Modules that, run with -m, execute code named in their arguments.
RUNNERS = frozenset({"cProfile", "code", "doctest", "pdb", "profile", "timeit", "trace",
                     "unittest"})
FILTERS = frozenset({"head", "tail", "sort", "uniq", "wc", "cut", "grep", "jq"})
FLAGS = frozenset("bBdEIOPqRsSuvx")
HEREDOC = re.compile(r"<<(-?)[ \t]*(?:'(\w+)'|\"(\w+)\"|(\w+))")
CREDENTIALS = re.compile(r"\.env\.e2e(?![.\w-])")


def segments(text):
    """Split a command into pipeline segments ({"separator", "words", "body"}), or return
    None for any shell syntax beyond words, quotes, `&&`, `|` and one here-document that
    ends the command."""
    found, words, word, body, separator, heredoc = [], [], None, None, "", None
    declared = False
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "'":
            end = text.find("'", i + 1)
            if end < 0:
                return None
            word, i = (word or "") + text[i + 1:end], end + 1
        elif c == '"':
            word, i = word or "", i + 1
            while i < n and text[i] != '"':
                if text[i] in "$`":
                    return None
                if text[i] == "\\" and i + 1 < n and text[i + 1] in '$`"\\':
                    i += 1
                word, i = word + text[i], i + 1
            if i == n:
                return None
            i += 1
        elif c == "\\" and i + 1 < n and text[i + 1] != "\n":
            word, i = (word or "") + text[i + 1], i + 2
        elif c in " \t":
            if word is not None:
                words.append(word)
                word = None
            i += 1
        elif text.startswith("<<", i):
            match = HEREDOC.match(text, i)
            if not match or declared:
                return None
            declared = True
            heredoc = (len(found), match[1], match[2] or match[3] or match[4], match[4] is None)
            i = match.end()
        elif c == "\n" and heredoc:
            owner, dash, delimiter, quoted = heredoc
            lines, i = [], i + 1
            while i < n:
                end = text.find("\n", i)
                end = n if end < 0 else end
                line = text[i:end].lstrip("\t") if dash else text[i:end]
                i = end + 1
                if line == delimiter:
                    break
                lines.append(line)
            else:
                return None
            document = "\n".join(lines) + "\n"
            # Anything after the terminator is a further command.
            if i < n or (not quoted and re.search(r"[$`\\]", document)):
                return None
            if owner == len(found):
                body = document
            else:
                found[owner]["body"] = document
            heredoc = None
        elif text.startswith("&&", i) or (c == "|" and not text.startswith("||", i)):
            if word is not None:
                words.append(word)
                word = None
            if not words:
                return None
            found.append({"separator": separator, "words": words, "body": body})
            separator = "&&" if c == "&" else "|"
            words, body = [], None
            i += len(separator)
        elif c in "\\\n;&|<>()$`#*?[]{}~!":
            return None
        else:
            word, i = (word or "") + c, i + 1
    if word is not None:
        words.append(word)
    if not words or heredoc:
        return None
    found.append({"separator": separator, "words": words, "body": body})
    return found


def invocation(found):
    """Return (cd directory, python segment) for the supported command shape, or None."""
    directory = "."
    if found[0]["words"][0] == "cd":
        if len(found[0]["words"]) != 2 or found[0]["body"] is not None or len(found) < 2:
            return None
        directory, found = found[0]["words"][1], found[1:]
        if found[0]["separator"] != "&&":
            return None
    python, filters = found[0], found[1:]
    if python["words"][0] not in ("python", "python3"):
        return None
    for segment in filters:
        if segment["separator"] != "|" or segment["words"][0] not in FILTERS or segment["body"]:
            return None
    return directory, python


def program(words, body, base):
    """Return (source, import directory) for what the invocation runs, or a reason it can't
    be read."""
    i = 1
    while i < len(words) and words[i].startswith("-") and words[i] != "-":
        option = words[i]
        if option in ("-c", "-m"):
            if i + 1 == len(words):
                return f"`{option}` has no argument"
            if option == "-c":
                return words[i + 1], base
            if words[i + 1].split(".")[0] in RUNNERS:
                return f"`-m {words[i + 1]}` runs code named in its arguments"
            return f"import {words[i + 1]}\n", base
        if option in ("-W", "-X"):
            i += 2
            continue
        if not FLAGS.issuperset(option[1:]):
            return f"option `{option}` isn't recognised"
        i += 1
    if i == len(words) or words[i] == "-":
        if body is None:
            return "it reads its program from standard input"
        return body, base
    path = os.path.join(base, words[i])
    try:
        with open(path, encoding="utf-8") as script:
            return script.read(), os.path.dirname(path)
    except (OSError, UnicodeDecodeError):
        return f"`{words[i]}` can't be read"


def starts_program(name):
    """Whether a dotted name is an os function that starts another program."""
    owner, _, function = name.rpartition(".")
    return owner == "os" and (
        function in ("popen", "startfile", "system")
        or function.startswith(("exec", "fork", "posix_spawn", "spawn")))


def external(source, directory, seen):
    """Return why the Python source may reach outside the machine, or None."""
    if CREDENTIALS.search(source):
        return "it names .env.e2e, which holds live provider credentials"
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", SyntaxWarning)
            tree = ast.parse(source)
    except (SyntaxError, ValueError):
        return None  # Python refuses to run it.
    nodes = list(ast.walk(tree))
    aliases = {"os"} | {
        alias.asname for node in nodes if isinstance(node, ast.Import)
        for alias in node.names if alias.name == "os" and alias.asname}
    for node in nodes:
        if isinstance(node, ast.Import):
            modules = [alias.name for alias in node.names]
        elif isinstance(node, ast.ImportFrom) and not node.level:
            modules = [node.module] + [f"{node.module}.{alias.name}" for alias in node.names]
        elif isinstance(node, ast.Call):
            function = node.func
            if isinstance(function, ast.Name) and function.id in DYNAMIC:
                return f"it calls {function.id}()"
            if (isinstance(function, ast.Attribute) and isinstance(function.value, ast.Name)
                    and function.value.id in aliases and starts_program(f"os.{function.attr}")):
                return f"it calls os.{function.attr}()"
            continue
        else:
            continue
        for module in modules:
            reason = imported(module, directory, seen)
            if reason:
                return reason
    return None


def imported(module, directory, seen):
    """Return why importing a module may reach outside the machine, or None."""
    parts = module.split(".")
    if starts_program(module) or any(
            ".".join(parts[:k]) in EXTERNAL for k in range(1, len(parts) + 1)):
        return f"it imports {module}"
    # A local module shadows the standard library, so it is read first.
    local = os.path.join(directory, parts[0])
    if os.path.isfile(local + ".py"):
        files = [local + ".py"]
    elif os.path.isdir(local):
        files = [os.path.join(root, name) for root, _, names in os.walk(local)
                 for name in names if name.endswith(".py")]
    elif parts[0] in sys.stdlib_module_names:
        return None
    else:
        return f"it imports {parts[0]}, which isn't in the standard library"
    for path in files:
        if path in seen:
            continue
        seen.add(path)
        try:
            with open(path, encoding="utf-8") as local_module:
                reason = external(local_module.read(), directory, seen)
        except (OSError, UnicodeDecodeError):
            return f"local module `{path}` can't be read"
        if reason:
            return f"{reason} (in {os.path.relpath(path, directory)})"
    return None


def decide(decision, reason):
    json.dump({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": decision,
        "permissionDecisionReason": reason,
    }}, sys.stdout)


def main():
    hook = json.load(sys.stdin)
    command = hook.get("tool_input", {}).get("command", "").strip()
    found = segments(command)
    shape = invocation(found) if found else None
    if shape is None:
        decide("ask", "Python runs without approval only as its own command: "
               "[cd DIR &&] python3 ... [| head ...], with no variables, substitutions, "
               "redirections or globs.")
        return
    directory, python = shape
    base = os.path.join(hook.get("cwd") or os.getcwd(), directory)
    source = program(python["words"], python["body"], base)
    reason = source if isinstance(source, str) else external(*source, set())
    if reason:
        decide("ask", f"This Python may make external calls: {reason}. "
               "Approve it only if it stays on this machine.")
    else:
        decide("allow", "Offline Python: standard library only, no network, "
               "process or dynamic-import use.")


if __name__ == "__main__":
    main()
