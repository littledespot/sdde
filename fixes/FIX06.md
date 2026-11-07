# FIX06 — Open Spec work

The only fix record: open work and user decisions not yet recorded in an ADR
([convention](README.md)). Each phase needs the user's approval before its changes, and
every live run needs its own approval; nothing here authorizes a code change, live call or
E2E run. **Decision** marks a question only the user settles; a recommendation is not a
decision. The governing design remains **Proposed design**. Implemented items are in
[Z_FIX06](Z_FIX06.md); earlier completed, closed and reverted work is in git history (last at
`0f3e4d2`).

## 1. Gate status and output quality

**Gate (ADR 0034): not met.** The D12.2 set's nine publications are adjudicated (§7 H1): 4 of 4
hello-world and 1 of 5 loan-renewal pass. `zig-out/e2e-spec/` holds the D12.1, D16.1 and D16.2
sets (six runs each) and the D12.2 set (ten runs), 1–2 November 2026, the six ADR 0047 runs of
3 November (`2026-11-03T04-1*`) and the six ADR 0047 + D12.3 runs of 7 November
(`2026-11-06T22-4*`, report v15, adjudicated); every earlier run, the D2.3 and Q10b sets
included, has been removed, and their evaluations and measures remain under `evaluations/`. The
current build decodes only `spec-e2e-report/v15` (`test/harness/e2e/contracts.zig:140`), so no
retained v12–v14 run can be adjudicated again.
Every retained run records `build.source.modified` true. The D16.2 set's captured build inputs
equal `ebc97d6` (the tree of `6e543e6`) byte for byte, all 1,824 files tracked, as the D2.3
set's equalled `194e29a`; whether either counts as "one committed build" (ADR 0034:64) is the
user's reading. Advisory, not gate evidence: over every scored publication since 29 October
(the table's sets plus the D13.1 pair `2026-11-01T04-13-54Z` and `04-14-32Z`; two published 29
October loan-renewal runs are unscored), hello-world met the rubric bar in 29 of 29 and
loan-renewal in 18 of 27. The user decides when Plan is actioned.

Reference for quality phases (§2 rule 7): the 12 adjudicated runs since ADR 0047 (3 and 7
November, one evaluator), the last kept state. ADR 0047 and D12.3 were kept on these runs,
which ran on uncommitted trees (user, 7 November 2026: "approved", after being told they were
direction only): a recorded exception to §2 rule 3, so the reference is measured but not on a
committed build. The two trees made the same requests for every call the 12 runs made: D12.3
changes only source-review and clarification requests, and none of the runs reached them.
Before them, the D12.2 set (kept 3 November 2026, [Z_FIX06](Z_FIX06.md) Q12 D12.2), 10 runs
(`2026-11-02T09-15-27Z` to `09-33-46Z`, 9 published) on source `bacfcd9ae368…`; measures in
`evaluations/e2e/<run>/measures.json` (the first six summarised in
`evaluations/d122-measures-set.json`) and evaluations in `evaluations/e2e/<run>/`. Its runs record
revision `b38628c`, `modified` true; whether their captured inputs equal `388438e`, which
committed D12.2's three workflow files, is unchecked and the user's reading under rule 3. For a
measure one call kind produces, rule 7 pools every publication whose request for that call is
byte-identical. A change proved under §2.10 moves neither. The previous references were D16.2
(`evaluations/d162-measures-set.json`) and D2.3 (`evaluations/d23-12/measures-set.json`);
"reference" in the defect-class table below and in §4 means the 18 publications of 31 October
(D2.3 and Q10b).

