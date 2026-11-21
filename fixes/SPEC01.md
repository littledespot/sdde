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
The current build decodes only `spec-e2e-report/v23` (`test/harness/e2e/contracts.zig:223`); every run above is v22 or earlier, so its report is `unavailable` to `e2e-measures` and `adjudicate-spec` rejects it. Each needs the build that made it.

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
| 2 | **Q21** behaviour claims need statements | lost source requirement: a behaviour claim no statement names, passed through a whole-group selection (none since ADR 0047) | M–L, by D21.1 | Fixtures at the owner, screens of each changed call kind, then a set | D21.1 deferred |

**Engine track, in gaps:** E3's feature logging waits on its preconditions (§5 E3); E7 last. E0 is on
hold. **Tests:** T3 in any gap; T4 with E1–E4. **Adjudication:** the evaluate-e2e skill for every set.

**Open problems without an item.**

- **Repair requests without step guidance:** seven repair sites take their task only from the
  three-line `repair.prompt.md` (`spec.workflow.yaml` steps `text-repair` in `extract-references`,
  the extraction repair in `validate-extraction`, `request` in `repair-reconciliation-candidate`,
  `repair` in `generate-unit`, `repair` in `generate-scenarios`, `request` in `repair-source-extraction`
  and `request` in `repair-source-candidate`), and the two reconciliation repairs among them
  (`repair-reconciliation-candidate` and `repair-source-candidate`) bind no context.
  Binding definitions (Q2) wasn't kept; counted as a brittleness measure (T5).

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

### Q21. Behaviour claims need statements

**Defect:** lost source requirement: a behaviour claim that no statement or scenario names
passes coverage, because the brief fields, entity basis and composed story select whole
groups and a claim maps through any field holding it (`specification_coverage.zig:52-61`,
`:75`). In a one-group feature, as both development cases were with `openai.gpt-oss-20b-1:0` (with
`claude-haiku-5-5` they form 1 to 5 groups, [Z_SPEC01](Z_SPEC01.md) "Q23"), ADR 0038 Decision 2's scenario
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
0026; the same-run transition's, ADR 0032, decided 14 November 2026).

### E6. Logging and visibility gaps

- **Prior-run crash finalization** (§14.10). **Authority decided 14 November 2026** (user:
  "recommendation accepted"): segment-header identity alone, with no persisted bootstrap
  lineage (ADR 0026 amended; §14.10 and ADR 0032 updated). Building it is deferred: a crashed
  run's logs stay whole and unpruned, and only damaged prior logs block later runs. Before
  building it, check that header identity suffices where the runner selects the prompt stream
  from the policy (`feature_log_runner.zig:87`), and decide its order against the current
  activation. The same-run policy transition's authority is decided separately (ADR 0032); E3's
  feature-logging conversion waits on ADR 0032's other preconditions (§5 E3).
- **Untested candidate arm:** `observation.capture`'s candidate arm
  (`test/harness/e2e/observation.zig:132-133`) has no direct test.

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
- Scripted branches no scenario selects: §10 C44.

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
- `source_selections.validate`'s typed `Issue` is discarded by both production callers
  (`validate_reference_claims.zig:32-34`, `source_omission_comparison.zig:130-131`), and
  `validate-reference-selections` validates token classifications only. Delete the unused
  detail and rename the step and key for what they do (touches `spec.workflow.yaml`, F0100,
  `workflow_tests.zig` and nine `src` files; lands in a gap).

### Design–code conflicts (7 November 2026 review)

**Defect:** none in published output: design text that the code contradicts or lacks misleads
design-routed changes. **Owner:** the cited documents (ADR and AGENTS.md changes are policy
edits). **Next:** **Decision** marks what only the user settles; F0002 is a code change.

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
- **Two same-stage `clarification_required` gaps becoming two forms (§14.14):** no test covers it.
  (The upstream-rework branch of `required_authority_clarifications.build` is deleted,
  [Z_SPEC01](Z_SPEC01.md) "Upstream rework".)
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

**C15. Repeated native work (no time to recover; one rule kept at many sites).**

