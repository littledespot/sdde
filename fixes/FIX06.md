# FIX06 — Open Spec work

The only fix record: open work and user decisions not yet recorded in an ADR
([convention](README.md)). Each phase needs the user's approval before its changes, and
every live run needs its own approval; nothing here authorizes a code change, live call or
E2E run. **Decision** marks a question only the user settles; a recommendation is not a
decision. The governing design remains **Proposed design**. Implemented items are in
[Z_FIX06](Z_FIX06.md); earlier completed, closed and reverted work is in git history (last at
`388438e`).

## 1. Gate status and output quality

**Gate (ADR 0034): not met.** No run is adjudicated (H1). `zig-out/e2e-spec/` holds the D12.1,
D16.1 and D16.2 sets (six runs each) and the D12.2 set (ten runs), 1–2 November 2026; every
earlier run, the D2.3 and Q10b sets included, has been removed, and their evaluations and
measures remain under `evaluations/`. The current build decodes only `spec-e2e-report/v14`
(`test/harness/e2e/contracts.zig:140`), so only the D16.2 and D12.2 runs can be adjudicated.
Every retained run records `build.source.modified` true. The D16.2 set's captured build inputs
equal `ebc97d6` (the tree of `6e543e6`) byte for byte, all 1,824 files tracked, as the D2.3
set's equalled `194e29a`; whether either counts as "one committed build" (ADR 0034:64) is the
user's reading. Advisory, not gate evidence: over every scored publication since 29 October
(the table's sets plus the D13.1 pair `2026-11-01T04-13-54Z` and `04-14-32Z`; two published 29
October loan-renewal runs are unscored), hello-world met the rubric bar in 29 of 29 and
loan-renewal in 18 of 27. The user decides when Plan is actioned.

Reference for quality phases (§2 rule 7): the D16.2 set, the last kept measured state (D12.1 +
D16.2 kept 2 November 2026, [Z_FIX06](Z_FIX06.md) Q16). It is 6 runs (`2026-11-02T02-27-46Z`
to `02-29-15Z`, 5 published) on source `1ae6b0583e57…`, the tree of `6e543e6`; measures in
`evaluations/d162-measures-set.json` and evaluations in `evaluations/e2e/<run>/`. A change
proved under §2.10 never moves it. The previous reference was D2.3 (12 runs on `dac4c4c` plus
its working tree, 31 October 2026; `evaluations/d23-12/measures-set.json`); "reference" in the
defect-class table below and in §4 means the 18 publications of 31 October (D2.3 and Q10b).

**Output quality** (advisory scoring against the case rubrics,
`evaluations/e2e/<run>/evaluation.json`; scorer judgment moves a score about ±3.6):

| Build                                        | Hello-world mean (range) | Loan-renewal mean (range)        | Below 80% |
| -------------------------------------------- | ------------------------ | -------------------------------- | --------- |
| Q1b and 8444312 (14 earlier evaluations)     | 90.8 (82.1–100)          | 83.6 (78.6–89.3; 2 undetermined) | 1         |
| D2.3 tree (12 runs; previous reference)      | 89.9 (85.7–100)          | 86.3 (82.1–92.9)                 | 0         |
| Q10b tree (6 runs)                           | 89.3 (89.3–89.3)         | 82.1 (78.6–85.7)                 | 1         |
| D12.1 alone (6 runs)                         | 89.3 (89.3–89.3)         | 72.6 (67.9–78.6)                 | 3         |
| D12.1 with D16.1 (6 runs, 4 published)       | 86.9 (85.7–89.3)         | 85.7 (1 published)               | 0         |
| D12.1 with D16.2 (6 runs, 5 published; reference) | 89.3 (2 published) | 85.7 (78.6–89.3)  | 1         |
| D12.2 (10 runs, 9 published)                 | 93.8 (89.3–100)          | 82.9 (78.6–89.3)                 | 3         |

No change since Q1b has improved the published output. Publications showing each defect
class, in the 18 reference publications of 31 October (D2.3 and Q10b, 9 per case) and the 15
since D12.1 (1–2 November; hello-world 8, loan-renewal 7), with the stage that produces them
now:

| Defect class                 | Reference HW / LR | Since D12.1 HW / LR | Producer since D12.1                                                                                          | Item         |
| ---------------------------- | ----------------- | ------------------- | ------------------------------------------------------------------------------------------------------------- | ------------ |
| rendering artefact           | 9 / 9             | 8 / 7               | engine (`assembly_or_render`)                                                                                 | Q7           |
| invented or restating entity | 8 / 9             | 7 / 7               | entities step                                                                                                 | Q15, Q18     |
| weakened obligation          | 0 / 8             | 2 / 6               | story step only; FR weakening 0 of 15                                                                         | Q12 D12.2, Q19 |
| unsupported addition         | 4 / 4             | 4 / 6               | story step (hello-world timing, display surface, ordering); records step (loan-renewal AC-001 "records the renewal", 5 of 7) | Q18, Q19, §3 open problem |
| restatement                  | 1 / 4             | 3 / 5               | brief title (2), story (2), records (D12.1's statement records; an edge case repeating an AC)                 | Q18, Q19, Q11 |
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
build's rate from chance (H6, Q18). The story's modes behave the same way (Q19). Items
elsewhere cite these figures rather than repeat them.

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
   build-provenance roots (`build/provenance.zig:21`).
4. **Measurement set:** three runs of each development case (decided 2 November 2026), each
   approved, extended under rule
   6 to at most eight per case. Every attempt counts. Nothing is tuned on the reserved
   qualification features. A run costs about 15k tokens (hello-world) to 20k (loan-renewal).
5. **Evaluation and measures:** `zig build e2e-measures` and `/evaluate-e2e` for every run.
   - Defect classes are those of the evaluate-e2e skill (§2), counted over native publications
     beside the publication rate per case.
   - Each repair is graded helpful, neutral, harmful or no progress.
   - Brittleness counts: T5.
6. **Keep or revert** (the default recommendation; the user decides).
   - **Before the set,** record:
     - targets: published-output defect classes, as event counts with unit, opportunity and
       direction; cost is reported, never a target;
     - guards: lost source requirement, unsupported addition, a critical criterion below its
       minimum, harmful repair, publication rate per case;
     - the run maximum.
   - **Improvement:** the pooled target count improves under a one-sided conditional binomial
     test at p ≤ 0.10, and doesn't worsen in either case that shows the class.
   - **Guards:** no guard count rises under the same test, the publication rate per case
     doesn't fall, and no class absent from the reference appears with an `established` trace
     to the changed owner. Hygiene phases (Q4 retry, Q5, a withdrawal in Q8) are kept on
     guards alone plus their **Keep if** measures.
   - **Sampling:** look after three runs per case, then extend by two or three with approval;
     never sample until a preferred answer emerges.
   - **Evidence floor:** fewer than about ten events across both states, or undecided at the
     maximum, is "not enough evidence". A target absent from both states of a case is "benefit
     not demonstrated".
   - Aggregate and criterion scores decide nothing alone. Say "kept", never "accepted".
7. **Reference:** the last kept measured state (§1).
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

**Proposed amendments (H6.1–H6.4, not decided):** a screening step before rule 4's set, one
evaluator version per comparison under rule 5, guard handling under rule 6 and a per-call
pooled reference under rule 7.

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

**Next** (each needs its decision or approval first):

1. **H6** measurement-method decisions (§7), with **T6** (§6).
2. **H1** adjudication (§7), before any §2.12 item strands the retained v14 runs.
3. **Q12 D12.2** keep or revert (§4 Q12).
4. **Q18 D18.1** and **Q19 D19.1** (§4).
5. **Q15 D15.1** revisit (§4 Q15) and **Q14 D14.1** re-decision (§4 Q14).

**Output track** (recommended order; each needs its decision first):

| Rank | Item | Defect class reduced (since D12.1: hello-world of 8 / loan-renewal of 7) | Effort | Validation | Decisions |
| --- | --- | --- | --- | --- | --- |
| 1 | **Q18** optional families and entities only from typed source claims (would absorb Q15) | invented or restating entity (7 / 7); edge-case and statement additions and restatements (loan-renewal edge cases in 4 of 7) | L | Then a set (H6 screening first, if adopted) | D18.1 |
| 2 | **Q19** the primary story | weakened obligation in the story (2 / 6); story additions (hello-world 4 of 8) | S–M | Measurement set (structural screening can't measure prose, H6.1) | D19.1 |
| 3 | **Q12 D12.2** generated fields receive obligation strength (built) | weakened obligation in the story (2 / 6; its set 0 of 4 / 1 of 5) | S | Set ran 2 November | D12.2 keep |
| 4 | **Q17** principles as records-call context (decided) | none scored; guards only unless the rubrics gain a principle criterion | M | Measurement set | D17.1 |
| 5 | **Q7 D7.5** a plain string only where a field offers no insertion | rendering artefact (1 joined-fragment story in 18 reference) | S | Measurement set | D7.5 |
| 6 | **Q14 b3** scenarios bound to their claim by the engine | lost source requirement (0 / 0; reference loan-renewal 3 of 9) | L | Measurement set | D14.1 re-decision |
| 7 | **Q7 D7.2** withdraw ADR 0045, keep ADR 0036 Decision 6 | none directly (docs) | S | None | D7.2 |

**Robustness track** (run completion and budget; no scored defect): E5's §22.6 correction
location. D13.1 removed the review calls where every runaway and SyntaxError of 31 October
occurred and where the budget ran short (lowest headroom 1,481 tokens): the D12.1, D16.1 and D16.2 runs
used 7,213–67,448 of 125,000 tokens. Run failures since D12.1 are exhausted retries: the
records call on `shared_member` twice (D16.1; D16.2 amends it) and reconciliation
dispositions on `missing_member` once (`2026-11-02T02-29-06Z`, an unchanged step).

**Build order, as decided** (each change set measured on its own committed build, §2.1 and
§2.3; completed change sets are in [Z_FIX06](Z_FIX06.md)):

1. Q12 D12.2's keep decision (committed in `388438e`; its set ran 2 November).
2. Q17 principles as records-call context, a measurement set (D17.1: after D12.2).
3. Q14 b3, a measurement set, unless D14.1 is re-decided (§4 Q14).
4. Q7 D7.5, a measurement set.

**Recommended changes to the order (not decided):** H6's adopted parts and T6 before the next
set; Q18, if D18.1 is approved, before Q17 (§4 Q17); Q19 as D19.1 decides; Q4's retry after
D7.5.

**Recommended, not yet decided:** H6 as each of its decisions recommends (§7); D12.2 kept,
with its watch items (§4 Q12); D18.1 yes, which would replace Q15's revisit (keep D15.1 as a
model limitation if D18.1 is declined); D5.1 no; D8.1 keep, record only; close D2.2, D11.3, Q9
and W5; hold Q14 b3 until lost source requirement recurs; H1 before any §2.12 item (E1, E4, E5,
E9) lands (§7 H1). D19.1 has no recommendation (§4 Q19).

**Engine track, in gaps:** E2 early; E3 after E2's first measure (nothing technical ties
startup to E1); E1 in any gap, retaking its freeze on the commit before it lands; E6 and E8 in
any gap; E4 after E1, E2's measure and Q9's capture replays (ADR 0033:264); E5's closed
reasons with the E1–E4 conversion that rewrites them, its evaluator gap in any gap; E9 with
E1, E4 or E5; R-A1 after E1; E7 last. E0 is on hold. E1, E4, E5 and E9 land only under §2.12.
E1–E4 before the closing set is the user's call (ADR 0034:100-104). **Tests:** T2 and T3 in
any gap; T4 with E1–E4; T6 with H6. **Human:** H1 for every set; H2 when required source review
is labelled or review returns; H3 when the user reviews the panels; H4 before any formal
baseline freeze; H5 at the user's choice; H6 before the next set. **Closing set:** repeated
runs of both cases on one committed, unmodified build (ADR 0034:64-65) unless the user amends
ADR 0034; every counted published run adjudicated (H1).

