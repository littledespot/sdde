# FIX06 — Phased rollout of the remaining Spec work

**Created:** 28 October 2026. **Status:** sole active fix record. It holds open work only,
in one ordered sequence. Each phase needs the user's approval before its changes, and
every live run needs its own approval. Nothing here authorizes a code change, live call
or E2E run by itself. Items marked **Decision** amend an accepted ADR, contract or scope.
The governing design remains **Proposed design**.

**Authority:** the user's directions of 28 October 2026: "output a phase rollout to
fixes/FIX06.md, the phases should be broken into e2e testable chunks to allow validation
and testing", then "review outstanding items that need to be implemented in FIX05 and
move them to FIX06 … ensure the order is optimal". It follows the 27 October audits of
production code, prompts, ADRs and tests (§1) and the user's rejection of ADR 0044 as "an
extremely poor direction".

**FIX05 is retired.** Its open items are below under their original IDs (A1–A5, B2, B4,
B5, B7, B9, B10, R1, R2, R6–R8, W3–W5 and the carried follow-ups). Its closed items,
current-state snapshots and history are in
[Z_FIX05 §21](Z_FIX05.md#21-fix05-retired--28-october-2026), with a map from every FIX05
ID to its new place. Earlier completed work is in [Z_FIX01](Z_FIX01.md),
[Z_FIX02](Z_FIX02.md) and [Z_FIX05](Z_FIX05.md).

## 1. Why

**Verdict carried from FIX05 (17 October review).** The deterministic core works: no value
breaking a declared native rule has escaped admission since Phase 1A, and every failure
ends as a typed outcome. Two structural properties make the engine expensive and its runs
brittle: every concept is spread across an action, a binding, a registry entry, data keys,
YAML nodes and pinned tests (A1–A5); and the Spec workflow is a long serial chain of
strict model judgments, so end-to-end success is roughly the product of per-call success
(B1).

**The rule recent work broke.** The design forbids deterministic judgement of prose:
[design.md:133](../design/design.md) ("Replacing semantic judgment with brittle keyword
rules" is a non-goal), [12-model-boundary.md:948](../design/contracts/12-model-boundary.md)
("Do not add keyword heuristics"), [17-specify.md:558](../design/contracts/17-specify.md)
("Lexical shape alone is not a semantic rejection") and
[text-field-composition.md:135-136](../design/contracts/text-field-composition.md) ("not a
keyword or substring ban"). Z_FIX05:3411 had also rejected modal-verb matching on 25
October.

**Findings of the 27 October audits** (read-only; key citations re-checked):

1. **Rejected patches** (removed by Q1a on 28 October 2026).
   - ADR 0044's must/may word list (`src/domain/obligation_strength.zig`), the only
     production code that read English words. It did harm on all three live firings: an
     invented "must renew" duty, an unchanged repair that failed the run, and a story
     replaced by the quoted claim.
   - The records-prompt line "never restate a requirement claim by claim", a single-run
     patch copying the evaluator's defect label, ignored in two of three later runs.
2. **Prompt structure.**
   - "Preserve conditions and obligations" appears in 17 places across three layers
     (context JSON, prompt files, Zig strings) and reaches every generated text field: the
     likely source of FR-001 appearing five to seven times per spec.
   - One three-line `repair.prompt.md` serves six repair sites; the reconciliation repair
     gets no context. On 27 October it marked hello-world's UTC claim a `duplicate`
     without the definition, and the spec lost the requirement.
   - The source-review prompt is a 38-line decision tree whose chosen label routes the
     engine; B2 labelling found the right type for 0 to 5 defective items per run.
   - Prompts restate engine-enforced rules, carry engine vocabulary and 35 schema field
     names (vocabulary has leaked into output), and hide the exact-value boundary rule.
   - Lines added after single runs and never measured: `extraction.context.json` lines 4,
     6, 8 and 9; `support.prompt.md` lines 14-16 and 29; `generation.context.json:4`;
     `required_authority_description.zig:131`, `:134` and `:138`.
3. **Fragile engine rules over text:** the list-item split (ADR 0036 Decision 3, ADR 0038
   Decision 4); delimiter stripping (ADR 0036 Decision 6) with ADR 0045 stacked on it; the
   exact-value boundary tables (ADR 0020); the substring duty rule (ADR 0024); the ASCII
   clause join; the GPT-OSS prefix salvage (§22.6); exact-text deletion of a requirement's
   last mention (ADR 0035); never-built keyword lints.
4. **Tests tied to wording:** ADR 0044's phrase tables; about 45 assertions in 11 files
   that copy model-facing English; fixtures named after live runs (R31, R35, R36, R42,
   FIX002); about 24 scripted "recovers" scenarios that prove only that the engine admits a
   valid answer.

**Root cause.** Every change in this period was decided on one run per case, mostly on
uncommitted builds with several changes stacked, and per-run evaluation recommendations
became edits. The same build scored 60.71% to 82.14% on hello-world on 27 October.

**Gate status (ADR 0034).** Not met: no run has been adjudicated (H1), and no committed
build has repeated runs of both cases. The measurement sets below produce that evidence;
the user decides when Plan is actioned.

## 2. Rules for every phase

1. **One change set per phase.** Nothing else is stacked into a measured build. A phase not
   kept is reverted in full, never patched on top.
2. **Offline first.** `/preflight` before editing; regression and negative tests at the
   owning boundary, comparing against owners rather than copied English; `zig build
   verify`; a `contract-reviewer` pass. Clean packaging checks when implementation
   boundaries change.
3. **Committed build.** The user commits each phase. Measurement uses that committed,
   unmodified build (`report.json` `build.source.modified` is `false`).
4. **Measurement set.** At least three runs of each development case (hello-world and
   loan-renewal) on that build, each run approved. Budget-stopped, malformed and exhausted
   runs stay in the attempted-workload denominator. Never tune on the sixteen reserved
   qualification features (ADR 0034).
5. **Evaluation of each run.** `/evaluate-e2e` (advisory), B2 labels for every review
   finding, and the measures below, reported per run and as minimum, median and maximum
   per case. Advisory scores are never acceptance; only H1 adjudication is.
6. **Measures.**

   | Group | Measure |
   | --- | --- |
   | Outcome | Useful completion per attempted workload (B1: call count is a reliability cost); published, failed or blocked with its diagnostic |
   | Quality | Advisory aggregate; critical failures; per-criterion scores |
   | Defect classes | Lost source requirement; weakened obligation; unsupported addition; invented or restating entity (B6); restatement; rendering artefact; engine-vocabulary leak; records per batch (B5 inflation) |
   | Repairs | Each repair graded helpful, neutral, harmful or no progress |
   | Admission | Protocol corrections; admission rejections by reason; runaways and re-sends; admission escape (a value violating a declared native rule reaching review or publication, with downstream sends and tokens) |
   | Review | Finding-type accuracy: share of findings whose type matches a frozen source-based label, with precision per predicted type and recall per labelled type at original and final assessment; a real defect with the wrong type is a harmful diagnosis. Detection recall; false statements |
   | Cost | Sends and actual tokens per stage (extraction and reconciliation, generation, review, repair) per attempted workload; review share; latency and retained memory where measured |

7. **Keep or revert.** The user decides. Default rule: keep when the phase's target
   measure improves at the median on both cases, no other defect class or critical
   failure rises beyond the last accepted state's range, and no new harm class appears;
   otherwise revert. A measure triggered too rarely (for example, fewer than three repairs
   of the targeted kind) is "not enough evidence"; more runs need approval.
8. **Reporting.** Keep these statements separate: implementation complete, mechanical
   checks passed, semantic benefit demonstrated, brittleness reduced, scope qualified. More
   passing tests, fewer calls or higher admission alone close no semantic gate. Results go
   in §10.
9. **Comparison point.** Each phase is compared with the last accepted state; Q1b sets the
   first.
10. **Model limitations.** A limitation under a coherent contract is a valid result. Never
    answer it with field-, case- or model-specific rules, phrase rules, sampling changes,
    extra retries, a second model, caps that discard output or a weaker admission rule.
    Explicit exceptions: the standalone evaluator's one mechanical correction
    ([Z_FIX05 §15](Z_FIX05.md#15-grader-one-shot-correction--18-october-2026), harness
    only, user decision of 18 October 2026) and ADR 0039's runaway re-send (engine, user
    decision of 26 October 2026). The §22.6 prefix salvage is a second engine exception
    that CLAUDE.md doesn't name (D11.4).
11. **Engine-track work** (§5) changes no model input. It is proved offline: every request
    kind the scripted driver produces is byte-identical before and after (compared
    through `model-request-debug` descriptions). It needs one live run of each case, and
    lands only between measurement sets, never during one. Quality phases take priority.
12. The [evaluation protocol](../test/calibration/semantic-simplicity/README.md) owns case
    partitions, scoring, the numeric gates and the experiment stops (H4).

**Boundary gates** for contract changes (carried from FIX01 §5):

| Boundary | Required positive evidence | Required negative evidence |
| --- | --- | --- |
| Summary representation | Combined, split and overlapping expressions; complete membership; stable identities and evidence | Missing or foreign IDs, altered categories, false support, changed exact values, conflicting interpretations |
| Normalization | Idempotence; same-evidence duplicates collapse; raw and provenance retained | Same text from different occurrences, distinct obligations, non-equivalent paraphrases, destructive truncation |
| Native carry-forward | Empty, non-final, final and one/many-child routing; identical current child and evidence; complete lineage | Stale or forged child content, changed evidence, token duplication, fabricated origin, skipped final semantic work |
| Repair | Exact target and dependencies, protected siblings, progress, full final validation | Stale authorization, widened scope, reset allowance, invalid survivor, unsupported verdict change |
| Loss attribution | Bound comparisons locate candidate-only and genuine upstream loss; dependencies and evidence retained | Missing or duplicate assignments, contradictory outcomes, uncertain owners treated as certain, lost source-only omissions, false upstream rebuilding |
| Exact-value representation | Occurrences recorded from exact bytes in bound fields; identity survives repair and readback | False matches, ambiguous occurrences, unbound fields, changed obligations |
| Loss-evidence correction | The narrow correction preserves subject, finding and scope; native validation reruns before repair | Nonexistent lines, stale producers, verdict replacement, budget or attempt reset, repeated defect |
| Cross-model behaviour | Paired repeated trials in unrelated domains; all declared outcomes and costs | Meaning changed despite valid JSON and IDs; false rejection, unsupported acceptance, inconclusive or unusable results |
| Whole workflow | Real publication, complete required review and separately approved rubric evaluation | An early stop reported honestly; no golden outputs, fabricated E2E success or offline substitute |

## 3. Sequence

Tracks: **Q** quality phases (model-input changes, each measured; the critical path), **E**
engine work (no model-input change; §2.11), **T** tests (offline only, any time), **H**
human and decision items, **R** research and backlog.

| Step | Item | Validation | Decisions |
| --- | --- | --- | --- |
| 1 | **Q1a** Remove ADR 0044 and the records-prompt line; hold ADR 0045 (**done 28 October**) | Offline | D1.1, D1.2 (decided) |
| 2 | **E0** Failed and blocked runs publish validated content (B10, ADR 0041) | Offline, byte-identical requests, one run per case | Accepted |
| 3 | **Q1b** Clean baseline | Measurement set; H1 may start | — |
| 4 | **Q2** Repair requests carry their step's own instructions | Measurement set, call replay | D2.1 |
| 5 | **Q3** One owner per model instruction | Byte-identical requests, one run per case | D3.1 |
| 6 | **Q4** Remove engine vocabulary and restated engine rules | Measurement set | D4.1 |
| 7 | **Q5** Remove unmeasured single-run guidance | Measurement set | D5.1 |
| 8 | **Q6** Scope "preserve obligations" to obligation-bearing fields | Measurement set | D6.1 |
| 9 | **Q7** Exact values | Measurement set per decision | D7.1–D7.3 |
| 10 | **Q8** Source-claim granularity (B7) | Measurement set on two builds | D8.1–D8.3 |
| 11 | **Q9** Reconciliation call structure (W4) | Capture replay, then measurement set | D9.1 |
| 12 | **Q10a** Publish source-review findings (B2) | One run per case, B2 labels | D10.1 |
| 13 | **Q10b** Simplify the source-review taxonomy (B2) | Measurement set, B2 labels | D10.2 |
| 14 | **Q11** Remaining rules and design text | One run per case where runtime changes | D11.1–D11.4 |

Between measurement sets, in ADR order: **E1** (A1, ADR 0030 slice 4) once Q2 is decided;
**E2** (A2, ADR 0031, with W5); **E3** (A3, ADR 0032); **E4** (W3, ADR 0033) after E1 and
E2's measure; **E5** (A4) folded into E1–E4; **E6** (logging gaps) any gap; **E7** (R2,
ADR 0025) after E1–E4. **T1–T4** any time. **H1** from Q1b; **H2** before Q10; **H3** and
**H4** before any formal baseline freeze; **H5** whenever the user chooses. **R** items
after the Q phase that produces their evidence.

**Why this order.**
- **Clean start.** Q1a removes the rejected patches first, so nothing is measured on them.
- **E0 before the baseline.** ADR 0041 changes failed-run publication, the workflow
  definition version (`workflow/v2`) and the report's failed-run fields (documented under
  `spec-e2e-report/v10`, not yet implemented). Landing it first keeps every measured run
  on one definition and report contract, so every run stays adjudicable (ADR 0039's report
  change stranded 16 v9 runs). Failed measurement runs then publish their validated
  content for evaluation. It changes no model input.
- **Harm before polish.** Q2 fixes repairs that lost a requirement or damaged output.
  It precedes E1 and E4: those large refactors must preserve Q2's bindings by
  byte-identical requests, which is cheaper than delaying the harm fix behind them.
- **One owner before content edits.** Q3 consolidates guidance, so Q4–Q6 each edit one
  place, and moves no bytes.
- **Hygiene before semantics.** Q4 and Q5 remove noise before Q6 changes what fields are
  asked to carry.
- **ADR-level rules after the baseline is stable.** Q7 and Q8 revisit accepted ADRs on
  repeated evidence. Q9 follows Q8 because claim count drives reconciliation's decisions.
- **Review last.** Q10 assesses what generation produces and depends on H2's labels.
- **Engine work in the gaps.** ADR 0034 puts Spec quality first; E1–E4 claim no quality
  change and land between measurement sets in ADR order. E7 (R2) comes after them because
  the conversions lower its cost and the two development cases don't exercise it.

## 4. Quality phases (Q)

### Q1. Remove the rejected patches and take the clean baseline

**Q1a: done 28 October 2026, uncommitted** (the user's "implement Q1a"). D1.1: ADR 0044
was deleted, as ADR 0027 was; its evidence stays in Z_FIX05 §21 (B7) and known-work. D1.2:
the records-prompt line is removed. The seven code and test files were restored to their
`28ff156` content (the commit before ADR 0044), which differed from `d74fc1f` only by ADR
0044, and `obligation_strength.zig` was deleted. ADR 0045 is marked on hold, and
text-field-composition.md is restored to its pre-ADR-0045 text, so the contract describes
the implemented behaviour until Q7 decides. Verified: `zig build verify` passed (164 of
164 steps, 1,969 of 1,969 tests) and a contract review found no code issues; its three
minor documentation findings are fixed.

**Q1a changes (as planned).**
- Remove ADR 0044 completely:
  - code: `src/domain/obligation_strength.zig`; the `weakened_obligation` rule in
    `specification_candidate.zig`; `weakenedObligation`, `weakened`, `Weakened`,
    `targetWeakening`, `recordWeakening` and `weakens` in `specification_generation.zig`;
    the requirement, `authorizeGroup` detail and revalidation check in
    `specification_repair.zig`;
  - tests and fixtures: the ADR 0044 tests in `specification_generation_test.zig`, the
    `weakened_obligation` and `reworded_weakening` shapes and assertions in
    `spec_generation_driver.zig` and `spec_generation_responses.zig`, and the three
    scenarios and librarian source in `test/integration/workflow_tests.zig`;
  - docs: ADR 0044, its §32 row, contract 17, F0100, ADR 0045's consequence bullet and
    known-work.
- Remove `records.prompt.md:9-10` and its ADR 0038 amendment note.
- Mark ADR 0045 on hold (B12), decided in Q7.

**Decisions.**
- **D1.1** Remove ADR 0044: delete the ADR as ADR 0027 was, or keep it marked withdrawn
  with its evidence. Record obligation weakening in generated text (B7) as a model
  limitation.
- **D1.2** Remove the records-prompt line. Claim-by-claim restatement (B5) is a symptom
  for Q6 and Q8, not patched in the prompt.

**Offline validation.** No reference to `weakened_obligation` or `obligation_strength`
remains; `zig build verify`; contract review.

**Q1b baseline.** After E0, the measurement set on the committed build. Expected, and
recorded rather than fixed: loan-renewal's story may say "may renew" (FR-001 keeps the
source wording) and hello-world's business rules may restate FR-001. **Exit:** the
baseline table in §10, with every measure.

### Q2. Repair requests carry their step's own instructions

**Goal.** No repair decides without the definitions its original request had.

**Changes.**
- Each repair request binds the prompt and context of the step it repairs, beside
  `repair.prompt.md`: the dispositions, signals or conflicts prompt for a reconciliation
  repair; the unit's prompt and `generation.context.json` for a specification-unit
  repair; the extraction prompt and context for extraction repairs.
- `repair.prompt.md` keeps only repair mechanics; its wording is otherwise unchanged.

**Decision.** **D2.1** A model request may bind more than one prompt resource, or each
repair site names its step's resources. `/preflight` confirms the owner: contracts 12 and
22, the §13 model actions, ADR 0016 and ADR 0030.

**Offline validation.** For every repair site, the repair packet carries the repaired
step's prompt bytes, compared with the resource itself.

**E2E validation.** Before the phase, `e2e-call --repeats` on the captured 27 October 09:40
hello-world reconciliation repair (call 6) measures how often the old request marks the
UTC claim a duplicate. Then the measurement set, grading every repair. **Keep if**
harmful repairs and requirements lost in repair fall and nothing else regresses.

### Q3. One owner per model instruction

**Goal.** Every instruction the model sees exists in exactly one place.

**Changes.** Move semantic guidance written in Zig (field purposes and review scopes in
`required_authority_description.zig`, the summary purpose in `reference_model_input.zig`,
the guidance in `specification_support_evidence.zig`) into workflow resources, or declare
the native registry its owner and delete the prompt-file copies. Mechanical diagnostics
stay native. Remove duplicates. The assembled request bytes do not change.

**Decision.** **D3.1** Which layer owns semantic guidance. Recommended: the workflow
resources (contract 12: "the workflow supplies prompt content"), with the native field
registry keeping only mechanical explanations. Amends text-field-composition.md:49-50 and
17-specify.md:249.

**Validation.** Byte-identical requests (§2.11); tests compare against the owning
resource; one run of each case.

### Q4. Remove engine vocabulary and restated engine rules from prompts

**Changes.**
- Remove engine vocabulary: "native", "engine", "canonical", "structural", "provenance",
  "The engine binds claim evidence", "Tokens are read-only native facts", "Kind … does not
  decide whether the engine requires exact preservation", "Family presence is structural".
- Remove rules the engine enforces and explains on violation: `records.prompt.md:11-13`,
  `extraction-classifications.prompt.md:3-5`, `extraction.context.json:14`, and "one entry
  per requirement_ordinal, exactly once" in the support and principle prompts.

**Decision.** **D4.1** Prompts carry task semantics only; engine-enforced structure is
explained by its admission correction.

**Validation.** For each removed rule, a scripted violation receives a correction that
states it, compared with the owning explanation. Measurement set. **Keep if** engine
vocabulary in published specs falls to zero, corrections and admission rejections stay
within the previous range, and no defect class regresses.

### Q5. Remove unmeasured single-run guidance lines

**Changes.** Remove `extraction.context.json` lines 4, 6, 8 and 9; `support.prompt.md`
lines 14-16 and 29; `generation.context.json:4`; and the field-purpose clauses "The source
need not supply a title", "do not invent a persona or benefit or require a prewritten
story" and "Displayed values alone do not establish entities…" (in their Q3 owner).

**Decision.** **D5.1** Remove them together; restore a line only if its targeted class
regresses, recording the evidence here.

**Validation.** Measurement set, watching title gaps, invented personas, entities invented
from displayed values, misclassified technical and validation claims, and compatible claims
labelled conflicting.

### Q6. Scope the obligation instruction to obligation-bearing fields

**Changes.** "Preserve conditions and obligations" applies only to functional
requirements, acceptance criteria, edge outcomes, business rules and prohibited behaviour.
Narrative fields (title, description, goal, story, entity meaning and relationships,
user-visible outcomes) keep their purpose only. One edit, in the Q3 owner.

**Decision.** **D6.1** Amend the shared field purposes (17-specify.md:249) and
`generation.context.json`'s `business_value` guidance.

**Validation.** Measurement set. **Keep if** restatement falls and organisation rises at
the median, and lost requirements and weakened obligations in requirements and acceptance
criteria do not rise.

### Q7. Exact values

**Decisions.**
- **D7.1** When an exact value is rejected, the correction states the boundary rule,
  generated from the closed boundary policy (`exact_value_boundary.zig`).
- **D7.2** Decide ADR 0036 Decision 6 (delimiter stripping) and ADR 0045 (B12) together:
  implement ADR 0045, or stop stripping and withdraw ADR 0045. Markdown in claim wording
  (B7) is measured here.
- **D7.3** Whether a token's appearance inside a claim (ADR 0024's substring rule) uses
  the same boundary as recognition, so short tokens inside words no longer create duties.

