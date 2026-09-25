# LLM_REWORK — Derive mechanical facts; ask models for semantic choices

**Reviewed:** 26 September 2026. **Status:** Feasible with a coordinated contract change; approval and implementation evidence remain outstanding.
**Scope:** Documentation only. No code, schema, workflow, configuration or governing
design changes are implemented or approved by this document. No live calls were made.

## 1. Finding and recommendation

The concept is sound: when validated input and an accepted rule determine one
answer, the engine should construct that answer. Asking the model to reproduce it,
then validating and repairing disagreements, introduces avoidable failure paths.
This already follows [design §4](../design/design.md#4-deterministic-and-llm-responsibility-boundary).

The strongest immediate opportunity is **reference bookkeeping**, not arithmetic.
The current exact-copy response repeats a token ID, its citation ID and its
supporting claim in separate places. Native code already knows that relationship.
The model should select the intended source occurrence once; existing native
owners should derive its fixed dependencies. Business meaning and selection of
semantic supporting evidence remain model-assisted and subject to review.

**Revised recommendation:** for typed content backed by a validated reference
ledger, use its preserved-token claim ID in both model and canonical exact
segments. Preserve explicit content-support selection once and derive reference
lineage from that selection plus the exact segments. Refactor existing reference
mechanics below Spec's types and policy so other workflow operations can reuse them.
This avoids a second reference syntax and independently stored dependency lists.
Counts, assembly, rendering, retries and publication retain their current owners.

**Across workflows:** any validated workflow may use this contract through registered
operations with declared typed content and reference inputs. It is not a universal
schema or replacement for all evidence IDs. Workflows without such content need no
reference ledger; arbitrary JSON does not acquire reference semantics automatically.
The concrete reuse boundary and proof required are in §6.1–§6.4.

Lookup feasibility is high; implementation readiness is not established. The
code audit found substantive gaps in the earlier proposal:

| Finding | Required correction |
| --- | --- |
| Flattened provenance cannot recover which claims were explicit versus derived. | Preserve explicit selection; define one derived effective-provenance view (§5.2). |
| Canonical pairs would require conversions that the atomic repair API does not currently support. | Prefer the same claim handle across text boundaries; do not add conversion infrastructure merely to preserve old pairs (§5.4). |
| Fixed-evidence repair can change authority when a reference is removed. | Pin effective evidence; a change outside that scope requires an authorized coupled target (§5.5). |
| An invalid handle prevents complete effective provenance from being calculated. | Bind candidate repair to independently validated facts; do not require unavailable old provenance or infer authority from the invalid handle (§5.5). |
| Rebuilding repair choices from each rejected replacement can enlarge its allowance. | Retain the original validated repair bound through the existing repair context, separately from the changing candidate/revision (§5.5). |
| New response IDs would still require model-side joins in today's request. | Expose directly claim-addressable choices through the existing evidence projection (§5.1). |
| Review evidence and completed readback consume the existing provenance contract. | Update these consumers together; pending clarification state has a different storage contract (§6). |
| The current shared reference helper imports Spec types; Spec eligibility is not universal. | Refactor the existing mechanical owner and retain purpose policy with consuming domains (§6.1). |
| A claim ordinal is meaningful only in its captured reference namespace. | Bind the namespace natively; preserve other evidence and operational IDs (§6.2–§6.3). |

These are reasons to settle the focused contract before coding, not to add a fixer
agent, reference registry, evidence store or execution framework. The proposal
removes one avoidable failure class; it cannot guarantee meaningful prose.
The rollout in §10 separates an independently testable ownership refactor from
one coordinated format change. Readback and repair are prerequisites to activating
that change, not later hardening work.

## 2. Evidence: the retained failure

Reviewed execution:
[`2026-09-25T08-21-44Z-b16638b5493910a4b1d29436213dcde9`](../zig-out/e2e-spec/2026-09-25T08-21-44Z-b16638b5493910a4b1d29436213dcde9/report.md).
Its executed source fingerprint matches the preceding approved §36 run documented
in [FIX_002](FIX_002.md#36-preserve-field-purpose-through-repair-and-recover-misbound-exact-content).

| Boundary | Observed evidence |
| --- | --- |
| Source/extraction | Start successfully, display the exact greeting, and SHOULD output UTC date/time all reached generation. Claim 1 carries business prose; claim 2 is the preserved greeting occurrence. |
| Reconciliation | One mixed signal incorrectly included the preserved-token claim in model prose. Existing evidence repair corrected its selection; execution continued. |
| Brief | Initial title used token 1/citation 2 but selected only claim 1. Repair converted the reference object into a JSON-looking prose string. It passed field validation; that is not semantic recovery. |
| Story | Initial output was only token 1/citation 2, again selecting claim 1. Both authorized coupled replacements returned the same invalid combination. |
| Repair request | Original sources, revised purpose guidance, schema and diagnostics were present. Calls 12 and 13 sent byte-identical requests at temperature 0; the rule did not explicitly identify missing supporting claim 2. |
| Terminal result | `unknown_exact` exhausted the bounded story repair: `RetryLimitExhausted`, two executions. All 13 calls returned final text; all 18,512 tokens were accounted against 100,000. |
| Later gates | Entity/record generation, full coverage, semantic/principle assessment, publication/readback and rubric grading were not reached. No specification or clarification was published. |

Seven raw responses received the existing logged prefix normalization. That was
not the terminal cause. There is no evidence of a count-arithmetic error, missing
source requirement, missing final answer or budget exhaustion in this run.

The failure exposes two separate problems:

1. The model repeats relationships the engine could derive, creating invalid joins.
2. A structurally valid string can still be meaningless or contain serialized
   metadata. Deterministic reference expansion addresses the first; semantic
   assessment is still required for the second.

The preceding §36 implementation passed 1,246 offline tests. Those tests establish
contract behavior and containment, not live semantic quality. No test or measurement
in this document establishes the proposed contract's effectiveness yet.

## 3. Ownership inventory

| Information/work | Current owner/status | Assessment |
| --- | --- | --- |
| Source inventory, lines, coordinates and verbatim spans | [source_selections](../src/domain/source_selections.zig), native readers | Already deterministic. Models select offered ranges; they do not compute coordinates or reproduce quotations. |
| Exact-token candidate identity and raw bytes | [structured_tokens](../src/domain/structured_tokens.zig), extraction identity actions | Already deterministic. Relevance and classification remain semantic where not fixed by policy. |
| Canonical claim/citation/token identities | [reference_extraction](../src/domain/reference_extraction.zig), [reference_claim_items](../src/domain/reference_claim_items.zig) | Already native, assigned after validation. Do not add another identity system. |
| Exact-copy choice | [typed_text.ExactCopy](../src/domain/typed_text.zig), [generation schema](../design/workflows/spec/generation.schema.json) | Model repeats token/citation and supporting-claim selection. Highest-priority simplification. |
| Citation union | [reference_support.select](../src/domain/reference_support.zig), [specification_provenance](../src/domain/specification_provenance.zig) | Already derived. `reference_support` currently imports Spec selection/provenance types; remove that coupling while reusing its mechanical owner (§6.1). |
| Summary statement `local_key` | [reconciliation validation](../src/domain/reference_reconciliation_validation.zig), schema and key repair | Model-generated uniqueness/order bookkeeping remains. Separate candidate for removal after defining ordering semantics. |
| Preserved-token reconciliation content | [reconciliation validation](../src/domain/reference_reconciliation_validation.zig), [repair](../src/domain/reference_reconciliation_repair.zig) | The sole selected preserved-token claim determines its token. Audit/removal of the repeated token field is feasible separately. |
| Review assignment ordinals | [specification_support](../src/domain/specification_support.zig) | Single-target repair already binds its assignment natively. Batch findings still need unambiguous association; do not bind unchecked array positions. |
| FR/AC IDs and numbering | [specification_identity](../src/domain/specification_identity.zig) | Already deterministic. The number of meaningful requirements is a semantic question, not an array-count calculation. |
| Coverage membership/counts | [specification_coverage](../src/domain/specification_coverage.zig) | Already computed. Counting a cited claim is not proving its meaning survived. |
| Exact-copy reconstruction after coverage failure | [specification_coverage_repair](../src/domain/specification_coverage_repair.zig) | Already native when the entire field equals a known literal and already cites its claim. Preserve this bounded behavior; do not replace it with a model call or expand it to guessed embedded matches. |
| JSON part assembly | [json_composition_runtime](../src/domain/json_composition_runtime.zig) | Already native and prompt-free. Preserve full assembled validation and exact producer dependencies. |
| Markdown, headings, escaping and literal expansion | [specification_projection](../src/domain/specification_projection.zig), [renderer](../src/domain/specification_markdown.zig) | Already deterministic. Do not ask a model to fix the rendered document. |
| Retry limits, usage, freshness and publication status | Existing runner, lifecycle, accounting and publication owners | Already engine authority. No change justified by this proposal. |

An important distinction: deterministic validation is not always deterministic
construction. Today native code rejects a misbound exact copy after the model has
chosen three related numbers. Removing the redundant choices prevents that specific
inconsistency before it needs a repair.

## 4. What should remain semantic

- Which requirements the source expresses; how to preserve MUST/SHOULD and conditions.
- Which source statements actually support newly written prose.
- Where an exact value belongs within meaningful behavior.
- Whether two requirements conflict, overlap or describe different cases.
- Entity applicability, principle interpretation, useful Given/When/Then and genuine
  missing user decisions, except where accepted policy already fixes the outcome.
- Relevant non-obvious task dependencies and architectural trade-offs.

The engine can derive the citation belonging to a selected occurrence. It cannot
derive from that citation alone that “the application must start successfully.”
It must not manufacture FRs/ACs from a counter, choose every available citation,
merge semantically similar prose using string heuristics, or default an uncertain
finding to success. Existing semantic review remains explicitly model-assisted.

## 5. Proposed exact-reference contract — source-backed content

### 5.1 Use an existing identity once

Illustrative **proposed model segment**, not an accepted schema:

```json
{"kind":"exact_copy","claim_id":2}
```

The existing reference ledger can resolve that preserved-token claim into:

```text
captured source occurrence → token 1 → citation 2 → exact bytes
```

[reference_claim_items.build](../src/domain/reference_claim_items.zig) already
checks a preserved-token claim's one citation, source occurrence and raw bytes.
[eligibleExactClaim](../src/domain/specification_provenance.zig) currently performs
the reverse lookup while authorizing §36 repair. Resolve the selected claim directly
through existing reference/provenance ownership. Remove reverse lookup only where
its callers disappear; native token/citation identities remain valid elsewhere.

**The request must also remove the join.** Today's
[model_evidence.Token/project](../src/domain/model_evidence.zig) offers a token ID,
value and citation separately from the owning claim. Changing only the response
schema would still ask the model to join these lists. Refactor this existing
projection to offer a claim-addressable exact choice with its trusted value and
source context. Do not add a second lookup table or strip evidence needed to choose
meaningfully. Request choices, schema exclusions and native eligibility must use
the same owning facts; an arbitrary integer still does not become a valid handle.

This projection also supplies reconciliation and source review. Reconciliation
still requires token IDs; its simplification is deferred in §7A. Preserve that
metadata for those consumers rather than globally replacing the shared token
record. Use contract-appropriate views from the same projection owner: directly
selectable claim occurrences for typed content, existing token facts where required.
Do not send duplicate exact-choice catalogues in one request or add workflow-name
branches to choose semantics.

The model still writes prose and selects evidence for its semantic assertions.
Exact-value dependency membership comes from the explicit exact-value selection,
not from guessing what a prose string might mean. Equal strings in two files remain
different occurrences. Never resolve by literal text or by the first matching value.

### 5.2 Preserve explicit selection; derive effective provenance

The current canonical representation **cannot reconstruct the required roles**.
[specification.Provenance](../src/domain/specification.zig) has one claim list and
its citation union. Under the proposed automatic derivation, these cases collapse:

| Explicit support `S` | Exact dependencies `E` | Effective claims `L` | After removing the exact reference |
| --- | --- | --- | --- |
| `[1]` | `[2]` | `[1,2]` | Claim 2 should disappear from derived lineage. |
| `[1,2]` | `[2]` | `[1,2]` | Claim 2 remains explicitly selected support. |

Subtracting exact dependencies loses intentional support in the second case;
keeping the old union leaves obsolete derived support in the first. This is a
demonstrated information loss, not an implementation detail to defer.

**Preferred contract:** retain explicit reference-claim selection `S` once with
canonical content. Derive `E` from that content's exact handles, then
`L = stableUnique(S + E)` through the refactored reference owner. Do not persist
independently writable `S`, `E` and `L` lists. Distinguish stored selection from
the effective reference view with types, not caller-specific meanings of `claim_ids`.
Spec composes this view into its evidence contract; other domains preserve their
own accepted support types. `L` describes reference claims, not all workflow evidence.

This requires a focused canonical-contract amendment. Retaining the old canonical
format is not compatible with all the proposed add/remove guarantees. Any retained
materialized citations or coverage remain checked projections, not selection authority.

Deriving a literal dependency never selects a business assertion on the model's
behalf. Explicit support may itself include a preserved-token claim; forbidding
that to avoid the ambiguity would be a new semantic restriction. For the current
source-backed Spec path, require eligible, nonempty effective support, permitting
`S=[]` when eligible exact references make `L` nonempty. Do not require a prose claim
merely because this fixture contains one. Other domains may legitimately have an
empty reference component and support from their own accepted authority; the shared
resolver must not impose Spec's nonempty-claim or no-user-response restrictions.

Use explicit-selection order followed by first exact-reference occurrence in
declared field/segment order for the stable union. Define this once in the existing
owner, including all fields in a shared-provenance record. Duplicate explicit
selections still reject. Repeated exact segments deduplicate dependencies, not text.
Recompute after authorized replacement or removal; do not append to the prior union.

### 5.3 Eligibility and scope are required decisions

Selection must resolve uniquely in the current immutable reference state, be of
the required preserved-token kind, and be permitted for the request and authorized
repair unit. Unknown or ineligible selections and foreign, stale or conflicting
request/reference-state bindings reject. A reused numeric ordinal alone cannot
reveal that the model intended an older occurrence; freshness comes from the
existing bound reference state and producer dependencies.
Use the owning purpose's eligibility policy; positive content and diagnostic
loss findings do not have identical evidence permissions.

Current `reference_support.select` derives source scopes from all selected claims;
`specification_provenance.resolvedChoices` uses them to offer passive IDs. A valid
old exact copy already includes its token claim in that selection. Compare new
behavior with that **equivalent valid candidate**, not the failed tuple missing
its required claim.

**Preferred Spec scope rule:** derive passive choices from effective lineage `L`, as
the equivalent valid old candidate does. Explicit-only scopes would narrow existing
valid behavior and are not a neutral safety measure. Newly selected occurrences
must still be eligible for the current assignment, and fixed repairs must not gain
new scope. Removal must revalidate passive siblings that depended on the removed
claim; operational capabilities remain entirely separate.

### 5.4 This is construction under a new contract, not silent repair

The current malformed tuple must not be accepted and silently patched. The new
model contract removes redundant fields, validates one selection, then constructs
canonical data according to an explicit rule. Reject superseded model formats;
do not add compatibility readers, guessing, or an optional fallback to old tuples.

The current [Values(boundary)](../src/domain/specification.zig) distinguishes model
and canonical evidence but shares business-text structure. Prefer a claim handle
in both model and canonical exact segments, with validity established at the native
boundary. The ledger owns the token/citation/bytes; duplicating the pair in every
canonical segment is not required to preserve exactness. Renderers and coverage
resolve it through the shared owner. Model data remains untrusted until admission.

This also avoids a real API obstacle: [atomic_repair.Contract](../src/domain/atomic_repair.zig)
uses one replacement type for expected values, `current_value`, response parsing,
comparison and merge. Keeping model handles but canonical pairs would require a
separate presentation/conversion contract. That alternative is feasible in principle,
but has more surface and no demonstrated benefit here. Never use a lossy model
projection as the native expected value or move lookup into generic JSON decoding.

The shared-handle option still needs schema/type, canonical-version, evidence and
consumer changes. It avoids text conversion machinery, not all contract work.

### 5.5 Specify fixed repair and review semantics before coding

The existing [native repair](../src/domain/specification_repair.zig) pins selection;
[omission repair](../src/domain/specification_coverage_repair.zig) compares canonical
claim/citation sets, and insertion matches reviewed evidence. Fixed explicit `S`
is not equivalent to fixed effective `L`: removing a sole exact segment can remove
a claim from `L` without changing `S`.

Where effective evidence is valid and available, preserve the existing fixed-evidence
boundary: a value-only repair cannot change its explicit support or effective
evidence. Recompute using the complete attributed singleton/record, then compare
with authorized evidence.
Retain exact expected-value/revision checks and the governing claim/citation
equality rules; equal source scopes alone do not establish equal evidence.
Reference addition, replacement or removal that changes that evidence requires an
explicitly authorized coupled target, or remains a typed block. The amendment must
name any newly supported coupled case; existing §36 authority does not automatically
authorize every such change. Do not silently add an explicit citation to compensate
for a removed derived dependency. Fixed membership and reviewed-omission repairs
must apply the same decision through their existing owners.

**Rejected candidates need a distinct precondition.** An unknown/wrong-kind handle
prevents `L` from being constructed. Requiring equality with a nonexistent old `L`
would disable repair; treating the bad handle as evidence would invent authority.
Today explicit provenance can resolve independently before the value fails.

**Recommended narrow amendment for approval:** bind a repair baseline
`B = stableUnique(valid S + independently valid exact handles already present in
the owning singleton/record)`. Resolve those handles through the same lookup and
the original assignment's eligibility policy; unknown, wrong-kind and ineligible
handles contribute nothing. `B` is a bound for recovery, not an assertion that the
rejected candidate is valid. Do not substitute the entire request catalogue.

Pin `S` exactly, preserve outside siblings, and require the replacement's effective
claim and derived citation **sets** to equal `B` and its citation union. Always
recompute canonical order from the replacement using §5.2. Source/omission evidence
already uses set comparisons; harmless segment reordering must not accidentally
become an evidence change. Native expected-value and revision comparisons remain
exact. Where complete old `L` exists, use it as the fixed baseline instead.

This narrow option permits, for example, replacing an invented handle with prose
supported by valid `S`. It does not permit choosing a new token occurrence outside
`B`. Such a repair can pass the field and still fail later exact-token coverage;
that is not successful workflow recovery. Empty effective support, unavailable
required tokens or other unresolved defects block unless a separately authorized
repair covers them. A broader alternative allowing new choices from the original
assignment catalogue needs explicit coupled evidence-change authority; it is not
implied by §36 and is not recommended for this first patch.

Invalid explicit support cannot be treated as fixed, trusted scope. If both `S`
and an exact handle fail, use the existing evidence-repair path first, or an
explicitly authorized group; reassess the handle after full validation. Retain
existing retry families and accounting. A replacement must not enlarge its own
allowance by introducing a new handle and then treating that rejected response as
fresh eligibility on the next attempt. Bind permitted choices through the existing
authorization facts; changed upstream authority invalidates that authorization.
Today `specification_repair.authorize` recaptures candidate facts on each attempt;
`pending_repair` retains the permit/target, not a fixed choice baseline. Retain the
original `B` in the existing domain repair context while expected value/revision
advance through the existing atomic owner. Do not add a parallel permission store.
Coupled, membership, reviewed insertion and native coverage repairs retain their
own approved policies; `B` must not silently replace those policies.

Distinguish bad candidate data from a broken evidence context. An unavailable
model-selected handle under a valid binding is a native candidate defect. Missing,
corrupt or stale engine-owned ledger/choice bindings follow their existing terminal
authority or runner rejection; they are not requests for the model to invent a
replacement reference and never become user clarifications.

[Spec source-review evidence](../src/domain/specification_support_evidence.zig) currently
requires supported findings to match the candidate's effective provenance and
replays that rule on readback. Preserve that comparison against derived `L`, while
presenting explicit support and exact-reference content accurately to review.
Literal lineage is not proof of semantic entailment. Negative/loss diagnostics retain
their distinct eligibility rules; do not globally tighten them to positive-content
provenance or change review verdict authority. This comparison is Spec's review
contract, not a universal rule for every workflow's findings.

There is a residual bookkeeping cost: supported review responses still repeat
evidence that admission requires to equal the candidate's effective provenance.
Project that native expected view through the existing review-guidance owner;
do not make the reviewer calculate `S + E`. Removing the repeated response fields
and attaching fixed positive evidence natively would require a separate review
contract amendment. It is not part of this first patch, and success here must not
be described as eliminating all model-side evidence bookkeeping.

## 6. End-to-end integration and feasibility

The following is the first production integration: Spec. Shared reuse requirements
follow in §6.1; the table does not make Spec policy mandatory for other workflows.

| Stage | Required treatment | Feasibility / failure to avoid |
| --- | --- | --- |
| Capture and extraction | Keep native spans, token candidates, classification and subsequent identity assignment. | Claim IDs do not exist yet. Do not force the proposed post-ledger ID into extraction or introduce a phase-dependent fallback. |
| Reconciliation | Preserve semantic dispositions/grouping and native identity/coverage checks. Consider redundant preserved-token fields as a separate follow-up. | Extraction/reconciliation business prose currently excludes exact-copy segments. Do not accidentally enable them by changing a shared type. |
| Request preparation | Offer directly claim-addressable exact choices and source meaning. Keep one configured response schema; initial and fixed-repair choices use the same eligibility facts. | Later initial requests also embed canonical brief/entities in `specification_session.packetFor`; omission packets embed the canonical candidate. Audit all model-visible context, not only `current_value`. |
| Model decode and native admission | Parse the closed shape; resolve exact selections; derive effective evidence; validate text, membership and full unit. | Preserve the rejected handle and location. Distinguish a bad selection under valid authority from a broken trusted binding; only the former is candidate repair. |
| Brief/story/entities/records | Apply the same contract to every attributed value, all record fields and admitted clarification questions using that representation. | Do not fix only primary-story generation. Shared-provenance records need a complete group dependency union. |
| Native repair | Existing atomic owner binds full native expected value, revision, scope and dependencies. Apply §5.5 to addition and removal, using full-record dependency recomputation. | Preserve precise repair target and existing retry identity when invalid handles alternate. Do not compare only explicit support when authorization pins effective evidence. |
| Protocol correction | Same selected response schema and existing lifecycle/accounting; retain the original assignment. | No additional retry engine or generic fixer. Native reference defects and JSON/schema defects remain distinct. |
| Coverage/omission repair | Retain native exact reconstruction; derive effective lineage for coverage and exact-set omission checks. Native and model replacements use coherent text syntax. | Same claim handles avoid pair/handle conversion. Evidence types still differ; verify selected expected values, displayed context, parsing and merge without adding a whole-specification native-to-JSON reassembly API. |
| Assembly and downstream invalidation | Retain deterministic assembly and runner-owned invalidation; recompute affected dependency closure and run full validation. | Completed parts cannot be reused after their reference/policy dependencies become stale. |
| Semantic/principle review | Inspect resulting content against original evidence. Supported-source evidence compares with effective provenance; diagnostic evidence retains its own eligibility (§5.5). | A greeting-only story can become mechanically consistent and still be a bad story. Do not overload the shared `Provenance` type with two meanings. |
| Rendering/publication | Expand exact bytes and render through existing owners only after required gates. | Reference objects inside strings remain prose, not hidden selections. Do not parse JSON-looking prose into evidence or ban it by a fixture-specific pattern. |
| Completed readback | Resolve stored explicit support and exact handles against the captured snapshot; recompute effective relationships and validate stored reviews/coverage. | Reject invalid handles, stale bindings and inconsistent retained projections. Constructing a derived view from canonical inputs is permitted; repairing corrupt stored authority is not. |
| Clarification/pending readback | Validate attributed generation questions before projection. Preserve pending reference-snapshot, clarification-ID and ledger validation. | Pending state does not store attributed generated content. Do not claim it replays complete specification provenance, or add that storage merely for this change. |
| Plan/tasks gates | Continue reading only validated predecessor authority; preserve open-clarification gates. | Shared policy should be reusable, but complete production Plan/Tasks model integration is not established by this audit. Do not claim unimplemented consumers are verified. |

The concrete localization owner is `specification_provenance.Inspection`:
`inspectAttributed`/`inspectRecord` currently resolve provenance before marking a
value target, and `specification_generation.rejectedPart` uses that target for
repair. Extend existing diagnostic facts for a rejected claim handle; do not route
a failed new lookup through a generic provenance error. Syntax/schema failures
retain protocol correction; well-shaped unavailable handles use native validation.

[Completed state](../src/domain/specification_state.zig) validates content,
coverage and review associations. [Pending state](../src/domain/incomplete_specification.zig)
stores references and clarification identities; generation questions are flattened
to text by [the existing question builder](../src/actions/clarification/build_specification_clarification_need.zig).
These are different contracts. The recommended canonical content change requires
an explicit version amendment and old-version rejection, including conformance of
any shared version tag; no migration, dual reader or new pending evidence store.

### 6.1 Shared mechanics and consuming-domain policy

Cross-workflow reuse requires a focused refactor, not simply calling
`specification_provenance` from Plan or Tasks. Today
[reference_support](../src/domain/reference_support.zig) accepts `spec.Selection`
and returns `spec.Provenance`; Spec additionally requires completed reconciliation,
retained claims and business-appropriate token kinds, and currently rejects
clarification-response support. Those are not universal reference rules.

| Responsibility | Owner after the proposed refactor |
| --- | --- |
| Handle identity and text syntax | Existing `reference_identity.ClaimId` and `typed_text`; syntax/membership validation receives native permitted choices. |
| Occurrence lookup and reference lineage | Existing reference owner resolves one bound ledger, checks identity/kind and derives stable claim/citation unions. Move its shared fact types below Spec; replace old declarations/callers rather than add a parallel resolver. |
| Applicable claims, token kinds and other support | Consuming domain's existing validator/policy. For example, Spec's exclusion of `code_sample` is not a global exact-reference prohibition. Model output or unregistered YAML rules cannot grant eligibility. |
| Attributed-unit boundaries and traversal | Registered typed content contract identifies the owning value/record and collects handles in declared order. Each domain preserves its other evidence types and full validation. |
| Repair scope, approval and semantic review | Existing consuming-domain authority, coordinated through shared repair/runner mechanisms. Reference expansion grants no new target or verdict authority. |
| Allocation and lifetime | Existing action/value owner retains immutable inputs and allocator-owned results; no process-wide cache or cross-execution reference table. |

The mechanical input is a bound reference ledger, explicit claim selection,
ordered typed exact handles and native eligibility facts. Its output is resolved
occurrences and a derived reference view, or a precise typed rejection. It does not
receive workflow names, model callbacks, publication authority or operational ports.

An empty reference component is not a universal text-validation bypass. Today's
`typed_text.Validator` validates a reference grammar binding and requires nonempty
source scopes. Each consumer must supply its accepted text/source context; accepting
user-answer-only typed prose without that context is not already implemented by
allowing `L=[]`. If a consumer needs that extension, define it explicitly at the
existing text boundary, reusing normalization and rejecting unavailable references.
Do not fabricate source scopes or weaken Spec validation to enable it.

Keep the dependency direction acyclic: `typed_text` should name the low-level
[reference_identity](../src/domain/reference_identity.zig) type, not import the
extraction/resolution layer that already consumes typed text. Shared reference
mechanics must not import Spec generation/session/policy types. Existing actions
call the pure owner; orchestrators only coordinate declared runner bindings. If a
separately callable operation is required, register it through the existing registry;
do not hide it in the runner or create a new dispatcher.

Keep this refactor bounded. `Items`, claim lookup and citation union currently live
under reference reconciliation. Reusing those mechanical fact types does not
require dismantling extraction/reconciliation or introducing a new generic evidence
framework. Move only declarations whose dependencies prevent reuse, and remove the
superseded declarations; preserve one implementation of each join and policy.

### 6.2 Configured shapes and identity bindings

[ADR 0003](../design/decisions/0003-generic-workflow-engine.md) allows any workflow
identity composed from registered contracts. A response schema supplies shape;
the registered native operation supplies semantic interpretation. Plan's existing
[typed-leaf design](../design/contracts/07-domain-representations.md) already
distinguishes business text, semantic text and operational references.

- Apply this contract to declared typed fields, including nested records, arrays
  and optional containers supported by that native contract. Do not recursively
  interpret arbitrary objects named `claim_id`, `kind` or `provenance`.
- Keep JSON decoding and [composition](../src/domain/json_composition_runtime.zig)
  structural and prompt-free. Assembly does not resolve references or certify
  semantic support; typed admission and full validation follow it.
- Keep one configured complete schema per response binding; derive selected/part
  schemas from it and verify conformance with the registered shared text contract.
  The [schema compiler](../src/domain/model_result_schema.zig) supports local
  `#/$defs/` references, not external schema imports. Do not invent a second schema
  registry or assume cross-file imports. Existing schema/partition limits still apply.
- No-reference workflows remain unchanged. A new JSON shape is usable only when its
  semantic fields have a supported registered native contract. New authority kinds
  require an explicit native-contract extension, not configurable executable rules.

`ClaimId` is snapshot-local. The request and native content owner must bind one
validated reference namespace; the model need not echo that engine identity. One
snapshot can contain many source documents. Two independent snapshots can both
contain claim 2; never flatten them into one ordinal space or choose the first match.
Multi-snapshot attribution within one unit is not established by current code and
needs a separate qualified-binding contract. Missing/ambiguous bindings must reject
before a request can treat those ordinals as available choices.

The corpus `StateId` alone is not a freshness proof. A rebuilt extraction can retain
that source namespace while changing claim order or meaning. Bind the actual
captured ledger and current producer/dependency generations, as existing
[native dependency capture](../src/domain/specification_candidate_context.zig) and
[reference lineage](../src/domain/reference_reconciliation_context.zig) already do.
Persisted readback resolves against its exact captured ledger/contract. Do not
substitute `(StateId, ClaimId)` equality for these checks or create a new hash/ID
registry to duplicate them.

A later workflow reuses the validated predecessor's reference identity where its
contract permits. It does not remint source occurrences merely because the workflow
name changed. Fresh execution envelopes remain execution-local; they do not replace
persisted reference namespaces, predecessor freshness or contract validation.

### 6.3 Workflow applicability and preserved authority

| Workflow/use | Reusable part | Authority that remains separate |
| --- | --- | --- |
| Specify | Source-backed business fields, exact literal dependencies and reference-derived citations. | Retained-claim policy, business token restrictions, coverage, questions and semantic/principle review. |
| Plan | Exact references in declared narrative fields using validated upstream evidence. | Editable-spec authority, accepted user answers, repository facts, principles, file/path candidates and plan approvals. |
| Tasks | References within supported description fields; existing native IDs/counts remain computed. | Task obligation IDs, approved `fileId`s, command IDs, dependencies and task-definition approval. |
| Implement | Reference display in declared explanatory content where its contract permits. | Authorized edits, raw code/patch payloads, approved files and task-scoped copy sources. No implicit expansion inside code strings. |
| Another registered workflow | The same typed reference mechanism, without a workflow-name branch, when its operations supply the required evidence. | Its own registered evidence, review and publication contract; no automatic SDD predecessor sequence. |
| Workflow without reference-backed content | Existing JSON/schema, runner and other deterministic operations. | No fabricated claims, source capture, additional prompts or mandatory reference stage. |

`L` is only the reference-claim component. [Plan](../design/contracts/18-plan.md)
also admits authenticated edits and other evidence; [Tasks](../design/contracts/19-tasks.md)
selects obligation/file/command IDs; [Implement](../design/contracts/20-implement.md)
uses authorized operation and copy-source contracts. Keep those namespaces and
accepted support. An exact display reference never grants read, write, copy, command
or approval authority and must not replace an operational ID.

Preserve the SDD gates: open Spec clarifications block Plan; open Spec/Plan
clarifications block Tasks; Implement requires current upstream approvals and no
unresolved upstream clarifications. Reference resolution satisfies none of these
gates by itself. Unrelated workflows retain their own declared gates.

### 6.4 Evidence needed to claim reuse

The inspected production workflow resources currently implement Spec; full
Plan/Tasks/Implement generation is not demonstrated. Their rows above are integration
requirements, not completed features. Verify a second non-Spec registered test
consumer with a different response shape and native eligibility before calling the
mechanism reusable. Merely renaming the Spec workflow or testing its helper directly
does not establish independent reuse. Test generic composition separately from
domain admission, and disclose offline tests versus live workflow evidence. Use
test-owned bindings for this proof; do not ship a production node, policy registry
or workflow solely to satisfy the test.

## 7. Other deterministic opportunities, ranked separately

### A. Reconciliation token metadata

A preserved-token statement/signal already selects its single owning claim but
also returns its token ID. Existing validation derives the required token and
existing repair can correct that metadata. Removing the redundant model field is
feasible through the same principle: one semantic selection, native expansion.
Do not remove semantic retained/duplicate/superseded/conflicting decisions under
the pretext that their IDs are mechanically checkable.

### B. Summary keys and ordering

`StatementProposal.local_key` is checked for uniqueness, has dedicated repair
cases, and determines sorting before native statement-ID assignment. Removing it
can eliminate a bookkeeping failure class, but requires an explicit ordering rule:
response-array order or a justified canonical order. Preserve occurrence-based
repair identity across insertion/deletion. Do not treat semantic equivalence or
desired presentation order as a numerical calculation. Remove the old key schema,
sort/key-repair branches and tests only with replacement evidence.

### C. Review assignment association

When one request already names one requirement, attach that identity natively;
the existing selected finding repairs already follow this pattern. In a batch,
missing/reordered findings make unchecked positional binding unsafe. Keep explicit
IDs or use an approved schema of engine-named slots with complete membership
validation. Do not create one call per finding merely to avoid a number: it can
increase latency and input tokens substantially.

### D. Deterministic diagnostics

Report the exact rejected selection and missing relationship from existing native
facts. This is useful regardless of contract redesign. It should replace generic
wording, not become another policy table or an excuse to retain redundant response
fields indefinitely. Repeated-error feedback must use confirmed failure identity;
attempt count alone does not establish repetition.

Counts, citation unions, record IDs, JSON assembly and Markdown generation already
have owners. Improve conformance where needed; do not build duplicate versions as
part of this work. No evidence supports replacing semantic review with arithmetic.

## 8. Benefits, costs and risks

**Expected benefits:** fewer invalid combinations; smaller model outputs; less
bookkeeping guidance; fewer avoidable repair calls; reproducible lineage and
diagnostics; clearer unit/property tests; shared mechanics with explicit domain policy.
Request/token/latency improvements are hypotheses until measured on comparable runs.

**Costs:** coordinated model/canonical contract changes, effective-provenance
derivation, repair/readback conformance and replacement regressions. The preferred
shared handle avoids bidirectional text conversion, but not those costs. Removing
redundant metadata can reduce useful context if requests are over-trimmed.

| Alternative | Assessment |
| --- | --- |
| Better diagnostics only | Smallest operational change; can name the missing claim precisely. Retains the model bookkeeping failure class. |
| One claim handle, still repeat it in provenance | Removes token/citation disagreement but preserves the reported missing-supporting-claim failure. Insufficient for this objective. |
| One handle, permanently flatten explicit and derived claims | Avoids the initial mismatch but cannot meet the stated removal/readback guarantees. Reject this shortcut. |
| One handle in model/canonical text; retain explicit selection and derive effective provenance | Preferred: meets the stated guarantees with one selection authority and no pair conversion. Requires the focused cross-cutting amendment. |

The model can still select the wrong or nonexistent occurrence, omit an exact
value, misunderstand a requirement, or return malformed JSON/no answer. This
proposal eliminates redundant joins, not all reference selection or provider
failures. Native membership checks and bounded recovery remain necessary.

| Risk | Required control |
| --- | --- |
| Citation laundering | Derive only dependencies of explicit allowed references; keep source entailment in semantic review. Never cite all claims by default. |
| Coverage appears complete while meaning is lost | Retain meaningful-story/FR/AC and obligation checks in semantic assessment and live rubric evaluation. Include deliberately poor but well-linked candidates in tests. |
| Identical literal selects wrong source | Use existing occurrence identity and captured source scope, not value equality. |
| Scope changes unexpectedly | Compare passive choices against an equivalent valid old candidate using complete lineage; preserve fixed repair scope. |
| Replacing/removing content leaves stale derived claims | Recompute from the complete authorized unit; do not append to old derived unions. |
| Retry scope silently widens | Preserve fixed effective evidence; a change needs a specifically authorized group or blocks. Preserve stable identity and bounds. |
| Two authorities disagree | One reference ledger and resolver; schemas/packets are projections. No parallel mapping cache or side store. |
| A shared projection breaks an unchanged consumer | Preserve reconciliation/review token metadata while deriving contract-appropriate choices from the same owner. |
| Spec policy leaks into other workflows | Keep common mechanics below domain types; each consumer supplies its native eligibility and other accepted evidence. |
| Same ordinal resolves against the wrong snapshot | Bind the exact namespace in the native request/value owner; reject ambiguous or swapped bindings. |
| Display values gain operational authority | Preserve file, command, obligation, approval and copy-source contracts; never interpret raw code/patch strings as display segments. |
| Readback conceals corruption | Recompute for comparison and reject mismatch, rather than normalize corrupt persisted data into validity. |
| Pre-/post-extraction identities are confused | Keep token-candidate classification separate from later claim selection. No runtime guessing between formats. |
| Simpler schema is mistaken for a solved workflow | Require downstream semantic assessment, publication/readback and rubric evidence. Safe failure is containment, not completion. |

## 9. Decisions required before implementation

The user's request authorizes this assessment only. Prior §36 approval authorized
bounded coupled repair, not native construction of new provenance under a changed
model contract. The following focused decisions are still proposed:

1. **Shared exact-reference shape:** use one preserved-token claim handle in model
   and canonical segments; update the closed content/version contracts and reject
   old formats. Apply through registered typed fields in any workflow, with the
   shared/domain split in §6.1. Preserve pre-ledger identities and other namespaces.
2. **Content selection and effective provenance:** persist explicit selection once;
   derive reference dependencies and their stable union. Keep this reference view
   consistent across its consumers without replacing other workflow support types.
   Spec positive review/readback and passive choices follow §5; other purpose and
   diagnostic policies retain their existing owners.
3. **Fixed/coupled repair:** pin available valid effective evidence for value-only
   repair; specify the independently validated scope used when a rejected handle
   prevents that evidence from existing. Define any additional authorized coupled
   add/remove cases; otherwise block them. Update membership/omission equality and
   precise targeting, retiring only mechanics made obsolete by the removed tuple.

The narrow invalid-handle baseline and comparison rule proposed in §5.5 need an
explicit decision before implementation; their documentation is not approval.
An implementation request must not silently choose broader authority. Review
evidence attachment, reconciliation token metadata removal, multiple-ledger attribution and zero-scope typed text remain
separate follow-ups, not prerequisites to be folded into this patch.

Governing amendment surfaces: [§7.1](../design/contracts/07-domain-representations.md),
[§12](../design/contracts/12-model-boundary.md),
[§16.3](../design/contracts/16-reference-ingestion.md),
[§17.3](../design/contracts/17-specify.md),
[§22](../design/contracts/22-repair.md), and affected persistence/rendering contracts
in [§§23–24](../design/design.md#23-rendering-and-editability-strategy).
In particular §17 currently requires the supporting claim in model-selected
provenance, and §22's approved §36 amendment says the engine adds no citations.
This document does not silently override those rules or accept the overall
Proposed design.

Summary-key removal and batch-review changes need their own bounded decisions;
they are not prerequisites for the first exact-reference change.

## 10. Phased rollout with testable checkpoints

**All chunks below are planned, not implemented.** Begin with Phase 0; contract
implementation waits for its approval gate. There are five phases and eleven
chunks. Each chunk produces a reviewable diff, named regression evidence and a
recorded proceed/revise decision. §11 supplies the common acceptance matrix;
passing a safe-block test must never be reported as successful recovery.

The smallest change that can land independently is the behavior-preserving owner
refactor in Phase 1. Phase 2 changes a closed format and must activate as **one
coherent change**: model/canonical types, schemas, repair and readback cannot run in
mixed versions. Develop its chunks in an isolated working change, test each owning
boundary, and integrate them before activation. They are review checkpoints, not
independent releases. Coalesce inseparable edits if necessary to keep their owning
tests executable; do not introduce temporary runtime flags, dual readers, skipped
tests or conversion adapters to manufacture smaller deployable patches.

### Phase 0 — Establish evidence and settle authority

**0.1 — Baseline and failure-class regression.**

- **Outcome/owners:** extend existing generation/request tests with the retained
  failure (§2): valid source occurrence, inconsistent tuple/support, repeated repair,
  and exhaustion. Include unrelated literals, two sources with equal bytes, a
  meaningful successful candidate and a mechanically valid but meaningless one.
- **Checks:** capture actual initial, native-repair and protocol-correction requests
  through existing fake ports; record request/schema bytes, compiled graph size and
  retained usage. Label existing failures as containment. Adapt these cases to the
  new contract later; never keep the old format as an accepted alternate.
- **Exit/revise:** every claimed failure has an observed boundary and every proposed
  success has assertions beyond parsing. If the motivating defect cannot be
  reproduced, correct the diagnosis before implementation. No live call is needed.

**0.2 — Approve the closed contract and repair table.** Depends on 0.1.

- **Outcome:** resolve §9 through the named governing contracts: shared claim handle,
  explicit selection versus derived lineage, version rejection, and §5.5's proposed
  invalid-handle bound. Specify each repair's target, fixed facts, permissible change,
  comparison and dependent validation. Identify tuple-specific authority to retire.
- **Checks:** trace initial generation, value/provenance/coupled/membership/omission
  repairs, positive/negative review and both state variants against that table. Work
  through reference addition/removal, invalid `S`, unavailable `L` and reordered text.
- **Exit/revise:** explicit approval and unambiguous accepted/rejected examples are
  required. If a case needs broader authority, expose that decision; do not defer it
  to request-building code. No new provider mode, workflow or retry policy is included.

### Phase 1 — Remove coupling without changing behavior

**1.1 — Refactor the existing reference owner.** Depends on Phase 0.

- **Outcome/owners:** move common selection/lineage mechanics below Spec types in
  `reference_support`; adapt its consumers. Keep Spec eligibility and non-reference
  support with their domains. Retain the current response and persisted formats.
- **Checks:** existing accepted/rejected selections, citation ordering, scope and
  rendered bytes remain unchanged; architecture checks enforce dependency direction.
  Request comparisons confirm the refactor has not changed model instructions or
  choices. Exercise allocation failure and cleanup at changed ownership boundaries.
- **Exit/revise:** this chunk may land independently once applicable tests and full
  verification pass. If it requires a second resolver, policy registry or a shared
  module importing Spec, revise the boundary before the contract change.

### Phase 2 — Implement one coordinated format change

**2.1 — Native handle resolution and lineage construction.** Depends on 1.1.

- **Outcome/owners:** change typed exact segments and canonical selection according
  to the approved contract. Reuse reference lookup/union and typed-text validation;
  consuming domains enumerate only their declared fields and owning evidence units.
- **Checks:** both §5.2 ambiguity examples round-trip; repeat references preserve
  text, derived membership deduplicates, explicit duplicates reject, and empty `S`
  follows the approved rule. Test arrays/optional fields/shared records, wrong-kind
  handles, same-value occurrences and stale producer bindings under the same state ID.
- **Exit/revise:** native construction and error localization pass at their owners.
  Ordinary JSON remains structural; no reflective search for `claim_id` keys and no
  literal-text guessing. Stop if the implementation loses explicit/derived roles.

**2.2 — Requests and configured schemas.** Depends on 2.1.

- **Outcome/owners:** update `model_evidence`, session/repair packets and configured
  complete schemas. Derive selected/part schemas through existing owners. Initial
  generation, embedded prior content, repair `current_value` and correction use the
  same handle syntax and eligibility. Replace superseded prompt instructions.
- **Checks:** inspect serialized requests, not only helper results. Offered choices
  identify the claim directly; old tuple fields reject; initial/repair schemas agree
  with native admission. Unchanged extraction/reconciliation/review consumers retain
  needed token metadata. No request contains parallel exact-choice catalogues.
- **Exit/revise:** contract tests pass for each request purpose, including selected
  repairs and omitted-record context. Any need for a whole-candidate conversion API
  or duplicated schema authority sends this chunk back to the ownership review.

**2.3 — Repair, coverage and dependency renewal.** Depends on 2.1–2.2.

- **Outcome/owners:** adapt native and coverage repair through their existing atomic
  authorizations. Retain the original approved invalid-handle baseline across attempts
  while updating expected value/revision. Compare effective evidence where required;
  keep coupled, membership and reviewed-insertion policies distinct. Update native
  exact reconstruction and remove the obsolete tuple-specific trigger/guidance.
- **Checks:** unknown handle → bounded valid replacement; unchanged/alternating errors
  → exhaustion; invalid `S` → its authorized recovery or block. A later rejected
  handle cannot enlarge the original bound. Reordering preserves evidence sets;
  adding/removing dependencies outside authority rejects. Verify siblings, origins,
  full-unit validation, dependent rebuilding and exact usage/retry accounting.
- **Exit/revise:** include a repair that passes its field but fails later coverage,
  proving no publication, alongside real bounded recovery. Missing/corrupt trusted
  bindings terminate without another model call. If recovery needs new authority,
  return to 0.2 rather than weakening equality or increasing retries.

**2.4 — Review, rendering and persisted readback.** Depends on 2.1–2.3.

- **Outcome/owners:** coverage, source/principle evidence, projection and completed
  state consume the same derived lineage. Preserve negative diagnostic eligibility.
  Update affected version contracts and pending-state handling together; pending
  state still does not store attributed specification content.
- **Checks:** meaningful fake-provider output reaches generation, coverage, semantic
  routing, publication and readback. Corrupt handles/selection/review projections
  reject. Test old versions, both current state variants, exact Markdown expansion,
  clarification failure precedence and downstream gates. A trusted-join pass cannot
  turn an inconclusive finding into a user question or completion.
- **Exit/revise:** every producer/consumer in §6 agrees; superseded formats, readers,
  tuple-only repair branches and fixtures are removed. Keep negative tests that reject
  old shapes. Any readback discrepancy blocks the whole Phase 2 change. No activation
  until Phase 3's integration gate passes.

### Phase 3 — Prove reuse and integration offline

**3.1 — Independent consumer and cross-boundary regressions.** Depends on Phase 2.

- **Outcome/owners:** prove the §6.4 contract through a test-owned registered non-Spec
  consumer with different fields and eligibility, using the same reference mechanism
  and existing runner/composition. Add no production demonstration workflow/framework.
- **Checks:** nested/array/optional typed fields, no-reference workflows and mixed
  domain evidence retain their boundaries. Sliced results, renewed dependencies,
  stale reads and operational IDs behave correctly. Combine successful assignments
  with repeated/alternating protocol and native errors under the global budget.
- **Exit/revise:** independent integration and negative tests pass without Spec/session
  imports or workflow-name branches. This proves a reusable contract, not completed
  Plan/Tasks/Implement workflows. A helper test or renamed Spec workflow is insufficient.

**3.2 — Measurements and complete verification.** Depends on 3.1.

- **Outcome:** compare 0.1's requests with the new contract across brief/story,
  records, selected repairs and corrections. Record input/schema/output bytes,
  configured graph/operation count and native runtime/allocation behavior over small
  and larger valid ledgers. Use existing measurement owners; add no permanent cache,
  benchmark framework or local model-call ceiling merely for this change.
- **Checks:** run the registered checks below, then full `zig build verify` and
  `git diff --check`. Full verify already includes clean-directory native packaging
  smoke; repeat it only when later changes invalidate that evidence. Review packaged
  workflow/schema resources and the full diff for duplicate policy and dead paths.
- **Exit/revise:** all applicable tests pass; no unexplained request/resource growth
  or additional orchestration/model call is accepted as automatic simplification.
  Bytes are not token counts. Offline usage fixtures prove accounting only; record
  actual model tokens in Phase 4. Failed checks reopen the owning chunk, not the judge.

### Phase 4 — Measure live effectiveness with separate approvals

**4.1 — Controlled assignments.** Depends on 3.2 and explicit call approval.

- **Outcome:** prepare comparable captured assignments from the reported and unrelated
  cases. Hold sources, semantic task and provider settings fixed; change the approved
  contract/projection together. Use the existing debugger and capture, with a declared
  call count and budget. Keep the old response as evidence, not a second runtime path.
- **Checks:** record final-answer presence, JSON/schema/native validity, literal and
  meaning preservation, repair outcomes, actual tokens and latency for every attempt.
  A failed earlier baseline alone does not establish a statistical improvement rate.
- **Exit/revise:** report whether the redundant join failure was removed and whether
  new failures appeared. Do not proceed on shape success alone. If poor semantic
  content remains, identify its owner separately; do not add guessed evidence or
  tuning for the greeting. No automatic rerun or workflow publication in this chunk.

**4.2 — Whole-workflow publication and rubric.** Depends on 4.1 and a separate E2E approval.

- **Outcome:** use `./scripts/e2e-spec.sh --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json` with an explicitly
  approved fresh target under this project's `zig-out` and the case's configured
  generation/grading budgets. Prepare the concrete proposal before asking approval.
- **Checks:** inspect original source obligations, meaningful story/FRs/Given–When–Then,
  exact values, principles, necessary clarifications, persisted readback, publication
  and the actual rubric report. Offline fixtures or hand-written expected Markdown
  cannot substitute for generated/scored output. Broader live claims need separately
  approved unrelated cases, not just the Hello World fixture.
- **Exit/revise:** close live readiness only with completed, validated publication
  and the configured rubric acceptance result. A pause, failure or ungraded output
  leaves the relevant gate open; retain its evidence and revise the owning chunk.
  Each further E2E execution needs approval. Do not bundle §7's deferred work to mask
  a failed result.

### Registered verification commands

These are existing [build.zig](../build.zig) steps to extend/use during implementation,
not tests executed by this documentation review. New tests must be registered in
the complete suite; do not use standalone `zig test` as a parallel build path.

| Boundary/chunks | Targeted commands |
| --- | --- |
| Reference mechanics, 1.1/2.1 | `zig build test-reference-evidence test-reference-model-input test-typed-text test-architecture` |
| Closed shapes/requests, 2.1–2.2 | `zig build test-specification-contract test-model-candidate-json test-model-result-schema test-model-request-preparation` |
| Native generation/repair/readback, 0.1/2.3–2.4 | `zig build test-specification-generation test-workflow-repair-retry` |
| Protocol/accounting/integration, 2.3/3.1 | `zig build test-model-request-workflow test-model-attempt-accounting test-pipeline-envelope test-atomic-execution test-workflow-graph` |
| Preserved upstream behavior and gates, 2.4/3.1 | `zig build test-reference-extraction test-reference-reconciliation test-required-authority test-clarification-inputs` |
| Independently landable change / complete integration, 1.1/3.2 | `zig build verify` and `git diff --check`; `zig build smoke` is available for targeted packaging iteration |

Keep revision decisions local to the owning chunk while validating their dependent
closure. If Phase 2 must be reversed before activation, reverse the coherent format
change, not selected readers. An older executable cannot be assumed to read newly
written state; version rejection remains mandatory. Preserve retained run evidence
and user clarification records rather than adding migrations or fallback readers.

## 11. Acceptance and regression matrix

| Case | Required evidence |
| --- | --- |
| Reported greeting and unrelated business requirements | One selected exact claim resolves the correct literal/citation without model-supplied duplicate IDs; meaningful successful candidates proceed through the existing gates. |
| Old tuple shape/version | New response and canonical contracts reject superseded segment fields and old state versions. No compatibility path. |
| Request choices | Offered exact choices identify their claim directly. Initial requests, fixed repairs, canonical brief/entity context and omission context use coherent handle syntax and eligibility. |
| Shared projection consumers | Spec exact-choice projection changes without dropping token IDs required by reconciliation or source review. Each request has the facts its declared contract requires, without duplicate choice lists. |
| Unknown/wrong-kind/ineligible claim or stale/foreign state binding | Typed rejection; no default, citation insertion, publication or clarification conversion. Reused ordinals do not bypass state/dependency checks. |
| Same literal in different sources | Exact selected occurrence retained; no first-match selection. |
| Repeated exact segment | Stable ordered citation union, preserved text order/repetition and idempotent expansion. Duplicate derived dependencies collapse; duplicate explicit evidence selections still reject. |
| Explicit/derived overlap | The two §5.2 examples remain distinguishable after round-trip. Removing a reference under an authorized group drops only derived support; intentional explicit token evidence survives. |
| Empty explicit selection | In source-backed Spec, `S=[]` is permitted when eligible exact segments supply nonempty effective evidence; empty effective evidence rejects. Other domains retain their accepted non-reference support. No semantic-quality pass is implied. |
| Reference added, replaced or removed | Correct dependency recomputation for the whole authorized unit; unrelated sibling data and producer origins unchanged. |
| Shared-provenance acceptance record | All fields contribute exact dependencies; Given/When/Then retain separate meaning and unaffected content. |
| Fixed-evidence repair | Pin explicit `S` exactly and compare effective claim/citation sets. Harmless segment reordering recomputes stable canonical order; it does not fail merely because the derived list order changed. Reference removal/addition cannot shrink/expand evidence without its authorized coupled target; include unchanged siblings in the full-record check. |
| Invalid candidate without complete provenance | Cover valid explicit support/siblings plus an unknown handle recovering within approved `B`, and empty/insufficient `B` blocking. Unknown handles grant no scope. A field-only success followed by exact-coverage failure must not publish. Do not demand equality with old `L` that never existed. |
| Invalid explicit support and invalid handle | Existing evidence repair or an authorized group handles invalid `S`; it is never pinned as trusted scope. Cover staged recovery and exhaustion with unchanged retry families, sibling data and accounting. |
| Repair cannot expand its own scope | Retain original `B` while expected values/revisions advance. A later rejected response containing a newly eligible handle cannot enlarge the next request's permitted set. Upstream changes invalidate existing authorization through its normal dependency checks. |
| Bad selection versus broken binding | Unknown model choices under valid authority may repair. Invalid/missing trusted ledger or choice binding follows existing terminal rejection, with no extra model call, clarification or publication. |
| Passive references and source scope | Equivalent valid candidates retain their available choices; removed dependencies force sibling revalidation. Operational path capabilities remain unchanged. |
| Native expected value / model presentation | Existing atomic checks still bind exact native expected values and dependencies. Shared handle syntax must not conceal differences in evidence shape or authorize lossy comparisons. |
| Diagnostic localization | A rejected handle names its field/segment and permitted choices; it targets value repair, not unrelated provenance. Changed invalid IDs do not restart the same assignment's allowance. |
| Supported and negative review evidence | Supported findings compare with effective provenance. Loss/negative findings retain their existing distinct eligibility; validate both live in-memory and on completed-state readback. |
| Sliced response/dependency renewal | Stale completed parts reject; renewed dependencies rebuild all affected validators/reviews before publication. |
| Missing answers, invalid JSON/schema and repeated invalid handles | Existing retry identities, exhaustion, failure precedence and exact usage accounting remain unchanged. Successful unrelated work continues within budget. |
| Completed versus pending state | Completed readback revalidates stored content selection, reference handles and coverage/review projections. Pending readback retains its reference/clarification identity contract without new content storage. Both share the state-version tag today; cover accepted current variants and rejected old versions together. |
| Canonical state tampering | Foreign/deleted claims, invalid exact handles and mismatched retained coverage/review projections reject on readback. Derived views are computed; corrupt authoritative values are never silently repaired. |
| Empty/meaningless but correctly linked story or AC | Never counted as semantic recovery merely because joins pass. Scripted review tests routing; approved live rubric tests actual quality. |
| Pre-ledger extraction and reconciliation | Their existing allowed shapes and source selections remain intact; exact-copy business segments are not newly admitted there. |
| Independent workflow reuse | Two differently named configured workflows with distinct response shapes use the same shared resolver through registered typed consumers. The second consumer has no Spec/session dependency or workflow-name branch. |
| Shape and policy variation | Nested records, arrays and optional typed fields contribute only to their owning evidence unit. Different native eligibility sets remain enforced; Spec-only restrictions do not become global. |
| Structural JSON versus typed meaning | Reference-looking objects in ordinary JSON remain ordinary data. Existing schema/composition limits reject unsupported shapes; resolution does not enter the generic assembler or decoder. |
| No-reference and mixed-support workflows | No unnecessary ledger/model calls for an unrelated workflow. Domain-accepted user answers, repository facts and other support are not dropped or converted to fabricated claims. |
| Namespace isolation and reuse | Swapped bindings reject across different states and after changed ledger production under the same corpus ID/ordinal. A bare ordinal cannot reveal unstated model intent. Valid predecessor identity survives a fresh execution; stale producer/contract changes invalidate dependents. |
| Operational and stage boundaries | Display references grant no file/copy/command capability; source-like strings inside code remain raw payload. Existing clarification and approval gates remain independent. |
| Shared dependency direction | Architecture checks reject shared reference/syntax modules importing Spec generation, sessions or policy; no second resolver/schema/policy registry. |

## 12. Feasibility conclusion

**Viable for reuse across workflows through a shared typed contract, with Spec as
the first integration.** The engine already has occurrence identities, structural
composition and registered-operation boundaries. The remaining work is the shared
reference refactor, canonical selection representation and repair/readback conformance.
The decisions in §9 are prerequisites to contract implementation. Phase 3 supplies
the offline integration/reuse evidence; Phase 4 separately assesses live outcomes.
Neither the approved contract nor successful helper tests establish those outcomes.

This does not promise automatic support for every JSON Schema, authority namespace
or future workflow. New domains reuse the mechanism by supplying their declared
typed fields, validated reference binding and native policy; they do not duplicate
the resolver or inherit Spec's semantic rules. Workflows without reference content
continue using their existing deterministic owners.

The first implementation should remove one avoidable failure class end to end.
It must not claim deterministic proof of specification quality, silently infer
business evidence, or hide unresolved model errors behind mechanically complete
coverage. Broader bookkeeping simplifications should follow measured evidence,
independently of this first contract.

**Evidence limit:** this review inspected current code and governing contracts;
it made documentation changes only. The proposed types/schemas have not been
compiled or exercised, and no live effectiveness claim follows from this review.
Existing regression owners include [specification generation tests](../src/specification_generation_test.zig),
[typed-text tests](../src/typed_text_test.zig), [request workflow tests](../src/model_request_workflow_test.zig)
and [native packaging smoke](../test/packaging/smoke.zig); implementation must extend
them with the matrix above rather than count existing containment tests as recovery evidence.
