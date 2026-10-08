# LLM_REWORK — Derive mechanical facts; ask models for semantic choices

> **Historical record — archived 9 October 2026.** Superseded as an active
> work tracker by [FIX01](../FIX01.md). Dated statuses, proposals and approvals
> apply to their recorded scope; archiving does not establish completion or grant
> new authorization.

**6 October implementation update:** [FIX_003](FIX_003.md#12-implementation-record)
and [ADR 0022](../../design/decisions/0022-native-reference-phase-handoffs.md) replace
global JSON composition with validated native phase handoffs, role/group handles,
native token projection and forced classifications. Earlier measurements below
remain historical evidence; the new implementation has no live reliability or
rubric result yet.

**Reviewed:** 27 September 2026 against the current worktree. **Status:** Phases 0–3 and the Phase 4.1 diagnostic batch complete. §6.9 C0, C1's bounded presence conformance, C2a and C2b are implemented offline; §15.7 records the coordinated provenance-free C2c cutover and its verification status. The remaining architecture-wide deterministic-field audit, C3 and live Phase 4.2/C4 outcome gates remain open. §14 reviews feasibility; §15 defines the expanded mandatory scope and completion evidence.
**Current scope — user direction, 27 September:** move **all deterministic work**
out of model responsibility across the architecture. This includes every current
model response, registered operation, initial/repair/correction path and evaluator,
plus the ownership contracts for Plan, Tasks, Implement and unrelated workflows.
§15 defines the required completion gate; provenance is the first implementation,
not the scope limit. Determined fields must be constructed in code, not left in
responses merely because schemas or validators can check them.
**Historical delivery:** Phase 0 baseline tests, approved [ADR 0020](../../design/decisions/0020-derived-exact-reference-lineage.md),
Phase 1's reference-owner refactor, Phase 2's coordinated format cutover,
Phase 3's offline integration/measurements and Phase 4's approved live measurements
are recorded below. Those completed scopes do not complete the broader mandate.
Phase 2 closes the identified owning-unit, request-choice and allocation gaps;
§10 records the checks. The latest retained workflow run still failed. Phase 4.1's
eight approved diagnostic calls, Phase 4.2's approved E2E run and the subsequent
user-run execution are recorded in §10. Publication/readback and rubric grading
remain unproven; Phase 4 is not complete.
**Current follow-up:** option 2's shared eligible-ID restriction is implemented
and observed in the latest production requests (§6.7). The `07-08-12Z` run reached
coverage and source review, then exhausted the token budget while repairing an
empty principle review. The broader review in §6.9 identifies related schema/native
conformance gaps across extraction, reconciliation, generation, review, repair and
grading. Its inventory defines the audit scope, not one implementation bundle.
**Revised direction:** the LLM handles semantic work only. Code constructs every
fact uniquely determined by validated inputs, accepted semantic selections and
native rules, and performs every mechanically decidable check. Checking a
model-returned computed fact does not count as transferring its construction.
Use focused semantic assignments with compact reusable response schemas; bind identity, retain results
and assemble complete collections through existing native and runner owners.
The expanded batch-slot proposal is superseded. Its measured growth remains in
§6.9 as the reason for rejecting that direction. C0's owning-boundary regression
and C2a's approved amendment are recorded in §6.9. C2b uses one selected finding
per request through the existing runner and native review owners. Live token cost, quality, publication, readback and
scoring remain unproven.
The C2b implementation includes working-review repair, request retirement/identity
and the coordinated prompt/schema cutover. Its offline request-size measurements
do not close aggregate cost, retained-memory or live-quality gates. §14 distinguishes
those evidence gaps from functionality already present.
**Budget direction (reaffirmed 27 September):** token cost may increase when
outcomes improve; cost reduction is not an acceptance gate. Compare preserved source
meaning, useful requirements, defensible review and validated completion alongside
actual usage. The user permits a larger configured finite budget for that work.
The current 100,000-token setting is a measured baseline,
not a permanent design ceiling; finite enforcement and accurate accounting remain.
Its purpose is to contain wasteful execution. Existing bounded retry/progress
checks stop repeated unresolved errors; successful work does not consume an
unrelated defect's allowance. Token spend alone is not a quality/progress signal.
The open-item review in §6.8 records current priorities and decision gaps; historical
Phase 2 findings remain closed unless new conformance evidence reopens them.
**Provenance follow-up (27 September):** §13 separates the completed ADR 0020
mechanics from remaining review bookkeeping, per-requirement source-link rendering
and conditional source-ID capture. It is a change plan, not implementation approval.
**Provenance-free response decision:** §15.4 records the user's requirement
that every model response forbid `provenance`. Semantic evidence grouping is
captured in validated reconciliation assignments before authoring; deterministic
lineage stays in code. The coordinated runtime cutover is in the current
worktree (§15.7); offline verification and live quality are separate gates.
**Selector necessity review:** §15.5 records five required follow-ups. Internal
occurrence identity does not require a model-returned `claim_id`. Remove even a
singleton selector when its value is determined after the model chooses a branch;
construct wholly determined fields without a model response. Existing contracts
and passing tests are not evidence that every current response field is necessary.

## 1. Finding and recommendation

The concept is sound: when validated input and an accepted rule determine one
answer, the engine must construct that answer. Asking the model to reproduce it,
then validating and repairing disagreements, introduces avoidable failure paths.
This already follows [design §4](../../design/design.md#4-deterministic-and-llm-responsibility-boundary).

**Success means transferring responsibility, not just rejecting more answers.**
Apply this distinction at every request and repair boundary:

| What the accepted inputs determine | Engine responsibility | Remaining model responsibility |
| --- | --- | --- |
| One answer: assigned identity, expected subject set/count, a selected exact token's dependencies, canonical IDs, citation unions, assembly or rubric totals | Construct it through the existing owner; omit redundant model-returned fields. Validate associations, freshness and persisted consistency deterministically. | None for the computed fact. |
| Several eligible answers: supporting source claims, a preserved occurrence or a semantic relationship | Compute the permitted set and validate the selection and its consequences. | Select the evidence/relationship that actually supports the intended meaning. Eligibility alone does not determine the right selection. |
| Meaning: business behavior, Given/When/Then, source support or policy compatibility | Supply current evidence, validate mechanically decidable rules and enforce failure/publication boundaries. | Propose or assess meaning. No native auto-filled positive finding or invented user decision. |

Required review subjects and their identities come from the existing native
requirements owner. The engine selects one subject, asks for its assessment and
attaches the result to that exact bound subject. The response contains semantic
content and genuinely chosen evidence; it does not repeat the assigned identity,
expected count, collection position or completion status. Code determines the next
assignment and validates complete membership after collecting the required results.
§6.9 C2a–C2b defines the implemented offline integration; its live quality gate remains open.

For example, the engine binds an assessment to requirement 42. The model returns
its decision, explanation and any evidence whose relevance requires judgment.
Code records the finding under 42, calculates any uniquely determined dependencies,
and retains it while processing the remaining assignments. The engine cannot
manufacture a missing assessment or establish its truth through identity matching.

This rule applies across workflows. It does not require one call for every JSON
field: a coherent semantic assignment may produce several related values or a
list whose contents are not known beforehand. Code still assigns resulting IDs,
counts and authorized structure. Supporting-claim and relationship choices remain
semantic when the supplied facts permit several meanings; never cite everything
or invent an ordering policy merely to remove an ID.

The first implemented opportunity was **reference bookkeeping**; §6.9 records the
remaining responsibility gaps and supporting conformance work.
The pre-cutover exact-copy response repeated a token ID, its citation ID and its
supporting claim in separate places. Native code already knows that relationship.
Where the source occurrence remains genuinely selectable, the model should choose
it once; existing native owners derive its fixed dependencies. Where an assignment
or chosen branch determines the occurrence, code supplies its identity (§15.5).
Business meaning and unresolved supporting-evidence choices remain model-assisted
and subject to review.

**Implemented first contract:** for typed content backed by a validated reference
ledger, use its preserved-token claim ID in both model and canonical exact
segments. Preserve explicit content-support selection once and derive reference
lineage from that selection plus the exact segments. Refactor existing reference
mechanics below Spec's types and policy so other workflow operations can reuse them.
This avoids a second reference syntax and independently stored dependency lists.
Counts, assembly, rendering, retries and publication retain their current owners.
C2a/C2b now implements focused review assignments. Removing reconciliation's
redundant token metadata and summary-key bookkeeping is required work in §7A–B;
summary ordering needs an accepted rule first. Missing decisions remain tracked
completion blockers, not grounds for permanently delegating bookkeeping to the model.
Do not reimplement facts that native owners already compute, or report schema
tightening alone as completing the deterministic rework.

**Across workflows:** any validated workflow may use this contract through registered
operations with declared typed content and reference inputs. It is not a universal
schema or replacement for all evidence IDs. Workflows without such content need no
reference ledger; arbitrary JSON does not acquire reference semantics automatically.
The concrete reuse boundary and proof required are in §6.1–§6.4.

The one-handle format is active and its Phase 2 native conformance checks pass;
live effectiveness is not established. The initial proposal review identified
the following design requirements, now governed by ADR 0020. Offline checks do
not establish that every future workflow consumer or model call satisfies them:

| Finding | Required correction |
| --- | --- |
| Flattened provenance cannot recover which claims were explicit versus derived. | Preserve explicit selection; define one derived effective-provenance view (§5.2). |
| Canonical pairs would require conversions that the atomic repair API does not currently support. | Prefer the same claim handle across text boundaries; do not add conversion infrastructure merely to preserve old pairs (§5.4). |
| Fixed-evidence repair can change authority when a reference is removed. | Pin effective evidence; a change outside that scope requires an authorized coupled target (§5.5). |
| An invalid handle prevents complete effective provenance from being calculated. | Bind candidate repair to independently validated facts; do not require unavailable old provenance or infer authority from the invalid handle (§5.5). |
| Rebuilding repair choices from each rejected replacement can enlarge its allowance. | Retain the original validated repair bound through the existing repair context, separately from the changing candidate/revision (§5.5). |
| New response IDs would still require model-side joins in today's request. | Expose directly claim-addressable choices through the existing evidence projection (§5.1). |
| Review evidence and completed readback consume the existing provenance contract. | Update these consumers together; pending clarification state has a different storage contract (§6). |
| The shared reference helper previously imported Spec types; Spec eligibility is not universal. | Phase 1 removed that dependency; purpose policy stays with consuming domains (§6.1). |
| A claim ordinal is meaningful only in its captured reference namespace. | Bind the namespace natively; preserve other evidence and operational IDs (§6.2–§6.3). |

These are reasons to settle the focused contract before coding, not to add a fixer
agent, reference registry, evidence store or execution framework. The proposal
removes one avoidable failure class; it cannot guarantee meaningful prose.
The rollout in §10 separates an independently testable ownership refactor from
one coordinated format change. Readback and repair are prerequisites to activating
that change, not later hardening work.

## 2. Evidence: the retained failure

Reviewed execution:
[`2026-09-25T08-21-44Z-b16638b5493910a4b1d29436213dcde9`](../../zig-out/e2e-spec/2026-09-25T08-21-44Z-b16638b5493910a4b1d29436213dcde9/report.md).
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

### Phase 0 run — the same reference join fails during brief generation

Execution
[`2026-09-25T21-53-09Z-74d618e36d74294723f5ca72d7a90347`](../../zig-out/e2e-spec/2026-09-25T21-53-09Z-74d618e36d74294723f5ca72d7a90347/report.md)
used clean revision `58b0917` (`Phase 0`). Its captured requests still use the
current token/citation tuple, not ADR 0020's claim-handle contract.

| Boundary | Observed evidence |
| --- | --- |
| Extraction/reconciliation, calls 1–7 | All three source obligations reached generation. Business claim 1 and preserved-token claim 2 remained separate; both were retained and no conflict was reported. |
| Brief, call 8 | The title selected existing token 1/citation 2 but declared only claim 1. Native validation rejected `title.value` with `unknown_exact`: supporting claim 2 was missing from its provenance. The reference itself exists. |
| Coupled repair, call 9 | The authorized replacement could change title content and its claim selection. The model returned the same invalid value and provenance. |
| Coupled repair, call 10 | The model added `Display ` and ` on startup` around the exact reference but still selected only claim 1. `changed:true` recorded a merge, not validation success. Moving the reference from segment 0 to 1 did not resolve the defect. |
| Terminal result | The same native assignment exhausted its two allowed repair executions (one initial attempt plus one retry): `RetryLimitExhausted`. All 10 calls returned final text; all 14,133 tokens were accounted against 100,000. |
| Later gates | Story, records, semantic/principle assessment, publication/readback and rubric grading were not reached. No specification or clarification was published; publication and grading are `not_run`. |

The [first repair request](../../zig-out/e2e-spec/2026-09-25T21-53-09Z-74d618e36d74294723f5ca72d7a90347/evidence/generation/call-000009/request.json)
included source text, both claims, the rejected tuple and an instruction to correct
content and claim selection together. It still required the model to join the token
to its supporting claim. Calls 9 and 10 sent byte-identical 5,107-byte requests;
call 8 was 10,242 bytes. Prompt schema text was 837 and 3,927 bytes respectively
(the compact native `response_format` schema objects were 616 and 3,012 bytes).
These are another failed baseline, not evidence of improvement. Malformed prefixes
were recovered by the existing decoder; no JSON/schema correction exhausted.
Authentication succeeded; missing answers and the global token limit were not the stop.

**Rollout impact:** Phase 1.1 subsequently removed the reference owner's Spec-type
coupling and Phase 2 implemented the coordinated format change. This run confirms the existing
rationale; it does not justify a new repair owner, more retries or a separate
prompt-only detour. Under
ADR 0020, selecting eligible exact claim 2 with explicit support `S=[1]` derives
`L=[1,2]`, removing this redundant join. It does not prove the title is useful or
the eventual specification preserves meaning; those remain semantic checks.

Extend the existing generation regression during Phase 2.3 with this variation:
unchanged replacement → prose changed and reference moved, same unresolved defect
→ exhaustion, plus bounded successful recovery and an unrelated requirement.
Preserve the existing retry identity and accounting: the owning target's validation,
not changed bytes, decides whether repair succeeded. Phase 3.1 must carry that
distinction through the runner and no-publication boundary.

### Pre-cutover run — earlier repairs recover, record repair exhausts

Execution
[`2026-09-25T22-18-57Z-dadf1076a7fcde7bd0710c1f047ab377`](../../zig-out/e2e-spec/2026-09-25T22-18-57Z-dadf1076a7fcde7bd0710c1f047ab377/report.md)
recorded modified revision `58b0917`, source fingerprint
`129b92c3c395bf79df8a485de4594e6d7e53409d3304e3d551a4dfff830408bb`.
Its requests still use the pre-cutover token/citation tuple.

| Boundary | Observed evidence |
| --- | --- |
| Extraction through brief, calls 1–9 | All source obligations reached generation. The title again failed `unknown_exact`; repair replaced the reference with prose and passed native field validation. |
| Story, calls 10–12 | The same join failed. Call 11 returned reasoning-tagged content without a final answer; existing protocol correction recovered on call 12, preserving request 11's identity and accounting both attempts. The replacement was prose. |
| Entity decision, calls 13–14 | `not_applicable` had the same invalid join in its basis. Repair added claim 2 and passed native validation, but the basis remained only the greeting literal. Correct citations do not explain applicability. |
| Records, calls 15–17 | Record 0's functional requirement again selected token 1/citation 2 with only claim 1. Both authorized record replacements returned it unchanged. The same assignment exhausted two repair executions: `RetryLimitExhausted`. |
| Terminal boundary | 17 provider calls, 25,996/100,000 tokens, complete usage accounting. No specification or clarification was published; semantic/principle assessment, persisted publication/readback and rubric grading were not reached. |

The [records response](../../zig-out/e2e-spec/2026-09-25T22-18-57Z-dadf1076a7fcde7bd0710c1f047ab377/evidence/generation/call-000015/model_output.txt)
also repeats the greeting as Given/When/Then and includes an entity despite the
fixed `not_applicable` decision. These are additional candidate problems; native
validation stopped at record 0's join before entity membership or semantic review
could assess the rest. The supplied prompt already described required behavior,
precondition, trigger and outcome, and instructed the model to follow the entity
decision. This is not evidence that purpose guidance or source requirements were absent.

The [record repair request](../../zig-out/e2e-spec/2026-09-25T22-18-57Z-dadf1076a7fcde7bd0710c1f047ab377/evidence/generation/call-000016/request.json)
included the rejected value, source evidence and permission to correct content and
claims together. Calls 16–17 sent identical 6,786-byte requests and received the
same invalid record. Earlier successful work continued; missing-answer recovery
and global token enforcement were not the final failure.

**Rollout consequence at that time:** implement the Phase 2 cutover, now present.
Its regression scope spans brief, story, entity basis and records,
including a shared-provenance acceptance criterion. Phase 3.1 must combine earlier
successful repairs, a recovered missing answer and later native exhaustion with
separate retry identities and exact accounting. Phase 2.4 and live Phase 4 must
distinguish correct lineage from meaningful content: deriving claim 2 removes the
redundant join, but cannot turn a greeting alone into a requirement, an applicability
explanation or a test scenario. Reaching a later failure does not establish improved
specification quality. No new retry or repair authority is justified by this run.

### Earlier post-cutover run — wrong-kind exact selection, then missing-answer exhaustion

Execution
[`2026-09-26T00-13-51Z-8c9c22b2f48057252273f4bf6d7dfd73`](../../zig-out/e2e-spec/2026-09-26T00-13-51Z-8c9c22b2f48057252273f4bf6d7dfd73/report.md)
recorded modified revision `a71afaa`, source fingerprint
`2acaaf88cc0af1a406f9e2506d88c7adc775c44ff66680311b402a8b9e64f981`.
The captured requests use the initial Phase 2 `exact_copy.claim_id` contract,
before the subsequent purpose-guidance conformance correction.

| Boundary | Observed evidence |
| --- | --- |
| Extraction/reconciliation, calls 1–7 | All three source obligations reached generation. Claim 1 contains business prose; claim 2 is the preserved greeting. Both were retained, with no conflict. |
| Brief, call 8 | Title, description and goal each returned only `{"kind":"exact_copy","claim_id":1}` with explicit support `[1]`. Claim 1 exists but is not a preserved-token occurrence; `preserved_tokens` offered claim 2. The integer passed the structural schema, then native validation rejected the title with `unknown_exact`. |
| Title repair, calls 9–10 | The first response contained only a reasoning block. Protocol correction added `missing_final_text` and the explanation “Final-answer admission failed: no final answer was received.” Call 10 returned a string containing the source bullet list. It was merged and the next native check advanced to the description defect. This is mechanical recovery, not evidence of a useful title. |
| Description repair, calls 11–12 | Both HTTP 200 responses ended after `</reasoning>`, with `finish_reason:"stop"` and no final text. They are attempts 1 and 2 of request 10. The shared protocol allowance exhausted at `generate-brief-repair-request-account`: `RetryLimitExhausted`, limit 1, two executions. No description replacement was merged. |
| Terminal result | 12 calls, 15,690/100,000 tokens, complete usage accounting. Story/records, coverage, semantic/principle review, publication/readback and grading were not reached. No specification or clarification was published. |

Eight leading-prefix normalizations were logged for calls 1–8. No JSON/schema
validation rejection was recorded after admission. The final stop was missing
answer exhaustion, not authentication, budget exhaustion or a repeated native
merge. [Raw call 12](../../zig-out/e2e-spec/2026-09-26T00-13-51Z-8c9c22b2f48057252273f4bf6d7dfd73/evidence/generation/call-000012/response.json)
and the [existing decoder](../../src/adapters/provider/bedrock_response.zig)
agree: no final answer follows the reasoning block. Reasoning must remain excluded
from candidate data. The requests included native `response_format.type="json_schema"`.

**Confirmed request defect:** the common purpose instruction says
“Embed exact_copy claim IDs within prose,” including in
[call 11's repair request](../../zig-out/e2e-spec/2026-09-26T00-13-51Z-8c9c22b2f48057252273f4bf6d7dfd73/evidence/generation/call-000011/request.json).
That request correctly has `preserved_tokens:[]`, a string-only selected schema,
and a diagnostic expressly prohibiting exact-copy values. The unconditional
instruction conflicts with those permitted choices and does not distinguish
structured reference objects from IDs written into prose. The returned reasoning
discusses inserting claim/citation numbers into strings, which is consistent with
that ambiguity; it does not establish why the provider omitted its final answer.

The empty repair choices are correct under ADR 0020: invalid claim 1 supplies no
exact lineage, so the original bound is `B=[1]`. Substituting claim 2 during this
value-only repair would add evidence outside that authority. Initial generation
may select the eligible claim 2 and derive `L=[1,2]`; the engine must not choose it
automatically or expand the repair bound to compensate for a poor response.

**Retained-run follow-up — Phase 2.2:** replace the ambiguous reference instruction
across brief/story, entity and record guidance, including their reused repair
prompts. State that prose uses strings; an exact-copy object, when permitted,
selects a listed `preserved_tokens.claim_id`, not a general claim, token ID or
citation ID. General retained claims remain available for semantic provenance;
they are not automatically exact-copy choices. IDs stay in structured fields.
Empty exact choices exclude exact objects; a string-only schema requires prose.
Keep field-purpose guidance, one evidence projection and the
existing schema/repair owners; replace wording rather than adding another prompt,
choice catalogue, dynamic-enum mechanism or retry path. The schema remains a
structural contract and native validation retains eligibility authority.

**Regression and live follow-up:** Phase 3.1 must cover wrong-kind selection →
title missing answer → protocol recovery → a different field's repeated missing
answers → exhaustion, plus successful completion and unrelated sources. Assert
that each emitted prompt agrees with its selected schema/choices, valid exact
handles still derive lineage, earlier repairs/siblings persist, retry identities
and tokens remain exact, and neither unresolved failure nor poor model
interpretation becomes a clarification. Phase 4 must separately measure final
answer availability and meaningful title/story/FR/AC content with approved calls.
This run does not justify changing the provider adapter or retry limits.

| Captured assignment | Request bytes | Prompt schema bytes | Actual input / total tokens |
| --- | ---: | ---: | ---: |
| Brief initial, call 8 | 9,693 | 3,607 | 1,502 / 1,667 |
| Title repair / correction, calls 9 / 10 | 3,592 / 3,937 | 178 each | 748 / 1,022; 797 / 944 |
| Description repair / correction, calls 11 / 12 | 3,604 / 3,949 | 178 each | 748 / 1,148; 797 / 959 |

The earlier coupled repairs and current value-only repairs have different scope;
their byte counts are not an equivalent-assignment benchmark. Smaller requests
are not proof of improved output quality. The old redundant
join was removed, but this run never selected the valid exact handle and produced
no graded specification. The subsequent Phase 2 conformance work closes the
request-guidance and code findings in §6.5, but does not change this live result.

### Earlier corrected-guidance run — eight recovered targets, then no final answer

Execution
[`2026-09-26T01-21-50Z-aa8fda0613a0159cf267a5c7f8ff35c8`](../../zig-out/e2e-spec/2026-09-26T01-21-50Z-aa8fda0613a0159cf267a5c7f8ff35c8/report.md)
recorded modified revision `a71afaa`, source fingerprint
`b6688a68a8b7ffa65b0abba4112874218592accfec3dc5aa81f335d0216b2b23`.
Captured brief/story, entity and record guidance matches the current corrected
prompts, including their reuse in repair. The earlier unconditional exact-copy
instruction is absent. Native `response_format.type="json_schema"` is present;
the route remains Bedrock `openai.gpt-oss-20b-1:0`, temperature 0, low reasoning.

| Boundary | Observed evidence |
| --- | --- |
| Extraction/reconciliation, calls 1–7 | All three source obligations remain available. Business claim 1 and preserved greeting claim 2 are retained, with no conflict. |
| Brief, calls 8–14 | All three fields incorrectly select exact claim 1, although only claim 2 is offered as a preserved token. Each field recovers after one missing answer and one protocol correction. Each replacement copies the whole requirements paragraph; native acceptance does not establish a useful title or goal. |
| Story, call 15 | Exact claim 2 with explicit support `S=[1]` is accepted without provenance repair, exercising the intended derived-lineage contract. The story is still only the greeting literal, so this is not semantic success. |
| Entity basis, calls 16–18 | Wrong-kind exact claim 1 is replaced after missing-answer recovery. The replacement copies source bullets rather than explaining the `not_applicable` decision. |
| Records, calls 19–27 | Initial FR, Given, When, Then and user-visible outcome all select exact claim 1. FR and Given/When/Then each recover after a missing answer. Replacements mostly repeat source requirements rather than fulfilling their individual purposes; semantic review has not assessed them. |
| Outcome repair, calls 28–29 | Both responses contain only a reasoning block, ending at `</reasoning>` with `finish_reason:"stop"`. Request 20 exhausts its two allowed attempts at `generate-records-repair-request-account`: `RetryLimitExhausted`, provider diagnostic `missing_final_text`. No replacement is merged for `records[2].text`. |
| Terminal boundary | 29 calls, 37,596/100,000 tokens, complete usage accounting. Coverage completion, source/principle review, publication/readback and grading are not reached. No specification or clarification is published; publication and grading are `not_run`. |

The [last repair request](../../zig-out/e2e-spec/2026-09-26T01-21-50Z-aa8fda0613a0159cf267a5c7f8ff35c8/evidence/generation/call-000028/request.json)
explicitly rejects exact claim 1, states that no exact/passive choices are permitted,
and requires source-backed strings while preserving fixed evidence. Its native
schema is only an object containing a string array. The correction adds
`missing_final_text`, “Final-answer admission failed: no final answer was received,”
and the complete-corrected-response instruction. It is not an identical retry.
[Raw call 29](../../zig-out/e2e-spec/2026-09-26T01-21-50Z-aa8fda0613a0159cf267a5c7f8ff35c8/evidence/generation/call-000029/response.json)
contains no final text for the adapter to admit. The evidence establishes the
missing answer, not why the provider/model omitted it. Do not substitute reasoning,
increase retries, infer an adapter defect or widen the repair's `B=[1]`.

Ten calls lack final answers: 9, 11, 13, 17, 20, 22, 24, 26, 28 and 29.
Eight native targets recover and execution continues; the ninth target exhausts
protocol recovery before a native merge. The 18 repair/correction calls consume
20,204 tokens. All calls return HTTP 200; budget, authentication and JSON/schema
correction exhaustion are not the terminal cause.

| Captured assignment | Request bytes | Actual input / total tokens |
| --- | ---: | ---: |
| Brief initial, call 8 | 9,740 | 1,510 / 1,628 |
| Story initial, call 15 | 7,426 | 1,266 / 1,328 |
| Records initial, call 19 | 18,803 | 2,804 / 3,046 |
| Outcome repair / correction, calls 28 / 29 | 5,353 / 5,698 | 1,098 / 1,238; 1,147 / 1,255 |

**Rollout impact:** this run does not demonstrate a Phase 2 contract regression;
it does demonstrate that corrected guidance and valid lineage are insufficient
for useful model output. Phase 3's offline sequence now covers those successful
repairs followed by late protocol exhaustion; meaningful recovery remains distinct
from mere field acceptance.
Phase 4.1 must test both the captured prose-only repair's final-answer availability
and fresh generation's reference selection/field meaning. The correct exact handle
already works; choosing its business use remains semantic. Existing schema-choice
narrowing proposals (§6.6) remain separate decisions, not an implicit extension of
this run review. No new evidence, retry or semantic-review authority is justified.

### Pre-Phase-4 run — identical requests, first repair receives no final answer

Execution
[`2026-09-26T02-40-05Z-d1afebc8a7c1bd09810bf1593a96b793`](../../zig-out/e2e-spec/2026-09-26T02-40-05Z-d1afebc8a7c1bd09810bf1593a96b793/report.md)
recorded modified revision `1c56234`, source fingerprint
`f970b687ca8f2c1db92368788c94e02647983d8ce9d2aafb400d80fa7abdbca4`.

| Boundary | Observed evidence |
| --- | --- |
| Extraction/reconciliation, calls 1–7 | All three source obligations reached generation. Business claim 1 and preserved greeting claim 2 were retained; no conflict was reported. |
| Brief, call 8 | Title, description and goal again contain only `exact_copy.claim_id:1`, with explicit support `[1]`. The request lists preserved-token claim **2**. Claim 1 is business prose, so native title validation rejects `unknown_exact`. The initial structural schema permits integer handles; native eligibility remains necessary. |
| Title repair, call 9 | The authorized replacement is `{"value":["..."]}` under fixed evidence `[1]`. The request explicitly names rejected claim 1, prohibits unavailable exact/passive choices and requires source-backed strings. The raw HTTP 200 response ends at `</reasoning>` with `finish_reason:"stop"`; no final answer follows. |
| Protocol correction, call 10 | Request **9**, attempt **2**, retains the original assignment, selected schema and evidence. It adds `missing_final_text`, “Final-answer admission failed: no final answer was received.” and the complete-corrected-response instruction. The raw response again contains only reasoning. No replacement reaches JSON/schema/native validation or a merge. |
| Terminal boundary | `RetryLimitExhausted` at `generate-brief-repair-request-account`: limit 1, two executions. All **10 calls / 13,375 tokens** are accounted against 100,000. No specification, clarification or completed state was published. Story/records, source/principle assessment, publication/readback and rubric grading were not reached. |

The [repair request](../../zig-out/e2e-spec/2026-09-26T02-40-05Z-d1afebc8a7c1bd09810bf1593a96b793/evidence/generation/call-000009/request.json),
[correction request](../../zig-out/e2e-spec/2026-09-26T02-40-05Z-d1afebc8a7c1bd09810bf1593a96b793/evidence/generation/call-000010/request.json)
and their raw responses establish two separate problems: incorrect semantic
selection starts repair; missing final text prevents that repair from producing
a candidate. This is not missing user information. Earlier malformed prefixes
were admitted through the existing normalization path; JSON/schema exhaustion
was not the terminal cause. The [adapter](../../src/adapters/provider/bedrock_response.zig)
correctly rejects an empty final portion rather than using reasoning as the answer.
The captures do not establish why the provider/model omitted that answer.

**Comparison:** all ten serialized request bodies are byte-identical to the
corresponding calls in the preceding `01-21-50Z` run, including native
`response_format.type:"json_schema"`, temperature 0 and low reasoning. Call 8's
raw message content is also identical. The same call-10 correction previously
returned a string containing the requirements; here it returns no final answer.
That earlier field acceptance was not evidence of a useful title. The changed
build fingerprint and earlier stop do not establish a Phase 3 regression: the
observed request remained the same and the provider response changed.

| Captured assignment | Request bytes | Actual input / total tokens |
| --- | ---: | ---: |
| Brief initial, call 8 | 9,740 | 1,510 / 1,628 |
| Title repair, call 9 | 3,639 | 756 / 868 |
| Title protocol correction, call 10 | 3,984 | 805 / 953 |

**Rollout impact:** keep Phases 0–3 complete as offline contract/integration work;
Phase 4 remains open. The existing [Spec runner regression](../../src/composition/root.zig)
already covers a misbound exact reference followed by two missing-answer attempts,
exact accounting and no publication. Prioritize this first-title assignment in
Phase 4.1, retaining the previous identical request's final answer as comparison
evidence and the earlier record-repair failure as a second captured assignment.
Measure final-answer availability separately from title usefulness and initial
reference selection. An increased retry limit, guessed citation, reasoning-as-answer
fallback or broader repair authority is not justified. Numeric-enum schema
selection remains the separate decision in §6.6; it could constrain the initial
wrong-kind choice but cannot itself repair an absent final answer.

## 3. Ownership inventory

| Information/work | Current owner/status | Assessment |
| --- | --- | --- |
| Source inventory, lines, coordinates and verbatim spans | [source_selections](../../src/domain/source_selections.zig), native readers | Already deterministic. Models select offered ranges; they do not compute coordinates or reproduce quotations. |
| Exact-token candidate identity and raw bytes | [structured_tokens](../../src/domain/structured_tokens.zig), extraction identity actions | Already deterministic. Relevance and classification remain semantic where not fixed by policy. |
| Canonical claim/citation/token identities | [reference_extraction](../../src/domain/reference_extraction.zig), [reference_claim_items](../../src/domain/reference_claim_items.zig) | Already native, assigned after validation. Do not add another identity system. |
| Exact-copy choice | [typed_text.ExactCopy](../../src/domain/typed_text.zig), [generation schema](../../design/workflows/spec/generation.schema.json) | Phase 2 uses one preserved-token claim handle and derives lineage. Purpose guidance distinguishes eligible exact choices from general evidence claims and respects narrowed repair schemas. |
| Citation union | [reference_support.select](../../src/domain/reference_support.zig), [specification_provenance](../../src/domain/specification_provenance.zig) | Already derived. Phase 1 removed the shared owner's Spec-type dependency; Spec eligibility remains in its own consumer (§6.1). |
| Summary statement `local_key` | [reconciliation validation](../../src/domain/reference_reconciliation_validation.zig), schema and key repair | Model-generated uniqueness/order bookkeeping remains. Separate candidate for removal after defining ordering semantics. |
| Preserved-token reconciliation content | [reconciliation validation](../../src/domain/reference_reconciliation_validation.zig), [repair](../../src/domain/reference_reconciliation_repair.zig) | The sole selected preserved-token claim determines its token. Audit/removal of the repeated token field is feasible separately. |
| Review assignment ordinals | [specification_support](../../src/domain/specification_support.zig) | C2a–C2b implements native assignment progress and identity for initial review and repair. Working validation defers only unvisited subjects; complete-set validation remains. Cost and live quality are open. |
| FR/AC IDs and numbering | [specification_identity](../../src/domain/specification_identity.zig) | Already deterministic. The number of meaningful requirements is a semantic question, not an array-count calculation. |
| Coverage membership/counts | [specification_coverage](../../src/domain/specification_coverage.zig) | Already computed. Counting a cited claim is not proving its meaning survived. |
| Exact-copy reconstruction after coverage failure | [specification_coverage_repair](../../src/domain/specification_coverage_repair.zig) | Already native when the entire field equals a known literal and already cites its claim. Preserve this bounded behavior; do not replace it with a model call or expand it to guessed embedded matches. |
| JSON part assembly | [json_composition_runtime](../../src/domain/json_composition_runtime.zig) | Already native and prompt-free. Preserve full assembled validation and exact producer dependencies. |
| Markdown, headings, escaping and literal expansion | [specification_projection](../../src/domain/specification_projection.zig), [renderer](../../src/domain/specification_markdown.zig) | Already deterministic. Do not ask a model to fix the rendered document. |
| Retry limits, usage, freshness and publication status | Existing runner, lifecycle, accounting and publication owners | Already engine authority. Focused requests must integrate their identities and retirement with these owners; no new policy, counter or publication authority. |

An important distinction: deterministic validation is not always deterministic
construction. Before Phase 2, native code rejected a misbound exact copy after the
model chose three related numbers. The active handle contract removes that join;
it does not prevent a wrong-kind selection or inconsistent use of its derived
evidence by downstream consumers.

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

## 5. Approved target exact-reference contract — source-backed content

### 5.1 Use an existing identity once

The **active model and canonical segment**, approved by ADR 0020:

```json
{"kind":"exact_copy","claim_id":2}
```

This is the implemented contract, not a permanent requirement to return the ID.
§§15.4–15.5 propose omitting determined model selectors while retaining canonical
occurrence identity and the existing resolver. That model/canonical separation
requires an ADR 0020 amendment; no accepted wire contract changes in this plan.

The existing reference ledger can resolve that preserved-token claim into:

```text
captured source occurrence → token 1 → citation 2 → exact bytes
```

[reference_claim_items.build](../../src/domain/reference_claim_items.zig) already
checks a preserved-token claim's one citation, source occurrence and raw bytes.
[reference_support.exact](../../src/domain/reference_support.zig) now resolves the
selected claim directly. The tuple-specific reverse lookup and §36 repair trigger
were removed; native token/citation identities remain valid elsewhere.

**The request must also remove the join.**
[model_evidence.Token/project](../../src/domain/model_evidence.zig) now includes the
owning `claim_id`, trusted value and source context. Do not add a second lookup
table or strip evidence needed to choose meaningfully. Request choices, schema
exclusions and native eligibility must use the same owning facts; an arbitrary
integer still does not become a valid handle. Phase 2.2 aligned the prompt and
fixed-repair choice projections with that rule.

This projection also supplies reconciliation and source review. Reconciliation
still requires token IDs; removing the redundant response field is required in
§7A. Retain native token metadata needed by canonical consumers after that cutover;
do not globally replace the shared token record. Use contract-appropriate views from the same projection owner: directly
selectable claim occurrences for typed content, existing token facts where required.
Do not send duplicate exact-choice catalogues in one request or add workflow-name
branches to choose semantics.

The model still writes prose and selects evidence for its semantic assertions.
Exact-value dependency membership comes from the explicit exact-value selection,
not from guessing what a prose string might mean. Equal strings in two files remain
different occurrences. Never resolve by literal text or by the first matching value.

### 5.2 Preserve explicit selection; derive effective provenance

The pre-cutover canonical representation could not distinguish the required roles
if automatic derivation overwrote the explicit claim list. These two cases explain
why [specification.Provenance](../../src/domain/specification.zig) now stores explicit
selection separately from the derived view:

| Explicit support `S` | Exact dependencies `E` | Effective claims `L` | After removing the exact reference |
| --- | --- | --- | --- |
| `[1]` | `[2]` | `[1,2]` | Claim 2 should disappear from derived lineage. |
| `[1,2]` | `[2]` | `[1,2]` | Claim 2 remains explicitly selected support. |

Subtracting exact dependencies loses intentional support in the second case;
keeping the old union leaves obsolete derived support in the first. This is a
demonstrated information loss, not an implementation detail to defer.

**Approved contract:** retain explicit reference-claim selection `S` once with
canonical content. Derive `E` from that content's exact handles, then
`L = stableUnique(S + E)` through the refactored reference owner. Do not persist
independently writable `S`, `E` and `L` lists. Distinguish stored selection from
the effective reference view with types, not caller-specific meanings of `claim_ids`.
Spec composes this view into its evidence contract; other domains preserve their
own accepted support types. `L` describes reference claims, not all workflow evidence.

ADR 0020 approved this amendment; Phase 2 activated its version changes. Retaining
the old canonical interpretation is incompatible with the add/remove guarantees.
Materialized citations and coverage remain checked projections, not selection authority.

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

**Required follow-up, not current wire behavior:** §§15.4–15.5 remove the model's claim
list when a native assignment already binds explicit `S`, or explicitly binds
`S=[]` with support derived from exact segments. Canonical `provenance.claim_ids`
still records `S`, never the effective union. General generation currently offers
eligible claims; that catalogue is not a fixed support assignment. The proposed
model/canonical separation also removes determined exact selectors. It needs a
focused amendment to ADR 0020's model-field correspondence, while preserving its
canonical selection, union, occurrence, evidence-bound and readback rules.

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

**Approved Spec scope rule:** derive passive choices from effective lineage `L`, as
the equivalent valid old candidate does. Explicit-only scopes would narrow existing
valid behavior and are not a neutral safety measure. Newly selected occurrences
must still be eligible for the current assignment, and fixed repairs must not gain
new scope. Removal must revalidate passive siblings that depended on the removed
claim; operational capabilities remain entirely separate.

### 5.4 This is construction under a new contract, not silent repair

The superseded malformed tuple must not be accepted and silently patched. The active
model contract removes redundant fields, validates one selection, then constructs
canonical data according to an explicit rule. Reject superseded model formats;
do not add compatibility readers, guessing, or an optional fallback to old tuples.

The current [Values(boundary)](../../src/domain/specification.zig) distinguishes model
and canonical evidence but shares business-text structure. Prefer a claim handle
in both model and canonical exact segments, with validity established at the native
boundary. The ledger owns the token/citation/bytes; duplicating the pair in every
canonical segment is not required to preserve exactness. Renderers and coverage
resolve it through the shared owner. Model data remains untrusted until admission.

This also avoids a real API obstacle: [atomic_repair.Contract](../../src/domain/atomic_repair.zig)
uses one replacement type for expected values, `current_value`, response parsing,
comparison and merge. Keeping model handles but canonical pairs would require a
separate presentation/conversion contract. That alternative is feasible in principle,
but has more surface and no demonstrated benefit here. Never use a lossy model
projection as the native expected value or move lookup into generic JSON decoding.

The shared-handle schema/type, version changes and §6.5 consumer corrections are
implemented. Avoiding conversion machinery alone did not establish end-to-end
conformance; the owning-unit tests in §10 provide the additional evidence.

### 5.5 Specify fixed repair and review semantics before coding

The existing [native repair](../../src/domain/specification_repair.zig) pins selection;
[omission repair](../../src/domain/specification_coverage_repair.zig) compares canonical
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
explicitly authorized coupled target, or remains a typed block. ADR 0020 retired
§36's tuple-specific authority; it does not authorize broader evidence changes.
Do not silently add an explicit citation to compensate
for a removed derived dependency. Fixed membership and reviewed-omission repairs
must apply the same decision through their existing owners.

**Rejected candidates need a distinct precondition.** An unknown/wrong-kind handle
prevents `L` from being constructed. Requiring equality with a nonexistent old `L`
would disable repair; treating the bad handle as evidence would invent authority.
Today explicit provenance can resolve independently before the value fails.

**Approved ADR 0020 rule:** bind a repair baseline
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
`specification_repair.authorize` recaptures candidate facts on each attempt;
the new `Candidate.value_bound` retains original `B` for that stable target while
expected value/revision advance through the existing atomic owner. Do not add a
parallel permission store. Keep this implemented protection and the full-unit
checks closed in §6.5.
Coupled, membership, reviewed insertion and native coverage repairs retain their
own approved policies; `B` must not silently replace those policies.

Distinguish bad candidate data from a broken evidence context. An unavailable
model-selected handle under a valid binding is a native candidate defect. Missing,
corrupt or stale engine-owned ledger/choice bindings follow their existing terminal
authority or runner rejection; they are not requests for the model to invent a
replacement reference and never become user clarifications.

[Spec source-review evidence](../../src/domain/specification_support_evidence.zig) currently
requires supported findings to match the candidate's effective provenance and
replays that rule on readback. Preserve that comparison against derived `L`, while
presenting explicit support and exact-reference content accurately to review.
Literal lineage is not proof of semantic entailment. Negative/loss diagnostics retain
their distinct eligibility rules; do not globally tighten them to positive-content
provenance or change review verdict authority. This comparison is Spec's review
contract, not a universal rule for every workflow's findings.

There is a residual bookkeeping cost: supported review responses still repeat
evidence that admission requires to equal the candidate's effective provenance.
The existing review-guidance owner already projects it as `supported_provenance`;
test that emitted initial/repair packets agree with native admission instead of
adding another projection or asking the reviewer to calculate `S + E`. Removing the repeated response fields
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
a failed new lookup through a generic provenance error. The actual rejecting
boundary determines recovery: §6.7's selected enums now reject some unavailable
handles during schema validation, before native admission. Those use complete-response
protocol correction; remaining native defects use the authorized atomic repair.

[Completed state](../../src/domain/specification_state.zig) validates content,
coverage and review associations. [Pending state](../../src/domain/incomplete_specification.zig)
stores references and clarification identities; generation questions are flattened
to text by [the existing question builder](../../src/actions/clarification/build_specification_clarification_need.zig).
These are different contracts. ADR 0020's `specification/v2` and
`specification-state/v6` cutover is active, including old-version rejection.
Phase 2 closed the owning-unit readback discrepancies recorded in §6.5. Preserve
that coverage when adding §6.7 restrictions; no migration, dual reader or new pending
evidence store is justified. Live completed readback remains unproven in Phase 4.

### 6.1 Shared mechanics and consuming-domain policy

Cross-workflow reuse cannot simply call `specification_provenance` from Plan or
Tasks. Phase 1 moved selection mechanics to reference-owned inputs and results in
[reference_support](../../src/domain/reference_support.zig). Spec still requires
completed reconciliation, retained claims and business-appropriate token kinds,
and rejects clarification-response support. Those are not universal reference
rules. Phase 2 extended the same owner to exact-handle lineage.

| Responsibility | Owner for the Phase 2 cutover |
| --- | --- |
| Handle identity and text syntax | Existing `reference_identity.ClaimId` and `typed_text`; syntax/membership validation receives native permitted choices. |
| Occurrence lookup and reference lineage | Existing reference owner resolves one bound ledger and derives stable claim/citation unions. Phase 1 moved its result types below Spec; Phase 2 added exact-handle lookup there. |
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
[reference_identity](../../src/domain/reference_identity.zig) type, not import the
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

[ADR 0003](../../design/decisions/0003-generic-workflow-engine.md) allows any workflow
identity composed from registered contracts. A response schema supplies shape;
the registered native operation supplies semantic interpretation. Plan's existing
[typed-leaf design](../../design/contracts/07-domain-representations.md) already
distinguishes business text, semantic text and operational references.

- Apply this contract to declared typed fields, including nested records, arrays
  and optional containers supported by that native contract. Do not recursively
  interpret arbitrary objects named `claim_id`, `kind` or `provenance`.
- Keep JSON decoding and [composition](../../src/domain/json_composition_runtime.zig)
  structural and prompt-free. Assembly does not resolve references or certify
  semantic support; typed admission and full validation follow it.
- Keep one configured complete schema per response binding; derive selected/part
  schemas from it and verify conformance with the registered shared text contract.
  The [schema compiler](../../src/domain/model_result_schema.zig) supports local
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
[native dependency capture](../../src/domain/specification_candidate_context.zig) and
[reference lineage](../../src/domain/reference_reconciliation_context.zig) already do.
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

`L` is only the reference-claim component. [Plan](../../design/contracts/18-plan.md)
also admits authenticated edits and other evidence; [Tasks](../../design/contracts/19-tasks.md)
selects obligation/file/command IDs; [Implement](../../design/contracts/20-implement.md)
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

### 6.5 Final implementation review — findings closed in Phase 2

**Evidence level:** the following were code-path findings against the first Phase 2
implementation. The retained run stopped before these downstream paths, so they
were not causes of its missing answers. The added regressions and current checks
are recorded in §10. The text below retains each causal finding and required
boundary so a future change does not recreate it.

**High — full-record admission and per-field rendering disagree (2.4).**
[inspectRecord/validateStored](../../src/domain/specification_provenance.zig) collect
all record fields before deriving `L`. In contrast,
[project](../../src/domain/specification_projection.zig) passes each field with the
record's complete provenance to `scalar`; `scopesFor` derives lineage from that
field alone and compares its citations with the record-wide union.

A concrete accepted shape is `S=[business claim 1]`, prose-only Given/When and an
exact claim `2` in Then, with distinct citations for the two claims. Record admission
derives `L=[1,2]`; rendering Given derives `[1]` and rejects the stored citation
union. The new shared-record test ends after `checkRecord`; the older projection
test uses uniform prose fields. Neither proves this path works. Resolve the owning
record once through the existing provenance owner and project its individual values
under that validated context. Do not add exact claim `2` to Given or overwrite `S`
to accommodate the renderer. Test admission → projection → rendering → completed
readback, with exact references in just one field, repeated references, relationship
arrays and unrelated source examples. Tampered persisted citations must still reject.

**High — repair paths do not consistently use the same owning unit (2.3).**

- [Omission authorization](../../src/domain/specification_coverage_repair.zig)
  computes effective claims from only the selected record field, whereas
  [source-review evidence](../../src/domain/specification_support_evidence.zig)
  computes record-wide support. It can refuse an otherwise eligible field repair
  whose sibling contains the exact dependency. `omissionPacket` also restricts
  schema alternatives using `S` instead of the effective bound: an exact-only
  field with `S=[]` can authorize but fail packet construction, and `S=[1]` with
  exact claim `2` can receive a prose-only schema despite needing to preserve `2`.
- [Native retry progress](../../src/domain/specification_repair.zig) validates a
  provenance target through explicit-only `p.select`, and a record value through
  single-field `checkAttributed`. Accepted `S=[]` with valid exact support, or
  support contributed by a sibling, can therefore be classified as unresolved.
  Resolve record evidence once, then validate the selected target under it. Simply
  checking the whole record would also be wrong: an unrelated sibling failure must
  not keep a successfully repaired target's retry counter recurring.
- Completed-value replacement changes text while retaining old materialized
  citations, then [replaceCompleted](../../src/domain/specification_session.zig)
  performs canonical revalidation. Reordering exact references can preserve the
  authorized claim/citation sets but change their required canonical order and
  reject. Recompute the affected unit's projection **after an authorized merge**,
  compare its effective sets against the authorization, then validate completely.
  Persisted readback must continue comparing and rejecting corrupt stored values;
  it must not use that construction path to silently repair them.

Use the same declared owning-unit traversal and resolved view for these consumers.
Sibling-derived support here means fields in the same shared-provenance record,
never evidence borrowed from a different attributed unit;
keep atomic authorization, domain-specific insertion/membership rules, runner
renewal and retry accounting with their current owners. Test repair of a prose
field whose exact support is in a sibling, exact-only `S=[]`, reordered references,
later sibling failure, scope expansion rejection and successful dependent rebuilding.
These are conformance repairs under ADR 0020, not permission for new evidence.

**High — request text and permitted choices still diverge (2.2).**
§2 records the unconditional exact-copy instruction in a string-only repair.
The provenance-repair rule also still demands nonempty explicit claims even though
ADR 0020 permits `S=[]` when eligible exact segments supply nonempty effective
support. Align the instruction and progress check with that same native rule.
There is also a shared packet issue: `packetForChoices` filters `preserved_tokens`
by the repair bound but builds `passive_literals` from every retained claim's scope.
`withSelectionChoices` narrows schema variants, not that list. With allowed passive
ID A and unrelated ID B, a fixed repair can still see both as choices even though
native validation admits only A. This is a code finding, not an observed passive-ID
failure in the latest run.

Preserve broad source evidence as context, but derive **offered replacements** from
the authorized unit through the existing provenance/session projection owners.
Keep one exact-choice list and one passive-choice list; do not add a second allowed-ID
catalogue or remove unrelated semantic source context. Verify emitted initial,
native-repair, omission and protocol-correction requests with zero, one and several
eligible choices and out-of-scope choices. A schema allowing arbitrary integers
still needs native membership validation; correct prompt wording is no guarantee
against a model selecting an unavailable integer.

**Medium — new shared lineage allocation cleanup is incomplete (2.1).**
`reference_support.lineage` owns an `ArrayList` without error cleanup. If an initial
append succeeds and later growth fails, a general allocator loses that buffer.
The Phase 1 allocation-failure test exercises `select`, not this new function.
Current arena callers release storage at teardown, so this is not evidence of a
live-run leak. Add ordinary owned-buffer cleanup and a growth-triggering allocation
failure test; preserve the already tested `select` implementation. Do not make the
shared API arena-only merely to avoid testing ownership.

**Medium — resource and reuse claims need direct evidence (3.1–3.2).**
[Coverage](../../src/domain/specification_coverage.zig) currently allocates effective
lineage for each candidate unit inside the retained-claim loop. The same unit is
thus traversed/allocated repeatedly. Measure this independently of provider tokens,
including repeated validation and larger ledgers. If material, derive each unit's
view once per validation pass using the existing owner; no persistent cache, second
coverage index or process-wide authority store is justified.

Independent reuse is feasible through the existing
[operation registry](../../src/ports/workflow_operation_registry.zig) and test-owned
schemas/bindings already demonstrated by [runner tests](../../src/workflow_execution_test.zig).
Use an isolated test registry and declared typed input/output; no production data
key, capability or demonstration workflow is needed. Prove different native
eligibility with a second typed consumer, and test structural composition separately.
Mixed-support tests may retain domain-owned non-reference evidence; they must not
pretend the current source-scoped text validator accepts answer-only typed text.

**What already agrees:** source-review `supported_provenance` is derived and
projected by its existing owner, completed intrinsic validation traverses whole
records, old wire/state versions reject, and native value repair retains original
`B`. Preserve these paths and extend their consumer tests. The primary problem is
inconsistent use of one authority's derived view, not a missing central repository
or a justification for another resolver.

### 6.6 Research check and feasibility limits

Rechecked AWS structured-output/response documentation on 27 September 2026;
§14 adds the evaluator's OpenAI boundary. AWS documents
`response_format` for open-weight InvokeModel structured output, numeric enums
and internal schema references. Its subset supports array `minItems` only at
`0` or `1`, and excludes numeric bounds and string-length constraints. New schemas
may require grammar compilation; identical schemas can reuse a cached grammar.
AWS specifies a 24-hour grammar cache from first access for identical schemas in
the same account. This is grammar reuse, not evidence of reduced prompt tokens.
Request-specific specialization can still add compilation latency; measure it.
[AWS structured outputs](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html)

Required object properties with `additionalProperties:false` can express a fixed
slot set, but the expanded batch-slot proposal is superseded (§6.9). Array length
alone cannot express one finding per subject, and
`uniqueItems` compares whole items: two different findings for the same subject
can still be distinct items. This rules out a count/uniqueness-only shortcut.
SDDE's closed profile does not currently expose `uniqueItems`, `contains` or
tuple validation; do not assume general JSON Schema keywords are available here.
[JSON Schema objects](https://json-schema.org/understanding-json-schema/reference/object),
[JSON Schema arrays](https://json-schema.org/understanding-json-schema/reference/array)

Internal references permit reuse of a schema definition, but do not guarantee
that an implementation preserves references when compiling or serializing it.
SDDE currently expands them in both places. A compact `$defs` source therefore
did not solve the superseded slot proposal's tree/wire expansion. Focused requests
reuse one canonical result shape. Reference-preserving serialization is not a
prerequisite for this direction and would not alone change compiler bounds.
[JSON Schema reuse](https://json-schema.org/understanding-json-schema/structuring#defs),
[AWS supported schema features](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html)

An enum can restrict an ID to a nonempty finite set; it cannot decide which
eligible occurrence preserves the intended meaning.
[JSON Schema enum](https://json-schema.org/understanding-json-schema/reference/enum)
Numeric enums and native eligible-ID restrictions now use the shared schema and
packet owners (§6.7). The same selected shape reaches provider guidance and local
validation. This is an offline conformance change, not a claim that the live model
will return final text or meaningful prose. Empty choices remove the unavailable
variant rather than producing an invalid empty enum.

JSON Schema treats integral number representations such as `2` and `2.0` as the
same integer. Extend SDDE's existing `exactInteger` checks rather than comparing
number spellings or introducing floating-point ID conversion.
[JSON Schema numeric types](https://json-schema.org/understanding-json-schema/reference/numeric)

AWS documents leading reasoning tags for this InvokeModel response. That explains
the framing, not the absence of a final answer in calls 17–18; their raw bodies
contain no text after the closing tag.
[AWS model response contract](https://docs.aws.amazon.com/bedrock/latest/userguide/model-parameters-openai.html)

The retained run already used native structured output. The reviewed sources do
not establish why its raw final answer was absent. Preserve the current missing-answer
classification, bounded correction and actual token accounting; do not use reasoning
as content or promise that prompt cleanup will fix the provider response. Phase 4
must separate final-answer availability, contract validity and semantic usefulness.

### 6.7 Option 2 — Restrict response choices using existing native authority

**Status: implemented and offline verified; observed live, full quality gate open.** The focused contract and 1,024-value limit were authorized in the
26 September 2026 implementation requests. Its outcome is precise:
an unavailable reference must fail the selected response schema, before native
candidate merge. Provider constraints may reduce invalid output; local schema and
native validation must still enforce the rule if the provider returns it anyway.

**Focused decision implemented:** extend design §12.2's existing tagged-alternative
restriction contract to narrow declared integer selectors to native eligible sets.
Preserve §12.9 / ADR 0016's composition binding, §22.4–§22.6's authorized replacement
and correction boundaries, and ADR 0020's reference/repair authority. Integer-enum
correction outlines now use the existing exact schema locator and type without
repeating the allowed list. The user separately approved increasing the existing shared enum limit to **1,024**; both
workflow-resource compilation and captured selected-schema reconstruction use it.
Larger sets reject without truncation or unrestricted fallback. This settles the
cardinality and bound-selector decisions. No live calls are authorized by this change.

**Limit-change verification:** `zig build test-model-result-schema
test-model-payload-schema --summary all` passed 83/83 tests; `zig build verify
--summary all` passed 126/126 build steps and 1,256/1,256 tests, including native
packaging smoke checks. `git diff --check` passed. No live calls were made.

In captured call 8, the exact-copy selector would have the following derived shape:

```json
"claim_id": { "enum": [2] }
```

The existing reference owner supplies `2`; it is not a configured constant or a
greeting-specific branch. Claim `1` remains eligible **business support** in
`provenance.claim_ids`. Restricting every field named `claim_id` to the same list
would corrupt the contract. Eligibility belongs to the declared selector and its
evidence scope, not its property name or numeric value.
This is an enum-only **schema fragment**. The current closed compiler permits
`enum` alone and rejects the previously illustrated `type` plus `enum` combination.
Prefer homogeneous string or integer enums through the existing node contract;
mixed-type enums and general JSON Schema keyword combinations are unnecessary.

**Shared ownership and scope:**

- Extend the existing [schema owner](../../src/domain/model_result_schema.zig) and
  compiler/validator/serializer for integer enums and restrictions. Reuse its
  canonical-to-selected schema relationship; derive a view of the one configured
  schema, never another provider-only schema or eligibility registry.
- Existing reference/passive and domain-policy owners supply allowed choices for
  their declared typed selectors. Bind those facts to the current ledger, source
  scope and assignment. Do not infer reference semantics in arbitrary JSON or branch
  on workflow names. General provenance, operational IDs and unrelated fields keep
  their own rules. Reuse the same mechanism across initial generation and existing
  insertion, replacement and omission requests that expose these choices.
- Initial choices can only express the availability known **before** the response.
  The model's later provenance selection can narrow passive/source eligibility;
  schema membership alone cannot prove that relationship. Native scope and semantic
  checks remain necessary. Fixed repairs can restrict to their already-known bound.
- Intersect restrictions with the canonical shape: zero choices remove the optional
  tagged alternative, one or more produce a stable unique allowed set. Never emit an
  empty enum, broaden a schema, silently truncate choices or select a default. A
  required selector with no valid alternative follows the existing typed rejection.
- Bind the selected schema once during request preparation. Prompt schema, native
  provider schema, local decoding/validation, diagnostics and protocol correction
  use that same restriction. Preserve it through cloning, request identity and
  configured part selection/assembly; validate the full assembled candidate too.
- Fixed-evidence repairs retain the original authorized choices; rejected responses
  cannot enlarge them. Changed dependencies invalidate the binding through the
  existing runner. Keep native eligibility, full validation, persisted readback,
  retries and token accounting with their current owners. Do not persist another
  allowed-ID authority or alter the canonical content format for request restrictions.

**End-to-end implementation findings (26 September review):**

| Boundary / evidence | Required treatment before claiming conformance |
| --- | --- |
| Integer enums — `model_result_schema.Compiler.node`, `jsonType`, `model_payload_schema.validateValue` | Implemented as a homogeneous integer-enum node alongside string enums. Cloning, complete/provider projection and exact numeric membership share existing owners. Regressions cover `2`, `2.0`, `2e0`, string `"2"`, fractions, range boundaries and duplicates. No broader scalar-enum support was added. |
| Selector binding — `model_result_schema.restrictNode` | Implemented using a packet-declared tagged variant and integer field. The selected canonical schema checks matching pairs and bounds before deriving restrictions; unrelated integer fields remain untouched. A provenance-only repair has no text selector, so retained text-choice facts do not change its selected schema. Duplicate declarations, empty/oversized sets and a mistyped matching target reject at preparation. A future request needing different sets for two occurrences of the same tag and field requires an exact-location declaration, not global inference. |
| Choice transport — `reference_model_input.withTextChoices`, `specification_session.packetForChoices/withSelectionChoices` | Native owners now carry exact ID sets out of band in the existing packet. `withContext`, `withJsonContext` and `atomic_repair.packet` retain them. Spec repair narrows presented display catalogues from typed facts, not by recovering authority from JSON. Reference extraction/reconciliation restrict passive IDs and still exclude exact-copy text. |
| Runtime ownership — `model_request_handoff.assign/prepared`, `model_request_preparation.Source.resultSchema` | Existing handoff retains a reference-counted `Restricted` schema and correction checks pointer identity. Reuse that lifetime and association. `Schema.clone` clones canonical content but does not retain `restriction_of`; it is not a safe replacement for retaining a live restricted binding. Bind after graph/schema cloning; do not add new request IDs or schema hashes to reset an assignment. |
| Composition — `json_composition_runtime.retain` | Retained proof must still be a restriction of the exact selected part, with current epoch/prerequisites. Byte-equal schemas from foreign requests are insufficient. Prove restriction retention through part capture and full assembly, sibling retention, and invalidation after reference renewal. |
| Scale and replay — `model_result_schema.max_choices`, `compileSelected` | **Approved shared limit: 1,024 enum values.** String and integer enums use the shared bound. Regressions accept 256, 257 and 1,024 values through cloning, complete/provider projection, readback and membership validation; compiler entrypoints reject 1,025 and native restrictions enforce the bound before preparation. Claim/token/passive IDs remain `u32`; this is a per-enum cardinality limit, not an ID-value or whole-workflow reference limit. Preserve the implemented resource checks; do not truncate, split into arbitrary extra calls or fall back to unrestricted integers. Provider-owned request limits remain unchanged. |
| Correction size — `model_schema_projection.outline`, `model_protocol_retry.build` | Integer-enum rejection retains the candidate path, reason and exact schema locator. The outline now says `integer` without repeating the complete allowed list, which remains in the selected schema. Measure the emitted request in approved live testing. |
| Capture/readback — request description, debugger and canonical state | `compileSelected` reads the numeric projection for diagnostic inspection; offline tests round-trip the selected schema. This diagnostic schema grants no execution authority. Canonical specification readback continues recomputing reference eligibility from its captured ledger; no persisted allowed-ID registry, state migration or compatibility reader. Live completed readback remains unproven. |

**Retry scope changes even though the retry owners do not.** Today call 8 passes
shape validation and receives separate native field repairs. Under option 2 it
would fail schema admission and enter complete-response protocol correction for
the brief assignment. Current `generate-unit` config permits an initial call plus
two corrections; a native repair request permits an initial call plus one correction.
Therefore identical call counts and byte preservation of fields in a rejected
initial response cannot be promised. Preserve already admitted units/parts and
authorized atomic-repair siblings; revalidate the complete corrected response and
its meaning. Test both successful multi-field correction and earlier exhaustion,
including alternating enum/JSON/missing-answer errors under one assignment budget.
Do not add another repair pass or raise limits to conceal this trade-off.

**Option 2 rollout and remaining evidence:**

| Chunk | Change and required evidence |
| --- | --- |
| O2.1 — Shared schema support | Implemented: homogeneous integer enums, bound tagged-field selectors, complete/provider projection and exact local validation. String enums and the 1,024-value bound remain shared. The latest wire schema restricts exact-copy choices to `[2]`; wrong-kind selection did not recur in that run. One observation does not establish reliability. |
| O2.2 — Bind native choices | Implemented: existing extraction, reconciliation, Spec generation and repair packets carry typed eligible IDs through request preparation. Spec repair packets narrow the visible display catalogue while retaining other source facts. Native provenance and full-candidate validation remain authoritative. The latest run passed coverage; complete publication/readback remains unproven. |
| O2.3 — Recovery and measurement | Existing correction/retry owners and budgets are unchanged. Full verification and packaging pass. §10 records actual request sizes and tokens from the latest run, which failed later during principle review. Comparative latency/reliability and a successful publication/readback/rubric run remain open. |

In the same deterministic brief request, four bound integer selectors render a
3,451-byte selected schema; replacing only those four enums with the canonical
integer bounds yields 3,607 bytes (156 fewer bytes with O2). This measures schema
projection size, not provider tokens or semantic quality. §10 adds actual live
request/token observations; comparative token/latency effectiveness remains open.

**Limits:** an eligible selection does not prove semantic support or useful writing.
Do not automatically substitute an allowed ID, attach all available evidence, infer
citations from prose, or increase retries. Option 1's metadata cleanup and option 3's
omitted fixed selectors are separate changes; neither is required for this patch.
Phase 4 remains open until its published/scored acceptance gate passes.

### 6.8 Open-item disposition after the end-to-end review

**Assessment:** option 2 is implemented through existing owners and present in the
latest wire requests. Review completeness and semantic usefulness now have direct
failure evidence; full publication remains open. No evidence justifies a new registry,
retry mechanism, fixer agent or workflow-specific ID mapping. This review does not
reopen the completed Phase 2 conformance work merely because live generation failed.

| Open item | Disposition / next evidence |
| --- | --- |
| Option 2 (O2.1–O2.3) | Integer schema, selector binding, packet transport and concise correction outline are implemented. The 1,024-value shared limit remains. Latest call 8 offered exact-copy `claim_id` enum `[2]`; the prior `unknown_exact` failure did not recur. This is limited live conformance evidence, not proof of useful output or reliable selection. |
| Deterministic ownership and supporting conformance | C0's baseline and C2a's focused contract are implemented with C2b. Native owners supply assignment identity, progress and collection assembly; some fixed evidence fields still need C2c. C1's presence corrections remain independent; the 13-area inventory does not authorize a system rewrite. |
| Complete review membership — implemented, effectiveness open | The retained pre-cutover call 15 returned no entries for 15 subjects. C2b now selects one subject, retains its finding and validates complete native membership. Do not reimplement this cutover. Extend scale/lifecycle evidence and measure whole-workflow cost and semantic usefulness (§14). |
| Missing final answers | Independent provider risk. Latest call 18 contained reasoning only with `finish_reason:stop`; existing correction recovered at call 19. Call 25 contained a final answer but was rejected at the budget boundary before candidate admission. The preceding run's calls 17–18 exhausted; retain both outcomes. No discarded answer, local output cap or need for extra retries is established. |
| Provider-setting comparison feasibility | Current `request_debugger.Edit` permits only content/schema edits, and `composition/request_debugger` rejects changed provider/model/reasoning/controls. ADR 0019 likewise fixes those settings. Current tooling can compare schemas/prompts at fixed settings; a controlled settings comparison of this captured request needs a separate focused diagnostic-contract amendment. Alternatively, approved isolated E2E cases can vary configuration, but their regenerated upstream requests are not a fixed-assignment experiment. No raw-client bypass or automatic route switching. |
| Field-purpose quality | Latest story repeats the greeting twice; the repaired entity explanation is the greeting alone. Source review nevertheless marked these supported. Existing generation guidance already requests field purpose, so missing prompt text alone is not an established cause. Regress review usefulness as well as generation shape, preserving genuine policy conflicts and source gaps. Do not add a literal blacklist, automatic positive verdict or a second review owner. |
| Phase 4.2 publication/readback/rubric | Remains open; the latest run reached neither publication nor grading. Production already parses canonical bytes before publication, and the harness rereads all required artifacts and proves byte equality. Record that composed same-contract proof; do not add a duplicate parse gate. Keep fresh-runtime/stale-contract readback tests separate. With the current null threshold, `not_configured` is not a quality pass: report criterion scores and the Phase 4.2 content checks. |
| Required §7A–B and alternatives 1/3 | These remain separate implementation chunks, but deterministic responsibility removal is now mandatory for overall completion (§15). §7C is implemented. Resolve token/key/fixed-evidence contracts; do not make removal conditional on measured token savings or a live failure. They are not established remedies for missing final text. |
| §7D diagnostics | The known unavailable-choice correction is already implemented. O2 must reuse its native facts and the existing schema diagnostic owner; there is no open general-purpose diagnostic redesign. |

**Verification status:** inspected producers, packet projections, compiled schemas,
provider projection/admission, corrections, native repair, composition, readback
ownership, debugger authority and rubric handling. Rechecked the official sources
in §6.6. Focused schema, Spec generation and model request checks passed **632/632
tests**. Final `zig build verify --summary all` passed **126/126 steps and
1,259/1,259 tests**, including native packaging smoke checks; `git diff --check`
passed. Those were implementation checks. This subsequent documentation review
inspected the user's retained run; it made no new provider or E2E call.

### 6.9 Cross-cutting schema/native conformance review

**Status: partially remediated; current disposition in §14.** Avoidable conformance gaps
allow model choices that could safely be excluded using already-known native facts.
Not every schema-valid/native-invalid response is a schema defect: native owners
must still check relationships, authority and meaning that the schema cannot prove.
This audit supports §1's primary ownership objective. Eliminate a redundant returned
fact when native inputs determine it; constrain a choice when they do not determine
its meaning. More schema checks are not a substitute for making that distinction.
Option 2 uses shared owners, but its scope covered reference eligibility only;
it did not establish conformance for presence, complete membership or conditional
evidence. Passing those ID tests did not establish end-to-end recovery. Preserve
that useful restriction while addressing the broader class through existing owners.

This inventory compares the configured schemas, selected-request construction,
provider projection, native validators, repair selections, readback and evaluator.
It is code-review evidence, not a claim that all listed failures occurred live or
that new regressions have run. Latest-run observations are in §10. Not every native
rule can or should become JSON Schema: distinguish unconditional shape rules,
request-bound facts, cross-field relationships and semantic judgments.

| Area | Confirmed exposure and existing owner | Required distinction / conformance check |
| --- | --- | --- |
| Required text across stages | Extraction, reconciliation and generation schemas allow empty text arrays/strings that [typed-text validation](../../src/domain/typed_text.zig) rejects. Some extraction text-repair schemas already require an element; sibling initial/repair definitions differ. | Cover descriptions, stories, entity explanations, record fields, reference reasons and replacements together. Require content only where the native contract does; whitespace/control-character checks still need the native text owner. |
| Generation provenance — resolved in §15.7 | The earlier response schema accepted arbitrary claim selections and clarification-response IDs. The current [generation schema](../../design/workflows/spec/generation.schema.json) forbids `provenance`; the engine binds support from validated reconciliation assignments and derives exact dependencies under ADR 0020. | Keep the closed response rejection and canonical/readback checks. An exact segment may add effective evidence without a repeated model selection; an unbound or stale assignment cannot be filled from the eligible catalogue. |
| Mandatory record families | The generation `records` array can be empty or omit FR/AC families. [Specification](../../src/domain/specification.zig) declares both mandatory; [authority admission](../../src/domain/specification_authority.zig) treats their absence as a candidate gap. | This is a completion obligation, not permission to invent content. A heterogeneous array minimum cannot establish both families. Preserve `needs_user`/`inconclusive`; the existing missing-entity insertion authority does not authorize general FR/AC insertion. |
| Entity decision versus records | Initial record schemas still offer all kinds although the entity decision is already fixed in the packet. [Session membership validation](../../src/domain/specification_session.zig) rejects entities under `not_applicable` and missing entities under `required`. | Project the fixed decision through the existing schema/selection owner; preserve conditional insertion/replacement authority and sibling records. Entity meaning remains semantic. |
| Extraction citations | Initial and citation-replacement collections can be empty; line IDs are broad integers. [Source selections](../../src/domain/source_selections.zig) requires citations, existing scope-local IDs and ordered ranges. | Cover initial, missing-citation and selected-range repair together. Supplied line choices are native facts; choosing which lines support a claim remains semantic. |
| Token-classification membership | The array permits missing, duplicate and foreign token candidates, plus choices incompatible with the extraction outcome. [Classification validation](../../src/domain/token_classification_validation.zig) already knows the candidate set and permitted decisions. | Test zero and nonzero candidate sets, complete membership, scope isolation and outcome-dependent choices. An empty collection can be legitimate; classification decisions must not be fabricated. |
| Summary/signal selections and keys | [Reconciliation schema](../../design/workflows/spec/reconciliation.schema.json) permits empty claim selections, arbitrary IDs and repeated local keys. [Reconciliation validation](../../src/domain/reference_reconciliation_validation.zig) checks selection, key uniqueness, content kind and coverage. | Reuse current claim facts for offered choices. Full coverage and kind consistency span entries; IDs alone do not prove them. Removing summary keys is the separate ordering decision in §7B. |
| Dispositions and conflicts | Broad collections permit absent/duplicate dispositions, invalid targets and conflict records with fewer than two claims. [Disposition validation](../../src/domain/reference_disposition_validation.zig) and reconciliation validation enforce membership, valid targets, reciprocity, cycles and coverage. | Preserve legitimate empty conflict sets. A present conflict needs valid related members. Existing feasibility guidance must remain derived from the relationship owner; this review does not authorize automatic disposition selection. |
| Source/principle review membership | **Closed in C2b:** model-facing batch collections are gone. [Shared collection validation](../../src/domain/specification_support.zig) binds one native subject per response, validates produced findings and checks the final complete set. | Preserve focused repair, origins, freshness and whole-review routing. Extend resource and live evidence; do not restore batch slots or remove defensive canonical membership checks. |
| Source-review evidence/applicability — response cutover in §15.7 | [Evidence admission](../../src/domain/specification_support_evidence.zig) enforces subject-specific eligibility and exact candidate evidence. The packet fixes `finding` or `applicability_finding`; the response has no `provenance`. | Keep semantic verdict and loss-location choices, source-only negatives and distinct principle citations. Reject an unbound positive instead of deriving support from eligible claims. |
| Review detail/question text | Shared `detail_value` allows empty negative explanations. `question_value` rejects empty strings locally but permits whitespace. Schema length counts characters; [clarification text](../../src/domain/clarification_inputs.zig) limits UTF-8 bytes and controls. | Preserve existing required/forbidden question variants and permitted empty positive detail. Test empty, blank, control-containing and multibyte text; do not claim a character minimum proves usefulness or byte-bound conformance. |
| Principle citation conditions | [Principle admission](../../src/domain/principle_assessment.zig) requires citations for negative decisions and validates selected chunks, line bounds and uniqueness. Initial and evidence-repair schemas still permit empty citations and broad IDs/ranges. | Derive retained-decision requirements and eligible chunks from the same owner. Compatible findings may legitimately omit citations. Valid coordinates do not prove that cited policy supports the verdict. |
| Rubric evaluation | [Packet schema](../../test/harness/packet.zig) derives structural fields from the judgment type but is not specialized to the captured rubric. It permits empty results, arbitrary criterion/document IDs, invalid score/disposition combinations and insufficient evidence. [Judgment validation](../../test/harness/judgment.zig) rejects them. | Exercise the grading boundary even while production generation is blocked. Preserve rubric-owned scoring, applicability, exact-quotation checks and native totals. Invalid judgment currently terminates evaluation; this review grants no new evaluator retry or authority over workflow completion. |

**Repairs are part of each row.** A selected repair knows its target, retained
decision and permitted evidence before calling the model. Use those facts through
existing packet/schema owners. Broad citation, text, provenance and principle
selection replacements can repeat the same defect. Existing exact/passive choice
restriction, claim-required source selection and question variants are useful
conformance examples to preserve, not reasons to create another repair path.

**Provider constraint fidelity is a separate boundary.** The current
[Bedrock projection](../../src/domain/model_schema_projection.zig) omits string-length
and numeric-range bounds and array maxima; a positive array minimum becomes `1`.
Enums and required object properties remain. The complete selected schema stays in
guidance and local validation. Therefore a local schema fix does not automatically
become provider enforcement. Inspect actual wire schemas in regressions; do not
add unsupported provider keywords or weaken complete validation. This is a
projection of one authority, not a second acceptance policy.

#### Feasibility corrections required before implementation

1. **Conformance is per rule, not schema/native equivalence.** For each proposed
   restriction, identify its accepted owner, exact subject/scope, lawful exceptions
   and where it can be represented. Prove that authorized valid candidates remain
   expressible and that the intended impossible choices reject. Native validation
   remains decisive for cross-entry relationships, byte/control rules and meaning.
   Do not turn the inventory into a new runtime rule registry or validator copy.
2. **Presence tightening changes the recovery path.** An empty field rejected by
   the selected schema no longer reaches atomic native repair. Existing protocol
   correction replaces the complete assigned response/part. Its instruction asks
   to preserve unaffected content, but no individually valid fields of that rejected
   response have been admitted or frozen. Test dropped/changed siblings, successful
   complete correction and exhaustion; do not promise mechanically unchanged siblings
   inside an invalid batch. Already admitted independent parts and native repair
   siblings retain their existing protection. Retry limits/accounting ownership stay
   fixed, but observed protocol/native counts and token costs can change.
3. **The focused format/execution cutover is implemented.** Initial review now
   selects the canonical named finding definition and attaches the assigned
   identity natively. Preserve that coordinated boundary in further changes. A
   single finding is not a restriction of the old batch shape; do not restore its
   decoder or treat initial generation as repair of an artificially empty review.
4. **Keep semantic choices distinct from computed facts.** Existing selector APIs
   do not express every conditional evidence rule. For remaining semantic choices,
   use supported schema projections and native relationship validation; do not
   enumerate every valid combination or create a general conditional-schema engine.
   Remove uniquely determined fields through their owning contract instead of
   asking the model to reproduce them under larger constraints (§7E–F).

#### Focused semantic assignments — shared contract

The user-selected direction replaces the expanded batch-slot proposal. Native
binding and assembly use existing owners; live cost and semantic effectiveness
remain unproven. C2a specifies the closed response/progress contract used by C2b.
The approved focused amendment touches
[§12.7](../../design/contracts/12-model-boundary.md#127-workflow-defined-model-operations)
and [§22](../../design/contracts/22-repair.md), including partial-review validation and
stable retry scope. It must preserve §12.8.1's complete-findings routing and the
§§6–7 action/runner boundary; this document does not amend them implicitly.

| Boundary | Required ownership and behavior |
| --- | --- |
| Determine work | Native review/evidence owners derive the required subject set, purpose and fixed applicability from current authority. Code selects the next pending semantic assignment. No model-generated identity, count, collection position or completion flag. |
| Prepare one assignment | Reuse the shared review packet and canonical `finding`, `applicability_finding` or `principle_finding` definition. Supply the subject and necessary source/policy context; return only its semantic result and evidence selections that require judgment. A focused target does not justify hiding related requirements or contradictions. |
| Execute | Coordinate existing request actions through runner-owned bindings and declared typed progress outcomes. Follow the existing extraction/generation progress-loop pattern; do not add a dispatcher, hidden action-to-action/model loop, runtime graph expansion per subject or another retry mechanism. Start serially. |
| Admit and retain | Validate one result through the existing review/evidence owners and attach the exact bound subject natively. Retain validated results and any current rejected candidate as distinct typed progress. Unvisited assignments are pending work, not missing-finding defects. A well-formed negative finding is valid review data, not a positive verdict or an immediate clarification. No partial salvage of an invalid response. |
| Complete | Assemble the native collection deterministically and run existing complete-set, relationship and evidence validation before advancing. Code proves required membership, not semantic truth. No model JSON reassembly call, native-to-JSON reassembly API or second completion authority. |
| Repair or fail | Protocol correction replaces only the current focused response. A schema-valid/native-invalid finding enters existing authorized field/evidence repair, retaining its verdict and old-value preconditions. Retire each request through the existing lifecycle before the next assignment. Earlier accepted results retain provenance unless dependencies invalidate them. Preserve bounded retries and actual-token accounting; failure grants no clarification/publication permission. |
| Renew and read back | Bind subject, purpose, candidate/evidence revision and selected schema through existing request/dependency owners. Rebuild affected results after authority changes. Validate canonical native evidence on readback; a model-format change alone does not require a new persisted mapping, state version or reader. |

**C2a — approved and applied 26 September 2026.** The governing §12.7/§22
contract now requires:

1. A review owner selects the next subject from its existing ordered native
   ledger and binds its typed `required_authority.Id`, review purpose, immutable
   parent and current dependency snapshot. Initial source-preservation,
   candidate-support and principle calls return one selected `Value`, using the
   existing `finding`, `applicability_finding` or `principle_finding` definition.
   The response contains no `entries`, ordinal, assignment ID, completion flag or
   native applicability choice already fixed by policy. The packet, selected
   schema and decoded value must refer to the same subject.
2. The review owner retains a working collection with pending native subjects,
   accepted values and their response origins, and at most the current rejected
   value. It validates every produced value and its dependencies immediately;
   pending subjects do not emit `missing_finding`. A native-invalid value enters
   the existing authorized atomic repair *before* the next subject. Only after
   every subject is accepted does the existing complete-set validator assemble
   canonical evidence and permit authority advancement. Negative and inconclusive
   findings remain review data and follow the existing complete-review routing.
3. An initial request's immutable assignment is the current review purpose and
   native subject under its existing parent. The review packet owner derives one
   ASCII slot from a purpose prefix (`source-preservation`, `candidate-support`
   or `principle-consistency`) and the lowercase SHA-256 digest of the canonical
   typed `required_authority.Id` snapshot, using the existing atomic snapshot
   encoder. Bind that same slot as `review_slot_id` and semantic-review purpose;
   it fits the existing 128-byte identity bound. Do not key it by response ordinal,
   attempt, revision or mutable text. Check the exact
   current dependency binding separately, so recycled subject IDs cannot admit
   stale results. Keep the collection's original native-candidate origin fixed
   from the first admitted response and retain each finding's own origin through
   repair. Dependent rebuilding also retains the pending parent defect key.
4. The existing runner owns attempt admission, global actual-token accounting,
   retry counters and request retirement. Release an accepted or repaired request
   before selecting another subject. Protocol correction stays on that subject;
   native repair stays on its authorized value/field, with old-value and revision
   preconditions. Repeated unresolved failures exhaust their current allowance;
   an independently successful subject permits further work within the finite
   configured budget. Cancellation, exhaustion, stale data and budget rejection
   cannot complete or publish either specification or clarification.

This replaces model-facing batch review responses and their insertion-only
recovery path, not the canonical `Review`/membership check needed for readback or
legitimate native repair. It does **not** permit verdict reassessment, invented
citations, partial publication, new retry authority, or a budget reset.
The selected schema changes the initial response contract; working-review repair
changes when the §22 authorization is valid. Both amendments were approved and
applied with the coordinated cutover in [§12.7](../../design/contracts/12-model-boundary.md#127-workflow-defined-model-operations)
and [§22](../../design/contracts/22-repair.md).

**C2b implementation checkpoint — preserve these mechanisms:**

| Former gap | Current implementation and remaining verification duty |
| --- | --- |
| Working-review repair | `validateWorking` calls the complete validator and defers only unvisited-subject omissions. Existing authorization/merge uses the working candidate and exact diagnostic; accepted verdicts and siblings remain fixed. Extend multi-finding failure/cleanup evidence rather than designing another validator. |
| Finding versus workflow outcome | Well-formed negative/inconclusive findings are retained. Existing authority reconciliation routes the complete collection, preserving candidate-defect precedence and the source-to-principle gate. A cursor or one valid user question cannot authorize publication. |
| Coordinated response cutover | Preparation, closed single-value decoding, source/principle prompts, selected definitions and the shared subgraph now use focused responses. `finding` versus `applicability_finding` follows the native subject. Keep canonical membership validation/readback; do not restore the superseded batch decoder. |
| Progress, identity and retirement | Existing review progress and registered bindings publish pending/accepted/rejected outcomes. YAML retires each request before continuation; subjects increase loop visits rather than compiled graph nodes per subject. Verify cancellation, dependent renewal and finite execution guards with larger sets. |

The request's stable native identity must distinguish pending subjects at the same
call site. Equal counts/ordinals are insufficient: changed records can reuse an
ordinal for different content. Preserve exact dependency binding and deterministic
native order; schema serialization, field ordering or a changed invalid answer
must not reset allowances. Duplicate delivery must not create another finding or
overwrite a conflicting result. Reuse existing envelope placement rules, without
adding a persisted queue, checkpoint or second result registry. Fresh invocations
still start at `start`.

Before C2b the packet owners bound the whole review to `source-support` or
`principle-consistency`; looping those identities unchanged would share one protocol
allowance across subjects. `reviewSlot` now derives the focused unit from the typed
subject and review purpose under the current parent authority. Retry identity remains
stable across revisions/corrections, while the exact dependency binding rejects
stale data. Existing native repair also includes the collection's original origin
in its scope; C2a defines a retained first origin for incremental production, rather
than replacing it with each latest response. Preserve per-finding origins, including the initial
finding and subsequent repair chain, through existing evidence/logging owners.
Keep dependent-rebuild requests bound to their pending native parent defect key;
new assignment IDs cannot create extra retries for that defect.

Retention is not permission to carry every intermediate allocation indefinitely.
[`retained_candidate.Storage`](../../src/application/retained_candidate.zig) retains
declared parent values; repeated full-array rebuilds can retain growing histories.
Measure live retained memory and teardown, and test allocation failure/cancellation
after several findings. Reuse ownership and envelope freshness checks; do not
weaken captured lineage or add a second cache to make the loop work.

Derive assignments from the existing authority projection. With no selected
principle chunks, [`principle_assessment.project`](../../src/domain/principle_assessment.zig)
creates no policy requirements and native review advancement skips the call.
Preserve this zero-work path. Never replace a required semantic assessment with a
manufactured compatible verdict, even if its identity/evidence can be calculated.

The shared mechanism must accept typed assignment facts from each domain, without
workflow-name branches or a global table of semantic rules. Spec source and
principle reviews are the first consumers. Prove reusable scheduling/binding with
an unrelated registered consumer; do not claim future Plan/Tasks integration from
Spec tests. A coherent assignment can contain several related fields or an unknown
semantic list. Avoid an indiscriminate call per JSON property.

**Schema-size check:** compact UTF-8 serialization of the retained provider schemas
and their existing finding subtrees gives:

| Captured review | Subjects | Existing array schema | Existing single finding value | Superseded inlined batch slots |
| --- | ---: | ---: | ---: | ---: |
| [Source, call 14](../../zig-out/e2e-spec/2026-09-26T07-08-12Z-d5ea99a5e3ff77dc8adf92dd7c58e810/evidence/generation/call-000014/request.json) | 18 | 9,686 | 9,412 | 169,945 |
| [Principles, call 15](../../zig-out/e2e-spec/2026-09-26T07-08-12Z-d5ea99a5e3ff77dc8adf92dd7c58e810/evidence/generation/call-000015/request.json) | 15 | 703 | 429 | 6,901 |

The single-finding column is the pre-cutover `entries.items.properties.value`
projection; the implemented request measurement follows below. The superseded experiment repeated that shape under required
`slot_1` through `slot_N` keys inside `entries`. That expansion was never an
implemented format, compiled graph, live call or token estimate. Prompt/evidence and the separate
guidance schema are excluded. A focused schema is smaller here because it removes
the batch wrapper/identity, but source evidence still makes the finding complex.
Removing further fields needs the owning derivation contract, not a size target.

**C2b compiled-request measurement (offline fixture, 26 September 2026):** The
implemented shared review path compiles to 720 operations (717 before this
cutover). A compatible fixture prepared 16 source requests totalling 339,455
wire bytes and 13 principle requests totalling 47,981 wire bytes. The selected
schema is 11,683 bytes for a source finding and 567 bytes for a principle
finding; repeated selected schemas account for 194,299 bytes across those 29
requests. These are first-attempt serialized request sizes, not provider tokens,
live cost or a quality result. The user accepted the higher call count; the
finite configured token budget and existing retry allowances remain unchanged.

**C2a offline request projection:** The two captured complete wire requests total
75,872 bytes (36,180 source; 39,692 principle). Holding their evidence and current
guidance fixed, selecting one requirement and replacing both schema copies with
the existing `value` subtree yields 18 projected source requests totaling
525,739 bytes (29,129–29,369 each) and 15 principle requests totaling
542,775 bytes (36,169–36,199 each): **1,068,514 bytes across 33 calls**.
This is a serialization projection, not a compiled focused packet, provider token
estimate or latency result; the eventual concise prompt and exact selected
schema may change it. It exposes the main risk: repeated evidence dominates the
saved bookkeeping. C2b's actual prepared-request measurement is recorded above;
retained-memory measurement remains open before live execution. Obtain a separately approved finite budget appropriate
to measured quality and cost. Do not solve the projection with hidden batching,
truncated evidence or another context authority.

**Quality leads; measure the resources it requires.** Reusing a compact schema across requests
avoids per-subject schema expansion; it does not avoid repeated input or provider
latency. Applied literally to the captured candidate review, one call per subject
means **18 source + 15 principle = 33 initial calls instead of two**, excluding
repairs and other stages. This is a call-count calculation, not a token estimate.
The last principle stage consumed 79,751 tokens, including ten repairs (§10).
Fifteen focused calls carrying the same large policy context could cost more.
The approved C2a boundary selects one native subject and retains its required
context; measure the implemented aggregate resource cost. Do not silently group rows or infer their semantic association;
if a cohesive assignment needs several results, specify its native binding explicitly.
Measure complete guidance, evidence, native schema, calls, actual tokens,
latency, allocation and retained-result growth for both purposes and larger unrelated
sets. Round-trip selected schemas through capture/debugger compilation. A higher
finite budget is acceptable when measured quality supports it; exceeding the old
100,000-token baseline alone does not invalidate the design. Record the selected
generation and grading budgets before an approved run and enforce each through
its existing accounting owner. Do not raise a limit automatically during execution,
add another budget source, increase retry allowances or truncate evidence.
Schema/resource bounds remain separate. Reduce context only where existing owners
establish that it is unnecessary; no hidden batching or concurrency.

Good quality means preserved source obligations, useful story/FR/AC, defensible
source and principle assessments, necessary clarifications only, and validated
publication/readback with rubric evidence. Valid JSON or successful joins alone
do not qualify. A larger budget can allow required work to finish; it does not
repair poor semantic decisions. Regress those decisions independently. Report
quality and cost together, identifying any budget difference in comparisons.

**Stop unproductive repetition through the existing progress owner.**
[§22.7](../../design/contracts/22-repair.md#227-repair-retry-limit-and-escalation)
already separates per-assignment protocol failure, per-defect native repair and
global usage. Preserve that separation:

- Repeated/alternating JSON, schema or missing-answer failures share the unresolved
  assignment's bounded allowance. New request IDs or changed error wording do not
  restart it.
- Native repair continues to another target only when its owning validator proves
  the selected defect resolved. A changed response, fewer diagnostics, extra tokens
  or an incremented revision is not progress. Required dependent review must finish
  before its parent repair can be considered resolved.
- Successful assignments and resolved defects retain their results and permit
  further work within the configured budget. Do not add a workflow-wide attempt
  limit that counts productive work as repeated failure.
- The global token limit is the cost backstop, not a semantic judge. It remains
  enforced and may stop even productive execution; a larger preconfigured budget
  can accommodate that work. No automatic replenishment or counter reset follows
  a success. Semantic quality remains with existing review and rubric evidence,
  without a new progress-scoring model or heuristic.

The retained run's eight successful finding insertions illustrate the distinction:
they were productive recoveries, although the initial empty batch was avoidable
and the workflow stopped at its budget gate without establishing final quality. Do not classify
all repair calls as stalled progress or infer useful final output from those repairs.
C2a/C2b record offline request bytes, call counts and clearly labelled projections
from retained evidence. Actual new token/latency/quality claims require separately
approved controlled calls and C4's whole-path run after implementation. Debugger
replays can test an individual response; they cannot establish native assembly,
dependency renewal or publication. No provider cache or setting change is assumed.

**Semantic risks remain open.** Literal-only content, valid citations attached to
unsupported prose, false conflicts/clarifications and incorrect positive reviews
can satisfy every mechanical constraint. Coverage records where evidence appears;
it does not prove that obligations, field purpose or source meaning survived.
Existing prompts already describe those duties. Scripted negative reviews prove
routing/containment, not that the model detects bad content. Separately approved
real-review observations must include poor-but-well-linked and valid candidates,
unrelated requirements, false acceptance and unnecessary rejection. End-to-end
rubric evidence then assesses the generated result. Do not add a keyword blacklist,
automatic verdict, generic prompt bulk or another reviewer. Known engine/candidate
failures must still terminate without becoming user questions.

**Preserved boundaries:** no inspected evidence justifies replacing selected-schema
binding, composition freshness, atomic repair, actual-token accounting, publication
gates or persisted revalidation. Readback rechecks mechanical authority; it does not
independently establish that a model-assisted verdict was semantically correct.
The evaluator keeps its separate rubric authority and cannot approve engine output.
Plan, Tasks and Implement remain proposed workflow work; reuse must be demonstrated
when their concrete model contracts exist, not claimed from Spec alone.

Two downstream integration boundaries need precise treatment:

- **Evaluator projection:** [`bedrock.request`](../../test/harness/bedrock.zig) currently
  sends the reflected judgment schema as both guidance and native structure; it
  does not use the workflow's provider projection. C3 must prove compatibility
  before reusing that projection. Adding unsupported score/string bounds directly
  to this wire schema, or copying a provider-keyword filter, is not a safe fix.
  Retain rubric-owned native checks where the existing profile cannot express them.
- **Readback already has a composed safeguard:**
  [`prepare_specification_output`](../../src/actions/specification/prepare_specification_output.zig)
  encodes canonical state and calls [`specification_state.parse`](../../src/domain/specification_state.zig)
  with the current contract source before publication. The
  [oracle](../../test/harness/e2e/oracle.zig) rereads disk bytes and requires exact equality
  with the prepared files; `workflow_state` is mandatory in every valid
  [E2E case](../../test/harness/e2e/contracts.zig). Together these prove persisted bytes
  match the state validated under that same contract. The earlier recommendation
  for an additional unconditional parse gate duplicated this check and is withdrawn.
  Fresh-runtime/current-contract revalidation, corruption and changed-authority
  rejection remain distinct readback tests. Reuse the existing parser/action if a
  separate direct inspection is needed; grading text alone establishes neither proof.

**Bounded follow-up sequence:**

| Chunk | Smallest cohesive work and exit evidence |
| --- | --- |
| C0 — Measured baseline (implemented) | Recorded scope: capture empty entity text/evidence and the empty-review → successful insertions → missing-answer recovery → budget-stop sequence. Include unrelated assignments, legitimate empty/source-only evidence and complete recovery within budget. Record the actual rejecting boundary. Add remaining inventory tests with their owning patches, not as one prerequisite test project. |
| C1 — Supporting presence conformance (implemented offline) | Unconditional required-text/citation minima now agree with native checks in shared initial/repair definitions; lawful empty collections and positive detail remain valid. The complete schema rejects empty required values, provider collection minima remain projected, and existing correction/accounting paths retain their authority. This does not remove deterministic model work, exact membership or native relational checks. |
| C2a — Focused assignment contract and cost (approved/implemented) | Recorded scope: specify native selection, compact response, working versus complete validation, authorized repair before completion, declared progress/retirement and exact request/result binding. Set stable assignment/collection-origin and pending-parent retry scopes; preserve negative-finding routing. Produce offline request/call measurements and labelled aggregate estimates, including the 33-versus-two call trade-off. Resolve the focused governing amendment and assignment/context boundary; propose a larger finite budget if needed for quality testing. No expanded slots or fallback. |
| C2b — Shared focused-review cutover (implemented offline) | Recorded scope: coordinate source-preservation, candidate-support and principle requests, prompts, schemas, decoding, native admission/repair and the shared runner subgraph. Test successful multi-assignment completion, malformed and native-invalid recovery, retained siblings, exhaustion, mixed gaps/defects, identity/retirement, renewal, zero-work, cleanup and stale readback. Remove superseded batch-only paths after auditing all producers; retain defensive native membership and reachable repair. No verdict reassessment or retry increase. |
| C2c — Remaining deterministic fields and semantic choices | Audit each returned field using §1's boundary: remove it when current authority determines its value; otherwise retain the semantic choice and project lawful options where supported. Cover §7A/B/E/F, extraction/reconciliation, assigned identities, constant/conditional fields and evaluator bookkeeping under §15; no deterministic residue is optional. Reuse each existing owner; no universal defaulting or citation-attachment service. Keep native-only relationships native. These distinct changes are not prerequisites to measuring C2b recovery. |
| C3 — Evaluation responsibility and conformance | Native criterion assignment/assembly, exact evidence reconstruction and conditional fixed values are required under §15, alongside schema conformance. Use existing judgment/capture/execution owners and resolve the provider-projection gap. Test scored/unscored decisions, occurrence selection and rejected evidence. Record the response/assignment amendment; no new retry authority. This track can proceed independently but is required for overall completion. |
| C4 — Whole-path effectiveness | Verify each implementation chunk with its owning regressions, measurements and registered full verification/packaging. Separately approve controlled semantic-review tests and live generation. Record budgets, actual tokens and latency; distinguish productive recovery from repeated unresolved failure and budget changes from design effects. Require useful story/FR/AC, source/principle assessment, validated publication/readback and rubric evidence. Higher budgets are acceptable for good quality, not evidence of it. |

**C0 regression baseline (26 September 2026):** The retained run above supplies
the observed sequence and exact 98,352 → 105,547-token stopping boundary. The
new `empty principle review can recover every assigned finding` test covers an
empty collection, ordered atomic insertions, preserved siblings and origins,
complete validation and readback for two unrelated requirements. The existing
`partial reviews retain all omissions` test covers invalid insertion, unchanged
correction and a separate successful recovery; `missing answers share protocol
allowance` covers absent final text, correction, exhaustion and exact usage; and
`dependent reviews retain parent allowances` covers successful independent work,
recurrence and a global budget stop. These are owning-boundary regressions, not
proof that the historical batch workflow would complete after the captured sequence.
C2b's focused production-path fixtures now exercise the new format. Preserve no
publication on budget/retry exhaustion and completion only after every required
finding validates; extend the remaining scale/lifecycle evidence in §14.

C0 establishes the first baseline; C2a's approved responsibility boundary and C2b's
focused implementation are present in the current worktree.
C1 is an implemented offline conformance improvement. C2b addresses the measured high-cost
failure class; it is not yet a demonstrated cost reduction. C2c and C3 are independent
tracks, not a requirement to rewrite every
model contract before another controlled test.
C2b removes review association bookkeeping; it does not by itself remove every
deterministic field identified in the inventory. Record any retained fields as
explicit C2c work until their owning contracts are changed. The target response
boundary above is the end state, not a claim that today's canonical finding already
contains only semantic work. A bounded patch may complete without the overall
responsibility-removal goal being complete.
Stop/revise a chunk when it changes valid accepted behavior, loses retained authority,
requires an unapproved representation or only shifts failure to a larger correction.
For responsibility-removal changes, identify the model-returned bookkeeping fields
removed and prove their replacements are computed from the same bound authority.
Schema tightening is justified by correctness; it is a separate result. Any
efficiency claim needs request bytes, actual provider tokens, call counts and
elapsed time, alongside preservation of semantic quality.

This documentation request does not approve a new response format, expanded repair
authority, verdict reassessment, provider-setting change or live call. Conformance
work must derive rules from existing accepted owners; changes to governing contracts
require their focused decisions. Phases 0–3 remain complete for their recorded scope;
the findings expand Phase 4's open readiness work. The original inventory review
made no code/test changes or test runs. The 27 September review's additional
offline checks and documentation validation are recorded in §14.

## 7. Required deterministic responsibility transfers, staged separately

The latest user direction makes every determined responsibility in this section
required for overall completion (§15). Separate chunks keep contracts reviewable;
they are not optional optimizations or dependent on a demonstrated live failure.
C is implemented, and §6.5 remains closed. A/B/E/F still need their concrete
response/ordering amendments before code changes; the scope mandate does not choose
those representations or expand repair authority.

| Item | Disposition and minimum evidence before implementation |
| --- | --- |
| A — reconciliation token metadata | Feasible because one preserved-token claim determines the token. Required cutover covers summaries, global signals, replacement, persistence and unchanged source review. Record the response amendment; a measured failure or cost saving is not a prerequisite to removal. |
| B — summary keys | Required removal of mechanical key/uniqueness work; settle the ordering contract first. Test shuffled arrays, insertion/deletion, stable retry identity and byte-stable state before removing keys/sort/repair together. No guessed semantic ordering. |
| C — review association and completeness | Implemented offline in C2a–C2b using native subject identity, selected finding definitions and runner progress. Model responses omit batch bookkeeping. Live effectiveness and resource evidence remain open; O2's ID restriction is a separate completed change. |
| D — diagnostic guidance | Known exact/passive guidance is complete in `ValueChoices.correction`; reuse it. O2's enum rejection uses the existing schema diagnostic/locator owner (§6.7). Further changes need a demonstrated missing native fact. |
| E — invariant empty response fields | Current generation and source-review admission reject nonempty `clarification_response_ids`. The required model-format cutover must omit the field and construct the native empty value. Apply across initial/repair consumers; retain rejection of nonempty persisted provenance. No legacy optional field, generic defaulting or rule imposed on other workflows. |
| F — exact review evidence already determined by native policy | Construct every list determined by full native provenance or an exact claim-set rule, including applicable localized-loss cases. Distinguish each conditional rule before removing its model field. Eligible subsets, selected sources and principle citations remain semantic. ADR 0020 did not approve this evidence-authority change. |

### A. Reconciliation token metadata

A preserved-token statement/signal already selects its single owning claim but
also returns its token ID. Existing validation derives the required token and
existing repair can correct that metadata. Removing the redundant model field is
feasible through the same principle: one semantic selection, native expansion.
Do not remove semantic retained/duplicate/superseded/conflicting decisions under
the pretext that their IDs are mechanically checkable.
The existing reconciliation repair already reconstructs a uniquely selected token
natively. Removing the redundant model field is a format simplification, not a
reason to add another resolver; cover statement/signal repair and snapshot readback
together under the required response amendment. The removal is mandatory; its exact
contract still needs to be recorded before implementation.

### B. Summary keys and ordering

`StatementProposal.local_key` is checked for uniqueness, has dedicated repair
cases, and determines sorting before native statement-ID assignment. Removing it
can eliminate a bookkeeping failure class, but requires an explicit ordering rule:
response-array order or a justified canonical order. Preserve occurrence-based
repair identity across insertion/deletion. Do not treat semantic equivalence or
desired presentation order as a numerical calculation. Remove the old key schema,
sort/key-repair branches and tests only with replacement evidence.

### C. Review assignment association

The engine already knows which subjects require review. The implemented cutover makes
that work explicit in native progress: select one semantic assignment, receive its
finding, attach identity and retain the validated result. The model does not plan
the collection or repeat its membership. Initial requests, working-candidate repair
and runner progress now use that binding pattern.

§6.9 C2a–C2b records this contract and its cost, freshness,
recovery and complete-set validation duties. The retained pre-cutover empty batch caused ten repair
calls and budget exhaustion; eight distinct findings were inserted successfully,
so this was not evidence of broken retry identity. Focused initial assignments
remove that batch-omission opportunity but can increase calls on a successful path.
Do not equate a smaller response schema with lower total cost or better meaning.

### D. Deterministic diagnostics

Report the exact rejected selection and missing relationship from existing native
facts. This is useful regardless of contract redesign. It should replace generic
wording, not become another policy table or an excuse to retain redundant response
fields indefinitely. Repeated-error feedback must use confirmed failure identity;
attempt count alone does not establish repetition.

Counts, citation unions, record IDs, JSON assembly and Markdown generation already
have owners. Improve conformance where needed; do not build duplicate versions as
part of this work. No evidence supports replacing semantic review with arithmetic.

### E–F. Keep model construction separate from persisted validation

E crosses the shared `Selection` type, initial requests, review/repair replacements
and closed decoding. Remove the superseded model key, including rejection of an
explicitly empty legacy field; construct only the empty native value authorized by
the new contract. Canonical `Provenance` remains separately validated. Do not strip
a nonempty stored value during a model-shaped projection and thereby accept it.

For F, [the evidence owner](../../src/domain/specification_support_evidence.zig) already
expresses derivability through `Requirements.rule(...).provenance` and `.claims.exact`.
Reuse those facts rather than a second table keyed by finding names. Some supported
aggregate subjects have no fixed provenance; independently selected `source_ids`
can include more than the required producer sources. Record evidence also spans
all its values, including Given/When/Then; do not invent a narrower per-field scope.
Invalid loss attribution, stale producers and invalid supplied selections still
reject. Fixed-evidence derivation cannot make a verdict deterministic or repair it.

[`validateStored`](../../src/domain/specification_support.zig) currently reconstructs
model-shaped findings from canonical evidence. E/F must preserve its native
validation and complete-evidence comparison: recompute expected facts to detect
corruption, never overwrite persisted evidence to make it valid. Retain repairs for
genuinely selected claims/sources/principle citations; remove only branches made
unreachable by the approved cutover. Test both boundaries and equivalent accepted
native results before removing a field. These are required, bounded decisions under §15, not a defaulting/auto-citation
framework. They do not reopen completed C2a/C2b.

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
| One handle in model/canonical text; retain explicit selection and derive effective provenance | Approved and active under ADR 0020. Meets the intended model with one selection authority; §6.5 conformance was closed in Phase 2. |

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

## 9. Approved Phase 0.2 decision

The user approved the focused contract on 26 September 2026. [ADR 0020](../../design/decisions/0020-derived-exact-reference-lineage.md)
is the governing authority for the exact claim handle, explicit versus derived
lineage, bounded value-only repair, version cutover, readback and failure
precedence. §§5–8 record the analysis behind that decision; they are not a
second implementation policy. The current runtime uses the new format; Phase 2
conformance did not restore or authorize the old one.

ADR 0020 approval does not grant broader coupled evidence changes, verdict reassessment,
multiple-ledger attribution, zero-scope typed text, reconciliation-token or
summary-key removal, or review execution/response redesign. The later C2a amendment
separately approved the focused review contract, now implemented in C2b. Other
extensions remain separate decisions
if later work needs them. In particular, the bounded invalid-handle baseline
cannot acquire a fresh claim from the whole assignment catalogue on retry.

## 10. Phased rollout with testable checkpoints

**Phases 0–3 and the Phase 4.1 diagnostic batch are done; Phase 4.2 remains open after a failed run.** The approved contract
activated at the coordinated Phase 2 format cutover. The original rollout has five
phases and eleven chunks; §6.7 records the implemented O2 follow-up and its open live gate. Each chunk produces a reviewable diff, named regression evidence and a
recorded proceed/revise decision. §11 supplies the common acceptance matrix;
passing a safe-block test must never be reported as successful recovery.

Phase 1's independent owner refactor and Phase 2's coordinated format activation
and conformance checks are complete. Do not
reintroduce temporary runtime flags, dual readers, skipped tests or pair/handle
conversion adapters to make individual fixes appear smaller.

**Next evidence order:** verify the implemented C0/C2a/C2b baseline, extend its
resource/lifecycle evidence and measure live semantic quality and provider tokens
only with separate approval. C1's presence fixes, other conditional choices and grading remain separate;
do not turn the inventory into a prerequisite system rewrite. Each implemented
chunk requires its own complete verification before separately approved live
measurement. The empty-review sequence and inadequate positive review are required
cases, with different mechanical/semantic evidence. Missing-answer behavior retains
the independent §6.8 diagnostic path.
The completed diagnostic batch and retained E2E executions grant no further calls.

Every follow-up has a failing regression at its owner, an unrelated accepted case
and a reject case. The repairs above implement existing ADR 0020 authority. Broader
evidence expansion and §7 changes remain separate decisions; the approved numeric
restriction contract is recorded in §6.7 and design §§12.2/22.6.

### Phase 0 — Establish evidence and settle authority

**0.1 — Baseline and failure-class regression — done.**

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

**0.2 — Approve the closed contract and repair table — done.** Depends on 0.1.

- **Outcome:** resolve §9 through the named governing contracts: shared claim handle,
  explicit selection versus derived lineage, version rejection, and §5.5's approved
  invalid-handle bound. Specify each repair's target, fixed facts, permissible change,
  comparison and dependent validation. Identify tuple-specific authority to retire.
- **Checks:** trace initial generation, value/provenance/coupled/membership/omission
  repairs, positive/negative review and both state variants against that table. Work
  through reference addition/removal, invalid `S`, unavailable `L` and reordered text.
- **Exit/revise:** explicit approval and unambiguous accepted/rejected examples are
  required. If a case needs broader authority, expose that decision; do not defer it
  to request-building code. No new provider mode, workflow or retry policy is included.

**Phase 0 complete (26 September 2026):** 0.1 has the baseline regression and
measurements below. The user approved 0.2; ADR 0020 records the decision and
accepted/rejected repair examples. The retained
[failed run](../../zig-out/e2e-spec/2026-09-25T08-21-44Z-b16638b5493910a4b1d29436213dcde9/report.md)
has 13 accounted calls, 18,512 actual tokens, two story-repair executions and no
publication or rubric grade. Its requests measure:

| Assignment | Serialized Bedrock request bytes | Prompt schema bytes | Actual input / total tokens |
| --- | ---: | ---: | ---: |
| Brief initial, call 9 | 10,242 | 3,927 | 1,583 / 1,763 |
| Brief repair, call 10 | 5,107 | 837 | 976 / 1,270 |
| Story initial, call 11 | 7,529 | 2,115 | 1,282 / 1,462 |
| Story repair, calls 12 and 13 | 5,850 each; byte-identical | 837 each | 1,132 / 1,661; 1,132 / 1,297 |

These are retained-run measurements, not model predictions or before/after
improvement claims. The failed run had no separate protocol-correction call; its
prefix normalizations stayed in the existing decoder. Existing fake-provider
[protocol correction tests](../../src/model_request_workflow_test.zig) retain the
selected schema and original request identity. The current Spec graph has 717
compiled operations under the [root compilation test](../../src/composition/root.zig);
the retained run does not separately report a compiled graph count. The new
[generation regression](../../src/specification_generation_test.zig) exercises the
same invalid exact join, unchanged repair response and exhaustion for two unrelated
requirements; it also checks bounded native recovery and keeps mechanical text
acceptance distinct from semantic adequacy. The existing meaningful-content test
in that owner covers source obligations, requirements, criteria and rendering.
§11 lists the later contract tests.
`zig build test-specification-generation` and the full
`zig build verify --summary all` passed (126/126 steps, 1,248/1,248 tests,
including packaged smoke checks). `git diff --check` passed. These offline
checks do not establish live model quality or implementation of the approved contract.

### Phase 1 — Remove coupling without changing behavior

**1.1 — Refactor the existing reference owner — done.** Depends on Phase 0.

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

**Phase 1 complete (26 September 2026):** `reference_support.select` now accepts
claim IDs and returns reference-owned claim, citation and scope facts. Spec
generation and review evidence adapt these facts under their existing eligibility
rules; neither schema nor request text changed. The old Spec-type import is gone.
Reference tests cover ordering, duplicate/foreign claims, stale state, invalid
scopes and allocation cleanup. The architecture test forbids Spec imports in the
shared owner, and review tests reject clarification-response support. The targeted
reference, Spec, typed-text and architecture suite passed (545/545 tests). The
complete verification, including packaged smoke checks, passed. This is an
ownership refactor; ADR 0020's exact-handle runtime behavior begins in Phase 2.

### Phase 2 — Implement one coordinated format change

**2.1 — Native handle resolution and lineage construction — done.** Depends on 1.1.

- **Closed scope:** fix owned-buffer cleanup in `reference_support.lineage` and
  test failure after successful allocation and during growth. Existing `select`
  cleanup and the active handle contract remain intact; no new lookup owner.
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

**2.2 — Requests and configured schemas — done.** Depends on 2.1.

- **Closed scope:** the earlier post-cutover run in §2 exposed an unconditional exact-copy
  instruction in a string-only repair. Replace it consistently in the existing
  purpose prompts. Also restrict offered exact/passive replacements from the same
  authorized owning-unit facts used by native validation, preserving broad source
  context. Verify emitted initial/repair/omission/correction requests with available,
  empty and foreign choices. No new repair or schema authority is needed.
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

**2.3 — Repair, coverage and dependency renewal — done.** Depends on 2.1–2.2.

- **Closed scope:** the three repair discrepancies in §6.5. Use complete owning
  evidence for omission authorization and choices; validate the selected retry
  target under that context; reconstruct derived order after an authorized merge
  while preserving effective sets. Keep unrelated sibling failures independent.
  Cover shared records and `S=[]`, not only attributed fields with explicit support.
- **Outcome/owners:** adapt native and coverage repair through their existing atomic
  authorizations. Retain the original approved invalid-handle baseline across attempts
  while updating expected value/revision. Compare effective evidence where required;
  keep coupled, membership and reviewed-insertion policies distinct. Update native
  exact reconstruction and remove the obsolete tuple-specific trigger/guidance.
- **Checks:** unknown handle → bounded valid replacement; unchanged/alternating errors
  → exhaustion, including §2's changed-prose/moved-reference recurrence under one
  target identity. Adapt the retained failure to the new handle contract rather
  than preserving the old tuple as an accepted format. Invalid `S` → its authorized
  recovery or block. A later rejected handle cannot enlarge the original bound.
  Reordering preserves evidence sets;
  adding/removing dependencies outside authority rejects. Verify siblings, origins,
  full-unit validation, dependent rebuilding and exact usage/retry accounting.
- **Exit/revise:** include a repair that passes its field but fails later coverage,
  proving no publication, alongside real bounded recovery. Missing/corrupt trusted
  bindings terminate without another model call. If recovery needs new authority,
  return to 0.2 rather than weakening equality or increasing retries.

**2.4 — Review, rendering and persisted readback — done.** Depends on 2.1–2.3.

- **Closed scope:** carry the full owning record's resolved evidence through
  per-field rendering. Add a mixed-field regression that reaches projection,
  complete-state encoding/readback and rendering comparison. Preserve strict
  intrinsic readback and already projected positive-review evidence. The projection
  patch can be developed first; closing this checkpoint requires repaired-flow tests.
- **Outcome/owners:** coverage, source/principle evidence, projection and completed
  state consume the same derived lineage. Preserve negative diagnostic eligibility.
  Update affected version contracts and pending-state handling together; pending
  state still does not store attributed specification content.
- **Checks:** meaningful fake-provider output reaches generation, coverage, semantic
  routing, publication and readback. Corrupt handles/selection/review projections
  reject. Test old versions, both current state variants, exact Markdown expansion,
  clarification failure precedence and downstream gates. A trusted-join pass cannot
  turn an inconclusive finding into a user question or completion.
  Include §2's correctly linked but literal-only entity basis and repeated
  Given/When/Then; test semantic rejection routing separately from native entity
  membership, alongside meaningful successful output.
- **Exit/revise:** every producer/consumer in §6 agrees; superseded formats, readers,
  tuple-only repair branches and fixtures are removed. Keep negative tests that reject
  old shapes. Any readback discrepancy blocks the whole Phase 2 change. No live
  readiness claim until Phase 3's integration gate passes.

**Phase 2 complete (26 September 2026):** Spec exact segments select one
preserved-token claim; the reference owner resolves its bytes and the provenance
owner derives effective claim and citation lineage from the complete field or
shared record. Generation and repair use the same handle in their configured
schema and request choices. Value repair retains its original evidence bound
across retries; coverage, positive review evidence, rendering and completed
readback consume derived lineage. The tuple-specific coupled repair and old
accepted wire/state versions were removed. The §6.5 follow-up resolves record
evidence once for field projection, omission authorization and selected retry
validation. Authorized completed-value edits reconstruct derived citation order
and compare evidence sets before full validation; readback rejects corrupt stored
projections. Fixed repair packets restrict exact and passive choices to their
bound, and purpose guidance no longer instructs string-only repairs to insert
reference IDs. Shared lineage frees its buffer on allocation failure.

Regressions cover mixed prose/exact scalar and relationship-array fields through
rendering and completed-state readback, tampered citations, sibling-derived and
empty-explicit evidence, omission packets and repairs, reordered citations,
unauthorized scope expansion, selected
retry progress despite a bad sibling, and allocation failure during lineage growth.
`zig build test-specification-generation test-reference-reconciliation --summary failures`,
`zig build verify --summary failures` (including native packaging smoke) and
`git diff --check` pass. These offline checks establish contract conformance, not
live semantic quality. Phase 3's independent cross-workflow integration and
comparative request/resource measurements are recorded below; Phase 4 owns
approved live tests.

### Phase 3 — Prove reuse and integration offline

**3.1 — Independent consumer and cross-boundary regressions.** Depends on Phase 2.

- **Outcome/owners:** prove the §6.4 contract through a test-owned registered non-Spec
  consumer with different fields and eligibility, using the same reference mechanism
  and existing runner/composition. Add no production demonstration workflow/framework.
- **Testable parts:** first compile/run that independent typed consumer with an
  isolated registry; then compose it with retained-part freshness and failure
  propagation tests. Extend the existing request-workflow tests for the retained
  Spec failure sequence instead of inventing a second provider/retry test harness.
- **Checks:** nested/array/optional typed fields, no-reference workflows and mixed
  domain evidence retain their boundaries. Sliced results, renewed dependencies,
  stale reads and operational IDs behave correctly. Combine successful assignments
  with repeated/alternating protocol and native errors under the global budget.
  A changed replacement with an unresolved target must retain its retry count;
  exhaustion must prevent both specification and clarification publication.
  Include §2's combined sequence: earlier native repairs succeed, a missing answer
  recovers within its request, then a different native assignment exhausts.
  Also cover the post-cutover sequence: wrong-kind exact selection, a repaired
  title after missing-answer recovery, then description protocol exhaustion before
  any native replacement. Keep those two exhaustion boundaries distinguishable.
  Extend it with the `01-21-50Z` run's eight successful native targets, each requiring
  missing-answer correction, then a ninth target's protocol exhaustion. Preserve
  completed siblings, per-assignment retry identities, fixed evidence and exact
  accounting. Include a correct exact handle with `S=[1]` that needs no provenance
  repair but supplies only a literal: native acceptance must not stand in for
  semantic review or convert an interpretation defect into a user clarification.
  Alongside containment, require meaningful recovery through FR/AC generation,
  coverage, source/principle assessment, publication and readback. A fake semantic
  review demonstrates routing only; it does not prove the model's judgment.
- **Exit/revise:** the independent consumer's integration and negative tests pass
  without Spec/session imports or workflow-name branches. This proves a reusable contract, not completed
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
- **Measurement method:** use equivalent assignments with the same source ledger,
  explicit evidence and repair scope. Record complete request/schema/output bytes,
  graph operations, native elapsed time and allocator counts/peak bytes for small
  and larger ledgers. Include the repeated lineage work identified in §6.5 and
  distinguish cumulative arena allocation from retained output. Historical coupled
  repair versus current value-only repair is not an equivalent before/after pair;
  keep those figures descriptive. Use retained baseline artifacts, not a legacy
  runtime path. Report initial generation and repair/correction costs separately,
  including missing answers; §2 records the latest observed costs. Do not infer
  tokens or semantic quality from byte reductions.
- **Exit/revise:** all applicable tests pass; no unexplained request/resource growth
  or additional orchestration/model call is accepted as automatic simplification.
  Bytes are not token counts. Offline usage fixtures prove accounting only; record
  actual model tokens in Phase 4. Failed checks reopen the owning chunk, not the judge.

**Phase 3 complete (26 September 2026):** A test-owned registered audit consumer
uses the normal compiler, sliced JSON runner and `reference_support` with its own
typed memo/check schema and eligibility rule. Its nested optional and array fields
accept valid lineage, reject a valid handle in a forbidden field and reject stale
ledger identity. It checks part producer IDs and accounted tokens. No Spec session,
workflow-name branch or second resolver was added. Existing no-reference composition,
retained-part freshness, protocol retry and operational-ID tests still pass.
The Spec runner now includes eight distinct repaired targets that each encounter
one missing final answer, followed by a ninth target that exhausts its own retry
allowance. Earlier successful work remains accounted; the terminal run publishes
neither specification nor clarification. Existing positive Spec scenarios exercise
requirements, acceptance criteria, source/principle review, publication and
completed readback. A correct exact handle with inadequate business text remains
a semantic concern, not proof of quality from native validation.

Retained [Phase 0 baseline](../../zig-out/e2e-spec/2026-09-25T08-21-44Z-b16638b5493910a4b1d29436213dcde9)
and [post-cutover run](../../zig-out/e2e-spec/2026-09-26T01-21-50Z-aa8fda0613a0159cf267a5c7f8ff35c8)
were measured from their generation evidence. Schema bytes below are the compact
UTF-8 serialization of `response_format.json_schema.schema`; output bytes are
the retained final-text file, or zero when no final text was returned.

| Assignment | Baseline request / schema / output bytes | Current request / schema / output bytes | Interpretation |
| --- | ---: | ---: | --- |
| Brief initial | 10,242 / 3,012 / 571 | 9,740 / 2,824 / 386 | Same case and purpose; changed response contract and model output. |
| Story initial | 7,529 / 1,642 / 156 | 7,426 / 1,548 / 140 | Same case and purpose; changed response contract and model output. |
| Brief repair versus current correction | 5,107 / 616 / 181 | 3,984 / 133 / 171 | Different authorized scopes; descriptive, not a reduction claim. |
| Records initial | No comparable baseline call | 18,803 / 5,914 / 578 | New work reached after the baseline stopped. |
| Records correction | No comparable baseline call | 5,700 / 133 / 171 (call 21); 5,698 / 133 / 0 (call 29) | Missing final answer is counted, not treated as JSON. |

The compiled Spec graph remains **717 operations**. Over 100 repeated complete
lineage/select derivations with valid one- and 16-claim ledgers, the reference-owner
test measured respectively **500/500 allocator calls**, **40/640 bytes retained
after derivation**, **240/1,762 bytes of peak arena capacity** and **41.0/41.7 ms**
on this development machine. Arena capacity includes allocation overhead and
intermediate work; it is not the retained output size. The retained bytes scale
with selected claims; these timings are not a cross-machine latency promise. The
test frees every measured allocation and retains allocation-failure coverage. The historical
runtime has no equivalent ledger benchmark, so these figures are current-resource
evidence, not a before/after performance claim. The initial requests did not grow;
the repair shapes are not equivalent and cannot establish cost or quality gains.
Phase 4 must measure actual provider tokens and semantic outcomes. No live provider
call or E2E run was made for Phase 3. `zig build test-model-request-workflow
test-reference-reconciliation --summary failures`, full `zig build verify
--summary failures` (including packaged smoke), and `git diff --check` passed.

### Phase 4 — Measure live effectiveness with separate approvals

**4.1 — Controlled assignments: done, adverse results.** Depends on 3.2 and explicit call approval.

**Approved diagnostic batch completed (26 September 2026):** all eight calls in
the [proposal](../../zig-out/llm-rework-phase4/diagnostics-2026-09-26/proposal.md)
were dispatched once, consuming **12,034/100,000 tokens**. Six exact replays matched
the captured wire bytes; two loan-brief observations reused the existing offline
request projection with unchanged prompt/schema/model settings.
The [results and raw-evidence links](../../zig-out/llm-rework-phase4/diagnostics-2026-09-26/report.md)
retain all attempts, token counts and exchange timings.

- Title repair, title correction and outcome repair returned no final answer.
- Five final answers passed schema checks, four after existing prefix normalization.
  The brief still selected wrong-kind handle 1. Records contained meaningful
  functional requirements but invalid exact references and incoherent Given/When/Then.
- Outcome correction returned source-backed prose; no native merge or full-candidate
  validation was executed. The loan replies selected offered handle 2 but used a
  literal-only title and copied the fixture's generic upstream description. That
  scripted context limits conclusions about model quality on unrelated sources.

The live assessment is adverse: removing redundant reference joins has not proved
useful complete generation or reliable final answers. Initial semantic selection
and field purpose remain with generation/semantic review; missing final answers
remain with provider admission and bounded correction. No new retry owner or
reference authority is justified. Native workflow checks remain `not_run` for
debugger replays; Phase 4 is **not complete**. Phase 4.2 must provide the actual
publication, readback and rubric evidence. One sandbox loopback failure occurred
before dispatch and consumed no provider call; it is recorded separately.

- **Outcome:** prepare comparable captured assignments from the reported and unrelated
  cases. Use the current approved contract/projection as the baseline. Hold sources,
  semantic task and provider settings fixed for a prompt comparison. Use the existing debugger and capture, with a declared
  call count and budget. Keep the old response as evidence, not a second runtime path.
- **Checks:** record final-answer presence, JSON/schema/native validity, literal and
  meaning preservation, repair outcomes, actual tokens and latency for every attempt.
  Start with the latest `02-40-05Z` run's title repair/correction (calls 9–10), whose
  guidance already conforms. The preceding run sent identical request bodies and
  call 10 returned final text; retain that comparison without treating it as a useful
  title. Include the prior `01-21-50Z` run's record repair/correction (calls 28–29).
  Preserve each assignment's fixed evidence/schema and measure final-answer availability.
  A failed earlier baseline alone does not establish a statistical improvement rate.
- **Two separate questions:** fixed-bound replay tests whether the corrected repair
  assignment returns usable, purpose-appropriate prose; fresh initial generation
  tests whether it selects the right occurrence and preserves behavior in story,
  requirements and Given/When/Then. Do not widen a replay's evidence to
  manufacture recovery, or treat prose-only repair as restored exact-token coverage.
  Retain every attempt, including missing answers; declare the case set, call count,
  budgets and success criteria before asking approval. Provider settings stay fixed
  for the prompt comparison; any later provider-setting comparison is a separate
  measured proposal. Report observations rather than claiming reliability from a
  handful of calls or reusing a prior approval.
- **Exit/revise:** report whether the redundant join failure was removed and whether
  new failures appeared. Do not proceed on shape success alone. If poor semantic
  content remains, identify its owner separately; do not add guessed evidence or
  tuning for the greeting. No automatic rerun or workflow publication in this chunk.

**4.2 — Whole-workflow publication and rubric: attempted, gate failed.** Depends on 4.1 and a separate E2E approval.

The separately approved execution
[`2026-09-26T03-01-57Z-a456e351f0bfbb82dc123b4f18f97860`](../../zig-out/e2e-spec/2026-09-26T03-01-57Z-a456e351f0bfbb82dc123b4f18f97860/report.md)
failed after **18 calls and 21,985/100,000 tokens**, with complete usage accounting.
It used the configured Bedrock `openai.gpt-oss-20b-1:0` route in `ap-southeast-2`,
a fresh isolated target and unchanged production sources (`0911cb7`, captured
source fingerprint `f970b687ca8f2c1db92368788c94e02647983d8ce9d2aafb400d80fa7abdbca4`).
No automatic rerun occurred. The first ten wire requests match the preceding
`02-40-05Z` run; their different returned final answers do not demonstrate a code improvement.

| Boundary | Observed result |
| --- | --- |
| Source and reconciliation, calls 1–7 | All three obligations and the exact greeting reached generation. Both claims were retained; no conflict or missing user decision was established. |
| Brief, calls 8–14 | Initial title, description and goal selected business claim 1 as an exact-copy handle. Each native defect received an independent repair. Calls 9/11/13 had no final answer; corrections 10/12/14 returned prose, merged and passed unit validation. The title and goal copied the requirements instead of serving their field purpose. |
| Story, call 15 | Exact-copy claim 2 with explicit support `[1]` passed native validation. This exercises derived reference lineage in production, but the literal-only story is not useful semantic recovery. |
| Entities, call 16 | `not_applicable` used wrong-kind exact claim 1 as its explanation. Native validation correctly reported `unknown_exact`; entity applicability itself was not rejected. |
| Repair/correction, calls 17–18 | The schema allowed only prose strings and the diagnostic explicitly prohibited the unavailable handle. The correction added `missing_final_text`. Both raw HTTP 200 responses contained only reasoning, ended with `finish_reason:stop`, and provided no final candidate. Request 14 exhausted its two executions: `RetryLimitExhausted`. |
| Later gates | Records/acceptance criteria, full coverage, source/principle assessment, publication, persisted readback and grading were not reached. Principles were present in the isolated project; their presence is not assessment. No specification or clarification Markdown was published. |

The [events](../../zig-out/e2e-spec/2026-09-26T03-01-57Z-a456e351f0bfbb82dc123b4f18f97860/events.jsonl)
contain 366 recorded step outcomes. No JSON/schema rejection exhausted; existing
logged prefix normalization handled affected final texts. The stop was missing
final answers during native-defect repair, not malformed JSON, lost source input,
missing credentials or the global token budget. Three other corrections recovered
in this same run, so the evidence supports inconsistent final-answer availability,
not a claim that all repairs fail. Neither reasoning nor a structurally accepted
paragraph may substitute for a validated, useful specification.

**Historical disposition:** this run motivated option 2 (§6.7). The following
execution exercises that change; it supersedes the claim that no live request
evidence exists. Retain the missing-answer assignments for any separately approved
controlled comparison; §6.8 records the current debugger's limits.

**Validation for this measurement-only change:** `zig build --summary failures`
passed; the exact E2E command below exited 1 with the retained failure above;
`git diff --check` passed. No production code, workflow, prompt, model setting or
judge was changed. The prior full verification remains offline conformance evidence,
not a substitute for this failed live gate.

#### Subsequent user run — empty principle review exhausts the token budget

Reviewed execution
[`2026-09-26T07-08-12Z-d5ea99a5e3ff77dc8adf92dd7c58e810`](../../zig-out/e2e-spec/2026-09-26T07-08-12Z-d5ea99a5e3ff77dc8adf92dd7c58e810/report.md)
used modified revision `0911cb7`, source fingerprint
`e178ef3e2406f582204d7f3033470598f18b6758126caa12ca831fa966876f81`.
The captured Bedrock `InvokeModel` requests contain native
`response_format.type:"json_schema"`, model `openai.gpt-oss-20b-1:0`, temperature
0 and low reasoning. Call 8's exact-copy selectors are restricted to enum `[2]`;
the earlier wrong-kind handle failure did not recur. This run progressed further,
but neither useful output nor Phase 4 completion is established.

| Boundary | Observed result |
| --- | --- |
| Calls 1–9 | Extraction/reconciliation preserved the source obligations; brief/story passed native checks. The title is the greeting alone and the story renders as `Hello, World!Hello, World!`. Valid reference selection does not establish useful meaning. |
| First native rejection, call 10 | Entity response was `not_applicable` with `basis.value:[]` and empty provenance. Event 257 reports `InvalidSpecification`, rule `provenance`; this is candidate invalidity, not a request for user information. |
| Calls 11–12 | Provenance repair returned claims `[1,2]`; full revalidation exposed the still-empty text (`InvalidTypedText`, reason `empty`). Text repair returned exact-copy claim 2. Both defects resolved mechanically, leaving a greeting as the explanation for entity non-applicability. |
| Calls 13–14 | Records contain three meaningful functional requirements and one acceptance criterion; complete coverage passed at event 315. Source review was admitted at event 331 despite calling the repeated greeting a supported actor/action/result. Coverage and admitted review are insufficient evidence of semantic usefulness. |
| Call 15 — principal cause of the repair cascade | The request supplied 15 principle-assessment subjects. The normalized response was `{"entries":[]}`. The selected array schema permits zero entries, while native review requires exactly one finding per subject. Event 347 reported all 15 as `missing_finding`. |
| Calls 16–24 | Existing atomic insertion added findings 1–8, retaining prior findings. Call 18 returned only reasoning; call 19 recovered that same assignment with final text. These were mostly successful repairs of distinct omissions, not repeated failure of one unresolved target. Seven findings remained absent. |
| Call 25 — terminal failure | Actual usage increased from **98,352 to 105,547/100,000 tokens**. The runner returned **`WorkflowTokenBudgetExceeded`** at the model-call boundary. Raw response contains a final finding for ordinal 9, but budget rejection prevented its admission/merge. It must not be counted as a missing-answer failure or successful repair. |
| Publication and evaluation | No specification or clarification Markdown was published. Persisted readback and rubric grading were `not_run`; there is no score. All 25 calls have actual usage. |

The [event stream](../../zig-out/e2e-spec/2026-09-26T07-08-12Z-d5ea99a5e3ff77dc8adf92dd7c58e810/events.jsonl)
contains 504 step outcomes. Fourteen responses received the existing logged prefix
normalization; no JSON/schema correction exhausted. A final-call overshoot followed
by immediate termination is the accepted [ADR 0011](../../design/decisions/0011-provider-owned-request-limits.md)
behavior. No subsequent call, automatic in-run budget increase or discarded usage
is justified. A fresh approved test may use a larger recorded budget under §6.9's
quality-led direction; it does not change this run's failure or accounting.

**Measured cost:**

| Work | Calls | Input tokens | Output tokens | Total tokens |
| --- | ---: | ---: | ---: | ---: |
| Extraction/reconciliation | 1–7 | 9,072 | 855 | 9,927 |
| Generation and entity repair | 8–13 | 8,329 | 744 | 9,073 |
| Source review | 14 | 5,589 | 1,207 | 6,796 |
| Initial principle review | 15 | 7,595 | 56 | 7,651 |
| Principle finding insertion/correction | 16–25 | 69,659 | 2,441 | 72,100 |

Principle review and repair consumed **79,751 tokens (75.6% of the run)**.
Call 15's wire request is 39,692 bytes; call 16's is 36,454 bytes for one finding.
In the compact repair input, the seven principle chunks occupy 30,853 bytes.
The selected requirement list is narrowed correctly; the full candidate and
principle evidence are repeated. The small finding schema is not the main payload
cost. High input tokens are acceptable when necessary, but this run paid repeatedly
for mechanically missing assessments. Byte figures measure retained request/input
serialization; token figures are provider-reported, not estimates.

**Owning boundaries and next bounded work:**

The following run-specific evidence feeds §6.9's bounded sequence;
it must not be implemented as an isolated principle-review exception.

1. **Capture this complete failure first.** Extend shared review/request regressions:
   15 assigned subjects → empty review → successful insertions → missing final
   answer and recovery → budget stop with an unmerged final answer. Include an
   unrelated, differently sized assignment set; prove successful full recovery,
   retained findings/provenance, freshness, exact accounting and no publication on
   exhaustion. Safe termination alone does not close the useful-generation gate.
2. **Move review association into focused native assignments (§7C).**
   [`principle_assessment.subjects/project`](../../src/domain/principle_assessment.zig)
   already derives the assignment set; [`specification_support.Contract`](../../src/domain/specification_support.zig)
   validates missing/duplicate/foreign findings for source and principle reviews.
   The current [`principle_review` schema](../../design/workflows/spec/support.schema.json)
   leaves batch membership to the model. §6.9 C2a supersedes required-slot expansion:
   native progress selects a subject, the model returns a compact semantic finding,
   and code binds/retains it. Specify the §§12.7/22 response and execution amendments
   and test costs before C2b activates both review purposes. Keep their semantic
   duties distinct; no auto-filled verdicts, unchecked positional association,
   second schema authority or extra reviewer.
3. **Keep context reduction and semantic quality separate.**
   [`principle_assessment.packet`](../../src/domain/principle_assessment.zig) and
   [`specification_support_repair.packet`](../../src/domain/specification_support_repair.zig)
   already own selection and repair projection. Assess a narrower presentation
   there only when dependencies show which evidence can safely be omitted;
   do not delete policy chunks or change policy selection merely to cut tokens.
   Focused assignments transfer responsibility; they do not establish a context
   reduction by themselves. Independently, regress the source review's acceptance of
   literal-only story/entity content using unrelated examples and the existing
   semantic owner. Existing prompts already explain field purpose; another generic
   sentence is not an evidenced remedy. Policy findings also disagree on whether
   UTC output is compatible with the captured greeting-only I/O principle.
   Preserve that policy evidence and assess actual meaning; do not relabel a
   candidate-writing defect as a policy conflict or user gap. Verdict reassessment
   remains outside current repair authority.

Phases 0–3 and option 2's offline implementation remain complete. Phase 4.2 stays
open for the complete review, useful specification, publication/readback and rubric
gate. The rubric still has `pass_threshold_percent:null`; report actual criterion
scores and `not_configured` rather than inventing a threshold. This documentation
update makes no code, prompt, workflow, policy or model-setting change and runs no
new live calls. Validation: retained requests/responses/events and their production
owners inspected; `git diff --check` passed for the documentation change.

- **Outcome:** use `./scripts/e2e-spec.sh --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json` with an explicitly
  approved fresh target under this project's `zig-out` and the case's configured
  generation/grading budgets. Prepare the concrete proposal before asking approval.
- **Checks:** inspect original source obligations, meaningful story/FRs/Given–When–Then,
  exact values, principles, necessary clarifications, publication and the actual
  rubric report. Record the production canonical parse plus mandatory persisted-byte
  equality proof under the same contract; retain fresh-read/changed-contract
  validation as separate boundary evidence (§6.9). Offline fixtures or hand-written
  expected Markdown
  cannot substitute for generated/scored output. Broader live claims need separately
  approved unrelated cases, not just the Hello World fixture.
- **Exit/revise:** close live readiness only with completed, validated publication
  and the configured rubric acceptance result. A pause, failure or ungraded output
  leaves the relevant gate open; retain its evidence and revise the owning chunk.
  Each further E2E execution needs approval. Keep §7's required follow-ups separately
  attributable; they cannot erase or mask a failed result.

### Registered verification commands

These are existing [build.zig](../../build.zig) steps to extend/use during implementation;
§14 separately records which ran during this review. New tests must be registered in
the complete suite; do not use standalone `zig test` as a parallel build path.

| Boundary/chunks | Targeted commands |
| --- | --- |
| Integer restrictions and bound requests, O2.1–O2.2 | `zig build test-model-result-schema test-model-payload-schema test-model-request-preparation`; extend debugger/composition regressions in their existing full-suite registrations |
| Reference mechanics, 1.1/2.1 | `zig build test-reference-evidence test-reference-model-input test-reference-reconciliation test-typed-text test-architecture` |
| Closed shapes/requests, 2.1–2.2 | `zig build test-specification-contract test-model-candidate-json test-model-result-schema test-model-request-preparation` |
| Native generation/repair/readback, 0.1/2.3–2.4 | `zig build test-specification-generation test-workflow-repair-retry` |
| Protocol/accounting/integration, 2.3/3.1 | `zig build test-model-request-workflow test-model-attempt-accounting test-pipeline-envelope test-atomic-execution test-workflow-graph` |
| Preserved upstream behavior and gates, 2.4/3.1 | `zig build test-reference-extraction test-reference-reconciliation test-required-authority test-clarification-inputs` |
| Evaluator and offline publication oracle, C3/C4 | `zig build test-rubric-evaluator test-e2e-harness`; these are offline tests, not a live E2E run |
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
| Implemented option 2 (§6.7) | Selected schemas admit only native eligible IDs for each declared tagged integer selector; business-support IDs keep distinct eligibility. Offline tests cover scalar membership, request selection, excluded alternatives and repair packet scope. Live complete-response recovery, full validation of a published result and quality remain to be shown. |
| Option 2 scale and replay | Preserve the implemented 256/257/1,024-choice coverage and 1,025 rejection under the approved shared limit; no silent truncation or unrestricted fallback. §6.7 records integer restriction and resource measurements. Captured selected schemas recompile, diagnostics locate the correct enum, and corrections avoid another full allowed-ID list. These checks do not establish focused-assignment cost or scale. |
| Option 2 correction scope | A schema-invalid initial unit receives complete-response correction under its existing assignment budget. Already admitted units/parts and atomic siblings remain unchanged; rejected initial fields do not acquire new immutability authority. Alternate enum, JSON and missing-answer failures without counter reset; prove successful recovery and failure without publication. |
| Shared projection consumers | Spec exact-choice projection changes without dropping token IDs required by reconciliation or source review. Each request has the facts its declared contract requires, without duplicate choice lists. |
| Unknown/wrong-kind/ineligible claim or stale/foreign state binding | Typed rejection; no default, citation insertion, publication or clarification conversion. Reused ordinals do not bypass state/dependency checks. |
| Same literal in different sources | Exact selected occurrence retained; no first-match selection. |
| Repeated exact segment | Stable ordered citation union, preserved text order/repetition and idempotent expansion. Duplicate derived dependencies collapse; duplicate explicit evidence selections still reject. |
| Explicit/derived overlap | The two §5.2 examples remain distinguishable after round-trip. Removing a reference under an authorized group drops only derived support; intentional explicit token evidence survives. |
| Empty explicit selection | In source-backed Spec, `S=[]` is permitted when eligible exact segments supply nonempty effective evidence; empty effective evidence rejects. Other domains retain their accepted non-reference support. No semantic-quality pass is implied. |
| Reference added, replaced or removed | Correct dependency recomputation for the whole authorized unit; unrelated sibling data and producer origins unchanged. |
| Shared-provenance acceptance record | All fields contribute exact dependencies; Given/When/Then retain separate meaning and unaffected content. A prose-only sibling must render when another field alone supplies exact evidence. Carry that case through publication and completed readback. |
| Fixed-evidence repair | Pin explicit `S` exactly and compare effective claim/citation sets. Harmless segment reordering recomputes stable canonical order; it does not fail merely because the derived list order changed. Reference removal/addition cannot shrink/expand evidence without its authorized coupled target; include unchanged siblings in the full-record check. |
| Invalid candidate without complete provenance | Cover valid explicit support/siblings plus an unknown handle recovering within approved `B`, and empty/insufficient `B` blocking. Unknown handles grant no scope. A field-only success followed by exact-coverage failure must not publish. Do not demand equality with old `L` that never existed. |
| Invalid explicit support and invalid handle | Existing evidence repair or an authorized group handles invalid `S`; it is never pinned as trusted scope. Cover staged recovery and exhaustion with unchanged retry families, sibling data and accounting. |
| Repair cannot expand its own scope | Retain original `B` while expected values/revisions advance. A later rejected response containing a newly eligible handle cannot enlarge the next request's permitted set. Upstream changes invalidate existing authorization through its normal dependency checks. |
| Omission/progress conformance | Resolve effective evidence over the entire owning unit, including `S=[]` and sibling-only exact support. The selected repair's success remains independent of another sibling defect; no false recurrence or allowance reset. |
| Authorized construction versus readback | An authorized replacement reorders/materializes derived citations under the same effective sets before canonical validation. A persisted mismatch rejects rather than passing through repair construction. |
| Bad selection versus broken binding | Unknown model choices under valid authority may repair. Invalid/missing trusted ledger or choice binding follows existing terminal rejection, with no extra model call, clarification or publication. |
| Passive references and source scope | Equivalent valid candidates retain their available choices; fixed repair packets offer only current authorized replacements, even when broad source context contains others. Removed dependencies force sibling revalidation. Operational path capabilities remain unchanged. |
| Native expected value / model presentation | Existing atomic checks still bind exact native expected values and dependencies. Shared handle syntax must not conceal differences in evidence shape or authorize lossy comparisons. |
| Diagnostic localization | A rejected handle names its field/segment and permitted choices; it targets value repair, not unrelated provenance. Changed invalid IDs do not restart the same assignment's allowance. |
| Supported and negative review evidence | Supported findings compare with effective provenance. Loss/negative findings retain their existing distinct eligibility; validate both live in-memory and on completed-state readback. |
| Sliced response/dependency renewal | Stale completed parts reject; renewed dependencies rebuild all affected validators/reviews before publication. |
| Missing answers, invalid JSON/schema and repeated invalid handles | Existing retry identities, exhaustion, failure precedence and exact usage accounting remain unchanged. Successful unrelated work continues within budget. |
| Completed versus pending state | Completed readback revalidates stored content selection, reference handles and coverage/review projections. Pending readback retains its reference/clarification identity contract without new content storage. Both share the state-version tag today; cover accepted current variants and rejected old versions together. |
| Canonical state tampering | Foreign/deleted claims, invalid exact handles and mismatched retained coverage/review projections reject on readback. Derived views are computed; corrupt authoritative values are never silently repaired. |
| Empty/meaningless but correctly linked story or AC | Never counted as semantic recovery merely because joins pass. Scripted review tests routing. Approved real-review observations test detection, including valid counterexamples; live rubric evaluation assesses the generated specification. |
| Earlier schema rejection | Record when a former native defect becomes complete-response correction. Test unchanged/changed/dropped fields, preserved already admitted parts, stable assignment and limits, and actual protocol/native accounting. A rejected batch has no independently frozen finding siblings. |
| Batch failure baseline and focused replacement | Reproduce the empty-review sequence before cutover. Under the new contract, test one semantic response per native assignment across both purposes and unrelated subjects. The response omits assigned IDs/counts and rejects superseded batch fields. Unvisited work is pending, not a repair error; full native membership checks still reject missing/duplicate/foreign findings at completion/readback. |
| Assignment binding, retention and scale | Test exact subject/schema/revision association, duplicate/conflicting delivery, same-sized remapped subjects and source/principle subjects sharing an ordinal. Stable ordering/identity survives correction; changed candidate/policy authority invalidates affected results. Preserve zero model calls when no principles apply. Measure aggregate calls, tokens, latency, allocation and retained state, including no-error and repair paths. |
| Native-invalid finding before collection completion | A schema-valid finding with invalid evidence or detail enters existing authorized repair while unvisited subjects remain pending. Retain the verdict, siblings and exact diagnostic; changed/dropped defects cannot reset allowance. Revalidate all produced entries, then complete membership before authority application. Full-finding regeneration must not bypass native repair limits. |
| Complete findings determine routing | Test genuine user gaps, localized repairable loss and unlocalized/inconclusive findings in different arrival orders. Admitted negative data does not mean success or immediate clarification. Complete reconciliation retains defect precedence and Plan-owned principle obligations; no new publication on unresolved failure. |
| Lifecycle, attribution and dependent rebuilding | Every assignment closes/retires through existing request operations before the next. Preserve distinct per-finding origins and repair links; repeating an unresolved assignment cannot reset counts via a new request ordinal or latest-origin scope. Rebuild under the existing pending parent key, and resolve it only after complete dependent review. Test cancellation/failure at retirement and renewal, with full actual usage retained. |
| Productive work versus unproductive repetition | Many successful assignments/repairs continue; repeated or alternating failure of one unresolved assignment/defect exhausts its existing allowance even with ample tokens. A budget overshoot still stops before admission or another call. Raising the configured budget never increases per-defect allowances or changes what counts as validated progress. |
| Focused execution across workflows | Exercise the same runner progress/request operations with source review, principle review and an unrelated registered consumer. Domain facts remain typed; no Spec-name branches, parallel scheduler, hidden model loop or model-generated completion. Native checks assemble the final collection; no JSON reassembly prompt. |
| Removal of fixed model fields | Reject legacy response keys after cutover. Prove equivalent native values from bound authority, preserve independently selected evidence and reject corrupted persisted fields before any model-shaped reconstruction can hide them. Remove unreachable repair branches, retaining native rejection and reachable semantic-selection repair. |
| Successful finding insertions followed by budget overshoot | Preserve all earlier findings and their origins; a missing-answer correction uses the same assignment allowance. Account the overshooting response completely and stop before its merge, subsequent calls or publication. Include successful full recovery within budget. |
| Pre-ledger extraction and reconciliation | Their existing allowed shapes and source selections remain intact; exact-copy business segments are not newly admitted there. |
| Independent workflow reuse | Two differently named configured workflows with distinct response shapes use the same shared resolver through registered typed consumers. The second consumer has no Spec/session dependency or workflow-name branch. |
| Shape and policy variation | Nested records, arrays and optional typed fields contribute only to their owning evidence unit. Different native eligibility sets remain enforced; Spec-only restrictions do not become global. |
| Structural JSON versus typed meaning | Reference-looking objects in ordinary JSON remain ordinary data. Existing schema/composition limits reject unsupported shapes; resolution does not enter the generic assembler or decoder. |
| No-reference and mixed-support workflows | No unnecessary ledger/model calls for an unrelated workflow. Domain-accepted user answers, repository facts and other support are not dropped or converted to fabricated claims. |
| Namespace isolation and reuse | Swapped bindings reject across different states and after changed ledger production under the same corpus ID/ordinal. A bare ordinal cannot reveal unstated model intent. Valid predecessor identity survives a fresh execution; stale producer/contract changes invalidate dependents. |
| Operational and stage boundaries | Display references grant no file/copy/command capability; source-like strings inside code remain raw payload. Existing clarification and approval gates remain independent. |
| Shared dependency direction | Architecture checks reject shared reference/syntax modules importing Spec generation, sessions or policy; no second resolver/schema/policy registry. |
| Allocation and scale | Inject failure after initial allocation, several accumulated findings and during lineage growth; no leaks with a general allocator. Measure repeated full-unit derivation and retained parent/array growth separately from tokens. Release transport safely, preserve necessary evidence and verify execution teardown; no persistent cache or weakened lineage. |
| Grading and readback evidence | Preserve rubric-owned checks and distinguish `not_configured` from a quality pass. Verify provider-schema projection separately. Production parse of canonical bytes plus persisted byte equality proves same-contract conformance; fresh-runtime, corruption and changed-contract tests prove different boundaries. Add no duplicate reader. |

## 12. Feasibility conclusion

**Viable for reuse across workflows through a shared typed contract, with Spec as
the first integration. Phases 2–3 are complete.** The reference-owner refactor,
handle representation, explicit selection, version cutover and §6.5 conformance
work are implemented. They require no new message layer, reference registry,
retry mechanism or general-purpose fixer.

**C0, C2a and C2b offline status:** The observed empty-review and bounded-recovery baseline,
focused contract and shared cutover are implemented. Expanded review slots and the
model-facing batch review parser/packet are removed. The engine owns the assignment
set, identity, progress and collection assembly. Initial preparation, working repair,
request lifecycle, prompts and schema selection have changed together; complete
collection admission and negative-finding routing remain. Some model-returned
fixed evidence fields remain C2c work; do not describe the entire response as purely
semantic. Preserve zero-work paths and canonical defensive validation.

Individual schemas can be smaller without a smaller total workflow. The captured
candidate review would expand from two initial calls to 33 under a literal
one-call-per-subject implementation. C2a records that trade-off and C2b measures a
different implemented fixture's 29 requests. The user
accepts a larger finite token budget for good quality; the old 100,000-token setting
is not an architectural ceiling. Offline schema sizes establish neither quality
nor live cost. C1's presence fixes are supporting conformance, not responsibility
removal; the remaining deterministic fields in C2c remain explicit open work.
Semantic usefulness and final-answer availability require their own evidence through
existing review and provider/request owners. Option 2 has limited positive live
evidence; the later budget failure does not reopen its implemented ID contract.
Repeat Phase 4.2 only with separate approval after full verification. C2c's
remaining deterministic-field audit is separate from this cutover.

This does not promise automatic support for every JSON Schema, authority namespace
or future workflow. New domains reuse the mechanism by supplying their declared
typed fields, validated reference binding and native policy; they do not duplicate
the resolver or inherit Spec's semantic rules. Workflows without reference content
continue using their existing deterministic owners.

The cutover removes one redundant model-side join. Completion must demonstrate
that its replacement works at every consumer. It must not claim deterministic
proof of specification quality, silently infer business evidence, or hide unresolved model errors behind mechanically complete
coverage. All remaining deterministic bookkeeping must transfer under §15, independently
of this completed first contract. Measurement assesses outcomes and resources;
it does not decide whether determined work belongs in code.

**Evidence limit:** Phases 2–3 establish offline conformance and reuse, including
packaged behavior. The earlier retained run accepted a valid derived reference
but produced poor interim content and exhausted missing-answer recovery. The
pre-Phase-4 `02-40-05Z` run stopped at the first title repair: its first ten requests match that earlier
run byte-for-byte, but the correction no longer returned final text. Neither run
reached publication or grading; this comparison does not establish a Phase 3
contract regression or a live quality improvement.
Phase 4.1's eight approved diagnostic calls also retained reference-selection,
field-meaning and missing-final-answer failures. They did not execute native merge
or publication. Phase 4.2's approved run recovered three brief fields and accepted
derived story lineage, but its entity-basis repair exhausted missing-answer
recovery. The subsequent `07-08-12Z` run exercised option 2, recovered entity defects,
passed coverage/source review and inserted eight principle findings before the
global token budget stopped execution. The literal-only story and source review's
acceptance of it remain semantic failures. Publication/readback and scoring remain
`not_run`. Phase 4 cannot be
marked complete. §9 records the original approval; §6.9 records C2a's later accepted
focused amendment. §14 distinguishes remaining decisions from those approvals.
Existing regression owners include [specification generation tests](../../src/specification_generation_test.zig),
[typed-text tests](../../src/typed_text_test.zig), [request workflow tests](../../src/model_request_workflow_test.zig)
and [native packaging smoke](../../test/packaging/smoke.zig); implementation must extend
them with the matrix above rather than count existing containment tests as recovery evidence.

## 13. Remaining provenance and requirement-source traceability plan

**Reviewed 27 September 2026 against the current worktree, including existing
uncommitted changes. Documentation only; no implementation or live calls.**
Authority: [ADR 0020](../../design/decisions/0020-derived-exact-reference-lineage.md),
[design §§1, 3–4](../../design/design.md#3-goals-non-goals-and-invariants),
invariants 1, 5–7, 12, 15–16, 19–23 and 30,
§§7.1, 12, 16–17, 21–24, and §31's reference, repair, view-integrity and
offline-integration criteria. The governing design remains Proposed. Decisions
identified below must be settled before their implementation; this plan does not
amend accepted schemas or authorize a live test.

**Completed — retain:** `{"kind":"exact_copy","claim_id":N}` selects one recorded
occurrence. [reference_support](../../src/domain/reference_support.zig) owns exact
resolution, stable lineage and citation selection without importing Spec types.
[specification_provenance](../../src/domain/specification_provenance.zig) supplies
Spec eligibility and traverses the attributed field or complete shared-provenance
record. Canonical `provenance.claim_ids` retains explicit `S`; effective support is
`stableUnique(S + eligible exact claims E)`, including valid `S=[]` cases. Citations
are derived, and stored projections are checked. Generation, record rendering,
coverage, fixed-evidence repair and `specification-state/v6` readback already use
this contract. Do not rename the field to `support` or reimplement the cutover.
Retaining these canonical mechanics does not require retaining every model-facing
selector: §§15.4–15.5 distinguish that remaining response-contract work.

Existing [generation tests](../../src/specification_generation_test.zig) cover derived
field/record lineage, repeated text in different sources, shared-record repair and
corrupt completed readback. The registered audit consumer in
[request-workflow tests](../../src/model_request_workflow_test.zig) already proves
non-Spec reuse with different eligibility, optional/array fields and stale-binding
rejection. §§10–11 record earlier offline results; §14 records the additional
targeted test runs for this review. Full live publication/readback and quality remain open.

**Confirmed gaps at this review baseline:** source review still asks for some mechanically fixed effective
claim lists (§7F); `spec.md` projects business text without provenance, while
`reference-context.md` shows sources/citations without generated-requirement
associations or navigable occurrence links. The current Markdown reader records
blocks/spans, not structured original-requirement IDs or their associations.
The last two are extensions to the current presentation/capture contracts, not
evidence that ADR 0020's union or repair implementation is missing.

| Remaining change | Existing owner/file | Reason | Required test | Contract decision needing approval |
| --- | --- | --- | --- | --- |
| **P1 — Implemented offline 27 September:** construct fixed review evidence; retain semantic selections. | [specification_support_evidence](../../src/domain/specification_support_evidence.zig), [specification_support](../../src/domain/specification_support.zig), [support repair](../../src/domain/specification_support_repair.zig), [support schema](../../design/workflows/spec/support.schema.json). Reuse §6.9 C2c / §7F. | `Requirements.rule(...).provenance` and `.claims.exact` determine some required lists; the engine now constructs them. Aggregate subjects without fixed provenance, independently chosen `source_ids`, selectable negative/loss evidence and principle citations retain their own rules. The verdict remains model-assisted. | Focused tests cover equivalent native findings, forbidden echoes, selectable evidence, localized loss, selected repair and corrupt readback. §15.6 records the controlled byte comparison. Full suite and live outcome evidence remain separate. | Focused §§12/17.3/22 review-response amendment recorded. Generation's `provenance.claim_ids` naming and ADR 0020 evidence bounds remain unchanged. |
| **P2 — New derived projection:** expose each generated requirement → effective claims → recorded occurrences through the existing owners. | [reference_support](../../src/domain/reference_support.zig), [reference_claim_items](../../src/domain/reference_claim_items.zig), [specification_provenance](../../src/domain/specification_provenance.zig), [specification_projection](../../src/domain/specification_projection.zig); existing [coverage](../../src/domain/specification_coverage.zig) supplies checked reverse mappings. | Join each admitted unit's resolved `L` to its validated `Item.citations`, source identity and captured location. `effectiveClaims` alone enumerates handles; it is not an admission/freshness check. Chunk-level `scopes` alone are not precise citation spans. Keep claim-to-occurrence edges even when citation display deduplicates; never union support across requirements. Use an ephemeral typed projection, not another persisted/writable mapping. | In one candidate, requirement A with `S=[1]`, exact `2` yields `[1,2]`; B with `S=[3]` stays `[3]`. Cover one claim with several citations, one source supporting several requirements, several sources supporting one requirement, and equal text at different locations in one file and different files. Repeat through rendering/readback. | No new selection or persistence authority. Define the output representation with P3; any shared occurrence projection remains independent of Spec types and eligibility. |
| **P3 — New visible traceability:** render requirement-keyed links and occurrence anchors in the existing `reference-context.md` output. | [reference_context](../../src/domain/reference_context.zig), [render-reference-context action](../../src/actions/reference/render_reference_context.zig), [specification_projection](../../src/domain/specification_projection.zig), existing rendering/publication workflow, and [pending-output preparation](../../src/actions/specification/prepare_incomplete_specification_output.zig), a direct sibling caller of the renderer. Completed state contains content and references; pending state does not contain generated requirements. | Recommended placement preserves the editable business document's current grammar. Display generated IDs, effective claims, citations, captured reference-state identity, document path and precise spans. Links must use validated artifact/source locations and renderer escaping; a current file link alone is not evidence of the captured version. | Deterministic ordering, valid local anchors/relative links, escaped paths, repeated occurrences and complete record coverage; rerender from parsed canonical state is byte-identical. Editing the sidecar cannot alter authority. Pending rendering receives no generated-requirement projection and retains its existing reference view; test this sibling path explicitly. | Approve the reference-view Markdown layout under §§17.6/23.1 and its rendering-contract binding. This placement needs no `spec.md` parser change or new state field. Storing partial generated requirements in pending state would be a separate ADR 0017/state amendment and is excluded. If links must appear inline in `spec.md`, first amend its F0100 §5 grammar, projection/parser and round-trip contract; do not append unrecognized metadata. |
| **P4 — Conditional capture extension:** preserve original requirement IDs only where an explicit, validated source association exists. Otherwise display capture/document/span anchors. | [reference ingestion](../../src/domain/reference_ingestion.zig), [Markdown reader](../../src/adapters/parsers/markdown_reference.zig), [reference_evidence](../../src/domain/reference_evidence.zig), [source selections](../../src/domain/source_selections.zig), [reference_snapshot](../../src/domain/reference_snapshot.zig). | Current source bytes may contain labels, but no structured ID-to-claim association is captured. Neither claim ordinals, source blocks nor generated `FR-*` IDs are original requirement IDs. The captured reference state identifies the source snapshot; it must not be labelled an author-supplied document version. Do not guess boundaries from nearby labels or similar prose. | With an approved capture format: one original ID → several generated IDs and the reverse; same label in different documents/versions remains distinct; absent IDs use spans; malformed, ambiguous, foreign and stale associations reject. No fabricated IDs from headings or prose. | Before adding fields, approve the explicit source-ID/version/association contract in §§7/16, reader/extraction binding, closed snapshot validation and any affected §24 state-version change. Keep associations inside the existing source ledger; no separate traceability store, migration or dual reader. Span-based P2–P3 can proceed without this optional capture extension. |
| **P5 — Verification extension:** carry the new projection through authorized repair, dependency renewal and strict persisted loading. Fix code only if these regressions expose a defect. | [specification_repair](../../src/domain/specification_repair.zig), [coverage repair](../../src/domain/specification_coverage_repair.zig), [specification_session](../../src/domain/specification_session.zig), [specification_state](../../src/domain/specification_state.zig); existing atomic/runner owners. | Preserve old-value/revision/generation checks, explicit `S`, original invalid-handle bound `B`, effective claim/citation sets, siblings and retry identity. Recompute after authorized merges; on load recompute and compare, never silently repair corrupt stored evidence. | Unknown, wrong-kind, out-of-scope and stale selections; reordered segments; add/remove outside the bound; invalid `S`; retries cannot enlarge `B`. An unrelated requirement stays unchanged. Stale trusted bindings terminate; unresolved model/engine defects produce neither missing-user questions nor successful publication. Field repair still may fail exact coverage or semantic review. | None for ADR 0020 conformance. Any new coupled evidence-change authority is out of scope and requires a separate decision. P4 may require persistence amendment. |
| **P6 — Extend existing reuse proof:** exercise occurrence projection in the registered non-Spec audit consumer. | [reference_support](../../src/domain/reference_support.zig), existing audit fixture in [model_request_workflow_test](../../src/model_request_workflow_test.zig), [architecture tests](../../src/architecture_test.zig). | Reuse is already demonstrated offline; extend its assertions instead of creating a workflow/framework. Each registered consumer supplies validated references and its own eligibility, coverage and approval policy. Clarification answers, policy evidence and operational capabilities remain distinct. | Separate audit units retain separate links; its forbidden-field and stale-binding cases still reject; nested/optional fields work. Shared code imports no Spec types, unrelated workflows inherit no SDD gates, and no-reference operations need no ledger. | None for test-owned reuse. A production workflow's new admission policy would need its own scoped contract, not a global Spec rule. |
| **P7 — Measure, reconcile documentation and verify:** baseline before implementation; compare equivalent compiled requests after each cutover. | Existing [schema selection](../../src/domain/model_result_schema.zig), [request preparation tests](../../src/model_request_preparation_test.zig), request-workflow tests, §10 measurements and [build.zig](../../build.zig). | Measure compiled selected schemas, provider projections and whole request/output bytes for initial, repair and correction assignments, plus aggregate calls and native allocation cost. Rendering-only changes should add no model bookkeeping. Documentation defects include F0100 §§5.6–5.7's old token/citation shape and design §32's still-pending cutover claim. | Same ledger/assignment/repair scope before/after; closed schemas exclude determined returned fields while genuine choices remain. Use §10's targeted checks, then `zig build verify` (including clean-directory native smoke) and `git diff --check`. Retain independent semantic/coverage/publication gates. | No approval for offline measurements. Update affected §§7/12/16/17/22/23/24, F0100 and these notes only for the agreed changes; preserve ADR 0020 and Proposed status. Each live model/E2E run needs separate approval. Bytes/offline fixtures prove neither token savings nor live reliability or semantic quality. |

Sequence after P1: implement P2–P3 through their existing owners; extend P5–P6
and complete P7.
P4 is conditional on needing structured original IDs beyond the existing span
anchors and must not delay or silently expand the span-based work. No source
support is inferred from prose, no model reproduces a derived relationship,
and no new agent, retry system or provenance authority is part of this plan.

## 14. Detailed remaining-work review — 27 September 2026

**Assessment: feasible through existing owners, with several scoped contract
decisions; no architectural rewrite is justified.** This review includes the
uncommitted focused-review implementation. It distinguishes schema conformance
gaps from new presentation/response contracts and from missing effectiveness
evidence. A native rejection with intact containment is not evidence of an
authority bypass. Historical live failures and measurements above remain historical;
they did not run the current focused-review format.

The authority route is [AGENTS.md](../../AGENTS.md), design §§1, 3–7, 12–13,
16–17, 21–24, 28 and 30–31, and accepted ADRs 0003, 0009, 0011, 0017, 0019
and 0020. Reviewed boundaries include ingestion, schema compilation, selected
requests, provider serialization, runner identities/accounting, admission, atomic
repair, review progress, retained ownership, rendering, publication, persisted
loading and the separate evaluator. No accepted design/ADR or code is changed by
this review. Proposed design status and existing user edits are preserved.

**Outcome priority:** higher token expenditure is acceptable when it improves
outcomes. Do not reject focused review because it uses more calls, or prefer a
smaller schema at the expense of source meaning, review accuracy or completion.
Measure cost to choose a sufficient finite budget and expose unproductive retries;
token savings are not required. Evidence of better outcomes must include semantic
quality, not merely valid JSON or mechanically consistent citations. This direction
does not authorize a live call, automatic budget replenishment or weaker gates.

### 14.1 Current status and complete conformance disposition

**Completed:** Phases 0–3, §6.5, O2's restrictions, C0, C2a/C2b and §7C/D's
identified changes. `nextSubject`, `collectFocused`, `validateWorking` and
`reviewSlot` in [specification_support](../../src/domain/specification_support.zig)
implement focused assignment. The existing
[application binding](../../src/application/specification_support_workflow.zig)
publishes typed progress, and the [workflow](../../design/workflows/spec.workflow.yaml)
retires requests before continuing. `validateWorking` reuses the complete validator
and suppresses only future-subject omissions; final authority still requires a
complete accepted collection. Fixed applicability selects the appropriate named
finding schema. These are implemented mechanisms, not new work to commission.

**Open:** C2c responsibility removal and lawful-choice
projection; C3 grading conformance; C4/Phase 4.2 effectiveness; §7A/B/E/F;
and §13's traceability extensions/evidence. The table covers all thirteen §6.9
areas. “Decision” means a contract decision before implementation, not a request
to approve this documentation update.

| Remaining change / classification | Existing owner/file | Feasibility and reason | Required evidence | Contract decision |
| --- | --- | --- | --- | --- |
| **1. C1 required text — implemented offline** | [Extraction](../../design/workflows/spec/extraction.schema.json), [reconciliation](../../design/workflows/spec/reconciliation.schema.json), [generation](../../design/workflows/spec/generation.schema.json), [typed_text](../../src/domain/typed_text.zig) | Required typed-text arrays and literal strings now expose their unconditional native minima in initial and selected definitions. Exact/passive-only content remains valid; blank/control/UTF-8 and relational rules remain native. | Schema rejection and valid-empty siblings are covered in candidate-schema tests; provider projection retains collection minima. Full native, correction, retry and accounting checks remain required with each later contract cutover. | No new semantic authority was needed. A change to what counts as valid text requires its own decision. |
| **2. Generation provenance — C2c bookkeeping/choice gap and §7E** | [specification_session](../../src/domain/specification_session.zig), [specification_provenance](../../src/domain/specification_provenance.zig), generation schema | §§15.4–15.5 remove fixed `S` echoes, invariant empty fields and determined exact selectors. Reassess source-bound assignments before retaining `provenance.claim_ids` for genuinely unbound support choices. Current tagged scalar restrictions cannot narrow its array items (§14.2), and restricting an ID to one value is not responsibility transfer. Never fill `S` from the eligible catalogue or `E`. | Fixed `[3]` without echo; singleton exact marker and wholly native exact field; `S=[]` plus exact evidence; `S=[1]` plus exact `2`; a separate record stays `[3]`; forbidden echoes, multiple-choice ambiguity, initial/repair/correction and corrupt readback. | §§15.4–15.5 model/canonical and per-unit assignment amendment, including ADR 0020 wording; §7E and any narrow choice-projection extension. No changed evidence bounds or global restriction on other workflows' clarification evidence. |
| **3. Required FR/AC membership — native completion gate retained** | [specification](../../src/domain/specification.zig), [specification_authority](../../src/domain/specification_authority.zig), [specification_session](../../src/domain/specification_session.zig) | A minimum on the heterogeneous record array cannot require both families. The closed profile has no `contains`/tuple membership mechanism. Keep native rejection; do not fabricate records. Family-partitioned responses or missing-family insertion are larger changes than C1. | Missing FR, missing AC, both absent, legitimate `needs_user`/`inconclusive`, and correct multi-family output; no publication or false clarification from candidate defects. | Required before reshaping/partitioning generation or adding insertion authority. Existing missing-entity authority does not cover FR/AC. Native containment needs no replacement. |
| **4. Fixed entity decision — implemented request choice** | [Session packet construction](../../src/domain/specification_session.zig) and [shared text projection](../../src/domain/reference_model_input.zig) | The captured `not_applicable` decision excludes tagged `entity` in records generation; narrowed packets retain the exclusion. `required` leaves the choice available, while native membership still requires at least one entity. | Both decisions, initial/narrowed schema, missing decision, required omission, stale repair and siblings have owning tests. | Existing admission rule supplied authority; no new decision was needed. |
| **5. Extraction citations — C1 minimum done; scoped choice open** | [source_selections](../../src/domain/source_selections.zig), extraction schema and packet/repair owners | Nonempty citations are now expressed in the shared schema. First/last line IDs are untagged sibling fields, outside today's O2 selector API. Ordered, scope-local ranges remain native relationships even if finite line choices are projected. | Empty citations and selected replacement have schema tests; range, scope and repeated-location tests remain native. | A precise selector contract if narrowing untagged IDs; no need for a new source locator or regex matching. |
| **6. Token classification — required native association and set construction** | [token_classification_validation](../../src/domain/token_classification_validation.zig), [reference_extraction_parser](../../src/domain/reference_extraction_parser.zig) | The owner already knows candidates and outcome-compatible decisions. Counts/unique whole objects cannot enforce one decision per candidate. Candidate identity is pre-ledger source/extractor/ordinal identity, not `ClaimId`. Fixed association removal is required: define native assignment/binding and assembly, retaining semantic classification. An accepted outcome that forces one result must also be constructed natively. Review cost without making lower cost a gate; do not copy Spec's call granularity indiscriminately. | Zero/nonzero candidates, duplicates/missing/foreign candidates, scope isolation, claims versus no-feature-claim outcomes and contradictions. No native fabrication of preserve/irrelevant decisions. | Required for changed extraction response/assignment shape. Keep current complete-set and outcome validation until then. |
| **7. Reconciliation selections/keys — C1 minima done; C2c and §7A/B open** | [reference_reconciliation_validation](../../src/domain/reference_reconciliation_validation.zig), [repair](../../src/domain/reference_reconciliation_repair.zig), reconciliation schema | Required statement, signal and selected-repair selections now have `minItems: 1`; array eligibility still needs the selector decision. Kind consistency and coverage span entries and stay native. Token metadata is uniquely derivable after selecting one preserved-token claim; `local_key` additionally determines order, so its removal is not merely deleting an ID. | Business/preserved-token summaries and signals, initial/replacement paths, duplicate/shuffled keys, coverage, insertion/deletion retry identity and canonical readback. | Separate token-response cutover (§7A) and ordering choice (§7B). Do not change either simply to fix a presence constraint. |
| **8. Dispositions/conflicts — partial shape opportunity, native graph rules retained** | [reference_disposition_validation](../../src/domain/reference_disposition_validation.zig), reconciliation schema | Require at least two members for each conflict in the complete schema; preserve an empty conflict collection. Bedrock projects positive minima to one, so native cardinality remains necessary. Reuse `repairChoices` for choices valid with fixed siblings. Reciprocity, duplicate/superseded relationships, cycles and full coverage cannot be reduced to an enum. | One-member conflict, valid no-conflict state, duplicate dispositions, invalid targets, reciprocal/cycle failures and repairs with no independent legal choice. | No new authority for shape conformance; semantic disposition/default selection or grouped repair expansion requires a decision. |
| **9. Review membership — implementation closed, evidence open** | Support contract, review application binding, shared workflow and existing runner | C2b already removes response ordinals/batch completeness. Preserve origins, native collection order and current parent binding. Remaining feasibility concern is aggregate work and lifecycle coverage (§14.3), not another review scheduler. | Multiple source/principle subjects; invalid finding repaired before advancing; zero-policy-work path; stale/repeated delivery; cancellation, exhaustion and no partial publication. | C2a already approved; no repeat approval for that contract. Different grouping/parallelism would be new scope. |
| **10. Source-review evidence — §7F/P1 responsibility gap** | [specification_support_evidence](../../src/domain/specification_support_evidence.zig), support parsing/schema and [repair](../../src/domain/specification_support_repair.zig) | Derive only what `Rule.provenance` or `.claims.exact` determines. Fixed applicability is already handled. Aggregate subjects without fixed provenance, eligible subsets, independent `source_ids` and localized loss are not universally derivable. More schema constraints alone retain the redundant work. | Equivalent accepted native evidence; positive and loss/negative cases; selectable extra sources; retained-verdict repair; stored corruption rejected before model-shaped reconstruction. | P1/§7F model-versus-canonical contract amendment. No change to semantic verdict ownership or generation's explicit selections. |
| **11. Review detail/questions — C1 conditional detail done; native rules retained** | Support schema, [evidence admission](../../src/domain/specification_support_evidence.zig), [clarification_inputs](../../src/domain/clarification_inputs.zig) | Negative source findings and selected gap-detail repairs now require a nonempty detail; positive detail may be empty. The shared `detail` repair remains permissive because it also serves valid positive findings. Character minima cannot establish nonblank text, allowed controls or byte limits. | Empty valid positive versus empty invalid negative detail and selected gap repair have schema tests; whitespace, question, verdict and evidence rules retain native tests. | No new authority for existing text rules. Avoid a schema-language expansion just to replace native byte/control checks. |
| **12. Principle citations — C1/C2c conditional-choice gap** | [principle_assessment](../../src/domain/principle_assessment.zig), support schema and principle repair packets | Negative decisions require citations; compatible may omit them. Current `principle_finding` is an object with a `decision` enum, not distinct constant `kind` tags. Initial decision-conditioned minima cannot be added as arbitrary `if/then` to this compiler. Retained-decision repairs can select an appropriate canonical shape after a scoped change. Line order, chunk membership and quote relevance stay separate. | Compatible empty citations, negative empty rejection, valid negative evidence, foreign/duplicate chunks, reversed/out-of-range lines, repair/readback retaining the original verdict. | Named selected-repair shapes or a coordinated response change if needed; no automatic policy citations or Spec-source-claim conversion. |
| **13. Evaluator — C3 open conformance gap** | [packet](../../test/harness/packet.zig), [judgment](../../test/harness/judgment.zig), existing OpenAI/Bedrock harness adapters | Bind rubric criterion assignments in code and construct their complete collection; enums alone leave deterministic association in the model. Select evidence occurrences once and reconstruct exact quotes. Current reflection is not directly compatible with the workflow compiler (§14.2). Scores/relevance remain semantic; fixed score-null cases and totals are native (§15). | Both providers' actual prepared schemas; valid scored/uncertain/not-applicable judgments; duplicate/missing/foreign IDs, illegal scores, missing/false quotations, invalid applicability and no grade on rejection. | Decide the bounded schema integration before using shared projection. Response-format/retry changes need separate authority; no per-criterion call loop is implied. |

### 14.2 Schema and provider feasibility limits

The shared [schema restriction API](../../src/domain/model_result_schema.zig) currently
supports exclusion of constant `kind` variants and eligible integer values for a
direct property of such a tagged object. It does not identify arbitrary paths,
array-item selections, untagged line IDs or sibling-dependent relationships.
Using it for every `claim_id`-like field would conflate distinct eligibility rules.
Where a new restriction is justified, extend that existing typed contract narrowly,
checking the selected target shape, ambiguity, empty/oversized sets and stale
bindings. Carry it through packet cloning, selected-schema compilation, correction
diagnostics, capture and debugger readback. Do not add a second policy registry.

The closed compiler accepts disjoint `oneOf` branches (distinct JSON types or
distinct constant object `kind` tags). It does not accept arbitrary conditionals
or overlapping object branches. Therefore splitting principle decisions into
same-shaped `oneOf` alternatives is not a drop-in fix. Native relationship checks
are intentional; extending general JSON Schema is neither necessary nor approved.
Array uniqueness compares complete elements, so it cannot establish unique
subject IDs in otherwise different findings. [JSON Schema arrays](https://json-schema.org/understanding-json-schema/reference/array)

**Evaluator integration is more than selecting a provider flag.**
`packet.resultSchema` reflects unbounded strings/arrays/integers, nullable `anyOf`
and typed enums. The workflow compiler instead requires its bounded closed profile
and accepted union representation. Feeding that JSON directly to `compile` will
reject. Choose a compatible representation for the required semantic-only response,
either through the existing reflection owner or a deliberate adaptation to the
shared schema representation with justified limits and unchanged valid judgments.
Narrowing the existing echoed criterion IDs alone cannot close C3 under §15. Do not
invent bounds, relax the workflow compiler or duplicate provider keyword filtering
to force reuse. If adaptation changes acceptance, record that evaluator contract
decision. The evaluator remains development-only and cannot grant workflow authority.

Current primary-source checks support these boundaries:

- Bedrock supports only `minItems:0/1` and excludes numeric bounds and string-length
  constraints. Unsupported schemas reject before inference; distinct schemas can
  require grammar compilation, while identical schemas can use its 24-hour cache.
  SDDE's complete local schema remains authoritative; grammar reuse does not imply
  fewer prompt tokens. [AWS structured outputs](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html)
- OpenAI strict structured output requires every object property to be required
  and objects to disallow additional properties; nullable required values model
  optional data. It documents a 1,000-value aggregate enum limit. Preserve the
  evaluator's required/nullable shape and check this provider's limits separately
  from SDDE's approved 1,024-value **per-enum** bound. This is not authority to lower
  the engine's global bound or apply Bedrock's profile to OpenAI requests.
  [OpenAI structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
- AWS documents reasoning preceding response content; it does not establish the
  cause of the retained reasoning-only outputs. Missing final text remains a
  provider observation, not an excuse to consume reasoning as the answer or add
  retries. [AWS OpenAI model parameters](https://docs.aws.amazon.com/bedrock/latest/userguide/model-parameters-openai.html)

Reference-preserving `$defs` serialization remains optional optimization work.
The current compiler/projection expands references. Any future change must preserve
diagnostic paths, selected restrictions, resource bounds and captured-schema
round trips; there is no evidence that it is needed for correctness. Alternative
1's metadata cleanup maps to §7A/E/F. Alternative 3's omission of fixed selectors
needs the same owning model/canonical distinction; a singleton exact catalogue
does not establish that business text ought to include that occurrence. Never
insert an exact segment just because it is the only eligible one.
However, once the model selects that exact-copy branch, a single permitted
occurrence determines its ID. Construct it in code rather than requiring a
singleton-enum echo. §§15.4–15.5 distinguish this from deciding whether to use it.

### 14.3 Remaining architecture, traceability and effectiveness work

| Remaining change / classification | Existing owner/file | Reason and feasible boundary | Required evidence | Contract decision |
| --- | --- | --- | --- | --- |
| **C2b retained-memory/scale — evidence gap with code-supported risk** | `collectFocused`/`validateWorking`, [retained_candidate](../../src/application/retained_candidate.zig), review binding | Each append allocates the full entry/origin prefix, reruns full validation and retains declared input parents. Retained prefix copies can total `N(N+1)/2`; complete validation also rescans prior entries/required subjects. Cleanup exists; this is not a demonstrated leak. Measure before changing ownership. | Source/principle sets at increasing sizes; peak retained bytes, allocation count, validation time, teardown, OOM/cancellation after several findings and dependent rebuilding. Distinguish shared source bytes from repeated projections. | None to measure or correct an established ownership defect within current contracts. Do not remove required parents, cache stale results or introduce another retained store merely for speed. |
| **C2b request/context cost — evidence gap, no savings requirement** | Review packets, selected-schema/request owners, existing capture/accounting | The recorded 29-request fixture and projected 33-request historical case use different inputs and are not a before/after comparison. Focused source packets retain broad reference/candidate context; principle packets retain policies and candidate context. Context removal may harm cross-requirement review. | Match ledger, candidate, policies and repair scope for comparisons. Record compiled graph/schema sizes, provider/guidance schemas, full initial/repair/correction bytes, calls, native resources; obtain actual tokens/latency only from approved calls. | Larger finite preconfigured budgets are permitted for improved outcomes. Changing the semantic assignment or omitting required context requires an explicit contract assessment, not silent truncation. |
| **P2–P3 occurrence links — new output extension, high feasibility** | Reference support/items, specification provenance/projection, [reference_context](../../src/domain/reference_context.zig), completed and pending output actions | §13 supplies the implementation plan. Use admitted per-unit lineage, not raw handle enumeration or coverage as alternate authority. Completed records can project links; pending state retains no generated records and must supply no such map. Derived sidecar data requires no persistence field. | Separate `[1,2]`/`[3]` requirements, repeated text occurrences, both many-to-many directions, stable anchors/escaping, canonical rerender and pending-output sibling path. | Approve reference-view layout/binding. Inline `spec.md` metadata would additionally amend its parser grammar. Storing pending records is excluded, not an implicit traceability requirement. |
| **P4 original IDs — conditional capture extension** | Existing source reader, ingestion, evidence and snapshot owners | Current snapshots have captured bytes/locations but no structured source-requirement association. Span links can ship first. Explicit original labels require a specified source format and association boundary; nearby headings, claim ordinals or prose similarity cannot supply them. | Qualified document/version/ID associations, ambiguity and stale rejection, multiple generated requirements per original and multiple originals per generated; missing IDs use captured spans. | Source contract plus any closed snapshot/state-version amendment. No independent mapping, invented version or compatibility reader. |
| **P5–P6 repair/readback/reuse — verification extension** | Existing ADR 0020 repair and state owners; non-Spec registered audit fixture | The single-claim contract, owning-unit unions, invalid-handle bound `B`, sibling protection and non-Spec resolution already exist. Extend tests for the new projection. The audit fixture proves reference reuse, not arbitrary focused-review scheduling; test that separately through existing generic runner operations as part of the architecture-wide completion evidence in §15. | Same trace after authorized repair/load; changed authority rejects; no cross-record support. Unrelated policy and nested/optional fields remain distinct; focused assignments cannot reset an unrelated consumer's retry allowance. | No new authority for existing invariants. New production consumers retain their own eligibility, coverage, approval and evidence types. |
| **C4 semantic usefulness and Phase 4.2 — open live acceptance** | Generation/review owners, existing E2E harness and rubric evaluator | Current offline success proves containment/assembly, not model detection of literal-only stories, false positive support or false conflicts. Require better outcomes even if tokens rise. Preserve independent exact coverage, semantic review and publication gates. | Approved paired review probes with valid and well-linked-but-wrong candidates, then whole production generation/publication/readback and criterion-level rubric results. Include unrelated obligations, false acceptance/rejection, necessary versus spurious clarification and recorded budgets/usage. A null grade threshold is not a quality pass. | Separate approval for each live/E2E run; no live approval inferred from this review or budget direction. No new reviewer, fallback route or retry system. |
| **Missing final answers/settings — unresolved cause, bounded diagnostic option** | Existing provider decoder, request retry/accounting and [ADR 0019 debugger](../../design/decisions/0019-single-request-debugger.md) | No evidence establishes that schema cleanup or a setting fixes absent final content. Existing debugger permits prompt/context/schema edits at captured settings. A settings-controlled replay cannot be implemented by bypassing that boundary. | Retained raw response, decoded final text, finish reason, actual usage and exact request identity. Separate protocol validity, semantic quality and workflow results. | Prompt/schema replay still needs live approval. Provider/model/reasoning-setting replay needs a scoped ADR 0019 amendment; alternate configured E2E runs are not identical-request comparisons. |
| **P7 documentation/validation — required follow-through** | Affected design contracts, F0100, existing test owners and build steps | Correct stale token/citation examples and still-pending cutover descriptions with the agreed implementation, preserving accepted ADRs and Proposed design status. Remove only superseded response/repair branches; defensive canonical checks remain. | Closed removed-field rejection, accepted/rejected fixtures, targeted tests, architecture/schema checks, full `zig build verify` and relevant clean-environment smoke when implementing cross-cutting changes. | Amend only the owning contracts approved for that chunk. This documentation review does not modify them. |

Two contracts merit explicit protection during §7E/F:
`validateStored` validates each canonical evidence record through
`evidence_admission.validate` **before** reconstructing a model-shaped finding,
then revalidates the collection and compares retained evidence. Keep that ordering
when fields disappear from model output, so reconstruction cannot erase corruption.
Likewise, deriving fixed positive evidence does not permit changing a retained
verdict or its original evidence bound during a value-only repair. Initial,
selected-repair, correction, renewal and persisted paths must share the same owner.

No extra readback gate is required: completed output preparation already parses
canonical state before publication, and the existing oracle checks persisted byte
equality. Fresh-runtime, stale-contract and corrupt-state tests remain separate.
No generic source-claim model may subsume clarification answers, policy citations,
approved files/commands or other operational capabilities. Future Plan/Tasks/
Implement contracts are included in the architecture-wide audit in §15, without
claiming their production model integrations exist. Multi-snapshot attribution
still requires its own explicit binding contract; no new workflow or namespace is
created merely to complete the current deterministic-responsibility audit.

### 14.4 Recommended sequence and review evidence

1. Record an equivalent-input baseline and extend the existing owners' tests for
   the selected chunk. Preserve completed C2b and ADR 0020 behavior; measure focused
   memory/lifecycle at scale. Do not repeat the single-claim or batch-removal work.
2. Implement C1's supported presence corrections and project the already-fixed
   entity decision into offered choices as bounded conformance changes. Treat relational rules as
   native unless a specific extension is justified. Assess earlier protocol
   rejection and complete-response correction, not just schema acceptance.
3. Settle §7E/F/P1's model/canonical contracts and P3's view layout. Prioritize fixed
   bookkeeping removal and useful per-requirement traceability over speculative
   schema compression. P2–P3 can proceed independently of conditional P4. C3's
   evaluator is an independent required track, including native criterion binding
   and exact-evidence reconstruction. Resolve and implement §7A/B's required
   response/ordering changes; do not defer deterministic residue as optional.
4. Validate each implemented cutover through current test/build owners, including
   its consumers, repairs, readback and output. Update only affected contracts and
   remove superseded paths together. No prompt additions merely to restate facts
   that a model response no longer returns.
5. Obtain separately approved semantic probes and whole-path execution with explicit
   finite generation/grading budgets. Accept increased token cost when outcomes
   improve; report useful completion and rubric evidence alongside spend. Do not
   present offline schemas, byte reductions or fixture success as live reliability.

**C1 and fixed-entity implementation (27 September, offline):** Required
typed-text arrays and literal strings, extraction citation selections,
reconciliation statement/signal/selected-repair claim selections, and negative
source-review details now expose their unconditional native minima in the
existing schema resources. Positive detail, empty claim/signal inventories,
empty explicit Spec support where exact evidence can supply it, and other lawful
empty collections remain valid. The accepted entity disposition narrows the
records schema through the existing packet and `ExcludedVariant` owner;
`required` still uses native membership validation. The shared text-choice
projection preserves unrelated fixed exclusions. Scripted complete-response
corrections now recover empty citations, selections and detail at the schema
boundary; whitespace and relational defects still exercise native validation.
No model or E2E call was made.

Offline validation for this slice passed with `zig build test -j1 --summary
failures` and `zig build verify -j1 --summary failures`, including the
repository scenario suite and packaged-runtime checks. These checks establish
contract behavior, not live model reliability.

Equivalent-input size audit used the committed schema resources as the before
baseline, the current compiled selected schemas as after, and the same fixed
user content in an offline Bedrock `encodeText` request. Values are bytes, not
token counts. The provider profile drops string-length minima while retaining
positive collection minima; the complete schema still validates both.

| Selected response | Complete schema before → after | Bedrock schema before → after | Controlled request before → after |
| --- | ---: | ---: | ---: |
| Extraction claim | 4,879 → 5,081 | 3,948 → 4,052 | 9,971 → 10,307 |
| Reconciliation global | 7,324 → 7,553 | 5,985 → 6,102 | 14,829 → 15,209 |
| Generation records | 10,424 → 10,829 | 8,464 → 8,659 | 20,884 → 21,544 |
| Source-review finding | 11,683 → 11,753 | 9,412 → 9,412 | 23,271 → 23,351 |

With the fixed `not_applicable` entity decision, the same controlled records
request is 18,089 bytes after selection versus 20,884 bytes before this slice.
These are offline shape measurements; they say nothing about live quality,
provider token accounting or whole-workflow reliability. C2c/§15 still owns
the remaining deterministic bookkeeping and traceability changes.

**Checks actually run during this review:**

- `zig build test-specification-generation test-model-request-workflow test-model-candidate-json --summary all`
  — **9/9 steps, 585/585 tests passed** (218 generation, 307 request-workflow,
  60 candidate-JSON). These inspect the current dirty worktree, not an isolated commit.
- `zig build test-rubric-evaluator --summary all`
  — **3/3 steps, 60/60 tests passed**, using offline harness tests.

These runs add confidence in existing behavior; they do not implement or test the
proposed new contracts. No implementation/test source was edited, no live model or
E2E call was made, and full verification/packaging was not rerun for this
documentation-only review. Earlier full-suite results remain labelled with their
original scope. `git diff --check` passed and all relative file-link targets exist.
Link validation checks target files, not external URLs or Markdown fragment IDs.

## 15. Required end state — all deterministic responsibility belongs in code

**User-directed scope amendment, 27 September 2026.** The user requires all
deterministic items to move out of LLM responsibility, considering the entire
architecture. This supersedes the optional/deferred treatment of deterministic
residue in earlier assessments. The direction is settled; this document update
does not implement code, select an unspecified ordering/response contract, approve
live calls or amend unrelated accepted authority. Concrete representation decisions
must be recorded in their governing contracts before their implementation.

This is one architecture-wide program delivered in cohesive chunks. A chunk can
finish while the program remains open. Completion cannot be declared after only
provenance, Spec generation, focused review or a successful example. A deterministic
item awaiting a contract decision stays a named open obligation, not an optional
optimization. Higher token cost is acceptable when outcomes improve; removal of
determined work does not depend on proving token savings or observing a live error.

### 15.1 What must leave the model boundary

For every model-returned field, relationship and collection duty, ask whether its
value is uniquely determined by **current validated inputs, the native assignment,
accepted semantic choices and an existing rule**. If so, its owning code must
construct it, including conditional facts determined only after a semantic choice.
Omit that value from the model response and selected-repair shapes; construct the
canonical representation after validating the choice. Keep useful derived facts
in model **input** when they help interpretation, without requiring an output echo.

| Category | Required treatment |
| --- | --- |
| Assigned identity, known subject set, counts, order under an accepted rule, fixed status, invariant empty/null values | Bind, enumerate, construct and assemble through native owners. No model-assigned bookkeeping key or repeated fixed field. |
| Consequences of a selection | Validate the selected occurrence/relationship once, then derive its token, exact bytes, citations, document/span identity, effective provenance and any rule-determined dependent values. No repeated join in another response field. |
| Mechanically decidable validity, eligibility, coverage, currentness and completion | Compute/check in code. Never ask a model to certify a graph, calculate a union, report executable success or choose whether a mandatory gate applies. Native validation still checks genuine model choices. |
| Genuine semantic selection or new content | Retain it: relevant claims, classification, relationship targets, useful prose/code, semantic dependencies, review verdicts, score/relevance judgments and unresolved business questions. Several eligible choices do not identify the right one. |
| Missing authority or undefined policy | Establish the owning contract/decision or reject through the existing boundary. Do not invent a deterministic default, guess a source association or make the model supply missing engine policy. |

Do not equate “checkable” with “constructible.” Knowing that a story must be
nonempty does not supply its business meaning. Knowing required FR/AC families
does not determine the number or content of requirements. Native code owns the
family obligations and completeness gate; the model still writes and selects
semantic content. Similarly, an exact-copy candidate being the only eligible
candidate does not mean it must be used.

An ID used to **select** an occurrence, file, policy span or relationship can
encode a semantic choice where alternatives matter; that does not make the ID
field itself indispensable. Assess whether a bound assignment can instead ask
for the semantic decision and associate it natively (§15.5). An ID merely restating
an assigned subject or the only occurrence permitted by a chosen branch must
disappear from returned data. Necessary JSON structure and
tags distinguishing genuine semantic alternatives remain encoding; fixed unit
identity/status must not be disguised as such a tag. Native construction is not
silent correction of untrusted fields: removed fields reject under the new closed
model shape, while stored canonical fields remain strictly validated.

For `provenance.claim_ids`, apply the concrete rules and samples in §15.4. Do not
retain a universal model-required provenance object merely because the canonical
record owns one, or omit a genuine semantic evidence choice merely to simplify JSON.

### 15.2 Architecture-wide responsibility and change matrix

Statuses below distinguish confirmed current gaps from existing owners and
proposed downstream contracts. The four current Spec schema resources and the
evaluator's reflected response are concrete audit entry points, not the complete
scope of the program. Every registered operation with a model result must be
accounted for, including configured composition parts and selected repairs.

| Surface / status | Deterministic responsibility and existing owner | Remaining model work | Required change and evidence / decision |
| --- | --- | --- | --- |
| **Ingestion, source occurrences and extraction — existing mechanics plus confirmed association gap** | [reference_ingestion](../../src/domain/reference_ingestion.zig), [source_selections](../../src/domain/source_selections.zig), [structured_tokens](../../src/domain/structured_tokens.zig), [classification validation](../../src/domain/token_classification_validation.zig): inventory, scope/span resolution, token bytes, candidate identity and complete known-candidate accounting. | Claim meaning, relevant ranges and preserve/irrelevant classification where policy allows a choice. | Remove classification identity echoes through native assignment/binding and collection construction; keep pre-ledger candidate identity distinct from `ClaimId`. `choices(.no_feature_claim)` permits only irrelevant: once that outcome is valid, construct the forced result rather than asking for repeated decisions. Define the coordinated extraction/composition response contract and validate all candidates/outcomes, stale scopes, zero work and repair identity. No automatic irrelevant classification where genuine choice remains. |
| **Reconciliation — required §7A/B and additional association/constants** | [reconciliation validation](../../src/domain/reference_reconciliation_validation.zig), [disposition validation](../../src/domain/reference_disposition_validation.zig), [repair](../../src/domain/reference_reconciliation_repair.zig): selected token join, citation unions, IDs, keys/order, known disposition subjects, graph checks and canonical unresolved status. | Summary/signal meaning, claim grouping, retained/duplicate/superseded/conflicting choices, directional targets and conflict interpretation. | Remove redundant `token_id`, mechanical `local_key`, assigned disposition `claim_id` echoes and `conflicts[].resolution` (currently only `unresolved`). Native binding must associate each decision; retain selected relationship IDs. Define ordering and response shape first. Derive duplicate relationship facts only where accepted semantics determine them; never invent reciprocal meaning to repair an invalid graph. Cover summaries/signals, coupled conflict repair, insertion/deletion, retry identity and snapshots. |
| **Generation and provenance — §15.7 runtime cutover in worktree** | [specification_generation](../../src/domain/specification_generation.zig), [session](../../src/domain/specification_session.zig), [provenance](../../src/domain/specification_provenance.zig), [reference_support](../../src/domain/reference_support.zig): unit binding, record IDs, exact occurrence expansion, `S + E`, citations and source links. | Business text, applicability and record meaning; reconciliation chooses the semantic signal grouping and generation roles. | Model responses reject `provenance` and fixed ID/citation echoes. Retain closed response, cross-batch, repair, stale-input and readback tests, full offline verification and separately approved live quality evidence. Structured original requirement IDs remain conditional on captured associations. |
| **Source/principle review — source response cutover in §15.7; principle audit open** | [specification_support](../../src/domain/specification_support.zig), [evidence rules](../../src/domain/specification_support_evidence.zig), [source_omission](../../src/domain/source_omission.zig), [principle_assessment](../../src/domain/principle_assessment.zig): assignment, membership, native applicability, origins and fixed evidence. | Source verdict, useful explanation/question, additional source choices and loss location; policy citation selection remains a separate semantic choice. | Source responses omit `provenance`, fixed loss and claim echoes; the engine constructs canonical evidence through the bound subject. Preserve source-only evidence and stored-evidence validation. Audit principle-specific conditional citations without converting them into source claims. |
| **Clarification and required-authority reconciliation — existing native ownership; audit every producer** | [required_authority](../../src/domain/required_authority.zig), [required_authority_clarifications](../../src/domain/required_authority_clarifications.zig), [clarification_preparation](../../src/domain/clarification_preparation.zig), [refresh](../../src/domain/clarification_refresh.zig), existing clarification actions: owner/subject/slot, requiredness, IDs, deduplication, answer schema, admission, status transitions and protected-form rendering. | Wording and explanation of a genuine semantic gap; human answers/approvals retain their own authority. | Do not ask for owner-stage choice, generated clarification IDs, answer-schema echoes or status/completion claims. Preserve candidate/engine-failure precedence, earliest-stage routing, current answer binding and closed-file protection. If a model selects a genuinely unresolved family/subject among alternatives, retain that semantic selector and derive its consequences. Test mixed defects/gaps and cross-stage routing. |
| **Generic model execution, composition and repair — existing owners; complete boundary audit required** | [model_request_preparation](../../src/domain/model_request_preparation.zig), [identity](../../src/domain/model_request_identity.zig), [schema](../../src/domain/model_result_schema.zig), [json_composition_runtime](../../src/domain/json_composition_runtime.zig), [atomic_repair](../../src/domain/atomic_repair.zig), existing runner/request/progress bindings: selection, assignment identity, schema projection, assembly, dependencies, preconditions, diagnostics, retirement, usage and retry accounting. | Only the remaining semantic result or authorized replacement. | No model merge pass, target/revision echo, retry plan, derived diagnostic, success flag or final collection bookkeeping. Use native reconstruction when one authorized replacement is uniquely determined; native failure still needs model repair when its solution is semantic. Keep structural composition free of evidence policy. Audit initial, selected, composed, correction, repair and dependent-rebuild shapes; no extra scheduler, retry engine or writable state. |
| **Plan — proposed production contract, included in this audit** | [§18](../../design/contracts/18-plan.md), [§7 representations](../../design/contracts/07-domain-representations.md), [§33 migration](../../design/contracts/33-prompt-migration.md): repository facts, file/path candidate identities, artifact paths, known obligations, coverage, approvals and view construction. | Architecture, relevant fact/file selection, semantic name-source/path-candidate choices, design tradeoffs and justified proposals. | Audit downstream proposal keys and repeated project/environment/kind/template facts against their selected options; assign identity and expand bound facts in code. Resolve any unknown-proposal association contract explicitly. No model-generated registry facts, derived filenames, artifact manifests or approval state. Do not claim an implementation exists merely because the design names an action. |
| **Tasks and Implement — proposed production contracts, included in this audit** | [§19](../../design/contracts/19-tasks.md), [§20](../../design/contracts/20-implement.md), existing generic execution/authority owners: obligation ledger, canonical IDs, graph construction/topological order, required commands/evidence, resource locks, safe parallel markers, authorization, copy bytes, expected target state and completion. | Work decomposition, non-obvious dependencies, allowed optional command/file/source selections, code and semantic repair. | Audit `internalKey`/proposal identity, repeated assigned file/task/source IDs, edge endpoints and operation preconditions. Native-assigned handles must support later genuine dependency choices; do not guess semantic edges from order or similarity. Preserve approvals, write sets, command evidence and whole-workflow publication. Record required design amendments without implementing missing workflows as an incidental provenance patch. |
| **Rendering, traceability, state loading and publication — existing owners plus P2–P4 extensions** | [specification_projection](../../src/domain/specification_projection.zig), [reference_context](../../src/domain/reference_context.zig), [specification_state](../../src/domain/specification_state.zig), [workflow_output](../../src/domain/workflow_output.zig), existing output actions: headings, links, IDs, status, manifests, serialization, validation and publication ordering. | None for mechanical presentation or persistence. Summaries may contain semantic prose but cannot establish status or evidence. | Derive requirement → effective claims → captured occurrences from the sole ledger. Preserve original requirement IDs only through validated captured associations. Do not add writable provenance, infer boundaries, populate pending records or import generated sidecars as authority. Recompute/compare on load; tampering must fail rather than be overwritten by reconstructed values. |
| **Rubric evaluator — required broader C3 transfer** | [capture/contracts](../../test/harness/contracts.zig), [packet](../../test/harness/packet.zig), [judgment](../../test/harness/judgment.zig), current harness execution/reporting: rubric subjects, result association/order/count, exact evidence bytes, null score for unscored decisions, weights, totals, thresholds and report status. | Score, applicability/uncertainty, explanation, evidence relevance and whether meaning is missing from the specification. | Replace echoed `criterion_id`/complete-list bookkeeping with native assignments and assembly. Replace reproduced `quote` bytes with one exact captured occurrence selection; derive the document identity when the selector already binds it. Define occurrence/range and assignment contracts, including Unicode/repeated text and score-conditional shapes. Do not use similar-text matching or infer semantic absence from missing quotes. Keep harness authority separate and use its existing execution/accounting owner; no new evaluator retry system. |
| **Other registered workflows, provider adapters and diagnostics — required shared proof** | Generic registry/runner, existing provider serializers, [request-workflow tests](../../src/model_request_workflow_test.zig), architecture tests and captured-request/debugger owners. | Each registered domain's actual semantic choices; provider observations remain external input. | Exercise native assignment/reconstruction with an unrelated registered consumer as well as existing reference reuse. No workflow-name branches, Spec eligibility leakage, hand-written provider acceptance policy or models calculating usage. Capture/replay derives exact schema/request metadata without granting workflow authority. Unknown workflow shapes are not interpreted by property names; the registered native contract owns their meaning. |

Known-set membership is mandatory engine work across extraction, disposition,
review and grading. Merely constraining echoed subject IDs to enums leaves that
responsibility in the model. Reuse native assignment and typed progress, choosing
a coherent semantic unit for each domain. This does **not** mandate one call per
property, expanded per-subject schemas or an unchecked positional list. If an
assignment returns several results, its contract must bind their roles exactly and
code must prove complete association. Unknown-length semantic lists remain valid;
assign their mechanical identities after admission, then expose those handles for
subsequent semantic selections when needed.

### 15.3 Inventory and completion evidence

Extend the tables in this document into the implementation's complete field/duty
inventory; do not add a runtime responsibility registry. Enumerate from configured
resources, compiled selected schemas, registered native contracts and evaluator
reflection. Include nested fields, conditional branches and derived relationships,
not just property names. For each entry record:

- native owner and validated input/choice from which it is computed;
- current model, canonical and persisted representations;
- disposition: already native, required transfer, genuine semantic choice or an
  explicit unresolved contract decision;
- for each retained selector, the unresolved semantic alternatives and why a
  native assignment does not already determine its value, including after another
  choice; evaluate assignment redesign rather than assuming the existing field is necessary;
- every producer/consumer, initial/selected/correction/repair path and dependency
  invalidation/readback path;
- removed model field/duty, canonical reconstruction, governing amendment and
  accepted/rejected regression evidence.

No retained output field may be labelled “semantic” merely because it is currently
generated by a model. Give its actual choice or judgment. No known deterministic
residue may disappear into a deferred list. Decisions about ordering, new-source-ID
capture, assignment binding or occurrence selection must stay visible until settled;
incomplete inventory or unresolved required transfers keep the overall work open.
Proposed workflows receive an explicit contract disposition, not a false runtime
completion claim or an obligation to implement every future workflow now.

The overall completion gate requires all of the following:

1. **Responsibility transferred:** every current model boundary is inventoried;
   no determined response field or known-set bookkeeping duty remains delegated.
   Native construction is exercised from minimal semantic responses. Compiled
   selected schemas and actual prepared requests omit removed fields, including
   repairs/corrections; closed decoders reject their reintroduction.
2. **Authority preserved:** no guessed evidence, invented requirement boundary,
   default semantic verdict or unsupported operational capability. ADR 0020's
   `S`, effective union, original `B`, sibling protection and stable retry identity
   remain. Stale/unknown/wrong-kind/out-of-scope inputs reject. Native repair cannot
   expand an evidence bound; reconstruction on load cannot conceal corruption.
3. **Architecture covered:** related producers/consumers change together through
   existing owners; generic code imports no Spec policy. Shared mechanics work for
   an unrelated registered consumer. Clarification, policy, source, approval and
   execution evidence retain distinct authority. No new agents, stores, hidden
   model loops, retries, compatibility paths or policy in structural composition.
4. **Validation complete:** accepted and rejected cases cover forced constants,
   conditional empties/nulls, known-set omissions, unknown-length semantic lists,
   repeated source text, many-to-many traceability, repair/renewal, persisted
   tampering and cleanup/scale. Run owning tests, architecture/schema checks and
   complete repository verification, including applicable packaging smoke, for
   implementation changes. Update affected contracts and remove only superseded
   schemas, prompts, decoders and unreachable repair branches together.
5. **Outcomes measured:** compare equivalent-input compiled schemas and complete
   initial/repair/correction requests, call counts and native resources. Separately
   approved live tests measure source fidelity, useful requirements, false review
   acceptance/rejection, clarification quality, completion/readback and rubric
   results alongside actual tokens/latency. Increased cost is acceptable for better
   outcomes; offline success establishes neither live reliability nor semantics.

Sequence the work by dependency: inventory and settle missing contracts; complete
conditional/fixed-field construction; transfer known-subject association in all
remaining domains; derive rendering/evidence views; verify the full producer–repair–
readback path and cross-workflow reuse; then obtain approved live outcome evidence.
C1 shape conformance supports these transfers but cannot substitute for them.
Earlier completed work remains closed and reusable. A successful C2b measurement
or P1–P3 implementation alone does not complete this broader requirement.

**This update:** documentation only. Additional review inspected all four current
Spec schema resources, extraction/classification, reconciliation, review/loss,
generation, clarification, evaluator response owners and downstream design contracts.
No code, tests, accepted ADRs or governing contracts were changed. The earlier §14
test results are not new runs for this amendment; no live calls were made.
Documentation validation: `git diff --check` and relative file-link checks passed;
the architecture matrix has consistent Markdown table columns. No code tests were
rerun for this documentation-only amendment.

### 15.4 Remove provenance from model responses

**User decision, 27 September 2026:** no model response may contain
`provenance`, including a nonempty `claim_ids` selection. The earlier P1
source-review and generation schemas permitted it; the coordinated cutover in
§15.7 replaces those shapes. Canonical `provenance.claim_ids` remains the
engine's explicit-selection record; this decision does not let the engine
invent semantic support. ADR 0020 now separates model and canonical fields.

The native assignment selects the applicable closed response shape before dispatch:

| Evidence situation for one owning unit | Model response | Native reconstruction |
| --- | --- | --- |
| Explicit support `S` already fixed by current validated authority | Content only; `provenance` is absent and forbidden. | Retain the exact bound `S`; derive `E` from the returned exact segments and compute `L = stableUnique(S + E)`. Apply any existing fixed-effective-evidence repair bound as well. |
| The contract explicitly fixes `S=[]`; eligible exact segments supply support | Content only; express only unresolved use/placement/occurrence choices. No empty provenance or determined exact-ID echo. | Construct canonical exact segments from the bound choice, store `S=[]`, and derive `E` and `L`. For source-backed Spec, absent/ineligible exact evidence cannot produce valid empty effective support. |
| Support remains genuinely unbound after reviewing the assignment boundary (§15.5) | Do not dispatch content that requires a model `provenance` field. Establish the semantic association through a validated per-unit assignment before authoring. | Resolve the bound association to `S`, then derive `E`, `L`, citations and source links through the existing owner. If no valid binding exists, block rather than guess. |

These are distinctions in the existing typed assignment/response contract, not a
model-returned mode flag, new runtime policy registry or another provenance store.
Every selected model schema must reject `provenance`. Do not add an optional-field
decoder or a fallback that inserts all eligible claims. Derive the selected
schema, decoder and native construction from the same bound facts through the
existing packet, registered operation and schema owners.

**A fixed support binding needs real authority.** Existing value-only repair
already retains explicit support and its effective bound. Fixed review rules also
already identify exact required evidence. Reuse those facts. Current initial
record generation does not fix per-record support simply by offering claims in
`specification_session.packetForChoices`. Initial content-only authoring needs a
documented per-unit assignment contract backed by an explicit prior accepted
selection or an accepted native rule identifying that unit's source obligation.
Bind it to the current ledger, subject and dependencies; do not invent the
association from similar prose, a lone eligible claim, a source filename or a
batch-wide catalogue. Semantic review must still reject content unsupported by
that bound evidence.

**Approved assignment design (27 September):** reuse validated reconciliation
signals as source-obligation groups. Reconciliation classifies which groups
support each feature-level field; the engine validates those roles and binds
the current group before each authoring task. Record generation iterates the
bound groups: one task may return several requirements, while a group spanning
several source claims permits one requirement to trace to several originals.
Overlapping groups permit one original to feed several generated requirements.
The record response contains business content only. Group membership and claim
identity come from the existing reconciliation/reference owner; neither array
position in a broad unbound batch nor text similarity may choose support.
Unassigned units block or return to source reconciliation as an engine defect.
This is the approved contract to implement, not current runtime behavior.

If support is not determined, preserve the genuine choice in the owning
assignment contract before requesting content. First evaluate native
subject/evidence binding under §15.5; it can remove returned identifiers without
claiming that code decided semantic support. A broad unbound synthesis response
is incompatible with the user decision. Moving the same ID selection into
another model call solely to hide it from the writing response is not
deterministic reconstruction. A fixed assignment cannot
silently acquire different support because the generated text would need it;
use existing explicitly authorized evidence-change/rework paths or reject the
candidate. Do not turn that failure into a request for missing user information.

**Preserve the distinction between `S` and `L`.** A bound `S=[1]` plus exact
claim `2` constructs canonical `provenance.claim_ids=[1]`, with effective claims
`[1,2]`; it must not store `[1,2]` as explicit selection. A bound `S=[]` plus exact
claim `2` stores `[]`, with effective claims `[2]`. Review evidence rules may
require the effective list, but that checked review projection must not overwrite
the content's explicit selection. Fixing `S` alone does not fix `L`: value-only
repair must also preserve the original effective claim/citation sets or ADR 0020's
original invalid-handle bound `B`, including outside siblings.

Bindings remain per owning field or shared-provenance record. Multiple fields
within one record contribute exact dependencies to that record's union. Another
record does not inherit it. If a coherent request returns several records, bind
each known role independently or establish each record's genuine evidence
association before authoring; do not give every output the whole request's
support. Preserve many-to-many source
traceability without inventing original requirement IDs.

**Owning change and contract decision:** coordinate
[specification_session](../../src/domain/specification_session.zig),
[generation parsing/admission](../../src/domain/specification_generation.zig),
[model/canonical representations](../../src/domain/specification.zig),
[provenance](../../src/domain/specification_provenance.zig),
[generation schema](../../design/workflows/spec/generation.schema.json), and their
existing repair, review, projection and state consumers. Record the focused
§§7.1/12/17/22 and ADR 0020 model-field amendment; preserve its evidence semantics.
Canonical explicit selection remains the single persisted selection authority.
Assess any contract-binding/state-version consequence through existing readback
owners; loading cannot depend on a live request ledger or replace corrupt stored
selection with a freshly inferred one. No second writable selection store or
compatibility reader is permitted. Registered non-Spec consumers may reuse the
mechanics with their own evidence policies.

**Response samples.** These show payload fragments for native-selected
assignments; the complete response also has the selected generation envelope.
The ID-free exact marker is model-only; canonical segments carry their resolved ID.
All evidence and wording below are illustrative.

**A. One record whose explicit support is already bound to claim `3`.** Its bound
source obligation is to email a receipt after an order is accepted. The model writes
the requirement without echoing the source selection:

```json
{
  "content": {
    "kind": "functional_requirement",
    "text": [
      "When an order is accepted, the system MUST email a receipt to the customer."
    ]
  }
}
```

The engine constructs canonical `S=[3]`, `E=[]`, `L=[3]`, then derives citations
and recorded source links. It assigns the generated requirement ID. The binding
must precede the response; this example does not authorize guessing `[3]` afterward.

**B. Exact occurrence determined; surrounding wording/placement still selectable.**
The assignment fixes `S=[]`, and its exact-copy branch permits only claim `2`,
the captured occurrence of `Order confirmed.`. The model can choose to use that
branch, but must not echo its uniquely determined numeric selector:

```json
{
  "value": [
    "Confirmation: ",
    {"kind": "exact_copy"}
  ]
}
```

The engine constructs canonical `{"kind":"exact_copy","claim_id":2}` from
the bound branch, then `S=[]`, `E=[2]`, `L=[2]` and the captured bytes. No marker
means no inferred use; empty effective support still rejects where required. If
the entire field is already fixed to that exact occurrence, code constructs it
directly and there is no model task for the field. This replaces the earlier B
example that needlessly returned `claim_id:2` for a determined occurrence.

This is a field payload, not a complete business requirement or a positive
semantic verdict. Multiple eligible occurrences require an explicit choice or a
valid narrower assignment; an unqualified marker must not pick one. If used for
repair, the original effective bound must permit the occurrence. Empty `S` grants
no new repair scope.

**C. A record whose supporting business claim was a semantic choice.** Claim
`1` describes confirmation behavior; exact claim `2` records its required message.
The association with claim `1` must be accepted and bound to this record's
assignment before the content response. The exact-copy branch has only
occurrence `2`, so its numeric ID is constructed in code:

```json
{
  "content": {
    "kind": "functional_requirement",
    "text": [
      "When an order is accepted, the system MUST display ",
      {"kind": "exact_copy"},
      " to the customer."
    ]
  }
}
```

The engine stores bound `S=[1]` and derives `L=[1,2]`; the separate record in A
remains supported only by `[3]`. The content response contains no provenance.
Without the prior association, this response cannot be admitted as supported.

**Required acceptance evidence:** initial, selected-repair and correction schemas
must forbid provenance and determined exact IDs, rejecting unexpected echoes.
The assignment must retain any genuine semantic association. Test A/B/C
together; wholly native fields; absent marker versus chosen marker; ambiguous
markers under multiple occurrences; independent records; exact occurrences with
equal text; no-exact/empty-support rejection;
foreign, wrong-kind and stale bindings; legitimate explicit support overlapping
`E`; fixed repair evidence and retry identity; and strict canonical readback.
An omitted field must never expand support, select a workflow mode or hide stored
corruption. Compare the compiled model-facing schemas and full prepared requests
before/after; retain independent semantic review, coverage and publication gates.

The later coordinated implementation is recorded in §15.7. These examples do
not authorize a live model call; live quality remains a separate gate.

### 15.5 Claim-ID necessity review — five required follow-ups

**Reviewed 27 September 2026.** A deterministic item must never be a model
responsibility, including a value determined only after another semantic choice.
Internal source identity and model-returned identity are different requirements.
ADR 0020 defines today's accepted contract; its existence and passing tests do
not establish that every field should remain model-facing. The five findings below
refine C2c/§7E–F and §15's architecture-wide mandate, not a new provenance project.

| Required follow-up / classification | Existing owner/file | Reason and proposed treatment | Required test/evidence | Contract decision before implementation |
| --- | --- | --- | --- | --- |
| **1. Remove determined exact selectors — confirmed response residue; earlier example B corrected.** | [reference_model_input](../../src/domain/reference_model_input.zig), [typed_text](../../src/domain/typed_text.zig), [request preparation](../../src/domain/model_request_preparation.zig), existing selected-schema and registered operation owners. | The retained call-8 schema requires `claim_id` with enum `[2]`. Once that branch is chosen, the ID is determined. Omit it and construct the canonical handle from the bound occurrence. The model may still choose use/placement. If the entire field is determined, construct it without model work. Existing native exact reconstruction in [coverage repair](../../src/domain/specification_coverage_repair.zig) is precedent within its current bounds, not authority to guess embedded occurrences. | Zero choices excludes the branch; one choice permits the ID-free marker; no marker adds no evidence; multiple choices cannot resolve an unqualified marker. Reject echoed IDs in the new shape, stale bindings and repair scope expansion. Cover initial, selected, correction, repair and unrelated registered consumers. | Amend ADR 0020 and §§7.1/12/17/22 for model/canonical separation and exact branch binding. Use typed owning contracts, not a generic scan for properties named `claim_id` or indiscriminate singleton-enum rewriting. |
| **2. Construct fixed review evidence — implemented offline in §15.6.** | [specification_support_evidence](../../src/domain/specification_support_evidence.zig), [support collection](../../src/domain/specification_support.zig), [support repair](../../src/domain/specification_support_repair.zig), existing support schema. | `Requirements.rule` computes `.claims.exact` and `.provenance`; the model projection now omits determined echoes and the engine constructs the canonical selection after the finding and any chosen loss location. Selectable evidence subsets and source/policy choices remain model decisions. The verdict remains semantic. | Focused regression tests cover minimal responses, forbidden echoes, fixed/selectable cases, retained-verdict repairs, conditional loss and corrupt stored evidence. Full/live evidence remains separately required. | Focused §§12/17/22 review-response amendment recorded under C2c/§7F. No automatic positive verdict or merged evidence authority. |
| **3. Bind support before authoring — required for provenance-free responses.** | [specification_session](../../src/domain/specification_session.zig), [generation](../../src/domain/specification_generation.zig), existing authority, semantic-review and request-identity owners. | `packetForChoices` offers eligible claims, not per-record fixed support. Define a validated per-unit source obligation or accepted association before content or review responses; code resolves its ledger identities and constructs `S`. Broad unbound synthesis cannot be admitted without inventing support. Relocating the same ID selection to another model call achieves nothing. | Multiple independent requirements, split/combined source obligations and both many-to-many directions; joint support that no single claim supplies; broad context without automatic support inheritance; stale assignments, false-positive/negative assessments and bounded repair. Measure calls, full requests and retained resources; no assumption of lower token cost. | Define grouping, per-unit binding and association admission before changing generation/assessment boundaries. A set of eligible claims or one lone claim is not fixed support. Reuse existing runner/semantic owners; no extra reviewer, hidden model loop or parallel evidence store. |
| **4. Keep semantic outcomes separate from ID conformance — confirmed retained-run failure.** | [retained run evidence](#subsequent-user-run--empty-principle-review-exhausts-the-token-budget), existing source/principle review, coverage, publication and [rubric judgment](../../test/harness/judgment.zig). | Earlier responses chose business claim `1` as an exact occurrence. Restriction to `[2]` avoided that error in the later run, but its story was the greeting twice. A valid ID, correct union or passing coverage is not meaningful content or successful recovery. Preserve independent semantic gates; do not turn engine/model defects into user questions. | Poor-but-well-linked titles, stories, applicability explanations and requirements, plus valid and unrelated examples. Offline tests establish routing; separately approved model/reviewer observations and full publication/readback/rubric evidence establish outcomes. Report false acceptance/rejection and costs; no reliability or savings claim from fixtures. | No policy weakening, retry increase or prompt-bulk remedy. Any live call or E2E run still requires separate approval; this plan grants none. |
| **5. Retain internal occurrence identity — completed mechanism to preserve.** | [reference_support](../../src/domain/reference_support.zig), [provenance](../../src/domain/specification_provenance.zig), [projection](../../src/domain/specification_projection.zig), [state](../../src/domain/specification_state.zig) and existing repair owners. | Keep the canonical claim identity qualified by its validated ledger and recorded occurrence. Equal text can have different source locations. Remove determined response selectors without removing internal identity, canonical `provenance.claim_ids` or the sole reference authority. Copied quotes, offsets, renamed labels and similar-text matching are not automatic replacements for semantic association. | Equal text in separate locations stays distinct; `S=[1]` plus exact `2` derives `[1,2]`, another record stays `[3]`; repair preserves original `B`, siblings and retry identity; fresh loading rejects stale/corrupt bindings and derived projections. Preserve non-Spec eligibility and separate clarification/policy/capability authority. | Assess model/canonical, parser/projection and any persistence consequences together. A model-only omission does not itself require changing stored handles; document any state-version change actually needed. No alternate ledger, compatibility reader or guessed source-requirement ID. |

**Completion rule:** every retained response selector must name an unresolved
semantic choice and justify why the assignment cannot already determine it.
Audit constants conditional on verdicts, variants and selected relationships, not
only values known before dispatch. Apply the same rule to extraction,
reconciliation, generation, review, repairs, evaluator outputs and other registered
workflows. Preserve operational/file, policy and clarification identity boundaries;
source-claim reconstruction must not become their authority. Remove only superseded
model fields and unreachable echo-repair paths, with coordinated schema, decoder,
prompt, native construction, readback and documentation changes.

The prior review ran
`zig build test-specification-generation test-reference-reconciliation test-reference-model-input test-model-request-workflow --summary all`:
**12/12 steps succeeded; 695/695 tests passed** (218 generation, 106 reconciliation,
64 reference-input and 307 request-workflow tests). It also inspected retained
requests/responses and confirmed the singleton enum and repeated-greeting result.
Those checks establish current behavior, not implementation or live reliability
of the proposed ID-free shapes. This documentation update does not rerun those
code tests or amend accepted contracts. Implementation and required contract
decisions remain open; compare compiled schemas and complete prepared requests
before/after, and measure actual quality/cost only through separately approved calls.

### 15.6 P1 source-review response cutover — 27 September 2026

P1's source-review portion of C2c is implemented in the current worktree. The
existing [evidence rule](../../src/domain/specification_support_evidence.zig) remains
the authority for fixed and selectable claims. The [model projection](../../src/domain/specification_support_model.zig)
now omits `provenance` for supported/not_applicable findings when that rule fixes
their claim set, and for candidate omissions whose selected loss or bound exact
rule fixes diagnostic claims. It omits invariant empty
`clarification_response_ids` and `loss:unlocalized`. The engine restores the
complete native finding before ordinary admission. Unlocalized/disposition
losses without an exact bound and other negative findings still require an
explicit selection; `source_ids` remains independently selectable. The single
candidate-omission schema has optional provenance because its necessity depends
on the selected loss. The decoder rejects both an echoed determined set and a
missing selectable set; native admission still validates the chosen location
and all source joins. Retained-verdict evidence repair uses `selection_fixed`
where its authorized rule determines claims. Strict persisted readback validates
the stored full evidence before any model projection. No verdict, principle
citation or generation-support policy was inferred from this cutover.

Focused §§12/17.3/22 and the support prompt/schema now record the wire/native
split. Scripted tests cover fixed positive and localized-loss reconstruction,
forbidden echoes, selectable findings and losses, selected repair, source-ID
faults, sibling preservation and corrupt readback. The previous scripted
fixed-claim corruption was retired as an impossible model response; its protocol
test now supplies the forbidden echo, and native repair tests use an actually
selectable source ID.
`zig build test -j1 --summary failures` and
`zig build verify -j1 --summary failures` both exited successfully on this
worktree; the complete scripted specification suite reported 165/165 scenarios.
`git diff HEAD --check` was clean. These are offline checks, not E2E quality
evidence.

The retained live E2E's call 15 (fixed positive finding) and call 16 (fixed
evidence repair) supplied equal-payload *before* requests. After figures use
the current compiler's selected complete/Bedrock schemas substituted into those
same captured request JSON objects, preserving every other message and field.
This is a controlled offline size projection, not a new model call or an actual
post-change request trace:

| Captured call / selected shape | Compiled complete schema bytes | Bedrock schema bytes | Controlled full request bytes |
| --- | ---: | ---: | ---: |
| 15, finding → finding_fixed | 11,753 → 4,386 | 9,412 → 3,335 | 31,298 → 25,221 |
| 16, selection → selection_fixed | 593 → 199 | 428 → 144 | 10,021 → 9,737 |

This measures only serialized bytes for equal inputs and schema substitution;
the support-prompt wording change is excluded. It does not establish tokenizer
cost, final-answer availability, business quality, publication or live
reliability. P1 is an intermediate cutover because its model schemas still
permit `provenance`; it does not satisfy the later user decision in §15.4.
Before P2–P3's existing-ledger traceability projection, implement the approved
per-unit association contract across initial generation, review, authorized
repair and state readback. Keep the existing reference owner, ADR 0020's
evidence bounds, and distinct semantic review. Do not remove the field from
the schema alone, infer `S` from eligible claims or `source_ids`, or replace it
with the same ID list under another name. The focused ADR 0020/§§7/12/17/22
amendment now states how an unbound semantic choice becomes a validated
assignment before any model response. P2–P3 requirement-keyed occurrence links,
optional P4 structured original IDs and P5–P7 verification remain open.

### 15.7 Current full-cutover worktree (27 September 2026)

The subsequent approved cutover is in progress. Generation and source-review
model schemas now reject `provenance`; the native generation parser constructs
canonical `S` from validated reconciliation role assignments and derives exact
dependencies and citations through the existing reference owner. Content-only
record and value repair decoders retain their authorized selection and evidence
bounds. This changes model response responsibility, not the persisted
`provenance.claim_ids` identity. Reconciliation still carries genuine semantic
claim grouping; an exact-copy occurrence still uses its single `claim_id`.

The completed reference view now has a requirement-keyed projection of each
record's effective claim-to-citation occurrence edges. It is recomputed from
canonical content and the captured reference ledger for rendering and output
equality; pending output has no generated-record projection. The view displays
captured spans and reference-state identity, not invented original requirement
IDs. The editable `spec.md` grammar and persisted state gain no traceability
field. Structured original IDs remain the conditional P4 decision.

The superseded model-facing provenance-repair path has been removed. A
producer-to-consumer audit found a further fixed reconciliation field:
`conflicts[].resolution` was always `unresolved`, while native validation
already constructed it. The response schema and proposal now omit it; the
canonical conflict still records the engine-owned status. `generation_roles`
remain semantic signal-to-authoring assignments, with native role validation
and claim resolution. A `records` signal can currently produce several
requirements, and the parser binds its same selected claim group to each one.
That is a semantic attribution risk: a group chosen for a batch does not by
itself prove that every resulting requirement is supported by every claim.
Before claiming per-requirement attribution complete, exercise a mixed-support
batch through per-record semantic review and either prove rejection or amend
the record-assignment contract so each record has its own validated semantic
source binding. Do not use prose matching or an unbound positional array to
infer support. The offline omission scenario exposed the corresponding repair
gap: after a missing record family is reviewed, several `records` signals may
be eligible, but the review has no uniquely bound source obligation for the
inserted record. Reusing the completed generation cursor is invalid; using a
union of all eligible record signals would guess support. The existing
`loss.reconciliation_signal` identifies a defective source producer and must
not be repurposed as the source for a missing generated record. Define the
per-record obligation and omission-to-obligation association in the existing
reconciliation/session/repair owners before claiming successful omission
recovery; preserve an engine failure or typed block when association is absent.
The generated-record and source-review cutover has
focused test evidence, but the complete offline fake-provider harness and
architecture-wide deterministic-field inventory are still open. This worktree
is **not yet verified complete**. No live model call has been made for this cutover.

**Required contract decision before omission recovery can be completed:**
make each reconciled record obligation own exactly one generated record. The
model selects its supporting claim group and intended record kind while
reconciling source meaning; native code assigns the obligation identity,
validates scope/coverage, binds the authoring request, constructs canonical
provenance and checks the returned record kind. Permit overlapping claim
groups for distinct obligations, including two obligations from the same
source claim, while rejecting duplicate obligations. A reviewed omission may
repair only a uniquely identified, unfulfilled obligation of the required
kind; otherwise return to reconciliation or block as an engine/source
association defect. This would amend ADR 0020's current allowance for one
record task to emit several requirements and requires coordinated schema,
snapshot, session, repair and review tests. Do not silently substitute the
family-wide claim union, guess by text, or reuse the completed generation
cursor as an insertion binding.

The following equal-input comparison substitutes each prior compiled schema
into the corresponding current captured Bedrock request, preserving the other
messages and request fields. It measures serialized bytes, not tokens or live
usage. The selected brief, record and source-finding shapes are matched; other
shapes are not represented by these three rows.

| Selected response | Prior/current compiled schema bytes | Prior/current controlled full request bytes |
| --- | ---: | ---: |
| Brief | 3,559 / 2,035 | 6,934 / 5,194 |
| Records | 6,138 / 5,376 | 10,995 / 10,125 |
| Source finding | 4,386 / 3,279 | 12,816 / 11,541 |

These offline measurements establish only payload-size changes for those
captured inputs. They do not establish lower aggregate token cost, better
semantic outcomes or live reliability. Those remain subject to separately
approved E2E execution and rubric evaluation.
