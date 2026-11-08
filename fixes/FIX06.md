# FIX06 — Open Spec work

The only fix record: open work and user decisions not yet recorded in an ADR
([convention](README.md)). Each phase needs the user's approval before its changes, and
every live run needs its own approval. **Decision** marks a question only the user settles;
a recommendation is not a decision. Implemented items are in [Z_FIX06](Z_FIX06.md); earlier
completed, closed and reverted work is in git history (Q18's closure last at `39fd9ff`,
earlier items at `0f3e4d2`; Q20 was never committed, §3).

## 1. Gate status and output quality

**Gate (ADR 0034): not met.** Every published run since D12.2 is adjudicated (§7 H1): D12.2,
4 of 4 hello-world and 1 of 5 loan-renewal publications pass; the 12 kept-state runs since ADR
0047, 5 of 6 and 1 of 6. `zig-out/e2e-spec/` holds the retained runs of 3 November 2026 and
later (the ADR 0047 runs of 3 November, `2026-11-03T04-1*`, report v14, and every later set in
the table below, v15), each recording `build.source.modified` true;
every earlier run has been removed, and its evaluation (and measures, where taken) remain
under `evaluations/`. The current build decodes only `spec-e2e-report/v15`
(`test/harness/e2e/contracts.zig:140`), so the 3 November runs can't be adjudicated again.

**Reference** for quality phases (§2 rule 7): the 12 adjudicated kept-state runs since ADR 0047
(`2026-11-03T04-1*`, `2026-11-06T22-4*`; the reverted Q20 runs excluded), the last kept state,
from uncommitted trees (§2 rule 3's recorded exception), so it is measured but not on a
committed build. The two trees made the same requests for every call the 12 runs made: D12.3
changes only source-review and clarification requests, and none of the runs reached them.
**Previous reference:** the D12.2 set (kept 3 November 2026, [Z_FIX06](Z_FIX06.md) Q12 D12.2),
10 runs (`2026-11-02T09-15-27Z` to `09-33-46Z`, 9 published) on source `bacfcd9ae368…`
(revision `b38628c`, `modified` true; the first six summarised in
`evaluations/d122-measures-set.json`). Whether its captured inputs equal `388438e` was never
checked and can't be now (run directories removed), so it counts under rule 3 only by the
user's reading. A change proved under §2.10 moves neither kind of rule 7 reference.

**Adjudicated reference** (§7 H1; skills `af394020…` and `0b552067…`, one evaluator by the
user's decision of 7 November 2026, [Z_FIX06](Z_FIX06.md) T7; the rows scored under
`1d66d882…` join them by the decision of 8 November 2026, §3 Next item 2). Accuracy defect
counts, content basis, as lost / weakened / unsupported addition / contradiction:

| Set | Hello-world | Loan-renewal |
| --- | --- | --- |
| D12.2 (previous reference) | 4 of 4 published pass; 0 / 0 / 2 / 0 (`09-15-31Z` unpublished) | 1 of 5 pass; 4 / 1 / 11 / 0 |
| ADR 0047, 3 runs per case (`28213a7` modified; direction only, §2 rule 3) | 2 of 3 pass; 0 / 1 / 0 / 0 | 1 of 3 pass; 3 / 1 / 2 / 0 |
| ADR 0047 + D12.3, 3 runs per case (7 November, `f6ef0f6` modified, skill `0b552067…`; direction only) | 3 of 3 pass; 0 / 0 / 1 / 0 | 0 of 3 pass; 2 / 1 / 1 / 0 |
| Q20, reverted (entity-meaning purpose; 3 runs per case, 7 November, `63fb521` modified, skill `1d66d882…`; direction only) | 3 of 3 pass; 0 / 0 / 0 / 0 | 1 of 3 pass; 6 / 0 / 0 / 0 |
| One-owner hygiene, reverted (role-routed field instructions; 3 runs per case, 7 November, `014fd15` modified, skill `1d66d882…`; direction only) | 3 of 3 pass; 0 / 0 / 0 / 0 | 0 of 2 published pass, 2 of 3 published; 2 / 0 / 1 / 0 |
| E10 and principles removal (3 runs per case, 8 November, `496d754` modified, skill `1d66d882…`; no model-input change; direction only) | 2 of 2 published pass, 2 of 3 published; 0 / 0 / 1 / 0 | 1 of 2 published pass, 2 of 3 published; 0 / 1 / 1 / 0 |
| Repeated-statement text not judged (3 runs per case, 8 November, `5b34dbc` modified, skill `1d66d882…`; the exemption never fired; the reference for the entity lever; direction only) | 3 of 3 pass; 0 / 0 / 1 / 0 | 1 of 3 pass; 3 / 1 / 1 / 0 |

Pooled over the 12 kept-state runs since ADR 0047, against D12.2: 12 of 12 published (9 of 10);
hello-world 5 of 6 pass (4 of 5 runs); loan-renewal 1 of 6 pass (1 of 5); loan-renewal per run,
lost 0.83 (0.8), weakened 0.33 (0.2), unsupported addition 0.5 (2.2). Every failure since ADR
0047, the Q20 runs' included, is a repeat that loses or weakens part of a requirement (§3 open
problems).

**Output quality** (advisory scoring against the case rubrics,
`evaluations/e2e/<run>/evaluation.json`; scorer judgment moves a score about ±3.6; context
only, since keep decisions use accuracy defect counts, §2 rule 6):

| Build | Hello-world mean (range) | Loan-renewal mean (range) | Below 80% |
| --- | --- | --- | --- |
| D12.2 adjudicated (previous reference; skill `af394020…`) | 92.9 (89.3–96.4) | 82.1 (75.0–92.9) | 3 |
| ADR 0047 (6 runs, `28213a7` modified) | 91.7 (85.7–96.4) | 84.5 (75.0–92.9) | 1 |
| ADR 0047 + D12.3 (6 runs, `f6ef0f6` modified) | 91.7 (89.3–92.9) | 85.7 (82.1–89.3) | 0 |
| Q20, reverted (6 runs, `63fb521` modified) | 97.6 (92.9–100) | 85.7 (78.6–92.9) | 1 |
| One-owner hygiene, reverted (6 runs, 5 published, `014fd15` modified) | 96.4 (96.4–96.4) | 83.9 (78.6–89.3) | 1 |
| E10 and principles removal (6 runs, 4 published, `496d754` modified) | 92.9 (89.3–96.4) | 89.3 (82.1–96.4) | 0 |

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
   were kept on 12 adjudicated runs from uncommitted trees (user, 7 November 2026: "approved",
   after being told they were direction only), so ADR 0047:102's live measurement set on a
   committed build is unmet (§1 reference).
4. **Measurement set:** three runs of each development case (decided 2 November 2026), each
   approved, extended under rule 6 to at most eight per case. Every attempt counts. Nothing is
   tuned on the reserved qualification features.
   - **Screening** (decided 3 November 2026, H6.1): before a set, each call kind whose request
     the change alters (the §2.10 projection names them) is screened with paired replays of a
     retained request from each case, `e2e-call --repeats` as captured and with `--edit`
     (design/harness/e2e.md:66-91), about ten per arm, on the captured run's model and
     reasoning effort. A screen measures only the structural counts of [Z_FIX06](Z_FIX06.md)
     T6, so it can't measure a prose-only change; it decides nothing, and each replay batch
     needs approval. Its
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
     retry, Q7 D7.5) are kept on guards alone plus their
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
modes; rule 6's test on about ten events reaches p ≤ 0.10 only for changes of about four
times; with five to seven guards each at a nominal one-sided 0.10, some guard "rises" by
chance in up to about 41–52% of sets (lower under the discrete test); and the evaluator
changed between a reference and the sets compared with it.

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
research. "Gap" means between measurement sets.

**Next:**

1. Q8 D8.3 and the bare-value correction are implemented ([Z_FIX06](Z_FIX06.md)); entity
   restatement is recorded as a model limitation (§3 open problems). The bare-value
   correction is kept or reverted on a repeated set of both cases on one committed build,
   scored on published output and publication rate; sets where the correction never fires
   are not enough evidence (as for D2.3 and D4.1). It first fired live on 8 November
   (`2026-11-07T20-44-15Z-9273…`, uncommitted tree): all three records attempts returned the
   same bare `"Loan renewed!"` and `"Renewal refused."`, and the run exhausted its retries.
   The repeated-statement change ([Z_FIX06](Z_FIX06.md)) is judged on the same set: it
   removes that failure where the bare outcome is a repeat, and the correction serves the
   rest.
2. **Closed 8 November 2026** (user: "recommendations accepted for 1 to 6"): skill `1d66d882…`
   is the same evaluator as `af394020…` and `0b552067…`, and the one divergence in their
   scores is evaluator variance ([Z_FIX06](Z_FIX06.md) T7).