**Adjudicated reference** (§7 H1; skills `af394020…` and `0b552067…`, one evaluator by the
user's decision of 7 November 2026, [Z_FIX06](Z_FIX06.md) T7). Accuracy defect counts, content basis, as lost / weakened /
unsupported addition / contradiction:

| Set | Hello-world | Loan-renewal |
| --- | --- | --- |
| D12.2 (reference) | 4 of 4 published pass; 0 / 0 / 2 / 0 (`09-15-31Z` unpublished) | 1 of 5 pass; 4 / 1 / 11 / 0 |
| ADR 0047, 3 runs per case (`28213a7` modified; direction only, §2 rule 3) | 2 of 3 pass; 0 / 1 / 0 / 0 | 1 of 3 pass; 3 / 1 / 2 / 0 |
| ADR 0047 + D12.3, 3 runs per case (7 November, `f6ef0f6` modified, skill `0b552067…`; direction only) | 3 of 3 pass; 0 / 0 / 1 / 0 | 0 of 3 pass; 2 / 1 / 1 / 0 |
| Q20, reverted (entity-meaning purpose; 3 runs per case, 7 November, `63fb521` modified, skill `1d66d882…`; direction only) | 3 of 3 pass; 0 / 0 / 0 / 0 | 1 of 3 pass; 6 / 0 / 0 / 0 |

Pooled over the 12 runs since ADR 0047, against the reference: 12 of 12 published (9 of 10);
hello-world 5 of 6 pass (4 of 5 runs); loan-renewal 1 of 6 pass (1 of 5); loan-renewal per run,
lost 0.83 (0.8), weakened 0.33 (0.2), unsupported addition 0.5 (2.2). The story carries 5
loan-renewal and 2 hello-world accuracy defects in the reference (one per defect entry, as the
table counts) and none in the 12 runs. Every other failure since ADR 0047 is a repeat that loses
or weakens part of a requirement (§3 open problems).

**Output quality** (advisory scoring against the case rubrics,
`evaluations/e2e/<run>/evaluation.json`; scorer judgment moves a score about ±3.6; context
only, since keep decisions use accuracy defect counts, §2 rule 6):

| Build                                        | Hello-world mean (range) | Loan-renewal mean (range)        | Below 80% |
| -------------------------------------------- | ------------------------ | -------------------------------- | --------- |
| Q1b and 8444312 (14 earlier evaluations)     | 90.8 (82.1–100)          | 83.6 (78.6–89.3; 2 undetermined) | 1         |
| D2.3 tree (12 runs)                          | 89.9 (85.7–100)          | 86.3 (82.1–92.9)                 | 0         |
| Q10b tree (6 runs)                           | 89.3 (89.3–89.3)         | 82.1 (78.6–85.7)                 | 1         |
| D12.1 alone (6 runs)                         | 89.3 (89.3–89.3)         | 72.6 (67.9–78.6)                 | 3         |
| D12.1 with D16.1 (6 runs, 4 published)       | 86.9 (85.7–89.3)         | 85.7 (1 published)               | 0         |
| D12.1 with D16.2 (6 runs, 5 published)       | 89.3 (2 published)       | 85.7 (78.6–89.3)                 | 1         |
| D12.2 (10 runs, 9 published; reference)      | 93.8 (89.3–100)          | 82.9 (78.6–89.3)                 | 3         |
| D12.2 adjudicated (H1, skill `af394020…`)    | 92.9 (89.3–96.4)         | 82.1 (75.0–92.9)                 | 3         |
| ADR 0047 (6 runs, `28213a7` modified)        | 91.7 (85.7–96.4)         | 84.5 (75.0–92.9)                 | 1         |
| ADR 0047 + D12.3 (6 runs, `f6ef0f6` modified) | 91.7 (89.3–92.9)        | 85.7 (82.1–89.3)                 | 0         |
| Q20, reverted (6 runs, `63fb521` modified)   | 97.6 (92.9–100)          | 85.7 (78.6–92.9)                 | 1         |

No change since Q1b has improved the published output. Publications showing each defect
class, in the 18 reference publications of 31 October (D2.3 and Q10b, 9 per case) and the 15
since D12.1 (1–2 November; hello-world 8, loan-renewal 7), with the stage that produces them
now:

| Defect class                 | Reference HW / LR | Since D12.1 HW / LR | Producer since D12.1                                                                                          | Item         |
| ---------------------------- | ----------------- | ------------------- | ------------------------------------------------------------------------------------------------------------- | ------------ |
| rendering artefact           | 9 / 9             | 8 / 7               | engine (`assembly_or_render`)                                                                                 | Q7           |
| invented or restating entity | 8 / 9             | 7 / 7               | entities step                                                                                                 | none (Q18 closed 3 November 2026; git `28213a7`) |
| weakened obligation          | 0 / 8             | 2 / 6               | story step only; FR weakening 0 of 15                                                                         | ADR 0047 (kept) |
| unsupported addition         | 4 / 4             | 4 / 6               | story step (hello-world timing, display surface, ordering); records step (loan-renewal AC-001 "records the renewal", 5 of 7) | ADR 0047 (story), §3 open problem |
| restatement                  | 1 / 4             | 3 / 5               | brief title (2), story (2), records (D12.1's statement records; an edge case repeating an AC)                 | ADR 0047 (story) |
| lost source requirement      | 0 / 3             | 0 / 0               | none                                                                                                          | Q14          |
| ambiguity                    | 0 / 0             | 1 / 0               | records step (an AC precondition contradicting its trigger)                                                   | none         |

**Swing factors** (the scored publications of the gate paragraph, advisory). Two presence
outcomes explain most of the spread between sets:

- Loan-renewal publications with edge cases average 78.9 and 3 of 11 meet the bar; without,
  86.2 and 15 of 16. Eight of the nine below 80% have edge cases (Fisher p ≈ 0.0006); the
  source states none. The pooled count crosses the evaluator change below; within the
  v3-scored sets alone, 1 of 8 with edge cases meets the bar against 4 of 4 without
  (p ≈ 0.01). Edge cases appear in 3 of 9 reference publications, 3 of 3 under D12.1 alone,
  1 of 3 under D16.2 and 4 of 5 under D12.2 (against the reference, p ≈ 0.13).
- Hello-world publications with an entity average 88.3 (22) and those without 95.4 (7).
  D12.2's hello-world mean of 93.8 comes from 2 of its 4 publications having none.

No change so far has controlled either rate, and a set of three to five runs can't tell a
build's rate from chance (§2 "Why rules 4–7 changed"). The story's modes behaved the same way until ADR 0047 composed it. Items
elsewhere cite these figures rather than repeat them.

**Corrected by the user's rulings (3 November 2026, §7 H1):** the edge cases and entity
meanings behind both gaps aren't inventions, so the gaps are the evaluator's classifications,
not confirmed defects. The story's "may renew" is a confirmed weakening. The table above
predates the rulings; the adjudicated reference (above) replaces it for keep decisions. Under
the repeat rule ([Z_FIX06](Z_FIX06.md) T7), lost source requirement is 4 of 5 D12.2 loan-renewal publications,
not 0: EC-001's outcome "fourteen days" without the new due date (`09-15-30Z`, `09-33-44Z`,
`09-33-46Z`, byte-identical records output) and EN-001's meaning without "calendar"
(`09-15-27Z-d2ee…`).

**Evaluator versions.** The 31 October reference was scored under `e2e-assistant-evaluation/v2`,
with no link check; the D12.1, D16.1, D16.2 and D12.2 sets under v3, whose link check also
counts each false link as an `unsupported_addition` (`.claude/skills/evaluate-e2e/SKILL.md:167`).
The skill was created on 19 October and edited seven times by 2 November, so comparisons with
the reference cross an instrument change. Within one set the scorer still moves on identical
content: in the D12.2 set the doubled delimiter around `Hello, World!` was scored against
organization in 3 of 4 hello-world publications and against nothing in `09-33-43Z` (100).

Since D13.1 the retained runs show 0 runaways, 0 re-sends and 0 SyntaxError corrections; the
highest run used 67,448 of the 125,000-token workflow budget (`2026-11-02T02-28-14Z`).

## 2. Rules for measured phases

AGENTS.md ("Model output, prompts and evidence", "Anti-overfitting rule", "Validation")
governs; these add what the phases need.

1. **One change set per measured build.** Changes that rule 10 proves leave every
   development-case request byte-identical may share the build. A change set that isn't kept
   is reverted in full, never patched on top. Recorded exception: D16.2 amends the D12.1 +
   Q16 change set after its set failed the publication guard (user, 2 November 2026:
   "approved").
2. **Owner first, offline first:** `/preflight`; regression and negative tests at the owning
   boundary, compared with owners rather than copied English; `zig build verify`;
   `contract-reviewer`. Cover unrelated members of the class (both development cases plus an
   offline unrelated-domain fixture).
3. **Build.** Measurement uses a committed, unmodified build (`build.source.modified` false),
   kept with no standing deviation (decided 1 November 2026). A set's runs share one
   `build.source.source_sha256`. `fixes/`, `.claude/` and `evaluations/` aren't
   build-provenance roots (`build/provenance.zig:21`). Recorded exception: ADR 0047 and D12.3
   were kept on 12 adjudicated runs from uncommitted trees (user, 7 November 2026), so ADR
   0047:102's live measurement set on a committed build is unmet (§1 reference).
4. **Measurement set:** three runs of each development case (decided 2 November 2026), each
   approved, extended under rule
   6 to at most eight per case. Every attempt counts. Nothing is tuned on the reserved
   qualification features. A run costs about 15k tokens (hello-world) to 20k (loan-renewal).
   - **Screening** (decided 3 November 2026, H6.1): before a set, each call kind whose request
     the change alters (the §2.10 projection names them) is screened with paired replays of a
     retained request from each case, `e2e-call --repeats` as captured and with `--edit`
     (design/harness/e2e.md:67-92), about ten per arm, on the captured run's model and
     reasoning effort. A screen measures only T6's structural counts, so it can't measure a
     prose-only change; it decides nothing, and each replay batch needs approval. Its
     as-captured arm is a call-level control allowed for screens only: a set adds no control
     run on the comparison point's build (decided 1 November 2026).
5. **Evaluation and measures:** `zig build e2e-measures` and `/evaluate-e2e` for every run.
   - Defect classes are those of the evaluate-e2e skill (§2), counted over native publications
     beside the publication rate per case.
   - Each repair is graded helpful, neutral, harmful or no progress.
   - Brittleness counts: T5.
   - **One evaluator version per comparison** (decided 3 November 2026, H6.3): a set and its
     reference are scored on one evaluate-e2e revision. When the skill has changed, the
     reference is re-scored first from its numbered copies under `evaluations/e2e/` (rubric
     scores and defect classes; the link check and defect origins need the run directory), with
     link-derived `unsupported_addition` counted apart ([Z_FIX06](Z_FIX06.md) T7).
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
     blocks only when it crosses the effect size recorded before the set. Hygiene phases (Q4's
     retry, Q7 D7.5, the one-owner hygiene change in §3) are kept on guards alone plus their
     **Keep if** measures.
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
    owns its 24-feature panel; FIX06 sets use the two development cases and aren't protocol
    experiments.
12. **Report versions:** `adjudicate-spec` decodes `report.json` strictly, so adding, removing
    or renaming a closed member needs a report version. Runs before the closing set stay
    unadjudicated unless the user adjudicates them (decided 1 November 2026; no members-only
    decoder).

**Why rules 4–7 changed** (H6.1–H6.4, decided 3 November 2026, user: "apply
recommendations"): a set couldn't tell a change's effect from a re-roll of the generation
modes. The swing factors vary within sets of identical requests (§1); rule 6's test on about
ten events reaches p ≤ 0.10 only for changes of about four times (D12.2's story weakening,
8 of 15 → 1 of 9, p = 0.093); with five to seven guards each at a nominal one-sided 0.10, the
chance that some guard "rises" by chance in a set is up to about 41–52% (lower under the
discrete test); and the evaluator changed between a
reference and the sets compared with it (§1). FIX04 recorded the pattern on 16 October
("near-identical requests give opposite results", git `18a5ec8:fixes/FIX04.md:111-112`), and
FIX01 to FIX05 tried about 80 levers, reverted about 15 and closed without a demonstrated
output gain. Screens cost about 1.4k (story), 2.3k (entities) and 3.6k (records) tokens per
replay against 14.6k–18.5k per run (`2026-11-02T09-33-46Z`).

**Boundary gates** for contract changes (from FIX01 §5, git `b2f10a3`). Offline tests prove
native mechanics only; negatives that turn on meaning are judged in live sets against
human-reviewed labels, never by native code or a new judge.

| Boundary | Positive evidence | Negative evidence | Applies to |
| --- | --- | --- | --- |
| Summary representation | Combined, split, overlapping expressions; complete membership; stable identities | Missing or foreign IDs, altered categories, false support, changed exact values | Q8 |
| Normalization | Idempotence; same-evidence duplicates collapse; raw and provenance kept | Different occurrences, distinct obligations, paraphrases, destructive truncation | Q8 (D8.3) |
| Native carry-forward | Empty, non-final, final, one/many-child routing; complete lineage | Stale or forged child content, changed evidence, fabricated origin | Any summary change |
| Repair | Exact target and dependencies, protected siblings, progress, full final validation | Stale authorization, widened scope, reset allowance, invalid survivor | Q14 b3, E4 |
| Exact-value representation | Occurrences from exact bytes in bound fields survive repair and readback | False matches, ambiguous occurrences, unbound fields, changed obligations | Q7 |
| Cross-model behaviour | Paired repeated trials in unrelated domains | Meaning changed despite valid JSON, false rejection, unsupported acceptance | H5 only |
| Whole workflow | Real publication of the expected outcome, complete required review, H1 adjudication | Early stop reported honestly; no golden outputs or advisory analysis as acceptance | Every set |

## 3. Priorities

Ranked by expected reduction of published-output defects (AGENTS.md). Tracks: **Q** quality
phases (model input or published output change, each measured), **E** engine (no
model-input change except E7), **T** tests, **H** human decisions, **R** research. "Gap" means
between measurement sets.

**Next:**

1. **Preflight the one-owner hygiene change** (§3 open problems), extended to the field rule
   that asks every prose field to restate (recommended after Q20's revert, 7 November 2026).
2. **Decision pending:** whether a title that repeats a requirement's value states it (§7 H1).
   `2026-11-06T22-45-46Z-d392…`'s title "…extending the due date by 14 days" was scored a lost
   requirement; if a title doesn't state one, that run passes (96.4%). Recommended yes; settling
   it adds the ruling to the evaluate-e2e skill.
3. The rest of the lossy-repeat open problem (§3 open problems): edge-case outcomes and titles.

ADR 0047 and D12.3 are kept, and skills `af394020…` and `0b552067…` count as one evaluator
(user, 7 November 2026: "approved"; [Z_FIX06](Z_FIX06.md) Q19 D19.2 and T7).

**Output track** (recommended order, not decided, inside the decided constraints: D17.1 puts
Q17 after D12.2, and D14.1 holds Q14 b3; each change set is measured on its own committed build,
§2.1 and §2.3; completed change sets are in [Z_FIX06](Z_FIX06.md)):

| Rank | Item | Defect class reduced (since D12.1: hello-world of 8 / loan-renewal of 7) | Effort | Validation | Decided |
| --- | --- | --- | --- | --- | --- |
| 1 | **One-owner hygiene** (§3 open problems), with Q12's leftover and the field rule | lost source requirement and weakened obligation in entity meanings (5 of the 10 lossy-repeat failures, §3); unsupported addition in AC wording; repeated obligation instructions | S–M | Request projection, then a set | Q12 leftover folded in; field-rule extension needs a decision |
| 2 | **Q17** principles as records-call context | none scored; guards only unless the rubrics gain a principle criterion | M | Records screen, then a set | D17.1 |
| 3 | **Q7 D7.5** a plain string only where a field offers no insertion | rendering artefact C (joined fragments; 2 of 5 D12.2 loan-renewal stories) | S | Screen, then a set | D7.5 yes, a conformance fix |
| 4 | **Q4** retry, with D4.1's extension | engine vocabulary (none published; AGENTS.md compliance) | S | Screens of each changed call kind, then a set | D4.1 extension yes |
| 5 | **Q14 b3** | lost source requirement (missing refusal scenario recurred, `2026-11-07T01-19-36Z-728d…`) | L | Measurement set | D14.1: held until the class recurs, which it now has |

**Robustness track** (run completion and budget; no scored defect): E5's §22.6 correction
location. D13.1 removed the review calls where every runaway and SyntaxError of 31 October
occurred and where the budget ran short (lowest headroom 1,481 tokens): the D12.1, D16.1 and D16.2 runs
used 7,213–67,448 of 125,000 tokens. Run failures since D12.1 are exhausted retries: the
records call on `shared_member` twice (D16.1; D16.2 amends it) and reconciliation
dispositions on `missing_member` once (`2026-11-02T02-29-06Z`, an unchanged step).

**Engine track, in gaps:** E2 early; E3 after E2's first measure (nothing technical ties
startup to E1); E1 in any gap, retaking its freeze on the commit before it lands; E6 and E8 in
any gap; E4 after E1, E2's measure and its capture replays (§5 E4); E5's closed reasons with
the E1–E4 conversion that rewrites them, its evaluator gap in any gap; E9 with E1, E4 or E5;
R-A1 after E1; E7 last. E0 is on hold. E1, E4, E5 and E9 land only under §2.12, after H1 has
adjudicated the D12.2 set (§7 H1). E1–E4 before the closing set is the user's
call (ADR 0034:100-104). **Tests:** T2 and T3 in any gap; T4
with E1–E4. **Adjudication:** H1 (the evaluate-e2e skill) for every set. **Human:** H2 when required source review is labelled or review
returns; H3 when the user reviews the panels; H4 before any formal baseline freeze; H5 at the
user's choice. **Closing set:** repeated runs of both cases on one committed, unmodified build
(ADR 0034:64-65) unless the user amends ADR 0034; every counted published run adjudicated (H1).

**Open problems without an item.** Each stays until a structural lever with an owner is found
or the user records it as a model limitation.

- **Lossy repeats in entity meanings, edge-case outcomes and titles** (lost source requirement
  and weakened obligation; the adjudicated reference, §1). A field that restates a requirement
  drops or weakens part of it, which fails the requirement's criterion by the severity rulings
  (§7 H1). It fails all 4 failed D12.2 loan-renewal publications (records step, EC-001
  "fourteen days" without the new due date; entities step, `09-15-27Z-d2ee…` EN-001 without
  "calendar"), all 3 failed 3 November runs (entity meanings: "It must begin execution" without
  "successfully", `04-10-57Z`; "A borrower may renew", `04-13-31Z`; and `04-12-37Z`'s EN-001 and
  EC-001) and all 3 failed 7 November runs (EC-001 "fourteen days", `22-43-53Z-8f8c…`, records
  step; EN-001 "Allows a borrower to renew", `22-45-22Z-c845…`, entities step; the title
  "…extending the due date by 14 days", `22-45-46Z-d392…`, brief step, the first title case and
  subject to §3 Next item 2). Rewording the entity-meaning purpose alone (Q20, reverted 7
  November 2026; §1) didn't stop restatement: every loan-renewal meaning still restated the
  whole behaviour, one dropping "leave its due date unchanged" (`2026-11-07T01-18-32Z-ba2e…`),
  and loan-renewal lost requirements rose to 2 per run. Likely cause: the engine asks every
  prose field to type exact values verbatim (`text_field_policy.zig:92`, `:103`, `:107`) and
  to preserve obligations (`generation.context.json:2`), although `entity_meaning`'s
  exact-copy role is `.prohibited` (`:59`); the one-owner hygiene change takes it. Still open: edge-case
  outcomes, whose purpose already asks to keep conditions and obligations
  (`packet-guidance.json:26`), and titles (purpose `:4`); a lever with an owner or a recorded
  model limitation. **Not accepted** (user, 7 November 2026: "that is a poor idea and I will
  not accept it"): the engine filling `then` and `expected_outcome` from the record's cited
  source lines, since the result restates the Given and reads as requirements, not observed
  outcomes.
- **Unsupported additions in the story and records calls.** Since D12.1 the hello-world story
  adds timing ("immediately"), a display surface ("on the screen") or an order ("followed
  by") in 4 of 8 publications, and loan-renewal AC-001 adds that the system records the
  renewal in 5 of 7 (4 of 9 in the reference). The invented trigger "The user launches the
  application executable." (5 of 17 hello-world publications from Q1b to 31 October) hasn't
  recurred; one unscored variant did (`2026-11-02T00-05-04Z`). The `given` purpose forbids
  invented prerequisites (`packet-guidance.json:22`), the `when` purpose (`:23`) doesn't.
  By the user's rulings (§7 H1) the loan-renewal edge cases and a generic AC trigger aren't
  additions, and ADR 0047 composes the story from its claims (no story addition in the 12 runs since
  ADR 0047). AC wording ("records the renewal", 4 of 5 D12.2 and 1 of 3 7 November loan-renewal
  publications) is ruled a minor addition (§7 H1) and has no structural lever. New on 7
  November: an entity meaning carrying the brief's invented goal ("to confirm it is running
  correctly", hello-world `22-42-00Z-6422…`; the brief reaches the entities request, D12.1), a
  watch item.
  **One-owner hygiene change** (recommended; output track rank 5): give the no-invention
  instruction one owner across the scenario clauses (`packet-guidance.json:22`,
  `records.prompt.md:8`, `generation.context.json:4`). Q12's leftover joins it (decided 3
  November 2026): `generation.prompt.md:2` and `packet-guidance.json:26` stop restating the
  context's "conditions and obligations". Proposed extension (a **Decision**, amending
  text-field-composition.md:20 and ADR 0020's general verbatim rule): the field rule's
  verbatim sentence and the context's obligation clause reach only fields whose role carries
  them (`text_field_policy.zig:57-59`), so entity meanings, titles and goals stop being asked
  to restate. It keeps §9's single-run sentences (`records.prompt.md:7-8`
  shares a sentence with the scenario clause). **Keep if** no guard blocks (§2 rule 6), with
  unsupported addition in AC wording a watch item. After ADR 0047 and this change, report the
  remaining AC elaboration as a model limitation (AGENTS.md) and let H1 judge it.
- **Repair requests without step guidance:** six repair sites take their task only from the
  three-line `repair.prompt.md` (`spec.workflow.yaml:362`, `:399`, `:596`, `:752`, `:829`,
  `:844`), and the two reconciliation repairs among them (`:596`, `:844`) bind no context.
  Binding definitions (Q2) wasn't kept; counted as a brittleness measure (T5).
- **Provider doesn't enforce the response schema:** the engine's request matches AWS's
  documented Converse shape (`outputConfig.textFormat` json_schema,
  `src/adapters/provider/bedrock_request.zig:74-77`; schemas within the documented limits),
  and the gpt-oss-20b model card lists structured outputs as supported. Yet Bedrock's raw text
  block (not engine extraction, `bedrock_response.zig:135-149`) opens with a fragment and
  restarts the JSON in 198 of 205 responses in the D12.1, D16.1 and D16.2 runs (433 of 451 in the 31
  October runs), and two 31 October answers ended `end_turn` inside an open string (`5cbe…`
  call 25, `eea3…` call 23), which a grammar enforced from the first token to the stop can't
  produce. So ADR 0039:75's "schema-constrained decoding" premise doesn't hold for this route.
  Open: whether Bedrock applies the grammar partly or not at all. **Decided 1 November 2026:**
  §22.6 normalization is recorded as a provider defect (evidence: Bedrock request IDs
  `ad3f7d58-3b6b-4e99-bb37-f6463a9eb6b5`, `e1840c2b-fb08-4af7-a2e5-2ae75582c8f2`), and ADR
  0039:75's premise is corrected at the next ADR 0039 edit (a policy edit). The live
  comparison (one retained request with and without native JSON mode) is deferred: it needs
  an `e2e-call` change (it keeps the captured response mode, design/harness/e2e.md:115-116) and
  approval. Every fault the prefix caused was in the review calls D13.1 removed; none since.
  No model or provider change (H5).

## 4. Quality phases (Q)

### Q2b. Generic content-loss guard for repairs

**D2.3** is implemented and kept ([Z_FIX06](Z_FIX06.md)). Open follow-ups:

- remove `Relations.competing` under §2.12 (`reference_reconciliation_diagnostic.zig:159-161`);
- fold `member_count` into the `collection` variant (`model_result_schema.zig:103`, `:197`);
- assert the exhausted scenario's final rejection reason (`spec_generation_driver.zig:129-146`
  asserts only `.retry_limit`, `:143-145`).

Out of scope unless harm appears: the statement, signal and conflict coverage inserts and
token classifications.

### Q4. Remove engine vocabulary and schema-stated rules from prompts (retry)

The first attempt was not kept ([Z_FIX06](Z_FIX06.md)). 12-model-boundary.md:408-409 and
ADR 0016:151-152 say "FIX06 Q4 removes them", so the retry keeps the ID. No published spec
from 29 to 31 October contains engine vocabulary (0 in the 18), so this is AGENTS.md
compliance, not an output target.

**D4.1's extension** (D4.1 in [Z_FIX06](Z_FIX06.md); decided 3 November 2026): the rule covers
native rule and correction texts too, and a sentence that says what a field, claim or response
contains stays even when the engine enforces or transforms it.

**Scope still model-visible:** `support.prompt.md:28-29` (bound for pre-generation source
review); `packet-guidance.json:63`; `reconciliation-dispositions.prompt.md:2-4`;
`extraction-classifications.prompt.md:2-5`; `records.prompt.md:4-5`;
`support-loss.prompt.md:22`; the "native code …" texts in
`src/domain/reference_reconciliation_diagnostic.zig` (lines 101, 106, 119, 122, 124, 132, 134),
which reach requests through `descriptionFor` (`reference_model_input.zig:297`);
`src/domain/typed_text.zig:156` (no projected request carries it, but
`specification_repair.zig:81` can send it). D13.1 removed the restated "exactly once" with
`principle.prompt.md`. Reword engine vocabulary in place; remove a restated rule only when the
schema or its correction states all of it; keep task semantics the engine doesn't check (both
`citations` sentences and the `claim_ids` definition). `records.prompt.md:9-13` states the
coverage rule and an "at most one record" rule (ADR 0038 Decisions 2 and 5); the engine checks
the second only for non-requirement statements (ADR 0038:103-106), and the sentence is kept as
written on purpose (:116-117). It stays as their only carrier on a first attempt, since the
provider schema can't express them.

