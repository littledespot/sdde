# FIX06 — Phased rollout of the remaining Spec work

**Created:** 28 October 2026. **Updated:** 31 October 2026 (review of every unimplemented item;
completed, closed and reverted records moved to [Z_FIX06](Z_FIX06.md), with the 28 October
review-merge note). **Status:** sole active fix record. It holds open work only, in one ordered
sequence; completed, closed and reverted FIX06 work is in [Z_FIX06](Z_FIX06.md). Each phase
needs the user's approval before its changes, and every live run needs its own approval.
Nothing here authorizes a code change, live call or E2E run by itself. Items marked
**Decision** amend an accepted ADR, contract or scope; recommendations are not decisions. The
governing design remains **Proposed design**.

**Authority:** the user's directions of 28 October 2026: "output a phase rollout to
fixes/FIX06.md, the phases should be broken into e2e testable chunks to allow validation
and testing", then "review outstanding items that need to be implemented in FIX05 and
move them to FIX06 … ensure the order is optimal", then "ensure the phase order is
optimal", "check that it is address tight coupling issues, and removing brittleness,
ensure that local fixes are not being implemented" and "Finish the FIX06 update". It
follows the 27 October audits of production code, prompts, ADRs and tests (§1) and the
user's rejection of ADR 0044 as "an extremely poor direction". On 31 October 2026 the user
asked to "perform a detailed review of all unimplemented items in fixes/FIX06.md, assess if
they are valid or still relevant", update FIX06 and move implemented items to Z_FIX06.

