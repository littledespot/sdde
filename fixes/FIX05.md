# FIX05 — Architecture review and consolidated open work

**Reviewed:** 17 October 2026, Australia/Melbourne, at `b2f10a3`. **Updated:** 23 October
2026.

**Status:** sole active fix record. It holds open work only: unimplemented decisions, open
proposals and the evidence rules. Completed implementation, dated live diagnostics and the
full decision records moved to [Z_FIX05](Z_FIX05.md) on 23 October 2026, under their
original IDs. Earlier completed work is in [Z_FIX01](Z_FIX01.md) and [Z_FIX02](Z_FIX02.md).
FIX05 consolidated the open work of FIX01 (Spec reliability backlog) and FIX04
(semantic-simplicity evaluation), which are deleted. Their last text is at `b2f10a3`
(`git show b2f10a3:fixes/FIX01.md`, `git show b2f10a3:fixes/FIX04.md`). Former item IDs
(FIX01 R1–R11, FIX04 F1–F13 and Phases 0–6) are kept for traceability.

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

### Current state — 23 October 2026

**Done and moved to Z_FIX05.** These are implemented and verified offline. Their live
semantic benefit is not demonstrated (§7).

| Item | State | Record |
| --- | --- | --- |
| B2 | Advisory post-generation review (ADR 0023) and one record family per source-review call; live effect open (B2 below) | [B2 records](Z_FIX05.md#b2-records) |
| B3 | Native exact-value recognition; mechanical live gate closed 17 October | [B3](Z_FIX05.md#b3-exact-value-bookkeeping-is-left-to-the-model) |
| B4 | Option 3 and the single 100,000-token budget; budget and scope decision open (B4 below) | [B4 records](Z_FIX05.md#b4-records), §9 |
| B5 | No record batch for token-only groups (ADR 0024); A/C comparison open (B5 below) | [B5 token-only batches](Z_FIX05.md#b5-token-only-record-batches) |
| B6 | GPT-OSS envelope prefix normalized; entity applicability open (B6 below) | [B6 envelope prefix](Z_FIX05.md#b6-gpt-oss-envelope-prefix), §12 |
| B7 | List-item extraction tried and reverted on 21 October; obligation weakening open (B7 below) | [B7 original record](Z_FIX05.md#b7-original-record) |
| B8 | Native preserved-token bookkeeping (ADR 0024) | [B8](Z_FIX05.md#b8-the-model-classifies-and-disposes-exact-value-tokens) |
| B9 | Feature-owned entity records and no output allowance; runaway class open (B9 below) | [B9 records](Z_FIX05.md#b9-records), §§9, 11, 16 |
| W1, W2 | No post-generation upstream rebuild; the duplicate path is deleted | [W1](Z_FIX05.md#w1-review-can-restart-the-whole-pipeline), [W2](Z_FIX05.md#w2-the-upstream-repair-path-exists-twice) |
| R8 | Acceptance policy implemented offline; adjudication and calibration open (R8 below) | [R8 record](Z_FIX05.md#r8-record), §17 |
| §§9–17 | Implementation records, 17–21 October | [Z_FIX05](Z_FIX05.md#9-b4b9-implementation--17-october-2026) |

Section references §9–§17 point to Z_FIX05.

**Live runs, 21–22 October 2026 (AEDT).** Every run used GPT-OSS-20B on Bedrock, ran once
and was separately approved. Advisory scores are `/evaluate-e2e` analysis under
`evaluations/`, not grades or acceptance.

| Run | Build | Calls / tokens | Outcome |
| --- | --- | --- | --- |
| [Hello-world](../zig-out/e2e-spec/2026-10-20T21-16-50Z-e36938ea061e468db9f9b2c6c5efc94c/report.json), 21 Oct 08:16 | `7a88804` | 25 / 65,896 | Published; advisory 89.29% |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-20T21-29-05Z-984a39676411cca90510cd014f625a4f/report.json), 21 Oct 08:29 | `7a88804` | 25 / 76,501 | Published; advisory 78.57%, below threshold |
| [Hello-world](../zig-out/e2e-spec/2026-10-21T00-38-18Z-b39db999214e70a1e97993ec1f3a5d00/report.json), 21 Oct 11:38 | `2bf5ca6` (B7), modified | 27 / 75,669 | Published; advisory 89.29% |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-21T00-45-18Z-3d0adef9037fc6708573f4b4bf2d3a34/report.json), 21 Oct 11:45 | `2bf5ca6` (B7), modified | 27 / 100,793 | `WorkflowTokenBudgetExceeded` in source review |
| [Hello-world](../zig-out/e2e-spec/2026-10-21T00-55-40Z-871ef5835db845f998a02fa87553dfed/report.json), 21 Oct 11:55 | `2bf5ca6` (B7), modified | 30 / 86,111 | Published; advisory 60.71%, with critical failures |
| [Hello-world](../zig-out/e2e-spec/2026-10-21T07-17-06Z-cbd566225c37b59539b17e81b88d7052/report.json), 21 Oct 18:17 | `2bf5ca6` (B7), modified | 19 / 35,869 | Failed: source-review `timeout` at 60 s (B9) |
| [Hello-world](../zig-out/e2e-spec/2026-10-21T07-40-30Z-35c394a473ad918f326a57351bb1b25a/report.json), 21 Oct 18:40 | `527f870` (B7 reverted), modified | 25 / 67,485 | Published; advisory 89.29% |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-21T07-45-38Z-1bde6e1800ab1c0ef972767b4101a3e9/report.json), 21 Oct 18:45 | `527f870`, modified | 24 / 63,190 | Failed: source-review `timeout` at 60 s (B9) |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-21T07-52-36Z-d390b591aa68651da4e0bf27d99b51ed/report.json), 21 Oct 18:52 | `527f870`, modified | 22 / 56,571 | Failed: source-review `timeout` at 60 s (B9) |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-21T08-13-29Z-c349baea793fb60355880e989bb740d6/report.json), 21 Oct 19:13 | `527f870`, 180 s deadline, modified | 25 / 92,825 | Published; advisory 82.14%; one review call ended `output_limit` (B9) |
| [Hello-world](../zig-out/e2e-spec/2026-10-21T21-30-07Z-73f19805794c3c63535e6c175ec0c103/report.json), 22 Oct 08:30 | `fee2f39`, modified | 24 / 63,918 | Published; not evaluated |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-21T21-31-00Z-aee04c3ee1ac6e061551be002d987027/report.json), 22 Oct 08:31 | `fee2f39`, modified | 32 / 100,763 | `WorkflowTokenBudgetExceeded` in principle review |

- **Completion.** Hello-world published in 5 of 6 attempts and loan-renewal in 2 of 6.
  All twelve reports are `spec-e2e-report/v9`, so the published ones can be adjudicated,
  but none has been. No run counts toward the [ADR 0034](../design/decisions/0034-spec-quality-gate.md)
  gate yet, and none ran on an unmodified committed build.
- **Content.** Loan-renewal's published output still weakens "must be able to renew" to
  "may renew" and has no refusal acceptance criterion (B7).
- **Budget.** Loan-renewal ran out of the 100,000-token budget in review in 2 of its 6
  attempts (B4).
- **Runaway output** caused all three timeouts; the 180 s deadline made it visible (B9).

**Providers.** [ADR 0028](../design/decisions/0028-anthropic-messages-provider.md)
(21 October) added the Anthropic Messages API provider on shared provider owners.
[ADR 0029](../design/decisions/0029-bedrock-model-families.md) (22 October) lets a Bedrock
catalogue entry name any model with a compiled family. The E2E catalogue lists Claude
Haiku 5.5 through both, and the live-test policy permits it for generation. Every E2E slot
still selects GPT-OSS-20B, and no live Claude call has been made. All live evidence in
this record therefore comes from one model, and which failure classes are model
limitations is unmeasured (R7).

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

**Decided 22 October 2026; implementation not started.**
[ADR 0030](../design/decisions/0030-engine-owned-model-request.md) replaces the request
subgraph with one `request-model` step per model request and one `count-model-tokens` step
per count. A fixed, capability-free kernel orchestrator runs the lifecycle through
runner-owned child bindings. Consumers, release, advisory routing, `retain-json-part` and
ledger initialization stay in YAML. The full record is in
[Z_FIX05](Z_FIX05.md#a1-decision-record).

Open:

- implementation, with ADR 0030's offline acceptance;
- the derived choices awaiting confirmation: the kernel-orchestrator form, including token
  counting, keeping `timeout-ms` as a step parameter, and keeping release and advisory
  routing in YAML;
- whether the engine should also take over release, and whether non-advisory request steps
  could omit their advisory mappings.

A1 is not expected to change model calls, tokens or reliability. Its estimated net YAML
saving is 35–90 lines (3–8%); the larger gains are no body copy per future workflow and
lifecycle changes confined to the engine.

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
- the derived choices awaiting confirmation: read-only stages, the absorption rule,
  ADR 0030's kernel form for model requests, the scope left to A3, `prepare-toolchain`
  first, offline evidence for structural conversions, and the contract-field and
  model-output limits. The restated W3, also derived here, was decided as ADR 0033.

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

**Status on 23 October.** The gate isn't met: no run has been adjudicated, no recent run
used an unmodified committed build, and loan-renewal published in 2 of its 6 attempts
since 21 October (§1).

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

**Still open:**

- **Live effect.** Review still ends loan-renewal runs on budget (B4). No run has measured
  the record-family change's net cost, and finding-type accuracy (§7) has no labelled live
  measurement.
- **Separate assessment model** (the original decision's option 3, not approved): assign
  review to a separately configured `models.slots.assessment` (former FIX02 and FIX03
  Phase 9). This needs the proposed ADR 0021 and configuration amendment. The 22 October
  live-test policy permits Claude Haiku 5.5 for generation only.

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

**Done.** Option 3 (one principle assignment per complete principle set) and the single
100,000-token workflow budget are implemented. Option 1, a separate advisory allowance,
was withdrawn: there is one total limit. Records are in
[Z_FIX05](Z_FIX05.md#b4-records) and §9.

Input is 93% of tokens. Review sends average about 2,500 input tokens for
single-field subjects. The four response schemas are 11.9–14.1 KB each, with 15–32
definitions.

The 100,000-token budget is compiled into every policy profile
([core](../src/composition/core_workflow_operations.zig#L35),
[native](../src/composition/native_workflow_operations.zig#L638)); it is not case
configuration. The protocol's experiment-wide stops of 1,000 sends and 2,000,000
tokens cover fewer than 20 such workflows, against 144 development workloads. The
Phase 2 budget-feasibility report is `insufficient`.

**Decision** (required before any baseline freeze): choose the budget and scope. The
options are:

- raise the workflow budget, or make it a workflow or configuration parameter,
  through an explicit engine contract change;
- revise the experiment stops before freezing, with a recorded rationale;
- reduce review or repair cost through its owner (B2);
- narrow the qualified scope.

The former recommendation was generation-only diagnostic scope for Phases 2–3, with
controlled predecessors, deferring complete-workflow qualification until review
qualifies. Separately, measure the prompt, schema and evidence token contributions
per call before trimming anything. Add no local size ceilings (ADR 0011).

**Evidence since 21 October.** Loan-renewal ended `WorkflowTokenBudgetExceeded` in review
at 21 October 11:45 (100,793 tokens) and 22 October 08:31 (100,763), and published at
76,501 and 92,825 tokens (§1). Raising the budget doesn't fix reliability.

### B5. Authoring follows mechanical source groups

Evidence from former F1, F9 and F13:

- Each record batch re-authors the whole feature, which produced competing or
  duplicate records in four runs.
- The group holding only a preserved value gets its own batch.
- One assignment can still require interpreting obligations, choosing record
  families, preserving conditions, building scenarios and entities, and deciding
  whether uncertainty blocks drafting.
- Six model requests precede authoring even on a three-line source.

**Done.** Token-only groups no longer get a record batch (approved 17 October with B8,
under [ADR 0024](../design/decisions/0024-native-exact-token-authority.md)). The record is
in [Z_FIX05](Z_FIX05.md#b5-token-only-record-batches).

**Proposal:** compare current per-group records (A) with one complete record
collection (C). Add a purpose-only acceptance-criterion diagnostic (B) or per-family
collections (D) only where measured failures justify them. Run it after B2 and B3,
which change every arm and dominate cost.

| Former phase | Status |
| --- | --- |
| 0 Evaluation protocol | Complete offline: [protocol, cases, specimens and scoring](../test/calibration/semantic-simplicity/README.md) |
| 1 Compatible execution | Live gate passed for the observed first request only ([record](Z_FIX02.md#phase-1-implementation-and-live-gate)) |
| 2 Baseline | [Harness](../test/harness/baseline/cli.zig) implemented; not frozen; needs B4's decision and a committed build (B3's gate closed on 17 October) |
| 3–6 A/C comparison, implementation, qualification, adoption | Not started |

Constraints carried from former F1–F8 and FIX04 §§4–5:

- Historical same-model panels ran under superseded contracts. They identify failure
  classes, not today's defect rate, so capture a fresh baseline on a frozen committed
  revision.
- Separate an oracle-premise capability test from a production handoff test.
  Evaluation expectations never enter generator inputs.
- Batching findings into one call, narrowing the semantic question and removing a
  required finding are different changes. Only the last changes authority.
- C needs disclosed, validated per-record support selection. Never bind every record
  to every group or discard lineage to make it pass.
- If C or D is selected, the production contract must define finite native
  assignments, complete content units, explicit supporting groups, exact assembly
  with origins, currentness and bounded correction, and it must keep every
  completion gate.
  - Generation parsing, session admission, provenance and readback, omission
    comparison and insertion, and entity ownership change together.
  - Replace superseded readers rather than keeping compatibility.
- If the baseline already meets the protocol's adequacy targets, retain it and stop
  the redesign.

### B6. Secondary failure classes to measure

- Before B3, entity applicability was marked required for a feature with no business
  data, and the entity-name exception then admitted an insertion-only name. No native
  rule can judge applicability. Both B3 baselines judged it correctly:
  `not_applicable` for hello-world and `required` for loan-renewal.
  Later hello-world publications judged it `required` and invented an entity
  ("Application Start" on 17 October 18:40, "Greeting" on 18 October).
- The GPT-OSS envelope-prefix malformation is resolved by native normalization of the
  truncated member-name form (18 October, §12).

Measure each as its own class in the baseline. Don't widen the normalizer or narrow
the entity-name exception without a decision.

### B7. Extraction collapses structured sources and weakens obligations

Evidence from GPT-OSS-20B runs, 17–21 October:

- **Collapsed lists.** Both sources are Markdown bullet lists of distinct requirements:
  three items in hello-world and five in loan-renewal. Through 20 October, extraction
  returned one claim for each whole list in every sample.
- **Weakened obligation.** Loan-renewal's claim turns "A borrower must be able to renew"
  into "may renew". It happened in at least five loan-renewal runs from 17 to
  21 October, and review judged the weakened text `supported` each time it was reviewed.
  On 21 October at 19:13 it appeared at extraction call 1 and review call 12 accepted it,
  and the published specification had no refusal acceptance criterion. The 18 October
  10:44 publication preserved the obligation.
- **Downstream effect.** With one behavioural claim per feature, every record cites the
  same claim, coverage is satisfied by any record that mentions it, and native checks
  cannot tell distinct duties from paraphrases.

**Tried and reverted — 21 October 2026.** On the user's instruction "implement B7",
`2bf5ca6` extracted each top-level Markdown list item as its own chunk, under ADR 0027
(`git show 2bf5ca6:design/decisions/0027-list-item-extraction-chunks.md`). Extraction
then returned one verbatim claim per item, but the outcome didn't improve:

- hello-world at 11:38 scored the same advisory 89.29% at 75,669 tokens, against 65,896
  before;
- loan-renewal at 11:45 ran out of budget at 100,793 tokens, against a 76,501-token
  publication before;
- on the same build, a later hello-world run scored 60.71% with critical failures, and
  another failed on a 60 s timeout (B9).

The user then directed "Revert B7, then do a live run". `527f870` reverted it, deleted
ADR 0027 and restored `source_blocks_v1` chunking and `specification-state/v19`. Its
message records the reason: the remaining defects come from generation, which already
received each item as its own requirement and which B7 does not change.

**Status.** List-item segmentation is withdrawn by that revert. One pair cannot decide a
contract change under §7, so the revert is a user decision, not evidence that
segmentation can't help. The obligation-weakening class stays open: extraction changes
modality, and review accepts the change. No proposal currently addresses it. Measure
whether it recurs with another permitted model (R7) before proposing an owner. The
original record is in [Z_FIX05](Z_FIX05.md#b7-original-record).

### B9. Model output can run away

**Done.** Approved on 17 October: entity records are authored once per feature with the
applicability decision, and non-entity batches can't emit them. Required `output_limit`
stays a typed failure; advisory `output_limit` closes that advice as incomplete (B4). The
2,048-token output allowance was withdrawn on 18 October, and each request now sends its
catalogue model's documented maximum (16,384 tokens for GPT-OSS-20B; ADR 0011 "Model
maximum output"). Records are in [Z_FIX05](Z_FIX05.md#b9-records), §9, §11 and §16.

Evidence of runaways under schema-constrained decoding at temperature 0.1 (GPT-OSS-20B):

- **17 October.** One record batch wrote 286 mostly invented entity records until the
  output limit. A source-review call broke its JSON close, then emitted about 48,500
  characters of blank lines.
- **18 October 10:44.** A source-review call stopped at Bedrock's then-default 4,096-token
  cap after a whitespace runaway.
- **21 October, 60 s deadline.** Three runs failed on a source-review `timeout` (18:17
  hello-world, 18:45 and 18:52 loan-renewal). A non-streaming response arrives only after
  generation ends, and a 16,384-token response takes about 37–74 s, so the deadline hid
  the cause.
- **21 October, 180 s deadline.** The user raised the request deadline to 180 s
  (`timeout-ms: 180000` in [spec.workflow.yaml](../design/workflows/spec.workflow.yaml#L1046),
  committed in `9719dc7`). In the 19:13 loan-renewal run, call 24 wrote a valid `supported`
  finding for `Renewal refused.`, then about 40,000 newline and space characters until the
  16,384-token limit, in 74.1 s. The engine recorded `output_limit`, closed that advice as
  incomplete and published. The call cost 19,402 tokens (21% of the budget). The same
  subject was under review when both earlier loan-renewal runs that day timed out, which
  suggests, speculatively, a subject-linked trigger.
- `/evaluate-e2e` found the whitespace pattern on 6 of about 700 retained calls, mostly in
  source review. That count is advisory analysis.

**Still open.** Each choice needs a decision. Don't answer the runaway with sampling
changes or extra retries (§7).

- **Deadline and maximum output.** The 180 s deadline covers GPT-OSS-20B's 16,384-token
  maximum. The catalogue's Claude Haiku 5.5 entries declare 128,000. If a slot selects
  that model, a runaway could again end as an unexplained `timeout`, and one completed
  runaway would exceed the 100,000-token budget. ADR 0028 leaves Claude's deadline
  undecided until latency is measured, and ADR 0029 leaves per-family deadlines
  undecided.
- **Lower output allowance.** ADR 0011 permits an optional per-slot `maxOutputTokens`. On
  18 October the user directed that there be no output token limits (§11), so this needs a
  new decision.
- **Bounded correction.** Decide whether a provider `output_limit` gets one bounded
  correction through the existing protocol-retry owner. §7 discourages extra retries, so
  this needs an explicit rule, not a local exception.
- **Cardinality bound.** Decide whether the closed records schema should bound per-family
  cardinality. It must not become a disguised size ceiling under ADR 0011.

Replay the runaway requests with repetitions to measure the rate before deciding.
Hello-world has no entities, so §7 also needs a second case that does.

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
- the derived choices awaiting confirmation: owner-specialized contracts, the 13-owner
  list, the `owner` check, "compiled operation" meaning the step instance, the §22.1
  reading, advisory stops outside the four operations, one Specify-only conversion, and
  offline evidence.

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

**Sequencing.** [ADR 0030](../design/decisions/0030-engine-owned-model-request.md) notes
that if it advances a capture or event contract, captures made before it can't be read by
the new build. Measure W4 before A1 lands, or from raw response bytes.

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

**Note (23 October 2026).** Both pairs are still in the workflow. An ADR 0031 stage
conversion may absorb them; check that before merging them separately.

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
Don't create a second provenance store or infer support from text matching. B5's
collection authoring would change the same binding.

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
longer needs a scope change. Every E2E slot still selects GPT-OSS-20B, and each run still
needs its own approval.

### R8. Development acceptance policy

**Implemented offline; human calibration review pending by user decision.**
[R8 development acceptance](../design/harness/acceptance.md) defines the shared quality
and critical gate and the per-case terminal outcome. Since 19 October the advisory grader
is removed from E2E (§17): a published run ends `human_adjudication_required`, and only a
human-written `human-spec-adjudication/v2` record, applied with the offline
`zig build adjudicate-spec`, decides acceptance. The record is in
[Z_FIX05](Z_FIX05.md#r8-record).

Open:

- **Adjudication.** No published run has been adjudicated. The 21–22 October reports are
  `spec-e2e-report/v9`, which the adjudicator reads; reports up to v8 can't be
  adjudicated.
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
  families in [ADR 0029](../design/decisions/0029-bedrock-model-families.md).
  [claude_connector.md](claude_connector.md) is now a historical source document. Open:
  - ADR 0028 names a new F0009 feature document and a contract §12.3.2, and neither
    exists yet.
  - ADR 0029 ("Live-test cost policy") says the shipped E2E cases select Claude Haiku 5.5
    with low effort in every slot. The configuration both cases use,
    [.sddtoolkit.json](../test/e2e/wf-001-hello-world/.sddtoolkit.json), selects
    GPT-OSS-20B in every slot. Either the configuration or the ADR text needs to change.
  - ADR 0028's "Live use" still says the policy permits only GPT-OSS-20B; since
    22 October it also names `anthropic` / `claude-haiku-5-5` for generation.
  - ADR 0028 leaves Claude's response mode (native schema or prompt-only) open until
    compatibility is measured. No live Claude call or compatibility probe has been made.
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

The 17–22 October sequence and its completed steps are in
[Z_FIX05 §6](Z_FIX05.md#6-recommended-order-as-of-22-october-2026). Under ADR 0034, Spec
quality is the critical path, and Plan starts only when the user declares the gate
passed. Nothing below authorizes a live call; each E2E run needs its own approval.

1. **Adjudicate.** No run counts toward the gate until a human adjudicates a published v9
   report under R8.
2. **Measure on a committed build.** Repeat both cases on one committed, unmodified build,
   counting every attempt (§7). Every 21–22 October run used a modified build. Use
   `/evaluate-e2e` for advisory defect origins.
3. **Separate model limitations from engine defects (R7).** All live evidence comes from
   GPT-OSS-20B. A paired comparison with a second permitted model would show whether B7's
   obligation weakening, B9's runaways and B6's entity invention recur. Settle B9's
   deadline point before selecting Claude Haiku 5.5.
4. **Then decide the open Spec failure classes:** B7's obligation weakening, B9's open
   choices, B2's review cost and finding-type accuracy, and B4's budget and scope.
5. **Architecture, in ADR order and independent of 1–4.** Implement ADR 0030 (A1) before
   adding operations for another workflow; if it advances a capture contract, measure W4
   first. Convert `prepare-toolchain` (ADR 0031) and record its measure, convert startup
   (ADR 0032), then convert repairs (ADR 0033). Fold A4's closed reasons and A5's rule
   style into each conversion, and check whether a conversion absorbs W5's pairs.
6. **Separate work.** R2 (ADR 0025) is a required feature that hasn't started. Decide R1
   before promising stronger provenance. Freeze the Phase 2 baseline only after B4's
   budget and scope decision, and run B5's A/C comparison only if generation-boundary
   failures remain. Gather R6 evidence after B2's live effect is measured.

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
  exception for the harness, not engine policy.
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
- **23 October 2026, completed work moved:** the user directed updating this record and
  moving completed items to Z_FIX05.
  - Moved: §1's dated diagnostics; the A1–A3, A6 and W3 decision records; B2's completed
    records; B3; B4's completed records; B5's token-only change; B6's prefix resolution;
    B7's original record; B8; B9's completed records; W1; W2; R8's record; the 17–22
    October §6 sequence; the §8 history; and §§9–17.
  - Recorded: B7's trial and revert; ADRs 0028 and 0029; the 21 October deadline change
    and runaway evidence; R7's policy change; the 21–22 October runs; the follow-ups
    carried from §§10, 11 and 17.
  - Rewrote §6.
  - Elsewhere: added the design.md §32 rows for ADRs 0028 and 0029, pointed the B3
    links in two calibration READMEs and Z_FIX02 to Z_FIX05, and updated
    `fixes/README.md`, the fix-records rule and `.claude/known-work.md`.
