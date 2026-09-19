# ADR 0016: Configure smaller JSON responses and assemble them deterministically

- **Status:** Accepted; configured object-part composition implemented
- **Date:** 2026-09-19
- **Decision authority:** User instructions to design and implement generic, configured response
  decomposition and prompt-free reconstitution across JSON shapes. Higher input
  token counts are acceptable; existing execution-budget enforcement remains.
- **Amends:** §§6, 12, 14, 16.4, 22 and 28 for configured response composition;
  ADRs 0012–0013 retain request, resource and compiler ownership.
- **Additional approved direction:** the user explicitly permits increasing the
  finite compiler graph limit; 512 is not an architectural invariant.
- **Does not approve:** an unbounded graph, hidden request dispatcher, new semantic
  repair authority, production dependency or live run.

## 1. Problem and intended outcome

R34 failed before extraction admission: malformed JSON was followed by repeated
misplacement of token classifications inside a claim. R33 accepted an identical
initial extraction request, then failed on a generation response. The retained
[audit](../../fixes/FIX_001.md#shared-contract-assessment--19-september-2026) found
intact evidence and schema delivery. Smaller output responsibilities are a
reliability hypothesis, not a demonstrated cure.

One configured semantic assignment may produce several independently schema-checked
JSON parts. Each model request returns its complete assigned part. Native code
assembles the admitted parts into the configured complete candidate, without
prompts or a model call. Full schema and domain validation remain mandatory.
Successfully admitted unrelated parts survive another part's correction within
the same execution. A fresh workflow invocation still starts empty.

The mechanism is generic over the engine's supported closed JSON-schema profile.
No action or orchestrator branches on a workflow, filename, domain property name,
claim kind or motivating example. Input evidence is retained where needed; neither
input-token minimization nor another per-call size gate is the objective.

## 2. Configuration and single schema authority

Use workflow-owned resources beneath `paths.workflows` and closed operation
parameters. `.sddtoolkit.json` continues to select roots/models/policy; it does not
gain a second response-shape registry. Workflow YAML keeps the prompts, model
slots, operation calls, outcomes and retry limits.

One captured result-schema resource remains the complete JSON shape authority.
A closed composition resource names that resource and assigns object-property
subtrees to stable part IDs. The existing workflow compiler resolves both,
derives each part schema from the same compiled nodes and seals the result.
Independently copied part schemas are prohibited. Local `$defs` remain ordinary
schema reuse under ADR 0013.

This extends ADR 0013's selection of whole named result definitions with compiler-
derived property projections implemented by the shared schema owner.
Keep each projected schema bound to its complete schema and part identity throughout
preparation, provider serialization, correction and admission.
Registry ownership transfer must bind the composition to the destination graph's
canonical schema owner. Do not retain compiler-arena pointers or clone a private
second copy of the referenced result schema inside the composition.

**Executable composition resource:**

```json
{
  "schema": "json-composition/v1",
  "result": "extraction-schema",
  "parts": {
    "content": {"paths": ["/kind", "/claims", "/reason"]},
    "classifications": {
      "paths": ["/token_classifications"],
      "requires": ["content"]
    }
  }
}
```

Here `result` resolves an existing alias in the declaring workflow; it is not a
path loader. `paths` are structural JSON Pointers, never filesystem paths or
model-proposed destinations. `requires` declares input dependencies, not a second
execution graph: the workflow compiler must prove that explicit YAML calls and
active composition handoffs satisfy them. It cannot remove a registered input
requirement or become a post-assembly semantic repair policy. No resource supplies executable expressions,
callbacks, model dispatch, defaults, conditional business policy or capabilities.

The existing resource compiler admits only the closed `json-composition/v1`
object above: `schema`, `result` and `parts` are required; optional `definition`
selects an existing `DefinitionId` through the referenced schema's `Schema.select`.
Without `definition`, the resource root is the complete schema. Unknown or malformed
definitions reject before inference. The resource and selection remain bound through
registry cloning, request preparation/admission, assembly and complete validation;
cloning resolves the selection against the destination resource owner. Captured
composition bytes include the selection. No copied schema or second registry is
introduced. This focused §12.9 amendment was approved on 19 September 2026.
Each part has nonempty
`paths` and optional `requires`; unknown fields reject. Part IDs and the result
alias use the existing resource-ID contract. The existing schema-profile bound
limits parts/selectors; dependencies and paths validate before inference.

| Registered operation | Configuration / handoff |
| --- | --- |
| `initialize-json-composition` | `composition` resource; binds the current packet and execution epoch. |
| `prepare-model-request` / `assign-model-request-id` | Select `composition-part`, or the existing `result-schema` path, exclusively. A part cannot override schema, result selection or input. |
| `retain-json-part` | Retains the exact schema-admitted, terminal-accepted request result and prerequisite placements. |
| `assemble-json` | Retires staging and installs the complete, unvalidated JSON candidate in one runner delta. |
| `validate-assembled-json` | Reuses complete schema validation; native consumers require its associated evidence. |

Dependent requests add only configured prerequisite values to the original packet's
`prerequisites` object. The ordinary request body and protocol correction remain
shared; each explicit call site keeps its own assignment identity.

Request preparation selects either its existing schema/definition binding or one
sealed composition-part binding. The latter resolves the complete schema through
the composition resource; callers cannot override it with a second schema.
Extend the existing `model_request_preparation.Source` association checks to retain
the composition, part and exact projected schema together. An alias alone, or
structurally equal schemas for different parts, cannot establish that association.
All provider, admission and correction consumers retain this same binding.

### Partition rules

- Pointers traverse declared object properties and select complete subtrees.
  Extend the shared JSON Pointer owner for strict parsing/resolution; its current
  renderer is not already a selector parser. Reject malformed escapes and array
  traversal; compare resolved segments for ownership, not string prefixes.
  Retain their names and nesting in the part response; no renaming or flattening
  mapper is introduced. An array is one subtree, preserving its order and values.
- Each possible target property has one configured producer, including optional
  properties whose producer may omit them. No overlapping parent/child selection,
  duplicate writer, missing owner, arbitrary extra property or last-writer-wins merge.
  Structural parent containers are derived from the schema, not model decisions.
- Resolve ownership separately for every permitted tagged variant. In the example,
  `/claims` and `/reason` occur in different branches; neither becomes an invented
  optional field in the other branch. A path absent from every branch rejects.
  The first implementation also rejects a part with no selected properties in
  any reachable active branch; it cannot infer a skip or manufacture a response.
- A discriminator has one producer. Its admitted value can select only an existing
  permitted branch. A dependent part consumes that exact value/revision; it does
  not repeat or override the discriminator. Identical variant projections may share
  schema structure at the same destination. Distinct destinations remain distinct
  values/producers even when both reference the same `$defs` entry; schema equality
  never merges `/billing` with `/shipping` or establishes value identity.
  Ambiguous variant selection or an unrepresentable partial schema rejects at
  compilation; keep the affected group together instead of weakening `oneOf`.
- Keep optional containers as whole subtrees in the first implementation. The
  encoding has no separate presence owner or absent-part transition;
  splitting `/details/summary` from `/details/rationale` when `details` is optional
  therefore rejects. Required object containers remain recursively decomposable.
  Missing and `null` stay distinct; assembly never invents presence or defaults.
- Further decomposition replaces an object subtree's ownership with disjoint deeper
  property selections and explicit calls, using these same operations. Parent and
  child plans cannot both write it. No new domain-specific implementation is needed
  for another supported shape.
- Arbitrary array-index partitioning, concatenation, semantic deduplication and
  model-invented work lists are outside the first implementation. Item-level
  decomposition requires a separately established finite assignment set, stable
  item identity and exact coverage/order contract. Genericity does not infer them
  from a schema or from whatever items the model happened to return.
- Existing schema/resource and expanded-graph bounds apply. Cyclic dependencies,
  unknown resources/parts, unsupported selectors and incompatible consumers reject
  before inference. There is no new per-call token ceiling.

## 3. Responsibilities and execution

| Owner | Responsibility |
| --- | --- |
| Existing resource capture and workflow compiler | Capture/parse configuration, resolve the complete schema, prove partition/dependency rules and bind ordinary registered operations. |
| Existing schema compiler/projection owner | Derive exact closed part schemas from the bound complete schema; retain both for their execution lifetime. |
| Existing request-preparation actions | Extend their sealed selection to bind one configured part and current declared inputs. No parallel part-only builder, provider call or successor selection. |
| Existing model-request operations | Invoke, decode, schema-check and correct that part using existing provider, retry and actual-usage owners. |
| Pure part-retention action | Propose one associated part with schema admission and successful request closure; the runner validates/applies its envelope delta. |
| Pure JSON-assembly action | Place current admitted values at their compiled destinations and produce one complete candidate plus its provenance projection. No parsing of arbitrary paths, semantic transformation, prompts or model capability. |
| Existing schema and domain validators | Validate the assembled shape, then cross-part/domain obligations, citations, coverage and semantic findings. |
| Existing runner and capability-free orchestration | Execute declared child bindings, apply deltas, branch on typed results and enforce limits. Orchestrators perform no assembly or validation work. |

The registered operations implement these responsibility boundaries. Keep detailed operations available; any consolidated pure entrypoint reuses
their domain functions, never invokes another action. Reuse definition-local
subgraphs for coordination. The composition resource does not hide a model-call
loop or an executable child graph.

Each workflow-owned task prompt requests only its assigned output, as does its
retained correction base. Replace the existing combined extraction instruction
when splitting it; a smaller schema alongside a prompt still requesting both
outputs is contradictory. Share evidence through the existing packet owners.
Assembly and retention have neither prompts nor model capabilities.

Each part uses an explicit originating model operation. Existing assignment identity
then distinguishes parts, while corrections retain the same unit/operation/purpose.
Changing the selected schema or allocating a new request ordinal alone does **not**
create a new retry allowance. A shared loop selecting different parts at one call
site would require an explicit extension to the existing identity contract; it is
not part of this design's initial integration.
Dependent rebuilding retains the existing native parent-defect association where
required. New part revisions or schema selections cannot replenish retry attempts.

### Graph capacity

The integrated Spec graph compiles to **577 operations**, compared with 519 after
extraction decomposition and 498 before composition. Global reconciliation now uses
three whole-array parts selected from the existing `global` definition. Summaries
use one part selected from `summary`, sharing assembled-candidate collection. All
requests reuse the lifecycle body; retention and complete assembly/validation use
shared subgraphs with independent compiled call sites.

The user explicitly permits raising this arbitrary implementation limit. The bound
is now **1,024**, defined once by `workflow_definition.max_steps`; schema validation,
expansion, compiled validation and runner storage use that same constant. The runner's
fixed `u64` retry array increases from 4,096 to 8,192 bytes. Graph tables and validation
working sets remain allocator-backed. Boundary coverage compiles and executes a full
1,024-operation graph, rejects one extra operation, detects an unguarded cycle of that
length and checks execution-limit arithmetic overflow. Qualified step identities
retain their existing validated string representation with a 128-byte compiler-owned
bound; authored local IDs remain 64 bytes. Retry-exhaustion evidence derives its
owned name storage from the same compiled bound. The measured Spec graph fits this
bound; no additional capacity configuration is introduced. Verification and measured
resource/request costs are recorded in [Chunk 18](../../fixes/IMP_001.md#r34-follow-up--configured-response-decomposition)
and its [R36 delivery](../../fixes/IMP_001.md#r36-follow-up--validated-slices-before-cross-slice-reconciliation).

Do not introduce request orchestration machinery solely to preserve 512. Detailed
operations and distinct request identities remain visible. Consolidate only where
there is a separate cohesive responsibility; neither a larger ceiling nor call
frames reduce the number of operations or model calls. Token and retry budgets
remain unchanged.

## 4. Candidate lifecycle, provenance and repair

Use the existing execution-local `PipelineEnvelope`. One registered native,
schema-bound composition value can hold the finite configured parts; configuration
cannot create native `DataKey`s, arbitrary envelope properties or a second store.
Bind each part to its compiled plan/schema, parent unit, actual producer
request/attempt, captured source/policy lineage and exact prerequisite part placements.
Seal those placements in the composition value and dependent request binding; the
aggregate envelope slot generation is not a part revision. Retaining sibling B
must not stale A or another part that depends on unchanged A. The composition owner
checks part bindings; existing runner gates check external source/policy freshness.
No separate revision ledger, dynamic pipeline keys or automatic regeneration is needed.
Retention requires the exact schema-admitted attempt and its logical request's
terminal `accepted` evidence. Reuse the existing candidate-handoff/lifecycle owners
to check that association; schema-valid but unclosed, failed, cancelled or foreign
results reject. Do not add a composition acceptance flag, lifecycle or token charge.

Separate stable candidate association from diagnostic producer attribution through
the existing identity/provenance owners. Today both extraction repair owners use
`entry.origin` in native defect scope; a composite must not substitute the last
call or change that anchor with each part repair. Freeze the composition's native
candidate association when its generation unit is established, retain it across
correction/assembly/repair of that same candidate, and retain the required native
parent binding during rebuilding. Per-field origins name the calls that produced
those values; they cannot reset recurrence history. No new retry ledger is needed.

Retain the existing idempotent occurrence rule: replaying the same sealed placement
has no additional effect; conflicting placement rejects. Equal JSON from another
invocation is not proof of the same occurrence. Missing, foreign, stale or
unadmitted parts cannot assemble. Recording historical evidence never makes it current.

Assembly produces deterministic JSON from those values, preserving strings, numbers,
array order and absence. It creates only configured structural containers, never
business values, IDs, citations or a provider response. Carry a path-to-producer
projection so domain decoding and later diagnostics attribute each value to its
real request. Do not attribute the result to the final call or fabricate an
invocation for assembly.
This map is an immutable projection for one candidate revision. Once native
decoding/repair owns claim and citation origins, those current origins alone feed
diagnostics and evidence projections. Insertion/deletion must move origins with
their values; an original array index is not stable provenance or repair identity.

Reuse the existing schema validator's pure traversal for complete-candidate checks;
keep provider-associated response evidence and assembled-candidate evidence distinct.
Refactor that owner rather than introduce a second validator or counterfeit provider
association. Passing every part schema does not establish cross-part validity.

After structural assembly, the complete **unvalidated** candidate becomes the sole
current candidate; this grants no semantic repair, acceptance or publication permission.
Candidate installation and consumed-staging retirement are one runner-applied delta;
rejected application or allocation failure leaves the prior envelope state unchanged
and does not expose the proposed candidate. Original parts remain provenance/history only.
Use the existing captured-value handoff to retain immutable part/provenance owners
and inherited source/policy lineage without a dangling current dependency on a
retired transport slot. Request release and staging retirement must not erase
producer attribution or make the assembled candidate spuriously stale.
Existing native authorization still selects the smallest safe defect, checks the
old value/revision and preserves unrelated siblings. It does not automatically
regenerate a whole part because that was the original generation boundary.
Never reassemble historical parts over a later repaired candidate. Current repairs
operate on native candidates and rebuild derived dependencies through existing
owners; this slice adds no native-candidate-to-part reprojection/reassembly API.

Protocol correction returns the complete assigned part under its retained schema.
A successful part is not regenerated merely because another part's JSON is invalid.
Configured `requires` applies while staging parts. A dependent value bound to a
different prerequisite placement rejects; conflicting placement is not a repair. After
handoff, the existing native domain owners alone determine impacted validation and
authorized rebuilding: a citation-only repair must not acquire a new classification
call merely because both belonged to dependent generation parts. The current
`no_feature_claim` → claim insertion likewise preserves classifications and reruns
native validation. An unlocalizable composition or cross-part rejection fails/blocks
through the existing typed boundary; it cannot
invent a semantic retry, field move, clarification or success rule.

All calls, including successful parts and corrections, charge the same global
actual-token budget. Reports retain independent request/attempt attribution and
native-defect history. No partial artifact publication, persisted part checkpoint,
resume path or second canonical document is added. Canonical domain persistence
and its complete readback validation remain authoritative.

## 5. First use: extraction

1. Request claims with their citations, or the existing `no_feature_claim` reason.
   Keep full relevant source lines, passive-literal and exact-token evidence.
2. Request the complete chunk-local classification collection using that admitted
   outcome and the original candidate/evidence set. Existing native policy permits
   preserve/irrelevant for `claims`, but only irrelevant for `no_feature_claim`.
   The generic assembly contract neither implements nor overrides that policy.
3. Assemble, validate the complete extraction schema, and pass through existing
   typed-text, classification, citation, token/claim construction and accounting
   owners. A preserve decision still creates a deterministic token claim.

An empty prose-claim collection does not establish `no_feature_claim`: preserved
tokens may still produce claims. Keep text and citations together, and retain
native checks for exactly one classification per supplied candidate. Omission
review still compares against source meaning; JSON completeness is not semantic
completeness.

Parsing retains distinct content/classification producers through initial decoding,
text validation, selected repair, evidence assembly and reporting. The first
admitted producer anchors native recurrence identity and remains unchanged by
repairs. Initial extraction and its protocol corrections use composition; the
combined generation prompt and call path have been removed. Atomic/additive repair keeps its existing selected-unit
response and merge authority. It neither invokes full composition nor replaces
unrelated classifications. These are distinct generation and repair responsibilities,
not compatibility formats. The canonical assembled domain payload remains unchanged.

The existing `rebuild-extraction` path validates repaired native data and rebuilds
tokens, claims, the ledger and downstream evidence; it does not repeat extraction
generation. Retain that path. Typed-text normalization and deterministic token-claim
construction remain there, never in generic JSON assembly.

Native provenance retains each classification item's producer and distinguishes
claim-content attribution from citation-collection diagnostic association. Updating one
classification or a claim's citations cannot relabel unaffected values. Collection
diagnostics derive attribution from current values; no parallel mutable origin map
or invented producer for an absent entry is introduced.

The feedback API is an existing unimplemented feature, not a new Chunk 18 deliverable.
Its future whole-chunk re-extraction must use this composition; `add_claim` remains
exactly one authorized claim with citations. Contract conformance does not authorize
implementing that entire API or a second extraction path in this change.

### Persisted contract readiness

The approved §12.7 amendment derives extraction-contract metadata from the existing
compiled graph/schema/composition and native partition identity. The canonical
snapshot writer records this comparison evidence; state readback and publication
resolve it against the current validated registry. Exact content and identities must
match, including part-operation parameters and composition dependencies. Missing or
changed authority rejects with `REFERENCE_EXTRACTION_CONTRACT_UNAVAILABLE`.

No separate partition configuration, schema copy used as authority, provider
checkpoint or recovery store is introduced. Readback retains full native validation;
a fresh invocation starts at `start`. This closes the metadata binding requirement,
not the separately deferred native-to-part feedback API.

This example does not limit the mechanism. Conformance must also demonstrate
unrelated configured nested objects, tagged variants and whole-array properties.
No automatic rollout to reconciliation, reviews or generation is implied; their
safe boundaries require their own dependency/coverage analysis using this contract.

## 6. Implementation acceptance

- Configuration accepts unrelated shapes and rejects unknown fields, invalid paths,
  overlap, missing ownership, cycles, ambiguous variants/presence and graph overflow.
  Reused `$defs` at different destinations retain distinct values/producers; a split
  that removes a discriminator needed to distinguish unequal branches rejects.
- Each projected schema derives from the exact complete schema; native/prompt
  provider modes and correction retain the same part association and constraints.
  Release compiler/capture owners, then prepare, correct, retain and assemble through
  the surviving registry; every projection still binds its canonical schema owner.
  Reject a correct shape bound to the wrong composition/part. Initial and correction
  prompts request no sibling output; assembly receives no prompt.
  Retention rejects schema-valid but unclosed requests and failed/cancelled/foreign
  attempts; matching terminal-accepted evidence admits the part without recharging it.
- Valid parts assemble byte-stably. Missing/foreign/conflicting/stale parts,
  incompatible branches and missing prerequisites reject; optional absence and array
  order survive. Cover allocation failure, abandonment and execution isolation;
  failed handoff leaves prior envelope state unchanged without exposing the proposed candidate.
  In a three-part fork A → B and A → C, retaining B must not invalidate unchanged A
  or C. Mismatched prerequisite placements and changed external source/policy reject.
- R34's wrong-level classifications reject within the content part. Cover bounded
  correction and exhaustion, successful claims retained during classification
  retries, complete recovery and unrelated JSON contracts. Full validation rejects
  invalid citations and incompatible classifications; source-preservation review
  still runs. Test established omission findings through existing repair/clarification
  owners without claiming semantic review detects every lost requirement.
- Provenance names each real producer after assembly, native repair and reporting.
  A repaired candidate cannot be overwritten from historical parts. Test claim
  insertion, citation repair, classification replacement and native rebuilding together:
  shifted indices retain current values/origins, with no stale origin map. Ordinary
  citation repair and `no_feature_claim` → claim insertion preserve classifications
  and trigger no automatic part-generation call; independently authorized repairs
  and existing dependent model operations remain available.
  Include normalized adjacent literals, missing-citation repair and one classification
  replacement: sibling producers remain unchanged and each rebuilt candidate contains
  exactly one deterministic claim per preserved token.
- Independent assignments, alternating failures, native-defect recurrence, global
  token exhaustion and usage retention obey the existing runner contract.
  The same unresolved defect retains its allowance across assembly and part/native
  repairs; producer changes cannot reset its frozen candidate association.
- Measure complete compiled operation count, response complexity, calls, actual
  usage and completed outcomes. Input tokens may increase; do not weaken evidence
  to meet an arbitrary size target. Run targeted checks, full `zig build verify`
  and clean native packaging when implemented.
- A separately approved live run must publish and score output before claiming
  E2E closure or demonstrated reliability improvement.
- Report persisted-contract/feedback readiness separately. A scored output cannot
  stand in for the still-missing exact-contract readback evidence described above.

The overall design remains **Proposed design**. Implementation, measurements and
verification of this accepted amendment are recorded in
[Chunk 18](../../fixes/IMP_001.md#r34-follow-up--configured-response-decomposition).
