# SPEC01 — Open Spec work

The fix record for open work and user decisions not yet recorded in an ADR
([convention](README.md)). Each phase needs the user's approval before its changes, and
every live run needs its own approval. **Decision** marks a question only the user settles;
a recommendation is not a decision. Decisions marked 15 November 2026 took their recommended best
option (user: "update the best options recommendations", then "yes"). Implemented items are in
[Z_SPEC01](Z_SPEC01.md); closed and reverted work, superseded measurements and earlier references
are in git history (`fixes/FIX06.md` before 9 November 2026; earlier items at `39fd9ff` and `0f3e4d2`).

## 1. Gate status and output quality

**Gate (ADR 0034): the user's to declare.** On 9 November 2026 the HEAD set, the first set on a
committed, unmodified build (`a3d083e`, source `5fb59f67…`, 3 runs per case, none retried,
`2026-11-08T22-3*`), published 6 of 6, and `adjudicate-spec` accepted every run (skill
`185b9bc6…`, no critical failure) with no lost or weakened requirement ([Z_SPEC01](Z_SPEC01.md)
Next 6). **Judged 9 November 2026** (user: "three per case is enough for now"): the HEAD set is
enough stability evidence for now. ADR 0034 leaves actioning Plan to the user, so none is
started. **Re-run decided 14 November 2026** (user: "the above recommendations are approved"): the
gate is re-run on the build after E1–E4 land, as one closing set after the output-track changes
(§3) are each kept or reverted, so the evidence comes from the build Plan work would start from
(ADR 0034, derived item 7). The closing set (`2026-11-15T21-47-*`) and the paragraph set (`01-49-*`) ran on
16 November 2026, each 6 of 6 published and passed with no lost or weakened requirement
([Z_SPEC01](Z_SPEC01.md) "Closing set", "Claim wording as one paragraph"). **Q14-check set run 16 November
2026** (`2026-11-16T07-18-*`, build `904ba482…`, `build.source.modified: true`; [Z_SPEC01](Z_SPEC01.md)
"An exact copy in a criterion"): 6 of 6 published, 5 passed; one critical failure, a weakened "may renew"
(records request unchanged). The gate stays the user's to declare.

**Reference** for quality phases (§2 rule 7): Q23's set (`2026-11-17T23-4*` to `23-58-08Z` and
`2026-11-18T05-3*`, 6 runs per case, `anthropic` `claude-haiku-5-5`, build `26982bb`, source `0a61828b…`), the
last kept state ([Z_SPEC01](Z_SPEC01.md) "Q23"), re-scored on `evaluate-e2e` `69c55877…` (21 November 2026, §2
rule 5; the counts of the older revisions are replaced). Accuracy defect counts, content basis, as lost /
weakened / unsupported addition / contradiction:

| Case | Publications | Pass | Defects | Advisory score, mean (range) |
| --- | --- | --- | --- | --- |
| Hello-world | 5 of 6 | 5 of 6 | 0 / 0 / 0 / 0 | 96.4 (92.9–100.0) |
| Loan-renewal | 5 of 6 | 5 of 6 | 0 / 0 / 0 / 0 | 98.6 (96.4–100.0) |

