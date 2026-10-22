# ADR 0034: Specify quality gate before Plan

- **Status:** Accepted
- **Date:** 2026-10-22
- **Decision authority:** The user's instruction on 22 October 2026: "The plan will not
  start until spec workflow is stable and producing high quality output, update the
  documentation". It decides [FIX05](../../fixes/FIX05.md) A6's scope question. It
  replaces A6's proposed bar, which was "until Specify publishes on both development
  cases".
- **Amends:**
  - design.md §30: Increments 3–5 (Plan, Tasks, Implement) start only after this gate;
  - the design.md §32 index;
  - AGENTS.md "Current project state";
  - FIX05 A6 and §6;
  - `.claude/known-work.md`;
  - ADR 0033's two references to FIX05 A6.

  The overall design remains **Proposed design**.

## Context

Plan, Tasks and Implement would consume Specify's output and multiply the engine's
per-concept costs. FIX05 A6 proposed starting them once Specify publishes on both
development cases.

The current state, on 22 October 2026:

- **Adjudication.** No published run has been human-adjudicated.
- **Hello-world.** Since the 20 October record-family change, it published in 5 of 6
  attempted runs.
- **Loan-renewal.** It published in 2 of 6 attempted runs. Two ran out of token budget and
  two ran out of time.

The gate below is not met. These figures are context, not gate evidence: 10 of those 12 runs
ran on uncommitted trees across four builds.

## Decision

### What waits

No work toward Plan, Tasks or Implement starts until the gate passes. That means:

- no contracts, ADRs or design amendments specific to those workflows;
- no workflow definitions for them;
- no engine code or tests whose purpose is those workflows.

Engine and Specify work continues, including ADRs 0030–0033 under their own sequencing
rules.

### The gate

The Spec workflow must be stable and producing high-quality output on both development
cases, hello-world and loan-renewal. The sixteen reserved qualification features are
never used for it.

- **High quality.** Each counted published specification is accepted under
  [R8](../harness/acceptance.md) by `zig build adjudicate-spec`, applying the user's
  `human-spec-adjudication/v2` record. That covers:
  - the rubric bar: at least an 80% aggregate, and every critical criterion at least 3/4;
  - R8's deterministic mechanics: the expected native outcome, validated artifacts, an
    intact source and provenance join, and zero measured admission escape.

  Advisory `/evaluate-e2e` analysis doesn't count, and no model grades a run.
- **Stable.** Repeated live runs of each case on the same committed build show stable
  output. Every attempted run counts, including runs stopped by budget or deadline and
  malformed or exhausted runs (CLAUDE.md). There is no fixed run count or pass rate: the
  user judges the evidence.
- **Evidence reported separately:**
  - mechanical checks passed;
  - publication rate per case;
  - adjudicated quality per run;
  - tokens, calls and latency per acceptable result.

### Who decides

Only the user declares the gate passed and decides when Plan is actioned, on that
evidence. The user said on 22 October 2026: "I will decide, when plan must be actioned, no
need to ask again".

- Agents don't ask the user to set a threshold or to start Plan.
- When Spec evidence is relevant, agents report it.
- An agent asked to start Plan, Tasks or Implement work without the user's go-ahead
  reports this gate and what remains, rather than starting.

## Derived under existing rules

The user's words set the gate. These details are derived from existing authority, not
from the user's words, and await the user's confirmation:

1. **Tasks and Implement** wait too, because they follow Plan in the ordered SDD suite.
2. **Design work waits,** not only code: no contracts, ADRs or amendments specific to those
   workflows (FIX05 A6's original scope).
3. **Both development cases** must meet the gate (CLAUDE.md: decide on at least two
   unrelated cases).
4. **"High quality" means R8 acceptance.** The user may want a higher bar than "accepted".
5. **Stability runs use one committed build,** and every attempt counts (CLAUDE.md).
6. **The evidence list** above.
7. **The build.** The gate must hold on the build Plan work starts from.

## Not decided here

- **Re-runs after a later structural change,** such as an ADR 0030–0033 conversion that
  lands after the gate passes. The user decides whether the gate is re-run on the new
  build. The recommendation is to run the gate after those conversions land.

## Consequences

- **Plan waits** until Specify's quality is established, however long that takes.
- **The FIX05 refactors can still land.** A1–A3 and W3 claim no quality change, so they
  don't count toward the gate. Each one changes the build, though. If one advances a report
  or step-event format, earlier runs can no longer be read by the new build (ADR 0030,
  "Retained evidence"). Gate evidence should therefore come from the build Plan work
  starts from.
- **Gate runs need approval.** Each live run the gate needs is billed and needs its own
  approval, as today. Each published run needs the user's adjudication.
