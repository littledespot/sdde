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

Comparison point for quality phases: Q1b, six runs per case on `371b55a` plus its working tree
(29 October 2026; measures `evaluations/q1b/measures-set.json`, evaluations and labels
`evaluations/e2e/2026-10-29T*/`). A change proved under §2.11 never moves it.

**Output quality, 31 October 2026** (advisory scoring of 18 publications against the case
rubrics, `evaluations/e2e/<run>/evaluation.json`; scorer judgment moves a score about ±3.6):

| Build | Hello-world mean (range) | Loan-renewal mean (range) | Below 80% |
| --- | --- | --- | --- |
| Q1b and 8444312 (14 earlier evaluations) | 90.8 (82.1–100) | 83.6 (78.6–89.3; 2 undetermined) | 1 |
| D2.3 tree (12 runs) | 89.9 (85.7–100) | 86.3 (82.1–92.9) | 0 |
| Q10b tree (6 runs) | 89.3 (89.3–89.3) | 82.1 (78.6–85.7) | 1 |

No change since Q1b has improved the published output. Defects per publication on the 18
runs, with the stage that produces them:

| Defect class | Hello-world | Loan-renewal | Producer | Item |
| --- | --- | --- | --- | --- |
| rendering artefact | 9 of 9 | 9 of 9 | engine (`assembly_or_render`) | Q7 |
| invented or restating entity | 8 of 9 | 9 of 9 | entities step (model) | Q15 |
| weakened obligation | 0 of 9 | 8 of 9 | story step; 2 FRs copy the entity basis sent to the records request | Q12 |
| unsupported addition | 4 of 9 | 4 of 9 | records step (AC triggers, coverage-driven outcomes, copied drafts) | Q12, Q14, §3 |
| restatement | 1 of 9 | 4 of 9 | records step (BR paraphrasing FR or source) | Q16 |
| lost source requirement | 0 of 9 | 3 of 9 | records step (refusal scenario missing) | Q14 |

Post-generation review flagged 4 of the 47 non-rendering defects and passed 43 (Q13).

## 2. Rules for measured phases

AGENTS.md ("Model output, prompts and evidence", "Anti-overfitting rule", "Validation")
governs; these add what the phases need.

1. **One change set per measured build** relative to the comparison point. Changes that rule
   11 proves leave every development-case request byte-identical may also be present. A
   change set that isn't kept is reverted in full, never patched on top.
2. **Owner first, offline first:** `/preflight`; regression and negative tests at the owning
   boundary, compared with owners rather than copied English; `zig build verify`;
   `contract-reviewer`. Cover unrelated members of the class (both development cases plus an
   offline unrelated-domain fixture).
3. **Build.** Measurement uses a committed, unmodified build (`build.source.modified` false).
   Since Q1b every set has run on the latest build, committed or not, by user decision (29
   October 2026, "run Q1b on the latest build", a recorded deviation; each later set approved
   the same way). **Decided 1 November 2026** (user: "apply best recommendations"): keep this
   rule, with no standing deviation, since AGENTS.md requires "one committed build". A set's
   runs share one `build.source.source_sha256`; nothing under the
   build-provenance roots (`build/provenance.zig:21`) changes while a set runs. `fixes/`,
   `.claude/` and `evaluations/` aren't roots.
