# FIX05 — Architecture review and consolidated open work

**Reviewed:** 17 October 2026, Australia/Melbourne, at `b2f10a3`.

**Status:** sole active fix record. It consolidates the open work of FIX01 (Spec
reliability backlog) and FIX04 (semantic-simplicity evaluation), which are deleted.
Their last text is at `b2f10a3` (`git show b2f10a3:fixes/FIX01.md`,
`git show b2f10a3:fixes/FIX04.md`). Former item IDs (FIX01 R1–R11, FIX04 F1–F13 and
Phases 0–6) are kept for traceability. Completed work and dated evidence remain in
[Z_FIX01](Z_FIX01.md) and [Z_FIX02](Z_FIX02.md).

Unless a dated user approval is recorded below, items are findings or proposals.
Items marked **Decision** amend an accepted ADR, contract or scope and need
explicit user approval first. A proposal authorizes no code change, live call or
E2E run. The governing design remains **Proposed design**.

**Evidence:** the code at `b2f10a3`, `zig build code-heuristics`, git history, the
run records in Z_FIX02 and the retained 16 October 22:00 run. No tests or live calls
were run for this review.

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

| Measure | Value |
| --- | --- |
| Hello-world reference | 189 bytes, three requirements ([stories.md](../test/e2e/wf-001-hello-world/reference/stories.md)) |
| Full-workflow diagnostics, 16 October (AEDT) | Eight runs on GPT-OSS-20B: two loan-renewal and six hello-world (F9, F11–F13 and 22:00); none published a specification |
| Most fully measured run (09:18) | 41 sends and 101,134 tokens; review 29 sends and 77%; input tokens 93% ([cost investigation](Z_FIX02.md#545-phase-2-review-and-repair-cost-investigation)) |
| First run passing every native generation check (20:33) | 42 calls and 100,884 tokens; budget exceeded during re-review; review 75.6% |
| Latest retained run (22:00, modified `3303498`) | `RetryLimitExhausted` at brief generation after 10 calls and 13,797 tokens: `embedded_insertion_syntax`, and a `{"token{` envelope prefix on call 2 |
| Code | 63,889 production and 82,792 test lines, for one of four planned workflows |
| Spec workflow | 1,168 YAML lines; 282 steps in 33 graphs (205 operation nodes, 77 subgraph calls); 185 distinct operations; 18 model-request sites (§4) |
| History | 199 commits in 8 weeks; 297,901 Zig lines inserted and 148,709 surviving; 22 ADRs between 26 August and 6 October |

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

**Decision** (amends ADRs 0005 and 0012): make one model request a single registered
operation. The YAML still chooses the slot, prompt, schema, context, retry limit and
outcome transitions. The engine owns accounting, authorization, invocation, admission
and lifecycle internally. This keeps visible what is asked and removes kernel
mechanics from project-authored graphs.

The workflow-authoring simplification (former FIX03 Phase 8) and the
architecture-wide responsibility audit (former FIX01 §8) belong to this decision. A
supported no-consolidation decision remains a valid outcome.

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

**Decision** (node granularity under §§5–6): let one registered operation own a
cohesive stage, such as extraction together with its own admission. Keep single
responsibility at the module and function level. Measure the files touched per
change before and after.

### A3. Type-erased child bindings hide data flow

Bootstrap configuration reading is 29 parameterless steps behind a `*anyopaque`
vtable ([bootstrap_child_bindings.zig](../src/application/bootstrap_child_bindings.zig#L10)).
Each step receives only the erased context and returns an outcome, so data moves
between steps through hidden mutable state. Production code has 386 `anyopaque` and
295 `@ptrCast`. The compiler cannot check the wiring where wiring errors happen, and
AGENTS.md lists unbounded `anyopaque` at boundaries as a prohibited shortcut.

**Proposal:** where an orchestrator's sequence is fixed, as in bootstrap and feature
logging, call typed steps with explicit inputs and outputs. Keep spy tests through a
typed interface. This changes the §14 orchestrator pattern, so confirm its scope
first.

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

### A6. Contracts change faster than evidence accumulates

- There were 22 ADRs between 26 August and 6 October.
- Design and fix records saw 139,051 lines written and 91,493 deleted.
- Phases 1A.2 and 1A.3 were each opened by a single hello-world run, while
  near-identical requests produced opposite failures (F13).

AGENTS.md requires every fix at the shared owning contract, with no backward
compatibility, so each amendment becomes a large cross-cutting diff.

**Proposal:** apply the evidence rules in §7 to every contract change.

**Decision** (scope): add no contracts for Plan, Tasks or Implement until Specify
publishes on both development cases.

## 3. Why runs are brittle

### B1. A long fail-closed chain of model judgments

Publication requires the whole workflow to pass every validator across 40 or more
sends. As an illustration, not a measurement: if each call produced acceptable
output 97% of the time after its retries, 41 calls would succeed together about 29%
of the time; at 95%, about 12%. Splitting work into more calls lengthens the chain
unless each call's success rate rises enough to compensate (former F5 and F7).

**Proposal:** treat call count per feature as a reliability cost. B2–B5 each shorten
the chain, as do the W1, W3 and W4 workflow changes (§4). Judge progress by useful
completion per attempted workload (§7), never by
per-call admission.

### B2. Review dominates cost and drives harmful repair

Evidence from former F9 and F13, and FIX01 R5 and R6:

- **Cost.** Review took 29 sends and 77% of tokens at 09:18, and 29 sends and 76,224
  tokens (75.6%) at 20:33. Four of the five runs that reached review stopped on the
  budget.
- **Task shape.** The same 20B model judges its own output, mostly one field per
  call (21 singleton `finding` sends at 09:18). It must choose among seven finding
  types under nested conditional rules
  ([support.prompt.md](../design/workflows/spec/support.prompt.md),
  [contract](../src/domain/specification_support.zig#L13)).
- **Wrong finding types.** Every reviewed run had them. Omissions were reported for
  invented or unsupported content, and all five 08:09 loss comparisons returned
  `lost` for those non-obligations.
- **Harmful repair.** At 20:33 a repair wrote "The application must start
  successfully" into an acceptance criterion's Given, so the precondition assumed the
  result under test, and re-review accepted it.
- **Panel result.** The 30-call actual source-review panel passed 15/26 faithful
  omission handoffs, 2/2 supported controls and 0/2 genuine-gap controls
  ([results](../test/calibration/source-loss-attribution/bound-preservation/citation-completeness/handoff-results.md)).

**Decision** (amends §17.3 and §22):

1. Review a whole unit or collection per call.
2. A finding that deterministic evidence doesn't corroborate becomes a note, a
   clarification or an input to regenerating the unit. It never triggers an
   automatic content repair.
3. Optionally assign review to a separately configured assessment model
   (`models.slots.assessment`; former FIX02 and FIX03 Phase 9). This needs the
   proposed ADR 0021 and configuration amendment, and qualifying it live needs a
   changed live-test policy.

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

### B3. Exact-value bookkeeping is left to the model

**Approval — 17 October 2026:** the user approved B3, first settling the offline
requirement-binding and punctuation rules, with B2 and W1 to be decided separately.
The user then explicitly approved both concrete choices from the
[offline policy comparison](../test/calibration/exact-value-recognition/README.md#b3-policy-comparison--17-october-2026):

1. Recognize current native request-eligible exact occurrences even when their
   claim IDs are outside selected support `S`; derive `E` while preserving `S`.
2. Use contextual complete-value delimiters: actual field edges, Unicode
   whitespace, balanced enclosing wrappers and terminal prose punctuation before
   a delimiter. A reference-adjacent literal-run edge is not a field edge.

The coordinated native implementation is complete and verified offline. Governing
amendments are recorded in [ADR 0020](../design/decisions/0020-derived-exact-reference-lineage.md#native-exact-value-recognition-amendment--approved-17-october-2026)
and the [composition contract](../design/contracts/text-field-composition.md#native-exact-values--approved-17-october-2026).

**Offline completion checks — 17 October 2026:** the final ladder passed in order:

```sh
zig build test-exact-value-admission test-exact-value-replay test-model-request-preparation test-model-request-workflow test-model-envelope test-model-candidate-json test-specification-generation test-workflow-repair-retry -j1 --summary all
zig build test-architecture -j1 --summary all
zig build verify -j1 --summary all
```

The targeted run passed **26/26 steps and 1,151/1,151 tests**; architecture passed
**3/3 steps and 151/151 tests**; full verification passed **163/163 steps and
1,819/1,819 tests**, including integration, schema and clean native packaging
smoke checks. `git diff HEAD --check` also passed. Logs are
`.zig-cache/b3-final-targeted.log`, `.zig-cache/b3-final-architecture.log` and
`.zig-cache/b3-final-verify.log`.

**Production-admission replay:** `zig build test-exact-value-admission -j1 --summary all`
repeats the integration check and writes
`.zig-cache/exact-value-production-admission/report.json` (SHA-256
`5e07666a28f749784c70dd6ca694e2c1736f88332af6067f4cdb0a2869c0640a`).
The [replay record](../test/calibration/exact-value-recognition/README.md#current-production-admission-replay--17-october-2026)
documents the immutable raw bytes and explicitly fresh, scripted native context:

- 16:20 insertion-only title: typed `prohibited_exact` rejection.
- 18:58 collapsed records: typed `reference_only` rejections.
- 20:22 prose values: admitted with unchanged `S`, one added exact claim and two
  behavioral exact-coverage targets; canonical stored validation also passes.
- 22:00 insertion syntax in prose: typed `embedded_insertion_syntax` rejection.
- An unrelated, explicitly scripted loan control admits through the same native
  path. It is not a live or retained loan-run result.

Admission escape is **zero among the four actually replayed captures**. The
20:33 run's raw capture and its inventoried mirrors could not be found; the report
retains its exact execution identity as unavailable, not a fifth replay success.
It introduces no distinct B3 admission class beyond the admitted-generation
control, but its harmful review/repair and later budget failure are not reproduced
or claimed resolved. Historical descriptions remain historical observations;
their metadata is not promoted into current request authority.

**Independent review:** the `contract-reviewer` reviewed the complete B3 diff and
the production-admission additions. No contract findings remain. Its reported
test-helper diagnostic-path lifetime defect was fixed before the final checks.

The shared recognizer, native request scope, response composition, value and
membership repair bounds, progress comparison and stored readback are integrated.
Completed/pending state now use `specification-state/v15`; current diagnostic
requests use `model-request-debug/v6`. Superseded contracts reject; frozen older
captures remain historical observations and cannot acquire current authority.

No live fidelity, cost or publication improvement is claimed. The Phase 1A.3 live
gate remains open and needs separate approval for each explicit E2E case. B2 and W1
are outside this implementation; the user's subsequent follow-on instruction is
recorded in §6. It supplies no per-run approval for live calls.

**Diagnosis before this cutover:** the model had to splice `exact_copy` insertions into its prose, and native coverage
credits only an insertion ([coverage](../src/domain/specification_coverage.zig#L77)).
A missing insertion has no repair route
([coverage repair](../src/domain/specification_coverage_repair.zig#L60)).

Runs have failed in both directions:

- values made only of insertions, or insertion syntax typed into prose (F10–F12, and
  again at 22:00 as `embedded_insertion_syntax`);
- values typed out with no insertion (F13, which blocked at coverage after 14 calls).

The presentation contradicts the rule: insertions "may supplement" prose and exact
copies "may carry" the obligation
([text_field_policy.zig](../src/domain/text_field_policy.zig#L75),
[:105](../src/domain/text_field_policy.zig#L105)), while coverage requires one.
Near-identical requests produced opposite failures. This contradicts the
[intent](../design/intent.md) that bookkeeping belongs to deterministic code. It also
supersedes the former R6 item 4 candidate of a simpler shared business-value
representation.

**Approved decision** (amends the [composition contract](../design/contracts/text-field-composition.md),
§7.1 and ADR 0020): recognise exact values natively.

- The model writes plain prose.
- Native code recognizes raw exact bytes before NFC in the current snapshot/request
  eligible occurrence scope, using the approved contextual delimiter policy.
  Competing lineages or overlapping eligible spans reject the whole field.
- Canonical exact nodes, field roles and repair evidence bounds remain; `S` is
  unchanged and recognized `E` contributes through the existing lineage owner.
- `exact_copy` leaves model-facing types, codecs and schemas.

The [offline prototype](../test/calibration/exact-value-recognition/README.md) replays
every retained capture with no model calls
([evidence](Z_FIX02.md#546-offline-native-exact-value-recognition-prototype)). Its
selected-membership and whole-word observations remain dated historical evidence;
the approved native scope and delimiter policies supersede them for production.

Open gates of the former Phases 1A.2 and 1A.3
([approved plan](Z_FIX02.md#phase-1a3-plan-and-decisions-as-approved)):

- The approved representation change replaces Phase 1A.3 steps 2–3: the
  21-send [attribution panel](../test/calibration/insertion-presentation/README.md)
  and the presentation rewording. Its implementation must address the mechanical
  coverage block without claiming semantic fulfillment.
- Close the live gate on a committed build with one separately
  approved hello-world diagnostic and one loan-renewal diagnostic.
  - Each must admit records with prose, or end in a typed composition failure after
    bounded protocol correction, with admission escape measured zero.
  - This also closes Phase 1A.2's gate.
  - Loan-renewal has not run on any build since Phase 1A.
  - The two F13 hello-world runs count only if no further presentation or
    representation change follows.

### B4. Fixed per-call overhead exhausts a compiled budget

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

### B5. Authoring follows mechanical source groups

Evidence from former F1, F9 and F13:

- Each record batch re-authors the whole feature, which produced competing or
  duplicate records in four runs.
- The group holding only a preserved value gets its own batch.
- One assignment can still require interpreting obligations, choosing record
  families, preserving conditions, building scenarios and entities, and deciding
  whether uncertainty blocks drafting.
- Six model requests precede authoring even on a three-line source.

**Proposal:** compare current per-group records (A) with one complete record
collection (C). Add a purpose-only acceptance-criterion diagnostic (B) or per-family
collections (D) only where measured failures justify them. Run it after B2 and B3,
which change every arm and dominate cost.

| Former phase | Status |
| --- | --- |
| 0 Evaluation protocol | Complete offline: [protocol, cases, specimens and scoring](../test/calibration/semantic-simplicity/README.md) |
| 1 Compatible execution | Live gate passed for the observed first request only ([record](Z_FIX02.md#phase-1-implementation-and-live-gate)) |
| 2 Baseline | [Harness](../test/harness/baseline/cli.zig) implemented; not frozen; needs B4's decision, B3's gate and a committed build |
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

- Extraction has merged hello-world's three requirements into one claim in every
  sample since Phase 1A.
- The GPT-OSS envelope-prefix malformation (`{"token{`) recurs. It is counted, not
  normalized.
- Entity applicability was marked required for a feature with no business data, and
  the entity-name exception then admitted an insertion-only name. No native rule can
  judge applicability.

Measure each as its own class in the baseline. Don't widen the normalizer or narrow
the entity-name exception without a decision.

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
  covers the decision-free preparation and publication steps.
- W1, W3 and W4 also reduce model calls; W2 and W5 only reduce implementation effort.
- Keep typed outcomes, closed admission, all-or-nothing publication and
  clarification persistence as they are.

### W1. Review can restart the whole pipeline

When review attributes a loss upstream, [`review`](../design/workflows/spec.workflow.yaml#L151)
routes `more` to [`repair-upstream`](../design/workflows/spec.workflow.yaml#L888).
Its merges invalidate the whole generation session and its content
([`specification_dependents`](../src/domain/source_omission.zig#L328)). The run then
rebuilds the affected upstream stage, regenerates every unit and reviews everything
again, so one finding, possibly a wrong one, can repeat nearly the whole run.

The 10 October 14:24 run did exactly this (former FIX01 R6 evidence, at `b2f10a3`):

- its upstream repair re-inserted behaviour that had already been extracted;
- it invalidated dependent work and recreated the same description defect;
- it ended `workflow_invalid` after 44 calls and 77,818 tokens.

**Decision** (amends §22): a post-generation upstream finding ends as a typed outcome
that names the producer and the evidence, or becomes a clarification. It never
automatically rebuilds an upstream stage and regenerates every unit. Pre-generation
source repair discards no generated content, so it is unaffected. This complements
B2, under which uncorroborated findings never repair, and narrows R6.

### W2. The upstream-repair path exists twice

The top-level steps from
[`repair-source` to `merge-source-reconciliation`](../design/workflows/spec.workflow.yaml#L117)
duplicate the [`repair-upstream`](../design/workflows/spec.workflow.yaml#L888)
subgraph. They use the same authorization, the same repair subgraphs and the same
transitions.

The merge operations also come in pairs, with identical bodies (code-heuristics
groups 4 and 5):

- [`merge-source-extraction-repair`](../src/actions/reference/merge_source_extraction_repair.zig)
  and [`merge-upstream-extraction-repair`](../src/actions/reference/merge_upstream_extraction_repair.zig);
- their reconciliation counterparts.

Each pair differs only in its static invalidation set. The upstream variant adds
`specification_dependents`, which don't exist before generation.

**Proposal** (no ADR change expected): call one subgraph from both places, with one
merge per producer that declares the union. This removes five YAML steps and two
operations, along with their bindings, registry entries and tests.

First confirm that runner delta validation accepts invalidating data that isn't
present yet. If it doesn't, that rule is what forces the duplication; record it
under A2.

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

**Decision** (under A2, after A1): give each owning stage one repair operation that
performs its authorization, input, request, parse and merge internally. Keep every
owner's authorization and merge rules. The YAML keeps only the outcome edges.

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
rules, and count extraction's requirement merging (B6) as its own class.

### W5. Identical sibling steps

Two pairs of steps have the same target, parameters and transitions:

- [`source-gaps`](../design/workflows/spec.workflow.yaml#L164) and
  [`candidate-gaps`](../design/workflows/spec.workflow.yaml#L171);
- [`finish-native`](../design/workflows/spec.workflow.yaml#L352) and
  [`finish-model`](../design/workflows/spec.workflow.yaml#L355).

**Proposal** (no ADR change): merge each pair. Other steps already join several paths,
for example `validate-dispositions`. The incoming paths here carry different data,
though, so first confirm that the workflow compiler's data-flow checking accepts
these two joins.

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

**Decision first:** the trusted authentication source and the persistence model
(former FIX03 Phase 7: 7A decisions, 7B source-driven resolution, 7C fresh answers).
Don't treat a closed form as authenticated or fabricate reference citations.

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
them if B2 is approved, because uncorroborated findings would then no longer drive
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
labels kept outside prompts and separate development and held-out families. The
live-test policy permits only GPT-OSS-20B, so cross-model evidence needs a changed
scope.

### R8. Development acceptance policy

**Decision required.** [E2E command success](../test/harness/e2e/contracts.zig)
includes completed evaluation and `awaiting_clarification`. The rubric supports an
aggregate threshold, not a critical-error veto, and cases have no
expected-terminal-outcome field.

Define expected terminal outcomes, critical failures, aggregate thresholds and
uncertainty before adding any automated gate. Keep one development evaluation policy
owner, separate from workflow authority.

The [whole-spec rubric calibration](../test/integration/fixtures/wf-001-hello-world/node-vitest/calibration/README.md)
is unfinished: its seven specimens, including `faithful-a/b`, omit the UTC
requirement. Refresh them and obtain human-reviewed labels before any
judge-acceptance claim.

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
- **Direct Anthropic provider.** [claude_connector.md](claude_connector.md) remains an
  unaccepted proposal. It needs an ADR, its §10 decisions and a changed live-test
  policy.
- Historical optional provider, reasoning-setting and principle-passage experiments
  are not current tasks.

## 6. Recommended order

**User-directed sequence — 17 October 2026:** the latest instruction supersedes
the earlier proposed order for B3, B2, W1 and W2:

1. Finish B3 offline: targeted tests, architecture checks, full verification and
   retained-capture replay through production admission. Record admitted or typed
   failed outcomes and admission escape. Obtain the `contract-reviewer` review,
   then commit. This establishes mechanics, not semantic improvement.
2. On that committed build, run one hello-world and one loan-renewal diagnostic,
   each only after its own explicit billed-run approval. Preserve generation
   failure as a baseline result under §7; do not open another rewording phase.
3. Decide and implement B2 and W1 together after those diagnostics: review findings
   without deterministic corroboration remain advisory, and post-generation
   attribution upstream ends as a typed outcome or clarification, never an
   automatic rebuild. Include W2 by deleting the unused post-generation upstream
   path and merge variants. Add A4 rejection reasons only if debugging needs them.
4. Rerun the same two separately approved diagnostics, measuring review's share of
   cost and finding-type accuracy. Governing amendments and their tests accompany
   the B2/W1 implementation; they are not part of the B3 change.

The remaining recommendations below are proposals, not additional authorization:

1. Consider A4's broader evidence gaps and W5's identical sibling steps separately
   from the debugging-only A4 scope above.
2. B4 remains a separate budget/scope decision.
3. Decide A1–A3, W3 and A6's scope freeze before starting Plan. Implement A1 before
   adding operations for another workflow.
4. Freeze the Phase 2 baseline under B4's decision. Measure W4 on retained captures,
   and run B5's A/C comparison only if generation-boundary failures remain.
5. Treat R2 as a separate required feature. Decide R1 and R8 before promising stronger
   provenance or automated quality gates. Gather R6 and R7 evidence after B2.

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
  second model or a weaker admission rule.
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

- **17 October 2026:** this review was written, and FIX01 (from 11 October) and FIX04
  (from 15 October) were consolidated here and deleted. The Spec workflow
  simplification review (§4) was added the same day, and §1's subgraph-call count was
  corrected from 78 to 77; a step named `call` had been counted as one.
- **Not carried forward:**
  - completed-execution narratives, already in Z_FIX01 and Z_FIX02;
  - the detailed FIX04 Phase 0–6 rollout text; the protocol and operator guide are
    in `test/calibration/semantic-simplicity/`;
  - superseded Luna-target research;
  - historical F1–F8 analysis, kept here only as the B5 constraints.
- **Retrieving the full text:** both deleted records remain in git at `b2f10a3`.