**Validation:** projection shows only the listed texts change; scripted missing and repeated
members get the `array_length` and `duplicate_member` corrections; then a set, with the
extraction requests screened first (§2 rule 4; the first attempt broke hello-world
extraction). **Keep if**
engine vocabulary stays absent and no guard blocks (§2 rule 6); corrections, rejections,
defect classes and cost are watch items. Never rename a field to chase a leak.

### Q7. Exact values

**Defect:** rendering artefact in 18 of 18 reference publications and 15 of 15 since D12.1
(counted from the published bytes):

- **A. Doubled delimiter** (70 occurrences in the 18 reference publications: FR 25, story 20,
  AC 19, UO 3, BR 2, expected outcome 1). ADR 0036 Decision 6 removes only backtick runs
  around a value (`exact_value_recognition.zig:137-152`, `delimited` at `:58-84`); the model's
  `"` stays in the neighbouring plain text (`specification_provenance.zig:289-297`); the
  projection gives an exact copy its own code span (`specification_projection.zig:152-168`;
  23-rendering.md:99-105) unless D7.4's exception applies (`delimitedByText`, `:174-185`),
  which excludes a value ending in terminal punctuation and so every development-case value;
  the renderer escapes the quotes (`specification_markdown.zig:324-343`). Where the span stays,
  the doubling is the engine's: it adds a span to a value the model already delimited.
