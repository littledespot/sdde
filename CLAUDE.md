@AGENTS.md

# Claude Code

[AGENTS.md](AGENTS.md), imported above, is the contract for every coding agent in this
repository, Claude Code included. Read its references to Codex as references to the
coding agent. This file adds only Claude Code specifics. It doesn't restate, relax or
outrank AGENTS.md.

## Intent

[design/intent.md](design/intent.md) sets out what the engine is for. It turns source
material and user requirements into traceable, validated outputs. Lower-capability
models do focused semantic work. Deterministic code does everything that can be
computed reliably.

Judge an engine change by its effect on:

- requirement preservation;
- unsupported additions;
- false assessments;
- repair-induced harm;
- successful completion;
- latency and cost per acceptable result.

Passing structural tests, or getting more model calls to succeed, is not enough. The
intent statement guides judgment but isn't contract authority. Its proposed shift
toward smaller semantic decisions hasn't been accepted.

## Authority

- The design documents AGENTS.md routes to are large. Use the `design-router` agent
  to collect the governing clauses with citations, rather than reading whole files.
- Before you propose, implement, review or decide an engine change, check the
  accepted ADRs for any rule the change would break.
- Put a durable project rule in AGENTS.md, or a Claude Code rule here, never in
  auto-memory. Memory holds only conversational preferences no repository file states.

## Live and billed steps

AGENTS.md lists them. The project settings make every one prompt, and the build
rejects any `test`, `test-*`, `smoke*` or `verify` step that depends on a live step.
The user starts a live Spec case with `/live-e2e <case>`. `/evaluate-e2e <run>`
assesses and adjudicates a retained run; AGENTS.md "Testing expectations" says who
triggers it ([R8](design/harness/acceptance.md)). A published run exits nonzero until
it is adjudicated.

## Commands without prompts

Only live or billed steps should ask the user for approval. Everything else must match
the project allow list, so in every Bash call, yours and every subagent's:

- Run one command per call from the project root, with relative paths. Use no `cd`,
  no `;`, `&&` or `||` chains, no pipes, redirects or process substitution, no
  variable assignments, and no `$` or backticks in the command text.
- Change files only with the Edit or Write tools, never `sed -i` or another shell
  command. `sed -n`, `cat`, `grep`, `find`, `head`, `wc`, `jq`, `diff` and offline
  `zig build` steps are fine for reading and checking.
- Never put Python in the command text (`-c` or a heredoc). Write the script to the
  scratchpad and run `python3 -I <file>`. The guard hook asks about any script that
  imports `subprocess`, `socket`, `asyncio`, `multiprocessing`, `importlib`, `ctypes`,
  `http` or `urllib.request`, or calls `os.system`, `popen`, `exec*`, `spawn*`, `eval`,
  `exec` or `__import__`.
- Before launching an agent that edits non-Markdown files, check the Edit allow list
  covers them.

## Claude Code setup

- The project settings and the Bash guard hook block access to `.env.e2e`.
  `.env.e2e.example` lists its variable names.
- After each edit to a repository `.zig` file, a hook runs the pinned `zig fmt`. If it
  reports a parse error, fix it before continuing.
- `/preflight <task>` produces the AGENTS.md "Before editing" analysis. `/verify`
  runs the validation ladder and writes the definition-of-done report.
- Before reporting a change complete, have the `contract-reviewer` agent review it
  against the AGENTS.md review rules. Name the changed files and give it the before
  text, since it runs no git command.
- These files are policy: AGENTS.md, CLAUDE.md, accepted ADRs, and the Claude Code
  settings and hooks. Change them only when the request includes that policy change.
  Markdown edits and `zig` commands don't prompt. Edits to the settings and hooks do,
  and so does every live or billed step.
