# Z_FIX02 — Completed fix-record work, 10–16 October 2026

This record consolidates the implemented changes, executed experiments and their
verification from the fix records retired on 16 October 2026. It follows the
[fix-record convention](README.md): [FIX01](FIX01.md) is the active backlog,
[FIX04](FIX04.md) is the active evaluation design, and [Z_FIX01](Z_FIX01.md) holds
earlier completed FIX01 work.

Completed execution is not completed semantic acceptance. A failed experiment is
recorded here because it finished, not because its question was answered; every
open gate is carried in FIX01 or FIX04. Dated status statements below are
historical and describe their recorded date. Nothing here renews an approval,
authorizes a live call or accepts the overall **Proposed design**.

The original FIX01-01, FIX01-02, FIX02 and FIX03 records are retained in the
[archive](archive/README.md) with only their relative link paths rewritten, so that
design documents and FIX04 can keep citing them by line number. FIX04's separate
implementation records were short working notes: their full text is folded into §5
and the files were removed.

## Completed-work index

| Record | Completed and recorded here | Open work and its owner | Original |
| --- | --- | --- | --- |
| FIX01-01 — bound preservation comparisons (10 Oct) | Phases 0–2 production implementation and offline verification; three 32-call Phase 3 comparisons; Phase 4 offline recovery verification (§1) | Phase 3 semantic acceptance failed; the conditional Phase 4 E2E runs never ran: FIX01 R6 | [archive](archive/FIX01-01.md) |
| FIX01-02 — diagnosis evidence to recovery (10–11 Oct) | Phase 0 recovery proof; Phase 2 reporting; the explicit `missing_obligation` handoff; native-owned assessed collections; citation guidance; Phase 4 offline integration; six panels, 298 diagnostic calls (§2) | The actual source-review direction and coverage defect, then production E2E: FIX01 R6 | [archive](archive/FIX01-02.md) |
| FIX03 — Spec workflow reliability review (11–14 Oct) | Phases 0, 1, 3 and 6; Phase 2's presentation work and its 14 October shared reliability follow-up (state v14); Phase 4's bounded AC transport; Phase 5's replacement contract and its 50 approved responses (§3) | Phases 7–11 and the live exits of Phases 2, 4, 5 and 6: FIX01 R2, R7, R11 and FIX04 | [archive](archive/FIX03.md) |
| FIX02 — independently configured assessments (10 Oct) | Nothing: the proposal was never implemented (§4) | Carried forward with FIX03 Phase 9: FIX01 R11 | [archive](archive/FIX02.md) |
| FIX04 — semantic simplicity evaluation (15–16 Oct) | Phase 0 protocol; Phase 1 compatibility harness and live gate; decoder correction; model switch; native reference review subjects; Phase 2 harness, audit and cost investigation; Phases 1A, 1A.2 and 1A.3 offline; seven full-workflow diagnostics and findings F9–F12 (§5), with F13 in FIX04 | Phase 1A.3's live items, the budget and scope decision, the Phase 2 baseline and Phases 3–6: FIX04 | [FIX04](FIX04.md) (active) |

## 1. FIX01-01 — Bound preservation comparisons (10 October 2026)

