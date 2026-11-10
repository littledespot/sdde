---
name: verify
description: Run this repository's offline validation ladder for the current change and write the AGENTS.md definition-of-done report, with exact commands, results, tests, open uncertainty and what was not run. Use when a change is ready, before claiming it is complete.
---

# Verify the current change

Every step is offline: this skill makes no live call and never runs the engine. If a
step leads to an edit, start again from step 1, so that step 6 passes on the final
tree.

1. **Scope.** List the files the change edited, from the work itself. `grep` each for
   trailing whitespace and conflict markers.
2. **Targeted tests.** Map the changed areas to their owning `zig build test-<area>`
   steps (`zig build --help` describes them) and run those.
3. **Static and architecture checks.** Run `zig build lint`, then
   `zig build test-architecture`.
4. **Review.** Ask the `contract-reviewer` agent to review the change. Fix or report
   every confirmed finding.
5. **Generated artifacts.** If the change affects canonical rendering or a generated
   projection, regenerate it from its source and confirm the outputs match.
6. **Full offline suite.** Run `zig build verify`. It can take several minutes: use a
   long timeout, or run it in the background and wait for it.
7. **Report**, as the AGENTS.md "Definition of done" requires:
   - changed contracts and files;
   - tests added or changed, with their accepted and rejected cases;
   - every command run, verbatim, with its pass or fail result, quoting failures;
   - governing ADR or contract updates, or why none were needed;
   - open uncertainty and approved deviations;
   - what was not shown: no live E2E ran, so the ladder demonstrates no semantic
     benefit; name any check that could not run, and why.
