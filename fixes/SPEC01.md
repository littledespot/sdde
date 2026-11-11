# SPEC01 — Open Spec work

The fix record for open work and user decisions not yet recorded in an ADR
([convention](README.md)). Each phase needs the user's approval before its changes, and
every live run needs its own approval. **Decision** marks a question only the user settles;
a recommendation is not a decision. Implemented items are in [Z_SPEC01](Z_SPEC01.md); closed
and reverted work, superseded measurements and earlier references are in git history
(`fixes/FIX06.md` before 9 November 2026; earlier items at `39fd9ff` and `0f3e4d2`).

## 1. Gate status and output quality

**Gate (ADR 0034): the user's to declare.** On 9 November 2026 the HEAD set, the first set on a
committed, unmodified build (`a3d083e`, source `5fb59f67…`, 3 runs per case, none retried,
`2026-11-08T22-3*`), published 6 of 6, and `adjudicate-spec` accepted every run (skill
`185b9bc6…`, no critical failure) with no lost or weakened requirement ([Z_SPEC01](Z_SPEC01.md)
Next 6). **Judged 9 November 2026** (user: "three per case is enough for now"): the HEAD set is
enough stability evidence for now. ADR 0034 leaves actioning Plan to the user, so none is
started.

**Reference** for quality phases (§2 rule 7): the HEAD set, the last kept state (§3 Next items
6, 7 and 8). Skills `af394020…`, `0b552067…`, `1d66d882…`, `3c74781e…` and `185b9bc6…` count
as one evaluator ([Z_SPEC01](Z_SPEC01.md) T7). Accuracy defect counts, content basis, as lost /
weakened / unsupported addition / contradiction:

| Case | Publications | Pass | Defects | Advisory score, mean (range) |
| --- | --- | --- | --- | --- |
| Hello-world | 3 of 3 | 3 of 3 | 0 / 0 / 0 / 0 | 94.0 (92.9–96.4) |
| Loan-renewal | 3 of 3 | 3 of 3 | 0 / 0 / 4 / 0 (three are AC-001's minor "records the loan as renewed") | 90.5 (85.7–92.9) |

Advisory scores are scored against the case rubrics (`evaluations/e2e/<run>/evaluation.json`);
scorer judgment moves one by about ±3.6, and keep decisions use the accuracy counts (§2 rule 6).

**Retained runs:** `zig-out/e2e-spec/` holds the HEAD set and twenty runs of 8 November 2026
(report v15, `build.source.modified` true): the `5b34dbc` "Repeated-statement text not
judged" set (`2026-11-08T00-39-26Z` to `00-45-47Z`), two `input_invalid` runs (`00-36-27Z`,
`00-37-49Z`), the entity and escaping set (`05-5*`) and six edge-case-lever runs on `071ce2b`
(`09-2*`). Earlier runs are removed; their evaluations and measures stay under `evaluations/`.
The current build decodes only `spec-e2e-report/v15` (`test/harness/e2e/contracts.zig:140`).

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
     blocks only when it crosses the effect size recorded before the set. Hygiene phases (Q4's
     retry, Q7 D7.5) are kept on guards alone plus their **Keep if** measures.
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
    naming no member). Their `1d66d882…` adjudications stand; their `3c74781e…` re-scores (§3
    Next item 3) stay unapplied. The twelve `05-5*` and `09-2*` runs are adjudicated under
    `3c74781e…`.

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
phases (model input or published output change, each measured), **E** engine (no model-input
change except E5's correction location and E7), **T** tests, **H** human decisions, **R**
research, **C** code-review findings (§10; none scheduled). "Gap" means between measurement sets.

**Next:**

1. The bare-value `reference_only` correction and the repeated-statement change are
   implemented ([Z_SPEC01](Z_SPEC01.md)). The correction is kept or reverted on a repeated set of
   both cases on one committed build, scored on published output and publication rate; sets
   where it never fires are not enough evidence. Its one live firing (8 November,
   `2026-11-07T20-44-15Z-9273…`, uncommitted tree) changed nothing: all three records attempts
   returned the same bare outcomes and the run exhausted its retries. The repeated-statement
   change is judged on the same set: it removes that failure where the bare outcome is a
   repeat, and the correction serves the rest.
2. **Closed 8 November 2026:** skill `1d66d882…` is the same evaluator as `af394020…` and
   `0b552067…` ([Z_SPEC01](Z_SPEC01.md) T7).
3. **Decided 8 November 2026** (user: "recommendations accepted for 1 to 6"): a title that
   repeats a requirement's value states it (§7 H1 "Titles"). The re-score of the reference it
   required is done (9 November 2026, skill `3c74781e…`, `evaluations/e2e/<run>/`); its records
   are unapplied (`adjudication-record.3c74781e-unapplied.json`, §2 rule 12).
4. **Decided 8 November 2026** (same words): Q14 b3 stays held and b4 is not started. Revisit b3
   if refusal scenarios go missing (§4 Q14).
5. Lossy repeats in titles have no lever (§3 open problems).
6. **Kept 9 November 2026:** an entity is a name and its groups ([Z_SPEC01](Z_SPEC01.md) Next 6).
7. **Kept 9 November 2026:** the renderer escapes only the bytes Markdown reads as markup
   ([Z_SPEC01](Z_SPEC01.md) Next 7).
8. **Kept 9 November 2026:** an edge case's outcome is the Then of a linked criterion
   ([Z_SPEC01](Z_SPEC01.md) Next 8). Evidence for it: EC-001's free-text outcome dropped
   "calendar", "existing" or the new due date, failing `successful-renewal` in 4 of the 6
   loan-renewal runs before 8 November and 2 of the 3 that day. ADR 0038:227-228's limit still applies: a success criterion
   citing the refusal claims can be a refusal edge case's only candidate and print the success
   Then. No HEAD-set run was scored with that defect; changing the link rule amends ADR 0038
   Decision 7 (a **Decision**).

**Output track** (recommended order, not decided, inside the decided constraints: D17.1 puts
Q17 after D12.2, and D14.1 holds Q14 b3; each change set is measured on its own committed
build, §2.1 and §2.3):

| Rank | Item | Defect class reduced | Effort | Validation | Decided |
| --- | --- | --- | --- | --- | --- |
| 1 | **Q14 b3** | lost source requirement: the add-a-link route of the missing refusal scenario (`728d…`; not `fa03…`'s first-attempt route, §4 Q14) | L | Measurement set | D14.1: held (§3 Next item 4) |
| 2 | **Q17** principles as records-call context | none scored; guards only unless the rubrics gain a principle criterion | M | Records screen, then a set | D17.1 |
| 3 | **Q7 D7.5** a plain string only where a field offers no insertion | rendering artefact C (joined fragments): none published since ADR 0047 composes the story; conformance only (§4 Q7) | S | Screen, then a set | D7.5 yes, a conformance fix |
| 4 | **Q4** retry, with D4.1's extension | engine vocabulary (none published; AGENTS.md compliance) | S | Screens of each changed call kind, then a set | D4.1 extension yes |
| 5 | **Q21** behaviour claims need statements | lost source requirement: a behaviour claim no statement names, passed through a whole-group selection (none since ADR 0047) | M–L, by D21.1 | Fixtures at the owner, screens of each changed call kind, then a set | D21.1 deferred |

**Robustness track** (run completion and budget; no scored defect): E5's §22.6 correction
location. Since D13.1 the measured runs show 0 runaways and 0 re-sends; the highest used 67,448
of the 125,000-token workflow budget (`2026-11-02T02-28-14Z`, which reached source review), and
the HEAD set used 12,971 to 17,037 tokens a run. Runs since ADR 0047 have failed only by retry
exhaustion, never budget, in two modes, each reported with no lever:
- records, on the bare outcomes `"Loan renewed!"` and `"Renewal refused."`: where the bare
  outcome is a wholly taken repeat its text is no longer judged ([Z_SPEC01](Z_SPEC01.md)
  "Repeated statement text is not judged"); `2026-11-07T06-12-34Z-f549…`'s outcome was the only
  non-scenario record naming its claim, so that case still fails;
- reconcile dispositions (`2026-11-07T20-44-02Z-9d7f…`, hello-world): the model answered with
  prose and no JSON on all three attempts, from a request byte-identical to one that succeeded:
  the model's variance under a coherent contract.

**Engine track, in gaps:** E2 early; E3 after E2's first measure (nothing technical ties
startup to E1); E1 in any gap, retaking its freeze on the commit before it lands; E6 and E8 in
any gap; E4 after E1, E2's measure and its capture replays (§5 E4); E5's closed reasons
with the E1–E4 conversion that rewrites them, its evaluator gap in any gap; E9 with E1, E4 or
E5; R-A1 after E1; E7 last. E0 is on hold. E1, E4, E5, E9 and T8 land only under §2.12. E1–E4
before the closing set is the user's call (ADR 0034:93-95). **Tests:** T2, T3 and T8 in any
gap; T4 with E1–E4. **Adjudication:** H1 (the evaluate-e2e skill) for every set.
**Human:** H2 when required source review is labelled or review returns; H3 when the user
reviews the panels; H4 before any formal baseline freeze; H5 at the user's choice. **Closing
set:** repeated runs of both cases on one committed, unmodified build (ADR 0034:55-56) unless
the user amends ADR 0034; every counted published run adjudicated (H1). The HEAD set (3 per
case) is enough for now (user); a later structural change (E1–E4) re-opens whether the gate is
re-run on the new build (ADR 0034:93-95).

**Open problems without an item.** Each stays until a structural lever with an owner is found
or the user records it as a model limitation.

- **Lossy repeats** (lost source requirement and weakened obligation). A field that restates a
  requirement drops or weakens part of it, which fails the requirement's criterion by the
  severity rulings (§7 H1).
  - **Entity fields: recorded as a model limitation** (user, 7 November 2026: "record as a
    model limitation"; AGENTS.md "Model output, prompts and evidence"), observed with Bedrock
    `openai.gpt-oss-20b-1:0` (`ap-southeast-2`, the only model in every live run, §7 H5): runs
    that show it still fail their criterion, nothing is weakened, and no further prompt change
    targets it. Two prompt changes, Q20's entity-meaning purpose and the one-owner hygiene
    change, didn't stop it and were reverted (7 November 2026). The structural lever, ADR 0038
    Decision 6, is kept ([Z_SPEC01](Z_SPEC01.md) Next 6).
  - **Edge-case outcomes:** ADR 0038 Decision 7, kept ([Z_SPEC01](Z_SPEC01.md) Next 8). **Not
    accepted** (user, 7 November 2026: "that is a poor idea and I will not accept it"): the
    engine filling `then` and `expected_outcome` from the record's cited source lines. ADR 0038
    Decision 7 records that this doesn't cover copying a criterion's Then.
  - **Titles:** still open (purpose `packet-guidance.json:4`; held to their values by §3 Next
    item 3). Needs a lever with an owner or a recorded model limitation.
- **Unsupported additions in AC wording.** AC-001's recording of the renewal ("records the loan
  as renewed", three of the HEAD set's four additions) is ruled a minor addition (§7 H1) and
  has no structural lever: the `given` purpose forbids invented prerequisites
  (`packet-guidance.json:22`), the `when` purpose (`:23`) doesn't. Q12's leftover restatement
  (`generation.prompt.md:2`) and the three no-invention texts (`packet-guidance.json:22`,
  `records.prompt.md:8`, `generation.context.json:4`) stay as they are after the one-owner
  hygiene change's revert. Report the remaining AC elaboration as a model limitation (AGENTS.md)
  and let H1 judge it.
- **Repair requests without step guidance:** six repair sites take their task only from the
  three-line `repair.prompt.md` (`spec.workflow.yaml:371`, `:408`, `:605`, `:760`, `:864`,
  `:879`), and the two reconciliation repairs among them (`:605`, `:879`) bind no context.
  Binding definitions (Q2) wasn't kept; counted as a brittleness measure (T5).
- **Provider doesn't enforce the response schema:** the engine's request matches AWS's
  documented Converse shape (`outputConfig.textFormat` json_schema,
  `src/adapters/provider/bedrock_request.zig:74-77`), and the gpt-oss-20b model card lists
  structured outputs as supported, yet Bedrock's raw text block (not engine extraction,
  `bedrock_response.zig:135-149`) opens with a fragment and restarts the JSON in 198 of 205
  responses in the D12.1, D16.1 and D16.2 runs, and two 31 October answers ended `end_turn`
  inside an open string. ADR 0039:67-72 records it as a provider defect (decided 1 November
  2026). Open: whether Bedrock applies the grammar partly or not at all. The live comparison
  (one retained request with and without native JSON mode) is deferred: it needs an `e2e-call`
  change (it keeps the captured response mode, design/harness/e2e.md:113-114) and approval.
  Since D13.1 the prefix caused two faults, both extract-classifications call 2
  (`2026-11-01T08-24-09Z-46f4…`, `2026-11-07T01-19-36Z-728d…`), each corrected by the next
  call. No model or provider change (H5).

## 4. Quality phases (Q)

### Q2b. Generic content-loss guard for repairs

**D2.3** is implemented and kept ([Z_SPEC01](Z_SPEC01.md)). Open follow-ups:

- remove `Relations.competing` under §2.12 (`reference_reconciliation_diagnostic.zig:162`);
- fold `member_count` into `collection`'s `exact_members` variant
  (`model_result_schema.zig:100-103`, `:197`), and ADR 0038 Decision 3's `coverage` into
  `unique_subset` (`:104-106`, `:206`);
- assert the exhausted scenario's final rejection reason (`spec_generation_driver.zig:136-153`
  asserts only `.retry_limit`, `:150-152`).

