# FIX06 — Open Spec work

The only fix record: open work and user decisions not yet recorded in an ADR
([convention](README.md)). Each phase needs the user's approval before its changes, and
every live run needs its own approval; nothing here authorizes a code change, live call or
E2E run. **Decision** marks a question only the user settles; a recommendation is not a
decision. The governing design remains **Proposed design**. Implemented items are in
[Z_FIX06](Z_FIX06.md); earlier completed, closed and reverted work is in git history (last at
`194e29a`).

## 1. Gate status and output quality

**Gate (ADR 0034): not met.** No run is adjudicated (H1). Every retained run is on a tree
marked `modified`; the D2.3 set's captured build inputs equal commit `194e29a` byte for byte,
so whether it counts as "one committed build" (ADR 0034:64) is the user's reading. Only 7 run
directories remain under `zig-out/e2e-spec/` (the six Q10b runs and `07-37-18Z-61b3…`): the
other 29 runs of 31 October were removed at 22:19 that day, and the 26 October `39a06ea` pair
and the 26–29 October runs earlier. Their evaluations and measures remain under
`evaluations/e2e/`, but a removed run can't be adjudicated (H1). The user decides when Plan is
actioned.

Reference for quality phases (§2 rule 7): D2.3, the last kept measured state (kept 1 November
2026). It is 12 runs on `dac4c4c` plus its working tree, 31 October 2026; measures in
`evaluations/d23-12/measures-set.json` and evaluations in `evaluations/e2e/2026-10-31T07-*/`.
A change proved under §2.10 never moves it.

**Output quality, 31 October 2026** (advisory scoring of 18 publications against the case
rubrics, `evaluations/e2e/<run>/evaluation.json`; scorer judgment moves a score about ±3.6):

| Build                                    | Hello-world mean (range) | Loan-renewal mean (range)        | Below 80% |
| ---------------------------------------- | ------------------------ | -------------------------------- | --------- |
| Q1b and 8444312 (14 earlier evaluations) | 90.8 (82.1–100)          | 83.6 (78.6–89.3; 2 undetermined) | 1         |
| D2.3 tree (12 runs)                      | 89.9 (85.7–100)          | 86.3 (82.1–92.9)                 | 0         |
| Q10b tree (6 runs)                       | 89.3 (89.3–89.3)         | 82.1 (78.6–85.7)                 | 1         |

No change since Q1b has improved the published output. Defects per publication on the 18
runs, with the stage that produces them:

| Defect class                 | Hello-world | Loan-renewal | Producer                                                            | Item         |
| ---------------------------- | ----------- | ------------ | ------------------------------------------------------------------- | ------------ |
| rendering artefact           | 9 of 9      | 9 of 9       | engine (`assembly_or_render`)                                       | Q7           |
| invented or restating entity | 8 of 9      | 9 of 9       | entities step (model)                                               | Q15          |
| weakened obligation          | 0 of 9      | 8 of 9       | story step; 2 FRs copy the entity basis sent to the records request | Q12          |
| unsupported addition         | 4 of 9      | 4 of 9       | records step (AC triggers, coverage-driven outcomes, copied drafts) | Q12, Q14, §3 |
| restatement                  | 1 of 9      | 4 of 9       | records step (BR paraphrasing FR or source)                         | Q16          |
| lost source requirement      | 0 of 9      | 3 of 9       | records step (refusal scenario missing)                             | Q14          |

Post-generation review flagged 4 of the 47 non-rendering defects and passed 43 (Q13).

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

**Output track** (recommended order; each needs its decision first):

| Rank | Item                                                                         | Defect class reduced (publications of 18)                                                                                   | Effort                 | Validation                                                                    | Decisions     |
| ---- | ---------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- | ---------------------- | ----------------------------------------------------------------------------- | ------------- |
| 1    | **Q7 D7.4** render a model-quoted exact value without the engine's code span | rendering artefact, values ending without punctuation only (none in the development cases)                                  | S–M                    | Implemented, proven offline ([Z_FIX06](Z_FIX06.md))                           | D7.4          |
| 2    | **Q12 D12.1** records stop receiving the brief and entity basis              | weakened obligation in FRs (all 4 copied loan-renewal FRs), FR equal to an unpublished draft (9), copied additions (2)      | S                      | Implemented ([Z_FIX06](Z_FIX06.md)); measurement set outstanding              | D12.1         |
| 3    | **Q13** remove both post-generation reviews, then show source lines inline   | removes review's false findings, runaways and budget stops; inline lines reduce no class, but show every link to the reader | L (remove), M (inline) | D13.1 committed (`2b3dc8b`); inline lines implemented ([Z_FIX06](Z_FIX06.md)) | D13.1 decided |
| 4    | **Q12 D12.2** story and description purposes name obligation strength        | weakened obligation in the story (loan-renewal 15 of 16 since Q1b)                                                          | S                      | Measurement set (enough events)                                               | D12.2         |
| 5    | **Q14** scenarios bound to their claim by the engine                         | lost source requirement (loan-renewal 3 of 9)                                                                               | M (b2) to L (b3)       | Measurement set                                                               | D14.1         |
| 6    | **Q15** entity applicability and restating meanings (B6)                     | invented or restating entity (17)                                                                                           | M–H                    | Offline rebuild, then a set                                                   | D15.1         |
| 7    | **Q16** requirements own their claims                                        | restatement (5)                                                                                                             | M                      | D16.2 implemented; its set is next                                            | D16.2         |
| 8    | **Q7 D7.5** a plain string only where a field offers no insertion            | rendering artefact (1 joined-fragment story)                                                                                | S                      | Measurement set                                                               | D7.5          |
| 9    | **Q7 D7.2** withdraw ADR 0045, keep ADR 0036 Decision 6                      | none directly (docs)                                                                                                        | S                      | None                                                                          | D7.2          |
| 10   | **Q17** principles as context for Spec generation (decided)                  | none scored today; guards only unless the rubrics gain a principle criterion                                                | M                      | Measurement set                                                               | D17.1         |

**Robustness track** (run completion and budget; no scored defect): E5's §22.6 correction
location; budget headroom (H4). D13.1 removed the review calls where every runaway and
SyntaxError in the 18 runs occurred. Three loan-renewal runs on `ddbc6d9` stopped on the
workflow budget and published nothing; the lowest headroom in the 18 runs was 1,481 tokens
(`07-27-53Z-1098…`, 21,299 without its runaway).

**Decided 1 November 2026** (user: "apply best recommendations"): D2.3 kept; Q10b step 1 not
kept (superseded by D13.1); D13.1 removes both post-generation reviews; D7.4 is not a
punctuation rule; D12.1 and D12.2 approved; D14.1 b3; D15.1 recorded as a model limitation
for now; D16.1 deferred; D17.1 records call only; T5 definitions approved; H2 convention
adopted; the provider defect recorded; §2 rules 3, 4 and 13 settled.

**Build order** (each change set measured on its own committed build, §2.1 and §2.3):

1. T5 counts: baseline taken 1 November 2026 ([Z_FIX06](Z_FIX06.md)); each later change set
   retakes them (§6 T5).
2. D13.1: implemented 1 November 2026, committed by `2b3dc8b`. Its one live run per case
   ran on 1 November (`04-13-54Z-c834…`, `04-14-32Z-9eda…`, tree marked `modified`): both
   published, 10 and 12 sends, 14,633 and 26,263 tokens; advisory scores 85.7 and 89.3, and
   loan-renewal published a refusal scenario after an `uncovered_member` correction. Both run
   directories were removed the same day, so neither can be adjudicated.
3. Q7 D7.4 and Q13 inline source lines: implemented 1 November 2026, proven offline
   ([Z_FIX06](Z_FIX06.md)).
4. Q12 D12.1 with Q16: implemented 2 November 2026 as one change set; its measurement set is
   next (§4 Q16).
5. Q12 D12.2, a measurement set.
6. Q17 principles as records-call context, a measurement set.
7. Q14 b3, a measurement set.
8. Q7 D7.5, a measurement set; D16.1 and D15.1 revisited on the results.

**Recommended, not yet decided:** D5.1 no; D8.1 keep, record only; close D2.2, D11.3, Q9
(keeping the capture replays E4 needs) and W5.