4. **Measurement set:** three runs of each development case, each approved, extended under
   rule 7 to at most eight per case; every attempt counts; nothing is tuned on the reserved
   qualification features. A 12-run set costs about 0.9–1.0M tokens (Q1b 918,713; D2.3
   996,625). **Decided 1 November 2026:** no interleaved control run on the comparison point's
   build (Q1b's run directories are gone); the reference is fresh runs on the next unmodified
   build.
5. **Evaluation:** `zig build e2e-measures` and `/evaluate-e2e` for every run (AGENTS.md:
   live runs are judged by scoring the published specs); B2 labels for every review finding
   only in sets that change review, after H2.
6. **Measures:** design/harness/e2e.md "Run measures". Rubric defect classes, counted over
   native publications beside the publication rate per case: lost source requirement;
   weakened obligation; unsupported addition; invented or restating entity (B6); restatement;
   rendering artefact; engine-vocabulary leak. Each repair is graded helpful, neutral, harmful
   or no progress. Review: finding-type accuracy (e2e.md "Reliability assessment"),
   provisional until H2, with precision per predicted type, recall per labelled type,
   detection recall, false statements and principle-citation precision. Brittleness counts:
   T5.
7. **Keep or revert** (default recommendation; the user decides).
   - Before the set, record target measures (published-output defect classes, as event
     counts with unit, opportunity and direction; cost is reported, never a target), guards
     (lost source requirement, unsupported addition, a critical criterion below its minimum,
     harmful repair, publication rate per case) and the run maximum.
   - Improvement: the pooled target count improves under a one-sided conditional binomial
     test at p ≤ 0.10 and doesn't worsen in either case that shows the class.
   - Guards: no guard count rises under the same test, the publication rate per case doesn't
     fall, and no class absent from the reference appears with an `established` trace to the
     changed owner. Hygiene phases (Q4 retry, Q5, a withdrawal in Q8) are kept on guards
     alone plus their **Keep if** measures.
   - Look after three runs per case; extend by two or three with approval; never sample until
     a preferred answer emerges. Fewer than about ten events across both states, or undecided
     at the maximum, is "not enough evidence"; a target absent from both states of a case is
     "benefit not demonstrated".
   - Aggregate and criterion scores decide nothing alone (one criterion step is 3.57 points).
     Say "kept", never "accepted".
8. **Reporting:** AGENTS.md's five evidence statements, separately.
9. **Comparison point:** the last kept measured state (§1).
10. **Model limitations:** AGENTS.md owns the rule and its exceptions; §9 adds no caps that
    discard output.
11. **Engine-track proof** (§5): offline on the scripted integration matrix against a request
    projection retaken on the commit before the item lands (current freezes
    `evaluations/request-projection/d23-2026-10-31` and `q10b-2026-10-31`). (a) Behaviour
    reproduces the freeze its ADR defines, or the ADR 0030 step traces and summaries, with
    expected differences stated before landing; (b) every accounted request's projection is
    byte-identical. One live run of each case; lands only between sets.
12. **Evaluation protocol:** the [protocol](../test/calibration/semantic-simplicity/README.md)
    owns its 24-feature panel; FIX06 sets use the two development cases and aren't protocol
    experiments.
13. **Adjudicability.** `adjudicate-spec` decodes `report.json` strictly
    (`src/domain/strict_json.zig`, `wireTypes`): removing or renaming a closed member a
    retained report carries strands that report, and adding a member needs a report version.
    Such a change lands only after H1 adjudicates the published set runs it strands, or the
    user records that they stay unadjudicated. Candidates: E1's request-lifecycle data keys,
    E4's repair keys, E5's split of `OperationExecutionFailed`, E9's `rejected_exact`, rule
    withdrawals in Q7 or Q8, `Relations.competing` (Q2b), Q13's would-have record, Q14 b2's
    and Q16's diagnostic reasons. `Relations.competing` and `rejected_exact` appeared only in
    failed, unpublished Q4 runs (`8be8…`, `7c6a…`), which are no longer retained, so removing
    them strands no retained run. **Decided 1 November 2026:** no members-only decoder (it
    conflicts with AGENTS.md's closed contracts and its ban on dual readers); runs before the
    closing set stay unadjudicated unless the user adjudicates them, so §2.13 no longer blocks
    a report version change.

**Boundary gates** for contract changes (from FIX01 §5, git `b2f10a3`). Offline tests prove
native mechanics only; negatives that turn on meaning are judged in live sets against
human-reviewed labels, never by native code or a new judge.

| Boundary | Positive evidence | Negative evidence | Applies to |
| --- | --- | --- | --- |
| Summary representation | Combined, split, overlapping expressions; complete membership; stable identities | Missing or foreign IDs, altered categories, false support, changed exact values | Q8 |
| Normalization | Idempotence; same-evidence duplicates collapse; raw and provenance kept | Different occurrences, distinct obligations, paraphrases, destructive truncation | Q8 (D8.3) |
| Native carry-forward | Empty, non-final, final, one/many-child routing; complete lineage | Stale or forged child content, changed evidence, fabricated origin | Any summary change |
| Repair | Exact target and dependencies, protected siblings, progress, full final validation | Stale authorization, widened scope, reset allowance, invalid survivor | Q2b, Q13 activation, Q14 b3, E4, R6 |
| Loss attribution | Bound comparisons locate candidate-only and upstream loss | Missing or duplicate assignments, uncertain owners treated as certain, false upstream rebuilding | R6 |
| Exact-value representation | Occurrences from exact bytes in bound fields survive repair and readback | False matches, ambiguous occurrences, unbound fields, changed obligations | Q7, R6 |
| Loss-evidence correction | Correction preserves subject, finding and scope; validation reruns before repair | Nonexistent lines, stale producers, verdict replacement, budget reset | R6 |
| Cross-model behaviour | Paired repeated trials in unrelated domains | Meaning changed despite valid JSON, false rejection, unsupported acceptance | H5 only |
| Whole workflow | Real publication of the expected outcome, complete required review, H1 adjudication | Early stop reported honestly; no golden outputs or advisory analysis as acceptance | Every set |

## 3. Priorities

Ranked by expected reduction of published-output defects (AGENTS.md). Tracks: **Q** quality
phases (model input or published output change, each measured), **E** engine (no
model-input change except E7), **T** tests, **H** human decisions, **R** research. "Gap" means
between measurement sets.

**Output track** (recommended order; each needs its decision first):

| Rank | Item | Defect class reduced (publications of 18) | Effort | Validation | Decisions |
| --- | --- | --- | --- | --- | --- |
| 1 | **Q7 D7.4** render a model-quoted exact value without the engine's code span | rendering artefact (18; 70 doubled delimiters) | S–M | A set while review requests carry the projection's code spans; offline only after D13.1 | D7.4 |
| 2 | **Q12 D12.1** records stop receiving the brief and entity basis | weakened obligation in FRs (all 4 copied loan-renewal FRs), FR equal to an unpublished draft (9), copied additions (2) | S | Measurement set | D12.1 |
| 3 | **Q13** remove both post-generation reviews, then show source lines inline (decided) | removes review's false findings, runaways and budget stops; inline lines make every link visible to the reader | L (remove), M (inline) | §2.11 proof and one run per case; inline lines offline | D13.1 decided |
| 4 | **Q12 D12.2** story and description purposes name obligation strength | weakened obligation in the story (loan-renewal 15 of 16 since Q1b) | S | Measurement set (enough events) | D12.2 |
| 5 | **Q14** scenarios bound to their claim by the engine | lost source requirement (loan-renewal 3 of 9) | M (b2) to L (b3) | Measurement set | D14.1 |
| 6 | **Q15** entity applicability and restating meanings (B6) | invented or restating entity (17) | M–H | Offline rebuild, then a set | D15.1 |
| 7 | **Q16** one statement record per claim | restatement (5) | M | Set, up to 8 runs per case | D16.1 |
| 8 | **Q7 D7.5** a plain string only where a field offers no insertion | rendering artefact (1 joined-fragment story) | S | Measurement set | D7.5 |
| 9 | **Q7 D7.2** withdraw ADR 0045, keep ADR 0036 Decision 6 | none directly (docs) | S | None | D7.2 |
| 10 | **Q17** principles as context for Spec generation (decided) | none scored today; guards only unless the rubrics gain a principle criterion | M | Measurement set | D17.1 |

**Robustness track** (run completion, the Incomplete banner, budget; no scored defect):
Q10b step 1's keep decision and the exact-value review fault (Q10b); E5's §22.6 correction
location; budget headroom (H4). Three loan-renewal runs on `ddbc6d9` stopped on the
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
2. D13.1: revert D10.2 in full, then remove both post-generation reviews in one change.
   Generation requests stay byte-identical, so §2.11's proof plus one live run per case.
3. Q13 inline source lines; then Q7 D7.4 (both offline-proven once no request carries the
   projection).
4. Q12 D12.1, a measurement set.
5. Q12 D12.2, a measurement set.
6. Q17 principles as records-call context, a measurement set.
7. Q14 b3, a measurement set.
8. Q7 D7.5, a measurement set; D16.1 and D15.1 revisited on the results.

**Recommended, not yet decided:** D5.1 no; D8.1 keep, record only; D10.3 record as a model
limitation (moot after D13.1); close D2.2, D11.3, Q9 (keeping the capture replays E4 needs)
and W5; Q10a closed (moot after D13.1).

**Engine track, in gaps:** E2 early; E3 after E2's first measure (nothing technical ties
startup to E1); E1 in any gap, retaking its freeze on the commit before it lands; E6 and E8 in
any gap; E4 after E1, E2's measure and Q9's capture replays (ADR 0033:264); E5's closed
reasons with the E1–E4 conversion that rewrites them, its evaluator gap in any gap; E9 with
E1, E4 or E5; R-A1 after E1; E7 last. E0 is on hold. E1, E4, E5 and E9 land only under §2.13.
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
- remove `Relations.competing` under §2.13 (`reference_reconciliation_diagnostic.zig:159-161`);
- fold `member_count` into the `collection` variant (`model_result_schema.zig:98`, `:214`);
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
(both `citations` sentences, the `claim_ids` definition, `records.prompt.md:9-11`).

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

- **D7.4** Render a model-quoted exact value without the engine's code span: when the plain
  text immediately around an exact copy forms a balanced pair from the existing closed wrapper
  table (`exact_value_boundary.zig:82-100`, `:163-189`), the projection gives that copy no
  span. No model bytes or canonical state change and no meaning is judged. The public
  `evaluate()` already reports `enclosing_wrappers` (`exact_value_boundary.zig:70-73`, `:82-100`),
  so the private table isn't copied. Effort S–M: `specification_projection.zig:90-119` plus
  owner tests; it must change the projected document, not `render()`, because two tests require
  parse(render(doc)) == doc (`specification_generation_test.zig:9216-9217`, `:9351-9352`) and
  publication checks render(project(state)) == render(parse(bytes))
  (`prepare_specification_output.zig:23-28`; `validate_specification_rendering.zig:13-19`). No
  editable-view reparse exists yet (Plan is gated). Amends 23-rendering.md:99-100,
  text-field-composition.md:75-81 and ADR 0036 Decision 6 (or a new ADR). Brackets and
  parentheses are in the table too (none in the retained runs). **Model input changes:**
  source, principle and loss review requests carry the projection's `code_spans` (35 of 178
  retained requests, all with quoted spans), so it needs a measurement set while
  post-generation review exists; if D13.1 removes it, no request carries the projection and it
  is proven offline. No tool re-renders a stored state (the projection needs live
  reconciliation data, `specification_provenance.zig:10-15`, `:31-34`); the offline proof is a
  test that parses each retained spec.md, applies the rule and re-renders: A from 26 to 0 on
  the 7 retained runs (70 in the 18 scored).
  **Decided 1 November 2026:** not a punctuation rule. The engine decides only whether to add
  its own delimiter, from the closed wrapper table recognition already applies (ADR 0036); no
  model bytes change and no meaning is judged. Built after D13.1, so it is proven offline.
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
- **D7.2** Decide ADR 0036 Decision 6 and ADR 0045 (on hold) together. Built without D7.4,
  ADR 0045 would double the delimiter on every quoted entity value (5 of 7 in the retained
  runs); after D7.4 it adds none and fixes the bare values. It would also add entity spans to
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