3. **Decided 8 November 2026** (same words): a title that repeats a requirement's value states it
   (§7 H1), so `2026-11-06T22-45-46Z-d392…`'s "…extending the due date by 14 days" is a lost
   requirement. The ruling is in the evaluate-e2e skill (a new version, Z_FIX06 T7), so §2
   rule 5 has the reference of the entity and escaping set re-scored under it first; no title
   in that reference drops a value, so its scores are expected to stay.
4. **Decided 8 November 2026** (same words): Q14 b3 stays held and b4 is not started. Lossy
   repeats caused 2 of today's 3 loan failures, which the entity and edge-case levers target; b3
   is large for a class absent from the last 3 loan runs, and b4's added restatements are the
   failure being removed. Revisit b3 after the edge-case set if refusal scenarios go missing.
5. The rest of the lossy-repeat open problem (§3 open problems): edge-case outcomes (proposed
   lever) and titles (held to their values by item 3; no lever yet).
6. **Applied, unmeasured** (8 November 2026; user: "Entity lever … is yes and approved", then
   "yes to all decisions"): an entity is a name and its groups, and the engine renders the
   statements that share a group (ADR 0038 Decision 6; §3 open problems). A set on both
   cases and `/evaluate-e2e` are still to do; each needs its own approval.
7. **Applied, unmeasured** (8 November 2026; user: "apply recommendations"): the renderer
   escapes only the bytes Markdown reads as markup (§23.1's closed table), so `spec.md` no
   longer shows `renewed\.`. No request changes (§2 rule 1), so it shares item 6's set, which
   shows the readability effect (`organization`) beside the entity lever's accuracy effect.

**Output track** (recommended order, not decided, inside the decided constraints: D17.1 puts
Q17 after D12.2, and D14.1 holds Q14 b3 (§3 Next item 4); each change set is measured on its
own committed build, §2.1 and §2.3; completed change sets are in [Z_FIX06](Z_FIX06.md)):

| Rank | Item | Defect class reduced | Effort | Validation | Decided |
| --- | --- | --- | --- | --- | --- |
| 1 | **Q14 b3** | lost source requirement: the add-a-link route of the missing refusal scenario (`728d…`; not `fa03…`'s first-attempt route, §4 Q14) | L | Measurement set | D14.1: held (§3 Next item 4) |
| 2 | **Q17** principles as records-call context | none scored; guards only unless the rubrics gain a principle criterion | M | Records screen, then a set | D17.1 |
| 3 | **Q7 D7.5** a plain string only where a field offers no insertion | rendering artefact C (joined fragments): none published since ADR 0047 composes the story; conformance only (§4 Q7) | S | Screen, then a set | D7.5 yes, a conformance fix |
| 4 | **Q4** retry, with D4.1's extension | engine vocabulary (none published; AGENTS.md compliance) | S | Screens of each changed call kind, then a set | D4.1 extension yes |
| 5 | **Q21** behaviour claims need statements | lost source requirement: a behaviour claim no statement names, passed through a whole-group selection (none since ADR 0047) | M–L, by D21.1 | Fixtures at the owner, screens of each changed call kind, then a set | D21.1 deferred |

**Robustness track** (run completion and budget; no scored defect): E5's §22.6 correction
location. D13.1 removed the review calls where every runaway and SyntaxError of 31 October
occurred and where the budget ran short. Since then the measured runs show 0 runaways and 0
re-sends; the highest used 67,448 of the 125,000-token workflow budget
(`2026-11-02T02-28-14Z`, which reached source review). Runs since ADR 0047 have failed only by
retry exhaustion, never budget:
- records, on the bare outcomes `"Loan renewed!"` and `"Renewal refused."`
  (`2026-11-07T06-12-34Z-f549…`, `07-38-56Z-2627…`, and on 8 November `2026-11-07T20-44-15Z-9273…`,
  where the bare-value correction was sent and changed nothing). Where the bare outcome is a
  wholly taken repeat (`2627…`, `9273…`) its text is no longer judged ([Z_FIX06](Z_FIX06.md));
  `f549…`'s outcome is the only non-scenario record naming its claim, so it is kept and still
  fails;
- reconcile dispositions (`2026-11-07T20-44-02Z-9d7f…`, hello-world): the model answered with
  its reasoning prose and no JSON, so `/claim_dispositions` was missing on all three attempts.
  `20-41-06Z-6197…` recovered from the same omission on its correction. The request is
  byte-identical to the pre-change `08-22-52Z` call, which succeeded: the model's variance
  under a coherent contract, reported with no lever.

The runs through 7 November used 13,363–45,309 tokens; the highest, `06-11-33Z-6897…`, spent
about 26k on five identical extraction claims (§4 Q8 D8.3).

**Engine track, in gaps:** E2 early; E3 after E2's first measure (nothing technical ties
startup to E1); E1 in any gap, retaking its freeze on the commit before it lands; E6 and E8
in any gap; E4 after E1, E2's measure and its capture replays (§5 E4); E5's closed reasons
with the E1–E4 conversion that rewrites them, its evaluator gap in any gap; E9 with E1, E4 or
E5; R-A1 after E1; E7 last. E0 is on hold. E1, E4, E5 and E9 land only under §2.12. E1–E4 before
the closing set is the user's call (ADR 0034:91-95). **Tests:** T2 and T3 in any gap; T4
with E1–E4. **Adjudication:** H1 (the evaluate-e2e skill) for every set. **Human:** H2 when
required source review is labelled or review returns; H3 when the user reviews the panels; H4
before any formal baseline freeze; H5 at the user's choice. **Closing set:** repeated runs of
both cases on one committed, unmodified build (ADR 0034:55-56) unless the user amends ADR 0034;
every counted published run adjudicated (H1).

**Open problems without an item.** Each stays until a structural lever with an owner is found
or the user records it as a model limitation.

- **Lossy repeats in entity meanings, edge-case outcomes and titles** (lost source requirement
  and weakened obligation; the adjudicated reference, §1). A field that restates a requirement
  drops or weakens part of it, which fails the requirement's criterion by the severity rulings
  (§7 H1). It fails all 4 failed D12.2 loan-renewal publications (records step, EC-001
  "fourteen days" without the new due date; entities step, `09-15-27Z-d2ee…` EN-001 without
  "calendar"), all 3 failed 3 November runs (entity meanings: "It must begin execution" without
  "successfully", `04-10-57Z`; "A borrower may renew", `04-13-31Z`; and `04-12-37Z`'s EN-001 and
  EC-001) and all 3 failed D12.3 runs (EC-001 "fourteen days", `22-43-53Z-8f8c…`, records
  step; EN-001 "Allows a borrower to renew", `22-45-22Z-c845…`, entities step; the title
  "…extending the due date by 14 days", `22-45-46Z-d392…`, brief step, the first title case,
  ruled a lost requirement by §3 Next item 3). Rewording the entity-meaning purpose alone (Q20: `business_meaning`
  read "What the business data concept is and the information it holds, without restating
  required behavior."; reverted 7 November 2026, §1) didn't stop restatement: every loan-renewal
  meaning still restated the whole behaviour, and both failed Q20 runs were lossy repeats
  (`2026-11-07T01-18-01Z-4bec…` EC-001 without "calendar" and the new due date; `01-18-32Z-ba2e…`
  EC-001, the title, and EN-001 without "leave its due date unchanged"); loan-renewal lost
  requirements rose to 2 per run. Routing the field instructions by role didn't stop it
  either (one-owner hygiene change, reverted 7 November 2026, §1; record in
  `evaluations/e2e/2026-11-07T06-1*`): entity meanings, titles and goals no longer received
  "Type required exact values verbatim" or the obligation clause (`packet-guidance/v4`
  `field_roles.obligation_bearing`), and the no-invention instruction had one owner. Weakened
  obligations fell to 0, but both published loan-renewal runs still failed
  `successful-renewal` on "fourteen days" without "calendar": `06-11-33Z-6897…` in EN-001's
  meaning, `06-14-18Z-7e23…` in its relationship after the meaning stopped restating; and
  `06-12-34Z-f549…` published nothing (three `reference_only` rejections of the user-visible
  outcome "Loan renewed!", link to the change speculative). Hello-world stopped publishing an
  unneeded entity (0 of 3, against 3 of 3 in the D12.3 set). So neither Q20 nor the one-owner
  hygiene change achieved the desired outcome: the model restates the requirement in whichever
  entity field is open. **Recorded as a model limitation** (user, 7 November 2026: "record as
  a model limitation"; AGENTS.md "Model output, prompts and evidence"): entity fields that
  restate a requirement and lose or weaken part of it, observed with Bedrock
  `openai.gpt-oss-20b-1:0` (`ap-southeast-2`, the only model used in every live run, §7 H5).
  Runs that show it still fail their criterion; nothing is weakened, and no further prompt
  change targets it. **Lever applied** (8 November 2026, §3 Next item 6; ADR 0038 Decision
  6): the structural lever the limitation allowed. An entity holds its name and its groups;
  the free-text `business_meaning` and relationships are gone, and the engine renders the
  statements that share a group as a related-statements line, so no free-text field but the
  name remains for the model to restate in. Measurement is pending. Still open: edge-case
  outcomes (purpose
  `packet-guidance.json:26`) and titles (purpose `:4`); a lever with an owner or a recorded
  model limitation. **Not accepted** (user, 7 November 2026: "that is a poor idea and I will
  not accept it"): the engine filling `then` and `expected_outcome` from the record's cited
  source lines, since the result restates the Given and reads as requirements, not observed
  outcomes. **Proposed lever, edge-case outcomes** (8 November 2026): an edge case keeps its
  condition and claims, and its outcome becomes a link to an acceptance criterion whose Then
  text the engine prints. The user decided that day that the 7 November rejection concerned
  only filling from source lines, so the copy is allowed with acceptance criteria as the only
  targets, and that a model step after records names the criterion (not response position).
  Design accepted on "apply recommendations" and "recommendations accepted for 1 to 6" (8
  November 2026), revised by the authority lookup: links stay inside the
  edge case's own records batch; the engine computes each edge case's candidates (criteria
  sharing a claim with it), links natively when exactly one, asks the model one closed choice
  per edge case with two or more (the shared result-schema mechanism has one allowed list per
  path), and fails the run with a typed reason when none, since the alternatives delete a
  scenario (ADR 0038:97) or add a second coverage rule; a printed outcome is a derived
  display. Needs a session unit and progress outcome, `specification/v5`, state v24 (ADR 0041
  moves to v25), `packet-guidance/v5`, required-authority 4, and amends ADR 0047, §17.3, §23.1
  and F0100 §5. A new call kind has no retained request to screen (§2 rule 4). Implementation
  waits for the item 6 and 7 set, then its own.
- **Unsupported additions in AC wording and entity meanings** (the story's ended with ADR
  0047). AC-001's recording of the renewal (4 of 5 D12.2, 2 of 3 ADR 0047, 1 of 3 D12.3 and 0
  of 3 Q20 loan-renewal publications) is ruled a minor addition (§7 H1) and has no structural
  lever; the `given` purpose forbids invented prerequisites (`packet-guidance.json:22`), the
  `when` purpose (`:23`) doesn't. An entity meaning carried the brief's invented goal once ("to
  confirm it is running correctly", hello-world `22-42-00Z-6422…`; the brief reaches the
  entities request, D12.1), a watch item. Q12's leftover restatements
  (`generation.prompt.md:2`, `packet-guidance.json:26`) and the three no-invention texts
  (`packet-guidance.json:22`, `records.prompt.md:8`, `generation.context.json:4`) stay as they
  are after the one-owner hygiene change's revert. Report the remaining AC elaboration as a
  model limitation (AGENTS.md) and let H1 judge it.
- **Repair requests without step guidance:** six repair sites take their task only from the
  three-line `repair.prompt.md` (`spec.workflow.yaml:361`, `:398`, `:595`, `:750`, `:827`,
  `:842`), and the two reconciliation repairs among them (`:595`, `:842`) bind no context.
  Binding definitions (Q2) wasn't kept; counted as a brittleness measure (T5).
- **Provider doesn't enforce the response schema:** the engine's request matches AWS's
  documented Converse shape (`outputConfig.textFormat` json_schema,
  `src/adapters/provider/bedrock_request.zig:74-77`), and the gpt-oss-20b model card lists
  structured outputs as supported. Yet Bedrock's raw text block (not engine extraction,
  `bedrock_response.zig:135-149`) opens with a fragment and restarts the JSON in 198 of 205
  responses in the D12.1, D16.1 and D16.2 runs, and two 31 October answers ended `end_turn`
  inside an open string, which a grammar enforced from the first token to the stop can't
  produce. Open: whether Bedrock applies the grammar partly or not at all. **Decided 1
  November 2026:** §22.6 normalization (of the malformed opening) is recorded as a provider
  defect; ADR 0039:67-72 now records it, with the Bedrock request IDs, in place of its former
  "schema-constrained decoding" premise. The live comparison (one
  retained request with and without native JSON mode) is deferred: it needs an `e2e-call`
  change (it keeps the captured response mode, design/harness/e2e.md:114-115) and approval.
  Since D13.1 the prefix caused two faults, both extract-classifications call 2
  (`2026-11-01T08-24-09Z-46f4…`, `2026-11-07T01-19-36Z-728d…`): the JSON restarted and never
  closed (`UnexpectedEndOfInput`, each corrected by the next call). No model or provider change
  (H5).

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

The first attempt was reverted on 31 October 2026: with the second `citations` sentence
(`extraction.context.json:14`) removed, hello-world's first extraction returned
`no_feature_claim` in 5 of 6 runs (`evaluations/q4/measures-set.json`; its record is
`fixes/Z_FIX06.md` at git `194e29a`). 12-model-boundary.md:380-381 and ADR 0016:155-156 say
FIX06 Q4 removes them, so the retry keeps the ID. No published spec from 29 to 31 October
contains engine vocabulary (0 in the 18), so this is AGENTS.md compliance, not an output
target.

**D4.1's extension** (D4.1 in [Z_FIX06](Z_FIX06.md); decided 3 November 2026): the rule covers
native rule and correction texts too, and a sentence that says what a field, claim or response
contains stays even when the engine enforces or transforms it.

**Scope still model-visible:** `support.prompt.md:28-29` (bound for pre-generation source
review); `packet-guidance.json:62`; `reconciliation-dispositions.prompt.md:2-4`;
`extraction-classifications.prompt.md:2-5`; `records.prompt.md:4-5`;
`support-loss.prompt.md:22`; the "native code …" texts in
`src/domain/reference_reconciliation_diagnostic.zig` (lines 101, 106, 119, 122, 124, 132, 134),
which reach requests through `descriptionFor` (`reference_model_input.zig:297`);
`src/domain/typed_text.zig:156` (no projected request carries it, but
`specification_repair.zig:81` can send it). Reword engine vocabulary in place; remove a restated rule only when the
schema or its correction states all of it; keep task semantics the engine doesn't check (both
`citations` sentences and the `claim_ids` definition). `records.prompt.md:9-13` states the
coverage rule and an "at most one record" rule (ADR 0038 Decisions 2 and 5); the engine checks
the second only for non-requirement statements (ADR 0038:103-106), and the sentence is kept as
written on purpose (:111-112). It stays as their only carrier on a first attempt, since the
provider schema can't express them.

**Validation:** projection shows only the listed texts change; scripted missing and repeated
members get the `array_length` and `duplicate_member` corrections; then a set, with the
extraction requests screened first (§2 rule 4; the first attempt broke hello-world
extraction). **Keep if** engine vocabulary stays absent and no guard blocks (§2 rule 6);
corrections, rejections, defect classes and cost are watch items. Never rename a field to
chase a leak.

### Q7. Exact values

**Defect:** rendering artefact, counted from the published bytes in 18 of 18 publications of
31 October (D2.3 and Q10b) and 15 of 15 in the D12.1, D16.1 and D16.2 sets:

- **A. Doubled delimiter** (70 occurrences in the 18 publications of 31 October). ADR 0036
  Decision 6 removes only backtick runs around a value (`exact_value_recognition.zig:137-152`);
  the model's `"` stays in the neighbouring text, and the projection gives an exact copy its
  own code span (`specification_projection.zig:152-168`) unless D7.4's exception applies
  (`delimitedByText`, `:174-185`), which excludes a value ending in terminal punctuation and so
  every development-case value. Where the span stays, the doubling is the engine's. Since ADR
  0047 the story shows one engine span; A remains in model-written FR and AC fields
  (`2026-11-07T01-18-32Z-dd03…`, `01-19-36Z-728d…`).
- **B. Plain value in an entity meaning** (20 in 14 publications of 31 October): ended on
  8 November 2026, when the entity lost its meaning (ADR 0038 Decision 6). ADR 0045, which
  would have shown them as code spans, was withdrawn (D7.2, [Z_FIX06](Z_FIX06.md)).
- **C. Fragments joined without a separator** (1 of 18 publications of 31 October; 2 of 5
  D12.2 loan-renewal stories): the schema keeps the fragments option when no reference is
  offered, and fragments join with no separator (`model_candidate_json.zig:251-253`). D7.5
  owns it.

- **D7.4** (implemented, [Z_FIX06](Z_FIX06.md)): decided 1 November 2026, D7.4 is not a
  punctuation rule (AGENTS.md "Prose heuristic").
- **D7.5** (decided 3 November 2026: yes, a conformance fix with no contract amendment, since
  07-domain-representations.md:74-79, ADR 0006:302-316, 12-model-boundary.md:196-198 and
  text-field-composition.md:21-22 already reserve fragments for composition around typed
  insertions): where a field offers no inserted reference, its schema offers only the plain
  string (`model_text_field.zig:174-190`; `textContract`, `model_text_wire.zig:277-292`). Schema
  bytes change in every generation request (0 passive literals in the retained runs), so a
  screen, then a set. Admission validates the response against the schema the model receives
  (`admit_model_response.zig:19-21`) before the codec runs
  (`model_candidate_handoff.zig:24-32`), so a fragments object against a plain-string field
  fails as `type_mismatch` with a protocol correction. Effort S: `walk` in
  `model_text_field.zig` and its tests; `generation.context.json:2` still describes
  fragments. Every fragments object seen in a
  published field was a story, which ADR 0047 composes natively; since then one appeared in a
  reconciliation signal (`2026-11-03T04-13-31Z-fa03…` call 5, unpublished). So D7.5 is a
  hygiene phase (§2 rule 6). **Keep if** no fragments object appears where no reference is
  offered and no guard blocks; admission rejections, protocol corrections, runaways,
  unsupported addition and restating entity are watch items.
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

**Defect:** restatement and claims lost in reconciliation when citations repeat. The list-item
split (`reference_extraction_text.zig:144-183`) fired in 13 of 40 first extractions and gave
the same claims as per-item citations; no current-build run repeated a citation set (on Q4's
reverted build loan-renewal repeated `[5,6,7,8,9]` and failed three times). ADR 0036 Decision
3 and ADR 0038 Decision 4 (the list-item split) stay as they are (D8.1, decided 3 November
2026).

- **D8.2** Whether "cites in full" (ADR 0036:116-120) covers a fenced block whose first or last
  interior line is blank (`markdown_code_spans.zig:53`, `:59`;
  `exact_token_obligation.zig:40-45`; `source_selections.zig:57-60`). No fixture covers it.
- **D8.3** decided and implemented 7 November 2026 ([Z_FIX06](Z_FIX06.md); ADR 0036
  Decisions 3 and 4 amended). Every offline request is byte-identical, so no regression is
  shown offline; semantic benefit is not demonstrated: none of the eight live runs of
  7 November (`2026-11-07T07-3*`) duplicated an extraction claim.

D8.2 is decided offline with fixtures at its owners and §2.10 projections, in any gap, or
recorded.

### Q13. Inline source lines

D13.1 (post-generation reviews removed) and the inline source lines are in
[Z_FIX06](Z_FIX06.md). Reopen link checks, in shadow mode, only if adjudication shows semantic
defects that the generation-side items (Q14, ADR 0047) leave; ADR 0047's part is met (lossy
repeats remain, §1), and Q14 hasn't landed. Reopening is a **Decision**: it amends ADR
0023's Decision (:46, :60-62) and its removal amendment (:25-42), and the harness makes no
judge call (AGENTS.md). **Proposed shape** (8 November 2026): each check asks one question of
one generated value against its fixed claims, returns a structured finding with evidence,
edits and decides nothing, and is labelled under H2's scheme (SKILL.md §7). Against it: the
26 October source review, on the same model, caught 1 of 28 defects by the assistant's
unconfirmed labels (`evaluations/b2-review-accuracy/2026-10-26/summary.md`), and a reliable
finding drives no repair unless ADR 0023:51-53 is also amended.
**D13.4** (decided 1
November 2026): principles are context and constraints only, never origins, and never modified
(Q17). Nothing checks what a shown source line means beyond the advisory evaluate-e2e link
check. Open:

- **Clarification question lines disagree.** `clarification_preparation.zig:32` prints
  `lines {start}–{end.line}`, so a citation of line 5 reads "lines 5–6" there and "line 5" in
  `spec.md`. Fix: use `source_coordinates.lines`. It changes clarification form bytes; no
  development case reaches a clarification today.
- **D13.7 (decision, needed only when Plan's editable reparse is built; ADR 0034 gates it):**
  what a hand-edited or stale source line does at the plan boundary. 23-rendering.md §23.1
  (:133-137) says readback compares it with the derived line, but not what a mismatch does.
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
  choice (for example records' `claim_ids`, `specification_session.zig:408`). A non-existent
  ID fails response admission as `enum_mismatch` (`model_payload_schema.zig:167`) and gets a
  protocol correction within the step's retry limit. No such correction has fired in any
  measured run (31 October onward).
- **Gap, the guidance:** the correction says only "this value is not among the allowed
  values" (`model_schema_diagnostic.zig:34`), and its expected shape for an ID choice is
  `{"type":"integer"}` (`model_schema_projection.zig:75-79`). It names neither the rejected
  ID nor the IDs that exist; the rejected response travels with the correction
  (`model_protocol_retry.zig:96`).
- **Change (approval needed to implement):** the `enum_mismatch` correction for an ID choice
  names the rejected value and lists the allowed IDs, both taken from the compiled choice,
  never hard-coded (D4.1's precedent for `uncovered_member`). It amends 22-repair.md:575-576,
  which keeps the allowed-ID list out of an integer-enum outline, and :571-572 ("no other
  correction changes"). It changes model-visible correction text only; first requests stay
  byte-identical (§2.10). Proven offline: a scripted non-existent claim gets the named
  correction and an accepted retry. A set can't measure it, since it hasn't fired live.

### Q14. Scenarios bound to their claims

**Defect:** lost source requirement: no scenario tests refusal in loan-renewal 3 of 9
publications of 31 October, none from D12.1 through D12.2, and 2 of 9 since ADR 0047:
`2026-11-03T04-13-31Z-fa03…` (scored no defect under skill `af394020…`) and
`2026-11-07T01-19-36Z-728d…` (scored `lost_source_requirement` under `1d66d882…`; on the Q20
build, but its records request carries no Q20 text). In both, one FR named every claim and the
success-only AC-001 cited the refusal lines. Coverage (ADR 0038 Decision 2;
`specification_session.zig:343-349`) covers FR, BR, UO and PB claims and checks links, not
meaning (ADR 0038:119-121), so an AC naming every claim passes it: `fa03…` passed on its first
attempt with no `uncovered_member` firing, a route b3 doesn't close. No retained
`uncovered_member` firing ended well: two Q1b runs exhausted the records retry limit (2,
`spec.workflow.yaml:722`), and three runs passed by adding the claim IDs to the success-only
AC-001 (`07-35-27Z-0669…` and `07-37-18Z-61b3…` on 31 October; `728d…`, whose call 12 repeated
call 11 before call 13 added claims 4 and 5). The advisory evaluate-e2e link check can't record
over-citation, so `728d…`'s AC-001, which names refusal claims it doesn't test, is labelled
`supported`.

- **b3 (D14.1):** a claim-bound scenario insert: the engine fixes the new record's
  `claim_ids` to the uncovered claim and the model writes only its content, closing the
  add-a-link escape. Effort L, using today's repair loop (`spec.workflow.yaml:739-764`); E4 is
  not a prerequisite.
  - Coverage must move from payload admission (`model_payload_schema.zig:205-217`, behind
    `shared_member` at `:200-204`, where no typed candidate exists and only a whole-response
    retry is possible) into the unit validator beside entity membership
    (`specification_generation.zig:248-265`).
  - Insert repair exists today only for entity membership (`specification_repair.zig:50-67`,
    `:128-141`, `:374-378`, `:469-478`). The record gates at `:254`, `:376` and `:470` lift; a
    group policy for a fixed claim is added (`GroupPolicy` has only `.membership`,
    `specification_candidate.zig:141-143`); the record repair definition stops being only
    `repair_record_entity` (`specification_repair.zig:271`); and the unused content-only
    `repair_record_acceptance_criterion` schema (`generation.schema.json:489-500`) gains an
    edge-case counterpart.
  - A compiled coverage rule needs covering kinds (`model_result_schema.zig:210`), so keeping
    `shared_member` at admission without `uncovered_member` changes the result-schema rule
    contract.
  - ADR 0038 Decision 1 already says repairs stay content-only and keep the record's claims
    (0038:63-64). Deletes the admission-time coverage check (`uncovered_member`) and D4.1's
    covering-kinds correction; D16.2's partly taken statement (`shared_member`) stays at
    admission and its repeated statement a native delete.
  - Amends ADR 0038 Decision 3 (:72-80, :160-162) and :98-100, :137-139;
    22-repair.md:268-272, :563-568 and :809-811; 12-model-boundary.md:105 and :870-872;
    17-specify.md:200-203; F0100:1224-1227 and :1402-1407.
  - An inserted scenario still links without checking meaning.
- **b4** (proposed 8 November 2026; not started, §3 Next item 4): claim-bound scenarios at first generation
  too: the engine fixes each scenario's `claim_ids` before the model writes it, closing
  `fa03…`'s first-attempt route that b3 leaves. Slots can come only from IDs, so a slot per
  claim needs the statements first (a second records call per group) or D21.1's unit (§4
  Q21). Risk: each added scenario is another restatement that can lose part of its claim, the
  cause of every failure since ADR 0047 (§1). Amends ADR 0038 Decisions 1–3 beyond b3's.
- **b2** (not chosen): the scenarios naming a claim must together contain every exact value
  its quoted text requires; it misses claim 4 and business-rule-only cases.

**D14.1 decided 1 November 2026:** b3, not b2. **Re-decided 3 November 2026:** b3 is held
until lost source requirement recurs, since the class is absent since D12.1 and a set could
show only "benefit not demonstrated" (§2 rule 6). When it recurs, b3 goes ahead as described.
The condition is met under both readings: as Q14's class (no scenario tests refusal) it
recurred in `fa03…` and `728d…` (2 in about 21 loan-renewal publications since D12.1, so a
three-run set may still show only "benefit not demonstrated"); as any lost source
requirement, the lossy repeats since D12.2 (§1) meet it. **Held** (8 November 2026, §3 Next
item 4): b3 stays held and b4 is not started. **Keep if** lost source requirement falls and
publication and exhausted runs don't worsen.

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
  reads them (`spec.workflow.yaml:42-44`). Adding them changes generation requests, so it is a
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
  publication) unless the case rubrics gain a criterion. Amends ADR 0015 (0015:10-14 already
  names D17.1), ADR 0023 "Principles" (0023:149-159), 17-specify.md's generation inputs
  (:257-299) and F0100.
- **Sequence (recommended, not decided; D17.1 places it after D12.2):** a records screen
  first: the loan-renewal rubric's
  proportionate-scope criterion penalises principle-derived prescriptions, so its guards need
  a settled reference.

### Q21. Behaviour claims need statements

**Defect:** lost source requirement: a behaviour claim that no statement or scenario names
passes coverage, because the brief fields, entity basis and composed story select whole
groups and a claim maps through any field holding it (`specification_coverage.zig:52-61`,
`:74`). In a one-group feature, as both development cases are, ADR 0038 Decision 2's scenario
rule never reaches an unnamed claim (ADR 0038:130-132; pinned at
`specification_generation_test.zig:8961-8964`). No failure since ADR 0047 is of this kind
(§1), so a set may show only "benefit not demonstrated".

**Proposed 8 November 2026** (not decided): a narrative selection gives traceability only;
every obligation-bearing claim must be named by a behaviour statement (FR, BR, UO or PB),
whose claims then need a scenario. A coverage gap blocks with no repair today
(`specification_coverage_repair.zig:26-30`), so it needs a correction at records admission
(ADR 0038 Decision 3) or a claim-bound insert (b3, §4 Q14), or silent passes become blocked
runs. Owner: `Coverage` (`model_result_schema.zig:56`) and `specification_coverage.zig`;
amends ADR 0038 Decision 2 and :125-132, 17-specify.md §17.5 and F0100.

**D21.1 (Decision):** which claims bear obligations: (a) every `business` claim, which
includes feature identity and purpose (`extraction.context.json:6`); (b) a new obligation
category in extraction (`:5-13`), changing extraction requests; (c) a bounded model
decomposition into source-span elements, the only option that separates a compound claim such
as loan-renewal's four-part refusal item (`stories.md:9`, ADR 0038:117-118), at the cost of a
model step whose losses nothing native detects. Treating shared source evidence as no
redundancy is not adopted: it would reverse ADR 0038 Decision 5 (user, 2 November 2026).

**D21.1 deferred** (8 November 2026; user: "recommendations accepted for 1 to 6"): no failure of
this kind has occurred since ADR 0047, so a set could show only "benefit not demonstrated", and
each option risks accuracy: (a) false blocks on identity claims, (b) a change to every
extraction request, (c) losses nothing native detects. If it resumes, take (b).

**Next:** D21.1 (deferred); fixtures at the owner (an unnamed claim, or one named only by an
assumption, non-goal or scenario, rejects), then screens and a set (§2 rules 4 and 6).

## 5. Engine track (E)

Each item: `/preflight`, offline tests, the §2.10 proof, `zig build verify`, one live run
per case (DE2–DE4 ask whether offline evidence replaces it), landing between sets and under
§2.12.

### E0. Failed and blocked runs publish validated content (B10, ADR 0041)

On hold since 30 October 2026 (ADR 0041:3-4). Nothing under `src/` names `failure-output`,
`spec_incomplete` or `run.incomplete_published`. To resume: implement ADR 0041 Decisions 1–8,
taking `specification-state/v24` (v23 is current, `specification_state.zig:8`; ADR 0041:5-10,
:42, :225); align the measures (`test/harness/e2e/measures.zig:207`, test `:739-742`;
e2e.md:681-684), design.md:208, 24-workflow-state.md:74, 25-publication.md:41-45, F0100:1171
and `test/harness/e2e/contracts.zig:209-212` with Decision 7.1 (an `invalid` run stays
`invalid` and may publish), and F0100:1165 with Decision 7.8 (the title precedes the status
line); add a test that a pre-E0 v15 report still decodes; flip every scenario asserting no
publication after an eligible failure (for example
`test/integration/workflow_tests.zig:2440`, `:2257-2265`, `:1724-1727`, `:1938-1939`;
`test/harness/integration/tests.zig:1741-1742`, `:1763-1772`), including ADR 0047's
`no_story_requirements` and `story_not_admissible` blocks, which no scenario covers; register
`run.incomplete_published` through `adrRequired` (`src/domain/log_event_registry.zig:99-105`,
test `:162-168`). If ADR 0041 is withdrawn, v15's `incomplete_publication` (e2e.md:355-356)
and the measures' `incomplete` value become dead code needing a report version.
Budget-stopped runs publish nothing while it is on hold (none since D13.1).

### E1. Engine-owned model request (A1, ADR 0030 slice 4)

Not started: the `request-model` step replacing `model-request-body`
(`spec.workflow.yaml:942-998`) and its five wrappers (`:868-941`), with the contract-variant
mechanism ADR 0033 reuses. It folds in ADR 0039's re-send and retires `validateRunawayRoutes`
(`src/domain/workflow_model_request_lifecycle.zig:86`). Retake the slice 1 freeze on the commit
before it lands (slices 1 and 4: git `194e29a:fixes/Z_FIX05.md:2794`, `:4430`). Slice 1 review
points: make `extract/content` and `extract/content-request` (`spec.workflow.yaml:311-323`) one
step; port each runner-level lifecycle test in `src/model_request_workflow_test.zig` one for one
with a mapping table and a reason for any dropped assertion (user decision, 23 October 2026,
option b). If E1 removes a request-lifecycle `DataKey`, it lands under §2.12.

### E2. Stage actions (A2, ADR 0031)

Not started: convert `prepare-toolchain` (`spec.workflow.yaml:172-201`) first and record ADR
0031's measures (:355-357) before another stage. **DE2:** confirm ADR 0031's derived choices
1–3 and 6–8 (:268-290), including whether choice 7's offline evidence replaces the live run.

### E3. Engine routines (A3, ADR 0032)

Not started. Convert startup first and measure it (ADR 0032:144-151). Feature logging waits on
its preconditions (:152-172): no test covers cancellation under a log lock, and the
policy-transition coordinator waits on E6's §14.10 decision. **DE3:** confirm ADR 0032's
derived choices 1–8 (:224-241), including offline evidence; can be asked with DE2.

### E4. Generic repair operations (W3, ADR 0033)

After E1, E2's measure and its capture replays (ADR 0033:261), which must be
`model-request-debug/v16` captures (`model_request_description.zig:5-10`; earlier captures no
longer decode): all Specify owners in one change on
offline equivalence evidence; the 29 operations and 13 owners of ADR 0033:87-103 still match
(10 authorize, 6 build, 6 parse, 7 merge). Seven operations read `.packet_guidance`; their
variants keep those reads. Retained reports carry repair keys, so it lands under §2.12.
**DE4:** confirm ADR 0033's derived choices 2–8 (:273-285; choice 6 is moot since D13.1,
:280-281). Q14 b3 extends the specification-unit repair route these operations replace; E4
isn't its prerequisite (§4 Q14).

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
  §22.6 requires (22-repair.md:519-520). Fixing it amends §22.6 and changes correction
  requests; one of the four corrections ran away. None has occurred since D13.1:
  `2026-11-07T01-19-36Z-728d…`'s `UnexpectedEndOfInput` correction named the true end of input
  (byte 362).

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
  change; it affects no model request.
- **Prior-run crash finalization** (§14.10) is blocked on a persisted bootstrap authority that
  doesn't exist (14-orchestration.md:323-327), so a crashed run's logs are kept whole and
  damaged prior logs block later runs until someone repairs or removes them. **Decision:**
  which persisted authority supplies the historical policy lineage (§14.10; ADR 0032:310-311,
  "Not decided here"). E3's feature-logging conversion waits on it.
- **Redaction policy ID:** 26-security.md:195 and F0002:539 name `redaction/default-v1`, which
  no code carries. **Decision:** a record carries the ID (a new field, so `feature-log/v3`;
  v2 is current, `feature_log_limits.zig:1`), or both documents drop it. **Recommended:** drop it.
- **Producerless rejection** (fixed, [Z_FIX06](Z_FIX06.md)), still open: contract 27
  (27-observability.md:44-47) names only coverage as an assembled-candidate example (design
  edit awaiting approval: add `producerless` as a second example); `observation.capture`'s
  candidate arm (`test/harness/e2e/observation.zig:131-132`) has no direct test. **Decision**
  (optional): a first-generation omission names its chunk's classification producer.
  **Recommended:** no.

### E7. Clarification answer recovery (R2, ADR 0025)

Not started; no §13 authentication chain exists in `src/`. Fresh answers can't complete
recovery: refresh rejects new submissions (`clarification_refresh.zig:65`); provenance
rejects nonempty response-ID sets (`specification_provenance.zig:88`,
`specification_support_evidence.zig:170`); form validation returns one
`InvalidClarificationInput` (`src/actions/clarification/validate_clarification_forms.zig`);
resolved needs are empty (`src/actions/clarification/build_resolved_clarification_needs.zig`);
passive literal origins are source-only (`passive_literals.zig:16`), so answer text can't get
ADR 0025's response-owned origin (0025:70-71); generation doesn't consume answers
(`specification_source_binding.zig:129`, `:181`). Complete the
[§17.4 lifecycle](../design/contracts/17-specify.md#174-specification-clarification-behavior)
under ADR 0025. Live validation needs a user-chosen clarification-expected case run twice with
forms answered between runs; neither the case nor a two-run harness flow exists. Last, after
E1–E4.

### E8. Typed schema-definition identities

Domain code names result-schema definitions by raw strings: T5.2 counted 20 production sites
on the `b38628c` tree (`zig-out/code-heuristics/report.json`, 2 November, as on the D13.1 tree;
baseline 22 in [Z_FIX06](Z_FIX06.md) T5), and ADR 0047 removed the story's. They fail only at
request preparation (`model_request_handoff.zig`; sites in `specification_support.zig`,
`specification_support_repair.zig`, `specification_session.zig`, `specification_repair.zig`,
`reference_model_input.zig` and the reference reconciliation and extraction-repair files).
Bind them as closed IDs checked at schema load. Test fixtures branch on names too
(`spec_generation_driver.zig`, `spec_generation_responses.zig`).

### E9. Superseded exact-handle correction

`ValueChoices.correction`'s `unknown_exact` arm (`specification_provenance.zig:177-180`) corrects
a model-authored exact handle that models can't author since `dfae959` (ADR 0020:233).
`ValueChoices.permits` (`:167-169`) has no caller. Delete the arm, `permits`, the
`rejected_exact` member (`typed_text.zig:144`), its assignments (`typed_text.zig:245`,
`specification_provenance.zig:426-433`) and the assertions that read it
(`typed_text_test.zig:32`, `specification_generation_test.zig:6907`,
`packet_guidance_test.zig:205`); the `unknown_exact` rejection stays. No freeze under
`evaluations/request-projection/` carries `rejected_exact`, and the only report that did (the failed
`2026-10-31T03-01-37Z-7c6a…`) is no longer retained. Lands with E1, E4 or E5.

## 6. Test track (T)

### T2. Test decoupling

Tests copy model-facing English or check its absence: about 32 lines of 25 or more characters
in 7 files (2 November 2026). Compare with the owning constant or resource instead: copies in
`model_request_workflow_test.zig`, `model_payload_schema_test.zig` (and its `:362-367` phrase
checks on `protocol.prompt.md`), `reference_model_input_test.zig`,
`test_fixtures/spec_generation_driver.zig`, `model_text_field_test.zig`,
`reference_reconciliation_test.zig`, `specification_generation_test.zig:8123`; absence checks
at `model_text_field_test.zig:177` and `model_request_workflow_test.zig:4529`. Rename tests,
fixtures and `measurement_prefix` dumps named after live runs: dumps r35, r36, r37, r40, r41
and fix002 (`workflow_tests.zig:1556-1636`); tests R36 (`model_envelope_test.zig:381`), R42
(`specification_generation_test.zig:6511`), FIX002 (`:6673`, `:6730`) and D1
(`model_candidate_json_test.zig:285`); fixture headers R35 and R36
(`summary_protocol_sequence.zig:1`, `global_protocol_sequence.zig:1`); and
`build/test_run_inputs.zig:22`, `:33-40`, deleting its orphaned `d1-review`, `r42-recovery`
and `r43-recovery` entries (`:20`, `:39`, `:40`; its test at `:145` uses `d1-review` as an
example). The never-run insertion-presentation panel with its `attribution-replay` tooling
was deleted on 8 November 2026 (user: "Yes, retire both"): its hash-pinned records request
listed the entity fields that ADR 0038 Decision 6 removed.

### T3. Coverage gaps (B5, B7)

- No integration scenario reaches ADR 0035's story `restatement`; unit coverage only.
  D16.2's `repeated_statement` has one (`workflow_tests.zig:1345-1348`, `:2234-2239`).
- The no-feature-claim text-repair route (`spec.workflow.yaml:350-371`) has unit coverage only;
  the integration `.unbound` mode ends `.invalid` before it.
- The retained GPT-OSS compatibility exchange is assessed `incompatible` since ADR 0036
  (`provider_compatibility_tests.zig:261-262`, `:305-309`), so the normal §22.6-normalized path
  has no compatible-assessment coverage.
- Proof limits recorded at implementation ([Z_FIX06](Z_FIX06.md)): no scripted scenario
  quotes an exact copy, so D7.4's freeze doesn't reach its path; Q13's two-source citations
  are covered at the codec, not the projection (the fixture reads one file); every scripted
  records batch has one claim, so D16.2's partly taken record is proven only at admission.
  A scripted multi-claim batch needs a per-group generator, since the baseline one names one
  claim per record (`spec_generation_responses.zig:769`); the scripted edge case waits for the
  edge-case lever's record shape (§3 open problems).

### T4. Architecture rules and replay (A5)

When E1–E4 remove files pinned by architecture tests, write the replacements as import-graph
and contract-shape rules (ADR 0030:464-468, 0031:337-353, 0032:291-303, 0033:338-341), not
per-file pins (about 70 of the 78 tests pin files). Prefer replaying retained captures over
extending `spec_generation_responses.zig`.

### T5. Brittleness counts

Baseline, definitions and decisions: [Z_FIX06](Z_FIX06.md). Each change set that a phase
reports on retakes them on its committed build: `zig build code-heuristics -- --freeze <dir>`
with the freeze §2.10 takes on that build, and T5.4 by hand from `spec.workflow.yaml` (a
`slot: repair` step whose prompt no non-repair step binds). Last taken 2 November 2026 on the
`b38628c` tree (the kept D12.1 + D16.2 change set; the D12.2 tree with freeze `b38628c-d122`
gives the same counts) with freeze `evaluations/request-projection/b38628c` (130 scenarios,
1,714 calls): T5.1 19, T5.2 20 (tests 88), T5.3 5 instructions at 11 sites, T5.4 6, T5.5 0,
T5.6 13 in 4 files. **Due:** not retaken for the kept ADR 0047 and D12.3 change set
(`f6ef0f6`, `39fd9ff`), whose freeze is `evaluations/request-projection/entity-meaning-before`
(130 scenarios, 1,592 calls); ADR 0047 deleted the story prompt and the story's
packet-guidance purpose, so T5.2 and T5.3 may change. T5.4 is still 6
(`spec.workflow.yaml:361`, `:398`, `:595`, `:750`, `:827`, `:842`, each binding
`repair-prompt`).

### T8. Report repairs cover every unit

**Defect (measurement):** `report.json` `repairs` keeps only the last merge of each candidate
still retained at run end (F0100 "These are retained merge snapshots"), so `e2e-measures` and
the evaluation miss earlier merges in a unit and every merge of an earlier unit. Native
`repeated_statement` deletes in `events.jsonl` against the report: `2026-11-03T04-12-37Z-6666…`
seven (revisions 1→2 to 7→8), one listed; `2026-11-06T22-45-22Z-c845…` two, one listed;
`2026-11-06T22-45-46Z-d392…` two (its records call ran in two units), none listed. §2 rule 5
grades every repair, and the harmful repair watch item depends on it. **Next:** the report
lists every merge in merge order (a report version, §2 rule 12); until then e2e.md states the
limit. Each `Merge` already carries its `operation` and `origin` (`atomic_repair.zig:35`,
`:39`).

## 7. Human and decision track (H)

### H1. Adjudication (R8)

**Decided 3 November 2026** (user: "yes", to "should the evaluator's rubric scores decide
acceptance instead of your record?"): the `/evaluate-e2e` skill writes each published run's
`spec-adjudication-record/v1` (renamed from `human-spec-adjudication/v2`, user: "can be
renamed") from its rubric scores and applies it with `zig build adjudicate-spec` (AGENTS.md
"Testing expectations"; ADR 0034 and design/harness/acceptance.md amended). It replaces the
user-scored five-run H1 and its comparison rule. Only the user triggers or approves the skill
(user, 3 November 2026: "must be trigger manually by the use[r]"; 7 November 2026: "you can
start /evaluate-e2e if I give approval"; AGENTS.md states the rule); `/live-e2e` doesn't run
it.

**Decided 3 November 2026** (user: "YES", "YES approved"): a run's first adjudication under a
skill version counts (R8, design/harness/acceptance.md). The D12.2 adjudication and the v15
report change are done ([Z_FIX06](Z_FIX06.md) H1); results in §1.

**Open:** `09-15-27Z-d2ee…`'s applied decision reads `admission_evidence_invalid`, from a
harness bug since fixed; its record scores `critical_failed`, which §1 counts. Its v14 report
survives only as `evaluations/adjudications/adjudication-7c50a2ef…/original-report.json`, so
correcting the applied decision needs the build that made it and the user's decision under
R8's first-adjudication rule.

**Rulings, 3 November 2026** (user, on the evaluator's classes and scores; not adjudication
records). The evaluate-e2e skill carries each as a scoring rule (SKILL.md §2, under the class
table); every evaluation before them counted the edge cases and entity meanings as
`unsupported_addition` or `invented_or_restating_entity`.

- **Classes:** "may renew" for "must be able to renew" **is** a weakened obligation; the edge
  cases ("renew a loan exactly on its due date", "has already been renewed and is now
  overdue") and the entity meaning ("a borrowable item … can be renewed once") **are not**
  inventions; the trigger "The borrower initiates a renewal request" **is not** an invented
  step. Then (user: "agreed on two rulings"): repetition alone isn't an accuracy defect, only a
  readability one scored against `organization`, while a repeat that drops, weakens or adds a
  condition or obligation is a defect of that kind; and an entity for a feature with no
  business data (hello-world's "Hello World Application") is a minor scope defect, at most one
  point of `proportionate-business-scope`.
- **Severity** (user: "Q1: yes, Q2: yes, Q3: yes"; the rubric minimum of 3 makes them decide
  pass or fail): a section that states a requirement more weakly than a correct FR scores that
  requirement's criterion below 3 (`02-29-15Z`'s story and entity meaning "may renew";
  `09-33-46Z`'s EC-001 "fourteen days" without the new due date), while a summary that doesn't
  claim to state the requirement ("triggers a success message") costs `organization` only; an
  invented login and selection step in the story is a material addition, `source-grounding`
  below 3 (the rubric names accounts and UI controls); recording the renewal ("records the
  renewal", "updates the loan record") is a minor addition, so `source-grounding` can stay at
  3: the one-renewal limit needs it.
- **Smaller** (user: "apply recommendations"): "immediately … followed by" in a hello-world
  story is a minor addition; "notification" or "notified" where it names the displayed message
  is a minor addition; "The user launches the application" isn't an invented step; escapes,
  quoted code spans and joined sentences are judged as rendered and cost `organization` only.
- **Titles** (8 November 2026; user: "recommendations accepted for 1 to 6"): a title that gives a
  requirement's value or wording states it, like any repeat above; one that gives none is a
  label, scored against `organization` only (§3 Next 3).

### H2. Review-label confirmation (B2)

The scheme is `b2-review-label/v2` (`.claude/skills/evaluate-e2e/SKILL.md` §7). §7's "A
defective subject with no finding of the expected type is `missed_defect`"
(`SKILL.md:377-378`) is ambiguous: Q1b's labels mark a `supported` verdict on a defective
subject `wrong_type`, `missed_defect` with a null predicted type (which inflates precision) or
both. **Proposed convention:** one entry per returned verdict; a wrong verdict on a defective
subject is `wrong_type` (counted in accuracy, and as a miss in recall); `missed_defect` only
when a subject got no verdict at all; `defect_class` null whenever the expected type is
`supported` (matches `SKILL.md:379-380`); path
`evaluations/b2-review-accuracy/<set>/<case>/<run>/`. **Adopted 1 November 2026:** the
convention goes into SKILL.md §7 when it is next edited; no edit since has carried it (the
path at `:361` still has no `<run>/` level). Relabelling Q1b isn't needed: after D13.1 no
post-generation review findings exist to label. §7 also governs required pre-generation
source review (`:355-358`), so the convention applies when that review's verdicts are
labelled.

### H3. Calibration panels (R8)

The hello-world and loan-renewal panels (each case's `calibration/` under
`test/integration/fixtures/`) have proposed labels only (`human-review.json`, `qualification.json` `pending`). They qualify
only the standalone evaluator; neither the gate nor FIX06's sets need them.

### H4. Experiment stops, qualified scope and the formal baseline (B4, B5)

**Decision** needed only before freezing the evaluation protocol's Phase 2 baseline. The
protocol stops at 1,000 sends or 2,000,000 tokens
([README](../test/calibration/semantic-simplicity/README.md):189-190), about 13.9 sends and
27.8k tokens for each of the Phase 2 baseline's 72 workloads. Since ADR 0047 the development
cases use 9 sends and about 13.5k (hello-world) and 17k (loan-renewal) tokens in 16 of the 18
retained runs (one loan-renewal run 10 sends and 20.5k, one 13 sends and 27.7k with four
corrections); before it, hello-world runs that reached source review used 34 sends and up to
67,448 tokens (`2026-11-02T02-28-14Z`). The 72 workloads are the panel's
development features in three variants and three repetitions (README:222-226; §2 rule 11),
whose cost on the current build is unmeasured, and the latest feasibility report
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
(`specification_story.zig:48-54`),
and in every run from Q1b to 31 October reconciliation formed one signal holding every quoted
claim. Measure whether grouping and source review meet the traceability claim (design.md:121)
before any binding change; the advisory evaluate-e2e link check gives per-record evidence
(D16.2 set: false links AC 2 of 11, EC 2 of 2, FR 0 of 15, EN 0 of 4). No second provenance
store, no support inferred from text matching.

### R6. Semantic repair attribution and recovery

D13.1 removed post-generation review, and loss localization now runs unconditionally
(`pendingLocalization`, `specification_support.zig:319-324`). Remaining proposals, each needing
a closed contract: source-authorized exact-reference repair eligibility (ADR 0033:350-351);
narrow correction of invalid loss evidence (today `invalid`,
`specification_support_workflow.zig:50`; `specification_support_repair.zig:93`); verdict
reassessment under §22.1 with no voting or retry-until-positive. Two runs reached required
source review after `no_feature_claim`: `2026-11-02T02-28-14Z`, whose repair was helpful, and
`2026-11-02T09-15-31Z`, whose false `candidate_omission` on the story ended the run (the story
has since left source review, [Z_FIX06](Z_FIX06.md) Q12 D12.3).

### B7 contract-review leftovers

- Prior-state readback checks stored claim text against the text policy only
  (`reference_snapshot.zig:116-117`; ADR 0036:192-194); re-quoting needs the Unicode
  normalizer at readback.
- `source_selections.validate`'s typed `Issue` is discarded by both production callers
  (`validate_reference_claims.zig:32-34`, `source_omission_comparison.zig:130-131`), and
  `validate-reference-selections` validates token classifications only. Delete the unused
  detail and rename the step and key for what they do (touches `spec.workflow.yaml`, F0100,
  `workflow_tests.zig` and nine `src` files; lands in a gap).

### Design–code conflicts (7 November 2026 review)

**Defect:** none in published output: design text that the code contradicts or lacks misleads
design-routed changes. **Owner:** the cited documents (ADR and AGENTS.md changes are policy
edits); the code defects it found are implemented ([Z_FIX06](Z_FIX06.md) E10). **Status:**
each verified against the tree on 7 November 2026.
**Next:** design edits on approval; **Decision** marks what only the user settles.

- **§13 catalogue granularity (Decision):** registered operations have no entry
  (`validate-workflow-operation-registry`, `parse-workflow-invocation`, `compile-naming-policy`,
  `activate-feature-logging`, `initialize-reference-extraction`; `resolve-provider-model-binding`
  only in F0006, :471 and :1000); 13-04, 13-05, 13-09 and 13-10 name actions no code registers (13-05's
  `MergeSpecificationUnitProposalAction`, 13-09 against `src/actions/log/`); §19.4, §20.3 and
  §20.7 actions have none (`DeriveRequiredChecksAction`, `CreateCommandSavepointAction`; that
  part waits for ADR 0034's gate). One entry per registered operation, or design-level entries
  that point to F0100 and model-request-operations.md?
- **Semantic-review and no-invention branches (Decision: keep or remove):** since D13.1 no
  Spec route produces a finding on generated content or a no-invention replacement (`src/` has
  no `invention`; source review admits F0100 §3.10's support findings), yet 13-04:272-317,
  :356-363, :373-381 and :404-407, 13-05:230-237, 12-model-boundary.md:530-532,
  14-orchestration.md:158-164 and :172, 22-repair.md:207-209 and :418-421 (principle citation
  diagnostics), invariant 18 (design.md:950-953), ADR 0033:138-139 and code.md samples 3, 4,
  13 and 28 keep them.
- **Principle selection in Plan-stage design** (8 November 2026): the category and selection
  policy is removed from code, ADR 0015, §9.4, F0001, the schema, §24, F0100 and design.md.
  Unimplemented Plan-stage text still names it: the §13.1 catalogue's principle entries
  (`13-01-bootstrap-configuration.md:1461-1662`, among the actions no code registers),
  18-plan.md:32 and :92, 20-implement.md:70, design.md:730 and
  code.md:1849. ADR 0034 gates it; a stage that filters principles needs its own mechanism
  and decision.
- **Orchestrator invoking an action:** 13-05:1897 has "the orchestrator statically invokes
  `AppendWorkflowControlEventAction` twice"; AGENTS.md lets an orchestrator coordinate only
  runner-owned child bindings.
- **Versioned data keys:** 06-pipeline-nodes.md:38 (`spec.ir@1`) and :52 ("versioned typed
  key"), against the closed, unversioned `DataKey` enum (`src/domain/pipeline.zig:4`).
- **Diagnostic codes:** none of 08-diagnostics-evidence.md:12-37's representative codes exists
  in `src/`, which uses `ENGINE_CONFIG_READ_ERROR`, `RETRY_LIMIT_EXHAUSTED`, `REPAIR_RECURRING`
  and others.
- **F0002 event registry** against `src/domain/log_event_registry.zig`: F0002 requires
  `repair_unit_kind` on `repair.applied` and `task_id` on `task.completed` and `task.failed`
  (F0002:362, :374, :376), which the code doesn't (`:47`, `:62-66`); no event admits the
  common optional `evidence_status` (F0002:316-317; `validateFact`, `:88-97`); `diagnostic_code`
  is a closed enum (F0002:326) but a validated token in code (`telemetry.zig:175-184`); the
  registry owns sensitivity (F0002:153), but `EventDefinition` has none (`:31-37`);
  `TelemetryFact` is one variant per event (F0002:193-217), but one struct with `event_type`
  and `fields` in code (`telemetry.zig:205-212`). **Decision:** tighten the code or relax F0002
  (the closed `diagnostic_code` enum and registry-owned sensitivity are the stronger contracts).
- **Setup order:** 15-bootstrap.md:31-34 and code.md:2030-2033 (sample 24) parse
  `toolchain.yaml` after the feature target is known; `spec.workflow.yaml:7` starts at
  `toolchain`, before `prepare-inputs` resolves the feature directory (`:202-224`).
- **Workflow selection names:** 14-orchestration.md:36-40, 13-02:8-27, 13-01:342 and
  code.md:2023-2024 name `ParseWorkflowSelectionAction`, `ValidateWorkflowIdAction` and
  `ResolveSelectedWorkflowAction`; the code registers `validate-workflow-operation-registry`,
  `parse-workflow-invocation` and `select-compiled-workflow` (`src/actions/workflow/`).
- **Root-registry names:** F0004:56-58 and 13-01:70-82 have one
  `ValidateEnginePathPolicyAction` and one `ResolveConfiguredBaseRootAction` for directories
  and the provider document; `bootstrap_root_runner.zig:28-35` runs separate
  `validate-configured-root-path-policy`, `validate-llm-provider-config-path-policy` and
  `resolve-llm-provider-config-path` steps.
- **Reference-state identity:** 13-03:8-39 allocates it from the feature `StateIdLedger`, with
  a tombstoned reference-ID ledger; the code (`reference_identity.zig:35-38`,
  `assign_reference_identities.zig`) and F0100:271-275 use a fresh 128-bit random
  `reference-<hex>` namespace and no persisted counter.
- **Feature-log identity:** 13-02:247-300 builds policy and binding IDs from bootstrap-authority
  and registry state IDs; accepted ADR 0018:55-57 and
  `src/adapters/system/feature_log_identity.zig:8-23` use a random run ID, a binding ordinal
  and a policy fingerprint, and ADR 0018:88-91 restores no bootstrap-policy lineage, which
  §14.10 still assumes (E6).
- **Mid-run logging transition (Decision):** 13-02:315, :321 and 14-orchestration.md:273-274,
  :286-287 and :298 require a committed, durable successor bootstrap authority; §9.4 keeps
  changed candidates execution-local with no independent successor (09-configuration.md:387-389,
  as ADR 0009 keeps candidate outputs private) and switches "after an adopting route"
  (:411-412); the validator checks neither (`validate_feature_log_policy_transition.zig:17-31`).
  **Recommended:** §9.4's reading, an execution-local successor with no durability proof.
- **Specify arguments (minor):** 13-02:36-41 gives duplicate, positional and unknown-argument
  rejection to `ValidateSpecifyArgumentsAction`; the parser does it
  (`src/actions/specify/parse_specify_invocation.zig:14-28`).
- **ProviderFailure:** F0006:834-840 lacks the optional `transport` diagnostic that the code
  carries (`llm_provider_operation.zig:193-205`) and the E2E report records
  (`test/harness/e2e/contracts.zig:137`).

### Retired FIX06 IDs cited elsewhere

These IDs are no longer in FIX06 (their records are in git at `194e29a`, `fixes/Z_FIX06.md`);
each citing file needs its reference rewritten, a docs edit needing approval for ADRs:
"D3.1" (`src/domain/packet_guidance.zig:1`); "T5(b)"
(`test/harness/e2e/measures.zig:197`); "T5(e)" (`src/test_fixtures/request_projection.zig:1`,
`test/integration/workflow_tests.zig:1311`); "FIX06 review measures"
(`.claude/skills/evaluate-e2e/SKILL.md:386`; the measures are defined at e2e.md:608-610).
Swept across `design/`, `.claude/`, `src/`, `test/`, `build/` and the agent files on 7
November 2026; "FIX06 <ID>" citations of items now in [Z_FIX06](Z_FIX06.md) resolve there.

### Wider scope retained

- **Memory and scale:** growing review sets, retained bytes, allocations, teardown,
  cancellation and OOM. Unmeasured.
- **Harness acceptance (former H-012, H-013, H-017; git `8ed40ba`):** the parts covered by
  tests were closed on 1 November 2026. Still open:
  - publication interruption: every write failure is covered as a failpoint (meeting ADR
    0009:144-146) but no process kill is tested; **recommended:** close;
  - rerun replacement through an unrelated workflow: covered at the shared writer; reopen when
    the first non-Spec publisher lands;
  - live negative cases as separate fixtures: none exist (`test/e2e/` holds the two
    development cases); adding them means live spend, the user's call.
- **Live-test cost policy:** `test/harness/model_cost_policy.zig:23-25` permits `anthropic` /
  `claude-haiku-5-5` for generation, citing a user direction of 22 October 2026 that no ADR
  records (ADR 0028:169-174); ADR 0029:118-126, e2e.md:41-44 and
  `test/harness/e2e/cli.zig:26`'s help list only the two Bedrock tuples. No live Claude call
  has been made. **Decision:** is that tuple an accepted live-test policy (ADR 0029 gains it,
  a policy edit), or is it removed from the code?

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