**Engine track, in gaps:** E2 early; E3 after E2's first measure (nothing technical ties
startup to E1); E1 in any gap, retaking its freeze on the commit before it lands; E6 and E8 in
any gap; E4 after E1, E2's measure and Q9's capture replays (ADR 0033:264); E5's closed
reasons with the E1–E4 conversion that rewrites them, its evaluator gap in any gap; E9 with
E1, E4 or E5; R-A1 after E1; E7 last. E0 is on hold. E1, E4, E5 and E9 land only under §2.12.
E1–E4 before the closing set is the user's call (ADR 0034:100-104). **Tests:** T2 and T3 in any gap; T4 with E1–E4. **Human:** H1 for every set; H2 only if review
returns; H3 when the user reviews the panels; H4 before any formal baseline freeze; H5 at
the user's choice. **Closing set:** repeated runs of both cases on one committed, unmodified
build (ADR 0034:64-65) unless the user amends ADR 0034; every counted published run
adjudicated (H1).

**Open problems without an item.** Each stays until a structural lever with an owner is found
or the user records it as a model limitation.

- **Invented AC triggers** (unsupported addition): "The user launches the application
  executable." in 5 of 17 hello-world publications since Q1b; no request from calls 7–10
  contains "executable" or "launch". The `given` purpose forbids invented prerequisites
  (`packet-guidance.json:23`), the `when` purpose (`:24`) doesn't. Recommended: give the
  no-invention instruction one owner across the scenario clauses (`packet-guidance.json:23`,
  `records.prompt.md:8`, `generation.context.json:4`) inside a hygiene change; at this rate
  a set can't decide it alone.
- **Repair requests without step guidance:** six repair sites take their task only from the
  three-line `repair.prompt.md` (`spec.workflow.yaml:376`, `:413`, `:610`, `:816`, `:899`,
  `:914`), and the two reconciliation repairs bind no context. Binding definitions (Q2) wasn't
  kept; counted as a brittleness measure (T5).
- **Provider doesn't enforce the response schema:** the engine's request matches AWS's
  documented Converse shape (`outputConfig.textFormat` json_schema,
  `src/adapters/provider/bedrock_request.zig:74-77`; schemas within the documented limits),
  and the gpt-oss-20b model card lists structured outputs as supported. Yet Bedrock's raw text
  block (not engine extraction, `bedrock_response.zig:135-149`) opens with a fragment and
  restarts the JSON in 172 of 178 retained responses (433 of 451 in the 18 runs), and two
  answers ended `end_turn` inside an open string (`5cbe…` call 25, `eea3…` call 23), which a
  grammar enforced from the first token to the stop can't produce. So ADR 0039:69's
  "schema-constrained decoding" premise doesn't hold for this route. The bodies after the
  prefix pass their schemas; the three failures are all `supported` details on exact-value
  subjects (Q10b), with one closer too many, matching the prefix. Open: whether Bedrock
  applies the grammar partly or not at all. **Decided 1 November 2026:** §22.6 normalization is
  recorded as a provider defect (evidence: Bedrock request IDs
  `ad3f7d58-3b6b-4e99-bb37-f6463a9eb6b5`, `e1840c2b-fb08-4af7-a2e5-2ae75582c8f2`), and ADR
  0039:69's premise is corrected at the next ADR 0039 edit (a policy edit). The live
  comparison (one retained request with and without native JSON mode) is deferred: it needs
  an `e2e-call` change (it keeps the captured response mode, design/harness/e2e.md:115-116) and
  approval. D13.1 removes the review calls where every fault occurred. No model or provider
  change (H5).

## 4. Quality phases (Q)

### Q2b. Generic content-loss guard for repairs

**D2.3** is implemented and committed (`194e29a`; [Z_FIX06](Z_FIX06.md)). **Kept** (decided 1
November 2026): 12 of 12 published, no repair ran, no hello-world spec lost UTC in 9 runs, the
lossy insert path is deleted. Open follow-ups:

- remove `Relations.competing` under §2.12 (`reference_reconciliation_diagnostic.zig:159-161`);
- fold `member_count` into the `collection` variant (`model_result_schema.zig:99`, `:193`);
- assert the exhausted scenario's final rejection reason (`spec_generation_driver.zig:170-187`).

Out of scope unless harm appears: the statement, signal and conflict coverage inserts and
token classifications. D9.1 must keep the binding in any combined schema.

**D2.2 — deferred 30 October 2026** (user decision): a generic revalidation guard rejecting a
replacement that loses an exact-value occurrence or a claim ID the old value had, unless the
authorized defect concerns it (amends §22.4). The dispositions insert that motivated
reopening it is deleted by D2.3, and no repair ran in the 18 runs. **Recommended:** close as
record only. Q13's regeneration guard covers the same ground for review-driven repairs.

### Q4. Remove engine vocabulary and schema-stated rules from prompts (retry)

The first attempt was not kept ([Z_FIX06](Z_FIX06.md)). 12-model-boundary.md:430-431 and
ADR 0016:148-149 say "FIX06 Q4 removes them", so the retry keeps the ID. No published spec
since 29 October contains engine vocabulary (0 in the 18), so this is AGENTS.md compliance,
not an output target.

**D4.1** is kept for `uncovered_member` ([Z_FIX06](Z_FIX06.md)); its first live firings were
satisfied by false links (Q14). **Proposed extension (not decided):** the rule covers native
rule and correction texts too, and a sentence that says what a field, claim or response
contains stays even when the engine enforces or transforms it.

**Scope still model-visible:** `support.prompt.md:35-36`; `packet-guidance.json:69`;
`reconciliation-dispositions.prompt.md:2-4`; `extraction-classifications.prompt.md:2-5`;
`records.prompt.md:4-5`; `support-loss.prompt.md:22`; the restated "exactly once"
(`support.prompt.md:3-4`, `principle.prompt.md:3-4`; `exact_members` already corrects both);
the "native code …" texts in `src/domain/reference_reconciliation_diagnostic.zig` (lines 101,
106, 119, 122, 124, 132, 134), which do reach requests; `src/domain/typed_text.zig:156` (sent
in no projected request). Reword engine vocabulary in place; remove a restated rule only when
the schema or its correction states all of it; keep task semantics the engine doesn't check
(both `citations` sentences and the `claim_ids` definition). `records.prompt.md:9-13` now
states two rules the engine checks (ADR 0038 Decisions 2 and 5); it stays as their only carrier
on a first attempt, since the provider schema can't express them.

**Validation:** projection shows only the listed texts change; scripted missing and repeated
members get the `array_length` and `duplicate_member` corrections; then a set. **Keep if**
engine vocabulary stays absent and corrections, rejections, defect classes and cost stay
within the comparison point's range. Never rename a field to chase a leak. **Recommended:**
after Q13 settles the source-review prompt; settle D4.1's extension first.

### Q5. Remove unmeasured single-run sentences

- `extraction.context.json:4` (`claims`): "Include meaningful identity and purpose headings."
  and "Separate independent behavior, implementation and verification facts."; the second
  sentence of `business`, `technical` and `validation` (`:6`, `:8`, `:9`).
- `support.prompt.md:15-16` (", including compatible requirements labelled conflicting";
  "Empty claims or conflict labels do not establish a source gap.") and `:29`.
- `records.prompt.md:7-8`: "Do not relabel positive requirements as assumptions or non-goals".
- `packet-guidance.json:4`, `:7`, `:9` (title, persona, displayed values); open whether ",
  and an explicit declaration of absence is unnecessary" (`:9`) goes too.

**D5.1** (open): remove them together as one change set; amends 17-specify.md:243-245 and
12-model-boundary.md:843-845 (`:1010-1011` is an admission rule, likely not amended). Risk:
Q4's one-sentence change to the same context coincided with hello-world publishing 1 of 6.
No defect is traced to any of these sentences. **Recommended (not decided):** no; reopen a
sentence only when a defect is traced to it. **Keep if** `unsupported_addition`,
`invented_or_restating_entity`, clarification and blocked outcomes, and the guards don't
worsen.

### Q7. Exact values

**Defect:** rendering artefact in 18 of 18 publications (counted from the published bytes):

- **A. Doubled delimiter** (70 occurrences in 18 publications: FR 25, story 20, AC 19, UO 3,
  BR 2, expected outcome 1). ADR 0036 Decision 6 removes only backtick runs around a value
  (`exact_value_recognition.zig:137-152`, `delimited` at `:58-84`); the model's `"` stays in
  the neighbouring plain text (`specification_provenance.zig:289-297`); the projection always
  gives an exact copy its own code span (`specification_projection.zig:101-109`;
  23-rendering.md:99-100); the renderer escapes the quotes (`specification_markdown.zig:243-262`).
  The doubling is the engine's: it adds a span to a value the model already delimited.
