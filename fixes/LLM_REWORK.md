# LLM_REWORK — Derive mechanical facts; ask models for semantic choices

**Date:** 25 September 2026. **Status:** Feasibility assessment and proposed rollout.
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

**Recommendation:** first design one shared post-extraction reference-selection
contract using existing preserved-token claim IDs. Remove redundant model-authored
relationships through canonical construction, rather than another prompt asking
the model to reconstruct them. Keep counts, assembly and rendering with their
existing deterministic owners. Do not create a reference registry, fixer agent,
second evidence store, retry policy or generic execution layer.

Core lookup feasibility is high. The complete change is cross-cutting: provenance
roles, repair scope and canonical readback must be settled before implementation.
It cannot honestly be described as a one-field rename or a guarantee of good prose.

## 2. Evidence: the latest failure

Reviewed execution:
[`2026-09-25T08-21-44Z-b16638b5493910a4b1d29436213dcde9`](../zig-out/e2e-spec/2026-09-25T08-21-44Z-b16638b5493910a4b1d29436213dcde9/report.md).
Its executed source fingerprint matches the preceding approved §36 run documented
in [FIX_002](FIX_002.md#36-preserve-field-purpose-through-repair-and-recover-misbound-exact-content).

| Boundary | Observed evidence |
| --- | --- |
| Source/extraction | Start successfully, display the exact greeting, and optionally output UTC date/time all reached generation. Claim 1 carries business prose; claim 2 is the preserved greeting occurrence. |
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
| Citation union | [reference_support.select](../src/domain/reference_support.zig), [specification_provenance](../src/domain/specification_provenance.zig) | Already derived as a stable unique union of selected claims. Extend this boundary; do not duplicate it. |
| Summary statement `local_key` | [reconciliation validation](../src/domain/reference_reconciliation_validation.zig), schema and key repair | Model-generated uniqueness/order bookkeeping remains. Separate candidate for removal after defining ordering semantics. |
| Preserved-token reconciliation content | [reconciliation validation](../src/domain/reference_reconciliation_validation.zig), [repair](../src/domain/reference_reconciliation_repair.zig) | The sole selected preserved-token claim determines its token. Audit/removal of the repeated token field is feasible separately. |
| Review assignment ordinals | [specification_support](../src/domain/specification_support.zig) | Single-target repair already binds its assignment natively. Batch findings still need unambiguous association; do not bind unchecked array positions. |
| FR/AC IDs and numbering | [specification_identity](../src/domain/specification_identity.zig) | Already deterministic. The number of meaningful requirements is a semantic question, not an array-count calculation. |
| Coverage membership/counts | [specification_coverage](../src/domain/specification_coverage.zig) | Already computed. Counting a cited claim is not proving its meaning survived. |
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

## 5. Proposed exact-reference contract

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
the reverse lookup while authorizing §36 repair. The new contract should resolve
the selected claim directly through existing reference/provenance ownership; do
not retain a redundant reverse-lookup path solely for the removed model format.

The model still writes prose and selects evidence for its semantic assertions.
Exact-value dependency membership comes from the explicit exact-value selection,
not from guessing what a prose string might mean. Equal strings in two files remain
different occurrences. Never resolve by literal text or by the first matching value.

### 5.2 Derive lineage without manufacturing support

Conceptually, a field/record has:

- model-selected evidence for its content;
- exact source dependencies implied by its typed exact-value selections;
- a native, stable union used for canonical lineage and citation accounting.

These are roles in one existing evidence path, not three independently mutable
registries. Native expansion must be deterministic and idempotent; repeated use of
one reference does not multiply citation entries. Do not deduplicate text segments:
repeating a value in two parts of a sentence can be intentional.

The proposal must explicitly settle how those roles survive canonicalization:

1. Deriving an exact-value dependency must not declare the surrounding prose
   semantically supported. Existing review still assesses source entailment.
2. Removing/replacing a reference must recompute its derived dependencies. Blindly
   unioning new claims into the old provenance leaves obsolete support behind.
3. Some content legitimately describes only an exact value. Do not impose a new
   blanket “every field must cite a prose claim” rule merely to fix this fixture.
4. If current canonical data can reconstruct the required distinctions uniquely,
   reuse it. If it cannot, make the smallest explicit canonical-contract amendment;
   do not add a hidden side table or infer which old claims were model-selected.

### 5.3 Eligibility and scope are required decisions

Selection must resolve uniquely in the current immutable reference state, be of
the required preserved-token kind, and be permitted for the request and authorized
repair unit. Unknown, foreign, stale, ineligible or conflicting evidence rejects.
Use the owning purpose's eligibility policy; positive content and diagnostic
loss findings do not have identical evidence permissions.

There is a material interaction with passive references: current
`reference_support.select` derives source scopes from selected claims, and
`specification_provenance.resolvedChoices` uses those scopes to offer passive IDs.
Adding an exact dependency can therefore change other available references.
**Do not silently broaden unrelated passive-reference choices.** The amendment
must define whether those choices use explicit content-support scopes or the
complete derived lineage. Prefer preserving the existing authorized choice scope;
if that requires retaining an evidence-role distinction, resolve it before coding.

### 5.4 This is construction under a new contract, not silent repair

The current malformed tuple must not be accepted and silently patched. The new
model contract removes redundant fields, validates one selection, then constructs
canonical data according to an explicit rule. Reject superseded model formats;
do not add compatibility readers, guessing, or an optional fallback to old tuples.

Canonical token/citation pairs may remain useful internally. The current
[Values(boundary)](../src/domain/specification.zig) distinguishes model and canonical
evidence but shares the same business-text type. A wire-only rename is insufficient:
the model-selection type and canonical exact-reference type need an explicit,
typed conversion at the existing evidence boundary. Keep generic JSON decoding
free of hidden reference lookup or workflow-dependent transformations.

## 6. End-to-end integration and feasibility

| Stage | Required treatment | Feasibility / failure to avoid |
| --- | --- | --- |
| Capture and extraction | Keep native spans, token candidates, classification and subsequent identity assignment. | Claim IDs do not exist yet. Do not force the proposed post-ledger ID into extraction or introduce a phase-dependent fallback. |
| Reconciliation | Preserve semantic dispositions/grouping and native identity/coverage checks. Consider redundant preserved-token fields as a separate follow-up. | Extraction/reconciliation business prose currently excludes exact-copy segments. Do not accidentally enable them by changing a shared type. |
| Request preparation | Project allowed occurrences and source meaning from current reference authority. Select the workflow's canonical schema through existing owners. | Avoid a new schema registry, copied per-caller lookup maps or loss of source context when shrinking response metadata. |
| Model decode and native admission | Parse closed proposed shape; resolve exact selections; construct derived evidence; validate text, membership and full unit. | Arbitrary IDs still reject. Native failures remain typed failures; no malformed-data-to-clarification conversion. |
| Brief/story/entities/records | Apply the same contract to every attributed value, all record fields and admitted clarification questions using that representation. | Do not fix only primary-story generation. Shared-provenance records need a complete group dependency union. |
| Native repair | Existing atomic owner binds old value, revision, scope and dependencies. A fixed-evidence text repair may select only references allowed by its fixed authority. | Deterministic derivation must not expand a value-only repair into new evidence authority. Adding external evidence still requires an authorized coupled target. |
| Protocol correction | Same selected response schema and existing lifecycle/accounting; retain the original assignment. | No additional retry engine or generic fixer. Native reference defects and JSON/schema defects remain distinct. |
| Coverage/omission repair | Reuse canonical coverage calculation and existing authorized repair/renewal paths. Project selected canonical current values into the correct new model shape where a model response is requested. | These packets currently read canonical completed data. Showing old pair-shaped values with a new claim-shaped schema would recreate conflicting guidance. Do not add a whole-specification native-to-JSON reassembly API. |
| Assembly and downstream invalidation | Retain deterministic assembly and runner-owned invalidation; recompute affected dependency closure and run full validation. | Completed parts cannot be reused after their reference/policy dependencies become stale. |
| Semantic/principle review | Inspect resulting content against original evidence; distinguish literal lineage from semantic support. | A greeting-only story can become mechanically consistent and still be a bad story. More passing joins is not a quality result. |
| Rendering/publication | Expand exact bytes and render through existing owners only after required gates. | Reference objects inside strings remain prose, not hidden selections. Do not parse JSON-looking prose into evidence or ban it by a fixture-specific pattern. |
| Persisted readback | Recompute expected relationships from the captured snapshot and compare with stored canonical data. Validate reviews and coverage again. | Reject tampered or stale evidence. Never repair stored canonical data during readback and thereby erase evidence of corruption. |
| Plan/tasks gates | Continue reading only validated predecessor authority; preserve open-clarification gates. | Shared policy should be reusable, but complete production Plan/Tasks model integration is not established by this audit. Do not claim unimplemented consumers are verified. |

Relevant existing readback owners are
[specification_state](../src/domain/specification_state.zig),
[incomplete_specification](../src/domain/incomplete_specification.zig),
[reference_snapshot](../src/domain/reference_snapshot.zig) and
[specification_support_evidence](../src/domain/specification_support_evidence.zig).
Persisted canonical format need not change merely because model syntax changes.
If evidence-role semantics require a format change, update its explicit contract
and reject old versions; no dual readers or migration subsystem.

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
diagnostics; clearer unit/property tests; identical rules across affected consumers.
Request/token/latency improvements are hypotheses until measured on comparable runs.

**Costs:** a coordinated model-boundary change, typed conversion, repair/readback
work and replacement regressions. Removing redundant metadata can reduce useful
context if requests are also over-trimmed. Keep original source meaning available.

| Risk | Required control |
| --- | --- |
| Citation laundering | Derive only dependencies of explicit allowed references; keep source entailment in semantic review. Never cite all claims by default. |
| Coverage appears complete while meaning is lost | Retain meaningful-story/FR/AC and obligation checks in semantic assessment and live rubric evaluation. Include deliberately poor but well-linked candidates in tests. |
| Identical literal selects wrong source | Use existing occurrence identity and captured source scope, not value equality. |
| New reference changes unrelated permissions | Decide evidence roles and passive-choice scope explicitly; inert text never grants operational capability. |
| Replacing/removing content leaves stale derived claims | Recompute from the complete authorized unit; do not append to old derived unions. |
| Retry scope silently widens | Fixed-evidence repairs remain fixed; altered evidence requires its existing authorized group. Preserve stable identity and bounds. |
| Two authorities disagree | One reference ledger and resolver; schemas/packets are projections. No parallel mapping cache or side store. |
| Readback conceals corruption | Recompute for comparison and reject mismatch, rather than normalize corrupt persisted data into validity. |
| Pre-/post-extraction identities are confused | Keep token-candidate classification separate from later claim selection. No runtime guessing between formats. |
| Simpler schema is mistaken for a solved workflow | Require downstream semantic assessment, publication/readback and rubric evidence. Safe failure is containment, not completion. |

## 9. Decisions required before implementation

The user's request authorizes this assessment only. Prior §36 approval authorized
bounded coupled repair, not native construction of new provenance under a changed
model contract. The following focused decisions are still proposed:

1. **Model reference shape:** accept one existing preserved-token claim occurrence
   selection and remove redundant token/citation fields from affected model responses.
   Preserve pre-ledger extraction identities and canonical literal precision.
2. **Evidence derivation and scope:** define derived exact dependencies versus
   semantic content-support selections, replacement/removal behavior, passive-choice
   scope and canonical reconstruction/readback. No semantic inference or automatic
   arbitrary citation insertion is authorized.
3. **Repair conformance:** define how the new model/canonical shapes project through
   fixed and coupled repairs, and retire §36 mechanics whose sole trigger becomes
   unrepresentable. Preserve genuine unknown/ineligible-reference failures and
   unrelated membership, omission and conflict authority.

Governing amendment surfaces: [§7.1](../design/contracts/07-domain-representations.md),
[§12](../design/contracts/12-model-boundary.md),
[§16.3](../design/contracts/16-reference-ingestion.md),
[§17.3](../design/contracts/17-specify.md),
[§22](../design/contracts/22-repair.md), and affected persistence/rendering contracts
in [§§23–24](../design/design.md#23-rendering-and-editability).
In particular §17 currently requires the supporting claim in model-selected
provenance, and §22's approved §36 amendment says the engine adds no citations.
This document does not silently override those rules or accept the overall
Proposed design.

Summary-key removal and batch-review changes need their own bounded decisions;
they are not prerequisites for the first exact-reference change.

## 10. Smallest architecturally complete rollout

1. **Settle the three decisions above and capture conformance cases.** Map every
   existing model/canonical consumer before changing its shape. Establish a concrete
   source-scope and add/remove dependency policy, not a prompt-only interpretation.
2. **Implement one native reference-expansion boundary.** Reuse current ledger,
   evidence and typed-text owners. Prove the mechanical transformation with unit
   and property tests before connecting it to workflow execution.
3. **Change all affected producers/consumers together.** Initial content, selected
   repairs, protocol schemas, current-value projections, canonical validation,
   coverage and readback must agree. Keep workflow orchestration through the
   existing runner. Replace prompt wording; do not add a new prompt or agent.
4. **Remove superseded machinery.** Old model tuple schemas, the redundant supporting
   claim requirement and repair cases specific to reconstructing that tuple must
   not survive as alternate supported formats. Preserve validation for unknown
   selections and all still-applicable bounded repair behavior.
5. **Verify and measure offline.** Run relevant registered target tests, full
   `zig build verify`, clean-environment native packaging checks and `git diff --check`.
   Measure actual serialized initial/repair/correction requests and compiled graph;
   do not predict savings from smaller example JSON alone.
6. **Obtain separate approval for controlled model and full E2E tests.** Use captured
   assignments, unchanged sources/schema policy and one variable at a time. Then
   inspect actual requirements, acceptance criteria, principles, publication/readback
   and rubric output. Retain failures and report incomplete evidence; no automatic rerun.

This replaces a redundant representation through one shared contract. It does not
require redesigning reconciliation semantics, adding model calls, changing provider
transport, raising retry allowances or removing validation.

## 11. Acceptance and regression matrix

| Case | Required evidence |
| --- | --- |
| Reported greeting and unrelated business requirements | One selected exact claim resolves the correct literal/citation without model-supplied duplicate IDs; meaningful successful candidates proceed through the existing gates. |
| Old tuple shape | Closed new model schema rejects superseded token/citation fields. No compatibility path. |
| Unknown, wrong-kind, ineligible or stale claim | Typed rejection; no default, citation insertion, publication or clarification conversion. |
| Same literal in different sources | Exact selected occurrence retained; no first-match selection. |
| Repeated exact segment | Deterministic citation set, preserved text order/repetition and idempotent expansion. |
| Reference added, replaced or removed | Correct dependency recomputation for the whole authorized unit; unrelated sibling data and producer origins unchanged. |
| Shared-provenance acceptance record | All fields contribute exact dependencies; Given/When/Then retain separate meaning and unaffected content. |
| Fixed-evidence repair | No newly derived claim or source scope outside authorization; coupled changes require their approved target. |
| Passive references and source scope | Derived exact lineage does not silently widen unrelated choices under the approved policy. Operational path capabilities remain unchanged. |
| Model/canonical projection | Initial and repair requests use one selected schema and show current values in its model shape; canonical persistence uses its declared shape. |
| Sliced response/dependency renewal | Stale completed parts reject; renewed dependencies rebuild all affected validators/reviews before publication. |
| Missing answers, invalid JSON/schema and repeated invalid handles | Existing retry identities, exhaustion, failure precedence and exact usage accounting remain unchanged. Successful unrelated work continues within budget. |
| Canonical state tampering | Foreign/deleted claims, altered token/citation joins and mismatched coverage/review evidence reject on readback; no silent reconstruction into success. |
| Empty/meaningless but correctly linked story or AC | Never counted as semantic recovery merely because joins pass. Scripted review tests routing; approved live rubric tests actual quality. |
| Pre-ledger extraction and reconciliation | Their existing allowed shapes and source selections remain intact; exact-copy business segments are not newly admitted there. |

## 12. Feasibility conclusion

**Proceed with a focused contract proposal, not another local prompt patch.** The
engine has the source occurrence identities and lookup facts needed to eliminate
the repeated-reference mismatch. The hard part is preserving evidence meaning and
repair/readback boundaries, not performing the lookup.

The first implementation should remove one avoidable failure class end to end.
It must not claim deterministic proof of specification quality, silently infer
business evidence, or hide unresolved model errors behind mechanically complete
coverage. Broader bookkeeping simplifications should follow measured evidence,
independently of this first contract.