Out of scope unless harm appears: the statement, signal and conflict coverage inserts and
token classifications.

### Q4. Remove engine vocabulary and schema-stated rules from prompts (retry)

The first attempt removed the second `citations` sentence (`extraction.context.json:14`) and
was reverted on 31 October 2026 after hello-world's first extraction returned
`no_feature_claim` in 5 of 6 runs (`evaluations/q4/measures-set.json`), so the retry keeps it.
12-model-boundary.md:369-370 and ADR 0016:157-158 say SPEC01 Q4 removes the restated rules. No
published spec contains engine vocabulary, so this is AGENTS.md compliance, not an output
target.

**D4.1's extension** (D4.1 in [Z_SPEC01](Z_SPEC01.md); decided 3 November 2026): the rule covers
native rule and correction texts too, and a sentence that says what a field, claim or response
contains stays even when the engine enforces or transforms it.

**Scope still model-visible:** `support.prompt.md:28-29` (bound for pre-generation source
review); `packet-guidance.json:62`; `reconciliation-dispositions.prompt.md:2-4`;
`extraction-classifications.prompt.md:2-5`; `records.prompt.md:4-5`;
`support-loss.prompt.md:22`; the "native code …" texts in
`src/domain/reference_reconciliation_diagnostic.zig` (lines 101, 106, 119, 122, 124, 132, 134),
which reach requests through `descriptionFor` (`reference_model_input.zig:297`);
`src/domain/typed_text.zig:156` (no projected request carries it, but
`specification_repair.zig:81` can send it). Reword engine vocabulary in place; remove a
restated rule only when the schema or its correction states all of it; keep task semantics the
engine doesn't check (both `citations` sentences and the `claim_ids` definition).
`records.prompt.md:9-13` states the coverage rule and an "at most one record" rule (ADR 0038
Decisions 2 and 5); the engine checks the second only for non-requirement statements (ADR
0038:155-158), and the sentence is kept as written on purpose (:163-164). It stays as their only
carrier on a first attempt, since the provider schema can't express them.

**Validation:** projection shows only the listed texts change; scripted missing and repeated
members get the `array_length` and `duplicate_member` corrections; then a set, with the
extraction requests screened first (§2 rule 4). **Keep if** engine vocabulary stays absent and
no guard blocks (§2 rule 6); corrections, rejections, defect classes and cost are watch items.
Never rename a field to chase a leak.

### Q7. Exact values

**Defect:** rendering artefact, found in every publication of 31 October and of the D12.1,
D16.1 and D16.2 sets:

- **A. Doubled delimiter.** ADR 0036 Decision 6 removes only backtick runs around a value
  (`exact_value_recognition.zig:134-152`); the model's `"` stays in the neighbouring text, and
  the projection gives an exact copy its own code span (`specification_projection.zig:186-190`)
  unless D7.4's exception applies (`delimitedByText`, `:202-208`), which excludes a value
  ending in terminal punctuation and so every development-case value. Where the span stays,
  the doubling is the engine's. Since ADR 0047, A remains in model-written FR and AC fields.
- **B. Plain value in an entity meaning:** ended 8 November 2026, when the entity lost its
  meaning (ADR 0038 Decision 6).
- **C. Fragments joined without a separator:** the schema keeps the fragments option when no
  reference is offered, and fragments join with no separator
  (`model_candidate_json.zig:251-253`). D7.5 owns it.

- **D7.4** (implemented, [Z_SPEC01](Z_SPEC01.md)): decided 1 November 2026, D7.4 is not a
  punctuation rule (AGENTS.md "Prose heuristic").
- **D7.5** (decided 3 November 2026: yes, a conformance fix with no contract amendment, since
  07-domain-representations.md:74-79, ADR 0006:302-316, 12-model-boundary.md:199-203 and
  text-field-composition.md:21-22 already reserve fragments for composition around typed
  insertions): where a field offers no inserted reference, its schema offers only the plain
  string (`model_text_field.zig:174-190`; `textContract`, `model_text_wire.zig:277-292`). Schema
  bytes change in every generation request, so a screen, then a set. Admission validates the
  response against the schema the model receives (`admit_model_response.zig:19-21`) before the
  codec runs (`model_candidate_handoff.zig:24-32`), so a fragments object against a
  plain-string field fails as `type_mismatch` with a protocol correction. Effort S: `walk` in
  `model_text_field.zig` and its tests; `generation.context.json:2` still describes fragments.
  Since ADR 0047 composes the story, the only fragments object seen was in a reconciliation
  signal (`2026-11-03T04-13-31Z-fa03…` call 5, unpublished), so D7.5 is a hygiene phase (§2
  rule 6). **Keep if** no fragments object appears where no reference is offered and no guard
  blocks; admission rejections, protocol corrections, runaways and unsupported addition are
  watch items.