- **B. Plain value in an entity meaning** (20 in 14 reference publications; 5 bare in 3): the
  field bars exact copies (`text_field_policy.zig:59`; `specification_provenance.zig:227-232`,
  `:281-284`, `:304-318`). All 20 sit on lines scored as invented or restating entity. ADR
  0045, which would have shown them as code spans, is withdrawn (D7.2, [Z_FIX06](Z_FIX06.md)).
  By the user's rulings (§7 H1) an entity meaning isn't an invention, so B is a rendering
  question only.
- **C. Fragments joined without a separator** (1 of 18 reference publications; 2 of 5 D12.2
  loan-renewal stories, each a `{"fragments":[...]}` object of plain strings): the schema keeps
  the fragments option when no reference is offered (`model_result_schema.zig:230`,
  `:328-351`; `model_text_field.zig:174-189`, `:228-251`), and fragments join with no separator
  (`model_candidate_json.zig:251-253`, `:269-282`).

- **D7.4** (implemented, [Z_FIX06](Z_FIX06.md)): decided 1 November 2026, D7.4 is not a
  punctuation rule (AGENTS.md "Prose heuristic").
- **D7.5** (decided 3 November 2026: yes, a conformance fix with no contract amendment, since
  07-domain-representations.md:74-80, ADR 0006:302-316, 12-model-boundary.md:1140-1141 and
  text-field-composition.md:20-21 already reserve fragments for composition around typed
  insertions): where a field offers no inserted reference, its schema offers only the plain
  string (`model_text_field.zig:174-190`; `textContract`, `model_text_wire.zig:277-292`). Schema
  bytes change in every generation request (0 passive literals in the retained runs), so a
  screen, then a set. Verified: admission validates the response against the same selected
  schema the model
  receives (`admit_model_response.zig:19-21`; `model_request_preparation.zig:27`, `:92-99`)
  before the codec runs (`model_candidate_handoff.zig:24-32`), so a fragments object against a
  plain-string field fails as `type_mismatch` with a protocol correction. Effort S: `walk` in
  `model_text_field.zig`, its tests, and the 9 `insertion-presentation` calibration requests
  with the sha256 pins in their `prepared/plan.json`; `generation.context.json:2` still
  describes fragments. Every observed fragments object is a story, which ADR 0047 composes natively,
  so D7.5 is a hygiene phase (§2 rule 6). **Keep if** no fragments object appears where no
  reference is offered and no guard blocks; admission rejections, protocol corrections,
  runaways, unsupported addition and restating entity are watch items.
