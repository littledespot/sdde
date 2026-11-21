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
`2026-11-18T05-3*`, 6 runs per case, `anthropic` `claude-haiku-5-5`, build `26982bb`, source `0a61828b…`, skill
`3fe52a92…`), the last kept state ([Z_SPEC01](Z_SPEC01.md) "Q23"). Skills `af394020…`, `0b552067…`, `1d66d882…`, `3c74781e…` and `185b9bc6…` count
as one evaluator, and `43c04100…` keeps `3fe52a92…`'s accuracy counts ([Z_SPEC01](Z_SPEC01.md) T7). Accuracy defect counts, content basis, as lost /
weakened / unsupported addition / contradiction:

| Case | Publications | Pass | Defects | Advisory score, mean (range) |
| --- | --- | --- | --- | --- |
| Hello-world | 5 of 6 | 5 of 6 | 0 / 0 / 3 / 0 | 93.6 (85.7–96.4) |
| Loan-renewal | 5 of 6 | 5 of 6 | 0 / 0 / 0 / 0 | 95.0 (92.9–96.4) |

Advisory scores are scored against the case rubrics (`evaluations/e2e/<run>/evaluation.json`);
scorer judgment moves one by about ±3.6, and keep decisions use the accuracy counts (§2 rule 6).

**Retained runs:** `zig-out/e2e-spec/` holds the Haiku set (`2026-11-17T08-4*`), D8.4's set (`21-5*` and
`22-0*`), Q23's set (`23-4*` to `23-58-08Z` and `2026-11-18T05-3*`), Q24's set (`2026-11-18T06-5*`) and two
hello-world runs that failed at the first extraction call (`2026-11-17T07-1*`). Earlier runs are removed;
their evaluations and measures stay under `evaluations/`.
The current build decodes only `spec-e2e-report/v24` (`report_schema` in `test/harness/e2e/contracts.zig`); every run above is v23 or earlier, so its report is `unavailable` to `e2e-measures` and `adjudicate-spec` rejects it. Each needs the build that made it.

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
| Summary representation | Combined, split, overlapping expressions; complete membership; stable identities | Missing or foreign IDs, altered categories, false support, changed exact values | Q8 |
| Normalization | Idempotence; same-evidence duplicates collapse; raw and provenance kept | Different occurrences, distinct obligations, paraphrases, destructive truncation | Q8 (D8.3) |
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

**Output track** (rank order of the table; each item's screens and set follow the set order
above, inside the decided constraints):

| Rank | Item | Defect class reduced | Effort | Validation | Decided |
| --- | --- | --- | --- | --- | --- |
| 1 | **Q26** a Given only where the source states one | unsupported addition and ambiguity in a criterion's Given (all 3 accuracy defects and 5 ambiguities of the 20 November set) | M | Fixtures at the owners, screens of the scenarios call, then a set | Decided 20 November 2026 |

**Engine track, in gaps:** E3's feature logging waits on its preconditions (§5 E3); E7 last. E0 is on
hold. **Tests:** T3 in any gap; T4 with E1–E4. **Adjudication:** the evaluate-e2e skill for every set.
**Code-review order** (§10; decided 21 November 2026, user: "update the documentation with the above
recommendations"): (1) deletions with no design change: C47's panel, C15's fifth render, C20's four keys, C27's two
logging keys; (2) C30's two deletions and C27's `place`; (3) C24; (4) C28 with C49's deadline timer; (5) C29; (6)
C33, proven with the request freeze; (7) C32 with C27's `packages`. Each lands with `/preflight`, the
§2.10 request-projection proof, `zig build verify` and the contract reviewer.

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
  (`specification_coverage.zig:64-75`). No evaluation shows it. Reopen as an item, with its own measured
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

### Q2b. Generic content-loss guard for repairs

**D2.3** implemented and kept 1 November 2026; record in [Z_SPEC01](Z_SPEC01.md) Q2b D2.3. Open
follow-ups:

- fold `member_count` into `collection`'s `exact_members` variant and `coverage` and `agree` into
  `unique_subset` (`IntegerChoice` in `model_result_schema.zig:97-123`; `coverage` is ADR 0038 Decision 5, not
  Decision 3). Turning `collection` into a tagged union makes the illegal pairings of `:223-254` unrepresentable
  and touches 39 sites outside the owner (tests, and `reference_model_input.zig:249`, `specification_support.zig`,
  `scenario_request.zig`) plus about 15 comparisons inside it. It changes no request byte and no ADR requires it
  (ADR 0046:50-53 keeps the native count, as a representation). Not done: prove it with the request freeze.

Out of scope unless harm appears: the statement, signal and conflict coverage inserts and
token classifications.

### Q8. Source-claim granularity (B7)

**Defect:** restatement and claims lost in reconciliation when citations repeat. ADR 0036
Decision 3 and ADR 0038 Decision 4 (the list-item split,
`reference_extraction_text.zig:144-183`) stay as they are (D8.1, decided 3 November 2026).

### Q13. Inline source lines

D13.1 (post-generation reviews removed) and the inline source lines are in
[Z_SPEC01](Z_SPEC01.md). **D13.4** (decided 1 November 2026): principles are context and
constraints only, never origins, and never modified (design.md §3.3 invariant 33). Nothing checks what a shown source
line means beyond the advisory evaluate-e2e link check.

### Q14. Scenarios bound to their claims

**Kept 15 November 2026** (record: [Z_SPEC01](Z_SPEC01.md) Q14 b4). Open parts only:

- **Restated edge cases** from the records call recur (loan-renewal EC-001 and EC-002 repeat AC-005) and
  cost `organization` only. The 13 November edge-case amendment (ADR 0038 Decision 7) is built
  (21 November 2026; `specification/v7`, `specification-state/v27`, `packet-guidance/v7`,
  `model-request-debug/v21`, `spec-e2e-report/v23`); its re-measure is open. The six runs of the
  20 November set before it (build `0de58c78…`, modified) wrote no edge case, so a set may show only
  "benefit not demonstrated" (§2 rule 6). Open: the evaluator ruling on an engine-printed copy of
  a criterion's scenario (`restatement` or not), which `evaluate-e2e` SKILL.md states for a repeat
  of a criterion; Q26 must define the `GIVEN` line for a criterion that has no Given.
  **Set record** (§2 rule 6, before the set): three runs of each development case, extended to at
  most eight per case; one build, both cases. Target: `restatement` by an edge case (scored against
  `organization`), counted per run as the edge cases that repeat a criterion's scenario, read
  under the open evaluator ruling above, so the count is reported both ways. Guards: lost source
  requirement, and the publication rate per case. Watch: `unsupported_addition` in an edge
  case's `given`, a `GIVEN` line whose own given repeats or contradicts the copied Given, and
  `edge_case_without_criterion` blocks. Evidence floor: fewer than about ten edge cases across
  the set is "not enough evidence"; none written is "benefit not demonstrated".
- **Late block, shown once** (`2026-11-15T07-50-08Z-f971…`, a Q17 run): the records call put claim 4
  ("A loan may be renewed only once.") only in an edge case, so no behaviour statement names it, it gets
  no slot and no criterion, and linking stops with `edge_case_without_criterion` (ADR 0038 Decisions 3
  and 7: `scenario_slots.zig:70`, `scenario_link.zig:25-53`). It covers any behaviour claim that only an
  edge case names, not only a scope-only claim. 1 of 5 loan-renewal records calls that carried principles
  and 0 of 16 earlier (no rate).

### Q26. A Given only where the source states one

**Decided** 20 November 2026 (user: "R1: YES", on the advisory R1 of the `2026-11-20T07-4*` and `07-5*`
evaluations); unbuilt. **Defect:** unsupported addition and ambiguity in an acceptance criterion's Given.
The scenarios request requires a Given even when a requirement states only a trigger: the response schema
gives `given` `minLength` 1, its field rule says "Write nonblank prose", and the purpose names "a
precondition, trigger and expected result". It also forbids invention and asks for "what its own wording
presupposes" (`scenarios.prompt.md:4-5`). So the model repeats the trigger or invents a prerequisite:

- hello-world AC-002 gives Given "has been started" and When "is started", and loan-renewal AC-005 gives
  Given "has successfully renewed" and When "The renewal completes successfully";
- hello-world AC-001 gives Given "installed and ready to be run", as in two runs of the 15 November sets.

In that set, a modified build so indicative only (§2 rule 3), 5 criteria in 4 of 6 runs repeat one
event as Given and When. All 3 accuracy defects are unsupported additions in a Given: "installed" once,
and "due date is known" twice. Cause: likely. The request is read from call 10 of `07-47-57Z`; that an
optional Given removes the choice is inferred.

**Change:**
- `given` is optional in the scenarios response and in the acceptance-criterion content, with its content
  and state versions advanced. Its field guidance (`packet-guidance.json:21`) says it is omitted when the
  sources state no starting situation. An edge case's own given (ADR 0038 Decision 7, built 21
  November 2026) shares that guidance entry and stays required, so this change must give the entry a
  text that suits both or key the two apart, and must define the edge case's `GIVEN` line (the
  criterion's Given, the separator, then the own given) for a criterion that has no Given.
