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
(ADR 0034, derived item 7). E1's live set (3 per case, 6 of 6 published and passed) is a
no-regression check, not the closing set.

**Reference** for quality phases (§2 rule 7): b4's second set (`2026-11-15T04-01-*`, build
`a349a72a…`, modified), the last kept state ([Z_SPEC01](Z_SPEC01.md) Q14 b4). Skills `af394020…`, `0b552067…`, `1d66d882…`, `3c74781e…` and `185b9bc6…` count
as one evaluator ([Z_SPEC01](Z_SPEC01.md) T7). Accuracy defect counts, content basis, as lost /
weakened / unsupported addition / contradiction:

| Case | Publications | Pass | Defects | Advisory score, mean (range) |
| --- | --- | --- | --- | --- |
| Hello-world | 3 of 3 | 3 of 3 | 0 / 0 / 1 / 0 (the greeting-then-timestamp order) | 92.9 (89.3–96.4) |
| Loan-renewal | 3 of 3 | 3 of 3 | 0 / 0 / 0 / 0 | 89.3 (85.7–92.9) |

Advisory scores are scored against the case rubrics (`evaluations/e2e/<run>/evaluation.json`);
scorer judgment moves one by about ±3.6, and keep decisions use the accuracy counts (§2 rule 6).

**Retained runs:** `zig-out/e2e-spec/` holds the HEAD set and twenty runs of 8 November 2026
(report v15, `build.source.modified` true): the `5b34dbc` "Repeated-statement text not
judged" set (`2026-11-08T00-39-26Z` to `00-45-47Z`), two `input_invalid` runs (`00-36-27Z`,
`00-37-49Z`), the entity and escaping set (`05-5*`) and six edge-case-lever runs on `071ce2b`
(`09-2*`). Earlier runs are removed; their evaluations and measures stay under `evaluations/`.
The current build decodes only `spec-e2e-report/v20` (`test/harness/e2e/contracts.zig:223`); earlier runs need their own build.

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
    naming no member). Their `1d66d882…` adjudications stand; their `3c74781e…` re-scores
    ([Z_SPEC01](Z_SPEC01.md) T7) stay unapplied. The twelve `05-5*` and `09-2*` runs are adjudicated under
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
change except the §22.6 correction location, outside E5 since DE5 7, and E7), **T** tests, **H** human decisions, **R**
research, **C** code-review findings (§10; none scheduled). "Gap" means between measurement sets.

**Next:** items 1 to 8 are implemented, kept or closed (records in [Z_SPEC01](Z_SPEC01.md)): Q14 b4
(item 4) was kept 15 November 2026, and item 8 (ADR 0038's edge-case outcome limit) needed no change,
since b4 gives each criterion one claim and neither set printed a success Then for a refusal edge case.

**Set order, decided 14 November 2026** (user: "the above recommendations are approved"). Each
change set is measured on its own committed build (§2.1, §2.3), against the previous item's
kept state (§2 rule 7); b4's second set is the reference for the next one ([Z_SPEC01](Z_SPEC01.md)
Q14 b4):
1. **Q17,** then **Q7 D7.5,** then **Q4** (the table below): screens, then a set each.
2. **The closing set** (§1).

The order is approved, not a blanket go-ahead: each screen batch and live set still needs its
own approval when it is ready (AGENTS.md; the project settings prompt for every live step).

**Output track** (rank order of the table; each item's screens and set follow the set order
above, inside the decided constraints: D17.1 puts Q17 after D12.2):

| Rank | Item | Defect class reduced | Effort | Validation | Decided |
| --- | --- | --- | --- | --- | --- |
| 1 | **Q17** principles as records-call context | none scored; guards only unless the rubrics gain a principle criterion | M | Records screen, then a set | D17.1 |
| 2 | **Q7 D7.5** a plain string only where a field offers no insertion | rendering artefact C (joined fragments): none published since ADR 0047 composes the story; conformance only (§4 Q7) | S | Screen, then a set | D7.5 yes, a conformance fix |
| 3 | **Q4** retry, with D4.1's extension | engine vocabulary (none published; AGENTS.md compliance) | S | Screens of each changed call kind, then a set | D4.1 extension yes |
| 4 | **Q21** behaviour claims need statements | lost source requirement: a behaviour claim no statement names, passed through a whole-group selection (none since ADR 0047) | M–L, by D21.1 | Fixtures at the owner, screens of each changed call kind, then a set | D21.1 deferred |

**Robustness track** (run completion and budget; no scored defect): the §22.6 correction
location, outside E5 since DE5 7. Since D13.1 the measured runs show 0 runaways and 0 re-sends; the highest used 67,448
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

**Engine track, in gaps:** E1's `DataKey` removal (§5 E1); E2 stops
at its three preparation stages (decided 14 November 2026); E3's feature logging waits on E6; E6
in any gap; the evaluator partial-body gap (§5 E5) in any gap; E7 last. E0 is on hold. E1's
`DataKey` removal and T8 land only under §2.12. **Tests:** T2, T3 and T8 in any gap; T4 with
E1–E4. **Adjudication:** H1 (the evaluate-e2e skill) for every set.
**Human:** H2 when required source review is labelled or review returns; H3 when the user
reviews the panels; H4 before any formal baseline freeze; H5 at the user's choice. **Closing
set:** repeated runs of both cases on one committed, unmodified build (ADR 0034:55-56) unless
the user amends ADR 0034; every counted published run adjudicated (H1). The HEAD set (3 per
case) is enough for now (user); the gate is re-run on the post-E1–E4 build (§1, decided 14
November 2026; ADR 0034:93-95).

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
  - **Entity applicability and naming: recorded as a model limitation** (user, 15 November 2026:
    "apply recommendation option A"): the entities call picks `required` and an entity for a feature
    with no business data in about half of hello-world runs, and sometimes names the feature itself.
    No b4 call is involved, the cost is at most one point, and no prompt change targets it
    ([Z_SPEC01](Z_SPEC01.md) Q22).
  - **Edge-case outcomes:** ADR 0038 Decision 7, kept ([Z_SPEC01](Z_SPEC01.md) Next 8). **Not
    accepted** (user, 7 November 2026: "that is a poor idea and I will not accept it"): the
    engine filling `then` and `expected_outcome` from the record's cited source lines. ADR 0038
    Decision 7 records that this doesn't cover copying a criterion's Then.
- **Unsupported additions in AC wording.** AC-001's recording of the renewal ("records the loan
  as renewed", three of the HEAD set's four additions) is ruled a minor addition (§7 H1) and
  has no structural lever: the `given` purpose forbids invented prerequisites
  (`packet-guidance.json:21`), the `when` purpose (`:22`) doesn't. Q12's leftover restatement
  (`generation.prompt.md:2`) and the three no-invention texts (`packet-guidance.json:21`,
  `records.prompt.md:8`, `generation.context.json:4`) stay as they are after the one-owner
  hygiene change's revert. Report the remaining AC elaboration as a model limitation (AGENTS.md)
  and let H1 judge it.
- **Repair requests without step guidance:** six repair sites take their task only from the
  three-line `repair.prompt.md` (`spec.workflow.yaml` steps `text-repair` in `extract-references`,
  the extraction repair in `validate-extraction`, `request` in `repair-reconciliation-candidate`,
  `repair` in `generate-unit`, `request` in `repair-source-extraction` and `request` in
  `repair-source-candidate`), and the two reconciliation repairs among them
  (`repair-reconciliation-candidate` and `repair-source-candidate`) bind no context.
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

**D2.3** implemented and kept 1 November 2026; record in [Z_SPEC01](Z_SPEC01.md) Q2b D2.3. Open
follow-ups:

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
12-model-boundary.md:369-370 and ADR 0016:159-160 say SPEC01 Q4 removes the restated rules. No
published spec contains engine vocabulary, so this is AGENTS.md compliance, not an output
target.

