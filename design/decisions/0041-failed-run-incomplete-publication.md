# ADR 0041: A failed or blocked run publishes its validated results, marked incomplete

- **Status:** Accepted
- **Date:** 2026-10-26
- **Decision authority:** The user's decision on 26 October 2026. Asked whether a
  required step that fails should also publish what it has, marked incomplete (for
  example, "if the records step runs away twice, the run would publish the title, brief
  and user story with an incomplete status"), the user answered "yes, publish and log,
  and mark as incompelete", then "update docs". It extends the same day's "incomplete
  results must be published, but it must be indicated that the results are incompelete,
  and it must also be logged" ([ADR 0040](0040-incomplete-review-published-marked-logged.md))
  from review to required work. On the same day the user approved extending it to
  blocked runs ("3 yes", then "update with recommendations and implement"). On
  27 October 2026 the user accepted the four mechanism decisions of a read-only design
  pass (Decision 6), with "update the docs with the above recommendations" after the
  recommendation "accept all four as proposed".
- **Amends:**
  - [ADR 0009](0009-atomic-workflow-execution.md): "Candidate outputs remain private
    until whole-workflow validation permits publication", for the validated content of
    a failed Specify run; the execution stays the atomic unit, nothing resumes, and a
    failed run still never reports success;
  - [ADR 0017](0017-incomplete-specification-publication.md): an execution that fails
    now publishes its own incomplete projection, instead of "no new specification
    publication";
  - [ADR 0039](0039-configured-temperatures-and-runaway-resend.md): a required runaway
    on its re-send publishes this projection instead of nothing;
  - [ADR 0040](0040-incomplete-review-published-marked-logged.md) Decision 5: a failed
    run publishes this projection;
  - [ADR 0011](0011-provider-owned-request-limits.md),
    [ADR 0023](0023-advisory-post-generation-review.md) and
    [ADR 0037](0037-configured-workflow-token-budget.md): a token-budget failure stays
    fatal to model work, but publishes this projection;
  - §3.3 (invariant on failed publication), §12.8.1 (the terminal-error rows), §17,
    §22.6 (uncorrectable JSON/schema rejection), §23.2 and §25 (the published set),
    §24 (`specification-state/v20`), §27 and F0002 (the `run.incomplete_published`
    event), §31.15, F0100 §5.5, diagram 09, the [E2E harness](../harness/e2e.md) and
    the §32 index;
  - §23.2 ("blocked … executions publish no new specification") and the §12.8.1
    administrative-block row, for blocked runs;
  - for the mechanism (Decision 6):
    - [ADR 0005](0005-workflow-defined-operations.md): the engine-kernel list gains running
      a definition's declared failure output after an eligible failure;
    - [ADR 0009](0009-atomic-workflow-execution.md): publication may run while failures
      are pending, only in failure-output mode;
    - [ADR 0030](0030-engine-owned-model-request.md): a runner rejection stays a terminal
      engine stop, not a YAML outcome, and may be followed only by the failure output;
    - §6 (runner rejections), §9 and [F0005](../features/F0005-WorkflowDefinitionRegistryService.md)
      (the definition contract becomes `workflow/v2` with an optional `failure-output`,
      and the formal [workflow-definition schema](../schemas/workflow-definition-v1.schema.json)
      with it), §14 (the engine loop) and §25 (the publication terminals).

  The overall design remains **Proposed design**.

## Context

When a required Specify step failed, for example a records response that ran away twice
or a correction that ran out, the run published nothing. Content that had already
passed its checks, such as the title, brief and user story, was lost, and the previous
publication stayed in place unchanged. ADR 0017 already publishes a validated
incomplete specification when a run pauses for clarification.

## Decision

1. **Which runs publish.** A Specify run that fails because model work couldn't be
   completed, or that ends `blocked`, publishes an incomplete specification. In engine
   terms (Decision 6), these are a YAML `failed`, `blocked` or `invalid` terminal and
   the runner's `retry_limit` and `token_budget` rejections. This covers:
   - a request that fails: a provider failure, a runaway on its re-send, missing usage
     or a request timeout (YAML `failed`), or exhausted protocol correction
     (`retry_limit`, `RetryLimitExhausted`);
   - exhausted repair, including `RepairNoProgress` (`retry_limit`), and a candidate
     that fails its validation with no repair left (YAML `invalid`);
   - a token-budget failure (`token_budget`, `WorkflowTokenBudgetExceeded`), which
     still stops all model calls;
   - a YAML `blocked` outcome, such as an administrative block, required upstream
     rework or a coverage gap (`no_independent_supported_target`).

   These still publish nothing:
   - cancellation (`cancelled`);
   - security, path, trusted-association or forged-evidence failures (`authority`),
     because the content can't be trusted;
   - a runner gate rejection (`gate`);
   - logging and model-capture failures (`logging`, `model_capture`), because the
     publication couldn't be recorded;
   - configuration, bootstrap, allocation and invariant failures (`operation_failed`);
   - the run deadline (`deadline_exhausted`); a single request's timeout is a YAML
     `failed` and publishes;
   - a failure before the reference snapshot validated, because nothing validated
     exists to publish.
2. **What is published.** Only content that passed every check that applies to it on
   its own: the validated reference snapshot and its cited source requirements (as in
   ADR 0017), and each generated unit (title, brief, story or record batch) that was
   admitted and validated before the failure.
   - A unit that failed, or was still being corrected or repaired, is not published, in
     whole or in part, and neither is a unit whose owner has an unresolved candidate
     outcome. Unvalidated model output never appears.
   - **No final requirement IDs.** Final IDs (`FR-001`, `AC-001` and the rest) exist only
     after whole-specification assembly, so the view lists validated records without
     them, as ADR 0017's view already does.
   - Checks over the whole specification (coverage, cross-record rules, review) didn't
     run. The output says so and claims no result for them.
3. **It is marked incomplete.** Rendering is deterministic from stored state.
   - `spec.md` starts with `**Status: Incomplete — the run failed.**` or
     `**Status: Incomplete — the run was blocked.**`, then one sentence naming the step
     and its diagnostic. Each section the run didn't produce
     shows that it wasn't generated.
   - `reference-context.md` has a "Run status" section with the step, the diagnostic,
     the units not produced and the checks that didn't run or didn't pass.
4. **It is logged.** After the failure or block events, the runner emits one warning
   `run.incomplete_published`, with the diagnostic code, before the publication writes.
   Its logging rejection prevents publication.
5. **It stays a failure or a block.**
   - The workflow outcome stays `failed` or `blocked`, and the executable exits nonzero.
   - A new `spec_incomplete` workflow-state variant, with a closed cause (`failed` or
     `blocked`), is written last by the shared writer. Like ADR 0017's pending state, it
     replaces any earlier completion authority, so Plan and later stages stay blocked.
   - It is never resumed. The next run starts again from `start` and revalidates
     current inputs.
   - Publication-write failures keep ADR 0009's failure rule.
6. **Mechanism: a declared failure output** (accepted 27 October 2026, not yet
   implemented). The runner's rejections end the run before any YAML edge, and
   publication accepts only `ok` and `needs_user`, so neither YAML routing nor today's
   publication path can reach these runs.
   - **The definition declares it.** A workflow definition may name one definition-local
     subgraph as `failure-output`. The compiler requires that subgraph to hold no model
     capability, to use only registered snapshot and incomplete-publication operations,
     and to end in its publication step. Only Specify declares one.
   - **The engine runs it through the runner.** When the loop ends in an eligible
     failure (Decision 1) and a validated reference snapshot exists, the generic engine
     orchestrator runs the declared steps through the same runner-owned step invocation,
     then returns the original failure. If the failure output itself fails, the original
     failure still stands. Runner rejections stay terminal engine stops, never YAML
     outcomes.
   - **Failure-output mode.** The runner refuses every model call; filesystem steps may
     run while failures are pending only in this mode; and one typed outcome-ledger policy
     lets an `incomplete` prepared output publish while failures are pending only when it
     carries every pending failure subject and its terminal is the recorded failure.
   - **Terminals and logging.** The publication terminal outcomes gain `failed` and
     `blocked`. At the logging barrier the finalizer logs the failure or block event with
     the original diagnostic, then `run.incomplete_published` (Decision 4), then
     finalizes, all before any write. The run report keeps the original rejection and
     adds an incomplete-publication marker for the CLI and the E2E report.
   - **`workflow/v2`.** The new member advances the closed definition contract from
     `workflow/v1` to `workflow/v2`. Every definition, the formal schema and every fixture
     move together, and `workflow/v1` rejects without a compatibility reader.
   - **Rejected alternatives.** Turning runner rejections into YAML outcomes would rewire
     every failure route and reverse ADR 0030 and §22's "never an ordinary YAML outcome".
     An ADR 0032 routine publishing after the failure would be a second publication path
     outside the runner.

## Consequences

- **Persistence.** `specification-state` advances to v20 for the new variant. Earlier
  states reject without migration. Workflow definitions advance to `workflow/v2`; a
  project holding a copied `workflow/v1` definition must replace it.
- **Risks.**
  - The outcome-ledger policy lets publication run while failures are pending. It stays
    limited to the incomplete prepared output and its recorded failure terminal.
  - A failed or blocked run overwrites the previous good `spec.md` (below).
  - A write failure part-way can leave mixed files, under ADR 0009's existing rule.
  - The change is about the size of ADR 0039.
- **Evidence.** A failed or blocked run with an incomplete publication is still a failed workload
  under AGENTS.md's evidence rules. Its incomplete specification is not scored, as for
  ADR 0017's pending view, and the E2E report records the published incomplete set.
- **Overwrites.** A failed run now replaces `spec.md` and `reference-context.md`, as a
  clarification pause already does.
- **Tests.**
  - Each publishing failure class, and a blocked run, publishes the incomplete set with
    its status, step and diagnostic, and the run still ends `failed` or `blocked` with a
    nonzero exit: one integration scenario each for a provider failure,
    `RunawayRepeated`, protocol exhaustion, `RepairNoProgress`, the token budget, a
    coverage block, an authority block, and a unit invalid with no repair left.
  - Each excluded class publishes nothing: cancellation, logging, authority, gate,
    `operation_failed`, the run deadline, and any failure before the snapshot.
  - Only validated units appear, without final requirement IDs: a unit mid-correction,
    mid-repair, rejected or with an unresolved candidate outcome is absent; sections the
    run didn't produce are marked not generated.
  - Mechanism: the compiler rejects a `failure-output` that is missing its subgraph,
    holds a model step or doesn't end in publication; a model call in failure-output
    mode is refused; publishing with a pending failure outside that mode is rejected; a
    failure inside the failure output keeps the original failure; `workflow/v1`
    definitions reject; orchestrator spy tests cover both the plain-failure and the
    failure-output branch.
  - `run.incomplete_published` is logged once; a logging rejection prevents
    publication.
  - The `spec_incomplete` state blocks Plan, replaces earlier completion authority,
    reads back and validates, and isn't resumed.
  - Identical state renders identical bytes.
