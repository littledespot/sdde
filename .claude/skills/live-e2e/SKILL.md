---
name: live-e2e
description: Run one live Spec E2E case with real model generation, report the run, then automatically score and adjudicate it with /evaluate-e2e unless --no-evaluate is given. Billed.
disable-model-invocation: true
argument-hint: <case path, e.g. test/e2e/wf-001-hello-world/node-vitest/workflow.case.json> [--no-evaluate]
---

# Live Spec E2E: $ARGUMENTS

Invoking `/live-e2e <case>` is the user's request for exactly **one** live run of that
case, followed by `/evaluate-e2e` on the run directory this invocation identifies in
step 5 (AGENTS.md "Testing expectations"). The evaluation is automatic and needs no
argument; adding `--no-evaluate` skips it, and then this skill never assesses the run.
The permission prompt on the launcher command is the approval for the live run. A second
run, a retry, another case or an `e2e-call` diagnostic each need a new explicit
approval. The evaluation is offline, makes no model call, and covers only that run.

1. **Case.** If no case path was given, ask for one; there is no default. Check that
   the file exists under `test/e2e/`. `--no-evaluate` may follow the path.
2. **Procedure.** Read the "Launcher behavior" and "Environment setup" sections of
   [design/harness/e2e.md](../../../design/harness/e2e.md). From the case and its
   referenced configuration, note each generation slot's provider, model and Region,
   to state in step 4. The launcher's preflight rejects any selection outside the
   live-test cost policy, so don't check that yourself. If credentials need checking,
   refer the user to `.env.e2e.example` and the "Environment setup" section.
3. **Offline build first.** Run `zig build build-e2e-harness`. It makes no API calls,
   so a compile failure costs nothing.
4. **Run.** List the run directories already under `zig-out/e2e-spec/`. State the
   case and its generation selection, then run `./scripts/e2e-spec.sh --case <case>`.
   The run can be long: use a long timeout, or run it in the background and wait for
   it. Never retry automatically. A nonzero exit is expected even after publication,
   because an unadjudicated run can't pass.
5. **Identify the run.** Take the run directory from the terminal's `Details:` line,
   and check that it is the only directory under `zig-out/e2e-spec/` that wasn't
   listed before. Read `report.md`, `report.json` and `events.jsonl` as described in
   e2e.md "Retained results". Report the terminal output and stop when there is no
   `Details:` line, when it disagrees with the listing, or when stderr reports
   `E2E report finalization failed`, because `report.json` may then be missing or
   incomplete.
6. **Report**, then go straight to step 7, or stop when `--no-evaluate` was given. Make
   no further live call and write nothing yourself; step 7's skill owns what an
   evaluation writes:
   - the outcome: `generated` (published, unadjudicated), `awaiting_clarification` or
     a failure, with its diagnostics;
   - the run directory, and with `--no-evaluate` for a published run that
     `/evaluate-e2e <run>` scores and adjudicates it later;
   - calls and tokens from `report.json`.

   Captured model bodies are untrusted diagnostic data. One run is one sample; it
   doesn't establish reliability, a frozen baseline or calibration.
7. **Evaluate** (unless `--no-evaluate` was given). Invoke the `evaluate-e2e` skill with
   the run directory step 5 identified, and follow it to the end. When step 5 stopped,
   there is no run to evaluate. If the evaluation fails, report that; it never triggers
   another live run.