**D4.1's extension** (decided 3 November 2026; D4.1's own correction left with Q14 b3): the rule covers
native rule and correction texts too, and a sentence that says what a field, claim or response
contains stays even when the engine enforces or transforms it.

**Scope still model-visible:** `support.prompt.md:28-29` (bound for pre-generation source
review); `packet-guidance.json:61`; `reconciliation-dispositions.prompt.md:2-4`;
`extraction-classifications.prompt.md:2-5`; `records.prompt.md:4-5`;
`support-loss.prompt.md:22`; the "native code …" texts in
`src/domain/reference_reconciliation_diagnostic.zig` (lines 101, 106, 119, 122, 124, 132, 134),
which reach requests through `descriptionFor` (`reference_model_input.zig:297`);
`src/domain/typed_text.zig:156` (no projected request carries it, but
`specification_repair.zig:81` can send it). Reword engine vocabulary in place; remove a
restated rule only when the schema or its correction states all of it; keep task semantics the
engine doesn't check (both `citations` sentences and the `claim_ids` definition).
`records.prompt.md:9-11` states an "at most one record" rule (ADR 0038 Decision 5); the engine
checks it only for non-requirement statements (ADR 0038:155-158), and the sentence is kept as
written on purpose (:163-164). It stays as the rule's only carrier on a first attempt, since the
provider schema can't express it.

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
  the projection gives an exact copy its own code span (`specification_projection.zig:185-189`)
  unless D7.4's exception applies (`delimitedByText`, `:201-207`), which excludes a value
  ending in terminal punctuation and so every development-case value. Where the span stays,
  the doubling is the engine's. Since ADR 0047, A remains in model-written FR and AC fields.
- **B. Plain value in an entity meaning:** ended 8 November 2026, when the entity lost its
  meaning (ADR 0038 Decision 6).
- **C. Fragments joined without a separator:** the schema keeps the fragments option when no
  reference is offered, and fragments join with no separator
  (`model_candidate_json.zig:251-253`). D7.5 owns it.

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

### Q13. Inline source lines

D13.1 (post-generation reviews removed) and the inline source lines are in
[Z_SPEC01](Z_SPEC01.md). **D13.4** (decided 1 November 2026): principles are context and
constraints only, never origins, and never modified (Q17). Nothing checks what a shown source
line means beyond the advisory evaluate-e2e link check.

- **Clarification question lines disagree.** `clarification_preparation.zig:32` prints
  `lines {start}–{end.line}`, so a citation of line 5 reads "lines 5–6" there and "line 5" in
  `spec.md`. Fix: use `source_coordinates.lines`. It changes clarification form bytes; no
  development case reaches a clarification today.
- **D13.7 (decided 15 November 2026, user: "yes"; applies when Plan's editable reparse is
  built, which ADR 0034 gates):** what a hand-edited or stale source line does at the plan
  boundary. 23-rendering.md §23.1 (:148-153) says readback compares it with the derived line,
  but not what a mismatch does. **Decision:** regenerate it from the re-attributed provenance,
  never block on it, since the line is a display and a user can't change what a record cites
  by editing it. The sentence joins §23.1 with the reparse code and its tests.
  **Limits:** a citation is only as true as its link (loan-renewal AC-001 cited refusal lines
  it doesn't test, `2026-11-07T01-19-36Z-728d…`), so it pairs with Q14 b3; entities cite whole
  groups (R1); semantic checking rests on adjudication (H1).

### Q14. Scenarios bound to their claims

**Kept 15 November 2026** (record: [Z_SPEC01](Z_SPEC01.md) Q14 b4). Open parts only:

- **Watch, from the second set:** the one-renewal criterion (claim 4) is a bare rule or changes modality in
  3 of 3 loan-renewal runs; AC-001 repeats other requirements' results in 2 of 3 (its Source then cites
  two of three claims), a **Decision** on ADR 0038 (an exact copy in a criterion must belong to the slot's
  own claims) only if it repeats in the next set; a Given that already holds the event its When names in
  2 of 3 hello-world runs.
- **Restated edge cases** from the records call recur (loan-renewal EC-001 and EC-002 repeat AC-005) and
  cost `organization` only; they wait for the 13 November edge-case amendment (ADR 0038 Decision 7,
  unbuilt), then re-measure.
- **Not shown by the sets** (one group each): a heading or lead-in claim that a behaviour statement names
  gets a full scenario; an edge case naming only a scope-only claim blocks late at the link step
  (`edge_case_without_criterion`); equal criteria across groups with generic wording block as
  `competing_records`; one group with many claims makes one long answer.
- **Entities call** invents or misnames an entity: not a b4 call, recorded as a model limitation (§3).

### Q17. Principles as Spec context

**Decided 1 November 2026** (user): "the workflow must never modify principles - NEVER" and
principles "should be used for context when executing the spec workflow".

- **Never modified:** holds today. Principles are read through a read-only source adapter
  (`src/adapters/filesystem/principle_source.zig`), the only principle capability is
  `principle_read` (`workflow_capability.zig:18`), and path validation rejects every project
  operation against the semantic-principles root (11-path-validation.md:20). Every future step
  (Plan, Implement, init, repair) keeps it. ADR 0015 records it (0015:36); design.md §3.3
  doesn't (adding it is a design edit awaiting approval).
- **D17.1 decided 1 November 2026:** the records call only (it writes the FR, AC, BR and other
  statement records principles constrain), with the principle files as the registry captures
  them, unnumbered (items never cite principles). The case principles are 28,067 (hello-world)
  and 29,399 (loan-renewal) bytes, about 7k tokens per records request (one per group, and
  again on a correction or re-send). A measurement set, with
  unsupported addition and invented entity as watch items (§2 rule 6; decided 3 November
  2026, user: "Yes, watch items"). D12.2 is kept.
- **Built offline, 15 November 2026; awaits its screen and set.** The records request, and no
  other (not brief, entities, scenarios or an atomic repair), carries each principle file's
  text as `principles` (`specification_principles.zig`; `build-specification-model-input`
  requires `principle_registry`), and the records prompt says how to read them. A project with
  no principle files gets no key. The freeze over 1,900 scripted requests: 1,888 identical, 12
  records requests in 5 scenarios gain the key, nothing else changes. Amended: ADR 0015, ADR
  0023, 17-specify.md, 09-configuration.md (:337, :354), 13-05 and F0100.
- **Target and risk:** no current rubric criterion scores principle consistency, so a set can
  show only guards (unsupported addition and invented entity from principle text,
  publication) unless the case rubrics gain a criterion. Principle text is no source: a record
  that copies a principle's literal gets no passive or exact authorisation. The case
  principles are technology, security and architecture standards, so the records prompt calls
  them "principles, given as context" and says they add no requirement; stack or technology
  content in a record is an unsupported addition (watch item).
- **Open (Plan gate, ADR 0034):** whether a Spec generated under an older principle registry
  is stale at Plan's gate. A changed registry already invalidates plan and task approvals
  (09-configuration.md:367); Spec regenerates every run.
- **Sequence (recommended, not decided):** a records screen first: the loan-renewal rubric's
  proportionate-scope criterion penalises principle-derived prescriptions, so its guards need a
  settled reference.

### Q21. Behaviour claims need statements

**Defect:** lost source requirement: a behaviour claim that no statement or scenario names
passes coverage, because the brief fields, entity basis and composed story select whole
groups and a claim maps through any field holding it (`specification_coverage.zig:52-61`,
`:75`). In a one-group feature, as both development cases are, ADR 0038 Decision 2's scenario
rule never reaches an unnamed claim (ADR 0038 Consequences, Limits; pinned at
`specification_generation_test.zig:9231-9234`). No failure since ADR 0047 is of this kind, so a
set may show only "benefit not demonstrated".