**Validation.** One measurement set per decision that changes model input or output.
**Keep if** exact-value rejections, corrections and spurious `missing_exact_copy` repairs
fall and rendering artefacts do not rise.

### Q8. Source-claim granularity (B7)

**Changes.** An experiment build on its own committed branch with the list-item split
disabled; the main build keeps it.

**Decisions.**
- **D8.1** Keep, change or withdraw ADR 0036 Decision 3 and ADR 0038 Decision 4. ADR
  0038's scenario-coverage rule depends on per-item claims, so a withdrawal must say how
  coverage is kept.
- **D8.2** Whether ADR 0036's "cites in full" includes a fenced block's blank first or last
  interior line (otherwise a token's bytes can fall outside the quote).
- **D8.3** Whether identical citation sets are a native duplicate.

**Validation.** A measurement set on each build: claim counts, conditions separated from
their items, restatement, claims lost in reconciliation, scenario coverage and cost.

### Q9. Reconciliation call structure (W4)

Even a three-line source needs two extraction calls and four reconciliation calls (summary,
dispositions, signals, conflicts) before authoring; reconciliation is the largest stage.
The split was deliberate ([ADR 0016](../design/decisions/0016-configured-json-response-composition.md)).

**Changes.** First replay retained captures (from raw response bytes, or captures made
after ADR 0030 slice 3, whose catalogues carry `requestTimeoutMs`) to test whether separate
dispositions, signals and conflicts calls change claims, groups or conflicts compared with
one combined call on small and single-source inputs.

**Decision.** **D9.1** Combine the calls only on that evidence (amends ADR 0016).

**Validation.** Measurement set: claims lost in reconciliation, cost and completion.

### Q10a. Publish source-review findings as advice (B2)

**Decision.** **D10.1** Amend ADR 0023: negative source-review findings appear as an
advisory section in `reference-context.md`, as principle findings already do; they never
repair content or create clarifications.

**Validation.** Rendering tests from typed findings; one run of each case; the measurement
set's B2 labels show how many published findings are true.

### Q10b. Simplify the source-review taxonomy (B2)

Review takes about 79% of tokens and catches little: on 26 October source review found 1
of 28 defective subjects with the right type and wrote 26 false statements; principle
review cited the governing rule in none of 108 findings. Quality over cost: no check is
dropped to save tokens, but spending that buys no quality is removed at its owner.

**Changes.**
- Fewer finding types, with the engine deriving routing from typed facts instead of the
  model choosing it.
- Unify the single and assignment schema selection (the two definitions order
  `candidate_invalid` and `inconclusive` differently, and single findings drop the
  `negative` guidance rule in a projection-specific branch).
- Clarify original-source authority, the candidate target and completeness for the
  assigned field purpose through the shared purpose and evidence owner (the former R6
  source-review direction), compared offline on the labelled failures plus clean controls
  before any live call.

**Decision.** **D10.2** Amend ADR 0023 and the support schema.

**Constraints.** Don't discard policies by keyword, truncate required evidence or add
local token ceilings; don't claim a larger budget fixes reliability; group subjects only
with evidence that per-subject findings, association, correction scope, origins and retry
identity survive. A separately configured assessment model is a model choice (H5).

**Validation.** Measurement set and B2 labels. **Keep if** finding-type accuracy and recall
rise and false statements fall.

### Q11. Remaining rules and design text

**Decisions.**
- **D11.1** Delete the never-built keyword lints from the design (design.md:252, acceptance
  criterion 21, 21-validation.md:20 and :38). Docs only.
- **D11.2** The acceptance-criterion clause join (`specification_markdown.zig:202`): keep
  it, give it a contract, or remove it.
- **D11.3** ADR 0035: never delete a covered restatement that is a requirement's last
  mention in the records.
- **D11.4** CLAUDE.md names the runaway re-send as "the one engine exception", but the
  GPT-OSS prefix salvage (§22.6, approved 18 October) is a second. Correct the wording or
  withdraw the salvage. Policy edit.

**Validation.** One run of each case where runtime behaviour changes; none for docs.

## 5. Engine track (E)

Each item: `/preflight`, offline tests, byte-identical requests (§2.11), `zig build
verify` with smoke, one live run of each case, landing between measurement sets.

### E0. Failed and blocked runs publish validated content (B10, ADR 0041)

Accepted on 26 October; mechanism accepted on 27 October. A Specify run that fails because
model work couldn't be completed, or ends `blocked`, publishes only its validated content
as an incomplete specification, marked in `spec.md` and `reference-context.md` and logged
as `run.incomplete_published`, while still ending `failed` or `blocked`. Mechanism: a
YAML-declared `failure-output` subgraph run by the engine through the runner in a
model-free failure-output mode; eligibility as ADR 0041 Decision 1; no final requirement
IDs; `workflow/v2`. Two tests asserting that a required repeated runaway publishes nothing
flip, and `spec.md`'s reader needs a slot for the failure status line beside ADR 0040's.
About the size of ADR 0039.

### E1. Engine-owned model request (A1, ADR 0030 slice 4)

Slices 1–3 are done. Open: the `request-model` step itself, with ADR 0030's offline
acceptance and the shared contract-variant mechanism ADR 0033 reuses.
- It folds ADR 0039's re-send (`check-model-runaway`, `build-model-runaway-resend` and the
  compiler route rule) into the `request-model` stages and retires that YAML rule.