- The prompt's presupposition sentence (`scenarios.prompt.md:3-5`) goes. Not adopted: restating the
  Given's meaning in the prompt, which the request already carries from the field guidance (one owner).
- A criterion without a Given renders "**When** … **Then** …".
- It amends ADR 0038 Decision 3, 17-specify.md:174 and :511, 23-rendering.md:24 and :134, and F0100:1081.
  The design text lands with the code.

**Expected effect:** fewer Givens that repeat the trigger or add a prerequisite. Loan-renewal AC-003's
"due date is known" sits beside a starting situation line 9 states, so only the removed sentence bears on
it, unproven. **Risk:** a criterion drops a Given its source states, such as loan-renewal AC-001's
eligibility conditions. Guards: lost source requirement and weakened obligation. **Not covered:** a Then
that repeats its own Given (loan-renewal AC-001 in `07-49-33Z`).

**Next:** `/preflight`, including how the equal-items correction and the duplicate rule compare an absent
Given; then fixtures at the owners, screens of the scenarios call and a set (§2 rules 4 and 6).

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

### E3. Engine routines (A3, ADR 0032)

Startup and provider bootstrap implemented 12 November 2026 and kept 14 November 2026; record in
[Z_SPEC01](Z_SPEC01.md) E3. Open: feature logging, which waits on its preconditions (ADR
0032, "Scope and order"). The baseline tests for cancellation under a lock and for the emergency
lines exist since E6.
The policy-transition coordinator's authority is decided on both sides (prior-run finalization's, ADR
0026; the same-run transition's, ADR 0032, decided 14 November 2026). §10 C28 (decided 21 November 2026)
deletes the same-run transition, which has no producer, and the `finalizeHistorical` stub, so the conversion
has two coordinators left, not three.

### E6. Logging and visibility gaps

- **Prior-run crash finalization** (§14.10). **Authority decided 14 November 2026** (user:
  "recommendation accepted"): segment-header identity alone, with no persisted bootstrap
  lineage (ADR 0026 amended; §14.10 and ADR 0032 updated). Building it is deferred: a crashed
  run's logs stay whole and unpruned, and only damaged prior logs block later runs. Before
  building it, check that header identity suffices where the runner selects the prompt stream
  from the policy (`feature_log_runner.zig:87`), and decide its order against the current
  activation. Build it as an ADR 0032 routine; §10 C28 deletes today's `finalizeHistorical` stub and the
  same-run policy transition. E3's feature-logging conversion waits on ADR 0032's other preconditions
  (§5 E3).

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

## 6. Test track (T)

### T3. Coverage gaps (B5, B7)

- The §22.6-normalized path has no compatible-assessment coverage: the only exchange that carries
  the prefix is a retained live GPT-OSS capture of the claim shape ADR 0036 removed, so it is
  assessed `incompatible` (`provider_compatibility_tests.zig:61`, `:262`, `:305-309`), while
  `.complete` is assessed `compatible` (`:261`, `:412`). Covering it needs a current-shape GPT-OSS
  exchange, from an approved `provider-compatibility` run, or a derived fixture that adds a scenario
  to about eight switches; no slot selects that model now.
- Proof limits recorded at implementation ([Z_SPEC01](Z_SPEC01.md)): no scripted scenario
  quotes an exact copy, so D7.4's freeze doesn't reach its path; Q13's two-source citations
  are covered at the codec, not the projection (the fixture reads one file); no scripted
  statement record names both a taken and an untaken claim, so D16.2's partly taken record is
  proven only at admission. The baseline generator gives every record the group's whole claim
  selection (`associateFixtureResponse`); only the story-restatement runs keep per-record claims
  (`own_claims`), in their first batch, so a partly taken record needs a per-group generator.

### T4. Architecture rules and replay (A5)