Link-derived `unsupported_addition`, counted apart ([Z_SPEC01](Z_SPEC01.md) T7): 1 in hello-world (1 false link in
29 records) and none in loan-renewal (1 `partial` link in 55). Advisory scores are scored against the case rubrics
(`evaluations/e2e/<run>/evaluation.json`); scorer judgment moves one by about ±3.6, and keep decisions use the
accuracy counts (§2 rule 6). **Ruled** 22 November 2026 (user: "update documenation with recommendation for
decisions 1 and 2"): a Given that states a precondition the source doesn't, however generic ("installed and
available to run", "with a known existing due date"), is a minor `unsupported_addition`, as the revision before
`69c55877…` counted it (3 in the hello-world reference); `evaluate-e2e` SKILL.md states it. Reason: Q26 was decided
on these Givens being defects, and a revision that doesn't count them can't measure Q26's class. The ruling decides a
score in 3 of the 5 publications of Q14's set (hello-world run 1 and both loan-renewal runs) without changing a pass,
and adds a minor `unsupported_addition` to each of the three loan-renewal publications of Q26's set. The table above
stays `69c55877…`'s. The reference for the Q26 follow-up's set, Q26's three sets and the two later ones, is scored on
`2b3fb8de…` ([Z_SPEC01](Z_SPEC01.md) "Q26 follow-up set"): hello-world 99.2% mean over Q26's nine runs, loan-renewal
94.5%, with 13 content-basis unsupported additions in Q26's nine loan-renewal runs, all generic Givens, and no lost,
weakened or contradicting requirement in any run of either case.

**Provider drift** (22 November 2026; [Z_SPEC01](Z_SPEC01.md) "Q26 follow-up set", signals screen): replayed unchanged,
set B's `06-52-17Z` signals request returned the earlier runs' four signals in 3 of 10 trials and three or two in the
rest, and none of the follow-up set's 8 loan-renewal runs returned four, so a new loan-renewal set may not share the
inputs of the reference runs above. **Screened** 23 November 2026 (user: "action the preconditions for stage 5";
[Z_SPEC01](Z_SPEC01.md) "E7 stage 5 precondition"): 8 of 10 trials returned other than the four signals `[1,4]`, `[2]`,
`[3]`, `[5]`, so the drift persists by the test recommended on 23 November. **Decided** 23 November 2026 (user: "update
documents with recommendations"): decide the schema change at the call level, as the earlier screens did (the records call,
captured schema against the changed one, 10 concurrent replays per arm and case, with its own approval), and judge the rule
6 set on the accuracy counts, reporting the signals grouping each run drew. The set ran first, then the call-level screen
([Z_SPEC01](Z_SPEC01.md) "E7 stage 5 screen"), which settled the schema change.

**Retained runs:** `zig-out/e2e-spec/` keeps the newest twelve runs: set B of 22 November 2026 (`2026-11-22T06-36-44Z`
to `06-54-55Z`) and the Q26 follow-up's set (`08-35-52Z` to `08-39-02Z`, [Z_SPEC01](Z_SPEC01.md) "Q26 follow-up set").
A new set removes the oldest runs past twelve (the Q26 sets' directories were removed that way); their evaluations and
measures stay under `evaluations/`. The current build decodes only `spec-e2e-report/v26` (`report_schema` in
`test/harness/e2e/contracts.zig`), and these reports carry v25 (§2 rule 12): the measures tool records them as an earlier
version, unavailable (`measures_cli.zig:171-172`, e2e.md "Retained results"), and their evaluations and measures stand.
The drift screen's `e2e-call` names no report schema (nothing in `test/harness/call` matches `spec-e2e-report`), so it is
likely unaffected (not run).

## 2. Rules for measured phases

AGENTS.md ("Model output, prompts and evidence", "Anti-overfitting rule", "Validation")
governs; these add what the phases need.

1. **One change set per measured build.** Changes that rule 10 proves leave every
   development-case request byte-identical may share the build. A change set that isn't kept
   is reverted in full, never patched on top. Recorded exceptions: D16.2 amended the D12.1 +
   Q16 change set after its set failed the publication guard (user, 2 November 2026:
   "approved"); §3 Next items 6 and 8, both request changes, were committed together and
   measured as one set (user, 9 November 2026: "apply recommendations").
2. **Owner first, offline first:** `/preflight`; regression and negative tests at the owning
   boundary, compared with owners rather than copied English; `zig build verify`;
   `contract-reviewer`. Cover unrelated members of the class (both development cases plus an
   offline unrelated-domain fixture).
3. **Build.** Measurement uses a committed, unmodified build (`build.source.modified` false),
   kept with no standing deviation (decided 1 November 2026). A set's runs share one
   `build.source.source_sha256`. `fixes/`, `.claude/` and `evaluations/` aren't
   build-provenance roots (`build/provenance.zig:21`). Recorded exception: ADR 0047 and D12.3
   were kept on adjudicated runs from uncommitted trees (user, 7 November 2026: "approved",
   after being told they were direction only); the HEAD set (§1) is ADR 0047's committed-build
   set (ADR 0047:113).
4. **Measurement set:** three runs of each development case (decided 2 November 2026), each
   approved, extended under rule 6 to at most eight per case. Every attempt counts. Nothing is
   tuned on the reserved qualification features.
   - **Screening** (decided 3 November 2026, H6.1): before a set, each call kind whose request
     the change alters (the §2.10 projection names them) is screened with paired replays of a
     retained request from each case, `e2e-call --repeats` as captured and with `--edit`
     (design/harness/e2e.md:66-91), about ten per arm, on the captured run's model and
     reasoning effort. A screen measures only the structural counts of [Z_SPEC01](Z_SPEC01.md)
     T6, so it can't measure a prose-only change; it decides nothing, and each replay batch
     needs approval. Its as-captured arm is a call-level control allowed for screens only: a
     set adds no control run on the comparison point's build (decided 1 November 2026).
5. **Evaluation and measures:** `zig build e2e-measures` and `/evaluate-e2e` for every run.
   - Defect classes are those of the evaluate-e2e skill (§2), counted over native publications
     beside the publication rate per case.
   - Each repair is graded helpful, neutral, harmful or no progress.
   - Brittleness counts: T5.
   - **One evaluator version per comparison** (decided 3 November 2026, H6.3): a set and its
     reference are scored on one evaluate-e2e revision. When the skill has changed, the
     reference is re-scored first from its numbered copies under `evaluations/e2e/` (rubric
     scores and defect classes; the link check and defect origins need the run directory), with
     link-derived `unsupported_addition` counted apart ([Z_SPEC01](Z_SPEC01.md) T7).
6. **Keep or revert** (the default recommendation; the user decides).
   - **Before the set,** record:
     - targets: accuracy defect classes (lost source requirement, weakened obligation,
       unsupported addition, contradiction), as counts of `content`-basis defects per
       publication with unit, opportunity and direction; cost is reported, never a target. A
       hygiene phase's own class may be its target;
     - guards: lost source requirement and the publication rate per case;
     - watch items, each with the effect size that would make it block: each accuracy class
       the change doesn't target, a critical criterion below its minimum, harmful repair;
     - the run maximum.
   - **Improvement:** the pooled target count improves under a one-sided conditional binomial
     test at p ≤ 0.10, and doesn't worsen in either case that shows the class.
   - **Guards** (amended 3 November 2026, H6.2): any rise in lost source requirement per
     publication blocks a keep; the publication rate per case doesn't fall; and no class absent
     from the reference appears with an `established` trace to the changed owner. A watch item
     blocks only when it crosses the effect size recorded before the set. Hygiene phases (such as
     Q4's retry and Q7 D7.5) are kept on guards alone plus their **Keep if** measures.
   - **Sampling:** look after three runs per case, then extend by two or three with approval;
     never sample until a preferred answer emerges.
   - **Evidence floor:** fewer than about ten events across both states, or undecided at the
     maximum, is "not enough evidence". A target absent from both states of a case is "benefit
     not demonstrated".
   - The aggregate percentage decides no keep (user, 3 November 2026: keep decisions use the
     accuracy defect counts); a run's adjudication pass or fail decides only its own
     acceptance. Say "kept", never "accepted".
7. **Reference** (amended 3 November 2026, H6.4): for a measure one call kind produces, every
   publication whose request for that call is byte-identical to the comparison point's, kept or
   not; for whole-run measures, the last kept measured state (§1).
8. **Reporting:** AGENTS.md's five evidence statements, separately.
9. **Model limitations:** AGENTS.md owns the rule and its exceptions; §9 adds no caps that
   discard output.
10. **Engine-track proof** (§5): offline, on the scripted integration matrix.
    - Compare against a request projection retaken on the commit before the item lands
      (design/harness/e2e.md "Request projection").
    - The behaviour reproduces the freeze its ADR defines, or the ADR 0030 step traces and
      summaries, with expected differences stated before landing.
    - Every accounted request's projection is byte-identical.
    - One live run of each case; the item lands only between sets.
11. **Evaluation protocol:** the [protocol](../test/calibration/semantic-simplicity/README.md)
    owns its 24-feature panel; SPEC01 sets use the two development cases and aren't protocol
    experiments.
12. **Report versions:** `adjudicate-spec` decodes `report.json` strictly, so adding, removing
    or renaming a closed member needs a report version. Runs before the closing set stay
    unadjudicated unless the user adjudicates them (decided 1 November 2026; no members-only
    decoder). Adjudicate a set before the next closed-member change lands, and advance the
    version with it. **Breach found 9 November 2026:** the entity lever removed the
    `business_meaning` entity field from the report's `admission_audit` subjects (ADR 0038
    Decision 6) without a new version, so the six `2026-11-08T00-3*` to `00-4*` reports no
    longer decode and `adjudicate-spec` rejects any record for them (`InvalidAdjudication`,
    naming no member). Their `1d66d882…` adjudications stand; their `3c74781e…` re-scores
    ([Z_SPEC01](Z_SPEC01.md) T7) stay unapplied. The twelve `05-5*` and `09-2*` runs are adjudicated under
    `3c74781e…`.

**Boundary gates** for contract changes (from FIX01 §5, git `b2f10a3`). Offline tests prove
native mechanics only; negatives that turn on meaning are judged in live sets against
human-reviewed labels, never by native code or a new judge.

| Boundary | Positive evidence | Negative evidence | Applies to |
| --- | --- | --- | --- |
| Summary representation | Combined, split, overlapping expressions; complete membership; stable identities | Missing or foreign IDs, altered categories, false support, changed exact values | Any summary representation change |
| Normalization | Idempotence; same-evidence duplicates collapse; raw and provenance kept | Different occurrences, distinct obligations, paraphrases, destructive truncation | Any normalization change |
| Native carry-forward | Empty, non-final, final, one/many-child routing; complete lineage | Stale or forged child content, changed evidence, fabricated origin | Any summary change |
| Repair | Exact target and dependencies, protected siblings, progress, full final validation | Stale authorization, widened scope, reset allowance, invalid survivor | Q14 b3, E4 |
| Exact-value representation | Occurrences from exact bytes in bound fields survive repair and readback | False matches, ambiguous occurrences, unbound fields, changed obligations | Any exact-value change |
| Whole workflow | Real publication of the expected outcome, complete required review, H1 adjudication | Early stop reported honestly; no golden outputs or advisory analysis as acceptance | Every set |

## 3. Priorities

Ranked by expected reduction of published-output defects (AGENTS.md). Tracks: **Q** quality
phases (model input or published output change, each measured), **E** engine (no model-input
change except E7), **T** tests, **C** code-review findings (§10; unscheduled unless an item says
otherwise). "Gap" means between measurement sets. Each screen
batch and live set needs its own approval (AGENTS.md).

**Output track:** Q26's follow-up (§4 Q26, decided 22 November 2026) was built, screened and run to eight per case,
and its edge-case entry reverted ([Z_SPEC01](Z_SPEC01.md) "Q26 follow-up set"); nothing awaits a set.

**Engine track, in gaps:** E7 stages 6–8 (decided 22 and 23 November 2026; stage 2 folded into stage 6 and stage 3
into stage 4 on 23 November, §5 E7), in order; stages 4, 5 and 5b are built, and stage 5's set, which changes
development-case request bytes, ran on 23 November 2026 as a rule 6 hygiene set (its keep is the user's call, under the
decisions of §1 and E7). E0 is on
hold.
**Byte-neutral, sharing the next set's build** (§2 rule 1): C22's remainder (§10.3; built 22 November 2026, its request
projection equal to Q26's, [Z_SPEC01](Z_SPEC01.md) "C22 remainder"). **Tests:** T4.
**Adjudication:** the evaluate-e2e skill for every set.

**Open problems without an item.**

- **Repair requests without step guidance:** seven repair sites take their task only from the
  three-line `repair.prompt.md` (`spec.workflow.yaml` steps `text-repair` in `extract-references`,
  the extraction repair in `validate-extraction`, `request` in `repair-reconciliation-candidate`,
  `repair` in `generate-unit`, `repair` in `generate-scenarios`, `request` in `repair-source-extraction`
  and `request` in `repair-source-candidate`), and the two reconciliation repairs among them
  (`repair-reconciliation-candidate` and `repair-source-candidate`) bind no context.
  Binding definitions (Q2) wasn't kept; counted as a brittleness measure (T5).
- **A behaviour claim extraction labels non-business:** the composed story quotes only `business`
  claims, so such a claim is in no story, and coverage passes it on context signals alone
  (`specification_coverage.zig:64-75`). One run shows the omission (`2026-11-22T06-54-55Z`, whose story drops
  "A loan may be renewed only once." because extraction labelled it `design`), but its FR and criterion state the limit, so
  no content-basis defect was filed. Reopen as an item, with its own measured
  class, when a scored run traces a content-basis defect to it, or to a behaviour claim that no
  requirement statement names. Q21, which proposed obligation-bearing claims for the second case, was
  closed 21 November 2026 (user: "update the documentation with the above recommendations"): since ADR
  0047 the story quotes every business claim and selects every group holding one (ADR 0047 Decision 1;
  `specification_story.zig`, `resolveGroups` in `specification_source_binding.zig`), so coverage maps any
  unnamed business claim through `primary_user_story` whatever the group count, the claim is printed in
  `spec.md`, and the evaluator rules a story-quoted requirement preserved. 61 evaluations from 17 to 21
  November 2026 show one `lost_source_requirement` (`2026-11-18T06-53-25Z-966d…`, an upstream `superseded`
  disposition that no Q21 option reaches). The limit stays recorded in ADR 0038:430-437.

## 4. Quality phases (Q)

### Q14. Scenarios bound to their claims

**Kept 15 November 2026** (record: [Z_SPEC01](Z_SPEC01.md) Q14 b4). Open parts only:

- **Restated edge cases** from the records call recur (loan-renewal EC-001 and EC-002 repeat AC-005) and
  cost `organization` only. The 13 November edge-case amendment (ADR 0038 Decision 7) is built and **kept**
  (user, 21 November 2026), its benefit not demonstrated: no edge case was written in the six runs of the 20
  November set before it or in the six of Q14's re-measure set (21 November 2026, build `c22fa1f`, modified), so a
  later set can show a benefit only if the records call writes edge cases (§2 rule 6; evidence floor about ten).
  **Ruled** 21 November 2026 (user: "update the documentation with rhe recommendations"): the engine-printed
  first part of an edge case's `GIVEN` line, the copied criterion Given, isn't `restatement`; `evaluate-e2e`
  SKILL.md states it. For a criterion with no Given the line is the edge case's own given alone (Q26).
- **Late block, shown once** (`2026-11-15T07-50-08Z-f971…`, a Q17 run): the records call put claim 4
  ("A loan may be renewed only once.") only in an edge case, so no behaviour statement names it, it gets
  no slot and no criterion, and linking stops with `edge_case_without_criterion` (ADR 0038 Decisions 3
  and 7: `scenario_slots.zig:70`, `scenario_link.zig:25-53`). It covers any behaviour claim that only an
  edge case names, not only a scope-only claim. 1 of 5 loan-renewal records calls that carried principles
  and 0 of 16 earlier (no rate).

### Q26. A Given only where the source states one

**Kept 22 November 2026** (user: "keep Q26, benefit not demonstrated"; record: [Z_SPEC01](Z_SPEC01.md) Q26).
Open parts only:

- **Retained repeats:** whether the field rule's "Write nonblank prose" (`text_field_policy.zig:110`), read beside the
  criterion's `given` entry, causes the Givens that repeat their When or fill a placeholder is unsettled (evaluator:
  `prompt_conflict`, `likely`, with `model_noncompliance` the other reading; 3 target events in 24 criteria in the first
  set, below the evidence floor). The rule is unchanged: it states the form of a Given that is written, and its
  per-field policy (`ac_given`, `edge_given`) is already keyed apart. A prompt or contract change is decided on both
  development cases with repeated runs (AGENTS.md). A second set on the same request bytes
  (22 November 2026, build source `7880686f…`, 3 runs per case, all six published and passed, 98.81% for each case)
  shows both sides: hello-world run 1 filled all 3 Givens with "No starting situation is stated in the sources."
  (one minor `placeholder`, the same `prompt_conflict` reading, 96.43%) while runs 2 and 3 omitted every Given;
  loan-renewal kept a Given on 15 of 15 criteria, 1 repeating its When and 5 generic preconditions (counted apart).
  A third set (22 November 2026, build source `4f3793a0…`, the same request bytes; all six published and passed,
  hello-world 100%, loan-renewal 97.62%): hello-world omitted the Given on 6 of 9 criteria with no filler and gave the
  other 3 a generic precondition; loan-renewal omitted one Given (the first in 45 loan-renewal criteria), repeated a
  When once and gave 5 of 15 a generic precondition, dropped none its source states, and repaired none (its two repairs
  replaced a Then). Across those three sets, 5 events (4 Givens repeating their When, 1 placeholder Given) in 72
  criteria. Two more sets (22 November 2026, builds `b8f50364…` and `4415163b…`, neither projected itself;
  [Z_SPEC01](Z_SPEC01.md) "Two sets on the batch of 22 November 2026"): 2 Givens repeating their When and no
  placeholder in 48 criteria (hello-world omitted every Given, 18 of 18; loan-renewal kept one on 30 of 30). Across the
  five sets, 7 events (6 Givens repeating their When, 1 placeholder Given) in 120 criteria: still below the floor.
- **Edge case live:** no run has written an edge case, so the edge case's `GIVEN` line for a Given-less criterion is
  unexercised live (Q14's edge-case bullet); the scripted scenario drives it offline.
- **Links prompt:** `links.prompt.md:2` says "its given and when cover that situation", and a criterion may have no Given.
  A reword was built with the follow-up and reverted with it, unmeasured: no development run has a link request.
- **Generic Givens** ("…with an existing due date"; 3, 5 and 5 of 15 loan-renewal criteria in Q26's three sets, 5 and 6
  of 15 in the two later ones) are a minor `unsupported_addition` under §1's ruling (22 November 2026). The removed
  presupposition sentence did not remove them, and no open change targets them; later sets count them.

**Follow-up built, then reverted** 22 November 2026 (decided the same day; user: "update documenation with recommendation
for decisions 3 4, 5, 6"; record: [Z_SPEC01](Z_SPEC01.md) "Q26 follow-up" and "Q26 follow-up set"): the criterion's and the
edge case's `given` guidance were keyed apart (`packet-guidance/v8`), `links.prompt.md` was reworded for a criterion
without a Given, and a scripted scenario drives a Given-less criterion and a linked edge case to publication. It aimed
to remove a conflict in the request that the evaluator traced (`prompt_conflict`, `likely`), judged on guards (lost
source requirement, the publication rate per case) and a **Keep if** (§2 rule 6, as Q4: no placeholder Given, no
criterion dropping a Given its source states), with weakened obligation, `unsupported_addition` in a Given, a Given
repeating its When and Q14's restated edge cases as watch items, against reference set B and Q26's sets, scored on
`evaluate-e2e` `2b3fb8de…`. The keyed-apart guidance and the links reword are reverted (below); the scenario (a test,
no request byte) and C22's remainder (separate) stay.
**Screened** 22 November 2026 (records call, 10 trials per arm, [Z_SPEC01](Z_SPEC01.md)): every trial valid, no edge case
written; hello-world named one of its three claims in 2 of 10 edited trials and in none of 10 as captured, within chance
at that size and the guard's to watch; loan-renewal equal. The link request has no development call to screen.
**Set run** 22 November 2026 (`2026-11-22T08-35-52Z` to `09-08-22Z`, build source `62d848af…` for all 16, eight runs per
case, the rule 6 maximum, all published and adjudicated as passed; [Z_SPEC01](Z_SPEC01.md) "Q26 follow-up set"):
hello-world mean 95.54% (reference, 15 runs on this evaluator, 99.29%), loan-renewal 90.63% (94.05%). **Guards:** no
lost source requirement under the evaluator's rulings and 16 of 16 published. **Watch fired, two ways.** (1) Hello-world:
the records call named only claim 2 of the three requirement claims in 2 of 8 runs (`09-04-25Z`, `09-06-47Z`, scored
89.29% and 85.71%; the requirements survive as story quotes, which coverage accepts, ADR 0047), in 2 of 10 edited-arm
screen trials against 0 of 10 as captured, and in none of the 15 earlier runs on this evaluator (once earlier, a
21 November run on a build before Q26's): 4 of 18 with this change against 0 of 25 without, one-sided p about 0.025, the
live part confounded by the provider drift. (2) Loan-renewal: a weakened obligation ("can renew" for "must be able to" in
FR-001) in 4 of 8 runs, none in 15 earlier, and every one in a run whose signals call put claim 1 in the three-claim group
`[1,4,5]` (4 of 6 such runs, 0 of 2 with `[1,4]`), a grouping the drift introduced (a screen of the same signals request
gave 4, 3 and 2 groups). Unsupported additions: 18 in the 8 loan-renewal runs, 16 of them generic Givens (16 of 40
criteria; 24 of 75 before) and 2 "followed by" in a user-visible outcome. A placeholder
Given in 1 of 8 hello-world runs, as in Q26's second set (1 of 3). No edge case was written. **Concurrent screen**
(22 November 2026, the records call of each case as captured and with the omission sentence put back, 20 trials per arm,
same moment, same model; [Z_SPEC01](Z_SPEC01.md) "Q26 follow-up set"): hello-world named only claim 2 in 5 of 20 as
captured and in none of 20 with the sentence (one-sided p about 0.024); loan-renewal's `[1,4,5]` call wrote "can renew"
in 16 of 20 as captured and in 1 of 16 completed with the sentence, which also had 4 protocol-invalid answers
(`string_length`, 0 as captured) that a correction send handles. **Reverted** 22 November 2026 (user: "action
recommendation"): the edge case's `given` shares the criterion's entry again (`packet-guidance/v7`, the omission
sentence in the records request), and `links.prompt.md:2` is as before; ADR 0016 and ADR 0038 say so. The tree's
request bytes equal Q26's (`evaluations/request-projection/q26-reverted-after` against `q26-after`: 1833 files
identical, the scripted scenario's calls added). **Next:** a set on the reverted build is the user's call.

## 5. Engine track (E)

Each item: `/preflight`, offline tests, the §2.10 proof, `zig build verify`, one live run
per case (DE2–DE4, in [Z_SPEC01](Z_SPEC01.md), asked whether offline evidence replaces it),
landing between sets and under §2.12.

### E0. Failed and blocked runs publish validated content (B10, ADR 0041)

On hold since 30 October 2026 (ADR 0041:3-4). Nothing under `src/` names `failure-output`,
`spec_incomplete` or `run.incomplete_published`. To resume: implement ADR 0041 Decisions 1–8,
taking the next `specification-state` version (v30, since E7 stage 4 took v29); align the measures
(`test/harness/e2e/measures.zig:207`, test `:739-742`; e2e.md:682-683), design.md:208,
24-workflow-state.md:78-83, F0100:1145 and `test/harness/e2e/contracts.zig:209-212` with
Decision 7.1 (an `invalid` run stays `invalid` and may publish), and F0100:1139 with Decision
7.8 (the title precedes the status line); add a test that a pre-E0 v16 report still decodes;
flip every scenario asserting no publication after an eligible failure (the `spec.md`
`FileNotFound` assertions after a failed or blocked run in `test/integration/workflow_tests.zig`;
`test/harness/integration/tests.zig:1759`, a budget stop), including ADR 0047's
`no_story_requirements` and `story_not_admissible` blocks, which no scenario covers; register
`run.incomplete_published` through `adrRequired` (`src/domain/log_event_registry.zig:99-105`,
test `:162-168`). If ADR 0041 is withdrawn, v16's `incomplete_publication` (e2e.md:353-356)
and the measures' `incomplete` value become dead code needing a report version.
Budget-stopped runs publish nothing while it is on hold (none since D13.1).

### E7. Clarification answer recovery (R2, ADR 0025)

**Stages 1, 4 and 5 built 22 and 23 November 2026** ([Z_SPEC01](Z_SPEC01.md)): an invalid closed form ends the run `blocked`
before any model call, with one typed reason per form; a valid closed form or `cancel` is authenticated, recorded as a
response with its evidence, and published with the run; a `defer` is ignored; a clarification's subject is the
engine-derived source selector, not a per-run ordinal or a model-picked record family (ADR 0025, the clarification
subject; `clarification-state/v4`). The model still names the record family, which the engine validates and never reads for
identity (ADR 0025 Decision 6), so the request projection equals the frozen baseline; the live set and the call-level screen
are in [Z_SPEC01](Z_SPEC01.md) ("E7 stage 5", "Live set", "E7 stage 5 screen"). Limits it
accepts (ADR 0025, "Limits this accepts"): a subject is stable only while the claims, citations and signal grouping are,
and ten replays of one signals request returned three groupings, so a records or signal need can name another subject on a
rerun of the same sources. The second limit, two needs of one stage whose cited lines coincide being one subject that the
refresh rejects with `InvalidClarificationInput` (the run ending `failed`, not `blocked`, on every rerun of those sources),
is closed by stage 5b below. No run has shown either. **Decided** 23 November 2026 (user: "update documents with
recommendations"): for the collision, the authority builder consolidates needs of one subject (§12.7 allows it for one
engine-built subject), built as stage 5b below, not a new blocked reason; for the drift, keep the selector until stage 7's
clarification-expected case shows whether an answered subject matches on a rerun, since an engine-owned selector cannot name
a multi-claim signal. What is left: provenance rejects nonempty
response-ID sets (`specification_provenance.zig:93`, `specification_support_evidence.zig:171`); resolved needs are empty
(`src/actions/clarification/build_resolved_clarification_needs.zig`); passive literal origins are source-only
(`passive_literals.zig:16`), so answer text can't get ADR 0025's response-owned origin; generation doesn't consume answers
(it binds empty response-ID sets, `specification_source_binding.zig:136`, `:196`), and a re-raised need for an accepted
subject ends `blocked` with `ProtectedClarification` (`clarification_refresh.zig:107-108`), so stages 4, 5 and 5b show no
benefit before stage 6 (likely, not run). Complete the
[§17.4 lifecycle](../design/contracts/17-specify.md#174-specification-clarification-behavior) under ADR 0025. §10 C8 adds
record-lifecycle gaps and C49 the clarification subject.

Stage 5b is built (23 November 2026; offline, no model request changes): the authority builder
(`src/domain/required_authority_clarifications.zig`, `consolidate`) makes the gaps of one stage and one subject one need that
asks each distinct question, gives each distinct reason, binds the union of the authorities and cites the union of the
evidence. ADR 0025's second limit, 14-orchestration.md:341-345, 13-05 and §12.7's consolidation line carry it. Its results are
in [Z_SPEC01](Z_SPEC01.md) "E7 stage 5b".

Remaining stages, each landable alone (offline unless stated); stage 2, response-ID admission from a resolved set, is
folded into stage 6: 6 generation consumes answers, with the response-ID admission and the answer-derived literals (request
bytes change only for runs that have responses); 7 the harness two-leg flow; 8 live runs.

**Decided** 22 and 23 November 2026 (user: "update the documentation with the recommendations", "action recommendations");
the stage 4 and 5 decisions are built and recorded in Z_SPEC01, and the ones below are unbuilt. Each design amendment below
lands with its stage's code, in ADR 0025 and the contracts it names:

- **Resolved responses** (stage 6, folded from stage 2; decided 23 November 2026, user: "action recommendations", then
  "actions recommendations" to drop stage 2). A record may cite a response ID only if it is in the resolved set: the
  `response_id` of each `resolved_by_user` record in the validated clarification state, so `cancelled_by_user` records
  and `defer_reason` responses grant none (`clarification_inputs.zig:158-167`, `:179`). One closed typed set of
  `spec.ResponseId`, the raw `u64` converted in the one builder. ADR 0025:74 says "current resolved response IDs" without
  defining them; the definition lands in ADR 0025 with the code. Until then every current rejection stays
  (`specification_provenance.zig:93`, `specification_support_evidence.zig:171`; pinned by
  `specification_generation_test.zig:2819` and `:4683`). It was folded because the set is empty until stage 4 and its only
  consumer is stage 6's binder, which fixes the carrier: the provenance `Context` is built in one place (`readContext`,
  `specification_workflow.zig:248`) but read at 25 call sites in 8 workflow files, and a step's data view holds only its
  declared inputs (`pipeline_data.zig:68`), so a new `Context` input is a key in each of at least 18 action contracts.
- **Answer-derived literals** (stage 6, moved from stage 4; decided 23 November 2026, user: "action recommendations").
  ADR 0025:65-71 scans path-shaped answer text at acceptance, but nothing consumes answer-derived literals until
  generation uses answers, and no clarification code reads passive literals. Re-derived each run from the published
  response, the sole durable owner of the submitted bytes (ADR 0025:94-96, §23.2). Four points stay open until stage 6
  has its consumer: whether the occurrences are persisted (a passive occurrence's `Origin` is in the reference snapshot,
  `reference_snapshot.zig:16-17`, validated at `specification_state.zig:131`, so persisting them changes the state
  shape), how an origin resolves to trusted bytes, the order of their IDs, and who owns the scan. Stage 6 also amends
  07-domain-representations.md:44-45 (the closed minting list) and F0100:404-406 (answers out of scope).
- **Proof regime and defect class.** Rule 10 for stage 6 (development-case runs have no responses, so their requests stay
  byte-identical; stage 4's projection is identical, Z_SPEC01) and a rule 6 set for stage 5. The measure is the
  clarification-expected case's complete-publication rate, zero without E7; guards: the chosen bullet kept
  (`lost_source_requirement`), the other absent (`contradiction`), and no invented resolution (`unsupported_addition`).
  **Decided** 23 November 2026 (user: "update documents with recommendations"): that rate needs stage 7's case, and the
  development cases raise no clarification, so stage 5's set has no defect class to target. It is judged as a rule 6 hygiene
  set, on its guards and keep-if measures (§2 rule 6), with no benefit claimed before stage 6.
  Stage 7's `answers` member is also a closed case member, so it takes the case version after stage 4's (`spec-e2e-case/v4`).
- **Clarification-expected case** (stage 7). A loan-renewal derivative with exactly one pair of contradictory bullets, so
  run 1 should raise one form; neither a reserved qualification feature nor a tuning target. No form, or more than one,
  is reported as an unmet criterion (a model limitation), with no retry or rewording.
- **Authoring answers between runs** (stage 7). An `answers` member in the case version after stage 4's holding one bounded text, since every Spec
  clarification takes one (`build_specification_clarification_need.zig:33`, `required_authority_clarifications.zig:159`).
  One launch runs run 1 and, only when it ends `needs_user` with exactly one open form, writes the text into the answer
  region, sets `requestedStatus: closed` and runs run 2; anything else is reported. No answer is matched to a form by its
  wording. The answer is the user's input, which ADR 0025 makes authority, not a project standard, so the principle-file
  rule (AGENTS.md "Testing expectations") is untouched.
- **Adjudication basis** (stage 7; the evaluate-e2e skill states it). Run 1 publishes the incomplete specification and
  its form (17-specify.md:483-486) and is adjudicated as a correct pause: one form naming the contradiction, and an
  incomplete specification that settles neither bullet. Run 2 is scored on the case rubric with the declared answer
  counted as source: the chosen bullet kept, the other dropped, the response ID cited.

**Not decided here:** the gate re-run after E7 is the user's (ADR 0034:91-95, which recommends re-running after a
structural change lands). Of the E7 stages, only stage 5's set changes development-case requests.

## 6. Test track (T)

### T4. Architecture rules and replay (A5)

`architecture_test.zig` still pins many named files by substring. Built: every `expectAbsent` reads code only
(comments are masked by the tokenizer; text that isn't Zig is judged as is), imports are read from tokens, the layer
rules for orchestrators, runners and `domain/` and `ports/` are import rules, the logging pins (ADR 0032:331-343,
ADR 0026) are contract-shape rules (walks over non-test `src`, an allowlist of the surviving `*_child_bindings.zig`,
the routine-caller table), and every test file must be reachable from a build root. Open: the remaining per-file pins
that stand for an ADR rule (ADR 0030:482-486, 0031:371-387, 0033:366-369, 0011:187-188) become contract-shape rules one
at a time, each keeping its rejected fixture, since none may be loosened and a file-name pin has no graph equivalent
without a per-file allowlist. No planned change removes the files they pin. Prefer replaying retained captures over
extending `spec_generation_responses.zig`.

### T5. Brittleness counts

Definitions and decisions: [Z_SPEC01](Z_SPEC01.md). The `code-heuristics` report names
them by `report.json` member: T5.1 `tests_copying_model_text`, T5.2 `schema_name_branches`,
T5.3 `repeated_instructions`, T5.5 `model_or_case_branches`, T5.6 `model_text_outside_owner`;
T5.4 isn't in it. Each change set that a phase reports on
retakes them on its committed build: `zig build code-heuristics -- --freeze <dir>` with the
freeze §2.10 takes on that build, and T5.4 by hand from `spec.workflow.yaml` (a `slot: repair`
step whose prompt no non-repair step binds). Last taken 22 November 2026 on the tree after the Q26 follow-up's edge-case
entry was reverted (modified; freeze `evaluations/request-projection/q26-reverted-after`): T5.1 11, T5.2 0 (tests 69),
T5.3 8 at 17 sites, T5.4 7, T5.5 0 and T5.6 15 in 4 files, equal to the counts on the build of Q26's set (`ea69a53`,
modified; freeze `evaluations/request-projection/q26-after`). While the keyed-apart entry stood (freeze
`q26-followup-after`) T5.3 was 9 at 19, the starting-situation sentence held by two entries. T5.1 gained one
single-word absence literal (`given`,
`model_candidate_json_test.zig:504`) in Q26's; the 21 November engine batch moved none of them (freeze
`evaluations/request-projection/q14-remeasure`, byte-identical to `coupling-final`: 10, 0, 8 at 17, 7, 0 and
15 in 4 files, equal to 19 November's). Those counts, beside the
ones taken 14 November 2026 after E5 (freeze `evaluations/request-projection/e5-final`) and 2 November 2026
on the `b38628c` tree (freeze `evaluations/request-projection/b38628c`, 130 scenarios, 1,714 calls), are
in [Z_SPEC01](Z_SPEC01.md) T5. No retake lies between 14 and 19 November, so each difference there is the
net of every change between the two dates, not one change's share. **Due:** with the next change set that a
phase reports on. T5.4's seven sites are the ones under "Repair requests without step guidance"; `repair` in
`generate-scenarios` (`spec.workflow.yaml:745`) is the seventh, and when it joined isn't recorded.

## 8. Backlog

§7 (human decisions) is removed; §8–§10 keep their numbers so citations elsewhere still resolve.

### Standing decisions of closed items

Closed 22 November 2026 with nothing left to build (user: "update documenation with recommendation for decisions 3
4, 5, 6"). These decisions still bind:

- **Q2b:** the statement, signal and conflict coverage inserts and the token classifications stay out of scope
  unless harm appears.
- **Q8 D8.1** (3 November 2026): ADR 0036 Decision 3 and ADR 0038 Decision 4 (the list-item split) stay as they are.
- **C4** (20 November 2026): the feature log's `model.completed` gains no cause field (the E2E report's
  `last_provider_rejection` and the CLI carry it), and result-schema and composition rejections get no cause per
  profile section (F0005 §9).
- **C15:** the clean path's validator re-runs, the codec's second parse and the registry's binding re-check stay. Each
  costs time only, and removing one needs an ADR 0022 amendment, value-decode parity or a sealed `ValidatedGraphs`
  first.
- **C19 and C25:** no import-acyclicity rule for `domain/`, which would be new authority; C19's shrink-only list and
  C25's rank pin stay.
- **C20** (21 November 2026): `DataKey` stays one closed enum; a key with no producer, consumer or schema is deleted
  when found.
- **C31** (21 November 2026): the engine-config reader gains no re-stat, identity or path re-binding (F0008:75
  requires them of the provider reader only).
- **C38** (20 November 2026): `/verify` judges a pass by its exit status and the `--summary line` count; no
  injectable emergency sink.
- **C47** (20 November 2026): the per-scenario step trace, the calibration reports and `source_loss_calibration.zig`'s
  live-trial slot stay.

### Retired SPEC01 IDs cited elsewhere

"SPEC01 <ID>" citations of items now in [Z_SPEC01](Z_SPEC01.md) resolve there. Items removed on
20 November 2026 as not affecting the Spec workflow's completion, tech debt or simplicity (Q4, Q7, Q17,
E1, E2, E5, E15, T2, H1–H5, R1, R6, C9, C11–C14, C16, C17, C48 and the wider-scope list) are in git
history. Items closed on 22 November 2026 with nothing left to build (Q2b, Q8, Q13, T3, C4, C15, C19–C21, C25, C28,
C30, C31, C36–C39 and C47) and the emptied §8 "Design–code conflicts" list are in git history and, where built, in
Z_SPEC01; their standing decisions are above.

## 9. Guardrails

The user's standing constraints beyond AGENTS.md:

- No model change or comparison (the user's call).
- The workflow never modifies principle files (1 November 2026; design.md §3.3 invariant 33).
- No caps that discard output, and no larger token budget: a budget failure is fixed at its
  cause, such as review cost or runaways (30 October 2026). No local token ceilings, no
  truncated required evidence, no claim that a larger budget fixes reliability.
- These single-run prompt sentences stay until a defect is traced to one (D5.1, 3 November
  2026; the former Q5, git `0f3e4d2`):
  - `extraction.context.json` `claims`: "Separate independent behavior, implementation and
    verification facts."; the second sentence of `business`, `technical` and `validation`;
  - `support.prompt.md:8-9`: ", including compatible requirements labelled conflicting" and
    "Empty claims or conflict labels do not establish a source gap."; `:22`: "A defective
    candidate is not a source gap.";
  - `records.prompt.md:7-8`: "Do not relabel positive requirements as assumptions or
    non-goals";
  - `packet-guidance.json`: "Displayed values alone do not establish entities, and an explicit
    declaration of absence is unnecessary." (`entities`).
- Never batch or group source-review subjects (30 October 2026); this binds the remaining
  pre-generation source review.
- Measures and replays use the owning steps (`zig build e2e-measures`, `e2e-call`), never
  one-off scripts, loops or new tracking files (29 October 2026).
- Don't narrow the entity-name exception without a decision (B6; `text_field_policy.zig:57`,
  `:65-70`; the composed story shares its incidental role since ADR 0047).
- Runaways stay a reported measure (ADR 0039).

## 10. Code review of the Spec workflow (C)

Read-only review completed on 11 November 2026 (user: "review the current spec workflow source
code, do complete end 2 end analysis, do not guess").

- **Scope:** all production files under `src/` as they stood on 11 November 2026, read in seven
  areas, and `spec.workflow.yaml` with its 24 resources. Tests and the harness were measured, not
  read in full. `src/debugger/` (web assets) wasn't reviewed. Re-checked against the tree on 14
  November 2026, except run-derived counts and the `zig build verify` output (C38).
- **Evidence:** every cited line was printed and checked against its claim. "Not executed" marks
  a path established by reading only. "Traced" marks a count or a reach taken from reading call
  sites and not recounted. "Grep" marks a search of the production tree.
- **Runs:** the six runs of 10 November 2026 UTC (`2026-11-10T19-41-*`, 3 per case, build
  `a6ae058`, `modified` true, source `527484a8…`, Debug; their `zig-out/e2e-spec` directories are
  gone, their `evaluations/e2e/` records remain), which the user started before asking for this
  review. They are not a measurement set (§2 rule 3) and decide nothing. Their sends, tokens and
  logged span are `e2e-measures` values (`evaluations/e2e/<run>/measures.json`). Every other run
  figure in this section is indicative: it was counted by one-off reads of retained requests,
  responses and logs, which §9 reserves for the owning steps and the user hasn't approved, so none
  may serve §2 rules 5–7 (decided 15 November 2026: `e2e-measures` owns none of them). "The 38
  runs" were the runs on `aws-bedrock` /
  `openai.gpt-oss-20b-1:0` retained on 11 November; many are no longer under `zig-out/e2e-spec`,
  so those counts can't be retaken, and the six retained runs of 14 November serve where a
  finding says so. The four `anthropic` / `claude-haiku-5-5` runs of 9 November 2026 were left
  out and no model is compared (§9). T5's counts were not retaken.
- **Status:** an item is unscheduled unless it records a decision, and each item needs its phase approval
  (§2). An item that names no defect class targets no published-output defect: it reports a fact
  or asks a Decision, and proposes no change (AGENTS.md: cost is reported, never the reason for
  a change). An item that changes a model request is a Q phase with a named class. **D** marks a
  cost that an accepted ADR or a contract requires, so removing it is a **Decision**.

### 10.1 Failures first

**C8. Clarification records (adds to E7).**

- Built in part (stage 4, 23 November 2026): an accepted answer closes its record
  (`clarification_acceptance.zig:80`). Prior subjects are retained (`clarification_refresh.zig:61-62`) and any open record
  gives `needs_user` (`:54-59`). A rerun with an open record still makes every model call, because open records are first
  checked at `check-output-clarifications` (in `publish-specification`), after generation; not re-checked after stage 4.
- Built (stage 5, 23 November 2026, [Z_SPEC01](Z_SPEC01.md)): authority subjects were keyed by per-run ordinals and the
  contract version. They now name the kind, the unit's kind and the source text the unit concerns (ADR 0025, the
  clarification subject).

### 10.3 Coupling

**C22. Change amplification (traced).**

- One operation with one new key: about 8 production files. In `native_workflow_operations.zig` the fields are one
  struct (`Operations`) and the `entries` rows and their count are derived from it (Z_SPEC01 "Refactors that leave
  request bytes unchanged"), so the operation costs an import alias, a field and its initializer there; the YAML,
  `DataKeys` and schemas are unchanged. The initializers are still written by hand, which the compiler checks against
  the fields. `model_request_operations.zig` is derived the same way (built 22 November 2026, [Z_SPEC01](Z_SPEC01.md)
  "C22 remainder"; decided the same day, user: "update documenation with recommendation for decisions 3 4, 5, 6").
- One record family: three Zig files the compiler enforces and `Kind.isScopeSection`, now a method with an
  exhaustive switch; a test requires a `record_<kind>` definition and the `record_kind` member for every family
  but the entity. `packet-guidance.json` was already checked at decode. `records.prompt.md:9-13` names the families
  in prose, which no test can judge.

**C23. The model boundary carries Spec names.** The 32-tag `text_field_policy.Field` is part of
the generic field binding (`model_text_field.zig:5-7`, `model_text_wire.zig`, `typed_text.zig`,
`model_text_composition.zig`, `atomic_repair.zig:281`); ADR 0038's statement rule is wired through
generic admission (`model_payload_schema.zig:4`). `Field` is JSON-stringified and decoded by name
(`atomic_repair.zig:73-79`, :101-107), so a replacement must serialise as the same name and compare by value:
one enum per owner, with the generic modules parameterised on it. That touches about 13 Spec domain files, 13
tests and the harness, and amends text-field-composition.md:53 ("one closed native field registry"). **Deferred**
21 November 2026 (user: "update the documentation with rhe recommendations"): it pays off only when a second
workflow adds its own text fields, so build it with Plan's first text field, not before.

### 10.6 Tests and harness

**C41. The scripted driver is also the oracle (adds to E8)** (built 22 November 2026, [Z_SPEC01](Z_SPEC01.md)): a
failed check or operation error at a converted site in one of its step hooks fails its scenario with a returned error and
no longer aborts the test binary, and an architecture pin keeps `unreachable`, `@panic(` and `std.debug.panic(` out of
`spec_generation_driver.zig`. Its merge gates are a `merge_routes` table of typed (operation, owner) pairs, and the
`gates_bound` block fails the scenario with `GatedRouteNotInGraph` when the compiled graph binds none of one. Three
end-to-end cases run a scenario with an injected hook fault and require `run` to return it (a failing step-trace
allocator, a wrong expectation, and both, which keeps the first). Still aborting: the `.?` unwraps and
`std.debug.assert` in the driver, and the `std.debug.panic` sites in the `Recorder` of `request_projection.zig`, which
wraps the provider on every matrix call and is outside the driver-hook item.

**C42. The scripted matrix runs through `root.Runtime` only** (built 22 November 2026, [Z_SPEC01](Z_SPEC01.md)): the five
hand copies of `Runtime.init`'s wiring in `test/integration/workflow_tests.zig` are gone and an architecture pin keeps the
file from naming `native_workflow_operations`. Two limits stay. Offline runs reach publication, a repaired publication and
a retry-limit failure through `root.Runtime` and the harness's `invoke.run` for both development cases, with only the
transport scripted (`test/harness/integration/tests.zig`; the answers come from `spec_generation_responses.build`, and
`invoke.Options.runner_view` is its test-only seam); the matrix does not use `invoke.run`, since its frozen projection
embeds the fake provider's identity and the driver's fault shapes live in fake-provider hooks (decided 22 November 2026:
`Runtime` only). The matrix overrides the provider bootstrap and runtime, so the production provider path and the Bedrock
slot are covered only by those development-case tests, and a wiring drift that only a fault path reads in that provider
wiring still passes.

**C45. Typed limits beyond the sequence fixtures** (built 22 November 2026, [Z_SPEC01](Z_SPEC01.md)): the scenarios-step
and the repair and repeated-scenario exhaustions derive from the compiled step's allowance, and the disposition
sequence's calls before its exhausted request are asserted as ledger structure, since the three fixed calls (extract
content 1, extract classifications 1, reconcile summary 1) do not follow from the limit. Still typed: the brief
scenarios' `attempts == 3` (limit-following on the persistent runs, a scripted fault count on the others, so it needs the
scenario's repetition), the scripted-fault counts of `repeated_provenance_fault` and the non-exhausted loss runs
(a fault count plus one, not the limit), and the limit literals in `test/harness/integration/tests.zig` (~:1032-1054,
~:2374, ~:2386), where no driver exists.

### 10.7 Unconfirmed readings

**C49. Built 20 November 2026 ([Z_SPEC01](Z_SPEC01.md) "C49"); what stays open.**
- **A clarification-only batch's subject:** built (stage 5, 23 November 2026). The subject was
  `{specification, record_kind, content}` with `record_kind` picked by the model, so a rerun that picked another kind
  minted another form. It is now `{specification, records, content}` with the source lines cited by the bound signal's
  claims, and the model's kind, which it still names and the engine validates, is not part of it. An answered group is
  authored by E7 (answers are not consumed yet), so until stage 6 a rerun asks again.

**C50. A workflow definition can route past the configured preservation review: closed as by design** (user, 22
November 2026, after the test below). `check-source-preservation-policy` routes `ok` (the source preservation check is
configured) to `preservation-requirements` and `more` to `generate` (`spec.workflow.yaml:98-100`). Routing both to
`generate` is rejected: the review step becomes unreachable (a row of the mutation table in
`test/harness/integration/tests.zig`). Swapping them (`ok: generate, more: preservation-requirements`) compiles and boots
ready, so a definition can skip a configured review; a harness test asserting `boot != .ready` failed and the same test
asserting `== .ready` passed (integration 147/147), and it was not kept. An outcome association cannot enforce it: the
descriptors (`preserve`, `observe`, `authority_reconcile` and the rest) carry the unresolved rejections of native
subjects, and the policy step's `ok` is decided by configuration and opens no subject. Kept as designed because the
project authors both its workflow definition and its validation config, so it can already skip the review with
`sourcePreservationCheck: false`; a swapped definition is its own authoring error, as in C36. The alternative, a
workflow-owned predecessor gate before `generate` (AGENTS.md: workflows enforce order through their own gates), needs a
new production gate, since C30 keeps the mechanism with none, and is not built. The `required-authority@1` gate, deleted
21 November 2026, never covered this step.