- ADR 0040's review closure, ADR 0042's required-items constraint and Q2's bindings carry
  over unchanged; refresh slice 1's equivalence freeze to the current request bodies.
- Settle the slice 1 review points: trace the advisory production run (budget exhaustion,
  output limits, the advisory protocol stop); make `extract/content` and
  `extract/content-request` one step; port each runner-level lifecycle test in
  `src/model_request_workflow_test.zig` one for one, with a mapping table and a reason for
  any dropped assertion (user decision of 23 October, option b).
- Not expected to change model calls, tokens or reliability. Whether the engine also takes
  over release is open (R-A1).

### E2. Stage actions (A2, ADR 0031) and identical sibling steps (W5)

Convert `prepare-toolchain` first and record A2's measure (files touched per change)
before converting another stage. Check whether a conversion absorbs W5's pairs
(`source-gaps`/`candidate-gaps`, `finish-native`/`finish-model`); otherwise merge them once
the workflow compiler's data-flow check accepts the joins. **Decision DE2:** confirm the
derived choices (read-only stages, the absorption rule, scope left to A3,
`prepare-toolchain` first, offline evidence for structural conversions, contract-field and
model-output limits).

### E3. Engine routines (A3, ADR 0032)

Convert startup (bootstrap, provider config, provider bootstrap) first and measure it;
convert feature logging once ADR 0032's preconditions hold. **Decision DE3:** confirm the
derived choices (category and location, internal branches on typed facts, reaching a
routine through the composition root or a binding, logging second, Specify invocation as a
stage action, ADR 0030's form kept, fake-port testing).

### E4. Generic repair operations (W3, ADR 0033)

After E1 and E2's measure, with all Specify owners in one change on offline equivalence
evidence, preserving Q2's bindings. **Decision DE4:** confirm the derived choices (the
13-owner list, the `owner` check, "compiled operation" meaning the step instance, the
§22.1 reading, advisory stops outside the four operations, one Specify-only conversion,
offline evidence).

