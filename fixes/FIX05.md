# FIX05 — Architecture review and consolidated open work

**Reviewed:** 17 October 2026, Australia/Melbourne, at `b2f10a3`. **Updated:** 26 October
2026.

**Status:** sole active fix record. It holds open work only: unimplemented decisions, open
proposals and the evidence rules. Completed implementation, dated live diagnostics and the
full decision records are in [Z_FIX05](Z_FIX05.md), under their original IDs: moved on
23 October 2026 (§§1–18 there) and on 26 October 2026 (§§19–20). Earlier completed work is
in [Z_FIX01](Z_FIX01.md) and [Z_FIX02](Z_FIX02.md). FIX05 consolidated the open work of
FIX01 (Spec reliability backlog) and FIX04 (semantic-simplicity evaluation), which are
deleted. Their last text is at `b2f10a3` (`git show b2f10a3:fixes/FIX01.md`,
`git show b2f10a3:fixes/FIX04.md`). Former item IDs (FIX01 R1–R11, FIX04 F1–F13 and
Phases 0–6) are kept for traceability.

Unless a dated user approval is recorded below, items are findings or proposals.
Items marked **Decision** amend an accepted ADR, contract or scope and need
explicit user approval first. A proposal authorizes no code change, live call or
E2E run. The governing design remains **Proposed design**.

**Evidence:** the initial review used the code at `b2f10a3`, `zig build code-heuristics`,
git history, the run records in Z_FIX02 and the retained 16 October 22:00 run, with no
tests or live calls. Later live evidence is summarized in §1 and recorded in Z_FIX05.

## 1. Verdict

The deterministic core works. Since Phase 1A no value breaking a declared native rule
has escaped admission, and every failure ends as a typed outcome. Duplication is low
(five pairs of repeated function bodies, two of which W2 removes), and production
code has no `@constCast` and nine
`catch unreachable`. The engine is not hard to build or brittle because of local code
quality.

Two structural properties cause both problems:

1. **The architecture makes every concept expensive.** One idea is spread across an
   action, a binding, a registry entry, global data keys, YAML nodes and pinned
   tests. The generic runner also has to police the model-request lifecycle that
   the YAML exposes (§2).
2. **The Spec workflow is a long serial chain of strict, fail-closed judgments by one
   small model.** End-to-end success is roughly the product of per-call success, and
   fixed per-call overhead exhausts the token budget before review finishes (§3).

A stronger model would likely hide these weaknesses rather than remove them.

| Measure, at the 17 October review | Value |
| --- | --- |
| Hello-world reference | 189 bytes, three requirements ([stories.md](../test/e2e/wf-001-hello-world/reference/stories.md)) |
| Code | 63,889 production and 82,792 test lines, for one of four planned workflows |
| Spec workflow | 1,168 YAML lines; 282 steps in 33 graphs (205 operation nodes, 77 subgraph calls); 185 distinct operations; 18 model-request sites (§4) |
| History | 199 commits in 8 weeks; 297,901 Zig lines inserted and 148,709 surviving; 22 ADRs between 26 August and 6 October |

