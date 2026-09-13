# FIX_001 — Phase 0 contract review

Status: Phase 0 complete; A1–A3 explicitly approved and applied to the design.
Reviewed: 13 September 2026, against source revision
`5d751c8ae06e4bac1641dc21655af2e596528ba8` and the current working tree.
Scope: chunk 00 of [TODO_FIX_001.md](TODO_FIX_001.md#phase-0--establish-the-shared-contract),
using [FIX_001 §§4 and 6](FIX_001.md#4-detailed-causes-and-ownership).
This document records implementation decisions, acceptance cases and amendment
approvals. Governing wording lives in `design/design.md`; this review introduces
no runtime contracts and establishes no test or live-run pass. Subsequent
implementation evidence is recorded in the [Phase 1 delivery log](TODO_FIX_001.md#phase-1-delivery-and-verification--13-september-2026); the boundary table below
retains the source state reviewed for Phase 0.
The later [R12 review](FIX_001.md#9-post-phase-1-live-run-review) reopened chunk 01
for missed protocol-prompt cleanup and refined observation/readiness checks.
The [Phase 1 follow-up](TODO_FIX_001.md#phase-1-follow-up-completion--13-september-2026)
now closes that item. A1–A3 and accepted engine authority remain unchanged.

## 1. Outcome, authority and ownership

The shared contract must distinguish a rejected model proposal from missing
source authority and from broken execution context. A repairable rejection must
reach the existing authorization, merge and validation path with enough evidence
to correct only its authorized unit. This applies to registered workflows across
the engine; Specify supplies the first concrete consumers.

The review follows [design §§1, 3–4](../design/design.md#1-executive-summary),
[§12](../design/design.md#12-llm-interaction-boundary),
[§17](../design/design.md#17-specify-stage-design),
[§§21–22](../design/design.md#21-deterministic-validation-catalogue),
[§25](../design/design.md#25-atomic-workflow-execution-and-output),
[§§27–28](../design/design.md#27-observability),
[§30](../design/design.md#30-delivery-sequence-for-the-new-engine) and
[§31](../design/design.md#31-acceptance-criteria-for-the-design-implementation).
The applicable invariants are 1, 5–9, 14–15, 19–23 and 30–32; acceptance criteria
12–19, 30–31, 34 and 36–41 cover the affected behavior. Accepted ADRs
[0006](../design/decisions/0006-minimal-model-response.md),
[0009](../design/decisions/0009-atomic-workflow-execution.md),
[0011](../design/decisions/0011-provider-owned-request-limits.md),
[0013](../design/decisions/0013-workflow-input-reuse.md) and
[0014](../design/decisions/0014-universal-response-format-guidance.md) retain their
authority. The governing design remains **Proposed design**.

| Responsibility | Existing owner and boundary |
| --- | --- |
| JSON shape and decoding | [Compiled schema](../src/domain/model_result_schema.zig), [schema diagnostics](../src/domain/model_schema_diagnostic.zig), [projection](../src/domain/model_schema_projection.zig) and [native codec](../src/domain/model_candidate_json.zig). A provider projection is guidance, not another acceptance policy. |
| Semantic candidate rejection | Owning domain validator returns checked data or a typed rejection. [Candidate diagnostics](../src/domain/candidate_validation_diagnostic.zig) carry that rejection; authorizers consume it rather than rediscovering its rules. |
| Repair authority | [Atomic repair](../src/domain/atomic_repair.zig) owns association and compare-and-swap. Domain owners supply typed targets, bound rules and dependency facts; they do not create another retry mechanism. |
| Continuation | Registered operation outcomes and [workflow YAML](../design/workflows/spec.workflow.yaml) select transitions through runner-owned bindings. No prompt or diagnostic renderer grants continuation. |
| Source authority | [Required authority](../src/domain/required_authority.zig) owns reconciliation and earliest-stage routing. Domain projections contribute facts without deciding success. |
| Clarification and publication | [Clarification refresh](../src/domain/clarification_refresh.zig) and [workflow output](../src/domain/workflow_output.zig) retain their lifecycle, protected-form and publication authority. |
| Observation | Native diagnostics and the existing request ledger feed [application projection](../src/application/candidate_validation_diagnostics.zig) and [harness trace](../test/harness/e2e/trace.zig). Reports do not revalidate or authorize candidates. |

Phase 0 changes documentation only. No runtime, schema, YAML, prompt, dependency,
packaging or security change is made. Later persisted evidence changes must update
state builders and parsers together. ADR 0009 rules out adding checkpoints,
rollback or provider recovery. No global retry counter or per-call token limit
is introduced. Offline checks cannot establish the first published, scored live
baseline; that remains rollout chunk 19.

## 2. Classification and transition matrix

These labels describe the existing §22.2 classes; they are not a new runtime enum
or configurable rule table:

- **Candidate rejection:** syntax/schema correction before valid IR, or
  `model_atomic` only when a safe target and current supporting authority exist.
- **Source-authority gap:** `user_input` through shared reconciliation, including
  upstream rework when detected downstream. Unknown ownership blocks.
- **Operational/context failure:** `environment` or `not_repairable`, depending
  on the exact native cause. No semantic repair attempt is consumed.
- **Canonical construction:** derive documented engine-owned facts from checked
  choices before candidate identity; do not silently repair asserted model facts.

An error name such as `InvalidReferenceReconciliation`, `InvalidSpecification`
or `InvalidRequiredAuthority` is insufficient to choose a class. Validate context
and association separately from candidate content. Current transitions below are
source observations, not new claims about unrecorded live runs. `end.*` denotes
the YAML edge; runner rejections can terminate before that edge is reached.

| ID / boundary | Current behavior and evidence | Intended classification and transition | Later chunks / acceptance |
| --- | --- | --- | --- |
| B01 — JSON and selected schema | [Protocol retry](../src/domain/model_protocol_retry.zig) retains original inputs and rejected bytes but fabricates schema examples. JSON/schema rejection already takes response-level correction. | Candidate protocol rejection → original assignment plus latest diagnostic and precise schema guidance → existing local accounting and decoding. Exhaustion stays terminal. A wrong request/schema association is a context failure. | 01, 02; T01 |
| B02 — Extraction text | [Text validator](../src/actions/reference/validate_reference_extraction_text.zig) checks both source/policy binding and candidate prose. `validate-extraction-text` has only `ok/failed`. | A localized lexical/passive-reference defect → typed candidate rejection → R1. Stale grammar, source binding, allocation or reader failure → operational/context failure. Missing meaning → source gap. | 04, 12; T02 |
| B03 — Token classifications | [Classification validator](../src/domain/token_classification_validation.zig) retains missing/duplicate/unknown/forbidden IDs. `validate-selections.invalid` already enters repair; the authorizer repeats selection validation. | Retain the native rejection and use the existing coupled collection target R2. Contradictory engine-owned blocked entries and invalid candidate inventory remain context failures. Never select the first duplicate decision. | 04, 08, 12; T03 |
| B04 — Source selections | [Selection validator](../src/domain/reference_selection_validation.zig) retains exact selection issues and origin. Invalid selections already enter replacement repair. | Invalid supplied line/occurrence selection → R3; empty selection collection → its existing bounded replacement. Engine reconstructs quotation bytes. Unavailable source authority cannot be manufactured by citation repair. | 04, 08, 12; T04 |
| B05 — Constructed extraction claims/accounting | [Claim validator](../src/actions/reference/validate_reference_claims.zig) can retain a model-selection rejection; `validate-claims.invalid` terminates. Wrong chunk/state or derived-token citations can instead fail operationally. | A retained candidate selection defect returns to R3 at its original raw unit, invalidating derived tokens/claims. Engine-derived corruption, count/state mismatch after construction, and accounting inconsistency fail without asking the model to recreate IDs or quotes. | 04, 12; T05 |
| B06 — Reconciliation summaries | [Summary validator](../src/actions/reference/validate_reference_reconciliation_summary.zig) checks echoed membership, unique keys, selected claims, text and exact coverage. Invalidity collapses through application failure; no summary repair before append. | Membership becomes canonical construction. Invalid statement content/selection/key or coverage → R4, when independently repairable, before assigning IDs or appending history. Invalid partition/history binding remains a context failure. | 03, 06, 09; T06 |
| B07 — Claim dispositions | [Disposition validator](../src/actions/reference/validate_reference_claim_dispositions.zig) checks total membership, cardinality, kinds, self-links, reciprocity and cycles. Failures collapse; `validate-dispositions.failed` terminates. | Candidate cardinality/relationship defects → R5. A valid representation of conflicting source authority is retained and blocks through the shared authority path; it is not repaired until it agrees. Invalid history/current input fails separately. | 03, 07, 10; T07 |
| B08 — Signals | [Signal validator](../src/actions/reference/validate_reference_signal_proposals.zig) checks evidence, content, repeated member sets and coverage. Retained claims need coverage; non-conflicting preserved-token claims need token projection. Failures terminate. | Citation unions become canonical construction; selection/content/missing or duplicate projection defects → R6. Unresolved conflicting claims cannot be made signal-eligible by repair. | 03, 05, 06, 10; T08 |
| B09 — Conflicts | [Conflict validator](../src/actions/reference/validate_reference_conflict_proposals.zig) checks selected claims, disposition relationships and pair coverage; failures terminate. [Completeness](../src/actions/reference/validate_reference_reconciliation_completeness.zig) returns `blocked` for accepted unresolved conflicts. | Invalid conflict representation → R7. Correctly represented unresolved source conflict → shared owner-correct gap, preserving evidence. Corrupt record assignments/history remain context failures. No automatic precedence or conflict deletion. | 03, 05, 06, 10, 15; T09 |
| B10 — Specification generation | [Generation validation](../src/domain/specification_generation.zig) checks fields, kind and duplicates; [application binding](../src/application/specification_workflow.zig) reduces failures to `invalid_unit`. Existing repair walks the candidate again and replaces an attributed field or entire record. | Native rejection → R8 for the smallest independent field/record. Invalid session/unit binding remains context failure. Unsupported asserted semantics follow the existing no-invention clarification contract. | 04, 08, 11, 12; T10 |
| B11 — Specification provenance | [Provenance validator](../src/domain/specification_provenance.zig) checks current context, retained claims, citation union order and exact-copy selections under overlapping error names. | Derive citation union from checked selections. Invalid meaningful selection → R8 with text preserved when independently valid. Foreign state or broken canonical evidence → context failure; genuinely absent support → source gap. | 04–06, 11; T11 |
| B12 — Specification coverage | [Coverage validator](../src/domain/specification_coverage.zig) computes claim/token obligations but returns broad invalidity; `validate-coverage.invalid` terminates. | Missing preservation of established authority → R9. Invalid current reference/accounting context fails. Source ambiguity follows shared reconciliation. Never patch the derived coverage ledger or relabel business content as context-only to evade a requirement. | 04, 11, 12, 14; T12 |
| B13 — Support review collection | [Support collector](../src/domain/specification_support.zig) validates one finding per requirement and provenance, then drops finding detail/origin. Invalid collection fails; valid unsupported findings reach authority gaps. | Malformed/inadequately evidenced review candidate → R10. A valid finding routes by the distinction in §6: established omission versus source gap. A valid negative verdict is never retried merely to obtain a positive verdict. | 06, 13–15; T13 |
| B14 — Mandatory content and authority gate | [Specification projection](../src/domain/specification_authority.zig) emits `ForcedGap(.missing)` for absent AC/FR families; [shared resolver](../src/domain/required_authority.zig) routes forced gaps before review evidence. Pre/post `needs-user` currently ends without the generation clarification branch. | Keep missing content blocking. Classify independently established source support before authorizing R9; otherwise keep the gap. Genuine gaps become existing `Needs` and use shared refresh/render/publication, or upstream rework/admin block. Positive review cannot clear a forced gap. | 13–15; T14 |
| B15 — Repair association and merge | [Atomic repair](../src/domain/atomic_repair.zig) implements replacement only; domain consumers select targets. Some bindings collapse merge/authorization failures. | Wrong owner, association, revision, old value, rule dependency or anchor → typed terminal rejection, not another semantic repair. Valid merge invalidates derived checks and runs producing, dependent and full validation. Origin changes only for the written unit. | 02, 04, 08–12; T15 |
| B16 — Publication and evaluation | [Output contract](../src/domain/workflow_output.zig) and [writer](../src/adapters/filesystem/workflow_output.zig) publish validated outputs, with completion state last. [Oracle](../test/harness/e2e/oracle.zig) checks exact publication; [evaluation](../test/harness/e2e/evaluation.zig) requires it. | Invalid prepared authority or filesystem/evidence write failure → operational/context failure. Never model-repair a write. No successful baseline unless all required actual output passes identity checks and receives a scored evaluation; quality acceptance is separate. | 02, 17–19; T16 |

All reconciliation rows also pass through
[reference_reconciliation_workflow.zig](../src/application/reference_reconciliation_workflow.zig).
Its shared `Unary`/`TextStage` bindings currently convert action errors to
`OperationExecutionFailed`; changing a YAML edge alone cannot retain diagnostics.

## 3. Authorized repair targets and dependency checks

The following are selected target contracts under §§22.1–22.5, not claims that
the code supports all operations. The shared implementation currently has
`Target`, `Replacement`, `Rule`, owner, revision and exact expected value; it has
no insert/delete implementation or general dependency-fact binding. Add only the
operation required by its first consumer, together with that consumer's tests.

For every target, authorization retains the originating native diagnostic,
exact owner and current candidate revision, selected operation/target, expected
old value or absence/anchor, rule values and authority revisions, plus immutable
dependency facts actually read. The model receives semantic choices and the
permitted value schema; it does not echo authorization metadata or select an
operation, pointer, key or insertion position. Domain facts feed the shared
contract without turning it into a graph solver or generic capability container.

Use these preconditions in the table:

- **Replace:** current owner/revision and exact target value match; unrelated
  values and origin associations remain unchanged.
- **Insert:** current owner/revision, required missing key/obligation and exact
  collection anchor match; the authorized member is still absent. The engine
  chooses identity/order, validates the added value and rejects duplicate keys.
- **Delete:** current owner/revision and exact selected member match; retained
  members and required coverage satisfy the authorized deletion proof. No model
  `approved` Boolean supplies that proof.
- **Group:** only a predeclared inseparable set within one authorized record or
  file, with exact target-key membership and old values. None of this work
  authorizes a group spanning separate claims, dispositions or specifications.

| Target | Smallest permitted write / operation | Immutable read dependencies and validation after merge |
| --- | --- | --- |
| R1 — Extraction prose | Replace one content field or typed content value. Replace a containing claim only if its text/selection cannot be valid independently within that record. | Current chunk, selected source lines, passive registry and text policy; rerun text, classification/selection, claim construction/accounting, then full extraction. |
| R2 — Classification collection | Retain the existing §22.1 coupled collection replacement for one chunk; it covers missing, extra, duplicate and forbidden decisions in one authorized record. | Exact candidate inventory, chunk outcome and permitted decision variants; rerun classifications and source selections, reconstruct tokens/claims, validate accounting and complete extraction. No semantic first/last survivor. |
| R3 — Source selections | Replace one invalid selection; replace the known-empty selection collection under the existing missing-citations target. A duplicate selection may be deleted only after proving redundancy and preserving nonempty support. | Original unchanged claim, captured source choices, exact scope and selection issue; reconstruct quotations, rerun selections, derived claims/tokens and full extraction. Re-selection is semantic evidence choice, not permission to fabricate quoted text. |
| R4 — Summary statement | Replace a faulty field/claim selection, or one inseparable statement. Insert one statement for engine-identified uncovered claim membership. Delete an exactly redundant statement only if total coverage and order remain valid. | Fixed partition membership, child summaries, existing statements/keys, selected claims and text context; rerun uniqueness, content and exact-once membership validation before append, then complete lineage. Overlapping non-equivalent statements use gate G1. |
| R5 — Disposition | Replace the relationship choice of one engine-identified claim; replace that claim's disposition variant only when tag/payload are inseparable. Insert its missing disposition. Delete a provably redundant duplicate entry. | Current selected claim and permitted targets/kinds, all graph facts needed for reciprocity and reachability, signal/conflict obligations; rerun cardinality, relationship and graph checks, dependent signals/conflicts, then full reconciliation. Cross-record inseparability uses G1. |
| R6 — Signal | Replace one selection/content field or inseparable signal; insert one missing required projection; delete only a proven redundant projection. | Current dispositions, claim/token kinds and selections, existing projection membership and coverage; derive citations, rerun signal text/uniqueness/coverage, conflict dependencies and complete reconciliation. |
| R7 — Conflict representation | Replace one invalid selection/summary/kind field or inseparable conflict record; insert a missing record for an engine-identified relationship obligation. Redundant-record deletion must preserve every required pair. | Current conflicting dispositions, relationship pairs, source evidence and other conflict records; derive citations, rerun conflict validation and total reconciliation. A genuine conflict remains unresolved and blocking. |
| R8 — Spec field/provenance/record | Replace independently invalid business text, meaningful provenance selection or exact-copy selection. Replace a record only for a record-level kind/content defect or genuine within-record coupling. Delete only a proven redundant record. | Unit kind, retained-claim eligibility, canonical citations, passive/exact-copy choices, sibling contents and downstream obligations; rerun originating check, full unit, IDs/coverage and required-authority gates before publication. Shared provenance used by several fields is one target only if every dependent field remains valid. |
| R9 — Missing spec content/coverage | Insert one engine-identified missing record for an established obligation, or replace the exact existing field/selection that failed preservation. Never edit coverage output directly. | Structural requirement, current validated source support, candidate membership and existing coverage; validate content/provenance, assign IDs under the existing ledger, rebuild coverage and required-authority reconciliation, then full candidate. A mandatory family is not evidence for an invented requirement. |
| R10 — Review candidate | Replace one finding's faulty field or inseparable finding; insert one missing finding keyed by engine requirement identity; delete only a mechanically redundant extra finding. | Exact requirement ledger, review phase, candidate/source snapshot, allowed evidence and registered applicability policy; revalidate complete finding cardinality/joins and rerun shared reconciliation. Candidate generation is a separate authorization, never a review repair side effect. |

Identity and ordering are preconditions, not model discretion. Existing run-local
indices are usable only when bound to the exact candidate revision; no new global
ID service is needed. Canonical IDs are assigned by their existing owners after
validation. When a change invalidates a derived value, rebuild it from its
canonical producer before any consumer uses it. Do not edit an append-only
summary history or an accepted snapshot to repair a later proposal.

Each merge runs the producing validator, then its declared dependencies. Other
already-rejected units may remain as separate diagnostics while a candidate is
held in memory, but a repair cannot silently ignore its own still-failing check,
create new unhandled dependency failures, or publish partial success. When no
local rejection remains, full-candidate validation is mandatory. Retry exhaustion
does not permit a larger write or weaker check.

### Cardinality and competing entries

Missing members use insert only when the engine can identify the required member
and ordering without inventing semantics. Extra/duplicate members are not all
equivalent: identical normalized text alone does not establish identical evidence,
obligations or disposition. Mechanical deletion requires equivalence under the
existing owning contract and preservation of all required coverage. Stable
ordering may choose which *equivalent* occurrence to remove; it cannot choose the
meaning of competing entries.

**G1 — Unsafe target or semantic survivor decision:** if competing non-equivalent
claims, summary statements or dispositions need a survivor decision, first require
a bounded candidate decision over the engine-supplied alternatives and validate
its evidence and coverage. Genuine non-equivalent authoritative resolutions use
§12.8 clarification, never majority/first/last selection. Where no existing
registered decision contract proves a safe choice and subsequent single-record
write order, this target remains blocked. Record the exact missing decision;
do not invent a selection service or authorize the whole collection/graph.
Likewise, a graph correction requiring inseparable writes to two different
records is gated under §22.1 rather than smuggled into `replace_group`.

G1 is an explicit rejection policy for those targets, not an open choice for an
implementer. Independently repairable cases in R1–R10 can proceed. A concrete
G1 case that must recover to meet a later chunk's acceptance requires the smallest
additional approved contract decision before that chunk can be called complete.

## 4. Final model-facing choices

These choices remove duplicated facts while retaining semantic selections and
canonical provenance. They are settled for this rollout, with A1–A3 approved and
applied to the design. Phase 2 implements the selection and disposition boundaries below; delivery
evidence is recorded in [the rollout](TODO_FIX_001.md#phase-2-delivery-and-verification--13-september-2026).
Richer support findings and routing remain with 13–14.

| Choice | Model proposes | Engine constructs / retains | Implementation gate |
| --- | --- | --- | --- |
| Summary membership | Statement grouping, content and selected claim IDs; retain the current statement-key contract for this scope. | `member_claim_ids` from the exact partition; `member_summary_ids` from validated child summaries. Store both in canonical summaries and validate complete lineage. | 06 complete; no new design amendment required. |
| Citation unions | Meaningful selected claim IDs and, where the existing lifecycle authorizes them, resolved clarification-response IDs. | One shared stable unique union: traverse validated selected claims in their supplied order, traverse each canonical claim's citations in order, retain first occurrence of each citation ID. Retain exact canonical quotations and all persisted provenance. | 05–06 complete under approved A3. |
| Dispositions | One claim selection plus a supported nested tagged relationship decision. | The canonical disposition enum and its related-claim list are derived from that checked decision. Cardinality/self/kind/reciprocity/cycle validation still owns acceptance. | 07 complete with schema/native conformance. |
| Support provenance | Selected evidence and a concise inspectable finding, including the missing datum or preservation defect for a negative judgment. | Validated requirement/finding association and derived citation union. Absence may have no evidence selection; it never receives fabricated citations. | Selection boundary complete in 06; richer findings and routing remain 13–14. |

Use separate raw proposal and canonical types at the existing trust boundary;
do not strip citation fields from a canonical state type to simplify a prompt.
The shared union constructor validates neither stage eligibility nor semantic
entailment on its own. Reconciliation and specification still apply their own
existing eligibility rules before construction. Reordered valid selections do
not acquire a new set-sorting requirement; canonical rendering follows the
defined selection order. Invalid/foreign/duplicate claim selections reject before
construction rather than being silently deduplicated.

The final disposition proposal uses `claim_id` and a nested `disposition` object
with the existing required `kind` codec:

| Nested `kind` | Payload | Canonical relationship |
| --- | --- | --- |
| `retained` | Empty struct, with no relationship payload. | Empty related-claim list. |
| `duplicate` | One `target_claim_id`. | Exactly that one related claim. |
| `superseded` | Nonempty `related_claim_ids`. | The selected related claims. |
| `conflicting` | Nonempty `related_claim_ids`. | The selected conflicting claims, subject to reciprocal coverage. |

These are structural contract descriptions, not example responses with invented
IDs. `retained` uses an empty struct, not `void`; nested alternatives keep `kind`
even when the selected root response omits its redundant tag. Use the existing
closed `oneOf` profile and native codec. Do not introduce arbitrary discriminators,
conditional-schema keywords or aliases. Remove the old enum-plus-always-present
relationship proposal in chunk 07; retain the canonical representation and its
validators. The live improvement from tagging is still unmeasured.

Exact source-line/occurrence choices in extraction, selected claim IDs, passive
literal IDs, token IDs and exact-copy citation selections are meaningful evidence
choices and remain. The union rule removes only determined aggregate citation
lists from reconciliation signals/conflicts and model-facing specification/support
provenance, including repair responses. It does not remove every `citation_id`
field in the application or add clarification-answer support before H-011 exists.

Shape is specified once in the compiled schema. Relationship rules remain in the
owning native contract; typed rule facts feed concise initial/repair guidance and
diagnostics. YAML references resources and routes typed outcomes. Prompts do not
repeat schemas, membership inventories or a second implementation of those rules.

## 5. Design amendment decisions

On 13 September 2026 the user explicitly instructed: “approve A1 and A2, update
docs”, then “A3 is approved, update docs”. A1–A3 are applied to `design/design.md`;
the corresponding runtime changes are implemented in Phases 1–2. No invariant,
accepted ADR, retry limit, native projection, JSON strictness or §17.5 canonical
union changes. The links below identify the sole governing wording for approved
amendments.

### A1 — Design §12.5, example bullet

**Approved and applied:** [design §12.5](../design/design.md#125-low-capability-model-operating-rules)
now requires complete compiled-schema guidance without synthetic candidate examples.

Reason: schema-valid placeholder values cannot establish domain-valid
relationships. The complete schema already carries fields and alternatives.
**Gate:** approval cleared for chunk 01's example removal.

### A2 — Design §22.6, shape-example bullet

**Approved and applied:** [design §22.6](../design/design.md#226-unparseable-output)
now requires precise expected-schema guidance for schema rejection and reuses the
original complete schema for syntax correction, without synthesized candidate values.

The existing original-assignment/schema/evidence, exact rejected bytes, decoder
locations, no semantic reconsideration, local accounting and latest-rejection-only
requirements remain. **Gate:** approval cleared for chunk 01; T01 must cover
both scopes and syntax.

### A3 — Design §17.3, provenance-selection sentences

**Approved and applied:** [design §17.3](../design/design.md#173-llm-work)
now makes claim/authorized-answer selection model-facing and citation-union
construction engine-owned, preserving meaningful exact-copy and source selections.

All other §17.3 text remains, including semantic-review limits and no-invention.
§17.5 remains unchanged. This permits removing aggregate model provenance fields;
it does not implement authenticated answer ingestion. **Gate:** approval cleared
for chunk 06's specification/support response change. Chunk 05 still preserves
current proposal shapes until chunk 06 changes all producers and consumers together.

## 6. Shared source support and candidate defects

The distinction is about which fact is invalid, not whether a finding was made
before or after generation. Apply it to deterministic producers and model-assisted
review through the shared authority boundary, not a Specify-only continuation flag.

| Established facts | Required treatment |
| --- | --- |
| Current validated authority supports the exact required datum; the candidate omits it or fails its authorized mechanical representation. | Candidate defect. Retain the exact requirement, supported source/evidence binding and faulty/missing target; authorize R8/R9 only where independently safe. Regenerate affected validation and reconciliation before success. |
| Source detail is missing, ambiguous, conflicting, stale or unsupported. | Genuine authority gap. Preserve the shared closed outcome, earliest owner and requirement identity. No ordinary repair may invent a value or choose among conflicting authorities. |
| The review record has a bad ordinal, missing required finding detail, invalid evidence selection, duplicate entry or invalid applicability disposition. | Review candidate defect R10. Repair its structure/evidence only; a valid substantive negative finding remains negative. |
| Canonical context, policy binding or retained execution association is broken. | Operational/context rejection. A semantic call cannot fix the engine's input authority. |

“Established support” is not a positive model Boolean, the mere existence of a
reference file, or a missing mandatory family. It requires the current exact
requirement/source binding, mechanically valid evidence joins and any applicable
semantic judgment, explicitly labelled model-assisted. A stale pre-generation
review cannot authorize a later candidate or a different field. An unsupported
assertion retains §22.2's one-use transition to `clarification_needed`; this
distinction does not create a general rewrite-until-supported escape hatch.

For `ForcedGap`, keep the engine-observed missing-content fact blocking regardless
of reviewer verdict. Chunk 14 must carry missing **candidate** content separately
from genuine missing **source** authority through the shared classification. The
candidate defect clears only after the exact obligation is satisfied and the
rebuilt complete ledger validates. Never delete a forced gap because review says
`supported`, or treat every post-generation negative as candidate omission.
No additional exception to §§12.8/22.2 is selected here.

A genuine gap becomes existing `clarification_refresh.Needs` using its structural
requirement, current authority, earliest owner, stable subject/slot and actionable
question. Multiple gaps retain separate subjects and deduplicate through the same
lifecycle. Do not forge a generation `clarification_needed` response to call its
specialized builder. Preserve closed forms, answer applicability and upstream
invalidation. Clarification publication still ends `needs_user`, not a completed
specification.

**G2 — Authenticated new answers:** [H-011](../design/harness/02-spec-workflow.md#h-011--complete-specification-clarification-handling)
has no selected trusted authentication mechanism for accepting a newly edited
answer. This review does not choose one. Form validation/protection may proceed;
answer acceptance and use as new generation authority remain gated. An
authority-complete baseline does not require inventing a user-answer provider;
a run needing an answer must report its unmet acceptance criteria.

## 7. Diagnostics, persistence and logging contract

The validator owns the diagnostic once: stable rule/cause, affected typed unit
and member, rejected value or missing obligation, admissible choices/constraints,
candidate revision, current authority/dependency binding and producing origin.
Multi-member failures retain enough member identities to explain missing, extra
and duplicate coverage. Application bindings retain the result; authorization
verifies its binding without repeating domain validation to rediscover the error.

In chunks 02–04 and 13, carry that evidence through collection, request release,
repair and terminal report. A replacement records its actual producing call even
if its bytes equal the previous value; unchanged siblings retain their origins.
Every event distinguishes the **current provider exchange** from the **candidate
being diagnosed**. Token usage belongs to its exchange. A later non-model failure
retains its terminal step/cause without attributing it to the last model call.

Use the existing logging/report path. No extra raw-prompt copy, catch-all error
message or new logging subsystem is needed. Harness evidence should distinguish
not requested, no response received, response retained but no extracted candidate
available, and evidence-write failure. Transport details must report only observed
phase/cause/status facts; existing generic failures do not justify guessing DNS,
TLS, credentials or sandbox causes. Chunk 16 owns this independent improvement.
For a budget stop after a received response, preserve available accounted usage
and the raw-response link even when extracted text is unavailable. Keep the last
observed protocol rejection and its origin separate from a later exchange and
terminal rejection; an unvalidated final response receives no invented JSON or
domain verdict. R12 makes these existing observation obligations concrete in
chunks 16/18. Use the native observation/accounting and existing rejection
retention owner, not report-side revalidation or a second history service.

Native diagnostic detail and explicitly permitted harness capture are distinct
from production metadata. [Design §26.5](../design/design.md#265-secrets-and-logging)
allows only registered IDs/enums/counts/codes and related metadata in events;
actual/expected content and arbitrary explanations must not leak there. Body
logging retains its direction/class opt-ins, redaction and sink protections.

[Origin](../src/domain/model_candidate_origin.zig) is an execution-local ledger
coordinate, never persisted provenance or a cross-run authority ID.
[Specification state](../src/domain/specification_state.zig) currently persists
`review.evidence`; chunk 13 must explicitly separate durable semantic evidence
from transient call correlation. Canonical evidence must retain the finding and
source/requirement joins needed to inspect and validate it after restart without
the request ledger. Update [state construction](../src/actions/specification/build_specification_state.zig),
[parsing](../src/actions/specification/parse_specification_state.zig),
[output preparation](../src/actions/specification/prepare_specification_output.zig)
and [publication](../src/application/specification_publication_workflow.zig) together.
Do not persist raw prompts or add a continuation snapshot to preserve diagnostics.

## 8. Acceptance matrix for implementation

These are required future regression cases, not executed tests. Each row includes
an accepted and rejected case and maps back to a boundary above. Test steps exist
in [build.zig](../build.zig); use the full invocation documented in
[the rollout](TODO_FIX_001.md#validation-commands-and-evidence). Domain tests must
also prove registered transitions and runner invalidations, not merely exercise
an authorizer directly. Repeat shared classes with unrelated source content and
at least two registered requirement kinds; the Hello World example is insufficient.

| Case / boundary | Accepted case | Rejected case | Owning offline checks |
| --- | --- | --- | --- |
| T01 / B01 | Independent valid fixtures cover every selected result and nested variant, exact integers `7`, `7.0`, `70e-1`, whitespace/order, and precise parent/value schema diagnostics without examples. | Duplicate keys, malformed JSON, fences, missing/mixed/unknown variant fields, fractional/out-of-range integers and foreign request/schema association reject; local/global exhaustion cannot reset. | `test-model-candidate-json`, `test-model-payload-schema`, `test-model-result-schema`, `test-model-request-workflow`, `test-model-attempt-accounting` |
| T02 / B02 | Correct one localized invalid text field with allowed passive/source references; preserve other claims and citations. | Same apparent text error under stale grammar/source binding never calls repair; out-of-scope edits and missing semantic authority cannot pass. | `test-reference-extraction`, `test-typed-text`, `test-structured-tokens` |
| T03 / B03 | Coupled classification replacement supplies every scoped candidate once after missing/duplicate/unknown decisions. | Foreign candidate, forbidden preservation, duplicated non-equivalent choice or corrupted engine-blocked entry remains rejected; no first/last collapse. | `test-reference-extraction`, `test-structured-tokens` |
| T04 / B04 | Repair one bad occurrence and an empty selection list from captured line choices; quotations exactly match capture. | Foreign line, ambiguous occurrence, absent source, empty support and stale revision reject; model-authored quotation is not authority. | `test-reference-extraction`, `test-reference-evidence` |
| T05 / B05 | Candidate selection rejection survives claim construction and returns to its precise source target with correct origin. | Corrupt derived token citation or chunk/state/count binding fails without semantic repair or invented identities; final accounting stays exhaustive. | `test-reference-extraction`, `test-reference-evidence`, `test` |
| T06 / B06 | Correct one statement and insert one uncovered claim's statement before append; canonical membership and sibling IDs/order remain intact. | Duplicate key, overlapping non-equivalent claims, missing coverage after deletion and corrupt history reject; a failed summary is never appended. | `test-reference-reconciliation`, `test-reference-model-input` |
| T07 / B07 | Tagged retained has no payload; duplicate selects one non-self compatible target. A missing claim gets exactly one disposition; one safe graph-edge correction revalidates dependent records. | Extra legacy field, self-link, wrong kind, cycle, asymmetric conflict, repeated disposition and unsafe cross-record repair reject. Both exact redundancy and competing duplicates exercise deletion/G1 behavior. | `test-model-candidate-json`, `test-reference-reconciliation` |
| T08 / B08 | Insert missing retained-claim signal and preserved-token projection; derive exact union once, preserving valid overlapping distinct claim sets. | Empty required coverage, duplicate member set, conflicting-claim selection, lost token coverage after deletion or foreign evidence rejects. | `test-reference-reconciliation`, `test-reference-model-input` |
| T09 / B09 | Repair one conflict representation or add its missing pair coverage; a valid unresolved conflict remains blocked with actionable owner-correct need. | Orphan/duplicate conflict, omitted relationship pair, fake resolution and deletion of a genuine conflict cannot become success. | `test-reference-reconciliation`, `test-required-authority`, `test-clarification-inputs` |
| T10 / B10 | Correct one record field/kind while preserving valid siblings; retain the native rule and origin through collection/release. | Whole-record replacement for an independent field, invented unsupported content, unrelated edits and byte-equal still-invalid repairs do not pass validation. | `test-specification-generation`, `test-specification-contract` |
| T11 / B11 | Selected eligible claims yield the canonical stable unique union; provenance-only repair leaves independently valid business text unchanged. | Unknown/duplicate/non-retained claim, foreign context, wrong exact-copy citation and invented answer provenance reject; union construction cannot conceal bad selections. | `test-specification-generation`, `test-reference-model-input`, `test-model-candidate-json` |
| T12 / B12 | Insert one supported missing requirement or fix one exact-copy selection; rebuild IDs, coverage and authority from the repaired candidate. | Lost coverage after deletion, open question converted into business content, context-only downgrade or direct coverage-ledger edit cannot pass. | `test-specification-generation`, `test-required-authority` |
| T13 / B13 | Fix a malformed/missing finding for one exact requirement; retained reason, evidence and transient origin identify its actual call. Durable evidence remains interpretable after request release/restart. | Duplicate/foreign finding, invalid evidence, unsupported applicability, persisted ledger-coordinate authority and retrying a valid negative solely to change its verdict reject. | `test-specification-generation`, `test-required-authority`, `test-specification-contract`, `test` |
| T14 / B14 | Established-source omission uses bounded candidate repair, then full reconciliation; genuine same-stage gap publishes a stable need and downstream detection requests earliest-owner rework. | Positive reviewer cannot bless missing AC/FR content or clear a forced gap. Missing/ambiguous/conflicting/stale source never enters ordinary repair; unknown ownership and unauthenticated new answer stay blocked. | `test-required-authority`, `test-specification-generation`, `test-clarification-inputs` |
| T15 / B15 | Replace, insert and authorized delete satisfy exact preconditions, update only written origins and rerun dependent/full validation; an unchanged replacement remains attributed to its actual call. | Wrong owner/purpose, stale revision/old value/read dependency, occupied insertion key, changed anchor, undeclared target/group member and lost coverage reject without mutation or semantic retry. | Consumer steps `test-reference-extraction`, `test-reference-reconciliation`, `test-specification-generation`; integration `test` |
| T16 / B16 | Successful publication passes exact-byte identity and those published bytes receive a scored rubric evaluation. Offline fault fixtures preserve distinct execution/evaluation/quality status. | Each output-write failure, absent/mismatched artifact, evidence-write failure, incomplete evaluation or stale prior output prevents baseline success; a low score is not falsely labelled a quality pass. | `test-e2e-harness`, `test-rubric-evaluator`, `test`; live evidence only in separately approved chunk 19 |

Every new repair consumer must prove revision/read-fact invalidation, immutable
siblings, allocation-failure cleanup, retry exhaustion and full revalidation.
No unused insert/delete/group API lands ahead of a tested consumer. Published
schemas, native types, model projection and stored provenance receive independent
accepted/rejected fixtures; examples produced by the code under test cannot be
their sole conformance oracle.

## 9. Review result, cleanup and approval gates

The boundary matrix covers every chunk-00 boundary with a later chunk and both
accepted/rejected cases. The target matrix covers replacement, missing entries,
extras, duplicates, dependency facts and validation order. Unsafe target scope is
explicitly gated, not left to a local fallback. Source authority, model judgment,
execution context and observations remain separate.

| Gate | Status | Dependent work |
| --- | --- | --- |
| A1–A2 | Explicitly approved on 13 September 2026 and applied to design §§12.5/22.6. | Chunk 01, including R12's prompt-cleanup and correction-coverage follow-up, implemented and verified offline; see the follow-up completion record. |
| A3 | Explicitly approved on 13 September 2026 and applied to design §17.3. | Chunk 06 implements the model-facing spec/support selection boundary and canonical evidence reconstruction under this approval. |
| G1 | Fail-closed target policy selected; no cross-record exception approved. | Only a concrete repair requiring an unestablished semantic survivor or inseparable multi-record write. |
| G2 | Authentication mechanism still unselected under H-011. | Acceptance of new edited answers, not read-only form protection or an authority-complete baseline. |

Phase 0's contract review and required amendment approvals are complete. G1 and
G2 remain explicit gates for the affected later work; no exception or authentication
mechanism was approved. Chunks 01–04, including the R12 follow-up, are implemented
and verified offline. Phase 2 (05–07) is implemented and verified
offline; the rollout records 120/120 verification steps and 1,374/1,374 tests.
Chunks 08–21 remain pending. The retained live run failed before
schema-valid IR existed for the failing cross-source summary, so the existing
§22.6 protocol boundary owns that rejection. If an intended fix exceeds
the approved governing wording, obtain the specific missing decision rather than
broadening this document into new authority.

Remove superseded runtime code with its owning implementation chunk: synthetic
example generation/tests (01), authorizer rule rediscovery (04), model membership
and union echoes (06), old disposition proposal format (07), and replaced failure
or clarification routes (12–15). Retain independent regression coverage and
historical run evidence. Phase 0 has no legacy runtime path to remove because it
introduces no replacement runtime path.

Documentation checks for this delivery are recorded in chunk 00 of the rollout.
No engine tests, live E2E calls or rubric evaluation were run for this review.