**FIX05 is retired.** Its open items are below under their original IDs (A1–A5, B2, B4, B5, B7,
B10, R1, R2, R6–R8, W3–W5 and the carried follow-ups); B9's last open item, T1, is done
(Z_FIX06), and its runaways stay a reported measure (§2.6). Its closed items, current-state
snapshots and history are in [Z_FIX05 §21](Z_FIX05.md#21-fix05-retired--28-october-2026), with
a map from every FIX05 ID to its new place. Earlier completed work is in [Z_FIX01](Z_FIX01.md),
[Z_FIX02](Z_FIX02.md) and [Z_FIX05](Z_FIX05.md); completed FIX06 work is in
[Z_FIX06](Z_FIX06.md).

## 1. Why

**Verdict carried from FIX05 (17 October review).** The deterministic core works: no value
breaking a declared native rule has escaped admission since Phase 1A (none in any run since
Q1b), and every failure ends as a typed outcome (three Q4 runs ended as harness errors instead
of their engine outcome; that harness defect is fixed, E6). Two structural properties make the
engine expensive and its runs brittle: every concept is spread across an action, a binding, a
registry entry, data keys, YAML nodes and pinned tests (A1–A5); and the Spec workflow is a long
serial chain of strict model judgments, so end-to-end success is roughly the product of
per-call success (B1). Q4 showed it: the only change to hello-world's first extraction request
was one removed context sentence, and that call then returned `no_feature_claim` in 5 of 6
runs (before: 0 of 13); 1 of 6 published. Causation is not replayed.

**The rule recent work broke.** The design forbids deterministic judgement of prose:
[design.md:133](../design/design.md) ("Replacing semantic judgment with brittle keyword
rules" is a non-goal), [12-model-boundary.md:1008](../design/contracts/12-model-boundary.md)
("Do not add keyword heuristics"), [17-specify.md:552](../design/contracts/17-specify.md)
("Lexical shape alone is not a semantic rejection") and
[text-field-composition.md:136-137](../design/contracts/text-field-composition.md) ("not a
keyword or substring ban"); AGENTS.md says so directly. Z_FIX05 had also rejected modal-verb
matching on 25 October.

**Findings of the 27 October audits, as of 31 October** (the original text is in
[Z_FIX06 §2](Z_FIX06.md#2-fix06-1-and-3-as-written-2831-october-2026)):

1. **Rejected patches:** removed by Q1a (`d4fd4a5`; Z_FIX06). Obligation weakening in generated
   text is a recorded model limitation (B7): loan-renewal's story says "may renew" in all four
   Q1b publications.
2. **Prompt structure.**
   - "Preserve conditions and obligations" appears in prompt files (`generation.prompt.md:2`,
     `records.prompt.md:2`), `generation.context.json`'s `business_value` and, since Q3,
     `packet-guidance.json` (story :7, functional requirement :15, outcome :27), and reaches
     every generated text field (the count of 17 wasn't retaken). Q6 scoped it to six record
     purposes (30 October) and stories still restated FR-001.
   - One three-line `repair.prompt.md` serves six repair sites (`spec.workflow.yaml:376`,
     `:413`, `:610`, `:816`, `:899`, `:914`), and the reconciliation repairs bind no context, so
     the dispositions insert repair gets none of its step's definitions (the dispositions prompt
     names the choices). On 27 October it marked hello-world's UTC claim a `duplicate`, and the
     spec lost the requirement. Q2 bound the definitions and replayed harm didn't fall (Q2b).
   - The source-review prompt is a 38-line decision tree (`support.prompt.md`) whose chosen
     label routes the engine; in Q1b, review flagged 4 of 35 defective subjects, none with the
     right type (Q10b).
   - Prompts restate engine-enforced rules and carry engine vocabulary and schema field names
     (for example `records.prompt.md:4`, "Family presence is structural"); Q4's removal wasn't
     kept (the Q4 retry), and no published spec shows a leak. D7.1 found no rejection whose
     correction could state the exact-value boundary rule (closed).
   - Sentences added after single runs and never measured (Q5).
3. **Fragile engine rules over text:** the list-item split (ADR 0036 Decision 3, ADR 0038
   Decision 4; Q8); delimiter stripping (ADR 0036 Decision 6), with ADR 0045 on hold (all 12
   publications evaluated since Q1b show a rendering artefact, some from it; Q7, D7.2); the
   exact-value boundary tables (ADR 0020); the substring duty rule (ADR 0024; D7.3); exact-text
   deletion of a requirement's last mention (ADR 0035; D11.3). Settled: the clause join (D11.2),
   the §22.6 prefix salvage (D11.4, an AGENTS.md exception) and the keyword lints (D11.1,
   deleted).
4. **Tests tied to wording** (T2, open): assertions that copy model-facing English (about 45;
   recounted 31 October as about 46 lines in 8 files, a lower bound); fixtures named after live
   runs (R31, R35, R36, R42, FIX002 and more); scripted "recovers" scenarios, which the testing
   contract already scopes as enforcement tests (28-testing.md:542-543).

**Root cause.** Every change before FIX06 was decided on one run per case, mostly on uncommitted
builds with several changes stacked, and per-run evaluation recommendations became edits. On 27
October three hello-world runs on three uncommitted trees scored 82.14%, 82.14% and 60.71%; the
60.71% came from a reconciliation repair whose identical request (`b7ccad7311…`) answered
`retained` at 05:06 and `duplicate` at 09:40. Q1b then measured run-level noise on one tree:
hello-world published 6 of 6 at 82.14–96.43% advisory and 58,282–122,002 tokens, loan-renewal
4 of 6 at 78.57–85.71%. Since then three single-change phases failed the keep rule and were
reverted (Q6, Q2 on its replays, Q4).

**Gate status (ADR 0034).** Not met. No run is adjudicated (H1). Repeated runs of both cases
exist only on uncommitted trees (Q1b and the D4.1, Q6 and Q4 sets): every retained run since 26
October records `modified: true` except the 26 October `39a06ea` pair. As plain facts, Q1b's
captured sources match `5bb7f17` except ADR 0041's text, D4.1's runs 2–6 equal `ce38bf2` (and
`1ba89f8`), and Q3's pair equals `9ee7fd6`, HEAD's tree. ADR 0034:64 names one committed build;
how that applies is the user's reading. The 25 runs published since Q1b are
`spec-e2e-report/v11`; older reports need a v10 build (H1). The user decides when Plan is
actioned.

## 2. Rules for every phase

AGENTS.md ("Model output, prompts and evidence", "Anti-overfitting rule", "Validation")
governs every phase. These rules add what FIX06 needs on top.

1. **One change set per measured build.** Relative to its comparison point (rule 9), a measured
   build adds exactly one change set. Q7 measures each decision that changes model input or
   output on its own build; Q8 measures D8.1's experiment build against the main build, and D8.2
   and D8.3 each on its own build when they change model input or output. Changes that rule 11
   proves leave every development-case model request byte-identical (Q10a, D7.3 and the engine
   track) may also be present. A change set that isn't kept is reverted in full, never patched
   on top, as Q2, Q4 and Q6 were.
2. **Owner first, offline first.** `/preflight` before editing. It names the failure class,
   its owning abstraction, the coupling the phase removes or the single owner it creates,
   and how unrelated members of the class are covered (both development cases plus an
   offline unrelated-domain fixture). A change scoped to one site, one prompt line, one case
   or one model's observed output is a local fix and out of scope. Then regression and
   negative tests at the owning boundary, comparing against owners rather than copied
   English; `zig build verify`; a `contract-reviewer` pass.
3. **Build.** Measurement uses a committed, unmodified build (`report.json`
   `build.source.modified` is `false`). Since Q1b every set has instead run on the latest
   build, committed or not, by user decision (29 October 2026: "run Q1b on the latest build",
   recorded as a deviation from this rule; each later set approved on the latest build);
   whether that practice replaces this rule is the user's decision. A set's runs
   share one source digest (`report.json` `build.source.source_sha256`); D4.1's run 1 is the one
   recorded exception, admitted on its request-projection freeze proof. While a set runs,
   nothing changes under the build-provenance roots (owned by `build/provenance.zig:21`,
   described in design/harness/e2e.md: build files, `src/`, `test/`, `design/`, `scripts/` and
   the root entry files); any such change moves the digest and splits the set. So test-track
   work, H3 and H4 records and design-text edits land between sets, as engine work does.
   `fixes/`, `.claude/` and `evaluations/` aren't roots: §10, B2 labels and evaluations can be
   written during a set. ADR 0034:64 names one committed build for gate evidence (step 20).
4. **Measurement set.** Three runs of each development case (hello-world and loan-renewal) on
   the phase's build, extended under rule 7; Q1b, the first reference, took six runs of each
   case. Each run is approved. AGENTS.md's evidence rules apply: every attempted run counts, and
   nothing is tuned on the reserved qualification features (rule 12). This rule also asked for
   one control run of each case on the last kept commit, interleaved with the set; no set since
   Q1b has had one (D4.1 was kept without them by user decision; Q6 and Q4 ran none, with no
   recorded decision). **Decision** for the user: drop control runs from measurement sets? Yes:
   sets compare only with Q1b's retained runs. No: each set adds one run per case on the
   comparison point's build (Q1b's captured inputs match `5bb7f17` except ADR 0041's text).
5. **Evaluation of each run.** T5's measures (`zig build e2e-measures`) for every run;
   `/evaluate-e2e` (advisory) and B2 labels for every review finding of each published run,
   reported per run and as minimum, median and maximum per case. T5 pools event counts over the
   set with their opportunity (sends, admitted values, repairs; B2 labels pool review subjects);
   rubric classes count the published runs that show them (§10). Acceptance comes only from H1
   adjudication (AGENTS.md "Testing expectations"). Practice since Q1b: D4.1 was kept on
   measures alone by user decision, Q4 failed its guards on measures alone, Q3's two runs were
   evaluated without B2 labels, and Q6's set left no measures or evaluations under
   `evaluations/`. **Decision** for the user: does a set already decided on its measures skip
   `/evaluate-e2e` and B2 labels? Yes or no.
6. **Measures** (defined and produced by T5).

   | Group | Measure |
   | --- | --- |
   | Outcome | Per attempted workload: `ok` with native publication, `failed` or `blocked`, each with its diagnostic, and whether a failed or blocked run published an incomplete specification (ADR 0041; none while E0 is on hold) (B1: call count is a reliability cost). Publication rate per case: native publications ÷ attempted runs; an incomplete publication doesn't count (ADR 0034). Adjudicated acceptance (R8) per attempted workload from H1 records, unknown until they exist. An advisory threshold result is reported as advisory, never as completion or acceptance |
   | Quality | Advisory aggregate; critical failures; per-criterion scores |
   | Defect classes | Lost source requirement; weakened obligation; unsupported addition; invented or restating entity (B6); restatement; rendering artefact; engine-vocabulary leak; records per records call (B5 inflation; a deterministic count from T5) |
   | Repairs | Each repair graded helpful, neutral, harmful or no progress |
   | Admission | Protocol corrections; admission rejections by reason; runaways and re-sends; admission escape (a value violating a declared native rule reaching review or publication, with downstream sends and tokens) |
   | Review | Finding-type accuracy ([e2e.md](../design/harness/e2e.md#reliability-assessment) definition), provisional until H2, with precision per predicted type and recall per labelled type at original and final assessment; detection recall; false statements; principle-citation precision (findings whose citation covers the governing principle's lines; blanket whole-file citations; details naming a principle they don't cite) |
   | Cost | Sends and actual tokens per stage (extraction and reconciliation, generation, review, repair) per attempted workload; review share; run latency; all dispatched sends, tokens and latency per acceptable (adjudicated) result, failed attempts included, unknown until H1 (ADR 0034; evaluation protocol) |
   | Brittleness | Not produced yet (T5's open part; none was counted at Q1b), then counted after each phase: sites per model instruction (target one); guidance sentences without repeated-run evidence; model-facing English copied into tests; raw-string branches on schema names; model- or case-specific branches; repair sites without their step's guidance; model-facing English in Zig outside its single owner |

   Rubric-based measures (Quality, and the defect classes traced from the rubric) cover
   native publications only, and are always shown beside the publication rate per case:
   `/evaluate-e2e` scores only a completed specification, and a failed incomplete
   specification (ADR 0041) is not scored. Repairs, Admission, Review, Cost and records per
   call cover every attempted run. Published runs not yet adjudicated are reported
   separately.

7. **Keep or revert.** The user decides; this is the default recommendation for phases
   validated by measurement sets (Q2b if reopened, the Q4 retry, Q5, a D7.2 build, Q8, Q9,
   Q10b, a Q10c change and D11.3 if built). Q10a, D7.3 and the engine items are decided by their
   own validation.
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
   - **Hygiene and non-inferiority phases** (the Q4 retry, Q5, a withdrawal in Q8, Q9) remove
     input without targeting a recorded defect; they are kept on the guards alone, plus the
     measures their **Keep if** line names. Q4, the first, failed them: hello-world published 1
     of 6.
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
9. **Comparison point.** Each measured phase is compared with the last kept measured state.
   Q1b's twelve runs are the comparison point (§10): D4.1 was kept, but its correction never
   fired and its requests matched Q1b's, and Q3 was proved under rule 11, so neither moved it.
   A change proved under rule 11 never moves it.
10. **Model limitations.** [AGENTS.md](../AGENTS.md#model-output-prompts-and-evidence)
    owns this rule and its three recorded exceptions, including the §22.6 prefix
    normalization (D11.4) (the evaluator's correction is recorded in
    [Z_FIX05 §15](Z_FIX05.md#15-grader-one-shot-correction--18-october-2026)). FIX06 adds: no
    caps that discard output.
11. **Engine-track work** (§5) changes no model input, except E7's answer-bearing requests.
    It is proved offline on the scripted integration matrix, against a freeze retaken on the
    commit before it lands (now `evaluations/request-projection/d41-2026-10-30/`; the `q2-`,
    `q4-` and `q6-` freezes are of reverted builds), with two parts:
    - **(a) Behaviour.** The item reproduces the freeze its ADR defines ("Freeze first" in
      ADRs 0030, 0031, 0032 and 0033). Items without one (E5, E6, E8, E9, and E0 if it
      resumes) use the ADR 0030 step traces and summaries: outcomes, retries, token
      accounting, and published and state files. Each states its expected differences before
      landing, such as E5's rejection reasons.
    - **(b) Requests.** Every accounted request's T5 projection is byte-identical.

    It needs one live run of each case and lands only between measurement sets, never
    during one (DE2 and DE3 ask whether ADR 0031's and ADR 0032's offline evidence replaces the
    live run for structural conversions). Quality phases take priority.
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
    rule. Candidates include request-lifecycle data keys E1 might remove, E4's repair data
    keys, E5's split of `OperationExecutionFailed`, E9's `rejected_exact` member and rule
    withdrawals in Q7 or Q8. Such a change lands only after H1 has adjudicated the published
    measurement-set runs it would strand, or after the user records that they stay
    unadjudicated (today 25 published v11 runs: Q1b 10, D4.1 5 and Q3 2 on kept builds, Q6 5
    and Q4 3 on reverted ones). **Adding a member is not safe either** (corrected 28 October
    2026): the strict decoder rejects an object whose member count differs from its type's
    field count, so a missing member fails like an unknown one even when the field has a
    default (`src/domain/strict_json.zig`, `wireTypes`). Any new report member therefore needs
    a report version and strands the earlier version on newer builds. Alternative
    **Decision** for the user: adjudication decodes only the members acceptance needs.

**Boundary gates** for contract changes (carried from FIX05 §7, `git show
28ff156:fixes/FIX05.md`, which took them from the deleted FIX01 §5 "Acceptance and
feasibility gates", text at `b2f10a3`):

| Boundary | Required positive evidence | Required negative evidence | Applies to |
| --- | --- | --- | --- |
| Summary representation | Combined, split and overlapping expressions; complete membership; stable identities and evidence | Missing or foreign IDs, altered categories, false support, changed exact values, conflicting interpretations | Q8; any future summary change |
| Normalization | Idempotence; same-evidence duplicates collapse; raw and provenance retained | Same text from different occurrences, distinct obligations, non-equivalent paraphrases, destructive truncation | Q8 (D8.3); any future summary change |
| Native carry-forward | Empty, non-final, final and one/many-child routing; identical current child and evidence; complete lineage | Stale or forged child content, changed evidence, token duplication, fabricated origin, skipped final semantic work | Any future summary change |
| Repair | Exact target and dependencies, protected siblings, progress, full final validation | Stale authorization, widened scope, reset allowance, invalid survivor, unsupported verdict change | Q2b (if D2.2 reopens or D2.3 is adopted), E4, R6 |
| Loss attribution | Bound comparisons locate candidate-only and genuine upstream loss; dependencies and evidence retained | Missing or duplicate assignments, contradictory outcomes, uncertain owners treated as certain, lost source-only omissions, false upstream rebuilding | R6 |
| Exact-value representation | Occurrences recorded from exact bytes in bound fields; identity survives repair and readback | False matches, ambiguous occurrences, unbound fields, changed obligations | Q7, R6 |
| Loss-evidence correction | The narrow correction preserves subject, finding and scope; native validation reruns before repair | Nonexistent lines, stale producers, verdict replacement, budget or attempt reset, repeated defect | R6 |
| Cross-model behaviour (only when the user changes or compares models, H5) | Paired repeated trials in unrelated domains; all declared outcomes and costs | Meaning changed despite valid JSON and IDs; false rejection, unsupported acceptance, inconclusive or unusable results | H5 |
| Whole workflow | Real publication of the case's expected outcome (a failed or blocked run's incomplete publication under ADR 0041 doesn't count), complete required review, and human adjudication ([R8](../design/harness/acceptance.md), H1) | An early stop reported honestly; no golden outputs, fabricated E2E success, offline substitute, or advisory analysis presented as acceptance | Every measurement set, E0 if it resumes |

Offline unit and integration tests prove native mechanics only: for normalization, for
example, that only exact same-evidence duplicates collapse and that paraphrases and other
occurrences stay separate ([16-reference-ingestion.md](../design/contracts/16-reference-ingestion.md)).
Negatives that turn on meaning are judged only in live measurement sets, against
human-reviewed labels (rule 5, H1, H2). They never require native code to judge meaning
(§9), and never require a new judge. Phases whose boundary has no row (Q5 prompt hygiene, the
Q4 retry, Q10 review, E0 failure publication) are governed by their own validation and, for
E0, ADR 0041's tests.

## 3. Sequence

Tracks: **Q** quality phases (model-input changes, each measured; the critical path), **E**
engine work (no model-input change except E7's answer-bearing requests; §2.11), **T**
tests (offline, between measurement sets), **H** human and decision items, **R** research
and backlog. "Gap" means between measurement sets.

**Done, closed, stopped or deferred.** Done: Q1a and Q1b; the pre-baseline decisions (D2.1,
D11.2, D11.4, D11.5, DE6, H2's label scheme, v11's E0 marker); T1; T5 except its brittleness
counts; D11.1; D4.1's `uncovered_member` correction (kept); Q3 (`9ee7fd6`); E6's
producerless-rejection report defect (31 October 2026). Closed: Q6 (not kept, 30 October 2026),
Q2 and Q4 (not kept, 31 October 2026), D7.1 (record only). Records in [Z_FIX06](Z_FIX06.md),
with the earlier table. Stopped or deferred by user decision: E0 (stopped 30 October 2026;
ADR 0041 on hold) and Q2b's D2.2 (deferred 30 October 2026).

Open steps, in the existing order:

| Step | Item | Validation | Decisions |
| --- | --- | --- | --- |
| 7 | **Q2b** Generic content-loss guard for repairs: D2.2 deferred 30 October 2026 (user decision; its recorded premise was wrong and its literal trigger was met, so it awaits the user's re-decision); D2.3 for the dispositions insert that lost UTC twice: **decided and implemented 31 October 2026 (ADR 0046); two sets run 31 October: 12 of 12 published, correction never fired; keep awaits the user** | Measurement set (guards; target "not enough evidence") | D2.2 (deferred), D2.3 (decided (b)) |
| 11 | **Q4 retry** Remove engine vocabulary and schema-stated rules (hygiene), scoped by D4.1's proposed extension; not scheduled (Q4 not kept 31 October 2026) | Measurement set (guards) | D4.1 (extension proposed) |
| 12 | **Q5** Remove unmeasured single-run sentences (hygiene) | Measurement set (guards) | D5.1 (open) |
| 13 | **Q8** Source-claim granularity (B7) | D8.2 and D8.3 offline; a measurement set on the experiment and main builds only if D8.1 changes or withdraws the split | D8.1–D8.3 |
| 14 | **Q10b** Simplify the source-review taxonomy (B2) | Measurement set, B2 labels after H2 | D10.2 |
| 15 | **Q10a** Publish source-review findings as advice (B2), once Q10b is kept with better precision | Byte-identical requests, one run per case, B2 labels | D10.1 |
| 16 | **Q10c** Principle-review citations (B11) | None if D10.3 records a model limitation; a measurement set and H2's principle labels if it changes model input | D10.3 |
| 17 | **Q7** D7.2 delimiter stripping with ADR 0045; D7.3 token duties | D7.2: docs only if it keeps Decision 6 and withdraws ADR 0045, otherwise a measurement set; D7.3 offline | D7.2, D7.3 |
| 18 | **Q9** Reconciliation call structure (W4): capture replays (before E1 or E4 changes the capture contract), then a measurement set | Capture replay, measurement set | D9.1 |
| 19 | **Q11** D11.3 story-restatement deletion (D11.1, D11.2, D11.4 and D11.5 done) | Record only, or fixtures and a measurement set if built (user decides) | D11.3 |
| 20 | **Closing set** (ADR 0034 gate evidence): repeated runs of both cases on one committed, unmodified build (`build.source.modified` false; ADR 0034:64-65; uncommitted-tree runs aren't gate evidence, :34-35), unless the user amends ADR 0034. ADR 0034 recommends the build Plan starts from, after the ADR 0030–0033 conversions (:98, :102-104); the user decides | Run count the user's call (:66-67); every counted published run adjudicated (H1) | H1 |

**Engine track, in gaps:** **E2** (A2, with W5) in an early gap (its slot "after E0" lapsed
when E0 stopped); **E1** (A1, ADR 0030 slice 4) in any gap (its trigger "after Q2 is kept"
lapsed with Q2's revert), retaking its freeze with T5's projection on the commit before it
lands; **E3** startup after E1; **E6**'s remaining items in any gap; **E8** typed
schema-definition identities in any gap; **E4** (W3, ADR 0033) after E1, E2's measure, Q9's
capture replays (ADR 0033:260) and D9.1; **E5** (A4): closed reasons and the
simultaneous-failure gap with the E1–E4 conversion that rewrites them, the evaluator gap in any
gap; **E9** with E1, E4 or E5; **R-A1** after E1; **E7** (R2) last. E0 is on hold. E1, E4, E5
and E9 land only under §2.13. **Tests:** T2, T3 and T5's brittleness counts in any gap; T4
with E1–E4. **Human:** H1 now and for every set; H2's confirmation before Q10b; H3 in a gap
whenever the user reviews the panels; H4 before any formal baseline freeze; H5 whenever the
user chooses. **R** items after the phase that produces their evidence.

**Recommended changes to this order** (review, 31 October 2026; none decided):
- **Q10b, then Q10a and Q10c, before Q5 and Q8.** Review is the largest measured target
  (72.8–88.0% of each published run's tokens since Q1b; 4 of 35 defective subjects flagged,
  none with the right type; four review-stage budget failures since Q1b), and its comparison point, Q1b,
  is labelled and needs only H2's confirmation; running Q8 first would move the comparison point
  to a set whose labels H2 must also confirm. Against it: the current order puts review after
  generation settles, because Q10b assesses what generation produces.
- ~~D2.3 decided before the hygiene phases~~ (decided and implemented 31 October 2026; its
  measurement set awaits approval).
- **D5.1: no for now** (Q5).
- **The Q4 retry after the targeted phases** (Q2b, Q8, Q10b).
- **D7.2 decided now** if it keeps Decision 6 and withdraws ADR 0045 (docs only); **D7.3 in any
  gap** (offline).
- **D11.3 closed as record only**, or built (Q11).
- **Q9 kept or dropped:** it saves at most two sends and 2–4% of tokens per run.
- **E3 startup after E2's first measure** instead of after E1; nothing technical ties startup to
  E1, and FIX05 ordered them by ADR number (`Z_FIX05.md:4430-4434`).
- **D9.1 dropped as a prerequisite of E4;** Q9's capture replays still precede E4 (ADR
  0033:260).
- **E1–E4 before the closing set:** ADR 0034 recommends running the gate after the ADR 0030–0033
  conversions land and leaves that to the user (`0034-spec-quality-gate.md:100-104`).

The review's first recommended step, fixing E6's `MissingProviderEvidence` report defect before
the next measurement set, is done (31 October 2026; Z_FIX06).

**Open problems without a phase.** Restatement (Q1b: 5 of 10 publications): no phase targets
it, and Q8 only guards it. Invented or restating entities (B6; Q1b 8 of 10), which Q6 didn't
move. Unsupported additions (Q1b 6 of 10). The in-request duplicates Q3 left for Q6 (for
example `generation.prompt.md:2` beside `generation.context.json`'s `business_value` in the
brief request); proposed home, the Q4 retry (user decision). Reconciliation-repair harm, Q2's
target, now has an owner: D2.3 (implemented 31 October 2026, ADR 0046; unmeasured). Each stays here until a structural lever with an
owner is found or the user records it as a model limitation.

**Why this order.**
- **Harm before polish.** Q2 targeted the only observed requirement loss, a reconciliation
  insert repair answering `duplicate`; it wasn't kept, and the loss recurred on 29 October
  (Q2b).
- **One owner before content edits.** Q3 (done) moved ownership without moving bytes, so later
  wording changes edit one place.
- **Hygiene after the targeted fixes.** The Q4 retry and Q5 have no improvement target and are
  kept on guards alone. Q4 showed their risk: removing one extraction-context sentence came
  with hello-world's publication falling from 6 of 6 to 1 of 6.
- **Granularity on settled prompts.** Q8 follows Q5 so its two arms share the final extraction
  prompts; with Q4 reverted, those are Q3's unless Q5 runs. A split-disabled arm also rewrites
  the `citations` sentence (Q8).
- **Review after generation settles.** Q10b assesses what generation produces and needs H2's
  labels; Q10a publishes advice only once Q10b has made it more accurate.
- **ADR-level text rules late.** Q1b and Q3 supplied D7.2's repeated rendering evidence (12 of
  12 evaluated publications); D7.3 is offline.
- **Q9 last.** It has the lowest value (reconciliation is 4–9% of a published run's tokens) and
  the highest risk, and its call count depends on Q8. Only its capture replays must precede E4
  (ADR 0033:260).
- **Engine work in the gaps.** ADR 0034 puts Spec quality first; engine items claim no
  quality change and land between sets, in ADR order, under §2.13. E2's slot already precedes
  E1; whether ADR order or E2's measure governs E3 is the user's choice.

## 4. Quality phases (Q)

### Q1. Remove the rejected patches and take the clean baseline

Done: Q1a on 28 October 2026 (`d4fd4a5`), Q1b on 29 October 2026; records in
[Z_FIX06](Z_FIX06.md#q1-remove-the-rejected-patches-and-take-the-clean-baseline). Q1b's table
(§10) is the comparison point.

### Q2. Repair requests carry their step's definitions

**Closed 31 October 2026 (user decision: not kept).** D2.1 (b) bound each phase family's field
definitions to its requests and repairs (2,218 of 4,406 projected requests changed; user content
identical). On paired replays of the 27 October 09:40 dispositions inserts, harmful answers
stayed 1 of 40 and valid answers fell from 40 to 36 of 40. The plan, D2.1, the replays and their
reports are in [Z_FIX06](Z_FIX06.md#q2-repair-requests-carry-their-steps-definitions). The gap
stays: six repair requests take their task only from the three-line `repair.prompt.md`
(`design/workflows/spec.workflow.yaml:376`, `:413`, `:610`, `:816`, `:899`, `:914`), and the two
reconciliation repairs (`:606-613`, `:910-915`) bind no context either; it is counted as a §2.6
brittleness measure. The requirement loss Q2 targeted is tracked in Q2b.

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

**Correction (review, 31 October 2026).** Q6's set did have a harmful repair: in hello-world
`2026-10-29T20-47-23Z-6e8e…` the dispositions insert for the UTC claim (call 6) answered
`duplicate` of claim 1, and the spec lost the requirement. D2.2 can't catch it, since an insert
has no old value. Whether this reopens D2.2 is the user's call. "Its own measurement set after
Q2" lost its anchor when Q2 wasn't kept.

**The dispositions insert.** Hello-world's UTC claim needed this insert
(`src/domain/reference_reconciliation_repair.zig:222`; request
`design/workflows/spec.workflow.yaml:606-613`) in four retained runs, with byte-identical request
text: `retained` on 27 October 05:06 and 29 October 20:52Z, `duplicate` of claim 1 on 27
October 09:40 and 29 October 20:47Z, each losing the requirement. They are the only requirement
losses among the 20 hello-world specs published 26–31 October before Q4. Replayed 20 times on
the Q1b build, the request answered `duplicate` once (Z_FIX06, Q2). An insert follows an initial
dispositions response that lists only claim 1, a complete JSON object: in the 40 pre-Q4 runs
that reached dispositions, five such responses produced all 12 inserts sent, 2 of them harmful.
Hello-world's initial dispositions request is byte-identical from 27 October 09:40 to the Q3
build (digest `2fbbc87e9f1d`), and 4 of its 20 runs took this path, so it is live on the current
build. The omission isn't tied to the §22.6 partial-prefix normalization: on Q4's build one
prefixed response listed all 25 claims, and an unprefixed one (`2026-10-31T02-54-32Z`) listed
only claim 1, followed by 24 `duplicate` inserts (harm unverified).

**Decision.** **D2.3, decided 31 October 2026: option (b), native variant** (user: "implement
D2.3: the requirement loss with recommendations"; ADR 0046). Option (a) was recording it as a
model limitation. **Implemented 31 October 2026, offline, uncommitted:**
- **Binding.** A dispositions assignment binds its semantic claim IDs as `exact_members` with
  a native count. The selected schema keeps its canonical bounds, so the request the model
  receives is unchanged. Admission rejects an omitted claim as `missing_member` (new reason; the
  correction names it as `member`) and a repeat as `duplicate_member`. The dispositions
  request's own `retry-limit` (2) bounds the whole-assignment correction, and exhaustion fails
  the run.
- **Conflict-group repair.** The source-omission conflict-group repair shares the binding under
  its `retry-limit` (1).
- **Deleted.** The per-claim insert, the redundant-record deletion, the competing block and the
  foreign replacement are deleted. A gap that still reaches readback is `InvalidAtomicRepair`.
- **Recording.** Descriptions record the binding in the existing `members` list, and replay
  reapplies member sets natively over the recorded bounds, so `model-request-debug/v13` and its
  captures still decode.
- **Packet copy.** A packet-copy bug (`model_input_packet.zig` dropped the new mode) was caught
  by the integration scenario and fixed.
- **Request projection.** `evaluations/request-projection/d23-2026-10-31` against
  `d41-2026-10-30`: 206 dispositions requests differ only in the recorded `members`. Every
  model-visible difference is in the rescripted scenarios 70, 82, 83 and 125–128.
- **Out of scope.** The statement, signal and conflict coverage inserts (at-least-one coverage,
  no harm seen) and token classifications (a composite key) are left out. Each needs its own
  decision if harm appears.
- **Order.** D2.3 lands before E4's freeze. D9.1 must keep the binding in any combined schema.
- **Report contract.** `Relations.competing` is no longer set but stays in the report contract
  until §2.13 allows its removal. The source's unused dispositions occurrence set is deleted
  (never reported or persisted; the projection is unchanged by it).
- **Measurement set (31 October 2026, 3 runs per case on the uncommitted D2.3 tree; measures
  `evaluations/d23/measures-set.json`).** All 6 published: hello-world 3 of 3
  (`07-27-52Z-d49e…`, `07-28-49Z-cdde…`, `07-29-37Z-f496…`), loan-renewal 3 of 3
  (`07-27-53Z-1098…`, `07-30-19Z-83fe…`, `07-31-09Z-615b…`).
  - **Target:** every first dispositions answer listed all its assigned claims (3 of 3 and 5
    of 5), so the new correction never fired and no reconciliation repair ran. Every
    hello-world spec keeps UTC. The set can't show the target (not enough evidence).
  - **Guards against Q1b:**
    - sends: hello-world 23 / 25 / 25 (Q1b 22 / 23 / 27); loan-renewal 25 / 26 / 29 (12 /
      25.5 / 27);
    - tokens: hello-world 61,885 / 73,706 / 84,067 (58,282 / 65,119 / 122,002); loan-renewal
      85,943 / 104,705 / 123,519 (26,347 / 96,736 / 113,908);
    - protocol corrections: hello-world 2 in 73 sends, both review `array_length` at
      `/findings` in one run (Q1b 1 / 142); loan-renewal 0 in 80 (5 / 129);
    - runaways: 1 hello-world and 2 loan-renewal, pooled; repairs 0.
  - **Excluded:** four earlier attempts made no billed call: two with a wrong `--case`
    argument (`input_invalid`) and two provider 403s before credentials were refreshed.
  - **Second set (31 October 2026, 3 more per case on the same tree; all 12 runs in
    `evaluations/d23-12/measures-set.json`).** All 6 published (`07-35-26Z-345c…`,
    `07-36-13Z-d0ed…`, `07-37-10Z-f5c2…`; `07-35-27Z-0669…`, `07-36-18Z-f191…`,
    `07-37-18Z-61b3…`). Again every first dispositions answer was complete, so the correction
    never fired and no reconciliation repair ran.
    - **Across 12 runs:** publication 6 of 6 per case; sends hello-world 23 / 23.5 / 25,
      loan-renewal 25 / 26.5 / 29; tokens 60,761 / 66,147 / 84,067 and 85,943 / 91,811.5 /
      123,519; protocol corrections 4 in 143 and 3 in 161 sends, none `missing_member`;
      runaways 1 and 2; repairs 0.
    - **Openings:** all 12 answers open with `{"{`. Every earlier omission opened with
      `{"claim{`, and that form didn't occur here (a correlation only).
    - **Omission rate:** 0 of 6 hello-world omissions against the earlier 4 of 18 on the same
      request bytes. That is within chance (about 0.22 probability), so the omission rate
      hasn't changed measurably and the target stays unobserved.
  - **Not done:** no evaluations, no adjudication. Keeping D2.3 is the user's decision.
- **Contract review.** No blockers. Two majors fixed: native replay cases, and the
  conflict-group repair's admission rejection. Minor fixes: the dead field deleted, the kept
  field commented, a criterion for a native count added to contract 12, the ADR's diagram
  reference corrected, and an equal-count foreign case added. Not changed: `member_count` could
  be folded into the `collection` variant (an illegal state guarded at restriction), and the
  exhausted scenario doesn't assert the final rejection reason.
- **Replays.** A retained capture's first dispositions request is unchanged, so replaying it
  measures only the omission rate (about 4 in 18 hello-world). The correction request exists only
  in captures from this build, so the target rests on the measurement set and any later replays
  of those captures. The target (2 losses in 20) is too rare for a set to show alone; declare it
  "not enough evidence" unless events accumulate.

**Validation.** Paired replays of the captured requests decide the target; then a measurement
set. **Keep if** requirements lost in reconciliation and harmful repairs fall, and sends,
tokens, `RepairNoProgress` and exhausted runs don't rise; under (b), count protocol corrections
against the inserts they replace. If D2.2 is reopened: **keep if** harmful repairs fall and
neither `RepairNoProgress` nor exhausted runs rise.

### Q3. One owner per model instruction

Done 31 October 2026, committed as `9ee7fd6`; record in
[Z_FIX06](Z_FIX06.md#q3-one-owner-per-model-instruction). Left open: T2 (only partly done by
Q3), the in-request duplicates Q3 left for Q6 (§3, "Open problems without a phase") and the
`ValueChoices.correction` arm (E9).

### Q4. Remove engine vocabulary and schema-stated rules from prompts

**Closed 31 October 2026 (user decision: not kept).** Every listed removal was built (3,149 of
4,406 projected requests changed), and the 12-run set (`evaluations/q4/measures-set.json`)
failed against Q1b: publication 1 of 6 for hello-world and 2 of 6 for loan-renewal.
Hello-world's first extraction call returned `no_feature_claim` in 5 of 6 runs, against 0 of 13
on the Q1b, D4.1, Q6 and Q3 builds, whose first extraction request differed from Q4's only by
the removed second `citations` sentence (`extraction.context.json:14`, "The cited lines become
the claim's wording; …"); causation is not replayed. Q4 removed it as restated engine behaviour,
but it says what a claim is. Record:
[Z_FIX06](Z_FIX06.md#q4-remove-engine-vocabulary-and-schema-stated-rules-from-prompts).

**Decision.** **D4.1** Prompts carry task semantics only; an engine-enforced rule leaves a
prompt only when the schema or its correction states it. **Decided 30 October 2026 for
`uncovered_member`** (step 5a; kept; record in Z_FIX06; it hasn't fired in the 26 runs since).
`required_preserve` is unchanged. Making any other correction state a rule changes
model-visible engine text and is a separate decision with its own measurement set. **Proposed
for the retry** (review, 31 October 2026; not decided): the rule covers native rule and
correction texts too, and a sentence that says what a field, claim or response contains stays
even when the engine also enforces or transforms it.

**Open: the retry** (not scheduled). Still model-visible: `support.prompt.md:35-36` ("The
engine binds claim evidence …; never return provenance or claim IDs"), `packet-guidance.json:69`
("Native code fixes claim evidence for the assigned subject"),
`reconciliation-dispositions.prompt.md:2-3` ("Tokens are read-only native facts"),
`extraction-classifications.prompt.md:2-5` ("the engine requires exact preservation",
"canonical", "native constraints"), `records.prompt.md:4-5` ("Family presence is structural"),
`support-loss.prompt.md:22` ("native-assigned"), the restated "one entry for every assigned
requirement_ordinal, exactly once" (`support.prompt.md:3-4`, `principle.prompt.md:3-4`;
`exact_members` gives a repeated member `duplicate_member` and a missing one `array_length`), and
two native texts: the "native code …" rule texts in
`src/domain/reference_reconciliation_diagnostic.zig` (lines 102, 107, 120, 123, 125, 133 and
135; in every initial reconciliation request, 866 of 4,406 projected, plus 2 of 44 context-free
repairs) and `src/domain/typed_text.zig:156` ("native admission assigns its occurrence
identity"; the `unknown_exact` description, sent in no projected or retained request, so
rewording it alone is provable under §2.11). Proposed scope (D4.1's extension): one change set
over all of them; reword engine vocabulary in place; remove a restated rule only when the schema
or its correction states all of it (the support and principle "exactly once"); keep task
semantics the engine doesn't check: both `citations` sentences, the `claim_ids` definition and
the coverage sentence (`records.prompt.md:9-11`). Also proposed, for the user to decide: the
in-request duplicates Q3 left (§3). No `extraction.context.json` sentence carries engine
vocabulary; the retry's extraction exposure is `extraction-classifications.prompt.md:2-5`. It
has no improvement target: none of the 22 specs published 29–31 October before Q4 contains
engine vocabulary. 12-model-boundary.md:421-422 and ADR 0016:148-149 say "FIX06 Q4 removes
them", so the retry keeps the Q4 ID.

**Validation.** Request projection: only the listed texts change. Scripted responses with a
missing and with a repeated member, for source and principle reviews, receive the
`array_length` and `duplicate_member` corrections, compared with the owning explanations. Then a
measurement set. **Keep if** (hygiene, §2.7) engine vocabulary stays absent from published
specs, and protocol corrections, admission rejections by reason, other defect classes and cost
stay within the comparison point's range. Never rename a field to chase an observed leak.

### Q5. Remove unmeasured single-run sentences

**Changes** (owners after Q3):
- `extraction.context.json:4` (`claims`): "Include meaningful identity and purpose headings."
  (`5a4001f`) and "Separate independent behavior, implementation and verification facts."
  (`d247a9c`; current wording from `f7199b1`); the second sentence of `business`, `technical`
  and `validation` (`:6`, `:8`, `:9`; `d247a9c`): "Preserve technical qualifiers with the
  behavior.", "Technical terminology alone does not make observable behavior technical.", "A
  behavioral requirement being testable does not make it a validation claim." "One
  independently meaningful source fact per entry." stays; claim granularity is Q8's.
- `support.prompt.md:15-16`: ", including compatible requirements labelled conflicting" and
  "Empty claims or conflict labels do not establish a source gap." (`ebbe968`; the idea first
  appears in `bc2c302`); `:29`: "A defective candidate is not a source gap." (`bdbae22`).
- `records.prompt.md:7-8`: "Do not relabel positive requirements as assumptions or non-goals"
  (`433ccf7`, reworded by `5ffec56`), keeping the rest of its sentence.
- `packet-guidance.json:4`, `:7` and `:9`: "The source need not supply a title" (`212a12c`), "do
  not invent a persona or benefit or require a prewritten story" (`35ded13`) and "Displayed
  values alone do not establish entities…" (first in `b55ff39`, 22 September, in contract 12 and
  the native description; current wording from `2bcd178`; its 32-call comparison,
  `test/calibration/entity-applicability/`, was prepared, superseded on 10 October and never
  run). Open: whether ", and an explicit declaration of absence is unnecessary"
  (`packet-guidance.json:9`) goes too; contract 12:830 states both.

**Decision.** **D5.1** (not decided) Remove them together as one change set (hygiene, §2.7). If
a watched class worsens, revert Q5 in full (§2.1); restoring or keeping a single sentence is a
new phase with its own measurement set, recorded here with its evidence. Amends
17-specify.md:239-241 (the title and persona clauses) and 12-model-boundary.md:829-831 (the
displayed-values clause, at :830-831); whether it also amends 12-model-boundary.md:996-997,
which mirrors the conflict-label and heading sentences, is unverified.
- **Risk.** Q4's only change to the extraction-context requests was one definitional
  `citations` sentence of this same context, and hello-world's first extraction call then
  returned `no_feature_claim` in 5 of 6 runs (not replayed). Q5's first item edits the `claims`
  and category entries carried by the extraction content request and its three repairs
  (`spec.workflow.yaml:331`, `:376`, `:413`, `:899`). Q5 has no quality target, so its set can
  only detect harm. Its relevance is low but not nil: it is the item for §2.6's "guidance
  sentences without repeated-run evidence" and AGENTS.md's "prompt patched after one run" flag.
- **Recommendations** (31 October 2026; not decided). Earlier that day: yes as written, after
  replaying hello-world's first extraction call paired with and without Q5 (each replay a live
  run needing approval), a `no_feature_claim` rise like Q4's stopping Q5 before the set. The
  later review: no for now, reopening a sentence only when a defect is traced to it, as its own
  measured change, with the `support.prompt.md` sentences going to Q10b, which rewrites that
  decision tree. The review also raised running the `extraction.context.json` removals on their
  own; that contradicts D5.1's one-set form and is only a question for the user.

**Validation** (if D5.1 is yes). Measurement set, watching `unsupported_addition` (invented
personas), `invented_or_restating_entity` (displayed-value entities), and clarification and
blocked outcomes (title gaps, conflict labels); of the classes the earlier text watched, only
those two are T5 classes. **Keep if** those and the guards don't worsen.

### Q6. Scope the obligation instruction

**Closed 30 October 2026 (user decision: not kept).** D6.1 (b) kept "preserve conditions and
obligations" only in six record purposes (1,026 of 4,406 requests changed). In its set stories
still restated FR-001 in all five publications and entity meanings in 4 of 5 (Q1b 8 of 10), so
restatement didn't improve (benefit not demonstrated, §2.7). Its one lost requirement
(hello-world `2026-10-29T20-47-23Z-6e8e…` dropped UTC) came from a reconciliation insert repair
whose request Q6 didn't change (Q2b). Record and runs:
[Z_FIX06](Z_FIX06.md#q6-scope-the-obligation-instruction).

Restatement stays a measured defect class with no proposed lever; Q8 measures it as a guard.
The in-request duplicates Q3 left have no owner; proposed home, the Q4 retry (user decision).

### Q7. Exact values

**D7.1** (exact-value corrections state the boundary rule) closed 31 October 2026 (user
decision, option 1: record only): no such correction exists. Record in
[Z_FIX06](Z_FIX06.md#d71-exact-value-corrections-state-the-boundary-rule).

**Decisions.**
- **D7.2** Decide ADR 0036 Decision 6 (delimiter removal) and ADR 0045 (B12) together, at
  Decision 6's owner (`exact_value_recognition.zig:58-84`; its prohibited-field branch,
  `specification_provenance.zig:227-232` and `:281-284`). Every published Q1b run has a
  rendering artefact (hello-world 6 of 6, loan-renewal 4 of 4), as do both Q3 runs.
  - Decision 6 was adopted after one live pair (ADR 0036:13-15). Since then models wrote exact
    values in backticks in 34 retained runs, and none of the 38 native publications (26–31
    October) shows escaped backticks or a generated-field `reference_only` rejection.
  - Its prohibited-field branch is the established mechanism of ADR 0045's case, plain values in
    an entity meaning (Q1b `09-03-15Z` D4, `09-05-47Z` D6; Q3 L-D3). That case is in Q1b
    loan-renewal 2 of 4 and in the Q3 loan-renewal run, which meets ADR 0045's build condition.
    In all six recorded instances the meaning also restated the requirements
    (`invented_or_restating_entity`, B6, which no phase owns), so ADR 0045 would format a defect
    rather than remove it. **Recommended** (review, 31 October 2026; needs the user's approval,
    as it edits accepted ADRs): keep Decision 6 and withdraw ADR 0045 (docs only).
  - Either outcome updates ADR 0045's hold sites (0045:3-5, 0020:21-22, 0036:36-38,
    design.md:1166). Building it re-applies the listed parts of `git show
    d74fc1f:design/contracts/text-field-composition.md` (the preamble, the incidental-occurrence
    sentence, the inventory rows, the section heading and its anchors, the prohibited-role list
    and the incidental-role bullet) to the current text, whose preamble now also names ADR 0036
    and the ADR 0016 packet-guidance amendment. Withdrawing it removes those references.
  - The model's own quotes around the engine's code span (Q1b hello-world 6 of 6, loan-renewal
    3 of 4; Q3 hello-world) have no owner: Decision 6 removes only backtick runs
    (`exact_value_recognition.zig:8-11`). Removing them would be a punctuation rule over model
    output (AGENTS.md "Prose heuristic"), so they stay recorded as model output unless the user
    decides otherwise.
  - Claim wording still carries source Markdown, list markers included, into later requests; no
    published spec since Q1a shows a list marker (B7).
- **D7.3** Whether a token's appearance inside a claim uses the recognition boundary, so a token
  inside a word (`CTIV` in `ACTIVE`, pinned at `structured_token_test.zig:45`; in-word
  `ACTIVEFUL` at `:56`) no longer forces a duty. Owner `exact_token_obligation.zig:11-31`;
  amends ADR 0024:33-35 and ADR 0036 Decision 5 (0036:121-125). A false duty makes the spec carry
  the token or blocks the run on `missing_exact_copy` (`specification_coverage.zig:93`). Claims
  quote source Markdown (ADR 0036), so the recognition boundary alone would also drop real
  duties: a link destination in its own claim (the `]` before `(` gives `unbalanced_wrapper`,
  `exact_value_boundary.zig:106`) and a code span with a suffix attached (`right_continuation`,
  `:122`). The decision says whether and how it keeps them. One option needs IDs only and none of
  the boundary tables: force a token only from a claim that cites its own occurrence (Decision
  5's "cites in full", which D8.2 also reads).

The boundary tables (`exact_value_boundary.zig`) are never extended case by case. A boundary
rejection is silent: the value stays prose (`exact_value_recognition.zig:109`) and no record
keeps its reason, so no set can count rejections by reason. When no other occurrence covers a
required value, the run ends in a `missing_exact_copy` block, which never repairs
(`specification_coverage_repair.zig:26-30`); none of the 54 retained runs (26–31 October) has
one.

**Validation.** D7.3 is deterministic and decided offline: accepted and rejected fixtures at its
owner (a token inside a word, a whole-word match in another claim of the chunk, a link
destination, a code span with a suffix) and byte-identical development-case requests (§2.11).
Each development token occurs only as its own delimited code span, so either rule forces the
same tokens and no set can exercise D7.3. D7.2 is docs only if it keeps Decision 6 and
withdraws ADR 0045; anything it builds changes published output and gets a measurement set.
**Keep an ADR 0045 build if** loan-renewal's plain-value artefacts fall and no guard rises.

### Q8. Source-claim granularity (B7)

**Changes.** An experiment build with the list-item split disabled
(`reference_extraction_text.zig:144-183`); the main build keeps it. A split-disabled arm must
also rewrite the second half of the `citations` sentence (`extraction.context.json:14`), which
describes the split, so it isn't an engine-only toggle.

**Evidence (31 October 2026).** The first extraction request, with its inference settings, has
been byte-identical since 26 October 07:06: 20 runs per case with output. The model cited the
whole list in 13 of the 40 (hello-world 9 of 20, loan-renewal 4 of 20); the split fired in each
and gave the same per-item claims the model gives when it cites per item, and none of the 40
repeated a citation set. Q1b's loan-renewal restatement (3 of 4 published) came from runs where
the split never fired. Q4's request differed only by the removed `citations` sentence (Z_FIX06):
loan-renewal then cited the whole list in 6 of 6 runs, and 2 of 6 repeated a citation set
(`[5,6,7,8,9]` five times, 25 quoted claims). In `2026-10-31T02-52-34Z-b671…` reconciliation
marked 24 claims `superseded` by claim 1, and the run failed on the token budget in review; in
`…T02-54-32Z-8be8…` 24 single-claim repairs answered `duplicate` of claim 1, leaving only
requirement 1 retained, and it failed on the budget at the signals request. In
`…T03-01-37Z-7c6a…` a twin appeared after the split under a different category (`technical`);
`same_content_kind` (`reference_disposition_validation.zig:149-152`) rejected its `duplicate`,
and the run exhausted its retries on that claim's signal.

**Decisions.**
- **D8.1** Keep, change or withdraw ADR 0036 Decision 3 and ADR 0038 Decision 4. ADR 0038's
  scenario-coverage rule depends on per-item claims, so a withdrawal must say how coverage is
  kept (ADR 0038:65-69), and must rewrite the `citations` sentence, a model-input change Q4's set
  implicates; such an arm would likely separate from the main build at extraction because of
  that sentence, not the split. On these sources no set can measure the split's known limit, a
  lead-in condition (ADR 0038:78-80): neither development source has one. **Recommended**
  (review, 31 October 2026; not decided): keep, record only.
- **D8.2** Whether "cites in full" (ADR 0036:121-125) covers a fenced block whose first or last
  interior line is blank. The block's token spans every interior line
  (`markdown_code_spans.zig:53`, `:59`), forcing is byte containment
  (`exact_token_obligation.zig:40-45`), and blank lines aren't citable
  (`source_selections.zig:57-60`), so a run that starts or ends on a content line leaves the
  blank line out of the quote (`reference_extraction_text.zig:198-205`): citing every content
  line leaves the token free unless the fence beside each blank edge line is cited. No fixture
  covers it (`reference_extraction_test.zig:364-385`).
- **D8.3** Whether claims with the same category and cited lines are one claim. The closest
  precedent is contract 16's exact-duplicate collapse with the raw response kept
  (16-reference-ingestion.md:254-262). Options: collapse them at extraction text validation
  after the split, or dispose of them natively as equal-byte tokens are
  (`reference_token_disposition.zig:1-11`). It must also cover claims inserted by source-omission
  repair (ADR 0036:119-120). A pair on the same lines with different categories (Q4's
  `03-01-37Z`; the scripted pair at `spec_generation_responses.zig:152-160`) needs its own
  answer.

**Validation.** D8.2 and D8.3 are deterministic and decided offline, like D7.3: accepted and
rejected fixtures at their owners, an unrelated-domain fixture, and §2.11 request projections
(byte-identical unless a scripted scenario repeats a same-category citation set; unverified).
Neither development source has a fenced block, and no current-build run repeated a citation set,
so no measurement set exercises either. If D8.1 is to change or withdraw the split, T5 first
defines claim counts and claims lost in reconciliation (e2e.md "Run measures" has neither), then
a measurement set runs on the experiment and main builds, also measuring conditions separated
from their items, restatement (including claim-by-claim business rules), scenario coverage and
cost. **Keep a withdrawal if** (non-inferiority) claims lost in reconciliation and restatement
don't worsen, conditions stay with their items, and scenario coverage doesn't fall.

### Q9. Reconciliation call structure (W4)

Every Q1b and Q3 run made two extraction calls and four reconciliation calls (summary,
dispositions, signals, conflicts) before authoring; more than eight claims add partition
summaries (`spec.workflow.yaml:451`). Reconciliation is the largest YAML stage (51 steps) but
took 4.1–8.6% of a published Q1b or Q3 run's tokens (review 74.6–88.0%); combining
dispositions, signals and conflicts saves at most two sends and 2–4% of tokens, and none of
those calls needed a protocol correction or re-send in the 20 Q1b, D4.1 and Q3 runs. Claim
count moves the cost more: on Q4's reverted build a 27-claim loan-renewal run made five summary
calls and 24 reconciliation repair calls (104,288 tokens).

The split is deliberate: [ADR 0022](../design/decisions/0022-native-reference-phase-handoffs.md)
requests, validates and repairs each phase before requesting its descendants, feeding each
the previous phase's validated native facts (§16.4 step 10, normative), through
[ADR 0016](../design/decisions/0016-configured-json-response-composition.md)'s assignment
contexts. ADR 0016 itself calls smaller responsibilities "a reliability hypothesis, not a
demonstrated cure".

**Changes.** First replay retained `model-request-debug/v13` captures (Q1b or later; raw
response bytes are no longer needed) with `e2e-call --repeats`: the separate dispositions,
signals and conflicts requests, and one combined request sent with `--edit`, comparing claims,
groups and conflicts on both development cases. The replays run before E4 (ADR 0033:260), and
before E1 if E1 advances `model-request-debug` (ADR 0030:373-376). Each replay needs approval.

**Decision.** **D9.1** Combine the calls only on that evidence. This amends ADR 0022 and
§16.4 step 10, ADR 0016's assignment-context amendment and ADR 0033's per-phase repair
owners, and must say how a combined response is validated phase by phase and how a defect in
one phase is repaired without re-requesting the others. With a gain this small, whether Q9
stays in the sequence is the user's decision.

**Validation.** Measurement set. **Keep if** reconciliation sends and tokens per attempted
workload fall, while claims lost in reconciliation, groups, conflicts and completion don't
worsen.

### Q10a. Publish source-review findings as advice (B2)

**Decision.** **D10.1** Amend ADR 0023 (0023:69-70, "This change adds no source-advice Markdown
section", as amended by ADR 0040:11-14 for incomplete source review) and the
`reference-context.md` rendering text (17-specify.md:465-467, 23-rendering.md:148-158,
F0100-SpecWorkflow.md:953-956): negative source-review findings appear as an advisory section,
as principle findings already do (`reference_context.zig:95-124`; source review shows only its
incomplete status, `:20-24`). They never repair content or create clarifications. Source review
flagged hello-world's lost UTC requirement as `candidate_omission` three times on 27 October
09:40, and again on 29 October 20:47Z (call 21, "Must also output date and time in UTC"); the
reader never saw it.

**Precondition** (§3): Q10b kept with better precision. On Q1b's provisional labels (H2), 8 of
source review's 12 non-`supported` findings were on clean subjects and the other 4 had the
wrong type, so most of a section published now would be false. If ADR 0041 resumes, its failed
view's `reference-context.md` needs the same section.

**Validation.** Rendering tests from typed findings; byte-identical requests (§2.11); one run
of each case; the measurement sets' B2 labels show how many published findings are true.

### Q10b. Simplify the source-review taxonomy (B2)

Review is the largest cost and catches little. On the kept builds since Q1b it took 72.8–88.0%
of each published run's tokens (Q1b hello-world 74.6–88.0%, loan-renewal 78.4–83.6%; D4.1
72.8–84.4%; the Q3 runs 74.6% and 82.0%). One D4.1 loan-renewal run, and three on the reverted
Q6 and Q4 builds, ended `WorkflowTokenBudgetExceeded` in review and published nothing. On Q1b's
provisional labels (H2), source review flagged 4 of 35 defective subjects, none with the right
type (hello-world 4 of 14, loan-renewal 0 of 21); 8 of its 12 non-`supported` findings were on
clean subjects, and its details held 30 false statements across 202 findings. The Q3
loan-renewal review judged all 23 subjects `supported`, including the story's "may renew". (On
26 October, one pre-Q1a label set: 1 of 28 defective subjects with the right type, 26 false
statements.) Quality over cost: no check is dropped to save tokens, but spending that buys no
quality is removed at its owner.

**Changes.**
- Fewer finding types, with the engine deriving routing from typed facts instead of the model
  choosing it. After generation no verdict repairs content or creates a clarification (ADR
  0023), yet assignments still offer up to eight verdicts, three of them with a `question`
  (`support.schema.json:133-160`; the decision tree is `support.prompt.md:12-33`).
- Unify the single and assignment finding selection. `finding` and `applicability_finding`
  order `candidate_invalid` and `inconclusive` differently (`support.schema.json:123-130`,
  `:148-157`); the definition is chosen by raw string (`specification_support.zig:218`, `:404`;
  E8); and source-preservation single findings drop the `negative` guidance rule in a
  projection branch (`:398-401`), while assignments derive both their guidance-rule removal and
  their excluded variants from one typed withheld set (`:230-236`, `:296-301`, `:323-330`).
  `preservation_finding` has its own `candidate_invalid_preservation` shape
  (`support.schema.json:92-107`), so whether definitions merge is D10.2's.
- Clarify original-source authority, the candidate target and completeness for the assigned
  field purpose in their Q3 owner, `packet-guidance.json`'s `review_scope` and
  `support_evidence` entries. Check the chosen change first with approved `e2e-call --repeats
  --edit` replays of Q1b's labelled review requests plus clean controls (model judgments can't
  be compared offline; `--edit` replaces only content and schema, so the captured admission
  constraints stay, and replaying an assignment whose schema drops a captured excluded verdict
  is unverified); the measurement set decides.

One observation for D10.2, a single run that decides nothing: Q4's `2026-10-31T02-52-18Z`, the
one retained run with empty extraction, raised the source-gap clarification that
`support.prompt.md:16` targets (`clarify/S01.md:17`).

**Decision.** **D10.2** Amend ADR 0023 and `support.schema.json`, and say whether the rewritten
`support.prompt.md` absorbs the sentences the Q4 retry and Q5 name (`support.prompt.md:3-4`,
`:14-16`, `:29`, `:35-36`).

**Constraints.** §9.

**Validation.** Measurement set and B2 labels, after H2. **Keep if** finding-type accuracy,
recall per labelled type and detection recall improve and false statements fall.

### Q10c. Principle-review citations (B11)

Since ADR 0042 Decision 4's line was withdrawn (0042:64-72), every principle citation has been a
whole file or absent: on 27 October hello-world had 21/21, 20/20 and 19/19 blanket and
loan-renewal 18/18 (09:40), with five details naming a principle they don't cite, and the 05:06
loan-renewal run cited nothing (0 of 22); Q1b 164 of 164; D4.1 79/79, Q4 47/47 and Q3 12/12
and 18/18; two Q6 loan-renewal runs cited nothing. `principle.prompt.md:16-17`'s "Cite relevant
policy text, not just a heading", there since 25 September (`433ccf7`), has not changed this. A
citation reaches the reader only on an adverse finding (`reference_context.zig:103-118`): one in
the 25 published runs from Q1b on, D4.1's 19:56 hello-world `ambiguous` display-name finding,
which cites `project-structure.md` lines 1–60 while its detail says no principle addresses the
subject. The packet gives each principle unnumbered, with only its chunk bounds, and chunks are
16 KiB windows (`principle_registry.zig:11`, `:148`), so each development-case principle is one
chunk and a precise range needs the model to count lines.

**Decision.** **D10.3** Either record citation precision as a model limitation, or change model
input: the citation instruction (`principle.prompt.md:14-18`; Q3 moved the principle packet's
task to the shared subject purposes in `packet-guidance.json`, and the citation instruction
stayed) or the principle presentation (numbered lines or smaller chunks). Before calling blanket
citations a model limitation, D10.3 says whether the current presentation is a coherent
contract. **Recommended** (review, 31 October 2026; not decided): record it, given one adverse
finding in 25 runs and ADR 0042 Decision 4's two prompt lines, which cut citations to 17 of 76,
then produced 20 templated false statements in one pair. A whole-file citation is structural, so
recording needs no H2; a change to model input needs H2's principle labels. No rule may inspect
citation text, and ADR 0042's admission constraint stays unchanged.

**Validation.** For a change to model input only: measurement set; principle-citation precision
and principle false statements.

### Q11. Remaining rules and design text

D11.1, D11.2, D11.4 and D11.5 are done (28–29 October 2026, committed in `371b55a` and
`5bb7f17`); their records are in [Z_FIX06](Z_FIX06.md#q11-d111-d112-d114-and-d115).
Withdrawing the §22.6 salvage would be a new decision.

**Decision.** **D11.3** ADR 0035: never delete a covered restatement whose claims no other
record names (claim IDs are the only deterministic reading of "last mention"; the user confirms
that reading). Only a story restatement can do that: `restatesStory`
(`specification_generation.zig:348-353`) flags any single-statement record other than a
functional requirement whose statement equals the story's when the story covers its evidence; a
cross-kind restatement (`:334-343`) keeps a record naming every claim of the deleted one. The
deleted record's claims stay mapped through the story (ADR 0038:86-88). The story form motivated
ADR 0035 (both cases on `8a600d7`, Z_FIX05:3076-3092) but hasn't fired since: the 54 retained
runs hold three restatement deletes, each a business rule identical to a functional requirement
(Q1b `2026-10-29T09-15-43Z-0ab4…`, graded helpful; Q6 `2026-10-29T20-45-17Z-7fb8…`, two). The
user decides: close it as record only, as D7.1 was, or build it (amends ADR 0035 Decision 2)
with accepted and rejected fixtures at the owner, then a measurement set, which may not exercise
it. It removes no closed report member (§2.13).

**Validation.** If built: fixtures at the owner, byte-identical development-case requests
(§2.11), then its own measurement set, never stacked with another decision; a set that never
exercises the rule reports "benefit not demonstrated" (§2.7).

## 5. Engine track (E)

Each item: `/preflight`, offline tests, the §2.11 freeze diff, `zig build verify`, one live
run of each case (DE2 and DE3 ask whether offline evidence replaces it for structural
conversions), landing between measurement sets and under §2.13. E7's live validation is its
clarification-producing case instead.

### E0. Failed and blocked runs publish validated content (B10, ADR 0041)

**On hold since 30 October 2026** (user: "stop E0";
`design/decisions/0041-failed-run-incomplete-publication.md:3-4`). Slice S1 and part of S2 were
built, then removed. Nothing under `src/` names `failure-output`, `spec_incomplete` or
`run.incomplete_published`. E0 changes no model input and no gate measure, because an
incomplete publication isn't counted (§2.6; ADR 0041:229-231). On kept builds it would have
published in 3 of 20 runs: Q1b loan-renewal 2 of 6 (`RetryLimitExhausted` at the records
request, the class D4.1 later targeted) and the D4.1 set's loan-renewal 1 of 3
(`WorkflowTokenBudgetExceeded` in review).

Accepted on 26 October; mechanism accepted on 27 October. A Specify run that fails because model
work couldn't be completed, or ends `blocked`, publishes only its validated content as an
incomplete specification, marked in `spec.md` and `reference-context.md` and logged as
`run.incomplete_published`, while keeping its outcome. Mechanism: a YAML-declared
`failure-output` subgraph run by the engine through the runner in a model-free failure-output
mode; eligibility as ADR 0041 Decision 1; no final requirement IDs; `workflow/v2`. The failed
view has no `spec.md` reader slot (ADR 0041 Decision 8.4). To resume:
- ADR 0041 Decisions 1–8 (7 and 8 approved 29 October 2026), in slices S1 definition and
  compilation (`workflow/v2`), S2 terminals, event and ledger, S3 runner mode and engine
  binding, S4 Specify content, S5 wiring and tests; about the size of ADR 0039.
- Decision 7.1 keeps an `invalid` run `invalid` and lets it publish (0041:156-159). The shipped
  measures reject a marker on any run that isn't `failed` or `blocked`
  (`test/harness/e2e/measures.zig:132`, test `:522-525`; design/harness/e2e.md:723-725), and ADR
  0041:116 and :236, design.md:208 and :1163, F0100:1183 and the `contracts.zig:224` doc comment
  still say the run ends `failed` or `blocked`. Align them with Decision 7.1.
- The v11 `incomplete_publication` member (the artifacts the run wrote; its step, diagnostic
  and outcome are the report's own `terminal_step`, `diagnostic` and `workflow_outcome`) exists
  and stays null (`test/harness/e2e/contracts.zig:224-227`), so E0 adds no report version. Add a
  test that a pre-E0 v11 report still decodes.
- ADR 0041's tests (:234-255). Every scenario that asserts an eligible failure after the
  snapshot publishes nothing flips. That includes the matrix-wide check
  (`test/integration/workflow_tests.zig:3056`) and the two required-runaway cases (`:2611-2616`;
  `test/harness/integration/tests.zig:1939-1956`).
- DE6 is implemented. Register `run.incomplete_published` through `adrRequired`
  (`src/domain/log_event_registry.zig:103-107`) and add it to the test at `:164-170`.

The amendment notes of ADRs 0009, 0011, 0017, 0023, 0037 and 0039 (0039:31-33 and :112-114)
still state ADR 0041's effect without the hold, while design.md, the contracts and the features
carry it; aligning them is a policy edit. If the user withdraws ADR 0041, this entry moves to
Z_FIX06, and v11's `incomplete_publication` and the measures' `incomplete` value become dead
code whose removal needs a report version (§2.13).

### E1. Engine-owned model request (A1, ADR 0030 slice 4)

Slices 1–3 are done ([Z_FIX05](Z_FIX05.md#a1-settled-choices-and-slices-13)). Open, not
started: the `request-model` step itself, replacing the 18-step `model-request-body`
(`spec.workflow.yaml:1032-1094`) and its five wrappers (`:940-1031`), with ADR 0030's offline
acceptance and the shared contract-variant mechanism ADR 0033 reuses (ADR 0030:261-310,
515-616).
- It folds ADR 0039's re-send (`check-model-runaway`, `build-model-runaway-resend` and the
  compiler route rule `validateRunawayRoutes`,
  `src/domain/workflow_model_request_lifecycle.zig:92`) into the `request-model` stages and
  retires that rule.
- ADR 0040's review closure and ADR 0042's required-items constraint carry over unchanged.
  Retake the slice 1 freeze, with T5's request projection, on the commit before it lands (Q3's
  requests match `d41-2026-10-30`). If Q2 is ever retried under D2.1 (a), whose new request
  binding is a new `request-model` parameter, E1 follows it.
- Settle the slice 1 review points: trace the advisory production run
  (`test/harness/integration/tests.zig`: budget exhaustion, output limits, the advisory
  protocol stop); make `extract/content` and `extract/content-request`
  (`spec.workflow.yaml:326-338`) one step; port each runner-level lifecycle test in
  `src/model_request_workflow_test.zig` one for one, with a mapping table and a reason for any
  dropped assertion (user decision of 23 October, option b: they are the baseline for pre-call
  termination, cancellation and authorization failure).
- Report `propagate-advisory-request-failure`'s remaining users and ask its keep-or-remove
  decision with E1 (ADR 0030:625-628).
- Not expected to change model calls, tokens or reliability (ADR 0030:512-513), so it claims
  nothing for the ADR 0034 gate. Whether the engine also takes over release is open (R-A1).
- If it advances `model-request-debug` (ADR 0030:373-376), Q9's capture replays run first. ADR
  0030 removes operations, bindings and registry entries, not data keys (:411-437), so the
  earlier "it retires request-lifecycle data keys" is unsupported. Every retained v11 report
  except Q4's three `harness_error` runs carries request-lifecycle `DataKey`s
  (`test/harness/e2e/contracts.zig:135-141`); if E1 removes or renames one, it lands under
  §2.13.

### E2. Stage actions (A2, ADR 0031) and identical sibling steps (W5)

Not started: `prepare-toolchain` is still nine single-step actions
(`design/workflows/spec.workflow.yaml:187-216`). Convert it first and record ADR 0031's measures
(`0031-stage-actions.md:364-366`) before converting another stage. Which stage follows is open
(:368-370); one candidate is the Specify invocation operation, which ADR 0032 makes a stage
action (`0032-engine-routines.md:181-187`). No quality change is claimed. ADR 0034 recommends
running the gate after the ADR 0030–0033 conversions land and leaves that to the user
(`0034-spec-quality-gate.md:100-104`). **Decision DE2:** confirm ADR 0031's derived choices
1–3 and 6–8 (:270-299; ADRs 0032 and 0033 settled 4 and 5), including whether choice 7's
offline evidence replaces the live run per case in §2.11 and §5.

**W5: recommended closed, record only** (review, 31 October 2026; the user decides). Both pairs
remain (`source-gaps`/`candidate-gaps`, `spec.workflow.yaml:165-178`;
`finish-native`/`finish-model`, :353-358). Each pair already calls one shared subgraph, so only
the call sites repeat. No planned conversion absorbs them: their subgraphs publish, or collect
and release a retained request, and those stay YAML steps (ADR 0031:131-144; ADR 0030:341-357).
A merged step must pass the compiler's join check, which requires identical key and composition
state on every incoming edge (`src/domain/workflow_data_flow.zig:69-70`). By reading (not
compiled), neither merged step would pass: `specification_generation_session` exists only on
the `candidate-gaps` path, and the open request part differs at `finish-native` and
`finish-model` (`src/domain/workflow_json_composition.zig:12-20`). If the user accepts closing
W5, this paragraph moves to Z_FIX06 and the heading stays.

### E3. Engine routines (A3, ADR 0032)

Not started: no `src/application/*_routine.zig` exists, and ADR 0032's figures still hold: ten
child-binding files of 515 lines, and 233 `anyopaque` lines in `src/application/`
(`0032-engine-routines.md:65-68`). Convert startup (bootstrap, provider config, provider
bootstrap) first and measure it (:144-151, :307-308). Feature logging converts only once ADR
0032's preconditions hold (:152-172). Two don't yet:
- No test covers cancellation under a log lock. An emergency-line count is asserted at
  `src/feature_log_runtime_test.zig:808`.
- The policy-transition coordinator waits for E6's §14.10 decision.

**Decision DE3:** confirm ADR 0032's derived choices 1–8 (:224-243), including whether offline
evidence (:204-217) replaces the live run per case in §2.11 and §5. DE2 and DE3 share ADR 0030's
form and the validated wrapper types, so they can be asked together. Slot: "after E1" (ADR
order) stands; the review recommends after E2's first measure instead (§3).

### E4. Generic repair operations (W3, ADR 0033)

After E1, E2's measure (ADR 0033:231-234), Q9's capture replays (ADR 0033:260) and D9.1, all
Specify owners in one change on offline equivalence evidence. The 29 per-owner operations (10
authorize, 6 input, 6 parse, 7 merge) and 13 owners of ADR 0033:85-101 still match
`spec.workflow.yaml`. Since Q3, seven of those operations read `.packet_guidance`
(specification-unit authorize, which composes the repair tails, and input;
specification-support authorize, input and merge; reconciliation and source-omission input);
their variants keep those reads. No Q2 bindings exist (Q2 not kept). It deletes the data keys
that only passed values between per-owner operations (ADR 0033:290-291); retained reports carry
repair keys (`reference_reconciliation_repair` in five, `specification_repair_authorization` in
two), so it lands under §2.13. **Decision DE4:** confirm ADR 0033's derived choices 2–8 (ADR
0033:272-283): the 13-owner list, the `owner` check, "compiled operation" meaning the step
instance, the §22.1 reading, advisory stops outside the four operations, one Specify-only
conversion, offline evidence. **Recommended** (review; not decided): drop D9.1 as a
prerequisite; if adopted later, it amends the reconciliation owners as they then stand.

### E5. Rejections say why (A4)

Give the payload-free `.authority` rejection a closed reason
(`src/domain/workflow_execution.zig:56`, printed as `failed` at `:74`; produced on 139 lines in
`workflow_pipeline_runner.zig` and 8 in `workflow_model_invocation.zig`) and split
`error.OperationExecutionFailed` (176 lines in non-test `src/application/`) into specific causes
at their owners, keeping typed outcomes and terminal precedence (under §2.13; no strictly
decoded member of a retained report carries either today). Closed reasons at sites E1–E4 rewrite
land with that conversion (most `.authority` sites are request-lifecycle checks E1 replaces), as
does the simultaneous-failure gap, which sits in the request lifecycle E1 rewrites; the
evaluator gap and sites no conversion touches land in any gap. ADR 0031 specifies naming the
failing step inside a stage (accepted, not implemented; 0031:196-203). Nothing has landed and
the class has grown: the runner's `.rejected = .authority` lines went from 119 to 135, and
`error.OperationExecutionFailed` lines from 147 to 176 (`b2f10a3`, 17 October, to HEAD). No
retained run has ended on `.authority`; the only `OperationExecutionFailed` terminals were Q4's
three harness stops, where the harness reused the engine's error name for its own stop (E6,
fixed). Failure-evidence gaps:

| Gap | Required change |
| --- | --- |
| Evaluator partial bodies disappear (harness-only, standalone `evaluate-spec`; matters for H3's judge qualification) | `Observation` has no completeness ([provider.zig](../test/harness/provider.zig):27-34); Bedrock passes no `response_body_on_error` and drops a failure body ([bedrock.zig](../test/harness/bedrock.zig):60-65, :79-86); OpenAI HTTP frees a partial body on a read error, timeout or cancellation ([http.zig](../test/harness/http.zig):30-45, :95-104); the trace saves only the error name ([evaluation_trace.zig](../test/harness/evaluation_trace.zig):34-38). Carry the transport's `ResponseBody` bytes and completeness (`src/adapters/provider/model_http_transport.zig:24-35`) through the observation, with redaction and adapter-to-trace fault tests |
| A later failure replaces the earlier cause | Accounting replaces an invocation cause ([workflow_model_invocation.zig](../src/application/workflow_model_invocation.zig):15-22), then a logging or capture failure replaces both ([workflow_pipeline_runner.zig](../src/application/workflow_pipeline_runner.zig):472-494); only capture keeps a later logging failure (`src/domain/model_capture_failure.zig:32`). Keep the first cause beside the one that ends the run, preserving terminal precedence and allocation-failure handling |

The former third row, "the loss-localization call origin isn't retained", was stale: both
associations are retained (the finding call in `origins`, the localization call in the
finding's `preservation`; `specification_support.zig:565`, `:570`, `:581`, `:800`),
invalid-loss diagnostics name the localization call, and invalid loss is never repaired (R6).
Its residual is E6's support-findings origin item. The two limits that followed the table are
stated in the harness contract (design/harness/e2e.md:523-525, :572-577;
`test/harness/e2e/progress.zig:1-2`).

### E6. Logging and visibility gaps

- Cancellation during segment reads and under the log lock becomes a logging failure, so the
  run ends `blocked`, not `cancelled` (`src/domain/workflow_execution.zig:80`). The sink's error
  set has no cancellation (`src/domain/operation_error.zig:17-25`). Recovery maps a failed
  segment listing to `SinkFailure` and other read failures to `CorruptStream`
  (`src/adapters/filesystem/feature_log_recovery.zig:29`, `:34`, `:51-61`), and the prune maps
  `Cancelled` to `SinkFailure` (`feature_log_historical_stream.zig:95-97`). It needs the user's
  decision first: ADR 0032 lists it under "Not decided here" and says reporting cancellation as
  cancellation changes the shared sink contract (`0032-engine-routines.md:312-313`; tracked gap
  at :128-130).
- The lock action reports every acquire failure as `LOG_LOCK_TIMEOUT`
  (`src/actions/log/acquire_feature_log_stream_lock.zig:18`). F0002 sets one attempt within
  2,000 ms (`design/features/F0002-LogService.md:564`; `stream_lock_attempt_count` is 1,
  `src/domain/feature_log_limits.zig:14`), but the adapter's single `tryLock` never waits for the
  deadline, which is only equality-checked, and `InvalidBinding` and `SinkFailure` aren't
  timeouts, though the closed code set has `LOG_SINK_FAILURE` (F0002:575;
  `src/adapters/filesystem/feature_log_lock.zig:9-27`).
- Prior-run crash finalization (§14.10) is blocked on a persisted bootstrap authority that
  doesn't exist (`design/contracts/14-orchestration.md:327-331`; ADR 0032 defers its historical
  authority, 0032:312-315), so a crashed run's logs are kept whole. E3's feature-logging
  conversion waits on this decision.
- `design/contracts/26-security.md:196` and `design/features/F0002-LogService.md:561` name a
  `redaction/default-v1` policy, but no code or record carries the ID; redaction is
  `src/domain/model_log_redaction.zig`. Decide whether a record carries the ID or both documents
  drop it.
- **Support-findings diagnostic origin** (formerly E5's third gap row). The observer projection
  gives a support-findings diagnostic one origin, its collection's first review call
  (`SupportFindings.from`, `src/domain/candidate_validation_diagnostic.zig:77-79`;
  `specification_support.zig:675`): call 5 in `2026-10-31T02-53-14Z-da42…`, where call 10
  found the omission and call 11 localized it, both kept in the evidence. `Diagnostic.origin()`
  also feeds the engine's validation log event (`src/application/workflow_pipeline_runner.zig:633`)
  and the CLI's failure output (`src/main.zig:45`), and design/harness/e2e.md:568-570 defines the
  "review origin", so which call counts is a contract question. Engine log output only; no model
  input.
- **Producerless rejection reported as a harness error: implemented 31 October 2026**; record
  in [Z_FIX06](Z_FIX06.md#e6-producerless-rejection-reported-as-a-harness-error). Still open:
  - contract 27 (27-observability.md:59-62) names only coverage as an assembled-candidate
    example, and no design text states "a missing value has no producer"; adding it is a design
    edit awaiting the user's approval;
  - `observation.capture`'s candidate arm has no direct test (it needs a runner);
  - **Decision** (optional; the fix doesn't need it): a first-generation omission could instead
    name its chunk's classification producer, as support's `missing_finding` names its response
    (`specification_support.zig:712`); that changes the validator's producer rule.
- **DE6** (ADR-required events at every threshold) is done; record in
  [Z_FIX06](Z_FIX06.md#de6-adr-required-events-at-every-log-threshold).

### E7. Clarification answer recovery (R2, ADR 0025)

Not started; none of the §13 authentication chain exists in `src/` (no `AuthenticationPort`,
`AuthenticateActorAction` or actor-evidence registry). Fresh answers can't complete the
registered recovery path (rechecked 31 October 2026): refresh rejects new nonempty submissions
with `AuthenticationRequired` (`clarification_refresh.zig:65`); provenance rejects nonempty
response-ID sets (`specification_provenance.zig:88`, `specification_support_evidence.zig:175`);
form validation parses answers without authenticating them and returns one
`InvalidClarificationInput` for any invalid form (`validate_clarification_forms.zig:17-61`); the
resolved-needs action builds empty needs (`build_resolved_clarification_needs.zig:8`); generation
doesn't consume accepted answers (source binding selects no response IDs,
`specification_source_binding.zig:95`, `:147`); passive literal origins are source-only
(`passive_literals.zig:16`). Complete the
[§17.4 lifecycle](../design/contracts/17-specify.md#174-specification-clarification-behavior)
under [ADR 0025](../design/decisions/0025-clarification-answer-authentication.md): the
account that runs the engine is the actor; one invalid closed form stops the run with a
typed reason per form; evidence in the shared actor-evidence registry; Specify only. Keep
ADR 0021's optional pre-generation source check; persistent semantic identity across edits needs
an explicit continuity contract, not line-derived IDs. It changes model input only when accepted
answers exist, which no development-case run produces (the harness never answers forms): every
request kind the scripted driver already produces stays byte-identical. A development case can
still pause for clarification (Q4's `2026-10-31T02-52-18Z` ended `needs_user`). Live validation
needs a clarification-expected case run twice, with the forms answered between runs (ADR
0025:176-177), chosen by the user and never a reserved feature; neither the case nor a two-run
harness flow exists (the harness takes only `--case`). ADR 0025:174-175 advances
specification-state and the clarification state version, which v11 `report.json` doesn't carry,
so §2.13 likely isn't triggered (unverified for the embedded capture). Last, after E1–E4.

### E8. Typed schema-definition identities

Domain code names result-schema definitions by raw strings. Two sites branch on a second copy of
a name, so a rename that misses them silently takes the other branch:
`src/domain/specification_review_retention.zig:80` and
`src/domain/specification_support_repair.zig:152`. The rest select a definition by name and fail
only when the request is prepared (`src/domain/model_request_handoff.zig:351-352`):
`specification_support.zig:218`, `:404`, `:506`, `:514`; `specification_support_repair.zig:143-144`;
`principle_assessment.zig:119`; `specification_session.zig:252-257`;
`specification_repair.zig:265-270`; `reference_model_input.zig:195`;
`reference_reconciliation_stage.zig:139-143` (checked at `:87`);
`reference_reconciliation_repair.zig:347-353`, `:787-793`; `reference_extraction_repair.zig:56`,
`:181`; `reference_extraction_text_repair.zig:65`. Bind them as closed IDs checked when the
schema loads, so a rename fails at load. Test fixtures also branch on names
(`src/test_fixtures/spec_generation_driver.zig:255`, `:406`, `:420`, `:934-938`;
`spec_generation_responses.zig:533`, `:983`, `:998`), which §2.6's brittleness count would
include. No model-input change.

### E9. Superseded exact-handle correction

New 31 October 2026 (review; formerly an observation in Q3's record). `ValueChoices.correction`'s
`unknown_exact` arm (`specification_provenance.zig:177-180`, added in `bfd7939`) corrects a
model-authored exact handle. Models can't author one since `dfae959` (17 October; ADR
0020:26-28; `typed_text.zig:17-19`), and ADR 0020:233 calls that repair case superseded.
Recognised copies are always permitted. `rejected_exact` (`typed_text.zig:144`) is otherwise set
only for a canonical segment with an invalid claim, which canonical revalidation turns into
`InvalidSpecificationUnit` (`specification_session.zig:558-561`), so it never reaches a
correction. `ValueChoices.permits` (`:167-169`) has no caller. Delete the arm, `permits`, the
member, its assignments (`typed_text.zig:245`, `specification_provenance.zig:426-433`) and the
assertions that read it (`packet_guidance_test.zig:206-207`, `typed_text_test.zig:32`,
`specification_generation_test.zig:8838`); the `unknown_exact` rejection stays. No request
changes: neither the `d41-2026-10-30` freeze nor retained evidence carries a value-choice
correction or `rejected_exact`. The dead-code analysis is by reading, not by running tests.
`typed_text.Issue` is serialized in `spec-e2e-report/v11` (`composition_error`,
`last_protocol_rejection`, `candidate_error`); the only retained report carrying one is Q4's
failed `2026-10-31T03-01-37Z-7c6a…`, so §2.13 needs only the user's record that it stays
unadjudicated. It lands with E1, E4 or E5, so it spends no live runs of its own.

## 6. Test track (T)

### T1. Repeated-runaway debug capture (B9)

Done 28 October 2026, committed in `5bb7f17`; record in
[Z_FIX06](Z_FIX06.md#t1-repeated-runaway-debug-capture-b9).

### T2. Test decoupling

Q3 removed the `specification_generation_test.zig` lines that copied the guidance it moved, and
`packet_guidance_test.zig` checks each entry by its wire path. Remaining, recounted 31 October
2026 (test literals of three or more words found in a model-facing owner, plus absence checks on
model-facing text; a lower bound): at least 37 copy lines and at least 5 absence checks, which
with the `protocol.prompt.md` checks make about 46 lines in 8 files. The audit's "about 45"
stands; its "11 files" is unverified.
- Copy lines: `model_request_workflow_test.zig` 11, `model_payload_schema_test.zig` 9 (including
  `:860`), `reference_model_input_test.zig` 6 (including `:91`, a full copy of
  `reference_reconciliation_diagnostic.zig:102`), `test_fixtures/spec_generation_driver.zig` 6
  (including `:285`), `model_text_field_test.zig` 2, `reference_reconciliation_test.zig` 2,
  `specification_generation_test.zig:10414` (added by Q3). Owners: `model_protocol_retry.zig:55`,
  `:78`; `model_schema_diagnostic.zig:21-35`; `strict_json.zig:25-28`;
  `reference_reconciliation_diagnostic.zig:96-132` (11 of the lines; it still carries the "native
  code" wording, the Q4 retry); `text_field_policy.zig:91-106`; `specification_repair.zig:130`;
  `principle.prompt.md`. Compare with the owning constant, function or resource, checked once in
  the wire.
- Remove `model_payload_schema_test.zig:362-367`'s phrase checks on `protocol.prompt.md`, or
  compare with the resource; likewise the absence checks at `model_text_field_test.zig:177`,
  `model_request_workflow_test.zig:4531` and `specification_generation_test.zig:7207` and
  `:7377`. `test/integration/insertion_presentation_tests.zig:65` stays while the
  insertion-presentation panel stays, and goes with it.
- Rename after the rule they test: tests `specification_generation_test.zig:3612` (R31), `:8438`
  (R42), `:8603`, `:8660` (FIX002), `model_envelope_test.zig:381` (R36); fixture headers
  `test_fixtures/summary_protocol_sequence.zig:1` (R35) and `global_protocol_sequence.zig:1`
  (R36); the `measurement_prefix` dumps at `test/integration/workflow_tests.zig:1668-1750` (r35,
  r36, r37, r40, r41, r42, r43, fix002) with their `build/test_run_inputs.zig:22`, `:33-40`
  entries; and comments naming R21, R22, R26 and R46.
- `test/harness/attribution/preparation.zig:191-198` edits English only on the superseded
  insertion-presentation panel, which never ran (`test/calibration/insertion-presentation/README.md:3-10`);
  its inputs are hash-pinned, and `insertion_presentation_tests.zig:63-66` checks the edit
  applied. One substitution target (`preparation.zig:195`) no longer appears in any production
  source; whether that check covers it is unverified. **Decision** for the user: delete the panel
  with its `attribution-replay` tooling, or keep it as historical evidence (B3 kept it).
- The scripted "recovers" scenarios need no change: the testing contract scopes them as
  enforcement tests, not live reliability (28-testing.md:542-543), and no test name or harness
  doc presents one as model evidence.

Offline, no model-input change; any gap.

### T3. Coverage gaps (B5, B7)

Offline, no model-input change; any gap (its slot beside Q2 lapsed with Q2's revert).
- No offline integration scenario reaches a records-batch native delete (`duplicate_record` or
  ADR 0035 `restatement`, `specification_repair.zig:82-83`); the scripted story always differs
  from every record (`test_fixtures/spec_generation_responses.zig:1085-1086`). Unit coverage only
  (`specification_generation_test.zig:1722`, `:2614`, `:2711`); Q1b's one live repair took this
  path.
- The no-feature-claim reason's text-repair route (`spec.workflow.yaml:365-386`) has unit
  coverage only (`reference_extraction_test.zig:597`, `:628`); no request in the
  `d41-2026-10-30` projection targets the reason.
- Since ADR 0036, the retained GPT-OSS compatibility exchange (prefix normalization, empty
  server-tool usage) is assessed `incompatible`
  (`test/integration/provider_compatibility_tests.zig:261-262`, `:305-309`); the only
  `compatible` scenario is the bare synthetic `{"kind":"claims","claims":[]}` (`:34`,
  `:296-303`). Current GPT-OSS responses usually need the §22.6 normalization (39 of 40 replays,
  Q2), so the diagnostic's normal path has no compatible-assessment coverage.

### T4. Architecture rules and replay (A5)

When E1–E4 replace the architecture tests that pin the files they remove (ADR 0031:228-230, ADR
0032:200-202), write the replacements as import-graph and contract-shape rules (ADR 0030:609-613,
0031:346-362, 0032:293-305, 0033:337-340) rather than per-file pins. On 31 October 2026, 68 of
the 78 tests in `src/architecture_test.zig` pin named files (FIX05: 69 of 79). Prefer replaying
retained real captures over extending the scripted response builder
(`src/test_fixtures/spec_generation_responses.zig`).

### T5. Measures and request projections (before Q1b)

**Done except the brittleness counts** (implemented 28–29 October 2026, committed in `5bb7f17`).
The (a)–(e) specification, its status record, the `spec-e2e-report/v11` decision, DT5 and the
freezes are in [Z_FIX06](Z_FIX06.md#t5-measures-and-request-projections-before-q1b).
Definitions: [e2e.md](../design/harness/e2e.md) "Run measures". The request-projection reference
is `evaluations/request-projection/d41-2026-10-30/` (Q3 matches it); `q2-2026-10-31`,
`q4-2026-10-31` and `q6-2026-10-30` are freezes of reverted builds.

**Open: brittleness counts (§2.6).** Never taken, at Q1b or after any later phase, so no phase
can yet report "brittleness reduced". `zig build code-heuristics` measures only file and
function size, decision tokens and duplicate bodies (`build/code_heuristics/model.zig`).
Computable there from source structure, exact matches only, never word lists: model-facing text
copied into tests (T2's recount shows the method), raw-string branches on schema names (E8),
instructions with more than one exact site, and repair steps that bind no step guidance (from
the workflow definition). "Guidance sentences without repeated-run evidence" is a record, not a
code count (Q5 lists them). "Model- or case-specific branches" and "model-facing English in Zig
outside its single owner" need a definition first. The user reviews the brittleness definitions
before they are taken (the 29 October approval covered "Run measures" only).

While ADR 0041 is on hold, v11's `incomplete_publication` (`test/harness/e2e/contracts.zig:224-227`)
and the measures' `incomplete` publication have no producer; removing them needs a report
version (§2.13). design/harness/e2e.md:723-724 still says the incomplete publication "is measured
once ADR 0041 writes its marker (FIX06 E0)".

## 7. Human and decision track (H)

### H1. Adjudication (R8)

Only a human `human-spec-adjudication/v2` record, applied with `zig build adjudicate-spec`,
decides acceptance. No run has been adjudicated. A build adjudicates only reports its contract
decodes (§2.13; `test/harness/human_adjudication.zig:72`).
- **v11, 29–31 October (38 runs).** Decodable on the current build, by inspection: each run's
  `build-inputs.json` shows the report contract (`test/harness/e2e/contracts.zig`),
  `human_adjudication.zig` and the candidate-diagnostic types byte-identical to HEAD for the
  Q1b, D4.1, Q6 and Q3 builds (Q4's differs only in `model_schema_diagnostic.zig`'s explanation
  refactor); report-graph changes since `5bb7f17` are additions the report doesn't serialize,
  and the 34 data keys the reports carry all exist. Only running `adjudicate-spec` would prove
  it. 25 native publications, each with its adjudication capture: Q1b 10, D4.1 5 and Q3 2 on
  kept builds; Q6 5 and Q4 3 on reverted ones (Q4's `02-52-18Z` published a clarification and
  has no capture). All record `modified: true`. Any later report member or closed-member removal
  (E1, E4, E5, E9, a rule withdrawal) strands them (§2.13).
- **v10, 26–27 October (16 runs).** Only a v10 build (`39a06ea` to `371b55a`) can read them.
  They include the clean `39a06ea` pair, the only retained runs on an unmodified committed
  build. The three 27 October loan-renewal reports (05:06 and 09:40 published, 08:31 failed) also
  carry Q1a's removed `weakened_obligation`, which only `d74fc1f` has; they stay unadjudicated
  unless the user decides otherwise.
- **v9, 24–25 October.** No run directory remains under `zig-out/e2e-spec/`; only their
  evaluations do. They stay unadjudicated (decided 27 October).

Needed for the ADR 0034 gate and for §2.6's adjudicated measures of any set; none has been
adjudicated (Q1b, D4.1, Q6 and Q4 were decided on advisory evidence).

### H2. Review-label confirmation (B2)

The scheme is defined (`b2-review-label/v2`, `.claude/skills/evaluate-e2e/SKILL.md:235-266`;
decided 28 October 2026) and Q1b used it, unevenly: its files sit in three places under
`evaluations/e2e/2026-10-29T*/` (`labels.json`, `b2-review-labels/`, `b2-review-accuracy/`),
none at the skill's `evaluations/b2-review-accuracy/<set>/<case>/`; per-type metrics take three
shapes; and a `supported` verdict on a defective subject is `wrong_type`, a null-prediction
`missed_defect`, or both (§10). First settle one convention in the skill and relabel Q1b to it
(advisory work under `evaluations/`), updating §10's label-location sentence to match. A human
then confirms or corrects Q1b's labels, the review comparison point, so they become the frozen
labels finding-type accuracy needs
([e2e.md](../design/harness/e2e.md#reliability-assessment)). The `b2-review-label/v1` sets under
`evaluations/b2-review-accuracy/` (26–27 October, pre-Q1a builds) are history. No run since Q1b
is labelled. Needed before Q10b, and before Q10c only if D10.3 changes model input.

### H3. Calibration panels (R8)

The [Hello World panel](../test/integration/fixtures/wf-001-hello-world/node-vitest/calibration/REVIEW.md)
(nine specimens) and the
[loan-renewal panel](../test/integration/fixtures/wf-002-loan-renewal/calibration/REVIEW.md)
(fifteen) have proposed labels only; their `human-review.json` and `qualification.json` records
are `pending`, and the panel and rubric hashes they bind still match the current files. They
qualify only the standalone supplied-spec evaluator, and that qualification is diagnostic
([acceptance.md](../design/harness/acceptance.md#review-and-qualify-the-grader)). E2E makes no
judge call, so neither the ADR 0034 gate (H1), FIX06's sets nor the evaluation protocol's
baseline freeze needs them. Confirmed labels would also give `/evaluate-e2e --panel` a human
key. Records land in a gap (§2.3).

### H4. Experiment stops, qualified scope and the formal baseline (B4, B5)

**Decision**, needed only before freezing the evaluation protocol's Phase 2 baseline; neither
FIX06's sets (§2.12) nor the ADR 0034 gate need it. The protocol stops at 1,000 sends or
2,000,000 tokens ([README](../test/calibration/semantic-simplicity/README.md):189-190). Q1b's
worst run (27 sends, 122,002 tokens) fits about 16 workflows in that, but the Phase 2 baseline
alone is 72 workloads (README:224-225; the earlier "144 development workloads" is the A/C
comparison's, :106), and the example plan's three phases come to 360–504
(`test/harness/baseline/feasibility.zig:435-436`). The latest feasibility report, built from one
15 October run, is `insufficient`, with both projections over the stops
(`zig-out/baseline/2026-10-15T22-38-08Z-4ae4…/budget-feasibility.json`). Options: reduce review
cost through its owner (Q10b), or narrow the qualified scope; any change to the stops is the
user's own call (§9). Measure the prompt, schema and evidence share of each call before trimming
anything; add no local size ceilings (ADR 0011). If the frozen baseline meets the protocol's
adequacy targets, retain it and stop the redesign.

### H5. Model choice (R7)

The user decides when to change or compare models. All live evidence comes from
GPT-OSS-20B. Only if the user selects Claude Haiku 5.5: measure its maximum-output time to
replace the interim 180,000 ms `requestTimeoutMs`, and settle Claude's response mode (native
schema or prompt-only).

## 8. Research and backlog (R)

### R1. Group-level provenance precision

Non-entity records name their claims within their batch's one group (ADR 0038 Decision 1;
`specification_generation.zig:144-149`); entities and the brief and story fields still select
whole groups (`specification_generation.zig:136-141`, `:166-169`;
`specification_provenance.zig:558-562`). In 25 of the 26 runs since Q1b, reconciliation formed
one model signal holding every retained quoted claim (exact-text claims get their own signals),
so on both development cases those fields carry every quoted claim as provenance. After Q10b
(which needs H2's labels), and after Q9 or D8.1 if either changes grouping, measure whether
grouping and source review meet the traceability claim (design.md:121) before any binding change
across generation, review, repair, omission insertion, readback and rendering. No second
provenance store, no support inferred from text matching.

### R6. Semantic repair attribution and recovery

Re-scoped under ADR 0023: post-generation findings don't drive content repair. Loss localization
runs only under required review (`specification_support.zig:601-606`), so the loss-evidence and
exact-reference proposals concern pre-generation source-readiness and preservation review; after
Q10b, whose taxonomy routes that review. Remaining proposals, each needing a closed contract:
source-authorized exact-reference repair eligibility (§22 and ADR 0020/0022 amendments; ADR
0033:349-350 leaves it open); narrow correction of invalid loss evidence (today a rejected loss
response ends the workflow `invalid`, `specification_support_workflow.zig:87` and
`spec.workflow.yaml:683-684`, and support repair refuses `invalid_loss`,
`specification_support_repair.zig:94`); verdict reassessment under §22.1, with no voting or
retry-until-positive. Entity-applicability repair can't change the entity decision, and
exact-reference repair can't add an unselected claim because its text matches. No evidence since
Q1b: with `sourcePreservationCheck` off, the development cases reach required review only when
no claim is generation-ready (`specification_provenance.zig:39-45`). Only the reverted Q4 build
did so: five hello-world runs, three with loss calls (1, 3 and 4) and no `invalid_loss`, all
three then stopped by E6's harness defect (fixed 31 October 2026), so their engine outcomes are
unknown. Earlier comparison records are in
[Z_FIX02](Z_FIX02.md#21-r6-follow-up-records-formerly-in-fix01).

### Summary hierarchy and cross-model variation

Closed 31 October 2026 (review; obsolete, record only); record in
[Z_FIX06](Z_FIX06.md#summary-hierarchy-and-cross-model-variation). FIX01 §9.20 recommendations
1–2 are implemented; the prepared comparison can't run; and the development cases exercise
neither the hierarchy nor carry-forward, a known gap they can't measure. A summary change meets
§2's summary-representation, normalization and carry-forward gates; cross-model work is H5's.

### B7 contract-review leftovers

From ADR 0036's contract review (`Z_FIX05.md:3260-3273`). Neither point has an observed outcome
or changes model input; the repeated citation ID is closed (Z_FIX06).
- Prior-state readback checks stored claim text against the text policy only
  (`reference_snapshot.zig:116-117`; ADR 0036:181-183, whose "FIX05 B7" pointer is stale).
  Re-quoting it from its citations needs the Unicode normalizer at readback. No development-case
  run starts from prior state.
- `source_selections.validate` builds a typed `Issue` (`source_selections.zig:12-18`) that both
  production callers discard (`validate_reference_claims.zig:32-34`,
  `source_omission_comparison.zig:132-133`); only `reference_evidence_test.zig:88-99` reads it.
  `validate-reference-selections` validates token classifications only
  (`validate_reference_selections.zig:7-11`, `spec.workflow.yaml:403`) and produces
  `validated_reference_selections` (`pipeline.zig:127`), which no retained report carries. Delete
  the unused detail and name the step and key for what they do (engine hygiene, §2.11 proof).
  The rename touches `spec.workflow.yaml` (installed by both E2E cases), F0100-SpecWorkflow.md,
  `test/integration/workflow_tests.zig` and nine `src` files, so it lands in a gap and includes a
  design-text edit.

### Wider scope retained

- **Retained memory and scale:** growing review sets, retained bytes, allocations, validation
  and teardown time, cancellation and OOM, dependent rebuilding. Unmeasured; none of the 54
  retained runs failed on memory.
- **Harness acceptance (former H-012, H-013, H-017; ticket text in git at `8ed40ba`):**
  publication process-interruption evidence; live negative cases as separate fixtures (malformed
  generation, real missing or conflicting authority, cancellation); rerun replacement through an
  unrelated registered workflow (H-017; no test found, unverified); an unchanged prior `spec.md`
  must not be labelled new after a blocked rerun. Recheck, then close or keep: shorter
  replacements (`file_access.zig:136`), concurrent closes (`workflow_tests.zig:3499`),
  unsubmitted drafts and stable subject IDs (`clarification_inputs_test.zig:46`); compiler
  rejection of skipped gates and undeclared resources (`workflow_definition_test.zig:430`,
  `:822`; `model_request_workflow_test.zig:134`); packaged execution without a `design/`
  fallback (`test/packaging/smoke.zig:597-605`); production Specify feature-log integration
  (live runs write the feature event and prompt logs that `e2e-measures` reads, while
  F0002-LogService.md:808-809 and F0100-SpecWorkflow.md:1565-1566 still call it open). None is on
  the ADR 0034 gate path. The evaluator responsibility transfer, H-017's live grading milestone,
  E2E judge failure, the live evaluator demonstration and the provider-compatibility diagnostic
  are closed ([Z_FIX06](Z_FIX06.md#wider-scope-retained-closed-parts)); the live clarification
  path is E7's.
- **Provider docs:** ADR 0028 links an F0009 feature document that doesn't exist
  (`0028-anthropic-messages-provider.md:35`, `:95`, `:151`), and its "Live use" (`:177`) says the
  cost policy permits only GPT-OSS-20B, while `test/harness/model_cost_policy.zig:17-25` also
  lists Claude Haiku 5.5 for generation; `test/harness/e2e/cli.zig:26`'s help lists only the two
  Bedrock tuples. Contract §12.3.2 now exists (`12-model-boundary.md:278`).

### R-A1. Engine-owned release

Whether the engine should also take over release, which changes ADR 0012's retained-request
handoff and needs the compiler to derive each request's lifetime (ADR 0030:620-622). Decide
after E1.

## 9. Guardrails

AGENTS.md ("Model output, prompts and evidence", "Anti-overfitting rule") and §2 govern every
phase: no local fixes, one change set per measured build, nothing under the build-provenance
roots changing while a set runs. The user's standing constraints beyond them:
- No model change or comparison (H5).
- No caps that discard output (§2.10), and no larger token budget: a budget failure is fixed at
  its cause, such as review cost or runaways (user, 30 October 2026). No local token ceilings,
  no truncated required evidence, no policy discarded by keyword, and no claim that a larger
  budget fixes reliability.
- Never batch or group source-review subjects; they keep ADR 0023's whole-unit assignments
  (user, 30 October 2026).
- Measures and replays use the owning steps (`zig build e2e-measures`, `e2e-call`), never
  one-off scripts, loops or new tracking files (user, 29 October 2026).
- Don't narrow the entity-name exception without a decision (B6).

## 10. Progress

Steps 1–11 (done, closed or reverted) are recorded in
[Z_FIX06 §7](Z_FIX06.md#7-progress-rows-111-and-the-cost-estimate), with E6's report fix (31
October 2026). Step 7's D2.3 is implemented, uncommitted (31 October 2026, ADR 0046; Q2b).
Its two 3 + 3 sets published 12 of 12, with the correction never firing; keeping it awaits the user. Steps 7 and 11–20 are otherwise open (§3); E1–E5, E7–E9,
T2–T4 and T5's brittleness counts are proposed or accepted, not started; E0 is on hold;
E6's other items are open.

### Q1b baseline (29 October 2026)

The comparison point (§2.9). Six runs per case on `371b55a` plus its working tree (source
`c7684e21…`, `modified: true`; §2.3), whose captured inputs match `5bb7f17` except ADR 0041's
text; runs 1 of each case are the 08:51 and 08:53 runs. Measures:
`evaluations/q1b/measures-set.json`; evaluations and labels: `evaluations/e2e/2026-10-29T*/`.
Advisory evaluations (`/evaluate-e2e`) are not acceptance; no run is adjudicated (H1).
Spreads are minimum / median / maximum over attempted runs unless stated.

| Measure | hello-world | loan-renewal |
| --- | --- | --- |
| Native publication | 6 / 6 | 4 / 6; runs 1 and 6 failed `RetryLimitExhausted` at the records call (`uncovered_member` three times each: a claim named by a functional requirement but by no acceptance criterion or edge case; both corrections returned the same response) |
| Advisory aggregate (published runs) | 82.14 / 89.29 / 96.43; 6 of 6 at or above 80 | 78.57 / 82.14 / 85.71; 3 of 4 at or above 80 (run 5 `threshold_failed`); renewal-eligibility at its minimum in all four |
| Sends | 22 / 23 / 27 | 12 / 25.5 / 27 |
| Actual tokens | 58,282 / 65,119 / 122,002 | 26,347 / 96,736 / 113,908 |
| Review share of tokens (published runs) | 74.6–88.0% (88.0% in the run with three runaways) | 78.4–83.6% |
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
Labels sit in each run's evaluation folder. H2 settles one label location.

**Set cost** (measured). Q1b's twelve runs used 918,713 tokens (hello-world 449,734,
loan-renewal 468,979); the three-per-case D4.1 and Q6 sets 551,488 and 531,119 (no control
runs); Q4's twelve 810,645; Q3's two rule-11 runs 163,267. A replayed repair call costs about
1,000–1,350 tokens (four `e2e-call` reports). Q10a and each engine item need one run per case
(§2.11). The earlier estimate is in Z_FIX06.
