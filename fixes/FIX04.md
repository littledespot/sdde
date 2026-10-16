# FIX04 — Critical review of semantic simplicity and generation feasibility

**Reviewed:** 15 October 2026, Australia/Melbourne. **Realigned:** 16 October 2026.

This review evaluates the supplied recommendations: retain single responsibility
for software, make model assignments semantically simpler, keep related meaning
together, and leave bookkeeping and authority with deterministic code. Its question
is whether a semantically simpler generation assignment improves
**source-faithful complete specification generation** by the selected small model.
It compares the current per-group record authoring (A) with one complete record
collection (C) first, and considers a purpose split (B) or per-family collections
(D) only where measured failures justify them (§5.2). Generation quality is the
primary outcome. An improved reviewer alone does not satisfy it, and a broken
reviewer can prevent good generation from completing (F9).

This document holds the findings, the feasibility assessment, the experiment design
and its evidence gates. It is not a progress log: completed implementation, live-run
records and verification are in [Z_FIX02](Z_FIX02.md#5-fix04--completed-evaluation-foundation-compatibility-and-admission-work-1516-october-2026), and [FIX01](FIX01.md)
remains the active implementation backlog under the
[fix-record convention](README.md). The user has authorized a larger change if
necessary and requested its steps and supporting research. Section 5 therefore
describes the complete change surface; size alone is not a reason to stop or request
the same authorization again. That authorization does not select an experimental
winner, authorize a live dispatch or accept the overall **Proposed design**.

**Selected model.** Live tests use **Bedrock GPT-OSS-20B**: `aws-bedrock /
openai.gpt-oss-20b-1:0 / ap-southeast-2`, Converse, native JSON Schema, explicit
low reasoning, engine-fixed temperature `0.1` and 16,384 requested output tokens.
The user selected it on 16 October, replacing the review's original
current-generation Luna target, which was never available to the test account.
The retained 15 October Phase 0 and 1 reports keep their historical Luna context and
do not qualify this binding. Historical GPT-OSS panels are same-model evidence, but
they ran under superseded contracts and codecs: they supply regression cases and
plausible failure classes, not the current defect rate (F7).

**Status — 16 October 2026.**

| Step | Status | Record |
| --- | --- | --- |
| Phase 0 — evaluation protocol | Complete offline, 15 October | [Z_FIX02](Z_FIX02.md#phase-0-implementation) |
| Phase 1 — compatible execution | Offline implementation complete; bounded live gate passed for the observed first request only | [Z_FIX02](Z_FIX02.md#phase-1-implementation-and-live-gate) |
| Phase 1A — composition admission | Implemented and committed (`bfec3d7`); offline gate passed; enforcement confirmed live | [Z_FIX02](Z_FIX02.md#phase-1a-plan-decisions-and-results) |
| Phase 1A.2 — presentation from the field registry | Implemented and committed (`2e64a31`); live gate open | [Z_FIX02](Z_FIX02.md#phase-1a2-plan-decisions-and-results) |
| Phase 1A.3 — composition correction at admission | Routing and attribution preparation implemented and committed (`6676ad8`); attribution sends, presentation correction and committed-build diagnostics pending | [Z_FIX02](Z_FIX02.md#phase-1a3-plan-and-decisions-as-approved) |
| Budget and scope decision (§5.5) | Required now; feasibility is `insufficient` | [Z_FIX02](Z_FIX02.md#545-phase-2-review-and-repair-cost-investigation) |
| Phase 2 — baseline | Harness implemented; baseline not frozen | [Z_FIX02](Z_FIX02.md#phase-2-harness-implementation) |
| Phases 3–6 — A/C comparison to adoption | Not started | — |

Five full-workflow development diagnostics ran on 16 October, two on loan-renewal
and three on hello-world. None published a specification or ran rubric evaluation;
F9–F12 record what they show. No semantic benefit, reduced brittleness or useful
publication is claimed. §1.1 sets the path from here to the A/C comparison.
Findings were first reviewed at `5816d9bed631acabcb256025e911bb565b8f9771`; each live
report records its exact source identity.

## 1. Assessment

**Retain semantic simplicity as a design criterion, but do not implement the
original AC-decomposition proposal as a production change yet.** The selected
GPT-OSS-20B binding passed its first-request compatibility check (Phase 1), so the
existing debugger can support a bounded comparison without first redesigning
generation. A production replacement requires unresolved
assignment, applicability, assembly and repair contracts, and its benefit for the
selected model remains unproven. Start by comparing
complete current output with whole-collection authoring; use a narrower purpose
diagnostic if mixed-purpose errors remain. Do not default to one call per family.

The 16 October full-workflow diagnostics add a second constraint (F9). Even when
generation succeeds, source review consumed three-quarters of the workflow's tokens,
misclassified every omission it reported, and exhausted the compiled budget before
finishing on a five-requirement feature. A generation-only improvement therefore
cannot produce useful completions until review cost and diagnosis quality are
measured. The full-workflow budget must also be reconciled with the protocol's
experiment limits before Phase 2 can be approved.

A third constraint comes before both (F10). In every run that reached generation,
native admission accepted model text whose composition cannot express its field's
purpose: values made only of exact-copy insertions, and insertion syntax typed
inside prose. Review then became the first detector of a structurally detectable
defect, misdiagnosed it, and drove a no-progress repair. This is a shared
representation and admission gap, not a record-authoring boundary, so the A/C
comparison cannot address it and would inherit it. Phases 1A to 1A.3 close it at
the shared owners, so that every arm runs under the same admission contract; their
remaining live checks are the last prerequisite before the baseline (§1.1).

A small JSON result, one action responsibility and a simple semantic assignment
are different properties. A concrete design concern is record generation: one
source-group assignment can still require interpreting obligations, choosing
record families, preserving conditions, constructing scenarios and entities, and
deciding whether uncertainty prevents drafting.

The evidence supports investigating that combined assignment. It does **not** yet
establish that decomposition caused better SDDE output, that smaller calls are
always better, or that further splitting will overcome the selected model's
semantic limitations. Neither the inspected research nor the 16 October
diagnostics resolve which decomposition, if any, improves this workload. Section 4 replaces the initial
experiment recommendation with a feasibility assessment; §5 selects a staged
comparison, outlines the larger change and defines testable phase gates for
meaningful improvement and reduced brittleness.

The material corrections to the initial review are:

- No frozen v14 baseline exists yet. The 16 October diagnostics show that the
  per-group record failure class recurs on the selected binding (F9), but one case
  and two runs supply no defect rate; historical counts cannot justify immediate
  redesign.
- Not every observed generation failure is a semantic assignment problem. The
  insertion-only and wire-syntax values in F10 are structurally detectable, and the
  design's own intent already says that a reference alone does not describe behavior.
  The gap is in enforcement ownership, and closing it is a prerequisite to the
  comparison rather than one of its candidates.
- At review time, the requested Luna cohort was not available through a
  configuration switch alone; it later proved unavailable to the test account. Any
  model change still needs trusted registration, compatible provider support and a
  fresh capture; old replay parents cannot be retargeted.
- Modified diagnostic replay already permits changing a request's task/schema.
  Production assignment authority is needed for adoption, not for forming every
  experimental question.
- Diagnostic receipts cannot be imported into actual workflow review/repair as
  authoritative producer evidence.
- AC quality, AC coverage, complete mixed-record coverage and full workflow
  success need different denominators and applicability judgments.
- FIX03's earlier investigation order is a recommendation among unselected
  experiments, not an accepted architectural constraint.

| Recommendation | Review finding |
| --- | --- |
| Retain single responsibility; add semantic simplicity | Supported. Treat semantic simplicity as an assignment-design and evaluation criterion. Much of its intent already appears in the governing baseline. |
| Define the exact judgment before designing the action | Supported, with a prerequisite: establish who supplies that judgment's source-backed premise and how its completeness is assessed. |
| Separate support, completeness and coverage | Supported. Current contracts already distinguish these duties; qualify the model's compliance instead of assuming the separation is absent. |
| Keep conditions, exceptions and outcomes together | Supported. Complete AC context and batched field review already exist. Neither implies reliable field-role judgment. |
| Reuse actions through the generic runner | Supported within registered typed contracts. Generic request transport does not supply new semantic assignment, repair or coverage authority. |
| Expect gains from reducing mixed decisions | A credible hypothesis, especially for generation. Require a fresh baseline on the selected binding and current contract; historical results under superseded contracts cannot select this design. |
| Begin with one failing assignment | Supported. Prioritize one generation failure class, use unrelated controls, and distinguish a component capability result from a replacement for the complete workflow. |

The practical objective should be **more source-faithful, usable generated content
per complete assigned duty**, with fewer unsupported additions and harmful repairs.
Lower call counts, more populated fields and higher schema-admission rates are
secondary observations.

### 1.1 Path to the A/C comparison and alignment safeguards

On 16 October the work ran through three prerequisite sub-phases, 1A, 1A.2 and
1A.3, each opened by the latest live diagnostic (F10–F12). Each was justified: a
known enforcement gap would be measured as a generation result, and closing it later
would leave the arms under different contracts. But the last two were each opened by
a single hello-world run, and the A/C comparison has not started. These safeguards
keep the remaining work on this review's question.

1. **Phase 1A.3 is the last prerequisite sub-phase.** After its remaining live
   items, a further composition failure opens a new prerequisite only if it shows an
   engine defect: a value violating a declared native rule escaped admission, or the
   engine's own schema, guidance or correction presentation contradicts the admission
   rule. A model that keeps failing under a coherent contract is a baseline result.
   Phase 2 measures it as first-pass fidelity, mechanical enforcement and admission
   escape, and the A/C comparison then measures whether either assignment reduces it.
2. **Decide prerequisites on more than one case.** Hello-world has three short
   requirements and one preserved token, so it cannot show whether a presentation
   rule generalizes. A further presentation or contract decision needs evidence from
   at least two unrelated development cases, starting with the hello-world and
   loan-renewal diagnostics that Phase 1A.3's exit gate requires. Its rationale must
   not depend on one case's literal or field.
3. **Never tune on qualification cases.** Prerequisite diagnostics use development
   cases or retained captures only. The sixteen reserved qualification features stay
   unseen until Phase 5 (§5.5, Phase 2).
4. **A model limitation is a valid outcome.** If the selected model cannot author
   composition-valid records under a coherent contract, report that limit of the
   tested request/model combination (§4.8). Do not answer it with field-specific
   rules, sampling changes, extra repair attempts, a second model or a weaker
   admission rule.
5. **Make the budget and scope decision now, not after Phase 1A.3.** It does not
   depend on Phase 1A.3's outcome. In the most fully measured diagnostic, extraction
   and generation alone used 18,818 tokens and 11 sends. The experiment-wide stops
   allow, on average, only 3,968–5,556 tokens and 1.98–2.78 sends per workload across
   the declared 360–504 workloads, before any review. The decision belongs to the
   user, its options are listed in §5.5, and it must be recorded before the Phase 2
   freeze.
6. **Work on review and repair cost in parallel, under its own owners.** Review used
   77% of the tokens in that diagnostic (F9). The source-review omission contract, the
   repair projection and any review batching are FIX01 R5 and R6 work, with their own
   qualification. They need not wait for generation work, and generation changes
   must not compensate for them.
7. **Keep A versus C the primary question.** A new item belongs on this plan's
   critical path only if it states how it makes A and C measurable under one
   contract. Otherwise it belongs in FIX01.

**Sequence from here:**

1. **Close Phase 1A.3** (§5.6): run the 21 attribution sends after separate
   approval; apply the presentation correction they support, or record a decision
   that none is needed; commit; then run one hello-world and one loan-renewal
   diagnostic on that committed build, each separately approved. This also closes
   Phase 1A.2's live gate.
2. **In parallel, now:** the budget and scope decision, and the review and repair
   contract work in FIX01 R5 and R6.
3. **Freeze the Phase 2 baseline** on a committed build with the recorded budget
   decision and sufficient cost evidence, then measure it on the development panel.
4. **Run Phase 3's A/C comparison**, then Phases 4–6 as their gates allow.

## 2. Authority and evidence boundaries

The governing review route is [design §§1, 3, 4, 30 and 31](../design/design.md),
particularly invariants 1, 6–9, 19–23, 24–30 and 32, and acceptance criteria 5–7,
12, 35–40. Focused contracts are [§12](../design/contracts/12-model-boundary.md),
[§17](../design/contracts/17-specify.md), [§21](../design/contracts/21-validation.md)
and [§22](../design/contracts/22-repair.md).

Those sources already require bounded nano-class assignments, original-source
authority, closed candidate admission, explicit failure, engine-owned identities
and publication, and a distinction between semantic assessment and deterministic
proof. Accepted ADRs [0012](../design/decisions/0012-workflow-owned-model-request.md),
[0016](../design/decisions/0016-configured-json-response-composition.md),
[0020](../design/decisions/0020-derived-exact-reference-lineage.md),
[0021](../design/decisions/0021-optional-source-preservation-review.md) and
[0022](../design/decisions/0022-native-reference-phase-handoffs.md) constrain reuse,
assembly, evidence, review and native handoffs.

Evidence classes in this report are deliberately separate:

- **Current contract/code:** what the inspected checkout implements or requires.
- **Historical live observations:** actual model outputs under their captured
  settings and contracts, including rejected and withdrawn candidates. Retained
  solely to audit prior findings and identify regression cases, not to infer current
  model capability or select a decomposition.
- **Offline evidence:** construction, schema, identity, routing and admission
  checks; these do not establish semantic quality.
- **Proposed experiment/design:** a hypothesis and its qualification requirements.
  The user's larger-change authorization does not itself select an experimental
  winner or authorize a bounded live dispatch/E2E run.

The supplied GitHub link pins FIX03 at `fa25102…`. Web retrieval of that snapshot
failed, and that Git object is unavailable locally. This review uses the current
local FIX03 and its retained evidence, not an asserted byte-identical historical
snapshot. Later delivery records matter: the 14 October amendment introduces
`candidate_invalid`, plain-string/explicit-composition model text, native structural
assembly facts and state v14. It also explicitly leaves authoring-boundary
experiments unqualified. See [FIX03's amendment](archive/FIX03.md#L1894) and
[ADR 0020's current state contract](../design/decisions/0020-derived-exact-reference-lineage.md#L205).

## 3. Detailed findings

### F1 — High: generation remains semantically broad despite its smaller software units

The current workflow has four sequential task types—brief, primary story, entity
applicability and records—using a shared generation subgraph. Record generation
binds one current source group but may produce multiple records. Its canonical
schema offers nine record families, with eligibility narrowed by current facts.
The generator must still decide how to express the assigned meaning across those
families. [Generation contract](../design/contracts/17-specify.md#L268),
[record alternatives](../design/workflows/spec/generation.schema.json#L437),
[record prompt](../design/workflows/spec/records.prompt.md).

For a data-bearing behavioral group, this can combine:

1. interpreting the original obligation and its qualifiers;
2. distinguishing the assigned group's duties from surrounding context;
3. selecting useful record families and deciding how many records are necessary;
4. converting behavior into an FR and a coherent Given/When/Then flow;
5. identifying business entities and meaningful relationships;
6. retaining exact values and unresolved decisions without inventing policy;
7. satisfying aggregate family requirements without repetition or filler.

These demands are not eliminated by putting them behind one `records` operation.
Nor does this establish a single-responsibility violation: one cohesive authoring
responsibility can still be difficult for the model.

The earlier report's examples came from the historical authoring-association
panel: 28 physical sends, 24 logical trials and 20 native
admissions, yet all six record-collection trials failed a material family,
association or field-purpose criterion. Equipment records borrowed availability
behavior into a retention assignment; renewal records lost eligibility or invented
prerequisites; startup records assumed the tested result in Given or substituted
a literal for behavior. [Primary results and scorecard](../test/calibration/authoring-associations/results.md).

**Implication:** establish which generation responsibility fails on the selected
binding before selecting a change. Do not use a reviewer-only improvement as
evidence that generation has become reliable. The archived cases do not isolate
task breadth from source grouping, representation, output format or model
competence, and supply no capability measurement under the current contract. The
16 October diagnostics show per-group batches re-authoring the whole feature on
the selected binding (F9); that is one case, not a rate.

### F2 — High: the recommendations must account for work already present and later failures

The current [generation context](../design/workflows/spec/generation.context.json#L5)
already states that assigned requirements are the batch's duties, other requirements
are context, and availability is not support. Native construction projects assigned
requirements separately and retains complete original sources.
[Source binding](../src/domain/specification_source_binding.zig#L35),
[packet construction](../src/domain/specification_session.zig#L216).

The current representation also allows ordinary prose as a string and uses an
explicit composition object for mixed text/reference insertions. Recommending
that the model stop assembling prose from bare arrays would repeat an already
accepted change. Native `required`, `present` and `unmet` family facts likewise
already reduce structural bookkeeping. Neither change proves meaning preservation.
[14 October delivery record](archive/FIX03.md#L1904). The representation is accepted, but
the 16 October diagnostics show that its admission is incomplete: the selected model
routinely produces composition the codec and validator accept but that cannot
express the field's purpose (F10). That is an enforcement gap in the accepted
contract, not a reason to reintroduce an earlier representation.

The initial report relies on these past panels. Their scope must be retained
without treating them as baseline evidence for the current contract:

| Experiment | Archived result | Limit of the historical claim |
| --- | --- | --- |
| Initial authoring associations | 20/24 native-admitted logical trials; all 6 record collections materially deficient | Native admission did not qualify those outputs semantically. |
| Assembly-family/ownership guidance | 42 calls; admission 3/10 baseline to 7/10 in each candidate arm; neither qualified | Family presence improved in those runs; meaning, ownership and completion remained deficient. |
| Subsequent rendering audit | Run-together text in 10/17 admitted collections | Those roundtrip/admission results did not qualify readable business content. |
| Withdrawn five-factor remediations | 46/60 responses before the token stop; no factor qualified; 14 requests unsent | The historical proposal did not gain qualification; unsent trials provide no result. |

Sources: [authoring results](../test/calibration/authoring-associations/results.md),
[assembly comparison and rendering qualification](../test/calibration/authoring-associations/assembly-requirements/results.md),
[withdrawn remediation results](../test/calibration/authoring-associations/remediations/results.md).

In particular, the withdrawn assembly-context arm copied prior records and
seeded unsupported content. This documents why that experiment was withdrawn;
it does not establish what the current contract would produce. The rollback and subsequent
v14 amendment also mean these panels did not measure the current restored/amended
packet. Reintroducing earlier prose would be a separately controlled intervention.

**Implication:** another sentence saying “preserve meaning” is not yet a new
experimental mechanism. Identify the semantic decision removed or clarified,
and compare against freshly captured current requests.

### F3 — High: support, local completeness and collection coverage require distinct judgments

The recommendation's distinction is correct, but the current shared owner already
expresses it. [Scope descriptions](../src/domain/required_authority_description.zig#L10)
and [§17.3](../design/contracts/17-specify.md#L166) distinguish:

| Duty | Proper question | Incorrect substitution |
| --- | --- | --- |
| Field support | Is the behavior expressed here justified by the source? | Does this field repeat every source requirement? |
| Local completeness | Does the represented behavior retain its own conditions, exceptions, negation and strength? | Is some broadly similar behavior mentioned? |
| Record coherence | Do the related fields jointly express a valid flow, with each field fulfilling its role? | Does every field contain the entire flow? |
| Collection coverage | Do the selected records collectively express all source-required duties of this collection purpose? | Is every individual record supported? |
| Source preservation | Did extraction/reconciliation retain the assigned original meaning, including meaning with no surviving claim? | Are the surviving claims internally consistent? |

A renewal statement can be source-backed in general while losing its restriction
to eligible loans with no reservation. Conversely, a correct opening-hours
description need not independently repeat a separate notification requirement.
The latter omission belongs to the appropriate collection assessment.

Current collection membership is also explicit: AC coverage selects AC records,
FR coverage selects FR records, and scenario coverage selects ACs, edge cases and
observable outcomes. A correct FR therefore does not automatically make a weak AC
guard correct. [Collection owner](../src/domain/specification_authority.zig#L41).

The historical 30-call source-review panel mixes responsibilities: it contains
mostly description assignments, not complete production traversal. Its 15/26
faithful omission handoffs and failed gap controls remain important, but not all
benchmark expectations establish a missing duty in the particular field assigned.
[FIX03 §3.2](archive/FIX03.md#32-benchmark-responsibility-is-not-fully-aligned-with-assigned-review-scope),
[panel results](../test/calibration/source-loss-attribution/bound-preservation/citation-completeness/handoff-results.md).

**Implication:** freeze the duty being assessed before scoring. Keep original
scores intact and record disputed scope separately. Current tests prove that the
packet presents the distinction; they do not prove that the selected model
follows it. The 16 October diagnostics suggest it often does not: every omission
reported there described invalid or unsupported content instead (F9).
[Scope and sibling tests](../src/specification_generation_test.zig#L5455).

### F4 — High: an explicit “R7 judgment” can conceal an unqualified upstream decision

The proposed cancellation example is a good *comparison task* if R7, its
restriction, its conditions and the relevant criterion are already faithfully
identified. It does not establish how those premises become available in production.

For arbitrary references, identifying a complete obligation, resolving pronouns,
preserving exceptions and deciding which statements belong together remain semantic
work. Native code can bind captured spans, identities and current associations. It
cannot infer every business proposition or prove that a model-extracted list is
exhaustive. Current source groups are availability/association structures, not
certified independent semantic units. [Design §4](../design/design.md#4-deterministic-and-llm-responsibility-boundary),
[authoring investigation boundary](archive/FIX03.md#L1919).

The existing omission pipeline illustrates the risk. The reviewer supplies
`missing_obligation`; a later focused comparison assesses whether intermediate
collections preserve that exact obligation. Native attribution treats the source
premise and deficient-subject endpoints as established by the admitted finding.
Correct downstream processing can therefore preserve a false upstream diagnosis.
[Comparison contract](../design/contracts/22-repair.md#L81),
[native endpoints](../src/domain/source_omission_comparison.zig#L73).
This is no longer only a contract risk: in the 08:09 diagnostic, all five
comparison assessments returned `lost` for omission premises that actually
described invalid or unsupported content (F9).

The 76-call citation comparison supplied the correct obligation. The 30-call
reviewer panel required discovering it. Their scores cannot be compared as a
same-task improvement or regression. [Recorded comparison](archive/FIX03.md#21-the-two-latest-panels-test-different-responsibilities).

**Implication:** distinguish an oracle-premise capability test from a production
handoff test. A stronger model or human may define evaluation expectations, but
those expectations must not silently enter the production generator's inputs.
If another model creates the assignment, include its actual failures, cost and
omissions in qualification. Do not add an unvalidated semantic planner or a second
obligation ledger to make the generator's task appear easy.

### F5 — Medium: preserving complete meaning is necessary; batching does not prove simplification

The current AC review already supplies complete Given/When/Then context and batches
the three existing native findings in one request. It preserves exact membership,
field purposes and separate collection coverage. Three findings remain three
semantic duties even when one provider call returns them.
[Batch owner](../src/domain/specification_support.zig#L112),
[accepted boundary](../design/contracts/17-specify.md#L127).

Historical calls 19 and 34 in the 11 October 07:03:52 UTC run used byte-identical
complete AC requests but produced opposing Given judgments. A later repair placed
successful startup in the precondition. Siblings were already visible; absent
context cannot be asserted as the cause. [Retained case](archive/FIX03.md#L2200).

The semantic unit should retain the actor/system, trigger, conditions, exceptions,
negation, obligation strength and outcome needed to understand the duty. This is
not a fixed field count. An AC is often coherent as a whole record; a source
condition may also govern several records. Splitting each scalar into a separate
call can increase the number of relationships the model must reconstruct.

**Implication:** distinguish three changes: fewer calls through batching, a narrower
semantic question, and removal/replacement of required findings. The third changes
authority and needs an explicit design decision. None follows automatically from
the first. Narrow the requested judgment without deleting relevant evidence or
introducing engine-local request-size ceilings prohibited by ADR 0011.

### F6 — High: reusable actions do not make a new semantic decomposition contract free

Existing actions already delegate packet construction to domain owners, and the
shared request subgraph handles invocation. The recommendation does not require a
new executable action for each requirement. [Generation action](../src/actions/specification/build_specification_model_input.zig),
[support action](../src/actions/specification/build_specification_support_input.zig).

However, a new assignment boundary must still specify its native subject, complete
scope, evidence, result variants, admission, dependencies and permitted downstream
effects before production adoption. Diagnostic replay can test a changed request
without granting those effects. ADR 0012 explicitly says generic request ownership
cannot replace semantic review, repair or clarification authority. ADR 0016's JSON decomposition owns
syntax and assembly; arbitrary array partitioning and model-created work lists
require a separately established finite assignment and exact coverage contract.
[ADR 0012](../design/decisions/0012-workflow-owned-model-request.md#L12),
[ADR 0016](../design/decisions/0016-configured-json-response-composition.md#L166).

The source reviewer also still has a broad classification task: support, omission,
invalid content, unresolved interpretation, actual user gaps and applicability.
Replacing this with several yes/no calls is not automatically safer. For example,
“not supported” does not identify whether the candidate invented behavior, the
source lacks a decision, or the evidence is inconclusive. Their outcomes have
different clarification and repair effects.

Current `candidate_invalid` already represents pure additions and contradictions,
with a separate nullable authority gap for mixed cases. It does not authorize a
new semantic repair or invent an omission. Reporting that this variant is missing
would repeat a superseded FIX03 finding.
[Current wire contract](../src/domain/specification_support_model.zig#L12),
[approved amendment](../design/contracts/12-model-boundary.md#source-invalid-content-finding--approved-14-october-2026).

**Implication:** keep the existing runner and shared owners. Any change to finding
granularity must thread through evidence admission, correction, reconciliation,
repair preconditions, retry identity, currentness and stored readback. Do not add
caller-specific continuation or interpret one successful subjudgment as completion.

### F7 — High: historical same-model evidence does not establish the current contract's baseline

The historical local panels used Bedrock GPT-OSS-20B with low reasoning and native
schema; the later authoring panels used temperature 0.1. The 16 October selection
uses the same model and settings, so those panels are same-model observations
rather than evidence about a different target. They still ran under superseded
packets, schemas, codecs and review contracts: before the v14 amendment, the
Converse cutover and the 16 October review-subject correction. Prompt, schema and
contract changes alter the assignment the model receives. The panels therefore
identify plausible failure classes and regression cases, not today's defect rate.

“Small” is a planning category, not a model identifier or measured ability.
Do not assume either that the old failures persist or that contract changes have
resolved them. Re-establish the baseline using the selected model and current
engine contract on a frozen revision. The old panels can inform difficult cases;
they cannot justify nine specialized calls, a stronger-model fallback or a claimed
capability ceiling.

The initial review found only GPT-OSS-20B and Claude 3.5 Haiku registered and a
GPT-OSS-style wire codec. The subsequent user-directed cutover added Bedrock Luna
to the [compiled model registry](../src/composition/provider_model_contracts.zig)
and replaced that codec with shared
[Converse encoding](../src/adapters/provider/bedrock_request.zig) and
[decoding](../src/adapters/provider/bedrock_response.zig). Luna remains registered
but is not a live-test selection. The
[registry validator](../src/domain/llm_provider_registry.zig) still rejects unknown
tuples and mismatched capabilities. Production dispatch remains
[Bedrock-only](../src/adapters/provider/provider_dispatch.zig).
Registration and offline fixtures did not prove live compatibility. The 16 October
first-request exchange did so for one request shape only (§5.6 Phase 1).

Qualification should pin the exact intended generation slot, provider/model,
reasoning, schema mode and provider output allowance. The review's Luna binding
omitted temperature and explicit reasoning controls because inspected primary
sources did not establish their Converse mapping. Its documented default medium
effort did not authorize an unverified field. The 16 October GPT-OSS selection
instead uses the already registered low-reasoning and fixed-temperature controls.
Historical temperature-zero reviewer panels are not this baseline.
[Current operating rules](../design/contracts/12-model-boundary.md#125-low-capability-model-operating-rules).

If a stronger model is used only for independent evaluation, label that use. If it
supplies plans, normalized obligations, routing decisions or repaired drafts to the
generator, it becomes part of the production system being evaluated. Its cost and
failure modes cannot be omitted while claiming success by the selected generator.
Similarly, configuring a stronger repair model is a separate intervention, not
evidence that the original generation assignment improved.

Repeated review or decomposition by the same model is not independent evidence.
An earlier semantic mistake can be shared by later steps. Record error propagation
and useful completion at the complete-duty level, not merely per-call correctness.
More calls can increase latency, actual-token use and exposure to inconsistent
judgments. Measure those effects on the selected binding; do not estimate their
size from the archived model runs.

### F8 — High: published research does not select a decomposition for the selected model

At the 15 October review, current-generation Bedrock Luna was selected for the
implemented test protocol, and the research below was gathered for that target.
The 16 October GPT-OSS-20B selection now governs live tests, so the Luna row
describes a superseded target rather than the selected model. The older-model
decomposition and verifier studies considered in the initial review remain
excluded from the capability evidence base. No inspected source qualifies
GPT-OSS-20B on this workload either; Phase 2 must measure it directly.

The additional research verified the following evidence for the 15 October target:

| Primary source | What was verified | What it cannot establish |
| --- | --- | --- |
| [AWS GPT-6 Luna model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-openai-gpt-6-luna.html) and [OpenAI's Luna documentation](https://developers.openai.com/api/docs/models/gpt-6-luna) | Current small-model target, released on Bedrock on 22 September 2026. Sydney uses `global.openai.gpt-6-luna`; Converse supports native JSON Schema with a schema string and the additional strict-output field. CountTokens is unsupported. | Native JSON constrains structure, not source fidelity. The user selects this target for every live test role. No live compatibility or semantic qualification has been established; explicit effort/temperature controls remain outside the verified Converse subset. |
| [StructEval's live result metadata](https://tiger-ai-lab.github.io/StructEval/static/data/leaderboard.json), checked against [Google's current Flash page](https://deepmind.google/models/gemini/flash/) | The published current-generation Gemini 3.8 Flash run covers 2,035 examples, evaluated on 10 October 2026. | The overall benchmark mixes rendered and text structures; a high aggregate result does not establish requirement preservation, uncertainty handling or complete specification quality. |
| [StructEval methodology](https://tiger-ai-lab.github.io/StructEval/) and [primary text evaluator](https://raw.githubusercontent.com/TIGER-AI-Lab/StructEval/main/structeval/eval_engine/eval_nonrenderable.py) | Its text metric combines load success with expected structural-path checks; the published weighting is 20% and 80%. | Structural validity is not a semantic decomposition comparison. The linked detailed live-run artifact could not be retrieved; these are published results, not independently reproduced or fully audited live-protocol evidence. |

No directly applicable study inspected in this review establishes
that per-family decomposition improves source-grounded specification generation.
Consequently, research does not select the winning assignment size, justify a
nine-call schedule, or establish a small-model capability ceiling. The proposed
comparison is needed to resolve that uncertainty on the intended models.

For the larger design, retain closed native contracts and original evidence.
Move established bookkeeping into native code where possible; do not replace
schema checks with trust in prose or add an unqualified semantic planner to make
the generator's input appear simpler. These are contract-based design conclusions,
not measured effects on the selected model.

### F9 — High: selected-binding full-workflow diagnostics expose generation, review and budget failures

The 16 October full-workflow diagnostics are the first evidence on the selected
binding under the current contract: two loan-renewal and three hello-world runs on
development builds, none of which published a specification. They are diagnostics
on two cases, not a baseline or a rate, and the classifications are this review's
source-based reading of untrusted model output, not human adjudication. The
[full record](Z_FIX02.md#f9--high-selected-binding-full-workflow-diagnostics-expose-generation-review-and-budget-failures)
keeps the call-level evidence. Three consequences shape the experiment:

- **Per-group authoring re-drafts the whole feature.** In both loan-renewal runs
  ([07:54](../zig-out/e2e-spec/2026-10-15T20-54-21Z-5f6e903390f38938113712b53a359de4/report.json),
  [08:09](../zig-out/e2e-spec/2026-10-15T21-09-33Z-3a7ceed77cb237531019300e1005152d/report.json)),
  each record batch re-authored the same renewal acceptance criterion and functional
  requirement instead of its own group's duties: at 07:54 as `competing_records` that
  blocked the run, at 08:09 as near-duplicates that each needed their own review.
  This is selected-binding evidence for the source-group ownership risk in F1 and
  §4.3. It supports running the A/C comparison first, because C removes the
  per-group authoring boundary; it does not show that C will succeed.
- **Review returns wrong finding types.** In the 08:09 run none of the three reported
  omissions described source meaning missing from the candidate, all five
  bound-preservation comparisons then returned `lost`, and three `unsupported`
  findings asked the user to define content the generator had invented. Finding type
  selects the repair or clarification route (F6), so a real defect reported with the
  wrong type is a harmful diagnosis. §5.5 therefore measures finding-type accuracy.
- **Review dominates cost, and the workflow cannot finish within budget.** Source
  review used 75% of the 08:09 run's tokens and 77% of the
  [09:18 run's](../zig-out/e2e-spec/2026-10-15T22-18-35Z-a8740d575019326cb5b63f994c3dc426/report.json)
  ([cost investigation](Z_FIX02.md#545-phase-2-review-and-repair-cost-investigation)). Both stopped on the 100,000-token workflow
  budget before review finished. That budget is a compiled engine constant
  ([core operations](../src/composition/core_workflow_operations.zig#L35),
  [native operations](../src/composition/native_workflow_operations.zig#L641)), not
  case configuration. At this cost, Phase 5 useful completion would measure the
  budget rather than quality, and the protocol's experiment-wide stops of 1,000 sends
  and 2,000,000 actual tokens cover fewer than 20 such workflows, against 144–288
  paired full workflows in Phase 5 alone (8–16 features × 3 variants × 3 repetitions
  × 2 builds).

**Implication:** generation decomposition alone cannot produce useful completions
while review cost and diagnosis quality are unmeasured. Phase 2 must attribute
failures and cost to review and repair as well as generation, measure finding-type
accuracy (§5.5) and settle budget feasibility before dispatch. Raising the compiled
budget is an engine contract change, not a test-configuration adjustment. It needs
an explicit decision and must be frozen before the baseline, so that baseline and
candidate share it. Do not raise it automatically to obtain a completion, and do not
weaken review gates to save tokens. Part of this review cost began with defects
native admission should have rejected (F10).

### F10 — High: model text composition is not admitted against its field purpose

**Failure class.** Every full-workflow run that reached generation under the
14 October model-text representation admitted one or both of two inverse composition
failures. Some values were made only of exact-copy insertions, such as the 09:18
story `Hello, World!Hello, World!`, built from two insertions and no prose. In
others, insertion syntax typed inside prose was admitted as business text. Review
then became the first detector of a structurally detectable defect, misdiagnosed it
and drove an unchanged repair; in the 09:18 run that chain cost about 23,000 tokens.
The [full record](Z_FIX02.md#f10--high-model-text-composition-is-not-admitted-against-its-field-purpose)
traces the five runs and every layer the defect passed through.

**General invariant.** A declared text field's admitted value must be able to
express that field's declared purpose. Typed insertions are exact-value and reference
evidence placed inside meaning, not a substitute for it, and the model's wire syntax
never becomes business text. One owner declares this per field and applies it
identically to initial authoring, protocol correction, every repair route,
collection coverage and stored readback. Whether any prose exists is deterministic;
whether the prose is adequate remains a semantic judgment.

**Resolution.** The accepted
[composition contract](../design/contracts/text-field-composition.md) implements the
invariant through one field-policy registry. Phase 1A enforces it at admission,
Phase 1A.2 projects it into model-facing presentation, and Phase 1A.3 corrects
composition defects at response admission (§5.6). The rule applies to every model
and provider, including the proposed [Claude connector](claude_connector.md). It has
no field-, case- or model-specific branch, no prompt-only fix, and no normalizer that
turns strings into insertions.

**Relation to the comparison.** A, B, C and D all share this representation, so none
of them addresses F10, and C would inherit it. Closing it is a prerequisite for a
fair comparison, not one of its candidates: a gain from adding such a rule to one arm
would not be a decomposition benefit (§5.2).

### F11 — High: admission now stops the defect, but generation cannot recover from it

The [16:20 hello-world diagnostic](../zig-out/e2e-spec/2026-10-16T05-20-15Z-44b2ac5e19cbf8d2ade89b149aed73c8/report.json),
the first full workflow on a committed build (`bfec3d7`, Phase 1A), confirmed the
enforcement. The brief's insertion-only title was rejected as `reference_only`
before any review, the unchanged repair exhausted after one execution, and no
defective value escaped. The run ended with `RepairNoProgress` after 8 calls and
12,896 tokens, against 101,134 for the 09:18 run that reached review with the same
failure class.

Generation did not recover, because the model-facing presentation contradicted the
admission rule. The projected schema still offered an insertion-only title, static
guidance told the model to insert exact copies in every field, exact choices were
offered to the whole unit, the policy appeared as a generic table, and the repair
packet echoed the rejected value in the shape the model was asked to return.
Phase 1A.2 projects all of it from the field registry. The
[full record](Z_FIX02.md#f11--high-admission-now-stops-the-defect-but-generation-cannot-recover-from-it)
keeps the call-level evidence and secondary observations, including extraction
merging the three hello-world requirements into one claim, which remains
unattributed.

### F12 — High: descriptive fields recover, but record fields collapse to insertions

The [18:58 hello-world diagnostic](../zig-out/e2e-spec/2026-10-16T07-58-59Z-ec56ff4bc24a21c0082210cf6caa8f31/report.json)
ran Phase 1A.2 on uncommitted code, so it is diagnostic evidence only. Every
descriptive field whose grammar no longer offers exact copies came back as prose, the
wire-syntax correction worked, the first rendered story repair succeeded, and
admission escape was measured zero. The run then failed at record generation, with
`RepairNoProgress` after 14 calls and 20,374 tokens and before any review:

1. **Record fields collapsed into insertions.** Given, When, Then, the functional
   requirement and the entity name each came back as a single exact-copy insertion:
   every field the request listed as permitting insertions. That the list and its
   obligation wording caused the collapse is a hypothesis, confounded by field type,
   which Phase 1A.3 attributes before any presentation change.
2. **Field-level repair could not recover a unit-wide collapse.** The Given repair saw
   neither the record's sibling fields nor its source group, while four of those
   siblings were also defective. Decision 4(a) therefore routes composition defects to
   the unit's bounded protocol correction, with the complete request.
3. **Entity applicability was wrong.** The entity pass declared an entity required for
   a feature with no business data, and the identity-label exception then admitted
   its insertion-only name. No native rule can judge applicability; Phase 2 measures
   it as its own failure class.

Extraction again merged the three requirements into one claim, and the GPT-OSS
envelope-prefix malformation recurred (`{"token{`). Both are counted, not corrected:
the approved normalizer is not widened without a decision. The
[full record](Z_FIX02.md#f12--high-descriptive-fields-recover-but-record-fields-collapse-to-insertions)
keeps the call-level evidence.

## 4. Critical feasibility assessment and revised proposal

### 4.1 Feasible diagnostic; incomplete production design

The original proposal overstated the work needed before an isolated experiment
and understated the work needed after it. These are separate scopes:

| Scope | Feasibility at this revision | Necessary work and limit |
| --- | --- | --- |
| Inspect and prepare current workflow packets | Available through existing authoring fixtures and capture owners | Inspect packets and controls; preserve historical freezes. Offline preparation does not establish dispatch support. |
| Capture the selected-binding baseline | First-request compatibility established (Phase 1); no frozen baseline yet | Freeze a committed revision, approve the panel and settle budget feasibility (F9). Compatibility covers only the observed first request shape. |
| Test an AC-focused request | Feasible after an eligible fresh capture on the frozen revision | Prepare/freeze the candidate, validate its serialized request and score actual responses. Fresh bounded live approval is required. No production family scheduler is a prerequisite. |
| Reuse native parsing/projection | Partly reusable in diagnostic tooling | Apply applicable schema, typed-text, occurrence and binding checks; record their scope. Do not force incomplete AC output through whole-specification completion. |
| Execute separate family assignments in production | Not implementation-ready | Establish assignment identity, applicability, finite scheduling, exact completion/assembly and repair dependencies. Reusing the generic runner does not supply those contracts. |
| Establish improved product reliability | Unproven | Actual production-origin generation, review and authorized repair, followed by complete publication and rubric qualification. |

[ADR 0019](../design/decisions/0019-single-request-debugger.md#replay) already
permits modified prompt/context/schema replay with retained provider settings.
The [service](../src/application/request_replay.zig#L1) sends at most one request,
stores authentic diagnostic results and provides no workflow binding.
The existing [authoring harness](../test/calibration/authoring-associations/README.md#L42)
uses that path. A candidate must still compile under the closed schema contract
and retain a valid captured parent; a missing archive cannot be replaced by a
fabricated receipt. Replay retains provider/model/settings; its
[authorization check](../src/composition/request_debugger.zig#L53) rejects a changed
target. Capture an authentic parent under the current contract on the frozen
revision. Do not reuse a historical GPT-OSS parent captured under a superseded
packet, schema or codec, even though the model is the same.

This is a qualitative feasibility assessment, not an implementation estimate or
runnable dispatch manifest. It needs preparation and scoring work. The selected
binding uses the existing Bedrock client; no new provider client is needed. No
generation-runtime redesign is needed merely to compare diagnostic requests.

### 4.2 High: current-baseline evidence is missing

The local current v14 preparation was inspected during this review. Its admission
report has status **not_run**, semantic quality **unscored**, and
native_workflow_origin_available **false**. Its equipment packet includes the
required entity family and present/unmet family facts, as well as the newer
model-text representation. It is not the request used by the historical panel.
The generated preparation location and owning build entry are documented in the
[authoring harness](../test/calibration/authoring-associations/README.md#L60).

The 16 October full-workflow diagnostics (F9–F12) are the first selected-binding
observations under the current contract. They are not this baseline: they cover two
cases, one of them outside the panel; all but one ran on uncommitted builds that
differed between runs; and none reached publication.

Historical errors justify selecting development cases; they do not establish
today's defect rate or an expected improvement. Capture a fresh current baseline
in any approved comparison. If it no longer exhibits the chosen failure, report
the lack of demonstrated improvement/headroom rather than changing the scoring
or declaring the old error fixed by the candidate.

The equipment example remains useful, but its precise conclusion is **wrong
support/ownership in an emitted AC**. Repeat 2 contains a correct retention FR;
it does not show complete loss of retention from every output.
The [case](../test/calibration/authoring-associations/cases.json#L100) separates
identifier/inspection-result retention from unavailable-until-success behavior.
The [first response](../zig-out/phase5-authoring-associations/live-archives/17-equipment-joint-support-records-1-records-1.response.json)
and [second response](../zig-out/phase5-authoring-associations/live-archives/19-equipment-joint-support-records-2-records-1.response.json)
retain the AC substitution.

Its MOCK brief goal and entity basis also emphasize availability. They may affect
salience, but that cause is unproven. Hold those exact predecessor bytes constant
between arms; cleaning them up only for the candidate would confound the result.
Later qualification must include actual generated predecessors.

### 4.3 High: an AC projection is not a universal completeness oracle

Current record assignments preserve their group's obligations across a mixed
collection. They may return an empty batch; mandatory AC/FR families apply to the
assembled specification. Neither group membership nor family presence proves that
every source duty belongs in an AC from every group.
[Current record contract](../design/decisions/0020-derived-exact-reference-lineage.md#L64),
[aggregate family projection](../src/domain/specification_session.zig#L151).

Before dispatch, each case needs a source-grounded account of the behavior that
an AC should test. Separate:

- an emitted AC that substitutes an unrelated duty or loses its own conditions;
- missing scenario coverage that the declared AC purpose actually requires;
- a duty legitimately represented in another family under the baseline contract;
- a batch without an AC where no per-group AC requirement exists.

For the selected diagnostic, explicitly asking for a retention scenario creates
a narrower task. Its success can be compared with the baseline's available AC
content, but absence of that scenario in the baseline is not automatically a
production-contract violation. Count baseline AC availability separately from
faithfulness of emitted ACs. Never average only the easy ACs while dropping
missing, malformed or rejected responses.

The scheduler also visits question-eligible groups, which can include token-only
or unresolved-decision evidence. There is no current rule that each has an
independent testable behavior. Cross-group conditions may require joint meaning
without authorizing a new association.
[Group enumeration](../src/domain/specification_source_binding.zig#L120).
Therefore an AC-per-group policy cannot be inferred from success on equipment.
Its generalization would need nonbehavioral, unresolved and cross-group cases,
without filler, arbitrary skipping or an unqualified model preclassifier.

### 4.4 High: a production split changes identity, assembly and repair

The obstacles are concrete, not just unspecified engineering effort:

| Current owner | Present invariant | Consequence for family-scoped production work |
| --- | --- | --- |
| Session population | Three preceding task assignments plus one iteration per retained group | A new finite assignment population must account for complementary purposes without silently advancing past unfinished work. [Iteration](../src/domain/specification_session.zig#L28). |
| Assignment and request identity | A record assignment identifies its group occurrence and reference snapshot; request ownership follows the group cursor | Purpose identity and dependencies must be explicit. Reusing a group identity cannot conceal a different task or reset retry history. [Assignment](../src/domain/specification_generation.zig#L31), [request owner](../src/domain/specification_session.zig#L123). |
| Collection assembly | Each admitted batch advances the cursor once; one batch per group is combined with actual producer origins | Several family results need exact membership, ordering, completion and origin retention; a second call is not an interchangeable replacement. [Assembly](../src/domain/specification_session.zig#L395). |
| JSON composition | Arrays remain whole; arbitrary array partition/concatenation and semantic deduplication are excluded | Generic composition cannot simply combine AC and FR partitions of the records array. A domain assignment/assembly contract is required. [ADR 0016](../design/decisions/0016-configured-json-response-composition.md#L134). |
| Aggregate validation/repair | Entity membership spans batches; missing-entity insertion depends on an established writable owner | Incomplete AC output cannot pretend to complete the original mixed batch or gain permission to insert a complementary entity. [Consistency and ownership](../src/domain/specification_session.zig#L434). |

These changes cross domain types, packet selection, collection, origins, repair
authorization and tests. They do not require one action per business question,
but they are not a prompt/resource-only rollout. Full readback and dependency
effects must be assessed before deciding whether any persisted contract changes.
Do not preselect a new storage version without that analysis.

### 4.5 Medium: output narrowing leaves context difficulty and can increase cost

The current packet retains assigned requirements, other requirements as context,
eligible exact choices and complete original sources.
[Packet construction](../src/domain/specification_session.zig#L198),
[source projection](../src/domain/model_evidence.zig#L76).
An AC-focused task removes other drafting purposes; it does not remove the need to
identify relevant facts among that evidence. Source-group ownership mistakes may
persist even when the task requests only one family.

Keep evidence constant for the initial comparison. Measure total request bytes,
prompt/schema/evidence contributions and actual input tokens. Evidence filtering
is a separate hypothesis: silently removing an exception or using only surviving
claims would compromise the experiment and the authority boundary.

For G source groups, current record generation uses G initial calls. A proposed
split with k_g purpose assignments per group uses the sum of k_g calls, before
correction, review and repair. Where original evidence repeats, additional calls
repeat its input cost. Output savings and fewer failed repairs might offset this;
no such saving is established. The complete-workload comparison must include
that overhead and remain sequential unless existing concurrency prerequisites
are satisfied.

There is no measured cost estimate for the proposed workload on the current
models. Use finite send and actual-token stops, not prohibited local size ceilings
or token reservations. Record an in-flight overshoot and incomplete pairs honestly.

### 4.6 Conditional experiment: purpose-only diagnostic

Prepare the current-contract baseline and complete-output comparison in §5 first.
If mixed-purpose errors persist, a source-grounded purpose diagnostic can isolate
a useful question before implementing production decomposition. Its live comparison
still needs a separately bounded approval. A family scheduler is not needed merely
to obtain these measurements.

Retain the equipment ownership failure as a development target and include an
unrelated condition-preservation case. A candidate assignment can ask:

> Produce complete Given/When/Then acceptance flows for the currently assigned
> behavioral requirements. Use their original sources to retain the conditions and
> outcomes. Other duties provide context and do not replace this assignment.

Use the **same current assigned requirement and original sources** in both arms.
Do not supply a human-corrected “retention obligation” only to the candidate.
Score source meaning independently of derived labels; upstream extraction or
grouping defects remain separately observable.

For the smallest comparison:

| Arm | Task and input | Interpretation |
| --- | --- | --- |
| A: current baseline | Current mixed-record task, selected schema, packet and controls | Establishes current output and the available AC projection. |
| B: purpose-only diagnostic | Same schema, source assignment, evidence, prior facts and controls; task requests AC output only | Tests whether narrowing the requested output purpose improves the relevant AC behavior while avoiding a simultaneous schema change. |

In B, whole-specification family requirements remain assembly-context facts; this
diagnostic is not asked to complete the full specification. Replace the existing
record task text rather than appending conflicting instructions to write all
families. Retain the packet's purpose catalogue as definitions and record every
task-text difference needed to express the narrower scope. AC-only applies to
content output; retain existing clarification and inconclusive alternatives and
score them separately from successful authoring. Other-family emissions remain preserved
evidence and count as failure to follow B's assigned purpose, not as a new
production rejection rule.

This comparison changes requested work and output burden by design. A benefit
supports the **narrower task package**, not a causal claim that a particular hidden
reasoning step was removed. It still uses the broad schema; if schema complexity
appears relevant, a later separately frozen B-versus-restricted-schema comparison
can test that factor. Do not start with a large multifactor panel or claim that
task narrowing and schema narrowing are independently qualified by one A/B test.

Keep G/W/T together and permit multiple necessary scenarios. Do not require exactly
one scenario per claim, use an authored FR as sole source authority, demand
invented prerequisites, or introduce a new semantic planner. Select cases where the
AC purpose is justified, then reserve broader applicability questions for the
production-design gate.

FIX03 recommends whole-collection versus per-group authoring first and explicitly
calls the alternatives **unselected experiments**.
[Recommendation](archive/FIX03.md#L1919), [qualification boundary](archive/FIX03.md#L1963).
That experiment tests the source boundary; this pilot tests output purpose.
Whole-collection authoring may reduce group fragmentation while increasing mixed
semantic work. Neither option has established superiority. With the selected
small-model binding, compare complete output first and retain this
purpose-only diagnostic for remaining failures. This does not promote either
option to accepted architecture. Preparing the alternative does
not need a separate policy exception merely because the earlier analysis proposed
a different order. Actual dispatch still requires fresh bounded approval.

### 4.7 Freeze an executable protocol before requesting dispatch

The initial report's qualitative promotion rule was not a runnable test plan.
Before live execution, specify:

1. **Cases and duties:** canonical source bytes, assigned groups, purpose-specific
   expected behavior, permissible variations, and material failure categories.
   Separate development from untouched qualification cases. Include conditions,
   negation/exception, an outcome incorrectly assumed in Given, source uncertainty
   and more than one necessary scenario. Do not tune on qualification responses.
2. **Current requests:** exact packet/prompt/schema bytes, immutable parent,
   applicable schema restrictions, production text construction and canonical
   rendering. Keep the current brief/entity seeds and source evidence identical
   across paired arms. Preserve historical freezes.
3. **Controls and counts:** exact selected small model, provider,
   region, reasoning, response mode and output allowance; current temperature
   policy; logical trials, repetitions and physical sends. Record the evaluation
   date and whether the provider exposes an immutable version or moving alias.
   Interleave or
   counterbalance the arms and record order. Repeated calls are clustered by case.
4. **Stops:** approved maximum sends and actual input-plus-output usage; halt after
   uncertain delivery, unknown usage or configuration drift. Predeclare minimum
   complete paired evidence and how unattempted/truncated responses affect the
   result. Do not retry an uncertain send or shrink scope to finish within budget.
5. **Scoring:** blind arm labels where practical, grade canonical resolved values
   against original sources, and adjudicate disputes independently. Label
   model-assisted judgments. If human assessment is unavailable, report that
   qualification limit rather than silently claiming a human-reviewed result.
6. **Decision rule:** predeclare the targeted improvement, material-regression
   categories and acceptable diagnostic cost. An underfilled panel or unresolved
   scoring dispute is inconclusive. Passing examples justify further investigation;
   they do not establish a reliable population rate.

The purpose diagnostic reports AC availability, source fidelity, role correctness,
omissions, unsupported additions, unresolved decisions, requested-purpose adherence,
provider/schema result and actual resources separately. Complete mixed-record
admission and workflow publication are **not exercised**, not passed. Where current
native checks reject the intentionally incomplete collection, retain the rejection
and explain its full-workload scope; do not waive it or count missing FR/entity
work as an AC-semantic error.

The [existing receipt owner](../src/test_fixtures/authoring_association_calibration.zig#L472)
combines schema, singleton construction, native parsing/binding and session
consistency. An AC diagnostic needs explicit scoring/preparation at those existing
boundaries; successful replay alone is insufficient. Reuse applicable validators,
but never fabricate missing records, origins or completion to make a response
appear production-admitted.

### 4.8 Separate the promotion gates

These evidence classes map to the operational phases in §5.6; they are not a
second rollout or an alternative route around its gates.

| Gate | Evidence required | Permitted conclusion |
| --- | --- | --- |
| Component capability | Current-baseline comparison, complete purpose-specific outputs, predeclared unrelated controls and recorded component cost; no material regression under frozen criteria | Invest in or reject a proposed assignment design. No full-workload cost or repair-quality claim. |
| Production integration | Accepted finite assignment/applicability/assembly contract, shared lifecycle implementation, positive/negative tests and complete complementary duties | Execute the actual production path for qualification; implementation mechanics alone do not establish semantic improvement. |
| Product qualification | Separately approved production-origin generation, review and permitted repair on untouched qualification features; full validation, publication and actual-output rubric | Assess useful completion, harmful diagnoses/repairs and total workload quality/cost. |

Diagnostic replay results cannot simply become the actual review/repair chain.
[ADR 0019](../design/decisions/0019-single-request-debugger.md#diagnostic-execution-boundary)
withholds workflow authority, and
[§28.8](../design/contracts/28-testing.md#288-model-conformance-comparisons)
explicitly prohibits importing replay results as workflow authority. Diagnostic
review packets may be projected and assessed as diagnostics; later production
qualification must generate fresh authentic workflow-origin candidates. Preserve
bad diagnoses in either evidence class instead of replacing them with oracle
obligations.

If the narrowed task remains unreliable, reject or revise that candidate within
the declared experimental scope. This establishes a limitation of the tested
request/model combination, not impossibility for all models in its tier. Do not expand
calls, retries, stronger-model dependencies or acceptance exceptions to force a
success. If the current baseline is already adequate, report no demonstrated
need for this decomposition.

## 5. Larger-change options and phased rollout

### 5.1 Planning assumptions and recommended starting point

The latest user selection is **GPT-OSS-20B only on Bedrock**. The exact binding is
**`openai.gpt-oss-20b-1:0` from Sydney**, Converse, native JSON Schema, low reasoning
and engine-fixed temperature `0.1`; no Luna, Sonnet, Sol, Haiku, direct OpenAI API
or alternative model ID/alias is a live test selection. The earlier
current-generation-only cohort restriction is superseded by this explicit switch.
This is a model choice, not evidence that it wins on SDDE quality. Do not
substitute historical small-model results or mix model cohorts.
Freeze exact model IDs, evaluation date and settings before dispatch.

The observable objective is source-faithful complete specification generation,
including conditions, exceptions, entities and justified uncertainty, at acceptable
total cost. The owning abstraction is the specification assignment/session and
source-association contract. The general design risk is **treating a mechanical
source group or output field as if it were a complete semantic task**. Current
reconciliation groups related claims of the same category; it does not certify
that each group contains a complete behavior and all its qualifiers.
[Reconciliation task](../design/workflows/spec/reconciliation-signals.prompt.md#L1).

Begin with current per-group generation versus whole-collection authoring over
the same original sources and complete record obligations. This tests whether
the whole-collection package improves complete outcomes. Add the
AC-purpose diagnostic only if the new baseline exhibits relevant mixed-purpose
errors. A nine-family schedule is a concrete alternative, not the default plan.

The larger-change authorization permits a complete redesign where justified.
It does not require changing every abstraction. Preserve the generic runner,
registered action boundaries, closed native validation, source authority and
atomic whole-workflow publication. Generation decomposition needs no new model
tool capability, alternate runtime or semantic planning gate. The selected binding
needs no new provider client, and no new production dependency is selected in this
report.

Generation is not the only owner of the complete outcome. On the selected binding,
source review consumed most of the workflow's tokens and produced wrongly typed
omission findings (F9). The comparison below therefore measures generation, while
Phase 2 must also attribute failures and cost to review and repair before any
generation redesign is credited with, or blamed for, workflow completion.

### 5.2 Compare distinct source and output boundaries

| Candidate | What it changes | Remaining difficulty and decision use |
| --- | --- | --- |
| A: current mixed records per group | Nothing; current complete pass is the control | Establish capability on the selected model under the current contract. Every group and complementary family remains in the workload denominator. |
| C: one complete mixed record collection | Removes the fixed per-group authoring boundary; permits each record to select actual supporting groups | Retains family selection and full-feature coverage in one request. This is the first full-output comparator for the current small-model baseline. |
| Purpose split retaining current source scope | Separates an evidenced difficult purpose, such as AC authoring, from complementary record work | Can help family/role confusion, but preserves source fragmentation and adds calls. An AC/non-AC split still leaves mixed complementary work; it is not equivalent to simplifying every family. |
| D: complete collection per record family | Combines a whole-source scope with a fixed output purpose and explicit per-record support selection | Removes family selection and fixed single-group inheritance, but repeats source context and leaves coverage/support selection to the model. Test the complete workload before choosing it. |
| Newly inferred coherent behavior units | Changes extraction/reconciliation to discover complete semantic assignments | Creates another semantic completeness dependency. Defer unless measured source-representation defects require it; amend the existing owner rather than adding a second obligation ledger. |

C is a **diagnostic package comparison**, not a perfectly isolated prompt change:
current record output has no per-record group selector. A candidate selector must
be disclosed, validated and scored. Never bind every record to every available
group, discard lineage to make C pass, or manufacture native workflow origins.
The diagnostic may expose a representational blocker without being production
admissible. Later integration must resolve it explicitly.

Use this decision rule after the frozen comparison:

| Evidence | Design decision |
| --- | --- |
| Current baseline is adequate | No decomposition rewrite is justified by these cases. |
| C improves complete source fidelity at acceptable total cost | Develop collection-level authoring with explicit support selection; do not add family stages automatically. |
| Purpose narrowing helps, C does not, and current groups faithfully represent the duties | Develop the smallest complete purpose split, including all complementary work. |
| Both changes help independently | Compare the combined complete workload; separate gains do not establish an interaction benefit. |
| A required behavior needs joint groups that fixed inheritance cannot represent | Resolve the source-association contract regardless of easy-case scores; prompt wording cannot remove the representational limit. |
| Neither change improves quality, or unsupported additions/cost materially worsen | Reject the candidates and revisit the measured failure or supported scope. Do not add stages or retries speculatively. |
| Quality looks promising but association or scoring is unresolved | Resolve that specific boundary; do not claim production qualification. |
| Baseline failures or cost concentrate in review or repair rather than generation | Generation decomposition is not the next intervention. Resolve the measured review or repair boundary first, through its owning contract and with its own qualification; do not compensate with generation changes. |
| Failures are structurally detectable but escape native admission (F10) | Not a decomposition question. Close the shared representation and admission contract first, then re-establish the baseline; a gain from adding such a rule to one arm is not a decomposition benefit. |

### 5.3 Concrete contract for collection-level authoring

The following is the proposed larger contract if C or D is selected. It is
specific enough to expose implementation obligations, but is not yet a recorded
amendment to governing contracts.

1. **Finite native assignments.** Derive an in-memory assignment manifest from the
   selected closed authoring contract. C has one complete-record assignment; D has
   one per permitted record family. Each entry identifies its purpose, current
   reference state, evidence snapshot and predecessor dependencies. It does not
   claim to be an independently verified business obligation. The model cannot
   create assignments, choose successors or mark an assignment completed.
2. **Complete content units.** Keep an AC's Given/When/Then together, including
   multiple necessary scenarios. Keep an edge case with its expected behavior and
   an entity with its meaning and relationships. D exposes only its family in the
   content schema; native code can construct fixed family tags. Retain closed
   clarification/inconclusive outcomes. Neither an authored FR nor a previous
   model summary replaces original source authority for another purpose.
3. **Explicit supporting groups.** Each record proposes content together with
   nonempty, unique current group selections. Reuse the existing narrative
   `resolveGroups`/association owner to construct canonical `source_group_ids`,
   the complete selected claim union, exact dependencies and citations. Joint
   support and legitimate overlaps are allowed; stale/foreign/repeated selections
   and positive use of open-question groups reject. This adds a real model task:
   choosing support. Native membership validation cannot prove that choice is
   semantically correct. [Canonical resolver](../src/domain/specification_source_binding.zig#L93).
4. **Exact assembly and origins.** Admit exactly one result per expected native
   assignment, preserve actual producer origins, and assemble in a documented
   stable assignment order with within-result occurrence order. Empty content
   is an admitted result only where permitted; it is never evidence of coverage.
   Missing/duplicate/foreign results block. Domain collection assembly owns this;
   generic JSON composition does not acquire arbitrary array concatenation or
   semantic deduplication.
5. **Currentness and bounded correction.** Request identity includes purpose and
   source dependencies. Protocol correction retains the same assignment, eligible
   catalogue, schema and retry allowance. Upstream changes invalidate affected
   candidates and reviews. Do not persist the manifest as a resumable execution
   checkpoint or publish a completed family independently.
6. **Independent completion gates.** After assembly, retain required family/entity
   checks, claim mapping, exact-token preservation, source/principle review,
   dependent validation and full-candidate validation. Model declarations of
   coverage, confidence, validity or inapplicability create no new authority.

For D, optional-family ownership must be explicit. There are nine current record
families: AC, user-visible outcome, edge case, FR, business rule, assumption,
non-goal, prohibited behavior and entity. Existing entity applicability may exclude
entity work. With no new applicability classifier, the other optional families
each have an owner that may return empty content. That means **eight or nine record
calls, plus the existing three preceding assignments**, before correction/review/
repair; it is not nine calls per source group. This requires amending the current
rule that an optional family has no dedicated call.
[Current policy](../design/contracts/17-specify.md#L312).

D preserves existing whole-specification coverage duties; it does not require
every source obligation to be repeated in every optional family. Existing
collection judgments cover AC, FR and scenario coverage, not completeness of
each optional family. Field support and claim mapping do not certify an empty
optional collection as semantically complete. Family-specific applicability work
therefore remains with the authoring model, and any new optional-family completeness
judgment would require an explicit review contract and its own qualification.
[Current collection subjects](../src/domain/specification_authority.zig#L41).

Compared with current `3 + G` initial generation calls, C uses `3 + 1`, while D
uses `3 + P`, with P equal to eight or nine under this proposal. These are call
counts, not token or quality estimates. D can be expensive for small G; C can
produce a large output and fail the provider's output allowance. Even one complete
family may be semantically difficult for the selected small model. Measure actual
tokens, latency, truncation and useful completion across feature sizes. Do not
add local size ceilings, reservations or silent truncation to make the redesign fit.

### 5.4 Repair and readback are part of the redesign

Changing generation alone would leave several single-group assumptions invalid:

| Existing consumer | Required coordinated change |
| --- | --- |
| [Generation parser and clarification](../src/domain/specification_generation.zig#L77) | Parse record selections through the shared association owner; keep question eligibility separate from positive-content support. |
| [Session admission/progress](../src/domain/specification_session.zig#L70) | Replace one-batch-per-group identity and cursor rules with exact selected-manifest membership and dependencies. |
| [New and stored record provenance](../src/domain/specification_provenance.zig#L245) | Validate complete multi-group associations through canonical resolution, including stored readback; removing a length check alone is insufficient. |
| [Omission comparison](../src/domain/source_omission_binding.zig#L98) | Project the complete authored support selection consistently, without inventing a convenient owning group. |
| [Omission insertion](../src/domain/specification_coverage_repair.zig#L404) | Bind the authorized purpose and existing explicit authored groups consistent with the admitted diagnosis. Otherwise retain blocking under current authority; do not infer support from all available groups or the last writable batch. |
| [Generation consistency/entity ownership](../src/domain/specification_session.zig#L434) | Resolve aggregate missing-family/entity findings to an authorized owner under the new assignment contract. Partial AC output cannot impersonate complete mixed work. |

Existing value-only repair must preserve the selected group/evidence set, old
value/revision, siblings and defect retry history. Broader generation scope does
not grant broader repair authority. The initial cutover can preserve explicit
blocking when an association cannot be repaired under existing rules; measure the
resulting blocked rate as a product outcome.

If qualification shows that correcting wrong or missing associations is necessary,
specify a separate narrowly authorized content-and-association rebuild: exact
target and admitted diagnostic, original evidence, old-value/revision conditions,
unchanged siblings, retained retries and complete dependent revalidation. Do not
silently regenerate an entire family or route the failure through an unrelated
action. The current [authored-unit restriction](../design/contracts/17-specify.md#L245)
must be explicitly amended before that behavior exists.

Canonical state already contains group arrays, but current validators permit only
one group per record. Inspect the final readback and identity consequences before
choosing a state version; do not infer that an unchanged JSON shape means an
unchanged contract. Reject superseded contracts without compatibility readers.
Retain atomic workflow publication, fresh invocation from `start` and the existing
clarification persistence exception.

### 5.5 Common measures: meaningful improvement and brittleness

The rollout is a sequence of evidence gates, not a commitment to deploy every
candidate. Each phase produces a reviewable result and an explicit **advance,
retain baseline, revise, or inconclusive** decision. Writing this plan completes
none of the phases. Track open implementation work in [FIX01](FIX01.md) and
completed records in [Z_FIX02](Z_FIX02.md); keep this document as the evaluation and
rollout design.

Use a complete source-backed duty set as the evaluation boundary. At diagnostic
scope this means the entire assigned record collection, including complementary
families. At product scope it means the actual published specification from the
complete selected workflow. Report those scopes separately. An AC-only result
cannot contribute a full-collection or workflow-completion success.

| Measure | Definition and denominator | What progress means |
| --- | --- | --- |
| First-pass fidelity | Proportion of well-posed attempted feature-generation workloads whose complete initial output preserves all required duties, conditions, exceptions, roles and support, without material invention; include every complementary assignment and score before correction or repair | Better generation; A's G assignments, C's one assignment and D's P assignments share the same feature denominator |
| Useful completion | Proportion of well-posed attempted feature executions that publish current, source-faithful output meeting the frozen rubric after the complete review/repair chain | Better delivered results; blocking every difficult input cannot inflate this rate |
| Clarification correctness | Correct specific unresolved decisions and permitted terminal outcomes on prelabelled gap/conflict cases; separately count false gaps on sufficient-source cases | Appropriate uncertainty handling, without treating clarification as completion |
| Material harm | Per-feature/workload-attempt incidence and exact counts of unsupported behavior, lost restrictions, wrong support, harmful diagnoses and harmful repairs, reported separately | Fewer substantive errors; extra provider calls cannot dilute the denominator or conceal deterioration in another category |
| Robust-case success | Proportion of attempted feature/repetition bundles whose original and predeclared variants all meet their respective semantic and terminal expectations | Correctness survives harmless changes and responds correctly to real requirement changes |
| Representation sensitivity | Material failures introduced by meaning-preserving variants whose original succeeds; show numerator, eligible-pair denominator and coverage in each arm, plus the common-original-success subset | A valid representation change causes fewer new failures; keep this separate from general fidelity |
| Repeat inconsistency | Proportion of independent features showing both semantic success and material failure across the same frozen number of identical-request repetitions | Less observed instability; consistently wrong responses still fail fidelity and robust-case measures |
| Finding-type accuracy | Proportion of review findings whose type (`supported`, `candidate_omission`, `candidate_invalid`, `unsupported`, inconclusive) matches the frozen source-based label for the assessed field; report each predicted type's precision and each labelled type's recall, at original and final assessment | Diagnoses route to the correct repair or clarification; a real defect reported with the wrong type counts as a harmful diagnosis |
| Mechanical enforcement | Accepted/rejected contract cases, provider/schema failures, correction recovery/exhaustion, state/origin/repair/publication invariants | Compatibility and enforcement only; passing tests does not establish semantic quality |
| Complete resource use | All physical sends, actual input/output tokens and elapsed time per attempted workload and per useful completion; show median and observed worst case | Benefit survives the cost of corrections, review, repair and failures; no cheap-looking partial workload |
| Stage resource share | Sends and actual tokens per stage (extraction/reconciliation, generation, review, repair) per attempted workload, including budget-stopped workloads | Identifies where cost and budget exhaustion arise; a generation saving cannot hide a review or repair increase |
| Admission escape | Proportion of attempted workloads in which a value violating a declared native composition or wire rule reached model review or publication, with the sends and tokens spent downstream of it; native rejections at admission are counted separately | Structural defects are stopped by their deterministic owner rather than discovered, misdiagnosed and repaired by model calls; a reduction here is mechanical evidence, not semantic quality |

A **material error** changes a required behavior, condition, exception, negation,
strength, actor, outcome, source association or necessary user decision. Harmless
paraphrasing and valid alternative scenarios are not errors. Freeze severity and
acceptable alternatives against original sources before seeing candidate results.
Do not use generated record counts, surviving extracted claims or keyword overlap
as the coverage denominator.

First-pass means the original model response for every required assignment in
the feature workload. Preserve its own assessment separately from corrected or
repaired output; corrected success cannot replace initial failure. A harmful later
review/repair retains its harm while initially faithful generation remains credited.
Issue events are cumulative; material-harm/false-gap incidence includes original
and final assessments. Report correction-assisted fidelity separately.
Per-assignment rates may diagnose a fixed purpose but cannot compare architectures
with different assignment counts. Robustness, sensitivity and repeat metrics in
the Phase 0 diagnostic scorer concern initial generation; final workflow outcomes
still require Phase 5.

Three different tests are needed to assess brittleness:

| Test | Controlled change | Expected evidence |
| --- | --- | --- |
| Repeatability | Same request, model and settings, with fresh authorized attempts | Record semantic pass/fail variability; do not require identical model prose |
| Meaning-preserving variation | Independently checked paraphrases, reordered independent source statements, supported formatting changes, or irrelevant context with no new obligation | Required meaning and appropriate outcome remain correct; preserve exact literals and meaningful ordering |
| Requirement sensitivity | Deliberately change a condition, exception, negation or required outcome, or remove necessary evidence | Output changes appropriately or asks the specific newly required question; consistently repeating the old answer is a failure |

Keep every variant in the same development or qualification partition as its
original feature. Native identities and evidence are regenerated through their
normal owners after input changes. Do not edit IDs by hand or expect unchanged
state IDs when source state changes. Compare meaning, not byte-identical model
text. Byte stability remains required for native rendering of the same accepted
payload. Invalid inputs belong in rejection tests, not in a claim that valid
input handling became brittle.

For progress decisions, use these proposed rules:

- **Mechanical gate:** all required owning-boundary and full verification checks
  pass, with no authority bypass, scope expansion, stale-origin acceptance or
  suppressed failure. A single demonstrated invariant violation blocks adoption.
- **Meaningful effect:** start with a minimum improvement of **10 absolute
  percentage points** in complete first-pass fidelity or robust-case success for
  diagnostics, and useful completion or robust-case success for product evaluation.
  The other primary measure must not decline. Require the gain to occur on at
  least two independent features from different domains. This is a proposed
  engineering threshold, not a research-derived reliability claim; change it only
  before freezing the comparison, with an explicit rationale.
- **Brittleness claim:** preselect representation sensitivity or repeat inconsistency
  as the primary brittleness measure and require at least a 10-point absolute
  reduction, with no loss in complete fidelity or robust-case success. A rise in
  all-variant success alone is improved robust performance, not evidence that
  sensitivity itself fell. For sensitivity comparisons, use the common-original-
  success subset, report both arms' eligible counts and freeze its minimum coverage;
  too few comparable controls means no brittleness claim. Requirement-changing
  controls must still meet their separate expected outcomes. A fidelity-only gain
  cannot be reported as demonstrated brittleness reduction.
- **Regression guard:** no newly introduced material failure on a previously
  faithful control, and no worsening material-harm or false-gap rate in any declared
  risk stratum. Preserve every observed regression for diagnosis; an overall mean
  cannot override it. Zero observed failures is reported with its sample count,
  not as proof of zero risk.
- **Absolute adequacy and cost:** freeze numeric minimum useful-completion and
  robust-success rates, maximum material-error rates, and allowed token/latency
  changes before dispatch. Relative improvement from a poor baseline is insufficient.
  Phase 0 fixes these values in its protocol; an unspecified “acceptable
  cost” or “good quality” cannot pass its gate. Resource criteria evaluate measured
  workload cost and do not add engine-local request-size limits or reservations.
- **Evidence sufficiency:** freeze development counts, repetitions, permitted early
  stops and a qualification-sizing rule in Phase 0. Use at least three repetitions
  for a development comparison intended to distinguish a recurring failure from a
  single draw; size qualification using
  baseline variability and the chosen effect threshold, then freeze exact
  qualification counts in Phase 2 before candidate selection or holdout access.
  Aggregate repeats and variants within their independent feature, then compare
  features with equal
  weight. Publish paired feature results and uncertainty, not just a pooled score.
  If the evidence cannot distinguish the required benefit from variability, the
  decision is inconclusive; do not add calls until a preferred answer appears.
- **Budget feasibility:** before Phase 2 dispatch, state which phases the
  experiment-wide send and token stops cover and project their demand from actual
  selected-binding usage, including full-workflow review and repair. Freeze the
  per-workflow token budget used by baseline and candidate builds. If the compiled
  workflow budget cannot complete the panel's full workflows, or the experiment-wide
  stops cannot cover the declared scope, record that as a required decision: raise
  the workflow budget through an explicit engine contract change, revise the
  experiment stops before freezing with an explicit rationale, reduce measured review
  or repair cost through its owner, or narrow the qualified scope. It is not
  permission to shrink the panel or to treat budget-stopped runs as completions.

All dispatched failures, malformed/truncated outputs and exhausted repairs remain
in the attempted-workload denominator. Genuine-gap cases use their separate
expected-outcome score. Record unattempted trials and unknown usage explicitly;
selectively incomplete pairs or missing required observations prevent promotion.
Evaluation expectations never enter generator inputs. Label model-assisted scoring,
blind arm labels where practical and resolve material scoring disagreements before
promotion. These rules refine the protocol in §4.7, not production authority.

### 5.6 Phased rollout and exit gates

#### Phase 0 — Make the evaluation executable

**Status: complete offline, 15 October 2026.** The concrete
[protocol](../test/calibration/semantic-simplicity/protocol.json),
[source-backed cases](../test/calibration/semantic-simplicity/cases.json),
[labelled specimens](../test/calibration/semantic-simplicity/specimens.json) and
[operating/scoring contract](../test/calibration/semantic-simplicity/README.md)
are implemented; the [retained results](../test/calibration/semantic-simplicity/phase0-results.md)
and the [implementation record](Z_FIX02.md#phase-0-implementation) hold the evidence. Eight development
and sixteen reserved qualification features each have three variants; three
repetitions of A/C give **144 development feature workloads**. The labels received a
separate model-assisted source review, not human approval. The prospective freeze
uses the selected GPT-OSS-20B binding.

The protocol fixes 85% initial fidelity, 75% robust success, 80% Phase 5 useful
completion, 5% maximum material-harm/false-gap incidence, a 10-point meaningful
effect/brittleness reduction, six common-original-success features, and maximum
token/latency ratios of 1.25/1.50. A seeded 10,000-resample paired feature interval
must have a lower bound above zero for a benefit claim; two unrelated feature
improvements and the no-material-regression rule also apply. Qualification sizing
is the frozen 8–16 feature planning approximation described in the operating
contract; inadequate precision or demand above 16 is inconclusive/infeasible,
never permission to shrink the panel after seeing results. Prospective experiment
limits are 1,000 sends and 2,000,000 actual tokens; `live_authorized` remains false.
These are proposed experimental gates, not production size limits or dispatch
approval. Only the selected Bedrock GPT-OSS-20B tuple is permitted for live tests.
The limits were frozen before any full-workflow cost was observed on the selected
binding and have not been reconciled with F9; the budget and scope decision in §5.5
must resolve this before dispatch.

**Deliverable:** a frozen comparison protocol, case inventory and scorecard using
existing calibration/harness owners. Include exact selected model identity/settings,
source bytes, expected duties and terminal outcomes, development/untouched
qualification partitions, variants, development counts, qualification-sizing rule,
numeric thresholds, maximum sends, actual-token stops and the feature-level
uncertainty/decision method.
Cover the source shapes in §5.1, including cross-group
conditions, several duties in one group, entities, exact values and genuine gaps.
Use unrelated domains and more than one feature size; record the intended scope
rather than implying coverage of every input.

**Test:** dry-run case loading, provider-neutral packet/fixture preparation, result
accounting and scoring aggregation without inference. The selected provider
binding is verified in Phase 1. Check prelabelled faithful/paraphrased, omitted,
invented, falsely clarified and harmfully repaired specimens. Verify that the
scorecard distinguishes structural success, semantic fidelity and publication;
fixture checks test accounting, while source labels still require semantic review.

**Exit gate:** every planned trial and source duty is accounted for; expected
outcomes and numerical gates are reviewable; no missing thresholds, mixed cohorts,
answer leakage or variant leakage into the holdout. Retain the protocol and dry-run
report. If labels or scoring remain disputed, revise the evaluator before changing
generation. This phase makes progress measurable; it establishes no model benefit.

#### Phase 1 — Establish compatible selected-model execution

**Status: offline implementation complete, 15 October 2026; bounded live gate passed,
16 October 2026, for the observed first request only.** The scenario prepares a
case's first production model request through the existing configuration, compiled
workflow, model-request preparation, authorization, Converse transport and capture
owners. It allows at most one physical inference send, with no retry, repair, judge
or workflow-publication authority, and keeps provider compatibility separate from
the interrupted workflow outcome. After separate explicit approval for the live
probe, use:

```sh
zig build provider-compatibility -- \
  --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json --live
```

The equivalent launcher is `./scripts/provider-compatibility.sh` with those same
arguments. There is no default case, and `--live` opts into dispatch but cannot
supply the user approval required by the model-conformance contract. Only the
selected binding is admitted, with no model, mode or settings substitution. The
[operating contract](../design/harness/e2e.md#test-one-fresh-provider-exchange)
defines its reports, and the
[offline evidence record](../test/calibration/semantic-simplicity/phase1-offline-results.md)
records the mechanical checks. The first HTTP-200 exchange exposed a
response-decoding defect, since corrected; the 07:46 exchange then passed candidate,
schema, usage and request-association checks. That qualifies only the observed
production request and settings, not every workflow request shape or semantic
quality. The [implementation record and probe history](Z_FIX02.md#phase-1-implementation-and-live-gate) are retained.

**Deliverable:** the selected binding's trusted registration and any required codec/
adapter support behind existing ports, with the generation assignment unchanged.
Verify official request, response, region, schema, reasoning, temperature, output
allowance, stop and usage contracts. Configure the validated catalogue and slot.
Any other model requires its own verified binding. Account access and IAM
permissions are preconditions to confirm outside the probe; 18 of the first 20 probes
were spent on access rejections (fifteen Luna, three GPT-OSS) that the probe cannot
diagnose.

**Test:** positive and negative provider/control cases, malformed and missing usage,
noncandidate stops, unknown model/region, cancellation, exact request association,
accounting and replay serialization. The bounded scenario additionally covers
first-send charging, second-send rejection, publication rejection before a child,
cancellation before/after dispatch, partial responses, transport failure and
capture/report failure without invented usage or success. Guard/preflight/argument,
classification and report-finalization tests belong to
`zig build test-provider-compatibility`. Fresh production runtime scenarios with
fake first exchanges belong to `zig build test-integration`; these exercise
configuration, request preparation, authorization, response identity and actual
accounting in unrelated domains. Neither suite supplies authentic provider evidence.
Run both, the provider suites in §5.7 and full
verification when the coordinated adapter change is complete. After separate
bounded live approval, capture an authentic exchange from the selected current
model using the production path; do not retarget a historical browser replay.

**Exit gate:** required offline checks pass and the live exchange has trustworthy
request/response/usage identity. Retain the compatibility report and authentic
capture. Advance with a provider-compatible baseline revision, not a semantic
quality claim. On incompatibility, repair the provider boundary; do not compensate
with generation prompts or a silent fallback model.

#### Phase 1A — Close the representation admission gap before the baseline

**Why it preceded Phase 2.** F10's composition failures are detectable by
deterministic code, recurred in every run that reached generation, and change which
candidates are admitted. Freezing a baseline before closing them would measure a
known enforcement gap, and closing them later would leave baseline and candidate
under different admission contracts. The phase is independent of the A/B/C/D choice
and adds no assignment, model call or semantic planner.

**Decided and implemented, 16 October 2026.** The user's implementation instruction
settled the field inventory, the exact-copy role of each field, the wire-syntax rule
with its exact-original-source exception, and the shared no-progress repair rule. The
accepted [composition contract](../design/contracts/text-field-composition.md)
records them; they amend §§7.1, 17.3 and 22 and ADR 0020. The offline replay rejects
all 29 captured F10 defects and admits all 50 prose-bearing controls, and full
verification passed with 156/156 steps and 1,699/1,699 tests.

**Exit gate: met offline; enforcement confirmed live.** On committed `bfec3d7`, the
16:20 diagnostic stopped the defect at admission and ran no review (F11). Generation
did not recover, which Phase 1A.2 addresses. The
[decisions, deliverable and implementation record](Z_FIX02.md#phase-1a-plan-decisions-and-results) are retained.

#### Phase 1A.2 — Make model-facing presentation consistent with admission

**Why it preceded Phase 2.** F11 showed admission enforcing the composition policy
while the schema, guidance, offered choices and repair packet contradicted it: the
presentation half of the same contract.

**Decided and implemented, 16 October 2026.** Under decision 1, approved by the user,
descriptive fields whose exact copies cannot satisfy coverage (title, goal,
entity-applicability basis, entity meaning, relationships, assumption and
clarification question) take a prohibited exact-copy role, and entity names keep the
identity-label exception. The decision is recorded in the
[composition contract](../design/contracts/text-field-composition.md#phase-1a2-amendment--exact-copies-only-where-they-can-carry-an-obligation)
and [ADR 0020](../design/decisions/0020-derived-exact-reference-lineage.md).
Per-field schemas, selected guidance and offered choices are projected from the field
registry for generation, protocol correction and every repair route, and
engine-produced values carry a native origin so that admission escape can report
measured zero. The change is committed as `2e64a31`, and full verification passed
with 156/156 steps and 1,718/1,718 tests. Its rendered composition-repair
presentation was later removed by Phase 1A.3.

**Exit gate: open.** One separately approved diagnostic each for hello-world and
loan-renewal on a committed build. Each must either admit the brief and story with
prose, or end in a typed composition failure after a correction whose presentation
differed materially, with admission escape measured zero. The 18:58 run met the
hello-world criteria in substance (F12), but on uncommitted code. Phase 1A.3's exit
gate closes this gate too. This is mechanical evidence, not quality. The
[full plan and implementation record](Z_FIX02.md#phase-1a2-plan-decisions-and-results) are retained.

#### Phase 1A.3 — Attribute insertion presentation and repair collapsed units as units

**Why it precedes Phase 2.** F12 shows the composition failure concentrated in
obligation-bearing record fields, with a plausible but unattributed presentation
cause, and a repair granularity that could not recover a unit-wide collapse. Both
change which candidates are admitted, so the baseline must be frozen after them.
Under §1.1 this is the last prerequisite sub-phase.

**Steps:**

1. **Commit Phase 1A.2 and rerun its gate on the committed build.** Committed as
   `2e64a31`; the rerun is part of this phase's exit gate.
2. **Attribute before changing presentation, through separately approved diagnostic
   replays.** **Prepared offline; 21 sends await approval.** The
   [prepared experiment](../test/calibration/insertion-presentation/README.md) replays
   the 18:58 run's records request (call 13) unchanged and in four presentation
   variants: without `insertion_fields`, with `field_rules` grouped by instruction,
   with both changes, and without the obligation wording. It also replays the
   extraction request (call 1) with and without its field rules and insertion list,
   to test the claim merging. Model, settings, evidence and schema stay identical,
   with three repetitions per arm, and the insertion-only rate is recorded per field
   and arm. The replays use the
   [single-request debugger](../design/decisions/0019-single-request-debugger.md) and
   carry no workflow authority.
3. **Correct presentation at its owner, as the attribution indicates.** In
   `model_field_presentation.zig`, state the composition rule once (prose is required;
   a permitted exact copy goes inside a sentence and never forms the whole value), list
   fields only where that changes the answer, remove duplicate rules, and describe
   permission without obligation wording. The selected schema stays the authority for
   what is permitted. No field-, case- or model-specific text. If the attribution shows
   no presentation effect, record that decision instead of changing the wording.
4. **Decide the repair granularity for composition failures. Decided and implemented:
   option (a), approved by the user, 16 October 2026.** Composition rules are checked
   at response admission for every response type, and one rejection reports every
   violating field. Correction uses the existing bounded protocol correction with the
   complete request, and unit repair no longer receives composition defects. The
   amendment is recorded in the
   [composition contract](../design/contracts/text-field-composition.md#phase-1a3-amendment--composition-defects-are-corrected-as-a-unit)
   and [§22.4](../design/contracts/22-repair.md#224-repair-request-and-response). It is
   committed as `6676ad8`; full verification passed with 156/156 steps and
   1,734/1,734 tests, and the retained replay now includes the 18:58 captures.
5. **Measure entity applicability as its own failure class.** No native rule can judge
   it. Record false-required applicability and its downstream cost in Phase 2
   attribution, and do not narrow the entity-name exception on this evidence.
6. **Keep** temperature, retry allowances and the envelope normalizer unchanged, with
   no field- or model-specific code.

**Test:** presentation projection tests for the chosen wording and deduplication at
the same owner, then `zig build verify --summary all`. The routing tests and the
extended replay already pass.

**Exit gate:** the attribution sends are scored and step 3 is applied or explicitly
declined; the result is committed with offline checks passing; then one separately
approved diagnostic each for hello-world and loan-renewal runs on that committed
build. Each must either admit records with prose, or end in a typed composition
failure after the bounded protocol correction with the complete request, with
admission escape measured zero. This also closes Phase 1A.2's live gate. It is
mechanical evidence, not quality. A run that ends in that typed failure is a baseline
result under §1.1, not a reason for another prerequisite sub-phase. The
[full plan and implementation record](Z_FIX02.md#phase-1a3-plan-and-decisions-as-approved) are retained.

#### Phase 2 — Establish baseline quality and failure sensitivity

**Deliverable:** an unchanged-generation baseline report for the selected model on
the development panel, including original, repeated and transformed inputs.
Freeze a committed provider-integrated baseline revision for later comparison;
runs on differing uncommitted builds, such as the 16 October diagnostics, cannot
form the baseline. Distinguish controlled-predecessor diagnostics from complete
production runs using actual predecessors; obtain the required live approvals for
each scope.

**Prerequisite:** close Phases 1A.2 and 1A.3 (§1.1) and record the budget and scope
decision in §5.5. With the compiled 100,000-token workflow budget, complete
production runs ended in budget exhaustion during review (F9), and part of that
review cost followed defects that native admission now rejects (F10). Since
Phase 1A, runs fail earlier, at generation (F11 and F12), so no complete-run cost has
yet been observed. The decision belongs to the user, can be made now, and must be
recorded before the baseline is frozen; re-measure feasibility under it after
Phase 1A.3.

**Test:** measure every §5.5 outcome, audit material disagreements between evaluation
and source expectations, and identify reproducible failure classes. Record whether
loss begins in extraction/grouping, generation, representation/admission, review or
repair, and report stage resource share, admission escape and finding-type accuracy
for complete production runs. Attribute a defect to the first stage that could have
stopped it deterministically, not to the first model call that noticed it. An
oracle-corrected requirement list cannot conceal an upstream failure. Keep
qualification cases and results unavailable for prompt/design tuning.

**Exit gate:** the predeclared evidence is sufficient to identify current headroom,
variability and resource use. Retain per-feature scores, source-backed error examples
and stage attribution. Apply the frozen sizing rule and record exact qualification
counts before candidate selection or holdout access. If the required evidence
cannot fit the allowed dispatch budget, report qualification as infeasible under
that budget rather than reducing the sample after seeing results.
If the baseline already meets adequacy/robustness targets
and there is no meaningful improvement to test, retain it and stop the redesign.
If the source of failure or scoring is unresolved, investigate that boundary;
do not start a family scheduler merely because the original panel failed.

**Harness: implemented, 16 October 2026.** The development-only
[baseline harness](../test/harness/baseline/cli.zig) separates offline budget
preparation, explicitly approved serial production acquisition and offline
source-backed assessment. The
[operator guide](../test/calibration/semantic-simplicity/README.md#prepare-acquire-and-assess-phase-2)
describes its commands and retained evidence. Freezing requires a committed build,
an explicit recorded budget decision and sufficient native full-workflow cost
evidence; the current
[feasibility report](../zig-out/baseline/2026-10-15T22-38-08Z-4ae44015f25ecde96580bc1c4c065da1/budget-feasibility.json)
is `insufficient`. The [implementation record, audit and cost investigation](Z_FIX02.md#phase-2-harness-implementation)
are retained. These mechanics do not close this phase's live evidence or semantic
exit gate.

#### Phase 3 — Select an assignment boundary through diagnostics

**Deliverable:** one bounded A/C complete-record comparison, with B considered only
for reproduced mixed-purpose errors and D only when combining changes is justified.
Keep the selected model, evidence, settings and scoring fixed; counterbalance request
order. Disclose C's support selector and output-scope changes as one intervention
package, as required by §5.2. Do not attribute its gain to one hidden reasoning step.

**Test:** compare complete-duty fidelity, robust-case success, material errors and
resources against A on the development panel. Preserve requested-purpose failures
and native rejections. B's AC projection remains a component score; assess all
complementary work before selecting a production decomposition. Candidate changes
start a newly frozen experiment rather than rewriting an existing comparison.

**Exit gate:** the chosen complete candidate meets the meaningful-effect and
regression gates within its declared scope and cost, or the decision is retain
baseline/revise/inconclusive. Retain exact serialized requests, authentic diagnostic
responses, paired scores and the selection rationale. Passing justifies implementing
one contract; it does not establish workflow qualification or confer producer
origins on replay results. No gain means no decomposition rollout.

#### Phase 4 — Implement the complete owning contract and prove enforcement

**Deliverable:** the governing amendment and one coherent implementation of the
selected design. Define manifest/assignment identity, support selection, empty
outcomes, completion, assembly/origins, correction/retry identity, invalidation,
repair and stored readback. Update §5.4's consumers together and record any
state-contract change. Retain Proposed status outside the specific amendment.

**Test:** positive and negative cases for joint support, legitimate overlap, empty
optional outputs, missing required families/entities, missing/duplicate/foreign
results, stale dependencies, unknown fields, invalid positive associations,
correction identity, exact values, canonical ordering, repair bounds, unchanged
siblings and readback. Inject publication failures and interruptions; prove no new
successful completion and fresh rerun behavior. Verify applicable downstream gates.
Run targeted generation/lifecycle suites, architecture checks and `zig build verify`.

**Exit gate:** all required tests pass, the complete diff preserves shared ownership,
and replaced runtime machinery/fixtures/descriptions are removed in the same cutover.
Keep incomplete work in development; introduce no production legacy path, dual
reader or fallback flag. Retain the contract-to-test map and verification results.
This establishes mechanical safety only. A failure returns to its owning contract,
never to a weaker validator or broader repair permission.

#### Phase 5 — Qualify the complete production workflow

**Deliverable:** a paired baseline/candidate qualification report on untouched
features, including the frozen variants and repetitions. Use the same selected model,
settings and frozen workflow token budget for both builds, actual generated
predecessors, fresh workflow-origin
candidates, normal review/repair, publication and the actual-output rubric. The
retained baseline runs in an isolated checkout/target; it is not a production
compatibility branch, and no persisted state is transferred between contracts.

**Test:** separately approve each live E2E run with its explicit case and target.
Score first-pass fidelity and published useful completion separately; include
harmful diagnoses/repairs, false gaps, blocked/failed runs and all resource use.
Budget-stopped runs remain failed attempts in the denominator.
Check that improvements seen with controlled predecessors survive the real upstream
pipeline. Grade only output attributable to the current execution, never stale
files left by a failed run. Apply the appropriate expected outcome to genuine gaps.

**Exit gate:** absolute adequacy, meaningful improvement, robustness, material-harm
and resource criteria all pass with sufficient paired evidence. The workflow's
published-output rubric is complete; successful generation with failed evaluation
is incomplete qualification. Report exactly which model, workflow and input scope
passed, and separately whether the brittleness-reduction gate passed. If reduced
brittleness is a required rollout outcome, a semantic-only gain leaves that outcome
open. If holdout failures are used for tuning, move those cases to regression
coverage and obtain fresh untouched qualification cases. Otherwise stop or revise
at the diagnosed owner; do not change thresholds, retries or models after the fact.

#### Phase 6 — Adopt the qualified scope and expand one dimension at a time

**Deliverable:** a bounded adoption decision identifying the qualified workflow,
selected model/version, source shapes, feature sizes, evidence and known limitations.
Use the single validated implementation. This is a scope-of-evidence statement,
not a fixture-specific runtime branch or a claim that every workflow is qualified.
External release/publication remains a separately authorized action.

**Test:** retain source cases and valid transformations as regression evidence.
For each expansion, change one declared dimension—such as a larger feature range,
another domain or another model—and repeat the applicable baseline and complete
qualification gates. Each model's result stands alone; another model's gain cannot
qualify it. The GPT-OSS-20B-only live-test constraint
remains in force; another model needs explicit changed scope. Recheck model
generations at execution time.

**Exit gate:** each expanded scope meets absolute adequacy, robustness,
non-regression and cost requirements; otherwise retain the narrower qualified
scope. Require a new meaningful-effect demonstration only when claiming an
improvement for that cohort or changing the design, not another 10-point gain on
an already near-perfect case. Changes to provider/model contracts return through
Phase 1; prompt, schema, assignment, evidence or repair changes
reopen affected offline and semantic gates. A moving model alias limits reproducibility
and requires fresh controls rather than assumed continued qualification.

On a material regression, halt further adoption, preserve evidence and return to
the lowest owning phase. Any reversal must restore a coherent implementation;
do not add runtime fallback paths or load incompatible state. New invocations
start at `start`, with the existing clarification protections. Publication failure
may leave replaced files but never new completion authority; this plan adds no
automatic file rollback or resumable phase checkpoint.

### 5.7 Verification commands and phase evidence

Use the repository's registered build steps. This table maps future phase checks;
[Z_FIX02](Z_FIX02.md#5-fix04--completed-evaluation-foundation-compatibility-and-admission-work-1516-october-2026) and the retained Phase 0 results record the verification
actually executed:

| Phase/boundary | Existing verification entries |
| --- | --- |
| Offline evaluation protocol and labelled accounting | `zig build test-rubric-evaluator`, `zig build test-integration` |
| Fresh one-send compatibility scenario, offline | `zig build test-provider-compatibility` (guards/CLI/report), `zig build test-integration` (fresh production runtime/fake exchange), `zig build test-provider-compatibility-launcher`, `zig build smoke-provider-compatibility` |
| Provider and request compatibility | `zig build test-provider-conformance`, `zig build test-provider-invocation-validation`, `zig build test-model-request-preparation`, `zig build test-model-request-workflow` |
| Source packets, generation and response contracts | `zig build test-reference-model-input`, `zig build test-specification-generation`, `zig build test-specification-contract` |
| Representation admission contract (Phase 1A) | `zig build test-typed-text`, `zig build test-model-envelope`, the source-packet and repair entries in this table, and `zig build test-integration` for the [retained F10 admission replay](../test/calibration/representation-admission/README.md); no model call is made |
| Composition correction and presentation attribution (Phase 1A.3) | `zig build test-model-envelope`, `zig build test-attribution-replay` and `zig build test-integration`; `zig build attribution-replay --` with `prepare`, `validate` or `score` prepares and scores the [attribution panel](../test/calibration/insertion-presentation/README.md) offline. Its approved sends use the single-request debugger, not this tool |
| Repair, runner, identity and lifecycle | `zig build test-workflow-repair-retry`, `zig build test-workflow-graph`, `zig build test-pipeline-envelope`, `zig build test-atomic-execution`, `zig build test-architecture` |
| Completed coordinated implementation | `zig build verify`, including offline integration and clean-directory native packaging checks |
| Separately approved authentic Phase 1 exchange | `zig build provider-compatibility -- --case <explicit-approved-case-path> --live`; at most one physical inference send, no judge or publication authority |
| Approved full-workflow qualification | `zig build e2e-spec -- --case <explicit-approved-case-path>` with the required configuration and per-run approval; never an automatic verification dependency |

See [build registration](../build.zig#L669), the
[live harness contract](../design/harness/e2e.md), and
[model-conformance rules](../design/contracts/28-testing.md#288-model-conformance-comparisons).
Extend tests at existing owners where the selected contract requires new cases;
a command passing today does not prove a future contract is covered.

Every phase decision should link its revision, protocol, case partition, model and
settings, exact commands or live manifest, attempted/unattempted counts, scorecard,
regressions, unknowns and next decision. Keep **implementation complete**, **mechanical
checks passed**, **semantic benefit demonstrated**, **brittleness reduced**, and
**scope qualified** as separate evidence statements. More passing unit tests, fewer
calls or higher schema admission alone cannot close the semantic rollout.

## 6. Review delivery and remaining uncertainty

The analysis inspected current assignment, evidence, review, generation and provider
owners; relevant accepted amendments; historical report/fixture provenance; and
current primary release/benchmark sources. Older model research is excluded from
capability conclusions. No inspected study directly qualifies the proposed
assignment granularity for the selected model. Detailed live benchmark artifacts
were not fully retrievable, and no public experiment was independently reproduced.
Historical model-quality numbers retain their original assessment limitations
and are not used to select the new architecture.

Delivered so far: Phase 0's closed evaluation contracts and offline scenario; the
separately requested Bedrock Converse transport, with typed reasoning retention and
the pre-credential live-test cost policy; Phase 1's bounded compatibility scenario
and the Converse usage-metadata correction; the Phase 2 baseline harness; and the
Phase 1A to 1A.3 composition admission, presentation and correction changes. No
production dependency was added. Each change's verification, its exact commands and
the live records are in [Z_FIX02](Z_FIX02.md#5-fix04--completed-evaluation-foundation-compatibility-and-admission-work-1516-october-2026). Test counts differ between commands
and revisions, so they are not comparable.

The live work of 15–16 October was separately authorized: twenty-two one-send
compatibility probes, three of them `compatible`, and five full-workflow development
diagnostics, none of which published a specification or ran rubric evaluation. No
live debugger replay has been performed. Source labels, review and the F9–F12
semantic interpretations remain model-assisted or reviewer readings of retained
outputs. Phases 1A to 1A.3 add mechanical evidence about where defects stop. No
semantic benefit, reduced brittleness or useful publication is claimed, and
historical results remain immutable.
