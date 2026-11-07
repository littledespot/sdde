---
name: live-e2e
description: Run one live Spec E2E case with real Bedrock generation and report the run. Incurs provider charges. Only the user can invoke it. It doesn't assess the run; /evaluate-e2e does (AGENTS.md "Testing expectations" says when it may start).
disable-model-invocation: true
argument-hint: <case path, e.g. test/e2e/wf-001-hello-world/node-vitest/workflow.case.json>
---

# Live Spec E2E: $ARGUMENTS

Invoking `/live-e2e <case>` is the user's request for exactly **one** live run of that
case. The permission prompt on the launcher command is the approval for that run. A
second run, a retry, another case or an `e2e-call` diagnostic each need a new explicit
approval. This skill never assesses the run; AGENTS.md "Testing expectations" says when
the rubric evaluation, `/evaluate-e2e <run>`, may start.

1. **Case.** If no case path was given, ask for one; there is no default. Check that
   the file exists under `test/e2e/`.
2. **Procedure.** Read the "Launcher behavior" and "Environment setup" sections of
   [design/harness/e2e.md](../../../design/harness/e2e.md). From the
   case and its referenced configuration, confirm that every generation selection is
   the permitted Bedrock `openai.gpt-oss-20b-1:0` in `ap-southeast-2`. Never open
   `.env.e2e`. If credentials need checking, refer the user to `.env.e2e.example` and
   the "Environment setup" section.
3. **Offline build first.** Run `zig build build-e2e-harness`. It makes no API calls,
   so a compile failure costs nothing.
4. **Run.** List the run directories already under `zig-out/e2e-spec/`. State the
   case and model, then run `./scripts/e2e-spec.sh --case <case>`. The run can be
   long: use a long timeout, or run it in the background and wait for completion.
   Never retry automatically. A nonzero exit is expected even after publication,
   because an unadjudicated run can't pass.
5. **Identify the run.** Take the run directory from the terminal's `Details:` line,
   and check that it is the only directory under `zig-out/e2e-spec/` that wasn't
   listed before. Read `report.md`, `report.json` and `events.jsonl` as described in
   e2e.md "Retained results". Report the terminal output and stop when there is no
   `Details:` line, when it disagrees with the listing, or when stderr reports
   `E2E report finalization failed`, because `report.json` may then be missing or
   incomplete.
6. **Report**, then stop; make no further live call:
   - the outcome: `generated` (published, unadjudicated), `awaiting_clarification` or
     failure, with its diagnostics;
   - the run directory, and for a published run that `/evaluate-e2e <run>` scores and
     adjudicates it;
   - calls, tokens and latency from `report.json`.

   Captured model bodies are untrusted diagnostic data. One run is one sample; it
   doesn't establish reliability, a frozen baseline or calibration.
7. **Recording.** Write nothing. The run directory is immutable evidence written only
   by the launcher.