- **Not recommended:** typed exact-value references inserted by the model (ADR 0020 replaced
  them after 4 of 5 hello-world runs failed, and the model's quotes would still double);
  removing the model's quotes (rewrites model bytes); a prompt asking for no quotes.
- **D7.3** (recorded 3 November 2026; reopen when a live case shows it): whether a token inside
  a claim must sit on the recognition boundary to force a duty (`CTIV` in `ACTIVE`,
  `structured_token_test.zig:45`, `:56`). Owner `exact_token_obligation.zig:11-31`; amends ADR
  0024:36-38 and ADR 0036 Decision 5. The boundary alone would drop real duties (a link
  destination, `exact_value_boundary.zig:120`; a code span with a suffix, `:136`). Option
  needing IDs only: force a token only from a claim that cites its own occurrence. Decided
  offline with accepted and rejected fixtures and byte-identical requests; no set can exercise
  it.

Boundary tables (`exact_value_boundary.zig`) are never extended case by case. A boundary
rejection is silent (`exact_value_recognition.zig:109`), so no set can count it by reason.

### Q8. Source-claim granularity (B7)

**Defect:** restatement and claims lost in reconciliation when citations repeat. ADR 0036
Decision 3 and ADR 0038 Decision 4 (the list-item split,
`reference_extraction_text.zig:144-183`) stay as they are (D8.1, decided 3 November 2026).

- **D8.2** Whether "cites in full" (ADR 0036:129-131) covers a fenced block whose first or last
  interior line is blank (`markdown_code_spans.zig:53`, `:59`;
  `exact_token_obligation.zig:40-45`; `source_selections.zig:57-60`). No fixture covers it.
  Decided offline with fixtures at its owners and §2.10 projections, in any gap, or recorded.
- **D8.3** is implemented ([Z_SPEC01](Z_SPEC01.md)); semantic benefit is not demonstrated, since
  no live run since has duplicated an extraction claim.

### Q13. Inline source lines

D13.1 (post-generation reviews removed) and the inline source lines are in
[Z_SPEC01](Z_SPEC01.md). **D13.4** (decided 1 November 2026): principles are context and
constraints only, never origins, and never modified (Q17). Nothing checks what a shown source
line means beyond the advisory evaluate-e2e link check.

- **Reopening link checks** (a **Decision**), in shadow mode, only if adjudication shows
  semantic defects that the generation-side items (Q14, ADR 0047) leave. It amends ADR 0023's
  Decision (:46, :60-62) and its removal amendment (:25-42), and the harness makes no judge
  call (AGENTS.md). **Proposed shape** (8 November 2026): each check asks one question of one
  generated value against its fixed claims, returns a structured finding with evidence, edits
  and decides nothing, and is labelled under H2's scheme (SKILL.md §7). Against it: the 26
  October source review, on the same model, caught 1 of 28 defects by the assistant's
  unconfirmed labels (`evaluations/b2-review-accuracy/2026-10-26/summary.md`), and a reliable
  finding drives no repair unless ADR 0023:51-53 is also amended.
- **Clarification question lines disagree.** `clarification_preparation.zig:32` prints
  `lines {start}–{end.line}`, so a citation of line 5 reads "lines 5–6" there and "line 5" in
  `spec.md`. Fix: use `source_coordinates.lines`. It changes clarification form bytes; no
  development case reaches a clarification today.
- **D13.7 (decision, needed only when Plan's editable reparse is built; ADR 0034 gates it):**
  what a hand-edited or stale source line does at the plan boundary. 23-rendering.md §23.1
  (:148-153) says readback compares it with the derived line, but not what a mismatch does.
  **Recommended:** regenerate it from the re-attributed provenance, never block on it, since
  the line is a display and a user can't change what a record cites by editing it.
  **Limits:** a citation is only as true as its link (loan-renewal AC-001 cited refusal lines
  it doesn't test, `2026-11-07T01-19-36Z-728d…`), so it pairs with Q14 b3; entities cite whole
  groups (R1); semantic checking rests on adjudication (H1).

**D13.6 — decided 1 November 2026** (user: "the review repair should check that the claim
exists, if the claim supplied by the LLM does not exist then is should attempt to get the LLM
to repair with guidance on the error"). Every claim a model supplies must exist; a
non-existent claim is rejected and the model is asked to repair it, with guidance on the
error.

- **Already in place:** every claim, signal and line ID a model supplies is a closed integer
  choice (for example records' `claim_ids`, `specification_session.zig:398`). A non-existent
  ID fails response admission as `enum_mismatch` (`model_payload_schema.zig:197`) and gets a
  protocol correction within the step's retry limit. No such correction has fired in any
  measured run.
- **Gap, the guidance:** the correction says only "this value is not among the allowed
  values" (`model_schema_diagnostic.zig:34`), and its expected shape for an ID choice is
  `{"type":"integer"}` (`model_schema_projection.zig:75-79`). It names neither the rejected
  ID nor the IDs that exist; the rejected response travels with the correction
  (`model_protocol_retry.zig:96`).
- **Change (approval needed to implement):** the `enum_mismatch` correction for an ID choice
  names the rejected value and lists the allowed IDs, both taken from the compiled choice,
  never hard-coded (D4.1's precedent for `uncovered_member`). It amends 22-repair.md:573-574,
  which keeps the allowed-ID list out of an integer-enum outline, and :568-569 ("no other
  correction changes"). It changes model-visible correction text only; first requests stay
  byte-identical (§2.10). Proven offline: a scripted non-existent claim gets the named
  correction and an accepted retry. A set can't measure it, since it hasn't fired live.

### Q14. Scenarios bound to their claims

**Defect:** lost source requirement: no scenario tests refusal, in 2 loan-renewal publications
since ADR 0047 (`2026-11-03T04-13-31Z-fa03…`, `2026-11-07T01-19-36Z-728d…`; none in the HEAD
set). In both, one FR named every claim and the success-only AC-001 cited the refusal lines.
Coverage (ADR 0038 Decision 2; `specification_session.zig:343-349`) covers FR, BR, UO and PB
claims and checks links, not meaning (ADR 0038:219-221), so an AC naming every claim passes
it: `fa03…` passed on its first attempt with no `uncovered_member` firing, a route b3 doesn't
close. No retained `uncovered_member` firing ended well: two runs exhausted the records retry
limit (2, `spec.workflow.yaml:732`), and three passed by adding the claim IDs to the
success-only AC-001. The advisory evaluate-e2e link check can't record over-citation.

- **b3 (D14.1):** a claim-bound scenario insert: the engine fixes the new record's
  `claim_ids` to the uncovered claim and the model writes only its content, closing the
  add-a-link escape. Effort L, using today's repair loop (`spec.workflow.yaml:749-774`); E4 is
  not a prerequisite.
  - Coverage must move from payload admission (`model_payload_schema.zig:235-247`, behind
    `shared_member` at `:228-234`, where no typed candidate exists and only a whole-response
    retry is possible) into the unit validator beside entity membership
    (`specification_generation.zig:248-265`).
  - Insert repair exists today only for entity membership (`specification_repair.zig:50-67`,
    `:128-141`, `:374-378`, `:469-478`). The record gates at `:254`, `:376` and `:470` lift; a
    group policy for a fixed claim is added (`GroupPolicy` has only `.membership`,
    `specification_candidate.zig:141-143`); the record repair definition stops being only
    `repair_record_entity` (`specification_repair.zig:271`); and the unused content-only
    `repair_record_acceptance_criterion` schema (`generation.schema.json:473-484`) gains an
    edge-case counterpart.
  - A compiled coverage rule needs covering kinds (`model_result_schema.zig:210`), so keeping
    `shared_member` at admission without `uncovered_member` changes the result-schema rule
    contract.
  - ADR 0038 Decision 1 already says repairs stay content-only and keep the record's claims
    (0038:95-96). Deletes the admission-time coverage check (`uncovered_member`) and D4.1's
    covering-kinds correction; D16.2's partly taken statement (`shared_member`) stays at
    admission and its repeated statement a native delete.
  - Amends ADR 0038 Decision 3 (:104-112, :287-289) and :150-152, :246-248;
    22-repair.md:270-274, :561-567 and :802-803; 12-model-boundary.md:105-108 and :846-847;
    17-specify.md:200-203; F0100:1195-1198 and :1374-1379.
  - An inserted scenario still links without checking meaning.
- **b4** (proposed 8 November 2026; not started, §3 Next item 4): claim-bound scenarios at
  first generation too: the engine fixes each scenario's `claim_ids` before the model writes
  it, closing `fa03…`'s first-attempt route that b3 leaves. Slots can come only from IDs, so a
  slot per claim needs the statements first (a second records call per group) or D21.1's unit
  (§4 Q21). Risk: each added scenario is another restatement that can lose part of its claim.
  Amends ADR 0038 Decisions 1–3 beyond b3's.
- **b2** (not chosen): the scenarios naming a claim must together contain every exact value
  its quoted text requires; it misses claim 4 and business-rule-only cases.

**D14.1:** b3, not b2 (decided 1 November 2026); held until lost source requirement recurs
(re-decided 3 November 2026), a condition since met; held again with b4 not started (8
November 2026, §3 Next item 4). When it goes ahead, **Keep if** lost source requirement falls
and publication and exhausted runs don't worsen.

### Q17. Principles as Spec context

**Decided 1 November 2026** (user): "the workflow must never modify principles - NEVER" and
principles "should be used for context when executing the spec workflow".

- **Never modified:** holds today. Principles are read through a read-only source adapter
  (`src/adapters/filesystem/principle_source.zig`), the only principle capability is
  `principle_read` (`workflow_capability.zig:18`), and path validation rejects every project
  operation against the semantic-principles root (11-path-validation.md:20). Every future step
  (Plan, Implement, init, repair) keeps it. ADR 0015 records it (0015:36); design.md §3.3
  doesn't (adding it is a design edit awaiting approval).
- **Context:** today no generation call receives principles; only `capture-principle-registry`
  reads them (`spec.workflow.yaml:44-46`). Adding them changes generation requests, so it is a
  model-input change measured by a set. Principles are context and constraints, never a
  requirement's origin: items still cite only source claims (D13.4).
- **D17.1 decided 1 November 2026:** the records call only (it writes the FR, AC, BR and other
  statement records principles constrain), with the principle files as the registry captures
  them, unnumbered (items never cite principles). The case principles are 28,067 (hello-world)
  and 29,399 (loan-renewal) bytes, about 7k tokens per run. A measurement set after D12.2,
  with unsupported addition and invented entity as watch items (§2 rule 6; decided 3 November
  2026, user: "Yes, watch items").
- **Target and risk:** no current rubric criterion scores principle consistency, so a set can
  show only guards (unsupported addition and invented entity from principle text,
  publication) unless the case rubrics gain a criterion. Amends ADR 0015 (0015:10-14 already
  names D17.1), ADR 0023 "Principles" (0023:149-159), 17-specify.md's consolidated-generation
  inputs (:260-336) and F0100.
- **Sequence (recommended, not decided; D17.1 places it after D12.2):** a records screen
  first: the loan-renewal rubric's proportionate-scope criterion penalises principle-derived
  prescriptions, so its guards need a settled reference.

### Q21. Behaviour claims need statements

**Defect:** lost source requirement: a behaviour claim that no statement or scenario names
passes coverage, because the brief fields, entity basis and composed story select whole
groups and a claim maps through any field holding it (`specification_coverage.zig:52-61`,
`:74`). In a one-group feature, as both development cases are, ADR 0038 Decision 2's scenario
rule never reaches an unnamed claim (ADR 0038:239-241; pinned at
`specification_generation_test.zig:9231-9234`). No failure since ADR 0047 is of this kind, so a
set may show only "benefit not demonstrated".

**Proposed 8 November 2026** (not decided): a narrative selection gives traceability only;
every obligation-bearing claim must be named by a behaviour statement (FR, BR, UO or PB),
whose claims then need a scenario. A coverage gap blocks with no repair today
(`specification_coverage_repair.zig:26-30`), so it needs a correction at records admission
(ADR 0038 Decision 3) or a claim-bound insert (b3, §4 Q14), or silent passes become blocked
runs. Owner: `Coverage` (`model_result_schema.zig:56`) and `specification_coverage.zig`;
amends ADR 0038 Decision 2 and :234-241, 17-specify.md §17.5 and F0100.

**D21.1 (Decision):** which claims bear obligations: (a) every `business` claim, which
includes feature identity and purpose (`extraction.context.json:6`); (b) a new obligation
category in extraction (`:5-13`), changing extraction requests; (c) a bounded model
decomposition into source-span elements, the only option that separates a compound claim such
as loan-renewal's four-part refusal item (`test/e2e/wf-002-loan-renewal/stories.md:9`, ADR
0038:217-218), at the cost of a model step whose losses nothing native detects. Treating
shared source evidence as no redundancy is not adopted: it would reverse ADR 0038 Decision 5
(user, 2 November 2026).

**D21.1 deferred** (8 November 2026; user: "recommendations accepted for 1 to 6"): no failure of
this kind has occurred since ADR 0047, so a set could show only "benefit not demonstrated", and
each option risks accuracy: (a) false blocks on identity claims, (b) a change to every
extraction request, (c) losses nothing native detects. If it resumes, take (b).

**Next:** D21.1 (deferred); fixtures at the owner (an unnamed claim, or one named only by an
assumption, non-goal or scenario, rejects), then screens and a set (§2 rules 4 and 6). §10 C30
records the blocking route's constant-result machinery.

## 5. Engine track (E)

Each item: `/preflight`, offline tests, the §2.10 proof, `zig build verify`, one live run
per case (DE2–DE4 ask whether offline evidence replaces it), landing between sets and under
§2.12.

### E0. Failed and blocked runs publish validated content (B10, ADR 0041)

On hold since 30 October 2026 (ADR 0041:3-4). Nothing under `src/` names `failure-output`,
`spec_incomplete` or `run.incomplete_published`. To resume: implement ADR 0041 Decisions 1–8,
taking `specification-state/v25` (ADR 0041:10-11, :44, :227); align the measures
(`test/harness/e2e/measures.zig:207`, test `:739-742`; e2e.md:682-683), design.md:208,
24-workflow-state.md:76-81, F0100:1145 and `test/harness/e2e/contracts.zig:209-212` with
Decision 7.1 (an `invalid` run stays `invalid` and may publish), and F0100:1139 with Decision
7.8 (the title precedes the status line); add a test that a pre-E0 v15 report still decodes;
flip every scenario asserting no publication after an eligible failure (the `spec.md`
`FileNotFound` assertions after a failed or blocked run in `test/integration/workflow_tests.zig`;
`test/harness/integration/tests.zig:1759`, a budget stop), including ADR 0047's
`no_story_requirements` and `story_not_admissible` blocks, which no scenario covers; register
`run.incomplete_published` through `adrRequired` (`src/domain/log_event_registry.zig:99-105`,
test `:162-168`). If ADR 0041 is withdrawn, v15's `incomplete_publication` (e2e.md:353-356)
and the measures' `incomplete` value become dead code needing a report version.
Budget-stopped runs publish nothing while it is on hold (none since D13.1).

### E1. Engine-owned model request (A1, ADR 0030 slice 4)

Not started: the `request-model` step replacing `model-request-body`
(`spec.workflow.yaml:979-1035`) and its five wrappers (`:905-978`), with the contract-variant
mechanism ADR 0033 reuses. It folds in ADR 0039's re-send and retires `validateRunawayRoutes`
(`src/domain/workflow_model_request_lifecycle.zig:86`). Retake the slice 1 freeze on the commit
before it lands (slices 1 and 4: git `194e29a:fixes/Z_FIX05.md:2794`, `:4430`). Slice 1 review
points: make `extract/content` and `extract/content-request` (`spec.workflow.yaml:321-333`) one
step; port each runner-level lifecycle test in `src/model_request_workflow_test.zig` one for one
with a mapping table and a reason for any dropped assertion (user decision, 23 October 2026,
option b). If E1 removes a request-lifecycle `DataKey`, it lands under §2.12.

### E2. Stage actions (A2, ADR 0031)

Not started: convert `prepare-toolchain` (nine steps, `spec.workflow.yaml:182-211`) first and
record ADR 0031's measures (:355-357) before another stage. **DE2:** confirm ADR 0031's
derived choices 1–3 and 6–8 (:268-290), including whether choice 7's offline evidence replaces
the live run. §10 C32 records what the stage feeds today.

### E3. Engine routines (A3, ADR 0032)

Not started. Convert startup first and measure it (ADR 0032:144-151). Feature logging waits on
its preconditions (:152-172): no test covers cancellation under a log lock, and the
policy-transition coordinator waits on E6's §14.10 decision. **DE3:** confirm ADR 0032's
derived choices 1–8 (:224-241), including offline evidence; can be asked with DE2.

### E4. Generic repair operations (W3, ADR 0033)

After E1, E2's measure and its capture replays (ADR 0033:261), which must be
`model-request-debug/v16` captures (`model_request_description.zig:5-10`; earlier captures no
longer decode): all Specify owners in one change on offline equivalence evidence; the 29
operations and 13 owners of ADR 0033:87-103 still match (10 authorize, 6 build, 6 parse, 7
merge). Seven operations read `.packet_guidance`; their variants keep those reads. Retained
reports carry repair keys, so it lands under §2.12. **DE4:** confirm ADR 0033's derived choices
2–8 (:273-285; choice 6 is moot since D13.1, :280-281). Q14 b3 extends the specification-unit
repair route these operations replace; E4 isn't its prerequisite (§4 Q14).

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
- **Correction location:** a SyntaxError correction tells the model the malformed opening
  (all four in the 18 runs of 31 October said `byte_offset 4`, key `"{"`), not the unterminated
  string: `model_envelope.zig:68` drops the re-parse diagnostic and `:75` reports the original,
  as §22.6 requires (22-repair.md:519). Fixing it amends §22.6 and changes correction requests.
  None has occurred since D13.1.
- Further payload-free failures, by area: §10 C4.

### E6. Logging and visibility gaps

- **Cancellation** during segment reads and under the log lock ends the run `blocked`, not
  `cancelled` (`operation_error.zig:16-24`; `feature_log_recovery.zig:29-61`;
  `feature_log_historical_stream.zig:95-97`). **Decided yes** (8 November 2026; user:
  "recommendations accepted for 1 to 6"): it ends `cancelled`, as its own phase after the
  entity and escaping set (user, 8 November 2026: "after"). Not implemented: it adds
  `Cancelled` to the `FeatureLogSink` error set and a `cancelled` log outcome, amending ADR
  0032:312-313's "Not decided" bullet, with no new `LOG_*` code. Measured scope: about 35
  `SinkFailure` mapping sites in the log adapters (`feature_log_segment_store.zig` 21,
  `feature_log_retention_store.zig` 6, `feature_log_lock.zig` 5, `feature_log_recovery.zig` 2,
  `feature_log_historical_stream.zig` 1) and about 9 consumers of the log outcome, not a small
  change; it affects no model request. No production code supplies a cancellation status today
  (§10 C28).
- **Prior-run crash finalization** (§14.10) is blocked on a persisted bootstrap authority that
  doesn't exist (14-orchestration.md:317-321), so a crashed run's logs are kept whole and
  damaged prior logs block later runs until someone repairs or removes them. **Decision:**
  which persisted authority supplies the historical policy lineage (§14.10; ADR 0032:310-311,
  "Not decided here"). E3's feature-logging conversion waits on it.
- **Redaction policy ID:** 26-security.md:195 and F0002:542 name `redaction/default-v1`, which
  no code carries. **Decision:** a record carries the ID (a new field, so `feature-log/v3`;
  v2 is current, `feature_log_limits.zig:1`), or both documents drop it. **Recommended:** drop it.
- **Producerless rejection** (fixed, [Z_SPEC01](Z_SPEC01.md)), still open: contract 27
  (27-observability.md:44-47) names only coverage as an assembled-candidate example (design
  edit awaiting approval: add `producerless` as a second example); `observation.capture`'s
  candidate arm (`test/harness/e2e/observation.zig:131-132`) has no direct test. **Decision**
  (optional): a first-generation omission names its chunk's classification producer.
  **Recommended:** no.

### E7. Clarification answer recovery (R2, ADR 0025)

Not started; no §13 authentication chain exists in `src/`. Fresh answers can't complete
recovery: refresh rejects new submissions (`clarification_refresh.zig:65`); provenance
rejects nonempty response-ID sets (`specification_provenance.zig:88`,
`specification_support_evidence.zig:171`); form validation returns one
`InvalidClarificationInput` (`src/actions/clarification/validate_clarification_forms.zig`);
resolved needs are empty (`src/actions/clarification/build_resolved_clarification_needs.zig`);
passive literal origins are source-only (`passive_literals.zig:16`), so answer text can't get
ADR 0025's response-owned origin (0025:70-71); generation doesn't consume answers (it binds
empty response-ID sets, `specification_source_binding.zig:132`, `:184`). Complete the
[§17.4 lifecycle](../design/contracts/17-specify.md#174-specification-clarification-behavior)
under ADR 0025. Live validation needs a user-chosen clarification-expected case run twice with
forms answered between runs; neither the case nor a two-run harness flow exists. Last, after
E1–E4. §10 C8 adds record-lifecycle gaps.

### E8. Typed schema-definition identities

Domain code names result-schema definitions by raw strings (T5.2: 20 production sites on the
`b38628c` tree, `zig-out/code-heuristics/report.json`, 2 November 2026; ADR 0047 removed the
story's, and `e681cfd` added `scenario_link`, `scenario_link_request.zig:19`). They fail only
at request preparation (`model_request_handoff.zig:343`; sites in `specification_support.zig`,
`specification_support_repair.zig`, `specification_session.zig`, `specification_repair.zig`,
`reference_model_input.zig`, `scenario_link_request.zig` and the reference reconciliation and
extraction-repair files). Bind them as closed IDs checked at schema load, each owner declaring
the definitions it reads; the generic `DefinitionId` (`model_result_schema.zig:19`) names no
Spec definition (ADR 0003:100-101). Test fixtures branch on names too
(`spec_generation_driver.zig`, `spec_generation_responses.zig`). §10 C34 and C41 add sites.

### E9. Superseded exact-handle correction

`ValueChoices.correction`'s `unknown_exact` arm (`specification_provenance.zig:172-175`)
corrects a model-authored exact handle that models can't author since `dfae959` (ADR 0020:233).
`ValueChoices.permits` (`:162-164`) has no caller. Delete the arm, `permits`, the
`rejected_exact` member (`typed_text.zig:144`), its assignments (`typed_text.zig:245`,
`specification_provenance.zig:426-433`) and the assertions that read it
(`typed_text_test.zig:32`, `specification_generation_test.zig:6907`,
`packet_guidance_test.zig:205`); the `unknown_exact` rejection stays. No freeze under
`evaluations/request-projection/` carries `rejected_exact`, and no retained report does. Lands
with E1, E4 or E5. §10 C27 adds the `.construct` singleton choice.

### E15. Streamed provider replies (proposal; no ADR)

**Defect:** none observed. Runs lost to a timeout or a dropped connection during a long
generation (successful completion); no failure is attributed to non-streaming (ADR
0030:250-252, :261-263), so the benefit is unmeasured. **Status:** proposed, not accepted; it
needs a new ADR amending ADR 0028 and ADR 0029 "Not decided here" and F0007's "no streaming"
(F0007:178). The wire research and design (Claude SSE events, Bedrock ConverseStream event-stream
frames, the failure table and the test list) are in git at `071ce2b`,
`fixes/claude-connector.md`. **Decisions for that ADR** (user, 8 November 2026, yes to all
four):
1. Streaming replaces non-streaming outright, including the standalone evaluator
   (`test/harness/bedrock.zig`): no dual path.
2. The engine reads the whole stream before decoding; no early stop.
3. An in-stream error classifies by its type alone: an `overloaded_error` event after HTTP 200
   is `service_unavailable`.
4. An unknown stream event type fails the call as `response_invalid`; only `ping` is skipped.

**Direction for this design** (user, 8 November 2026): no Claude model is called through
Bedrock initially, so `claude-haiku-5-5` streams only through the Anthropic Messages API and
only GPT-OSS-20B needs the ConverseStream probe. It doesn't change the live-test policy, which
still permits Claude Haiku 5.5 through Bedrock (ADR 0029). **Open:** whether
GPT-OSS-20B streams through ConverseStream, and which usage fields Claude's stream always
carries (each needs an approved live probe); whether a bearer API key authorizes
`bedrock:InvokeModelWithResponseStream` (set aside by the user); whether ADR 0037's budget
counts input tokens that a failed Claude stream reported in `message_start`.

## 6. Test track (T)

### T2. Test decoupling

Tests copy model-facing English or check its absence: about 32 lines of 25 or more characters
in 7 files (2 November 2026). Compare with the owning constant or resource instead: copies in
`model_request_workflow_test.zig`, `model_payload_schema_test.zig` (and its `:362` phrase
checks on `protocol.prompt.md`), `reference_model_input_test.zig`,
`test_fixtures/spec_generation_driver.zig`, `model_text_field_test.zig`,
`reference_reconciliation_test.zig`, `specification_generation_test.zig`; absence checks at
`model_text_field_test.zig:177` and `model_request_workflow_test.zig:4529`. Rename tests,
fixtures and `measurement_prefix` dumps named after live runs: dumps r35, r36, r37, r40, r41
and fix002 (`workflow_tests.zig:1633-1698`); tests R36 (`model_envelope_test.zig:381`), R42
(`specification_generation_test.zig:6843`) and D1
(`model_candidate_json_test.zig:285`); fixture headers R35 and R36
(`summary_protocol_sequence.zig:1`, `global_protocol_sequence.zig:1`); and their
`build/test_run_inputs.zig` entries (`:22`, `:33-38`), deleting its orphaned `d1-review`,
`r42-recovery` and `r43-recovery` entries (`:20`, `:39`, `:40`; the test at `:145` uses
`d1-review` as an example). §10 C47 adds further unnamed inputs and the unread dump files.

### T3. Coverage gaps (B5, B7)

- No integration scenario reaches ADR 0035's story `restatement`; unit coverage only.
  D16.2's `repeated_statement` has one (`workflow_tests.zig:1402`, `:2380-2387`).
- The no-feature-claim text-repair route (`spec.workflow.yaml:360-381`) has unit coverage only;
  the integration `.unbound` mode ends `.invalid` before it.
- The retained GPT-OSS compatibility exchange is assessed `incompatible` since ADR 0036
  (`provider_compatibility_tests.zig:261-262`, `:305-309`), so the normal §22.6-normalized path
  has no compatible-assessment coverage.
- Proof limits recorded at implementation ([Z_SPEC01](Z_SPEC01.md)): no scripted scenario
  quotes an exact copy, so D7.4's freeze doesn't reach its path; Q13's two-source citations
  are covered at the codec, not the projection (the fixture reads one file); every scripted
  records batch has one claim, so D16.2's partly taken record is proven only at admission.
  A scripted multi-claim batch needs a per-group generator, since the baseline one names one
  claim per record (`spec_generation_responses.zig:769`).
- Scripted branches no scenario selects, and stages the development cases never exercise: §10
  C44 and C48.

### T4. Architecture rules and replay (A5)

When E1–E4 remove files pinned by architecture tests, write the replacements as import-graph
and contract-shape rules (ADR 0030:464-468, 0031:337-353, 0032:291-303, 0033:338-341), not
per-file pins (about 70 of the 79 tests pin files). Prefer replaying retained captures over
extending `spec_generation_responses.zig`. §10 C46 adds the raw-text matching.

### T5. Brittleness counts

Definitions and decisions: [Z_SPEC01](Z_SPEC01.md). The `code-heuristics` report names
them by `report.json` member: T5.1 `tests_copying_model_text`, T5.2 `schema_name_branches`,
T5.3 `repeated_instructions`, T5.5 `model_or_case_branches`, T5.6 `model_text_outside_owner`;
T5.4 isn't in it. Each change set that a phase reports on
retakes them on its committed build: `zig build code-heuristics -- --freeze <dir>` with the
freeze §2.10 takes on that build, and T5.4 by hand from `spec.workflow.yaml` (a `slot: repair`
step whose prompt no non-repair step binds). Last taken 2 November 2026 on the `b38628c` tree
with freeze `evaluations/request-projection/b38628c` (130 scenarios, 1,714 calls): T5.1 19,
T5.2 20 (tests 88), T5.3 5 instructions at 11 sites, T5.4 6, T5.5 0, T5.6 13 in 4 files.
**Due:** not retaken since the kept ADR 0047 and D12.3 change set (`f6ef0f6`, `39fd9ff`; freeze
`evaluations/request-projection/entity-meaning-before`, 130 scenarios, 1,592 calls) or the HEAD
set's build; ADR 0047 deleted the story prompt and purpose, so T5.2 and T5.3 may change. T5.4
is still 6 (`spec.workflow.yaml:371`, `:408`, `:605`, `:760`, `:864`, `:879`, each binding
`repair-prompt`).

### T8. Report repairs cover every unit

**Defect (measurement):** `report.json` `repairs` keeps only the last merge of each candidate
still retained at run end (F0100:1368-1371, "These are retained merge snapshots"), so
`e2e-measures` and the evaluation miss earlier merges in a unit and every merge of an earlier
unit. Retained `2026-11-08T09-23-55Z-149a…`: seven distinct deletes (revisions 1→2 to 7→8) in
`events.jsonl`, 7→8 alone in `report.json`. §2 rule 5 grades every repair, and the harmful
repair watch item depends on it. Each step event already carries that step's merges
(`test/harness/e2e/trace.zig:570`, `:640`); only the report reads them once, from the last
state (`invoke.zig:118`, `observation.zig:130`). **Owner:** the E2E observer. **Next:** collect
the distinct merges (by authorization) across the step captures, in sequence order, into the
report (a report version, §2 rule 12), amending those F0100 lines and e2e.md:641-643 (which
states the limit meanwhile); F0100:1366-1367, the engine's rule, stays. Each `Merge` already
carries its `operation` and `origin` (`atomic_repair.zig:35`, `:39`). Proof: a scripted run with
several merges in one unit and merges in two units reports each merge once, in order.

## 7. Human and decision track (H)

### H1. Adjudication (R8)

**Decided 3 November 2026** (user: "yes", to "should the evaluator's rubric scores decide
acceptance instead of your record?"): the `/evaluate-e2e` skill writes each published run's
`spec-adjudication-record/v1` from its rubric scores and applies it with `zig build
adjudicate-spec` (AGENTS.md "Testing expectations"; ADR 0034 and design/harness/acceptance.md
amended). Only the user triggers or approves the skill (AGENTS.md states the rule);
`/live-e2e` doesn't run it.

**Decided 3 November 2026** (user: "YES", "YES approved"): a run's first adjudication under a
skill version counts (R8, design/harness/acceptance.md).

**Open:** `2026-11-02T09-15-27Z-d2ee…`'s applied decision reads `admission_evidence_invalid`,
from a harness bug since fixed; its record scores `critical_failed`. Its v14 report survives
only as `evaluations/adjudications/adjudication-7c50a2ef…/original-report.json`, so correcting
the applied decision needs the build that made it and the user's decision under R8's
first-adjudication rule.

**Rulings** (user, on the evaluator's classes and scores; not adjudication records). The
evaluate-e2e skill carries each as a scoring rule (SKILL.md §2, under the class table).

- **Classes** (3 November 2026): "may renew" for "must be able to renew" **is** a weakened
  obligation; the edge cases ("renew a loan exactly on its due date", "has already been
  renewed and is now overdue") and the entity meaning ("a borrowable item … can be renewed
  once") **are not** inventions; the trigger "The borrower initiates a renewal request" **is
  not** an invented step. Then (user: "agreed on two rulings"): repetition alone isn't an
  accuracy defect, only a readability one scored against `organization`, while a repeat that
  drops, weakens or adds a condition or obligation is a defect of that kind; and an entity for
  a feature with no business data (hello-world's "Hello World Application") is a minor scope
  defect, at most one point of `proportionate-business-scope`.
- **Severity** (3 November 2026; user: "Q1: yes, Q2: yes, Q3: yes"; the rubric minimum of 3
  makes them decide pass or fail): a section that states a requirement more weakly than a
  correct FR scores that requirement's criterion below 3 (`02-29-15Z`'s story and entity
  meaning "may renew"; `09-33-46Z`'s EC-001 "fourteen days" without the new due date), while a
  summary that doesn't claim to state the requirement ("triggers a success message") costs
  `organization` only; an invented login and selection step in the story is a material
  addition, `source-grounding` below 3 (the rubric names accounts and UI controls); recording
  the renewal ("records the renewal", "updates the loan record") is a minor addition, so
  `source-grounding` can stay at 3: the one-renewal limit needs it.
- **Smaller** (3 November 2026; user: "apply recommendations"): "immediately … followed by" in
  a hello-world story is a minor addition; "notification" or "notified" where it names the
  displayed message is a minor addition; "The user launches the application" isn't an invented
  step; escapes, quoted code spans and joined sentences are judged as rendered and cost
  `organization` only.
- **Titles** (8 November 2026; user: "recommendations accepted for 1 to 6"): a title that gives a
  requirement's value or wording states it, like any repeat above; one that gives none is a
  label, scored against `organization` only (§3 Next 3).
- **Linked Then** (9 November 2026; user: "Once, same evaluator, no re-score"): a defect in an
  edge case's linked Then is filed once, on the criterion (§3 Next 8; skill `185b9bc6…` is the
  same evaluator, [Z_SPEC01](Z_SPEC01.md) T7).

### H2. Review-label confirmation (B2)

The scheme is `b2-review-label/v2` (`.claude/skills/evaluate-e2e/SKILL.md` §7). Since 10
November 2026 §7 carries the convention adopted 1 November 2026: one entry per returned
verdict; a wrong verdict on a defective subject is `wrong_type` (counted in accuracy, and as
a miss in recall); `missed_defect` only when a subject got no verdict at all; `defect_class`
null whenever the expected type is `supported`; path
`evaluations/b2-review-accuracy/<set>/<case>/<run>/`. Q1b's labels predate it: they mark a
`supported` verdict on a defective subject `wrong_type`, `missed_defect` with a null
predicted type (which inflates precision) or both. Relabelling Q1b isn't needed: after D13.1
no post-generation review findings exist to label. §7 also governs required pre-generation
source review, so the convention applies when that review's verdicts are labelled.

### H3. Calibration panels (R8)

The hello-world and loan-renewal panels (each case's `calibration/` under
`test/integration/fixtures/`) have proposed labels only (`human-review.json`,
`qualification.json` `pending`). They qualify only the standalone evaluator; neither the gate
nor SPEC01's sets need them.

### H4. Experiment stops, qualified scope and the formal baseline (B4, B5)

**Decision** needed only before freezing the evaluation protocol's Phase 2 baseline. The
protocol stops at 1,000 sends or 2,000,000 tokens
([README](../test/calibration/semantic-simplicity/README.md):189-190), about 13.9 sends and
27.8k tokens for each of the Phase 2 baseline's 72 workloads. Since ADR 0047 the development
cases use about 9 sends and 13k to 17k tokens a run (the HEAD set: 9 calls, 12,971 to 17,037
tokens; one earlier post-ADR 0047 loan-renewal run used 13 sends and 27.7k, near the
ceiling); before D13.1, hello-world runs that reached source review used 34 sends and up to
67,448 tokens (`2026-11-02T02-28-14Z`). The 72 workloads are the panel's development features
in three variants and three repetitions (README:222-224; §2 rule 11), whose cost on the
current build is unmeasured, and the latest feasibility report
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

Entities and the brief select whole groups (`specification_generation.zig:136-141`,
`:166-169`; `specification_provenance.zig:558-562`), as does the engine-composed story
(`specification_story.zig:48-54`), and reconciliation has formed one signal holding every
quoted claim in every run measured. Measure whether grouping and source review meet the
traceability claim (design.md:121) before any binding change; the advisory evaluate-e2e link
check gives per-record evidence. No second provenance store, no support inferred from text
matching. §10 C11 records one weakened signal and the request shape behind it.

### R6. Semantic repair attribution and recovery

D13.1 removed post-generation review, and loss localization now runs unconditionally
(`pendingLocalization`, `specification_support.zig:319-324`). Remaining proposals, each needing
a closed contract: source-authorized exact-reference repair eligibility (ADR 0033:350-351);
narrow correction of invalid loss evidence (today `invalid`,
`specification_support_workflow.zig:50`; `specification_support_repair.zig:93`); verdict
reassessment under §22.1 with no voting or retry-until-positive. Evidence: of two runs that
reached required source review, `2026-11-02T02-28-14Z`'s repair helped and
`2026-11-02T09-15-31Z`'s false `candidate_omission` on the story ended the run (the story has
since left source review, [Z_SPEC01](Z_SPEC01.md) Q12 D12.3).

### B7 contract-review leftovers

- Prior-state readback checks stored claim text against the text policy only
  (`reference_snapshot.zig:116-117`; ADR 0036:205-206); re-quoting needs the Unicode
  normalizer at readback.
- `source_selections.validate`'s typed `Issue` is discarded by both production callers
  (`validate_reference_claims.zig:32-34`, `source_omission_comparison.zig:130-131`), and
  `validate-reference-selections` validates token classifications only. Delete the unused
  detail and rename the step and key for what they do (touches `spec.workflow.yaml`, F0100,
  `workflow_tests.zig` and nine `src` files; lands in a gap).

### Design–code conflicts (7 November 2026 review)

**Defect:** none in published output: design text that the code contradicts or lacks misleads
design-routed changes. **Owner:** the cited documents (ADR and AGENTS.md changes are policy
edits). **Next:** **Decision** marks what only the user settles; F0002 is a code change.

- **Semantic-review and no-invention branches (Decision: keep or remove):** since D13.1 no
  Spec route produces a finding on generated content or a no-invention replacement (`src/` has
  no `invention`; source review admits F0100 §3.10's support findings), yet 13-04's repair and
  no-invention proposal entries, 12-model-boundary.md:505-507,
  14-orchestration.md:155-160 and :164-168, 22-repair.md:209-211 and :417-419 (principle citation
  diagnostics), invariant 18 (design.md:950-953), ADR 0033:138-139 and code.md samples 3, 4,
  13 and 28 keep them.
- **F0002 event registry** against `src/domain/log_event_registry.zig`. **Decided** (9 November
  2026): F0002 stays the target (F0002 §4 says so); the code change is open. F0002 requires
  `repair_unit_kind` on `repair.applied` and `task_id` on `task.completed` and `task.failed`
  (F0002:365, :377, :379), which the code doesn't (`:47`, `:62-66`); no event admits the
  common optional `evidence_status` (F0002:319-320; `validateFact`, `:88-97`); `diagnostic_code`
  is a closed enum (F0002:329) but a validated token in code (`telemetry.zig:175-184`); the
  registry owns sensitivity (F0002:153), but `EventDefinition` has none (`:31-37`);
  `TelemetryFact` is one variant per event (F0002:193-217), but one struct with `event_type`
  and `fields` in code (`telemetry.zig:205-212`). **Next:** the code change, recording any
  event-row or report version it moves (§2 rule 12).
- **Upstream rework as a form (Decision):** `required_authority_clarifications.build` turns an
  `upstream_rework_required` entry into a form for its owner stage (`:15`), where §14.14 sends
  an earlier-owner gap to §24.5's invalidation route. In the graph the gate blocks any set
  holding such an entry before `build` runs (`required_authority.zig:275`), so only
  `required_authority_test.zig:515-559`, which calls `build` directly, exercises it; Spec also
  detects only at `spec` (`workflow_outcome_binding.zig:717`, `specification_authority.zig:57`,
  `source_preservation.zig:23`). Settle it before a downstream stage detects gaps (ADR 0034).
  No test covers the path the graph does reach, two same-stage `clarification_required` gaps
  becoming two forms (§14.14).
- **Renderer version (Decision):** 23-rendering.md §23.1, 24-workflow-state.md:154,
  and 13-01's `ValidateRendererContractVersionAction` require a renderer
  version recorded in state and views, and renewed plan/task review when review-visible bytes
  change; Spec state records none (`specification_state.zig:8-24`) and a rerun regenerates the
  views (ADR 0036:177-178). Keep it as the target for stages that persist review-visible views,
  or remove it across those sites?
- **Mid-run logging transition (Decision):** 14-orchestration.md:267-268,
  :280-281 and :292 require a committed, durable successor bootstrap authority; §9.4 keeps
  changed candidates execution-local with no independent successor (09-configuration.md:376-378,
  as ADR 0009 keeps candidate outputs private) and switches "after an adopting route"
  (:400-401); the validator checks neither (`validate_feature_log_policy_transition.zig:17-31`).
  **Recommended:** §9.4's reading, an execution-local successor with no durability proof.
- More, from the 11 November 2026 code review: §10 C39.

### Retired SPEC01 IDs cited elsewhere

"SPEC01 <ID>" citations of items now in [Z_SPEC01](Z_SPEC01.md) resolve there.

### Wider scope retained

- **Memory and scale:** growing review sets, retained bytes, allocations, teardown,
  cancellation and OOM. Unmeasured.
- **Harness acceptance (former H-012, H-013, H-017; git `8ed40ba`):** still open:
  - publication interruption: every write failure is covered as a failpoint at the writer, but
    no process kill is tested and no test reruns the workflow over the leftover files. **Not
    closed:** §10 C2 reads a window (not executed) in which the rerun fails, against ADR
    0009:144-146;
  - rerun replacement through an unrelated workflow: covered at the shared writer; reopen when
    the first non-Spec publisher lands;
  - live negative cases as separate fixtures: none exist (`test/e2e/` holds the two
    development cases); adding them means live spend, the user's call.
- **Live-test cost policy help:** ADR 0029 names `anthropic` / `claude-haiku-5-5` for
  generation (user decision, 9 November 2026), but `test/harness/e2e/cli.zig:26`'s help still
  lists only the two Bedrock tuples and the Bedrock credential, and
  `test/harness/model_cost_policy.zig:23` cites ADR 0028 for the tuple. Correct both with the
  next harness code change. No live Claude call has been made.

### R-A1. Engine-owned release

Whether the engine also takes over release, changing ADR 0012's retained-request handoff (ADR
0030:475-477). Decide after E1.

## 9. Guardrails

The user's standing constraints beyond AGENTS.md:

- No model change or comparison (H5).
- The workflow never modifies principle files (1 November 2026; Q17).
- No caps that discard output, and no larger token budget: a budget failure is fixed at its
  cause, such as review cost or runaways (30 October 2026). No local token ceilings, no
  truncated required evidence, no claim that a larger budget fixes reliability.
- These single-run prompt sentences stay until a defect is traced to one (D5.1, 3 November
  2026; the former Q5, git `0f3e4d2`):
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
    is unnecessary." (`entities`).
- Never batch or group source-review subjects (30 October 2026); this binds the remaining
  pre-generation source review.
- Measures and replays use the owning steps (`zig build e2e-measures`, `e2e-call`), never
  one-off scripts, loops or new tracking files (29 October 2026).
- Don't narrow the entity-name exception without a decision (B6; `text_field_policy.zig:61`,
  `:69-74`; the composed story shares its incidental role since ADR 0047).
- Runaways stay a reported measure (ADR 0039).

## 10. Code review of the Spec workflow (C)

Read-only review completed on 11 November 2026 (user: "review the current spec workflow source
code, do complete end 2 end analysis, do not guess").

- **Scope:** all 701 production files under `src/` (68,383 lines), read in seven areas, and
  `spec.workflow.yaml` with its 24 resources. Tests and the harness were measured, not read in
  full. `src/debugger/` (web assets) wasn't reviewed.
- **Evidence:** every cited line was printed and checked against its claim. "Not executed" marks
  a path established by reading only. "Traced" marks a count or a reach taken from reading call
  sites and not recounted. "Grep" marks a search of the production tree.
- **Runs:** the six runs of 10 November 2026 UTC (`zig-out/e2e-spec/2026-11-10T19-41-*`, 3 per
  case, build `a6ae058`, `modified` true, source `527484a8…`, Debug), which the user started
  before asking for this review. They are not a measurement set (§2 rule 3) and decide nothing.
  Their sends, tokens and logged span are `e2e-measures` values
  (`evaluations/e2e/<run>/measures.json`). Every other run figure in this section is
  indicative: it was counted by one-off reads of retained requests, responses and logs, which
  §9 reserves for the owning steps and the user hasn't approved, so none may serve §2 rules 5–7
  (C18). "The 38 runs" are the retained runs on `aws-bedrock` / `openai.gpt-oss-20b-1:0`. The
  four retained `anthropic` / `claude-haiku-5-5` runs of 9 November 2026 are left out and no
  model is compared (§9). T5's counts were not retaken.
- **Status:** nothing here is approved or scheduled, and each item needs its phase approval
  (§2). An item that names no defect class targets no published-output defect: it reports a fact
  or asks a Decision, and proposes no change (AGENTS.md: cost is reported, never the reason for
  a change). An item that changes a model request is a Q phase with a named class. **D** marks a
  cost that an accepted ADR or a contract requires, so removing it is a **Decision**.

### 10.1 Failures first

**C1. An empty array at admission aborts the process.**
`src/domain/model_payload_schema.zig:209-210` runs `for (1..count)` whenever an array has a member
set; on the pinned Zig 0.16.0 that loop panics with `integer overflow` when `count` is 0 (run as
a standalone probe). An empty array reaches it when the schema has no `minItems` and the member
count is `native`, which keeps the schema's minimum (`model_result_schema.zig:445-448`, default 0
at `:855`): the dispositions request (`reference_model_input.zig:242-245`;
`reconciliation.schema.json:507-526`). So `{"claim_dispositions":[],"conflict_groups":[]}` ends
the run with a panic, not the correction `reference_model_input.zig:238-240` describes. The
membership test's schema has `"minItems":1` (`src/model_payload_schema_test.zig:751`, asserted
at `:762`), so it never feeds an empty array. **Class:** successful completion (AGENTS.md
"Expected rejections are typed outcomes"). **Owner:** `model_payload_schema.zig`. Not executed
in the engine. **Next:** a unit case with a `minItems`-less array, a native member set and `[]`,
then the guard. No request changes.

**C2. A publication interrupted between a form and its state blocks every rerun.** Forms are
written before the clarification state (`clarification_output.zig:17-29`), one file at a time
with no rollback (`adapters/filesystem/workflow_output.zig:1-2`, `:56-87`), and each file is
truncated in place before it is written (`file_access.zig:8-9`, `:40-42`). The next run fails
`prepare-inputs` when forms exist without a state or their count differs from its records
(`validate_clarification_forms.zig:19-22`; `spec.workflow.yaml:251-253`). ADR 0009's acceptance
(`:144-146`) requires that "a fresh rerun replaces the complete output set without recovery".
The failpoint test drives the input capturer and the writer with placeholder bytes and fails
before the file is touched (`test/integration/workflow_tests.zig:3019-3103`, `:3028`), so it
exercises neither the truncation nor the next run's form validation. **Reach:** only when a form
is written, which no development case does; the truncation window covers both state files on
every publication. Not executed. **Class:** successful completion. **Owner:**
`clarification_output.zig` and the publication writer. **Next:** an integration scenario that
fails the clarification-state write and reruns the workflow, then a **Decision** on the remedy,
since ADR 0009:122-123 rules out rollback and recovery stores.

**C3. A console or flush failure after a successful append leaves the log unclosable.**
`feature_log_runner.zig:222-234` appends the row, writes it to the console
(`catch return error.ConsoleFailure`, `:232`) and only then advances `event_state` (`:233-234`);
the append writes before it syncs (`feature_log_segment_store.zig:99-100`). After either failure
the row is on disk and the state isn't advanced, and every later append and the close require
the file size to equal that stale state (`:96`, `:125-126`). The prompt stream has the same shape
(`feature_log_runner.zig:328-341`). The segment keeps no trailer, which ADR 0026:95-100 treats
as a crashed run. Not executed; the test checks the failing call only
(`src/feature_log_runtime_test.zig:409-438`). **Class:** successful completion. **Owner:**
`feature_log_runner.zig` (`persistEvent`, `persistPrompt`). **Next:** a runner test that appends
again after each failure.

**C4. Most failures report one payload-free name (adds to E5).**

- **Provider and authorization:** the provider result holds a typed cause and a transport
  diagnostic (`llm_provider_operation.zig:170-180`, `:193-205`), but nothing logs or reports
  them: outside `domain/` and `adapters/` the cause is only built or compared
  (`workflow_provider_authorization.zig:80-81`; grep). `model.completed` has no cause field and
  is emitted with a null reason (`log_event_registry.zig:68`;
  `workflow_pipeline_runner.zig:500`). The CLI prints the outcome tag, then an operation error
  name or a candidate diagnostic if the run recorded one (`src/main.zig:43-45`). A missing key
  and a malformed one are the same case (`provider_api_key.zig:35-37`), and the response decode
  diagnostic is dropped (`provider_response_assembly.zig:127`). So a missing key, HTTP 401, 403
  or 429 and a DNS or TLS failure should all read `failed`. Not executed.
- **Workflow definition:** every schema, compile and graph rejection is one of two codes with
  no step, key or rule (`compile_workflow_graphs.zig:13`; 66 `invalid()` lines there, 38 in
  `validate_compiled_workflow_graphs.zig`, 69 in `validate_workflow_definition_schema.zig`;
  mapped at `bootstrap_workflow_runner.zig:212`, `:224`, `:255`, `:265`). A key missed from a
  hand-written invalidation list (`source_omission.zig:343`, `:345`; `required_authority.zig:123`)
  fails the same way, because the data-flow check rejects producing a key that is still
  available (`workflow_data_flow.zig:87-95`).
- **Result schemas and compositions:** 90 and 48 `invalid()` lines, one error each
  (`model_result_schema.zig`, `json_composition.zig`).
- **Reference ingestion:** ten typed reasons (`reference_ingestion.zig:42-53`) are discarded;
  each becomes `InvalidReferenceAccounting` (`validate_reference_accounting.zig:29`, `:44`),
  against ADR 0036:198-200 ("fails at ingestion with a typed reason", said of malformed text).
  Any file that isn't `.md` or `.markdown` is one of them (`markdown_reference.zig:17`).
- **Toolchain:** `error.InvalidToolchain` on 68 lines in ten files.
- **Runner:** `.rejected = .authority` on 121 lines of `workflow_pipeline_runner.zig`.

**C5. Model answers the schema admits that end the run with no correction.**

- `claims: []` with nothing preserved: `validate_reference_claims.zig:28` returns an error and
  the step has no `invalid` route (`spec.workflow.yaml:425-427`), so the run ends `failed`.
  F0100:325-326 states the rule, not its outcome.
- A repeated ID in `claim_ids` or `signal_ids` is rejected at parse
  (`specification_generation.zig:156-157`; `specification_source_binding.zig:166`) and routed
  `invalid: end.invalid` (`spec.workflow.yaml:739`). **D:** ADR 0038:88-89.
- An edge case with no candidate criterion ends `blocked` after every generation call
  (`scenario_link.zig:46-48`; `scenario_link_request.zig:57-60`).

**Class:** successful completion. **Owners:** `validate_reference_claims.zig` and its route;
`specification_generation.zig` (the ADR 0038 parse); `scenario_link.zig`. **Next:** a
**Decision** for each on correction against stop.

**C6. A descriptor that passes registry and graph validation can fail at run time.**
`validDescriptor` checks that the keys are declared and that the kind and repair role fit
(`workflow_outcome_association.zig:586-602`). At run time the binding looks the result key up in
hard-coded tables that end `else => return error.InvalidOutcomeAssociation`
(`workflow_outcome_binding.zig:432-438`; also `:200-206`, `:421`). Giving another authorizer a
`blocked` outcome compiles, validates and then rejects the first run that takes it. Not
executed. **Owner:** `workflow_outcome_binding.zig`.

**C7. Stray files and directory modes (Decisions).** **Class:** successful completion for the
first two; none for the third. **Owners:** the filesystem adapters cited.

- Any entry in `clarify/` that isn't a six-character `.md` name fails the run
  (`adapters/filesystem/feature_input_source.zig:83-85`; asserted at
  `test/integration/workflow_tests.zig:2860`, `:2869`). F0100:197-203 intends it; the user
  exempted the same case for log folders (ADR 0026:73-75, log-folder entries amendment).
  **Decision:** the same exemption for `clarify/`?
- Any non-Markdown file in the reference directory fails ingestion (C4). **Decision:** skip it, or
  keep failing with its typed reason?
- Activation creates every missing directory owner-only, the specs root and the feature
  directory included (`adapters/filesystem/feature_log_layout.zig:12`, `:71`, `:74`);
  `project/specs` and `project/specs/hello-world` are mode 700 in `2026-11-10T19-41-09Z-22a6…`.
  The design names only log directories (ADR 0018:65; 26-security.md:208). **Decision:**
  intended?

**C8. Clarification records (adds to E7).**

- Nothing closes a record. The only status writer sets `open` (`clarification_refresh.zig:124`;
  no production code assigns a resolved or cancelled status, by grep), prior subjects are
  retained (`:61-62`), and any open record gives `needs_user` (`:54-59`). A rerun with an open
  record still makes every model call, because open records are first checked at
  `check-output-clarifications` (`spec.workflow.yaml:832-834`), after generation.
- Authority subjects are keyed by per-run ordinals and the contract version
  (`required_authority_clarifications.zig:77-88`), which `source_preservation.zig:26` says don't
  survive a rebuild. 24-workflow-state.md:113-115 says regenerated IDs don't define a new
  clarification.

### 10.2 Optimisation

**C9. Where a run's time and tokens go (facts; no item).**

- 263–275 runner steps for nine model calls. 99 are the request lifecycle (11 a call); with the
  prepare, retain and retire steps around it, 119, or 43–45% of a run (E1).
- Mean logged span 8.65 s: 92.2% inside the nine `invoke-model` steps, 3.4% inside all other
  steps, 4.3% between steps. The 40 steps before logging starts aren't timed.
- Each call step runs about 110 ms longer than the provider's reported latency (11.5% of the
  span). That covers connection setup and the prompt-log writes, unsplit (C13, C14).
- Input tokens are 92.5% of a hello-world run (11,987) and 89.7% of a loan-renewal run (14,816).

**C10. The conflicts request is sent when only one answer is admissible.** No branch tests whether
a conflict group was accepted: after signals the phase is `.signals`
(`reference_reconciliation_stage.zig:106`) and `check-conflicts` routes to the request
(`spec.workflow.yaml:553-563`). With no group the choice set is empty
(`reference_reconciliation_stage.zig:79-81`) and the schema owner narrows the array to
`maxItems: 0` (`model_result_schema.zig:423-430`). In the 38 runs every conflicts request
carries `"maxItems":0` and every answer is `{"conflicts":[]}`. The call is 9.4% of their model
tokens (1,128 and 1,651 input tokens a run in the two cases) and can only return the forced
value or fail. **D:** ADR 0022:108-109 ("Empty eligible catalogues admit only an empty authored
collection"); `:136-138` already constructs forced token classifications natively with no call
(`construct_forced_token_classifications.zig`). **Class:** successful completion in principle,
since the call can only fail; no such failure is observed, so no benefit is demonstrated.
**Owner:** `reference_reconciliation_stage.zig` and the `check-conflicts` route. **Decision:**
whether ADR 0022's native rule extends to the conflicts stage. No other request would change.

**C11. The leaf summary adds a paraphrase that only the next reconciliation requests read (adds to
R1).** For one source of up to eight claims the leaf summary is always requested: native reuse
needs exactly one child (`reference_reconciliation_validation.zig:491`). Its prose is sent to the
dispositions and signals requests (`reference_model_input.zig:155-161`); that it is neither
persisted nor rendered is traced. Those requests carry it without the "earlier summaries are
supporting context" purpose, which is attached to summary requests only
(`reference_model_input.zig:89`; `packet-guidance.json:57`).

- In 29 of the 38 runs the signal's content equals the summary statement's.
- In `2026-11-10T19-41-11Z-986f…` the summary wrote "A borrower may renew" for "must be able to
  renew", the signal copied it, and `reference-context.md` SIG-1 published it (1 of the 19
  loan-renewal contexts in the 38 runs). `spec.md` kept "must be able to renew": that run's
  three generation requests carry neither the summary nor the signal wording (checked). Signal
  prose is also sent to source review when that runs
  (`specification_review_subject.zig:38-39`).
- The summary call is 9.6% of the 38 runs' model tokens and the four reconciliation calls
  40.7%. They returned 152 of 152 dispositions `retained`, one signal holding every model claim
  in all 38, and no conflict.

**Class:** weakened obligation in the published reference context (the case rubrics score
`spec.md` only). One observation on a modified build is not enough evidence (§2 rule 6;
AGENTS.md: a single run never decides), so this is a lead for R1's measurement and proposes no
change. **D:** 16-reference-ingestion.md:242, ADR 0022 and ADR 0036:44 keep leaf summaries and
model-written signals; ADR 0036:196-197 leaves native claim references open ("needs its own
evidence").

**C12. Request composition.** Share of all request characters in a run (hello-world /
loan-renewal):

| Part | Share | Authority |
| --- | --- | --- |
| Result schema as system text | 26.4% / 22.4% | **D:** ADR 0006:124-132 |
| The same schema as the provider's native schema | 21.8% / 18.5% | **D:** same, with `json: true` |
| `[string or fragments]` alternative where no insertion is offered (both copies) | 12.6% / 10.7% | Q7 D7.5: decided, not implemented |
| `4294967295` bounds in the text copy | 3.0% / 2.5% | The schema files state them (ADR 0006's grammar; §9 no caps) |
| `field_rules` | 7.1% / 6.0% | none found |

- The two schema copies differ. None of the 345 native copies in the 38 runs has a `maxItems` or
  a `minItems` above 1: `conflict_groups` reads `minItems: 2` in the text and `1` natively in
  all 38 dispositions requests, and the conflicts `maxItems: 0` exists only in the text.
  Whether the native copy is billed can't be told from these runs. Prompt-only mode
  (`json: false`, F0007:81) would send one copy; that bears on §3 "Provider doesn't enforce the
  response schema".
- `field_rules` repeats one instruction for each text field (`model_field_presentation.zig:90`):
  11 rules with one distinct instruction in the records request, 54% and 46% of its user packet.
  `generation.context.json:2` states the prose and exact-value rule again in other words.
- Each reconciliation packet carries the claim wording three times: in `claims`, in
  `citations[].verbatim` and in the summaries or accepted signals. `citations`, mostly location
  fields, is 22–37% of a packet and the summaries or signals 12–16%. No reconciliation response
  can cite (the schema has no citation field). **D:** ADR 0022:92-94, which predates ADR 0036's
  quoted claims.

Each change here would be a model-input change (a measured set, §2 rules 4 and 6). None is
proposed.

**C13. A new HTTP client and connection for every model call.** `model_http_exchange.zig:101-108`
(`.keep_alive = false`; the comment lists "connection reuse" among what isn't installed). No
design text requires or forbids reuse (grep of `design/`). How much of C9's 110 ms it accounts
for isn't measured (C17).

**C14. Log volume and per-record work.**

- At `debug` the prompt log is 851–889 KB a run, and 76.7% of it is the request-source snapshot:
  the workflow YAML and bound resources, rewritten for each of the nine requests
  (`request_source_capture.zig:50`). **D:** ADR 0019:95-101.
- Each record reopens the lock file and the segment (`feature_log_orchestrator.zig:17-29`;
  `feature_log_segment_store.zig:88-100`): about nine system calls (traced) for each of the 656
  records of a hello-world run (492 event, 164 prompt). The lock per record is **D**
  (F0002:250-251; 26-security.md:216-219); reopening the files is not.
- Activation re-reads every prior segment of the feature and walks every earlier run directory
  (`adapters/filesystem/feature_log_history.zig:46-92`). **D:** ADR 0026, whose `:138-139`
  records that the number of prior runs is unbounded. The harness never meets it: each run has a
  fresh project.

**C15. Repeated native work (no time to recover; one rule kept at many sites).**

- Every executed step revalidates the whole operation registry, a pairwise ID loop over 201
  operations included (`workflow_pipeline_runner.zig:168`, `:693`;
  `ports/workflow_operation_registry.zig:117-140`, "Rebuild on every call").
- The clean path re-runs validators in all six runs: `validate-dispositions` three times and
  `validate-signals` twice, because each release returns to the first validator
  (`spec.workflow.yaml:549`, `:569`); `check-summary-reuse` and `validate-summary` twice, once
  for the requested leaf summary and once for the parent partition that reuses it.
- One request packet is built through 10 to 15 full copies (traced), each copying every source's
  bytes (`model_input_packet.zig:164-205`, `:199`).
- The codec parses a response, re-serialises it and parses it again
  (`model_candidate_json.zig:128-135`).
- Publication renders `spec.md` five times and parses it twice (`render_specification.zig:13`;
  `validate_specification_rendering.zig:14-17`; `prepare_specification_output.zig:24-25`).
  **D:** 13-05:364-370, :381-388.
- `token_classification_validation.zig:213` hashes every source byte into a value whose only
  use is a copy (`build_preserved_token_claims.zig:38`; traced).
- Graph validations run two or three times at startup (traced), with the retry-authority block
  duplicated (`validate_compiled_workflow_graphs.zig:54-68`; `workflow_registry.zig:172-186`).

**C16. Source review, when it runs, sends the whole evidence catalogue with every per-subject
request** (`specification_support.zig:129`; traced: the ledger is rebuilt nine times a subject).
§7 H4 records 34 sends and 67,448 tokens for a hello-world run that reached it. One request a
subject is the user's guardrail and §9 forbids truncating required evidence, so no change is
proposed.

**C17. Several of these counts aren't in the owning step.** `e2e-measures` gives sends, tokens,
stages and the logged span. It doesn't give the time split and per-call gap of C9, the
forced-answer count of C10, the reconciliation counts of C11, the request-part shares and
schema differences of C12, the log bytes of C14 or the passive-literal count of C48.

**C18. Next for C9–C17:** a **Decision** on which of those counts `e2e-measures` should own,
under a new measures version, so a set reports them from the owning step. Until then they stay
indicative (§9). **Class:** measurement. **Owner:** `test/harness/e2e/measures.zig`.

### 10.3 Coupling

**C19. The generic domain core imports the Spec stages.** 115 files, 113 in `domain/` and 2 in
`ports/`, form one import cycle (701 files, 4,288 import edges; `pipeline.zig` is imported by
337). The engine's error set is a union of 37 error sets (`operation_error.zig:55-91`,
re-exported at `workflow_execution.zig:52`); that file imports 31 others, 14 of them Spec-stage
modules, and each Spec file imports `pipeline.zig` for data keys. ADR 0003:100-101 says the four
workflows are "not special cases in the generic engine". The layer test checks layers, not
cycles inside `domain/`.

**C20. `DataKey` is one closed enum of 194 keys** (`pipeline.zig:4-199`). Traced split: 42
startup, 23 logging, 17 model request, 2 output, and 110 that only Spec operations touch. Every
per-step structure is sized by the total. **D:** 06-pipeline-nodes.md:91; ADR 0003:84-85.

**C21. The generic outcome association hard-codes Spec keys and types.**
`workflow_outcome_association.zig:112-113` holds `required_authority.zig` and
`clarification_refresh.zig` result types, and six of its 15 descriptor variants
(`workflow_outcome_association.zig:19-35`) are assigned at one or two sites (grep).
`workflow_outcome_binding.zig` branches on `.required_authority_result` and
`.validated_specification_unit` (`:200-206`), `.specification_support_review` (`:421`) and four
repair keys (`:432-438`). A second workflow with its own gate, clarification route or blockable
repair needs edits to both files.

**C22. Change amplification (traced).**

- One operation with one new key: 8 production files and 15 sites.
  `native_workflow_operations.zig` keeps three parallel lists of about 170 lines and a hand-kept
  count (`:229`, `core.entries.len + 169 + model_request.count`).
- One record family: three Zig files the compiler enforces, plus `generation.schema.json`,
  `packet-guidance.json`, the prose of `records.prompt.md:9-13` and
  `specification_markdown.zig:155`, which it doesn't.
- One reconciliation phase: five parallel enums (`reference_reconciliation.zig:125`,
  `reference_reconciliation_stage.zig:6`, `reference_reconciliation_diagnostic.zig:57`,
  `reference_reconciliation_repair.zig:499`, `reference_reconciliation_repair_workflow.zig:35`)
  and the YAML strings (`reference_reconciliation_stage_workflow.zig:75`), bridged by tag name.

**C23. The model boundary carries Spec names.** The 33-tag `text_field_policy.Field` is part of
the generic field binding (`model_text_field.zig:5-7`); ADR 0038's statement rule is wired through
generic admission (`model_payload_schema.zig:4`); the schema and admission files sit inside the
115-file cycle (C19). One text field is described in up to six places under three names (traced:
the brief title as `title`, `display_name` and `spec_title`).

**C24. One request fact is held in up to five ledgers and re-checked at five to seven sites**
(attempt number, the binding, input and sampling triple, deadline, terminal outcome; traced).
**D:** model-request-operations.md:62-65, :113-118; ADR 0030:194-197 keeps the rules after E1.

**C25. Reference, repair and review modules import each other, and six files reach through the
validators' nesting.** `reference_reconciliation.zig:123` imports its diagnostic,
which imports the repair owner (`reference_reconciliation_diagnostic.zig:16`), which imports
`source_omission.zig` (`reference_reconciliation_repair.zig:687`), which imports
`specification_support.zig` (`source_omission.zig:52`). Ten production sites in six files reach
`assignments.checked.prior.prior` directly (for example `specification_provenance.zig:27`, `:32`,
`:41`, `:52`), although `reference_support.zig:26` wraps it.

### 10.4 Simplification

**C26. Registered operations that no shipped workflow uses.** `design/workflows/` holds one
definition.

- No workflow anywhere: `prepare-clarification-output` (registered at
  `native_workflow_operations.zig:566`).
- Test workflows only: `scan-path-tokens`, `validate-source-citations`,
  `parse-required-authority-observations`. Their keys (`path_token_scan`,
  `reference_citation_proposals`, `validated_source_citations`,
  `raw_required_authority_observations`) have no other producer or consumer.
- Registered beside the consolidated operation Spec uses: the four principle steps
  (`native_workflow_operations.zig:409-413`; 13-01:442-443 documents them).

**C27. Code with no production caller.** Each was checked by grep with tests excluded.

- `model_request_handoff.zig:213` `acceptsRetained`; `model_request_workflow.zig:156`
  `selectionForPacket`; `model_text_wire.zig:106-122` `checkProseFields` and its helper;
  `model_result_schema.zig:13` `ChoiceBoundError`.
- The engine-constructed singleton choice (`.singleton = .construct`), superseded by ADR
  0020:26-28 and set only in tests (adds to E9).
- `PipelineEnvelope.place` (`pipeline_envelope.zig:75-84`); `DataKey.feature_log_recovery` and
  `.log_drop_evidence` (`pipeline.zig:185`, `:197`).
- `ValidToolchain.packages()` (`toolchain_safety.zig:10-12`); `ToolChainService`
  (`toolchain_service.zig`), which F0003:214 says the runner constructs.
- `generation.schema.json:485-496` `repair_record_functional_requirement` has no reference in
  the schema or the code, like the `repair_record_acceptance_criterion` Q14 records.
  `attributed_value` (`:3-14`) has the same body as `value` (`:497-508`); code selects each by
  name (`specification_repair.zig:269-271`).

**C28. Paths no production run can take.**

- Nothing supplies a cancellation or deadline status: production passes the default runtime
  (`composition/root.zig:53`; `pipeline.zig:242`, `alwaysActive`), no production code sets
  `status_fn` and no signal is handled (grep). So the branches on a `cancelled` or
  `deadline_exhausted` runtime status run only in tests, E6's cancellation change included, and
  an interrupt ends the process with no finalization.
- Feature logging: `WorkflowLog.log` (`pipeline.zig:326-339`) has no production caller (grep);
  the mid-run policy transition, historical finalization and the non-empty recovery path have
  test callers only (traced). The designs specify them (14-orchestration.md §§14.9–14.10;
  27-observability.md:6-10); ADR 0009's fresh-run rule and ADR 0026:8-9 leave them unused.

**C29. YAML duplicates, dead edges and one-valued options.** Bare line numbers in this item are
`spec.workflow.yaml`.

- Identical bodies: the `model-request` and `support-request` subgraphs (`:922-953`; E1 removes
  both); the `finish-native` and `finish-model` steps (`:348-353`); the `release-signals` and
  `release-conflicts` steps (`:547-549`, `:567-569`). `repair-source-extraction` and
  `repair-source-candidate` (`:856-886`) differ in one step. Only the step-trace fixture names
  any of these: `model-request` and `support-request`
  (`src/test_fixtures/workflow_step_trace.zig:19`). Whether the join rule
  (`workflow_data_flow.zig:70`) requires the paired steps wasn't checked.
- `check-reconciliation`'s `ok: end.ok` (`:505-507`) can't be taken. The step runs only after a
  summary response or repair, on the input for which the same check returned `more` at
  `select-composition` (`:460-462`; `check_reference_reconciliation_purpose.zig:5-8`), and that
  input is rebuilt only after `build-summary`.
- `clarification-output` (`:1057-1080`) repeats four of the last seven operations of
  `publish-specification` in the same order, and `check-clarification-progress` runs twice in a
  row on the pending path (`:832-834`, then `:1060-1062`).
- Every call site passes `selection: input` (nine sites; `:916` hard-codes it).

**C30. Typed machinery whose result is constant.**

- Coverage repair can only block: a one-variant decision (`specification_coverage_repair.zig:10`,
  `:22-30`) with a repair role, a descriptor, a data key and a binding branch
  (`workflow_outcome_binding.zig:433`). The step has no `ok` route (`spec.workflow.yaml:811-813`).
  Q21 owns the gap that this route blocks on.
- `validated_specification_rendering` is always `true`
  (`specification_rendering_workflow.zig:53`), so the `!rendering_valid` checks
  (`build_specification_state.zig:16`; `prepare_specification_output.zig:17`) can't fire.
- The authority outcome is computed by `reconcile` and again by `validate`
  (`required_authority.zig:364-365`), and all four `reconcile` outcomes route to `gate`
  (`spec.workflow.yaml:1053`). **D:** 13-10:81-83. The `required-authority@1` gate is registered
  (`native_workflow_operations.zig:579`), but no production operation declares it (`:665`),
  against F0100:723.
- `checkConsistency` is called at admission, story composition and assembly
  (`validate_specification_unit.zig:11`; `compose_specification_story.zig:21`;
  `specification_session.zig:631`), but acts only on a records batch while records are being
  admitted (`specification_session.zig:541-546`), so the other two calls return null (read).

**C31. Per-kind and copied code (traced unless a line is cited).**

- Reconciliation writes statement, signal and conflict logic once a kind
  (`reference_reconciliation_repair.zig:589-594` beside `:597-602`); 13 action files differ only
  in their contract literal. The one-contract-per-file rule is **D**; the domain repetition isn't.
- `persistEvent` and `persistPrompt` (`feature_log_runner.zig:153-236`, `:274-342`) differ in
  builder, serialiser and stream tag, so C3 has to be fixed twice.
- The open-fstat-check sequence for a log segment is written seven times, and the bounded read
  helper is re-implemented five times.
- The ledger owner block is written five times, and four identical revision structs exist.
- The engine-config and provider-config readers duplicate each other with different rigour
  (`adapters/filesystem/engine_config_source.zig:116-134` has no post-read check).

**C32. The toolchain stage feeds only a policy list and an identity.** 47 action contracts require
`valid_toolchain`; production reads `policies()` and `identity()` only (grep). Both development
cases run with `presets: []` and `policies: []` (`project/.sddtoolkit/principles/toolchain.yaml`;
one run of each case checked), so the nine steps always give the compiled-in rules. Adds to E2.

**C33. JSON composition is 987 production lines for two uses** (traced), one of which, the summary,
has a single part. **D:** ADR 0016:42, :246-247.

### 10.5 Brittleness (latent)

**C34. Names carried as strings.**

- Result-schema definition names are also built from enum tags
  (`reference_reconciliation_stage.zig:141`, `@tagName(v) ++ "_assignment"`;
  `reference_reconciliation_repair.zig:330`, `"repair_{s}"`), so renaming a tag changes the
  definition a request selects. Adds to E8.
- Operation parameter names are spelled in a descriptor table and again at each lookup
  (`model_request_workflow.zig:27-32` against `:166-192`). The lookup returns null on a miss
  (`:236-242`), so a drifted optional `context` or `protocol-prompt` is dropped from the request
  with no error.
- The support packet is edited by raw JSON key after encoding (`specification_support.zig:134-148`:
  `getPtr("…").?`, and `orderedRemove` with its result discarded).
- Log columns are read by literal position in the recovery, retention and debugger readers
  (traced: 25 sites in `feature_log_format.zig` and `feature_log_recovery.zig`, about 35 in
  `request_debugger_archive.zig`).

**C35. `else` arms on closed sets.** Production has 300 `else =>` arms in 126 files; not all are on
closed sets. Arms that give a default and no error: `model_result_schema.zig:931` (a shallow
copy of any other node; the file has 14 arms), `reference_reconciliation_repair.zig:385`,
`:472`, `:485`, `:586`, `:623` (the file has 23), `bootstrap_roots.zig:34`, `:41`,
`log_event_registry.zig:135`, `workflow_registry.zig:304`. AGENTS.md asks for exhaustive
switches on closed sets.

**C36. Order and position.**

- `required_authority.zig:358` compares the ordinals of two different enums (`DetectionStage`
  and `Stage`, `:356`); `:401-414` orders by declaration order.
- Unit kinds are compared by integer tag across two unions (`specification_generation.zig:240`;
  `specification_repair.zig:212`).
- The YAML pairs prompts with units by step position (`spec.workflow.yaml:701-715`) and nothing
  ties a prompt to its unit (no Zig file names the three prompt resources, by grep), so a
  swapped prompt would be accepted.

**C37. Limits that don't bind, and hand counts.**

- `retry-limit: 64` (`spec.workflow.yaml:770`) and `128` (`:525`, `:593`, `:618`) count visits
  per defect key, which the repair routes can't reach (traced). The real bound is a target
  population written as literals (`specification_repair.zig:186-196`;
  `reference_reconciliation_repair.zig:126-131`). An overflow surfaces as the payload-free
  `.authority` rejection (traced).
- The retry limit is enforced by two formulas with two errors (`workflow_retry.zig:423`;
  `model_attempt_accounting.zig:288`); the second can't fire through the runner (traced).
- The 64 MiB value bound is written 11 times in six application files (grep; for example
  `passive_literal_workflow.zig:16-18`).

**C38. A passing `zig build verify` reads as a failure.** A passing run prints 6.2 MB: 4,437
feature-log rows and two `failed command:` lines, which Zig prints for any step that wrote to
stderr (`test-integration`, and `test` through `emit_emergency_log_failure_record.zig:22`). The
default summary mode prints no success line; only `--summary line` shows `169/169 steps
succeeded; 2003/2003 tests passed`. **Owner:** the tests that write to the real stderr.

**C39. Design text the code contradicts (adds to §8 "Design–code conflicts").** F0100:723
("Protected operations declare that gate"; C30). F0003:214 (the runner constructs
`ToolChainService`; C27). 26-security.md:224-225 says a log row is encoded before the lock is
taken; `feature_log_orchestrator.zig:17-22` takes the lock first. 13-05:276-278 and ADR
0021:24-25 predate the source-preservation projection (traced).

### 10.6 Tests and harness

**C40. A scripted scenario is identified by its position, and the position names its
request-projection freeze.** `runSpecificationWorkflows`
(`test/integration/workflow_tests.zig:1367-2608`) derives 134 scenario indices from list lengths
(`:1415`, `:1418`, `:1451`), and 18 of its lines branch on a literal index (grep). The index
names the freeze directory (`:1620`; `src/test_fixtures/request_projection.zig:168-170`), so one
added fault renumbers every later scenario: under `evaluations/request-projection/` the three
source-preservation scenarios are 177–179 in freeze `93476e7`, 125–127 in `2b3dc8b`, 126–128 in
`b38628c` and 128–130 in `lever-after`. Two freezes taken either side of such a change don't
line up by path for §2 rule 10's byte comparison, and each scenario T3 asks for causes one
shift. **Class:** measurement. **Owner:** `runSpecificationWorkflows` and
`request_projection.zig`. **Next:** key a scenario and its freeze directory by a stable name.

**C41. The scripted driver is also the oracle, and its checks are gated on name literals (adds to
E8).** `src/test_fixtures/spec_generation_driver.zig` gates checks on operation IDs on nine lines
(`:181`, `:531-533`, `:551`, `:582`, `:603`, `:607`, `:628`), on the `extraction-schema` resource
(`:243`) and on slot names (`:191`). Renaming one, code and YAML together, turns the guard false
and the check stops running with no failure. A failed driver assertion is a panic: the file has
167 `catch unreachable` lines.

**C42. No offline run reaches publication through the production composition.** The scripted
scenarios run a hand copy of `Runtime.init`'s wiring (`workflow_tests.zig:1098`, `:1581`, `:3192`,
`:3262`, against `composition/root.zig:106`). Every offline run through `root.Runtime` or the
harness's `invoke.run` stops before publication (traced), so the harness's success path runs end
to end only live.

**C43. Scenarios patch shipped assets by exact text with no check that the patch applied.**
`workflow_tests.zig:1557` (`"group-size: 8"`) and `:1566` (`"/reason"` in
`extraction.composition.json`). If either text changes, the scenario runs unpatched and passes.
The guarded form is at `test/harness/integration/tests.zig:145-146`.

**C44. Scripted branches that no test selects (adds to T3).** 8 of the driver's 24 fault shapes
(`spec_generation_driver.zig:11`: seven of the nine `review_*` shapes and
`runaway_partial_assignment`) and 10 of the 11 support faults
(`spec_generation_responses.zig:11`; only `foreign_source_single` is set,
`workflow_tests.zig:1648`, `:1702`). Checked by grep.

**C45. Versions, layouts and lists repeated by hand.**

- `spec-e2e-report/v15` is spelled on 66 lines in 15 test files, because the schema field has no
  default (`test/harness/e2e/contracts.zig:140`). §2 rule 12 makes each closed-member change a
  version bump.
- The measures reader repeats the evidence layout as literals and returns no responses when the
  directory is missing (`test/harness/e2e/measures_cli.zig:184-203`, `:190`); its tests write
  their own layout (traced), so a moved evidence path would read as zero responses with tests
  passing.
- The 24 workflow assets are listed again in five places (`workflow_tests.zig:1560`,
  `test/packaging/smoke.zig:596-604`, three case files).
- Sequence fixtures pin call positions and retry limits as number literals
  (`summary_protocol_sequence.zig:71-72`; `global_protocol_sequence.zig:72-73`).

**C46. Architecture tests match raw text (adds to T4, which owns the per-file pin count).**
`expectAbsent` is a substring search over the raw file (`src/architecture_test.zig:1997-1999`),
so a comment containing "plan", "hard" or "reference" fails a test with no boundary change
(`:1269-1272`, `:1073-1075`, `:1680-1681`).

**C47. Registration and leftovers.**

- A `*_test.zig` runs only if `tests.zig`, `src/root.zig` or `src/runtime_tests.zig` imports it.
  Nothing checks reachability: `test-build-registration` checks test executables on a synthetic
  graph (traced).
- Each integration run writes about 1,000 files that nothing reads: 18 dump prefixes and an
  unconditional step trace for every scenario (`workflow_tests.zig:1727-1728`; traced).
  `build/test_run_inputs.zig:28-30` lists three `principle-citation-*` inputs that nothing names.
  Adds to T2.
- `src/test_fixtures/authoring_association_calibration.zig:16` reads a retained run of 11 October
  2026 that is no longer under `zig-out/e2e-spec/`, so part of a unit test returns `.unavailable`
  (`:297`) and is skipped.

**C48. Stages the development cases never exercise (adds to T3).** Neither is dead code and no
removal is proposed: live runs give them no coverage, so only offline tests do.

- Source review and its repairs run only when the source isn't ready (reconciliation not
  complete, or no eligible claim; `specification_provenance.zig:39-45`) or when
  `validation.sourcePreservationCheck` is true (`check_source_preservation_policy.zig:8`; default
  false, `config.zig:68`). That is 40 whole files and 3,078 lines (import closure, traced), 206
  YAML lines and three resources. None of the six runs made a review send.
- The passive-literal stage (five steps, `spec.workflow.yaml:281-295`) gave an empty list in all
  344 requests that carry one in the 38 runs.

### 10.7 Unconfirmed readings

**C49. Four readings to confirm or drop.** Each is read from the cited lines only and proposes no
change. **Next** for each: a test at its owner that shows the behaviour.

- A records batch bound to a group that holds an open question is offered record content that
  validation refuses, which would block the run (`specification_source_binding.zig:153`;
  `specification_provenance.zig:560`; `specification_repair.zig:80`). **Owner:**
  `specification_source_binding.zig`. **Class:** successful completion.
- The composed story copies fence, table and Setext lines when a claim cites them
  (`specification_story.zig:120`). **Owner:** `specification_story.zig`. **Class:** rendering
  artefact in the published story.
- The provider operation clock reads `.boot` (`provider_operation_clock.zig:13`) and the HTTP
  exchange sleeps on `.awake` (`model_http_exchange.zig:84`), so a request deadline is measured
  on two clocks. **Owner:** the provider adapters. **Class:** none.
- A retry population can differ after a source-omission merge
  (`reference_reconciliation_repair.zig:145-147`; `workflow_retry.zig:460`). **Owner:**
  `reference_reconciliation_repair.zig`. **Class:** successful completion.