`architecture_test.zig` has 109 tests, about 80 of them pinning named files by substring. Built: every
`expectAbsent` reads code only (comments are masked by the tokenizer; text that isn't Zig is judged as is),
imports are read from tokens, and the layer rules for orchestrators, runners and `domain/` and `ports/` are
import rules. Open: the per-file pins that stand for an ADR rule (ADR 0030:475-479, 0031:372-388, 0032:329-341,
0033:367-370, 0011:187-188) become contract-shape rules one at a time, each keeping its rejected fixture, since
none may be loosened and a file-name pin has no graph equivalent without a per-file allowlist. The precondition
"E1–E4 remove files" no longer holds: only E3's logging conversion can still remove pinned files. Prefer
replaying retained captures over extending `spec_generation_responses.zig`.

### T5. Brittleness counts

Definitions and decisions: [Z_SPEC01](Z_SPEC01.md). The `code-heuristics` report names
them by `report.json` member: T5.1 `tests_copying_model_text`, T5.2 `schema_name_branches`,
T5.3 `repeated_instructions`, T5.5 `model_or_case_branches`, T5.6 `model_text_outside_owner`;
T5.4 isn't in it. Each change set that a phase reports on
retakes them on its committed build: `zig build code-heuristics -- --freeze <dir>` with the
freeze §2.10 takes on that build, and T5.4 by hand from `spec.workflow.yaml` (a `slot: repair`
step whose prompt no non-repair step binds). Last taken 19 November 2026 on the working tree after
T2 (a modified build; 145 scenarios, 1,969 calls, a freeze not retained). Its counts, beside the ones
taken 14 November 2026 after E5 (freeze `evaluations/request-projection/e5-final`) and 2 November 2026
on the `b38628c` tree (freeze `evaluations/request-projection/b38628c`, 130 scenarios, 1,714 calls), are
in [Z_SPEC01](Z_SPEC01.md) T5. No retake lies between them, so each difference is the net of every
change between the two dates, not one change's share. **Due:** with the next change set that a phase
reports on. T5.4 is now 7, the sites under "Repair requests without step guidance". That list named
six until this count; `repair` in `generate-scenarios` (`spec.workflow.yaml:772`) is the seventh, and
when it joined isn't recorded.

## 8. Backlog

§7 (human decisions) is removed; §8–§10 keep their numbers so citations elsewhere still resolve.

### B7 contract-review leftovers

- Prior-state readback checks stored claim text against the text policy only
  (`reference_snapshot.zig:116-117`; ADR 0036:205-206); re-quoting needs the Unicode
  normalizer at readback.

### Design–code conflicts (7 November 2026 review)

**Defect:** none in published output: design text that the code contradicts or lacks misleads
design-routed changes. **Owner:** the cited documents (ADR and AGENTS.md changes are policy
edits). **Next:** **Decision** marks what only the user settles; F0002 is a code change.

- **F0002 event registry** against `src/domain/log_event_registry.zig`. **Decided** (9 November
  2026): F0002 stays the target (F0002 §4 says so). Built: the required `repair_unit_kind` on
  `repair.applied` and `task_id` on `task.completed` and `task.failed`, the common optional
  `evidence_status`, and registry-owned sensitivity (the event stream admits public metadata only). No event
  column, report member or format version moved, so §2 rule 12 required no bump. Open:
  - `diagnostic_code` is a closed enum in F0002:329-331 but a validated token in code (`telemetry.zig:175-185`),
    and 06-pipeline-nodes.md:188 says the existing token rule stands and adds no code family. The codes have many
    sources and two spellings of one cause today (`RETRYLIMITEXHAUSTED` on the terminal event,
    `RETRY_LIMIT_EXHAUSTED` on `retry.exhausted`). **Decision:** the enum's members and which spelling.
  - `TelemetryFact` is one variant per event (F0002:191-220) but one struct with `event_type` and `fields` in code
    (`telemetry.zig:207-215`). Mechanical: about ten production files and 40 test literals, no row changes.
  - **Decision:** a `model.completed` cause field. SPEC01 C4 closed it on 20 November 2026 and
    27-observability.md:103-105 states "`model.completed` gains no cause field"; F0002:357 lists none. Adding one
    reverses both and needs the field's name and closed members.
- More, from the 11 November 2026 code review: §10 C39.

### Retired SPEC01 IDs cited elsewhere

"SPEC01 <ID>" citations of items now in [Z_SPEC01](Z_SPEC01.md) resolve there. Items removed on
20 November 2026 as not affecting the Spec workflow's completion, tech debt or simplicity (Q4, Q7, Q17,
E1, E2, E5, E15, T2, H1–H5, R1, R6, C9, C11–C14, C16, C17, C48 and the wider-scope list) are in git
history.

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
- **Status:** nothing here is approved or scheduled, and each item needs its phase approval
  (§2). An item that names no defect class targets no published-output defect: it reports a fact
  or asks a Decision, and proposes no change (AGENTS.md: cost is reported, never the reason for
  a change). An item that changes a model request is a Q phase with a named class. **D** marks a
  cost that an accepted ADR or a contract requires, so removing it is a **Decision**.

### 10.1 Failures first

**C4. Most failures report one payload-free name.**

- **Provider and authorization (built 20 November 2026, Z_SPEC01):** the run report and the CLI
  carry the last call's typed failure (contract 08). **Decided** 20 November 2026 (user: "update the
  documatation with above recommendations"):
  - **Closed, no change.** The feature log's `model.completed` gains no cause field
    (27-observability.md:103-105): the E2E report's `last_provider_rejection` and the CLI carry the
    cause. A provider stop and a runner rejection print no provider line (contract 08:37-39): every
    stop writes a warning `model.provider_stopped` with its reason (27-observability.md:141), and
    retry exhaustion prints its own line (`main.zig:65-68`).
  - **To build as one change (unbuilt).** The provider failure line gains two enum reasons, never a
    key byte, a length or provider text. Class: none (diagnosability). Order: after C38's cost table.
    - `credential=missing|malformed`. An unset key, an empty one and a malformed one (a space,
      control or non-ASCII byte, such as a CR from CRLF line endings) all read `authentication_failed;
      delivery=not_sent` (`provider_api_key.zig:35-37`), and `.env.e2e` can't be read to tell them
      apart. Owners: the key capture, a `malformed` key state, `api_key_authorization.zig:25` and the
      port's failure enum, `ProviderFailure` and `provider_failure_detail.zig`, the replay's
      unavailable-key arm (`request_replay.zig:92`) and the packaged smoke's pin.
    - `decode=<reason>`. Every `response_invalid` without a content diagnostic names why: a body that
      isn't JSON (`provider_response_assembly.zig:122`), a body the decoder refuses (`:127`, where its
      diagnostic is dropped today), the assembly step (`:132`) and an error body the error table
      doesn't know (`:144`). The JSON path is never printed, because it is built from provider field
      names (contract 08:42). ADR 0028 rejects an undocumented field, so a new provider field would
      fail every call with no retry; no retained run has shown it.
    - It amends contract 08:41 and F0006 §8; the design text lands with the code.
- **Workflow definition (built 20 November 2026, Z_SPEC01):** a rejection used to be one of two
  codes with no step, key or rule. It now prints a rule class, the definition's path and the
  step or resource after its code; the schema, compile and graph owners still return one error
  each, and a rule is one per section or stage, so a finer cause (the data key a data-flow
  rejection names) is not reported. A key missed from a
  hand-written invalidation list (`source_omission.zig:343`, `:345`; `required_authority.zig:124`)
  fails the same way, because the data-flow check rejects producing a key that is still
  available (`workflow_data_flow.zig:87-95`).
- **Result schemas and compositions:** a rejected resource already prints its file and
  `resource=<id>` under `compiled_resources` (`workflow_graph_compilation.zig:264`, `:276`); the
  cause inside it is not reported, because `model_result_schema.zig` (94 `invalid()` sites) and
  `json_composition.zig` (47) return one error each. About 40 of the schema sites and 35 of the
  composition sites are startup compile; the rest are request-time restriction and projection
  (`restrictFieldPolicies`, `narrowChoice`, `projectVariants`), which F0005 §9 does not govern.
  **Decided not to build** (user, 20 November 2026, after the preflight): a cause per profile section
  would need a typed slot through the four compiler-port functions and about nine new rule classes,
  amending F0005 §9 ("a rule names a stage, not a cause"; "never per call site"), 13-01 and ADR 0032,
  for a diagnostic that names no published-output defect. Four unrecorded returns in
  `compileResources` (`:253`, `:256`, `:257`, `:275`) print the step only.
- **Reference ingestion (built 20 November 2026, Z_SPEC01):** an entry that could not be read or
  decoded fails `validateAccounting` with the error of its own reason, and the CLI prints the first
  failing entry's display path after that name (contract 08). The nine names stay.
