# Claude Code configuration

This directory configures Claude Code for SDDE engine development. The working
contract for every agent is [AGENTS.md](../AGENTS.md). [CLAUDE.md](../CLAUDE.md)
imports it and adds the Claude Code specifics.

| Path | Purpose |
| --- | --- |
| `settings.json` | Shared permissions and hooks. Committed. |
| `settings.local.json` | Personal overrides. Git-ignored. |
| `hooks/guard-bash.sh` | PreToolUse guard. It denies any shell command that names `.env.e2e`. It forces a prompt for the billed live build steps (`run`, `e2e-spec`, `e2e-call`, `evaluate-spec`, `provider-compatibility`, `baseline`), their launchers and `zig-out/bin/` binaries, wherever they appear in a compound command. |
| `hooks/format-zig.sh` | PostToolUse formatter. It runs the pinned `zig fmt` on an edited repository `.zig` file and returns parse errors to Claude. It skips files outside the repository, fetched packages and build output, and does nothing when the active Zig differs from `.zigversion`. |
| `rules/` | Path-scoped guidance that loads only when matching files are read or edited: Zig 0.16 idioms, source-layer constraints and the fix-record convention. |
| `agents/design-router.md` | Read-only subagent that returns the governing design authority for a task, with citations. |
| `agents/contract-reviewer.md` | Read-only subagent that reviews a diff against the AGENTS.md review rules. |
| `skills/preflight/` | `/preflight <task>`: the AGENTS.md "Before editing" analysis. |
| `skills/verify/` | `/verify`: the offline validation ladder and the definition-of-done report. |
| `skills/live-e2e/` | `/live-e2e <case>`: one approved, billed live Spec E2E run. Only the user can invoke it. |
| `skills/evaluate-e2e/` | `/evaluate-e2e <run>`: offline, advisory rubric assessment of a retained E2E run that traces each defect to the call, prompt and engine stage that produced it. Writes to the Git-ignored `evaluations/`; never adjudicates. |

## Permission model

- **Allowed without a prompt:**
  - offline build steps that `build.zig` proves cannot reach a live step (`test`,
    `test-*`, `smoke*`, `verify`, `lint`, `build-*`, `code-heuristics`);
  - `zig fmt`;
  - the offline integration launcher;
  - read-only git commands.
- **Always prompt, including in auto mode:**
  - live or billed steps and their launchers;
  - engine execution;
  - `git push`, PR creation and merging, and releases;
  - edits to policy files: AGENTS.md, CLAUDE.md, accepted ADRs, and this directory's
    settings and hooks.
- **Denied:**
  - reading or editing `.env.e2e`;
  - editing fetched packages (`zig-pkg/`) or build output (`.zig-cache/`, `zig-out/`).

The ask and deny rules are the declarative baseline. The guard hook also catches forms
those rules can't express, such as a live step named alongside an offline one in a
single `zig build` invocation. The two layers overlap on purpose, because live runs
cost money and `.env.e2e` holds credentials.

Both hooks need `jq` and a POSIX shell. Without `jq`, the guard hook lets the command
through and the permission rules still apply.

After editing `settings.json` or a hook, run `/hooks` once, or restart the session, to
reload the configuration.
