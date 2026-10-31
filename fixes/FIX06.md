# FIX06 — Phased rollout of the remaining Spec work

**Created:** 28 October 2026. **Updated:** 28 October 2026 (detailed review merged: 25
adversarially verified findings, 15 high-severity findings checked by hand, the coupling
review and a new order; 119 unverified medium and low findings were not applied and are
kept in `evaluations/fix06-review/2026-10-28/review-merge.json`, Git-ignored analysis). **Status:** sole active fix
record. It holds open work only, in one ordered sequence. Each phase needs the user's
approval before its changes, and every live run needs its own approval. Nothing here
authorizes a code change, live call or E2E run by itself. Items marked **Decision** amend
an accepted ADR, contract or scope. The governing design remains **Proposed design**.

**Authority:** the user's directions of 28 October 2026: "output a phase rollout to
fixes/FIX06.md, the phases should be broken into e2e testable chunks to allow validation
and testing", then "review outstanding items that need to be implemented in FIX05 and
move them to FIX06 … ensure the order is optimal", then "ensure the phase order is
optimal", "check that it is address tight coupling issues, and removing brittleness,
ensure that local fixes are not being implemented" and "Finish the FIX06 update". It
follows the 27 October audits of production code, prompts, ADRs and tests (§1) and the
user's rejection of ADR 0044 as "an extremely poor direction".

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
("Do not add keyword heuristics"), [17-specify.md:547-548](../design/contracts/17-specify.md)
("Lexical shape alone is not a semantic rejection") and
[text-field-composition.md:129-130](../design/contracts/text-field-composition.md) ("not a
keyword or substring ban"); AGENTS.md now says so directly. Z_FIX05 had also rejected
modal-verb matching on 25 October.

**Findings of the 27 October audits** (read-only; key citations re-checked):

1. **Rejected patches** (removed by Q1a, committed as `d4fd4a5`).
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
   - One three-line `repair.prompt.md` serves six repair sites, and the reconciliation
     repair gets none of its step's prompt (the dispositions prompt defines `duplicate`).
     On 27 October it marked hello-world's UTC claim a `duplicate`, and the spec lost the
     requirement.
   - The source-review prompt is a 38-line decision tree whose chosen label routes the
     engine; B2 labelling found the right type for 0 to 5 defective items per run.
   - Prompts restate engine-enforced rules, carry engine vocabulary and 35 schema field
     names, and hide the exact-value boundary rule.
   - Sentences added after single runs and never measured (Q5).
3. **Fragile engine rules over text:** the list-item split (ADR 0036 Decision 3, ADR 0038
   Decision 4); delimiter stripping (ADR 0036 Decision 6) with ADR 0045 stacked on it; the
   exact-value boundary tables (ADR 0020); the substring duty rule (ADR 0024); the ASCII
   clause join; the GPT-OSS prefix salvage (§22.6); exact-text deletion of a requirement's
   last mention (ADR 0035); never-built keyword lints.
4. **Tests tied to wording:** about 45 assertions in 11 files that copy model-facing
   English; fixtures named after live runs (R31, R35, R36, R42, FIX002); about 24 scripted
   "recovers" scenarios that prove only that the engine admits a valid answer.

**Root cause.** Every change in this period was decided on one run per case, mostly on
uncommitted builds with several changes stacked, and per-run evaluation recommendations
became edits. On 27 October three hello-world runs on three different uncommitted trees
(ADR 0044, its fix and its wording; `source_sha256` `2801308d…`, `7d44c218…`,
`4e385f21…`) scored 82.14%, 82.14% and 60.71%. Their extraction, summary and dispositions
requests were byte-identical; the 60.71% came from a reconciliation repair whose identical
request (`b7ccad7311…`) answered `retained` at 05:06 and `duplicate` at 09:40. No retained
build has two valid runs of one case, so run-level noise on one build is still unmeasured;
Q1b measures it.

**Gate status (ADR 0034).** Not met: no run has been adjudicated (H1), and no committed
build has repeated runs of both cases. The three 27 October loan-renewal reports no longer
decode after Q1a (§2.13, H1). The measurement sets below produce the evidence; the user
decides when Plan is actioned.

## 2. Rules for every phase

AGENTS.md ("Model output, prompts and evidence", "Anti-overfitting rule", "Validation")
governs every phase. These rules add what FIX06 needs on top.

1. **One change set per measured build.** Relative to its comparison point (rule 9), a
   measured build adds exactly one change set. Q7 measures each decision that changes model
   input or output on its own build; Q8 measures D8.1's experiment build against the main
   build, and D8.2 and D8.3 each on its own build when they change model input or output.
   Changes that rule 11 proves leave every development-case model request byte-identical
   (Q3, Q10a and the engine track) may also be present. A change set that isn't kept is
   reverted in full, never patched on top.
2. **Owner first, offline first.** `/preflight` before editing. It names the failure class,
   its owning abstraction, the coupling the phase removes or the single owner it creates,
   and how unrelated members of the class are covered (both development cases plus an
   offline unrelated-domain fixture). A change scoped to one site, one prompt line, one case
   or one model's observed output is a local fix and out of scope. Then regression and
   negative tests at the owning boundary, comparing against owners rather than copied
   English; `zig build verify`; a `contract-reviewer` pass.
3. **Committed build.** The user commits each phase. Measurement uses that committed,
   unmodified build (`report.json` `build.source.modified` is `false`). While a set runs,
   its checkout stays at that commit with nothing changed, committed or not, under the
   build-provenance roots (owned by `build/provenance.zig`, described in
   design/harness/e2e.md: build files, `src/`, `test/`, `design/`, `scripts/` and the root
   entry files); any such change sets `modified` or moves the revision and splits the set.
   So test-track work, H3 and H4 records and design-text edits land between sets, as engine
   work does. `fixes/`, `.claude/` and `evaluations/` aren't roots: §10, B2 labels and
   evaluations can be written during a set.
4. **Measurement set.** Three runs of each development case (hello-world and loan-renewal)
   on the phase's build, interleaved with one control run of each case on the last kept
   commit (the user provides its checkout). Q1b, the first reference, takes six runs of
   each case. Each run is approved. AGENTS.md's evidence rules apply: every attempted run
   counts, and nothing is tuned on the reserved qualification features (rule 12).
5. **Evaluation of each run.** `/evaluate-e2e` (advisory), B2 labels for every review
   finding and T5's measures, per run and as minimum, median and maximum per case. Event
   counts are also pooled over the set with their opportunity (source claims,
   obligation-bearing fields, repair responses, review subjects). Acceptance comes only
   from H1 adjudication (AGENTS.md "Testing expectations").
6. **Measures** (defined and produced by T5).

   | Group | Measure |
   | --- | --- |
   | Outcome | Per attempted workload: `ok` with native publication, `failed` or `blocked`, each with its diagnostic, and whether a failed or blocked run published an incomplete specification (ADR 0041) (B1: call count is a reliability cost). Publication rate per case: native publications ÷ attempted runs; an incomplete publication doesn't count (ADR 0034). Adjudicated acceptance (R8) per attempted workload from H1 records, unknown until they exist. An advisory threshold result is reported as advisory, never as completion or acceptance |
   | Quality | Advisory aggregate; critical failures; per-criterion scores |
   | Defect classes | Lost source requirement; weakened obligation; unsupported addition; invented or restating entity (B6); restatement; rendering artefact; engine-vocabulary leak; records per records call (B5 inflation; a deterministic count from T5) |
   | Repairs | Each repair graded helpful, neutral, harmful or no progress |
   | Admission | Protocol corrections; admission rejections by reason; runaways and re-sends; admission escape (a value violating a declared native rule reaching review or publication, with downstream sends and tokens) |
   | Review | Finding-type accuracy ([e2e.md](../design/harness/e2e.md#reliability-assessment) definition), provisional until H2, with precision per predicted type and recall per labelled type at original and final assessment; detection recall; false statements; principle-citation precision (findings whose citation covers the governing principle's lines; blanket whole-file citations; details naming a principle they don't cite) |
   | Cost | Sends and actual tokens per stage (extraction and reconciliation, generation, review, repair) per attempted workload; review share; run latency; all dispatched sends, tokens and latency per acceptable (adjudicated) result, failed attempts included, unknown until H1 (ADR 0034; evaluation protocol) |
   | Brittleness | Counted at Q1b and after each phase: sites per model instruction (target one); guidance sentences without repeated-run evidence; model-facing English copied into tests; raw-string branches on schema names; model- or case-specific branches; repair sites without their step's guidance; model-facing English in Zig outside its single owner |

   Rubric-based measures (Quality, and the defect classes traced from the rubric) cover
   native publications only, and are always shown beside the publication rate per case:
   `/evaluate-e2e` scores only a completed specification, and a failed incomplete
   specification (ADR 0041) is not scored. Repairs, Admission, Review, Cost and records per
   call cover every attempted run. Published runs not yet adjudicated are reported
   separately.

7. **Keep or revert.** The user decides; this is the default recommendation for phases
   validated by measurement sets (Q2, Q2b, Q4–Q9, Q10b, Q10c and Q11's runtime decisions).
   Q3, Q10a, D7.1, D7.3, D11.2 and the engine items are decided by their own validation.
   - **Before the set,** the phase records its target measures as event counts with their
     unit, opportunity and direction; its guards (lost source requirement, unsupported
     addition, a critical criterion below its minimum, harmful repair, publication rate per
     case); and its maximum of eight runs per case.
   - **Improvement.** The pooled target count improves under a one-sided conditional
     binomial test at p ≤ 0.10, and doesn't worsen in either case where the reference shows
     the class.
   - **Guards.** No guard count rises under the same test; the publication rate per case
     doesn't fall; and no defect class absent from the reference appears with an
     `established` trace to the changed owner.
   - **Hygiene and non-inferiority phases** (Q4, Q5, a withdrawal in Q8, Q9) remove input
     without targeting a recorded defect; they are kept on the guards alone, plus the
     measures their **Keep if** line names.
   - **Stopping.** Look after three runs per case: stop and report on traced harm or a
     decided result; otherwise extend by two or three runs per case with approval, up to the
     maximum. Never sample until a preferred answer emerges.
   - **Not enough evidence.** A target with fewer than about ten events across the two
     states, or still undecided at the maximum, is reported as "not enough evidence"; a
     target absent from both states of a case is "benefit not demonstrated" for that case.
   - Advisory aggregate and criterion scores are reported as minimum, median and maximum
     but decide nothing alone: one criterion step is 3.57 points, and three runs detect a
     one-step shift about half the time.
   - Use "kept", never "accepted": only H1 adjudication is acceptance.
8. **Reporting.** Report AGENTS.md's five evidence statements separately. Passing tests,
   fewer calls or higher admission alone close no semantic gate
   ([intent](../design/intent.md)). Results go in §10.
9. **Comparison point.** Each measured phase is compared with the last kept measured
   state: every run on its commit, control runs included. Q1b sets the first. A change
   proved under rule 11 doesn't move it.
10. **Model limitations.** [AGENTS.md](../AGENTS.md#model-output-prompts-and-evidence)
    owns this rule and its three recorded exceptions, including the §22.6 prefix
    normalization (D11.4) (the evaluator's correction is recorded in
    [Z_FIX05 §15](Z_FIX05.md#15-grader-one-shot-correction--18-october-2026)). FIX06 adds: no
    caps that discard output.
11. **Engine-track work** (§5) changes no model input, except E7's answer-bearing requests.
    It is proved offline on the scripted integration matrix, against a freeze retaken on
    the commit before it lands, with two parts:
    - **(a) Behaviour.** The item reproduces the freeze its ADR defines ("Freeze first" in
      ADRs 0030, 0031, 0032 and 0033). Items without one (E0, E5, E6, E8) use the ADR 0030
      step traces and summaries: outcomes, retries, token accounting, and published and
      state files. Each states its expected differences before landing, such as E0's
      failure-path publication or E5's rejection reasons.
    - **(b) Requests.** Every accounted request's T5 projection is byte-identical.

    It needs one live run of each case and lands only between measurement sets, never
    during one. Quality phases take priority.
12. **Evaluation protocol.** The [evaluation protocol](../test/calibration/semantic-simplicity/README.md)
    owns its 24-feature panel: the panel's case partitions (including the sixteen reserved
    qualification features), and the scoring, numeric gates and experiment stops for the
    panel's own baseline, selection and qualification (H4). FIX06's measurement sets use the
    two development cases, which aren't panel features, so they aren't protocol
    experiments; rules 1–11 govern them. Their runs may still serve as native cost evidence
    for H4.
13. **Adjudicability.** `adjudicate-spec` decodes `report.json` strictly, so a change that
    removes or renames a closed member a retained report carries strands that report: a
    `DataKey` in `corrections` or `outstanding_work`, an operation error name, a candidate
    rule. Candidates include E1's request-lifecycle operations, E4's repair data keys, E5's
    split of `OperationExecutionFailed` and rule withdrawals in Q7, Q8 or Q11. Such a change
    lands only after H1 has adjudicated the published measurement-set runs it would strand,
    or after the user records that they stay unadjudicated. **Adding a member is not safe
    either** (corrected 28 October 2026): the strict decoder rejects an object whose member
    count differs from its type's field count, so a missing member fails like an unknown
    one even when the field has a default (`src/domain/strict_json.zig`, `wireTypes`). Any
    new report member therefore needs a report version and strands the earlier version on
    newer builds. Alternative **Decision** for the user: adjudication decodes only the
    members acceptance needs.

**Boundary gates** for contract changes (carried from FIX05 §7, `git show
28ff156:fixes/FIX05.md`, which took them from the deleted FIX01 §5 "Acceptance and
feasibility gates", text at `b2f10a3`):

| Boundary | Required positive evidence | Required negative evidence | Applies to |
| --- | --- | --- | --- |
| Summary representation | Combined, split and overlapping expressions; complete membership; stable identities and evidence | Missing or foreign IDs, altered categories, false support, changed exact values, conflicting interpretations | Q8; R summary hierarchy |
| Normalization | Idempotence; same-evidence duplicates collapse; raw and provenance retained | Same text from different occurrences, distinct obligations, non-equivalent paraphrases, destructive truncation | Q8 (D8.3); R summary hierarchy |
| Native carry-forward | Empty, non-final, final and one/many-child routing; identical current child and evidence; complete lineage | Stale or forged child content, changed evidence, token duplication, fabricated origin, skipped final semantic work | R summary hierarchy |
| Repair | Exact target and dependencies, protected siblings, progress, full final validation | Stale authorization, widened scope, reset allowance, invalid survivor, unsupported verdict change | Q2, Q2b, E4, R6 |
| Loss attribution | Bound comparisons locate candidate-only and genuine upstream loss; dependencies and evidence retained | Missing or duplicate assignments, contradictory outcomes, uncertain owners treated as certain, lost source-only omissions, false upstream rebuilding | R6 |
| Exact-value representation | Occurrences recorded from exact bytes in bound fields; identity survives repair and readback | False matches, ambiguous occurrences, unbound fields, changed obligations | Q7, R6 |
| Loss-evidence correction | The narrow correction preserves subject, finding and scope; native validation reruns before repair | Nonexistent lines, stale producers, verdict replacement, budget or attempt reset, repeated defect | R6 |
| Cross-model behaviour (only when the user changes or compares models, H5) | Paired repeated trials in unrelated domains; all declared outcomes and costs | Meaning changed despite valid JSON and IDs; false rejection, unsupported acceptance, inconclusive or unusable results | H5 |
| Whole workflow | Real publication of the case's expected outcome (a failed or blocked run's incomplete publication under ADR 0041 doesn't count), complete required review, and human adjudication ([R8](../design/harness/acceptance.md), H1) | An early stop reported honestly; no golden outputs, fabricated E2E success, offline substitute, or advisory analysis presented as acceptance | Every measurement set, E0 |

Offline unit and integration tests prove native mechanics only: for normalization, for
example, that only exact same-evidence duplicates collapse and that paraphrases and other
occurrences stay separate ([16-reference-ingestion.md](../design/contracts/16-reference-ingestion.md)).
Negatives that turn on meaning are judged only in live measurement sets, against
human-reviewed labels (rule 5, H1, H2). They never require native code to judge meaning
(§9), and never require a new judge. Phases whose boundary has no row (Q3–Q6 prompt
ownership, Q10 review, E0 failure publication) are governed by their own validation and,
for E0, ADR 0041's tests.

## 3. Sequence

Tracks: **Q** quality phases (model-input changes, each measured; the critical path), **E**
engine work (no model-input change except E7's answer-bearing requests; §2.11), **T**
tests (offline, between measurement sets), **H** human and decision items, **R** research
and backlog. "Gap" means between measurement sets.

| Step | Item | Validation | Decisions |
| --- | --- | --- | --- |
| 1 | **Q1a** Remove ADR 0044 and the records-prompt line; hold ADR 0045 (**done**, `d4fd4a5`) | Offline | D1.1, D1.2 (decided) |
| 2 | **Pre-baseline decisions** (**decided 28 October**, as recommended): D2.1 (b), E0's report marker (as an optional v10 member; reopened under rule 13 and decided 29 October as a `spec-e2e-report/v11` member, step 3), the H2 label scheme, D11.2 (keep, contract, shared terminal policy), D11.4 (name the exception), DE6 (always emit ADR-required events), D11.5; D11.2, D11.4, D11.5 and DE6 implemented | Decisions; offline | D2.1, D11.2, D11.4, D11.5, DE6 (decided) |
| 3 | **T5** measures and request projections, with `spec-e2e-report/v11` (decided 29 October); **T1**; D11.1 docs; all committed before the set (D11.2 and D11.5 were done in step 2). H1 may start on the clean 26 October `39a06ea` pair | Offline | — |
| 4 | **Q1b** Clean baseline, six runs per case, on the committed build; Q2's pre-phase replays alongside | Measurement set | T5's definitions (approved 29 October); DT5 (decided and implemented 29 October) |
| 5 | **E0** Failed and blocked runs publish validated content (B10, ADR 0041): built during Q1b, landing after it and before Q2's set | Stopped 30 October 2026 (user decision); ADR 0041 on hold | Accepted; DE6 decided first |
| 5a | **D4.1 correction** The `uncovered_member` correction names the kinds that count as cover, from the compiled coverage rule (moved ahead of Q2 on 30 October 2026, user decision: Q1b's two loan-renewal failures were this correction making no progress) | Measurement set (correction never fired) | Decided, implemented and kept 30 October |
| 6 | **Q2** Repair requests carry their step's definitions (one generic owner), with **T3** | Paired replays decide the target; measurement set guards | D2.1 |
| 7 | **Q2b** Generic content-loss guard for repairs (deferred 30 October 2026: D2.2 decided no for now; reopen on a harmful repair) | Measurement set | D2.2 (deferred) |
| 8 | **Q3** One owner per model instruction (move only), with **T2** (**done** 31 October 2026) | §2.11 projections byte-identical, one run per case | D3.1 (decided) |
| 9 | **Q6** Scope "preserve obligations" to the fields D6.1 names, with the in-request dedupe (built and measured before Q2 and Q3 on 30 October 2026, then reverted: not kept) | Measurement set | D6.1 (b), decided 30 October |
| 10 | **D7.1** Exact-value corrections state the boundary rule | Offline; byte-identical requests | D7.1 |
| 11 | **Q4** Remove engine vocabulary and schema-stated rules (hygiene) | Measurement set (guards) | D4.1 |
| 12 | **Q5** Remove unmeasured single-run sentences (hygiene) | Measurement set (guards) | D5.1 |
| 13 | **Q8** Source-claim granularity (B7) | Measurement set on the experiment and main builds | D8.1–D8.3 |
| 14 | **Q10b** Simplify the source-review taxonomy (B2) | Measurement set, B2 labels after H2 | D10.2 |
| 15 | **Q10a** Publish source-review findings as advice (B2) | Byte-identical requests, one run per case, B2 labels | D10.1 |
| 16 | **Q10c** Principle-review citations (B11) | Measurement set, B2 labels | D10.3 |
| 17 | **Q7** D7.2 delimiter stripping with ADR 0045 (measured); D7.3 token duties (offline) | Measurement set (D7.2); offline (D7.3) | D7.2, D7.3 |
| 18 | **Q9** Reconciliation call structure (W4): capture replays (before E4), then a measurement set | Capture replay, measurement set | D9.1 |
| 19 | **Q11** D11.3, and D11.4 if the salvage is withdrawn, each its own set | A measurement set per runtime decision | D11.3, D11.4 |
| 20 | **Closing set** on the final build (ADR 0034 gate evidence) | Measurement set | — |

**Engine track, in gaps:** **E2** (A2, with W5) in an early gap after E0; **E1** (A1, ADR
0030 slice 4) after Q2 is kept, retaking its freeze with T5's projection; **E3** startup
after E1; **E6** fixes in any gap, with **DE6** decided before E0; **E8** typed
schema-definition identities in any gap; **E4** (W3, ADR 0033) after E1, E2's measure,
Q9's capture replays and D9.1; **E5** (A4) folded into E1–E4; **R-A1** after E1; **E7**
(R2) last. E1, E4 and E5 land only under §2.13. **Tests:** T1 and T5 before Q1b; T3 with
Q2; T2 with Q3; T4 when E2 and E3 rewrite tests. **Human:** H1 now and for every set; H2's
scheme before Q1b and its confirmation before Q10b; H3 and H4 in gaps before any formal
baseline freeze; H5 whenever the user chooses. **R** items after the phase that produces
their evidence.

**Why this order.**
- **Measure before changing.** T5 must exist before Q1b, or no set can be compared (§2.6).
  Decisions that change no model input but change rendering or the report (D11.2, E0's
  report marker) are settled first so every measured run shares them.
- **Baseline first, then E0.** `adjudicate-spec` reads only `report.json` and its embedded
  capture, and `e2e-call` replays captured requests without compiling definitions, so
  `workflow/v2` strands no run. E0's report marker ships in `spec-e2e-report/v11` with T5
  (decided 29 October; rule 13), so E0 changes no report version. E0 changes no model
  input and no outcome measure (a failed
  run that publishes stays failed and isn't scored), so it doesn't need to delay the
  baseline. DE6 comes first because E0 adds a required warning event.
- **Harm before polish.** Q2 fixes the only observed requirement loss; Q2b guards against
  repairs that drop content. Both precede E1 and E4, which must then preserve Q2's
  bindings.
- **One owner before content edits.** Q3 moves ownership without moving bytes, so Q4 and Q5
  each edit one place. Q6 was tried first anyway (30 October 2026, user decision) and
  reverted; Q2's replays on "the last pre-Q2 build" include D4.1.
- **Hygiene after the targeted fixes.** Q4 and Q5 have no improvement target and are kept
  on guards alone. D7.1 lands before Q4 so corrections already state the boundary rule.
- **Granularity on settled prompts.** Q8 follows Q4 and Q5 so its two arms share the final
  extraction prompts.
- **Review after generation settles.** Q10b assesses what generation produces and needs
  H2's labels; Q10a publishes advice only once Q10b has made it more accurate.
- **ADR-level text rules late.** D7.2 needs repeated rendering evidence; D7.3 is offline.
- **Q9 last.** It has the lowest value and the highest risk, its call count depends on Q8,
  and its capture replays must precede E4, which may change the capture format.
- **Engine work in the gaps.** ADR 0034 puts Spec quality first; engine items claim no
  quality change and land between sets, in ADR order, under §2.13.

## 4. Quality phases (Q)

### Q1. Remove the rejected patches and take the clean baseline

**Q1a: done 28 October 2026, committed as `d4fd4a5`** (the user's "implement Q1a"). D1.1:
ADR 0044 was deleted, as ADR 0027 was; its text and evidence stay in Z_FIX05 §21 (B7). D1.2:
the records-prompt line is removed. The seven code and test files were restored to their
`28ff156` content, which differed from `d74fc1f` only by ADR 0044, and
`obligation_strength.zig` was deleted. ADR 0045 is on hold: its status line, ADR 0020's and
ADR 0036's amendment notes and its §32 row say so, and text-field-composition.md is back to
its pre-ADR-0045 text. Verified: `zig build verify` (164 of 164 steps, 1,969 of 1,969
tests); no tracked file outside `fixes/` names `weakened_obligation` or
`obligation_strength`; a contract review found no code issues. Obligation weakening in
generated text is recorded as a model limitation (B7); claim-by-claim restatement (B5) is a
symptom for Q6 and Q8.

**Q1b baseline.** After Q1a and the pre-baseline steps (§3), six runs per case on the
committed build. Expected, and recorded rather than fixed: loan-renewal's story may say
"may renew" (FR-001 keeps the source wording) and hello-world's business rules may restate
FR-001. **Exit:** the baseline table in §10, with every measure produced by T5.

### Q2. Repair requests carry their step's definitions

**Goal.** No repair decides without the definitions its original request had, through one
generic owner rather than per-site wiring.

**Changes.** Each repair request also carries the definitions of the step it repairs,
beside `repair.prompt.md`. The support repair already does this (`prompt: {param:
prompt}`, `spec.workflow.yaml:713-718`).
- **Reconciliation repair** (`repair-reconciliation-candidate`, line 605, reached from 521
  and 589): `reconciliation.prompt.md` for a summary target; the dispositions, signals or
  conflicts prompt for those targets.
- **Source-omission reconciliation repair** (909): the dispositions, signals or conflicts
  prompt of its target.
- **Specification-unit repair** (811): the unit's prompt (`{param: prompt}`).
- **Extraction text repair** (371, the no-feature-claim reason): `extraction-content.prompt.md`.
- **Classification repair** (408): `extraction-classifications.prompt.md`.
- **Source-omission extraction repair** (894): the content prompt for a claim or outcome
  target; the classifications prompt for a classification target.

Context bindings don't change. At 589, 894 and 909 one site serves several steps, so the
definitions follow the authorized target, never a per-site value; the engine never chooses
a prompt (12-model-boundary.md:361-364).

**Decision.** **D2.1** (**decided 28 October 2026: option (b)**; implemented in Q2) How a repair request gets its step's definitions. Today a request
binds one task `prompt`, an optional `context` and an optional `protocol-prompt`, ADR 0030's
`request-model` declares the same, and diagnostic capture allows one resource per role. A
step prompt's whole-task sentence can't sit beside "Return only the selected replacement"
unchanged (ADR 0016:200-203). Options:
- **(a)** a second, ordered task-prompt binding: a new request parameter and capture role;
  605 split per phase; 894 and 909 routed per kind; the step prompts' task sentences given
  a form that is safe in a repair;
- **(b)** each step's definitions move into one shared resource per phase family (a new
  reconciliation context, and the existing extraction and generation contexts), bound by
  the step request and its repairs; task sentences stay in the step prompts and
  `repair.prompt.md` stays the only repair task. No new binding or per-target routing;
  initial request bytes change;
- **(c)** as the support and principle repairs do, bind only the step's prompt and delete
  `repair.prompt.md`, which puts a repair clause in every step prompt and conflicts with
  Q3's one owner.

`/preflight` confirms the owner (contract 12 at 361-373, contract 22 at 437-438,
`PrepareModelRequestAction`, ADRs 0016, 0019, 0030 and 0033) before any recommendation. It
amends contract 22:437-438 ("Native unit repair uses the configured repair prompt …").

**Offline validation.** For every repair site and target kind, the repair request's static
developer content carries the repaired step's definitions, compared with the resource
itself; the user-content packet is byte-identical to before.

**E2E validation.** Repairs are rare: the 28 retained runs of 24–27 October hold four
reconciliation-repair calls, all in two hello-world runs on 27 October. The targeted effect
is decided on paired replays of identical captured state:
- **Capture.** `zig-out/e2e-spec/2026-10-27T09-40-42Z-26e5a21c5438c853bbfb338b62d42247`, call
  6 (the dispositions insert repair for the UTC claim, right answer `retained`); its request
  `b7ccad7311…` answered `retained` at 05:06 and `duplicate` at 09:40. Control: call 5
  (claim 2, correctly `retained`). Add every other retained repair request at a Q2 site
  whose trigger survives Q1a.
- **Old request.** `e2e-call --repeats 20` with the captured settings, on the last pre-Q2
  build while it can still load the `model-request-debug/v13` capture.
  **Done 29 October 2026** on the Q1b build (`openai.gpt-oss-20b-1:0`, `low`): call 6
  answered `retained` 19 times and `duplicate` (target claim 2) once, which would drop the
  UTC claim (harmful); control call 5 answered `retained` 20 times. All 40 exchanges
  completed and were schema-valid; 39 needed the §22.6 normalization (37 leading brace
  quote, 2 repeated field prefix). Reports: `zig-out/e2e-call/2026-10-29T09-18-37Z-d0b3…/`
  (call 6) and `…-404a…/` (call 5).
- **Q2 request.** The same requests with the repaired step's definitions added as Q2 binds
  them, sent by `e2e-call` with `--repeats` from an edited-content file (decided 30 October
  2026: a small T-track change reusing the debugger's modified-replay validation, ADR 0019;
  implemented 30 October as `e2e-call --edit <file>`),
  run on a copy of the retained project under `evaluations/`, never on `zig-out/`. Record any
  difference from the request the Q2 build assembles.
- **Counting.** Read each repeat's returned disposition, grade it helpful, neutral, harmful
  or no progress, and count every requested repeat, including failed exchanges. Both right
  answers are `retained`, so report that the replay can't separate an improvement from a
  lean toward `retained`. Each replay needs approval.

Then the measurement set on both cases, grading every repair, as the end-to-end guard.
**Keep if** harmful and no-progress responses fall on the paired replays and no guard rises
in the set (§2.7).

### Q2b. Generic content-loss guard for repairs

**Decision.** **D2.2** A repair that drops untargeted content passes native revalidation:
on 27 October 09:40 loan-renewal's story became the quoted claim with its list marker, and
revalidation and both reviews passed it (one observation). Decide a generic revalidation
guard limited to what the engine computes reliably. A replacement is rejected as the same
repair's defect, within the existing allowance and adding no retry, when it loses an
exact-value occurrence the old value had, or a claim ID the old record named, unless the
authorized defect concerns it. Fields without claim IDs get no text-similarity check; loss
there is graded as repair harm and reported. Amends contract 22 (§22.4 and the value-only
repair rule).

**Decided 30 October 2026: no for now, deferred** (user decision). The only observation came
from ADR 0044's repair, removed in Q1a; no harmful repair has been seen since (Q1b, D4.1's
and Q6's sets), the guard might not have caught that case, and it could block legitimate
repairs. Reopen D2.2 if a harmful repair appears on the current build.

**Validation.** Its own measurement set after Q2. **Keep if** harmful repairs fall and
neither `RepairNoProgress` nor exhausted runs rise.

### Q3. One owner per model instruction

**Goal.** Every instruction the model sees exists in exactly one place.

**Changes.** Move semantic guidance written in Zig into workflow resources: field purposes
and review scopes (`required_authority_description.zig`), the summary purpose
(`reference_model_input.zig`), the support evidence guidance
(`specification_support_evidence.zig`), and the semantic tails of native repair
requirements and corrections ("preserving its source meaning",
`specification_repair.zig:132`; "Preserve the fixed evidence and source meaning",
`specification_provenance.zig:193`). Before moving a string, classify it as a mechanical
diagnostic or as semantic guidance; identity, coverage and sibling-order requirements stay
native (`specification_repair.zig:82-83`, `reference_reconciliation_repair.zig:174`). The
compiler rejects a registered field purpose or review scope with a missing or extra
resource entry.

Q3 only moves ownership: each instruction is produced from its new owner at its current
position, so no request's bytes change. Copies that never reach the same request merge into
the one owner. A duplicate inside one request (for example `generation.prompt.md:2` and
`generation.context.json`'s `business_value`, both in the brief request) stays until a
measured phase removes it, because removing it changes model input.

**Decision.** **D3.1** Which layer owns semantic guidance. Recommended: the workflow
resources (contract 12: "the workflow supplies prompt content"), with the native field
registry keeping only mechanical explanations, and the native packet builder writing
resource-owned text at its current packet positions. Amends text-field-composition.md:47-48,
12-model-boundary.md:369-371 and 758-759, and ADR 0016:124-127 ("Canonical native
validators and requirement descriptions remain the sole rule and purpose owners"). If that
placement isn't adopted, Q3 changes model input and is measured like any quality phase.
**Decided 30 October 2026: option (a)**, workflow resources own semantic guidance (user:
"D3.1 - option 1 - approved!"); Q3 implementation started the same day. Design choices
approved 30 October 2026: one closed `packet-guidance/v1` resource
(`design/workflows/spec/packet-guidance.json`, 48 entries) compiled and checked for exactly
one entry per registered key; one capture step publishes it for the run and the 19 consumer
operations read it from run data; clarification questions stay native (user-facing); the
entity-repair resource entry is only its meaning tail; source-omission evidence drops its
stored `purpose` copy; mechanical sentences inside moved blocks move with them (Q4 edits them
there). Slices S1 infrastructure and summary purpose, S2 purposes, S3 review scopes and
evidence guidance, S4 repair tails, S5 close-out; each keeps every request byte-identical.
**S1 done 30 October 2026:** the resource, `packet-guidance/v1` compiler checks, the
`capture-packet-guidance` step and `.packet_guidance` run data; the summary purpose reads
from the resource; contract 12, ADR 0016 amendment and the action catalogue updated.
Request projection identical to `d41-2026-10-30` (198 scenarios, 4,406 calls); `zig build
verify` 169/169 steps, 1,993 tests.
**S2 done 30 October 2026:** feature purposes, record families, record fields and reference
tasks (27 entries) read only from the resource; their Zig copies are deleted. O3 removed the
stored comparison `purpose`, which repair requests also present, so a generic
`model_presentation.zig` contract re-presents stored evidence from the guidance at its
request position. A compile-time guard rejects model input that reaches an unpresented value,
and it moved support repair onto the presenting path too. Request projection identical to
`d41-2026-10-30`; `zig build verify` 169/169 steps, 1,995 tests.
**S3 done 31 October 2026:** review scopes (11) and support-evidence guidance (7) read only
from the resource; the evidence owner's one `selection_instruction` is presented in initial
review, insertion and repair. Tests check every marked entry by its wire path, without
calling the code under test. Request projection identical to `d41-2026-10-30`; `zig build
verify` 169/169 steps, 1,996 tests.
**S4 and S5 done 31 October 2026:** both repair tails read from the resource;
`authorize-specification-repair` composes them when it authorizes (coverage repair places no
tail). All 52 resource texts are absent from Zig, and contract 12 and ADR 0016 describe the
finished state. Request projection identical to `d41-2026-10-30`; `zig build verify` 169/169
steps, 1,997 tests. Live runs 31 October 2026 (user-approved), both published:
hello-world `2026-10-31T00-46-30Z-1a6191e1…` (22 calls, 58,147 tokens, advisory 100%) and
loan-renewal `2026-10-31T00-47-05Z-6258a7a8…` (26 calls, 105,120 tokens, one review runaway
re-sent, advisory 89.3%); live requests carry the resource texts. Q3 is complete. Observed in
review, outside Q3: `ValueChoices.correction`'s rejected exact-copy arm has no production
producer.

**Validation.** T5 request projections byte-identical (§2.11); tests compare against the
owning resource; one run of each case.

### Q4. Remove engine vocabulary and schema-stated rules from prompts

**Changes** (quoted, because earlier phases shift line numbers):
- Remove engine vocabulary and restated engine behaviour: the words "native", "engine",
  "canonical", "structural" and "provenance"; "The engine binds claim evidence", "Tokens are
  read-only native facts", "Kind … does not decide whether the engine requires exact
  preservation", "Family presence is structural", and its twin in the support request,
  "Native code fixes claim evidence for the assigned subject" (in its Q3 owner); and the
  second sentence of `extraction.context.json`'s `citations` entry ("The cited lines become
  the claim's wording; lines from several top-level list items become one claim per
  item."), which describes a native transform no response can violate.
- Remove a restated rule only where the schema or the engine's correction states it: "one
  entry for every assigned requirement_ordinal, exactly once" in the support and principle
  prompts (`exact_members`; a repeated member gets `duplicate_member`, a missing one
  `array_length`).
- Keep as task semantics, rewording only their engine vocabulary: "Each record's claim_ids
  name the assigned requirements it states." (the only definition of claim_ids); "Every
  claim a functional requirement names must also be named by an acceptance criterion or edge
  case that tests it." (`uncovered_member` defers to it, and "that tests it" is meaning the
  engine doesn't check); the forced-preservation sentences of
  `extraction-classifications.prompt.md` (their violation is a repair whose rule carries
  only candidate IDs); and the first `citations` sentence.

**Decision.** **D4.1** Prompts carry task semantics only. An engine-enforced rule leaves a
prompt only when the schema or its correction states it. Making a correction state a rule
(naming the covering kinds in `uncovered_member`, or explaining `required_preserve`) changes
model-visible engine text and would be a separate decision with its own measurement set.
**Decided 30 October 2026** for `uncovered_member` (sequence step 5a, ahead of Q2): the
correction names the covering kinds, taken from the compiled coverage rule, never
hard-coded. `required_preserve` is unchanged. Implemented 30 October 2026: the `uncovered_member` diagnostic carries the
compiled rule and its correction adds `covering` (`kind_property`, `kinds`); every other
correction is byte-identical: the request-projection freeze
(`evaluations/request-projection/d41-2026-10-30/`) differs from the step-3 base in exactly 4
of 4,406 requests, all `uncovered_member` corrections. Contract review (one major: the
owner comparison never ran; two minor) fixed: a real uncovered case in the payload test, the
driver compares with `specification_session.scenario_coverage`, the correction rejects a
covering rule on any other reason, one serialization; the fixed build's freeze is
byte-identical. Measurement set approved 30 October 2026 and running on the latest build;
run 1 (hello-world, `2026-10-29T19-56-29Z-919b…`) used the pre-fix build, whose requests the
freeze proves identical, so it counts. **Set result (30 October 2026):** hello-world 3 of 3
published, loan-renewal 2 of 3 (one `WorkflowTokenBudgetExceeded`: review 98,870 and repair
7,806 tokens); no run had an `uncovered_member` rejection, so the correction never fired and
every request matched the Q1b build's. **Kept by user decision** without evaluations or
control runs (`evaluations/e2e/d41-measures-set.json`).

**Validation.** Scripted responses with a missing and with a repeated member, for source and
principle reviews, receive the `array_length` and `duplicate_member` corrections, compared
with the owning explanations; sentences kept as task semantics are unchanged in the
assembled requests. Then the measurement set. **Keep if** (hygiene, §2.7) engine vocabulary
in published specs stays absent, and protocol corrections, admission rejections by reason,
other defect classes and cost stay within the comparison point's range. The class is
already at zero (none of the 13 specs published on 26–27 October contains engine
vocabulary; hello-world's "exact text" is plain English), so Q4 can't show a gain. Never
rename a field to chase an observed leak.

### Q5. Remove unmeasured single-run sentences

**Changes.** Remove these sentences, keeping each definition sentence around them:
- `extraction.context.json`: "Include meaningful identity and purpose headings." (`5a4001f`)
  and "Separate independent behavior, implementation and verification facts." (`d247a9c`) in
  `claims`; the second sentence of `business`, `technical` and `validation` ("Preserve
  technical qualifiers with the behavior.", "Technical terminology alone does not make
  observable behavior technical.", "A behavioral requirement being testable does not make it
  a validation claim."; `d247a9c`). "One independently meaningful source fact per entry."
  stays; claim granularity is Q8's.
- `support.prompt.md`: ", including compatible requirements labelled conflicting" and
  "Empty claims or conflict labels do not establish a source gap." (`ebbe968`) and "A
  defective candidate is not a source gap." (`bdbae22`).
- `records.prompt.md`: "Do not relabel positive requirements as assumptions or non-goals"
  (`433ccf7`), keeping the rest of its sentence.
- The field-purpose clauses, in their Q3 owner: "The source need not supply a title"
  (`212a12c`), "do not invent a persona or benefit or require a prewritten story"
  (`35ded13`) and "Displayed values alone do not establish entities…" (`433ccf7`; its
  32-call comparison was prepared, never run).

**Decision.** **D5.1** Remove them together as one change set (hygiene, §2.7). If a watched
class worsens, revert Q5 in full (§2.1); restoring or keeping a single sentence is a new
phase with its own measurement set, recorded here with its evidence. Amends
17-specify.md:238-240 (the title and persona clauses) and 12-model-boundary.md:769-771 (the
displayed-values clause).

**Validation.** Measurement set, watching title gaps, invented personas, entities invented
from displayed values, misclassified technical and validation claims, and compatible claims
labelled conflicting. **Keep if** those classes and the guards don't worsen.

### Q6. Scope the obligation instruction

**Changes.** "Preserve conditions and obligations" reaches only the fields D6.1 names; every
other generated field keeps its purpose only. Today it reaches the brief
(`generation.prompt.md:2`), every field (`generation.context.json`'s `business_value`), the
story (its purpose) and every record family (`records.prompt.md:2`). One edit, in the Q3
owner, which also removes the in-request duplicates Q3 left. Exact-copy roles and coverage
don't change: an exact value in a description, story or user-visible outcome still
satisfies coverage (ADR 0020; text-field-composition.md:57).

**Decision.** **D6.1** Which generated fields carry the instruction:
- **(a)** the fields text-field-composition.md:57 calls obligation-bearing (brief
  description; story; acceptance-criterion given, when and then; user-visible outcome; edge
  condition and outcome; functional requirement; business rule; non-goal; prohibited
  behaviour), which keeps it on the description and story where FR-001's restatement
  appears; or
- **(b)** a narrower set (functional requirements, acceptance criteria, edge outcomes,
  business rules and prohibited behaviour, with edge conditions and non-goals placed
  explicitly), called "the scoped fields", while description, story and user-visible
  outcome keep their obligation-bearing exact-copy role.

Either way, amend the shared field purposes (17-specify.md:238-239) and
`generation.context.json`'s `business_value` guidance. Changing an exact-copy role is not
part of Q6.

**Decided 30 October 2026: (b)**; built, measured and **reverted in full the same day (user
decision, not kept)**. The build made the field purposes the single owner: `business_value`
ended at "Fulfil the assigned field purpose.", the brief and story lost the instruction, and
the functional-requirement, acceptance-criterion, edge-case, business-rule, non-goal and
prohibited-behaviour purposes carried it (1,026 of 4,406 requests changed). Its set, three
runs per case against Q1b: restating entity meanings 4 of 5 published (Q1b 8 of 10), stories
still restated FR-001 in all five, one lost source requirement (hello-world dropped the UTC
requirement; Q1b none), loan-renewal 2 of 3 published (one token-budget failure). The target
didn't improve and a guard got worse, so §2.7 reverts it. Restatement needs another lever.

**Validation.** Measurement set. **Keep if** restatement improves, and lost requirements and
weakened obligations in requirements and acceptance criteria don't worsen.

### Q7. Exact values

**Decisions.**
- **D7.1** When an exact value is rejected, the correction states the boundary rule,
  generated from the closed boundary policy (`exact_value_boundary.zig`), never from a
  prose list.
- **D7.2** Decide ADR 0036 Decision 6 (delimiter stripping) and ADR 0045 (B12) together. ADR
  0045 is a symptom fix stacked on Decision 6, so the default is to decide Decision 6 at its
  owner, and build ADR 0045 only if Decision 6 stays and repeated runs show the artefact.
  Either outcome updates ADR 0045's hold sites (its status line, the notes in ADR 0020 and
  ADR 0036, its §32 row). Implementing it restores its text-field-composition.md amendment
  (`git show d74fc1f:design/contracts/text-field-composition.md`: the preamble, the
  incidental-occurrence sentence, the inventory rows, the section heading and its anchors,
  the prohibited-role list and the incidental-role bullet); withdrawing it removes those
  references. Markdown in claim wording (B7) is measured here.
- **D7.3** Whether a token's appearance inside a claim uses the same boundary as recognition,
  so short tokens inside words no longer create duties. Amends ADR 0024's substring rule.

The boundary tables are never extended case by case; any change to them is decided from
rejections counted by reason across measurement sets (none so far).

**Validation.** D7.1 and D7.3 are deterministic and decided offline: accepted and rejected
fixtures at their owners (`exact_value_boundary.zig`, `exact_token_obligation.zig`); a
scripted rejection receives a correction that states the boundary rule, compared with the
owner; and development-case requests are byte-identical before and after (§2.11). The 28
retained runs of 24–27 October contain no exact-value rejection and no `missing_exact_copy`
repair, and neither development source has a short token, so no measurement set can
exercise either. D7.2 changes published output and gets a measurement set. **Keep D7.2 if**
rendering artefacts fall on loan-renewal and no guard rises.

### Q8. Source-claim granularity (B7)

**Changes.** An experiment build on its own committed branch with the list-item split
disabled; the main build keeps it.

**Decisions.**
- **D8.1** Keep, change or withdraw ADR 0036 Decision 3 and ADR 0038 Decision 4. ADR 0038's
  scenario-coverage rule depends on per-item claims, so a withdrawal must say how coverage
  is kept.
- **D8.2** Whether ADR 0036's "cites in full" includes a fenced block's blank first or last
  interior line (otherwise a token's bytes can fall outside the quote).
- **D8.3** Whether identical citation sets are a native duplicate.

**Validation.** A measurement set on the D8.1 experiment build and on the main build; D8.2
and D8.3 each on its own build when they change admission or correction (§2.1). Measures:
claim counts, conditions separated from their items, restatement (including claim-by-claim
business rules), claims lost in reconciliation, scenario coverage and cost. **Keep if**
(withdrawing the split, non-inferiority) claims lost in reconciliation and restatement
don't worsen, conditions stay with their items, and scenario coverage doesn't fall.

### Q9. Reconciliation call structure (W4)

Even a three-line source needs two extraction calls and four reconciliation calls (summary,
dispositions, signals, conflicts) before authoring; reconciliation is the largest stage.
The split is deliberate: [ADR 0022](../design/decisions/0022-native-reference-phase-handoffs.md)
requests, validates and repairs each phase before requesting its descendants, feeding each
the previous phase's validated native facts (§16.4 step 10, normative), through
[ADR 0016](../design/decisions/0016-configured-json-response-composition.md)'s assignment
contexts. ADR 0016 itself calls smaller responsibilities "a reliability hypothesis, not a
demonstrated cure".

**Changes.** First replay retained captures (from raw response bytes, or captures made after
ADR 0030 slice 3, whose catalogues carry `requestTimeoutMs`) to test whether separate
dispositions, signals and conflicts calls change claims, groups or conflicts compared with
one combined call on small and single-source inputs. The replays run before E4, which may
change the capture format.

**Decision.** **D9.1** Combine the calls only on that evidence. This amends ADR 0022 and
§16.4 step 10, ADR 0016's assignment-context amendment and ADR 0033's per-phase repair
owners, and must say how a combined response is validated phase by phase and how a defect in
one phase is repaired without re-requesting the others.

**Validation.** Measurement set. **Keep if** reconciliation sends and tokens per attempted
workload fall, while claims lost in reconciliation, groups, conflicts and completion don't
worsen.

### Q10a. Publish source-review findings as advice (B2)

**Decision.** **D10.1** Amend ADR 0023: negative source-review findings appear as an
advisory section in `reference-context.md`, as principle findings already do; they never
repair content or create clarifications. On 27 October 09:40 source review flagged
hello-world's lost UTC requirement three times, and the reader never saw it.

**Validation.** Rendering tests from typed findings; byte-identical requests (§2.11); one run
of each case; the measurement sets' B2 labels show how many published findings are true.

### Q10b. Simplify the source-review taxonomy (B2)

Review takes about 79% of tokens and catches little. On 26 October (one label set,
provisional until H2) source review found 1 of 28 defective subjects with the right type and
wrote 26 false statements. Quality over cost: no check is dropped to save tokens, but
spending that buys no quality is removed at its owner.

**Changes.**
- Fewer finding types, with the engine deriving routing from typed facts instead of the
  model choosing it.
- Unify the single and assignment schema selection (the two definitions order
  `candidate_invalid` and `inconclusive` differently, and single findings drop the
  `negative` guidance rule in a projection-specific branch).
- Clarify original-source authority, the candidate target and completeness for the assigned
  field purpose through the shared purpose and evidence owner (the former R6 source-review
  direction), compared offline on the labelled failures plus clean controls before any live
  call.

**Decision.** **D10.2** Amend ADR 0023 and the support schema.

**Constraints.** Don't discard policies by keyword, truncate required evidence or add local
token ceilings; don't claim a larger budget fixes reliability; group subjects only with
evidence that per-subject findings, association, correction scope, origins and retry
identity survive. A separately configured assessment model is a model choice (H5).

**Validation.** Measurement set and B2 labels, after H2. **Keep if** finding-type accuracy
and recall improve and false statements fall.

### Q10c. Principle-review citations (B11)

Since ADR 0042 Decision 4's line was withdrawn, every principle citation has been a whole
file: on 27 October hello-world had 21/21, 20/20 and 19/19 blanket, and loan-renewal 18/18,
with five details naming a principle they don't cite. `principle.prompt.md`'s "Cite
relevant policy text, not just a heading", there since 25 September, has not changed this.

**Decision.** **D10.3** After H2 confirms the principle labels, either record citation
precision as a model limitation, or change the principle task at its Q3 owner. No rule may
inspect citation text, and ADR 0042's admission constraint stays unchanged.

**Validation.** Measurement set; principle-citation precision and principle false
statements.

### Q11. Remaining rules and design text

**Decisions.**
- **D11.1** Delete the never-built keyword lints from the design (design.md:252, acceptance
  criterion 21, 21-validation.md:20 and :38). Docs only.
- **D11.2** The acceptance-criterion clause join (`specification_markdown.zig:202`): keep it
  with a contract, change it, or remove it. Decided before Q1b because it changes every
  `spec.md`. **Decided and implemented 28 October 2026:** kept, with a contract in
  [§23](../design/contracts/23-rendering.md); the join uses the exact-value boundary owner's
  terminal-punctuation policy (`exact_value_boundary.endsWithTerminal`) instead of its own
  ASCII check, and readback treats an escaped comma as clause text. Only clauses ending in
  non-ASCII terminal punctuation, `,`, `;` or `:` render differently.
- **D11.3** ADR 0035: never delete a covered restatement that is a requirement's last
  mention in the records.
- **D11.4** AGENTS.md ("Model output, prompts and evidence") records two exceptions: the
  evaluator's one mechanical correction and ADR 0039's single runaway re-send. The §22.6
  prefix normalization (user-approved 21 September 2026 in ADR 0014; widened to partial
  member names on 18 October 2026; reused by the evaluator for judge responses) is a third.
  It isn't rare: 332 of the 349 completed responses in the 26–27 October runs carry
  `model.response_normalized`. Either name it in AGENTS.md as a recorded engine exception,
  or withdraw it and record the opening as a model limitation, accepting that nearly every
  response would then need a protocol correction (which also amends ADR 0014 and §22.6).
  Policy edit. **Decided and implemented 28 October 2026:** AGENTS.md now names it as the
  third recorded exception, reported separately.
- **D11.5** Retarget the evidence citations in accepted ADRs to AGENTS.md's "Model output,
  prompts and evidence": 0031:244 and :251, 0032:206 and :216, 0033:256, 0034:66, :93 and
  :96, and 0039:52 and :182 (ADR 0041 is already retargeted). Where an ADR quotes the old
  wording, use AGENTS.md's current text. Policy edit; no behaviour change. **Done 28
  October 2026.**

**Validation.** D11.1 and D11.5, and the D11.4 wording option, are docs only. D11.2 changes
rendering only: decide it offline by re-rendering every retained run's stored state with the
old and the new renderer and comparing the output. D11.3, and D11.4 if the salvage is
withdrawn, are each a separate phase with its own measurement set, never stacked with
another Q11 decision.

## 5. Engine track (E)

Each item: `/preflight`, offline tests, the §2.11 freeze diff, `zig build verify`, one live
run of each case, landing between measurement sets and under §2.13. E7's live validation is
its clarification-producing case instead.

### E0. Failed and blocked runs publish validated content (B10, ADR 0041)

Accepted on 26 October; mechanism accepted on 27 October. A Specify run that fails because
model work couldn't be completed, or ends `blocked`, publishes only its validated content as
an incomplete specification, marked in `spec.md` and `reference-context.md` and logged as
`run.incomplete_published`, while still ending `failed` or `blocked`. Mechanism: a
YAML-declared `failure-output` subgraph run by the engine through the runner in a model-free
failure-output mode; eligibility as ADR 0041 Decision 1; no final requirement IDs;
`workflow/v2`. Its report marker is `spec-e2e-report/v11`'s `incomplete_publication`, the
artifacts the run wrote (its step, diagnostic and outcome are the report's own
`terminal_step`, `diagnostic` and `workflow_outcome`); it landed with T5 (decided 29 October
2026) and stays null until E0 writes it, so E0 changes no report version. With a test that a
pre-E0 v11 report still decodes. Two tests asserting that a required repeated
runaway publishes nothing flip. The failed view has no `spec.md` reader slot (ADR 0041
Decision 8.4). Implementation decisions: ADR 0041 Decisions 7 and 8 (approved 29 October
2026); slices S1 definition and compilation, S2 terminals, event and ledger, S3 runner
mode and engine binding, S4 Specify content, S5 wiring and tests. DE6 is decided first. About the size of ADR 0039.

### E1. Engine-owned model request (A1, ADR 0030 slice 4)

Slices 1–3 are done. Open: the `request-model` step itself, with ADR 0030's offline
acceptance and the shared contract-variant mechanism ADR 0033 reuses.
- It folds ADR 0039's re-send (`check-model-runaway`, `build-model-runaway-resend` and the
  compiler route rule) into the `request-model` stages and retires that YAML rule.
- ADR 0040's review closure, ADR 0042's required-items constraint and Q2's bindings carry
  over unchanged; retake the slice 1 freeze, with T5's request projection, on the commit
  before E1 (after Q2).
- Settle the slice 1 review points: trace the advisory production run (budget exhaustion,
  output limits, the advisory protocol stop); make `extract/content` and
  `extract/content-request` one step; port each runner-level lifecycle test in
  `src/model_request_workflow_test.zig` one for one, with a mapping table and a reason for
  any dropped assertion (user decision of 23 October, option b).
- Not expected to change model calls, tokens or reliability. Whether the engine also takes
  over release is open (R-A1). It retires request-lifecycle data keys, so it lands under
  §2.13.

### E2. Stage actions (A2, ADR 0031) and identical sibling steps (W5)

Convert `prepare-toolchain` first and record A2's measure (files touched per change) before
converting another stage. Check whether a conversion absorbs W5's pairs
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

After E1, E2's measure, Q9's capture replays and D9.1, with all Specify owners in one change
on offline equivalence evidence, preserving Q2's bindings. It deletes repair data keys, so
it lands under §2.13. **Decision DE4:** confirm the derived choices (the 13-owner list, the
`owner` check, "compiled operation" meaning the step instance, the §22.1 reading, advisory
stops outside the four operations, one Specify-only conversion, offline evidence).

### E5. Rejections say why (A4)

Give `.authority` a closed reason and split `OperationExecutionFailed` into specific causes
at their owners, keeping typed outcomes and terminal precedence (under §2.13). Recount the
sites after each of E1–E4 before adding reasons elsewhere. Failure-evidence gaps:

| Gap | Required change |
| --- | --- |
| Evaluator partial bodies disappear | Thread retained bytes and completeness through the shared observation ([provider.zig](../test/harness/provider.zig), [bedrock.zig](../test/harness/bedrock.zig), [http.zig](../test/harness/http.zig), [evaluation_trace.zig](../test/harness/evaluation_trace.zig)), with redaction and adapter-to-trace fault tests |
| Simultaneous failures overwrite earlier causes | Retain bounded primary and secondary evidence ([workflow_model_invocation.zig](../src/application/workflow_model_invocation.zig), [workflow_pipeline_runner.zig](../src/application/workflow_pipeline_runner.zig)), preserving terminal precedence and allocation-failure handling |
| The loss-localization call origin isn't retained | Preserve both the finding and localization associations through collection, correction, repair authorization and reporting ([specification_support.zig](../src/domain/specification_support.zig)) |

Limits: build snapshots don't prove the compiler consumed exactly that snapshot under
concurrent edits; progress labels include routine invalidation, so not every progress event
is a semantic repair.

### E6. Logging and visibility gaps

- Cancellation during segment reads and under the log lock is reported as a logging
  failure, against keeping cancelled distinct from failed.
- The lock action reports every acquire failure as a timeout.
- Prior-run crash finalization (§14.10) needs a persisted bootstrap authority that doesn't
  exist, so a crashed run's logs are kept until it is decided.
- §26 and F0002 name the `redaction/default-v1` policy, but no code or record carries it.
- `model.provider_stopped`, `model.runaway_resent` and `review.incomplete` are warnings
  (`src/domain/log_event_registry.zig:65`, `:67`, `:69`), and ADR 0041 specifies
  `run.incomplete_published` (E0) as one too. The threshold check
  (`src/domain/log_policy.zig:90-92`) drops every warning when `logs.level` is `error`,
  `fatal` or its alias `critical`, all accepted levels, so an incomplete review, a re-send
  and, after E0, a failed run's incomplete publication can happen without the event ADRs
  0039–0041 require. That breaks the rule that incomplete results are published only when
  marked and logged. **Decision DE6**, before E0: emit ADR-required events whatever the
  threshold (one typed property in the shared event registry, not a per-event branch); stop
  accepting levels above `warning`; or accept and record the gap. **Decided and implemented
  28 October 2026:** the registry's typed `Emission` marks `model.response_normalized`,
  `model.provider_stopped`, `model.runaway_resent` and `review.incomplete` `always`, and the
  threshold action consults the definition; E0 marks `run.incomplete_published` the same way.

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
explicit continuity contract. It changes model input only when clarification answers exist,
which the development cases never produce: every request kind the scripted driver already
produces stays byte-identical, and answer-bearing requests are measured on a
clarification-producing case the user chooses (never a reserved feature). Last, after
E1–E4.

### E8. Typed schema-definition identities

Domain code branches on support-schema definition names written as raw strings
(`specification_review_retention.zig:80`, `specification_support_repair.zig:152`,
`specification_support.zig:218`). AGENTS.md requires typed IDs: a closed enum bound when the
schema loads, so a renamed definition fails at load instead of silently changing a branch.
No model-input change.

## 6. Test track (T)

### T1. Repeated-runaway debug capture (B9)

ADR 0039's debug-capture test: at `debug`, a repeated runaway leaves both attempts'
requests, request descriptions and complete returned outputs in the prompt log before the
failure events; at a higher level, only the events. No live run has had a repeated runaway.
Before Q1b. **Done 28 October 2026** (uncommitted): `src/model_request_workflow_test.zig`,
"ADR 0039: a repeated runaway is captured in full at debug before its failure, and only its
events survive higher levels", at every log level, including §26.5's always-emitted events
at `error` and `fatal`.

### T2. Test decoupling

- Replace the about 45 assertions that copy model-facing English with comparisons to the
  owning constant, function or resource, checked once in the wire.
- Remove `model_payload_schema_test.zig:362-367`'s phrase checks on `protocol.prompt.md`, or
  compare with the resource.
- Rename fixtures named after live runs (R31, R35, R36, R42, FIX002) after the rule they
  test.
- Describe the scripted "recovers" scenarios as engine admission tests, never as evidence
  that a correction helps a model.
- `test/harness/attribution/preparation.zig:191-197` builds the
  `records_no_obligation_wording` arm by English `replaceOwned` on instruction text without
  checking that the substitution matched: make an unmatched substitution an error, or derive
  the arm from the owning rule.

### T3. Coverage gaps (B5, B7)

- No offline integration scenario exercises a records-batch native delete (ADR 0035).
- The extraction reason's text-repair route has unit coverage only (Q2's regression test).
- No synthetic current-schema exchange replaces the retained `compatible` one.

### T4. Architecture rules and replay (A5)

When E2 and E3 rewrite the affected tests, express architecture rules as import-graph and
contract-shape rules instead of per-file pins (69 of 79 pin files, with 420 source-text
assertions). Prefer replaying retained real captures over extending the scripted response
builder.

### T5. Measures and request projections (before Q1b)

Every set must be measured and labelled the same way as the baseline, and engine items need
a request-byte proof that doesn't exist today. Validation: offline, against the retained 27
October runs; no live run. The user reviews the definitions before Q1b.
- **(a) Deterministic counts.** A read-only script writes
  `evaluations/e2e/<run>/measures.json` from `report.json`, `events.jsonl` and the feature
  event log: outcome, terminal step and diagnostic; sends and actual tokens per stage, with
  one stage mapping from `attempts[].step` and repair attempts matched through
  `repairs[].origin`; protocol corrections; re-sends and runaways, counted separately;
  admission rejections by reason; admission escapes with their downstream sends and tokens;
  repairs; records per records call; run latency from the feature log; and the brittleness
  counts (§2.6). Decide the owner first (a script beside `prepare.py`, or the baseline
  scorer's existing definitions); never write a second definition of a measure the scorer
  owns. `/evaluate-e2e` reads its cost profile from `measures.json`.
- **(b) One labelling vocabulary.** The `/evaluate-e2e` skill owns the defect classes and
  repair grades; `evaluation.json` gets a new schema version with a class per defect and a
  grade per repair, recorded independently of the defect's origin class. The assistant
  applies them as advisory labels; no deterministic code classifies prose.
- **(c) Set summaries.** Per-case minimum, median and maximum, and pooled event counts with
  their opportunities (§2.5).
- **(d) Review labels.** `b2-review-label/v2` adds a source-backed expected finding type
  beside the predicted type, uses (b)'s vocabulary and always carries its metrics block.
  Review measures stay provisional until H2.
- **(e) Request projection.** The ADR 0030 freeze (`evaluations/adr0030-freeze/5ce2af4/`,
  stale) records call sites, outcomes, tokens and files, but no request bytes. Record at the
  provider port, which E1–E4 keep: for each invocation the fake provider receives (or a
  recording wrapper around it), record `model_request_description.Description.from(request,
  binding, kind)` keyed by request ID and attempt, keeping content, protocol_prompt, schema,
  response_mode, controls, sampling, reasoning_effort and the native admission members, and
  omitting `version`, `workflow_version` and `request_step`, which E1 and E4 change by design.
  It is an observation, never asserted; a proof is a byte diff of two freeze directories
  under `evaluations/`. Retire any driver `measurement_prefix` dump that only duplicates it.

**Status, 28 October 2026 (uncommitted).**
- (a) and (c): `zig build e2e-measures` writes `measures.json` (`e2e-measures/v1`) per run
  and a set summary (`e2e-measures-set/v1`), offline, reusing the scorer's admission metric
  and the production parsers; definitions are in [e2e.md](../design/harness/e2e.md) ("Run
  measures"), including each stage's sends, tokens and shares from v11's per-attempt request
  purpose and owner, through the stage classification and accumulation the baseline scorer
  also uses (moved to `baseline/stages.zig`, one owner). **Not yet:** the brittleness
  counts, which belong in `zig build code-heuristics` from source structure, never from
  word lists.
- (b) and (d): the `/evaluate-e2e` skill holds the defect-class vocabulary, repair grades,
  `e2e-assistant-evaluation/v2` and `b2-review-label/v2` (provisional until H2).
- (e): a recorder at the fake provider port writes projections keyed by scenario and call
  order (request ordinals restart per unit); `SDDE_REQUEST_PROJECTION=<dir> zig build
  test-integration` takes a freeze, and `diff -r` proves byte identity. First freeze:
  `evaluations/request-projection/371b55a-worktree/` (4,378 requests; a repeat freeze was
  identical). The driver's `measurement_prefix` dumps stay: they also record wire encoding,
  compiled steps and composition, which the projection omits.
- Contract-review fixes (28 October): the event-log reader is strict and versioned through
  the log-format owners, and `measures.json` records the run's log threshold; publication
  is `native`, `incomplete` (v11's marker, written once E0 lands) or `none`; the pooled
  publication rate counts every attempted run, with undecodable reports counted separately;
  `--out` must sit under `evaluations/` and never inside a run directory; a report marked
  v1–v10 is `unavailable`, and an undecodable v11 report makes the run unmeasurable (DT5). So no retained run's
  report measures: all are v10 or older. Their call evidence and feature logs still measure
  where the retained configuration decodes, which excludes the 24–25 October runs (no
  configured temperatures). `e2e-measures` builds and smoke-tests in the offline suite.
- Freezes are grouped as `<group>/scenario-NNN/call-NNNN.json` with a `manifest.json`
  (groups, scenarios, calls): the first freeze's flat layout let case groups overwrite each
  other's scenario numbers, so it is superseded. **Base freeze taken 29 October 2026** on
  the step-3 tree (v11 and DT5 included; uncommitted at the time, tree digest
  `99bad68a5db586f3` over `git diff HEAD` and the untracked files), fresh:
  `evaluations/request-projection/step3-2026-10-29/`, 8 groups, 198 scenarios, 4,406
  requests; a repeat freeze was byte-identical. It is E0's base as long as the step-3
  commit holds this tree; otherwise it is retaken on that commit.
- **Report version, decided 29 October 2026 (user: "move to v11"):** `spec-e2e-report/v11`
  records each attempt's request `purpose` and `owner_kind` from its native request
  identity (a composed request's identity carries its base packet's), and ADR 0041's
  `incomplete_publication`. Baseline acquisition, which embeds the report, advances to
  `baseline-acquisition/v8` and rejects an attempt whose purpose or owner differs from its
  physical receipt; the baseline trace reads both from the same request identity. An
  offline runaway scenario checks that each re-send is attributed to the stage of the
  request the runaway targeted (review, repair or generation). Retained v10 runs no longer
  decode on builds from v11 (rule 13; H1).
- **Definitions approved 29 October 2026 (user),** as written in
  [e2e.md](../design/harness/e2e.md) ("Run measures"), keeping the coarse stages: they match
  §2.6's cost row (extraction and reconciliation, generation, review, repair).
- **Decision DT5, decided and implemented 29 October 2026 (user).** Two guards that protect
  the baseline's completeness and comparability; they change no engine output, so they
  improve no specification (the first change that can is Q2).
  1. **A run that can't be measured doesn't stop the set.** A run whose records can't be
     read or trusted (for example, a feature log whose last row was cut off mid-write) is
     recorded as `unmeasurable`, naming which kind of record from a closed list, counted
     as attempted (§2.4) and never as a publication. An exhaustive, compile-checked switch
     classifies every error. A run without a readable `case.json` (it can't be attributed
     to a case) and an operational failure of the measurement itself (cancellation,
     exhausted resources) still stop the command.
  2. **A case's runs share one log threshold.** Rejection, validation-failure and latency
     counts compare only at one level, so the set summary records each case's threshold,
     and a case whose measured runs differ stops the command, naming the case and both
     levels. Both cases share one configuration at `debug` today.

  Every run is measured and summarized before anything is written, so a stop leaves no
  partial output.
- **Draft measures files renamed 29 October 2026 (user).** The seven files the draft
  producer wrote on 28 October predate the final format (no log threshold or stages), so
  they are now `evaluations/e2e/<run>/measures-draft.json` for the six 27 October runs and
  `evaluations/fix06-review/2026-10-28/measures-set-2026-10-27-draft.json`.
  `/evaluate-e2e` never reads them, and the three hello-world files keep the only
  report-derived counts for runs whose v10 reports v11 can't read.

## 7. Human and decision track (H)

### H1. Adjudication (R8)

Only a human `human-spec-adjudication/v2` record, applied with `zig build adjudicate-spec`,
decides acceptance. No run has been adjudicated. A run can be adjudicated only by a build
whose report contract decodes it (§2.13). From `spec-e2e-report/v11` (29 October), every
retained run is v10 or older, so only a build before v11 reads them. Q1a's removal of the
`weakened_obligation` rule made the three 27 October loan-renewal reports (05:06 and 09:40
published, 08:31 failed) undecodable, and they stay unadjudicated unless the user decides
otherwise; the retained v9 runs also stay unadjudicated (decided 27 October). The clean 26
October `39a06ea` pair is v10. Needed for the ADR 0034 gate, for every
measurement set from Q1b on.

### H2. Review-label confirmation (B2)

Freeze the label scheme (T5's `b2-review-label/v2`) before Q1b (decided 28 October 2026;
T5 defines it). A human then confirms or
corrects the labels under `evaluations/b2-review-accuracy/` so they become frozen evidence.
Needed before Q10b and Q10c.

### H3. Calibration panels (R8)

The [Hello World panel](../test/integration/fixtures/wf-001-hello-world/node-vitest/calibration/REVIEW.md)
(nine specimens) and the
[loan-renewal panel](../test/integration/fixtures/wf-002-loan-renewal/calibration/REVIEW.md)
(fifteen) have proposed labels only; human-review and judge-qualification records are
pending. Needed before judge qualification and any formal baseline freeze; records land in a
gap.

### H4. Experiment stops, qualified scope and the formal baseline (B4, B5)

**Decision**, before freezing the evaluation protocol's Phase 2 baseline (FIX06's
measurement sets don't need it, §2.12): the protocol's stops of 1,000 sends and 2,000,000
tokens cover 16 workflows at 125,000 tokens against 144 development workloads, so the
budget-feasibility report stays `insufficient`. Revise the stops with a recorded rationale,
reduce review cost through its owner (Q10b), or narrow the qualified scope. Measure the
prompt, schema and evidence share of each call before trimming anything; add no local size
ceilings (ADR 0011). If the frozen baseline meets the protocol's adequacy targets, retain it
and stop the redesign.

### H5. Model choice (R7)

The user decides when to change or compare models. All live evidence comes from
GPT-OSS-20B. Only if the user selects Claude Haiku 5.5: measure its maximum-output time to
replace the interim 180,000 ms `requestTimeoutMs`, and settle Claude's response mode (native
schema or prompt-only).

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
eligibility (§22 and ADR 0020/0022 amendments); narrow correction of invalid loss evidence
(today `invalid_loss` ends the workflow `invalid`); verdict reassessment under §22.1, with no
voting or retry-until-positive. Entity-applicability repair can't change the entity
decision, and exact-reference repair can't add an unselected claim because its text matches.
Earlier comparison records are in
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

Stored readback doesn't re-quote claim text from its citations; admission admits a repeated
citation ID; `source_selections` naming was left out of scope. No observed outcome.

### Wider scope retained

- **Evaluator responsibility transfer:** judgment accepts criterion IDs and quoted strings,
  then checks coverage and substring presence; define the assignment and occurrence contract
  first.
- **Retained memory and scale:** growing review sets, retained bytes, allocations,
  validation and teardown time, cancellation and OOM, dependent rebuilding.
- **Harness acceptance (former H-012, H-013, H-017):** publication interruption evidence;
  production Specify feature-log integration; live negative paths (malformed generation, real
  missing or conflicting authority, clarification, cancellation, judge failure); rerun
  replacement (shorter output, unsubmitted drafts, concurrent closes, no duplicate subject
  IDs, an unrelated workflow); an unchanged prior `spec.md` must not be labelled new after a
  blocked rerun (E0 changes this); compiler rejection of skipped gates and undeclared
  resources; packaged execution without a `design/` fallback; the H-017 live milestone; live
  evaluator demonstration (H-004/H-006); the provider-compatibility diagnostic. Ticket text
  in git at `8ed40ba`.
- **Provider docs:** ADR 0028 names an F0009 feature document and contract §12.3.2, which
  don't exist, and its "Live use" still says only GPT-OSS-20B is permitted.

### R-A1. Engine-owned release

Whether the engine should also take over release, which needs the compiler to derive each
request's lifetime. Decide after E1.

## 9. Guardrails

- AGENTS.md "Model output, prompts and evidence" and "Anti-overfitting rule" govern every
  phase.
- No local fixes: no change scoped to one site, prompt line, case or model output. Fix the
  failure class at its owner, and record symptoms that have no structural owner as model
  limitations.
- One change set per measured build (§2.1); nothing under the build-provenance roots changes
  while a set runs (§2.3).
- No model change or comparison (H5).
- No caps that discard output.
- Don't narrow the entity-name exception without a decision (B6).

## 10. Progress

| Step | Item | State | Build | Runs | Result |
| --- | --- | --- | --- | --- | --- |
| 1 | Q1a | Done 28 October 2026 (D1.1, D1.2 decided) | `d4fd4a5` | Offline only | `zig build verify`: 164 of 164 steps, 1,969 of 1,969 tests; `git diff --check` clean; no tracked file outside `fixes/` names the removed rule; contract review: no code findings, three minor doc findings fixed |
| 2 | Pre-baseline decisions | Decided 28 October 2026; D11.2, D11.4, D11.5 and DE6 implemented, uncommitted | Working tree on `d4fd4a5` | Offline only | `zig build verify` on the final tree: 164 of 164 steps, 1,972 of 1,972 tests; D11.2: none of the 21 retained `spec.md` files has a clause ending whose join changes, so re-rendering is byte-identical; contract review: no code defects; its major finding (§26.5 and §13.9 still stated the old emission rule) and six minor findings fixed |
| 3 | T5, T1, D11.1, `spec-e2e-report/v11`, DT5 | Implemented 28 October 2026; v11, the measure-definition approval and DT5 on 29 October (decided that day); uncommitted, except brittleness counts (see T5) | Working tree on `371b55a` | Offline only | `zig build verify` on the final tree: 169 of 169 steps, 1,984 of 1,984 tests; contract reviews: step 3 had no blockers and one major, seven minor and three nit findings, all fixed; v11 had no blockers or majors and eight minor findings and a nit, all resolved (the draft measures files are renamed); DT5 had no blockers, one major (operational errors marked a run unmeasurable), three minor and five nit findings, all fixed; see T5's status |
| 4 | Q1b | Done 29 October 2026 on the latest build by user decision ("run Q1b on the latest build"): the uncommitted step-3 tree, source digest `c7684e21…`, so every run records `modified: true` (a user-approved deviation from §2 rule 3). Runs 1 of each case are the 08:51 and 08:53 runs | `371b55a` + working tree | 6 hello-world, 6 loan-renewal | Baseline table below; measures `evaluations/q1b/measures-set.json`; evaluations `evaluations/e2e/2026-10-29T*/`; none adjudicated |
| 5 | E0 | Stopped 30 October 2026 by user decision ("stop E0"): slice S1 and part of S2 were built, then removed; ADR 0041 on hold with Decisions 7 and 8 recorded | — | — | — |
| 6–20 | Q2–Q11, closing set | Proposed | — | — | — |
| — | E1–E8, T2–T4 | Proposed or accepted, not started | — | — | — |

### Q1b baseline (29 October 2026)

Advisory evaluations (`/evaluate-e2e`) are not acceptance; no run is adjudicated (H1).
Spreads are minimum / median / maximum over attempted runs unless stated.

| Measure | hello-world | loan-renewal |
| --- | --- | --- |
| Native publication | 6 / 6 | 4 / 6; runs 1 and 6 failed `RetryLimitExhausted` at the records call (`uncovered_member` three times each: a claim named by a functional requirement but by no acceptance criterion or edge case; both corrections returned the same response) |
| Advisory aggregate (published runs) | 82.14 / 89.29 / 96.43; 6 of 6 at or above 80 | 78.57 / 82.14 / 85.71; 3 of 4 at or above 80 (run 5 `threshold_failed`); renewal-eligibility at its minimum in all four |
| Sends | 22 / 23 / 27 | 12 / 25.5 / 27 |
| Actual tokens | 58,282 / 65,119 / 122,002 | 26,347 / 96,736 / 113,908 |
| Review share of tokens (published runs) | 74.6–80.9% | 78.4–83.6% |
| Protocol corrections (pooled per send) | 1 / 142 | 5 / 129 |
| Runaways and re-sends (pooled per send) | 4 / 142 (all in review) | 3 / 129 (all in review) |
| Admission rejections (pooled per send) | 1 / 142 (`SYNTAXERROR`) | 7 / 129 (6 `UNCOVERED_MEMBER`, 1 `SYNTAXERROR`) |
| Admission escapes | 0 / 86 values | 0 / 108 values |
| Repairs | 1 (native business-rule delete, graded helpful) | 0 |
| Records per records call | 2 / 2 / 5 | 3 / 5.5 / 8 |
| Latency (ms) | 26,414 / 31,836 / 267,969 | 11,182 / 70,681 / 121,720 |
| Lost source requirement (published) | 0 / 6 | 1 / 4 (no inactive-loan refusal scenario) |
| Weakened obligation (published) | 0 / 6 | 4 / 4 story "may renew"; 2 / 4 FR-001 too |
| Unsupported addition (published) | 3 / 6 (trigger "executable"; entity "immediately … followed by") | 3 / 4 (AC-001 adds a renewal mark or "remains active") |
| Invented or restating entity (published) | 4 / 6 | 4 / 4 |
| Restatement (published) | 2 / 6 | 3 / 4 |
| Rendering artefact (published) | 6 / 6 (code span inside the model's quotes) | 4 / 4 (same; plain-text values in entity meaning) |
| Review detection recall (published) | 4 of 14 defective subjects flagged, none with the right type | 0 of 21 |
| Principle citations | all blanket | all blanket |

The label convention for a `supported` verdict on a defective subject differs between
evaluations (`wrong_type`, `missed_defect`, or both), so finding-type accuracy isn't pooled
until H2 settles it; each run's `labels.json` and `notes.md` state the convention used.
Labels sit in each run's evaluation folder.

**Cost estimate.** Runs on 26–27 October used 61,906–93,411 tokens (hello-world) and
85,486–98,032 (published loan-renewal). A measurement set with its two control runs is about
0.5–0.8 million tokens; Q1b's twelve runs about 0.75–1.2 million; each extension about
0.25–0.6 million. A replayed repair call costs about 1,300 tokens. Q3, Q10a and each engine
item need one run per case.