- **Toolchain:** every toolchain failure is `error.InvalidToolchain`; the stage names the
  failing step in the event (`Step` in `prepare_toolchain.zig`), not the rule that failed.

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

**C15. Repeated native work (no time to recover; one rule kept at many sites).** What no ADR
requires is built: one registry structure check per runner, one copy of a packet chain's source
bytes, no unused token-classification snapshot, and one outcome-flow check at startup. What stays:

- The clean path re-runs validators: `validate-dispositions` three times and `validate-signals`
  twice with a conflict group, once fewer without one, because each release returns to the first
  validator (`release-collected` in `validate-reconciliation`). Not routing alone: the collect
  actions invalidate the carrier the next validator reads, so only a validator step rebuilds it. Removing
  the re-runs means the collect actions replace the carrier and the YAML gains release sites, an ADR 0022
  amendment (:24-26, :161) and a 13-03 amendment; no clause requires the repeats, and the validators cost
  little beside a model call. `check-summary-reuse` and `validate-summary` run once per partition, which
  ADR 0022:63-70 and :88-91 require. Inside the parent path `reuse-summary` re-runs `reusableSummary`
  after `check-summary-reuse`; removing that needs a new `DataKey`, and ADR 0022:63-69 keeps a stale child
  failing, never falling back.
- Publication renders `spec.md` five times and parses it twice. 13-05:299-311 and :328-330 require four
  renders (render, validate's two, prepare's re-render against the state). The second round trip in
  `prepare_specification_output.zig:25-26` repeats the validate parse on the same bytes and no clause names it.
  **Decided** 21 November 2026 (user: "update the documentation with the above recommendations"); unbuilt:
  delete `:25` and the `reparsed` clause of `:26`. Only `render-specification` produces
  `rendered_specification` and nothing replaces it, and `prepare` requires `validated_specification_rendering`,
  which only validate's round trip on the same value produces, so the fifth render can't fail. 13-05:310-311
  owns the round trip; 13-05:329's "re-render byte-identically" is render 4, so no design text changes. Add a
  rejected case at `prepare` (bytes that differ from the state's render).
- The codec parses a response, re-serialises it and parses it again (`decode` in
  `model_candidate_json.zig`). Nothing needs the re-serialised bytes, but a value-based decode needs
  parity for the types with `jsonParse` hooks (`specification_source_binding.zig:40`,
  `positive_json_integer.zig:26`), which isn't established.
- Registry publication re-checks the resource bindings as `cloneGraph`'s precondition
  (`workflow_registry.zig:158`; `src/workflow_registry_test.zig` pins it). `ValidatedGraphs` is a plain
  struct, not a sealed proof, so dropping the check needs it sealed first.

### 10.3 Coupling

**C19. The generic domain core imports the Spec stages.** The engine's error set is a union of
operation error sets (`operation_error.zig`, re-exported at `workflow_execution.zig:52`), and
`model_request_identity.zig` and `workflow_output.zig` also import a Spec-stage module; each Spec file
imports `pipeline.zig` for data keys, and `pipeline.zig` and `pipeline_data.zig` import each other. ADR
0003:100-101 says the four workflows are "not special cases in the generic engine". Built: a rule in
`architecture_test.zig` lists the generic engine's domain files that import a Spec stage (by file-name
prefix), those three today, and fails on a new one or a stale entry, so the list only shrinks. No clause
forbids an import cycle in `domain/`, so none is asserted; a cycle-free rule would be new authority.
Whether the 119-file cycle the 11 November review counted is one strongly connected component was never
established by a graph pass.

**C20. `DataKey` is one closed enum of 136 keys** (`pipeline.zig:4-141`): 23 logging, 17 model
request and 2 output keys, and 94 startup keys and keys that only Spec operations touch. Every
per-step structure is sized by the total. **D:** 06-pipeline-nodes.md:38 alone requires one enum
(ADR 0003:84-85 states only the engine-change rule); splitting it edits that contract, and about 20 architecture
pins name keys.
**Decided** 21 November 2026 (user: "update the documentation with the above recommendations"): keep the one
closed enum; the item closes once its leftovers go. Per-workflow enums would break ADR 0003:109-110 (workflows
are run-time YAML sharing operations), an enum assembled from contracts is the same enum, and a union of owner
enums loses dense indexing (06:9-10, :38); the size is cost only, and the kernel keys' move was refused on 19
November 2026 ("E1 DataKey - NO", [Z_SPEC01](Z_SPEC01.md)). Unbuilt: delete `invocation_working_directory`
(`pipeline.zig:8`, no other reference), `raw_engine_config` (`:9`), `engine_config` (`:10`) and
`canonical_log_level` (`:13`), read only by tests as borrowed fixture keys, under ADR 0032:229-236; point those
tests at test-local schemas and replace `engine_config` in 06:38's example list. The enum then shrinks only through
the feature-logging conversion (E3) and stage conversions.

**C21. The generic outcome association keeps closed readers by decision.** The two Spec result types in the
`reclassify` arms are gone: the binding reads the owner's sealed result and the association checks the
`ResultOutcome` it names. A blockable repair still needs a member of `BlockedReader` and its arm in
`authorizationBlocked`, a second diagnostic admission a member of `AdmissionReader`, and a second clarification
route a member of `RouteReader`, each with its arm; a missing arm does not compile. ADR 0033:195-201, F0005:660-663
and 13-04:326-332 make them closed, so owner-supplied readers would be an amendment. A second workflow with its own
gate or refresh descriptor still edits the association and the binding. The request descriptors keep their evidence
keys in `requestOperation`: closed, because every model call runs each of the 14 kernel stages that produce them,
and a workflow definition can't author them (ADR 0030).

**C22. Change amplification (traced).**

- One operation with one new key: about 8 production files. `native_workflow_operations.zig` keeps three
  parallel lists (fields, initializers and `entries` rows) and a hand-kept count (`core.entries.len + 108 +
  model_request.count`). A field with no row compiles; a test in `test/harness/integration/tests.zig` now finds it.
  One table would need the operation fields in their own struct, because `entries` can't type itself from the
  struct that holds it, and about 12 external `native.<field>` accesses would move.
- One record family: three Zig files the compiler enforces and `Kind.isScopeSection`, now a method with an
  exhaustive switch; a test requires a `record_<kind>` definition and the `record_kind` member for every family
  but the entity. `packet-guidance.json` was already checked at decode. `records.prompt.md:9-13` names the families
  in prose, which no test can judge.