D8.2 and D8.3 are decided offline with fixtures at their owners and §2.11 projections, in any
gap, or recorded.

### Q9. Reconciliation call structure (W4)

Reconciliation is 4–9% of a published run's tokens; combining dispositions, signals and
conflicts saves at most two sends and 2–4% of tokens and reduces no defect class. **D9.1**
(combine only on capture-replay evidence) amends ADR 0022, §16.4 step 10, ADR 0016's
assignment contexts and ADR 0033's per-phase owners. **Recommended (not decided):** close Q9;
keep only the `model-request-debug/v13` capture replays E4 needs (ADR 0033:264).

### Q10a. Publish source-review findings as advice (B2)

**D10.1** Amend ADR 0023:79-80 (as amended by ADR 0040:11-14) and the `reference-context.md`
rendering text (17-specify.md:469-471, 23-rendering.md:148-158, F0100:961-964) so negative
source findings appear as an advisory section (`reference_context.zig:100-123`). In the 18
runs this would have published 19 notes, 16 of them misleading (13 on clean subjects, 2 of the
wrong type, 1 with a false rationale; the false AC-001 note in 7 of 9 hello-world runs), and
left spec.md unchanged. **Recommended (not decided):** close in favour of Q13.

### Q10b. Simplify the source-review taxonomy (B2)

