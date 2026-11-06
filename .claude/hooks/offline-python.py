"""PreToolUse (Bash) helper for guard-bash.sh: approve Python that makes no external calls.

guard-bash.sh pipes the hook input here, after its own checks, for a command that runs
python or python3. A command shaped

    [cd DIR &&] python[3] [options] (SCRIPT | -c CODE | -m MODULE | - <<'EOF' ... EOF) [ARGS]
        [| head|tail|sort|uniq|wc|cut|grep|jq ...]

is approved when Python can parse everything it runs, every module it imports is in the
standard library or a readable local module, and none of it reaches the network, starts
another program, loads code dynamically or names .env.e2e. Python found doing any of those
is put to the user, with the reason. Every other command, and code this check can't read,
gets no decision here, so the session's permission mode decides it.
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
# Module files Python can load that this check can't read.
COMPILED = (".so", ".pyd", ".pyc")
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
    """Return (source, import directory) for what the invocation runs, or None when this
    check doesn't support the invocation or can't read what it runs."""
    i = 1
    while i < len(words) and words[i].startswith("-") and words[i] != "-":
        option = words[i]
        if option in ("-c", "-m", "-W", "-X") and i + 1 == len(words):
            return None
        if option == "-c":
            return words[i + 1], base
        if option == "-m":
            if words[i + 1].split(".")[0] in RUNNERS:
                return None  # It runs code named in its arguments.
            return f"import {words[i + 1]}\n", base
        if option in ("-W", "-X"):
            i += 2
            continue
        if not FLAGS.issuperset(option[1:]):
            return None
        i += 1
    if i == len(words) or words[i] == "-":
        return None if body is None else (body, base)
    path = os.path.join(base, words[i])
    # A pipe or device, such as /dev/stdin, reads differently here than in the command.
    if not os.path.isfile(path):
        return None
    try:
        with open(path, encoding="utf-8") as script:
            return script.read(), os.path.dirname(path)
    except (OSError, UnicodeDecodeError):
        return None


def starts_program(name):
    """Whether a dotted name is an os function that starts another program."""
    owner, _, function = name.rpartition(".")
    return owner == "os" and (
        function in ("popen", "startfile", "system")
        or function.startswith(("exec", "fork", "posix_spawn", "spawn")))


def external(source, directory, seen, unread):
    """Return why the Python source may reach outside the machine, or None. What this check
    can't read is added to `unread`."""
    if CREDENTIALS.search(source):
        return "it names .env.e2e, which holds live provider credentials"
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", SyntaxWarning)
            tree = ast.parse(source)
    except (SyntaxError, ValueError):
        # The command's interpreter may parse what this one can't.
        unread.append("code this Python can't parse")
        return None
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
            reason = imported(module, directory, seen, unread)
            if reason:
                return reason
    return None


def local_files(local):
    """Return the source files Python can load for the local module or package `local`, or
    None when it can also load code this check can't read: a compiled module, or a
    symlinked directory inside the package."""
    directory, name = os.path.split(local)
    try:
        entries = os.listdir(directory)
    except OSError:
        entries = []
    if any(entry.startswith(name + ".") and entry.endswith(COMPILED) for entry in entries):
        return None
    files = [local + ".py"] if os.path.isfile(local + ".py") else []
    for root, dirs, names in os.walk(local):
        # __pycache__ caches the bytecode of the sources read here.
        dirs[:] = [d for d in dirs if d != "__pycache__"]
        if (any(os.path.islink(os.path.join(root, d)) for d in dirs)
                or any(n.endswith(COMPILED) for n in names)):
            return None
        files += [os.path.join(root, n) for n in names if n.endswith(".py")]
    return files


def imported(module, directory, seen, unread):
    """Return why importing a module may reach outside the machine, or None. What this
    check can't read is added to `unread`."""
    parts = module.split(".")
    if starts_program(module) or any(
            ".".join(parts[:k]) in EXTERNAL for k in range(1, len(parts) + 1)):
        return f"it imports {module}"
    # A local module shadows the standard library, so it is read first.
    local = os.path.join(directory, parts[0])
    files = local_files(local)
    if files is None:
        unread.append(f"{local} can load compiled or linked code")
        return None
    if not files and not os.path.isdir(local):
        if parts[0] not in sys.stdlib_module_names:
            unread.append(f"{parts[0]} is outside the standard library")
        return None
    for path in files:
        if path in seen:
            continue
        seen.add(path)
        try:
            with open(path, encoding="utf-8") as local_module:
                reason = external(local_module.read(), directory, seen, unread)
        except (OSError, UnicodeDecodeError):
            unread.append(f"{path} can't be read")
            continue
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
        return
    directory, python = shape
    base = os.path.join(hook.get("cwd") or os.getcwd(), directory)
    source = program(python["words"], python["body"], base)
    if source is None:
        return
    unread = []
    reason = external(*source, set(), unread)
    if reason:
        decide("ask", f"This Python may make external calls: {reason}. "
               "Approve it only if it stays on this machine.")
    elif not unread:
        decide("allow", "Offline Python: standard library or readable local modules only, "
               "no network, process or dynamic-import use.")


if __name__ == "__main__":
    main()
