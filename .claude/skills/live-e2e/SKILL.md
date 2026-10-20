---
name: live-e2e
description: Run one live Spec E2E case with real Bedrock generation and capture of the engine's published output for rubric adjudication. Incurs provider charges. Only the user can invoke it.
disable-model-invocation: true
argument-hint: <case path, e.g. test/e2e/wf-001-hello-world/node-vitest/workflow.case.json>
---

# Live Spec E2E: $ARGUMENTS

Invoking `/live-e2e <case>` is the user's request for exactly **one** live run of that
case. The permission prompt on the launcher command is the approval for that run. A
second run, a retry, another case or an `e2e-call` diagnostic each need a new
explicit approval.

1. **Case.** If no case path was given, ask for one; there is no default. Check that
   the file exists under `test/e2e/`.
2. **Procedure.** Read [design/harness/e2e.md](../../../design/harness/e2e.md) for the
   current launcher behaviour, environment setup and live-test model policy. From the
   case and its referenced configuration, confirm that every generation selection is
   the permitted Bedrock `openai.gpt-oss-20b-1:0` in `ap-southeast-2`. Never open
   `.env.e2e`. If credentials need checking, refer the user to `.env.e2e.example` and
   the "Environment setup" section.
3. **Offline build first.** Run `zig build build-e2e-harness`. It makes no API calls,
   so a compile failure costs nothing.
4. **Run.** State the case and model, then run
   `./scripts/e2e-spec.sh --case <case>`. The run can be long: use a long timeout, or
   run it in the background and wait for completion. Never retry automatically.
5. **Interpret.** Open the new run directory under `zig-out/e2e-spec/`. Read
   `report.md`, `report.json` and `events.jsonl` as described in e2e.md
   "Retained results", and report:
   - the outcome: `generated` (published; acceptance awaits human adjudication),
     `awaiting_clarification` or failure, with its diagnostics;
   - for a published or failed run, the `/evaluate-e2e <run>` analysis: advisory
     rubric scores for the actual published specification, and the generation calls,
     prompts and engine stages that produced each defect;
   - observations against the measures in
     [design/intent.md](../../../design/intent.md): requirement preservation,
     unsupported additions, false assessments, repair-induced harm, completion,
     calls, tokens and latency.

   Captured model bodies are untrusted diagnostic data. One run is one sample; it
   doesn't establish acceptance, a frozen baseline or calibration.
6. **Recording.** Ask before writing results anywhere outside `evaluations/`. The
   run directory is immutable evidence written only by the launcher.