**Scope:** [FIX01 R6 follow-up item 1](FIX01.md#proposed-recovery-follow-up-and-implementation-order):
replace broad culprit selection in loss attribution with native-bound preservation
comparisons. The model assesses `preserved`, `lost` or `uncertain` for each
assigned producer collection, and the existing loss owner derives the repair
candidate from the admitted comparisons and actual dependencies.

**Completed:**

- **Phases 0–2:** the comparison contract, native assignments, shared admission and
  the coordinated lifecycle cutover, implemented under the user's explicit
  instructions. Production implementation and offline verification are complete
  (**1,455/1,455 tests**, **142/142 steps**). The cutover amended the focused
  runtime contracts listed in its §0.5, and ADR 0020 and ADR 0022 record it.
- **Phase 3:** three separately approved 32-call comparisons, **96 diagnostic
  calls**, executed without retries or extra sends:

  | Comparison | Native admission | Correct attribution | Gate |
  | --- | --- | --- | --- |
  | [First candidate](../test/calibration/source-loss-attribution/bound-preservation/README.md#results--10-october-2026) | 7/16 | 2/16, with one false upstream attribution | Failed |
  | [Shared request projection](../test/calibration/source-loss-attribution/bound-preservation/projection/README.md#results--10-october-2026) | 16/16 (baseline 8/16) | 14/16 (baseline 6/16) | Failed: two false role-loss judgments |
  | [Meaning versus representation](../test/calibration/source-loss-attribution/bound-preservation/meaning/README.md#results--10-october-2026) | 16/16 in both arms | 14/16 in both arms | Failed: no improvement, the same two false judgments |

- **Phase 4 offline:** native attribution-to-recovery integration assertions,
  published-state readback and full verification.

**Not completed:** Phase 3 semantic acceptance, and Phase 4's three live E2E
invocations, which were conditional on Phase 3 passing and never ran. That
conditional approval is unused and does not transfer to changed requests. FIX01 R6
tracks the open acceptance.

Final status checklist, as recorded:

- [x] Phase 0: comparison scope, semantics and derivation decisions completed under the user's Phase 0 instruction; see §§0.1–0.6.
- [x] Phase 1: native assignments and owning-boundary admission tests complete.
- [x] Phase 2: coordinated lifecycle cutover, documentation and full offline verification complete.
- [x] Phase 3 execution: first 32/32 approved trials retained, natively checked and assessed.
- [x] Phase 3 projection follow-up: shared presentation revised; second 32/32 approved trials executed and assessed.
- [x] Phase 3 meaning follow-up: shared presentation and lifecycle checks updated; third 32/32 approved trials executed, admitted and assessed.
- [ ] Phase 3 acceptance: both arms remain at 14/16 correct with two false role-loss judgments; the candidate did not improve outcomes.
- [x] Phase 4 offline work: native attribution-to-recovery integration assertions, published-state readback and full verification complete.
- [ ] Phase 4 live gate: approved production recovery, publication and rubric criteria met.

### 1.1 R6 item 1 status formerly recorded in FIX01

**10 October status:** the contract and recovery mechanics are implemented and
verified offline in [FIX01-01](archive/FIX01-01.md). Its first 32-call comparison failed:
7/16 candidate responses passed native admission and 2/16 yielded correct
admitted attribution, with one false upstream attribution. The shared request
projection follow-up removes competing IDs, source coordinates and assessed-subject
ambiguity. Its [separately approved 32-call comparison](../test/calibration/source-loss-attribution/bound-preservation/projection/README.md#results--10-october-2026)
improved admission to 16/16 and correct attribution to 14/16 (baseline 8/16 and
6/16), but still failed two gates: it falsely diagnosed role loss when a business
claim expressed the literal without a separate preserved-token member. Separate
meaning preservation from canonical representation in the next candidate.
That shared presentation follow-up is now implemented: resolved claim meanings
omit extraction-category labels, and guidance distinguishes expressed behavior
from its representation. Its [32-call comparison](../test/calibration/source-loss-attribution/bound-preservation/meaning/README.md)
executed under fresh approval: both arms admitted 16/16 and correctly attributed
14/16, repeating the same two false role-loss judgments. Category removal and
clarified guidance did not improve outcomes. Semantic acceptance and conditional
production E2E remain open. All three diagnostic
allowances are consumed. Do not count measured improvement as completion.

## 2. FIX01-02 — From valid diagnosis evidence to correct recovery (10–11 October 2026)

**Scope:** after FIX01-01, address the remaining semantic attribution failure and
show that correct attribution enables useful repair and publication, using FIX02's
assessment routing only where it is relevant.

**Completed:**

- **Phase 0:** the latest story recovery proven offline, with source and evidence
  negatives retained and the evidence frozen.
- **Phase 2:** rejection reporting, and the explicitly approved `missing_obligation`
  handoff. The source reviewer states the omitted requirement separately from its
  explanation, and admission, loss projection, correction, repair and persisted v11
  readback carry it unchanged (**1,461/1,461 tests**, **142/142 steps**).
- **Native-owned assessed collections:** loss responses return judgments, source
  spans and explanations without a member selection; complete native assignments
  are retained under state v12.
- **Citation-completeness guidance** in the loss prompt and §22, with the schema,
  native attribution and repair permissions unchanged.
- **Phase 4 offline:** compiled-workflow integration of successful, invalid and
  recurring story-value repairs for the greeting and loan requirements, through
  publication and readback, and a fix to a temporary claim-selection allocation
  lifetime in the shared omission-packet builder.
- **Six approved diagnostic panels, 298 live calls in total; no E2E run:**

  | Panel | Calls | Result |
  | --- | ---: | --- |
  | Phase 1 context-removal pilot | 12 | Failed: baseline 1/6 correct, candidate 2/6, with a captured-case regression |
  | Explicit `missing_obligation` handoff (Phase 3) | 48 | Failed: correct attribution 18/24 → 20/24; the captured story regressed 2/2 → 0/2 |
  | One comparison per call (isolation) | 60 | Failed: correct labels 22/24 → 24/24, but two native rejections left correct admitted attribution at 22/24 in both arms |
  | Native-owned assessed collections | 72 | Passed the inherited gates: admission and correct attribution 22/24 → 24/24, with judgments 24/24 in both arms |
  | Citation completeness | 76 | Passed: complete citations 36/38 → 38/38, with 26/26 correct admitted attributions in both arms |
  | Actual source-review handoff | 30 | Failed: 15/26 faithful omission handoffs, 2/2 supported controls, 0/2 genuine-gap controls |

**Not completed:** Phase 1 selected no candidate; the actual source-review handoff
failed Phase 3 qualification; Phase 4's actual output and rubric acceptance and
observed live recovery are pending; FIX02's routing was never selected. The next
item, carried to FIX01 R6, is the actual source-review's shared direction and
coverage defect, before any further qualification.

Completion record, as recorded:

- [x] Phase 0: latest story recovery proven offline; source/evidence negatives retained; evidence frozen and Phase 2 rejection inventory recorded.
- [ ] Phase 1: experiment and assessment completed (12/12); gate failed, so no supported candidate selected.
- [ ] Phase 2: reporting and explicitly approved obligation handoff implemented and verified offline; supported semantic selection remains unmet; FIX02 routing remains unselected.
- [ ] Phase 3: 48/48 obligation and 60/60 isolation panels failed; the subsequent 72/72 native-scope and 76/76 citation panels passed their frozen diagnostic gates. Actual source-review's 30/30 calls completed but failed semantic handoff qualification (15/26 faithful obligations; 0/2 genuine gaps).
- [ ] Phase 4: offline integration and full verification complete; actual output/rubric acceptance and observed live recovery remain pending.

### 2.1 R6 follow-up records formerly in FIX01

These paragraphs were FIX01 R6's record of the follow-ups above, kept verbatim.

**Explicit-obligation follow-up — 10 October 2026:** after the context-removal
pilot failed (baseline 1/6 correct, candidate 2/6 with captured-case regression),
the user approved implementing a distinct `missing_obligation` handoff and the
Phase 3 rerun. The existing source reviewer now states the omitted requirement
separately from the diagnostic explanation. Schema admission, review evidence,
loss projection, correction, revision binding, repair consumers and persisted
v11 readback carry that statement unchanged. The loss call assesses complete
collections against it, retaining surrounding evidence as context. No new verdict,
repair permission, semantic retry or reviewer was added.
See [FIX01-02's implementation record](archive/FIX01-02.md#explicit-obligation-follow-up--10-october-2026)
and the [new calibration package](../test/calibration/source-loss-attribution/bound-preservation/obligation/README.md).
`zig build verify --summary all -j2` passed **1,461/1,461 tests and 142/142 steps**.
All approved **48 loss calls** (12 cases × two arms × two repetitions) completed
on 10 October, 09:59:39Z–10:01:15Z. The
[results](../test/calibration/source-loss-attribution/bound-preservation/obligation/results.md)
record baseline **18/24** versus candidate **20/24** correct attribution, native
admission **24/24 versus 23/24**, and adequate evidence **17/24 versus 19/24**.
Both arms score 14/16 on the original eight cases and 13/16 on evidence; the
candidate misses the required improvement, retains two false upstream diagnoses
and scores only 6/8 candidate-loss cases against the 7/8 minimum. The captured
story regresses from 2/2 to 0/2, despite improvement from 2/6 to 6/6 on fresh cases.
The declared semantic gate therefore **failed**. The captured description also
remains incorrect in both arms and repetitions.

Usage was **60,910 input + 12,670 output = 73,580 tokens**. The 48-call allowance
is consumed, separately from the preceding 12-call pilot: 60 diagnostic calls in
this rollout at that panel's close. No additional live calls or Phase 4 E2E had
run at that point; its conditional gate remains unmet. The failed pilot is not promoted, and the explicit-obligation
mechanism is not an accepted semantic fix. Production source-review obligation
fidelity has only offline mechanical coverage; it needs separate live qualification.
Fixed supplied obligations cannot establish the full handoff's semantic quality
or E2E publication acceptance. Review the retained failure before selecting any
further change; no automatic experiment allowance follows.

**Isolation comparison execution — 10 October 2026:** the user subsequently
approved **60 physical calls**, comprising 24 batched baseline and 36 isolated
candidate calls, for the [prepared experiment](../test/calibration/source-loss-attribution/bound-preservation/isolation/README.md).
It reuses all twelve now-known cases and scores 24 complete decisions per arm
against the unchanged gates. The baseline is the current explicit-obligation
packet; the candidate assigns one complete comparison per call with unchanged
guidance, sources, supporting context and settings. All **60/60** calls completed;
the [results](../test/calibration/source-loss-attribution/bound-preservation/isolation/results.md)
and [scorecard](../test/calibration/source-loss-attribution/bound-preservation/isolation/scorecard.json)
retain the failed gate. Correct preservation labels improved **22/24 → 24/24**,
native admission fell **24/24 → 22/24**, correct admitted attribution stayed
**22/24**, and adequate evidence improved **21/24 → 22/24**. False upstream
attributions fell **2 → 0** and the captured story improved **0/2 → 2/2**;
the captured description was correct in both repetitions of both arms.

Candidate extraction repetition 1 and unresolved-producer repetition 2 had
correct loss judgments and source citations but returned `members: []` for
nonempty collections. Both reject with `InvalidPreservationComparison`.
Original-subset admission and correct attribution fell **16/16 → 14/16**,
failing the minimum admission, genuine extraction/unresolved and no-regression
gates. The required two-result improvement is also impossible against that
perfect subset baseline, but the native failures independently prevent passing.
No threshold changed. The captured-story benefit does not prove batching is the
sole cause: the already-single-comparison unresolved control had identical input
but failed once. Candidate cost rose **37,239 → 55,463 tokens (+48.9%)** and
24 → 36 calls; total usage was **92,702 tokens**.

The 60-call allowance is consumed, bringing this rollout to 120 diagnostic calls.
No production split or further live call followed that panel. The user subsequently
approved removing the redundant model-returned member selection across the shared
contract. The typed response, schema, admission, correction, persistence, fixtures
and calibration now agree: comparison IDs bind complete native collections, and
responses supply only judgments, original-source spans and explanations. State v12
rejects earlier snapshots; old responses with `members` reject as unknown fields.
No IDs are supplied to previously rejected answers. Collection freshness,
comparison completeness, source joins and repair permission remain native checks.

The [new native-scope comparison](../test/calibration/source-loss-attribution/bound-preservation/native-scope/README.md)
held isolated inputs and model settings fixed in both arms for **72/72** completed
physical calls. It used the actual frozen prior native owner for baseline admission
and the current owner for candidate admission; neither reads the other's response
contract. Retain historical failures unchanged. Measure judgment accuracy,
explanation adequacy and native admission separately: assigned scope does not prove
the model considered every member, and removing selected IDs removes one observable
cross-check. Its new allowance is consumed. The
[results](../test/calibration/source-loss-attribution/bound-preservation/native-scope/results.md)
show both arms' judgments correct **24/24**, but baseline empty selections caused
two rejections; candidate admission and correct attribution reached **24/24**.
The inherited gates passed, including original-subset attribution **14/16 → 16/16**,
captured-story **2/2** and the six known family regressions **6/6**. This is an
admission improvement, not a gain in judgment accuracy. Candidate unresolved
repetition 2 omits the alarm source citation: explanation/source adequacy fell
**24/24 → 23/24** despite correct safe attribution. The historical no-case-regression
gate measures attribution accuracy, separately from its evidence minimum; no
threshold changed. Do not describe the result as zero semantic regressions.
Production isolation remains conditional; live source-review fidelity, the actual
review-to-loss handoff and Phase 4 publication/rubric acceptance remain unqualified.

**Citation-completeness follow-up — 11 October 2026:** the user requested the
shared evidence clarification and qualification recommendations. The existing
loss prompt and §22 now distinguish citations establishing the entire original
obligation from explanations assessing preservation in the assigned collection.
The schema, native attribution and repair permissions are unchanged. The approved
76-call comparison passed its frozen gates: complete/relevant citations improved
**36/38 → 38/38**, with **38/38** correct verdicts and **26/26** correct admitted
attributions in both arms. Both previously missing alarm citations were complete
in the candidate. This demonstrates improvement on the supplied-obligation panel;
the separately approved actual source-review panel then completed and failed its
frozen gates. Only **15/26** actual omission handoffs were faithful: seven omissions
were missed and four returned an inadequate or wrong target. Both genuine-gap
controls invented source obligations; supported controls passed **2/2**. All thirty
responses passed native mechanical admission, with unchanged actual obligations,
source IDs and replay lineage. That verifies conversion, not semantics. No
downstream loss call, repair or E2E ran. See the
[implementation and qualification record](archive/FIX01-02.md#citation-completeness-and-actual-handoff-follow-up--11-october-2026)
for the offline mechanics, [citation results](../test/calibration/source-loss-attribution/bound-preservation/citation-completeness/results.md)
and [actual source-review failures](../test/calibration/source-loss-attribution/bound-preservation/citation-completeness/handoff-results.md).
The historical native-scope results and acceptance thresholds remain unchanged.

## 3. FIX03 — Critical review of Spec workflow reliability (11–14 October 2026)

**Scope:** a critical review of the Spec workflow's reliability against a supplied
architectural critique, with a phased rollout (Phases 0–11) of its recommendations.
The retained [Phase 0 baseline](archive/FIX03-phase0-baseline.json) moved to the
archive with it.

| Phase | Completed | Full verification | Open at retirement |
| --- | --- | --- | --- |
| [0](archive/FIX03.md#phase-0--freeze-the-baseline-and-resolve-responsibility) — freeze the baseline and resolve responsibility | Complete, 11 Oct: retained baseline and accounting, a finite responsibility map and recommendation dispositions | Offline preparation only | — |
| [1](archive/FIX03.md#phase-1--establish-mechanical-safety-and-observability) — mechanical safety and observability | Complete, 11 Oct: indirect failure-masking reproduction, shared failure preservation, capture isolation and authorized recovery controls | 1,494/1,494 tests, 142/142 steps | Live verification partial: correction, repair and publication not reached |
| [2](archive/FIX03.md#phase-2--clarify-source-review-and-remove-redundant-input-work) — clarify source review | Presentation implementation and comparison preparation; the [14 October shared reliability follow-up](archive/FIX03.md#shared-reliability-follow-up--approved-14-october-2026): source-only `candidate_invalid`, string-or-`fragments` model text, native assembly facts, aggregate repair ownership and `specification-state/v14` | 1,496/1,496 tests, 142/142 steps; then 1,495/1,495 tests, 137/137 steps on 14 Oct | Semantic qualification |
| [3](archive/FIX03.md#phase-3--connect-diagnosis-attribution-and-permitted-repair) — connect diagnosis, attribution and repair | Complete at the offline exit, 11 Oct | 1,498/1,498 tests, 142/142 steps | Live qualification |
| [4](archive/FIX03.md#phase-4--reduce-redundant-review-granularity) — reduce redundant review granularity | Bounded AC transport and lifecycle (batched Given/When/Then review) complete offline, 11 Oct | 1,502/1,502 tests, 142/142 steps | Semantic gate; the 07:03:52 UTC run exposed an inconsistent field verdict |
| [5](archive/FIX03.md#phase-5--evaluate-replacing-the-presentation-role-gate) — replace the presentation-role gate | The [§5.2.1 replacement contract](archive/FIX03.md#521-phase-5-replacement-contract--implemented-candidate-qualification-pending) implemented and verified offline, 13 Oct; the 22-call historical and 28-call current-authoring panels received all 50 approved responses | 1,510/1,510 tests, 142/142 steps | The current-authoring candidate failed semantic qualification; the later family-guidance and five-factor remediation panels did not qualify either |
| [6](archive/FIX03.md#phase-6--retain-only-demonstrably-unaffected-review-evidence) — retain only unaffected review evidence | Execution-local source-review retention implemented, 11 Oct | 1,509/1,509 tests, 142/142 steps | Live usefulness |
| 7–11 | Not started | — | Carried to FIX01 R2, R7 and R11, and to FIX04 |

The 14 October follow-up is the contract FIX04 reviews: its model-text
representation is the one whose admission FIX04 Phase 1A completed, and its
recommendation to compare one complete record collection with the current
per-group pass first is now FIX04's A/C comparison. The review's own verification
history is its [§10](archive/FIX03.md#10-verification-history-and-rereview-limits):
the initial `test-engine test-architecture` run passed 1,306/1,306 tests, and the
later test-suite cleanup reduced 1,454 named tests to 1,433, with final verification
at 1,444/1,444 tests and 142/142 steps.

## 4. FIX02 — Independently configured assessments: not implemented (10 October 2026)

FIX02 proposed routing the existing semantic assessments through
`models.slots.assessment`, while generation and authorized repair keep their own
bindings. Its rollout table recorded every milestone as proposed or not run, and
the Spec workflow still selects only the `spec_generation` and `repair` slots.
FIX01-02 left the routing unselected, and FIX03 Phase 9 kept it as a conditional
measurement option. Nothing is recorded here as completed. The proposal is retained
in the [archive](archive/FIX02.md) and carried forward as FIX01 R11.

## 5. FIX04 — Completed evaluation-foundation, compatibility and admission work (15–16 October 2026)

FIX04 remains the active evaluation design. This section holds the records removed
from it on 16 October, kept verbatim: its status and live-evidence header, the full
F9–F12 diagnostic findings, the completed phase plans and their results, its
implementation records, its delivery record, and the FIX04 entries formerly in
FIX01's implementation history. FIX04 keeps condensed findings and phase summaries
under the same headings. Section references (§) and phase names in the moved text
refer to FIX04; links point to current locations.

The full-workflow diagnostics, in Melbourne time on 16 October:

| Run | Case | Build | Calls | Tokens | Outcome |
| --- | --- | --- | ---: | ---: | --- |
| 07:54 | loan-renewal | uncommitted `4f25a06` (source `abf965…`) | 13 | 25,508 | `UnsafeSpecificationRepair` on competing duplicate records, before source review |
| 08:09 | loan-renewal | uncommitted `4f25a06` (source `fbb975…`) | 37 | 101,002 | `WorkflowTokenBudgetExceeded` during entity source review |
| 09:18 | hello-world | uncommitted `94e2838` (source `2a30ee8d…`) | 41 | 101,134 | `WorkflowTokenBudgetExceeded` in review, which used 77% of the tokens |
| 16:20 | hello-world | committed `bfec3d7` | 8 | 12,896 | `RepairNoProgress`: the insertion-only title was rejected at admission and the repair repeated it |
| 18:58 | hello-world | `54de975` with uncommitted Phase 1A.2 code (source `fbd52cd8…`) | 14 | 20,374 | `RepairNoProgress` at record generation; admission escape measured zero |
| 20:22 | hello-world | committed `6676ad8` | 14 | 22,780 | Blocked at native exact-copy coverage before review: the value was typed, never inserted ([FIX04 F13](FIX04.md#f13--high-composition-correction-works-but-exact-values-now-fail-the-other-way-and-review-still-dominates)) |
| 20:33 | hello-world | committed `6676ad8` | 42 | 100,884 | `WorkflowTokenBudgetExceeded` during re-review, with review at 75.6% of the tokens ([FIX04 F13](FIX04.md#f13--high-composition-correction-works-but-exact-values-now-fail-the-other-way-and-review-still-dominates)) |

Twenty-two one-send compatibility probes also ran between 15 October 16:25 and
16 October 16:16. Eighteen received HTTP 403 access rejections, one exposed the
response-decoding defect, and three were `compatible`: 07:46, 13:55 and 16:16, the
last on clean committed `bfec3d7`. No run published a specification or ran rubric
evaluation, and no live debugger replay was performed.

### 5.1 Status and live evidence as recorded on 16 October

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
are recorded in [FIX01](#56-fix01-implementation-history-entries-1516-october-2026); this summary records
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
([Phase 2 audit](#544-phase-2-implementation-audit),
[cost investigation](#545-phase-2-review-and-repair-cost-investigation)). Its first defect was not
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

The [18:58 hello-world run](../zig-out/e2e-spec/2026-10-16T07-58-59Z-ec56ff4bc24a21c0082210cf6caa8f31/report.json)
was the first live test of Phase 1A.2. It ran on `54de975` with the Phase 1A.2 code
still uncommitted (`modified: true`), so it is diagnostic evidence and cannot close
that phase's exit gate. The brief and story were admitted with prose, admission
escape was measured zero, and the run reached record generation before failing with
`RepairNoProgress` after 14 calls and 20,374 tokens.
[F12](#f12--high-descriptive-fields-recover-but-record-fields-collapse-to-insertions)
records the findings and the Phase 1A.3 remediation.

**Repository revision:** findings were first reviewed at
`5816d9bed631acabcb256025e911bb565b8f9771`. The 16 October evidence ran on uncommitted
builds of `4f25a0603d14b1d7413f3e992e53c931c97c40eb` and, for the 09:18 diagnostic,
`94e2838999a889d4b9ea01eeab23bf758f39a1a9`. Phase 1A is committed as
`bfec3d7f39a4dd25b6d3673206327d4e4c1e92db`, on which the 16:16 probe and 16:20
diagnostic ran unmodified. `54de975` commits only the Phase 1A.2 decision documents;
the 18:58 diagnostic ran on it with the Phase 1A.2 code uncommitted (source
`fbd52cd8…`). Each report records its exact source identity.

**Status:** **Phase 0 complete (offline), 15 October 2026**; its
concrete protocol and evidence are linked in §5.6. The user-directed Converse
cutover and small-model test cost policy are included. **Phase 1's offline
implementation is complete and mechanically verified**: a fresh production-request
compatibility harness has a one-send boundary. Its authentic separately authorized
GPT-OSS-20B exchange passed the bounded compatibility gate on 16 October. No full
workflow has completed on the selected binding. **Phase 1A's implementation and
offline exit gate are complete, 16 October 2026**: its accepted composition
contract, retained replay and 1,699 passing verification tests are recorded in
[the implementation evidence](#541-phase-1a-implementation-record). Its live mechanical
behavior is confirmed on committed `bfec3d7`: the defect stopped at admission and the
run ended early with a typed failure. Generation did not recover: that build's
model-facing presentation still offered and encouraged the rejected shape (F11).
**Phase 1A.2's offline implementation is complete, 16 October 2026**; its
implementation and validation are recorded in
[the Phase 1A.2 evidence](#542-phase-1a2-implementation-record). Its first live test,
on uncommitted code, fixed the descriptive fields and repaired the story, but record
fields collapsed into insertions and their field-level repair repeated the defect
(F12). Separately approved hello-world and loan-renewal diagnostics on a committed
build remain required to close its exit gate, and **Phase 1A.3** addresses F12
before the Phase 2 freeze. Phase 2's harness is implemented, but its baseline
remains unfrozen pending Phases 1A.2 and 1A.3 and renewed budget feasibility with the
recorded user decision. Semantic benefit and reduced
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

### 5.2 Live diagnostic findings F9–F12

#### F9 — High: selected-binding full-workflow diagnostics expose generation, review and budget failures

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

#### F10 — High: model text composition is not admitted against its field purpose

This finding describes the retained diagnostics before the Phase 1A amendment.
The [completed implementation and offline evidence](#541-phase-1a-implementation-record)
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

#### F11 — High: admission now stops the defect, but generation cannot recover from it

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
   the unit (four for the brief, including `clarification_question`, which its
   selected schema permits through the clarification alternative;
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

#### F12 — High: descriptive fields recover, but record fields collapse to insertions

**Run.** The [18:58 hello-world diagnostic](../zig-out/e2e-spec/2026-10-16T07-58-59Z-ec56ff4bc24a21c0082210cf6caa8f31/report.json)
ran on `54de975` with the Phase 1A.2 code uncommitted (source `fbd52cd8…`,
`modified: true`) and the GPT-OSS-20B binding. It ended `workflow_failed` with
`RepairNoProgress` (`unchanged_repair`) at `generate-records-merge-repair`, after
14 calls and 20,374 tokens. Admission escape was **measured zero** (9 admitted values
from 7 producers). No review call was made and nothing was published.

**What worked:**

| Calls | Unit | Outcome |
| --- | --- | --- |
| 2 → 3 | Token classification | Malformed envelope (`{"token{…`), fixed by protocol correction |
| 8 → 9 | Brief | Title and goal came back as plain prose under their string-only grammar. The description typed insertion syntax inside prose, which was rejected as `EmbeddedInsertionSyntax`; protocol correction, with the complete assignment, produced prose with a real insertion |
| 10 → 11 | Story | Insertion-only, rejected as `reference_only`. The composition repair with the rendered defect returned prose with an embedded exact copy and was admitted (`changed: true`) |
| 12 | Entity applicability | Admitted as prose (but see failure 3) |
| 13 → 14 | Records | Insertion-only in five fields; the repair repeated the value and the run stopped with `unchanged_repair` |

Phase 1A.2's intended effects are therefore visible. Every field whose grammar no
longer offers exact copies came back as prose (title, goal, entity-applicability
basis, entity meaning and relationship: five of five), the wire-syntax rule and its
correction worked, the first rendered composition repair succeeded, and the escape
metric reports a measured zero.

**What failed:**

1. **Initial record authoring collapsed into insertions.**
   [Call 13](../zig-out/e2e-spec/2026-10-16T07-58-59Z-ec56ff4bc24a21c0082210cf6caa8f31/evidence/generation/call-000013/model_output.txt)
   returned `{"fragments":[{"kind":"exact_copy"}]}` for Given, When, Then, the
   functional requirement and the entity name: every returned field that the request's
   new `insertion_fields.exact_copy` list named. The unlisted fields (entity meaning
   and relationship) came back as prose. The pre-Phase-1A records request for the same
   case ([09:18 run, call 10](../zig-out/e2e-spec/2026-10-15T22-18-35Z-a8740d575019326cb5b63f994c3dc426/evidence/generation/call-000010/model_output.txt))
   had no such list and returned prose records, typing the literal inline. Across this
   run, initial outputs in listed fields were insertion-only in six of seven cases
   (story, Given, When, Then, requirement text, entity name; the description embedded
   insertion syntax instead), and in none of the five unlisted fields. The records
   request carried 15 `field_rules` with only three distinct instructions, ten of
   them identical: "Write nonblank prose describing the behavior or constraint. Exact
   copies may carry its exact-value obligation inside that prose; use only insertion
   alternatives listed for this field", plus an 11-path insertion list.
   **Hypothesis, not yet attributed:** the presentation of where insertions are
   *permitted*, with obligation wording, is being followed as an instruction to insert.
   It is confounded by field type, because the listed fields are the obligation-bearing
   ones most likely to mention the token. It must be attributed before presentation
   changes.
2. **Field-level repair cannot recover a collapsed record.** The Given repair
   ([call 14 request](../zig-out/e2e-spec/2026-10-16T07-58-59Z-ec56ff4bc24a21c0082210cf6caa8f31/evidence/generation/call-000014/request.json))
   received the rendered defect and field rule, but `source_groups: []`, none of the
   record's sibling fields, and a field purpose that forbids inventing prerequisites,
   while four other fields of the same batch were also defective. The successful story
   repair had its source groups and a narrative purpose. Even had Given succeeded,
   three more single-field repairs (When, Then, requirement text) would have followed
   in sequence against the same degenerate siblings. A composition failure spanning a
   unit is being repaired at field granularity. By contrast, the brief's
   embedded-syntax failure went through protocol correction with the complete original
   assignment, and that succeeded.
3. **Entity applicability was wrong, and the identity-label exception admitted the
   consequence.** [Call 12](../zig-out/e2e-spec/2026-10-16T07-58-59Z-ec56ff4bc24a21c0082210cf6caa8f31/evidence/generation/call-000012/model_output.txt)
   declared an entity "required" for a feature with no business data, justified by an
   invented need to capture "identity, configuration, and runtime behavior". The
   records batch then needed an entity, and its insertion-only name `Hello, World!` is
   admissible under the entity-name exception. Native rules cannot judge
   applicability; this is a semantic defect that inflates record work and later review.

**Also observed:**

- **Extraction merged the three requirements into one claim** again: four of four
  samples since Phase 1A, against one of two before it. Records therefore receive one
  source group carrying every behavior. Still unattributed; include it in the
  attribution replays.
- **GPT-OSS envelope-prefix malformation recurred** (`{"token{` here; `{"kind{` and
  `{"find{` in earlier runs), costing one protocol correction each. The approved
  normalizer covers only `{"{`; do not widen it without a decision, and count it under
  mechanical enforcement.
- **No complete-run cost exists yet.** The run used 20,374 tokens in 14 calls and
  still did not reach review.

**Implication.** Phase 1A.2 resolved the descriptive-field failure and repaired the
story. The same failure class now concentrates in obligation-bearing record fields,
and field-level repair cannot recover a unit-wide collapse. Phase 1A.3 attributes
the presentation hypothesis and settles the repair granularity before the Phase 2
freeze. Do not add sampling or temperature changes, extra repair attempts, a second
model, envelope-normalizer widening or field-specific code.

### 5.3 Completed phase plans and results

#### Phase 0 implementation

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

#### Phase 1 implementation and live gate

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

#### Phase 1A plan, decisions and results

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
[The implementation record](#541-phase-1a-implementation-record) maps every deliverable
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

#### Phase 1A.2 plan, decisions and results

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
   without exact-copy insertion objects. Passive references remain permitted, so
   prose presence still needs native admission. A literal the model types there is
   ordinary prose without lineage, which
   those fields do not need because their occurrences cannot satisfy coverage.
   Entity names keep their identity-label exception. The amendment is recorded in the
   [composition contract](../design/contracts/text-field-composition.md#phase-1a2-amendment--exact-copies-only-where-they-can-carry-an-obligation)
   and [ADR 0020](../design/decisions/0020-derived-exact-reference-lineage.md);
   its offline implementation is recorded in
   [the Phase 1A.2 evidence](#542-phase-1a2-implementation-record).
2. **Project schemas per field from the registry.** Each field's fragment alternatives
   list only its permitted insertion kinds, through the shared schema-projection owner,
   with one rule for generation, protocol correction and every repair route. Where
   insertions remain permitted, "contains prose" still cannot be expressed in the
   closed schema profile or provider grammars. Nonblank prose remains a native
   admission rule for every prose-required field.
3. **Derive guidance from the registry.** Remove the unconditional `exact_copy`
   sentence from `generation.context.json`. Present the assigned fields' composition
   rules in plain, field-specific terms, only for fields in the selected schema; drop
   rows for fields the request cannot return, such as extraction kinds outside the
   selected schema. Retain clarification-question rules when the selected schema
   permits a clarification response, including the brief's current alternative.
4. **Offer exact-copy choices only where they can be used.** Supply preserved tokens and
   token-only source groups only with a request containing a field whose policy
   permits them, and identify which fields may use them.
5. **Make composition repairs present the defect, not an echoable answer.** For a
   composition issue, show the rejected value as rendered text with the specific issue
   and the field's rule, while the exact old value stays native for compare-and-swap.
   The repair schema uses the same per-field projection. When no insertion
   alternatives remain, it offers only literal text forms; native admission still
   enforces nonblank prose.
6. **Close the reporting gap.** Give engine-produced values a native origin, so
   admission escape can report measured zero.
7. **Keep** the no-progress exhaustion, temperature and repair allowances unchanged.

**Offline implementation and checks:** complete, 16 October 2026. Final
`zig build verify -j2 --summary all` passed **156/156 steps and 1,718/1,718 tests**,
including the retained F10/F11 replay and native packaging smoke. The registry drives native
field bindings, selected schema and guidance, insertion catalogues and every repair
schema. Composition repairs present rendered defects while exact compare-and-swap
witnesses remain native. Typed native producer proofs close the attribution gap
without treating missing model receipts as known evidence. See
[implementation and validation](#542-phase-1a2-implementation-record).

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

**Live result — 16 October 2026, uncommitted build.** The 18:58 hello-world
diagnostic exercised Phase 1A.2 on uncommitted code (F12). The brief and story were
admitted with prose; the run ended in a typed composition failure (in records) after
a repair with rendered presentation; and admission escape was measured zero. That
meets this gate's hello-world criteria in substance, but not on a committed build,
and the loan-renewal diagnostic has not run. The gate therefore remains open. F12's
record-field failures are addressed in Phase 1A.3.

**Then, before the Phase 2 freeze:** the budget and scope decision in §5.5, using the
new cost evidence, and the review and repair contract work identified in F9 and the
[cost investigation](#545-phase-2-review-and-repair-cost-investigation), if the runs now reach review
and exhaust the budget there.

#### Phase 1A.3 plan and decisions as approved

**Why it precedes Phase 2.** F12 shows the composition failure now concentrated in
obligation-bearing record fields, with a plausible but unattributed presentation
cause, and a repair granularity that cannot recover a unit-wide collapse. Both
change which candidates are admitted, so the baseline must be frozen after them.

**Steps:**

1. **Commit Phase 1A.2 and rerun its gate on the committed build.** The 18:58 run used
   uncommitted code and is diagnostic evidence only.
2. **Attribute before changing presentation, through separately approved diagnostic
   replays.** Using the [single-request debugger](../design/decisions/0019-single-request-debugger.md),
   replay call 13's exact captured request unchanged and in presentation variants:
   (a) without `insertion_fields`; (b) with `field_rules` reduced to one entry per
   distinct instruction; (c) both; and (d) without the "obligation" wording. Keep the
   model, settings and schema identical, with at least three repetitions per arm.
   Also replay call 1 (extraction) with and without its field rules and insertion list,
   to test the claim merging. Record the insertion-only rate per field and arm.
   Replays carry no workflow authority. Expect about 4,000 tokens per records replay
   and 16 to 20 sends in total.
3. **Correct presentation at its owner, as the attribution indicates.** In
   `model_field_presentation.zig`, state the composition rule once (prose is required;
   a permitted exact copy goes inside a sentence and never forms the whole value), list
   fields only where that changes the answer, remove duplicate rules, and describe
   permission without obligation wording. The selected schema stays the authority for
   what is permitted. No field-, case- or model-specific text.
4. **Decide the repair granularity for composition failures. Decided: option (a),
   approved by the user, 16 October 2026.**
   - **(a) Unit-level correction (approved).** Route `reference_only` through the
     unit's existing bounded protocol correction, with the complete original
     assignment, as embedded insertion syntax already is. Composition is a property of
     the whole response, its defective fields share one cause, and that route succeeded
     live for the brief.
   - **(b) Richer field repair (not selected).** Keep unit repair, but give
     record-field composition repairs the record's sibling values and its source
     group, and repair all composition defects of one record in one request.

   The amendment is recorded in the
   [composition contract](../design/contracts/text-field-composition.md#phase-1a3-amendment--composition-defects-are-corrected-as-a-unit)
   and [§22.4](../design/contracts/22-repair.md#224-repair-request-and-response):
   composition rules are checked at response admission for every response type, one
   rejection reports every violating field, correction uses the existing bounded
   protocol correction with the complete request, and unit repair no longer receives
   composition defects. Offline implementation and attribution preparation are
   recorded in [the Phase 1A.3 record](#543-phase-1a3-admission-routing-and-attribution-preparation). Live
   attribution and the presentation change remain pending.
5. **Measure entity applicability as its own failure class.** No native rule can judge
   it. Record false-required applicability and its downstream cost in Phase 2
   attribution, and do not narrow the entity-name exception on this evidence.
6. **Keep** temperature, retry allowances and the envelope normalizer unchanged, with
   no field- or model-specific code.

**Test:** presentation projection tests for the chosen wording and deduplication;
routing tests for the chosen repair granularity across generation, protocol
correction and every repair route; the retained replay extended with the 18:58
captures, still rejecting every captured defect; offline integration; then
`zig build verify --summary all`.

**Exit gate:** offline checks pass; decision 4 is recorded (16 October 2026); the
change is committed; then one separately approved diagnostic each for hello-world and
loan-renewal on that committed build. Each must either admit records with prose, or
end in a typed composition failure after one correction or repair that had complete
unit context, with admission escape measured zero. This also closes Phase 1A.2's live
gate. It is mechanical evidence, not quality.

#### Phase 2 harness implementation

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
The subsequent [implementation completeness audit](#544-phase-2-implementation-audit) maps
each measure to its owner and records the separately approved live diagnostic;
its failed execution does not close this phase.

### 5.4 Implementation records formerly kept as separate files

#### 5.4.1 Phase 1A implementation record

Formerly `FIX04-phase1a-implementation.md`.

This records Phase 1A's original validation. Its subsequent presentation, native
producer and format changes are recorded in
[Phase 1A.2](#542-phase-1a2-implementation-record); the counts below remain historical.

The explicit implementation instruction settles the four policy decisions in
[the accepted composition contract](../design/contracts/text-field-composition.md).
It amends §§7.1, 17.3, 22 and ADR 0020 without changing the overall Proposed
design status. This is engine development and offline mechanical evidence;
no new live workflow, provider request or target-project execution is included.

| Required behavior | Owning contract and implementation |
| --- | --- |
| Explicit prose and insertion roles | `text_field_policy.zig` has an exhaustive field inventory. Narrative and behavior fields require nonblank prose; entity names are the sole identity-label exception. Only declared behavior/constraint fields carry obligation-bearing exact copies. |
| Native admission and protocol correction | `model_text_wire.zig` recognizes the closed insertion grammar in declared prose. `model_envelope.zig` uses existing bounded correction. `typed_text.zig` enforces field composition and the same source-aware wire rule after decoding. Explicit native selectors cover plain-string review clarification questions. |
| Exact original-source exception | Native packets, including reconstructed reconciliation-stage packets, preparation, correction and repair retain original source witnesses. Source-backed wire-object spans preserve their exact bytes during canonical normalization; surrounding prose uses the existing NFC owner. Matching display text and earlier model output do not supply a witness. |
| Coverage | `specification_coverage.zig` credits composition-valid obligation-bearing fields. Incidental insertions retain lineage but do not satisfy behavioral coverage. The obsolete whole-field literal-to-insertion coverage rewrite and its execution path are removed; unsupported reconstruction blocks. |
| Repair and progress | `atomic_repair.zig` compares canonical declared text for progress while keeping exact old-value and dependency preconditions. `workflow_retry.zig` and the runner exhaust unchanged repairs under the current defect key before applying their tentative deltas. Actual sends/tokens and completed counts remain charged; no successful repair, re-review or publication follows. |
| Presentation and readback | Generation/reference/repair packets project the field registry. Native and stored-value validators reuse its composition and source rules, including source-review questions. Source-aware clarification refresh, rendering and publication check retained questions against current original sources, including successful workflows with no new needs; user answers and protected-form bytes retain their own contracts. |
| Reporting | Current reports use `first_native_rejection`, separate `representation_admission` attribution and a native admitted-value audit. The primary escape denominator is invoked native workflows, including zero-send failures, with unknown coverage explicit; producer-origin incidence is secondary. Generation-arm scoring retains its existing dispatched-workload convention. Later sends/tokens measure chronological exposure, not causal cost. |

Native record-batch assembly retains per-field repair origins and stable occurrence
identities, including gaps from deleted records. The audit uses that same native
projection to deduplicate assembled views without conflating equal fields from
different records or attributing repaired text to its initial author.
Clarification projections retain their native IDs; a missing current producer
origin remains explicit rather than manufacturing attribution or measured zero.

Current debug descriptions use `model-request-debug/v4` and replay records use
`request-replay/v5` to retain the native source/prose metadata. E2E reports/events
and the affected baseline acquisition, scoring and assessment-input contracts
use their current closed versions. Unsupported historical versions are rejected;
there is no compatibility reader or rewrite of authentic captures.

##### Retained replay

The [retained fixture](../test/calibration/representation-admission/README.md)
copies exact bytes and hashes from all five F10 diagnostics. Its integration
replay exercises native admission for 23 captured exchanges and 79 selected
values: 10 insertion-only values, 19 encoded insertion values and 50 prose-bearing
controls. The fixture is available from a clean checkout and does not depend on
ignored capture directories. It supplies no current workflow or semantic authority.

##### Validation and remaining evidence

Verified with the repository-pinned Zig 0.16.0:

| Command | Result |
| --- | --- |
| `zig build test-model-envelope test-model-request-preparation --summary all` | 6/6 steps; 81/81 tests passed. |
| `zig build test-model-logging --summary all` | 9/9 steps; 204/204 tests passed. |
| `zig build test-clarification-inputs test-specification-generation test-baseline test-required-authority test-workflow-repair-retry test-atomic-execution test-architecture --summary all` | 29/29 steps; 1,317/1,317 tests passed on the final implementation. |
| `zig build verify --summary all` | 156/156 steps; 1,699/1,699 tests passed, including lint, the complete offline integration suite, architecture checks and clean-directory native packaging smoke tests. |
| `git diff --check` and `git diff --cached --check` | Passed. Existing staged work was preserved. |

The retained replay's machine result is
`.zig-cache/representation-admission/replay.json`: five runs, 23 exchanges,
79 values, 10 `reference_only`, 19 `embedded_insertion_syntax`, 50 admitted,
and zero provider calls. The final full-verification log is
`.zig-cache/phase1a-verify-complete.log`; the final owner-check log is
`.zig-cache/phase1a-final-owners.log`. Complete suites ran without a scenario
filter. Historical debug formats remain unsupported rather than supplying
current calibration evidence. No dependency, model binding or live budget changed.

Phase 1A's implementation and offline exit gate are complete. This evidence
establishes native admission enforcement and bounded no-progress handling.
The Phase 2 freeze still requires a committed build, renewed budget feasibility
and its recorded user decision. Separately approved live diagnostics and the
development-panel baseline remain outstanding; offline admission enforcement
does not establish semantic improvement, useful publication or reduced live cost.

#### 5.4.2 Phase 1A.2 implementation record

Formerly `FIX04-phase1a2-implementation.md`.

This implements the user's approved offline remediation in
[FIX04 Phase 1A.2](FIX04.md#phase-1a2--make-model-facing-presentation-consistent-with-admission).
The accepted [composition contract](../design/contracts/text-field-composition.md)
and ADR 0020 retain the exact-copy prohibition for descriptive fields, the entity-name
exception and the existing passive/source roles. The overall design remains Proposed.
No model binding, temperature, retry allowance, workflow budget or dependency changes.

| Required behavior | Owning contract and implementation |
| --- | --- |
| Per-field schemas | Native wire declarations bind returned text leaves to `text_field_policy.zig`. `model_candidate_json.zig` derives their paths; `model_text_field.zig` filters insertion alternatives through the registry. The shared schema owner applies this to initial generation, narrowed/composed results, protocol correction and every repair route. A closed repair field selection distinguishes a replacement's wire contract from a separately selected native wire member, matching its existing decoder. Descriptive exact-copy insertions also reject at native admission and stored readback. |
| Selected guidance | `model_field_presentation.zig` derives plain field rules and permitted insertion targets from the actual selected schema, intersecting its remaining alternatives with the registry. A plain-string question advertises no insertion alternatives. The unconditional exact-copy sentence and whole-inventory tables are removed. Clarification guidance remains when that schema permits a clarification response. |
| Usable choices | Native packet producers declare insertion catalogues and token-only source-group entries. The shared presenter offers them only when a returned field permits their insertion kind. Original source evidence retains its separate purpose. Projection retains exact original array indices and leaves the immutable native packet unchanged. |
| Rendered composition repairs | `atomic_repair.zig` distinguishes structured diagnostic repair from native composition repair. Composition packets show the canonically rendered defect and registry rule, omitting the rejected wire value and raw containing candidate. Record rendering uses the same shared lineage as native record validation. Fixed non-question detail facts remain available without echoing the rejected question. Exact compare-and-swap witnesses, dependencies, repair permits and unchanged-repair exhaustion remain native and unchanged. Extraction, reconciliation, specification and source-question repair use this owner. |
| Native origins | The audit's producer is a closed model/native/unavailable union. Native summary reuse links to an earlier audited value and the real native validation digest. Clarification refresh retains validated native state identity. Missing model receipts and missing native parents remain unknown. Complete native-origin audits can report measured zero without inventing model calls. |
| Capture and replay | `model-request-debug/v5` and `request-replay/v6` retain native wire-field bindings. Affected E2E reports, baseline acquisition and baseline scoring use v3. Events and assessment inputs retain their unchanged versions. Historical captures are immutable; no compatibility reader or migration is added. |

Removing exact-copy alternatives does not make the grammar express prose presence
where passive or source insertions remain permitted. Native admission still owns
that check. A selected string-only contract enforces a string through its grammar.
These are mechanical checks, not semantic adequacy or source-fidelity judgments.

##### Retained evidence

The [F10/F11 replay fixture](../test/calibration/representation-admission/README.md)
contains six runs, 25 captured exchanges and 83 selected values. It retains exact
original request, response, outcome and model-output bytes with SHA-256 bindings.
Stronger-policy expectations are 7 `reference_only`, 5 `prohibited_exact`,
19 `embedded_insertion_syntax` and 52 admitted controls. No captured bytes are
corrected or promoted into current workflow authority. The replay makes zero
provider calls.

##### Validation

Validation uses the repository-pinned Zig 0.16.0, through `build.zig`, without
scenario filters.

| Command | Result |
| --- | --- |
| `zig build test-reference-reconciliation test-specification-generation test-integration -j2 --summary all` | 14/14 steps; 640/640 tests passed. Includes all 164 configured specification-generation scenarios, prepared repair requests across every reconciliation content kind, ordinary and false-empty extraction omissions, and the complete retained replay. |
| `zig build verify -j2 --summary all` | 156/156 steps; 1,718/1,718 tests passed. Includes 1,597 repository unit tests, 115 integration tests, architecture checks, lint and clean-directory native packaging smoke tests. |
| `git diff --check` and `git diff --cached --check` | Passed. |

The final full-verification log is `.zig-cache/phase1a2-verify-complete.log`;
the final repair/integration log is `.zig-cache/phase1a2-final-integration.log`.
The retained replay's machine result is
`.zig-cache/representation-admission/replay.json`: six runs, 25 exchanges,
83 values, 31 rejected defects, 52 admitted controls and zero provider calls.
Regression coverage also includes selected-schema guidance and catalogue omission,
plain question fields, native exclusions, record-wide lineage, fixed question-repair
facts, unchanged protocol-correction inputs, stale CAS, stored readback, native producer
proofs, missing model receipts and allocation failures.

Phase 1A.2's offline implementation and verification are complete. The diff retains
the existing source exception, no-progress exhaustion, provider API, model settings
and resource allowances. There are no approved deviations or compatibility readers.

##### Remaining live evidence

This offline implementation does not close the separately approved live exit gate.
FIX04 still requires one hello-world and one loan-renewal diagnostic on a committed
build. Each must admit brief/story prose or end in a typed composition failure after
a materially different repair presentation, with admission escape measured zero.
No live run was performed for this implementation request. Phase 2 still requires
renewed budget-feasibility evidence, the user's recorded budget/scope decision and
a committed baseline build. Semantic improvement, useful publication and reduced
live cost remain unmeasured.

#### 5.4.3 Phase 1A.3 admission routing and attribution preparation

Formerly `FIX04-phase1a3-implementation.md`.

Authority: the approved decision 4(a) in
[FIX04 Phase 1A.3](FIX04.md#phase-1a3--attribute-insertion-presentation-and-repair-collapsed-units-as-units),
[the composition amendment](../design/contracts/text-field-composition.md#phase-1a3-amendment--composition-defects-are-corrected-as-a-unit)
and [§22.4](../design/contracts/22-repair.md#224-repair-request-and-response).
The design remains Proposed. This work changes engine development contracts;
it does not run a workflow against a target project.

The causal defect is shared response admission: it rejected embedded wire syntax,
but admitted insertion-only values that then reached field-level unit repair.
The request already retains native field identities, original sources and the
complete assignment. Composition rejection belongs at that shared boundary,
before stage-specific validation, using the request's existing protocol correction.

The applicable baseline is design §§1, 3–4, 12, 21–22, 27–28 and 30–31, especially
the candidate-data boundary, native mechanical validation, local bounded retries,
unchanged-repair exhaustion and immutable diagnostic replay. Persistence,
publication, executable capabilities, provider settings and retry allowances do
not change. Presentation wording is reserved for the separately approved
attribution experiment.

##### Admission and repair

The shared response checker follows native field bindings and reports concrete
JSON pointers, field identities and typed composition reasons together. It reuses
the canonical composition policy and source-aware wire grammar. Envelope decoding
retains this diagnostic separately from JSON syntax failures; the existing
protocol-correction owner includes it with the complete original request.
The owners are [model_text_composition.zig](../src/domain/model_text_composition.zig),
[model_envelope.zig](../src/domain/model_envelope.zig),
[model_protocol_retry.zig](../src/domain/model_protocol_retry.zig) and the existing
`typed_text.zig` / `model_text_wire.zig` policy and grammar owners.

Generation, extraction, reconciliation, clarification questions and replacement
responses use that admission boundary. Composition defects cannot authorize unit
repair. The obsolete composition-specific rendered repair presentation is removed;
other repair kinds retain their authorization, old-value/revision checks, progress
comparison and bounded exhaustion. Native/stored-value composition checks remain.
Harness reports, retired-request snapshots, first-rejection evidence and receipt
records retain the grouped composition diagnostic separately from JSON syntax.
Terminal and Markdown views expose every rejected field.

##### Retained offline evidence

The [retained replay](../test/calibration/representation-admission/README.md) adds
the authentic 18:58 diagnostic's calls 8–14. It binds unchanged request, response,
output, context, transport and source bytes with SHA-256. Its historical selected
schemas do not retain the current native field bindings, so it reports wire-syntax
rejection separately from per-field composition validation. It does not invent
historical metadata or claim replay of current whole-response admission.

##### Attribution preparation

The [prepared experiment](../test/calibration/insertion-presentation/README.md)
retains call 13 (records) and call 1 (extraction) from
`2026-10-16T07-58-59Z-ec56ff4bc24a21c0082210cf6caa8f31`.
Records have five presentation arms; extraction has two. Three repetitions per
arm make exactly 21 single-request sends, all pending explicit approval.
Model, settings, evidence and selected schema remain fixed. The offline tool
prepares requests and scores immutable debugger results; it cannot send a request.
Mechanical insertion-only rates and native admission diagnostics do not assess
semantic quality or supply workflow authority.
The canonical strict JSON decoder now handles explicitly declared inert JSON
evidence leaves recursively, as it already did at the root. Closed enclosing
metadata, wire types, unknown fields and duplicate rejection remain enforced;
the calibration tool adds no parallel or coercing reader.

##### Validation and remaining gate

**Offline gate passed, 16 October 2026.**

| Command or evidence | Result |
| --- | --- |
| `zig build verify -j1 --summary all` | 156/156 steps and 1,734/1,734 tests passed, including 120/120 integration tests, architecture, formatting and clean native packaging smoke. Full log: `.zig-cache/fix04-phase1a3-verify-complete.log`. |
| Retained replay within that verification | Seven runs, 32 captures and 100 selected values: 13 `reference_only`, five `prohibited_exact`, 20 embedded-syntax rejections and 62 admitted controls. Eleven complete responses reject the schema-only wire-syntax guard. Zero provider calls. |
| `zig build attribution-replay -- prepare test/calibration/insertion-presentation/prepared` | Seven arms, 14 edit/request artifacts and the 21-trial plan materialized offline. |
| `zig build attribution-replay -- validate test/calibration/insertion-presentation/prepared` | Deterministic regeneration, original request reconstruction and all source pins passed. |
| `zig build attribution-replay -- score test/calibration/insertion-presentation/prepared test/calibration/insertion-presentation/receipts.template.json zig-out/insertion-presentation.unattempted.score.json` | All 21 trials remain unattempted; zero sends and no inferred success. |
| `git diff --check` | Passed. |

Owner-focused build steps also passed during iteration: model-envelope admission
(46 tests), model-request workflow correction/recovery/exhaustion (420), repair
retry (32), real extraction/reconciliation/specification producers (609 combined)
and the offline attribution helper (15). The final full suite includes the later
strict-decoder and report-retention regressions.

The integration matrix preserves native scalar/identity repair coverage using an
invalid-scalar fixture where the former blank fixture now belongs to protocol
correction. The intentional blank story omission response instead proves bounded
protocol exhaustion, grouped `/value` diagnostics, charged sends, zero merges and
no publication. No test was skipped or assertion weakened.

Earlier verification attempts exposed installed-compiler/cache and loopback
sandbox restrictions, a stale fixture assertion, and exhausted disk space.
The final run used the same checks serially with the required system access.
Generated Zig scratch and task-created standalone test caches were cleared; stale
cache manifests were archived before rebuilding. Source and retained live-run
evidence were preserved. No production dependency, provider setting, retry budget,
normalizer or architecture exception changed.

No model calls or E2E runs occurred. The attribution sends,
the evidence-based change in `model_field_presentation.zig`, and the separately
approved committed-build hello-world and loan-renewal diagnostics remain open.

#### 5.4.4 Phase 2 implementation audit

Formerly `FIX04-phase2-audit.md`.

This historical audit precedes the subsequently authorized Phase 1A admission
amendment. Its command results describe that earlier build. The
[Phase 1A implementation record](#541-phase-1a-implementation-record) records the new
contract and verification; the Phase 2 freeze still requires fresh feasibility
evidence on the committed build containing that amendment.

This audit maps [Phase 2 and the common measures](FIX04.md#55-common-measures-meaningful-improvement-and-brittleness)
to the development harness. Implementation, offline enforcement evidence and live
semantic evidence are separate. The governing design remains proposed.
The applicable boundaries are [design §§1, 3–4, 28, 30–31](../design/design.md):
LLM output remains candidate data, semantic assessment is not deterministic
proof, the native workflow/runner retains authority, and automated verification
cannot make live model calls. The changes belong to the development acquisition
and assessment harness; production generation assignments and budget policy
remain governed by their existing contracts.

| Required behavior | Implementation and regression boundary |
| --- | --- |
| Unchanged A alone; original/repeated/transformed development inputs | `test/harness/generation_comparison.zig`: 72 A workloads, equal independent-feature weighting, separate baseline/paired modes |
| Committed provider-integrated source/build, exact inputs and selected settings | `baseline/freeze.zig`, `frozen_binding.zig`: closed freeze, exact source/build/toolchain/input hashes, native compiled budget, explicit model binding and drift rejection |
| Settings across native model roles | The protocol explicitly names its generation slot; generation keeps low reasoning and 16,384 output tokens. Each other request matches its exact frozen slot controls, including omitted provider-owned output allowances; no role-specific exception or substitution is inferred |
| Budget feasibility before freezing | `baseline/feasibility.zig`, `preflight.zig`: authentic selected-binding whole-workflow usage, review/repair included, explicit recorded decision, no completion inferred from stopped lower bounds |
| Exact requests and original responses; corrections remain separate | Production `e2e/invoke.zig` and `trace.zig`, `baseline/acquisition.zig`, `candidates.zig`, `reviews.zig`: native origins, original raw HTTP/model bytes, candidate snapshots and native typed findings |
| Experiment-wide bounded accounting | `baseline/dispatch.zig`, `experiment.zig`: charge before transport, full actual usage including overshoot, halt on unknown/uncertain usage, canonical one-shot freeze claim, no restart or resume |
| Honest incomplete execution | `baseline/acquisition.zig`: every planned trial retained, paid receipts survive report-write failure, independent source-drift diagnostics, failures/unknown usage/unattempted trials remain distinct |
| Diagnostic versus actual complete workflow scope | Native whole-workflow invocation uses actual predecessors; comparison diagnostics cannot invent publication authority; native useful-completion assessment is separate |
| Actual-output fidelity and clarification correctness | `baseline/assessment.zig`: exact native output/source quotations, original versus current labels, explicit dispute/provenance, no generated-view authority |
| Original upstream meaning and corrected predecessors | `baseline/upstream.zig`: each original extraction/reconciliation assignment has its own exact native output/hash/source-backed assessment; corrected originals cannot disappear behind faithful specification generation; the selected generation sizing metric remains unchanged |
| Useful completion | `baseline/useful_completion.zig`: exact native publication plus source fidelity plus canonical frozen-rubric assessment; missing/disputed/unconfigured assessment remains unknown |
| Correct evaluator rubric and isolation | Explicit `--rubric` uses `semantic-simplicity/rubric.json`, replacing template-specific criteria; evaluator files/expectations are excluded from generation materialization |
| Harm, including review before a candidate exists | Cumulative source-backed issue events, exact per-category counts, per-feature incidence and independent-feature risk-stratum rates; later recovery cannot erase harm |
| Robustness, sensitivity and repeats | Per-variant semantic/mechanical/unknown coverage; all variant repetitions checked; attempted/partial/unattempted bundles; unattempted variants cannot become representation failures |
| Finding-type accuracy | Typed native source/principle/preservation findings with source-backed expected kinds; original/latest/corrective confusion counts, precision/recall and explicit unmeasured contracts |
| Failure origin and reproducible examples | Independent supplied causal stage and native chronology, exact trial examples grouped by category/stage/domain/repetition; unknown causes block advancement |
| Complete resource use and stage shares | All physical sends, actual input/output tokens and elapsed time; median/worst distributions, failed-inclusive cost per useful completion, stage and feature totals/shares with unknown usage explicit |
| Qualification sizing and feasible exact counts | User-selected complete first-pass generation fidelity; counts retained when infeasible; forecast includes actual baseline cost and every declared future phase; incomplete evidence cannot select holdout IDs |
| Explicit Phase 2 decision | `baseline/phase2_decision.zig`: advance, retain baseline, revise or inconclusive; generation changes do not compensate for upstream/review/repair/provider failures |

The implementation audit found and corrected gaps in budget reuse, receipt
retention, publication assessment, template-rubric reuse, variant denominators,
material-versus-mechanical variability, cumulative early-review harm, qualification
cost scope and causal-attribution gates. Tests cover accepted and rejected cases
at these owners; scripted tests remain offline integration evidence.
Roundtrip regressions also cover canonical fixed-digest arrays, assembled candidate
snapshots, intermediate per-origin mechanical rejection evidence and inherited
verdict proof for all current partial review-repair schemas.

The live exit gate also requires the frozen development panel's authentic outputs,
completed source-backed assessments, resolved material disagreements, measured
failure sensitivity and exact feasible qualification counts. A diagnostic run on
an uncommitted build cannot close it. The current implementation must not claim
semantic benefit, reduced brittleness or Phase 5 qualification from mechanical
verification alone.

##### Approved live diagnostic

The user explicitly approved one live evidence run. Executed:

```sh
./scripts/e2e-spec.sh --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json
```

[Native report](../zig-out/e2e-spec/2026-10-15T22-18-35Z-a8740d575019326cb5b63f994c3dc426/report.json)
and [readable report](../zig-out/e2e-spec/2026-10-15T22-18-35Z-a8740d575019326cb5b63f994c3dc426/report.md)
retain the exact source/build reconstruction, native requests/responses and
actual usage. The configured binding was Bedrock `openai.gpt-oss-20b-1:0`, Sydney,
low reasoning, native schema. The retained build revision is `94e2838999a889d4b9ea01eeab23bf758f39a1a9`,
with source hash `2a30ee8d6f01e4b286da002c40c75e6bbc759e13faf52ff0f6e9193667014175`
and `modified: true`.

The command failed with `WorkflowTokenBudgetExceeded`: 41 physical model calls,
101,134 actual tokens against the compiled 100,000-token workflow budget, with
complete usage accounting. The terminal operation was
`g58-g46-g36-g25-g14-g6-review-post-source-assess-model-request-call`.
No specification was published and rubric evaluation did not run. This is a
full-workflow development diagnostic with a stopped cost lower bound, not a
frozen baseline, complete product run or quality qualification. There was no
automatic retry, budget increase or second live run.

The current budget decision and committed-baseline prerequisites remain open.
This failed diagnostic does not authorize reducing the panel or changing engine
budget policy. Raising the workflow budget, reducing review/repair cost through
its owning contract, or narrowing qualified scope requires the explicit decision
specified by FIX04 §5.5.

##### Final verification and feasibility readback

`zig build test-baseline test-rubric-evaluator --summary all` passed **6/6 steps,
535/535 tests** after the final slot-aware fix. `zig build verify --summary all`
passed **156/156 steps, 1,659/1,659 tests**, including architecture, offline
integration and native clean-directory packaging/smoke checks. Staged and
unstaged `git diff --check` passed. Automated checks made no model calls.

The final offline `baseline prepare` used the explicit protocol, cases,
Hello World workflow template, publication rubric and
`zig-out/baseline/phase2-audit-budget-plan.json`, which names the retained live
diagnostic as cost evidence and keeps the user decision unresolved. Exact command:

```sh
zig build baseline -- prepare --protocol test/calibration/semantic-simplicity/protocol.json --cases test/calibration/semantic-simplicity/cases.json --template-case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json --budget-plan zig-out/baseline/phase2-audit-budget-plan.json --rubric test/calibration/semantic-simplicity/rubric.json
```

The [feasibility report](../zig-out/baseline/2026-10-15T22-38-08Z-4ae44015f25ecde96580bc1c4c065da1/budget-feasibility.json)
successfully imports all 41 exact native exchanges, including the repair slot's
omitted output allowance, and accounts 101,134 actual tokens. It correctly returns
`insufficient` and exits 1 with no freeze, acquisition or API call. Reasons include
uncommitted baseline, unresolved user decision, no complete product-flow cost
evidence, observed workflow-budget exhaustion, and projected experiment-stop
exceedance. This is the expected admission rejection, not a test failure.

The declared baseline/selection/qualification scope is 360–504 workloads. Under
its explicit worst-observed-cost assumption the report projects 14,760–20,664
sends and 36,408,240–50,971,536 tokens, against 1,000 sends and 2,000,000 tokens.
Because the observed workflow stopped, these costs remain diagnostic lower-bound
evidence; they are not completion-cost guarantees or authority to raise limits.
Phase 2's code implementation and mechanical verification are complete. Its live
baseline, semantic assessment and qualification-sizing exit gate remain open.

The user subsequently selected **investigate review/repair cost within current
budgets**. The [retained-capture investigation](#545-phase-2-review-and-repair-cost-investigation)
attributes 77.06% of tokens to review, documents the unchanged story repair and
source-obligation diagnosis error, and identifies the owning follow-up contracts.
It made no new model calls or production/budget changes; feasibility remains
insufficient.

#### 5.4.5 Phase 2 review and repair cost investigation

Formerly `FIX04-phase2-cost-investigation.md`.

The user selected **investigate review/repair cost within current budgets** after
the approved diagnostic exhausted the 100,000-token workflow budget. This
investigation reads that retained capture; it performs no additional model calls,
changes no budget or production contract, and does not close Phase 2's live exit
gate. The applicable boundaries are design §§3–4, 17, 21–22 and FIX04 §5.5:
semantic judgments remain model-assisted, complete review and publication gates
remain required, and actual failures stay in the resource denominator.

##### Measured cost

The [native report](../zig-out/e2e-spec/2026-10-15T22-18-35Z-a8740d575019326cb5b63f994c3dc426/report.json)
and [per-call analysis](../zig-out/phase2-review-cost-analysis-2026-10-16.json)
account for every physical send and cross-check all 41 native usage records
against the original provider responses.

| Stage | Sends | Input tokens | Output tokens | Actual total | Share |
| --- | ---: | ---: | ---: | ---: | ---: |
| Extraction and reconciliation | 6 | 7,250 | 637 | 7,887 | 7.80% |
| Specification generation | 5 | 10,227 | 704 | 10,931 | 10.81% |
| Review, including protocol correction | 29 | 72,489 | 5,444 | 77,933 | 77.06% |
| Semantic repair | 1 | 4,322 | 61 | 4,383 | 4.33% |
| **Total** | **41** | **94,288** | **6,846** | **101,134** | **100%** |

Stage attribution reconstructs captured native result-definition selections,
composition contracts and exact call lineage. Direct purpose/owner receipts were
absent in this historical E2E capture; the analysis is diagnostic attribution,
not new engine authority. No call is unclassified and no usage is unknown.

Review comprises 21 singleton `finding` sends costing 55,356 tokens, four
`record_findings` sends costing 13,298 tokens, and four
`preservation_comparisons` sends costing 9,279 tokens. Counts include repeated
assignments and the correction; they are not distinct semantic-subject counts.
The 478 `report.corrections` records are native observations, not 478 paid calls.

Call 23 is the only protocol retry: request 22, attempt 2, costing 3,533 tokens.
It is already included in review. Removing only this retry would leave 97,601
tokens at the same unfinished workflow position, with required work outstanding;
that is not evidence that the workflow could complete within budget.
Input tokens account for 93.23% of total usage. The capture does not provide
provider token counts for individual prompt/schema/evidence components, so byte
sizes must not be reported as measured component token savings.

##### Findings and owning contracts

**A source-review judgment confused field instructions with original source
obligations.** Call 15 correctly notices the defective story
`Hello, World!Hello, World!`, but its `missing_obligation` copies the engine's
instruction to write a narrative. The original source states startup, greeting
and UTC-output behavior; it does not demand a prewritten story. Call 16 then
reports that the extracted claims lost that narrative instruction, even though
the compared collection contains all three source behaviors. This is a
source-backed, model-assisted assessment of the captured outputs, not
deterministic semantic proof or human adjudication.

The owning boundary is the source-review assignment and omission statement in
[`specification_support.zig`](../src/domain/specification_support.zig), its
[`support.prompt.md`](../design/workflows/spec/support.prompt.md), and
[§§17.3/22.1](../design/contracts/22-repair.md). Native membership validation
cannot prove that the statement is faithful to its source. A universal rewrite
from `candidate_omission` to `candidate_invalid` would be wrong: the duplicated
literal really omits behavior, and call 37 later states concrete missing source
behavior. No admitted verdict was changed during this investigation.

**The semantic repair made no progress.** Call 8 generates the story using two
`exact_copy` fragments and no narrative. Call 36 returns the same two fragments.
The native merge records `changed: false`, revision 6 → 7. The repair costs 4,383
tokens; the five observed subsequent review calls cost another 13,933. Their
combined 18,316 tokens are observed cost, not a claim that all revalidation could
be removed. The story is still defective and no specification was published.

The owning boundaries are
[`specification_coverage_repair.zig`](../src/domain/specification_coverage_repair.zig),
[`atomic_repair.zig`](../src/domain/atomic_repair.zig), and the shared retry and
dependent-validation contracts. A no-progress outcome could save failure cost
only through an explicit shared contract; treating an unchanged defective value
as repaired or skipping required validation would violate the existing design.

**Review retention already works and has deliberate exclusions.** After repair,
the paid calls reassess the negative story finding, its loss comparison, the
negative scenario-coverage finding, its loss comparison, and the previously
protocol-corrected second AC assignment. Clean eligible assignments are reused.
[§22.4](../design/contracts/22-repair.md) explicitly excludes omissions and their
revision-bound preservation comparisons from reuse, and conservatively reassesses
protocol-corrected assignments without an additional complete dependency witness.
Adding another cache or accepting equal text alone is not the fix.
The full provider request bytes are identical for calls 15/37 (story), 19/39
(scenario coverage), and 22/41 (second AC). Their repetition follows those
exclusions; it does not establish that their required judgments can be skipped.

##### Next implementation work and evidence needed

1. Qualify the source-review omission contract against original sources, field
   purposes and loss localization. Use the captured false narrative obligation
   and unrelated examples; preserve real missing-behavior findings and all native
   evidence checks. Do not introduce semantic verdict retries without authority.
2. Investigate the model-facing repair projection at the existing rule/packet
   owners. The current omission repair sends both generation context and the
   native preservation evidence structure. Call 36's user payload is 14,705
   bytes: its repair rule is 10,668 bytes, including 9,876 bytes of native
   preservation proof (67.2% of the payload); the candidate adds 2,808 bytes.
   `Rule.guidance()` currently returns the full `ReviewEvidence`, which the
   shared atomic packet serializes. These are measured UTF-8 byte sizes, not
   independently measured token costs or guaranteed savings. Any smaller typed projection must
   retain the authorized old value, target, actual source meaning and internal
   dependency proof. Prove its coverage offline before claiming token savings.
3. If call reduction is still required, propose a bounded review-assignment
   batching amendment with exact per-subject findings, origins, rejection,
   correction and repair tests. The current accepted batch is Given/When/Then;
   broader batching needs an explicit contract decision and semantic comparison.
   It must preserve all independent support and collection judgments.

These are production-owner follow-up work, not missing acquisition/scorer
implementation. No production optimization is implemented or claimed by this
read-only investigation.

The experiment-wide feasibility problem remains separate from one workflow's
100,000-token stop. The declared 360–504-workload scope allows only about
5,556–3,968 tokens and 2.78–1.98 sends per workload on average under the current
2,000,000-token/1,000-send stops. In this one diagnostic, extraction plus
generation alone used 18,818 tokens and 11 sends. Applying that observed initial
cost to the whole scope would already exceed both stops before review; this is
an explicit planning comparison, not a measured cost estimate for unseen cases
or changed candidate architectures. The
[feasibility report](../zig-out/baseline/2026-10-15T22-38-08Z-4ae44015f25ecde96580bc1c4c065da1/budget-feasibility.json)
therefore remains insufficient. Review-cost work cannot itself authorize a
freeze, a smaller panel, larger limits, or another live run.

The implementation checks recorded in the [Phase 2 audit](#544-phase-2-implementation-audit)
remain the latest code validation: 535/535 targeted tests and 1,659/1,659 complete
verification tests passed. This investigation changed only tracking documents
and wrote ignored diagnostic artifacts; text whitespace checks passed.

#### 5.4.6 Offline native exact-value recognition prototype

**16 October 2026.** The user authorized only the first, offline step of
[FIX04 §1.1 item 1](FIX04.md#11-path-to-the-ac-comparison-and-alignment-safeguards).
This is engine-development diagnostic tooling, with **zero model calls**. It
does not amend §7.1, ADR 0020 or the composition contract; production schemas,
recognition, lineage, coverage, repair, persistence and publication are unchanged.
Phase 1A.3 steps 2–3 remain pending rather than silently removed.

The relevant authority is design §§1, 3–4, 7.1, 12, 21–22, 28 and 30–31:
candidate data remains untrusted, required authority cannot be inferred from
matching display text, and offline mechanical evidence is not semantic proof.
The prototype explores the recurring representation burden, not the separate
review-cost or authoring-boundary work.

The development-only `exact_value_replay.zig` entry point and
`test/harness/exact_value/` separate a pure raw-UTF-8 recognizer, captured-value
measurement, Unicode properties, immutable prompt reconstruction, controls and
filesystem acquisition. The recognizer records exact byte spans before NFC or
case folding, retains repeated disjoint occurrences, and blocks overlapping or
competing eligible lineages. Unbound matches remain visible without recognition
credit. The experimental word-boundary adapter uses the existing pinned Unicode
dependency while treating connector punctuation and format characters as word
continuations; no production dependency or Unicode policy changes.

The corpus policy is explicitly **`selected_requirement_membership`**: an
occurrence's own claim ID must occur in the field's captured assigned/selected
requirement set. This conservative experiment is not current ADR 0020 eligibility.
Current explicit exact insertions can add `E` to selected `S`; the prototype does
not decide whether a unique prose match may do the same. Same source, offered
catalogue membership and matching spelling cannot manufacture the missing
token-to-business-requirement relation under the experimental policy.

Corpus inspection uses canonical JSON, envelope, schema, composition and source
wire owners. Exact call identity, run scope, content and schema bind current
native metadata; an identical sibling request cannot lend its witness. Invalid
field bindings, unavailable source witnesses, historical schema gaps and
insertion-adjacent boundary gaps remain explicit. Original-source witnesses take
precedence over projected packet sources. Existing typed insertions and their
explicitly labelled display counterfactuals never become historical plain-prose
output. Proposed exact nodes still face current composition rules, including
behavioral prose and the incidental entity-name exception. The canonical archive
decoder's inherited classification of some internal allocation failures as invalid
input is unchanged; the wrapper propagates exposed allocation failures.

Independent controls fix 53 expectations before execution: **18 matched,
22 no match, 4 ambiguous and 9 rejected**, across hello-world, loan renewal,
technical values, Unicode and invalid inputs. All pass. Separate denial and
punctuation-extension tests show why lexical matching cannot prove semantic
coverage: `1.2` matches inside `1.2.3`, and `/v1/renewals` matches inside
`/v1/renewals/archive` under the experimental word policy. These are observed
limits of the proposed criterion, not cases hidden by domain-specific bans.

The pinned integration fixture retains exact native descriptions, packets,
schemas, raw text and SHA-256 witnesses for the 20:22 hello-world run's records
calls 13 and 14, and the unrelated 08:09 loan-renewal run's records call 10.
Hello-world's business-bound response exposes three unbound greeting occurrences
(Then, FR and entity meaning); the token-bound response recognizes two (Then and
FR). The historical loan response's encoded insertion syntax remains text, with
native field metadata unavailable. No missing association or metadata is invented.

The full offline command was:

```sh
zig build exact-value-replay -j1 --summary all -- --output zig-out/exact-value-recognition.complete.json --root zig-out --root test/calibration
```

It passed **3/3 build steps**, inventories all supported capture families beneath
both explicit roots, and retains unsupported/missing observations. The
[report](../zig-out/exact-value-recognition.complete.json) is 5,119,612 bytes with
SHA-256 `591a4c8250d3d1e2e563ebdc8c6ea6a430f1703d584b50100b629da2d6c91fa6`.
The 3,743 physical inventory rows include request-only/prepared records and
63 unsupported archive placeholders whose inner call counts are unknown; they
are **not** 3,743 independent model calls. There are 1,126 known exchange IDs,
77 exact-identity/payload duplicate rows and 1,948 unknown identities. Three
thousand unrelated nonregular filesystem entries are counted outside the capture
denominator.

Of 1,000 request rows exposing exact values, 645 have processable output.
164 capture projections produce 454 field measurements (394 after known duplicate
rows are excluded). Current metadata has 70 exact-origin joins, including every
context in the latest F13 run. Physical field observations contain 29 matched
plain runs, 63 unbound witnesses, 28 unavailable insertion-adjacent runs and
18 invalid proposed compositions. Existing typed references (95) and explicit
counterfactual fields (80) have separate denominators. There are 68 missing/invalid
requirement bindings and 320 unavailable native field identities. These counts
include mirrors and do not supply a semantic false-match rate.

The remaining physical dispositions include 1,335 missing responses, one
unavailable response, 690 unsupported legacy provider envelopes, 460 unsupported
historical descriptions and 63 unsupported archives. Among processed rows,
541 have no exact-value context, eight have invalid packets, two have invalid
model JSON, and 479 declare no relevant model-text fields. Missing evidence has
not been scored as success, and no legacy production reader has been restored.

`zig build test-exact-value-replay -j1 --summary all` passed **57/57 tests** across
**5/5 steps**. The independent controls and authentic captured regressions remain
separate unit and integration evidence. Final
`zig build verify -j1 --summary all` passed **163/163 steps and 1,764/1,764 tests**,
including **122/122 integration tests**, architecture/format checks, the existing
native packaging smoke and the helper's clean-directory scan of the three supplied
captures (22 measured fields) without source assets, the Zig toolchain or
credentials. The final full-check log is
`.zig-cache/exact-value-verify-final.log`; `git diff --check` also passed.

**Decision remains open.** The prototype establishes byte-level behavior and
the available evidence, not production adoption. A representation amendment must
resolve how prose creates exact lineage beyond selected requirements and what
punctuation-boundary recognition is allowed to establish. Missing historical
bindings and unsupported envelopes prevent complete retrospective qualification;
no live fidelity or cost improvement is claimed. The
[prototype README](../test/calibration/exact-value-recognition/README.md) records
commands, controls, source pins and limitations.

### 5.5 Review delivery record

FIX04 §6 as recorded on 16 October.

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
`bfec3d7`), and five full-workflow development diagnostics (two loan-renewal, three
hello-world), none of which published a specification or ran rubric evaluation
(header and F9–F12). No live debugger replay was performed. Phase 1's bounded
exchange gate is closed for the observed first request only. Phase 1A's accepted
contract, implementation and offline gate are complete, and its enforcement is
confirmed live. Phase 1A.2 is implemented offline and was exercised once live on
uncommitted code; its exit gate is still open. Phase 1A.3 and Phases 2–6 remain
open. Phase 2 requires Phases 1A.2 and 1A.3, fresh budget-feasibility evidence, the
recorded user decision and a committed baseline build. Source labels, review and the
F9–F12 semantic interpretations remain
model-assisted or reviewer readings of retained outputs. Phase 1A adds the separate
mechanical evidence linked above; no semantic
benefit, reduced brittleness or useful publication is claimed. Historical results
remain immutable.

### 5.6 FIX01 implementation-history entries, 15–16 October 2026

These entries were recorded in FIX01 §2, newest first.

**16 October 2026 — FIX04 Phase 1A.2 live diagnostic and Phase 1A.3 decision:**
Phase 1A.2 (model-facing presentation from the field registry) is committed as
`2e64a31`; its offline evidence is in [the Phase 1A.2 record](#542-phase-1a2-implementation-record).
The separately approved [18:58 hello-world run](../zig-out/e2e-spec/2026-10-16T07-58-59Z-ec56ff4bc24a21c0082210cf6caa8f31/report.json)
ran on that code before it was committed, so it is diagnostic evidence only. The
brief and story were admitted with prose, admission escape was measured zero, and
the run failed at record generation with `RepairNoProgress` after 14 calls and
20,374 tokens: record fields collapsed into insertions and the field-level repair
repeated the value ([FIX04 F12](FIX04.md#f12--high-descriptive-fields-recover-but-record-fields-collapse-to-insertions)).
The user approved Phase 1A.3 decision 4, option (a): composition defects are rejected
at response admission and corrected through the existing bounded protocol
correction, recorded in the
[composition contract](../design/contracts/text-field-composition.md#phase-1a3-amendment--composition-defects-are-corrected-as-a-unit)
and §22.4. Decision 4 routing and attribution preparation are now implemented
offline ([implementation record](#543-phase-1a3-admission-routing-and-attribution-preparation)). The separately
approved attribution sends and resulting presentation correction in
[Phase 1A.3](FIX04.md#phase-1a3--attribute-insertion-presentation-and-repair-collapsed-units-as-units)
remain pending before the Phase 2 baseline freeze.

**16 October 2026 — FIX04 Phase 1A live result and Phase 1A.2 decision:** Phase 1A
(text-field composition admission) is committed as `bfec3d7`; its implementation
and offline evidence are in [the Phase 1A record](#541-phase-1a-implementation-record).
On that clean build the 16:16 one-send probe was `compatible`, and the separately
approved [16:20 hello-world run](../zig-out/e2e-spec/2026-10-16T05-20-15Z-44b2ac5e19cbf8d2ade89b149aed73c8/report.json)
failed with `RepairNoProgress` after 8 calls and 12,896 tokens. Native admission
rejected the brief's insertion-only title as `reference_only` before any review, and
the unit repair returned the same value. Enforcement is confirmed live; generation
did not recover, because schemas, guidance, offered choices and the repair packet
still present the rejected shape ([FIX04 F11](FIX04.md#f11--high-admission-now-stops-the-defect-but-generation-cannot-recover-from-it)).
The user approved Phase 1A.2 decision 1: descriptive fields whose exact copies
cannot satisfy coverage now have a prohibited exact-copy role, recorded in the
[composition contract](../design/contracts/text-field-composition.md#phase-1a2-amendment--exact-copies-only-where-they-can-carry-an-obligation)
and ADR 0020. Implementation of [Phase 1A.2](FIX04.md#phase-1a2--make-model-facing-presentation-consistent-with-admission)
is pending and precedes the Phase 2 baseline freeze.

**16 October 2026 — FIX04 baseline measurement harness:** unchanged arm A now has
independent planning and scoring, a committed-build/budget-feasibility admission
gate, authentic production exchange/candidate capture, experiment-wide physical
send and actual-token accounting, and offline source-backed assessment intake.
The user selected complete first-pass fidelity for qualification sizing.
Original, corrected, failed, unknown-usage and unattempted evidence remain
distinct. Evaluator expectations and qualification sources are excluded from
generation inputs. [FIX04 Phase 2](FIX04.md#phase-2--establish-baseline-quality-and-failure-sensitivity)
retains the budget-decision prerequisite and open live/semantic exit gate;
implementation and offline checks do not establish baseline quality.
Verification: `zig build test-baseline test-rubric-evaluator build-baseline lint
test-architecture test-integration --summary all` passed 23/23 steps and 714/714
tests; `zig build verify --summary all` passed 156/156 steps and 1,625/1,625 tests,
including native clean-directory smoke checks. Offline preparation with the
unresolved example plan correctly emitted an insufficient-feasibility report
with the compiled 100,000-token workflow budget and no freeze or API call.

**16 October 2026 — Phase 2 completeness audit:** the
[item-by-item audit](#544-phase-2-implementation-audit) records additional corrections to
one-shot experiment admission, receipt retention, evaluator rubric isolation,
native useful-completion assessment, upstream original judgments, variability
denominators, finding lineage, cost forecasts and evidence-gated decisions.
The separately approved Hello World diagnostic exhausted the unchanged workflow
budget: 41 calls, 101,134/100,000 tokens, no published specification or rubric
result. This is retained failure evidence; the baseline panel and budget decision
remain open.
Final audit verification passed `zig build test-baseline test-rubric-evaluator
--summary all` (535/535 tests) and `zig build verify --summary all` (156/156 steps,
1,659/1,659 tests). The offline feasibility import accounts all 41 live exchanges
with exact per-slot controls and correctly blocks freezing under the unresolved
budget decision; see the audit for exact commands and retained report links.

**16 October 2026 — native reference review subjects:** source, signal, exact-token
and conflict reviews now resolve the same native subject used by omission
comparison and localization. Initial and correction packets keep the assigned
reference's source meaning, use and conditions; authored fields and collections
retain their own assessments. This removes the broad whole-candidate reference
fallback. It does not authorize new repair targets or reassess accepted findings.
Regression coverage includes unrelated source domains, pending and assembled
candidates, stale/foreign targets and continued refusal of unsafe token repairs.

The separately authorized [07:54 full loan-renewal baseline](../zig-out/e2e-spec/2026-10-15T20-54-21Z-5f6e903390f38938113712b53a359de4/report.json)
stopped before source review: two record-generation groups emitted competing
duplicate records. `UnsafeSpecificationRepair` blocked publication after 13 calls
and 25,508 tokens. Existing per-group association and content-only repair authority
cannot select, merge or delete those competing owners. Collection-level initial
record authoring remains a separate design decision under §17.3 and ADR 0020;
this presentation correction does not enact it.

Offline verification passed `zig build test-specification-generation --summary all`
(324/324 tests), `zig build lint test-architecture test-integration --summary all`
(240/240 tests), and `zig build verify --summary all` (149/149 steps,
1,555/1,555 tests, including clean native packaging smoke).
The authorized post-fix command was
`./scripts/e2e-spec.sh --case test/e2e/wf-002-loan-renewal/workflow.case.json`.
Its [08:09 full run](../zig-out/e2e-spec/2026-10-15T21-09-33Z-3a7ceed77cb237531019300e1005152d/report.json)
failed with `WorkflowTokenBudgetExceeded`: 37 calls consumed 101,002 tokens
against the 100,000-token workflow budget. The stop occurred during the third
entity's business-meaning source review, before native signal/token/conflict
reviews. The shared reference correction therefore remains unverified live.
No candidate repair ran, no specification was published, and publication/rubric
checks were not run. Captured earlier reviews include a rejected literal-only
story, unsupported entity findings and inconsistent omission judgments; this run
does not establish semantic quality or justify weakening a gate or raising a
budget automatically.

**16 October 2026 — observed request compatibility:** the separately authorized
[07:46 probe](../zig-out/provider-compatibility/2026-10-15T20-46-55Z-cb4fdfbfe3b6aff88bc99e68fa980506/report.json)
passed the selected first production request's compatibility checks: HTTP 200,
2,254 accounted tokens, accepted candidate/schema and existing prefix
normalization. Its intentional one-send cancellation produced no specification
or rubric grade. This qualifies that exchange, not workflow quality or completion.

**16 October 2026 — Converse usage metadata correction:** the 07:29 Melbourne
native response returned HTTP 200, but the shared codec rejected the optional
empty `usage.serverToolUsage` object before token accounting or candidate
normalization. The codec now explicitly validates this closed empty metadata
shape; unsupported nested fields and wrong types still reject. Canonical replay
inspection and compatibility reports retain decoder reasons and field paths.
Offline regressions use the exact response to check 2,254-token accounting,
existing approved prefix normalization and selected-schema validation. This
does not change prompts, correction policy, model settings or publication gates.

**16 October 2026 — user-directed test model switch:** current generation,
repair, rubric evaluation and diagnostics select Bedrock
`openai.gpt-oss-20b-1:0` from `ap-southeast-2`. Spec generation, repair and grading
use low reasoning with registered temperature `0.1`. This supersedes the Luna
test selection recorded below; retained offline results remain historical evidence
and no live run is authorized by the switch.

**15 October 2026 — FIX04 evaluation foundation and Converse:** the user-requested
Phase 0 prepares a frozen current-small-model protocol, 24 source-backed features
with 72 variants, six labelled specimens and feature-level accounting with no
publication authority. The associated Bedrock transport change uses shared
Converse codecs, typed reasoning diagnostics and a pre-credential live-test cost
policy permitting only Bedrock Luna and excluding Sonnet/Sol/Haiku. Canonical live
fixtures select `global.openai.gpt-6-luna` with native JSON Schema;
generation topology and semantic acceptance rules are unchanged.
[FIX04 §5.6](FIX04.md#56-phased-rollout-and-exit-gates) and its
[retained Phase 0 report](../test/calibration/semantic-simplicity/phase0-results.md)
record the completed scope/checks: **Phase 0 complete offline**, with full
verification at 145/145 build steps and 1,671/1,671 tests. No live
compatibility, model-quality, brittleness or E2E gate is closed by offline tests.

**15 October 2026 — FIX04 Phase 1 bounded compatibility scenario:** the subsequent
user-authorized **offline implementation is complete and mechanically verified**.
Final full verification passed **155/155 build steps and 1,786/1,786 tests**,
including architecture, offline integration and native clean-directory packaging.
The implementation prepares the first production model request from an
explicit case, reusing configuration, compiled workflow, request authorization,
Converse transport and immutable capture owners. The development command
`zig build provider-compatibility -- --case <explicit-case-path> --live` and its
launcher permit only the registered Bedrock global Luna/Sydney native-schema
binding, with the case's existing output allowance and omitted explicit
temperature/reasoning controls. A transport-owned bound permits at most one
physical inference send; usage survives typed cancellation and no replacement
send, retry, repair, judge or workflow publication is authorized. Retained JSON
and Markdown reports separate request compatibility from workflow completion and
semantic quality. Typed invocation/step outputs and side effects block publication
before child execution, even before the first send. Read-only inspection joins
canonical bytes/identity, the closed trace transport outcome and production usage;
transport-observed request/response SHA-256 values reject substituted readback
without granting engine state/predecessor authority. Unknown actual tokens are
nullable and distinct from the explicitly retained accounted total; HTTP rejection
alone remains inconclusive.
Bodies from interrupted/uncertain delivery remain unvalidated and inconclusive.
Guard/CLI/report tests belong to `test-provider-compatibility`; fresh production
runtime scenarios with fake exchanges belong to `test-integration`. See
[the offline evidence record](../test/calibration/semantic-simplicity/phase1-offline-results.md),
[FIX04 Phase 1](FIX04.md#phase-1--establish-compatible-selected-model-execution)
and the [harness operating contract](../design/harness/e2e.md#test-one-fresh-provider-exchange).
That implementation request authorized offline work/checks, not a live diagnostic
or E2E run. The later separately authorized 16 October compatibility result is
recorded above. No generation assignment or semantic acceptance gate changed.