The dated live diagnostics of 16–18 October are in
[Z_FIX05 §1](Z_FIX05.md#1-live-diagnostics-1618-october-2026).

### Current state — 26 October 2026

**Done, committed and moved to Z_FIX05.** Everything below is on `39a06ea`, merged as
PR #10 (`1261106`), and verified offline. Live semantic benefit is not demonstrated
unless a row says so (§7).

| Item | State | Record |
| --- | --- | --- |
| B2 | Advisory post-generation review (ADR 0023); one record family per source-review call | [B2 records](Z_FIX05.md#b2-records) |
| B3, B8 | Native exact-value recognition and bookkeeping (ADR 0024) | [B3](Z_FIX05.md#b3-exact-value-bookkeeping-is-left-to-the-model), [B8](Z_FIX05.md#b8-the-model-classifies-and-disposes-exact-value-tokens) |
| B4 | One principle assignment per principle set; one budget, configured as `workflowTokenBudget` (ADR 0037, 125,000 for E2E) | [B4 records](Z_FIX05.md#b4-records), [B4 configured budget](Z_FIX05.md#b4-configured-budget-record) |
| B5 | No batch for token-only groups (ADR 0024); cross-kind restatement deleted natively (ADR 0035); records name their claims and functional requirements need a scenario (ADR 0038) | [B5 token-only batches](Z_FIX05.md#b5-token-only-record-batches), [B5 records](Z_FIX05.md#b5-records-2425-october-2026) |
| B6 | GPT-OSS envelope prefix normalized | [B6 envelope prefix](Z_FIX05.md#b6-gpt-oss-envelope-prefix) |
| B7 | Source-quoted claim wording and code-delimiter removal (ADR 0036); list-item claim split (ADR 0038) | [B7 records](Z_FIX05.md#b7-records-2125-october-2026) |
| B9 | Feature-owned entity records; no output allowance; one re-send after a runaway at the configured `temperatureRunawayRetry`, logged (ADR 0039) | [B9 records](Z_FIX05.md#b9-records), [B9 runaway evidence](Z_FIX05.md#b9-runaway-evidence-and-re-send-decision) |
| Review publication | Incomplete review published, marked and logged (ADR 0040); principle verdicts need citations at admission (ADR 0042) | [Z_FIX05 §20](Z_FIX05.md#20-adrs-00390043-and-live-runs--26-october-2026) |
| Vocabulary | Model-facing `exact_text` names (ADR 0043) | [Z_FIX05 §20](Z_FIX05.md#20-adrs-00390043-and-live-runs--26-october-2026) |
| A1 | ADR 0030 slices 1–3 (freeze, token counting removed, catalogue deadline) | [A1 slices 1–3](Z_FIX05.md#a1-settled-choices-and-slices-13) |
| W1, W2 | No post-generation upstream rebuild; the duplicate path is deleted | [W1](Z_FIX05.md#w1-review-can-restart-the-whole-pipeline), [W2](Z_FIX05.md#w2-the-upstream-repair-path-exists-twice) |
| R8 | Acceptance policy implemented offline; adjudication and calibration open (R8 below) | [R8 record](Z_FIX05.md#r8-record) |
| Test performance P1, P9 | Untraced leak-checking allocator and opt-in test-run reuse | [Z_FIX05 §18](Z_FIX05.md#18-offline-test-performance-p1-and-p9--24-october-2026) |

The 21–25 October runs and the record as it stood on 25 October are in
[Z_FIX05](Z_FIX05.md#current-state-as-of-25-october-2026).

**Live runs on 26 October 2026 (AEDT), GPT-OSS-20B on Bedrock, each user-approved.**
Advisory scores are `/evaluate-e2e` analysis under `evaluations/e2e/`, not grades or
acceptance.

| Run | Build | Calls / tokens | Outcome |
| --- | --- | --- | --- |
| Hello-world and loan-renewal, 17:57 | `54ce8fa`, modified | 1 / 0 each | `authorization_denied`: the Bedrock API key had expired |
| [Hello-world](../zig-out/e2e-spec/2026-10-26T07-06-24Z-2bcbb4d769b998b2249210be1e590348/report.json), 18:06 | `54ce8fa`, modified (the ADR 0038–0043 tree) | 24 / 66,358 | Published; advisory 82.14% |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-26T07-06-25Z-a5ac7cc3a13b9dc94d84828648c7eaba/report.json), 18:06 | `54ce8fa`, modified | 26 / 91,129 | Published; advisory 78.57%, below threshold, no critical failure |
| [Hello-world](../zig-out/e2e-spec/2026-10-26T08-09-02Z-314509c4e65f3bb4bc6a15fc2d3dd4ed/report.json), 19:09 | `39a06ea` | 25 / 84,951 | Published; advisory 82.14%; one source-review runaway recovered by the re-send |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-26T08-09-03Z-a89fd748b0ce942ddd496ba3e42469c3/report.json), 19:09 | `39a06ea` | 26 / 89,887 | Published; advisory 78.57%, below threshold, no critical failure |

- **Completion since 21 October**, counting every attempt: hello-world published 15 of
  17, loan-renewal 7 of 17. All four completed 26 October runs published, every call was
  admitted first time apart from the one runaway, and no review ended incomplete.
- **What held across the four runs:**
  - loan-renewal's refusal behaviour has its own acceptance criterion (AC-002), written
    on the first records attempt, which no earlier build achieved (B5);
  - the 25 October `uncertain` title verdict that failed loan-renewal didn't recur, but
    principle citations collapsed (B11);
  - business rules restate the functional requirement in every run of both cases (B5);
  - invented or restating entities (B6), "may renew" in loan-renewal's story (B7), the
    renderer artefacts (B12), and source review passing defects (B2).
- **The re-send worked once.** Hello-world's source review of `Hello, World!` ran to the
  16,384-token maximum (18,823 tokens). The identical request at temperature 1 returned
  an admitted finding, and the log recorded `model.provider_stopped` then
  `model.runaway_resent` (B9).
- **Vocabulary.** "The preserved token" is gone from both cases (ADR 0043). Hello-world's
  brief now says "display the exact text …", which reads as plain English; watch it.
- **Evidence status.** One pair ran on an unmodified committed build of the current engine
  (`39a06ea`). No run has been adjudicated (R8, A6).

**Awaiting the user's decision:** ADR 0041's four mechanism choices (B10), the principle
prompt rewording (B11), business-rule guidance (B5), the renderer fixes (B12), the retained
v9 reports (R8), withdrawing B9's two conflicting choices, and B4's experiment stops.

**Providers.** ADR 0028 (Anthropic Messages API) and ADR 0029 (Bedrock model families) are
implemented. All live evidence so far comes from GPT-OSS-20B; the account has no Claude
Haiku 5.5 access, and model choice is the user's decision (R7).

## 2. Why the engine is hard to implement

### A1. Engine lifecycle mechanics live in workflow YAML

[ADR 0005](../design/decisions/0005-workflow-defined-operations.md#L28) requires every
retry branch, repair branch and success rule to be visible in YAML.
[ADR 0012](../design/decisions/0012-workflow-owned-model-request.md) retains one
request across YAML steps. Lifecycle correctness, however, stays a kernel duty.

As a result, one model call is a preparation node plus 14
[`model-request-body`](../design/workflows/spec.workflow.yaml#L1016) nodes:

- attempt accounting, operation assignment and authorization;
- a phase check and two lifecycle advances;
- invocation, observation validation and operation completion;
- admission, retry and close;
- two termination nodes.

The kernel then has to police every ordering of its own lifecycle.
[`executeStep`](../src/application/workflow_pipeline_runner.zig#L165) is 313 lines
with 213 decision tokens, and the "generic" runner mentions `model` 130 times and
`provider` 82 times. A wiring error surfaces as a runtime rejection, not a compile
error. Any lifecycle change touches YAML, runner checks and tests together.

**Decided 22 October 2026; partly implemented (slices 1–3).**
[ADR 0030](../design/decisions/0030-engine-owned-model-request.md) replaces the request
subgraph with one `request-model` step per model request. A fixed,
capability-free kernel orchestrator runs the lifecycle through
runner-owned child bindings. Consumers, release, advisory routing, `retain-json-part` and
ledger initialization stay in YAML. The full record is in
[Z_FIX05](Z_FIX05.md#a1-decision-record).

**Settled choices and slices 1–3** (freeze `5ce2af4`, token counting removed and the
deadline moved to each catalogue entry's `requestTimeoutMs`, 23–24 October) are recorded
in [Z_FIX05](Z_FIX05.md#a1-settled-choices-and-slices-13).

Open:

- **Slice 4:** the `request-model` step itself, with ADR 0030's offline acceptance and the
  shared contract-variant mechanism (confirmed 23 October 2026) that ADR 0033 reuses.
  - Since ADR 0039 the shared request body also carries `check-model-runaway` and
    `build-model-runaway-resend`, guarded by a compiler rule that admission's `invalid`
    route goes through them. Slice 4 folds the re-send into the `request-model` stages
    (ADR 0030 stage 12, as amended by ADR 0039) and retires that YAML rule.
  - ADR 0042's required-items constraint and ADR 0040's review closure must carry over
    unchanged; the slice 1 freeze is the equivalence baseline.
- the measured replacement for Claude Haiku 5.5's interim 180,000 ms `requestTimeoutMs`,
  only if the user selects that model;
- whether the engine should also take over release, which needs the compiler to derive
  each request's lifetime.

Slice 4 also settles the open points from the slice 1 contract review:

- the advisory production run (`test/harness/integration/tests.zig`, budget exhaustion,
  output limits and the advisory protocol stop) is not traced yet;
- the extraction content request appears as two keys, `extract/content`
  (preparation) and `extract/content-request` (the body), which slice 4 makes one
  `request-model` step;
- the deterministic evidence is the step traces and summary counts; file hashes are
  deterministic only because the run's reference state ID and recorded filesystem
  observations (file IDs and timestamps) are masked;
- pre-call termination, cancellation and authorization failure never occur in the
  matrix. **Decided 23 October 2026 (user, option b):** their baseline is today's
  runner-level lifecycle tests in `src/model_request_workflow_test.zig`, which compile
  real YAML and drive the real runner against fake ports. Slice 4 ports each one for
  one to `request-model`, with the same ports and assertions, and records a table
  mapping every existing test to its ported test, with a reason for any assertion it
  drops (such as tests that pin the removed operations' YAML ordering).

A1 is not expected to change model calls, tokens or reliability. The 22 October estimate
of a 35–90-line (3–8%) net YAML saving grows, because ordinary sites no longer route
advisory outcomes and no site declares a deadline. The larger gains are no body copy per
future workflow, lifecycle changes confined to the engine and less engine code.

### A2. Every concept costs about six coordinated edits

There are 266 actions, with a median size of 17 lines. Most delegate to
`src/domain/`, which holds 33,366 lines. Each operation also needs:

- an application binding with a second contract and an outcome association, for
  example [the protocol-retry binding](../src/application/model_protocol_retry_workflow.zig#L7);
- a registry entry;
- entries in the closed 196-member [`DataKey`](../src/domain/pipeline.zig#L4) enum,
  which 351 files import;
- a YAML node;
- usually an architecture test.

Churn concentrates at the centre. `composition/root.zig` changed in 86 of 199
commits, `pipeline.zig` in 48, the runner in 38 and `native_workflow_operations.zig`
in 37. Recent commits touch 50–200 files. Plan, Tasks and Implement would multiply
this cost.

**Decided 22 October 2026 as option (b); implementation not started.**
[ADR 0031](../design/decisions/0031-stage-actions.md) lets one registered stage action own
a deterministic sequence of internal steps that routes no outcome. Its internal steps are
typed functions, each with one responsibility and only the port it uses. Model requests,
writes, publication, commands, clarification persistence, feature-log activation, gate
issuers, repairs and every routed outcome stay their own actions or YAML transitions. The
full record is in [Z_FIX05](Z_FIX05.md#a2-decision-record).

Open:

- convert `prepare-toolchain` first, and record the A2 measure (files touched per change)
  before converting another stage;
- the derived choices awaiting confirmation: read-only stages, the absorption rule, the
  scope left to A3, `prepare-toolchain` first, offline evidence for structural
  conversions, and the contract-field and model-output limits. The restated W3, also
  derived here, was decided as ADR 0033, and ADR 0030's kernel form for model requests
  was confirmed on 23 October.

### A3. Type-erased child bindings hide data flow

Bootstrap configuration reading is 29 parameterless steps behind a `*anyopaque`
vtable ([bootstrap_child_bindings.zig](../src/application/bootstrap_child_bindings.zig#L10)).
Each step receives only the erased context and returns an outcome, so data moves
between steps through hidden mutable state. Production code has 386 `anyopaque` and
295 `@ptrCast`. The compiler cannot check the wiring where wiring errors happen, and
AGENTS.md lists unbounded `anyopaque` at boundaries as a prohibited shortcut.

**Decided 22 October 2026 as option (b); implementation not started.**
[ADR 0032](../design/decisions/0032-engine-routines.md) makes each fixed engine sequence a
typed engine routine in `src/application/*_routine.zig`: each step is a typed function with
only the port it uses, with no erased child bindings, vtables or shared optional state.
Routines get fake-port tests. The workflow-engine orchestrator and ADR 0030's request
coordinator are out of scope, and Specify invocation becomes an ADR 0031 stage action. The
full record is in [Z_FIX05](Z_FIX05.md#a3-decision-record).

Open:

- convert startup (bootstrap, provider config and provider bootstrap) first and measure it;
- convert feature logging only once ADR 0032's preconditions hold;
- the derived choices awaiting confirmation: the category and location, internal branches
  on typed facts, reaching a routine through the composition root or a binding, logging
  second, Specify invocation as a stage action, ADR 0030's form kept, and fake-port
  testing.

### A4. Rejections do not say why

The runner has 119 sites that return a payload-free `.rejected = .authority`, and
[`Rejection.diagnostic`](../src/domain/workflow_execution.zig#L54) reports only
`failed` for it. `src/application/` has 147 `error.OperationExecutionFailed` sites,
and production code has 865 `catch return <fixed tag>` mappings. Nested compiled step
IDs such as `g37-g25-g17-g8-generate-brief-gen-request-account` locate a failure but
not its cause. Every integration defect therefore needs manual bisection, which is
part of why the request debugger was built.

**Proposal** (no ADR change expected): give `.authority` a closed reason, and split
`OperationExecutionFailed` into specific causes at their owners. Keep typed outcomes
and terminal precedence unchanged.

The open failure-evidence gaps of former R9 belong here:

| Confirmed gap | Owning boundary and required change |
| --- | --- |
| Evaluator partial bodies disappear | [Observation](../test/harness/provider.zig#L19) lacks completeness and error-exit evidence. [Bedrock](../test/harness/bedrock.zig#L52) omits the transport's failure-body slot. [OpenAI HTTP](../test/harness/http.zig#L95) loses prefixes on read failure. [The trace](../test/harness/evaluation_trace.zig#L23) records only a thrown error. Thread retained bytes and completeness through the shared observation, with redaction and adapter-to-trace fault tests. |
| Simultaneous failures overwrite earlier causes | [Accounting](../src/application/workflow_model_invocation.zig#L24) can supersede an invocation cause, and [runner capture](../src/application/workflow_pipeline_runner.zig#L410) can supersede it again. Retain bounded primary and secondary evidence, preserving terminal precedence, ownership and allocation-failure handling. |
| The loss-localization call origin is not retained separately | [`collectLoss`](../src/domain/specification_support.zig#L369) keeps the original finding origins, so diagnostics can name the finding call instead of the localization call. Preserve both associations through collection, correction, repair authorization and reporting. |

Two further limits:

- Build snapshots capture allowlisted Git-visible bytes; they don't prove that the
  compiler consumed exactly that snapshot under concurrent edits.
- Progress labels include routine invalidation and retirement, so don't count every
  progress event as a semantic repair.

**Sequencing (23 October 2026).** The ADR 0030 and ADR 0031 conversions will move many of
these sites. ADR 0031 records the failing internal step in each stage's diagnostic, which
it calls "the shape FIX05 A4 asks for". Recount the sites after each conversion before
adding closed reasons elsewhere.

### A5. Tests pin structure and cannot see semantic failure

- Of 79 architecture tests, 69 pin specific files, with 420 source-text assertions.
  `src/architecture_test.zig` changed in 63 of 199 commits.
- The integration [driver](../src/test_fixtures/spec_generation_driver.zig#L185)
  threads about 40 fault flags into a hand-scripted
  [741-line response builder](../src/test_fixtures/spec_generation_responses.zig#L121).
  The two files changed 53 and 46 times respectively.
- Test code exceeds production code.

None of these tests can detect the semantic failures that block publication. Only
live runs can, and those are rare and billed.

**Proposal** (no ADR change): when the affected tests next change, express
architecture rules as import-graph and contract-shape rules instead of per-file pins.
Prefer replaying retained real captures over extending scripted responses, as the F10
admission replay and the exact-value prototype already do.

The ADR 0031 and ADR 0032 conversions rewrite the affected architecture rules, which is
the trigger this proposal names.

### A6. Contracts change faster than evidence accumulates

- There were 22 ADRs between 26 August and 6 October.
- Design and fix records saw 139,051 lines written and 91,493 deleted.
- Phases 1A.2 and 1A.3 were each opened by a single hello-world run, while
  near-identical requests produced opposite failures (F13).

AGENTS.md requires every fix at the shared owning contract, with no backward
compatibility, so each amendment becomes a large cross-cutting diff.

**Proposal:** apply the evidence rules in §7 to every contract change.

**Decided 22 October 2026, with a higher bar.**
[ADR 0034](../design/decisions/0034-spec-quality-gate.md): no Plan, Tasks or Implement
contracts, workflow definitions or code until the Spec workflow is stable and producing
high-quality output on both development cases. Quality means each counted published
specification passes R8 human adjudication. Stability means repeated runs of both cases
on one committed build, counting every attempted run. There is no fixed run threshold;
the user judges the evidence and decides when Plan is actioned. The full record is in
[Z_FIX05](Z_FIX05.md#a6-decision-record).

**Status on 26 October.** The gate isn't met:
- no run has been adjudicated (R8);
- four pairs used an unmodified committed build: `7a88804`, `8a600d7`, `269410b` and,
  for the current engine, `39a06ea` (26 October 19:09);
- since 21 October loan-renewal published in 7 of 17 attempts and hello-world in 15 of 17,
  with all four completed 26 October runs published (§1).

## 3. Why runs are brittle

### B1. A long fail-closed chain of model judgments

Publication requires the whole workflow to pass every validator across 40 or more
sends. As an illustration, not a measurement: if each call produced acceptable
output 97% of the time after its retries, 41 calls would succeed together about 29%
of the time; at 95%, about 12%. Splitting work into more calls lengthens the chain
unless each call's success rate rises enough to compensate (former F5 and F7).

**Proposal:** treat call count per feature as a reliability cost. B2, B4 option 3, B5 and
W1 have shortened the chain. Of the open items, W4 and B5's collection authoring would
shorten it further; ADRs 0030–0033 change workflow steps, not model calls. Judge progress
by useful completion per attempted workload (§7), never by per-call admission.

### B2. Review dominates cost and drives harmful repair

Post-generation review took 75–80% of workflow tokens, reported invented content as
omissions, judged byte-identical text both supported and omitted, accepted an
obligation-strength change, and once wrote a harmful repair that re-review accepted. The
evidence and records are in [Z_FIX05](Z_FIX05.md#b2-records).

**Done.** Approved on 17 October and implemented offline under
[ADR 0023](../design/decisions/0023-advisory-post-generation-review.md): every
post-generation semantic finding is advice, reviewed as whole units or collections. It
never authorizes content repair, an upstream rebuild, a mandatory Plan obligation or a
clarification. Source review assigns one record family per call (approved 18 October,
built 20 October, `specification-state/v19`).

**Still open: accuracy and waste.** On 25 October the user set quality above cost and
approved the 125,000-token budget instead of making source review optional, so source
review stays. On 26 October review took 41–58% of each run's tokens and:
- passed "may renew" in loan-renewal's story (B7), invented timing words in hello-world's
  story and invented entities (B6);
- made false statements, such as that the source defines an entity or that it says
  "may renew";
- filed unsupported additions as `candidate_omission`, a harmful diagnosis under §7;
- in loan-renewal returned `supported` for every source-review subject.

**Next:** label retained 26 October findings offline against frozen, source-based labels
(finding-type accuracy, §7) before any change that lets review alter output or removes a
review call. Under "quality over cost, but never waste", spending that buys no quality is
removed at its owner, never by keyword or truncation. A separately configured assessment
model (the original option 3, not approved) is a model choice and stays the user's
decision (R7).

Measure the review workload (former R5): coverage, sends and actual tokens per stage,
latency, retained memory and finding-type accuracy (§7).

- Don't discard policies by keyword, truncate required evidence or add local token
  ceilings.
- Don't claim that raising the budget fixes reliability.
- Group subjects only with evidence that per-subject findings, association,
  correction scope, origins and retry identity survive.

If the current review contract is kept, the next bounded work is the former R6
source-review direction. The reviewer sometimes checks only candidate clauses that
match sources, and sometimes promotes candidate additions into source requirements.
Clarify original-source authority, the candidate target and completeness for the
assigned field purpose through the existing shared purpose and evidence owner. Then
prepare a controlled actual-review comparison using these failures plus unrelated
controls. Further calls need bounded approval.

### B4. Fixed per-call overhead exhausts a compiled budget

**Done.** One principle assignment per principle set, and one total budget, configured
since ADR 0037 as `.sddtoolkit.json`'s `workflowTokenBudget` (125,000 for E2E). The records
are in [Z_FIX05](Z_FIX05.md#b4-records) and
[Z_FIX05](Z_FIX05.md#b4-configured-budget-record).

**Decision** (still open, required before any baseline freeze): the experiment stops and
the qualified scope. The protocol's stops of 1,000 sends and 2,000,000 tokens cover 16
workflows at 125,000 tokens each, against 144 development workloads, so the Phase 2
budget-feasibility report stays `insufficient`. The options are to revise the stops with a
recorded rationale, reduce review cost through its owner (B2), or narrow the qualified
scope. Measure the prompt, schema and evidence share of each call before trimming
anything, and add no local size ceilings (ADR 0011).

Since 25 October no run has stopped on the budget: the 26 October runs used 66,358–91,129
tokens.

### B5. Authoring follows mechanical source groups

**Done.** Token-only groups get no record batch (ADR 0024), covered cross-kind
restatements are deleted natively (ADR 0035), and each non-entity record names the
claims it supports, with every claim a functional requirement names also named by an
acceptance criterion or edge case (ADR 0038). One records call per feature was not
adopted. The records are in [Z_FIX05](Z_FIX05.md#b5-token-only-record-batches) and
[Z_FIX05](Z_FIX05.md#b5-records-2425-october-2026).

**Live effect, 26 October.** Loan-renewal's refusal behaviour has its own acceptance
criterion in both runs, on the first records attempt; the scenario rule didn't need to
fire. ADR 0038's limit stands: the rule checks links, not meaning.

Open:

- **Business rules restate functional requirements** (every 26 October run of both cases;
  loan-renewal states one requirement up to five times across the story, FR-001, business
  rules and the entity). ADR 0035 deletes only exact, covered restatements.
  **Decision:** add records guidance that a business rule holds only a constraint not
  already stated by a functional requirement (recommended), or extend the duplicate rule
  to partial restatements, which needs meaning, not text, and so isn't computable natively.
- **Records inflation.** On 25 October one loan-renewal batch wrote 40 records and another
  304. The 26 October batches were normal. It has no owner: B9's cardinality bound
  conflicts with the user's no-caps rule. Measure it on repetitions.
- **Follow-up:** no offline integration scenario exercises a records-batch native delete
  (ADR 0035).
- **Baseline.** Phase 2's harness exists but isn't frozen; it needs B4's decision and a
  committed build. The A/C comparison is superseded by ADR 0038. If the baseline meets the
  protocol's adequacy targets, retain it and stop the redesign.

### B6. Secondary failure classes to measure

- **Entity applicability.** No native rule can judge it. Hello-world has invented a
  required entity in most publications ("Application Start", "Greeting", "Application",
  and "HelloWorldApplication" in both 26 October runs). Loan-renewal's entity restates
  the behaviour, and source review has passed it with false claims about the source.
- The GPT-OSS envelope-prefix malformation is resolved
  ([Z_FIX05](Z_FIX05.md#b6-gpt-oss-envelope-prefix)).

Measure entity applicability as its own class in the baseline and in B2's labelling.
Don't narrow the entity-name exception without a decision.

### B7. Extraction collapses structured sources and weakens obligations

**Done.** Claims are a category and admission-bounded source lines whose wording the engine
quotes (ADR 0036, with Decision 6 dropping code delimiters around exact values), and list
sources yield one claim per top-level item (ADR 0038). Per-item chunking (ADR 0027) stays
withdrawn. The records are in [Z_FIX05](Z_FIX05.md#b7-original-record) and
[Z_FIX05](Z_FIX05.md#b7-records-2125-october-2026).

Open:

- **Weakened obligation, now at generation.** Claims carry the source's "must be able to
  renew" since ADR 0036, yet generation still writes "may renew": the brief, story and
  FR-001 in the first 26 October run, the story only in the second. Source review passed
  it each time. No keyword rule; measure it as a class in B2's labelling, then decide the
  owner.
- **Contract-review leftovers** (no observed outcome): stored readback doesn't re-quote
  claim text from its citations; admission admits a repeated citation ID; the extraction
  reason's text-repair route has unit coverage only; no synthetic current-schema exchange
  replaces the retained `compatible` one; `source_selections` naming was left out of scope.
- **Markdown in claim wording** reaches later calls. Backticks around exact values are
  removed at admission (Decision 6); other effects are unmeasured.
- **Decisions:** whether ADR 0036's "cites in full" includes a fenced block's blank first
  or last interior line (otherwise the token's bytes can fall outside the quote), and
  whether identical citation sets are a native duplicate.

### B9. Model output can run away

**Done.** Entity records are authored once per feature; no request carries an output
allowance below the model's documented maximum; and since ADR 0039 a runaway is re-sent
once with the identical request at the configured `temperatureRunawayRetry`, outside
`retry-limit`, and logged. A runaway on the re-send fails required work with
`RunawayRepeated` and ends advice incomplete (ADR 0040). The records are in
[Z_FIX05](Z_FIX05.md#b9-records) and
[Z_FIX05](Z_FIX05.md#b9-runaway-evidence-and-re-send-decision).

**Live effect.** One runaway in the four 26 October runs, on hello-world's `Hello, World!`
(call 21), was recovered by its re-send. Every completed source-review runaway so far
has been on an exact-value subject (`Renewal refused.`, `Loan renewed!`, `Hello, World!`).
One recovery is one sample: keep reporting each runaway, its re-send and what the re-send
returned.

Open:

- **Conflicting with user direction; recommend withdrawal.** Two earlier choices would cap
  output: a lower per-slot output allowance, and a per-family records cardinality bound.
  The user directed on 18 October that there be no output token limits and on 25–26
  October that limits must not discard useful output. Both stay open only until the user
  confirms their withdrawal.
- **Claude Haiku 5.5's deadline.** Its catalogue maximum is 128,000 tokens under an
  interim 180,000 ms deadline; measure it only if the user selects that model.

### B10. Failed and blocked runs publish nothing

**Decided 26 October 2026 ([ADR 0041](../design/decisions/0041-failed-run-incomplete-publication.md));
docs updated, implementation waiting on four decisions.** A Specify run that fails because
model work couldn't be completed, or ends `blocked`, should publish only its validated
content as an incomplete specification, marked in `spec.md` and `reference-context.md` and
logged as `run.incomplete_published`, while still ending `failed` or `blocked`.

A read-only design pass found that the commonest loan-renewal failures (exhausted
correction, `RepairNoProgress`, the token budget) are runner rejections that end the run
before any YAML edge, and that publication today requires `ok` or `needs_user`. The
decisions it needs:

1. **Mechanism:** a YAML-declared workflow-level `failure-output` subgraph, run by the
   engine through the runner after an eligible failure, with a model-free runner
   failure-output mode. It amends ADRs 0005, 0009 and 0030.
2. **Eligibility:** YAML `failed`, `blocked` and `invalid` terminals and the
   `retry_limit` and `token_budget` rejections; cancellation, authority, logging,
   capture, operational and deadline failures publish nothing.
3. **No final requirement IDs** in the incomplete view, as ADR 0017's view already does.
4. **`workflow/v2`** for the new definition member.

When implemented, two tests that assert a required repeated runaway publishes nothing must
flip, and `spec.md`'s reader needs a slot for the failure status line beside ADR 0040's.

### B11. Principle citations collapsed after ADR 0042's prompt line

ADR 0042 added "if no principle addresses the subject, it is compatible" to the principle
prompt, and the 25 October `uncertain` title verdict didn't recur. But citations on
`compatible` findings fell from 481 of 481 in 33 earlier principle-review responses to 17 of
76 in the four 26 October runs (three runs cited none). Loan-renewal's second run gave a
false reason, "No principle governs user-visible behavior descriptions", although the
supplied user-interface principle covers them.

**Decision:** reword the line so a verdict cites the principle text it rests on whenever
one applies, for example: "Cite the principle text behind every verdict. Use uncertain only
when a cited principle applies but compliance can't be decided; a subject no supplied
principle addresses is compatible, and only then without citations." It amends ADR 0042
Decision 4.

### B12. Renderer artefacts in published specifications

Deterministic and present in most runs: the acceptance-criterion clause join renders
"…\., **When**" (`specification_markdown.zig:40-44`), and exact values appear as quoted
code spans with an extra full stop. These are code defects at the renderer with no
contract change; they need only the user's go-ahead.

## 4. Spec workflow simplification

This section reviews [spec.workflow.yaml](../design/workflows/spec.workflow.yaml) at
`b2f10a3`. The workflow has 282 steps in 33 graphs. Of those, 157 (56%) only pass
`ok` to the next step and `failed` to the end. It has 18 model-request sites, 8 of
them repairs.

| Stage | Steps | Run-time cost in the measured runs |
| --- | ---: | --- |
| Deterministic preparation (toolchain, inputs, references) | 43 | No model calls; three subgraphs are fully linear |
| Extraction | 40 | One or two calls per chunk (classification is skipped when native code can classify it), plus text and selection repairs |
| Reconciliation | 54 | Four calls (summary, dispositions, signals and conflicts), even for a three-line source |
| Source-review gate and source-omission repair | 28 | See note below |
| Generation | 20 | Three calls plus one per source group |
| Review | 42 | 29 calls and about 77% of tokens |
| Publication and clarification | 30 | No model calls |
| Model-request plumbing | 25 | Runs on every call, plus 15 explicit release steps |

Note on the source-review row: the pre-generation review did not run in any measured
case. Both cases share a configuration with `sourcePreservationCheck: false`, and
otherwise it runs only when references aren't ready for generation. Its repair
subgraphs are shared with W1's post-generation path.

What already applies, and what to keep:

- A1 (request plumbing) and A2 (stage-level operations) apply here unchanged. A2
  covers the decision-free preparation and publication steps. Under ADR 0031, A2 covers
  the read-only parts of publication preparation, such as rendering and validation; the
  publication writes stay their own action.
- W1 and W4 reduce model calls; W2, W3 and W5 only reduce implementation effort.
- Keep typed outcomes, closed admission, all-or-nothing publication and
  clarification persistence as they are.

W1 and W2 are done; their records are in [Z_FIX05](Z_FIX05.md#w1-review-can-restart-the-whole-pipeline).

### W3. Eight repair routes repeat one shape

The eight repair request sites are:

- text repair;
- extraction repair;
- reconciliation repair;
- support repair;
- specification-unit repair;
- omission repair;
- source-extraction repair;
- source-reconciliation repair.

Each runs authorize, build input, request, parse, release and merge, which comes to
55 repair-related steps in all.

**Decided 22 October 2026 as generic repair operations; implementation not started.** As
first written, W3 put a model request inside one operation, which ADR 0030 and ADR 0031
both forbid. [ADR 0033](../design/decisions/0033-generic-repair-operations.md) restates it:
four generic operations, `authorize-repair`, `build-repair-input`, `parse-repair` and
`merge-repair`, replace the 29 per-owner ones. Each takes a closed `owner` enum, checked
against native facts, that selects no policy, scope or defect identity; owner rules stay
in owner modules. `request-model`, release and the advisory repair stops stay YAML steps,
and every repair boundary rule is unchanged. Today there are 29 per-owner operations
across 13 owners, and 7 repair model-call sites. The full record is in
[Z_FIX05](Z_FIX05.md#w3-decision-record).

Open:

- conversion, after ADR 0030 is implemented and ADR 0031's first conversion is measured,
  with all Specify owners in one change on offline equivalence evidence;
- the derived choices awaiting confirmation: the 13-owner list, the `owner` check,
  "compiled operation" meaning the step instance, the §22.1 reading, advisory stops
  outside the four operations, one Specify-only conversion, and offline evidence.

Owner-specialized contracts (derived choice 1) were confirmed on 23 October 2026: the 29
variants use the shared contract-variant mechanism that ADR 0030 builds first.

### W4. Reconciliation always makes four calls

Even hello-world's three-line source needs two extraction calls and four
reconciliation calls before any authoring starts (B5). Reconciliation is also the
largest stage, at 54 steps. The split into summary, dispositions, signals and
conflicts was deliberate
([ADR 0016](../design/decisions/0016-configured-json-response-composition.md)), so
collapsing it needs evidence.

**Proposal** (measure first): replay retained captures to test, for small and
single-source inputs, whether separate dispositions, signals and conflicts calls
change the claims, groups or conflicts compared with one combined call. Follow the §7
rules, and count extraction's requirement merging (B7) as its own class.

**Sequencing.** Since ADR 0030 slice 3 (24 October 2026) every catalogue entry requires
`requestTimeoutMs`, so tools that revalidate a retained catalogue, including the
`e2e-call` replay, can't read captures made before it. The user accepted landing slice 3
before W4 was measured. Measure W4 from raw response bytes or from captures made after
slice 3.

### W5. Identical sibling steps

Two pairs of steps have the same target, parameters and transitions:

- [`source-gaps`](../design/workflows/spec.workflow.yaml#L160) and
  [`candidate-gaps`](../design/workflows/spec.workflow.yaml#L167);
- [`finish-native`](../design/workflows/spec.workflow.yaml#L348) and
  [`finish-model`](../design/workflows/spec.workflow.yaml#L351).

**Proposal** (no ADR change): merge each pair. Other steps already join several paths,
for example `validate-dispositions`. The incoming paths here carry different data,
though, so first confirm that the workflow compiler's data-flow checking accepts
these two joins.

**Note (checked 26 October 2026).** Both pairs are still in the workflow. An ADR 0031
stage conversion may absorb them; check that before merging them separately.

## 5. Other carried open work

### R1. Group-level provenance precision

[Record binding](../src/domain/specification_source_binding.zig#L138) assigns a
complete accepted group, and [generation parsing](../src/domain/specification_generation.zig#L77)
attaches it to every returned record. Citations stay exact, but membership doesn't
mean each record expresses every linked claim. This follows ADR 0020 and is not a
defect.

**Decision:** first measure whether grouping and source review meet the intended
traceability claim. If record-specific support is required, approve one binding
change across generation, review, repair, omission insertion, readback and rendering.
Don't create a second provenance store or infer support from text matching.

**Partly settled 25 October 2026 ([ADR 0038](../design/decisions/0038-record-claims-and-scenario-coverage.md)):** non-entity records now name their supporting
claims within their one group, so citations and review evidence narrow to those claims.
Entities and narrative fields still bind whole groups.

### R2. Clarification answer recovery

**Confirmed implementation gap.** Fresh answers cannot complete the registered
recovery path:

- [Refresh](../src/domain/clarification_refresh.zig#L65) rejects new nonempty
  submissions with `AuthenticationRequired`.
- [Provenance](../src/domain/specification_provenance.zig#L84) rejects nonempty
  response-ID sets.
- Workflow preparation validates forms without authenticating answers, and the
  resolved-needs action constructs empty needs.
- Generation doesn't consume accepted answers.
- [Passive literal origins](../src/domain/passive_literals.zig#L16) are source-only.

Complete the [§17.4 lifecycle](../design/contracts/17-specify.md#174-specification-clarification-behavior):
authentication, response publication, current applicability, dependent invalidation,
response-owned literals, generation, review and readback.

**Decided 21 October 2026** in
[ADR 0025](../design/decisions/0025-clarification-answer-authentication.md), which
covers former FIX03 Phase 7 (7A decisions, 7B source-driven resolution, 7C fresh
answers):
- the account that runs the engine is the actor, and the run that reads valid closed
  forms accepts them;
- one invalid closed form stops the run, accepts no answers and reports a typed reason
  for each failing form;
- evidence goes in the shared actor-evidence registry;
- the scope is Specify only.

A closed form alone is not authentication, and answers never receive fabricated
reference citations.

Native [coverage](../src/domain/specification_coverage.zig#L45) cannot discover facts
that were never extracted. Keep ADR 0021's optional pre-generation source check, and
measure original-source omissions separately. Persistent semantic identity across
edits needs an explicit continuity contract, not line-number-derived IDs.

### R6. Semantic repair attribution and recovery

**Status.** Bound preservation comparisons were implemented under FIX01-01. All three
32-call comparisons failed the semantic gate; the best reached 16/16 admission and
14/16 correct attribution
([record](Z_FIX02.md#1-fix01-01--bound-preservation-comparisons-10-october-2026)). The
follow-ups ran as follows ([records](Z_FIX02.md#21-r6-follow-up-records-formerly-in-fix01)):

- explicit obligation (48 calls): failed;
- isolation (60 calls): failed;
- native-owned collections (72 calls): passed the diagnostic gates, as an admission
  gain rather than a judgment gain;
- citation completeness (76 calls): passed;
- actual source-review handoff (30 calls): failed.

**Remaining proposals.** Each needs a closed contract and coordinated tests. Re-scope
them under the approved B2 scope: post-generation semantic findings no longer drive
content repair.

1. **Source-authorized exact-reference repair eligibility** (former item 2).
   - Derive eligible choices from the target's current authorized assignment and
     omission evidence, through shared owners.
   - Preserve occurrence identity, old value, revision and dependencies.
   - Ambiguous same-text occurrences grant nothing.
   - This needs coordinated §22 and ADR 0020/0022 amendments. B3 would change it.
2. **Narrow correction of invalid loss evidence** (former item 3). The
   [support repair owner](../src/domain/specification_support_repair.zig#L94) rejects
   `invalid_loss`, and [`loss-collect`](../design/workflows/spec.workflow.yaml#L684)
   then ends the workflow `invalid`.
   - Correct malformed evidence while preserving the reviewed subject, the fixed
     omission and the current scope.
   - Use one selectable line catalogue.
   - Revalidate the corrected evidence before any content repair.
3. **Verdict reassessment** stays a separate, unapproved decision under
   [§22.1](../design/contracts/22-repair.md#221-definition-of-atomic). A proposal
   must state its trigger, current evidence, closed outcomes, one active finding, a
   stable allowance and disagreement handling. No voting or retry-until-positive.

Two recovery limits stay explicit:

- entity-applicability repair cannot change the entity decision;
- exact-reference repair cannot add an unselected claim because its text matches.

The outcome to prove is: defective description → established upstream preservation →
authorized description-only repair → impacted and full validation → continuation,
with unrelated upstream data unchanged. Genuine upstream losses must still reach the
correct producer.

[ADR 0033](../design/decisions/0033-generic-repair-operations.md) leaves R6's
exact-reference repair eligibility open and doesn't foreclose it.

### R7. Semantic reliability across models

Acceptance remains open. Explicit false `unsupported` decisions and wrong eligible
selections remain semantic errors. Automatic role reconsideration would need its own
trigger, target, invalidation and allowance contract.

The prepared but unexecuted comparisons are historical plans, not authorization:
record authoring (12 calls), signal grouping (12) and entity applicability (32)
([Z_FIX01 §9.12–§9.14](Z_FIX01.md#912-call-12-authoring-projection-and-loss-evidence-follow-up--9-october-2026)).
Verify their frozen inputs against the current candidate before proposing a run.

Broader evidence needs:

- initial, correction, repair and rebuild contexts;
- unrelated source families;
- optional and mandatory fields;
- supported paraphrases;
- negation, condition and modality changes;
- incomplete sources.

Score first-pass and recovered outcomes separately. Use repeated paired trials, with
labels kept outside prompts and separate development and held-out families. Since
22 October the live-test policy also permits Claude Haiku 5.5 for generation, through the
Anthropic API (ADR 0028) and Bedrock (ADR 0029), so cross-model generation evidence no
longer needs a scope change. From 23 to 24 October every E2E slot selected Claude Haiku 5.5
on Bedrock; the slots select GPT-OSS-20B again while the account lacks Haiku access. The
user decides when to change or compare models (25 October 2026). Each run still needs its
own approval.

### R8. Development acceptance policy

**Implemented offline; human adjudication and calibration open.** Only a human-written
`human-spec-adjudication/v2` record, applied with the offline `zig build adjudicate-spec`,
decides acceptance; a published run ends `human_adjudication_required`. The record is in
[Z_FIX05](Z_FIX05.md#r8-record).

Open:

- **Adjudication.** No published run has been adjudicated. The 26 October reports are
  `spec-e2e-report/v10` and can be adjudicated.
- **Retained v9 reports.** ADR 0039 advanced the report to v10, so this build can't
  adjudicate the 16 retained v9 runs, and several were made by uncommitted builds.
  **Decision:** accept that they stay unadjudicated (recommended, since they predate ADRs
  0038–0043), or adjudicate them on matching builds first.
- **Calibration.** The [Hello World panel](../test/integration/fixtures/wf-001-hello-world/node-vitest/calibration/REVIEW.md)
  (nine specimens) and the
  [loan-renewal panel](../test/integration/fixtures/wf-002-loan-renewal/calibration/REVIEW.md)
  (fifteen) have proposed labels only. Real human-review and judge-qualification records
  remain pending.

### Summary hierarchy and cross-model variation

Former FIX01 §9.20 recommendations 1–2 are implemented
([Z_FIX01 §9.20](Z_FIX01.md#920-completed-summary-recommendations-and-supporting-review--10-october-2026)),
but their live acceptance is open. Execute the
[prepared summary comparison](../test/calibration/summary-coverage/README.md) only
under fresh approval. Assess meaning preservation with source-preservation review
both enabled and disabled, plus retained statement growth and downstream cost.

Open proposals, with their original numbering:

3. Classify meaning defects separately from representation and source gaps, reusing
   §12.8.1 and §22.2. A grouping error must not become a user question.
4. Extend repair only for genuinely coupled defects. That needs typed coupling
   evidence, deterministic membership and a maximum scope; shared claim IDs alone
   don't prove inseparability. Reassess the full-survivor condition for
   redundant-projection deletion.
5. Make cross-model variation part of acceptance evidence. Offline, cover variation
   cases at every summary level. Live, run repeated comparisons measuring valid
   meaning rejected, unsupported meaning accepted, recovery, cost and completion.

Constraints (former FIX01 §1):

- Summary admission is not per-summary semantic review.
- Loss localization has no summary target
  ([`Location`](../src/domain/source_omission.zig#L8)).
- Allowing overlap can retain misleading paraphrases.
- Duplicate normalization needs conserved evidence, obligations and occurrence
  identity.
- Single-child carry-forward must read the current validated history.
- Don't replace the general repair owner.

Summary-hierarchy measurement (former FIX03 Phase 10) ranks below the review and
repair workload.

### Wider scope retained

- **Evaluator responsibility transfer.** [Judgment](../test/harness/judgment.zig#L14)
  accepts criterion IDs and quoted strings, then checks coverage and substring
  presence. Define the assignment and occurrence contract first.
- **Retained-memory and scale evidence.** Measure growing review sets, retained
  bytes, allocations, validation and teardown time, cancellation and OOM, and
  dependent rebuilding.
- **Harness acceptance (former design/harness tickets H-012, H-013, H-017).**
  Publication process-interruption evidence; production Specify feature-log
  integration; live negative-path evidence for malformed generation, real
  missing/conflicting authority, clarification, cancellation and judge failure;
  and rerun replacement covering shorter output with no trailing bytes,
  unsubmitted drafts, concurrent closes, no duplicate subject IDs and an unrelated
  workflow. Also open: an unchanged prior `spec.md` must not be labelled new output
  after a blocked rerun; compiler rejection of skipped gates and undeclared
  resources; packaged execution without a `design/` fallback; the H-017 live
  generation-plus-grading milestone with stale-artifact rejection; live evaluator
  demonstration (H-004/H-006); and the provider-compatibility diagnostic, whose
  frozen binding the shipped cases now satisfy, since no allowance remains (§11). H-011's answer
  authentication is R2 and H-002/H-016 calibration is R8. The ticket text remains
  in git at `8ed40ba`.
- **Direct Anthropic provider: implemented** as
  [ADR 0028](../design/decisions/0028-anthropic-messages-provider.md), with Bedrock model
  families in [ADR 0029](../design/decisions/0029-bedrock-model-families.md). Open:
  - ADR 0028 names a new F0009 feature document and a contract §12.3.2; neither exists.
  - ADR 0028's "Live use" still says the policy permits only GPT-OSS-20B; since
    22 October it also names `anthropic` / `claude-haiku-5-5` for generation.
  - Claude's response mode (native schema or prompt-only) stays open until compatibility
    is measured; no live Claude call has succeeded.
- Historical optional provider, reasoning-setting and principle-passage experiments
  are not current tasks.

### Follow-ups carried from completed records

- **Single and assignment schema selection** (§10). The single source-preservation path
  picks a schema definition, while assignments exclude a variant. The two definitions
  order `candidate_invalid` and `inconclusive` differently, and single findings drop the
  `negative` guidance rule in a projection-specific branch. Unifying them on one mechanism
  changes the workflow schema resource and retained request bindings, so it is a separate
  change.
- **Provider-stop visibility** (§11). `model.provider_stopped` is a warning-level event, so
  a configured `logs.level` of `error` or `fatal` filters it out.
- **Logging gaps** (§17, ADR 0026):
  - cancellation during segment reads and under the log lock is reported as a logging
    failure, which conflicts with keeping cancelled distinct from failed;
  - the lock action reports every acquire failure as a timeout;
  - prior-run crash finalization (§14.10) needs a persisted bootstrap authority that
    doesn't exist, so a crashed run's logs are kept until it is decided;
  - §26 and F0002 name the compiler-owned `redaction/default-v1` policy, but no code or
    persisted record carries that ID.

## 6. Recommended order

Earlier sequences are in [Z_FIX05 §6](Z_FIX05.md#6-recommended-order-as-of-22-october-2026)
and [Z_FIX05](Z_FIX05.md#6-recommended-order-as-of-26-october-2026). Under ADR 0034, Spec
quality is the critical path, and Plan starts only when the user declares the gate passed.
Accuracy comes first; token cost is never a reason to drop a check, and spending that buys
no quality is removed at its owner. Nothing below authorizes a live call; each E2E run
needs its own approval.

1. **Adjudicate (R8).** No run counts toward the gate until a human adjudicates one. The
   26 October v10 reports can be adjudicated; decide what happens to the retained v9 runs.
2. **Decide and implement the 26 October Spec follow-ups**, each with `/preflight`:
   - B11, the principle prompt rewording;
   - B5, business-rule guidance;
   - B12, the renderer artefacts;
   - B10, ADR 0041, once its four mechanism decisions are made.
3. **Measure on a committed build.** Repeat both cases on one committed, unmodified build,
   counting every attempt and reporting runaways, re-sends and incomplete reviews
   separately (§7). One pair has run on `39a06ea`. Use `/evaluate-e2e` for advisory defect
   origins.
4. **Measure review accuracy (B2)** by offline labelling before any change that lets review
   alter output; label B7's obligation weakening and B6's entity applicability as their
   own classes.
5. **Model choice is the user's decision (R7).** All live evidence comes from GPT-OSS-20B.
6. **Close the remaining Spec decisions:** B4's experiment stops and qualified scope before
   any baseline freeze; withdrawing B9's two conflicting choices; B7's fenced-block and
   duplicate-citation questions.
7. **Architecture, in ADR order and independent of 1–6.** ADR 0030 slice 4 (A1), which
   absorbs ADR 0039's re-send steps, before adding operations for another workflow; then
   `prepare-toolchain` (ADR 0031) with its measure, startup (ADR 0032) and repairs
   (ADR 0033). Fold A4's closed reasons and A5's rule style into each conversion, and check
   whether a conversion absorbs W5's pairs.
8. **Separate work.** R2 (ADR 0025) is a required feature that hasn't started. Decide R1
   before promising stronger provenance. Freeze the Phase 2 baseline only after B4's
   decision. Gather R6 evidence after B2's labelling.

## 7. Acceptance and evidence rules

Keep these evidence statements separate: **implementation complete**, **mechanical
checks passed**, **semantic benefit demonstrated**, **brittleness reduced** and
**scope qualified**. More passing tests, fewer calls or higher schema admission alone
close none of the semantic gates.

Rules for every contract change (former FIX04 §1.1):

- Decide on at least two unrelated development cases, with replayed repetitions. A
  single run cannot decide a change.
- Never tune on the sixteen reserved qualification features.
- A model limitation under a coherent contract is a valid result. Don't answer it
  with field-, case- or model-specific rules, sampling changes, extra retries, a
  second model or a weaker admission rule. The development grader's single
  mechanical correction ([Z_FIX05 §15](Z_FIX05.md#15-grader-one-shot-correction--18-october-2026),
  user decision of 18 October 2026) is an explicit
  exception for the harness, not engine policy. The one engine exception is ADR 0039's
  runaway re-send (user decision of 26 October 2026): an `output_limit` stop is re-sent
  once at the configured `temperatureRunawayRetry`. It covers no other failure.
- Budget-stopped, malformed and exhausted runs stay in the attempted-workload
  denominator.

The [evaluation protocol](../test/calibration/semantic-simplicity/README.md) owns
case partitions, scoring, the numeric gates and the experiment stops. Three further
measures, not yet in it, apply to full-workflow runs:

| Measure | Definition |
| --- | --- |
| Finding-type accuracy | Share of review findings whose type matches a frozen, source-based label for the assessed field. Report precision per predicted type and recall per labelled type, at original and final assessment. A real defect reported with the wrong type is a harmful diagnosis. |
| Stage resource share | Sends and actual tokens per stage (extraction and reconciliation, generation, review, repair) per attempted workload, including budget-stopped runs. |
| Admission escape | Share of attempted workloads in which a value violating a declared native rule reached review or publication, with the sends and tokens spent downstream of it. This is mechanical evidence, not semantic quality. |

Boundary gates carried from former FIX01 §5:

| Boundary | Required positive evidence | Required negative evidence |
| --- | --- | --- |
| Summary representation | Combined, split and overlapping expressions; complete membership; stable identities and evidence | Missing or foreign IDs, altered categories, false support, changed exact values, conflicting interpretations |
| Normalization | Idempotence; same-evidence duplicates collapse; raw and provenance retained | Same text from different occurrences, distinct obligations, non-equivalent paraphrases, destructive truncation |
| Native carry-forward | Empty, non-final, final and one/many-child routing; identical current child and evidence; complete lineage | Stale or forged child content, changed evidence, token duplication, fabricated origin, skipped final semantic work |
| Repair | Exact target and dependencies, protected siblings, progress, full final validation | Stale authorization, widened scope, reset allowance, invalid survivor, unsupported verdict change |
| Loss attribution | Bound comparisons locate candidate-only and genuine upstream loss; dependencies and evidence retained | Missing or duplicate assignments, contradictory outcomes, uncertain owners treated as certain, lost source-only omissions, false upstream rebuilding |
| Exact-value representation | Occurrences recorded from exact bytes in bound fields; identity survives repair and readback | False matches, ambiguous occurrences, unbound fields, changed obligations |
| Loss-evidence correction | The narrow correction preserves subject, finding and scope; native validation reruns before repair | Nonexistent lines, stale producers, verdict replacement, budget or attempt reset, repeated defect |
| Cross-model behaviour | Paired repeated trials in unrelated domains; all declared outcomes and costs | Meaning changed despite valid JSON and IDs; false rejection, unsupported acceptance, inconclusive or unusable results |
| Whole workflow | Real publication, complete required review and separately approved rubric evaluation | An early stop reported honestly; no golden outputs, fabricated E2E success or offline substitute |

Offline unit and integration tests verify native mechanics. Live comparisons with
reviewed labels assess changed meaning. Run `zig build verify` and the clean
packaging checks when implementation boundaries change. Each live diagnostic needs
bounded approval, and each E2E run needs its own explicit approval
([live harness](../design/harness/e2e.md)).

## 8. Record history

- **17–22 October 2026:** see [Z_FIX05 §8](Z_FIX05.md#8-record-history-to-22-october-2026).
- **23–25 October 2026:** see [Z_FIX05](Z_FIX05.md#8-record-history-2325-october-2026).
- **26 October 2026, decisions:** the user decided ADR 0039 (configured `temperature` and
  `temperatureRunawayRetry`; one re-send after a runaway, logged; every retry response
  passes the same checks), ADR 0040 (incomplete review published, marked and logged),
  ADR 0041 (failed and blocked runs publish their validated content, marked and logged),
  ADR 0042 (principle verdicts need citations at admission; the prompt defines
  `uncertain`) and ADR 0043 (model-facing `exact_text` names). CLAUDE.md and §7 record the
  re-send as the one engine exception to the rule against sampling changes and extra
  retries.
- **26 October 2026, implementation:** ADRs 0039, 0042, 0040 and 0043 implemented in that
  order, then a contract review's two major and four minor findings fixed (a false
  missing-final-text log on a first runaway, exact-value harness measurement, a compiler
  rule for the re-send route, full re-send identity, logging only an actual re-send,
  harness temperatures). `zig build verify`: 164 of 164 steps, 1,968 of 1,968 tests.
  Committed as `39a06ea` and merged as PR #10. ADR 0041 awaits its decisions (B10).
  [Z_FIX05 §20](Z_FIX05.md#20-adrs-00390043-and-live-runs--26-october-2026) holds the
  record.
- **26 October 2026, live runs:** two attempts denied by an expired Bedrock key, then two
  published pairs (§1).
- **26 October 2026, record review:** by user direction, completed work moved to Z_FIX05
  §§19–20 (the 25 October state and runs, A1's settled choices and slices 1–3, B4's
  configured budget, B5's and B7's records, B9's runaway evidence and decision, the
  23–26 October §6 sequence and the 23–25 October history). The open items were checked
  for relevance and alignment: B10–B12 are new; B9's lower output allowance and
  cardinality bound are flagged as conflicting with the user's no-limits direction; B2's
  separate assessment model is recorded as the user's model choice.