**Open problems without an item.** Each stays until a structural lever with an owner is found
or the user records it as a model limitation.

- **Unsupported additions in the story and records calls.** Since D12.1 the hello-world story
  adds timing ("immediately"), a display surface ("on the screen") or an order ("followed
  by") in 4 of 8 publications, and loan-renewal AC-001 adds that the system records the
  renewal in 5 of 7 (4 of 9 in the reference). The invented trigger "The user launches the
  application executable." (5 of 17 hello-world publications from Q1b to 31 October) hasn't
  recurred; one unscored variant did (`2026-11-02T00-05-04Z`). The `given` purpose forbids
  invented prerequisites (`packet-guidance.json:23`), the `when` purpose (`:24`) doesn't.
  Edge cases, entities and statement families now have a proposed structural lever (Q18), and
  the story's content is D19.1's; AC wording ("records the renewal") has none. Recommended:
  give the no-invention instruction one owner across the scenario clauses
  (`packet-guidance.json:23`, `records.prompt.md:8`, `generation.context.json:4`) inside a
  hygiene change (screened first if H6 is adopted); after Q18 and Q19, report the remaining AC and story
  elaboration as a model limitation (AGENTS.md) and let H1 judge it.
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
token classifications. D9.1 must keep the binding in any combined schema.

**D2.2 — deferred 30 October 2026** (user decision): a generic revalidation guard rejecting a
replacement that loses an exact-value occurrence or a claim ID the old value had, unless the
authorized defect concerns it (amends §22.4). The dispositions insert that motivated
reopening it is deleted by D2.3, and no repair ran in the 18 runs of 31 October.
**Recommended:** close as record only.

### Q4. Remove engine vocabulary and schema-stated rules from prompts (retry)

The first attempt was not kept ([Z_FIX06](Z_FIX06.md)). 12-model-boundary.md:408-409 and
ADR 0016:151-152 say "FIX06 Q4 removes them", so the retry keeps the ID. No published spec
from 29 to 31 October contains engine vocabulary (0 in the 18), so this is AGENTS.md
compliance, not an output target.

**Proposed extension of D4.1** ([Z_FIX06](Z_FIX06.md); not decided): the rule covers native
rule and correction texts too, and a sentence that says what a field, claim or response
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
extraction requests screened first if H6 is adopted (the first attempt broke hello-world
extraction). **Keep if**
engine vocabulary stays absent and corrections, rejections, defect classes and cost stay
within the comparison point's range. Never rename a field to chase a leak. **Recommended:**
settle D4.1's extension first.

### Q5. Remove unmeasured single-run sentences

- `extraction.context.json:4` (`claims`): "Include meaningful identity and purpose headings."
  and "Separate independent behavior, implementation and verification facts."; the second
  sentence of `business`, `technical` and `validation` (`:6`, `:8`, `:9`).
- `support.prompt.md:8-9` (", including compatible requirements labelled conflicting";
  "Empty claims or conflict labels do not establish a source gap.") and `:22`.
- `records.prompt.md:7-8`: "Do not relabel positive requirements as assumptions or non-goals".
- `packet-guidance.json:4`, `:7`, `:9` (title, persona, displayed values); open whether ",
  and an explicit declaration of absence is unnecessary" (`:9`) goes too.

**D5.1** (open): remove them together as one change set; amends 17-specify.md:197-199 and
12-model-boundary.md:793-795 (`:943-944` is an admission rule, likely not amended). Risk:
Q4's one-sentence change to the same context coincided with hello-world publishing 1 of 6.
No defect is traced to any of these sentences. **Recommended (not decided):** no; reopen a
sentence only when a defect is traced to it. **Keep if** `unsupported_addition`,
`invented_or_restating_entity`, clarification and blocked outcomes, and the guards don't
worsen.

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
- **B. Plain value in an entity meaning** (20 in 14 reference publications; 5 bare in 3, ADR
  0045's case): the field bars exact copies (`text_field_policy.zig:59`;
  `specification_provenance.zig:227-232`, `:281-284`, `:304-318`). All 20 sit on lines
  scored as invented or restating entity.
- **C. Fragments joined without a separator** (1 of 18; 2 of 25 retained story calls): the
  schema keeps the fragments option when no reference is offered
  (`model_result_schema.zig:230`, `:328-351`; `model_text_field.zig:174-189`, `:228-251`),
  and fragments join with no separator (`model_candidate_json.zig:251-253`, `:269-282`).

- **D7.4** (implemented, [Z_FIX06](Z_FIX06.md)): decided 1 November 2026, D7.4 is not a
  punctuation rule (AGENTS.md "Prose heuristic").
- **D7.5** Where a field offers no inserted reference, its schema offers only the plain string
  (`model_text_field.zig:174-190`; `textContract`, `model_text_wire.zig:277-292`). Contracts:
  07-domain-representations.md:74-80, ADR 0006:302-316, 12-model-boundary.md:1140-1141,
  text-field-composition.md:20-21; whether this is an amendment or a conformance fix (07
  already ties fragments to "composition around typed insertions") is the user's call. Schema
  bytes change in every generation request (0 passive literals in the retained runs), so a set
  (screened first if H6 is adopted). Verified: admission validates the response against the
  same selected schema the model
  receives (`admit_model_response.zig:19-21`; `model_request_preparation.zig:27`, `:92-99`)
  before the codec runs (`model_candidate_handoff.zig:24-32`), so a fragments object against a
  plain-string field fails as `type_mismatch` with a protocol correction. Effort S: `walk` in
  `model_text_field.zig`, its tests, and the 9 `insertion-presentation` calibration requests
  with the sha256 pins in their `prepared/plan.json`; `generation.context.json:2` still
  describes fragments. **Keep if** no fragments object appears where no reference is offered
  and publication, admission rejections, protocol corrections, runaways, unsupported addition
  and restating entity don't worsen.
- **D7.2** Decide ADR 0036 Decision 6 and ADR 0045 (on hold) together. Even with D7.4, ADR
  0045 would double a quoted entity value that ends in terminal punctuation, which is every
  retained case (5 of 7); it would fix the bare values. Since D13.1 and D12.1 no request
  carries an entity's spans, so its "model-facing … unchanged" claim (0045:44-46) holds.
  **Recommended (not decided; edits accepted ADRs):** keep Decision 6, which turns the model's
  backticks into one code span, and withdraw ADR 0045, docs only, removing its hold sites
  (0045:3-5, 0020:21-22, 0036:41-43, design.md:1157).
- **Not recommended:** typed exact-value references inserted by the model (ADR 0020 replaced
  them after 4 of 5 hello-world runs failed, and the model's quotes would still double);
  removing the model's quotes (rewrites model bytes); a prompt asking for no quotes.
- **D7.3** Whether a token inside a claim must sit on the recognition boundary to force a duty
  (`CTIV` in `ACTIVE`, `structured_token_test.zig:45`, `:56`). Owner
  `exact_token_obligation.zig:11-31`; amends ADR 0024:33-35 and ADR 0036 Decision 5. The
  boundary alone would drop real duties (a link destination, `exact_value_boundary.zig:120`; a
  code span with a suffix, `:136`). Option needing IDs only: force a token only from a claim
  that cites its own occurrence. Decided offline with accepted and rejected fixtures and
  byte-identical requests; no set can exercise it. **Recommended:** record until a live case
  shows it.

Boundary tables (`exact_value_boundary.zig`) are never extended case by case. A boundary
rejection is silent (`exact_value_recognition.zig:109`), so no set can count it by reason.

### Q8. Source-claim granularity (B7)

**Defect:** restatement and claims lost in reconciliation when citations repeat. The list-item
split (`reference_extraction_text.zig:144-183`) fired in 13 of 40 first extractions and gave
the same claims as per-item citations; no current-build run repeated a citation set. On Q4's
reverted build loan-renewal repeated `[5,6,7,8,9]` and failed (`2026-10-31T02-52-34Z-b671…`,
`02-54-32Z-8be8…`, `03-01-37Z-7c6a…`).

- **D8.1** Keep, change or withdraw ADR 0036 Decision 3 and ADR 0038 Decision 4. A withdrawal
  must keep scenario coverage, now of FR, BR, UO and PB claims (ADR 0038:65-71), and rewrite
  the `citations` sentence (`extraction.context.json:14`). **Recommended (not decided):** keep,
  record only. If changed, T5 first defines claim counts and claims lost in reconciliation,
  then a set on an experiment and the main build; **keep a withdrawal if** claims lost and
  restatement don't worsen, conditions stay with their items and scenario coverage doesn't
  fall.
- **D8.2** Whether "cites in full" (ADR 0036:126-130) covers a fenced block whose first or last
  interior line is blank (`markdown_code_spans.zig:53`, `:59`;
  `exact_token_obligation.zig:40-45`; `source_selections.zig:57-60`). No fixture covers it.
- **D8.3** Whether same-category claims on the same cited lines are one claim (precedent
  16-reference-ingestion.md:254-262), including claims inserted by source-omission repair; a
  same-lines pair with different categories needs its own answer.

D8.2 and D8.3 are decided offline with fixtures at their owners and §2.10 projections, in any
gap, or recorded.

### Q9. Reconciliation call structure (W4)

Reconciliation was 4–9% of a published run's tokens on 31 October; combining dispositions,
signals and conflicts saves at most two sends and reduces no defect class. **D9.1** (combine
only on capture-replay evidence) amends ADR 0022, §16.4 step 10, ADR 0016's assignment
contexts and ADR 0033's per-phase owners. **Recommended (not decided):** close Q9. The capture
replays E4 needs (ADR 0033:264) must be `model-request-debug/v16` captures
(`model_request_description.zig:5-10`); earlier captures no longer decode.

### Q11. Story-restatement deletion

**D11.3** ADR 0035: never delete a covered restatement whose claims no other record names (the
user confirms that claim IDs are the reading of "last mention"). Only a story restatement can
do that (`restatesStory`, `specification_generation.zig:334-339`, called from
`specification_session.zig:621-623`); D16.2's `repeated_statement` deletes only a record
whose every claim another record names. `restatesStory` hadn't fired since `8a600d7` in the 54
runs retained before 31 October, and no restatement deletion appears in the 36 runs retained
on 31 October. Since D12.1 one story repeats its single FR (`2026-11-02T02-27-58Z`); deleting
that FR would lose its claims. **Recommended (not decided):** close as record only.

### Q12. Copied and weakened obligations

**Defect:** weakened obligation. Reference: loan-renewal 8 of 9 publications (15 of 16 since
Q1b), by a copy route (removed by D12.1, [Z_FIX06](Z_FIX06.md)) and a story route. Since D12.1
no FR weakens an obligation (0 of 15); the story weakens "must" in 6 of 7 loan-renewal ("may
renew") and 2 of 8 hello-world ("should also output") publications, from story requests
byte-identical across the D12.1, D16.1 and D16.2 freezes.

- **Story route.** The story request (call 8) receives the claims verbatim ("must be able to
  renew") and no drafts. Before D12.2 the FR field purpose named obligation strength
  (`packet-guidance.json:15`) and FRs kept "must"; the story and description purposes (`:7`,
  `:5`) didn't.
- **D12.2** (approved 1 November 2026) gives obligation strength one owner that every
  generated field receives, `generation.context.json`'s `business_value`. Implemented 2
  November 2026 and committed in `388438e` ([Z_FIX06](Z_FIX06.md)); the story and FR purpose
  edits also reach pre-generation source-review and source-loss requests as subject
  descriptions. Left for a later hygiene change (the user's call): `generation.prompt.md:2`
  and `packet-guidance.json:27` still restate the context's "conditions and obligations". A
  separate change set from D12.1 (§2.1). **Keep if** the story's weakening
  falls, FR weakening doesn't rise (FR's wording owner moves) and unsupported addition and
  restatement don't rise.
  - **Set, approved 2 November 2026** (user: "approved"; recorded before it runs, rule 6):
    target, story weakening of an obligation, events per publication, direction down, pooled
    over both cases; guards, FR weakening, unsupported addition, restatement, lost source
    requirement, a critical criterion below its minimum, harmful repair, publication rate per
    case; run maximum three per case, extended by two or three with approval to eight.
  - **Baseline, decided 2 November 2026** (same approval): the story-weakening target compares
    with the 15 publications since D12.1 (hello-world 2 of 8, loan-renewal 6 of 7), whose
    story requests are byte-identical across the D12.1, D16.1 and D16.2 freezes; the guards
    compare with the reference, the D16.2 set (§1).
  - **Set result** (2 November 2026; ten runs `2026-11-02T09-15-27Z` to `09-33-46Z`, five per
    case after one approved extension, on source `bacfcd9ae368…`, `modified` true; measures
    in `evaluations/e2e/<run>/measures.json`, the first six summarised in
    `evaluations/d122-measures-set.json`):
    - publication: hello-world 4 of 5, loan-renewal 5 of 5. `09-15-31Z` ended
      `workflow_invalid`: extraction returned `no_feature_claim` (an unchanged request), then
      the pre-generation story review returned a false `candidate_omission` from a request
      differing from `02-28-14Z`'s only by D12.2's story purpose, and `repair-source` found no
      upstream producer. Plausibly D12.2, not established (one pair, temperature 0.1);
    - target, story weakening: 8 of 15 → 1 of 9 (hello-world 2/8 → 0/4, loan-renewal 6/7 →
      1/5), p = 0.093; 9 events, at the evidence floor. Three hello-world stories are
      byte-identical to pre-D12.2 stories;
    - guards against the D16.2 set (5 publications → 9): unsupported addition 6 → 19 (1.2 →
      2.1 per publication, p = 0.16; loan-renewal 4 → 16, p = 0.08 alone, with new story
      additions in `09-33-44Z` and `09-33-46Z`); restatement 3 → 5; FR weakening 0 → 0; lost
      source requirement 0 → 0; critical criterion below minimum 1 → 3 runs (loan-renewal
      source-grounding, p = 0.55); harmful repair 0 → 0;
    - advisory scores: hello-world 89.3, 92.9, 100, 92.9; loan-renewal 89.3, 78.6, 89.3,
      78.6, 78.6.
  - **Story modes in the set:** loan-renewal "may renew" (`09-15-30Z`), the five source lines
    joined with no separator (`09-15-27Z-d2ee…`, `09-15-32Z`) and invented steps
    (`09-33-44Z`, `09-33-46Z`; "logs into the library system and selects an active loan",
    "updates the loan record"), each a scored defect (Q19). The invented-steps mode appears in
    no earlier evaluation: it is new in the field whose purpose D12.2 changed.
  - **Loan-renewal unsupported additions by field, D16.2 → D12.2:** story 0 → 4, edge case
    2 → 6, AC 2 → 4, entity 0 → 2. Edge cases (4 of 5 publications against 1 of 3; §1 swing
    factors) explain at most 4 of the 12 added events; the story's new mode explains 4.
  - **Keep if, read:** story weakening fell (9 events, "not enough evidence" under rule 6's
    floor); unsupported addition rose 6 → 19 and restatement 3 → 5, neither significant
    (pooled p = 0.16); FR weakening didn't rise. So the **Keep if** is not met as written.
  - **Decision (open): keep or revert D12.2.** **Recommended (not decided):** keep under
    AGENTS.md's one owner per instruction, with two watch items for the next set: the story's
    invented-steps mode and the story-review failure. If the next set shows the story's
    additions again, revisit the story purpose (Q19).
- **Not recommended:** a typed obligation-strength field (07-domain-representations.md:160
  forbids a duplicate modality field; making it matter needs a word check or engine-rendered
  modal text).

### Q13. Inline source lines

D13.1 (post-generation reviews removed) and the inline source lines are in
[Z_FIX06](Z_FIX06.md). Reopen link checks, in shadow mode, only if adjudication shows semantic
defects that the generation-side items (Q12, Q14, Q15, Q18, Q19) leave. **D13.4** (decided 1
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
  semantic checking rests on human adjudication (H1).

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

**D14.1 decided 1 November 2026:** b3 (Q13's link checks won't exist after D13.1). **Keep if**
lost source requirement falls and publication and exhausted runs don't worsen. **Decision
(re-decide D14.1):** the class is absent since D12.1, and the change set is kept, so the
reference has none and a set could show only "benefit not demonstrated" (§2 rule 6).
**Recommended (not decided):** hold b3 and reopen it when lost source requirement recurs.

### Q15. Entity applicability and restating meanings (B6)

**Defect:** invented or restating entity in 17 of 18 reference publications and 14 of 15 since
D12.1. Hello-world, which has no data, was judged `required` in 8 of 9 reference and 7 of 8
later publications, with names taken from the source title; loan-renewal's meaning restates
the behaviour in 9 of 9 and 7 of 7, and its relationship names no other entity or one no
record defines. The entities request (call 9) gets every source group, the full source and the
brief (`specification_session.zig:257-265`, `:300-313`), never the story or records. Every
claim in the 18 reference runs has category `business`, so no typed fact distinguishes a data
concept. `checkConsistency` and ADR 0035's `statement()` skip entities
(`specification_session.zig:547-564`; `specification_generation.zig:324-329`).

- **Lever 1:** when an entity meaning equals a single-statement record or the story after
  resolving exact copies, delete the entity and set `not_applicable`. It matched 7 of the 18
  reference publications (all hello-world), because FR-001 copied the entity basis; since
  D12.1 it matches 0 of 15. It is also blocked: repair may not change the decision
  (22-repair.md:269-273) and ADR 0035 exempts entities (0035:48-49, :88-89). It would amend
  ADR 0035 Decision 1, 22-repair.md:269-273, 17-specify.md:226-227 and F0100:1131-1133.
- **Lever 4:** a typed data-concept fact at extraction or reconciliation that entities must
  cite. Changes every extraction request and depends on intent.md's unaccepted
  smaller-decision shift.
- **Not recommended:** typed relationship targets (remove no defect; may induce a second
  invented entity).
- **Hypothesis, not testable offline:** requiring every entity basis to cite a group may bias
  the model toward `required`. The rule is enforced three times (`generation.schema.json:178-180`,
  `:563-583`; native, `specification_generation.zig:300`; 07-domain-representations.md:161)
  and applies to both decisions. It was constant across every evaluated build, while
  hello-world's `not_applicable` rate moved from 0 of 15 (19–27 October) to 4 of 16 from Q1b
  to 31 October, so it didn't cause that shift. Testing its own effect needs repeated live
  runs with the citation optional, which amends 07-domain-representations.md:161 and the
  native check.

**D15.1 decided 1 November 2026:** entity applicability is recorded as a model limitation for
now; revisit on D12.1's results. **Revisit due:** D12.1 removed lever 1's signal and the class
is unchanged; only lever 4 remains, and it depends on intent.md's unaccepted shift. The entity
is one of §1's two swing factors. **Recommended (not decided):** fold Q15 into Q18, whose
D18.1 generalises lever 4 to every optional family; if D18.1 is declined, keep D15.1.

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
  with guards on unsupported addition and invented entity.
- **Target and risk:** no current rubric criterion scores principle consistency, so a set can
  show only guards (unsupported addition and invented entity from principle text,
  publication) unless the case rubrics gain a criterion. Amends ADR 0015 (0015:10-15 already
  names D17.1), ADR 0023 "Principles" (0023:149-159), 17-specify.md's generation inputs
  (:264-284) and F0100.
- **Sequence (recommended, not decided; D17.1 places it after D12.2):** after Q18 if D18.1 is
  approved, screened first if H6 is adopted. It adds about 7k
  tokens of generic principle text to the call that writes most edge-case and statement
  additions, and the loan-renewal rubric's proportionate-scope criterion penalises
  principle-derived prescriptions, so before Q18 its guards can't be read.

### Q18. Optional sections only from typed source claims

**Defect:** unsupported addition, restatement and invented or restating entity in record
families and entities the source supplies nothing for. They decide most of the spread between
sets (§1 swing factors).

- **Evidence** (advisory evaluations since 29 October; the field read from each defect's
  description, so approximate): of 59 unsupported additions, AC 20, story 15, edge case 13,
  entity 4, other statements and the brief 7, FR about none; of 51 invented or restating
  entities, 50 in the entity. Edge cases ("renew a loan exactly on its due date", "has already
  been renewed and is now overdue") and hello-world's `required` entity are §1's swing factors.
  Without D16.1's "at most one" sentence (D12.1 alone) the records call wrote business rules,
  outcomes, assumptions, non-goals and prohibitions, all scored as restatement or invention
  ([Z_FIX06](Z_FIX06.md) Q16).
- **Cause:** every records batch's schema offers every family but `entity`
  (`record.content.oneOf`, `generation.schema.json:429-459`; the per-batch exclusion,
  `specification_session.zig:205-217`, is the owner the lever extends), and the entities unit
  always decides applicability. The only controls are words, "optional
  families need no filler" (`records.prompt.md:6`) and "Do not invent decisions"
  (`generation.context.json:4`), and nothing native can check "supported content"
  (F0100:1069; 17-specify.md:133-142). GPT-OSS-20B at low reasoning effort fills an offered
  slot at a rate that moves with the request bytes.
- **Lever (proposed):** extraction already gives each claim a closed `category`
  (`extraction.schema.json:109-118`; meanings at `extraction.context.json:5-13`, among them
  `implementation_assumption` and `scope_guard`; 16-reference-ingestion.md:188-191). Extend it
  with the kinds the optional families need, for example boundary or exception, data concept,
  rule and prohibition. A records batch's schema then offers FR and AC always and an optional
  family only when an assigned claim carries its kind; the entities unit runs only when a claim
  is a data concept, and otherwise `not_applicable` is native with that basis. Generalises Q15
  lever 4 to every optional family; typing one source line is intent.md's smaller decision
  (design/intent.md:82-105).
- **Amends:** 17-specify.md §17.3 (:92-104, :201-233), F0100 §5.1 and §5.4 (:1069-1072,
  :1131-1133), 16-reference-ingestion.md's claim categories, ADR 0038 (families and scenario
  coverage), 07-domain-representations.md:161, `extraction.context.json` and
  `packet-guidance.json` `record_families`; it adopts intent.md's shift for this purpose.
- **Validation:** `/preflight`; accepted and rejected tests at the schema owner (no boundary
  claim, no `edge_case` variant; a data-concept claim runs the entities unit; an unknown kind
  rejects); an unrelated-domain fixture whose source states a boundary and a non-goal; the
  §2.10 projection (every extraction, records and entities request changes); then a set, with
  the extraction call screened on both cases first if H6 is adopted.
- **Keep if:** unsupported addition and invented or restating entity fall; lost source
  requirement doesn't appear (a stated boundary, rule or data concept typed as plain behaviour
  loses its section); publication and extraction `no_feature_claim` don't worsen.
- **Risk:** extraction moves with request bytes (Q4's first attempt: `no_feature_claim` in 5 of
  6 hello-world runs), and typing is itself a model judgment. The whole-feature entity decision
  says `required` for hello-world in 22 of 29 publications, so per-line typing must be shown
  better, not assumed.
- **Decision D18.1:** should an optional section appear only when a source line has first been
  typed as its kind? Today loan-renewal's records call adds edge cases such as "renew a loan
  exactly on its due date" in 11 of 27 publications, and hello-world gets an entity such as
  "HelloWorldApplication" in 22 of 29. Yes: one ADR; every extraction request changes; a set;
  intent.md's smaller-decision shift is accepted for this purpose; and a native
  `not_applicable` from the absence of a data-concept claim replaces F0100's rules that an
  empty `entities` collection can't prove the feature has no business data and that a missing
  section is never a supported non-applicability fact (F0100:1131-1138). No: those sections
  stay per-run outcomes, recorded as model limitations. **Recommended (not decided):** yes.

### Q19. The primary story

**Defect:** weakened obligation (26 of 30 weakenings since 29 October are in the story, by the
field each defect names), unsupported addition (15 of 59) and restatement in the primary story.

- **Evidence:** the story is mandatory (F0100:1068), and its purpose asks for "One narrative
  describing the actor or system identified by the source, its action and intended result"
  (`packet-guidance.json:7`). For a list of requirements, every loan-renewal story so far falls
  in one of three modes, each a scored defect: "A borrower may renew…" (weakened obligation);
  the five source lines joined with no separator (restatement and rendering artefact C, Q7
  D7.5); and "A borrower logs into the library system and selects… updates the loan record"
  (unsupported addition). The D12.2 set shows all three on one build (Q12). Hello-world's story
  adds timing, a display surface or an order in 4 of 8 publications since D12.1 (§3).
- **Decision D19.1:** may the primary story restate its source's requirements in one paragraph,
  adding nothing? Example: "The application must start successfully. When started, it must
  display "Hello, World!" and also output the date and time in UTC." The question covers every
  source, not only requirement lists: no typed fact tells a list from a narrative today. Yes:
  the story can be composed from its assigned claims' text, so it can't weaken or add; it
  amends F0100 §5.2's "Main user journey", the story purpose and evaluate-e2e's `restatement`
  definition (`.claude/skills/evaluate-e2e/SKILL.md:67`), the comparison point is re-scored
  under the new definition so restatement doesn't fall by definition alone, and a later
  `/preflight` settles how the story is composed. No: the story keeps needing content the
  source lacks, and after Q18 its remaining
  elaboration is reported as a model limitation (AGENTS.md). **No recommendation:** it decides
  what the story is for; the evidence shows only that every mode so far is a scored defect.

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
and may publish); add a test that a pre-E0 v14 report still decodes; flip the scenarios
asserting no publication (`test/integration/workflow_tests.zig:2440`, `:2257-2265`;
`test/harness/integration/tests.zig:1741-1742`, `:1763-1772`); register
`run.incomplete_published` through `adrRequired` (`src/domain/log_event_registry.zig:99-105`,
test `:162-168`). The amendment notes of ADRs 0009 (:15), 0011 (:46), 0017 (:7), 0037 (:11)
and 0039 (:31) state ADR 0041's effect without the hold; aligning them is a policy edit. If
ADR 0041 is withdrawn, v14's `incomplete_publication` (e2e.md:367) and the measures'
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

### E2. Stage actions (A2, ADR 0031) and identical sibling steps (W5)

Not started: convert `prepare-toolchain` (`spec.workflow.yaml:173-202`) first and record ADR
0031's measures (:364-366) before another stage. **DE2:** confirm ADR 0031's derived choices
1–3 and 6–8 (:270-299), including whether choice 7's offline evidence replaces the live run.
**W5: recommended closed, record only** (user decides): D13.1 deleted `candidate-gaps`, so one
pair remains (`finish-native` / `finish-model`, both calling `finish-extraction-response`,
`spec.workflow.yaml:339-344`), and by reading the merged step wouldn't pass the join check
(`workflow_data_flow.zig:69-70`).

### E3. Engine routines (A3, ADR 0032)

Not started. Convert startup first and measure it (ADR 0032:144-151). Feature logging waits on
its preconditions (:152-172): no test covers cancellation under a log lock, and the
policy-transition coordinator waits on E6's §14.10 decision. **DE3:** confirm ADR 0032's
derived choices 1–8 (:224-243), including offline evidence; can be asked with DE2.

### E4. Generic repair operations (W3, ADR 0033)

After E1, E2's measure and Q9's capture replays (see §3): all Specify owners in one change on
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
a model-authored exact handle that models can't author since `dfae959` (ADR 0020:233).
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

### T6. Structural counts in the measures (H6)

Count each records response's records by `content.kind`, and each entities response's
`disposition`, from the response's discriminator and arrays as `recordsCount` already counts
the records array (`test/harness/e2e/measures.zig:24-25`, `:170-184`): structure, never prose.
They are §1's two swing factors and need no evaluator. Two owners, one counting function:

- **Runs:** `e2e-measures`, whose new members need a new `e2e-measures` version
  (design/harness/e2e.md:682).
- **Replays (H6 screening):** `e2e-call`'s report (`call-diagnostic-report/v2`,
  `test/harness/call/report.zig:5`) records the counts per trial, which needs `v3` and an
  amendment of e2e.md:146-152 ("semantic validation and rubric quality assessment are not
  assessed" stays true: the counts are structure).

No engine or request change (§2.10). Tests at the owner, as for `recordsCount` (`:539-546`).

## 7. Human and decision track (H)

### H1. Adjudication (R8)

Only a human `human-spec-adjudication/v2` record applied with `zig build adjudicate-spec`
decides acceptance; none exists. Retained: the D12.1 (v12), D16.1 (v13), D16.2 (v14) and D12.2
(v14) sets. The current build decodes only v14 (`test/harness/e2e/contracts.zig:140`), so only
the D16.2 and D12.2 runs can be adjudicated from this checkout, and any later member change
strands them (§2.12). Every earlier run was removed and can't be adjudicated; v9 runs stay
unadjudicated (user decision, 27 October 2026). Needed for the ADR 0034 gate and adjudicated
measures. No adjudication has yet checked the evaluator's defect classes against the user's
judgment, although every keep decision so far rests on them (H6).

**Recommended (not decided):** adjudicate five contrasting publications before any §2.12 item
lands: hello-world with an entity (`2026-11-02T02-27-46Z`) and without (`09-33-43Z`);
loan-renewal with a "may renew" story and no edge cases (`02-29-15Z`), a joined-copy story and
one edge case (`09-15-32Z`), and an invented-steps story and two edge cases (`09-33-46Z`).

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

### H6. Measurement method (proposed amendment to §2 rules 4–7)

**Why:** a set can't separate a change's effect from a re-roll of the generation modes.

- The swing factors vary within sets of identical requests (§1). Sets are three to five runs
  per case, a rubric point is 3.57%, and the scorer moves on identical content (§1).
- Rule 6's test on about ten events reaches p ≤ 0.10 only for changes of about four times
  (D12.2's story weakening, 8 of 15 → 1 of 9, p = 0.093). With five to seven guards each at a
  nominal one-sided 0.10, the chance that some guard "rises" by chance in a set is up to about
  41–52% (lower under the discrete test).
- The evaluator changed between the 31 October reference and every later set (§1), and the
  current reference is five publications, two of them hello-world.
- FIX04 recorded the pattern on 16 October ("near-identical requests give opposite results",
  git `18a5ec8:fixes/FIX04.md:111-112`); FIX01 to FIX05 tried about 80 levers, reverted about
  15 and closed without a demonstrated output gain. FIX06's clearest output gain removed an
  input (D12.1, [Z_FIX06](Z_FIX06.md)), and removing calls (D13.1) ended runaways; moved
  sentences re-rolled outcomes (Q4's first attempt; git `371b55a:fixes/Z_FIX05.md:4129-4134`,
  `:4332-4340`).

Four separate decisions, each the user's:

1. **Decision H6.1, screening (rule 4):** should a change be screened with repeated single-call
   replays before a set decides it? Example: replay loan-renewal's records call ten times as
   captured and ten times with the change (`e2e-call --repeats 10`, then `--edit` with the
   change's bytes; design/harness/e2e.md:67-92), and compare edge-case counts. Each changed
   call kind the §2.10 projection names is screened on a retained v14 request from both cases,
   with the captured run's model and reasoning effort (§9: no model comparison). In
   `2026-11-02T09-33-46Z` a story call took 1,434 tokens, entities 2,298 and records 3,637,
   against 14.6k–18.5k per run. The screen measures only T6's structural counts: the
   evaluator can't score a replay (SKILL.md:4 takes runs only), so a change whose effect is
   prose (Q19's story, Q4) gains nothing from it unless the user labels replay outputs by
   hand. A screen decides nothing; the set on the committed build still decides (AGENTS.md).
   Yes: rule 4 gains the step, T6 is built first, and each replay batch needs approval. It
   reopens rule 4's 1 November decision, "no interleaved control run on the comparison
   point's build" (git `340261e:fixes/FIX06.md:72-74`), since an as-captured arm is a
   call-level control; the user says whether the screen supersedes it. No: decisions stay on
   three to five whole runs. **Recommended (not decided):** yes.
2. **Decision H6.2, guards (rule 6):** should one pre-stated target and the publication rate
   per case decide keep or revert, with the other guards (lost source requirement,
   unsupported addition, a critical criterion below its minimum, harmful repair) demoted to
   watch items unless they cross an effect size stated before the set, such as a doubling
   with at least five events? Yes: fewer chance reverts, but a real rise smaller than the
   stated size no longer blocks a keep; lost source requirement is the guard most at risk.
   No: every guard keeps blocking, and a set with several guards often shows a chance rise.
   **Recommended (not decided):** no for lost source requirement, which keeps blocking at
   any rise; yes for the others.
3. **Decision H6.3, one evaluator version per comparison (rule 5):** should a set and its
   reference always be scored on one evaluate-e2e version, re-scoring the reference when the
   skill has changed, with link-derived `unsupported_addition` counted apart? Example: the 31
   October reference (v2) re-scored under v3 before comparing it with D16.2. Re-scoring the
   31 October runs recovers rubric scores and defect classes from their numbered copies under
   `evaluations/e2e/`, but not the link check or defect origins, because their run
   directories and `reference-context.md` are gone. Yes: rule 5 changes. No: comparisons keep
   crossing skill edits. **Recommended (not decided):** yes.
4. **Decision H6.4, pooled reference (rule 7):** should each call kind's reference pool every
   publication whose request for that call is byte-identical to the current one, kept or not,
   as Q12's D12.2 baseline pooled the D12.1-alone, D16.1 and D16.2 sets for the story? Yes:
   larger references (15 publications instead of 5 for the story). No: the reference stays
   the last kept set. **Recommended (not decided):** yes.

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
helpful, and `09-15-31Z`, whose false `candidate_omission` ended the run (Q12).

### B7 contract-review leftovers

- Prior-state readback checks stored claim text against the text policy only
  (`reference_snapshot.zig:116-117`; ADR 0036:206-208); re-quoting needs the Unicode
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
"Q3" (ADR 0016:152); "Q1a, D1.2" (ADR 0038:147); "Q2" (ADR 0046:42-43); "T5(b)"
(`.claude/skills/evaluate-e2e/SKILL.md:57`); "DT5" (design/harness/e2e.md:689); "T5(a)",
"T5(c)" (`test/harness/e2e/measures.zig:1-2`); "T5(e)"
(`src/test_fixtures/request_projection.zig:1`, `test/integration/workflow_tests.zig:1311`);
"T5" meaning the measures, which FIX06's T5 no longer is (`e2e_measures.zig:1`,
`test/harness/e2e/measures_cli.zig:1`); "D10.2" (ADR 0023:27, ADR 0041:6; its record is in
git at `388438e`). Other retired IDs cited outside FIX06 haven't been swept since 1 November.

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
- Never batch or group source-review subjects (30 October 2026); this binds the remaining
  pre-generation source review.
- Measures and replays use the owning steps (`zig build e2e-measures`, `e2e-call`), never
  one-off scripts, loops or new tracking files (29 October 2026).
- Don't narrow the entity-name exception without a decision (B6; `text_field_policy.zig:60`,
  `:68-73`).
- Runaways stay a reported measure (ADR 0039).
