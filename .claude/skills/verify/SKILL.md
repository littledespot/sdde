---
name: verify
description: Run this repository's offline validation ladder for the current change and write the AGENTS.md definition-of-done report, with exact commands, results, tests, open uncertainty and what was not run. Use when a change is ready, before claiming it is complete.
---

# Verify the current change

Every step is offline. Live calls, E2E and engine execution against a target project
are never part of this skill.

1. **Scope.** Run `git status --short`, `git diff --stat main...HEAD` and
   `git diff --stat HEAD` to identify the changed files, then `git diff --check`.
2. **Targeted tests.** Map the changed areas to their owning `zig build test-<area>`
   steps (`zig build --help` lists them with descriptions) and run those first.
3. **Static and architecture checks.** Run `zig build lint`, then
   `zig build test-architecture`.
4. **Full offline suite.** Run `zig build verify`. It covers lint, all unit and
   integration tests, architecture, test registration and the clean packaged-executable
   smoke tests. It can take several minutes: use a long timeout, or run it in the
   background and wait for completion. AGENTS.md requires it on the final tree for
   every change that needs the "Before editing" analysis. It is also the packaging
   smoke evidence for runtime, build,
   asset, configuration, filesystem or process changes.
5. **Diff review.** Ask the `contract-reviewer` agent to review the change. Resolve
   or report every confirmed finding.
6. **Generated artifacts.** If canonical rendering or a generated projection is
   affected, regenerate it from its source and confirm the outputs match. Never edit
   a projection directly.
7. **Report**, following the AGENTS.md definition of done:
   - changed contracts and files;
   - tests added or changed, with their accepted and rejected cases;
   - every command run, verbatim, with its pass or fail result (quote failures);
   - documentation, ADR or traceability updates, or why none were needed;
   - unresolved uncertainty and approved deviations;
   - evidence not produced: always state that no live E2E ran, and name any check
     that could not run and why.

Report a failing check as failing. Never weaken a test, schema, validator or
architecture rule to make the ladder pass.
