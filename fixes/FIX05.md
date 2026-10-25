# FIX05 — Architecture review and consolidated open work

**Reviewed:** 17 October 2026, Australia/Melbourne, at `b2f10a3`. **Updated:** 25 October
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
| B4 | Option 3 and the single workflow budget. Implemented 25 October, uncommitted: the budget is `.sddtoolkit.json`'s required `workflowTokenBudget`, 125,000 for E2E (ADR 0037). Open: experiment stops and qualified scope (B4 below) | [B4 records](Z_FIX05.md#b4-records), §9 |
| B5 | No record batch for token-only groups (ADR 0024). Implemented 25 October: cross-kind restatement in the native duplicate rule (ADR 0035). Proposed: one complete record collection with native acceptance-criterion coverage (B5 below) | [B5 token-only batches](Z_FIX05.md#b5-token-only-record-batches) |
| B6 | GPT-OSS envelope prefix normalized; entity applicability open (B6 below) | [B6 envelope prefix](Z_FIX05.md#b6-gpt-oss-envelope-prefix), §12 |
| B7 | List-item chunking tried and reverted on 21 October. Implemented 25 October, uncommitted: source-quoted claim wording and code-delimiter removal (ADR 0036); the native list-item claim split was withdrawn the same day after two live pairs (B7 below) | [B7 original record](Z_FIX05.md#b7-original-record) |
| B8 | Native preserved-token bookkeeping (ADR 0024) | [B8](Z_FIX05.md#b8-the-model-classifies-and-disposes-exact-value-tokens) |
| B9 | Feature-owned entity records and no output allowance; runaway class open (B9 below) | [B9 records](Z_FIX05.md#b9-records), §§9, 11, 16 |
| W1, W2 | No post-generation upstream rebuild; the duplicate path is deleted | [W1](Z_FIX05.md#w1-review-can-restart-the-whole-pipeline), [W2](Z_FIX05.md#w2-the-upstream-repair-path-exists-twice) |
| R8 | Acceptance policy implemented offline; adjudication and calibration open (R8 below) | [R8 record](Z_FIX05.md#r8-record), §17 |
| §§9–17 | Implementation records, 17–21 October | [Z_FIX05](Z_FIX05.md#9-b4b9-implementation--17-october-2026) |
| Test performance P1, P9 | Untraced leak-checking allocator and opt-in test-run reuse, implemented 24 October (`bf8a297`, `2bafdb0`, `269410b`); no verify result or re-measurement recorded | [Z_FIX05 §18](Z_FIX05.md#18-offline-test-performance-p1-and-p9--24-october-2026) |

Section references §9–§18 point to Z_FIX05.

**Live runs since 21 October 2026 (AEDT).** Every run in the table used GPT-OSS-20B on
Bedrock, ran once and was separately approved. The eleven Claude Haiku 5.5 attempts of
24 October, all `authorization_denied` before any output, are in the §8 log. Advisory scores are `/evaluate-e2e` analysis under
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
| [Hello-world](../zig-out/e2e-spec/2026-10-24T06-49-59Z-172d37237530ce1fdd29108d598ab447/report.json), 24 Oct 17:49 | `8a600d7` | 24 / 63,402 | Published; advisory 89.29% |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-24T06-58-47Z-67dd5ecc82bd3aa1d1ccdc1b6a3be752/report.json), 24 Oct 17:58 | `8a600d7` | 31 / 99,098 | Published, 902 tokens under budget; one bounded protocol correction in source review; advisory 82.14% |
| [Hello-world](../zig-out/e2e-spec/2026-10-24T20-52-24Z-920d6f61f4f754ba0febe016a63a0d73/report.json), 25 Oct 07:52 (step 0) | `269410b` | 24 / 63,013 | Published; advisory 89.29% |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-24T20-52-59Z-2eea9516eda639fe5f16f42ea5f8d431/report.json), 25 Oct 07:52 (step 0) | `269410b`, own principles | 29 / 109,327 | `WorkflowTokenBudgetExceeded` in principle review, after a source-review runaway (`output_limit`, 19,404 tokens) on `Renewal refused.` (B9) |
| [Hello-world](../zig-out/e2e-spec/2026-10-24T22-15-43Z-30b8b0c83633333af9b587cffd04a72f/report.json), 25 Oct 09:15 (B5) | `47723fd` | 24 / 63,479 | Published; advisory 82.14%; no restatement to delete |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-24T22-16-19Z-66cb68e78884933cdbb32c75a15a6314/report.json), 25 Oct 09:16 (B5) | `47723fd` | 25 / 80,195 | Published; advisory 82.14%; no restatement to delete |
| [Hello-world](../zig-out/e2e-spec/2026-10-25T02-14-59Z-affe7e5515d88a93ea871e6cac782617/report.json), 25 Oct 13:14 (B7) | `47723fd`, ADR 0036 uncommitted | 24 / 65,021 | Published; advisory 82.14%; escaped backticks around the greeting |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-25T02-15-01Z-67214efa45244f986e884838c171a5c5/report.json), 25 Oct 13:15 (B7) | `47723fd`, ADR 0036 uncommitted | 27 / 109,967 | `WorkflowTokenBudgetExceeded` in policy review, after a source-review runaway (`output_limit`, 19,270 tokens) on `Loan renewed!` (B9) |
| [Hello-world](../zig-out/e2e-spec/2026-10-25T03-31-56Z-8ad5e999fcf1b2bd4f7c2fdeba3a0fab/report.json), 25 Oct 14:31 (B7 + Decision 6) | `47723fd`, ADR 0036 uncommitted | 27 / 75,877 | Published; advisory 71.43%, critical failure on source-grounding (filler assumption, non-goal and prohibition) |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-25T03-31-57Z-b94ba811af124b3c5fc699618cae4e01/report.json), 25 Oct 14:31 (B7 + Decision 6) | `47723fd`, ADR 0036 uncommitted | 18 / 112,532 | `WorkflowTokenBudgetExceeded` in source review, after a records runaway (294 edge cases) (B9) |

- **Completion.** Hello-world published in 10 of 11 attempts and loan-renewal in 4 of 11.
  All sixteen reports are `spec-e2e-report/v9`, so the published ones can be adjudicated,
  but none has been. No run counts toward the
  [ADR 0034](../design/decisions/0034-spec-quality-gate.md) gate yet. Three pairs (one run
  of each case) used an unmodified committed build:
  - `7a88804` (21 October 08:16 and 08:29 AEDT);
  - `8a600d7` (24 October 17:49 and 17:58);
  - `269410b` (25 October 07:52, the step 0 baseline of §6 step 4).

  The rest were modified builds.
- **Run-to-run variation.** Hello-world's step 0 text differed noticeably from
  `8a600d7`, though nothing affecting hello-world had changed:
  - its title became concise and its BR-001 disappeared;
  - FR-001 gained the startup obligation;
  - the acceptance criterion gained an implementation detail.

  The advisory score stayed at 89.29%. Single runs therefore can't attribute a change, so
  each measurement round needs repetitions (§7).
- **Loan-renewal's own principles.** Principle review judged all 19 subjects `compatible`
  on `269410b`, where `8a600d7` had 4 `conflicting` and 3 `uncertain`. The output wasn't
  admitted, because the budget ran out first.
- **Content.** Loan-renewal's published output still weakens "must be able to renew" to
  "may renew" and has no refusal acceptance criterion (B7). On 24 October FR-001 kept
  "must allow", but the story, a business rule and the entity say "may renew"; FR-001
  covers both refusal conditions, and an edge case now covers the already-renewed one.
- **Budget.** Loan-renewal ran out of the 100,000-token budget in review in 3 of its 8
  attempts (B4). The 24 October run published with 902 tokens left, review taking 81.3%.
  The 25 October step 0 run reached 109,327 tokens after a runaway, and would have
  published under the approved 125,000 budget.
- **Runaway output** caused all three timeouts; the 180 s deadline made it visible (B9).

**Providers.** [ADR 0028](../design/decisions/0028-anthropic-messages-provider.md)
(21 October) added the Anthropic Messages API provider on shared provider owners.
[ADR 0029](../design/decisions/0029-bedrock-model-families.md) (22 October) lets a Bedrock
catalogue entry name any model with a compiled family. The E2E catalogue lists Claude
Haiku 5.5 through both, and the live-test policy permits it for generation. On 23 October
the user chose Claude Haiku 5.5 on Bedrock (`au.anthropic.claude-haiku-5-5`, low effort)
for every E2E slot. All eleven attempts ended `authorization_denied`, because the account
lacks access to the model, and on 24 October the user switched the slots back to
GPT-OSS-20B (ADR 0029, amended; see the 24 October log entry). No live Claude run has
completed. All
live evidence in this record so far comes from GPT-OSS-20B, and which failure classes
are model limitations is unmeasured (R7).

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

**Decided 22 October 2026; partly implemented (slices 1–3; see "Implementation
progress").** [ADR 0030](../design/decisions/0030-engine-owned-model-request.md) replaces
the request
subgraph with one `request-model` step per model request (its 22 October text also gave
counting a `count-model-tokens` step, removed on 23 October; see below). A fixed,
capability-free kernel orchestrator runs the lifecycle through
runner-owned child bindings. Consumers, release, advisory routing, `retain-json-part` and
ledger initialization stay in YAML. The full record is in
[Z_FIX05](Z_FIX05.md#a1-decision-record).

**Choices settled — 23 October 2026.** The user asked for "the best possible solution,
remember this is a POC and best outcomes is the primary goal", then directed "update docs
with" the resulting table. ADR 0030's "Choices settled on 23 October 2026" records it:

| Choice | Derived on 22 October | Settled |
| --- | --- | --- |
| 1. Form | Kernel orchestrator | **Kept** |
| 2. Token counting | Rebuild as `count-model-tokens` | **Removed**: no workflow, fixture or registered model uses it |
| 3. Deadline | `timeout-ms` on every request step | **Moved to each catalogue entry** as a required `requestTimeoutMs` |
| 4a. Release | Explicit YAML step | **Kept** |
| 4b. Advisory routing | Every step maps all six outcomes | **Only steps marked `advisory: allowed` map `more` and `blocked`**; they may carry both kinds of request |

The global token count is unchanged: the workflow budget, report totals and per-call
usage come from actual inference usage, never from counting. The amendment points ADRs
0005, 0011, 0014, 0019, 0023, 0028 and 0029, design.md, contracts §§6, 9, 12, 14, 27 and
28, the operation catalogue, F0005–F0007, F0100, diagram 16 and the README to it. No code,
workflow YAML or catalogue changed.

Open:

- implementation, with ADR 0030's offline acceptance, including the shared
  contract-variant mechanism (confirmed 23 October 2026) that ADR 0033 reuses;
- the measured replacement for Claude Haiku 5.5's interim 180,000 ms `requestTimeoutMs`;
- whether the engine should also take over release, which needs the compiler to derive
  each request's lifetime.

**Implementation progress.**

- **Slice 1, freeze — done 23 October 2026 (`5ce2af4`).** The Specify integration matrix
  writes one step trace and summary per scenario to `.zig-cache/workflow-step-trace/`
  (`src/test_fixtures/workflow_step_trace.zig`). A request-lifecycle step inside a request
  wrapper is keyed by its call site plus the stage's operation ID, the form `request-model`
  keeps; a lifecycle body reached without a wrapper fails the run. Each summary records
  the outcome, the canonical rejection diagnostic, step and call counts, token totals,
  every accounted inference (call site, purpose, request and attempt ordinals) and the
  hashes of the published and state files. 195 scenarios: 147 ok, 36 failed, 6 invalid,
  5 needs-user and 1 blocked. Two consecutive runs produced 1,018 identical files. The
  baseline is reproducible by running `zig build test-integration` at `5ce2af4`; a copy
  goes to `evaluations/adr0030-freeze/5ce2af4/`.
- **Open points for slice 4,** from the slice 1 contract review:
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
- **Slice 2, token counting removed — done 24 October 2026.** The four count
  operations, the `input_token_count` operation kind (`ProviderOperationKind` is now
  `{ inference }`; every persisted kind field stays), the `assign-provider-operation`
  `kind` parameter (assignment takes no parameters and assigns inference), the count
  capability, the `exact_token_count_unavailable` failure cause, the two count data keys,
  Bedrock CountTokens encoding, decoding and endpoint, the provider port's
  `countInputTokens`, every fake and spy count path, the two count test files and their
  build steps, and the packaging smoke's count cases are deleted. Actual-usage accounting
  is unchanged. Tests that looped over both kinds keep their inference case; forged-kind
  rejections became forged-attempt rejections. The inference-then-authorization closure
  test, the option (b) baseline for that case, was converted to a second attempt whose
  authorization fails or is cancelled, rather than deleted. Superseded count text was
  removed from contracts §12, the operation catalogue, F0006, F0007, `code.md`, diagram 16
  and the README; the ADR notes and design.md mark the removal implemented. The Specify
  step traces are identical to the slice 1 freeze, and the production-admission report is
  unchanged. Left for later:
  - ADRs 0006 and 0013 mention optional counting in their historical text; each now
    carries an ADR 0030 pointer (user-approved 24 October 2026);
  - F0007's model table predates ADR 0029's families;
  - trivially true `.inference` guards in files slice 2 did not edit, including the
    harness's now-unreachable `CaptureNotInference`, go with `request-model` (slice 4);
  - a pre-existing conformance case (`provider_conformance_test.zig`, forged operation)
    is rejected for being a copy before its foreign attempt is checked; it needs its own
    fix.
- **Slice 3, deadline in the catalogue — done 24 October 2026.** Every `.sddproviders.json`
  entry's `config` requires `requestTimeoutMs` (a `RequestTimeout` of 1 to 2^32-1 ms, so a
  monotonic deadline can always be formed), read through one `requestTimeout()` accessor;
  the test-only config schema `empty_object` is now `deadline_only`. Authorization
  preparation takes no parameters: the runner binds the request's catalogue deadline to
  every provider operation of the request, including protocol corrections, and a YAML
  `timeout-ms` is rejected at compilation. Replay uses the captured deadline instead of a
  fixed 300,000 ms. Shipped values: 180,000 ms for GPT-OSS-20B and an interim 180,000 ms for
  both Claude Haiku 5.5 entries (B9), 60,000 ms in the packaging fixture's catalogue; the
  frozen calibration protocol records 180,000 ms and advances to schema 4, so an older
  protocol is rejected as a version mismatch (both user-approved). `model-request-debug`
  advanced to v11 and `model-call-evidence` to v3, with v2 and v1 kept readable as
  historical evidence. Retained runs captured before this change can no longer be read by
  `e2e-call`, the compatibility inspection, the baseline or the frozen binding. **Freeze
  recheck:** the Specify step traces and summaries are identical to the slice 1 baseline
  (all 545 entries), and the production-admission report is unchanged; the deadline
  changed nothing observable in the matrix.

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

**Status on 25 October.** The gate isn't met:
- no run has been adjudicated;
- only three pairs used an unmodified committed build (one run of each case, on
  `7a88804`, `8a600d7` and `269410b`);
- loan-renewal published in 3 of its 8 attempts since 21 October (§1).

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
  - On 25 October the user set quality above cost and approved a configurable
    125,000-token budget (B4) instead of making source review optional.
  - Source review therefore stays. Its open problems are its accuracy (false assessments
    and missed obligation changes) and waste. Under "quality over cost, but never waste",
    review spending that buys no quality is still to be removed at its owner. Measuring
    the prompt, schema and evidence share of each call (B4) is the first step; nothing is
    removed by keyword or truncation.
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
workflow budget are implemented; since ADR 0037 the budget is the configured
`workflowTokenBudget`. Option 1, a separate advisory allowance,
was withdrawn: there is one total limit. Records are in
[Z_FIX05](Z_FIX05.md#b4-records) and §9.

Input is 93% of tokens. Review sends average about 2,500 input tokens for
single-field subjects. The four response schemas are 11.9–14.1 KB each, with 15–32
definitions.

Until ADR 0037 the 100,000-token budget was compiled into every policy profile and was
not case configuration. The protocol's experiment-wide stops of 1,000 sends and 2,000,000
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

**Approved 25 October 2026: a configurable workflow budget, raised to 125,000 tokens.**
The user directed "make budget configurable and increase to 125000", and set the
priority: "the key of the entire app is to ensure quality … if budget has to be
increased in favour of quality it is fine", then "quality over cost, but never waste".
- Token cost is not a reason to drop or weaken a quality check.
- Spending that buys no quality is waste, to remove at its owner.

This settles the budget half of the decision above.

- **Change.**
  - The single workflow token budget stops being compiled into the policy profiles
    ([core](../src/composition/core_workflow_operations.zig#L35),
    [native](../src/composition/native_workflow_operations.zig#L638)).
  - It becomes a validated configuration value, read once at bootstrap.
  - It remains one total limit for the run, as option 3 left it.
- **Value.** 125,000 in the shipped E2E configuration, which both cases use, and in the
  example configuration.
- **Design points for the ADR.** It amends ADR 0011's budget contract, as ADR 0023
  amended it.
  - Where the value lives: the project configuration or the workflow definition.
  - It is a closed, required, positive value with no engine default (AGENTS.md: no
    fallbacks).
  - Offline tests that exhaust the budget, and fixtures read by the step-trace freeze,
    set their own explicit values, so the ADR 0030 freeze stays comparable.
  - Persisted values that carry the budget, such as a report's
    `token_accounting.total_budget`, take the configured value.
- **Implemented 25 October 2026, uncommitted
  ([ADR 0037](../design/decisions/0037-configured-workflow-token-budget.md)).** The user
  directed "make the token cap an external setting, that is stored and loaded from
  .sddtoolkit.json, to the e2e test set the token cap to 125000".
  - `.sddtoolkit.json` has a required root `workflowTokenBudget`, an integer from 1 to
    4,294,967,295, decoded through the positive-integer rule the catalogue's limits
    now share (moved to `positive_json_integer.zig`). It sits at the root so model-slot
    consumers don't depend on it.
  - The composition root passes it to the pipeline runner's per-execution ledger.
    Policy profiles (nine copies of 100,000) and compiled graph authority no longer
    carry a budget, and the runner's policy cross-check compares capabilities only.
  - Values: 125,000 in the E2E configuration and the example; 100,000 in the baseline
    protocol and unit fixtures; 90,000 in the scripted budget test, which shows the
    ledger reads the configuration.
  - The baseline harness reads the configured value; its feasibility report's field is
    now `configured_workflow_budget` (`baseline-budget-feasibility/v2`,
    `baseline-freeze/v3`). The E2E report is unchanged at v9.
  - Checks: `zig build test` 1,813 of 1,813 and integration 129 of 129 passed.
  - **Live pair, 25 October 18:19** (advisory analyses in `evaluations/e2e/`): both
    published, each at advisory 85.71% with no critical failure; reports record the
    configured 125,000. Hello-world used 61,885 tokens; loan-renewal 98,492, under the old
    100,000 too, so the larger budget wasn't decisive. Loan-renewal's source-review call
    24 ran to the 16,384-token maximum on `Renewal refused.` (B9), and its refusal
    behaviour still has no scenario (B5). Records: 2 per case, no filler.
- **Still open, before any baseline freeze: the experiment stops and the qualified
  scope.** At 125,000 tokens per workflow, the protocol's 2,000,000-token stop covers
  16 workflows, so the Phase 2 feasibility report stays `insufficient`.

**Evidence since 21 October.** Loan-renewal ended `WorkflowTokenBudgetExceeded` in review
at 21 October 11:45 (100,793 tokens) and 22 October 08:31 (100,763), and published at
76,501, 92,825 and, on 24 October, 99,098 tokens (§1). A larger budget gives quality
changes room; on its own it doesn't make review cheaper or runs more reliable.

### B5. Authoring follows mechanical source groups

Evidence from former F1, F9 and F13:

- Each record batch re-authors the whole feature, which produced competing or
  duplicate records in four runs.
- The group holding only a preserved value gets its own batch.
- One assignment can still require interpreting obligations, choosing record
  families, preserving conditions, building scenarios and entities, and deciding
  whether uncertainty blocks drafting.
- Six model requests precede authoring even on a three-line source.
- **24 October (`8a600d7`).** Each case formed one real group, because extraction merged
  each list into one claim (B7), so each made exactly one records call (call 10). Today's
  per-group authoring and a single collection therefore behave the same on both cases.
  - Native coverage
    ([specification_coverage.zig](../src/domain/specification_coverage.zig)) accepts a
    claim mapped to any target, whether the story, the brief or any record.
  - Loan-renewal's refusal behaviour had no acceptance criterion in all three evaluated
    runs (`7a88804`, `527f870`, `8a600d7`).

**Done.** Token-only groups no longer get a record batch (approved 17 October with B8,
under [ADR 0024](../design/decisions/0024-native-exact-token-authority.md)). The record is
in [Z_FIX05](Z_FIX05.md#b5-token-only-record-batches).

**Original proposal:** compare current per-group records (A) with one complete record
collection (C). Add a purpose-only acceptance-criterion diagnostic (B) or per-family
collections (D) only where measured failures justify them. Run it after B2 and B3,
which change every arm and dominate cost.

**Proposal: one complete record collection with native acceptance-criterion coverage.**
This is the recommended option, recorded on 25 October 2026 by user direction. It
replaces running the A/C comparison and needs a decision and an ADR before
implementation.

1. **One authoring call per feature (C).** It writes the complete record collection, and
   each record names the claims it supports. The engine validates those links, under the
   constraints below.
2. **Coverage that knows record families.** Extend native coverage so that every
   behavioural claim must be cited by at least one acceptance criterion or edge case. A
   gap is a typed defect that takes the existing bounded correction. Context-only claims
   are exempt.

- **Why C over A.**
  - Per-group batches re-authored the whole feature and produced duplicates.
  - Records bind their whole group (R1), so a per-claim check can't be made.
  - Calls grow with group count, which lengthens the chain (B1).
  - C has one author, explicit support links, and a call count that doesn't depend on
    the source's structure.
- **Why native coverage over B and D.** B is model-facing guidance, which the model can
  ignore. Once support links are explicit, coverage is computable, so deterministic code
  owns it. D adds calls without measured need.
- **Why not run the comparison.** On both current cases A and C produce the same single
  records call, so it can't decide anything, and its baseline is blocked on B4.
- **What it depends on to pay off.**
  - **Requirement-level claims.** With one merged claim, one acceptance criterion
    already satisfies coverage, so the missing refusal criterion is still not caught.
    B7's native list-item split, which supplied them, was withdrawn on 25 October after
    the records call inflated with more claims. With C, more claims no longer add
    records calls.
  - **Review headroom (B2, B4).** More claims mean more review subjects. The 21 October
    list-item run exhausted the budget in source review. The approved 125,000-token
    budget (B4) provides headroom; whether it is enough is unmeasured.
- **Cost and risk.**
  - It is a large contract change; the constraints below list what changes together.
  - It amends ADR 0020's group binding, which would settle R1.
  - One larger call has a larger output and an all-or-nothing failure, and a correction
    re-sends the whole collection.
- **Evidence required (§7).**
  - Offline, multi-claim features: a behavioural claim without an acceptance criterion
    or edge case is rejected; an acceptance criterion that paraphrases a functional
    requirement is accepted; context-only claims are exempt.
  - Then repeated live runs of both cases, counting every attempt.
- **Order.** The configurable budget (B4) first, then requirement-level claims (B7), then
  this.

**Implemented 25 October 2026: cross-kind restatement in the native duplicate rule
([ADR 0035](../design/decisions/0035-cross-kind-restatement.md)).** The user answered
"YES" to the recommended option. In the preflight they decided three rules:
- a restatement is deleted only when the kept occurrence covers its evidence;
- an uncovered one is left as today;
- a functional requirement is kept, and otherwise the earlier record.

Same-kind duplicate checks run first, so a competing pair still blocks. A restatement
has its own `restatement` repair rule. The text below is the approved proposal; ADR
0035 is authoritative where they differ. Follow-up: no offline integration scenario yet
exercises a records-batch native delete, whether duplicate or restatement.

- **Today.** `duplicate_record`
  ([specification_generation.zig:291-305](../src/domain/specification_generation.zig#L291-L305))
  compares whole typed content, record kind included, and compares records only with
  other records.
  - Identical text in two kinds passes, and so does a record that repeats the primary
    user story.
  - Its remedy is a native delete of the redundant record
    ([specification_repair.zig:82-87](../src/domain/specification_repair.zig#L82-L87)),
    with old-value and revision preconditions. A delete builds no model request
    ([atomic_repair.zig:128](../src/domain/atomic_repair.zig#L128)).
- **Change.**
  - Compare normalized statement text across the single-statement record kinds:
    functional requirements, business rules, assumptions, non-goals, prohibitions and
    user-visible outcomes.
  - Also compare them against the primary user story, which is never the deleted
    occurrence.
  - Acceptance criteria and edge cases keep today's same-kind comparison.
  - Reuse the native delete and the coverage revalidation unchanged.
- **Evidence.** On `8a600d7`, BR-001 equals the primary user story word for word in both
  cases: hello-world specification lines 7 and 21, and loan-renewal lines 7 and 31.
- **Effect.**
  - It deletes those business rules with no model call.
  - It removes their review subjects, which saves tokens where loan-renewal's budget is
    tight.
  - B7's source-quoted wording would make restatements word for word more often, so this
    rule would catch more of them.
- **Limits.**
  - It catches exact restatement only. Paraphrased filler still passes, such as
    loan-renewal's non-goal restating the one-renewal limit, or a restated prohibition.
  - An entity description identical to the story can't be deleted, because deleting the
    entity would change the entity decision (R6). It needs a bounded rewrite of that
    field, under its own decision.
  - Deleting a record can remove an obligation's last mention in the records:
    hello-world's BR-001 is the only record that says "start successfully". Coverage
    still passes through the story; B5's acceptance-criterion coverage would catch real
    gaps in testing.
- **Evidence required (§7).**
  - Offline, at the rule:
    - a business rule identical to the story is deleted natively, and coverage holds;
    - a functional requirement identical to a business rule loses the later one;
    - an acceptance criterion that paraphrases a functional requirement is kept;
    - an entity description identical to the story isn't deleted.
  - Then repeated live runs of both cases.

| Former phase | Status |
| --- | --- |
| 0 Evaluation protocol | Complete offline: [protocol, cases, specimens and scoring](../test/calibration/semantic-simplicity/README.md) |
| 1 Compatible execution | Live gate passed for the observed first request only ([record](Z_FIX02.md#phase-1-implementation-and-live-gate)) |
| 2 Baseline | [Harness](../test/harness/baseline/cli.zig) implemented; not frozen; needs B4's decision and a committed build (B3's gate closed on 17 October) |
| 3–6 A/C comparison, implementation, qualification, adoption | Not started; the recommended option above replaces the comparison |

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

Evidence from GPT-OSS-20B runs, 17–24 October:

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
- **24 October (`8a600d7`).** Both cases again extracted one claim per list (lines 5–7
  and 5–9), and loan-renewal's claim again read "may renew".
  - Every later loan-renewal call received both the cited source text ("must be able to
    renew") and the weakened claim. The guidance says that original sources establish
    obligations and that claims are derived evidence
    ([required_authority_description.zig:10-11](../src/domain/required_authority_description.zig#L10-L11)).
  - Yet the story, BR-001 and the entity followed the claim while FR-001 followed the
    source, so the published specification contradicts itself.
  - Review calls 12 and 14 judged the weakened text accurate.
  - The extraction guidance already asks for one fact per claim and for each fact's
    obligation strength to be kept
    ([extraction.context.json:4](../design/workflows/spec/extraction.context.json#L4)).

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

**Status.** Per-item chunking before extraction (ADR 0027) stays withdrawn by that revert.
One pair cannot decide a contract change under §7, so the revert is a user decision, not
evidence that segmentation can't help. Source-quoted claim wording, for the
obligation-weakening half, is implemented
([ADR 0036](../design/decisions/0036-source-quoted-claims.md)). The native list-item split
for the list-collapse half was implemented and withdrawn on 25 October, so list collapse
is open again. The original record is in [Z_FIX05](Z_FIX05.md#b7-original-record).

**Implemented 25 October 2026, uncommitted (ADR 0036, option 1).** The user directed
"implement B7 with option 1". ADR 0036 is authoritative where the approved text below
differs.

- **Contract.** A model claim is `{category, citations}`, where `citations` is a set of
  line IDs. Admission restricts them to the chunk's citable lines, decided by one shared
  predicate.
  - One function at extraction text validation quotes the cited lines as written,
    Markdown included. A run continues across uncited blank lines and is trimmed only at
    its ends.
  - One proposal is one claim. The list-item split described in the reviews below was
    withdrawn (see "Split withdrawn").
- **Deleted.** Claim-text repair (text repair keeps only the `no_feature_claim` reason),
  citation repair, the `source_selections` diagnostic, `business_text_replacement`, the
  `retain-reference-claim-rejection` operation and the write-only claim citation origins.
  `validate-reference-claims` now ends `ok` or `failed`.
- **Defects found and fixed.**
  - In implementation:
    - A citation choice scoped to the `claim` definition couldn't bind the whole
      extraction response, so every initial request would have failed at handoff. The
      initial request now bounds `/claims/*/citations`, and the omission claim repair
      bounds its own `citations`.
    - The source-omission merge kept only the first claim of a split proposal; it then
      inserted every claim. With the split withdrawn, it inserts its one claim again.
  - In two contract reviews:
    - **Rewriting the quote was fragile.** The first draft removed markers and code
      delimiters and changed whitespace. Its line-by-line parsing ignored fenced code,
      multi-line code spans and wrapped numbers such as `2024.`. Some admitted citations
      quoted to nothing and failed the run, words fused and delimiters leaked. A code
      block with a blank line lost its exact-value duty.
      - The quote is now the cited source bytes as written, which removes that class.
      - List structure was given one Markdown owner (withdrawn with the split).
    - **Quadratic cost.** Rebuilding the whole source's scan for every chunk was
      quadratic: 777 MB held at 256 chunks. Each source's fenced code is now scanned once
      per validation.
    - **C1 control characters** passed ingestion but fail the text validator. The
      Markdown reader now uses the typed-text scalar rule.
  - In a third review:
    - Trimming a run's ends could strip a fenced block's own bytes and lose its
      exact-value duty. Code lines are no longer trimmed.
    - Joining runs with a line break could form a JSON insertion object absent from the
      source and fail the run. Runs are now joined by an ellipsis line.
    - Other fixes:
      - Each chunk's first line is found by binary search.
      - The test helpers use the shared citable predicate.
      - List-structure fixes (HTML blocks, one marker parser) went with the split.
- **Tests.**
  - New coverage:
    - quoting, one claim per proposal, including lines cited out of order, a heading with
      a nested list, runs across blank lines, fenced code, leading indentation, and chunks
      starting inside and after a fenced block in two sources;
    - the exact-value duty for a multi-line code span and a fenced block with a blank
      line;
    - an allocation bound across 128 chunks;
    - admission bounds, including blank lines, for the initial request and omission
      repair;
    - rejection of model wording;
    - an omission repair over two list items, inserting one quoted claim;
    - C1 rejection at ingestion;
    - a reason-repair test that keeps the deleted claim-text test's packet, origin,
      progress and stale-authority coverage.
  - Deleted: four unit tests and six integration scenarios for the deleted routes.
  - **Scripted fixtures:**
    - claims cite only citable lines;
    - the omit-exact scenario authors distinct text per claim;
    - the classification-loss scenario keeps its token on an unquoted line;
    - the omission repair cites one line.
  - **Retained GPT-OSS exchange:** the debugger replays it with its retained wire shape;
    the provider-compatibility test now expects the current schema to reject it.
- **Checks.**
  - `zig build test`: 1,809 of 1,809 passed. Fix3's `test-build-reuse` fails only with a
    repository-relative cache.
  - Integration: 129 of 129 passed.
  - `zig build lint`, `zig build test-architecture` and `zig build verify` (out-of-repo
    cache) passed.
- **Open, from the contract review.**
  - Stored readback doesn't re-quote claim text from its citations. It would need the
    Unicode normalizer at readback.
  - Admission caps the citation count but admits a repeated ID; the quote ignores the
    repeat.
  - The extraction reason's text-repair route now has unit coverage only.
  - No synthetic current-schema exchange replaces the retained one's `compatible`
    assessment.
  - Claim wording now carries Markdown (list markers, backticks) into later calls. The
    first live pair showed generation copying backticks around exact values; Decision 6
    removes them at admission. Other Markdown effects are unmeasured.
  - `source_selections`'s typed rejection detail is read only by tests now, and the
    `validate-reference-selections` operation and its value key validate token
    classifications only. Renaming or trimming them was left out of scope.
- **Live pair, 25 October 13:14–13:15, on the uncommitted tree** (advisory analyses in
  `evaluations/e2e/`):
  - **Extraction:** both cases cited a whole list as one claim, and the engine split it
    into one quoted claim per item (3 and 5). Reconciliation grouped each case's claims
    back into one signal.
  - **Hello-world** published at 65,021 tokens, advisory 82.14% (unchanged). Its "should
    output" weakening didn't recur. A new defect appeared: generation copied the
    quoted Markdown and wrapped the greeting in backticks, which render escaped beside
    the exact-value code span.
  - **Loan-renewal** failed `WorkflowTokenBudgetExceeded` at 109,967 tokens, after a
    source-review runaway on the preserved-token subject `Loan renewed!`. This is the
    third runaway on a preserved-token subject (B9).
    - Before failing, its records batch authored 12 records against 2 in the previous
      run, including both refusal conditions as edge cases.
    - Generation still wrote "may renew" in the brief, story and entity, although every
      claim and signal it received said "must be able to renew". The weakening's source
      is now generation.
    - Under the approved 125,000 budget (B4) the run would have continued.
- **Backtick fix, 25 October (user: "apply recommendations as per above", ADR 0036
  Decision 6):** the exact-value recogniser reports equal backtick runs directly around a
  value, and admission drops them with it. The value becomes an exact copy in an
  obligation-bearing field and stays text elsewhere. Nothing else in the text changes.
  - Fixed during implementation: prohibited fields used the unit's lineage for the first
    recognition and every value for the re-check, so their stored value no longer
    matched. They now always use every eligible value.
  - Fixed after contract review:
    - Removing delimiters could join a longer value across the gap, so the re-check
      turned ambiguous and escaped as an untyped error. Delimiters now stay unless
      removing them leaves the same matches, and the re-check reports a typed issue.
    - A backtick between two values could be claimed by both, panicking in a prohibited
      field. It now belongs to neither, and every caller cuts one outer span.
    - Tests now catch both cases and a reverted composition cut.
    - A second review found that repairs recognise with a narrower lineage than the
      re-check, so the guard could approve a removal that the re-check then found
      ambiguous. Removal is now a separate recogniser step, checked against every
      eligible value. A repair-path test catches the narrow-set mutation.
  - Checks: `zig build test` 1,812 of 1,812, integration 129 of 129, lint and
    architecture passed. The typed re-check in `valueIn` has no reachable test once the
    guard shares one set; it stays as a typed outcome.
  - The other open items affect no outcome, so they stay open: readback re-quoting, the
    repeated citation ID and reason-repair integration coverage.
- **Live pair, 25 October 14:31, B7 + Decision 6** (advisory analyses in
  `evaluations/e2e/`):
  - **Hello-world** published, advisory 71.43%, with a critical failure on
    source-grounding.
    - Decision 6 worked: the greeting renders once.
    - The records call added a filler assumption ("system clock is set to UTC"), a
      non-goal forbidding any other output and a crash prohibition. It also wrote
      business rules that restate the quoted claims. Source review flagged the three
      fillers, as advice only and filed as `candidate_omission`.
  - **Loan-renewal** failed on budget. Its records call ran away with 294 edge cases
    (9,318 output tokens) enumerating loan-state combinations, which source review then
    had to assess.
    - This is a new form of the B9 runaway class, in generation.
    - B9's open "cardinality bounds" choice is its owner.
    - The 125,000 budget alone would not have saved it.
  - Across the four B7 runs, generation output varies widely: loan-renewal's records went
    from 12 to 304 (294 of them edge cases), and hello-world's from 3 to 8.
- **Split withdrawn, 25 October (user: "make the changes as suggested").** Quoting stays;
  the native list-item split is removed, so one proposal is one claim again.
  - **Why.** In the four B7 runs the records call authored 3, 12, 8 and 304 records,
    against 2 to 4 for the same cases with one claim per list. The extra records were
    unsupported fillers and restatements, and once a runaway enumeration. The evidence is
    correlational and small; it says requirement-level claims don't pay off while the
    records call is unbounded (B9).
  - **Changed.**
    - [reference_extraction_text.zig](../src/domain/reference_extraction_text.zig) quotes
      each proposal as one claim. It keeps a per-validation cache of each source's fenced
      code blocks, which the quote needs for the code-line trimming rule.
    - `markdown_code_spans.zig` is back to its committed form: `listSegments`, `ListLine`
      and the shared marker parser are deleted.
    - The source-omission merge inserts its one claim.
    - The extraction `citations` guidance again asks for the lines of "the complete
      claim", and drops "and no others", which pushed toward narrow claims.
  - **Tests.** The quoting test now asserts one claim per proposal, including a two-item
    list cited out of order, a heading with a nested list and trimmed indentation. The
    chunk-boundary case uses two sources, with chunks starting inside and after fenced
    blocks; a cache keyed to the wrong source fails it. The omission-repair test inserts
    one claim over two items and checks its quote; the authoring test quotes
    hello-world's whole chunk; the post-generation advice test uses the default
    whole-chunk claim again.
  - **Checks.** `zig build verify` (out-of-repo cache): 164 of 164 steps, 1,941 of 1,941
    tests. A contract review found no code defect; its document and coverage findings
    are fixed.
  - **Live pair, 25 October 16:46** (advisory analyses in `evaluations/e2e/`):
    - **Hello-world** published, advisory 85.71% (71.43% before), no critical failure.
      Extraction itself cited one line per claim; reconciliation merged them. The
      records call wrote 3 records and the native restatement rule deleted one. No
      filler families. The invented entity persists, and review judged it supported.
    - **Loan-renewal** failed on budget at 101,424, after the last source-review subject.
      Generation received one merged quoted claim, yet the records call wrote 40 records:
      five near-repeats of all eight families, fillers included. Native deletes removed
      17 exact copies; 23 reached review. The 125,000 budget would probably have let it
      publish, with filler.
    - Extraction returned five claims each citing all five lines. Under quoting they are
      identical; reconciliation marked four as duplicates.
    - **Reading.** Withdrawing the split didn't stop loan-renewal's records inflation, so
      claim count isn't its only driver. The records cardinality bound (B9) is the open
      owner. Identical citation sets are a new, computable duplicate (decision open).
  - **Open, found in review (predates the withdrawal).** A fenced block whose first or
    last interior line is blank can escape the exact-value duty: citing every other
    line quotes the block without that blank line, so the token's bytes aren't in the
    quote. Whether ADR 0036's "cites in full" means every citable interior line needs a
    decision.
- **Next:** the user decides on the commit, and on B9's cardinality bound.

**Approved 25 October 2026: source-quoted claim wording.** The user answered "YES" to
the recommended option. It needs an ADR amending the §16 extraction contract, written
with the implementation; the native list-item split below is part of the same ADR.

The model keeps the semantic work: it selects each claim's cited source lines and
classifies the claim. The engine supplies the wording, taking each claim's statement text
natively from its cited lines, so no paraphrase can change obligation strength, conditions
or negation. [ADR 0024](../design/decisions/0024-native-exact-token-authority.md) applies
the same pattern to exact values.

- **Why this owner.** The weakened claim adds no information the source lacks, because
  every downstream call already receives the cited source text. It only adds a second,
  conflicting wording, which the model follows despite explicit guidance. Removing the
  paraphrase removes the conflict by construction, without keyword rules, for any
  modality or language.
- **What it fixes.** Obligation changes that start at extraction and are copied
  downstream, which is every observed case.
- **What it doesn't fix.**
  - List collapse: citations are whole lines, so a merged selection stays merged, though
    its wording is correct. The native list-item split below was tried and withdrawn.
  - Repetition across record kinds. B5's cross-kind duplicate rule handles that.
  - Defects introduced at generation.
- **Design points for the ADR.**
  - Normalize list markers and Markdown in the quoted text, and keep ADR 0024's native
    authority for exact values inside it.
  - Claim text validation
    ([reference_extraction_text.zig](../src/domain/reference_extraction_text.zig)) checks
    a source-derived value instead of model prose.
  - Decide whether reconciliation statements and signals, which also restate claims,
    must reference claim text natively. Otherwise they can reintroduce a paraphrase.
  - A cited line that holds two facts stays one claim.
- **Alternatives considered.**
  - Comparing modal verbs between claim and source is a keyword rule. It is fragile with
    negation and phrasing such as "is required to", which AGENTS.md's anti-overfitting
    rule forbids.
  - Review can't fix it. Source review is already told to check obligation strength
    ([required_authority_description.zig:20](../src/domain/required_authority_description.zig#L20))
    and missed it, and under ADR 0023 it can't change the output.
- **Evidence required (§7).**
  - Offline, accepted and rejected extraction fixtures where the proposed text differs
    from the cited source, including negation and conditions ("must not", "only if") in
    unrelated sources.
  - Then repeated live runs of both cases, counting every attempt.

**Approved 25 October 2026, implemented and withdrawn the same day: one claim per source
requirement, by native list-item split.** The user directed "apply the best option" for
B7's list-collapse half, then "make the changes as suggested" to withdraw it (see "Split
withdrawn" above). The approved text follows as history.

- **Change.** When a claim's citation spans more than one top-level Markdown list item,
  the engine splits it into one claim per item. Each new claim:
  - cites its own item's lines;
  - quotes that item's text, under source-quoted wording;
  - keeps the merged claim's category, and the token classifications for its own lines.

  A claim inside one item, a heading claim and prose are unchanged. No model call is
  added.
- **Why this option.**
  - Per-item chunking (ADR 0027, reverted on 21 October) gave the model one item per call.
    That added extraction calls: hello-world rose from 65,896 to 75,669 tokens.
  - Rejecting a merged claim for a bounded correction costs a call per claim, and the
    model can merge again.
  - With source-quoted wording the engine already owns each claim's text. Splitting at the
    source's own Markdown structure is therefore deterministic, works for any structured
    source and costs nothing at extraction.
- **Depends on.** Source-quoted wording, in the same change and the same §16 ADR.
- **Limits.**
  - It acts on explicit structure only. Several requirements in one prose sentence or
    paragraph stay one claim.
  - If the items of one merged claim need different categories, the copied category is
    wrong. The ADR decides whether such a split is rejected for correction instead.
  - Nested list items stay with their top-level item.
- **Cost interaction.**
  - Reconciliation still makes four calls, but signals may form more groups. Until B5's
    single collection lands, each group gets its own records call.
  - More claims and records also mean more source-review subjects. The 21 October
    list-item run ran out of budget in source review.
  - The approved 125,000-token budget (B4) provides that headroom; whether it is enough
    is unmeasured.
- **Evidence required (§7).**
  - Offline:
    - a merged claim over *n* top-level items becomes *n* claims, with each item's text,
      citations, category and token classifications;
    - a claim inside one item, a heading claim, prose and nested items are unchanged.
  - Then repeated live runs of both cases, counting every attempt.

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
  (`timeout-ms: 180000` in the Specify workflow, committed in `9719dc7`; since ADR 0030
  slice 3 the value lives in each catalogue entry's `requestTimeoutMs`). In the 19:13 loan-renewal run, call 24 wrote a valid `supported`
  finding for `Renewal refused.`, then about 40,000 newline and space characters until the
  16,384-token limit, in 74.1 s. The engine recorded `output_limit`, closed that advice as
  incomplete and published. The call cost 19,402 tokens (21% of the budget). The same
  subject was under review when both earlier loan-renewal runs that day timed out, which
  suggests, speculatively, a subject-linked trigger.
- **25 October, step 0 (`269410b`).** Source-review call 28 reviewed the same subject, the
  exact value `Renewal refused.`. Its reasoning concluded "supported"; it then ran to the
  16,384-token maximum in 69 s, costing 19,404 tokens.
  - That advice closed incomplete. Principle review then pushed the run to 109,327
    tokens, so it ended `WorkflowTokenBudgetExceeded`.
  - This is a second completed runaway on that subject, so the subject-linked trigger
    remains a hypothesis with more support. It isn't established.
- `/evaluate-e2e` found the whitespace pattern on 6 of about 700 retained calls, mostly in
  source review. That count is advisory analysis.

**Still open.** Each choice needs a decision. Don't answer the runaway with sampling
changes or extra retries (§7).

- **Deadline and maximum output.** The 180 s deadline covers GPT-OSS-20B's 16,384-token
  maximum. The catalogue's Claude Haiku 5.5 entries declare 128,000. If a slot selects
  that model, a runaway could again end as an unexplained `timeout`, and one completed
  runaway would exceed the workflow budget (125,000 in the E2E configuration). *Implemented 24 October 2026* (ADR 0030
  slice 3): each catalogue entry declares its own required `requestTimeoutMs`, so a
  deadline follows its model. Claude Haiku 5.5 starts at the shared 180,000 ms until its
  measured maximum-output time replaces it, and the budget point stands.
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
longer needs a scope change. From 23 to 24 October every E2E slot selected Claude Haiku 5.5
on Bedrock; the slots select GPT-OSS-20B again while the account lacks Haiku access. The
user decides when to change or compare models (25 October 2026). Each run still needs its
own approval.

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
  - *Resolved 23 October 2026:* ADR 0029 says the shipped E2E cases select Claude
    Haiku 5.5 with low effort in every slot, but the configuration both cases use,
    [.sddtoolkit.json](../test/e2e/wf-001-hello-world/.sddtoolkit.json), still selected
    GPT-OSS-20B, which also failed the compatibility preflight test. The user chose Haiku
    via Bedrock, and the configuration now matches the ADR. Its deadline is the interim
    180,000 ms until measured (B9). On 24 October the user switched the slots back to
    GPT-OSS-20B after every Haiku attempt was denied (ADR 0029, amended).
  - ADR 0028's "Live use" still says the policy permits only GPT-OSS-20B; since
    22 October it also names `anthropic` / `claude-haiku-5-5` for generation.
  - ADR 0028 leaves Claude's response mode (native schema or prompt-only) open until
    compatibility is measured. No live Claude call has succeeded, and no compatibility
    probe has been made.
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
   counting every attempt (§7). Two pairs have used an unmodified committed build
   (`7a88804` and `8a600d7`). Use `/evaluate-e2e` for advisory defect origins.
3. **Model choice is the user's decision (R7).** All live evidence comes from GPT-OSS-20B.
   The user decides when to change or compare models, and B7 doesn't wait on that. If the
   user selects Claude Haiku 5.5, measure its latency for its `requestTimeoutMs` first
   (B9, ADR 0030).
4. **Implement the approved Spec changes (25 October 2026), each with `/preflight`:**
   - first, B5's cross-kind restatement in the native duplicate rule, which is
     independent of the others (done: ADR 0035);
   - the configurable workflow budget at 125,000 tokens (B4), which gives the later
     changes room in loan-renewal's live runs (done, uncommitted: ADR 0037);
   - then B7's source-quoted claim wording, under one ADR amending §16 (done,
     uncommitted: ADR 0036). Its native list-item split was implemented and withdrawn.

   Quality over cost, but never waste (user, 25 October): token cost is not a reason to
   drop a check, and spending that buys no quality is removed at its owner.
5. **Then decide the open Spec failure classes:**
   - B2's finding-type accuracy and false assessments;
   - B4's experiment stops and qualified scope, before any baseline freeze;
   - B5's proposed single record collection with native acceptance-criterion coverage;
   - B9's open choices.
6. **Architecture, in ADR order and independent of 1–5.** Implement ADR 0030 (A1), as
   amended on 23 October, before adding operations for another workflow. Slices 1–3 are
   done; the catalogue deadline already made pre-24-October runs unreadable to replay
   tools, so W4 uses raw response bytes or newer captures. Adjudicate the existing v9
   runs before `request-model` lands if it advances the report contract.
   Convert `prepare-toolchain` (ADR 0031) and record its measure, convert startup
   (ADR 0032), then convert repairs (ADR 0033). Fold A4's closed reasons and A5's rule
   style into each conversion, and check whether a conversion absorbs W5's pairs.
7. **Separate work.** R2 (ADR 0025) is a required feature that hasn't started. Decide R1
   before promising stronger provenance. Freeze the Phase 2 baseline only after B4's
   budget and scope decision. B5's proposal replaces its A/C comparison. Gather R6
   evidence after B2's live effect is measured.

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
- **23 October 2026, ADR 0030 choices settled:** the user directed the best option for
  each derived choice (A1). ADR 0030 now keeps the kernel orchestrator and YAML release,
  removes provider token counting, moves the request deadline to each catalogue entry as
  `requestTimeoutMs`, and lets only `role: advisory` steps map `more` and `blocked`
  (renamed and made one-directional later the same day; see the next entry). Updated A1,
  A2, B9 and §6, the affected ADRs, design.md, contracts, features, diagram 16, the
  README and known-work. No code, workflow YAML or catalogue changed.
- **23 October 2026, ADR 0030 review fixes:** a contract review of the amendment found
  factual, pointer and wording defects. Fixed: Claude Haiku 5.5's interim 180,000 ms
  deadline, the count-path claim, unconditional retained-evidence breakage, ADR 0012's
  note, contract §9 in the amends list, ADR 0028's named clauses, the catalogue's count
  operations, the replay deadline, an oversized-deadline rejection and line wrapping.
- **23 October 2026, one-directional advisory check:** the review found that
  `assess-support` serves both the required pre-generation review and post-generation
  advice, so a two-directional `role: advisory` check would fail every run. The user
  directed "update documentations" with the one-directional form: a step marked
  `advisory: allowed` maps `more` and `blocked` and may carry both kinds of request, and
  only an advisory request at an unmarked step is rejected, at preparation, before any
  attempt. A second review confirmed it safe against the code. Its framing as two
  `request-model` contract variants was then confirmed (next entry). Updated ADR 0030,
  ADRs 0005 and 0023, design.md, contracts §§12, 28 and the operation catalogue, F0005,
  F0006, F0100, A1 and known-work. No code, workflow YAML or catalogue changed.
- **23 October 2026, shared contract-variant mechanism:** after comparing a shared
  variant mechanism, separate operations, a compiler special case and a union contract,
  the user directed "update the documentation around option 1". ADR 0030 builds one
  mechanism (complete closed variants, one closed selector parameter at compile time,
  per-variant admission, compiler and runner checks against the compiled variant), and
  ADR 0033 reuses it; this confirms ADR 0033's derived choice 1. Updated ADRs 0030, 0033
  and 0005, design.md, F0005, A1, W3 and known-work. No code, workflow YAML or catalogue
  changed.
- **23 October 2026, second review of ADR 0030:** a contract review found ADR 0030's
  selector sentence ("selects no … owner rule") contradicting ADR 0033's owner rules.
  Fixed: the selector grants no policy, scope or defect identity, and each operation's
  ADR owns any rule selection and run-time selector check. Also added optional selectors
  and per-outcome descriptors to the mechanism, registry-wide checks, compiled-graph and
  publication rechecks, testable acceptance cases, and a loss-localization case; updated
  ADRs 0005 and 0033, contract 28, F0005, known-work and a stale Z_FIX05 link. ADR 0033's
  derived choices 2–8 still await confirmation. No code, workflow YAML or catalogue
  changed.
- **23 October 2026, `zig build verify` restored after ADR 0029:** verify failed on `main`
  with 17 failing steps, all from the ADR 0029 change: the baseline harness still built a
  Region-only transport request, the rubric-evaluator smoke expected the error text from
  before `TEST_EVALUATION_FAMILY`, the example catalogue had no `family`, the packaging
  smoke's invalid-Region case used a Region ADR 0029 made valid, a capture test's legacy
  version edit changed the archive row length, and the compatibility test expected the
  E2E configuration to select Claude Haiku 5.5. The user chose Haiku via Bedrock for
  every E2E slot; the other fixes are test and fixture corrections.
- **23 October 2026, ADR 0030 slice 1 (`5ce2af4`, committed with the verify repair):** the
  freeze instrumentation and its baseline; A1 records it and the open points for slice 4.
  The user chose option (b) for the pre-call termination, cancellation and authorization
  failure baseline. Corrected §1, A6 and §6: the first 21 October pair ran on an
  unmodified committed build (`7a88804`).
- **24 October 2026, ADR 0030 slice 2:** provider token counting removed from code,
  tests, build steps and documentation; A1 records the scope, the kept persisted kind
  fields and the converted inference-then-authorization closure test.
- **24 October 2026, ADR 0030 slice 3:** the provider-operation deadline moved to each
  catalogue entry's `requestTimeoutMs`; A1 and B9 record the scope, versions, shipped
  values and the freeze recheck.
- **24 October 2026, Claude Haiku 5.5 route:** the first live Haiku runs on clean `cbabda6`
  (nine attempts, one call and 0 tokens each) all ended `authorization_denied` while the
  account's IAM policy and model access were set up. Runs 8 and 9 showed the AU
  cross-Region profile `au.anthropic.claude-haiku-5-5` routing to `ap-southeast-4`. For the
  user's Sydney-only requirement, `2014df4` pinned the in-Region ID
  `anthropic.claude-haiku-5-5`; run 10 also ended `authorization_denied` (Bedrock 403: "not
  available for this account"). The AWS model card (checked 24 October) lists Claude Haiku
  5.5 in `ap-southeast-2` only through the AU geo and global profiles. The user then chose
  the AU profile, accepting routing to `ap-southeast-4` and relaxing the Sydney-only
  requirement, and the pin was reverted (`7da8ef0`). Run 11, through the AU profile, got the
  same 403, so the denial is the account's access to the model (an AWS Marketplace
  subscription is the likely prerequisite), not the Region. The user then switched every
  E2E slot back to GPT-OSS-20B; ADR 0029 records both changes. All eleven attempts count
  as attempted workloads.
- **24 October 2026, GPT-OSS pair on `8a600d7`:** the first runs since ADR 0030 slices 1–3
  both published on an unmodified committed build: hello-world (24 calls, 63,402 tokens,
  advisory 89.29%, unchanged from 21 October) and loan-renewal (31 calls, 99,098 tokens,
  902 under budget, advisory 82.14%, unchanged from 21 October). §1 and A6 record the pair; neither run is
  adjudicated.
- **24 October 2026, loan-renewal principles:** loan-renewal copied hello-world's principles,
  whose "State Ownership: Keep no application state" made the policy review mark the
  stateful loan behaviour `conflicting` (four findings on `8a600d7`). By user direction the
  case now supplies its own project principles, `test/e2e/wf-002-loan-renewal/principles/`,
  for a "Library Lending" project: same seven files and `toolchain.yaml`, with domain-owned
  in-memory state, atomic operations and typed rejections, and no rule taken from the
  renewal story. Principles reach only the policy review, not generation. Loan-renewal
  principle findings before this change come from hello-world's principles.
- **24 October 2026, test performance P1 and P9 (recorded 25 October):** from the
  investigation note `improve_test_performance.md`:
  - `bf8a297` and `2bafdb0` implemented P1, the untraced leak-checking allocator;
  - `269410b` implemented P9, opt-in test-run reuse, which `verify` refuses.
  They were committed without the FIX05 record the note requires; Z_FIX05 §18 now holds
  it. The note's other proposals remain unadopted.
- **25 October 2026, B7 proposal:** by user direction, B7 records source-quoted claim
  wording as the recommended option, with the 24 October evidence that every later call
  received the source text and followed the weakened claim. It needs a decision and an
  ADR amending §16. §6 now records that model choice is the user's decision, and B7 no
  longer waits on a model comparison.
- **25 October 2026, B5 proposal:** by user direction, B5 records the recommended option.
  It is one complete record collection per feature, each record naming the claims it
  supports, with native coverage requiring every behavioural claim to be cited by an
  acceptance criterion or edge case. It replaces the A/C comparison, which can't
  discriminate while each case forms one group. It needs a decision and an ADR, and it
  depends on requirement-level claims (B7) and review headroom (B2/B4). §1 and §6 point
  to it.
- **25 October 2026, cross-kind duplicate proposal:** by user direction, B5 records the
  recommended option for repetition across record kinds. It widens the native
  `duplicate_record` rule to compare statement text across single-statement record kinds
  and against the user story, keeping its native delete, which makes no model call. It
  needs a decision and is independent of B7, B2 and B4. Known-work's "Record authoring
  duplicates" entry carries both B5 proposals.
- **25 October 2026, approvals:** the user approved three changes. None is implemented
  yet.
  - B5's cross-kind restatement in the native duplicate rule ("YES").
  - B7's source-quoted claim wording ("YES").
  - For B7's list-collapse half, "apply the best option", recorded as a native split of
    claims at top-level list-item boundaries. It adds no model call and builds on the
    quoted wording; ADR 0027's per-item chunking stays withdrawn.

  §1, §6 (a new step 4, "Implement the approved Spec changes") and known-work record
  them. B7's two changes share one ADR amending §16.
- **25 October 2026, budget and priority:** the user approved making the workflow token
  budget configurable and raising it to 125,000 (B4), instead of making source review
  optional. The priority is "quality over cost, but never waste": token cost is not a
  reason to drop a check, and spending that buys no quality is removed at its owner.
  - B4 records the change and its ADR design points.
  - B2 records that source review stays, and that its waste and accuracy remain open.
  - B5 and B7 now name the budget as their headroom.
  - §6 step 4 adds the budget to the approved changes, and step 5 keeps B4's experiment
    stops and qualified scope open.
- **25 October 2026, step 0 baseline on `269410b`:** both cases ran once on an unmodified
  build, as the reference for the approved changes (§6 step 4).
  - **Hello-world** published: 24 calls, 63,013 tokens, advisory 89.29%. Its text varied
    noticeably from `8a600d7` with nothing relevant changed, so later rounds need
    repetitions.
  - **Loan-renewal** failed `WorkflowTokenBudgetExceeded` at 109,327 tokens. A
    source-review runaway on `Renewal refused.` cost 19,404 tokens, the second on that
    subject (B9). Under the approved 125,000 budget it would have published.
  - Its own principles brought principle review to 19 `compatible` decisions, though the
    output wasn't admitted.

  Advisory analyses are in `evaluations/e2e/`.
- **25 October 2026, B5 cross-kind restatement implemented (ADR 0035):** the user's
  preflight decisions were to delete only covered restatements, leave uncovered ones, and
  keep the functional requirement (otherwise the earlier record).
  - **Code:** `restatement`/`restatesStory` in `specification_generation.zig`.
    Restatements run in the session consistency check after every same-kind check, with
    a closed `restatement` repair rule using the native delete.
  - **Tests:** two existing tests now give the deletable kinds their own wording. The
    R46 competing pair still blocks. The scripted complete story in the integration
    fixture gained leading words, so review-advice scenarios don't trip the delete. New
    tests cover the story, superset evidence, ordering and uncovered cases.
  - **Status:** `zig build verify` passes. The integration scenario for a records-batch
    delete remains a follow-up.
- **25 October 2026, B5 live pair on `47723fd`:** both cases published, at advisory 82.14%
  each.
  - **Hello-world:** 24 calls and 63,479 tokens. Its score fell from 89.29% because the
    story wrote "should output" and invented an entity.
  - **Loan-renewal:** 25 calls and 80,195 tokens. It used fewer review calls because the
    model wrote fewer records.
  - **ADR 0035 didn't fire.** Neither records call produced a restating business rule,
    assumption, non-goal, prohibition or user-visible outcome. The pair is therefore
    run-to-run variation, not evidence about B5. B5's effect needs repetitions that
    produce restatements.
  - **Persisting defects:**
    - obligation weakening in the story and entity: "may renew", "should output" (B7);
    - an entity that copies the story or is invented (outside ADR 0035; B6, R6);
    - a paragraph title;
    - no refusal acceptance criterion (B5 collection proposal).
- **25 October 2026, B7 implemented (ADR 0036):** the user directed "implement B7 with
  option 1". Claims are a category and admission-bounded line IDs; one pure function
  quotes their wording and, until its withdrawal below, split them at top-level list
  items. Claim-text and citation repair are deleted.
  - Implementation found and fixed two defects: the citation bound's scope at handoff,
    and the omission merge dropping split claims. A contract review then found four
    major issues and a second review four more. Claims now quote the cited source bytes
    as written, with list structure from one Markdown owner built once per source. The
    reader rejects C1 controls, and the split follows "one claim per item" when a
    heading is cited. The omission bound gained rejected cases. Re-quoting at readback
    stays open.
  - **Documents:** ADR 0036 and the design.md §32 row, ADR 0016's amended-by note,
    F0100 §§3.7–3.8, contracts §§12.7, 13, 16.3–16.4 and 22, text-field composition,
    diagrams 05 and 21, and known-work.
  - **Status:** uncommitted at the user's direction. Unit, integration, lint,
    architecture and full `verify` checks pass.
- **25 October 2026, B7 live pair on the uncommitted ADR 0036 tree:** by user direction,
  before deciding on the commit.
  - **Hello-world** published, advisory 82.14%, with a new escaped-backtick defect.
  - **Loan-renewal** ran out of budget after a runaway on a preserved-token subject.
    Its records now cover each requirement, but generation still weakens "must be able
    to renew".
  - The B7 block records the details.
- **25 October 2026, B7 kept and backtick fix:** the user asked whether to fix or
  abandon B7, and then directed "apply recommendations as per above". B7 is kept. ADR 0036
  Decision 6 makes admission drop the Markdown code delimiters directly around a
  recognised exact value. The text-field composition contract and the §32 row record
  it. The open items that affect no outcome stay open.
- **25 October 2026, second B7 live pair (with Decision 6):** by user direction.
  - **Hello-world** published at advisory 71.43%, with a critical failure from filler
    records; the backtick defect is fixed.
  - **Loan-renewal** failed on budget after a records runaway of 294 edge cases, a new
    B9 form.
  - The B7 block records the details.
- **25 October 2026, list-item split withdrawn:** the user directed "make the changes as
  suggested". Source quoting and Decision 6 stay; one proposal is one claim again, and the
  extraction `citations` guidance again asks for the complete claim. ADR 0036 Decision 3
  records the withdrawal and its evidence. Unit, integration, lint, architecture and full
  `verify` checks pass. The B7 block records the details.
- **25 October 2026, live pair after the split's withdrawal:** by user direction.
  Hello-world published at advisory 85.71% with no filler records; loan-renewal failed on
  budget after a 40-record batch with repeats. The B7 block records the details.
- **25 October 2026, B4 implemented (ADR 0037):** the user directed that the token cap
  be stored in and loaded from `.sddtoolkit.json`, at 125,000 for E2E. The budget is a
  required root `workflowTokenBudget`; policy profiles and compiled graphs no longer
  carry it. The B4 block records the details.
- **25 October 2026, live pair at the configured 125,000 budget:** by user direction.
  Both cases published at advisory 85.71%. The B4 block records the details.