**C23. The model boundary carries Spec names.** The 32-tag `text_field_policy.Field` is part of
the generic field binding (`model_text_field.zig:5-7`, `model_text_wire.zig`, `typed_text.zig`,
`model_text_composition.zig`, `atomic_repair.zig:281`); ADR 0038's statement rule is wired through
generic admission (`model_payload_schema.zig:4`). **Decision:** the field identity. `Field` is JSON-stringified
and decoded by name (`atomic_repair.zig:73-79`, :101-107), so a replacement must serialise as the same name and
compare by value: one enum per owner, with the generic modules parameterised on it. That touches about 13
Spec domain files, 13 tests and the harness, and amends text-field-composition.md:53 ("one closed native field
registry"). No workflow definition names a tag, so the move is Zig only and changes no request byte.

**C24. The binding, input and sampling triple is written out by hand.** The five ledgers (request identity,
attempt accounting, provider operation, authorization lease, tokens) hold distinct facts: the attempt number has
one owner (model-request-operations.md:84-85 forbids a second retry counter), the three terminal facts are
distinct by contract (:256-258, :295-296), and the deadline copy in the invoked operation is required (:160). The
re-checks validate different runner deltas, a deadline that changes with time, or the lease's trust boundary
(:77-79, :109-110, :149, :160-165; ADR 0030:200-203; ADR 0039:159-160), so they stay. The debt:
`provider_operation_lifecycle.Assignment` (`:11-16`) names the triple, but five sites compare it field by field,
`Record` flattens it (`:61-63`), the lease `Entry` copies two of its fields (`provider_authorization_lease_table.zig:19`,
`:22`), and the lease's `matches` (`:210-217`) omits sampling, covered today only at
`workflow_model_accounting.zig:169` and `provider_invocation_validation.zig:142`.
**Decided** 21 November 2026 (user: "update the documentation with the above recommendations"); unbuilt, class
none (brittleness), no amendment: `Record` holds an `Assignment`, `Assignment.of(request)` and `eql` replace the
five comparisons, and the lease `Entry` stores the `Assignment` and `matches` compares it whole, which adds the
sampling check at consumption ADR 0039:159 asks for. Tests: a lease consumed with another sampling is denied;
update `provider_operation_lifecycle_test.zig:265` and `model_request_workflow_test.zig:986`, `:6625`. Proof:
byte-identical request projection.

**C25. Repair, omission and support modules still import each other.** The reconciliation core and its
diagnostic no longer import them (the repair target types moved to the diagnostic, which carries the pending
repair), and `Accounted.global()` is the one place the checked chain is unwound; both are pinned in
`architecture_test.zig`. Still cyclic: `reference_reconciliation_repair.zig` and `source_omission.zig` import each
other (`Authorization`, `Replacement` and `Repair` at `source_omission.zig:325-338`), and `source_omission.zig`
and `specification_support.zig` import each other. Breaking the first moves those unions to
`source_omission_repair.zig`; no document names either edge.

### 10.4 Simplification

**C27. Code with no production caller.** **Decided** 21 November 2026 (user: "update the documentation with
the above recommendations"); unbuilt, each a deletion:

- `PipelineEnvelope.place` and `Placement` (`pipeline_envelope.zig:23`, `:75-84`): delete them. Re-pointing the
  tests at `apply` doesn't work for the accepted case: `apply` always starts a fresh occurrence (`:130`) and
  `applyOccurrence` turns an existing record into `InformationConflict` (`:191`). Move the rejected cases
  (foreign scope, conflicting value or origin, schema mismatch, history not reviving authority) to
  `applyOccurrence`, and delete the idempotent assertions and `model_request_workflow_test.zig:7927-7935`. Amend
  06-pipeline-nodes.md:238-242 and F0005:645-646 to "a second recording of one occurrence and key rejects".
  ADR 0016:299 stays: the composition runtime implements its rule (`json_composition_runtime.zig:139-145`).
- `DataKey.feature_log_recovery` and `.log_drop_evidence` (`pipeline.zig:127`, `:139`, their only references):
  delete them now. Ruling: ADR 0032:208-210's "compiler-locked `DataKey`s" of the logging envelope are the keys
  the envelope uses; these two have no producer, consumer, schema or pin, so they are leftovers of removed
  operations (AGENTS.md "Delete superseded code").
- `ValidToolchain.packages()`, the stored copy and `Composed.packages` (`toolchain_composition.zig:9-16`, copied
  at `toolchain_safety.zig:51-52`): delete them with C32; `Resolved.packages` stays because it orders the policy
  union. Package facts belong to Plan's design (13-01:497-502). Amend 13-01:414 and F0003:202-204; update the
  literal `.packages =` fixtures (`path_token_test.zig`, `reference_preparation_test.zig`,
  `test_fixtures/reference_text.zig`).

**C28. Paths no production run can take.** Nothing supplies a cancellation or deadline status: `run`
(`composition/root.zig:24`), the request debugger (`request_debugger.zig:13`) and the harness
(`test/harness/e2e/invoke.zig:30`) pass `.{}`, so `status_fn` is `alwaysActive` (`pipeline.zig:184`, `:502-504`),
and nothing installs a signal handler (grep `sigaction`, `SIGINT`). Fourteen production status readers have dead
`.cancelled` and `.deadline_exhausted` arms (among them `runtimeTerminal`, `workflow_pipeline_runner.zig:1226-1231`,
the four stage actions and `model_http_exchange.zig:55-57`), about 100 tests are named for cancellation, and
`WorkflowLog.log`, the mid-run policy transition (`Lifecycle.transition`, `LogService.transition`), `finalizeHistorical`
and the non-empty `recover` branch have test callers only. Ctrl-C today is the default SIGINT kill, an ADR 0009
interruption: the OS releases the per-stream `flock`s, the logs stay in an ADR 0026 crash shape that is kept whole
but not pruned until E6, and a killed harness run writes no report. The ADRs decide how a cancellation is checked
and recorded (ADR 0011:164-165, 0031:228-231, 0032:98-100, :131-133, :193-207; 0026:105; design.md:95), not where it
comes from. A lease expiry reaches `Rejection.deadline_exhausted` in production (`workflow_pipeline_runner.zig:1116`,
fed by `checkDeadline` at `:656`), so that one is live. `WorkflowLog` is owned by F0002 (:32-33, :72, :128-129,
:173-183, :651, :674-677, :741-746), F0003:268-271, :352 and F0004:221, and 27-observability.md:9 is already false
(the runner emits through `workflow_event_capture.Capture`, `workflow_pipeline_runner.zig:259`).
**Decided** 21 November 2026 (user: "update the documentation with the above recommendations"); unbuilt, one
change with the C49 deadline timer, class none (no published-output change; an in-flight call is billed either way,
ADR 0009:58):

- **A cancellation source:** a SIGINT adapter at the composition root (`src/adapters/system/`, about 40 lines;
  `std.posix.sigaction` with `SA.RESETHAND`) whose handler only stores an atomic, read by `status_fn` in `run`,
  the request debugger and the harness (through a composition re-export: `architecture_test.zig:71` forbids
  `/adapters/system/` in `invoke.zig`). The first Ctrl-C ends the run `cancelled` within one timer slice, with
  closed, prunable logs and a `workflow_cancelled` harness report (`invoke.zig:39-41`); a second is the default
  kill. `Io.Threaded` retries its sleeps on EINTR (`std/Io/Threaded.zig:11604-11606`). Test: install the
  handler, `std.posix.raise` SIGINT, restore the previous action. Not adopted: deletion, which the distinct
  completion states forbid (design.md:95) and which `Io`'s `Canceled` mapping would not remove.
- **Deleted in the same change:** `RuntimeStatus.deadline_exhausted` (`pipeline.zig:176-180`; no document names a
  run-level deadline producer) with its arms and test arms (`startup_routine_test.zig:394`,
  `model_provider_bootstrap_test.zig:128`, `workflow_value_flow_test.zig:215`); the `WorkflowLog` channel for
  action telemetry (`pipeline.zig:271-294`, `StepInput.log`, the runner's construction, `NodeDelta.telemetry_facts`,
  `addedTelemetryFacts`, the `InvalidTelemetryCount` check, `max_facts_per_delta`, and their tests); the mid-run
  policy transition (about 200 lines with no producer: ADR 0032:206-207, and `ClassifyBootstrapAuthorityChangeAction`
  is "Proposed, no code", 13-01:450-453), with its `DataKey` (`pipeline.zig:130`) and `scanOtherBindings` /
  `scans_run_history`; and the `finalizeHistorical` stub with `FinalizationMode` (ADR 0026:44-45 and §14.10:315 already
  say it is unbuilt; E6 builds it). This reverses the 14 November 2026 authority for the same-run transition, which
  returns with a producer.
- **Kept:** the sink's cancellation mapping and its baseline tests (ADR 0032:164-165), non-empty recovery and
  `recoverDropped` (ADR 0032:180-182; §14.10:303), active finalization and retention.
- **Amends:** ADR 0032 "Cancellation mapping" (a source bullet; :193-198's reason: the source is read only at
  boundaries and timer slices, never inside a sink call), :99, :135-136 and :199-210; ADR 0031:233, :238-239; ADR
  0026:45-47; §14.10:259-291; 09-configuration.md:392, :401; 13-09:26-31; F0002–F0005 and 27-observability.md:6-10,
  06-pipeline-nodes.md:73-80, :96-97 for `WorkflowLog`; F0004:204, :260 and F0005:114, :833, :966 for the run-level
  deadline. The design text lands with the code.

**C29. `result-selection` repeats a fact the packet owns.** `input` selects the definition the input packet
names (`model_request_handoff.zig:265-270`, `:296`); `resource` sends the bound schema's root and drops a packet's
definition, while the packet's integer choices still name it (`reference_model_input.zig:247-261`). `input` is on 16
of the 19 `request-model` steps; the other three are composition steps, which forbid the parameter
(`workflow_model.zig:65-71`). Every production packet that reaches a `result-schema` step names a definition; only
the packaged fixture (`test/packaging/fixtures/provider-request/provider-request.workflow.yaml:13`, a static input)
and some tests use `resource`. The opt-in is ADR 0013:73-74, the producer supplies the identity (:75).
**Decided** 21 November 2026 (user: "update the documentation with the above recommendations"); unbuilt, class
none (brittleness): derive the selection from the input. A `result-schema` step given a packet selects the
packet's definition; a packet with no definition fails before invocation (ADR 0012:68 kept); a static or absent
input sends the whole resource; composition steps are unchanged. The parameter, its enum and the 16 YAML lines go.
Not adopted: `input` as the default (moves the noise), or a packet with no definition falling back to the whole
resource (drops a fail-before-invocation check). Amends ADR 0012:64-68, ADR 0013:73-74, ADR 0016:113, ADR 0030:121
and 13-04-model.md:11-14; about 20 test edits (`model_request_workflow_test.zig` patches and packet tests,
`model_capabilities_test.zig:47`, `repair_routes_test.zig:76`, `test_fixtures/prepared_model_repair.zig:23`,
`specification_generation_test.zig:9029`, `:9348`). No request byte changes; prove it with the request freeze.
`finish-native`/`finish-model` and `repair-source-extraction`/`repair-source-candidate` can't merge (the join rule
compares composition state, `workflow_data_flow.zig:69-70`; a call binds every parameter, ADR 0013:27, :30), so
those parts are closed.

**C30. Typed machinery whose result is constant.** **Decided** 21 November 2026 (user: "update the
documentation with the above recommendations"); unbuilt, class none, no request byte changes:

- **Coverage repair's one-variant decision: delete it.** `specification_coverage_repair.zig:10` is
  `union(enum) { blocked }`, and `authorize` (:22-31) re-checks a revision and snapshot that can't have changed
  (it runs straight after validation, `spec.workflow.yaml:818-824`) and always stamps
  `.no_independent_supported_target`. `validate-specification-coverage` returns `blocked` itself, with its reason,
  as `plan-scenario-links` does (`scenario_link_workflow.zig:30-48`); the run outcome, publication and diagnostic
  are unchanged. Delete `specification_coverage_repair.zig`, `specification_coverage_repair_workflow.zig`, the owner
  member, `DataKey` (`pipeline.zig:100`), payload variant, the `.specification_coverage` blocked reader, the
  diagnostics branch, the `operation_error.zig:60` import, `native_workflow_operations.zig:37`, `:468`,
  `Rejection.dependencies`, `Rejection.revision` and `repair.stamp`. Not adopted: ending `invalid`, which contradicts
  22-repair.md:823-824, F0100:1387-1390 and ADR 0041:87-88. Amends ADR 0033:105, :107 (12 owners, 28 variants), :194,
  :197-199 (three readers), :348; 13-04-model.md:324, :330; 13-05:230-231, :236. Tests: the run stays `blocked` with
  its session attached; if the E2E report serializes the whole `Rejection` (`test/harness/e2e/contracts.zig:282`),
  dropping its fields needs a report version (§2 rule 12).
- **The `required-authority@1` gate: drop the registration and the text.** No production operation declares it
  (`required_authority_workflow.zig:18`, registered at `native_workflow_operations.zig:434`). The outcome ledger
  already enforces the authority: until the reconciliation clears, model requests are refused and the run can't
  end `ok` (`workflow_outcome_binding.zig:179-197`, `:312-339`, `:371-375`), and generation won't start while an
  authority key is live (`specification_workflow.zig:64-67`). The pre-commit rebuild (§31.39, 13-10:73-75) stays.
  Keep the general gate mechanism, which Plan's predecessor gates need (`workflow_value_flow_test.zig`), and the
  `required_authority_gate` key, which the ledger reads. Delete `:18`, set `.gates = &.{}`, and rewrite
  `required_authority_workflow_test.zig:213-253` to assert that a rejected result routed onward can't end `ok`.
  Amends F0100:719-724, :727-730 and 13-10:74-75; it closes C39's F0100 entry.

**C31. Per-kind and copied code (traced unless a line is cited).** Built: one persist path for both log
streams, one segment open and one whole-segment read in `feature_log_file.zig`, and one generic `Revision`.
Open:

- Reconciliation writes statement, signal and conflict logic once a kind (`select` in
  `reference_reconciliation_repair.zig`).
- The ledger owner block is written five times (`createInitial`, `createSuccessor` and
  `createLifecycleSuccessor` in `model_request_identity.zig`; `createInitial` and `apply` in
  `model_attempt_accounting.zig`), with the chain release and retain beside them. A shared helper takes the
  payload type and each owner's reference-exhaustion error, and needs an allocation-failure test for the two
  owners first: only the lifecycle owner has one.
- The engine-config and provider-config readers differ in rigour, not by copying. The engine reader already
  checks the read length through `bounded_file_capture.capture`; it lacks the provider reader's re-stat, identity
  and path re-binding after the read. F0008:75 requires those for the provider only and F0001:162-167 asks the
  engine reader for the limit and size drift, so matching them is a tightening: **Decision.** The two ports and
  routines stay separate (ADR 0032:86, :105).

**C32. Contracts that only re-check the toolchain.** 46 contracts require `valid_toolchain` (26 actions and 20
repair operations, `src/repair_operations_test.zig:76-104`). Only `compile-naming-policy` builds from it
(`policies()` and `identity()`, `naming_policy.zig:16-30`); the others re-check the binding (`typed_text.zig:135`,
`naming.validateBinding` through `path_token_grammar.zig:34-35`), which no compiled graph can fail: producing an
available key is rejected (`workflow_data_flow.zig:87-88`) and nothing replaces or invalidates `valid_toolchain`.
Both development cases ship `presets: []` and `policies: []` (`test/e2e/<case>/principles/toolchain.yaml`), so they
get only `core.safety@1`, whose rules feed Spec's path-token grammar (F0100 §3.6:346-365).
**Decided** 21 November 2026 (user: "update the documentation with the above recommendations"); unbuilt, class
none (coupling): keep the stage and its nine steps (they validate the project's toolchain file on every run, and
F0003 and design.md §30 Increment 1 make them core for Plan). Only `compile-naming-policy` and
`prepare-reference-tokens` read `valid_toolchain`; grammar construction keeps the exact binding F0100 §3.6 requires.
Remove the key from the other 24 action and 20 repair contracts and `source_omission.zig:339`, and `current` from
`typed_text.Context`, `ScopeSetContext`, `dependencies`, `reference_reconciliation_validation.TextContext`, the
provenance context, the `reference_extraction_*` functions and `readContext` (`specification_workflow.zig:249-256`);
downstream `validateBinding` keeps its inputs check. Delete `packages` in the same change (C27). Add an architecture
pin that `prepare-toolchain` is the only producer of `valid_toolchain` and nothing replaces or invalidates it; delete
the stale-successor tests (such as `reference_preparation_test.zig:351`). Amends F0003:202-204, :255, F0100:1353,
13-01:414 and the `valid_toolchain` entries of the 13-03 to 13-05 Reads lines. No request byte changes (the
toolchain is never serialized); prove it with the request freeze. Not adopted: deleting stage steps.

**C33. JSON composition for a one-part summary.** The core is 980 lines (`json_composition.zig`,
`json_composition_runtime.zig`, `workflow_json_composition.zig`, `json_composition_workflow.zig` and four actions).
Extraction uses all of it (two parts, `requires`, alternatives by the content part's `kind`, a native part;
`spec.workflow.yaml:219-254`). The summary composes one part, `/statements`, from the one-property `summary`
definition (:384-415; `reconciliation.schema.json:74-107`), so assembly and `validate-assembled-json` re-check one
shape; `definition` and `input-context` exist only for it (`json_composition.zig:133-142`, `:162-166`). The other three
reconciliation assignments select natively (`reference_reconciliation_stage.zig:38`), as does the summary's own
repair (YAML :520-528). **D:** ADR 0016:42 (generic mechanism), :251-252 ("Summaries use one part selected from
`summary`"), ADR 0022:33. ADR 0016:126 ("The common composition/request owner performs selection") is already false
for three of the four assignments.
**Decided** 21 November 2026 (user: "update the documentation with the above recommendations"); unbuilt, class none
(simplification): shrink. The summary calls `request-model` with `result-schema: reconciliation-schema` and
`result-selection: input` (or C29's derived rule), its packet builder selects `summary` natively, and
`collect-reference-reconciliation-result` reads the admitted request as `collect-reference-dispositions-candidate`
does. Delete the summary's composition asset and resource line, the `initialize-summary`, `retain-summary` and
`assemble-summary` steps, and the `definition` and `input-context` features with their tests; keep the mechanism for
extraction. Not adopted: replacing extraction's composition (ADR 0016:408-411; risks the classification request's
`prerequisites` bytes). Amends ADR 0016:93-104, :121-134, :251-252, ADR 0022:33, contract 12:933-943 and
13-03:278-281. Request bytes are expected unchanged but unproven: the request freeze must compare `schema.project`
(`json_composition.zig:198-211`) against `select(summary)`; if any byte differs, it is a Q phase with sets (AGENTS.md).
Retained captures record the summary as a composition and replay differently afterwards (no dual reader).

### 10.5 Brittleness (latent)

**C36. Order and position, still open.** The YAML pairs prompts with units by step position (subgraph
`generate-specification`). The test driver ties each unit to its prompt (`generationPrompt` in
`spec_generation_driver.zig`, which it asserts against each request's prompt bytes), so a swap fails `zig build test-integration`, but the engine accepts it: ADR
0005:74-76 and 0012:57 make the pairing the workflow's to declare, and resources are validated by kind only
(`workflow_graph_compilation.zig:349-354`).

**C37. Limits that don't bind, still open.** The retry values `64` and `128` are ADR 0033:99, :103, :202-206's, and `maximum_population = 128` is a user decision (15 November 2026); the
retry limit is enforced at `workflow_retry.zig:447`, `workflow_pipeline_runner.zig:529`,
`model_attempt_accounting.zig:288` and `workflow_compilation.zig:223`, of which the accounting error can't fire
through the runner (only `model_attempt_accounting_test.zig:26-30`, `:50-59` reach it), and ADR 0030:200-203
fixes the semantics, so unifying them is its own change.

**C38. A passing `zig build verify` still reads as a failure.** Zig prints a `failed command:` line for
any step that wrote to stderr, and the default summary mode prints no success line; only `--summary line`
shows `N/N steps succeeded; M/M tests passed`. Built 20 November 2026 ([Z_SPEC01](Z_SPEC01.md) "A passing
run is quiet"): `test-integration` fell from 9.9 MB of stderr to 0.46 MB. What still writes to stderr:
the scenario cost table (`scenario_timing.zig`), which nothing reads (no script, skill, record, design
file or evaluation names `scenario-cost` or `scenario-total`); about 300 feature-log rows from the baseline acquisition tests, whose production code
materializes the frozen case config itself; and 33 `SDDE_LOG_FAILURE` emergency lines in `test` from the
layout tests, because the composition builds `log_output.Adapter` inline (`feature_logging_runtime.zig:143`).
**Decided** 20 November 2026 (user: "update the documentations with the above recommendations"): judge the
pass where it is read.
- `/verify` runs `zig build verify --summary line` and judges the run by its exit status and the
  `N/N steps succeeded` line (`.claude/skills/verify/SKILL.md` step 6, changed the same day).
- **The cost table goes** (decided 20 November 2026, user: "update the documatation with above
  recommendations"; unbuilt). Delete `report`, `write` and their test, the `test-scenario-timing` step
  and its registration, and the timing arithmetic; keep the phase that a failing scenario's message
  names (`workflow_tests.zig:1556`). Not adopted: printing it on request through a build option, for
  output nothing reads. Unverified: whether it is `test-integration`'s last stderr writer (0.46 MB
  remains, more than the table); the preflight measures it. First in the order, before C4's two
  reasons.
- **No** injectable emergency sink. ADR 0032:168-169 keeps the emergency line exactly once, and the composition
  root builds every adapter (ADR 0032:114; 29-package-structure.md:11-12), so a seam there would serve only 33
  predictable test lines.

**C39. Design text the code contradicts (adds to §8 "Design–code conflicts").** F0100:723-724
("Protected operations declare that gate"; C30) is removed with C30's gate (decided 21 November 2026). The
other two are corrected:
26-security.md now says a log row is encoded under the held lock once the stream state yields its sequence, and
13-05 names both source projections. ADR 0021 never stated the restriction.

### 10.6 Tests and harness

**C41. The scripted driver is also the oracle (adds to E8).** A failed assertion in one of its step hooks
is a panic: `src/test_fixtures/spec_generation_driver.zig` has 104 `catch unreachable` lines. Its
`isRoute` and `isSourceMerge` gates use typed IDs, which break the build when renamed, but nothing checks
that the graph still binds those owners.

**C42. The scripted matrix still runs a hand copy of `Runtime.init`'s wiring** (`workflow_tests.zig:1095`,
`:1699`, `:3703`, `:3774`, against `composition/root.zig:59`). One offline run now reaches publication
through `root.Runtime` and the harness's `invoke.run`, with only the transport scripted
(`test/harness/integration/tests.zig`, "an offline Spec run reaches publication…"; the answers come from
`spec_generation_responses.build`, and `invoke.Options.runner_view` is its test-only seam). It is the happy
path of hello-world on the Claude slot. No fault scenario, no second case and no Bedrock slot runs through
the production composition, so a wiring drift that only a fault path reads still passes the matrix.

**C45. Hand counts in the sequence fixtures, still open.** `summary_protocol_sequence.zig:70-90` and
`global_protocol_sequence.zig:72-91` script a scenario for retry limit 2, so their call positions and attempt
ordinals follow from it, and deriving the limit needs the compiled step's id, a string.

**C47. Registration and leftovers.**

- A `*_test.zig` runs only if `tests.zig`, `src/root.zig` or `src/runtime_tests.zig` imports it.
  Nothing checks reachability: `test-build-registration` checks test executables on a synthetic
  graph (traced).
- Tests write outputs that no test or build step reads: a step trace for every scenario
  (`workflow_tests.zig:1353`; Z_SPEC01 uses it as structural-equivalence evidence) and calibration
  reports under `.zig-cache/` (`authoring-comparison`, `authoring-associations`,
  `representation-admission`, `semantic-simplicity/phase0`; versioned report schemas, written and
  read back inside their own suites). **Kept** (user, 20 November 2026): the trace is the proof that
  a refactor leaves the executed steps unchanged, and the calibration suites replay retained
  captures.
- The authoring-association calibration's parent preflight, which skipped part of a unit test because
  the retained run of 11 October 2026 is gone, is deleted (user, 21 November 2026). `collect` now returns
  `StaleCalibrationRun` or `MissingCalibrationParent` when `live-run.json` exists
  (`authoring_association_calibration.zig:347-354`), so a leftover file fails `zig build test`, `run_manifest`
  is otherwise always null, and the live-receipt branch of `consumeTrial` (:400-447) is unreachable;
  `admitReceipt` and `responseFacts` run only from the mock receipts in `receiptChecks` (:531-555), and
  `verifyAuthoringDiagnosticParent` (`workflow_tests.zig:2871-2922`, called at :1695) preflights a lineage no
  panel can launch from, writing a file nothing reads. The panel pins `openai.gpt-oss-20b-1:0` in five places,
  and its README (:66-69) is a second replay procedure beside §2 rule 4's screening. Nothing in force depends on
  it; ADR 0048:146 only records it. **Decided** 21 November 2026 (user: "update the documentation with the above
  recommendations"); unbuilt: delete the panel whole: `src/test_fixtures/authoring_association_calibration.zig`,
  its test (`specification_generation_test.zig:38-40`), `test/calibration/authoring-associations/`,
  `test/calibration/authoring-roles/` (read by no code), `workflow_tests.zig:1695` and `:2871-2922`, and the
  `build/test_run_inputs.zig:13` entry (re-point the `:107` example); `authoring-associations` leaves the list in
  the bullet above. No design change. Check that scenario 0's request projection stays byte-identical (the
  preflight also wrote `test/e2e/config/.sddproviders.json` into its project, `:2885`). The behaviour the offline
  run touched is tested at its owners (`specification_generation_test.zig:4573`, `:7862`;
  `model_candidate_json_test.zig:104`, `:603-608`).
- **Not yet checked, same pattern:** `source_loss_calibration.zig:203-225` consumes receipts against
  `handoff.parent.json`, and no code reads the `record-authoring`, `signal-grouping`, `summary-coverage` and
  `entity-applicability` calibration material.

### 10.7 Unconfirmed readings

**C49. Built 20 November 2026 ([Z_SPEC01](Z_SPEC01.md) "C49"); what stays open.**
- **Live sets for the story reading and the records batch** (Q phases, rendering artefact and successful
  completion): not run, and each needs the user's approval (§2 rule 4). Neither development case's source has
  a fence, table, Setext heading or open question, so a set can show only that nothing regresses ("benefit
  not demonstrated", §2 rule 6); the offline tests at each owner carry the evidence. The records batch also
  moves a run that ended blocked to `awaiting_clarification`, so a set that reaches it reports false
  questions and missed gaps apart (28-testing.md §28.9).
- **A clarification-only batch's subject:** the subject is `{specification, record_kind, content}` and the
  model picks `record_kind` (`build_specification_clarification_need.zig:26-29`), so a rerun that picks
  another kind mints another form. This is true of every records clarification; the batch only reaches it
  more often. An answered group is authored by E7 (answers are not consumed yet), so until then a rerun asks
  again.
- **The request deadline on macOS:** the deadline is read on `.boot` (`provider_operation_clock.zig:13`), which is
  `CLOCK_BOOTTIME` on Linux and `CLOCK_MONOTONIC_RAW` on macOS (`std/Io/Threaded.zig:14087-14105`); both count
  suspended time, so the deadline judged after each call (`workflow_pipeline_runner.zig:656`) is right on both. Only
  the exchange timer's wake is late on macOS: `clock_nanosleep` is absent there, so `Threaded.sleep` takes
  `sleepNanosleep` (:11649-11672), a relative `nanosleep` that ignores the clock, and a stall spanning a sleep ends
  later by up to the time asleep. No effect on published output, calls or cost. **Decided** 21 November 2026 (user:
  "update the documentation with the above recommendations"); unbuilt, built with C28's cancellation source: the
  timer sleeps `min(slice, remaining)` and re-reads the injected `lease.Clock` and the run status after each wake, the
  same code on every platform, at most one slice late. The slice is polling granularity, not a limit. Amends ADR 0030
  "Request deadline" with an enforcement bullet. Delete the source-text pin and its comment
  (`provider_operation_clock.zig:18-36`); tests in `src/model_http_test.zig`: the fake clock jumps past the deadline
  between slices and the exchange times out within one slice; the status turns cancelled mid-exchange and the
  exchange returns `error.Cancelled` with both tasks joined; relax the fixture's exact 100 ms assertion (:192).

**C50. A workflow definition can route past the configured preservation review** (by reading, not executed).
`check-source-preservation-policy` routes `ok` to `preservation-requirements` and `more` to `generate`
(`spec.workflow.yaml:99-100`), and its operation (`SourcePreservationPolicy`, `required_authority_workflow.zig:22-44`)
declares no outcome association, so a definition that routes `ok` to `generate` compiles and skips a configured
review. F0100:723 says YAML cannot bypass required authority; the gate C30 drops never covered this step, and one on
retire wouldn't either. **Next:** a test at the owner that compiles such a definition, then a decision on the owner
(an outcome association on the policy step, or a compile-time rule).
