# FIX04 — Critical review of semantic simplicity and generation feasibility

**Reviewed:** 15 October 2026, Australia/Melbourne.

**Current test selection — 16 October 2026:** The user switched back to
**Bedrock GPT-OSS-20B**: `aws-bedrock / openai.gpt-oss-20b-1:0 /
ap-southeast-2`, Converse, native JSON Schema, explicit low reasoning,
engine-fixed temperature `0.1` and 16,384 requested output tokens. This
supersedes the review's Luna-only selection and omitted-control instructions.
The prospective protocol and live fixtures use this binding; the retained
15 October Phase 0/1 reports and snapshots keep their historical Luna context.
Their results do not qualify the newly selected binding. The configuration switch
itself authorized no live run; a later separately authorized exchange passed the
bounded compatibility gate as recorded below.

**Current response-decoding correction — 16 October 2026:** the
[07:29 Melbourne attempt](../zig-out/provider-compatibility/2026-10-15T20-29-20Z-a99ee228b9e19af49dd6e2784a35b700/report.json)
received HTTP 200 with 2,254 reported tokens. The shared decoder rejected
`usage.serverToolUsage: {}` before accounting or candidate inspection. The
[provider contract](../design/features/F0007-AWSBedrockProvider.md#response-failure-and-accounting)
now explicitly supports this closed empty metadata object and retains precise
rejection diagnostics for unsupported shapes. The existing approved `{"{` prefix
normalizer is unchanged. Captured-response offline regression is mechanical
evidence; no new live call or semantic-quality qualification follows from this fix.

**Current live evidence — 16 October 2026:** run details and exact commands
are recorded in [FIX01](FIX01.md#2-implementation-history); this summary records
their evaluation scope. Twenty bounded compatibility probes ran between 15 October
16:25 and 16 October 07:46 Melbourne. Fifteen Luna and three GPT-OSS attempts
received HTTP 403 `AccessDeniedException` from account access or IAM policy; they
are inconclusive and reported no usage. One GPT-OSS HTTP-200 exchange exposed the
decoding defect above. The separately authorized
[07:46 Melbourne probe](../zig-out/provider-compatibility/2026-10-15T20-46-55Z-cb4fdfbfe3b6aff88bc99e68fa980506/report.json)
was compatible for its first production request: HTTP 200, accepted JSON/schema,
2,254 accounted tokens and the existing prefix normalization. The one-send stop
intentionally cancelled the workflow; it published no specification and ran no
rubric evaluation.

Two separately authorized loan-renewal full-workflow runs followed. They are
**development diagnostics, not Phase 2 baseline evidence**: loan-renewal is outside
the Phase 0 case panel, and both ran on uncommitted builds of `4f25a06` with
different source identities. The
[07:54 run](../zig-out/e2e-spec/2026-10-15T20-54-21Z-5f6e903390f38938113712b53a359de4/report.json)
(source `abf965…`) blocked on competing duplicate records at
`UnsafeSpecificationRepair`, before source review, after 13 calls and 25,508 tokens.
Native reference review subjects were then aligned with omission localization under
existing authority; this does not change per-group record authoring or authorize
competing-record repair. The
[08:09 post-fix run](../zig-out/e2e-spec/2026-10-15T21-09-33Z-3a7ceed77cb237531019300e1005152d/report.json)
(source `fbb975…`) failed with `WorkflowTokenBudgetExceeded`: 37 calls and 101,002
tokens against the compiled 100,000-token workflow budget. It stopped during entity
source review, before the corrected native reference reviews, with no candidate
repair, specification publication or rubric evaluation. Live validation of that
correction and full-workflow acceptance remain open. [F9](#f9--high-selected-binding-full-workflow-diagnostics-expose-generation-review-and-budget-failures)
records what these runs show.

A third separately approved full-workflow diagnostic, the
[09:18 hello-world run](../zig-out/e2e-spec/2026-10-15T22-18-35Z-a8740d575019326cb5b63f994c3dc426/report.json)
on an uncommitted build of `94e2838…` (source `2a30ee8d…`), failed with
`WorkflowTokenBudgetExceeded` after 41 calls and 101,134 tokens; review used 77%
([Phase 2 audit](FIX04-phase2-audit.md),
[cost investigation](FIX04-phase2-cost-investigation.md)). Its first defect was not
the malformed JSON at call 22 that the report labels `first_observed_defect`, but
call 8's story, made only of two exact-copy insertions and admitted by native
validation. [F10](#f10--high-model-text-composition-is-not-admitted-against-its-field-purpose)
traces that failure class through every run that reached generation and sets out
the architecture-level change. After the correction, `zig build verify --summary all`
passed 149/149 steps and 1,555/1,555 tests, including native packaging smoke. The
155/1,786 count in §5.6 comes from the wider Phase 1 command
`test-provider-compatibility test-rubric-evaluator verify`, so the two counts are
not comparable.

After Phase 1A was committed as `bfec3d7`, two more one-send probes (13:55 and 16:16)
were `compatible`, the second on the clean committed build. The separately approved
[16:20 hello-world run](../zig-out/e2e-spec/2026-10-16T05-20-15Z-44b2ac5e19cbf8d2ade89b149aed73c8/report.json),
the first full workflow on a committed build and the first after Phase 1A, failed with
`RepairNoProgress` after 8 calls and 12,896 tokens. Native admission rejected the
brief's insertion-only title at call 7, before any review, and the unit repair at
call 8 returned the same value.
[F11](#f11--high-admission-now-stops-the-defect-but-generation-cannot-recover-from-it)
records why and the Phase 1A.2 remediation.

**Repository revision:** findings were first reviewed at
`5816d9bed631acabcb256025e911bb565b8f9771`. The 16 October evidence ran on uncommitted
builds of `4f25a0603d14b1d7413f3e992e53c931c97c40eb` and, for the 09:18 diagnostic,
`94e2838999a889d4b9ea01eeab23bf758f39a1a9`. Phase 1A is committed as
`bfec3d7f39a4dd25b6d3673206327d4e4c1e92db`, on which the 16:16 probe and 16:20
diagnostic ran unmodified. Each report records its exact source identity.

**Status:** **Phase 0 complete (offline), 15 October 2026**; its
concrete protocol and evidence are linked in §5.6. The user-directed Converse
cutover and small-model test cost policy are included. **Phase 1's offline
implementation is complete and mechanically verified**: a fresh production-request
compatibility harness has a one-send boundary. Its authentic separately authorized
GPT-OSS-20B exchange passed the bounded compatibility gate on 16 October. No full
workflow has completed on the selected binding. **Phase 1A's implementation and
offline exit gate are complete, 16 October 2026**: its accepted composition
contract, retained replay and 1,699 passing verification tests are recorded in
[the implementation evidence](FIX04-phase1a-implementation.md). Its live mechanical
behavior is confirmed on committed `bfec3d7`: the defect stopped at admission and the
run ended early with a typed failure. Generation did not recover, because the
model-facing presentation still offers and encourages the rejected shape (F11), so
**Phase 1A.2** must close before the Phase 2 freeze. Phase 2's harness is
implemented, but its baseline remains unfrozen pending Phase 1A.2 and renewed budget
feasibility with the recorded user decision. Semantic benefit and reduced
brittleness remain unmeasured.

This review evaluates the supplied recommendations: retain single responsibility
for software, make model assignments semantically simpler, keep related meaning
together, and leave bookkeeping and authority with deterministic code. At review
time the test constraint was **current-generation Luna only on Bedrock**, with **Sonnet,
Sol and Haiku excluded**, and the retained Phase 0 evidence froze
`global.openai.gpt-6-luna`. Luna was never available to the test account, and the
16 October selection above replaces it with GPT-OSS-20B. Historical GPT-OSS panels
are therefore same-model evidence, but they ran under superseded engine contracts
and codecs. They supply regression cases and plausible failure classes; they do not
establish the current contract's defect rate or select an architecture (F7).
Generation quality remains the primary outcome; an improved reviewer alone does not
satisfy it, and a broken reviewer can prevent good generation from completing (F9).

The user has authorized a larger change if necessary and requested its steps and
supporting research. Section 5 therefore describes the complete change surface;
size alone is not a reason to stop or request the same authorization again. The
current implementation delivers the offline evaluation foundation and the
separately requested Bedrock Converse transport, including typed reasoning
retention, registration and live-test cost enforcement. The subsequent Phase 1
implementation prepares a fresh production request and retains bounded provider
compatibility evidence without publication authority. Generation prompts,
assignment topology and semantic admission rules are unchanged; F10 proposes an
admission contract change that is not implemented. The explicit
transport amendment does not accept the overall **Proposed design**.
[FIX01](FIX01.md) remains the active implementation
backlog under the [fix-record convention](README.md). This report supplies findings
and decision criteria, not a parallel progress checklist.

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
comparison cannot address it and would inherit it. Close it through the shared
owners before the Phase 2 baseline is frozen, so that every arm runs under the same
admission contract.

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
experiments unqualified. See [FIX03's amendment](FIX03.md#L1894) and
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
[14 October delivery record](FIX03.md#L1904). The representation is accepted, but
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
[FIX03 §3.2](FIX03.md#32-benchmark-responsibility-is-not-fully-aligned-with-assigned-review-scope),
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
[authoring investigation boundary](FIX03.md#L1919).

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
same-task improvement or regression. [Recorded comparison](FIX03.md#21-the-two-latest-panels-test-different-responsibilities).

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
context cannot be asserted as the cause. [Retained case](FIX03.md#L2200).

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

The two 16 October loan-renewal runs are the only full-workflow evidence on the
selected binding. They are development diagnostics on one five-requirement case
([source](../test/e2e/wf-002-loan-renewal/stories.md)), not a baseline or a rate.
Model outputs are untrusted candidates. The classifications below are this
review's source-based reading, not human adjudication.

**Generation: per-group authoring re-drafts the whole feature.** In both runs, each
record batch re-authored the same renewal acceptance criterion and functional
requirement instead of its assigned group's duties. At 07:54 the group-2 batch
([call 13](../zig-out/e2e-spec/2026-10-15T20-54-21Z-5f6e903390f38938113712b53a359de4/evidence/generation/call-000013/model_output.txt))
nearly reproduced group 1's records
([call 12](../zig-out/e2e-spec/2026-10-15T20-54-21Z-5f6e903390f38938113712b53a359de4/evidence/generation/call-000012/model_output.txt));
native admission rejected them as `competing_records` and blocked the run. At 08:09
all three batches emitted overlapping renewal AC/FR records whose wording differed
enough to be admitted as distinct, so each near-duplicate then needed its own
source review. The same run's brief titled the feature `Loan renewed!Renewal refused.`,
two exact-copy literals in place of a name. The entity pass created a `Loan` entity
with a "has a renewal status" relationship that the source does not state. This is
selected-binding evidence for the source-group ownership risk in F1 and §4.3. It
supports running the A/C comparison first, because C removes the per-group
authoring boundary; it does not show that C will succeed.

**Review: wrong finding types, confirmed downstream.** Before the budget stop,
review returned 27 findings: 20 `supported`, 3 `candidate_omission`,
1 `candidate_invalid` and 3 `unsupported`. None of the three omissions described
source meaning missing from the candidate:

- [call 13](../zig-out/e2e-spec/2026-10-15T21-09-33Z-3a7ceed77cb237531019300e1005152d/evidence/generation/call-000013/model_output.txt)
  reported the invalid title, which is a `candidate_invalid` defect;
- [call 28](../zig-out/e2e-spec/2026-10-15T21-09-33Z-3a7ceed77cb237531019300e1005152d/evidence/generation/call-000028/model_output.txt)
  reported a renewal-status attribute that the source does not establish;
- [call 33](../zig-out/e2e-spec/2026-10-15T21-09-33Z-3a7ceed77cb237531019300e1005152d/evidence/generation/call-000033/model_output.txt)
  gave as its `missing_obligation`: "No source requirement for the business
  meaning of Loan is present in the original source."

The bound-preservation comparisons
([14](../zig-out/e2e-spec/2026-10-15T21-09-33Z-3a7ceed77cb237531019300e1005152d/evidence/generation/call-000014/model_output.txt),
[29](../zig-out/e2e-spec/2026-10-15T21-09-33Z-3a7ceed77cb237531019300e1005152d/evidence/generation/call-000029/model_output.txt),
[34](../zig-out/e2e-spec/2026-10-15T21-09-33Z-3a7ceed77cb237531019300e1005152d/evidence/generation/call-000034/model_output.txt))
returned `lost` for all five assessments, which is F4's risk observed on the
selected binding. The three `unsupported` findings ask the user to define entity
content the generator invented; admitted as clarifications, they would be false
gaps. Had the budget allowed, these findings would have driven repair or
clarification from false premises. F6 applies directly: finding type selects the
repair or clarification route, so a real defect reported with the wrong type is a
harmful diagnosis.

**Cost and budget: review dominates, and the workflow cannot finish.** In the 08:09
run, extraction through validation used 6 calls and 8.8k tokens (9%), generation
6 calls and 16.8k tokens (17%), and source review 25 calls and 75.4k tokens (75%).
Review then stopped before the signal, token and conflict assessments. The
13 October hello-world diagnostic, under an earlier contract, also exhausted the
budget, with review using about 78k of its 100k tokens. The 100,000-token budget is
a compiled engine constant
([core operations](../src/composition/core_workflow_operations.zig#L35),
[native operations](../src/composition/native_workflow_operations.zig#L641)), not
case configuration. At current review cost every full workflow on the development
cases would end `failed` on budget, so Phase 5 useful completion would measure the
budget rather than quality. The protocol's experiment-wide stop of 2,000,000 actual
tokens and 1,000 sends includes review and repair, and covers fewer than 20 full
workflows at 100k tokens or more each. Phase 5 alone needs 144–288 paired full
workflows (8–16 features × 3 variants × 3 repetitions × 2 builds), and Phase 2
also requires complete production runs.

**Implication:** generation decomposition alone cannot produce useful completions
while review cost and diagnosis quality are unmeasured. Phase 2 must attribute
failures and cost to review and repair as well as generation, measure finding-type
accuracy (§5.5) and settle budget feasibility before dispatch. Raising the compiled
budget is an engine contract change, not a test-configuration adjustment. It needs
an explicit decision and must be frozen before the baseline, so that baseline and
candidate share it. Do not raise it automatically to obtain a completion, and do not
weaken review gates to save tokens. Part of this review cost begins earlier, with
defects native admission should have rejected (F10).

### F10 — High: model text composition is not admitted against its field purpose

This finding describes the retained diagnostics before the Phase 1A amendment.
The [completed implementation and offline evidence](FIX04-phase1a-implementation.md)
record the current enforcement; historical report field names and captures below
remain unchanged.

**Observed chain (09:18 hello-world diagnostic).** Call 8 asked for the primary user
story, whose purpose is "one narrative describing the actor or system identified by
the source, its action and intended result". The model returned
[`{"fragments":[{"kind":"exact_copy"},{"kind":"exact_copy"}]}`](../zig-out/e2e-spec/2026-10-15T22-18-35Z-a8740d575019326cb5b63f994c3dc426/evidence/generation/call-000008/model_output.txt):
no prose, and the sole eligible token inserted twice, rendering
`Hello, World!Hello, World!`. Native admission accepted it. Source review
(call 15) correctly saw a defect but reported an omission whose "obligation" was the
engine's own narrative instruction; loss localization (call 16) confirmed it; the
omission repair (call 36) returned the same two insertions, merged with
`changed: false`; and re-review (calls 37–41) ran until the 100,000-token budget was
exhausted. Together these cost about 23,000 tokens: 4,682 for the misdiagnosis
(calls 15–16) and 18,316 for the unchanged repair and the five reviews it triggered,
as the cost investigation measured. That is observed cost, not evidence that the run
would otherwise have completed.

**This is a recurring failure class, not a story defect.** Every full-workflow run
that reached generation under the 14 October model-text representation shows one or
both of two inverse composition failures on the selected binding:

| Run | Values made only of insertions | Insertion syntax typed inside prose and admitted as text |
| --- | --- | --- |
| [13 Oct 22:02 UTC, hello-world](../zig-out/e2e-spec/2026-10-13T22-02-37Z-b20ce81708023ac1030af300c845affa/report.json) | brief title, story, omission repair (calls 7, 8, 40) | calls 7, 11, 13 |
| [13 Oct 22:03 UTC, loan-renewal](../zig-out/e2e-spec/2026-10-13T22-03-58Z-facbd733ec967b7453a85ef64d4bb571/report.json) | story (8) | calls 10, 11 |
| [15 Oct 20:54 UTC, loan-renewal](../zig-out/e2e-spec/2026-10-15T20-54-21Z-5f6e903390f38938113712b53a359de4/report.json) | story (10) | calls 9, 12, 13 |
| [15 Oct 21:09 UTC, loan-renewal](../zig-out/e2e-spec/2026-10-15T21-09-33Z-3a7ceed77cb237531019300e1005152d/report.json) | title `Loan renewed!Renewal refused.` and story (7, 8) | calls 10–12 |
| [15 Oct 22:18 UTC, hello-world](../zig-out/e2e-spec/2026-10-15T22-18-35Z-a8740d575019326cb5b63f994c3dc426/report.json) | story, entity-applicability basis, omission repair (8, 9, 36) | — |

The second column means wire syntax became business text. For example, the 21:09
run admitted the acceptance criterion "…displays the message
`{"fragments":[{"kind":"exact_copy","claim_id":2}] }` along with the new due date",
and source review judged most such fields `supported`. Counts come from a scan of
retained model outputs; they describe five development diagnostics on two cases,
not a population rate.

**General invariant.** A declared text field's admitted value must be able to
express that field's declared purpose. Typed insertions are exact-value and
reference evidence placed inside meaning, not a substitute for it, and the model's
wire syntax never becomes business text. One owner must declare this per field and
apply it identically to initial authoring, protocol correction, every repair route,
collection coverage and stored readback. [Design §7.1](../design/contracts/07-domain-representations.md#71-shared-types)
already states the intent ("Exact copies can appear within a sentence"), and
[§17.3](../design/contracts/17-specify.md#173-llm-work) says "a reference alone does
not describe behavior or a goal" and "literal values alone do not replace the
behavior involving them". It also says that guidance "is not a deterministic
semantic validator". The structural part of it, whether any prose exists at all, is
deterministic and is currently unowned.

**Where the architecture lets the failure through:**

| Layer | Current behavior | Gap | Required change at the owning boundary |
| --- | --- | --- | --- |
| Field-purpose contract | Purposes are prose strings in [required_authority_description.zig](../src/domain/required_authority_description.zig), which declares "no requiredness or routing policy"; generation guidance restates them | No typed property says whether a field needs prose or what role exact copies play in it | Add one closed, typed composition policy per declared text field, owned by the field registry: whether nonblank prose is required, and whether exact-copy and passive insertions are prohibited, incidental or obligation-bearing in that field. Every consumer reads it from that owner. |
| Wire codec ([§7.1, 14 October amendment](../design/contracts/07-domain-representations.md#approved-model-facing-text-amendment--14-october-2026)) | Any prose string is accepted, including the codec's own insertion-object syntax | Unexecuted insertions become prose in four of the five runs | Reject a prose fragment containing the closed insertion grammar as a protocol error, routed to the existing protocol correction, unless those exact bytes occur in the original source. Never convert such text into an insertion; §7.1 forbids inferring an occurrence from equal text. |
| Typed-text validator ([typed_text.zig:130-182](../src/domain/typed_text.zig#L130-L182)) | Every insertion sets `visible = true`; only an empty or blank value rejects | Insertion-only values pass for every field | Apply the field policy: a prose-required field without nonblank prose fails with a typed `reference_only` issue whose explanation comes from the policy owner. Callers ([specification_provenance.zig:225-240](../src/domain/specification_provenance.zig#L225-L240), extraction and reconciliation text validation) pass the field's policy instead of applying a local rule. |
| Collection coverage ([specification_coverage.zig:73-98](../src/domain/specification_coverage.zig#L73-L98), ADR 0020) | A `business_exact_string` token's obligation is satisfied by an `exact_copy` occurrence in any singleton or record field | A literal-only title or story satisfies the exact-copy obligation, so the native gate rewards the degenerate output | Count only occurrences in fields whose policy declares the token's role obligation-bearing and that passed composition. Whether the token is used correctly remains a semantic review judgment. |
| Admission routing | Native typed issues already route to unit repair (`generate-unit` → `authorize-repair`) | The composition defect never became a native issue, so it fell through to model review | No new route. The new issue uses the existing unit repair with the old value, issue and field purpose; wire-syntax rejections use protocol correction. |
| Repair ([atomic_repair.zig](../src/domain/atomic_repair.zig), shared retry owner) | Repair outputs pass `valueIn`, but nothing rejected them; an unchanged result merges with `changed: false`, and the merge allowances are 64 executions per defect key | A no-progress repair consumes budget and triggers re-review | Repair outputs automatically meet the same composition rule. Separately, the shared retry owner treats a repair whose canonical result equals the rejected value for the same defect key as no progress, ending in a typed exhausted outcome. This needs an explicit shared contract, not a repair-route branch. |
| Source review ([specification_support.zig](../src/domain/specification_support.zig)) | Review was the first detector and misdiagnosed the defect | Model review was acting as a mechanical validator, and its wrong finding type selected the wrong repair route | Invariant: a value that fails a declared native rule never reaches model review. Review remains for semantics; qualifying omission statements against original sources stays a separate item (cost investigation step 1). |
| Model-facing presentation | Shared guidance is mostly insertion syntax; the story prompt is two lines; the story packet offers a token-only group and the preserved token; the schema allows insertion-only arrays | The model is not told the rule, and the schema cannot express it | Present each field's composition policy from its owner in the packet, and offer exact-copy choices only where the policy permits them. Schemas stay guidance: neither the closed schema profile nor provider grammars (Bedrock or Anthropic) can express "contains a prose string". Do not add a new prompt sentence as the fix (F2). |
| Readback and rendering | Stored state and renderers trust admitted values | A value admitted before the change could persist | Stored readback validates with the same policy, with no compatibility reader; the renderer never emits wire syntax. |
| Evaluation and reporting | `first_observed_defect` is the first *native* rejection; Phase 2 attribution has no representation category | Structurally detectable defects are attributed to generation or review, and the report label misleads | Rename the label to "first native rejection". Add an admission-escape measure and a representation/admission category to Phase 2 attribution (§5.5, Phase 2). |

**What must not be done.** No branch for stories, titles, Hello World, repeated
literals or GPT-OSS. No prompt-only fix. No normalizer that turns strings into
insertions, strips duplicates or merges fragments. No extra model call or reviewer
instruction acting as the validator. No removal of exact-copy support to hide the
failure, which would lose ADR 0020 lineage. No weakening of review or coverage gates,
and no budget increase justified by this finding. The policy applies to every
model and provider, including the proposed [Claude connector](claude_connector.md).

**Expected effect and its limit.** In the 09:18 run, call 8 would have been rejected
at admission and sent to one native unit repair with an explicit issue, instead of
reaching review. The model may repeat the failure; the no-progress rule then ends it
early as a typed failure. This removes an entry point for the review and repair
chain in F9 and the cost investigation. It does not establish completion within the
budget, semantic quality or any comparison result.

**Relation to the other proposals.** The A/B/C/D comparisons all change record
authoring and share this representation, so none of them addresses F10, and C would
inherit it. The cost investigation's next steps (qualify review omissions, shrink the
repair projection, consider review batching) reduce the cost of failures that F10
would stop at admission; they remain needed for failures F10 cannot detect.

**Implication:** close F10 in Phase 1A (§5.6) before the Phase 2 baseline is frozen.
It changes accepted contracts in §7.1, §17.3 and ADR 0020, so it needs the
decisions listed there before implementation. Phase 1A's live result is in F11.

### F11 — High: admission now stops the defect, but generation cannot recover from it

**Run.** The [16:20 hello-world diagnostic](../zig-out/e2e-spec/2026-10-16T05-20-15Z-44b2ac5e19cbf8d2ade89b149aed73c8/report.json)
ran on committed `bfec3d7` (`modified: false`) with the GPT-OSS-20B binding. It
ended `workflow_failed` with `RepairNoProgress` (`unchanged_repair`) at
`generate-brief-merge-repair`, after 8 calls and 12,896 tokens. No review call was
made and nothing was published.

**What Phase 1A did as designed:**

- Call 7, the brief, returned the title
  [`{"fragments":[{"kind":"exact_copy"}]}`](../zig-out/e2e-spec/2026-10-16T05-20-15Z-44b2ac5e19cbf8d2ade89b149aed73c8/evidence/generation/call-000007/model_output.txt).
  Native admission rejected it as `reference_only` for `spec_title`; the report's
  `first_native_rejection` points there, before any review.
- The unit repair, [call 8](../zig-out/e2e-spec/2026-10-16T05-20-15Z-44b2ac5e19cbf8d2ade89b149aed73c8/evidence/generation/call-000008/model_output.txt),
  returned the same single insertion. The shared retry owner ended it after 1 of 64
  allowed executions, with no re-review or publication.
- No defective value escaped: 0 of 4 admitted values. The run cost 12,896 tokens,
  against 101,134 for the 09:18 run that reached review with the same failure class.

**What it shows.** The model behavior persists: this is the sixth consecutive run
with an insertion-only value, this time in the title rather than the story. Phase 1A
converts a silent defect into an early, typed failure at its owner. It cannot by
itself produce a valid specification; the workflow now fails at generation instead
of in review.

**Why the repair could not succeed.** The model-facing presentation contradicts the
admission rule it is meant to express:

1. **The schema still offers the rejected shape.** The title's projected schema, in
   both the [generation request](../zig-out/e2e-spec/2026-10-16T05-20-15Z-44b2ac5e19cbf8d2ade89b149aed73c8/evidence/generation/call-000007/request.json)
   and the [repair request](../zig-out/e2e-spec/2026-10-16T05-20-15Z-44b2ac5e19cbf8d2ade89b149aed73c8/evidence/generation/call-000008/request.json),
   allows a fragments array of only `exact_copy` objects. The title's exact-copy role
   is `incidental`, so the projection offers an insertion that cannot satisfy coverage,
   and constrained decoding permits the answer admission rejects.
2. **Static guidance contradicts the policy.**
   [generation.context.json](../design/workflows/spec/generation.context.json) still
   tells the model, for every field, to "insert an exact_copy object instead of
   typing the literal inside a string". Phase 1A's deliverable was to remove guidance
   the policy owner now supplies; this sentence remains and applies even where the
   policy requires prose.
3. **Exact choices are offered to the whole unit.** The brief packet supplies the
   preserved token and its token-only source group to title, description and goal
   together, although only the description's role is obligation-bearing.
4. **The policy is presented as a generic table.** `text_fields` lists every field of
   the unit (four for the brief, including the irrelevant `clarification_question`;
   eight for extraction) with one identical explanation and engine vocabulary such as
   `incidental` and `obligation_bearing`, instead of a field-specific instruction for
   the assigned target.
5. **The repair packet anchors on the defect.** The rejected value appears as
   `current_value` in exactly the wire shape the model is asked to return. The reply
   equals it without the `claim_id`. With temperature 0.1 and otherwise identical
   inputs a repeat is likely; the no-progress rule correctly stopped it, but the
   repair offered no materially different path to a valid value.

**Secondary observations, not yet attributable:**

- **Extraction merged the three hello-world requirements into one claim** in all
  three post-Phase-1A samples (both probes and this run), against one of the two
  pre-Phase-1A hello-world runs. The extraction packet grew from 615 to 2,839 bytes
  because of the policy table (about 320 more input tokens). Five samples cannot
  attribute this; Phase 2's upstream attribution must measure it, and 1A.2 removes
  table rows that do not apply to the request.
- **The description typed `Hello, World!` as prose** rather than inserting it. In an
  obligation-bearing field that is permitted prose, but it creates no occurrence, so
  exact-copy coverage would depend on later records. This is the next watch item
  once the title is admitted.
- **`admission_escape` reports `unavailable`** rather than measured zero, because one
  engine-produced reconciliation value has `origin: null` and is counted as
  unattributed. With zero escapes the metric should be able to report measured zero;
  this is a harness attribution gap.

**Implication.** The realignment is complete on the admission side of the composition
contract and incomplete on its presentation side. Admission enforces the field
policy, but the schema, static guidance, offered choices and repair packet still
present an insertion-only answer as available, and in places as preferred. Close this
in Phase 1A.2 (§5.6) before the Phase 2 freeze. Do not add sampling or temperature
changes, extra repair attempts, a second model, or field-specific code.

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

The 16 October full-workflow diagnostics (F9) are the first selected-binding
observations under the current contract. They are not this baseline: loan-renewal
is outside the panel, the builds were uncommitted and differed between runs, and
neither run reached publication.

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
[Recommendation](FIX03.md#L1919), [qualification boundary](FIX03.md#L1963).
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
none of the phases. Record implementation progress and links to evidence in
[FIX01](FIX01.md); keep this document as the evaluation and rollout design.

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
  workflow budget cannot complete the panel's full workflows, record that as a
  required decision (raise it through an explicit engine contract change, reduce
  measured review or repair cost through its owner, or narrow the qualified scope),
  not as permission to shrink the panel or treat budget-stopped runs as completions.

All dispatched failures, malformed/truncated outputs and exhausted repairs remain
in the attempted-workload denominator. Genuine-gap cases use their separate
expected-outcome score. Record unattempted trials and unknown usage explicitly;
selectively incomplete pairs or missing required observations prevent promotion.
Evaluation expectations never enter generator inputs. Label model-assisted scoring,
blind arm labels where practical and resolve material scoring disagreements before
promotion. These rules refine the protocol in §4.7, not production authority.

### 5.6 Phased rollout and exit gates

#### Phase 0 — Make the evaluation executable

**Implementation:** **Complete (offline), 15 October 2026.** The concrete
[protocol](../test/calibration/semantic-simplicity/protocol.json),
[source-backed cases](../test/calibration/semantic-simplicity/cases.json),
[labelled specimens](../test/calibration/semantic-simplicity/specimens.json) and
[operating/scoring contract](../test/calibration/semantic-simplicity/README.md)
are implemented. The [retained results](../test/calibration/semantic-simplicity/phase0-results.md)
and [generated dry-run snapshot](../test/calibration/semantic-simplicity/phase0-dry-run.json)
record 72 variants, 225 source-backed duty labels, all 144 planned synthetic
workloads, six required scoring specimens, zero actual sends/tokens and no
workflow authority. All required offline checks passed.

The prospective freeze now uses **GPT-OSS-20B / Converse / Sydney / low reasoning /
native JSON Schema / engine-fixed temperature 0.1 / 16,384 requested output
tokens**. Its closed schema rejects the superseded Luna default-reasoning and
strict-output fields. The retained snapshot above describes the earlier Luna
freeze; the canonical offline integration producer regenerates the new model
and protocol identity under `.zig-cache/semantic-simplicity/phase0/`.
Eight development and sixteen reserved qualification features each have three variants;
three repetitions of A/C give **144 development feature workloads**. The labels
received a separate model-assisted source review, not human approval. The dry run
exports only 24 development source inputs, excluding expectations, duties and
native identities. Exact production request bytes and compatible live binding
remain Phase 1/2 prerequisites before any live comparison.

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
binding. They have not been reconciled with the 16 October diagnostics, which
exhausted a 100,000-token workflow budget on one small feature (F9). Phase 2's
budget-feasibility step (§5.5) must resolve this before dispatch.

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

**Offline implementation complete; mechanical checks passed, 15 October 2026.**
Final verification passed **155/155 build steps and 1,786/1,786 tests**; the
[retained evidence record](../test/calibration/semantic-simplicity/phase1-offline-results.md)
records exact commands and scope. The later authentic exchange result is recorded
below and qualifies only the observed request/settings.

The user-authorized development command
prepares a fresh case through the existing production configuration, compiled
workflow, model-request preparation, authorization, Converse transport and capture
owners. The first model assignment remains unchanged; it depends on the selected
workflow and normally concerns reference extraction in the supplied Spec case.
This is not a historical debugger replay or a generation-quality comparison.

After separate explicit approval for the live probe, use:

```sh
zig build provider-compatibility -- \
  --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json --live
```

The equivalent launcher is `./scripts/provider-compatibility.sh` with those same
arguments. There is no default case. `--live` opts into dispatch but cannot supply
the user approval required by the model-conformance contract. The exact permitted
binding is **Bedrock `openai.gpt-oss-20b-1:0` / Sydney / Converse / native JSON
Schema / low reasoning / temperature 0.1**. The GPT-OSS profile supplies its
registered reasoning control and omits Luna's strict-output field. The request inherits the case's configured
output allowance and must match Phase 0's frozen 16,384 tokens, as the supplied
Spec slot does. This is an experiment setting, not an engine size ceiling.
Configuration preflight checks all slots against the cost policy and requires
complete trace/debug capture before reading credentials. Production catalogue and
request authority are validated before transport. No model/mode/settings
substitution or fallback is admitted.

The transport allows at most **one physical inference send**, charged before the
attempt; transport failure cannot authorize a replacement. The runner stops
through a typed cancellation after the exchange while preserving original
rejections, and rejects any further dispatch. Supplied actual usage is retained
before the stop, including rejected/stopped candidates.
There are no retry, repair, judge or workflow-publication calls and no successful
workflow-completion authority. Provider compatibility and production workflow
outcome are separate results.
Typed invocation/step outputs, replacements and side-effect policy reject any
publication-capable child before execution through `publication_prohibited`,
including before the first model exchange.

Each run retains `report.json` and `report.md` beneath
`zig-out/provider-compatibility/<UTC-date-time>-<unique-id>/`, linking available
immutable request/response captures. The report identifies the revision, exact
binding/settings, request/response bytes and association, closed schema inspection,
provider stop, physical sends, actual usage and separately captured provider
reasoning. Missing, malformed or uncertain evidence cannot close compatibility.
Unknown actual consumption is `total_actual_tokens: null` with
`usage_complete: false`; `total_accounted_tokens` explicitly retains native
accounting. HTTP rejection alone is inconclusive, rather than proof of codec or
model incompatibility.
Read-only inspection reconstructs the exact canonical request and joins native
identities/request-response bytes with the closed trace transport outcome and
production accounting metadata. HTTP status/request ID come from the transport
record. Request/response SHA-256 identities retained at the trusted transport
observation bind external readback to the observed bytes and reject substitutions;
they are diagnostic byte identities, not engine state or predecessor authority.
Bodies from interrupted/uncertain delivery remain retained and
inconclusive without candidate validation or invented usage.
Reasoning remains diagnostic data, never semantic evidence or publication authority.
See the [operating contract](../design/harness/e2e.md#test-one-fresh-provider-exchange).

**Authentic exchange: bounded compatibility gate passed, 16 October 2026.**
The first HTTP-200 exchange exposed the response-decoding defect recorded above.
After that correction, the separately authorized 07:46 exchange passed candidate,
schema, usage and request-association checks. It qualifies only the observed
production request/settings, not every workflow request shape or semantic quality.
The [Phase 1 offline evidence record](../test/calibration/semantic-simplicity/phase1-offline-results.md)
records the mechanical checks separately from this live evidence.

**Deliverable:** the selected binding's trusted registration and any required codec/
adapter support behind existing ports, with the generation assignment unchanged.
Verify official request, response, region, schema, reasoning, temperature, output
allowance, stop and usage contracts. Configure the validated catalogue and slot.
Any other model requires its own verified binding. Account access and IAM
permissions are preconditions to confirm outside the probe; 18 of the 20 probes
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

**Why it precedes Phase 2.** F10's composition failures are detectable by
deterministic code, recur in every run that reached generation, and change which
candidates are admitted. Freezing a baseline before closing them would measure a
known enforcement gap, and closing them later would leave baseline and candidate
under different admission contracts. This phase is independent of the A/B/C/D
choice and adds no assignment, model call or semantic planner.

**Decisions settled for the authorized implementation — 16 October 2026:**

The explicit Phase 1A implementation instruction authorizes the amendments.
The accepted [composition contract](../design/contracts/text-field-composition.md)
records the exact inventory and rules; the items below retain the decision scope.

1. **Field inventory.** For every declared text field in Spec generation, repair,
   clarification, extraction and reconciliation, whether nonblank prose is required.
   Nonblank prose is required for every narrative or behavioral field, including
   title, description, goal, story, Given/When/Then, expected outcomes, requirement
   and rule text, entity basis and meaning, relationships and clarification
   questions. Entity names are the explicit optional-prose identity-label
   exception; their insertions remain incidental and do not satisfy behavioral
   coverage. There is no fragment-count or repeated-literal special case.
2. **Exact-copy role per field.** Which fields may carry insertions at all, and in
   which fields an occurrence satisfies an exact-copy obligation for collection
   coverage. Only composition-valid behavior/constraint fields are obligation-bearing;
   the accepted inventory distinguishes incidental descriptive fields and
   reference fields without exact-copy insertions. This amends ADR 0020.
3. **Wire-syntax rule.** Rejecting prose that contains the closed insertion grammar,
   with the exact-original-source-byte exception, as a protocol error through
   existing bounded correction. Native and stored checks use the same grammar.
4. **No-progress repair.** The shared definition of a repair that returns the
   rejected value unchanged for the same defect key, and how it exhausts the existing
   allowances. Canonically unchanged replacements under the exact current key
   produce shared `unchanged_repair` exhaustion before the tentative delta applies;
   actual calls/usage remain charged and no re-review or successful repair follows.

**Deliverable:** the accepted amendments to [§7.1](../design/contracts/07-domain-representations.md#71-shared-types),
[§17.3](../design/contracts/17-specify.md#173-llm-work), ADR 0020 and the repair
contract in §22, and one coherent implementation at the owners in F10's table: field
policy registry, codec, typed-text validator and its callers, coverage, retry owner,
packet presentation, stored readback and harness reporting. Remove guidance text the
policy owner now supplies, so that rule and presentation cannot drift.

**Test:** accepted and rejected cases for every consumer that validates typed text:
initial generation, protocol correction, unit repair, omission repair, coverage
repair, extraction and reconciliation where the inventory declares a policy, and
stored readback. Cover fields in unrelated domains, legitimate in-sentence insertions,
declared lone-insertion fields, wire syntax with and without a source occurrence,
coverage satisfied only in obligation-bearing fields, and no-progress repair
exhaustion. Replay the retained captured model outputs from the five runs in F10
through native admission offline: each listed value must now reject with the
expected typed issue, and the runs' prose-bearing values must still admit. This
uses retained evidence and makes no model call. Then run architecture checks and
`zig build verify --summary all`.

**Exit gate:** all checks pass, the offline replay shows every F10 value rejected at
its owner and no legitimate value rejected, and the amendments are accepted. One
separately approved full-workflow diagnostic per development case may then measure
admission rejections, unit-repair outcomes and downstream review calls. It is
mechanical evidence about where defects stop, not a quality or completion claim.
The Phase 2 baseline is frozen afterwards, on a committed revision that includes
this contract.

**Implementation and offline gate complete — 16 October 2026.**
[The implementation record](FIX04-phase1a-implementation.md) maps every deliverable
to its owner and records the settled amendments and validation. The retained
offline replay rejects all 29 captured defects (10 insertion-only and 19 encoded
insertions) and admits all 50 prose-bearing controls from five runs and 23
exchanges. `zig build verify --summary all` passed all 156 steps and 1,699 tests,
including offline integration, architecture and clean-directory packaging checks.
No new provider request or live workflow was run; renewed feasibility and live
quality evidence remain Phase 2 work.

**Live result — 16 October 2026.** On committed `bfec3d7`, the approved hello-world
diagnostic confirmed the mechanical behavior: the brief's insertion-only title was
rejected at admission, the unchanged repair exhausted after one execution, and no
review ran (F11). The defect class persisted and generation did not recover, so the
live step is satisfied for enforcement but not for recovery. Phase 1A.2 follows.

#### Phase 1A.2 — Make model-facing presentation consistent with admission

**Why it precedes Phase 2.** F11 shows that admission enforces the composition policy
while the schema, guidance, offered choices and repair packet contradict it. This is
the presentation half of the same contract. The composition contract already makes
the field registry the single owner of presentation; F11 shows that ownership is not
yet complete. Freezing a baseline now would measure that contradiction.

**Remediation.** All of it is projected from the field policy registry, with no
field-, workflow- or model-specific code:

1. **Decide which insertions are offered, not just tolerated. Decided: approved by
   the user, 16 October 2026.** Fields whose exact-copy role was `incidental` (title,
   goal, entity-applicability basis, entity meaning, relationships, assumption,
   clarification question) change to a `prohibited` exact-copy role and are projected
   without exact-copy insertion objects, so constrained decoding itself requires
   prose. A literal the model types there is ordinary prose without lineage, which
   those fields do not need because their occurrences cannot satisfy coverage.
   Entity names keep their identity-label exception. The amendment is recorded in the
   [composition contract](../design/contracts/text-field-composition.md#phase-1a2-amendment--exact-copies-only-where-they-can-carry-an-obligation)
   and [ADR 0020](../design/decisions/0020-derived-exact-reference-lineage.md);
   implementation is pending.
2. **Project schemas per field from the registry.** Each field's fragment alternatives
   list only its permitted insertion kinds, through the shared schema-projection owner,
   with one rule for generation, protocol correction and every repair route. Where
   insertions remain permitted, "contains prose" still cannot be expressed in the
   closed schema profile or provider grammars and stays a native admission rule.
3. **Derive guidance from the registry.** Remove the unconditional `exact_copy`
   sentence from `generation.context.json`. Present the assigned fields' composition
   rules in plain, field-specific terms, only for fields in the selected schema; drop
   rows for fields the request cannot return, such as `clarification_question` in a
   brief write request or extraction kinds outside the selected schema.
4. **Offer exact-copy choices only where they can be used.** Supply preserved tokens and
   token-only source groups only with a request containing a field whose policy
   permits them, and identify which fields may use them.
5. **Make composition repairs present the defect, not an echoable answer.** For a
   composition issue, show the rejected value as rendered text with the specific issue
   and the field's rule, while the exact old value stays native for compare-and-swap.
   The repair schema uses the same per-field projection, so for fields recommended in
   item 1 prose is grammar-enforced.
6. **Close the reporting gap.** Give engine-produced values a native origin, so
   admission escape can report measured zero.
7. **Keep** the no-progress exhaustion, temperature and repair allowances unchanged.

**Test:** per-field schema projection for every permitted and prohibited insertion kind
and every consumer; guidance projection with no unconditional exact-copy instruction
and only the selected fields; repair-packet rendering for each composition issue,
with the native old value unchanged; native-origin attribution in the audit; the
retained F10 replay and the F11 captures still rejecting; offline integration; then
`zig build verify --summary all`.

**Exit gate:** offline checks pass; decision 1 is recorded (16 October 2026). Then one separately
approved diagnostic each for hello-world and loan-renewal on a committed build. Each
must either admit the brief and story with prose, or end in a typed composition
failure after a repair whose presentation differed materially, with admission escape
reported as measured zero. This is mechanical evidence, not quality.

**Then, before the Phase 2 freeze:** the budget and scope decision in §5.5, using the
new cost evidence, and the review and repair contract work identified in F9 and the
[cost investigation](FIX04-phase2-cost-investigation.md), if the runs now reach review
and exhaust the budget there.

#### Phase 2 — Establish baseline quality and failure sensitivity

**Deliverable:** an unchanged-generation baseline report for the selected model on
the development panel, including original, repeated and transformed inputs.
Freeze a committed provider-integrated baseline revision for later comparison;
runs on differing uncommitted builds, such as the 16 October diagnostics, cannot
form the baseline. Distinguish controlled-predecessor diagnostics from complete
production runs using actual predecessors; obtain the required live approvals for
each scope.

**Prerequisite:** close Phases 1A and 1A.2, then complete the budget-feasibility
step in §5.5. With the compiled 100,000-token workflow budget, complete production
runs ended in budget exhaustion during review (F9), and part of that review cost
followed defects that native admission now rejects (F10). After Phase 1A the run
fails earlier, at generation (F11), so no complete-run cost has yet been observed.
Re-measure feasibility after Phase 1A.2; the required budget decision belongs to the
user and must be recorded before the baseline is frozen.

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

**Implementation record — 16 October 2026:** the development-only
[baseline harness](../test/harness/baseline/cli.zig) now separates offline budget
preparation, explicitly approved serial production acquisition and offline
source-backed assessment. Arm A can be planned/scored without C. Freezing
requires a committed build, explicit recorded budget decision and sufficient
native full-workflow cost evidence; the current budget-stopped diagnostics do
not satisfy that prerequisite. Every physical send, native usage observation,
original/corrected candidate and unattempted trial remains distinct. Evaluator
expectations remain outside materialized generation inputs. Qualification uses
the user's selected complete first-pass fidelity metric. The
[operator guide](../test/calibration/semantic-simplicity/README.md#prepare-acquire-and-assess-phase-2)
describes the commands and retained evidence. These mechanics do not close this
phase's live evidence or semantic exit gate.
The subsequent [implementation completeness audit](FIX04-phase2-audit.md) maps
each measure to its owner and records the separately approved live diagnostic;
its failed execution does not close this phase.

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
§6 and the retained Phase 0 results distinguish actually executed verification:

| Phase/boundary | Existing verification entries |
| --- | --- |
| Offline evaluation protocol and labelled accounting | `zig build test-rubric-evaluator`, `zig build test-integration` |
| Fresh one-send compatibility scenario, offline | `zig build test-provider-compatibility` (guards/CLI/report), `zig build test-integration` (fresh production runtime/fake exchange), `zig build test-provider-compatibility-launcher`, `zig build smoke-provider-compatibility` |
| Provider and request compatibility | `zig build test-provider-conformance`, `zig build test-provider-invocation-validation`, `zig build test-model-request-preparation`, `zig build test-model-request-workflow` |
| Source packets, generation and response contracts | `zig build test-reference-model-input`, `zig build test-specification-generation`, `zig build test-specification-contract` |
| Representation admission contract (Phase 1A) | `zig build test-typed-text`, `zig build test-model-envelope`, the source-packet and repair entries in this table, and `zig build test-integration` for the [retained F10 admission replay](../test/calibration/representation-admission/README.md); no model call is made |
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

The delivery now includes Phase 0's closed evaluation contracts, fixed offline
integration scenario and retained fixture/result evidence. The separately
requested production change replaces provider-specific Bedrock chat serialization with
shared Converse invocation/count/replay/harness codecs, adds the Luna registration
(still registered, no longer a live-test selection) and retains optional provider
reasoning in typed debugger diagnostics.
The current development live-test policy permits only the selected Bedrock GPT-OSS-20B tuple
before credentials/network. Canonical live fixtures and the explicit judge
selection use that same model; judging remains a separately labelled role with
its own settings/accounting, not independent model evidence. No production
dependency was added.

The user subsequently requested Phase 1's bounded fresh-request scenario. It
reuses production owners, limits transport to one physical inference send and
retains provider compatibility separately from the interrupted workflow outcome.
The command and launcher require an explicit case and live opt-in; their offline
tests exercise rejection and failure evidence without connecting to Bedrock.
The later authentic compatible exchange closed the bounded Phase 1 exchange gate.
Its operating contract and command are recorded in §5.6; its
[offline evidence record](../test/calibration/semantic-simplicity/phase1-offline-results.md)
is separate from the authentic compatibility qualification. Implementation progress remains
in FIX01.
Phase 1's offline implementation and mechanical checks are complete: final full
verification passed **155/155 build steps and 1,786/1,786 tests**, including
provider/request checks, offline production integration, architecture and native
clean-directory packaging. The retained evidence record supplies the exact
registered command. Those offline checks performed no authentic model exchange;
the later 16 October attempts, decoder correction and compatible exchange are
recorded above. Full workflow publication and rubric acceptance remain open.

The analysis inspected current assignment, evidence, review, generation and provider
owners; relevant accepted amendments; historical report/fixture provenance; and
current primary release/benchmark sources. Older model research is excluded from
capability conclusions. No inspected study directly qualifies the proposed
assignment granularity for the selected model. Detailed live benchmark artifacts
were not fully retrievable, and no public experiment was independently reproduced.
Historical model-quality numbers retain their original assessment limitations
and are not used to select the new architecture.

Verification and retained counts are recorded in the
[Phase 0 report](../test/calibration/semantic-simplicity/phase0-results.md).
Targeted checks cover closed fixtures, complete workload denominators, initial
versus corrected labels, persistent harm, uncertainty/stops, provider controls,
usage, exact replay, reasoning ownership/display and cost rejection. Required full
verification includes architecture, offline integration and native clean-directory
packaging. Phase 0 verification passed **145/145 build steps and 1,671/1,671 tests**:
`ZIG_GLOBAL_CACHE_DIR=/private/tmp/sdde-zig-global-cache zig build --global-cache-dir
/private/tmp/sdde-zig-global-cache test-rubric-evaluator verify -j2 --summary all`.
The rerun used approved sandbox escalation for the nested compiler checks and
local debugger socket; no model-provider call was made. Bedrock inference routing
is exhaustively checked as `/converse` for all registered model/region tuples;
optional token counting is the separate `/count-tokens` operation. The active
Bedrock runtime, harness and current provider documentation contain no legacy
inference API endpoint, codec, alias, fallback or obsolete API reference. Generic
workflow `invoke-model` action names and immutable historical evidence retain
their separate meanings.

The Phase 0 and Phase 1 offline verification runs made no model/provider calls.
Separately authorized live work then ran on 16 October: twenty-two one-send
compatibility probes, of which three were `compatible` (the last on committed
`bfec3d7`), and four full-workflow development diagnostics (two loan-renewal, two
hello-world), none of which published a specification or ran rubric evaluation
(header, F9, F10 and F11). No live debugger replay was performed. Phase 1's bounded
exchange gate is closed for the observed first request only. Phase 1A's accepted
contract, implementation and offline gate are complete, and its enforcement is
confirmed live; Phase 1A.2 and Phases 2–6 remain open. Phase 2 requires Phase 1A.2,
fresh budget-feasibility evidence, the recorded user decision and a committed
baseline build. Source labels, review and the F9–F11 semantic interpretations remain
model-assisted or reviewer readings of retained outputs. Phase 1A adds the separate
mechanical evidence linked above; no semantic
benefit, reduced brittleness or useful publication is claimed. Historical results
remain immutable.