- **B. Plain value in an entity meaning** (20 in 14 publications; 5 bare in 3, ADR 0045's
  case): the field bars exact copies (`text_field_policy.zig:59`;
  `specification_provenance.zig:227-232`, `:281-284`, `:304-318`). All 20 sit on lines
  scored as invented or restating entity.
- **C. Fragments joined without a separator** (1 of 18; 2 of 25 retained story calls): the
  schema keeps the fragments option when no reference is offered
  (`model_result_schema.zig:252`, `:358-381`; `model_text_field.zig:174-189`, `:228-251`),
  and fragments join with no separator (`model_candidate_json.zig:251-253`, `:269-282`).

- **D7.4** is implemented ([Z_FIX06](Z_FIX06.md); ADR 0036 Decision 6). Open: none of the
  development-case values changes, so §1's rendering-artefact counts shouldn't fall on
  either case.
- **D7.5** Where a field offers no inserted reference, its schema offers only the plain string
  (`model_text_field.zig:179-189`; `textContract`, `model_text_wire.zig:277-292`). Contracts:
  07-domain-representations.md:74-80, ADR 0006:303-316, 12-model-boundary.md:1212-1213,
  text-field-composition.md:20-21; whether this is an amendment or a conformance fix (07
  already ties fragments to "composition around typed insertions") is the user's call. Schema
  bytes change in every generation request (0 passive literals in the retained runs), so a
  set. Verified: admission validates the response against the same selected schema the model
  receives (`admit_model_response.zig:19-21`; `model_request_preparation.zig:27`, `:92-99`)
  before the codec runs (`model_candidate_handoff.zig:24-32`), so a fragments object against a
  plain-string field fails as `type_mismatch` with a protocol correction. Effort S: `walk` in
  `model_text_field.zig:179-189`, its tests, and 9 `insertion-presentation` calibration
  fixtures; `generation.context.json:2` still describes fragments. **Keep if** no fragments object appears where no reference is offered
  and publication, admission rejections, protocol corrections, runaways, unsupported addition
  and restating entity don't worsen.
- **D7.2** Decide ADR 0036 Decision 6 and ADR 0045 (on hold) together. Even with D7.4, ADR
  0045 would double a quoted entity value that ends in terminal punctuation, which is every
  retained case (5 of 7); it would fix the bare values. It would also add entity spans to
  review requests, contrary to its "model-facing … unchanged" claim (0045:43-47). **Recommended
  (not decided; edits accepted ADRs):** keep Decision 6, which turns the model's backticks into
  one code span, and withdraw ADR 0045, docs only, removing its hold sites (0045:3-5,
  0020:21-22, 0036:36-38, design.md:1166).
