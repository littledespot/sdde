# Known failure classes and open work

Dated snapshot, last updated 23 October 2026. It mirrors the repository's active fix
record, [FIX05](../fixes/FIX05.md), which stays authoritative; completed work is in
[Z_FIX05](../fixes/Z_FIX05.md). Recheck the code before relying on an item. The
evidence rules for contract changes are in CLAUDE.md.

All live evidence so far comes from one model, GPT-OSS-20B on Bedrock. The live-test
policy also permits Claude Haiku 5.5 for generation (ADRs 0028 and 0029), but every E2E
slot still selects GPT-OSS-20B, so which classes below are model limitations is
unmeasured.

The labels *Proposed*, *Approved* and "needs a decision" record user decisions. Only
the user changes them; change a label here only to record a decision the user has
already made.

## Spec workflow failure classes seen in live runs

- **Extraction weakens obligations.** Loan-renewal's "must be able to renew" becomes
  "may renew" at extraction, and review judges it supported; the published output
  also lacks a refusal acceptance criterion. Extraction also returns one claim for a
  whole Markdown list. *Tried and reverted, 21 October 2026:* list-item extraction
  (ADR 0027, `2bf5ca6`) gave one claim per item but no better output and higher cost,
  and the user directed its revert (`527f870`, ADR 0027 deleted). The weakening has no
  current proposal; measure whether it recurs with another permitted model first.
- **Review dominates cost and misreports finding types.** Post-generation review
  takes about 75–80% of workflow tokens. It files invented or unsupported content as
  `candidate_omission`, has judged byte-identical text both supported and omitted,
  and has accepted an obligation-strength change. Under ADR 0023 every
  post-generation finding is advice: it never repairs content, rebuilds an upstream
  stage or creates a clarification. *Built 20 October 2026 (approved 18 October):*
  source review assigns one record family per call (ADR 0023 "Record families",
  `specification-state/v19`). Its effect on cost is not yet measured live, and
  loan-renewal still ran out of budget in review twice on 21–22 October.
- **Record authoring duplicates.** A record batch can re-author the whole feature.
  Groups holding only preserved tokens no longer get a batch (ADR 0024). The native
  duplicate rule compares whole typed content, including the record kind, so
  identical text in two record kinds passes. *Proposed:* compare per-group records
  with one complete collection, only if generation-boundary failures remain. Add an
  acceptance-criterion diagnostic or per-family collections only where measured
  failures justify them.
- **Entity applicability is a model judgment** that no native rule can check.
  Hello-world has no data, yet it has been judged both `not_applicable` and
  `required`.
- **Unresolvable positive advisory verdicts** (FIX05 route 4) are withheld from the
  assignment's response schema. *Built 20 October 2026*: one in a response is a
  typed admission defect that takes protocol correction (ADR 0023). The reachable
  case is a coverage subject whose collection has no records. No live run has hit
  it yet.
- **GPT-OSS envelope prefixes.** GPT-OSS-20B often malforms a response's opening, for
  example `{"token{` or `{"find{`. Admission normalizes the truncated member-name form
  (approved 18 October 2026). Widening the normalizer needs a decision.
- **Runaway output.** GPT-OSS-20B sometimes writes a valid finding, then tens of
  thousands of whitespace characters until the 16,384-token maximum, mostly in source
  review. Under the old 60 s request deadline this showed only as a `timeout` (three
  runs on 21 October). The user raised the deadline to 180 s (`9719dc7`); the runaway
  then ended `output_limit`, its advice closed incomplete and the run published. The
  catalogue's Claude Haiku 5.5 entries declare 128,000 output tokens, so 180 s may not
  cover that model. *Settled in design on 23 October 2026 (ADR 0030 amendment, not yet
  implemented):* each catalogue entry declares its own `requestTimeoutMs`; Haiku starts at
  the shared 180,000 ms until its measured maximum-output time replaces it. Lower
  allowances, bounded
  correction and cardinality bounds each need a decision; don't tune sampling or add
  retries.
- **Budget headroom.** Loan-renewal has exhausted the 100,000-token budget in review
  (most recently 22 October, at 100,763 tokens) and published at 76,501–97,475 tokens.
  Raising the budget doesn't fix reliability.

## Other open work

- **Clarification answer recovery** is a confirmed implementation gap: fresh answers
  cannot complete the registered recovery path. Refresh rejects new nonempty
  submissions with `AuthenticationRequired`, and provenance rejects nonempty
  response-ID sets. Treat it as a separate required feature. *Decided 21 October
  2026 (ADR 0025):* the account that runs the engine is the actor, and the run that
  reads valid closed forms accepts them. Implementation hasn't started.
