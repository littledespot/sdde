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

## Authority and open work

- The design documents AGENTS.md routes to are large. Use the `design-router` agent
  to collect the governing clauses with citations, rather than reading whole files.
- Before you propose, implement, review or decide an engine change:
  - read [.claude/known-work.md](.claude/known-work.md), a dated snapshot of known
    failure classes and open work;
  - check the accepted ADRs for any rule the change would break.

## Live commands

AGENTS.md lists the live commands and holds the evidence rules. The project settings
make every one of them prompt, and the build rejects any `test`, `test-*`, `smoke*` or
`verify` step that depends on a live step.

The user starts a live Spec case with `/live-e2e <case>`.

## E2E assessment

- Use `/evaluate-e2e <run>` to assess a retained run. Its output is advisory analysis,
  not a grade or a review; acceptance follows AGENTS.md
  ([R8](design/harness/acceptance.md)). A published run exits nonzero until it is
  adjudicated.

## Claude Code setup

- The project settings and the Bash guard hook block access to `.env.e2e`.
  `.env.e2e.example` lists its variable names.
- After each edit to a repository `.zig` file, a hook runs the pinned `zig fmt`. If it
  reports a parse error, fix it before continuing.
- `/preflight <task>` produces the AGENTS.md "Before editing" analysis. `/verify`
  runs the validation ladder and writes the definition-of-done report.
- Before reporting a change complete, have the `contract-reviewer` agent review the
  diff against the AGENTS.md review rules.
- These files are policy, so every edit to them prompts: AGENTS.md, CLAUDE.md,
  accepted ADRs, and the Claude Code settings and hooks. Change them only when the
  request includes that policy change.
- [.claude/README.md](.claude/README.md) describes this configuration for maintainers.