### E5. Rejections say why (A4)

Give `.authority` a closed reason and split `OperationExecutionFailed` into specific causes
at their owners, keeping typed outcomes and terminal precedence. Recount the sites after
each of E1–E4 before adding reasons elsewhere. Failure-evidence gaps:

| Gap | Required change |
| --- | --- |
| Evaluator partial bodies disappear | Thread retained bytes and completeness through the shared observation ([provider.zig](../test/harness/provider.zig), [bedrock.zig](../test/harness/bedrock.zig), [http.zig](../test/harness/http.zig), [evaluation_trace.zig](../test/harness/evaluation_trace.zig)), with redaction and adapter-to-trace fault tests |
| Simultaneous failures overwrite earlier causes | Retain bounded primary and secondary evidence ([workflow_model_invocation.zig](../src/application/workflow_model_invocation.zig), [workflow_pipeline_runner.zig](../src/application/workflow_pipeline_runner.zig)), preserving terminal precedence and allocation-failure handling |
| The loss-localization call origin isn't retained | Preserve both the finding and localization associations through collection, correction, repair authorization and reporting ([specification_support.zig](../src/domain/specification_support.zig)) |

Limits: build snapshots don't prove the compiler consumed exactly that snapshot under
concurrent edits; progress labels include routine invalidation, so not every progress
event is a semantic repair.

