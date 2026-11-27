# ADR 0034: Specify quality gate before Plan

- **Status:** Accepted
- **Date:** 2026-10-22
- **Decision authority:** User decisions, 22 October and 3, 7, 14 and 28 November 2026
- **Amends:** design.md §30 (Increments 3–5 start only after this gate); AGENTS.md "Current
  project state"

## Context

Plan, Tasks and Implement would consume Specify's output and multiply the engine's
per-concept costs. [SPEC01](../../fixes/SPEC01.md) §1 records the gate's status.

## Decision

### What waits

No work toward Plan, Tasks or Implement starts until the gate passes. Tasks and Implement
wait with Plan, because they follow it in the ordered SDD suite. Design work waits, not only
code:

- no contracts, ADRs or design amendments specific to those workflows;
- no workflow definitions for them;
- no engine code or tests whose purpose is those workflows.

Engine and Specify work continues.

### The gate

The Spec workflow must be stable and producing high-quality output on both development
cases, hello-world and loan-renewal. The sixteen reserved qualification features are
never used for it.

- **High quality.** Each counted published specification is accepted under
  [R8](../harness/acceptance.md), which owns the rubric bar and the deterministic mechanics.
  `zig build adjudicate-spec` applies the `spec-adjudication-record/v1` that the
  `/evaluate-e2e` skill writes; AGENTS.md "Testing expectations" sets who may start the skill.
- **Stable.** Repeated live runs of each case on one build whose recorded
  `build.source.modified` is false, with one recorded source hash, show stable output. Every
  attempted run counts, including runs stopped by budget or deadline and malformed or
  exhausted runs (AGENTS.md). There is no fixed run count or pass rate: the user judges the
  evidence.
- **The build.** The gate must hold on the build Plan work starts from. After a later
  structural change, the gate is re-run on that build.
- **Evidence reported separately:**
  - mechanical checks passed;
  - publication rate per case;
  - adjudicated quality per run;
  - tokens, calls and latency per acceptable result.

### Who decides

Only the user declares the gate passed and decides when Plan is actioned, on that
evidence.

- Agents don't ask the user to set a threshold or to start Plan.
- When Spec evidence is relevant, agents report it.
- An agent asked to start Plan, Tasks or Implement work without the user's go-ahead
  reports this gate and what remains, rather than starting.

## Consequences

- **Plan waits** until Specify's quality is established, however long that takes.
- **A build change can make earlier runs unreadable.** If a change advances a report or
  step-event format, the new build can no longer read earlier runs
  ([ADR 0030](0030-engine-owned-model-request.md), "Retained evidence"), which is why gate
  evidence comes from the build Plan work starts from.
- **Gate runs need approval.** Each live run the gate needs is billed and needs its own
  approval. Each published run needs the skill's adjudication.