- Every executed step revalidates the whole operation registry, a pairwise ID loop over every
  registered operation included (`authorityMatches` in `workflow_pipeline_runner.zig`, called by
  `executeStep`; `Registry.validate` in `ports/workflow_operation_registry.zig`, "Rebuild on
  every call").
- The clean path re-runs validators in all six runs: `validate-dispositions` three times and
  `validate-signals` twice, because each release returns to the first validator
  (the `ok` routes of `release-signals` and `release-conflicts` in `validate-reconciliation`; a
  source with no conflict group has no `release-conflicts` since ADR 0022's forced conflicts answer,
  so each validator runs once fewer); `check-summary-reuse` and `validate-summary` twice, once for the requested leaf summary and
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
`workflow_outcome_binding.zig` reads its owners' decisions through closed readers. A second workflow with its own
gate or clarification route needs edits to both files. A blockable repair needs a member of `BlockedReader`
and its arm in `authorizationBlocked`, a second diagnostic admission a member of `AdmissionReader` and its arm
in `diagnosticAdmission`, and a second clarification route a member of `RouteReader` and its arm in the
`clarification_route` branch; a missing arm does not compile. The request descriptors keep their evidence keys
in `requestOperation`: closed, because every model call runs each of the 14 kernel stages that produce them, so
a wrong key fails the first test, and a workflow definition can't author them (ADR 0030).

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
- `ValidToolchain.packages()` (`toolchain_safety.zig:10-12`); `workflow_tests.zig:508-509` calls it.
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
- `persistEvent` and `persistPrompt` (`feature_log_runner.zig:225-315`, `:353-427`) differ in
  builder, serialiser and stream tag, so a change to how a row persists is made twice.
- The open-fstat-check sequence for a log segment is written seven times, and the bounded read
  helper is re-implemented five times.
- The ledger owner block is written five times, and four identical revision structs exist.
- The engine-config and provider-config readers duplicate each other with different rigour
  (`adapters/filesystem/engine_config_source.zig:116-134` has no post-read check).

**C32. The toolchain stage feeds only a policy list and an identity.** 27 action contracts require
`valid_toolchain`; production reads `policies()` and `identity()` only (grep). Both development
cases run with `presets: []` and `policies: []` (`project/.sddtoolkit/principles/toolchain.yaml`;
one run of each case checked), so the stage's nine steps always give the compiled-in rules.

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

**C39. Design text the code contradicts (adds to §8 "Design–code conflicts").** F0100:720
("Protected operations declare that gate"; C30). 26-security.md:224-225 says
a log row is encoded before the lock is taken; `feature_log_orchestrator.zig:17-22` takes the
lock first. 13-05:209 and ADR 0021:24-25 predate the source-preservation projection
(`Source.acceptsProjection` accepts it).

### 10.6 Tests and harness

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
`workflow_tests.zig` (`"group-size: 8"` and `"/reason"` in
`extraction.composition.json`). If either text changes, the scenario runs unpatched and passes.
The guarded form is at `test/harness/integration/tests.zig:145-146`.

**C44. Scripted branches that no test selects (adds to T3).** 8 of the driver's 25 fault shapes
(`Fault.shape` in `spec_generation_driver.zig`: seven of the nine `review_*` shapes and
`runaway_partial_assignment`). Checked by grep. `SupportFault` has since shrunk to its one
selected member, `foreign_source_single`.

**C45. Versions, layouts and lists repeated by hand.**

- `spec-e2e-report/v23` is spelled on every test line that builds a report, in 16 test files (and
  its predecessor on the lines of the rejection tests), because the schema field has no default
  (`test/harness/e2e/contracts.zig:223`). `baseline-acquisition/v15`, `e2e-step-event/v6`,
  `baseline-score/v7` and `provider-compatibility-report/v4` add 14 more. §2 rule 12 makes each
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
- Tests write outputs that no test or build step reads: a step trace for every scenario
  (`workflow_tests.zig:1353`; Z_SPEC01 uses it as structural-equivalence evidence) and calibration
  reports under `.zig-cache/` (`authoring-comparison`, `authoring-associations`,
  `representation-admission`, `semantic-simplicity/phase0`; versioned report schemas, written and
  read back inside their own suites). **Kept** (user, 20 November 2026): the trace is the proof that
  a refactor leaves the executed steps unchanged, and the calibration suites replay retained
  captures.
- `src/test_fixtures/authoring_association_calibration.zig:16` reads a retained run of 11 October
  2026 that is no longer under `zig-out/e2e-spec/`, so part of a unit test returns `.unavailable`
  (`:297`) and is skipped.

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
- **The request deadline on macOS:** the exchange timer sleeps on `.boot`, which counts suspended time on
  Linux (`CLOCK_BOOTTIME`). Zig 0.16's threaded `Io` sleeps a relative duration with `nanosleep` on macOS,
  which takes no clock, so suspended time still doesn't count there. Counting it would need the timer to read
  the deadline's clock again after a wake, which no decision covers.