**Proposed 8 November 2026** (not decided): a narrative selection gives traceability only;
every obligation-bearing claim must be named by a behaviour statement (FR, BR, UO or PB),
whose claims then need a scenario. A coverage gap blocks with no repair today
(`specification_coverage_repair.zig:26-30`), so it needs a correction at records admission,
or silent passes become blocked runs. Owner: `Coverage` (`model_result_schema.zig:56`) and
`specification_coverage.zig`; amends ADR 0038 Decision 2 and its Limits, 17-specify.md
§17.5 and F0100.

**D21.1 (Decision):** which claims bear obligations: (a) every `business` claim, which
includes feature identity and purpose (`extraction.context.json:6`); (b) a new obligation
category in extraction (`:5-13`), changing extraction requests; (c) a bounded model
decomposition into source-span elements, the only option that separates a compound claim such
as loan-renewal's four-part refusal item (`test/e2e/wf-002-loan-renewal/stories.md:9`, ADR
0038 Consequences, Limits), at the cost of a model step whose losses nothing native detects. Treating
shared source evidence as no redundancy is not adopted: it would reverse ADR 0038 Decision 5
(user, 2 November 2026).

**D21.1 deferred** (8 November 2026; user: "recommendations accepted for 1 to 6"; confirmed 15 November 2026): no failure of
this kind has occurred since ADR 0047, so a set could show only "benefit not demonstrated", and
each option risks accuracy: (a) false blocks on identity claims, (b) a change to every
extraction request, (c) losses nothing native detects. If it resumes, take (b).

**Next:** D21.1 (deferred); fixtures at the owner (an unnamed claim, or one named only by an
assumption, non-goal or scenario, rejects), then screens and a set (§2 rules 4 and 6). §10 C30
records the blocking route's constant-result machinery.

## 5. Engine track (E)

Each item: `/preflight`, offline tests, the §2.10 proof, `zig build verify`, one live run
per case (DE2–DE4, in [Z_SPEC01](Z_SPEC01.md), asked whether offline evidence replaces it),
landing between sets and under §2.12.

### E0. Failed and blocked runs publish validated content (B10, ADR 0041)

On hold since 30 October 2026 (ADR 0041:3-4). Nothing under `src/` names `failure-output`,
`spec_incomplete` or `run.incomplete_published`. To resume: implement ADR 0041 Decisions 1–8,
taking `specification-state/v27` (ADR 0041 names v27 since 14 November 2026); align the measures
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

### E1. Engine-owned model request (A1, ADR 0030 slice 4)

Implemented and kept 13 November 2026; record in [Z_SPEC01](Z_SPEC01.md) E1. Open:

- **`DataKey` enum:** removing the engine-internal request keys from it is a follow-up change (DE1b,
  [Z_SPEC01](Z_SPEC01.md) E1); it lands under §2.12.
- **Retention:** recorded retention keeps every call's raw exchange for the run, and its growth is
  unmeasured.

### E2. Stage actions (A2, ADR 0031)

Implemented 12 November 2026 (the three preparation stages; E2b and E2c kept the same day); record in
[Z_SPEC01](Z_SPEC01.md) E2, E2b and E2c. Open: converting any other subgraph is a separate decision, and
**decided 14 November 2026** (user: "recommendation accepted") none converts before the closing set
(§1). The remaining chains are short or excluded by ADR 0031: publication, clarification output and
the authority gate write, branch or issue a gate, and the assemble subgraph has a repair step. The
only eligible candidates, read from the YAML with no freeze taken, are two pure five-step tails
(before publish, and in clarification output). A conversion changes the build before the closing set.
Revisit when Plan work begins (ADR 0034).

### E3. Engine routines (A3, ADR 0032)

Startup and provider bootstrap implemented 12 November 2026 and kept 14 November 2026; record in
[Z_SPEC01](Z_SPEC01.md) E3. Open: feature logging, which waits on its preconditions (ADR
0032:152-179): no test covers cancellation under a log lock, and no test counts the emergency lines.
The policy-transition coordinator's authority is decided on both sides (prior-run finalization's, ADR
0026; the same-run transition's, ADR 0032, decided 14 November 2026, §8).

### E5. Rejections say why (A4)