### E6. Logging and visibility gaps

- Cancellation during segment reads and under the log lock is reported as a logging
  failure, against keeping cancelled distinct from failed.
- The lock action reports every acquire failure as a timeout.
- Prior-run crash finalization (§14.10) needs a persisted bootstrap authority that doesn't
  exist, so a crashed run's logs are kept until it is decided.
- §26 and F0002 name the `redaction/default-v1` policy, but no code or record carries it.
- `model.provider_stopped` is a warning, so `logs.level` `error` or `fatal` filters it
  out: **Decision DE6** whether that is acceptable.

### E7. Clarification answer recovery (R2, ADR 0025)

Fresh answers can't complete the registered recovery path: refresh rejects new nonempty
submissions with `AuthenticationRequired`, provenance rejects nonempty response-ID sets,
preparation validates forms without authenticating answers, generation doesn't consume
accepted answers, and passive literal origins are source-only. Complete the
[§17.4 lifecycle](../design/contracts/17-specify.md#174-specification-clarification-behavior)
under [ADR 0025](../design/decisions/0025-clarification-answer-authentication.md): the
account that runs the engine is the actor; one invalid closed form stops the run with a
typed reason per form; evidence in the shared actor-evidence registry; Specify only. Keep
ADR 0021's optional pre-generation source check; persistent identity across edits needs an
explicit continuity contract. **Validation** needs a clarification-producing development
case chosen by the user (never a reserved feature). It changes model input only when
answers exist, so it is measured on that case.

## 6. Test track (T)

### T1. Repeated-runaway debug capture (B9)

ADR 0039's debug-capture test: at `debug`, a repeated runaway leaves both attempts'
requests, request descriptions and complete returned outputs in the prompt log before the
failure events; at a higher level, only the events. No live run has had a repeated runaway.

### T2. Test decoupling

- Replace the about 45 assertions that copy model-facing English with comparisons to the
  owning constant, function or resource, checked once in the wire.
- Remove `model_payload_schema_test.zig:362-367`'s phrase checks on `protocol.prompt.md`,
  or compare with the resource.
- Rename fixtures named after live runs (R31, R35, R36, R42, FIX002) after the rule they
  test.
- Describe the scripted "recovers" scenarios as engine admission tests, never as evidence
  that a correction helps a model.

### T3. Coverage gaps (B5, B7)

- No offline integration scenario exercises a records-batch native delete (ADR 0035).
- The extraction reason's text-repair route has unit coverage only.
- No synthetic current-schema exchange replaces the retained `compatible` one.

### T4. Architecture rules and replay (A5)

When E2 and E3 rewrite the affected tests, express architecture rules as import-graph and
contract-shape rules instead of per-file pins (69 of 79 pin files, with 420 source-text
assertions). Prefer replaying retained real captures over extending the scripted response
builder.

## 7. Human and decision track (H)

### H1. Adjudication (R8)

Only a human `human-spec-adjudication/v2` record, applied with `zig build adjudicate-spec`,
decides acceptance. No run has been adjudicated. Any `spec-e2e-report/v10` run can be;
the retained v9 runs stay unadjudicated (decided 27 October). Needed for the ADR 0034 gate,
from the Q1b baseline on.

### H2. Review-label confirmation (B2)

A human confirms or corrects the B2 labels under `evaluations/b2-review-accuracy/` so they
become frozen evidence. Needed before Q10's decisions.

### H3. Calibration panels (R8)

The [Hello World panel](../test/integration/fixtures/wf-001-hello-world/node-vitest/calibration/REVIEW.md)
(nine specimens) and the
[loan-renewal panel](../test/integration/fixtures/wf-002-loan-renewal/calibration/REVIEW.md)
(fifteen) have proposed labels only; human-review and judge-qualification records are
pending. Needed before judge qualification and any formal baseline freeze.

### H4. Experiment stops, qualified scope and the formal baseline (B4, B5)

**Decision**, before freezing the evaluation protocol's Phase 2 baseline (FIX06's
measurement sets don't need it): the protocol's stops of 1,000 sends and 2,000,000 tokens
cover 16 workflows at 125,000 tokens against 144 development workloads, so the
budget-feasibility report stays `insufficient`. Revise the stops with a recorded
rationale, reduce review cost through its owner (Q10b), or narrow the qualified scope.
Measure the prompt, schema and evidence share of each call before trimming anything; add
no local size ceilings (ADR 0011). If the frozen baseline meets the protocol's adequacy
targets, retain it and stop the redesign.

### H5. Model choice (R7)

The user decides when to change or compare models. All live evidence comes from
GPT-OSS-20B. Only if the user selects Claude Haiku 5.5: measure its maximum-output time to
replace the interim 180,000 ms `requestTimeoutMs`, and settle Claude's response mode
(native schema or prompt-only).

## 8. Research and backlog (R)

### R1. Group-level provenance precision

Record binding assigns a complete accepted group; ADR 0038 narrowed non-entity records to
their named claims, but entities and narrative fields still bind whole groups. Measure
whether grouping and source review meet the traceability claim (after Q8, with B2 labels)
before any binding change across generation, review, repair, omission insertion, readback
and rendering. No second provenance store, no support inferred from text matching.

### R6. Semantic repair attribution and recovery

Re-scoped under ADR 0023 (findings don't drive content repair); after Q10b. Remaining
proposals, each needing a closed contract: source-authorized exact-reference repair
eligibility (§22 and ADR 0020/0022 amendments); narrow correction of invalid loss
evidence (today `invalid_loss` ends the workflow `invalid`); verdict reassessment under
§22.1, with no voting or retry-until-positive. Entity-applicability repair can't change
the entity decision, and exact-reference repair can't add an unselected claim because its
text matches. Earlier comparison records are in
[Z_FIX02](Z_FIX02.md#21-r6-follow-up-records-formerly-in-fix01).

### Summary hierarchy and cross-model variation

Former FIX01 §9.20 recommendations 1–2 are implemented; live acceptance is open. Run the
[prepared summary comparison](../test/calibration/summary-coverage/README.md) only under
fresh approval, with source-preservation review enabled and disabled. Open proposals:
classify meaning defects separately from representation and source gaps (§12.8.1, §22.2);
extend repair only for genuinely coupled defects; make cross-model variation part of
acceptance evidence (H5). Constraints: summary admission is not per-summary review; loss
localization has no summary target; overlap can retain misleading paraphrases; duplicate
normalization needs conserved evidence; single-child carry-forward reads current history;
don't replace the general repair owner. Ranks below Q10.

### B7 contract-review leftovers

Stored readback doesn't re-quote claim text from its citations; admission admits a
repeated citation ID; `source_selections` naming was left out of scope. No observed outcome.

### Wider scope retained

- **Evaluator responsibility transfer:** judgment accepts criterion IDs and quoted
  strings, then checks coverage and substring presence; define the assignment and
  occurrence contract first.
- **Retained memory and scale:** growing review sets, retained bytes, allocations,
  validation and teardown time, cancellation and OOM, dependent rebuilding.
- **Harness acceptance (former H-012, H-013, H-017):** publication interruption evidence;
  production Specify feature-log integration; live negative paths (malformed generation,
  real missing or conflicting authority, clarification, cancellation, judge failure);
  rerun replacement (shorter output, unsubmitted drafts, concurrent closes, no duplicate
  subject IDs, an unrelated workflow); an unchanged prior `spec.md` must not be labelled new
  after a blocked rerun (E0 changes this); compiler rejection of skipped gates and
  undeclared resources; packaged execution without a `design/` fallback; the H-017 live
  milestone; live evaluator demonstration (H-004/H-006); the provider-compatibility
  diagnostic. Ticket text in git at `8ed40ba`.
- **Provider docs:** ADR 0028 names an F0009 feature document and contract §12.3.2, which
  don't exist, and its "Live use" still says only GPT-OSS-20B is permitted.

### R-A1. Engine-owned release

Whether the engine should also take over release, which needs the compiler to derive each
request's lifetime. Decide after E1.

## 9. Guardrails

- No deterministic rule that matches words or phrasing in model output, and no test that
  enumerates sentence variants.
- No change decided on one run; no stacked changes in a measured build.
- No model change or comparison (H5), no sampling change beyond ADR 0039, no extra
  retries, no caps that discard output, no case-, field- or model-specific rule.
- Don't narrow the entity-name exception without a decision (B6).
- Report model limitations under a coherent contract as results.
- Never tune on the sixteen reserved qualification features.
- The user manages git; every live run needs approval naming its case.

## 10. Progress

| Step | Item | State | Build | Runs | Result |
| --- | --- | --- | --- | --- | --- |
| 1 | Q1a | Done 28 October 2026 (D1.1, D1.2 decided); awaiting the user's commit | Working tree on `d74fc1f` | Offline only | `zig build verify`: 164 of 164 steps, 1,969 of 1,969 tests; `git diff --check` clean; contract review: no code findings, three minor doc findings fixed |
| 2 | E0 | Accepted (ADR 0041); not started | — | — | — |
| 3–14 | Q1b–Q11 | Proposed | — | — | — |
| — | E1–E7, T1–T4 | Proposed or accepted, not started | — | — | — |

**Cost estimate.** A measurement set is six runs at about 75,000 to 95,000 tokens each,
about 450,000 to 570,000 tokens. Q3, Q10a, Q11 and each engine item need one run per case.