Step 1 (D10.2) is implemented, uncommitted ([Z_FIX06](Z_FIX06.md)). **Not kept** (decided 1
November 2026): it cannot change the spec (ADR 0023), and D13.1 removes post-generation source
review. It is reverted in full as the first step of D13.1's change set (§2.1), which returns
`specification-state` to v19. Q10b's later steps are moot.

**The exact-value review fault** (the only later step with an output link): every runaway
and SyntaxError in the 18 runs is a `supported` finding whose `detail` string is never closed,
on an exact-value reference subject: 8 of 62 such calls against 0 of 190 other source-review
calls (14 of 92 against 0 of 260 in the 36 runs retained on 31 October), 88,364 tokens. A runaway on the
re-send ends advice incomplete, and a budget stop publishes nothing. Levers (no caps):
- remove the `supported` detail field (amends ADR 0023:74-77 and `support.schema.json`);
  measured with approved `e2e-call --repeats` on a retained exact-value request against the
  12.9% baseline (0 faults in 30 repeats gives p ≈ 0.016);
- or drop exact-value reference subjects from post-generation advice: their duty is native
  (ADR 0024:29-50); 62 calls, 0 true findings, 17% of review tokens; amends ADR 0023:218-221
  and the §17.3 subject list, and removes a check (the user's call).

The data can't separate "exact-value subject" from "a quoted value ending in punctuation" as
the trigger: all three exact values end in `!` or `.`.

**Other later steps** have no output effect and are superseded if Q13 replaces the review:
the packet-guidance step (`review_scope`, `support_evidence`, including the `authority_gap`
clause advisory packets still carry, `specification_support.zig:419`); rewriting
`support.prompt.md` (`:22-33` still describe the withheld verdicts); unifying `finding` and
`applicability_finding` selection (`support.schema.json:123-130`, `:148-157`; raw-string
choice at `specification_support.zig:218`, `:442`, E8; projection-branch rule drop at
`:436-439`); merging `preservation_finding`.

### Q10c. Principle-review citations (B11)

**Defect:** every principle citation is a whole file or absent: in the 18 runs 286 of 286
findings were `compatible`, 277 cite a whole chunk, 9 none, 0 a part, and no adverse finding
appeared. The packet gives each principle unnumbered as one 16 KiB chunk
(`principle_registry.zig:11`, `:148`). The one published principle defect was an
`array_length` exhaustion (`07-37-10Z-f5c2…`: 2 of 14 findings twice), which published
"Review status: Incomplete". **D10.3:** record citation precision as a model limitation, or
change the citation instruction (`principle.prompt.md:14-18`) or presentation (numbered
lines, smaller chunks). **Recommended (not decided):** record it. No rule may inspect citation
text; ADR 0042's admission constraint stays. Line-citeable principles are a precondition of
D13.4's conflict check.

### Q11. Story-restatement deletion

**D11.3** ADR 0035: never delete a covered restatement whose claims no other record names (the
user confirms that claim IDs are the reading of "last mention"). Only a story restatement can
do that (`restatesStory`, `specification_generation.zig:348-353`); it hadn't fired since
`8a600d7` in the 54 runs retained before 31 October, and no restatement or duplicate-record
deletion appears in the 36 runs retained on 31 October. **Recommended (not decided):** close as record
only.

### Q12. Copied and weakened obligations

**Defect:** weakened obligation, loan-renewal 8 of 9 (15 of 16 since Q1b), by two routes:
- **Copy route.** The records request receives the unpublished brief
  (`specification_session.zig:289-293`) and the entity decision with its basis (`:303-306`;
  17-specify.md:317-320; `records.prompt.md:1` tells the model to use the brief). FR-001 lost
  "must" in all 4 loan-renewal FRs copied from these drafts (both current ones copy the entity
  basis byte for byte) and in none of 12 written fresh; FR-001 equals the basis byte for byte
  in 9 of 18 runs; "followed by" orderings travelled the same way (2 of 18). Neither draft is
  published (`specification_markdown.zig:22-28`).
- **Story route.** The story request (call 8) receives the claims verbatim ("must be able to
  renew") and no drafts, yet says "may renew" in 15 of 16 loan-renewal publications. The FR
  field purpose names obligation strength (`packet-guidance.json:15`) and fresh FRs keep "must"
  in 12 of 12; the story and description purposes (`:7`, `:5`) don't.

- **D12.1** Stop sending the brief and the entity decision to the records request and its
  repair packets; the request keeps the full sources, claims, exact texts and record
  requirements, which is everything records uses: records admission, consistency and coverage
  never read the brief, the entity decision or the title (`specification_session.zig:69-88`,
  `:505-536`, `:320-324`). Files: `specification_session.zig:185-189`, `:287-295`, `:298-308`
  (records repair packets come through `specification_repair.zig:260`); delete
  `EntityDecision` and `entities()` (`specification_projection.zig:8`, `:20-23`; used only at
  `specification_session.zig:305`; `Brief` stays for the entities request); the records-only
  "prior drafts" sentence in `generation.context.json:4` and 17-specify.md:331-333;
  `records.prompt.md:1`; tests `specification_generation_test.zig:322-330`, `:410-428`,
  `:3335-3347`. Amends 17-specify.md:317-320 and :331-333; no ADR. Effort S. A multi-group
  batch still receives every other group's claims (`context_requirements`, `:225-232`); it
  loses only the model-written title, description and goal, and the disposition and basis.
  **Keep if** FR weakening per
  loan-renewal run and FR text equal to an unpublished draft fall to zero, and restatement,
  lost source requirement and publication don't worsen. **Approved 1 November 2026:** the
  first model-input change (§3 build order).
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

### Q13. Review that checks each link (redesign of post-generation review)

**Defect:** review can't improve the published output. Under ADR 0023 post-generation
findings never repair, block or ask (0023:74-82, :159-167), and source findings aren't shown
to readers. In the 18 runs review used 70.8–84.7% of tokens (median 77.3%; source 53.1–73.1%,
principle 11.1–25.1%). It flagged 4 of the 47 non-rendering defects (3 with the right type)
and passed 43: weakened obligation 0 of 10, unsupported addition 1 of 10, entity 2 of 17, lost
requirement 1 of 3, restatement 0 of 7. Of its 19 negative findings, 4 were right, 2 had the
wrong type and 13 were on clean subjects. Required review ran in none of the 18.

**Causes** (verified on `10-23-59Z-caf58f4…` calls 18 and 21 and `07-35-27Z-0669…` calls
10–12):
1. It asks whether one field is supported by the source; content in the wrong place (an
   entity restating FR-001, a duplicate record) is "supported" by that question.
2. It sees one record and is told not to judge the whole (`support.prompt.md`: "do not
   require sibling conditions to be repeated in it or replace its finding with a verdict on
   the whole unit"), so duplication and missing scenarios are invisible.
3. It is given the generator's claim links as fixed evidence ("Native code fixes claim
   evidence for the assigned subject"), so a false link passes (loan-renewal AC-001).
4. Its prompt describes seven verdicts, authority gaps and readiness rules; after D10.2 three
   verdicts are offered and the prompt is unchanged.
5. A right answer (call 21, the entity decision) changes nothing.

Making today's findings drive repair would harm the output: at 4 right findings in 19, most
repairs would hit clean subjects (net harm if more than about 27% of wrong repairs do harm).

**Proposal (not decided):** replace post-generation source review with link checks.
- **Deterministic first:** every record has a link, every claim is linked, no byte-identical
  duplicates, exact values kept.
- **One focused, blind question per link:** "Which of these source claims does this record
  state? Quote the part." The engine compares the answer with the generator's `claim_ids`; a
  mismatch, or a stated claim with weaker obligation or added content, is a finding typed as
  a rubric defect class (lost source requirement, weakened obligation, unsupported addition).
  A reverse check per claim (which records state it) finds omissions.
- **Evidence-bound:** a finding names its claim and quotes the record and the source; the
  engine checks that the claim exists and that both quotes exist byte for byte. A finding that
  fails is rejected and the model is asked to repair it with guidance naming the error (D13.6),
  within the retry limit; on exhaustion the advice ends incomplete (ADR 0040).
- **Regeneration:** only the engine-selected record, with the engine fixing its claim IDs;
  guidance is the finding's claim text and defect type. The replacement is accepted only if it
  keeps its other links and exact values, passes native validation and passes the same link
  check; otherwise the original stays and the finding is published marked (ADR 0040).
  Additive actions (a missing scenario) are enabled before rewrites; deletions stay advisory.
  Attempts stay within existing retry limits; no voting or re-asking until positive.
- **Shadow mode:** the checks run in every live run under today's advisory policy (ADR 0023
  unchanged) and record would-have actions; `/evaluate-e2e` scoring and H2-confirmed labels
  give precision, recall and projected harm per finding type. Optional dry-run regeneration
  into an unpublished copy grades each replacement helpful, neutral or harmful.
- **Activation:** per finding type, by user decision as a typed policy, once precision meets
  the user's threshold (for example 90% on at least 30 confirmed findings) with no harmful
  dry-run regeneration. A type that never qualifies stays advisory, recorded as a model
  limitation.
- **Principles:** a record's origin is a source claim; principles are project-level
  constraints checked for conflict, which needs line-citeable principles (Q10c).

**Brittleness:** model-dependent control flow (contained by deterministic action rules
testable with scripted answers), cascades (one regeneration per record per finding; the
original stays on failure), more model-facing text (guidance is typed finding content with one
owner; ADR 0033's generic operations; today's `support.prompt.md` goes), overfitting
(AGENTS.md's rule; both cases plus an unrelated fixture) and budget (checks replace today's
review, not add to it). T5's counts are taken first so the effect can be reported.

**Alternative (user proposal, 31 October 2026): no post-generation review, with each item's
claims shown inline.** Removing review is not decided. **Decided 1 November 2026** (user: "the
claims associate with the AC, FR and EN should be placed after each AC, FR and EN"): spec.md
shows, after each AC, FR and EN, the claims linked to it with their source file and lines.
**Format decided 1 November 2026:** file and lines only, one line per item with the source
file and merged line ranges, computed from the item's claims and their citations. Target
output (hello-world `10-23-59Z-f331…`, rendered from its `reference-context.md` links):

```markdown
- **AC-001**: **Given** The application is not yet running\. **When** … **Then** …
  - Source: `references/hello-world/stories.md` lines 5–7

- **FR-001**: The application must start successfully\, display the exact text …
  - Source: `references/hello-world/stories.md` lines 5–7

**EN-001**
- **NAME** Hello World Application
- **BUSINESS MEANING** The application must start successfully\, …
- Source: `references/hello-world/stories.md` lines 5–7
```

Several files join with "; " (`a.md` lines 3–4; `b.md` line 9). Open: approval to implement
(record only for now). It amends 23-rendering.md and F0100's spec format, and the §23
editable-view reparse (23-rendering.md:90-103) must use the same projection, so the added lines
can't break a user-edited spec.
- **Inline sources (decided; effort M, about 8 src and 4 test files):** the lines come from
  `traceRequirements` (`specification_projection.zig:37-52`), the owner reference-context's
  "Generated Requirement Sources" already uses (`reference_context.zig:84-94`; paths
  `:28`; span ends are exclusive, `source_coordinates.zig:2-23`). The projection gains a
  typed sources view on each AC, FR and EN record. The reference snapshot is built after
  rendering today (`spec.workflow.yaml:851-875`), so `build-reference-snapshot` moves before
  `project-document`, or `project-document` takes the reference directory. The codec renders
  and parses a protected line so the publish-time round trip holds
  (`validate_specification_rendering.zig:13-19`); it must not collide with the two-space
  continuation rule (`specification_markdown.zig:354-366`). No state or report version
  changes, and no model request changes. Amends 23-rendering.md:128 ("Reference citations are
  not rendered into the business-only file"), :152-153 (spec grammar unchanged), :116-118 and
  F0100 §5.1. Offline proof needs a new test: strict-decode the 6 retained v20 states,
  compute the sources, insert them into the retained spec.md and check the round trip and the
  ranges against "Generated Requirement Sources". Small open choices: "line 6" for a single
  line, records whose provenance is only clarification answers, incomplete (pending) views,
  and whether reference-context keeps its own section.
- **Removing review:** source and principle review can't be split. Principle review starts
  only after an accepted post-generation source review (`specification_review.zig:14-31`), and
  the advisory machinery goes only when both go, so the clean option removes both in one
  change. Effort L, about 45–60 files and a net deletion of several thousand lines, mostly
  tests: the `review-candidate` subgraph and post-generation gate, `candidate-gaps`, every
  advisory route (`spec.workflow.yaml:625-650`, `:702-749`, `:956-1094`), about 820 lines of
  post-only modules, the advisory branches in shared runner files, the spec.md "Review
  status" line and reference-context's review and principle sections. The post-generation
  gate's only native check (a missing AC or FR family) is already enforced by generation and
  state validation (`specification_session.zig:160-172`; `specification_state.zig:104`). Stays:
  required review, loss review, `support.prompt.md` and `support.schema.json` (required parts),
  and principle capture (Q17 needs it). Versions: `specification-state` v21, `spec-e2e-report`
  v12 (§2.13), `baseline-acquisition` v9, `packet-guidance` v2 if review-scope keys go; the
  ADR-required `review.incomplete` event retires. Effect: review can no longer stop a run on
  budget, and it frees 71–85% of each run's tokens (53–73% is source review).
- **Limits:** a citation is only as true as its link (loan-renewal AC-001 would cite the
  refusal line it doesn't state), so it pairs with Q14 b3; story and entities cite whole groups
  (R1); semantic checking rests on human adjudication (H1).
- **Amends** (removal): ADR 0023 (retire), ADRs 0040 and 0042 (moot), ADR 0030's advisory
  carriers, ADR 0039's advice-incomplete clause, ADR 0011's advice budget text, ADR 0041's
  review-failure clause, design.md §3.3 invariants 20 and 22, §§12.6–12.8, 17.3–17.4, 22, 23,
  24, F0100, design/harness/e2e.md, acceptance.md:141 and the evaluate-e2e skill. Q10a, Q10b
  and Q10c become moot, and D10.2 is reverted in full (§2.1). Link checks stay possible later.

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
  `enum_mismatch` (`model_payload_schema.zig:119`, `:128`) and gets a protocol correction
  within the step's retry limit. No such correction fired in the 18 runs.
- **Gap, the guidance:** the correction says only "this value is not among the allowed
  values" (`model_schema_diagnostic.zig:33`), and its expected shape for an ID choice is
  `{"type":"integer"}` (`model_schema_projection.zig:73-77`). It names neither the rejected
  ID nor the IDs that exist.
- **Change (approval needed to implement):** the `enum_mismatch` correction for an ID choice
  names the rejected value and lists the allowed IDs, both taken from the compiled choice,
  never hard-coded (D4.1's precedent for `uncovered_member`). It changes model-visible
  correction text only; first requests stay byte-identical (§2.11). Proven offline: a
  scripted non-existent claim gets the named correction and an accepted retry. A set can't
  measure it, since it didn't fire in the 18 runs.
- In Q13's link checks, the claim a finding names and its quotes are checked the same way
  (see "Evidence-bound").

**D13.1 decided 1 November 2026:** remove both post-generation reviews (source and
principle) in one change, after reverting D10.2, and show inline source lines. Link checks
(the proposal) aren't built; D13.2 and D13.3 lapse unless review returns.

**Decisions:** **D13.1** (decided above); **D13.2** the activation threshold, and the ADR 0023 amendment per activated type (also
design.md invariants 20 and 22, 22-repair.md:220-231, ADR 0023:350-357 and :400-403);
**D13.3** dry-run regeneration; **D13.4** decided 1 November 2026: principles are context and
constraints only, never origins, and never modified (Q17).
**Feasibility:** M–L: a new review contract (unit, closed outcomes, guidance shape), a packet
builder, a would-have record in reports (a report version, §2.13) and its evaluation;
activation reuses ADR 0033's repair operations. Approved `e2e-call` replays of retained
records calls can estimate precision before a live set. **Keep if** (shadow): publication and
guards unchanged and cost not above today's review; activation decided per type on precision.
Add link checks later, in shadow mode, only if adjudication shows semantic defects that the
deterministic checks and the generation-side items (Q12, Q14, Q15) leave.

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
  not a prerequisite. Coverage must move from payload admission (`model_payload_schema.zig:155-170`,
  where no typed candidate exists and only a whole-response retry is possible) into the unit
  validator beside entity membership (`specification_generation.zig:252-267`). Insert repair
  exists today only for entity membership (`specification_repair.zig:50-67`, `:127-140`,
  `:373-377`, `:469-476`); the record gates at `:252`, `:373` and `:469` lift, a group policy
  for a fixed claim is added, and the unused content-only `repair_record_acceptance_criterion`
  schema (`generation.schema.json:527-538`) gains an edge-case counterpart. ADR 0038 Decision 1
  already says repairs stay content-only and keep the record's claims (0038:51-52). Deletes the
  admission-time coverage check and D4.1's covering-kinds correction
  (`model_payload_schema.zig:49-57`, `:155-170`; `model_schema_diagnostic.zig:37`;
  `model_protocol_retry.zig:60`; `specification_session.zig:317-324`, `:362`). Amends ADR 0038
  Decision 3 (:57-64, :120-122), 22-repair.md:271-275 and :609-614, 12-model-boundary.md:131,
  17-specify.md:249-252, F0100:1405 and design.md:1160. An inserted scenario still links
  without checking meaning.
- **b2:** the scenarios naming a claim must together contain every exact value its quoted text
  requires (IDs and exact bytes; `exact_token_obligation.zig:47-57`). On the 24 retained
  records responses it fires only on the two false links; it misses claim 4 and
  business-rule-only cases; it runs after parsing (`specification_coverage.zig:107-135`), so
  its failure route (coverage repair or block) needs a decision, and it adds a report reason
  (§2.13). Effort M–L.
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

### Q16. One statement record per claim

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
  reason (§2.13); a `records.prompt.md:9-11` sentence (model input). Effort M; 7 events, so
  plan up to 8 runs per case.

**D16.1 decided 1 November 2026:** deferred until Q12 and Q14 are measured; build then only if
restatement remains (D12.1 removes the BR-with-the-only-"must" hazard, and b3 extends coverage).

### Q17. Principles as Spec context

**Decided 1 November 2026** (user): "the workflow must never modify principles - NEVER" and
principles "should be used for context when executing the spec workflow".
- **Never modified:** holds today. Principles are read through a read-only source adapter
  (`src/adapters/filesystem/principle_source.zig`: reader, enumerator, capturer), and path
  validation rejects every project operation against the semantic-principles root
  (11-path-validation.md:20). Every future step (Plan, Implement, init, repair) keeps it; it
  becomes a design.md §3.3 invariant when the design is next amended.
- **Context:** today no generation call receives principles. In `10-23-59Z-f331…` calls 1–22
  carry none; only the post-generation principle review (call 23) does. Adding them changes
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

Each item: `/preflight`, offline tests, the §2.11 proof, `zig build verify`, one live run
per case (DE2 and DE3 ask whether offline evidence replaces it), landing between sets and under
§2.13.

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
**Decision** with E1: keep or remove `propagate-advisory-request-failure` (ADR 0030:625-628).
If it removes a request-lifecycle `DataKey`, it lands under §2.13.

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
variants keep those reads. Retained reports carry repair keys, so it lands under §2.13.
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
- **Support-findings diagnostic origin** is its collection's first review call
  (`candidate_validation_diagnostic.zig:78-80`), not the finding or localization call
  (`2026-10-31T02-53-14Z-da42…`); it feeds the log event and CLI output, and e2e.md:568-570
  defines "review origin", so which call counts is a contract question. **Recommended:** define
  it as the call that returned the outstanding finding, using the per-evidence `origins` the
  diagnostic already carries (no new data). Moot if D13.1 removes post-generation review.
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

Domain code names result-schema definitions by raw strings. Partly done: D10.2 replaced the
`specification_support_repair.zig` branch with typed correction shapes; one site still
branches on a second copy (`specification_review_retention.zig:80`), and the rest fail only at
request preparation (`model_request_handoff.zig:351-352`; sites in `specification_support.zig`,
`principle_assessment.zig`, `specification_session.zig`, `specification_repair.zig`,
`reference_model_input.zig`, `reference_reconciliation_*.zig`,
`reference_extraction_*repair.zig`). Bind them as closed IDs checked at schema load. Test
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
with the freeze §2.11 takes on that build, and T5.4 by hand from `spec.workflow.yaml` (a
`slot: repair` step whose prompt no non-repair step binds).

## 7. Human and decision track (H)

### H1. Adjudication (R8)

Only a human `human-spec-adjudication/v2` record applied with `zig build adjudicate-spec`
decides acceptance; none exists. Only 7 v11 runs remain under `zig-out/` (the Q10b set and
`07-37-18Z-61b3…`); they should decode on the current build (by inspection only), and any
later member change strands them (§2.13). The other 31 October runs (11 of the 12 D2.3 runs
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
- **Harness acceptance (former H-012, H-013, H-017; git `8ed40ba`), rechecked 1 November
  2026.** Covered by tests, so closed: shorter replacements (`file_access.zig:136`;
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
