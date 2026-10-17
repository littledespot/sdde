@AGENTS.md

# Claude Code

[AGENTS.md](AGENTS.md), imported above, is the contract for every coding agent in this
repository, Claude Code included. Read its references to Codex as references to the
coding agent. This file adds only Claude Code specifics; it does not restate, relax
or outrank AGENTS.md.

## Intent

[design/intent.md](design/intent.md) says what the engine is for. It turns source
material and user requirements into traceable, validated outputs. Lower-capability
models do focused semantic work, and deterministic code does everything that can be
computed reliably. Weigh engine changes by their effect on:

- requirement preservation;
- unsupported additions;
- false assessments;
- repair-induced harm;
- successful completion;
- latency and cost per acceptable result.

Passing structural tests, or getting more model calls to succeed, is not enough. The
intent statement guides judgment but is not contract authority. Its proposed
refinement toward smaller semantic decisions is still being evaluated in
[FIX05](fixes/FIX05.md).

## Navigating authority and work

- AGENTS.md routes work by section number in [design/design.md](design/design.md).
  Section *N* is detailed in `design/contracts/NN-*.md`. The §13 action catalogue is
  in `design/contracts/actions/13-*.md`. Accepted amendments are ADRs in
  [design/decisions/](design/decisions/), indexed in design.md §32.
- These documents are large. Use the `design-router` agent to collect the governing
  clauses with citations instead of reading whole files into the main conversation.
- [fixes/FIX05.md](fixes/FIX05.md) is the sole active fix record.
  [fixes/README.md](fixes/README.md) defines the fix-record convention.

## Commands

Use Zig **0.16.0** exactly ([.zigversion](.zigversion)). Build and test only through
`build.zig` steps; `zig build --help` lists them.

| Purpose | Command |
| --- | --- |
| Format and AST check | `zig build lint` |
| Unit tests | `zig build test` |
| Layer and authority boundaries | `zig build test-architecture` |
| One owning boundary | `zig build test-<area>` |
| Offline integration scenarios | `./scripts/test-integration.sh` |
| Packaged executable in a clean directory | `zig build smoke` |
| Complete offline verification | `zig build verify` |

None of these make model calls. The build rejects any `test`, `test-*`, `smoke*` or
`verify` step that depends on a live step.

Billed live calls and engine execution need explicit user approval every time, and
the project settings make them prompt. That covers:

- `zig build run`, `e2e-spec`, `e2e-call`, `evaluate-spec`, `provider-compatibility`
  and `baseline`;
- the matching `scripts/*.sh` launchers;
- any binary under `zig-out/bin/`.

The user starts a live Spec case with `/live-e2e <case>`.

## Claude Code setup

- `.env.e2e` holds live provider credentials. Never read, print, source, copy or edit
  it; the launchers load it themselves. `.env.e2e.example` lists the variable names.
- After each edit to a repository `.zig` file, a hook runs the pinned `zig fmt`. If it
  reports a parse error, fix it before continuing.
- `/preflight <task>` runs the AGENTS.md "Before editing" analysis. `/verify` runs the
  validation ladder and writes the definition-of-done report.
- Before reporting a change complete, have the `contract-reviewer` agent review the
  diff against the AGENTS.md review rules.
- These files are policy, and edits to them always prompt: AGENTS.md, CLAUDE.md,
  accepted ADRs, and the Claude Code settings and hooks. Change them only when the
  task includes that policy change.
- [.claude/README.md](.claude/README.md) describes this configuration for maintainers.