- **Not recommended:** typed exact-value references inserted by the model (ADR 0020 replaced
  them after 4 of 5 hello-world runs failed, and the model's quotes would still double);
  removing the model's quotes (rewrites model bytes); a prompt asking for no quotes.
- **D7.3** (recorded 3 November 2026; reopen when a live case shows it): whether a token inside
  a claim must sit on the recognition boundary to force a duty (`CTIV` in `ACTIVE`,
  `structured_token_test.zig:45`, `:56`). Owner `exact_token_obligation.zig:11-31`; amends ADR
  0024:33-35 and ADR 0036 Decision 5. The boundary alone would drop real duties (a link
  destination, `exact_value_boundary.zig:120`; a code span with a suffix, `:136`). Option
  needing IDs only: force a token only from a claim that cites its own occurrence. Decided
  offline with accepted and rejected fixtures and byte-identical requests; no set can exercise
  it.

Boundary tables (`exact_value_boundary.zig`) are never extended case by case. A boundary
rejection is silent (`exact_value_recognition.zig:109`), so no set can count it by reason.

### Q8. Source-claim granularity (B7)

**Defect:** restatement and claims lost in reconciliation when citations repeat. The list-item
split (`reference_extraction_text.zig:144-183`) fired in 13 of 40 first extractions and gave
the same claims as per-item citations; no current-build run repeated a citation set. On Q4's
reverted build loan-renewal repeated `[5,6,7,8,9]` and failed (`2026-10-31T02-52-34Z-b671…`,
`02-54-32Z-8be8…`, `03-01-37Z-7c6a…`).

ADR 0036 Decision 3 and ADR 0038 Decision 4 (the list-item split) stay as they are (D8.1,
decided 3 November 2026).

- **D8.2** Whether "cites in full" (ADR 0036:125-129) covers a fenced block whose first or last
  interior line is blank (`markdown_code_spans.zig:53`, `:59`;
  `exact_token_obligation.zig:40-45`; `source_selections.zig:57-60`). No fixture covers it.
- **D8.3** Whether same-category claims on the same cited lines are one claim (precedent
  16-reference-ingestion.md:254-262), including claims inserted by source-omission repair; a
  same-lines pair with different categories needs its own answer.

D8.2 and D8.3 are decided offline with fixtures at their owners and §2.10 projections, in any
gap, or recorded.

### Q13. Inline source lines

D13.1 (post-generation reviews removed) and the inline source lines are in
[Z_FIX06](Z_FIX06.md). Reopen link checks, in shadow mode, only if adjudication shows semantic
defects that the generation-side items (Q14, ADR 0047) leave. **D13.4** (decided 1
November 2026): principles are context and constraints only, never origins, and never modified
(Q17).

Nothing checks what a shown source line means beyond the advisory evaluate-e2e link check.
Open:

- **Clarification question lines disagree.** `clarification_preparation.zig:32` prints
  `lines {start}–{end.line}`, so a citation of line 5 reads "lines 5–6" there and "line 5" in
  `spec.md`. Fix: use `source_coordinates.lines`. It changes clarification form bytes; no
  development case reaches a clarification today.
- **D13.7 (decision, needed only when Plan's editable reparse is built; ADR 0034 gates it):**
  what a hand-edited or stale source line does at the plan boundary. 23-rendering.md §23 says
  readback compares it with the derived line, but not what a mismatch does. **Recommended:**
  regenerate it from the re-attributed provenance, never block on it, since the line is a
  display and a user can't change what a record cites by editing it.
  **Limits:** a citation is only as true as its link (loan-renewal AC-001 would cite the
  refusal line it doesn't state), so it pairs with Q14 b3; entities cite whole groups (R1);
  semantic checking rests on adjudication (H1).

**D13.6 — decided 1 November 2026** (user: "the review repair should check that the claim
exists, if the claim supplied by the LLM does not exist then is should attempt to get the LLM
to repair with guidance on the error"). Every claim a model supplies must exist; a
non-existent claim is rejected and the model is asked to repair it, with guidance on the
error.

- **Already in place:** every claim, signal and line ID a model supplies is a closed integer
  choice: records' `claim_ids` (`specification_session.zig:404`), the question, brief, story
  and basis `signal_ids` (`:403`, `:406-411`), entity `signal_ids` (`:412`), dispositions and
  conflict groups (`reference_model_input.zig:241`, `:247`), extraction lines (`:58`) and
  conflicts (`reference_reconciliation_stage.zig:81`). A non-existent ID fails response
  admission as `enum_mismatch` (`model_payload_schema.zig:167`) and gets a protocol correction
  within the step's retry limit. No such correction fired in the 18 runs of 31 October or the
  D12.1, D16.1 and D16.2 runs.
- **Gap, the guidance:** the correction says only "this value is not among the allowed
  values" (`model_schema_diagnostic.zig:34`), and its expected shape for an ID choice is
  `{"type":"integer"}` (`model_schema_projection.zig:75-79`). It names neither the rejected
  ID nor the IDs that exist; the rejected response travels with the correction
  (`model_protocol_retry.zig:96`).
- **Change (approval needed to implement):** the `enum_mismatch` correction for an ID choice
  names the rejected value and lists the allowed IDs, both taken from the compiled choice,
  never hard-coded (D4.1's precedent for `uncovered_member`). It amends 22-repair.md:578-579,
  which keeps the allowed-ID list out of an integer-enum outline, and :574-575 ("no other
  correction changes"). It changes model-visible correction text only; first requests stay
  byte-identical (§2.10). Proven offline: a scripted non-existent claim gets the named
  correction and an accepted retry. A set can't measure it, since it hasn't fired live.

### Q14. Scenarios bound to their claims

**Defect:** lost source requirement: no scenario tests refusal in loan-renewal 3 of 9
reference publications (and 3 in the Q1b era); 0 of 15 since D12.1, where every loan-renewal
publication tests refusal. Likely cause: without the drafts the records call writes one FR per
claim, and coverage gives each FR-named claim a scenario. Coverage (ADR 0038 Decision 2;
`specification_session.zig:340-346`) now covers FR, BR, UO and PB claims and checks links, not
meaning (ADR 0038:126-128). Before D12.1 every retained `uncovered_member` firing failed: two
Q1b runs exhausted the records retry limit (2, `spec.workflow.yaml:724`), and two 31 October
runs (`07-35-27Z-0669…`, `07-37-18Z-61b3…`) passed by adding the claim IDs to the success-only
AC-001. It hasn't fired in the D12.1, D16.1 and D16.2 runs.

- **b3 (D14.1):** a claim-bound scenario insert: the engine fixes the new record's
  `claim_ids` to the uncovered claim and the model writes only its content, closing the
  add-a-link escape. Effort L, using today's repair loop (`spec.workflow.yaml:741-766`); E4 is
  not a prerequisite.
  - Coverage must move from payload admission (`model_payload_schema.zig:205-217`, behind
    `shared_member` at `:200-204`, where no typed candidate exists and only a whole-response
    retry is possible) into the unit validator beside entity membership
    (`specification_generation.zig:249-266`).
  - Insert repair exists today only for entity membership (`specification_repair.zig:50-67`,
    `:128-141`, `:374-378`, `:469-478`). The record gates at `:253`, `:376` and `:470` lift; a
    group policy for a fixed claim is added (`GroupPolicy` has only `.membership`,
    `specification_candidate.zig:141-143`); the record repair definition stops being only
    `repair_record_entity` (`specification_repair.zig:270`); and the unused content-only
    `repair_record_acceptance_criterion` schema (`generation.schema.json:527-538`) gains an
    edge-case counterpart.
  - A compiled coverage rule needs covering kinds (`model_result_schema.zig:210`), so keeping
    `shared_member` at admission without `uncovered_member` changes the result-schema rule
    contract.
  - ADR 0038 Decision 1 already says repairs stay content-only and keep the record's claims
    (0038:63-64). Deletes the admission-time coverage check (`uncovered_member`) and D4.1's
    covering-kinds correction; D16.2's partly taken statement (`shared_member`) stays at
    admission and its repeated statement a native delete.
  - Amends ADR 0038 Decision 3 (:72-80, :180-182) and :98-100, :155-157; 22-repair.md:269-273,
    :565-576 and :812-814; 12-model-boundary.md:126 and :1020-1022; 17-specify.md:209-212;
    F0100:1234-1236 and :1403-1408; design.md:1151.
  - An inserted scenario still links without checking meaning.
- **b2:** the scenarios naming a claim must together contain every exact value its quoted text
  requires (IDs and exact bytes; `exact_token_obligation.zig:47-56`). On the 24 records
  responses retained on 31 October it fires only on the two false links; it misses claim 4
  and business-rule-only cases; it runs after parsing (`specification_coverage.zig:107-128`),
  so its failure route (coverage repair or block) needs a decision, and it adds a report
  reason (§2.12). Effort M–L.
- The advisory evaluate-e2e link check counts false links (D16.2 set: AC 2 of 11, edge case 2
  of 2).

**D14.1 decided 1 November 2026:** b3, not b2. **Re-decided 3 November 2026:** b3 is held
until lost source requirement recurs, since the class is absent since D12.1 and a set could
show only "benefit not demonstrated" (§2 rule 6). When it recurs, b3 goes ahead as described.
**Keep if** lost source requirement falls and publication and exhausted runs don't worsen.

### Q17. Principles as Spec context

**Decided 1 November 2026** (user): "the workflow must never modify principles - NEVER" and
principles "should be used for context when executing the spec workflow".

- **Never modified:** holds today. Principles are read through a read-only source adapter
  (`src/adapters/filesystem/principle_source.zig`: reader, enumerator, capturer), the only
  principle capability is `principle_read` (`workflow_capability.zig:18`), and path
  validation rejects every project operation against the semantic-principles root
  (11-path-validation.md:20). Every future step (Plan, Implement, init, repair) keeps it. ADR
  0015 records it (0015:26-27); design.md §3.3 doesn't, although design.md was amended in
  `2b3dc8b` and `6e543e6` (adding it is a design edit awaiting approval).
- **Context:** today no generation call receives principles; only `capture-principle-registry`
  reads them (`spec.workflow.yaml:43-45`). Adding them changes generation requests, so it is a
  model-input change measured by a set. Principles are context and constraints, never a
  requirement's origin: items still cite only source claims (Q13's D13.4 resolved).
- **D17.1 decided 1 November 2026:** the records call only (it writes the FR, AC, BR and other
  statement records principles constrain), with the principle files as the registry captures
  them, unnumbered (items never cite principles). The case principles are 28,067 (hello-world)
  and 29,399 (loan-renewal) bytes, about 7k tokens per run. A measurement set after D12.2,
  with unsupported addition and invented entity as watch items (§2 rule 6; decided 3 November
  2026, user: "Yes, watch items").
- **Target and risk:** no current rubric criterion scores principle consistency, so a set can
  show only guards (unsupported addition and invented entity from principle text,
  publication) unless the case rubrics gain a criterion. Amends ADR 0015 (0015:10-15 already
  names D17.1), ADR 0023 "Principles" (0023:149-159), 17-specify.md's generation inputs
  (:264-284) and F0100.
- **Sequence (recommended, not decided; D17.1 places it after D12.2):** after the one-owner
  hygiene change's set, with a
  records screen first. It adds about 7k tokens of generic principle text to the
  records call, and the loan-renewal rubric's proportionate-scope criterion penalises
  principle-derived prescriptions, so its guards need a settled reference.

## 5. Engine track (E)

Each item: `/preflight`, offline tests, the §2.10 proof, `zig build verify`, one live run
per case (DE2 and DE3 ask whether offline evidence replaces it), landing between sets and under
§2.12.

### E0. Failed and blocked runs publish validated content (B10, ADR 0041)

On hold since 30 October 2026 (ADR 0041:3-9). Nothing under `src/` names `failure-output`,
`spec_incomplete` or `run.incomplete_published`. To resume: slices S1–S5 per ADR 0041
Decisions 1–8, taking `specification-state/v22` (v21 is current, `specification_state.zig:8`;
ADR 0041:4-6, :43); align the measures (`test/harness/e2e/measures.zig:132`, test `:522-525`;
e2e.md:730-733), ADR 0041:120 and :240, design.md:208 and :1154, F0100:1179 and
`test/harness/e2e/contracts.zig:209-212` with Decision 7.1 (an `invalid` run stays `invalid`
and may publish); add a test that a pre-E0 v15 report still decodes; flip the scenarios
asserting no publication (`test/integration/workflow_tests.zig:2440`, `:2257-2265`;
`test/harness/integration/tests.zig:1741-1742`, `:1763-1772`); register
`run.incomplete_published` through `adrRequired` (`src/domain/log_event_registry.zig:99-105`,
test `:162-168`). The amendment notes of ADRs 0009 (:15), 0011 (:46), 0017 (:7), 0037 (:11)
and 0039 (:31) state ADR 0041's effect without the hold; aligning them is a policy edit. If
ADR 0041 is withdrawn, v15's `incomplete_publication` (e2e.md:371) and the measures'
`incomplete` value become dead code needing a report version. Budget-stopped runs publish
nothing while it is on hold (three on `ddbc6d9`; none since D13.1).

### E1. Engine-owned model request (A1, ADR 0030 slice 4)

Not started: the `request-model` step replacing `model-request-body`
(`spec.workflow.yaml:944-1000`) and its five wrappers (`:870-943`), with the contract-variant
mechanism ADR 0033 reuses. It folds in ADR 0039's re-send and retires `validateRunawayRoutes`
(`src/domain/workflow_model_request_lifecycle.zig:86`). Retake the slice 1 freeze on the commit
before it lands. Slice 1 review points: trace the advisory production run; make
`extract/content` and `extract/content-request` (`spec.workflow.yaml:312-324`) one step; port
each runner-level lifecycle test in `src/model_request_workflow_test.zig` one for one with a
mapping table and a reason for any dropped assertion (user decision, 23 October 2026, option b).
`propagate-advisory-request-failure` and the advisory protocol were deleted with D13.1.
If E1 removes a request-lifecycle `DataKey`, it lands under §2.12.

### E2. Stage actions (A2, ADR 0031)

Not started: convert `prepare-toolchain` (`spec.workflow.yaml:173-202`) first and record ADR
0031's measures (:364-366) before another stage. **DE2:** confirm ADR 0031's derived choices
1–3 and 6–8 (:270-299), including whether choice 7's offline evidence replaces the live run.

### E3. Engine routines (A3, ADR 0032)

Not started. Convert startup first and measure it (ADR 0032:144-151). Feature logging waits on
its preconditions (:152-172): no test covers cancellation under a log lock, and the
policy-transition coordinator waits on E6's §14.10 decision. **DE3:** confirm ADR 0032's
derived choices 1–8 (:224-243), including offline evidence; can be asked with DE2.

### E4. Generic repair operations (W3, ADR 0033)

After E1, E2's measure and its capture replays (ADR 0033:264), which must be
`model-request-debug/v16` captures (`model_request_description.zig:5-10`; earlier captures no
longer decode): all Specify owners in one change on
offline equivalence evidence; the 29 operations and 13 owners of ADR 0033:89-105 still match
(10 authorize, 6 build, 6 parse, 7 merge). Seven operations read `.packet_guidance`; their
variants keep those reads. Retained reports carry repair keys, so it lands under §2.12.
**DE4:** confirm ADR 0033's derived choices 2–8 (:276-288; choice 6 is moot since D13.1,
:283-284). Q14 b3 reuses these operations.

### E5. Rejections say why (A4)

Give the payload-free `.authority` rejection a closed reason
(`src/domain/workflow_execution.zig:56`, `:74`) and split `error.OperationExecutionFailed`
(131 sites in 38 production files, 2 November 2026) into causes at their owners; sites E1–E4
rewrite land with that conversion. Failure-evidence gaps:

- Evaluator partial bodies disappear (harness only; matters for H3): carry the transport's
  `ResponseBody` bytes and completeness through `test/harness/provider.zig:27-34`,
  `bedrock.zig` (`:67-70`), `http.zig` (`:99-101`) and `evaluation_trace.zig`, with redaction
  and fault tests.
- A later failure replaces the earlier cause
  (`src/application/workflow_model_invocation.zig:15-22`,
  `workflow_pipeline_runner.zig:448-470`): keep the first cause beside the terminal one.
- **Correction location:** all four SyntaxError corrections in the 18 runs of 31 October told
  the model `byte_offset 4`, key `"{"` (the malformed opening), not the unterminated string;
  `model_envelope.zig:68` drops the re-parse diagnostic and `:75` reports the original, as
  §22.6 requires (22-repair.md:522-523). Fixing it amends §22.6 and changes correction
  requests; one of the four corrections ran away. None has occurred since D13.1.

### E6. Logging and visibility gaps

- **Cancellation** during segment reads and under the log lock ends the run `blocked`, not
  `cancelled` (`operation_error.zig:16-24`; `feature_log_recovery.zig:29-61`;
  `feature_log_historical_stream.zig:95-97`). **Decision:** should cancellation during log
  reads or under the lock end the run `cancelled`? If yes: add `Cancelled` to the
  `FeatureLogSink` error set and propagate it, amending ADR 0032:314-315's "Not decided"
  bullet; no new `LOG_*` code.
- **Lock failures** all report `LOG_LOCK_TIMEOUT` (`acquire_feature_log_stream_lock.zig:18`):
  the single `tryLock` never waits, and `InvalidBinding` and `SinkFailure` aren't timeouts
  (F0002:562, :573-574; `feature_log_lock.zig:9-27`). No decision needed: map those two to
  F0002's existing `LOG_SINK_FAILURE` and keep `LockUnavailable` as `LOG_LOCK_TIMEOUT`.
- **Prior-run crash finalization** (§14.10) is blocked on a persisted bootstrap authority that
  doesn't exist (14-orchestration.md:326-330), so a crashed run's logs are kept whole and
  damaged prior logs block later runs until someone repairs or removes them. E3's
  feature-logging conversion waits on this decision.
- **Redaction policy ID:** 26-security.md:196 and F0002:559 name `redaction/default-v1`, which
  no code carries. **Decision:** a record carries the ID (a `feature-log/v2` field, so a
  version change), or both documents drop it. **Recommended:** drop it.
- **Producerless rejection** (fixed, [Z_FIX06](Z_FIX06.md)), still open: contract 27
  (27-observability.md:58-61) names only coverage as an assembled-candidate example (design
  edit awaiting approval: add `producerless` as a second example); `observation.capture`'s
  candidate arm (`test/harness/e2e/observation.zig:77`) has no direct test. **Decision**
  (optional): a first-generation omission names its chunk's classification producer.
  **Recommended:** no.

### E7. Clarification answer recovery (R2, ADR 0025)

Not started; no §13 authentication chain exists in `src/`. Fresh answers can't complete
recovery: refresh rejects new submissions (`clarification_refresh.zig:65`); provenance
rejects nonempty response-ID sets (`specification_provenance.zig:88`,
`specification_support_evidence.zig:170`); form validation returns one
`InvalidClarificationInput` (`src/actions/clarification/validate_clarification_forms.zig`);
resolved needs are empty (`src/actions/clarification/build_resolved_clarification_needs.zig`);
generation doesn't consume answers (`specification_source_binding.zig:95`, `:147`). Complete
the [§17.4 lifecycle](../design/contracts/17-specify.md#174-specification-clarification-behavior)
under ADR 0025. Live validation needs a user-chosen clarification-expected case run twice with
forms answered between runs; neither the case nor a two-run harness flow exists. Last, after
E1–E4.

### E8. Typed schema-definition identities

Domain code names result-schema definitions by raw strings: T5.2 counted 20 production sites
on the D13.1 tree (`zig-out/code-heuristics/report.json`, 1 November; baseline 22 in
[Z_FIX06](Z_FIX06.md) T5). They fail only at request preparation (`model_request_handoff.zig`;
sites in `specification_support.zig`, `specification_session.zig`, `specification_repair.zig`,
`reference_model_input.zig` and the reference reconciliation and extraction-repair files).
Bind them as closed IDs checked at schema load. Test fixtures branch on names too
(`spec_generation_driver.zig`, `spec_generation_responses.zig`).

### E9. Superseded exact-handle correction

`ValueChoices.correction`'s `unknown_exact` arm (`specification_provenance.zig:177-180`) corrects
a model-authored exact handle that models can't author since `dfae959` (ADR 0020:231).
`ValueChoices.permits` (`:167-169`) has no caller. Delete the arm, `permits`, the
`rejected_exact` member (`typed_text.zig:144`), its assignments (`typed_text.zig:245`,
`specification_provenance.zig:426-433`) and the assertions that read it
(`typed_text_test.zig:32`, `specification_generation_test.zig:6575`,
`packet_guidance_test.zig:203`); the `unknown_exact` rejection stays. Neither current freeze
carries `rejected_exact`, and the only report that did (the failed
`2026-10-31T03-01-37Z-7c6a…`) is no longer retained. Lands with E1, E4 or E5.

## 6. Test track (T)

### T2. Test decoupling

Tests copy model-facing English or check its absence: about 32 lines of 25 or more characters
in 7 files (2 November 2026). Compare with the owning constant or resource instead: copies in
`model_request_workflow_test.zig`, `model_payload_schema_test.zig` (and its `:362-367` phrase
checks on `protocol.prompt.md`), `reference_model_input_test.zig`,
`test_fixtures/spec_generation_driver.zig`, `model_text_field_test.zig`,
`reference_reconciliation_test.zig`, `specification_generation_test.zig:7791`; absence checks
at `model_text_field_test.zig:177` and `model_request_workflow_test.zig:4529`. Rename tests,
fixtures and `measurement_prefix` dumps named after live runs: dumps r35, r36, r37, r40, r41
and fix002 (`workflow_tests.zig:1556-1636`); tests R36 (`model_envelope_test.zig:381`), R42
(`specification_generation_test.zig:6180`), FIX002 (`:6342`, `:6398`) and D1
(`model_candidate_json_test.zig:279`); fixture headers R35 and R36
(`summary_protocol_sequence.zig:1`, `global_protocol_sequence.zig:1`); and
`build/test_run_inputs.zig:22`, `:33-40`, deleting its orphaned `d1-review`, `r42-recovery`
and `r43-recovery` entries (`:20`, `:39`, `:40`). **Decision:** delete the never-run
insertion-presentation panel with its `attribution-replay` tooling
(`test/harness/attribution/preparation.zig:191-199`, whose first replacement phrase at `:195`
no longer occurs in production text), or keep it.

### T3. Coverage gaps (B5, B7)

- No integration scenario reaches a `duplicate_record` delete or ADR 0035's story
  `restatement`; unit coverage only. D16.2's `repeated_statement` has one
  (`workflow_tests.zig:1345-1348`, `:2234-2239`).
- The no-feature-claim text-repair route (`spec.workflow.yaml:351-372`) has unit coverage only;
  the integration `.unbound` mode ends `.invalid` before it.
- The retained GPT-OSS compatibility exchange is assessed `incompatible` since ADR 0036
  (`provider_compatibility_tests.zig:261-262`, `:305-309`), so the normal §22.6-normalized path
  has no compatible-assessment coverage.

### T4. Architecture rules and replay (A5)

When E1–E4 remove files pinned by architecture tests, write the replacements as import-graph
and contract-shape rules (ADR 0030:505-509, 0031:346-362, 0032:293-305, 0033:341-344), not
per-file pins (about 70 of the 78 tests pin files). Prefer replaying retained captures over
extending `spec_generation_responses.zig`.

### T5. Brittleness counts

Baseline, definitions and decisions: [Z_FIX06](Z_FIX06.md). Each change set that a phase
reports on retakes them on its committed build: `zig build code-heuristics -- --freeze <dir>`
with the freeze §2.10 takes on that build, and T5.4 by hand from `spec.workflow.yaml` (a
`slot: repair` step whose prompt no non-repair step binds). Retaken 2 November 2026 on the
`b38628c` tree (the kept D12.1 + D16.2 change set) with
freeze `evaluations/request-projection/b38628c` (130 scenarios, 1,714 calls): T5.1 19, T5.2 20
(tests 88), T5.3 5 instructions at 11 sites, T5.4 6 (`spec.workflow.yaml:362`, `:399`,
`:596`, `:752`, `:829`, `:844`, each binding `repair-prompt`), T5.5 0, T5.6 13 in 4 files.
T5.1, T5.2, T5.5 and T5.6 equal the D13.1 tree's. The D12.2 tree with freeze
`b38628c-d122` gives the same counts. The `340261e-d162` freeze predates the final D16.2
tree (129 scenarios, 1,702 calls).

## 7. Human and decision track (H)

### H1. Adjudication (R8)

**Decided 3 November 2026** (user: "yes", to "should the evaluator's rubric scores decide
acceptance instead of your record?"): the `/evaluate-e2e` skill writes each published run's
`spec-adjudication-record/v1` (renamed from `human-spec-adjudication/v2`, user: "can be
renamed") from its rubric scores and applies it with `zig build adjudicate-spec` (AGENTS.md;
ADR 0034 and design/harness/acceptance.md amended). Only the user triggers or approves the
skill (user, 3 November 2026: "must be trigger manually by the use[r]"; 7 November 2026: "you
can start /evaluate-e2e if I give approval"); `/live-e2e` doesn't run it. It
replaces the user-scored five-run H1 and its comparison rule.

**Decided 3 November 2026** (user: "YES", "YES approved"): a run's first adjudication under a
skill version counts (R8, design/harness/acceptance.md). The D12.2 adjudication and the v15
report change are done ([Z_FIX06](Z_FIX06.md) H1); results in §1.

**Open:** `09-15-27Z-d2ee…`'s applied decision reads `admission_evidence_invalid`, from a
harness bug since fixed; its record scores `critical_failed`, which §1 counts. Its report is
v14, which this build can't decode, so correcting the applied decision needs the build that
made it and the user's decision under R8's first-adjudication rule.

**Rulings, 3 November 2026** (user, on the evaluator's classes; not adjudication records):
"may renew" for "must be able to renew" **is** a weakened obligation; the edge cases ("renew a
loan exactly on its due date", "has already been renewed and is now overdue") and the entity
meaning ("a borrowable item … can be renewed once") **are not** inventions; the trigger "The
borrower initiates a renewal request" **is not** an invented step. Then (user: "agreed on two
rulings"): repetition alone isn't an accuracy defect, only a readability one scored against
`organization`, while a repeat that drops, weakens or adds a condition or obligation is a
defect of that kind; and an entity for a feature with no business data (hello-world's "Hello
World Application") is a minor scope defect, at most one point of
`proportionate-business-scope`. The evaluate-e2e skill carries every ruling below (SKILL.md
§2, under the class table); every evaluation before them counted the edge cases and entity
meanings as `unsupported_addition` or `invented_or_restating_entity`.

**Severity rulings, 3 November 2026** (user: "Q1: yes, Q2: yes, Q3: yes"; they set scores, the
classes above set kinds; the rubric minimum of 3 makes them decide pass or fail):

- A section that states a requirement more weakly than a correct FR scores that requirement's
  criterion below 3: `02-29-15Z`'s story (line 7) and entity meaning (47) "may renew" against
  FR-001 (23); `09-33-46Z`'s EC-001 (27) "fourteen days" without the new due date against
  FR-002 and FR-003 (41, 45). A summary that doesn't claim to state the requirement
  (`09-15-32Z` line 33, "triggers a success message") costs `organization` only.
- An invented login and selection step in the story (`09-33-46Z` line 7) is a material
  addition: `source-grounding` below 3 (the rubric names accounts and UI controls).
- Recording the renewal ("records the renewal", AC-001; "updates the loan record", story) is a
  minor addition, so `source-grounding` can stay at 3: the one-renewal limit needs it.

Under these the story fails 3 of D12.2's 5 loan-renewal publications (`09-15-30Z` weakens;
`09-33-44Z` and `09-33-46Z` invent steps), and EC-001's lossy outcome (`09-15-30Z`,
`09-33-44Z`, `09-33-46Z`, byte-identical records output) fails `successful-renewal`; that class
is the §3 lossy-repeat open problem.

**Smaller rulings, 3 November 2026** (user: "apply recommendations"): "immediately … followed
by" in a hello-world story is a minor addition; "notification" or "notified" where it names the
displayed message is a minor addition; "The user launches the application" isn't an invented
step; escapes, quoted code spans and joined sentences are judged as rendered and cost
`organization` only.

### H2. Review-label confirmation (B2)

The scheme is `b2-review-label/v2` (`.claude/skills/evaluate-e2e/SKILL.md` §7). Q1b's labels
sit in three layouts under `evaluations/e2e/2026-10-29T*/` (run root, `b2-review-labels/`,
`b2-review-accuracy/`), and a `supported` verdict on a defective subject is labelled
`wrong_type` (5 runs), `missed_defect` with a null predicted type (2 runs, which inflates
precision: `09-03-15` reports accuracy 0.9714) or both (2 runs); the D2.3 and Q10b runs have
no labels. Cause: §7's "A defective subject with no finding of the expected type is
`missed_defect`" (`SKILL.md:286-287`) is ambiguous. **Proposed convention:** one entry per
returned verdict; a wrong verdict on a defective subject is `wrong_type` (counted in accuracy,
and as a miss in recall); `missed_defect` only when a subject got no verdict at all;
`defect_class` null whenever the expected type is `supported` (matches e2e.md:670-672); path
`evaluations/b2-review-accuracy/<set>/<case>/<run>/`. **Adopted 1 November 2026:** the
convention goes into SKILL.md §7 when it is next edited; the edits in `2b3dc8b` and `6e543e6`
didn't carry it (the path at `:270` still has no `<run>/` level). Relabelling Q1b isn't
needed: after D13.1 no post-generation review findings exist to label. §7 also governs
required pre-generation source review (`:264-267`), so the convention applies when that
review's verdicts are labelled.

### H3. Calibration panels (R8)

The hello-world and loan-renewal panels (`test/integration/fixtures/*/calibration/`)
have proposed labels only (`human-review.json`, `qualification.json` `pending`). They qualify
only the standalone evaluator; neither the gate nor FIX06's sets need them.

### H4. Experiment stops, qualified scope and the formal baseline (B4, B5)

**Decision** needed only before freezing the evaluation protocol's Phase 2 baseline. The
protocol stops at 1,000 sends or 2,000,000 tokens
([README](../test/calibration/semantic-simplicity/README.md):189-190), about 13.9 sends and
27.8k tokens for each of the Phase 2 baseline's 72 workloads. Since D13.1 the development
cases use 10–12 sends and about 14.5k (hello-world) and 18.3–19.7k (loan-renewal, published)
tokens; failed loan-renewal runs used about 27k, and two hello-world runs 34 sends each, 67,448
(`02-28-14Z`) and 65,621 (`09-15-31Z`) tokens (source-review repairs). The 72 workloads come from the protocol's 24-feature panel
(§2 rule 11), whose cost on the current build is unmeasured, and the latest feasibility report
(`zig-out/baseline/2026-10-15T22-38-08Z-4ae4…/budget-feasibility.json`, `insufficient`)
predates D13.1; retaking it is a `baseline` run (live, approval needed). Options if it still
doesn't fit: narrow the qualified scope, or the user changes the stops. Measure each call's
prompt, schema and evidence share before trimming; no local size ceilings (ADR 0011).

### H5. Model choice (R7)

The user decides when to change or compare models; all live evidence is GPT-OSS-20B. Only if
the user selects Claude Haiku 5.5: measure its maximum-output time to replace the interim
180,000 ms `requestTimeoutMs`, and settle Claude's response mode.

## 8. Research and backlog (R)

### R1. Group-level provenance precision

Entities and the brief and story fields select whole groups
(`specification_generation.zig:136-141`, `:166-169`; `specification_provenance.zig:558-562`),
and in every run from Q1b to 31 October reconciliation formed one signal holding every quoted
claim. Measure whether grouping and source review meet the traceability claim (design.md:121)
before any binding change; the advisory evaluate-e2e link check gives per-record evidence
(D16.2 set: false links AC 2 of 11, EC 2 of 2, FR 0 of 15, EN 0 of 4). No second provenance
store, no support inferred from text matching.

### R6. Semantic repair attribution and recovery

D13.1 removed post-generation review, and loss localization now runs unconditionally
(`pendingLocalization`, `specification_support.zig:319-324`). Remaining proposals, each needing
a closed contract: source-authorized exact-reference repair eligibility (ADR 0033:353-354);
narrow correction of invalid loss evidence (today `invalid`,
`specification_support_workflow.zig:50`; `specification_support_repair.zig:93`); verdict
reassessment under §22.1 with no voting or retry-until-positive. Two retained runs reached
required source review after `no_feature_claim`: `2026-11-02T02-28-14Z`, whose repair was
helpful, and `09-15-31Z`, whose false `candidate_omission` on the story ended the run (the
story has since left source review, [Z_FIX06](Z_FIX06.md) Q12 D12.3).

### B7 contract-review leftovers

- Prior-state readback checks stored claim text against the text policy only
  (`reference_snapshot.zig:116-117`; ADR 0036:205-207); re-quoting needs the Unicode
  normalizer at readback.
- `source_selections.validate`'s typed `Issue` is discarded by both production callers
  (`validate_reference_claims.zig:32-34`, `source_omission_comparison.zig:130-131`), and
  `validate-reference-selections` validates token classifications only. Delete the unused
  detail and rename the step and key for what they do (touches `spec.workflow.yaml`, F0100,
  `workflow_tests.zig` and nine `src` files; lands in a gap).

### Retired FIX06 IDs cited elsewhere

These IDs are no longer in FIX06 (their records are in git at `194e29a`, `fixes/Z_FIX06.md`);
each citing file needs its reference rewritten, a docs edit needing approval for ADRs:
"D3.1" (12-model-boundary.md:400-401, ADR 0016:132, `src/domain/packet_guidance.zig:1`);
"Q3" (ADR 0016:152); "Q1a, D1.2" (ADR 0038:147); "Q2" (ADR 0046:42-43); "T5(e)"
(`src/test_fixtures/request_projection.zig:1`, `test/integration/workflow_tests.zig:1311`);
"D10.2" (ADR 0023:27, ADR 0041:6; its record is in git at `388438e`). Swept across `design/`,
`.claude/`, `src/`, `test/` and the agent files on 7 November 2026.

### Wider scope retained

- **Memory and scale:** growing review sets, retained bytes, allocations, teardown,
  cancellation and OOM. Unmeasured.
- **Harness acceptance (former H-012, H-013, H-017; git `8ed40ba`):** the parts covered by
  tests were closed on 1 November 2026. Still open:
  - publication interruption: every write failure is covered as a failpoint (meeting ADR
    0009:142-145) but no process kill is tested; **recommended:** close;
  - rerun replacement through an unrelated workflow: covered at the shared writer; reopen when
    the first non-Spec publisher lands;
  - live negative cases as separate fixtures: none exist (`test/e2e/` holds the two
    development cases); adding them means live spend, the user's call;
  - production Specify feature-logging is done, but F0002:806-807 and F0100 still call it open
    (design edit).
- **Provider docs:** ADR 0028 links an F0009 feature document that doesn't exist
  (`0028-anthropic-messages-provider.md:35`, `:95`, `:151`), and its "Live use" (`:177`)
  contradicts `test/harness/model_cost_policy.zig:17-25`; `test/harness/e2e/cli.zig:26`'s help
  lists only the two Bedrock tuples, not the Anthropic route. No live Claude call has been made. Fixing ADR 0028 is a
  policy edit.

### R-A1. Engine-owned release

Whether the engine also takes over release, changing ADR 0012's retained-request handoff (ADR
0030:516-518). Decide after E1.

## 9. Guardrails

The user's standing constraints beyond AGENTS.md:

- No model change or comparison (H5).
- The workflow never modifies principle files (1 November 2026; Q17).
- No caps that discard output, and no larger token budget: a budget failure is fixed at its
  cause, such as review cost or runaways (30 October 2026). No local token ceilings, no
  truncated required evidence, no claim that a larger budget fixes reliability.
- These single-run prompt sentences stay until a defect is traced to one (D5.1, 3 November
  2026; the former Q5, git `0f3e4d2`), and the one-owner hygiene change says which it keeps:
  - `extraction.context.json` `claims`: "Include meaningful identity and purpose headings." and
    "Separate independent behavior, implementation and verification facts."; the second
    sentence of `business`, `technical` and `validation`;
  - `support.prompt.md:8-9`: ", including compatible requirements labelled conflicting" and
    "Empty claims or conflict labels do not establish a source gap."; `:22`: "A defective
    candidate is not a source gap.";
  - `records.prompt.md:7-8`: "Do not relabel positive requirements as assumptions or
    non-goals";
  - `packet-guidance.json`: "The source need not supply a title." (`display_name`) and
    "Displayed values alone do not establish entities, and an explicit declaration of absence
    is unnecessary." (`entities`). The story purpose's "Do not invent a persona or benefit or
    require a prewritten story." left with that purpose (ADR 0047 Decision 5, amended 7
    November 2026), after `09-15-31Z`'s false finding quoted it.
- Never batch or group source-review subjects (30 October 2026); this binds the remaining
  pre-generation source review.
- Measures and replays use the owning steps (`zig build e2e-measures`, `e2e-call`), never
  one-off scripts, loops or new tracking files (29 October 2026).
- Don't narrow the entity-name exception without a decision (B6; `text_field_policy.zig:60`,
  `:68-73`).
- Runaways stay a reported measure (ADR 0039).
