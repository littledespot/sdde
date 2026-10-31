# Z_FIX06 — Completed FIX06 work and dated evidence

Moved from FIX06 on 31 October 2026, after a review of every unimplemented FIX06 item.
[FIX06](FIX06.md) keeps the open work; this file keeps completed implementation, dated live
diagnostics and the full decision records, under their original FIX06 IDs and headings. Each
moved record is reproduced as FIX06 held it on 31 October 2026, followed by a dated note with
the review's corrections (current line references, overtaken statements and evidence found
since).

This record is historical. Its proposals, status statements and checklists grant no approval
and establish no live acceptance. Accepted contracts and ADRs remain the governing authority.
Section references in the moved text (§1–§10, "rule 3", "step 5a") use FIX06's numbering.

## Contents

- [§1 Review records](#1-review-records): the 28 October 2026 review merge and the 31 October
  2026 review of the unimplemented items
- [§2 FIX06 §1 and §3 as written 28–31 October 2026](#2-fix06-1-and-3-as-written-2831-october-2026)
- [§3 Quality phases](#3-quality-phases): [Q1](#q1-remove-the-rejected-patches-and-take-the-clean-baseline)
  (Q1a and Q1b), the [pre-baseline decisions](#pre-baseline-decisions-sequence-step-2),
  [Q2](#q2-repair-requests-carry-their-steps-definitions) (not kept),
  [Q3](#q3-one-owner-per-model-instruction),
  [Q4](#q4-remove-engine-vocabulary-and-schema-stated-rules-from-prompts) (not kept, with
  D4.1's kept correction), [Q6](#q6-scope-the-obligation-instruction) (not kept),
  [D7.1](#d71-exact-value-corrections-state-the-boundary-rule) (closed) and
  [D11.1, D11.2, D11.4 and D11.5](#q11-d111-d112-d114-and-d115)
- [§4 Engine track](#4-engine-track): [DE6](#de6-adr-required-events-at-every-log-threshold)
  and [E6's producerless-rejection report defect](#e6-producerless-rejection-reported-as-a-harness-error)
- [§5 Test track](#5-test-track): [T1](#t1-repeated-runaway-debug-capture-b9) and
  [T5](#t5-measures-and-request-projections-before-q1b) (all but its brittleness counts)
- [§6 Research and backlog](#6-research-and-backlog): the
  [summary hierarchy item](#summary-hierarchy-and-cross-model-variation) (obsolete), the
  [closed parts of "Wider scope retained"](#wider-scope-retained-closed-parts) and
  [B7's repeated citation ID](#b7-contract-review-leftovers-repeated-citation-id)
- [§7 Progress rows 1–11 and the cost estimate](#7-progress-rows-111-and-the-cost-estimate)

## 1. Review records

### 28 October 2026 review merge

FIX06's header recorded: "**Updated:** 28 October 2026 (detailed review merged: 25
adversarially verified findings, 15 high-severity findings checked by hand, the coupling
review and a new order; 119 unverified medium and low findings were not applied and are
kept in `evaluations/fix06-review/2026-10-28/review-merge.json`, Git-ignored analysis)."

### 31 October 2026 review of the unimplemented items

The user's direction of 31 October 2026: "perform a detailed review of all unimplemented items
in fixes/FIX06.md, assess if they are valid or still relevant. update fixes/FIX06.md. … if
items have been implemented in fixes/FIX06.md move them to fixes/Z_FIX06.md". Ten groups of
items were each assessed and then independently verified, read-only (no build, live or
model-calling step); where a verifier corrected an assessor, the verifier's reading was
applied. The review's working files are session analysis, not kept in the repository.
Recommendations it made that need a user decision are recorded in FIX06 as recommendations,
never as decisions. E6's producerless-rejection defect, which the review diagnosed, was fixed
the same day before FIX06 was updated (§4).

## 2. FIX06 §1 and §3 as written 28–31 October 2026

FIX06 rewrote both sections on 31 October 2026. Their earlier text follows, unchanged.

### FIX06 §1 Why, as of 31 October 2026

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

### FIX06 §3 Sequence, as of 31 October 2026

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
| 6 | **Q2** Repair requests carry their step's definitions (one generic owner), with **T3** (built, replayed and reverted 31 October 2026: not kept) | Paired replays decide the target; measurement set guards | D2.1 (decided) |
| 7 | **Q2b** Generic content-loss guard for repairs (deferred 30 October 2026: D2.2 decided no for now; reopen on a harmful repair) | Measurement set | D2.2 (deferred) |
| 8 | **Q3** One owner per model instruction (move only), with **T2** (**done** 31 October 2026) | §2.11 projections byte-identical, one run per case | D3.1 (decided) |
| 9 | **Q6** Scope "preserve obligations" to the fields D6.1 names, with the in-request dedupe (built and measured before Q2 and Q3 on 30 October 2026, then reverted: not kept) | Measurement set | D6.1 (b), decided 30 October |
| 10 | **D7.1** Exact-value corrections state the boundary rule (closed 31 October 2026: no such correction exists; recorded only) | Offline; byte-identical requests | D7.1 (decided: option 1) |
| 11 | **Q4** Remove engine vocabulary and schema-stated rules (hygiene) (built, measured and reverted 31 October 2026: not kept) | Measurement set (guards) | D4.1 |
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
  on guards alone.
- **Granularity on settled prompts.** Q8 follows Q4 and Q5 so its two arms share the final
  extraction prompts.
- **Review after generation settles.** Q10b assesses what generation produces and needs
  H2's labels; Q10a publishes advice only once Q10b has made it more accurate.
- **ADR-level text rules late.** D7.2 needs repeated rendering evidence; D7.3 is offline.
- **Q9 last.** It has the lowest value and the highest risk, its call count depends on Q8,
  and its capture replays must precede E4, which may change the capture format.
- **Engine work in the gaps.** ADR 0034 puts Spec quality first; engine items claim no
  quality change and land between sets, in ADR order, under §2.13.

## 3. Quality phases

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

**Moved 31 October 2026.** Q1b ran on `371b55a` plus the uncommitted step-3 tree (source
`c7684e21…`, `modified: true`) by user decision ("run Q1b on the latest build"), not on a
committed build; its captured sources match `5bb7f17` except ADR 0041's text. All 12 Q1b label
sets are `b2-review-label/v2`. No production code names `weakened_obligation`; the
`/evaluate-e2e` skill's advisory defect vocabulary uses the label
(`.claude/skills/evaluate-e2e/SKILL.md:63`). Q1b's table stays in FIX06 §10 as the comparison
point. Q1a's audit detail (ADR 0044's three harmful firings, the ignored records-prompt line) is
in §2 above, finding 1.

### Pre-baseline decisions (sequence step 2)

Decided 28 October 2026 as recommended; the step's row and progress row are in §2 and §7.
D11.2, D11.4, D11.5 and DE6 were committed in `371b55a` (28 October 2026) and D11.1's docs in
`5bb7f17` (29 October 2026); their records are below. E0's report marker shipped as
`spec-e2e-report/v11`'s `incomplete_publication`, which stays null while E0 is on hold. H2's
label scheme, `b2-review-label/v2`, is used by all 12 Q1b label sets (its confirmation is FIX06
H2). D2.1 (b) was later built in Q2 and not kept.

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

**Built, replayed and reverted 31 October 2026 (user decision: not kept).** D2.1 (b) was
built: a new reconciliation context plus the extraction and generation contexts held each
step's field definitions, step prompts kept their tasks, and every family request and repair
bound its context (user content byte-identical in all 4,406 projected calls). The paired
replay (40 calls, 20 per request, edit files in `evaluations/q2-replay/`): call 6 answered
`retained` 20 times (before: 19, plus 1 harmful `duplicate`); control call 5 answered
`retained` 15 times, `duplicate` of claim 1 once (harmful: drops the greeting) and four
times returned `{"claim_id":2{"kind":"retained"}` (`protocol_invalid`; before: 20 valid
`retained`). Harmful 1/40 → 1/40 and valid 40/40 → 36/40, so the keep rule failed; the
`claim_id` prefix plausibly echoes the context's dispositions-list definition (unmeasured).
Reports: `zig-out/e2e-call/2026-10-31T02-01-48Z-42c8…/` (call 6) and `…T02-02-01Z-250e…/`
(call 5). All Q2 code, resources, tests and docs were reverted; `d41-2026-10-30` stays the
request-projection reference (`q2-2026-10-31` is stale).

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

**Moved 31 October 2026 (closed: not kept).** The line references above predate Q3, which added
five lines near the top of `design/workflows/spec.workflow.yaml`, so every site moved +5: the
`repair-prompt` sites are now `:376`, `:413`, `:610` (request `:606-613`, reached from `:526`
and `:594`), `:816`, `:899` and `:914`, and the support repair's `prompt: {param: prompt}` is at
`:722` (block `:718-723`). 12-model-boundary.md:361-364 is now `:401-403` (and `:408-412`);
contract 22:437-438 is `22-repair.md:442-443`; ADR 0016:200-203 is `:220-223`.
- The Q2 projection, `evaluations/request-projection/q2-2026-10-31/` (2,218 of 4,406 requests
  changed, no user-content difference), is stale; `d41-2026-10-30` stays the reference.
- The four replay counts re-verify from their `report.md` files; all four replay
  `2026-10-27T09-40-42Z-26e5…` calls 5 and 6. `e2e-call --edit` (`ce38bf2`) stays and serves
  later paired replays.
- §3's "Q2's replays on 'the last pre-Q2 build' include D4.1" was inaccurate: the old-request
  replays ran at 09:18Z on 29 October on the Q1b build, before D4.1, which changes no
  reconciliation request.
- The same dispositions insert request lost hello-world's UTC requirement again on 29 October
  20:47Z (`2026-10-29T20-47-23Z-6e8e…`, call 6, in Q6's set). The harm and its evidence are
  tracked in FIX06 Q2b.

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

**Moved 31 October 2026 (done).** Committed as `9ee7fd6`, whose tree is HEAD `ddbc6d9`'s; the
captured sources of both live runs equal `9ee7fd6`. `packet-guidance.json` holds 52 strings,
and no Zig copy of "conditions and obligations" remains. The semantic tails cited above at
`specification_repair.zig:132` and `specification_provenance.zig:193` now live in
`packet-guidance.json`'s `repair_tails`. Left open: T2, which §3 row 8 marked done with Q3 but
which Q3 only partly did (FIX06 T2); the in-request duplicates Q3 left for Q6, which wasn't kept
(FIX06 §3, "Open problems without a phase"); and the `ValueChoices.correction` observation, now
FIX06 E9.

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

**Built, measured and reverted 31 October 2026 (user decision: not kept).** Every listed
removal was made in the workflow resources (request projection: 3,149 of 4,406 calls changed,
all by the listed removals), and the 12-run set (`evaluations/q4/measures-set.json`, one
tree) failed the keep rule against Q1b:
- **Publication:** hello-world 1 of 6 (Q1b 6 of 6); loan-renewal 2 of 6 (Q1b 4 of 6).
- **hello-world:** extraction's first call returned `no_feature_claim` ("does not contain any
  explicit feature claims") in 5 of 6 runs (Q1b 0 of 6). Three runs then went through a
  source-omission extraction repair and ended `harness_error` `MissingProviderEvidence` at
  `rebuild-extraction-selections` (classification of `Hello, World!` missing); one failed
  `InvalidSpecificationUnit` at generation start; one ended `awaiting_clarification`.
- **loan-renewal:** one run extracted 27 claims from five requirement lines and exceeded the
  token budget after 24 reconciliation repairs; one failed `RetryLimitExhausted` in
  reconciliation repair (summary membership, then signal coverage); two exceeded the budget
  in review (one with two runaways).
- **Likely cause:** removing the second `citations` sentence of `extraction.context.json`
  ("The cited lines become the claim's wording; lines from several top-level list items
  become one claim per item."). Q4 classed it as a native transform no response can
  violate, but it told the model what a claim is. Unverified by a controlled replay.
All Q4 changes were reverted. A retry without the `citations` removal is a new change with
its own measurement set. Unchanged and still model-visible: engine words in native Zig text
(`reference_reconciliation_diagnostic.zig` "native code …" lines, in 868 of 4,406 requests,
and `typed_text.zig`'s "native admission assigns its occurrence identity"); removing them
changes engine text and needs its own decision (D4.1).

**Validation.** Scripted responses with a missing and with a repeated member, for source and
principle reviews, receive the `array_length` and `duplicate_member` corrections, compared
with the owning explanations; sentences kept as task semantics are unchanged in the
assembled requests. Then the measurement set. **Keep if** (hygiene, §2.7) engine vocabulary
in published specs stays absent, and protocol corrections, admission rejections by reason,
other defect classes and cost stay within the comparison point's range. The class is
already at zero (none of the 13 specs published on 26–27 October contains engine
vocabulary; hello-world's "exact text" is plain English), so Q4 can't show a gain. Never
rename a field to chase an observed leak.

**Moved 31 October 2026 (closed: not kept; D4.1's `uncovered_member` correction kept).** FIX06
Q4 keeps D4.1's decided rule, its proposed extension and the open retry.
- **Request-level attribution.** Hello-world's first extraction request was byte-identical
  (digest `c2c8f826d8fd`) in all 13 pre-Q4 runs on the Q1b, D4.1, Q6 and Q3 builds, and Q4's
  differed only by the removed second `citations` sentence. Between the projections
  (`q4-2026-10-31` against `d41-2026-10-30`), that sentence is the only difference in all 320
  projected requests that carry it (305 initial, 15 repair). First-call `no_feature_claim`:
  5 of 6 Q4 runs, 0 of 13 before. Causation is still not replayed.
- **Correction to "one run extracted 27 claims".** Two loan-renewal runs extracted 27 claims
  (25 quoted). In `2026-10-31T02-52-34Z-b671…` the initial dispositions marked 24 claims
  `superseded` by claim 1, and the run exceeded the budget in review. In `…T02-54-32Z-8be8…`
  24 dispositions inserts all answered `duplicate` of claim 1 (harm unverified), after five
  summary calls; its 24 reconciliation repair calls used 104,288 tokens, and it exceeded the
  budget at the signals request. Loan-renewal's first claim cited lines 5–9 together in 6 of 6
  Q4 runs (1 of 13 before); its first extraction request digest moved from `32c7d522d089` to
  `e301dcb5a316`, differing only in the context part.
- **The three hello-world `harness_error` runs** were stopped by the harness before the
  classification repair (E6, fixed 31 October 2026, §4), so their engine outcome is unknown.
- **Stopping.** Q4 ran six runs per case, though its publication guard was decided after three
  (hello-world 0 of 3 published against Q1b's 6 of 6; conditional binomial (2/3)^6 = 0.088);
  runs 4–6 used 442,577 tokens. The record doesn't say whether twelve runs were approved up
  front.
- **Build.** The 12 runs record revision `ddbc6d9`, source `724097ea…`, `modified: true`.
  `evaluations/request-projection/q4-2026-10-31/` is stale.
- **Engine vocabulary.** None of the 22 specs published 29–31 October before Q4 contains engine
  vocabulary.
- **D4.1.** The `uncovered_member` correction (`model_schema_diagnostic.zig:34`,
  `model_protocol_retry.zig:59-71`) has not fired in any of the 26 runs since Q1b (13 of them
  loan-renewal), so its effect is unmeasured. "Measurement set approved 30 October 2026 and
  running on the latest build" is history: the set finished and was kept. It ran on `5bb7f17`
  plus working tree (run 1 `ef3a36f3…`, runs 2–6 `708089f7…`); runs 2–6's captured sources
  equal `ce38bf2`.
- **Engine words in native Zig text.** The `typed_text.zig:156` text is the `unknown_exact`
  description, also used as a repair requirement and a composition-correction explanation; it
  is in no projected or retained request. Both native texts are in the FIX06 Q4 retry.

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

**Moved 31 October 2026 (closed: not kept).** Build: `1ba89f8` plus working tree (source
`415a1cd2…`). Runs: hello-world `2026-10-29T20-44-34Z-b9b0…`, `20-47-23Z-6e8e…` and
`20-52-31Z-a1ac…`; loan-renewal `20-45-17Z-7fb8…`, `20-49-48Z-9d15…` (failed
`WorkflowTokenBudgetExceeded` at review-post-source) and `20-53-48Z-3bd1…`. No measures,
evaluations or labels were kept under `evaluations/`, so the entity counts are unverified (spot
checks agree; in `20-53-48Z` the story equals FR-001). The projection
`evaluations/request-projection/q6-2026-10-30/` is stale; its 1,026 changed requests are 822
generation (264 records, 192 brief, 171 story, 169 entities, 26 generation repairs), 169 source
review, 29 principle review and 6 support-loss, none a reconciliation request.
- **Correction.** The lost UTC requirement came from a reconciliation dispositions insert repair
  (call 6, `duplicate` of claim 1) whose request text is identical to 27 October 09:40's; Q6
  didn't change it (FIX06 Q2b). The revert stands on the target alone: restatement didn't
  improve (benefit not demonstrated, §2.7).
- The in-request duplicates Q6 was to remove remain (for example `generation.prompt.md:2` beside
  `generation.context.json`'s `business_value` in the brief request). ADR 0038:97 still says
  "FIX06 Q6 and Q8 measure it"; it is an accepted ADR and is unchanged.

### D7.1 Exact-value corrections state the boundary rule

- **D7.1** When an exact value is rejected, the correction states the boundary rule,
  generated from the closed boundary policy (`exact_value_boundary.zig`), never from a
  prose list. **Closed 31 October 2026 (user decision, option 1: record only).** No such
  correction exists: an exact value touching other text is not rejected but read as prose
  (`exact_value_recognition.zig` skips the boundary rejection), and the only later check,
  the feature coverage `missing_exact_copy`, always blocks without a model repair
  (`specification_coverage_repair.zig`). Never observed in the 28 retained runs or Q1b.
  Stating the rule up front (in the field rule "Type required exact values verbatim") or
  making a touching value a repairable rejection would each change model input or
  acceptance and need their own decision and measurement.

**Moved 31 October 2026 (closed by user decision, option 1: record only).** Evidence update:
none of the 54 retained runs (26–31 October; the Q1b, D4.1, Q6, Q3 and Q4 sets included) has
an exact-value admission rejection or a `missing_exact_copy` block; the 24–25 October runs are
no longer retained. `missing_exact_copy` is raised at `specification_coverage.zig:93`, and
`specification_coverage_repair.zig:26-30` keeps it blocking. FIX06 Q7 keeps the latent class
visible: a required value touching other text is read as prose, and if nothing else covers it
the run ends in a `missing_exact_copy` block.

### Q11: D11.1, D11.2, D11.4 and D11.5

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

**Moved 31 October 2026 (done; D11.3 stays open in FIX06 Q11).** D11.1 was committed in
`5bb7f17` (29 October 2026); D11.2, D11.4 and D11.5 in `371b55a` (28 October 2026).
- **D11.1.** The removal notes are at design.md:254 and :992-993 (criterion 21),
  21-validation.md:23-24 and :52-53, and 17-specify.md:562; no other design text names either
  lint. The current design.md:254 and criterion-21 wording is a later rewording from `9ee7fd6`.
- **D11.2.** The join is `clauseSeparator` at `specification_markdown.zig:211-212` (`:202` is
  now `fn escaped`); readback accepts only the separator the renderer derives and treats an
  escaped comma as clause text (`:185-186`, `:195-197`); the contract is 23-rendering.md:116-120;
  `exact_value_boundary.endsWithTerminal` is at `:152`. Regression test:
  `src/specification_contract_test.zig`, "acceptance clauses that end a sentence join without a
  comma…" (ellipsis, the CJK full stop, a closing comma, backslash runs, and readback rejection
  of the old doubled separator).
- **D11.4.** AGENTS.md:188-196 names the §22.6 normalization as the third recorded exception,
  reported separately. Withdrawal wasn't chosen, so withdrawing it now would be a new decision.
  The 332-of-349 count re-verifies from the 16 feature logs of 26–27 October; the Q2 pre-phase
  replays (29 October) needed it in 39 of 40.
- **D11.5.** Every listed line cites AGENTS.md; ADR 0041 (:230) already did, and no file under
  `design/` cites CLAUDE.md. ADR 0034:93-94 quotes a prefix of AGENTS.md's current sentence.

## 4. Engine track

### DE6. ADR-required events at every log threshold

From FIX06 E6:

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

**Moved 31 October 2026 (done).** Committed in `371b55a`. Current references: the typed
`Emission` at `src/domain/log_event_registry.zig:29`; the four events at `:70`, `:72`, `:74`
and `:76`, each wrapped in `adrRequired` (`:103-107`); the registry test at `:164-170`. The
threshold action emits `always` events before consulting `isEmitted`
(`src/actions/log/evaluate_log_threshold.zig:24-27`, test `:39-49`); `log_policy.zig:90-92` is
unchanged, and no other threshold path bypasses the action. Step-2 verification: `zig build
verify` 164 of 164 steps, 1,972 tests, and a contract review (§7, row 2). E0's
`run.incomplete_published` never landed (E0 stopped 30 October 2026); it appears only in design
text marked on hold (F0002:361, 26-security.md:90), and FIX06 E0 lists its registration for a
resume.

### E6. Producerless rejection reported as a harness error

From FIX06 E6, as recorded on 31 October 2026 after the fix:

- **Producerless rejection reported as a harness error (implemented 31 October 2026).** Three
  Q4 hello-world runs (`2026-10-31T02-53-14Z-da42…`, `…T02-54-10Z-e167…`, `…T02-55-16Z-d0d3…`)
  ended `harness_error` `MissingProviderEvidence`. A source-omission repair replaced chunk 1's
  `no_feature_claim` with a claim and cleared its classifications;
  `validate-reference-selections` returned `invalid` with `Hello, World!`'s `preserve` missing
  and, by rule, no origin ("a missing value has no producer"), which routes to the
  classification repair. The shared projection `attribution()` mapped every origin-less
  classification rejection to `missing_response`, so the harness stopped the run; the engine
  outcome from that repair on is unknown, and Q4's measures count the runs as unpublished.
  Fix: the validator names the rule (`producerless`, missing entries only) and `attribution()`
  takes it from there, giving `candidate` (contract 27); a lost origin on a duplicate, unknown
  or forbidden entry still rejects, as does an origin on a producerless rejection, and
  `rejectionOrigin` now refuses an issue set naming a classification its entry doesn't hold.
  No other kind has a rule-defined null origin. Tests: unit (`src/structured_token_test.zig`),
  harness correlation (`test/harness/integration/tests.zig`) and the engine scenario that
  produces the rejection (`test/integration/workflow_tests.zig`). No model-input change: the
  request projection is byte-identical to `d41-2026-10-30`. `zig build verify`: 169 of 169
  steps, 1,998 of 1,998 tests. Contract review: no blockers or majors; three minor findings
  fixed. Open: contract 27 (27-observability.md:59-62) names only coverage as an
  assembled-candidate example and no design text states "a missing value has no producer"
  (adding it is a design edit, needs approval); `observation.capture`'s candidate arm has no
  direct test (it needs a runner). **Decision (not needed for this fix):** a first-generation
  omission could instead name its chunk's classification producer, as support's
  `missing_finding` names its response (`specification_support.zig:712`); that changes the
  validator's producer rule.

**Moved 31 October 2026 (implemented).** The review's diagnosis, made from the three runs and
the code before the fix (not reproduced): the trigger, a `no_feature_claim` chunk holding an
exact value that a source-omission repair then turns into a claim, occurred in exactly these 3
of the 6 Q4 hello-world runs (5 of 6 returned `no_feature_claim` first; `02-51-18` then failed
`InvalidSpecificationUnit` and `02-52-18` ended `needs_user`, neither with a repair). The engine
never reached the classification repair: `observation.capture` raised the error, the trace
rejected the next step (`authorize-extraction-repair`) with the harness's own
`operation_failed: OperationExecutionFailed`, and the report named the last executed step
(`trace.last_step`) with `models: []` and `last_model_step: null`. The harness test at
`test/harness/integration/tests.zig:1178-1215` (an `unknown` issue whose origin is genuinely
lost) is the negative case a correct fix keeps. The open notes stay in FIX06 E6, with the
separate support-findings origin question (formerly E5's third gap row).

## 5. Test track

### T1. Repeated-runaway debug capture (B9)

ADR 0039's debug-capture test: at `debug`, a repeated runaway leaves both attempts'
requests, request descriptions and complete returned outputs in the prompt log before the
failure events; at a higher level, only the events. No live run has had a repeated runaway.
Before Q1b. **Done 28 October 2026** (uncommitted): `src/model_request_workflow_test.zig`,
"ADR 0039: a repeated runaway is captured in full at debug before its failure, and only its
events survive higher levels", at every log level, including §26.5's always-emitted events
at `error` and `fatal`.

**Moved 31 October 2026 (done).** Committed in `5bb7f17` (29 October 2026); the test is at
`src/model_request_workflow_test.zig:7998`. Still no live repeated runaway on 31 October 2026:
no retained report carries `RunawayRepeated`, and the 15 runs with `model.provider_stopped`
have an equal count of `model.runaway_resent`. B9's runaways stay a reported measure (FIX06
§2.6, Admission).

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

**Moved 31 October 2026 (done except the brittleness counts, which stay open in FIX06 T5).**
Committed in `5bb7f17` (29 October 2026); `smoke-e2e-measures` runs in the offline suite under
`verify`, and `SDDE_REQUEST_PROJECTION` is read at `src/test_fixtures/request_projection.zig:13`.
Code comments and docs cite "FIX06 T5", "T5(a)", "(b)", "(e)" and "DT5" (for example
`test/harness/e2e/measures.zig:1`, `measures_cli.zig:1`, `e2e_measures.zig:1`,
`src/test_fixtures/request_projection.zig:1`, `test/integration/workflow_tests.zig:1329`,
`design/harness/e2e.md:682` and `.claude/skills/evaluate-e2e/SKILL.md:57`); the (a)–(e)
specification and DT5 are the text above. Statements since overtaken:
- "uncommitted": committed in `5bb7f17`.
- "no retained run's report measures": since Q1b, 38 of the 54 retained runs are v11 and
  measure.
- "`incomplete` (v11's marker, written once E0 lands)": E0 stopped on 30 October 2026, so
  nothing produces the marker; removing it would need a report version (§2.13).
- The step-3 freeze as "E0's base": the request-projection reference is `d41-2026-10-30`, which
  Q3 matches; `q2-2026-10-31`, `q4-2026-10-31` and `q6-2026-10-30` are freezes of reverted
  builds.
- "the brittleness counts, which belong in `zig build code-heuristics`": that holds for four of
  §2.6's seven counts; one is a record and two need definitions (FIX06 T5).

## 6. Research and backlog

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

**Moved 31 October 2026 (obsolete; review, record only).** FIX01 §9.20 recommendations 1–2 are
implemented ([Z_FIX01](Z_FIX01.md) §9.21–9.22). The prepared comparison can't run: its parent
capture (`2026-10-10T00-32-22Z-4b66…`) is gone, its packets predate ADR 0036, its frozen
temperature 0 differs from every retained run's 0.1 (re-preparation would be needed,
`test/calibration/summary-coverage/README.md:45-48`), and its candidate clause is now
production wording (`reference_reconciliation_diagnostic.zig:102`). The development cases fit
one summary partition, so they exercise neither the hierarchy nor carry-forward: every
retained run made one summary call except Q4's two 25-claim runs, which made five. Their live
behaviour is an unmeasured gap these cases can't measure. None of the 14 evaluated Q1b and Q3
runs traces a defect to a summary, and summary losses already localize as
`unsupported_summary` with no repair target. "Make cross-model variation part of acceptance
evidence" proposed a model comparison, which only the user can choose (FIX06 H5). Summary loss
is judged through each set's traced defect classes (§2.5, §2.6) and H1; a summary change meets
§2's summary-representation, normalization and carry-forward gates. The verifier preferred
closing it in place; it moved here with FIX06's other closed records, and FIX06 keeps the
heading. `test/calibration/summary-coverage/README.md:145-148` still says this remains open in
FIX06 (a test-tree edit, not made).

### Wider scope retained: closed parts

FIX06's "Wider scope retained" read, on 31 October 2026:

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

**Closed 31 October 2026 (review).** The open parts stay in FIX06 under the same heading.
- **Evaluator responsibility transfer: closed.** Line locators settled the occurrence half
  (`rubric-judgment/v2`, `fb0f670`, 18 October 2026): the judge cites line locators and the
  harness resolves the exact bytes (`test/harness/judgment.zig:17-20`, `:80-100`). The judge
  still names criterion IDs, whose count, missing and duplicate checks are a defined assignment
  contract (`judgment.zig:70-79`, `:142-146`; design/harness/evaluator.md:214-218, correctable
  reasons `:309-312`). Both halves are defined, and nothing records a need to move assignment
  into native code.
- **The H-017 live milestone and E2E judge failure: superseded.** E2E makes no judge call;
  acceptance is H1 (design/harness/acceptance.md:24-30).
- **The live evaluator demonstration (H-004/H-006):** part of H3's judge qualification.
- **The live clarification path:** E7's two-run case (ADR 0025:176-177).
- **The provider-compatibility diagnostic: closed.** The open point (FIX05 at `b16f49c`) was
  that its frozen 16,384-token binding rejected the shipped 2,048-token cases. Since ADR 0029's
  24 October amendment the shipped cases pass its preflight
  (`test/harness/compatibility/tests.zig:144-146`; design/harness/e2e.md:200-201). It is frozen
  to Bedrock GPT-OSS-20B and rejects the anthropic target (`test/harness/frozen_binding.zig:10-14`,
  `:29-34`), so it neither changes nor compares models. design/harness/README.md:44 still says
  shipped cases are rejected (not edited).
- **"(E0 changes this)":** void, since E0 stopped; the requirement itself stays open.
- **Provider docs:** contract §12.3.2 now exists (12-model-boundary.md:278, added in `9ee7fd6`);
  the F0009 and "Live use" parts stay open in FIX06.

### B7 contract-review leftovers: repeated citation ID

FIX06's "B7 contract-review leftovers" read, on 31 October 2026:

Stored readback doesn't re-quote claim text from its citations; admission admits a repeated
citation ID; `source_selections` naming was left out of scope. No observed outcome.

**Closed in part 31 October 2026 (review).** A repeated citation ID isn't open work: ADR 0036
Decision 1 admits it and it adds nothing (0036:61-62; `reference_extraction_text.zig:150-157`),
decided in `f7199b1`, the commit that recorded the leftover. The readback and naming leftovers
stay open in FIX06.

## 7. Progress rows 1–11 and the cost estimate

FIX06 §10's rows for finished steps, as of 31 October 2026:

| Step | Item | State | Build | Runs | Result |
| --- | --- | --- | --- | --- | --- |
| 1 | Q1a | Done 28 October 2026 (D1.1, D1.2 decided) | `d4fd4a5` | Offline only | `zig build verify`: 164 of 164 steps, 1,969 of 1,969 tests; `git diff --check` clean; no tracked file outside `fixes/` names the removed rule; contract review: no code findings, three minor doc findings fixed |
| 2 | Pre-baseline decisions | Decided 28 October 2026; D11.2, D11.4, D11.5 and DE6 implemented, uncommitted | Working tree on `d4fd4a5` | Offline only | `zig build verify` on the final tree: 164 of 164 steps, 1,972 of 1,972 tests; D11.2: none of the 21 retained `spec.md` files has a clause ending whose join changes, so re-rendering is byte-identical; contract review: no code defects; its major finding (§26.5 and §13.9 still stated the old emission rule) and six minor findings fixed |
| 3 | T5, T1, D11.1, `spec-e2e-report/v11`, DT5 | Implemented 28 October 2026; v11, the measure-definition approval and DT5 on 29 October (decided that day); uncommitted, except brittleness counts (see T5) | Working tree on `371b55a` | Offline only | `zig build verify` on the final tree: 169 of 169 steps, 1,984 of 1,984 tests; contract reviews: step 3 had no blockers and one major, seven minor and three nit findings, all fixed; v11 had no blockers or majors and eight minor findings and a nit, all resolved (the draft measures files are renamed); DT5 had no blockers, one major (operational errors marked a run unmeasurable), three minor and five nit findings, all fixed; see T5's status |
| 4 | Q1b | Done 29 October 2026 on the latest build by user decision ("run Q1b on the latest build"): the uncommitted step-3 tree, source digest `c7684e21…`, so every run records `modified: true` (a user-approved deviation from §2 rule 3). Runs 1 of each case are the 08:51 and 08:53 runs | `371b55a` + working tree | 6 hello-world, 6 loan-renewal | Baseline table below; measures `evaluations/q1b/measures-set.json`; evaluations `evaluations/e2e/2026-10-29T*/`; none adjudicated |
| 5 | E0 | Stopped 30 October 2026 by user decision ("stop E0"): slice S1 and part of S2 were built, then removed; ADR 0041 on hold with Decisions 7 and 8 recorded | — | — | — |
| 5a | D4.1 correction | Kept 30 October 2026 by user decision | Latest build | 6 (correction never fired) | `evaluations/e2e/d41-measures-set.json` |
| 6 | Q2 | Built, replayed and reverted 31 October 2026 | Working tree on `ddbc6d9` | 40 replay calls | Harmful 1/40 → 1/40; valid 40/40 → 36/40 |
| 8 | Q3 | Done 31 October 2026 (committed `9ee7fd6`) | Working tree on `8444312` | 2 (one per case, both published) | Requests byte-identical to `d41-2026-10-30` |
| 9 | Q6 | Built, measured and reverted 30 October 2026 | Latest build | Measurement set | Not kept |
| 10 | D7.1 | Closed 31 October 2026 (record only) | — | — | No exact-value boundary correction exists |
| 11 | Q4 | Built, measured and reverted 31 October 2026 | Working tree on `ddbc6d9` | 12 | Published 1/6 and 2/6 (Q1b 6/6, 4/6) |
| 12–20 | Q5–Q11, closing set | Proposed | — | — | — |
| — | E1–E8, T2–T4 | Proposed or accepted, not started | — | — | — |

**Corrections (review, 31 October 2026).**
- Row 2: D11.2, D11.4, D11.5 and DE6 were committed in `371b55a` (28 October 2026). Row 3:
  T1, T5, D11.1, v11 and DT5 were committed in `5bb7f17` (29 October 2026), except T5's
  brittleness counts.
- Row 5a: built on `5bb7f17` plus working tree (run 1 `ef3a36f3…`, runs 2–6 `708089f7…`); runs
  2–6's captured sources equal `ce38bf2`.
- Row 8: Q3's two runs' captured sources equal `9ee7fd6`. T2 isn't done (FIX06 T2).
- Row 9: built on `1ba89f8` plus working tree (`415a1cd2…`); 6 runs; no measures or evaluations
  retained.
- The last row is superseded: DE6 is done, T2 is partly done, and T5's brittleness counts were
  unlisted.

The pre-set cost estimate, superseded by measured set costs in FIX06 §10:

**Cost estimate.** Runs on 26–27 October used 61,906–93,411 tokens (hello-world) and
85,486–98,032 (published loan-renewal). A measurement set with its two control runs is about
0.5–0.8 million tokens; Q1b's twelve runs about 0.75–1.2 million; each extension about
0.25–0.6 million. A replayed repair call costs about 1,300 tokens. Q3, Q10a and each engine
item need one run per case.
