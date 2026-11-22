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
accuracy counts (§2 rule 6). **Ruling needed** (the user's): this revision doesn't count a generic Given such as
"installed and available to run" or "with a known existing due date" as an unsupported addition, and the revision
before it did (3 in the hello-world reference). It decides a score in 3 of the 5 publications of Q14's set
(hello-world run 1 and both loan-renewal runs) without changing a pass. It would add a minor
`unsupported_addition` to each of the three loan-renewal publications of Q26's set.

**Retained runs:** `zig-out/e2e-spec/` holds the Haiku set (`2026-11-17T08-4*`), D8.4's set (`21-5*` and
`22-0*`), Q23's set (`23-4*` to `23-58-08Z` and `2026-11-18T05-3*`), Q24's set (`2026-11-18T06-5*`) and two
hello-world runs that failed at the first extraction call (`2026-11-17T07-1*`), and the runs of 19 to 21
November 2026. Earlier runs are removed; their evaluations and measures stay under `evaluations/`.
The current build decodes only `spec-e2e-report/v25` (`report_schema` in `test/harness/e2e/contracts.zig`); every run above is v24 or earlier, so its report is `unavailable` to `e2e-measures` and `adjudicate-spec` rejects it. Each needs the build that made it.

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

**Output track:** no item awaits a screen or a set. Q26, the last, is kept; §4 holds its open parts.

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

**D2.3** implemented and kept 1 November 2026; record in [Z_SPEC01](Z_SPEC01.md) Q2b D2.3. `collection` is a tagged
union (Z_SPEC01 "Refactors that leave request bytes unchanged").

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

- **Shared `given` guidance:** the one sentence also reaches the repair request of a held Given, where only
  `replace` is possible, and the records request for an edge case, whose `given` stays required; no Given was
  repaired in the set. Keying the two entries apart (`packet-guidance/v8`) is the alternative, and the remedy if
  the field rule's "Write nonblank prose" (`text_field_policy.zig:110`) causes the retained repeats (evaluator:
  `prompt_conflict`, `likely`; 3 target events in 24 criteria, below the evidence floor). A prompt or contract
  change is decided on both development cases with repeated runs (AGENTS.md). A second set on the same request bytes
  (22 November 2026, build source `7880686f…`, 3 runs per case, all six published and passed, 98.81% for each case)
  shows both sides: hello-world run 1 filled all 3 Givens with "No starting situation is stated in the sources."
  (one minor `placeholder`, the same `prompt_conflict` reading, 96.43%) while runs 2 and 3 omitted every Given;
  loan-renewal kept a Given on 15 of 15 criteria, 1 repeating its When and 5 generic preconditions (counted apart).
  A third set (22 November 2026, build source `4f3793a0…`, the same request bytes; all six published and passed,
  hello-world 100%, loan-renewal 97.62%): hello-world omitted the Given on 6 of 9 criteria with no filler and gave the
  other 3 a generic precondition; loan-renewal omitted one Given (the first in 45 loan-renewal criteria), repeated a
  When once and gave 5 of 15 a generic precondition, dropped none its source states, and repaired none (its two repairs
  replaced a Then). Across the three sets, 5 events (4 Givens repeating their When, 1 placeholder Given) in 72
  criteria: still below the floor.
- **Not driven end to end:** `links.prompt.md` still says "its given and when cover that situation", and no
  scripted integration scenario drives a Given-less criterion; the owner tests and `verify` cover it. No run has
  written an edge case, so an edge case's `GIVEN` line for a Given-less criterion is unexercised live (Q14's
  edge-case bullet).
- **Generic Givens** ("…with an existing due date", 3 of 15 loan-renewal criteria in the set) wait on §1's
  ruling needed.

## 5. Engine track (E)

Each item: `/preflight`, offline tests, the §2.10 proof, `zig build verify`, one live run
per case (DE2–DE4, in [Z_SPEC01](Z_SPEC01.md), asked whether offline evidence replaces it),
landing between sets and under §2.12.

### E0. Failed and blocked runs publish validated content (B10, ADR 0041)

On hold since 30 October 2026 (ADR 0041:3-4). Nothing under `src/` names `failure-output`,
`spec_incomplete` or `run.incomplete_published`. To resume: implement ADR 0041 Decisions 1–8,
taking `specification-state/v29` (ADR 0041 names it); align the measures
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