- **Prior-run crash finalization is not implemented.** §14.10 resolves each prior
  run's policy through a persisted `BootstrapAuthorityState`, which the engine
  lacks. Retention runs (ADR 0026, built 20 October 2026). It keeps any run with an
  active tail, so a crashed run's logs stay until this is decided. Damaged prior
  logs block later runs until someone repairs or removes them. Stray regular files
  in the log folders, such as Finder's `.DS_Store`, are left alone (ADR 0026,
  amended 21 October 2026).
- **Cancellation during log reads and under a log lock is reported as a logging
  failure.** The shared segment readers and the feature-log sink port have no
  cancellation outcome, for the current run or for retention. That conflicts with
  keeping cancelled distinct from failed. Fixing it changes the shared sink
  contract.
- **Every lock-acquisition failure is reported as `LOG_LOCK_TIMEOUT`.** The shared
  acquire action collapses an insecure or unopenable lock file into a timeout, for
  the current run and for retention.
- **Provider records.** ADR 0028 names an F0009 feature document and a contract
  §12.3.2, and neither exists. ADR 0029 says the shipped E2E cases select Claude
  Haiku 5.5, but their configuration selects GPT-OSS-20B; either the configuration or
  the ADR text needs to change. No live Claude call has been made.
- **Group-level provenance precision.** A record binds a whole accepted group, so
  membership doesn't mean each record expresses every linked claim. This follows
  ADR 0020 and is not a defect. Decide it before promising stronger provenance.
- **Architecture decisions before Plan.** Several problems are known:
  - lifecycle mechanics live in workflow YAML. *Approved 22 October 2026 (ADR 0030):* one
    engine-owned `request-model` step per model request replaces the 16-step subgraph and
    its wrappers. *Choices settled 23 October 2026:* kernel orchestrator and YAML release
    kept; provider token counting removed (the global token count, from actual usage,
    stays); the deadline moves to each catalogue entry as `requestTimeoutMs`; only steps
    marked `advisory: allowed` map `more` and `blocked` (they may carry both kinds of
    request; only an advisory request at an unmarked step is rejected). It builds the
    shared contract-variant mechanism that ADR 0033 reuses (confirmed 23 October 2026).
    Documentation is updated; implementation hasn't started;
  - each concept costs about six coordinated edits. *Approved 22 October 2026 (ADR 0031,
    option (b)):* one stage action whose internal steps are typed functions and route no
    outcome; its read-only limit awaits confirmation.
    Documentation is updated; the first conversion, `prepare-toolchain`, hasn't started;
  - type-erased child bindings hide data flow. *Approved 22 October 2026 (ADR 0032,
    option (b)):* fixed engine sequences become typed engine routines, startup first and
    feature logging second under preconditions. Documentation is updated; implementation
    hasn't started;
  - many rejections carry no reason. *Proposed:* closed reasons at their owners; the
    ADR 0030 and 0031 conversions will move many of the sites first;
  - repair routes repeat one shape: eight routes at `b2f10a3`; today 29 per-owner
    operations, 13 owners and 7 repair model-call sites. *Approved 22 October 2026 (ADR 0033):* four
    generic repair operations with a closed `owner` and owner-supplied rules replace the
    29 per-owner ones, as per-owner contract variants (choice 1, confirmed 23 October
    2026) on the mechanism ADR 0030 builds. They convert after A1 and A2's first
    conversion. Documentation is updated; implementation hasn't started;
  - reconciliation always makes four calls;
  - two pairs of sibling steps are identical. *Proposed:* merge them; this needs no
    ADR change. An ADR 0031 stage conversion may absorb them first.

  Before starting Plan, decide the questions on lifecycle, edit cost, child bindings
  and repair routes, and freeze the contract scope. Move lifecycle mechanics out of
  YAML before adding operations for another workflow.
  - *Decided 22 October 2026 (ADR 0034):* Plan, Tasks and Implement work doesn't start
    until the Spec workflow is stable and producing high-quality output on both
    development cases.
  - Quality means R8 human adjudication; stability means repeated runs, counting every
    attempt.
  - There is no fixed run threshold. The user decides when Plan is actioned; don't ask.
  - It isn't met: no run has been adjudicated, every 21–22 October run used a modified
    build, and loan-renewal published in 2 of 6 attempts since 21 October.