Implemented and kept 14 November 2026; record in [Z_SPEC01](Z_SPEC01.md) E5, with DE5 (decided 14
November 2026, user: "yes", to the E5 preflight's ten recommendations). Open:

- **Evaluator partial bodies disappear** (a separate item; harness only; matters for H3): carry the
  transport's `ResponseBody` bytes and completeness through `test/harness/provider.zig:27-34`,
  `bedrock.zig` (`:67-70`), `http.zig` (`:99-101`) and `evaluation_trace.zig`, with redaction and
  fault tests.
- **Correction location** (dropped from E5, DE5 7: it changes model-facing correction bytes, has no
  scored defect and has not occurred since D13.1; it needs its own phase if it ever does): a
  SyntaxError correction tells the model the malformed opening (all four in the 18 runs of 31 October
  said `byte_offset 4`, key `"{"`), not the unterminated string: `model_envelope.zig:68` drops the
  re-parse diagnostic and `:75` reports the original, as §22.6 requires (22-repair.md:526-527). Fixing
  it amends §22.6 and changes correction requests.
- **Workflow-definition rejection detail** (a separate item, DE5 8): F0005 §9.
- **Further payload-free failures,** by area: §10 C4.
- **First cause in the log and CLI:** the feature log's terminal event keeps the terminal code only,
  so a production run's first cause is visible in the harness report, step event and trace and not in
  the log or the CLI; showing it there needs an event field and an F0002 change.

### E6. Logging and visibility gaps

- **Cancellation** during segment reads and under the log lock ends the run `blocked`, not
  `cancelled` (`operation_error.zig:16-24`; `feature_log_recovery.zig:29-61`;
  `feature_log_historical_stream.zig:95-97`). **Decided yes** (8 November 2026; user:
  "recommendations accepted for 1 to 6"): it ends `cancelled`, as its own phase after the
  entity and escaping set (user, 8 November 2026: "after"). Not implemented: it adds
  `Cancelled` to the `FeatureLogSink` error set and a `cancelled` log outcome, amending ADR
  0032:319-320's "Not decided" bullet, with no new `LOG_*` code. Measured scope: about 35
  `SinkFailure` mapping sites in the log adapters (`feature_log_segment_store.zig` 21,
  `feature_log_retention_store.zig` 6, `feature_log_lock.zig` 5, `feature_log_recovery.zig` 2,
  `feature_log_historical_stream.zig` 1) and about 9 consumers of the log outcome, not a small
  change; it affects no model request. No production code supplies a cancellation status today
  (§10 C28).
- **Prior-run crash finalization** (§14.10). **Authority decided 14 November 2026** (user:
  "recommendation accepted"): segment-header identity alone, with no persisted bootstrap
  lineage (ADR 0026 amended; §14.10 and ADR 0032 updated). Building it is deferred: a crashed
  run's logs stay whole and unpruned, and only damaged prior logs block later runs. Before
  building it, check that header identity suffices where the runner selects the prompt stream
  from the policy (`feature_log_runner.zig:87`), and decide its order against the current
  activation. The same-run policy transition's authority is decided separately (§8 "Mid-run logging
  transition", ADR 0032); E3's feature-logging conversion waits on the cancellation change above and
  on ADR 0032's other preconditions (§5 E3).
- **Redaction policy ID: dropped 14 November 2026** (user: "recommendation accepted").
  `redaction/default-v1` is gone from 26-security.md and F0002 §6.4 (the row is :548). No code
  carried it, and a record field would invalidate every `feature-log/v2` segment. F0002's
  "classified fragments retain their existing detector contract" clause still has no code
  counterpart.
- **Producerless rejection** (fixed, [Z_SPEC01](Z_SPEC01.md)). **Decided no** (user, 14 November
  2026): a classification entry missing at first generation does not name its chunk's
  classification producer; the validator's `producerless` rule and `candidate` attribution stand,
  and contract 27 (27-observability.md:45-50) now names `producerless` beside coverage as an
  assembled-candidate example (user, 14 November 2026: "approved"). Still open:
  `observation.capture`'s candidate arm (`test/harness/e2e/observation.zig:132-133`) has no direct
  test.

### E7. Clarification answer recovery (R2, ADR 0025)

Not started; no §13 authentication chain exists in `src/`. Fresh answers can't complete
recovery: refresh rejects new submissions (`clarification_refresh.zig:65`); provenance
rejects nonempty response-ID sets (`specification_provenance.zig:88`,
`specification_support_evidence.zig:171`); form validation returns one
`InvalidClarificationInput` (`validateClarificationForms` in `src/actions/specify/prepare_inputs.zig`);
resolved needs are empty (`src/actions/clarification/build_resolved_clarification_needs.zig`);
passive literal origins are source-only (`passive_literals.zig:16`), so answer text can't get
ADR 0025's response-owned origin (0025:70-71); generation doesn't consume answers (it binds
empty response-ID sets, `specification_source_binding.zig:136`, `:188`). Complete the
[§17.4 lifecycle](../design/contracts/17-specify.md#174-specification-clarification-behavior)
under ADR 0025. Live validation needs a user-chosen clarification-expected case run twice with
forms answered between runs; neither the case nor a two-run harness flow exists. Last, after
E1–E4. §10 C8 adds record-lifecycle gaps.

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
- The no-feature-claim text-repair route (`authorize-text-repair` to `text-repair` in `extract-references`) has unit coverage only;
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
- Scripted branches no scenario selects, and stages the development cases rarely exercise: §10
  C44 and C48.

### T4. Architecture rules and replay (A5)

When E1–E4 remove files pinned by architecture tests, write the replacements as import-graph
and contract-shape rules (ADR 0030:464-468, 0031:337-353, 0032:298-310, 0033:338-341), not
per-file pins (about 70 of the 79 tests pin files). Prefer replaying retained captures over
extending `spec_generation_responses.zig`. §10 C46 adds the raw-text matching.

### T5. Brittleness counts

Definitions and decisions: [Z_SPEC01](Z_SPEC01.md). The `code-heuristics` report names
them by `report.json` member: T5.1 `tests_copying_model_text`, T5.2 `schema_name_branches`,
T5.3 `repeated_instructions`, T5.5 `model_or_case_branches`, T5.6 `model_text_outside_owner`;
T5.4 isn't in it. Each change set that a phase reports on
retakes them on its committed build: `zig build code-heuristics -- --freeze <dir>` with the
freeze §2.10 takes on that build, and T5.4 by hand from `spec.workflow.yaml` (a `slot: repair`
step whose prompt no non-repair step binds). Last taken 14 November 2026 on the working tree after
E5 (a modified build) with freeze `evaluations/request-projection/e5-final`; its counts, beside the
ones taken 2 November 2026 on the `b38628c` tree with freeze `evaluations/request-projection/b38628c`
(130 scenarios, 1,714 calls), are in [Z_SPEC01](Z_SPEC01.md) E5. No retake lies between the two, so the
difference is the net of the kept ADR 0047 and D12.3 change set (`f6ef0f6`, `39fd9ff`), E1 to E5 and E8,
not each change's share. **Due:** with the next change set that a phase reports on. T5.4 is still 6
(the six sites that bind `repair-prompt`, listed under "Repair requests without step guidance").

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

The 3 November 2026 decisions that the evaluator's rubric scores decide acceptance and that a
run's first adjudication under a skill version counts are in [Z_SPEC01](Z_SPEC01.md) H1.

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
experiment-wide stops are 1,000 sends or 2,000,000 tokens
([README](../test/calibration/semantic-simplicity/README.md):189-199), about 13.9 sends and
27.8k tokens for each of the 72 Phase 2 workloads if the baseline is the only consumer. A published
run uses about 9 sends and 13k to 17k tokens (the HEAD set), but a run that reaches source review
uses more: `2026-11-14T06-58-13Z-7dea…` (loan-renewal, `invalid`) used 22 sends and 59,703 tokens.
A freeze needs a feasible projection from the worst listed run
(`test/harness/baseline/feasibility.zig`), and 22 × 72 is 1,584 sends, so today's numbers would not
be admitted; the 15 October feasibility report predates D13.1 and its reader. **Decided 15 November
2026:** not yet; leave H4 open until the formal baseline is asked for, since the closing set supplies
current cost evidence. The choice then is narrowing the qualified scope or dropping the baseline; changing the stops
or trimming calls for cost alone is excluded (AGENTS.md; ADR 0011 for any size ceiling).

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

- **No-invention routing** was removed from the design text (record in [Z_SPEC01](Z_SPEC01.md)
  "Design–code conflicts resolved"). F0006:855 and :1017 still name it, and the Plan and Tasks wording
  that names semantic or model-assisted review (18-plan.md:289 and :307, 19-tasks.md:188,
  14-orchestration.md §14.14) stays: ADR 0034:32-36 bars Plan- and Tasks-specific design edits until
  the gate passes.
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
- **Upstream rework as a form (decided 15 November 2026):** `required_authority_clarifications.build`
  turns an `upstream_rework_required` entry into a form (`:15`), where §14.14 and invariant 22 send an
  earlier-owner gap to §24.5's rework route. The gate blocks such a set before `build` runs
  (`required_authority.zig:276`), so only `required_authority_test.zig:517-561` exercises the branch,
  and Spec detects only at `spec` (`specification_authority.zig:58`). The design wins: delete that
  branch and move its test to `.spec` detection, in a gap before the closing set; no design edit, so
  ADR 0034 is untouched. No test covers two same-stage `clarification_required` gaps becoming two
  forms (§14.14).
- **Renderer version (decided 15 November 2026):** §23.1's version rules stay the target for stages
  that get approvals (23-rendering.md:49 cites this entry); build or delete nothing now.
- **Mid-run logging transition:** decided (ADR 0032, §14.10). Open only when a route needs the
  switch: no production code switches policy mid-run (`Lifecycle.transition` has test callers only,
  §10 C28), no text says which event would produce a changed logging candidate, and "adopting
  route" (09-configuration.md:400) is undefined.
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
- **Status:** nothing here is approved or scheduled, and each item needs its phase approval
  (§2). An item that names no defect class targets no published-output defect: it reports a fact
  or asks a Decision, and proposes no change (AGENTS.md: cost is reported, never the reason for
  a change). An item that changes a model request is a Q phase with a named class. **D** marks a
  cost that an accepted ADR or a contract requires, so removing it is a **Decision**.

### 10.1 Failures first

**C2. A publication interrupted between a form and its state blocks every rerun** (class: successful
completion). Forms are written before the state (`clarification_output.zig:17-29`) and truncated in place
(`file_access.zig:40-42`), and every rerun re-stamps each open form with a new state revision
(`clarification_refresh.zig:79-82`), so a failure between a form write and the state write fails the next
`prepare-inputs` (`src/actions/specify/prepare_inputs.zig:180-204`), against ADR 0009:144-146 ("a fresh
rerun replaces the complete output set without recovery"). Forms are also user input, and the writer never
overwrites a closed one (`workflow_output.zig:79`). Reach: only when a form is written, which no
development case does; not executed, and no test reruns after a failure (the failpoint test fails before
the file is touched). **Decision** on the remedy, since ADR 0009:122-123 rules out rollback and recovery
stores. **Decided 15 November 2026:** not yet: first an offline scenario that fails the state write and
reruns (the regression test any remedy needs; no engine change). The likely remedy then is a typed
exception that stops failing on leftover forms holding no user submission, with closed forms still
stopping; it comes back to the user with the scenario's result.

**C3. A console or flush failure after a successful append leaves the log unclosable.**
`feature_log_runner.zig:222-234` appends the row, writes it to the console
(`catch return error.ConsoleFailure`, `:232`) and only then advances `event_state` (`:233-234`);
the append writes before it syncs (`feature_log_segment_store.zig:99-100`). After either failure
the row is on disk and the state isn't advanced, and every later append and the close require
the file size to equal that stale state (`:96`, `:125-126`). The prompt stream has the same shape
(`feature_log_runner.zig:328-341`). The segment keeps no trailer, which ADR 0026 ("Crashed runs
are kept whole") treats as a crashed run. Not executed; the test checks the failing call only
(`src/feature_log_runtime_test.zig:409-438`). **Class:** successful completion. **Owner:**
`feature_log_runner.zig` (`persistEvent`, `persistPrompt`). **Next:** a runner test that appends
again after each failure.

**C4. Most failures report one payload-free name (adds to E5).**

- **Provider and authorization:** the provider result holds a typed cause and a transport
  diagnostic (`llm_provider_operation.zig:170-180`, `:193-205`), but nothing logs or reports
  them: outside `domain/` and `adapters/` the cause is only built or compared
  (`workflow_provider_authorization.zig:80-81`; grep). `model.completed` has no cause field and
  is emitted with a null reason (`model_completed` in `log_event_registry.zig`;
  `logModelCompletion` in `workflow_pipeline_runner.zig`). The CLI prints the outcome tag, then
  an operation error name or a candidate diagnostic if the run recorded one
  (`src/main.zig:43-45`). A missing key and a malformed one are the same case
  (`provider_api_key.zig:35-37`), and the response decode diagnostic is dropped
  (`provider_response_assembly.zig:127`). So a missing key, HTTP 401, 403 or 429 and a DNS or TLS
  failure should all read `failed`. Not executed.
- **Workflow definition:** every schema, compile and graph rejection is one of two codes with
  no step, key or rule (`workflow_graph_compilation.zig`, `workflow_graph_validation.zig` and
  `workflow_definition_schema.zig` return one `invalid()` error each; the startup routine maps
  the failing step to its code in `startup_routine.zig` `code`). A key missed from a
  hand-written invalidation list (`source_omission.zig:343`, `:345`; `required_authority.zig:124`)
  fails the same way, because the data-flow check rejects producing a key that is still
  available (`workflow_data_flow.zig:87-95`).
- **Result schemas and compositions:** 86 and 48 `invalid()` lines, one error each
  (`model_result_schema.zig`, `json_composition.zig`).
- **Reference ingestion:** ten typed reasons (`reference_ingestion.zig:42-53`) are discarded;
  each becomes `InvalidReferenceAccounting` (`validateAccounting` in
  `prepare_reference_evidence.zig`), against ADR 0036:198-200 ("fails at ingestion with a typed
  reason", said of malformed text). Any file that isn't `.md` or `.markdown` is one of them
  (`markdown_reference.zig:17`). The stage names the failing step in the event
  (`validate_accounting`), not the reason.
- **Toolchain:** every toolchain failure is `error.InvalidToolchain`; the stage names the
  failing step in the event (`Step` in `prepare_toolchain.zig`), not the rule that failed.

**C6. A descriptor that passes registry and graph validation can fail at run time.**
`validDescriptor` checks that the keys are declared and that the kind and repair role fit
(`workflow_outcome_association.zig:585-602`). At run time the binding looks the result key up in
hard-coded tables that end `else => return error.InvalidOutcomeAssociation`
(`authorizationBlocked` in `workflow_outcome_binding.zig`; also the `clarification_route` branch
and `diagnosticAdmission`). Giving another authorizer a `blocked` outcome compiles, validates and
then rejects the first run that takes it. Not executed. **Owner:** `workflow_outcome_binding.zig`.

**C7. A stray entry in `clarify/` fails the run, even after every model call**
(`adapters/filesystem/feature_input_source.zig:83-85`; the publish step repeats the capture; class:
successful completion). **Decided 15 November 2026:** the same exemption the user gave log folders (ADR
0026): a regular file not named like a form is never opened or changed; directories, symlinks,
form-shaped names and orphan or missing registered forms still fail. Its own phase: the adapter, the
`.unknown` test case, and 23-rendering.md:263-264, 24-workflow-state.md:123 and F0100:200-201.

**C8. Clarification records (adds to E7).**

- Nothing closes a record. The only status writer sets `open` (`clarification_refresh.zig:124`;
  no production code assigns a resolved or cancelled status, by grep), prior subjects are
  retained (`:61-62`), and any open record gives `needs_user` (`:54-59`). A rerun with an open
  record still makes every model call, because open records are first checked at
  `check-output-clarifications` (in `publish-specification`), after generation.
- Authority subjects are keyed by per-run ordinals and the contract version
  (`required_authority_clarifications.zig:77-88`), which `source_preservation.zig:26` says don't
  survive a rebuild. 24-workflow-state.md:115-117 says regenerated IDs don't define a new
  clarification.

### 10.2 Optimisation

**C9. Input tokens are most of a run (a fact; no item).** Input tokens are 92.5% of a
hello-world run (11,987) and 89.7% of a loan-renewal run (14,816).

**C10. The conflicts request is sent when only one answer is admissible** (class: successful completion
in principle: with no conflict group the call can only return `{"conflicts":[]}` or fail; no failure is
observed, so no benefit is demonstrated). `check-conflicts` tests only the phase
(`reference_reconciliation_stage.zig:106`), so with no group the choice set is empty (`:79-81`) and the
schema owner narrows the array to `maxItems: 0`; five of the six runs of 14 November sent such a request,
and the sixth (loan-renewal) had a conflict group, so its call was a real choice. **D:** ADR
0022:108-109 ("Empty eligible catalogues admit only an empty authored collection"); `:136-138` already
constructs forced token classifications natively with no call. **Decision:** whether ADR 0022's native
rule extends to the conflicts stage. **Decided 15 November 2026:** yes, conflicts only: a forced answer
is computable structure and the call adds failure exposure and no information; tokens are reported,
never the reason. It amends ADR 0022:64-66 and :108-109 and changes the step trace, the freeze and one
scripted fault test; implementation is its own phase.

**C11. The leaf summary adds a paraphrase that only the next reconciliation requests read (adds to
R1).** For one source of up to eight claims the leaf summary is always requested: native reuse
needs exactly one child (`reference_reconciliation_validation.zig:491`). Its prose is sent to the
dispositions and signals requests (`reference_model_input.zig:159-165`); that it is neither
persisted nor rendered is traced. Those requests carry it without the "earlier summaries are
supporting context" purpose, which is attached to summary requests only
(`reference_model_input.zig:89`; `packet-guidance.json:56`).

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
design text requires or forbids reuse (grep of `design/`). How much of a call's latency it
accounts for isn't measured (C17).

**C14. Log volume and per-record work.**

- At `debug` the prompt log is about 750 KB a run (754 KB in a 14 November hello-world run), most
  of it the request-source snapshot: the workflow YAML and bound resources, rewritten for each of
  the nine requests (`captureDocument` in `request_source_capture.zig`). **D:** ADR 0019:96-102.
- Each record reopens the lock file and the segment (`feature_log_orchestrator.zig:17-29`;
  `feature_log_segment_store.zig:88-100`): about nine system calls (traced) for each of the
  roughly 660 records of a hello-world run. The lock per record is **D** (F0002:250-251;
  26-security.md:216-219); reopening the files is not.
- Activation re-reads every prior segment of the feature and walks every earlier run directory
  (`adapters/filesystem/feature_log_history.zig:46-92`). **D:** ADR 0026 (Consequences), which
  records that the number of retained prior runs is unbounded. The harness never meets it: each
  run has a fresh project.

**C15. Repeated native work (no time to recover; one rule kept at many sites).**

- Every executed step revalidates the whole operation registry, a pairwise ID loop over every
  registered operation included (`authorityMatches` in `workflow_pipeline_runner.zig`, called by
  `executeStep`; `Registry.validate` in `ports/workflow_operation_registry.zig`, "Rebuild on
  every call").
- The clean path re-runs validators in all six runs: `validate-dispositions` three times and
  `validate-signals` twice, because each release returns to the first validator
  (the `ok` routes of `release-signals` and `release-conflicts` in `validate-reconciliation`);
  `check-summary-reuse` and `validate-summary` twice, once for the requested leaf summary and
  once for the parent partition that reuses it.
- One request packet is built through 10 to 15 full copies (traced), each copying every source's
  bytes (`cloneWith` and `copyOriginalSources` in `model_input_packet.zig`).
- The codec parses a response, re-serialises it and parses it again (`decode` in
  `model_candidate_json.zig`).
- Publication renders `spec.md` five times and parses it twice (`render_specification.zig:13`;
  `validate_specification_rendering.zig:14-17`; `prepare_specification_output.zig:24-25`).
  **D:** 13-05 (`ValidateSpecificationRenderingAction`, `PrepareSpecificationOutputAction`).
- `token_classification_validation.zig` builds its dependency snapshot with
  `atomic_repair.snapshot`, which hashes every source byte, into a value whose only use is a
  copy (`build_preserved_token_claims.zig:38`; traced).
- Startup repeats two compiled-graph checks: outcome flow runs in the compiler and in graph
  validation (`workflow_graph_compilation.zig:85`, `workflow_graph_validation.zig:53`), and
  resource bindings run there and once more in registry publication, which keeps them as
  `cloneGraph`'s precondition (`workflow_graph_compilation.zig:267`,
  `workflow_graph_validation.zig:37`, `workflow_registry.zig:158`).

**C16. Source review, when it runs, sends the whole evidence catalogue with every per-subject
request** (`specification_support.zig:129`; traced: the ledger is rebuilt nine times a subject).
§7 H4 records 34 sends and 67,448 tokens for a hello-world run that reached it. One request a
subject is the user's guardrail and §9 forbids truncating required evidence, so no change is
proposed.

**C17. Several of these counts aren't in the owning step.** `e2e-measures` gives sends, tokens,
stages and the logged span. It doesn't give the input-token share of C9, the forced-answer
count of C10, the reconciliation counts of C11, the request-part shares and schema differences
of C12, the log bytes of C14 or the passive-literal count of C48.

### 10.3 Coupling

**C19. The generic domain core imports the Spec stages.** 119 files, 117 in `domain/` and 2 in
`ports/`, form one import cycle (`pipeline.zig` is imported by 237 of 608 non-test files). The
engine's error set is a union of 41 error sets (`operation_error.zig:55-95`, re-exported at
`workflow_execution.zig:52`); that file imports 33 others, 14 of them Spec-stage modules, and
each Spec file imports `pipeline.zig` for data keys. ADR 0003:100-101 says the four
workflows are "not special cases in the generic engine". The layer test checks layers, not
cycles inside `domain/`.

**C20. `DataKey` is one closed enum of 142 keys** (`pipeline.zig:4-147`): 23 logging, 17 model
request and 2 output keys, and 100 startup keys and keys that only Spec operations touch. Every
per-step structure is sized by the total. **D:** 06-pipeline-nodes.md:38; ADR 0003:84-85.

**C21. The generic outcome association hard-codes Spec keys and types.**
`workflow_outcome_association.zig` holds `required_authority.zig` and `clarification_refresh.zig`
result types (the `reclassify` arms `authority_result` and `clarification_result`), and several
of its 14 descriptor variants (`Descriptor`) are assigned at one to three sites (grep).
`workflow_outcome_binding.zig` branches on `.required_authority_result` and
`.validated_specification_unit` (the `clarification_route` branch), `.specification_support_review`
(`diagnosticAdmission`) and four repair keys (`authorizationBlocked`). A second workflow with its
own gate, clarification route or blockable repair needs edits to both files.

**C22. Change amplification (traced).**

- One operation with one new key: 8 production files and 15 sites.
  `native_workflow_operations.zig` keeps three parallel lists of about 110 entries and a
  hand-kept count (`:176`, `core.entries.len + 112 + model_request.count`).
- One record family: three Zig files the compiler enforces, plus `generation.schema.json`,
  `packet-guidance.json`, the prose of `records.prompt.md:9-13` and `isScope` in
  `specification_markdown.zig`, which it doesn't.
- One reconciliation phase: five parallel enums (`reference_reconciliation.zig:125`,
  `reference_reconciliation_stage.zig:6`, `reference_reconciliation_diagnostic.zig:57`,
  `reference_reconciliation_repair.zig:512`, `reference_reconciliation_repair_workflow.zig:36`)
  and the YAML strings (`reference_reconciliation_stage_workflow.zig:75`), bridged by tag name.

**C23. The model boundary carries Spec names.** The 32-tag `text_field_policy.Field` is part of
the generic field binding (`model_text_field.zig:5-7`); ADR 0038's statement rule is wired through
generic admission (`model_payload_schema.zig:4`); the schema and admission files sit inside the
119-file cycle (C19).

**C24. One request fact is held in up to five ledgers and re-checked at five to seven sites**
(attempt number, the binding, input and sampling triple, deadline, terminal outcome; traced).
**D:** model-request-operations.md ("Accounting integration" and the authorization sections: the
runner validates the exact retained request, attempt, binding, input and deadline); ADR 0030
("Stage rules carry over").

**C25. Reference, repair and review modules import each other, and six files reach through the
validators' nesting.** `reference_reconciliation.zig:123` imports its diagnostic,
which imports the repair owner (`reference_reconciliation_diagnostic.zig:16`), which imports
`source_omission.zig` (`reference_reconciliation_repair.zig:700`), which imports
`specification_support.zig` (`source_omission.zig:52`). Ten production sites in six files reach
`assignments.checked.prior.prior` directly (for example `specification_provenance.zig:27`, `:32`,
`:41`, `:52`), although `reference_support.zig:26` wraps it.

### 10.4 Simplification

**C26. Registered operations that no shipped workflow uses.** `design/workflows/` holds one
definition.

- No workflow anywhere: `prepare-clarification-output` (registered as
  `output.PrepareClarifications` in `native_workflow_operations.zig`).
- Test workflows only: `scan-path-tokens`, `validate-source-citations`,
  `parse-required-authority-observations`. Their keys (`path_token_scan`,
  `reference_citation_proposals`, `validated_source_citations`,
  `raw_required_authority_observations`) have no other producer or consumer.
- Registered beside the consolidated operation Spec uses: the four principle steps
  (`principles.Inventory`, `ValidateInventory`, `Capture` and `Build` in
  `native_workflow_operations.zig`; 13-01:424-426 documents them).

**C27. Code with no production caller.** Each was checked by grep with tests excluded.

- `model_request_handoff.zig:213` `acceptsRetained`; `model_text_wire.zig:106-122`
  `checkProseFields` and its helper; `model_result_schema.zig:13` `ChoiceBoundError`.
- `PipelineEnvelope.place` (`pipeline_envelope.zig:75-84`); `DataKey.feature_log_recovery` and
  `.log_drop_evidence` (`pipeline.zig:133`, `:145`).
- `ValidToolchain.packages()` (`toolchain_safety.zig:10-12`); `ToolChainService`
  (`toolchain_service.zig`; two architecture pins and `workflow_tests.zig:508-509` use it), which
  F0003:206 says the runner constructs. Recommended: delete it with those uses and that claim, as one change with C39.
- `generation.schema.json:481-492` `repair_record_functional_requirement` has no reference in
  the schema or the code. `attributed_value` (`:3-14`) has the same body as `value`
  (`:493-504`); code selects each by name (`switch (kind)` in `specification_repair.zig`).

**C28. Paths no production run can take.**

- Nothing supplies a cancellation or deadline status: production passes the default runtime
  (`run` in `composition/root.zig` passes `.{}`; `pipeline.zig` `alwaysActive`), no production
  code sets `status_fn` and no signal is handled (grep). So the branches on a `cancelled` or
  `deadline_exhausted` runtime status run only in tests, E6's cancellation change included, and
  an interrupt ends the process with no finalization.
- Feature logging: `WorkflowLog.log` (`pipeline.zig:281-295`) has no production caller (grep);
  the mid-run policy transition, historical finalization and the non-empty recovery path have
  test callers only (traced). The designs specify them (14-orchestration.md §§14.9–14.10;
  27-observability.md:6-10); ADR 0009's fresh-run rule and ADR 0026:8-9 leave them unused.

**C29. YAML duplicates, dead edges and one-valued options** (`spec.workflow.yaml`).

- Identical bodies: the `finish-native` and `finish-model` steps (`extract-references`); the
  `release-signals` and `release-conflicts` steps (`validate-reconciliation`).
  `repair-source-extraction` and `repair-source-candidate` differ in one step (`request`).
  Whether the join rule (`workflow_data_flow.zig:70`) requires the paired steps wasn't
  checked.
- `check-reconciliation`'s `ok: end.ok` (`reconcile-references`) can't be taken. The step runs
  only after a summary response or repair, on the input for which the same check returned `more`
  at `select-composition` (`check_reference_reconciliation_purpose.zig:5-8`), and that input is
  rebuilt only after `build-summary`.
- `clarification-output` repeats four of the last seven operations of `publish-specification`
  in the same order, and `check-clarification-progress` runs twice in a row on the pending path
  (`check-output-clarifications`, then `check`).
- Every `request-model` step that names a `result-schema` (14 of the 17) passes
  `result-selection: input`; no shipped step selects `resource`.

**C30. Typed machinery whose result is constant.**

- Coverage repair can only block: a one-variant decision (`specification_coverage_repair.zig:10`,
  `:22-30`) with a repair role, a descriptor, a data key and a binding branch
  (`authorizationBlocked` in `workflow_outcome_binding.zig`). The step has no `ok` route
  (`authorize-coverage-repair` in `assemble-specification-candidate`).
  Q21 owns the gap that this route blocks on.
- `validated_specification_rendering` is always `true`
  (`specification_rendering_workflow.zig:53`), so the `!rendering_valid` checks
  (`build_specification_state.zig:16`; `prepare_specification_output.zig:17`) can't fire.
- The authority outcome is computed by `reconcile` and again by `validate`
  (`required_authority.zig:365-366`), and all four `reconcile` outcomes route to `gate`
  (step `reconcile` in `authority-gate`). **D:** 13-10:81-83. The `required-authority@1` gate is
  registered (the registry's `gates` in `native_workflow_operations.zig`), but no production
  operation declares it, against F0100:720.
- `checkConsistency` is called at admission, story composition and assembly
  (`validate_specification_unit.zig:11`; `compose_specification_story.zig:21`;
  `specification_session.zig:792`), but acts only on a records batch while records are being
  admitted or their scenarios written (`specification_session.zig:674`), so the other two calls
  return null (read).

**C31. Per-kind and copied code (traced unless a line is cited).**

- Reconciliation writes statement, signal and conflict logic once a kind (`select` in
  `reference_reconciliation_repair.zig`).
- `persistEvent` and `persistPrompt` (`feature_log_runner.zig:153-236`, `:274-342`) differ in
  builder, serialiser and stream tag, so C3 has to be fixed twice.
- The open-fstat-check sequence for a log segment is written seven times, and the bounded read
  helper is re-implemented five times.
- The ledger owner block is written five times, and four identical revision structs exist.
- The engine-config and provider-config readers duplicate each other with different rigour
  (`adapters/filesystem/engine_config_source.zig:116-134` has no post-read check).

**C32. The toolchain stage feeds only a policy list and an identity.** 27 action contracts require
`valid_toolchain`; production reads `policies()` and `identity()` only (grep). Both development
cases run with `presets: []` and `policies: []` (`project/.sddtoolkit/principles/toolchain.yaml`;
one run of each case checked), so the stage's nine steps always give the compiled-in rules.
Adds to E2.

**C33. JSON composition is about 980 production lines for two uses** (traced), one of which, the
summary, has a single part. **D:** ADR 0016:42, :248-249.

### 10.5 Brittleness (latent)

**C34. Names carried as strings.**

- Operation parameter names are spelled in a descriptor table and again at each lookup
  (`preparation_parameters` against each `resource(step, "…")` lookup in
  `model_request_workflow.zig`). The lookup returns null on a miss (`resource`), so a drifted
  optional `context` or `protocol-prompt` is dropped from the request with no error.
- The support packet is edited by raw JSON key after encoding (`specification_support.zig:134-148`:
  `getPtr("…").?`, and `orderedRemove` with its result discarded).
- Log columns are read by literal position in the recovery, retention and debugger readers
  (traced: 25 sites in `feature_log_format.zig` and `feature_log_recovery.zig`, about 35 in
  `request_debugger_archive.zig`).

**C35. `else` arms on closed sets.** Production has 313 `else =>` arms in 128 files; not all are on
closed sets. Arms that give a default and no error: `model_result_schema.zig:883` (a shallow
copy of any other node; the file has 13 arms), `reference_reconciliation_repair.zig:398`,
`:485`, `:498`, `:599`, `:636` (the file has 22), `bootstrap_roots.zig:34`, `:41`,
`log_event_registry.zig:142`, `workflow_registry.zig:324`. AGENTS.md asks for exhaustive
switches on closed sets.

**C36. Order and position.**

- `required_authority.zig:359` compares the ordinals of two different enums (`DetectionStage`
  and `Stage`, `:357`); `:403-419` orders by declaration order.
- Unit kinds are compared by integer tag across two unions (`specification_generation.zig:243`;
  `specification_repair.zig:265`).
- The YAML pairs prompts with units by step position (subgraph `generate-specification`) and nothing
  ties a prompt to its unit (no Zig file names the three prompt resources, by grep), so a
  swapped prompt would be accepted.

**C37. Limits that don't bind, and hand counts.**

- `retry-limit: 64` (`merge-repair` in `generate-unit`) and `128` (the `merge` steps of
  `reconcile-references`, `validate-reconciliation` and `repair-reconciliation-candidate`) count visits
  per defect key, which the repair routes can't reach (traced). The real bound is a target
  population written as literals (`targetBound` in `specification_repair.zig`;
  `reference_reconciliation_repair.zig:126-131`). An overflow surfaces as an `.authority`
  rejection (traced).
- The retry limit is enforced by two formulas with two errors (`countAttempt` in
  `workflow_retry.zig`; `model_attempt_accounting.zig:288`); the second can't fire through the
  runner (traced).
- The 64 MiB value bound is written 8 times in six files (grep; for example
  `passive_literal_workflow.zig:6`).

**C38. A passing `zig build verify` reads as a failure.** A passing run prints 6.2 MB: 4,437
feature-log rows and two `failed command:` lines, which Zig prints for any step that wrote to
stderr (`test-integration`, and `test` through `emit_emergency_log_failure_record.zig:22`). The
default summary mode prints no success line; only `--summary line` shows `N/N steps
succeeded; M/M tests passed`. **Owner:** the tests that write to the real stderr.

**C39. Design text the code contradicts (adds to §8 "Design–code conflicts").** F0100:720
("Protected operations declare that gate"; C30). F0003:206 (C27). 26-security.md:224-225 says
a log row is encoded before the lock is taken; `feature_log_orchestrator.zig:17-22` takes the
lock first. 13-05:209 and ADR 0021:24-25 predate the source-preservation projection
(`Source.acceptsProjection` accepts it).

### 10.6 Tests and harness

**C40. A scripted scenario is identified by its position, and the position names its
request-projection freeze.** `runSpecificationWorkflows`
(`test/integration/workflow_tests.zig`) derives its scenario indices from list lengths
(`classification_repair_start` to `link_start`), and 17 of its lines branch on a literal index
(grep). The index names the freeze directory (`Recorder` at `:1621`;
`src/test_fixtures/request_projection.zig:168-170`), so one added fault renumbers every later
scenario: under `evaluations/request-projection/` the three
source-preservation scenarios are 177–179 in freeze `93476e7`, 125–127 in `2b3dc8b`, 126–128 in
`b38628c` and 128–130 in `lever-after`. Two freezes taken either side of such a change don't
line up by path for §2 rule 10's byte comparison, and each scenario T3 asks for causes one
shift. **Class:** measurement. **Owner:** `runSpecificationWorkflows` and
`request_projection.zig`. **Next:** key a scenario and its freeze directory by a stable name.

**C41. The scripted driver is also the oracle, and its checks are gated on name literals (adds to
E8).** `src/test_fixtures/spec_generation_driver.zig` gates checks on operation IDs on seven lines
(`:558-560`, `:578`, `:609`, `:630`, `:634`), on the `extraction-schema` resource (`:275`) and on
slot names (`:218`). Renaming one, code and YAML together, turns the guard false and the check
stops running with no failure. A failed driver assertion is a panic: the file has 101
`catch unreachable` lines.

**C42. No offline run reaches publication through the production composition.** The scripted
scenarios run a hand copy of `Runtime.init`'s wiring (`workflow_tests.zig:1082`, `:1582`, `:3224`,
`:3295`, against `composition/root.zig:57`). Every offline run through `root.Runtime` or the
harness's `invoke.run` stops before publication (traced), so the harness's success path runs end
to end only live.

**C43. Scenarios patch shipped assets by exact text with no check that the patch applied.**
`workflow_tests.zig:1558` (`"group-size: 8"`) and `:1567` (`"/reason"` in
`extraction.composition.json`). If either text changes, the scenario runs unpatched and passes.
The guarded form is at `test/harness/integration/tests.zig:145-146`.

**C44. Scripted branches that no test selects (adds to T3).** 8 of the driver's 24 fault shapes
(`spec_generation_driver.zig:13`: seven of the nine `review_*` shapes and
`runaway_partial_assignment`) and 10 of the 11 support faults
(`spec_generation_responses.zig:12`; only `foreign_source_single` is set,
`workflow_tests.zig:1649`, `:1703`). Checked by grep.

**C45. Versions, layouts and lists repeated by hand.**

- `spec-e2e-report/v20` is spelled on 81 lines in 16 test files (with 11 more lines naming a
  superseded version in the rejection tests), because the schema field has no default
  (`test/harness/e2e/contracts.zig:223`). `baseline-acquisition/v14`, `e2e-step-event/v5`,
  `baseline-score/v6` and `provider-compatibility-report/v3` add 14 more. §2 rule 12 makes each
  closed-member change a version bump.
- The measures reader repeats the evidence layout as literals and returns no responses when the
  directory is missing (`test/harness/e2e/measures_cli.zig:184-203`, `:190`); its tests write
  their own layout (traced), so a moved evidence path would read as zero responses with tests
  passing.
- The 24 workflow assets are listed again in five places (`workflow_tests.zig:1561`,
  `test/packaging/smoke.zig:335-342`, three case files).
- Sequence fixtures pin call positions and retry limits as number literals
  (`summary_protocol_sequence.zig:71-72`; `global_protocol_sequence.zig:72-73`).

**C46. Architecture tests match raw text (adds to T4, which owns the per-file pin count).**
`expectAbsent` is a substring search over the raw file (`src/architecture_test.zig`), so a
comment containing "plan", "hard" or "reference" fails a test with no boundary change (the
`expectAbsent` calls with those three words).

**C47. Registration and leftovers.**

- A `*_test.zig` runs only if `tests.zig`, `src/root.zig` or `src/runtime_tests.zig` imports it.
  Nothing checks reachability: `test-build-registration` checks test executables on a synthetic
  graph (traced).
- Each integration run writes about 1,000 files that nothing reads: 18 dump prefixes and an
  unconditional step trace for every scenario (`workflow_tests.zig:1728-1729`; traced).
  `build/test_run_inputs.zig:28-30` lists three `principle-citation-*` inputs that nothing names.
  Adds to T2.
- `src/test_fixtures/authoring_association_calibration.zig:16` reads a retained run of 11 October
  2026 that is no longer under `zig-out/e2e-spec/`, so part of a unit test returns `.unavailable`
  (`:297`) and is skipped.

**C48. Stages the development cases rarely exercise (adds to T3).** Neither is dead code and no
removal is proposed: live runs give them almost no coverage, so mostly offline tests do.

- Source review and its repairs run only when the source isn't ready (reconciliation not
  complete, or no eligible claim; `generationReady` in `specification_provenance.zig`) or when
  `validation.sourcePreservationCheck` is true (`check_source_preservation_policy.zig:8`; default
  false, `config.zig:68`). That is dozens of production files (import closure, traced), over a
  fifth of the YAML and three resources. None of the six runs of 10 November made a review send;
  of the six of 14 November, one (a loan-renewal run that also formed a conflict group) made 12.
- The passive-literal registry gave an empty list in all 344 requests that carry one in the 38
  runs.

### 10.7 Unconfirmed readings

**C49. Four readings to confirm or drop.** Each is read from the cited lines only and proposes no
change. **Next** for each: a test at its owner that shows the behaviour.

- A records batch bound to a group that holds an open question is offered record content that
  validation refuses, which would block the run (`specification_source_binding.zig:157`;
  `specification_provenance.zig:559`; `specification_repair.zig:80`). **Owner:**
  `specification_source_binding.zig`. **Class:** successful completion.
- The composed story copies fence, table and Setext lines when a claim cites them
  (`specification_story.zig:120`). **Owner:** `specification_story.zig`. **Class:** rendering
  artefact in the published story.
- The provider operation clock reads `.boot` (`provider_operation_clock.zig:13`) and the HTTP
  exchange sleeps on `.awake` (`model_http_exchange.zig:84`), so a request deadline is measured
  on two clocks. **Owner:** the provider adapters. **Class:** none.
- A retry population can differ after a source-omission merge
  (`reference_reconciliation_repair.zig:145-147`; `workflow_retry.zig:471`). **Owner:**
  `reference_reconciliation_repair.zig`. **Class:** successful completion.