- The retained live GPT-OSS capture, the only exchange with a real §22.6 prefix, has the claim shape ADR 0036
  removed, so it is assessed `incompatible`. A derived exchange (`.prefix_normalized` in
  `provider_compatibility_tests.zig`, the contract's first malformed opening in front of a schema-valid candidate) is
  assessed `compatible`, which proves the harness classification only. A current-shape GPT-OSS capture needs an
  approved `provider-compatibility` run; no slot selects that model now.
- Proof limits recorded at implementation ([Z_SPEC01](Z_SPEC01.md)): no scripted scenario
  quotes an exact copy, so D7.4's freeze doesn't reach its path (requests never carry spans, and the owner has unit
  tests); no scripted statement record names both a taken and an untaken claim, so D16.2's partly taken record is
  proven only at admission. The baseline generator gives every record the group's whole claim
  selection (`associateFixtureResponse`); only the story-restatement runs keep per-record claims
  (`own_claims`), in their first batch, so a partly taken record needs a per-group generator.

### T4. Architecture rules and replay (A5)

`architecture_test.zig` has 110 tests, about 80 of them pinning named files by substring. Built: every
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
step whose prompt no non-repair step binds). Last taken 22 November 2026 on the build of Q26's set (`ea69a53`,
modified; freeze `evaluations/request-projection/q26-after`): T5.1 11, T5.2 0 (tests 69), T5.3 8 at 17 sites,
T5.4 7, T5.5 0 and T5.6 15 in 4 files. T5.1 gained one single-word absence literal (`given`,
`model_candidate_json_test.zig:504`); the 21 November engine batch moved none of them (freeze
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

### B7 readback leftover

- Readback re-quotes each stored claim's wording from its stored citation spans, but binds no stored citation's
  `source_id`, `block_id` or `verbatim` to the claim's chunk: the snapshot validator compares ordinals only, and
  `source_citations.validate` checks all four fields at admission. A state with a retargeted `source_id` or an
  altered `verbatim` and an unchanged `location` reads back.

### Design–code conflicts (7 November 2026 review)

**Defect:** none in published output: design text that the code contradicts or lacks misleads
design-routed changes. **Owner:** the cited documents (ADR and AGENTS.md changes are policy
edits). **Next:** **Decision** marks what only the user settles.

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
  - **Open residual.** ADR 0028 rejects an undocumented field, so a new provider field would fail every call
    with no retry (`decode=body_refused`); no retained run has shown it. The E2E harness rejects a missing or
    invalid key before the run (`test/harness/environment.zig`), so only the CLI path reports `credential=`.
- **Workflow definition (built 20 November 2026, Z_SPEC01):** a rejection used to be one of two
  codes with no step, key or rule. It now prints a rule class, the definition's path and the
  step or resource after its code; the schema, compile and graph owners still return one error
  each, and a rule is one per section or stage, so a finer cause (the data key a data-flow
  rejection names) is not reported. A key missed from a
  hand-written invalidation list (`source_omission.zig:156-158`; `required_authority.zig:124`)
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
bytes, no unused token-classification snapshot, one outcome-flow check at startup, and one parse of
`spec.md` at publication (four renders, as 13-05:299-311 and :328-330 require). What stays:

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

**C20. `DataKey` is one closed enum of 128 keys** (`pipeline.zig:4-133`): 20 logging, 17 model
request and 2 output keys, and 89 startup keys and keys that only Spec operations touch. Every
per-step structure is sized by the total. **D:** 06-pipeline-nodes.md:38 alone requires one enum
(ADR 0003:84-85 states only the engine-change rule); splitting it edits that contract, and about 20 architecture
pins name keys.
**Decided** 21 November 2026 (user: "update the documentation with the above recommendations"): keep the one
closed enum. Per-workflow enums would break ADR 0003:109-110 (workflows are run-time YAML sharing operations), an
enum assembled from contracts is the same enum, and a union of owner enums loses dense indexing (06:9-10, :38); the
size is cost only, and the kernel keys' move was refused on 19 November 2026 ("E1 DataKey - NO",
[Z_SPEC01](Z_SPEC01.md)). A key with no producer, consumer or schema is deleted when found. The enum then shrinks
only through the feature-logging conversion (E3) and stage conversions.

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

