# LLM_REWORK — Derive mechanical facts; ask models for semantic choices

**Reviewed:** 26 September 2026. **Status:** Phases 0–2 complete; Phases 3–4 remain.
**Scope:** Phase 0 baseline tests, approved [ADR 0020](../design/decisions/0020-derived-exact-reference-lineage.md),
Phase 1's reference-owner refactor and Phase 2's coordinated format cutover.
The retained runs and the conformance review are recorded below.
Phase 2 closes the identified owning-unit, request-choice and allocation gaps;
§10 records the checks. The latest retained run still failed; this assessment
launched no model calls or E2E rerun.

## 1. Finding and recommendation

The concept is sound: when validated input and an accepted rule determine one
answer, the engine should construct that answer. Asking the model to reproduce it,
then validating and repairing disagreements, introduces avoidable failure paths.
This already follows [design §4](../design/design.md#4-deterministic-and-llm-responsibility-boundary).

The strongest immediate opportunity is **reference bookkeeping**, not arithmetic.
The pre-cutover exact-copy response repeated a token ID, its citation ID and its
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

### Phase 0 run — the same reference join fails during brief generation

Execution
[`2026-09-25T21-53-09Z-74d618e36d74294723f5ca72d7a90347`](../zig-out/e2e-spec/2026-09-25T21-53-09Z-74d618e36d74294723f5ca72d7a90347/report.md)
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

The [first repair request](../zig-out/e2e-spec/2026-09-25T21-53-09Z-74d618e36d74294723f5ca72d7a90347/evidence/generation/call-000009/request.json)
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
[`2026-09-25T22-18-57Z-dadf1076a7fcde7bd0710c1f047ab377`](../zig-out/e2e-spec/2026-09-25T22-18-57Z-dadf1076a7fcde7bd0710c1f047ab377/report.md)
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

The [records response](../zig-out/e2e-spec/2026-09-25T22-18-57Z-dadf1076a7fcde7bd0710c1f047ab377/evidence/generation/call-000015/model_output.txt)
also repeats the greeting as Given/When/Then and includes an entity despite the
fixed `not_applicable` decision. These are additional candidate problems; native
validation stopped at record 0's join before entity membership or semantic review
could assess the rest. The supplied prompt already described required behavior,
precondition, trigger and outcome, and instructed the model to follow the entity
decision. This is not evidence that purpose guidance or source requirements were absent.

The [record repair request](../zig-out/e2e-spec/2026-09-25T22-18-57Z-dadf1076a7fcde7bd0710c1f047ab377/evidence/generation/call-000016/request.json)
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
[`2026-09-26T00-13-51Z-8c9c22b2f48057252273f4bf6d7dfd73`](../zig-out/e2e-spec/2026-09-26T00-13-51Z-8c9c22b2f48057252273f4bf6d7dfd73/report.md)
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
merge. [Raw call 12](../zig-out/e2e-spec/2026-09-26T00-13-51Z-8c9c22b2f48057252273f4bf6d7dfd73/evidence/generation/call-000012/response.json)
and the [existing decoder](../src/adapters/provider/bedrock_response.zig)
agree: no final answer follows the reasoning block. Reasoning must remain excluded
from candidate data. The requests included native `response_format.type="json_schema"`.

**Confirmed request defect:** the common purpose instruction says
“Embed exact_copy claim IDs within prose,” including in
[call 11's repair request](../zig-out/e2e-spec/2026-09-26T00-13-51Z-8c9c22b2f48057252273f4bf6d7dfd73/evidence/generation/call-000011/request.json).
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

### Latest run — corrected guidance, eight recovered targets, then no final answer

Execution
[`2026-09-26T01-21-50Z-aa8fda0613a0159cf267a5c7f8ff35c8`](../zig-out/e2e-spec/2026-09-26T01-21-50Z-aa8fda0613a0159cf267a5c7f8ff35c8/report.md)
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

The [last repair request](../zig-out/e2e-spec/2026-09-26T01-21-50Z-aa8fda0613a0159cf267a5c7f8ff35c8/evidence/generation/call-000028/request.json)
explicitly rejects exact claim 1, states that no exact/passive choices are permitted,
and requires source-backed strings while preserving fixed evidence. Its native
schema is only an object containing a string array. The correction adds
`missing_final_text`, “Final-answer admission failed: no final answer was received,”
and the complete-corrected-response instruction. It is not an identical retry.
[Raw call 29](../zig-out/e2e-spec/2026-09-26T01-21-50Z-aa8fda0613a0159cf267a5c7f8ff35c8/evidence/generation/call-000029/response.json)
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
for useful model output. Keep Phase 2 complete and Phases 3–4 open. Extend the
existing Phase 3.1 sequence with these successful repairs followed by late protocol
exhaustion, and keep meaningful recovery distinct from mere field acceptance.
Phase 4.1 must test both the captured prose-only repair's final-answer availability
and fresh generation's reference selection/field meaning. The correct exact handle
already works; choosing its business use remains semantic. Existing schema-choice
narrowing proposals (§6.6) remain separate decisions, not an implicit extension of
this run review. No new evidence, retry or semantic-review authority is justified.

## 3. Ownership inventory

| Information/work | Current owner/status | Assessment |
| --- | --- | --- |
| Source inventory, lines, coordinates and verbatim spans | [source_selections](../src/domain/source_selections.zig), native readers | Already deterministic. Models select offered ranges; they do not compute coordinates or reproduce quotations. |
| Exact-token candidate identity and raw bytes | [structured_tokens](../src/domain/structured_tokens.zig), extraction identity actions | Already deterministic. Relevance and classification remain semantic where not fixed by policy. |
| Canonical claim/citation/token identities | [reference_extraction](../src/domain/reference_extraction.zig), [reference_claim_items](../src/domain/reference_claim_items.zig) | Already native, assigned after validation. Do not add another identity system. |
| Exact-copy choice | [typed_text.ExactCopy](../src/domain/typed_text.zig), [generation schema](../design/workflows/spec/generation.schema.json) | Phase 2 uses one preserved-token claim handle and derives lineage. Purpose guidance distinguishes eligible exact choices from general evidence claims and respects narrowed repair schemas. |
| Citation union | [reference_support.select](../src/domain/reference_support.zig), [specification_provenance](../src/domain/specification_provenance.zig) | Already derived. Phase 1 removed the shared owner's Spec-type dependency; Spec eligibility remains in its own consumer (§6.1). |
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

The existing reference ledger can resolve that preserved-token claim into:

```text
captured source occurrence → token 1 → citation 2 → exact bytes
```

[reference_claim_items.build](../src/domain/reference_claim_items.zig) already
checks a preserved-token claim's one citation, source occurrence and raw bytes.
[reference_support.exact](../src/domain/reference_support.zig) now resolves the
selected claim directly. The tuple-specific reverse lookup and §36 repair trigger
were removed; native token/citation identities remain valid elsewhere.

**The request must also remove the join.**
[model_evidence.Token/project](../src/domain/model_evidence.zig) now includes the
owning `claim_id`, trusted value and source context. Do not add a second lookup
table or strip evidence needed to choose meaningfully. Request choices, schema
exclusions and native eligibility must use the same owning facts; an arbitrary
integer still does not become a valid handle. Phase 2.2 aligned the prompt and
fixed-repair choice projections with that rule.

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

The pre-cutover canonical representation could not distinguish the required roles
if automatic derivation overwrote the explicit claim list. These two cases explain
why [specification.Provenance](../src/domain/specification.zig) now stores explicit
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

The shared-handle schema/type, version changes and §6.5 consumer corrections are
implemented. Avoiding conversion machinery alone did not establish end-to-end
conformance; the owning-unit tests in §10 provide the additional evidence.

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
parallel permission store. Keep this implemented protection when correcting the
remaining full-unit checks in §6.5.
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
a failed new lookup through a generic provenance error. Syntax/schema failures
retain protocol correction; well-shaped unavailable handles use native validation.

[Completed state](../src/domain/specification_state.zig) validates content,
coverage and review associations. [Pending state](../src/domain/incomplete_specification.zig)
stores references and clarification identities; generation questions are flattened
to text by [the existing question builder](../src/actions/clarification/build_specification_clarification_need.zig).
These are different contracts. ADR 0020's `specification/v2` and
`specification-state/v6` cutover is active, including old-version rejection.
Remaining readback tests must cover the owning-unit discrepancies below without
adding a migration, dual reader or new pending evidence store.

### 6.1 Shared mechanics and consuming-domain policy

Cross-workflow reuse cannot simply call `specification_provenance` from Plan or
Tasks. Phase 1 moved selection mechanics to reference-owned inputs and results in
[reference_support](../src/domain/reference_support.zig). Spec still requires
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

### 6.5 Final implementation review — findings closed in Phase 2

**Evidence level:** the following were code-path findings against the first Phase 2
implementation. The retained run stopped before these downstream paths, so they
were not causes of its missing answers. The added regressions and current checks
are recorded in §10. The text below retains each causal finding and required
boundary so a future change does not recreate it.

**High — full-record admission and per-field rendering disagree (2.4).**
[inspectRecord/validateStored](../src/domain/specification_provenance.zig) collect
all record fields before deriving `L`. In contrast,
[project](../src/domain/specification_projection.zig) passes each field with the
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

- [Omission authorization](../src/domain/specification_coverage_repair.zig)
  computes effective claims from only the selected record field, whereas
  [source-review evidence](../src/domain/specification_support_evidence.zig)
  computes record-wide support. It can refuse an otherwise eligible field repair
  whose sibling contains the exact dependency. `omissionPacket` also restricts
  schema alternatives using `S` instead of the effective bound: an exact-only
  field with `S=[]` can authorize but fail packet construction, and `S=[1]` with
  exact claim `2` can receive a prose-only schema despite needing to preserve `2`.
- [Native retry progress](../src/domain/specification_repair.zig) validates a
  provenance target through explicit-only `p.select`, and a record value through
  single-field `checkAttributed`. Accepted `S=[]` with valid exact support, or
  support contributed by a sibling, can therefore be classified as unresolved.
  Resolve record evidence once, then validate the selected target under it. Simply
  checking the whole record would also be wrong: an unrelated sibling failure must
  not keep a successfully repaired target's retry counter recurring.
- Completed-value replacement changes text while retaining old materialized
  citations, then [replaceCompleted](../src/domain/specification_session.zig)
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
[Coverage](../src/domain/specification_coverage.zig) currently allocates effective
lineage for each candidate unit inside the retained-claim loop. The same unit is
thus traversed/allocated repeatedly. Measure this independently of provider tokens,
including repeated validation and larger ledgers. If material, derive each unit's
view once per validation pass using the existing owner; no persistent cache, second
coverage index or process-wide authority store is justified.

Independent reuse is feasible through the existing
[operation registry](../src/ports/workflow_operation_registry.zig) and test-owned
schemas/bindings already demonstrated by [runner tests](../src/workflow_execution_test.zig).
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

Rechecked official documentation on 26 September 2026. AWS documents
`response_format` for open-weight InvokeModel structured output, numeric enums,
internal schema references and a limited JSON Schema subset. New schemas may
incur grammar compilation and cached schemas are reused. These are provider
constraints to account for when measuring requests, not grounds to relax native
validation. [AWS structured outputs](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html)

An enum can restrict an ID to a nonempty finite set; it cannot decide which
eligible occurrence preserves the intended meaning.
[JSON Schema enum](https://json-schema.org/understanding-json-schema/reference/enum)
Here, dynamic numeric enums are **a deferred option**, not a configuration-only fix:
SDDE's `model_result_schema.Node.enumeration` accepts strings, and current native
restriction only removes unavailable tagged variants. Extending numeric enums and
binding dynamic choices through schema selection, identity, correction and assembly
needs a focused contract decision and conformance tests. Do not create an
adapter-only schema or a parallel list. Empty choices should remove the variant,
not create an invalid empty enum. Consider this only after measuring the bounded
conformance patches; it would not repair missing final text or meaningless prose.

The retained run already used native structured output. The reviewed sources do
not establish why its raw final answer was absent. Preserve the current missing-answer
classification, bounded correction and actual token accounting; do not use reasoning
as content or promise that prompt cleanup will fix the provider response. Phase 4
must separate final-answer availability, contract validity and semantic usefulness.

## 7. Other deterministic opportunities, ranked separately

These are deferred assessments, not additional Phase 2 work. Keep their response
and persistence contracts unchanged while closing §6.5. Their feasibility differs:

| Item | Disposition and minimum evidence before implementation |
| --- | --- |
| A — reconciliation token metadata | Feasible because one preserved-token claim determines the token. Separate approval/cutover must cover summaries, global signals, replacement, persistence and unchanged source review; measure whether this remains a material failure source. |
| B — summary keys | Feasible only after an ordering decision. Test shuffled arrays, insertion/deletion, stable retry identity and byte-stable state before removing keys/sort/repair together. No guessed semantic ordering. |
| C — review association | Single-target repair already binds identity; reuse it. Batch association is still a real choice. Keep current IDs unless an approved named-slot contract demonstrates lower cost and exact membership under missing/reordered output. |
| D — diagnostic guidance | Existing `ValueChoices.correction` already names unavailable exact/passive selections. Correct its inputs/consumers in Phase 2; do not create another guidance owner. Extend other diagnostics only for demonstrated missing native facts. |

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

The user approved the focused contract on 26 September 2026. [ADR 0020](../design/decisions/0020-derived-exact-reference-lineage.md)
is the governing authority for the exact claim handle, explicit versus derived
lineage, bounded value-only repair, version cutover, readback and failure
precedence. §§5–8 record the analysis behind that decision; they are not a
second implementation policy. The current runtime uses the new format; Phase 2
conformance did not restore or authorize the old one.

Approval does not grant broader coupled evidence changes, verdict reassessment,
multiple-ledger attribution, zero-scope typed text, reconciliation-token or
summary-key removal, or batch-review redesign. Those remain separate decisions
if later work needs them. In particular, the bounded invalid-handle baseline
cannot acquire a fresh claim from the whole assignment catalogue on retry.

## 10. Phased rollout with testable checkpoints

**Phases 0–2 are done; Phases 3–4 remain.** The approved contract
activated at the coordinated Phase 2 format cutover. There are five phases and eleven
chunks. Each chunk produces a reviewable diff, named regression evidence and a
recorded proceed/revise decision. §11 supplies the common acceptance matrix;
passing a safe-block test must never be reported as successful recovery.

Phase 1's independent owner refactor and Phase 2's coordinated format activation
and conformance checks are complete. Do not
reintroduce temporary runtime flags, dual readers, skipped tests or pair/handle
conversion adapters to make individual fixes appear smaller.

**Next implementation order:** run independent reuse/failure integration and
measurements (3.1–3.2), then separately approved controlled calls and a complete
scored E2E (4.1–4.2).

Every follow-up has a failing regression at its owner, an unrelated accepted case
and a reject case. The repairs above implement existing ADR 0020 authority. Broader
evidence expansion, numeric-enum schemas and §7 changes remain separate decisions.

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
[failed run](../zig-out/e2e-spec/2026-09-25T08-21-44Z-b16638b5493910a4b1d29436213dcde9/report.md)
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
[protocol correction tests](../src/model_request_workflow_test.zig) retain the
selected schema and original request identity. The current Spec graph has 717
compiled operations under the [root compilation test](../src/composition/root.zig);
the retained run does not separately report a compiled graph count. The new
[generation regression](../src/specification_generation_test.zig) exercises the
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

- **Closed scope:** the latest run in §2 exposed an unconditional exact-copy
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
live semantic quality. Phase 3 still owns independent cross-workflow integration
and comparative request/resource measurements; Phase 4 owns approved live tests.

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
  Extend it with the latest run's eight successful native targets, each requiring
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

### Phase 4 — Measure live effectiveness with separate approvals

**4.1 — Controlled assignments.** Depends on 3.2 and explicit call approval.

- **Outcome:** prepare comparable captured assignments from the reported and unrelated
  cases. Hold sources, semantic task and provider settings fixed; change the approved
  contract/projection together. Use the existing debugger and capture, with a declared
  call count and budget. Keep the old response as evidence, not a second runtime path.
- **Checks:** record final-answer presence, JSON/schema/native validity, literal and
  meaning preservation, repair outcomes, actual tokens and latency for every attempt.
  Start with the latest run's captured calls 28–29 from §2, whose guidance already
  conforms; preserve their fixed evidence/schema and measure final-answer availability.
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
| Reference mechanics, 1.1/2.1 | `zig build test-reference-evidence test-reference-model-input test-reference-reconciliation test-typed-text test-architecture` |
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
| Empty/meaningless but correctly linked story or AC | Never counted as semantic recovery merely because joins pass. Scripted review tests routing; approved live rubric tests actual quality. |
| Pre-ledger extraction and reconciliation | Their existing allowed shapes and source selections remain intact; exact-copy business segments are not newly admitted there. |
| Independent workflow reuse | Two differently named configured workflows with distinct response shapes use the same shared resolver through registered typed consumers. The second consumer has no Spec/session dependency or workflow-name branch. |
| Shape and policy variation | Nested records, arrays and optional typed fields contribute only to their owning evidence unit. Different native eligibility sets remain enforced; Spec-only restrictions do not become global. |
| Structural JSON versus typed meaning | Reference-looking objects in ordinary JSON remain ordinary data. Existing schema/composition limits reject unsupported shapes; resolution does not enter the generic assembler or decoder. |
| No-reference and mixed-support workflows | No unnecessary ledger/model calls for an unrelated workflow. Domain-accepted user answers, repository facts and other support are not dropped or converted to fabricated claims. |
| Namespace isolation and reuse | Swapped bindings reject across different states and after changed ledger production under the same corpus ID/ordinal. A bare ordinal cannot reveal unstated model intent. Valid predecessor identity survives a fresh execution; stale producer/contract changes invalidate dependents. |
| Operational and stage boundaries | Display references grant no file/copy/command capability; source-like strings inside code remain raw payload. Existing clarification and approval gates remain independent. |
| Shared dependency direction | Architecture checks reject shared reference/syntax modules importing Spec generation, sessions or policy; no second resolver/schema/policy registry. |
| Allocation and scale | Inject failure after initial allocation and during lineage growth; no leaks with a general allocator. Measure repeated full-unit derivation separately from model tokens and avoid persistent caches for per-pass work. |

## 12. Feasibility conclusion

**Viable for reuse across workflows through a shared typed contract, with Spec as
the first integration. Phase 2 is complete.** The reference-owner refactor,
handle representation, explicit selection, version cutover and §6.5 conformance
work are implemented. They require no new message layer, reference registry,
retry mechanism or general-purpose fixer.

**Implement next:** Phase 3's independent consumer, cross-boundary failure and
recovery tests, and comparative request/resource measurements. Phase 2's offline
success is not evidence that the provider's missing final answers or semantic
quality in the retained run improved.

This does not promise automatic support for every JSON Schema, authority namespace
or future workflow. New domains reuse the mechanism by supplying their declared
typed fields, validated reference binding and native policy; they do not duplicate
the resolver or inherit Spec's semantic rules. Workflows without reference content
continue using their existing deterministic owners.

The cutover removes one redundant model-side join. Completion must demonstrate
that its replacement works at every consumer. It must not claim deterministic
proof of specification quality, silently infer business evidence, or hide unresolved model errors behind mechanically complete
coverage. Broader bookkeeping simplifications should follow measured evidence,
independently of this first contract.

**Evidence limit:** Phase 2's tests and full verification establish offline
conformance, including packaged behavior. The latest retained run used corrected
guidance and accepted a valid derived reference, but still produced poor interim
content and exhausted missing-answer recovery before publication or grading.
This assessment launched no provider calls or E2E. Phase 3 supplies independent offline integration and
measurements; Phase 4 requires separately approved live effectiveness and a
published, scored output. ADR 0020's explicitly excluded extensions remain
unapproved.
Existing regression owners include [specification generation tests](../src/specification_generation_test.zig),
[typed-text tests](../src/typed_text_test.zig), [request workflow tests](../src/model_request_workflow_test.zig)
and [native packaging smoke](../test/packaging/smoke.zig); implementation must extend
them with the matrix above rather than count existing containment tests as recovery evidence.