- **Not recommended:** typed exact-value references inserted by the model (ADR 0020 replaced
  them after 4 of 5 hello-world runs failed, and the model's quotes would still double);
  removing the model's quotes (rewrites model bytes); a prompt asking for no quotes.
- **D7.3** Whether a token inside a claim must sit on the recognition boundary to force a duty
  (`CTIV` in `ACTIVE`, `structured_token_test.zig:45`, `:56`). Owner
  `exact_token_obligation.zig:11-31`; amends ADR 0024:33-35 and ADR 0036 Decision 5. The
  boundary alone would drop real duties (a link destination, `exact_value_boundary.zig:106`; a
  code span with a suffix, `:122`). Option needing IDs only: force a token only from a claim
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
  must keep scenario coverage (ADR 0038:65-69) and rewrite the `citations` sentence
  (`extraction.context.json:14`). **Recommended (not decided):** keep, record only. If
  changed, T5 first defines claim counts and claims lost in reconciliation, then a set on an
  experiment and the main build; **keep a withdrawal if** claims lost and restatement don't
  worsen, conditions stay with their items and scenario coverage doesn't fall.
- **D8.2** Whether "cites in full" (ADR 0036:121-125) covers a fenced block whose first or last
  interior line is blank (`markdown_code_spans.zig:53`, `:59`;
  `exact_token_obligation.zig:40-45`; `source_selections.zig:57-60`). No fixture covers it.
- **D8.3** Whether same-category claims on the same cited lines are one claim (precedent
  16-reference-ingestion.md:254-262), including claims inserted by source-omission repair; a
  same-lines pair with different categories needs its own answer.

D8.2 and D8.3 are decided offline with fixtures at their owners and §2.10 projections, in any
gap, or recorded.

### Q9. Reconciliation call structure (W4)

Reconciliation is 4–9% of a published run's tokens; combining dispositions, signals and
conflicts saves at most two sends and 2–4% of tokens and reduces no defect class. **D9.1**
(combine only on capture-replay evidence) amends ADR 0022, §16.4 step 10, ADR 0016's
assignment contexts and ADR 0033's per-phase owners. **Recommended (not decided):** close Q9;
keep only the `model-request-debug/v13` capture replays E4 needs (ADR 0033:264).

### Q11. Story-restatement deletion

**D11.3** ADR 0035: never delete a covered restatement whose claims no other record names (the
user confirms that claim IDs are the reading of "last mention"). Only a story restatement can
do that (`restatesStory`, `specification_generation.zig:334-339`); it hadn't fired since
`8a600d7` in the 54 runs retained before 31 October, and no restatement or duplicate-record
deletion appears in the 36 runs retained on 31 October. **Recommended (not decided):** close as record
only.

### Q12. Copied and weakened obligations

**Defect:** weakened obligation, loan-renewal 8 of 9 (15 of 16 since Q1b), by two routes:

- **Copy route** (before D12.1). The records request received the brief and the entity
  decision with its basis, and `records.prompt.md:1` told the model to use the brief.
  - FR-001 lost "must" in all 4 loan-renewal FRs copied from these drafts (two copied the
    entity basis byte for byte), and in none of 12 written fresh.
  - FR-001 equalled the basis byte for byte in 9 of 18 runs, in both cases.
  - "followed by" orderings travelled the same way (2 of 18).
  - Only the brief's title is published; its description and goal, and the entity basis,
    are not.
- **Story route.** The story request (call 8) receives the claims verbatim ("must be able to
  renew") and no drafts, yet says "may renew" in 15 of 16 loan-renewal publications. The FR
  field purpose names obligation strength (`packet-guidance.json:15`) and fresh FRs keep "must"
  in 12 of 12; the story and description purposes (`:7`, `:5`) don't.

- **D12.1** is implemented ([Z_FIX06](Z_FIX06.md)): records requests and their repair packets
  no longer receive the brief or the entity decision. Open: its measurement set, recorded
  here before it runs (§2 rule 6).
  - **Reference state:** the 18 publications scored on 31 October (D2.3 and Q10b;
    `evaluations/e2e/2026-10-31T*/evaluation.json`).
    - The set's build also carries D13.1, D7.4 and Q13, so its repair and rendering-artefact
      counts aren't attributed to D12.1.
    - Q13's source lines aren't scored as defects (evaluate-e2e SKILL.md §2).
  - **Targets** (event counts, direction down, counted in both cases and pooled):
    - **FR weakening:** an FR stating a source obligation with less force. Opportunity: each
      FR whose claims carry an obligation. Only loan-renewal has shown it.
    - **FR equal to an unpublished draft:** FR text byte-equal to the entity basis or the
      brief's description or goal. Opportunity: each FR. Reference 9 of 18 runs, both cases.
  - **Guards:** lost source requirement, unsupported addition, restatement, a critical
    criterion below its minimum, harmful repair, publication rate per case.
  - **Run maximum:** three runs per case first, then extended by two or three with approval,
    to at most eight per case.
  - **Keep if** (approved 1 November 2026): both targets fall to zero, and restatement, lost
    source requirement and publication don't worsen. Rule 7's test decides "doesn't worsen".
  - **Set result** (1 November 2026, six runs `2026-11-01T08-24-04Z` to `08-24-11Z`):
    - **Build:** all six share source `732665ccc30f…`, recorded `build.source.modified` true
      (run at the user's instruction).
    - **Publication and cost:** 6 of 6 published, 10–11 sends; hello-world about 14.5k tokens,
      loan-renewal 18.8–19.7k.
    - **Advisory scores:** hello-world 89.3 ×3; loan-renewal 67.9, 78.6, 71.4, each with a
      critical criterion below its minimum (`evaluations/e2e/<run>/evaluation.json`; measures
      `evaluations/d121-measures-set.json`).
    - **Targets** (reference 18 runs → set 6 runs):
      - FR equal to an unpublished draft: 9 → 0 (p ≈ 0.075; nine events, just under rule 6's
        floor of about ten);
      - FR weakening: 2 → 0, too few events to decide. Every loan-renewal FR now copies its
        source line, "must" included.
    - **Guards:**
      - unsupported addition 10 → 11, a rise (p = 0.006; the link check added one, 2 November);
      - restatement 7 → 12, a rise (p = 0.0005);
      - runs with a critical criterion below its minimum 0 → 3;
      - lost source requirement 3 → 0 (every loan-renewal run now tests refusal);
      - publication unchanged;
      - the one repair (a native delete of five BRs equal to the FRs) was helpful;
      - against the D2.3 reference alone (§1, 12 runs), unsupported addition 6 → 11 (p =
        0.008) and restatement 4 → 12 (p = 0.0008) still rise;
      - link check (evaluate-e2e, 2 November): false links FR 0/18, AC 2/11, EC 4/5, AS 3/3,
        NG 2/3, BR 2/4, EN 1/6, UO and PB 0/5.
    - **Cause** (likely): without the brief, the loan-renewal records call wrote one FR per
      claim. It also wrote assumption, non-goal, prohibited-behavior and edge-case records,
      which appeared in 0 of 9 reference loan-renewal publications and in 3 of 3 here. They
      invent content (an overdue refusal, a system-access assumption, a concurrent-renewal
      non-goal) or restate FRs. The set can't separate the context removal from the
      `records.prompt.md:1` edit. Hello-world is unchanged.
    - **Decided 2 November 2026** (user: "the above recommendations are approved"): D12.1 is
      not kept alone. Its code stays as part of a new change set, D12.1 with Q16 (§4 Q16),
      measured as one against the D2.3 reference.
- **D12.2** Give obligation strength one owner that every generated field receives:
  `generation.context.json:2` (sent with every generation and repair request,
  `spec.workflow.yaml:784`, `:815`) becomes "…preserve source-backed conditions, obligations
  and obligation strength"; delete the duplicates at `packet-guidance.json:15` ("and
  obligation strength"), `records.prompt.md:7` and the story purpose's "Preserve conditions and
  obligations;" (`packet-guidance.json:7`); `generation.prompt.md:2` optionally. The story
  already receives "obligations" twice; only "strength" is missing. The description purpose
  needs no change: the brief is never published. A model-input change with enough events for a
  set to decide (15 of 16), effort S. It reopens B7's recorded model limitation: the user's
  call. A separate change set from D12.1 (§2.1). **Keep if** the story's weakening falls, FR
  weakening doesn't rise (FR's wording owner moves) and unsupported addition and restatement
  don't rise. **Approved 1 November 2026:** after D12.1's set.
- **Not recommended:** a typed obligation-strength field (07-domain-representations.md:160
  forbids a duplicate modality field; making it matter needs a word check or engine-rendered
  modal text).

### Q13. Inline source lines (post-generation review removed)

**D13.1 is implemented** (1 November 2026, committed by `2b3dc8b`); its live runs are in §3's
build order. The link-check proposal of 31 October was not built; D13.2 and D13.3
lapse. Reopen link checks, in shadow mode, only if adjudication shows semantic defects that the
generation-side items (Q12, Q14, Q15) leave. **D13.4** (decided 1 November 2026): principles are
context and constraints only, never origins, and never modified (Q17).

**Inline sources** are implemented (1 November 2026; [Z_FIX06](Z_FIX06.md); 23-rendering.md
§23, F0100 §5.6). Open:

- The next measurement set shows them on live specs; nothing checks what a shown line means.
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
  choice: records' `claim_ids` (`specification_session.zig:362`), the brief, story, basis and
  question `signal_ids` (`:361`, `:365-369`), dispositions and conflict groups
  (`reference_model_input.zig:241`, `:247`), extraction lines (`:58`) and conflicts
  (`reference_reconciliation_stage.zig:81`). A non-existent ID fails response admission as
  `enum_mismatch` (`model_payload_schema.zig:143`, `:152`) and gets a protocol correction
  within the step's retry limit. No such correction fired in the 18 runs.
- **Gap, the guidance:** the correction says only "this value is not among the allowed
  values" (`model_schema_diagnostic.zig:33`), and its expected shape for an ID choice is
  `{"type":"integer"}` (`model_schema_projection.zig:73-77`). It names neither the rejected
  ID nor the IDs that exist.
- **Change (approval needed to implement):** the `enum_mismatch` correction for an ID choice
  names the rejected value and lists the allowed IDs, both taken from the compiled choice,
  never hard-coded (D4.1's precedent for `uncovered_member`). It changes model-visible
  correction text only; first requests stay byte-identical (§2.10). Proven offline: a
  scripted non-existent claim gets the named correction and an accepted retry. A set can't
  measure it, since it didn't fire in the 18 runs.

### Q14. Scenarios bound to their claims

**Defect:** lost source requirement, loan-renewal 3 of 9 (and 3 in the Q1b era): no scenario
tests refusal. Scenario coverage (ADR 0038 Decision 2; `specification_session.zig:317-324`)
covers only FR-named claims and checks links, not meaning (ADR 0038:76-77). Every retained
firing of the `uncovered_member` correction failed: two Q1b runs exhausted the records retry
limit (2, `spec.workflow.yaml:788`), and two 31 October runs (`07-35-27Z-0669…`,
`07-37-18Z-61b3…`) passed by adding the claim IDs to the success-only AC-001. In
`10-23-59Z-5cbe…` refusal sat only in business rules and nothing fired.

- **b3 (recommended):** a claim-bound scenario insert: the engine fixes the new record's
  `claim_ids` to the uncovered claim and the model writes only its content, closing the
  add-a-link escape. Effort L, using today's repair loop (`spec.workflow.yaml:805-830`); E4 is
  not a prerequisite. Coverage must move from payload admission (`model_payload_schema.zig:179-203`,
  where no typed candidate exists and only a whole-response retry is possible) into the unit
  validator beside entity membership (`specification_generation.zig:252-267`). Insert repair
  exists today only for entity membership (`specification_repair.zig:50-67`, `:127-140`,
  `:373-377`, `:469-476`); the record gates at `:252`, `:373` and `:469` lift, a group policy
  for a fixed claim is added, and the unused content-only `repair_record_acceptance_criterion`
  schema (`generation.schema.json:527-538`) gains an edge-case counterpart. ADR 0038 Decision 1
  already says repairs stay content-only and keep the record's claims (0038:51-52). Deletes the
  admission-time coverage check (`uncovered_member`) and D4.1's covering-kinds correction.
  ADR 0038 Decision 5's partly taken statement (`shared_member`) stays at admission, since
  D16.1 decided it is a protocol correction; its repeated statement is a native delete
  (D16.2). Amends ADR 0038
  Decision 3 (:57-64, :120-122), 22-repair.md:271-275 and :609-614, 12-model-boundary.md:131,
  17-specify.md:249-252, F0100:1405 and design.md:1160. An inserted scenario still links
  without checking meaning.
- **b2:** the scenarios naming a claim must together contain every exact value its quoted text
  requires (IDs and exact bytes; `exact_token_obligation.zig:47-57`). On the 24 retained
  records responses it fires only on the two false links; it misses claim 4 and
  business-rule-only cases; it runs after parsing (`specification_coverage.zig:107-135`), so
  its failure route (coverage repair or block) needs a decision, and it adds a report reason
  (§2.12). Effort M–L.
- **c:** extend coverage to business-rule claims (`specification_session.zig:322`; ADR 0038
  Decision 2) only after b2 or b3; with today's correction it yields false links or failed
  runs.
- Q13's link check would detect the false link without any of these.

**D14.1 decided 1 November 2026:** b3 (Q13's link checks won't exist after D13.1). **Keep if**
lost source requirement falls and
publication and exhausted runs don't worsen.

### Q15. Entity applicability and restating meanings (B6)

**Defect:** invented or restating entity in 17 of 18. Hello-world, which has no data, was
judged `required` in 8 of 9, with names taken from the source title; loan-renewal's meaning
restates the behaviour in 9 of 9, and 8 have a relationship naming no other entity. The
entities request (call 9) gets every source group, the full source and the brief
(`specification_session.zig:285-295`), never the story or records. Every claim in all 18 runs
has category `business`, so no typed fact distinguishes a data concept.
`checkConsistency` and ADR 0035's `statement()` skip entities
(`specification_session.zig:505-520`; `specification_generation.zig:324-329`). The entity
meaning equals the basis in 8 of 8 hello-world `required` runs. Applicability review flagged
2 of 8 hello-world `required` runs, as advice only.

- **Lever 1:** when an entity meaning equals a single-statement record or the story after
  resolving exact copies (7 of 18, all hello-world; 0 under today's typed equality), delete the
  entity and set `not_applicable`. Blocked today: repair may not change the decision
  (22-repair.md:271-275) and ADR 0035 exempts entities (0035:42-43, :79-80). Amends ADR 0035
  Decision 1, 22-repair.md:271-275, 17-specify.md:267-268 and F0100:1143-1145. Native and
  after the last generation call, so proven by rebuilding the published specs offline.
  Effect: hello-world to about 1 of 9; loan-renewal unchanged. Effort M–H.
- **Lever 4:** a typed data-concept fact at extraction or reconciliation that entities must
  cite. Changes every extraction request and depends on intent.md's unaccepted
  smaller-decision shift.
- **Not recommended:** typed relationship targets (remove no defect; may induce a second
  invented entity).
- **Hypothesis, not testable offline:** requiring every entity basis to cite a group may bias
  the model toward `required`. The rule is enforced three times (`generation.schema.json:178-180`,
  `:563-583`; native, `specification_generation.zig:300`; 07-domain-representations.md:161)
  and applies to both decisions. It was constant across every evaluated build, while
  hello-world's `not_applicable` rate moved from 0 of 15 (19–27 October) to 4 of 16 since Q1b,
  so it didn't cause that shift. Testing its own effect needs repeated live runs with the
  citation optional, which amends 07-domain-representations.md:161 and the native check.

**D15.1 decided 1 November 2026:** entity applicability is recorded as a model limitation for
now. Lever 1's signal exists only because FR-001 copies the entity basis, which D12.1 removes,
and lever 4 depends on an unaccepted intent shift. Revisit on D12.1's results; inline source
lines make a restating entity visible to the reader meanwhile.

### Q16. Requirements own their claims

**Defect:** restatement, 5 of 18 publications (7 defects): business rules paraphrasing the FR
or the source, AC and edge-case repeats, the story repeating the FR. ADR 0035's exact
equality catches none of them.

- **Lever:** an ID-only admission constraint beside ADR 0038 coverage: in one batch each claim
  is named by at most one FR, BR, UO, AS, NG or PB record (scenarios exempt), corrected by
  protocol correction, never deletion. Over 29 decidable publications (the 18 plus 10 Q1b and 2
  on `8444312`, from retained "Generated Requirement Sources" and evaluation records) it flags
  6 of 9 restatement publications; the 3 misses are the story restating the FR (Q11's
  territory). It flags 0 of 20 clean publications, but 19 of those have one statement record,
  so its specificity still rests on one run (`5cbe…`). An offline replay must drop exact-token
  claims, which the published lists include and admission never sees. It must come with
  scenario coverage for every statement kind's claims (else `5cbe…`'s loss repeats), and it
  must not remove a BR that carries the only "must" (`1098…`, `71ed…`, Q1b `09-13-36`; Q12
  D12.1 removes that case). Amends ADR 0038 Decisions 1–3 and :89-99, 17-specify.md:247-257; a new diagnostic
  reason (§2.12); a `records.prompt.md:9-13` sentence (model input). Effort M; 7 events, so
  plan up to 8 runs per case.

**D16.1 decided 2 November 2026** (user: "the above recommendations are approved"): build Q16
with D12.1 as one change set, because restatement rose under D12.1 alone.
- **Rule:** in one records batch, each claim is named by at most one functional requirement,
  business rule, user-visible outcome, assumption, non-goal or prohibited behavior. Scenarios
  are exempt. A violation gets a protocol correction, never a deletion.
- **Coverage:** a claim named by a functional requirement, business rule, user-visible outcome
  or prohibited behavior needs an acceptance criterion or edge case that names it. Assumptions
  and non-goals are scope statements and need none (user, 2 November 2026: "No, behaviour kinds
  only").
- **Risk** (Q14 c): extending coverage before b3 can produce false links or exhausted records
  retries under today's correction. Under D12.1 the FRs name every claim, so the extension
  should rarely fire. The advisory link check (evaluate-e2e) counts false links.
- **Implemented 2 November 2026** with D12.1 as one change set ([Z_FIX06](Z_FIX06.md); ADR
  0038 Decisions 2, 3 and 5). Open: its measurement set, against the D2.3 reference (§1), three
  runs per case, recorded here before it runs:
  - **Targets** (event counts, direction down, pooled over both cases): restatement; FR equal
    to an unpublished draft; FR weakening.
  - **Guards:** lost source requirement, unsupported addition, a critical criterion below its
    minimum, harmful repair, publication rate per case, exhausted records retries, and false
    links (link check).
  - **Run maximum:** three runs per case, extended by two or three with approval to eight.
  - **Also counted:** `shared_member` firings per records batch.
  - **Decided 2 November 2026:** Q16 replaces ADR 0035's in-batch record-versus-record
    deletion ("Yes, Q16 replaces it"); one `shared_member` correction lists every second
    naming ("Yes, list every location"). Replaying the rule on the D12.1 records responses
    gives 4, 8 and 8 second namings per loan-renewal batch and none for hello-world.
  - **Keep if:** restatement and FR-draft copies fall and FR weakening doesn't rise, with no
    guard rising under rule 6.
  - **Set result** (2 November 2026, six runs `2026-11-02T00-04-31Z` to `00-05-48Z`; measures
    `evaluations/q16-measures-set.json`, evaluations `evaluations/e2e/<run>/`):
    - **Build:** all six share source `6b37001bfce8…`, recorded `build.source.modified` true.
    - **Publication:** hello-world 3 of 3; loan-renewal 1 of 3 (D2.3 6 of 6; one-sided
      hypergeometric p = 0.083). Both failures exhausted the records retry limit on
      `shared_member` (`00-04-45Z`, `00-05-17Z`).
    - **Cost:** hello-world 10 sends, about 14.6k tokens; loan-renewal 10 sends and 18.5k
      published, 12 sends and 26.9–27.0k failed.
    - **Advisory scores:** hello-world 85.7, 85.7, 89.3; loan-renewal 85.7 (one run). No
      critical criterion below its minimum.
    - **Targets** (D2.3, 12 publications → set, 4 publications):
      - restatement: 4 → 2, no fall per publication (hello-world 1 → 2: a title and a story
        restating their own requirements; loan-renewal 3 → 0);
      - FR equal to an unpublished draft: 0 in the set (9 of the 18 D2.3 and Q10b runs);
      - FR weakening: 0.
    - **Guards:**
      - publication fell in loan-renewal (above);
      - exhausted records retries 0 → 2;
      - unsupported addition 6 → 4, 0.5 → 1.0 per publication (p = 0.22);
      - lost source requirement 2 → 0; no repair ran;
      - link check: false links AC 1/5, FR 0/12, EN 1/4.
    - **`shared_member`:** it fired in 2 of 6 first records batches, both loan-renewal, each
      time on two user-visible outcome records naming FR-003's and FR-005's claims. Both
      corrections returned the same outcome records, so all six rejections hit the same two
      namings. Because the FRs name every claim, no claim ID at the located position
      (`/records/<i>/claim_ids/<j>`, shape integer) is admissible. Only removing the later
      record, or changing the earlier one, satisfies the rule, and the correction says
      neither (likely; model limitation or contract gap).
    - **Hello-world's new story and title defects** come from requests byte-identical to the
      D12.1 set's (the two freezes differ only in the 169 records requests), so they aren't
      attributed to Q16.
  - **Not kept as built.** Loan-renewal publication fell (guard), so rule 6 recommended
    reverting.

**D16.2 decided 2 November 2026** (user: "approved", then "Yes, exempt FRs"; an exception to
§2 rule 1): amend the change set instead of reverting it.
- **Rule:** a business rule, outcome, assumption, non-goal or prohibition whose every claim a
  requirement (before or after it) or an earlier such record names is deleted natively, with
  no model call (`repeated_statement`). One naming such claims and others gets the item-level
  `shared_member` correction. Requirements are never deleted or rejected by this rule, since
  one prose claim can hold two obligations and deleting the second requirement would lose
  one. After the contract review (user: "Yes, keep it", twice): a repeated statement holding
  the batch's only copy of an exact value is kept, and the records prompt's "at most one"
  sentence stays unchanged for the set.
- **Evidence:** in the 12 retained runs' first records attempts, 24 statements were wholly
  taken (9 business rules, 6 outcomes, 3 assumptions, 3 non-goals, 3 prohibitions), all
  scored as restatements or inventions; none was partly taken and no two requirements shared
  a claim. Both failed `D16.1` runs' rejected records are wholly taken outcomes, so the
  amended rule deletes them and the batch admits.
- **Measurement set:** against the D2.3 reference, three runs per case, with the targets,
  guards, run maximum and **Keep if** recorded above for D16.1; also counted:
  `repeated_statement` deletions and `shared_member` corrections per records batch.
- **Set result** (2 November 2026, six runs `2026-11-02T02-27-46Z` to `02-29-15Z`; measures
  `evaluations/d162-measures-set.json`, evaluations `evaluations/e2e/<run>/`):
  - **Rule activity:** none. No first records attempt had a business rule, outcome,
    assumption, non-goal or prohibition, so nothing was deleted or corrected.
  - **Publication:** loan-renewal 3 of 3; hello-world 2 of 3. `02-29-06Z` exhausted
    reconciliation dispositions on `missing_member` (claim 2 omitted three times). The
    request is byte-identical across D2.3, D16.1 and D16.2, so it is a model limitation in
    an unchanged step (hypergeometric p = 0.33).
  - **Cost:** 10 sends, 14.6k (hello-world) and 18.3–18.5k (loan-renewal) tokens. One outlier:
    `02-28-14Z`, 34 sends and 67k tokens. There, extraction returned `no_feature_claim` and
    the pre-generation source review's repair loop recovered it; the repair was helpful.
  - **Advisory scores:** hello-world 89.3, 89.3; loan-renewal 89.3, 78.6, 89.3 (D2.3 means 89.9
    and 86.3). One critical criterion below its minimum: `02-28-51Z` source-grounding, from
    two invented edge cases.
  - **Targets** (D2.3, 12 publications → set, 5):
    - restatement: 4 → 3, no fall (p = 0.88). All three are outside the rule's reach: a title
      sentence, a story equal to its single FR, and an edge case repeating an acceptance
      criterion;
    - FR equal to an unpublished draft: 0 of 5 (p = 0.11 alone). Across the D12.1, D16.1 and
      D16.2 sets it is 0 of 15 against 9 of 18 (p = 0.004);
    - FR weakening: 0.
  - **Guards:**
    - unsupported addition 6 → 6, 0.5 → 1.2 per publication (p = 0.109, just above rule 6's
      0.10); 4 come from the records call (two AC 'records the renewal' additions, two
      invented edge cases), 2 from story calls with unchanged requests;
    - lost source requirement 2 → 0;
    - critical criterion below minimum 0 → 1 run;
    - harmful repair 0; exhausted records retries 0 (D16.1: 2);
    - link check: false links AC 2/11, EC 2/2, FR 0/15, EN 0/4.
  - **Keep if:** not met; restatement didn't fall. The set never exercised the rule itself, so
    it neither shows nor rules out a benefit from it.

### Q17. Principles as Spec context

**Decided 1 November 2026** (user): "the workflow must never modify principles - NEVER" and
principles "should be used for context when executing the spec workflow".

- **Never modified:** holds today. Principles are read through a read-only source adapter
  (`src/adapters/filesystem/principle_source.zig`: reader, enumerator, capturer), and path
  validation rejects every project operation against the semantic-principles root
  (11-path-validation.md:20). Every future step (Plan, Implement, init, repair) keeps it; it
  becomes a design.md §3.3 invariant when the design is next amended.
- **Context:** today no generation call receives principles. In `10-23-59Z-f331…` calls 1–22
  carry none, and since D13.1 no call does. Adding them changes
  generation requests, so it is a model-input change measured by a set. Principles are
  context and constraints, never a requirement's origin: items still cite only source claims
  (Q13's D13.4 resolved).
- **D17.1 decided 1 November 2026:** the records call only (it writes the FR, AC, BR and other
  statement records principles constrain), with the principle files as the registry captures
  them, unnumbered (items never cite principles). About 7k tokens per run; a measurement set
  after D12.2 with guards on unsupported addition and invented entity.
- **Cost:** the case principles are 28,067 (hello-world) and 29,399 (loan-renewal) bytes,
  about 7k tokens per call that carries them; all four generation calls add about 28k tokens
  per run, offset if D13.1 removes post-generation review.
- **Target and risk:** no current rubric criterion scores principle consistency, so a set can
  show only guards (unsupported addition and invented entity from principle text,
  publication) unless the case rubrics gain a criterion. Amends ADR 0015, ADR 0023 "Principle
  handoff" (0023:405-412), 17-specify.md's generation inputs and F0100.

## 5. Engine track (E)

Each item: `/preflight`, offline tests, the §2.10 proof, `zig build verify`, one live run
per case (DE2 and DE3 ask whether offline evidence replaces it), landing between sets and under
§2.12.

### E0. Failed and blocked runs publish validated content (B10, ADR 0041)

On hold since 30 October 2026 (ADR 0041:3-7). Nothing under `src/` names `failure-output`,
`spec_incomplete` or `run.incomplete_published`. To resume: slices S1–S5 per ADR 0041
Decisions 1–8, taking the next `specification-state` version after v20; align the measures
(`test/harness/e2e/measures.zig:132`, test `:522-525`; e2e.md:723-725), ADR 0041:120 and
:240, design.md:208 and :1163, F0100:1191 and `contracts.zig:224` with Decision 7.1 (an
`invalid` run stays `invalid` and may publish); add a test that a pre-E0 v11 report still
decodes; flip the scenarios asserting no publication (`test/integration/workflow_tests.zig:3055`,
`:2597-2605`; `test/harness/integration/tests.zig:1939-1956`); register
`run.incomplete_published` through `adrRequired` (`src/domain/log_event_registry.zig:103-107`,
test `:164-170`). The amendment notes of ADRs 0009, 0011, 0017, 0023, 0037 and 0039 state ADR
0041's effect without the hold; aligning them is a policy edit. If ADR 0041 is withdrawn, v11's
`incomplete_publication` and the measures' `incomplete` value become dead code needing a report
version. Budget-stopped runs publish nothing while it is on hold (three on `ddbc6d9`).

### E1. Engine-owned model request (A1, ADR 0030 slice 4)

Not started: the `request-model` step replacing `model-request-body`
(`spec.workflow.yaml:1032-1094`) and its five wrappers (`:940-1031`), with the contract-variant
mechanism ADR 0033 reuses. It folds in ADR 0039's re-send and retires `validateRunawayRoutes`
(`src/domain/workflow_model_request_lifecycle.zig:92`). Retake the slice 1 freeze on the commit
before it lands. Slice 1 review points: trace the advisory production run; make
`extract/content` and `extract/content-request` (`spec.workflow.yaml:326-338`) one step; port
each runner-level lifecycle test in `src/model_request_workflow_test.zig` one for one with a
mapping table and a reason for any dropped assertion (user decision, 23 October 2026, option b).
`propagate-advisory-request-failure` and the advisory protocol were deleted with D13.1.
If E1 removes a request-lifecycle `DataKey`, it lands under §2.12.

### E2. Stage actions (A2, ADR 0031) and identical sibling steps (W5)

Not started: convert `prepare-toolchain` (`spec.workflow.yaml:187-216`) first and record ADR
0031's measures (:364-366) before another stage. **DE2:** confirm ADR 0031's derived choices
1–3 and 6–8 (:270-299), including whether choice 7's offline evidence replaces the live run.
**W5: recommended closed, record only** (user decides): both pairs (`source-gaps` /
`candidate-gaps`, `finish-native` / `finish-model`) already share one subgraph
(`spec.workflow.yaml:165-173`, `:353-358`), and by reading neither merged step would pass the
join check (`workflow_data_flow.zig:69-70`).

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
**DE4:** confirm ADR 0033's derived choices 2–8 (:276-287). Q13's activation and Q14 b3 reuse
these operations.

### E5. Rejections say why (A4)

Give the payload-free `.authority` rejection a closed reason
(`src/domain/workflow_execution.zig:56`, `:74`) and split `error.OperationExecutionFailed`
(185 sites in 42 production files) into causes at their owners; sites E1–E4 rewrite land with that
conversion. Failure-evidence gaps:

- Evaluator partial bodies disappear (harness only; matters for H3): carry the transport's
  `ResponseBody` bytes and completeness through `test/harness/provider.zig:27-34`,
  `bedrock.zig` (`:67-70`), `http.zig` (`:99-101`) and `evaluation_trace.zig`, with redaction
  and fault tests.
- A later failure replaces the earlier cause
  (`src/application/workflow_model_invocation.zig:15-22`,
  `workflow_pipeline_runner.zig:472-494`): keep the first cause beside the terminal one.
- **Correction location:** all four SyntaxError corrections in the 18 runs told the model
  `byte_offset 4`, key `"{"` (the malformed opening), not the unterminated string;
  `model_envelope.zig:68` drops the re-parse diagnostic and `:75` reports the original, as
  §22.6 requires (22-repair.md:565-566). Fixing it amends §22.6 and changes correction
  requests; one of the four corrections ran away.

### E6. Logging and visibility gaps

- **Cancellation** during segment reads and under the log lock ends the run `blocked`, not
  `cancelled` (`operation_error.zig:16-24`; `feature_log_recovery.zig:29-61`;
  `feature_log_historical_stream.zig:95-97`). **Decision:** should cancellation during log
  reads or under the lock end the run `cancelled`? If yes: add `Cancelled` to the
  `FeatureLogSink` error set and propagate it, amending ADR 0032:313-314's "Not decided" bullet;
  no new `LOG_*` code.
- **Lock failures** all report `LOG_LOCK_TIMEOUT` (`acquire_feature_log_stream_lock.zig:18`):
  the single `tryLock` never waits, and `InvalidBinding` and `SinkFailure` aren't timeouts
  (F0002:564, :575; `feature_log_lock.zig:9-27`). No decision needed: map those two to F0002's
  existing `LOG_SINK_FAILURE` and keep `LockUnavailable` as `LOG_LOCK_TIMEOUT`.
- **Prior-run crash finalization** (§14.10) is blocked on a persisted bootstrap authority that
  doesn't exist (14-orchestration.md:327-331), so a crashed run's logs are kept whole and
  damaged prior logs block later runs until someone repairs or removes them. E3's
  feature-logging conversion waits on this decision.
- **Redaction policy ID:** 26-security.md:196 and F0002:561 name `redaction/default-v1`, which
  no code carries. **Decision:** a record carries the ID (a `feature-log/v2` field, so a
  version change), or both documents drop it. **Recommended:** drop it.
- **Producerless rejection** (fixed, [Z_FIX06](Z_FIX06.md)), still open: contract 27
  (27-observability.md:59-62) names only coverage as an assembled-candidate example (design
  edit awaiting approval: add `producerless` as a second example); `observation.capture`'s
  candidate arm has no direct test. **Decision** (optional): a first-generation omission names
  its chunk's classification producer. **Recommended:** no.

### E7. Clarification answer recovery (R2, ADR 0025)

Not started; no §13 authentication chain exists in `src/`. Fresh answers can't complete
recovery: refresh rejects new submissions (`clarification_refresh.zig:65`); provenance
rejects nonempty response-ID sets (`specification_provenance.zig:88`,
`specification_support_evidence.zig:199`); form validation returns one
`InvalidClarificationInput` (`validate_clarification_forms.zig:17-61`); resolved needs are empty
(`build_resolved_clarification_needs.zig:8`); generation doesn't consume answers
(`specification_source_binding.zig:95`, `:147`). Complete the
[§17.4 lifecycle](../design/contracts/17-specify.md#174-specification-clarification-behavior)
under ADR 0025. Live validation needs a user-chosen clarification-expected case run twice with
forms answered between runs; neither the case nor a two-run harness flow exists. Last, after
E1–E4.

### E8. Typed schema-definition identities

Domain code names result-schema definitions by raw strings: T5.2 counts 20 production sites
after D13.1 (Z*FIX06 T5), which fail only at request preparation
(`model_request_handoff.zig`; sites in `specification_support.zig`, `specification_session.zig`,
`specification_repair.zig`, `reference_model_input.zig`, `reference_reconciliation**.zig`,
`reference*extraction**repair.zig`). Bind them as closed IDs checked at schema load. Test
fixtures branch on names too (`spec_generation_driver.zig`, `spec_generation_responses.zig`).

### E9. Superseded exact-handle correction

`ValueChoices.correction`'s `unknown_exact` arm (`specification_provenance.zig:177-180`) corrects
a model-authored exact handle that models can't author since `dfae959` (ADR 0020:233).
`ValueChoices.permits` (`:167-169`) has no caller. Delete the arm, `permits`, the
`rejected_exact` member (`typed_text.zig:144`), its assignments (`typed_text.zig:245`,
`specification_provenance.zig:426-433`) and the assertions that read it
(`typed_text_test.zig:32`, `specification_generation_test.zig:9132`,
`packet_guidance_test.zig:206`); the `unknown_exact`
rejection stays. Neither current freeze carries `rejected_exact`, and the only report that
did (the failed `2026-10-31T03-01-37Z-7c6a…`) is no longer retained. Lands with E1, E4 or E5.

## 6. Test track (T)

### T2. Test decoupling

About 46 lines in 8 files copy model-facing English or check its absence (lower bound, 31
October 2026). Compare with the owning constant or resource instead: copies in
`model_request_workflow_test.zig`, `model_payload_schema_test.zig` (and its `:362-367` phrase
checks on `protocol.prompt.md`), `reference_model_input_test.zig`,
`test_fixtures/spec_generation_driver.zig`, `model_text_field_test.zig`,
`reference_reconciliation_test.zig`, `specification_generation_test.zig:10806`; absence checks
at `model_text_field_test.zig:177`, `model_request_workflow_test.zig:4531`,
`specification_generation_test.zig:7466`, `:7636`. Rename tests, fixtures and
`measurement_prefix` dumps named after live runs (R31, R35, R36, R42, FIX002 and others;
`workflow_tests.zig:1668-1750`, `build/test_run_inputs.zig:22`, `:33-40`). **Decision:** delete
the never-run insertion-presentation panel with its `attribution-replay` tooling
(`test/harness/attribution/preparation.zig:191-198`), or keep it.

### T3. Coverage gaps (B5, B7)

- No integration scenario reaches a records-batch native delete (`duplicate_record` or ADR
  0035 `restatement`); unit coverage only.
- The no-feature-claim text-repair route (`spec.workflow.yaml:365-386`) has unit coverage only.
- The retained GPT-OSS compatibility exchange is assessed `incompatible` since ADR 0036
  (`provider_compatibility_tests.zig:261-262`, `:305-309`), so the normal §22.6-normalized path
  has no compatible-assessment coverage.

### T4. Architecture rules and replay (A5)

When E1–E4 remove files pinned by architecture tests, write the replacements as import-graph
and contract-shape rules (ADR 0030:609-613, 0031:346-362, 0032:293-305, 0033:341-344), not
per-file pins (68 of 78 tests pin files). Prefer replaying retained captures over extending
`spec_generation_responses.zig`.

### T5. Brittleness counts

Baseline, definitions and decisions: [Z_FIX06](Z_FIX06.md). Each change set that a phase
reports on retakes them on its committed build: `zig build code-heuristics -- --freeze <dir>`
with the freeze §2.10 takes on that build, and T5.4 by hand from `spec.workflow.yaml` (a
`slot: repair` step whose prompt no non-repair step binds).

## 7. Human and decision track (H)

### H1. Adjudication (R8)

Only a human `human-spec-adjudication/v2` record applied with `zig build adjudicate-spec`
decides acceptance; none exists. Only 7 v11 runs remain under `zig-out/` (the Q10b set and
`07-37-18Z-61b3…`); they should decode on the current build (by inspection only), and any
later member change strands them (§2.12). The other 31 October runs (11 of the 12 D2.3 runs
included), the v10 and 29 October runs (including the clean `39a06ea` pair) can't be
adjudicated from this checkout; v9 runs stay unadjudicated (user decision, 27 October 2026).
Needed for the ADR 0034 gate and adjudicated measures.

### H2. Review-label confirmation (B2)

The scheme is `b2-review-label/v2` (`.claude/skills/evaluate-e2e/SKILL.md` §7). Q1b's labels
sit in three layouts under `evaluations/e2e/2026-10-29T*/` (run root, `b2-review-labels/`,
`b2-review-accuracy/`), and a `supported` verdict on a defective subject is labelled
`wrong_type` (5 runs), `missed_defect` with a null predicted type (2 runs, which inflates
precision: `09-03-15` reports accuracy 0.9714) or both (2 runs); the D2.3 and Q10b runs have
no labels. Cause: §7's "A defective subject with no finding of the expected type is
`missed_defect`" is ambiguous. **Proposed convention:** one entry per returned verdict; a wrong
verdict on a defective subject is `wrong_type` (counted in accuracy, and as a miss in recall);
`missed_defect` only when a subject got no verdict at all; `defect_class` null whenever the
expected type is `supported` (matches e2e.md:661-663); path
`evaluations/b2-review-accuracy/<set>/<case>/<run>/`. Relabel effort: 2 skill lines, 10
duplicate entries deleted, about 5 converted, 7 `defect_class` values reviewed, metrics
recomputed in 10 files. **Adopted 1 November 2026:** the convention goes into SKILL.md §7 when
it is next edited. Relabelling Q1b isn't needed: after D13.1 no post-generation review findings
exist to label, so H2 applies only if review returns.

### H3. Calibration panels (R8)

The hello-world and loan-renewal panels (`test/integration/fixtures/*/calibration/`)
have proposed labels only (`human-review.json`, `qualification.json` `pending`). They qualify
only the standalone evaluator; neither the gate nor FIX06's sets need them.

### H4. Experiment stops, qualified scope and the formal baseline (B4, B5)

**Decision** needed only before freezing the evaluation protocol's Phase 2 baseline. The
protocol stops at 1,000 sends or 2,000,000 tokens
([README](../test/calibration/semantic-simplicity/README.md):189-190), about 27.8k tokens for
each of the Phase 2 baseline's 72 workloads. The worst current run is 123,519 tokens, and the
non-review tokens alone are about 14.7k (hello-world) and 18.5–26k (loan-renewal) per run, so
no review lever within the constraints makes Phase 2 fit. The latest feasibility report is
`insufficient` (`zig-out/baseline/2026-10-15T22-38-08Z-4ae4…/budget-feasibility.json`).
Options: narrow the qualified scope, or the user changes the stops. Measure each call's
prompt, schema and evidence share before trimming; no local size ceilings (ADR 0011).

### H5. Model choice (R7)

The user decides when to change or compare models; all live evidence is GPT-OSS-20B. Only if
the user selects Claude Haiku 5.5: measure its maximum-output time to replace the interim
180,000 ms `requestTimeoutMs`, and settle Claude's response mode.

## 8. Research and backlog (R)

### R1. Group-level provenance precision

Entities and the brief and story fields select whole groups
(`specification_generation.zig:136-141`, `:166-169`; `specification_provenance.zig:558-562`),
and in every run since Q1b reconciliation formed one signal holding every quoted claim. Measure
whether grouping and source review meet the traceability claim (design.md:121) before any
binding change; Q13's link checks give the per-record evidence. No second provenance store, no
support inferred from text matching.

### R6. Semantic repair attribution and recovery

Under ADR 0023 post-generation findings don't drive repair; loss localization runs only under
required review (`specification_support.zig:653-658`). Remaining proposals, each needing a
closed contract, after Q13: source-authorized exact-reference repair eligibility (ADR
0033:353-354); narrow correction of invalid loss evidence (today `invalid`,
`specification_support_workflow.zig:87`; `specification_support_repair.zig:97`); verdict
reassessment under §22.1 with no voting or retry-until-positive. No evidence since Q1b: the
development cases reach required review only when no claim is generation-ready.

### B7 contract-review leftovers

- Prior-state readback checks stored claim text against the text policy only
  (`reference_snapshot.zig:116-117`; ADR 0036:181-183); re-quoting needs the Unicode
  normalizer at readback.
- `source_selections.validate`'s typed `Issue` is discarded by both production callers
  (`validate_reference_claims.zig:32-34`, `source_omission_comparison.zig:132-133`), and
  `validate-reference-selections` validates token classifications only. Delete the unused
  detail and rename the step and key for what they do (touches `spec.workflow.yaml`, F0100,
  `workflow_tests.zig` and nine `src` files; lands in a gap).

### Retired FIX06 IDs cited elsewhere

These IDs are no longer in FIX06 (their records are in git at `194e29a`, `fixes/Z_FIX06.md`);
each citing file needs its reference rewritten, a docs edit needing approval for ADRs:
"D3.1" (12-model-boundary.md:422-423, ADR 0016:132, `src/domain/packet_guidance.zig:1`);
"Q3" (ADR 0016:149); "Q1a, D1.2" and "Q6" (ADR 0038:96-97); "Q2" (ADR 0046:42-43); "T5(b)"
(`.claude/skills/evaluate-e2e/SKILL.md:57`); "DT5" (design/harness/e2e.md:682); "T5(a)",
"T5(c)" (`test/harness/e2e/measures.zig:1-2`); "T5(e)" (`src/test_fixtures/request_projection.zig:1`,
`test/integration/workflow_tests.zig:1329`); "T5" meaning the measures (`e2e_measures.zig:1`,
`test/harness/e2e/measures_cli.zig:1`).

### Wider scope retained

- **Memory and scale:** growing review sets, retained bytes, allocations, teardown,
  cancellation and OOM. Unmeasured.
- **Harness acceptance (former H-012, H-013, H-017; git `8ed40ba`), rechecked 1 November 2026.** Covered by tests, so closed: shorter replacements (`file_access.zig:136`;
  `workflow_tests.zig:3498`), concurrent closes (`:3498`), unsubmitted drafts and stable
  subject IDs (`clarification_inputs_test.zig:46`), skipped gates and undeclared resources
  (`required_authority_workflow_test.zig:219`; `workflow_definition_test.zig:298`, `:430`,
  `:822`; `smoke.zig:135`), packaged execution without a `design/` fallback (`smoke.zig:608`;
  no production file names `design/`), and an unchanged prior `spec.md` not labelled new after
  a blocked rerun (`test/harness/integration/tests.zig:448`, `oracle.zig:11-18`). Production
  Specify feature-logging is done (`spec.workflow.yaml:59-61`, `composition/root.zig:112`,
  `workflow_tests.zig:1899-1915`); F0002:807-808 and F0100 still call it open (design edit).
  Still open:
  - publication interruption: every write failure is covered as a failpoint
    (`workflow_tests.zig:3605`, meeting ADR 0009:142-145) but no process kill is tested;
    **recommended:** close;
  - rerun replacement through an unrelated workflow: covered at the shared writer; reopen when
    the first non-Spec publisher lands;
  - live negative cases as separate fixtures: none exist (`test/e2e/` holds the two
    development cases); adding them means live spend, the user's call.
- **Provider docs:** ADR 0028 links an F0009 feature document that doesn't exist
  (`0028-anthropic-messages-provider.md:35`, `:95`, `:151`), and its "Live use" (`:177`)
  contradicts `test/harness/model_cost_policy.zig:17-25`; `test/harness/e2e/cli.zig:26`'s help
  lists only the two Bedrock tuples. No live Claude call has been made. Fixing ADR 0028 is a
  policy edit.

### R-A1. Engine-owned release

Whether the engine also takes over release, changing ADR 0012's retained-request handoff (ADR
0030:620-622). Decide after E1.

## 9. Guardrails

The user's standing constraints beyond AGENTS.md:

- No model change or comparison (H5).
- The workflow never modifies principle files (1 November 2026; Q17).
- No caps that discard output, and no larger token budget: a budget failure is fixed at its
  cause, such as review cost or runaways (30 October 2026). No local token ceilings, no
  truncated required evidence, no claim that a larger budget fixes reliability.
- Never batch or group source-review subjects; they keep ADR 0023's whole-unit assignments (30
  October 2026). Q13's per-link checks keep one subject per question.
- Measures and replays use the owning steps (`zig build e2e-measures`, `e2e-call`), never
  one-off scripts, loops or new tracking files (29 October 2026).
- Don't narrow the entity-name exception without a decision (B6).
- Runaways stay a reported measure (ADR 0039).