- One operation with one new key: about 8 production files. In `native_workflow_operations.zig` the fields are one
  struct (`Operations`) and the `entries` rows and their count are derived from it (Z_SPEC01 "Refactors that leave
  request bytes unchanged"), so the operation costs an import alias, a field and its initializer there; the YAML,
  `DataKeys` and schemas are unchanged. The initializers are still written by hand, which the compiler checks against
  the fields, and `model_request_operations.zig` keeps its own `count = 8` and parallel rows (a test guards it).
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

**C25. Repair, omission and support modules still import each other.** The reconciliation core and its
diagnostic no longer import them (the repair target types moved to the diagnostic, which carries the pending
repair), and `Accounted.global()` is the one place the checked chain is unwound; both are pinned in
`architecture_test.zig`. `source_omission.zig` no longer imports `reference_reconciliation_repair.zig`,
`reference_extraction_repair.zig` or `specification_support.zig`: the repair-authority derivation is
`source_omission_authority.zig` and `Authorization`, `Replacement` and `Repair` are `source_omission_repair.zig`'s.
A rank pin in `architecture_test.zig` holds the direct-import order of those six modules; it does not claim
transitive acyclicity. A 58-module domain cycle group remains: `source_omission` with `required_authority`
(`:5`, `:101-102`, `:516`), `source_omission_comparison` and `specification_support_evidence`, and
`reference_extraction.zig:69`, `:94` with `reference_extraction_repair.zig`. No document names these edges.

### 10.4 Simplification

**C28. The run's cancellation source; what stays.** The operator's interrupt is the one cancellation source
(`src/adapters/system/interrupt_source.zig`, installed by `composition/root.zig` `run` and the E2E harness; ADR
0030 "Request deadline"). A lease expiry still reaches `Rejection.deadline_exhausted`; `RuntimeStatus` has no deadline member.
- **The request debugger installs no handler.** Its idle `accept` loop never reads the status and `Io.Threaded`
  retries its sleeps on EINTR, so a handler would swallow the first Ctrl-C; the default kill stays there.
- **Exit code:** a cancelled CLI run exits 1, not 130 (`main.zig:42-76`); a second Ctrl-C is the default kill.
- **Recovery no longer scans the run's other bindings:** a stray entry in the run directory outside the binding
  directory no longer fails recovery, and `rotation.maxSegments` counts the current binding's segments, which is
  the run's while a run has one binding.
- **Unproven:** the cancel-within-a-slice path is tested at the timer with a fake clock and a flipping status
  (`model_http_test.zig`), at the adapter with `raise`, and through the harness's `invoke.run` with a real SIGINT
  raised on a scripted call (Z_SPEC01 "Test-track closures"). Not proven: a Ctrl-C the kernel delivers to an arbitrary
  thread, `Io.Threaded` sleeps retried on EINTR under the real HTTP adapter, and the CLI exit code.

**C30. Typed machinery whose result is constant; what stays.** The general gate mechanism
stays with no production gate, which Plan's predecessor gates need; nothing now registers `required_authority_gate`
as gate evidence, so only the outcome ledger and the sole writer (`validate-required-authority-reconciliation`)
enforce it. A definition that routes a rejected authority result onward runs the later step and still can't end
`ok`; one that skips validation leaves its step unreachable (`required_authority_workflow_test.zig`).

**C31. Per-kind and copied code (traced unless a line is cited).** Built: one persist path for both log
streams, one segment open and one whole-segment read in `feature_log_file.zig`, one generic `Revision`, one `select`
over the statement, signal and conflict kinds in `reference_reconciliation_repair.zig`, and one ledger owner
(`ledger_owner.zig`, shared by `model_request_identity.zig` and `model_attempt_accounting.zig`; Z_SPEC01 "Refactors
that leave request bytes unchanged"). `retainOwner`'s exhaustion branches are not allocation failures, and no public
seam of either ledger reaches them; the helper's own tests do.

Closed 21 November 2026 (user: "update the documentation with rhe recommendations"): the engine-config reader
keeps F0001:162-167's limit and size-drift checks and gains no re-stat, identity or path re-binding, which
F0008:75 requires of the provider reader only.

### 10.5 Brittleness (latent)

**C36. Order and position, still open.** The YAML pairs prompts with units by step position (subgraph
`generate-specification`). The test driver ties each unit to its prompt (`generationPrompt` in
`spec_generation_driver.zig`, which it asserts against each request's prompt bytes), so a swap fails `zig build test-integration`, but the engine accepts it: ADR
0005:74-76 and 0012:57 make the pairing the workflow's to declare, and resources are validated by kind only
(`workflow_graph_compilation.zig:349-354`).

**C37. Limits that don't bind.** The retry values `64` and `128` are ADR 0033:99, :103, :202-206's, and
`maximum_population = 128` is a user decision (15 November 2026). `workflow_retry.Limit` decides when a limit is
exhausted (`standing`, `allowance`); the retry scope, the runner, the compiled allowance and the attempt accounting
call it and keep their own error mappings. The accounting error can't fire through the runner (only
`model_attempt_accounting_test.zig` reaches it), and ADR 0030:124-125 fixes the semantics.

**C38. A passing `zig build verify` still reads as a failure.** Zig prints a `failed command:` line for
any step that wrote to stderr, and the default summary mode prints no success line; only `--summary line`
shows `N/N steps succeeded; M/M tests passed`. What still writes to stderr:
about 300 feature-log rows (0.45 MB) from the baseline acquisition tests, whose production code
materializes the frozen case config itself; and 33 `SDDE_LOG_FAILURE` emergency lines in `test` from the
layout tests, because the composition builds `log_output.Adapter` inline (`feature_logging_runtime.zig:143`).
**Decided** 20 November 2026 (user: "update the documentations with the above recommendations"): judge the
pass where it is read.
- `/verify` runs `zig build verify --summary line` and judges the run by its exit status and the
  `N/N steps succeeded` line (`.claude/skills/verify/SKILL.md` step 6, changed the same day).
- **No** injectable emergency sink. ADR 0032:168-169 keeps the emergency line exactly once, and the composition
  root builds every adapter (ADR 0032:114; 29-package-structure.md:11-12), so a seam there would serve only 33
  predictable test lines.

**C39. Design text the code contradicts (adds to §8 "Design–code conflicts").** Corrected:
26-security.md now says a log row is encoded under the held lock once the stream state yields its sequence, and
13-05 names both source projections. ADR 0021 never stated the restriction.

### 10.6 Tests and harness

**C41. The scripted driver is also the oracle (adds to E8).** A failed assertion in one of its step hooks
is a panic: `src/test_fixtures/spec_generation_driver.zig` has 98 `catch unreachable` lines. Its merge gates are a
`merge_routes` table of typed (operation, owner) pairs, and the `gates_bound` block fails the scenario with
`GatedRouteNotInGraph` when the compiled graph binds none of one (Z_SPEC01 "Test-track closures").

**C42. The scripted matrix still runs a hand copy of `Runtime.init`'s wiring** (`workflow_tests.zig:1061`,
`:1758`, `:3705`, `:3776`, against `composition/root.zig:65`). Offline runs reach publication, a repaired
publication and a retry-limit failure through `root.Runtime` and the harness's `invoke.run` for both development
cases, with only the transport scripted (`test/harness/integration/tests.zig`; the answers come from
`spec_generation_responses.build`, and `invoke.Options.runner_view` is its test-only seam). No Bedrock slot runs
through the production composition, and the matrix's other fault paths still run the hand copy, so a wiring drift
that only one of those reads still passes.

**C45. Typed limits beyond the sequence fixtures, still open.** The summary, global and disposition sequences derive
their calls from the compiled step's allowance. The scenarios-step exhaustion (`workflow_tests.zig:2041-2042`) and
the disposition sequence's fixed calls before its exhausted request (extraction content 2, classification 1) still
type values that follow from the limit.

**C47. Leftovers.**

- Tests write outputs that no test or build step reads: a step trace for every scenario
  (`writeStepTrace`, `workflow_tests.zig:1291`; Z_SPEC01 uses it as structural-equivalence evidence) and calibration
  reports under `.zig-cache/` (`authoring-comparison`,
  `representation-admission`, `semantic-simplicity/phase0`; versioned report schemas, written and
  read back inside their own suites). **Kept** (user, 20 November 2026): the trace is the proof that
  a refactor leaves the executed steps unchanged, and the calibration suites replay retained
  captures.
- `source_loss_calibration.zig` consumes a review receipt only when one exists (none does), and its admission gate
  has accepted and rejected tests: a live-trial slot, **kept**.

### 10.7 Unconfirmed readings

**C49. Built 20 November 2026 ([Z_SPEC01](Z_SPEC01.md) "C49"); what stays open.**
- **A clarification-only batch's subject:** the subject is `{specification, record_kind, content}` and the
  model picks `record_kind` (`build_specification_clarification_need.zig:26-29`), so a rerun that picks
  another kind mints another form. This is true of every records clarification; the batch only reaches it
  more often. An answered group is authored by E7 (answers are not consumed yet), so until then a rerun asks
  again.
