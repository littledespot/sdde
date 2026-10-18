# FIX05 — Architecture review and consolidated open work

**Reviewed:** 17 October 2026, Australia/Melbourne, at `b2f10a3`.

**Status:** sole active fix record. It consolidates the open work of FIX01 (Spec
reliability backlog) and FIX04 (semantic-simplicity evaluation), which are deleted.
Their last text is at `b2f10a3` (`git show b2f10a3:fixes/FIX01.md`,
`git show b2f10a3:fixes/FIX04.md`). Former item IDs (FIX01 R1–R11, FIX04 F1–F13 and
Phases 0–6) are kept for traceability. Completed work and dated evidence remain in
[Z_FIX01](Z_FIX01.md) and [Z_FIX02](Z_FIX02.md).

Unless a dated user approval is recorded below, items are findings or proposals.
Items marked **Decision** amend an accepted ADR, contract or scope and need
explicit user approval first. A proposal authorizes no code change, live call or
E2E run. The governing design remains **Proposed design**.

**Evidence:** the code at `b2f10a3`, `zig build code-heuristics`, git history, the
run records in Z_FIX02 and the retained 16 October 22:00 run. No tests or live calls
were run for that initial review. Dated B3 updates below record subsequent
approved checks and live diagnostics separately.

## 1. Verdict

The deterministic core works. Since Phase 1A no value breaking a declared native rule
has escaped admission, and every failure ends as a typed outcome. Duplication is low
(five pairs of repeated function bodies, two of which W2 removes), and production
code has no `@constCast` and nine
`catch unreachable`. The engine is not hard to build or brittle because of local code
quality.

Two structural properties cause both problems:

1. **The architecture makes every concept expensive.** One idea is spread across an
   action, a binding, a registry entry, global data keys, YAML nodes and pinned
   tests. The generic runner also has to police the model-request lifecycle that
   the YAML exposes (§2).
2. **The Spec workflow is a long serial chain of strict, fail-closed judgments by one
   small model.** End-to-end success is roughly the product of per-call success, and
   fixed per-call overhead exhausts the token budget before review finishes (§3).

A stronger model would likely hide these weaknesses rather than remove them.

| Measure | Value |
| --- | --- |
| Hello-world reference | 189 bytes, three requirements ([stories.md](../test/e2e/wf-001-hello-world/reference/stories.md)) |
| Full-workflow diagnostics, 16 October (AEDT) | Eight runs on GPT-OSS-20B: two loan-renewal and six hello-world (F9, F11–F13 and 22:00); none published a specification |
| Most fully measured run (09:18) | 41 sends and 101,134 tokens; review 29 sends and 77%; input tokens 93% ([cost investigation](Z_FIX02.md#545-phase-2-review-and-repair-cost-investigation)) |
| First run passing every native generation check (20:33) | 42 calls and 100,884 tokens; budget exceeded during re-review; review 75.6% |
| Pre-B3 retained run (22:00, modified `3303498`) | `RetryLimitExhausted` at brief generation after 10 calls and 13,797 tokens: `embedded_insertion_syntax`, and a `{"token{` envelope prefix on call 2 |
| B3 live baselines, 17 October (AEDT), committed `dfae959` | Both pass the local mechanical admission gate with zero observed escapes; hello-world blocks later on competing records (12 calls, 18,757 tokens), loan-renewal fails during review on budget (38 calls, 101,933 tokens). Neither publishes (§B3). |
| B5/B8/R8 live diagnostics, 17 October (AEDT), committed `8ed40ba` | Both reach post-generation review. Hello-world exhausts the budget in principle review (30 calls, 103,873 tokens); loan-renewal fails on a runaway review response at the provider output limit (13 calls, 45,322 tokens). Neither publishes (§1). |
| B4/B9 live diagnostics, 17 October (AEDT), committed `f086dd1` | Hello-world publishes for the first time (26 calls, 70,830 tokens); human adjudication is pending and the advisory grader fails to parse. Loan-renewal blocks on a forbidden source-review verdict (23 calls, 64,636 tokens), fixed offline in §10 (§1). |
| §10–§12 live diagnostics, 18 October (AEDT), uncommitted build on `85556b2` | 09:58/10:00: hello-world publishes (24 calls, 64,489 tokens); loan-renewal finishes source review, then fails on budget (31 calls, 111,880 tokens) after five truncated-prefix retries. 10:43/10:44, after §12: both cases publish for the first time (27 calls / 72,434 and 23 / 93,621). All three grader runs fail `quote_not_found` (§1); line locators replace quotes in §13. |
| §13 live diagnostics, 18 October (AEDT), committed `fb0f670` | Hello-world publishes (24 calls, 62,894 tokens); the grader's line locators all resolve, but it omits source evidence for one criterion. Loan-renewal blocks at its first source-review assignment, which omitted one member (11 calls, 21,989 tokens); fixed offline in §14 (§1). |
| §14 live diagnostics, 18 October (AEDT), committed `96fb905` | Hello-world publishes (25 calls, 65,728 tokens); the grader again omits source evidence for one criterion. Loan-renewal no longer blocks: source review runs 21 assignments without a membership defect, then exhausts the token budget (31 calls, 100,441 tokens) (§1). |
| B2/W1 live diagnostics, 17 October (AEDT), committed `b4c7b07` | Neither reaches review. Hello-world blocks on the token-only record batch again (11 calls, 17,754 tokens); loan-renewal fails at its first record batch on the provider output limit after runaway entity output (10 calls, 32,333 tokens). Neither publishes (§1). |
| Code | 63,889 production and 82,792 test lines, for one of four planned workflows |
| Spec workflow | 1,168 YAML lines; 282 steps in 33 graphs (205 operation nodes, 77 subgraph calls); 185 distinct operations; 18 model-request sites (§4) |
| History | 199 commits in 8 weeks; 297,901 Zig lines inserted and 148,709 surviving; 22 ADRs between 26 August and 6 October |

### Post-B3 outcome assessment — 17 October 2026

This assessment compares the two B3 live baselines with the 16 October runs and with
the [intent](../design/intent.md). B3 records the mechanics of those baselines.

**Verdict: the direction is right, but the outcome has not improved yet.**

B3 did what it was designed to do:

- Every generation call in both runs was admitted on its first attempt, with no
  composition correction. Before B3, four of the five most recent hello-world runs
  failed on exact values.
- Loan-renewal passed exact-value coverage in a live run for the first time.
- Failures moved downstream to the boundaries this record predicted: B5's record
  batches and B2's review. No new failure class appeared.

But neither run published. Useful completion is therefore still zero across the ten
full-workflow runs since 16 October, and loan-renewal ended where its 08:09 run did:
out of budget in review.

| Case | Run (AEDT) | Build | Calls / tokens | Generation corrections | Furthest point | Terminal |
| --- | --- | --- | --- | --- | --- | --- |
| Hello-world | 16 Oct 16:20 | `bfec3d7` | 8 / 12,896 | Title rejected; repair repeated it | Brief | `RepairNoProgress` |
| Hello-world | 16 Oct 18:58 | `54de975` plus uncommitted code | 14 / 20,374 | Record fields collapsed into insertions | Records | `RepairNoProgress` |
| Hello-world | 16 Oct 20:22 | `6676ad8` | 14 / 22,780 | Story corrected twice | Coverage | Blocked: value typed, not inserted |
| Hello-world | 16 Oct 20:33 | `6676ad8` | 42 / 100,884 | Not recorded | Re-review | Budget |
| Hello-world | 16 Oct 22:00 | modified `3303498` | 10 / 13,797 | Insertion syntax in prose | Brief | `RetryLimitExhausted` |
| Hello-world | **17 Oct 09:05** | **`dfae959` (B3)** | **12 / 18,757** | **None** | **Records batch 2** | **Blocked: duplicate records** |
| Loan-renewal | 16 Oct 07:54 | uncommitted `4f25a06` | 13 / 25,508 | Not recorded | Records | Blocked: duplicate records |
| Loan-renewal | 16 Oct 08:09 | uncommitted `4f25a06` | 37 / 101,002 | Not recorded | Entity review | Budget |
| Loan-renewal | **17 Oct 09:06** | **`dfae959` (B3)** | **38 / 101,933** | **None** | **Entity review** | **Budget** |

Against the intent's success measures:

| Measure | Observed in the B3 baselines |
| --- | --- |
| Requirement preservation | Hello-world: all three duties preserved. Loan-renewal: all five source duties appear in functional-requirement prose, but extraction weakened "must be able to renew" to "may renew" (B7), no acceptance criterion tests refusal, and `Renewal refused.` lost its exact-value witness (B8). |
| Unsupported additions | Minor. The Loan–Borrower, DueDate and RenewalStatus relationships are inferred, not stated; hello-world's goal adds "confirming the application runs correctly". |
| False assessments | Review accepted the weakened obligation as faithful (calls 15, 17 and 23), accepted refusal coverage that doesn't exist (call 20), and gave opposite verdicts on byte-identical text (calls 29 and 35). |
| Repair-induced harm | None observed; no content repair ran. |
| Successful completion | 0 of 2 (0 of 10 since 16 October). |
| Latency | About 17 seconds and 52 seconds. |
| Cost per acceptable result | Undefined, because there is no acceptable result. |

**Alignment with the intent.** B3, and the B2/W1 change now being implemented under
[ADR 0023](../design/decisions/0023-advisory-post-generation-review.md), both apply
the intent's central principle: deterministic code owns bookkeeping, and model review
is advice, not authority. Two cautions follow from these runs:

1. **Publication will soon stop being a measure of quality.** Once review is
   advisory, a candidate like this loan-renewal one could publish despite its
   weakened obligation, missing refusal scenario and dropped exact value. The intent
   counts useful, faithful output, not publication. R8's acceptance policy and a
   refreshed rubric calibration therefore need to be in place before the post-B2/W1
   reruns, or a publication will be mistaken for success.
2. **The next failures are engine structure, not model capability.** Three of them
   are bookkeeping or structure that code can own: token-only record batches (B5),
   model-disposed exact tokens (B8) and extraction collapsing structured sources
   (B7). Fixing them applies the same principle as B3. Rewording prompts does not.

### Post-B2/W1 live diagnostics — 17 October 2026

Both reruns used committed `b4c7b07` (B2/W1/W2), unmodified, about 2.5 hours after
the B3 baselines. B2's committed-build live comparison records their mechanics and
audit artifacts; this section assesses outcome and direction.

| Case | Run (AEDT) | Calls / tokens | Duration | Furthest point | Terminal |
| --- | --- | --- | --- | --- | --- |
| [Hello-world](../zig-out/e2e-spec/2026-10-17T00-38-56Z-f26b1f0f123016ca419a66968d79addf/report.json) | 17 Oct 11:38 | 11 / 17,754 | About 15 s | Records batch 2 | Blocked: duplicate records (B5) |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-17T00-39-51Z-9210b2b21f83c723235fef18c6eed60e/report.json) | 17 Oct 11:39 | 10 / 32,333 | About 50 s | Records batch 1 | Failed: provider output limit (B9) |

Admission escape is zero in both runs (14 and 9 admitted values).

**Verdict: no improvement, and B2/W1 is still untested live.**

- **B2/W1 not exercised.** Neither run reached review, so these runs neither confirm
  nor refute the advisory-review change. Its offline verification (B2) remains the
  only evidence.
- **No publication.** Useful completion is 0 of 12 full-workflow runs since
  16 October.
- **No sign that B2/W1 caused either failure.** It changed review only. The
  generation requests use identical inference settings and differ from the B3
  baselines only in what earlier model calls produced.

What the runs show:

- **B5 reproduced exactly.** Hello-world's second record batch was again assigned
  only `Hello, World!`; the model re-authored the feature and the run blocked. It is
  now the deterministic hello-world blocker, in 2 of 2 runs since B3.
- **Exact values lost again, by a different route (B8).** Token classification
  (call 2) marked both `Loan renewed!` and `Renewal refused.` as `irrelevant`, so the
  run carried no exact-value obligations at all. In the B3 baseline the same step
  preserved both, and reconciliation then dropped one. Loan-renewal has lost exact
  obligations in both post-B3 runs.
- **Runaway record output (new B9).** With no tokens, loan-renewal had only one
  record batch.
  - The entities step's basis now named three entities.
  - The batch wrote an acceptance criterion, a functional requirement and then 286
    invented entity records, degenerating into names like
    `RenewalNotificationFailureNotificationFailure…Log`, until the 16,384-token
    output limit.
  - That one call used 19,979 tokens (62% of the run) and 37 seconds.
  - The engine rejected the partial output with a typed `output_limit`, as
    designed.
- **B7 reproduced.** Extraction collapsed the source list into one claim in all four
  post-B3 runs. It weakened loan-renewal's "must be able to renew" to "may renew" in
  both loan runs.
- **Run-to-run variance.** With identical source bytes and settings (temperature
  0.1), the same steps flipped between runs:
  - token classification went from preserve to `irrelevant`;
  - the entity basis went from one entity to three;
  - record output went from 3 records to 286.

  Single model judgments that decide bookkeeping aren't stable enough to depend on.
- **Minor text defects.** Hello-world's story says "exactly as preserved", which is
  engine vocabulary leaking into business text. Its title is the whole requirement
  sentence.

**Direction and alignment.** The direction is still consistent with the intent.
These runs, however, move the binding constraints upstream of review, onto things
the engine can own:

- the token-only record batch (B5), which is deterministic;
- exact-value classification and disposition (B8);
- extraction granularity (B7).

Both runs stopped explicitly, with typed outcomes and no invented success, as the
intent requires. Until B5 and B8 change, further billed reruns add little
information: hello-world will block on B5, and B2/W1 stays unobserved unless a run
reaches review.

### Post-R8 live diagnostics — 17 October 2026

Both runs used committed `8ed40ba`, which adds B5, B8 and R8 on top of B2/W1/W2.
The build was unmodified; each run was separately approved and ran once.

| Case | Run (AEDT) | Calls / tokens | Duration | Furthest point | Terminal | R8 acceptance |
| --- | --- | --- | --- | --- | --- | --- |
| [Hello-world](../zig-out/e2e-spec/2026-10-17T02-28-48Z-98d2a6fa251a2fda83c0720101e8bf93/report.json) | 17 Oct 13:28 | 30 / 103,873 | About 44 s | Principle review | Budget (`WorkflowTokenBudgetExceeded`) | Failed: no publication |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-17T02-30-17Z-40047cad83559d7eacc1b9a991f60a7c/report.json) | 17 Oct 13:30 | 13 / 45,322 | About 66 s | Third source-review call | Provider `output_limit` | Failed: no publication |

Admission escape is zero in both runs (14 and 16 admitted values). Neither run
published, so no human adjudication applied. Useful completion is 0 of 14 runs
since 16 October.

**Verdict: real progress upstream; the blocker is now review cost and runaway
output.**

What improved:

- **B5 and B8 work as designed.** Each run authored exactly one record batch, so the
  token-only batch is gone, and with it the duplicate-record block and the
  duplicated review. Both runs preserved their exact values, and reconciliation
  disposed only the business claim.
- **Both runs reached post-generation review.** Hello-world finished source review
  and entered principle review, the furthest any hello-world run has reached.
- **Source review cost less and raised no false findings here.**
  - Hello-world's source review took 13 calls and 39,025 tokens, against 29 sends and
    77,933 tokens on 16 October at 09:18.
  - All 13 calls returned `supported`, with no mis-typed omissions.
  - These are unlabelled model judgments on simple content.
- **No rebuild loop.** No upstream rebuild or loss-localization call occurred (W1).

What blocks now:

- **Advisory review spends the budget and fails the run.**
  - Hello-world's review used 89,283 tokens (86% of the run) to return only
    `supported` and `compatible`.
  - Under ADR 0023 those verdicts can't change the specification. Yet spending the
    budget on them prevented publication of a candidate whose content looked
    faithful.
  - Principle review alone took 7 calls and 50,258 tokens, because every call
    resends all seven principle documents (567 lines, about 6,800 input tokens).
- **Runaway output, now in review (B9).**
  - Loan-renewal's third source-review call began a `supported` finding, broke its
    JSON close, then emitted about 48,500 characters of blank lines until the
    16,384-token limit. That one call cost 20,587 tokens.
  - Runaways have now ended 2 of the 3 loan-renewal runs since B3 (records, then
    review) and none of the hello-world runs.
- **Known content gaps remain.**
  - Extraction still collapses each list into one claim, and loan-renewal still
    says "may renew" (B7).
  - Loan-renewal again has no acceptance criterion for refusal. The runaway
    finding accepted refusal coverage from the brief and description, which the
    scenario scope disallows.
  - Hello-world adds a business rule that duplicates its functional requirement, and
    loan-renewal's title is a whole paragraph.

**Direction and alignment.** B5 and B8 applied the intent's principle and removed
their failure classes on the first live attempt. The remaining misalignment is with
"useful, faithful outputs at an acceptable total cost". An advisory stage that
cannot change the output now consumes most of the budget and decides whether
anything publishes. That inverts the intent: advice should inform, not gate, and it
should not cost more than producing the output. B4 records the options.

### Post-B4/B9 live diagnostics — 17 October 2026

Both runs used committed `f086dd1` (B4 option 3 and B9), unmodified; each was
separately approved and ran once.

| Case | Run (AEDT) | Calls / tokens | Furthest point | Terminal | R8 acceptance |
| --- | --- | --- | --- | --- | --- |
| [Hello-world](../zig-out/e2e-spec/2026-10-17T07-40-56Z-42741c03ae9491dd21356847f896c273/report.json) | 17 Oct 18:40 | 26 / 70,830 | Publication | `ok`; principle advice incomplete (provider output limit) | `human_adjudication_required`; grader `invalid_judgment` |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-17T07-41-55Z-70ace07a65f0a8a981d08fbf6512409f/report.json) | 17 Oct 18:41 | 23 / 64,636 | Source review | Blocked: `UnsafeSupportRepair` | Failed: no publication |

Admission escape is zero in both runs (21 and 15 admitted values). This is the first
publication since 16 October: 1 of 16 runs. Whether it is useful awaits human
adjudication.

What improved:

- **Principle review is one call.** It took 1 call and 10,621 tokens, against 7 calls
  and 50,258 tokens after R8. Hello-world finished within budget.
- **Advice no longer gates publication.** The principle call stopped at the 2,048-token
  output allowance, and the run still published with explicit incomplete advice.

What blocks or misleads now:

- **Forbidden verdict offered, then blocked (loan-renewal).** Source review returned
  `not_applicable` for entity applicability. Admission rejects that verdict whenever a
  candidate exists, and no repair applies, so the run blocked. The whole-assignment
  schema from B2 always offered it. §10 fixes this offline.
- **Principle advice is structurally truncated.** The single principle call covered
  16 subjects, and each finding cited all seven chunks. It reached about subject 11
  before the 2,048-token allowance, so it was not runaway output. B4 option 3 and B9's
  allowance conflict on any feature that isn't trivial. **Decided 18 October 2026:**
  the user directed that there be no output token limits; §11 removes the allowance
  and logs every provider-applied stop.
- **The advisory grader cannot parse this provider.** Every GPT-OSS response in both
  runs, including the grader's, began with the `{"{` opening artifact. Production
  envelope parsing strips it under the approved §22.6 exception. The grader
  ([judgment.zig](../test/harness/judgment.zig)) parses strict JSON directly with no
  retry, so it reported `invalid_judgment`. **Approved 18 October 2026:** the grader
  now uses the canonical envelope parser (§11). Its unadmitted output scored every
  criterion 4/4, despite the unsupported content below.
- **Content defects in the published hello-world specification:**
  - AS-001 "The system clock is set to UTC." is unsupported by the source;
  - entity applicability is `required`, with an invented "Application Start" entity,
    where both B3 baselines judged it `not_applicable` (B6);
  - the three source requirements remain one FR and one AC (B7), BR-001 repeats FR-001,
    and the title is the whole requirement sentence.
- **B7 reproduced again.** Loan-renewal extraction produced one claim saying "may
  renew".
- **Truncated-key prefix.** `{"find{` cost one protocol retry in each run (B6),
  later normalized (§12).

### §10–§12 live diagnostics — 18 October 2026

All four runs used an uncommitted build on `85556b2` (`modified: true`). It included
§10–§12 and another party's unfinished reference-extraction edits. Each run was
separately approved and ran once.

| Case | Run (AEDT) | Calls / tokens | Retries | Terminal | Grader |
| --- | --- | --- | --- | --- | --- |
| [Hello-world](../zig-out/e2e-spec/2026-10-17T22-58-49Z-4e3589f14a064581bd107bf4a73d00e4/report.json) | 18 Oct 09:58 | 24 / 64,489 | 0 | Published | `quote_not_found` |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-17T23-00-08Z-5210055c5d2617259529446984f05612/report.json) | 18 Oct 10:00 | 31 / 111,880 | 5 | `WorkflowTokenBudgetExceeded` in principle review | Not run |
| [Hello-world](../zig-out/e2e-spec/2026-10-17T23-43-23Z-050dc69173887cb5f0b9d63922650155/report.json) | 18 Oct 10:43 | 27 / 72,434 | 0 | Published | `quote_not_found` |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-17T23-44-18Z-9f793695f5dc438e28b7d9f4b8a5f8d9/report.json) | 18 Oct 10:44 | 23 / 93,621 | 0 | **Published** (first loan-renewal publication) | `quote_not_found` |

Admission escape is zero in all four runs (19, 48, 20 and 55 admitted values).

What improved:

- **§10:** loan-renewal finished source review in both runs. No forbidden verdict was
  offered, and nothing blocked.
- **§11, grader:** the grader parsed every judge response.
- **§11, output allowance:** no stop occurred while the allowance was absent and the
  largest legitimate output was 2,772 tokens.
- **§12:** at 10:00, the truncated `{"find{` prefix appeared six times and cost five
  retries and 18,802 tokens. At 10:44 the engine normalized the one occurrence and
  logged a `REMOVED_PARTIAL_FIELD_PREFIX` warning, with no retry.
- **Principle review completed** in every run that reached it.

What blocks or misleads now:

- **The grader cannot match its quotes.**
  - None of the eight specification quotes at 10:44 appear in the captured bytes,
    even after removing Markdown backslash escapes.
  - The judge also drops inline code, bold labels and emphasis markers, and changes
    case.
  - **Decided 18 October:** the judge cites line locators instead (§13).
- **Bedrock caps output when no allowance is sent.**
  - At 10:44, source-review call 22 stopped at exactly 4,096 output tokens
    (`OUTPUT_LIMIT`). The runner logged it as `model.provider_stopped`.
  - When no `maxTokens` is sent, Bedrock's default for this model is therefore 4,096,
    not the 16,384 that requests used to reach.
  - Here the cap only cut a whitespace runaway (about 96% whitespace after a broken
    JSON close), holding it to 6,758 tokens. That assignment's advice closed
    incomplete and publication continued.
  - Decision deferred: keep the default unless a stop cuts legitimate output.
- **Loan-renewal duplicates records (B7).**
  - Extraction produced one claim.
  - The single record call generated 74 records, and 32 published, with heavy
    paraphrase duplication: AC-003 repeats AC-001, there are five overlapping
    user-visible outcomes, six overlapping edge cases, and FR-003 to FR-005 restate
    FR-001.
  - Every record traces to one claim, so native normalization cannot tell distinct
    duties from paraphrases.
  - AS-001 adds an implementation assumption (a renewal flag), and the title is a
    paragraph.
- **The budget margin is thin.** Loan-renewal finished at 93,621 of 100,000 tokens,
  with review at 78% of usage.

Content gains: loan-renewal preserved all five duties, including "must allow", for
the first time with a refusal acceptance criterion (AC-002) and both exact
messages. Hello-world's title and earlier unsupported assumption are fixed. It still
merges the three requirements and invents a "Greeting" entity. These reports are
`spec-e2e-report/v5`, which the current adjudicator no longer reads (§13).

### §13 live diagnostics — 18 October 2026

Both runs used committed `fb0f670` (`modified: false`). Each was separately approved
and ran once.

| Case | Run (AEDT) | Calls / tokens | Terminal | Grader |
| --- | --- | --- | --- | --- |
| [Hello-world](../zig-out/e2e-spec/2026-10-18T01-10-09Z-2c88ca9292b1d2df35136bd8c47b830d/report.json) | 18 Oct 12:10 | 24 / 62,894 | Published | `missing_source_evidence` (`organization`) |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-18T01-11-19Z-2c6a7e7aa61b7090db33fb3bfabc2b6b/report.json) | 18 Oct 12:11 | 11 / 21,989 | Blocked: `UnsafeSupportRepair` | Not run |

Admission escape is zero in both runs (18 and 19 admitted values). Neither run
retried.

- **Line locators work.** All 13 of the judge's citations resolve to in-range lines
  that have text. The judgment failed only because `organization` cited no source
  lines, while the contract requires source evidence. The grader still has no
  correction for an invalid judgment, which is an open decision.
- **Loan-renewal blocked on a membership defect.**
  - Its first source-review assignment (display name, description, primary goal)
    returned findings for two members and none for `primary_goal`.
  - Native collection rejected the whole assignment and kept no candidate.
    Support repair cannot authorize without a candidate, so authorization returned
    `UnsafeSupportRepair` and the workflow ended `blocked`.
  - This is the second advisory block of this class after 17 October's
    `invalid_decision`. §14 fixes it offline.

### §14 live diagnostics — 18 October 2026

Both runs used committed `96fb905` (`modified: false`). The user approved the pair,
and each case ran once.

| Case | Run (AEDT) | Calls / tokens | Terminal | Grader |
| --- | --- | --- | --- | --- |
| [Hello-world](../zig-out/e2e-spec/2026-10-18T04-31-59Z-3be140e05e0a4438b7b8032623a9f278/report.json) | 18 Oct 15:31 | 25 / 65,728 | Published | `missing_source_evidence` (`clarity-testability`) |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-18T04-33-30Z-1f61f06f029c491beac9698bcfd21026/report.json) | 18 Oct 15:33 | 31 / 100,441 | Failed: `WorkflowTokenBudgetExceeded` in post-generation source review | Not run |

Admission escape is zero in both runs (18 and 63 admitted values).

- **The membership block did not recur.** Loan-renewal's source review completed
  21 assignment calls (calls 11–31) with no membership defect and no retry. No
  response needed the §14 correction, so this pair shows the block is gone. It
  does not show live that the correction recovers.
- **Loan-renewal now fails on budget.** Records generation (call 10) produced
  duplicate records, which native atomic deletions removed without a model call
  (B7). Post-generation source review then spent 80,901 tokens on 21 assignments
  before the 100,000-token budget stopped it (B2). This matches the
  10:00 run's budget failure (§10–§12 diagnostics).
- **Hello-world** corrected one malformed JSON response in source review (call 23,
  a syntax error at byte 4) on its second attempt, then published.
- **The grader failed for the second run in a row.** It cited no source lines for
  `clarity-testability`, after `organization` at 12:10. The grader still has no
  correction for an invalid judgment, so this open decision now blocks every
  grade.

## 2. Why the engine is hard to implement

### A1. Engine lifecycle mechanics live in workflow YAML

[ADR 0005](../design/decisions/0005-workflow-defined-operations.md#L28) requires every
retry branch, repair branch and success rule to be visible in YAML.
[ADR 0012](../design/decisions/0012-workflow-owned-model-request.md) retains one
request across YAML steps. Lifecycle correctness, however, stays a kernel duty.

As a result, one model call is a preparation node plus 14
[`model-request-body`](../design/workflows/spec.workflow.yaml#L1016) nodes:

- attempt accounting, operation assignment and authorization;
- a phase check and two lifecycle advances;
- invocation, observation validation and operation completion;
- admission, retry and close;
- two termination nodes.

The kernel then has to police every ordering of its own lifecycle.
[`executeStep`](../src/application/workflow_pipeline_runner.zig#L165) is 313 lines
with 213 decision tokens, and the "generic" runner mentions `model` 130 times and
`provider` 82 times. A wiring error surfaces as a runtime rejection, not a compile
error. Any lifecycle change touches YAML, runner checks and tests together.

**Decision** (amends ADRs 0005 and 0012): make one model request a single registered
operation. The YAML still chooses the slot, prompt, schema, context, retry limit and
outcome transitions. The engine owns accounting, authorization, invocation, admission
and lifecycle internally. This keeps visible what is asked and removes kernel
mechanics from project-authored graphs.

The workflow-authoring simplification (former FIX03 Phase 8) and the
architecture-wide responsibility audit (former FIX01 §8) belong to this decision. A
supported no-consolidation decision remains a valid outcome.

### A2. Every concept costs about six coordinated edits

There are 266 actions, with a median size of 17 lines. Most delegate to
`src/domain/`, which holds 33,366 lines. Each operation also needs:

- an application binding with a second contract and an outcome association, for
  example [the protocol-retry binding](../src/application/model_protocol_retry_workflow.zig#L7);
- a registry entry;
- entries in the closed 196-member [`DataKey`](../src/domain/pipeline.zig#L4) enum,
  which 351 files import;
- a YAML node;
- usually an architecture test.

Churn concentrates at the centre. `composition/root.zig` changed in 86 of 199
commits, `pipeline.zig` in 48, the runner in 38 and `native_workflow_operations.zig`
in 37. Recent commits touch 50–200 files. Plan, Tasks and Implement would multiply
this cost.

**Decision** (node granularity under §§5–6): let one registered operation own a
cohesive stage, such as extraction together with its own admission. Keep single
responsibility at the module and function level. Measure the files touched per
change before and after.

### A3. Type-erased child bindings hide data flow

Bootstrap configuration reading is 29 parameterless steps behind a `*anyopaque`
vtable ([bootstrap_child_bindings.zig](../src/application/bootstrap_child_bindings.zig#L10)).
Each step receives only the erased context and returns an outcome, so data moves
between steps through hidden mutable state. Production code has 386 `anyopaque` and
295 `@ptrCast`. The compiler cannot check the wiring where wiring errors happen, and
AGENTS.md lists unbounded `anyopaque` at boundaries as a prohibited shortcut.

**Proposal:** where an orchestrator's sequence is fixed, as in bootstrap and feature
logging, call typed steps with explicit inputs and outputs. Keep spy tests through a
typed interface. This changes design §14's orchestrator pattern, so confirm its
scope first.

### A4. Rejections do not say why

The runner has 119 sites that return a payload-free `.rejected = .authority`, and
[`Rejection.diagnostic`](../src/domain/workflow_execution.zig#L54) reports only
`failed` for it. `src/application/` has 147 `error.OperationExecutionFailed` sites,
and production code has 865 `catch return <fixed tag>` mappings. Nested compiled step
IDs such as `g37-g25-g17-g8-generate-brief-gen-request-account` locate a failure but
not its cause. Every integration defect therefore needs manual bisection, which is
part of why the request debugger was built.

**Proposal** (no ADR change expected): give `.authority` a closed reason, and split
`OperationExecutionFailed` into specific causes at their owners. Keep typed outcomes
and terminal precedence unchanged.

The open failure-evidence gaps of former R9 belong here:

| Confirmed gap | Owning boundary and required change |
| --- | --- |
| Evaluator partial bodies disappear | [Observation](../test/harness/provider.zig#L19) lacks completeness and error-exit evidence. [Bedrock](../test/harness/bedrock.zig#L52) omits the transport's failure-body slot. [OpenAI HTTP](../test/harness/http.zig#L95) loses prefixes on read failure. [The trace](../test/harness/evaluation_trace.zig#L23) records only a thrown error. Thread retained bytes and completeness through the shared observation, with redaction and adapter-to-trace fault tests. |
| Simultaneous failures overwrite earlier causes | [Accounting](../src/application/workflow_model_invocation.zig#L24) can supersede an invocation cause, and [runner capture](../src/application/workflow_pipeline_runner.zig#L410) can supersede it again. Retain bounded primary and secondary evidence, preserving terminal precedence, ownership and allocation-failure handling. |
| The loss-localization call origin is not retained separately | [`collectLoss`](../src/domain/specification_support.zig#L369) keeps the original finding origins, so diagnostics can name the finding call instead of the localization call. Preserve both associations through collection, correction, repair authorization and reporting. |

Two further limits:

- Build snapshots capture allowlisted Git-visible bytes; they don't prove that the
  compiler consumed exactly that snapshot under concurrent edits.
- Progress labels include routine invalidation and retirement, so don't count every
  progress event as a semantic repair.

### A5. Tests pin structure and cannot see semantic failure

- Of 79 architecture tests, 69 pin specific files, with 420 source-text assertions.
  `src/architecture_test.zig` changed in 63 of 199 commits.
- The integration [driver](../src/test_fixtures/spec_generation_driver.zig#L185)
  threads about 40 fault flags into a hand-scripted
  [741-line response builder](../src/test_fixtures/spec_generation_responses.zig#L121).
  The two files changed 53 and 46 times respectively.
- Test code exceeds production code.

None of these tests can detect the semantic failures that block publication. Only
live runs can, and those are rare and billed.

**Proposal** (no ADR change): when the affected tests next change, express
architecture rules as import-graph and contract-shape rules instead of per-file pins.
Prefer replaying retained real captures over extending scripted responses, as the F10
admission replay and the exact-value prototype already do.

### A6. Contracts change faster than evidence accumulates

- There were 22 ADRs between 26 August and 6 October.
- Design and fix records saw 139,051 lines written and 91,493 deleted.
- Phases 1A.2 and 1A.3 were each opened by a single hello-world run, while
  near-identical requests produced opposite failures (F13).

AGENTS.md requires every fix at the shared owning contract, with no backward
compatibility, so each amendment becomes a large cross-cutting diff.

**Proposal:** apply the evidence rules in §7 to every contract change.

**Decision** (scope): add no contracts for Plan, Tasks or Implement until Specify
publishes on both development cases.

## 3. Why runs are brittle

### B1. A long fail-closed chain of model judgments

Publication requires the whole workflow to pass every validator across 40 or more
sends. As an illustration, not a measurement: if each call produced acceptable
output 97% of the time after its retries, 41 calls would succeed together about 29%
of the time; at 95%, about 12%. Splitting work into more calls lengthens the chain
unless each call's success rate rises enough to compensate (former F5 and F7).

**Proposal:** treat call count per feature as a reliability cost. B2–B5 each shorten
the chain, as do the W1, W3 and W4 workflow changes (§4). Judge progress by useful
completion per attempted workload (§7), never by
per-call admission.

### B2. Review dominates cost and drives harmful repair

Evidence from former F9 and F13, and FIX01 R5 and R6:

- **Cost.** Review took 29 sends and 77% of tokens at 09:18, and 29 sends and 76,224
  tokens (75.6%) at 20:33. Four of the five runs that reached review stopped on the
  budget.
- **Task shape.** The same 20B model judges its own output, mostly one field per
  call (21 singleton `finding` sends at 09:18). It must choose among seven finding
  types under nested conditional rules
  ([support.prompt.md](../design/workflows/spec/support.prompt.md),
  [contract](../src/domain/specification_support.zig#L13)).
- **Wrong finding types.** Every reviewed run had them. Omissions were reported for
  invented or unsupported content, and all five 08:09 loss comparisons returned
  `lost` for those non-obligations.
- **Harmful repair.** At 20:33 a repair wrote "The application must start
  successfully" into an acceptance criterion's Given, so the precondition assumed the
  result under test, and re-review accepted it.
- **Panel result.** The 30-call actual source-review panel passed 15/26 faithful
  omission handoffs, 2/2 supported controls and 0/2 genuine-gap controls
  ([results](../test/calibration/source-loss-attribution/bound-preservation/citation-completeness/handoff-results.md)).
- **B3 baselines, 17 October.** These classes recur on cleanly admitted content:
  - review took 76.1% of loan-renewal's tokens;
  - it judged byte-identical relationship text both `supported` (call 29) and
    `candidate_omission` (call 35);
  - it accepted an obligation-strength change as faithful (B7).

  39.5% of the review cost went on records duplicated by the token-only batch (B5).

**Decision** (amends §17.3 and §22):

1. Review a whole unit or collection per call.
2. A finding that deterministic evidence doesn't corroborate becomes a note, a
   clarification or an input to regenerating the unit. It never triggers an
   automatic content repair.
3. Optionally assign review to a separately configured assessment model
   (`models.slots.assessment`; former FIX02 and FIX03 Phase 9). This needs the
   proposed ADR 0021 and configuration amendment, and qualifying it live needs a
   changed live-test policy.

**Approval — 17 October 2026; implemented and verified offline:** following the B3 live
baselines, the user approved B2 and W1 together, including W2's deletion of the
unused post-generation upstream-repair path. The user explicitly selected
**“All post-generation semantic reviews”**, including principle review. Batch
whole units or collections while preserving native per-subject association,
correction scope, origins and retry identity. All post-generation semantic findings
remain advisory: they cannot authorize content repair or an automatic upstream
rebuild, manufacture a mandatory Plan obligation, or manufacture a clarification.
Current native facts, authority-completeness checks and genuine supported human
decisions remain mandatory. The separate assessment-model/configuration option,
budget changes and further live calls are not authorized by this approval.

**Approval — 18 October 2026 (record families):** after the 15:33 loan-renewal run
spent 80,901 tokens on per-record advice, the user approved amending ADR 0023 and
§17.3 so source review assigns one record family per call, with feature collection
subjects kept separate, one protocol-correction allowance and atomic stop per family,
`specification-state` advancing to v19, and the budget and reviewed record kinds
unchanged. The user also chose to send each Bedrock model's documented maximum output
from its provider configuration, because Bedrock otherwise stops GPT-OSS-20B at 4,096
output tokens (§1) and a 21-record family needs about 5,800. That needs an ADR 0011
amendment. Neither is implemented yet.

**Additional approval — 17 October 2026:** the user approved source-only positive
readiness evidence before an authored candidate exists. The native source-purpose
role requires explicitly selected nonempty original source IDs and empty canonical
claim, citation and clarification selections, independent of catalogue size.
It retains model-assisted source authority without creating authored associations.
[ADR 0023](../design/decisions/0023-advisory-post-generation-review.md) governs the
shared packet/decoder/admission/readback rule and pre-generation repair closure;
generated-content provenance checks remain unchanged. This approval authorizes
no further billed diagnostic.

**Implementation and offline verification — 17 October 2026:**
[ADR 0023](../design/decisions/0023-advisory-post-generation-review.md) is implemented.
Native assessment completion retains all source/principle verdicts as advice,
with complete canonical review units and per-member origins. Post-generation
upstream/omission repair routes and duplicate merges are deleted. Native phase,
projection-lifetime and active-permit guards preserve required pre-generation
repair, including its original dependent review after sources become ready.
The approved source-only readiness rule is shared across packet, decoder,
admission and v16 stored validation; it creates no authored support.

| Verification command | Result |
| --- | --- |
| `zig build test-specification-generation test-model-candidate-json -j1 --summary all` | 6/6 steps; 477/477 tests |
| `zig build test-required-authority test-model-result-schema test-model-request-preparation test-workflow-repair-retry test-exact-value-admission -j1 --summary all` | 15/15 steps; 435/435 tests |
| `zig build test-integration -j1 --summary all` | 8/8 steps; 122/122 tests; all 164 original and 19 additional scenarios |
| `zig build test-architecture -j1 --summary all` | 3/3 steps; 151/151 tests |
| `zig build verify -j1 --summary all` | 163/163 steps; 1,814/1,814 tests, including clean native packaging smoke |

The independent `contract-reviewer` found no remaining findings. Final logs and
hashes are retained in `.zig-cache/b2-validation-manifest.json`; integration's
complete matrix is recorded in `.zig-cache/b2-advisory-integration-14-summary.json`.
These checks prove offline mechanics, not publication or output quality. The
separately approved committed-build comparisons are recorded below.

**Committed-build live comparison — 17 October 2026:** the user separately
approved exactly one hello-world and one loan-renewal diagnostic on
`b4c7b07f792d88a6ae2639bef2e0600a029a2a24`. Both ran once from a clean detached
checkout; captured provenance reports `modified: false`, Zig 0.16.0, and source
hash `792f1266c53668831977ceea8a4c923b028b4ea1d4e6fc417f1fa4c3531cae47`.
The launch commands were unchanged:

- `./scripts/e2e-spec.sh --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json`
- `./scripts/e2e-spec.sh --case test/e2e/wf-002-loan-renewal/workflow.case.json`

| Build / case | Accounted calls | Workflow tokens | All review tokens | Terminal outcome |
| --- | ---: | ---: | --- | --- |
| B3 `dfae959` / hello-world | 12 | 18,757 | 0; not reached | Blocked: duplicate / competing records |
| B2/W1/W2 `b4c7b07` / hello-world | 11 | 17,754 | 0; not reached | Blocked: duplicate / competing records |
| B3 `dfae959` / loan-renewal | 38 | 101,933 | 77,537 (76.1%) | Failed: workflow token budget |
| B2/W1/W2 `b4c7b07` / loan-renewal | 10 | 32,333 | 0; not reached | Failed: provider `output_limit` |

Hello admitted and advanced the first prose record batch, including native exact
recognition, then rejected a byte-identical repeated user-visible outcome as
`duplicate_record` / `competing_records`; repair authorization returned
`UnsafeSpecificationRepair` with `blocked`. No repair occurred. Its complete
observed admission audit contains 14 values from 8 producers, five canonical
exact witnesses, and zero escaped or unattributed values.

Loan stopped before records were collected: the provider returned
`stopReason=max_tokens`, with 16,384 output tokens against the requested 16,384
limit. Its complete observed audit contains 9 values from 7 producers and zero
escaped or unattributed values, but **no exact witnesses**. Both original
inline-code candidates had been classified `irrelevant`; the admitted message
strings remained literals. This is an upstream classification observation, not
a counted native admission escape. This attempt neither exercises native exact
recognition nor proves original-source token preservation.

Both runs stopped before any semantic review finding, publication or rubric
evaluation. Review cost effects and finding-type accuracy are **unmeasured**;
the lower totals reflect different execution coverage and do not establish B2
savings, semantic benefit or reduced brittleness. No baseline label is transferred
to a changed candidate. Both per-run approvals are consumed. Under §7, retain the
generation failures as baseline evidence; do not open another rewording sub-phase
or automatically rerun.

The new reports are retained at:

- `zig-out/e2e-spec/2026-10-17T00-38-56Z-f26b1f0f123016ca419a66968d79addf/report.json`
- `zig-out/e2e-spec/2026-10-17T00-39-51Z-9210b2b21f83c723235fef18c6eed60e/report.json`

`zig-out/b2-live-diagnostics/manifest.json` hashes the retained artifacts;
`zig-out/b2-live-diagnostics/accounting.json` records all four runs using exact
captured native workflow routes, unique accounting origins, complete usage and
explicit unknown handling. Its SHA-256 is
`a1a9918b20b12d756c9db49ff979d686cee537f25338a8f639bd28deb4817269`.
The offline analysis command is
`python3 .zig-cache/b2_diagnostic_analysis.py <retained-run-directory>`;
its SHA-256 is `1221b14d94d19a03a60e04733dbc507ce65d566697becd5758697da6e063a572`.
It counts all pre-generation and post-generation semantic review/correction
work when present, keeps evaluation outside workflow spend, and does not alter
frozen B3 artifacts. Independent read-only audit confirmed the native failures,
admitted-value scope and absent review evidence. B2/W1/W2 is implemented and
verified offline; its live review benefit remains unproven.

Measure the review workload (former R5): coverage, sends and actual tokens per stage,
latency, retained memory and finding-type accuracy (§7).

- Don't discard policies by keyword, truncate required evidence or add local token
  ceilings.
- Don't claim that raising the budget fixes reliability.
- Group subjects only with evidence that per-subject findings, association,
  correction scope, origins and retry identity survive.

If the current review contract is kept, the next bounded work is the former R6
source-review direction. The reviewer sometimes checks only candidate clauses that
match sources, and sometimes promotes candidate additions into source requirements.
Clarify original-source authority, the candidate target and completeness for the
assigned field purpose through the existing shared purpose and evidence owner. Then
prepare a controlled actual-review comparison using these failures plus unrelated
controls. Further calls need bounded approval.

### B3. Exact-value bookkeeping is left to the model

**Approval — 17 October 2026:** the user approved B3, first settling the offline
requirement-binding and punctuation rules, with B2 and W1 to be decided separately.
The user then explicitly approved both concrete choices from the
[offline policy comparison](../test/calibration/exact-value-recognition/README.md#b3-policy-comparison--17-october-2026):

1. Recognize current native request-eligible exact occurrences even when their
   claim IDs are outside selected support `S`; derive `E` while preserving `S`.
2. Use contextual complete-value delimiters: actual field edges, Unicode
   whitespace, balanced enclosing wrappers and terminal prose punctuation before
   a delimiter. A reference-adjacent literal-run edge is not a field edge.

The coordinated native implementation is complete and verified offline. Governing
amendments are recorded in [ADR 0020](../design/decisions/0020-derived-exact-reference-lineage.md#native-exact-value-recognition)
and the [composition contract](../design/contracts/text-field-composition.md#native-exact-values).

**Offline completion checks — 17 October 2026:** the final ladder passed in order:

```sh
zig build test-exact-value-admission test-exact-value-replay test-model-request-preparation test-model-request-workflow test-model-envelope test-model-candidate-json test-specification-generation test-workflow-repair-retry -j1 --summary all
zig build test-architecture -j1 --summary all
zig build verify -j1 --summary all
```

The targeted run passed **26/26 steps and 1,151/1,151 tests**; architecture passed
**3/3 steps and 151/151 tests**; full verification passed **163/163 steps and
1,819/1,819 tests**, including integration, schema and clean native packaging
smoke checks. `git diff HEAD --check` also passed. Logs are
`.zig-cache/b3-final-targeted.log`, `.zig-cache/b3-final-architecture.log` and
`.zig-cache/b3-final-verify.log`.

**Production-admission replay:** `zig build test-exact-value-admission -j1 --summary all`
repeats the integration check and writes
`.zig-cache/exact-value-production-admission/report.json` (SHA-256
`5e07666a28f749784c70dd6ca694e2c1736f88332af6067f4cdb0a2869c0640a`).
The [replay record](../test/calibration/exact-value-recognition/README.md#current-production-admission-replay--17-october-2026)
documents the immutable raw bytes and explicitly fresh, scripted native context:

- 16:20 insertion-only title: typed `prohibited_exact` rejection.
- 18:58 collapsed records: typed `reference_only` rejections.
- 20:22 prose values: admitted with unchanged `S`, one added exact claim and two
  behavioral exact-coverage targets; canonical stored validation also passes.
- 22:00 insertion syntax in prose: typed `embedded_insertion_syntax` rejection.
- An unrelated, explicitly scripted loan control admits through the same native
  path. It is not a live or retained loan-run result.

Admission escape is **zero among the four actually replayed captures**. The
20:33 run's raw capture and its inventoried mirrors could not be found; the report
retains its exact execution identity as unavailable, not a fifth replay success.
It introduces no distinct B3 admission class beyond the admitted-generation
control, but its harmful review/repair and later budget failure are not reproduced
or claimed resolved. Historical descriptions remain historical observations;
their metadata is not promoted into current request authority.

**Independent review:** the `contract-reviewer` reviewed the complete B3 diff and
the production-admission additions. No contract findings remain. Its reported
test-helper diagnostic-path lifetime defect was fixed before the final checks.

The shared recognizer, native request scope, response composition, value and
membership repair bounds, progress comparison and stored readback are integrated.
Completed/pending state now use `specification-state/v15`; current diagnostic
requests use `model-request-debug/v6` (since advanced to v8, §11 and §14). Superseded contracts reject; frozen older
captures remain historical observations and cannot acquire current authority.

**Approved live baselines — 17 October 2026 (AEDT):** both separately approved
diagnostics ran on clean committed `dfae95968a555892b0821684c2436229e0b6de5f`, captured
source digest `45646203775fd3598deb9bd6089875250ded59b4928f74b29160e61f1f882529`.
The user's B3 PASS criterion was admitted prose records **or** a bounded typed
composition failure/correction, with admission escape zero. Both runs admitted
records from ordinary model prose and meet that local mechanical gate. **The B3
mechanical live gate is closed.** Whole-workflow publication, semantic benefit and
reduced brittleness remain unproven; neither run published or reached a semantic
rubric result. No further live run is authorized by this result.

| Baseline and retained report | Outcome | Sends / actual tokens | Observed admitted values / origins / escapes |
| --- | --- | --- | --- |
| [Hello-world, 16 October 22:05:27Z](../zig-out/e2e-spec/2026-10-16T22-05-27Z-83aeeb4bcf310f6fd46ca12b3e26b8fe/report.json) | `workflow_blocked`: `duplicate_record` / `competing_records`, followed by `UnsafeSpecificationRepair` | 12 / 18,757 | 14 / 8 / 0 |
| [Loan-renewal, 16 October 22:06:05Z](../zig-out/e2e-spec/2026-10-16T22-06-05Z-8425e2615767d8c8fbe3172e67479cdc/report.json) | `workflow_failed`: `WorkflowTokenBudgetExceeded` during source-loss review | 38 / 101,933 | 27 / 9 / 0 |

Both audit captures are complete for their declared
`native_admitted_text_composition_and_wire` scope, with zero unattributed values.
This measures observed native composition and wire escapes, not semantic coverage
of every original obligation. Hello-world call 11 admits the first records batch;
its selected business support is claim 1 while native exact recognition adds claim
2 for `Hello, World!`. The second batch then competes with existing records.
Loan-renewal calls 12 and 13 admit both prose records batches and reach review.
The audit retains five canonical exact-value witnesses for hello-world and six
for loan-renewal. Neither report has a typed composition failure.

| Stage | Hello-world sends / tokens | Loan-renewal sends / tokens |
| --- | --- | --- |
| Reference preparation | 7 / 8,450 | 8 / 11,997 |
| Generation | 5 / 10,307 | 5 / 12,399 |
| Post-generation review, including loss attribution | 0 / 0 | 25 / 77,537 |

Loan review consumed **65.8% of sends and 76.1% of actual tokens**: 21 source
assessment sends and four loss-attribution sends; no principle review was reached.
The 21 assessment sends produced 25 finding units (21 `supported`, four
`candidate_omission`). These are observed output types, not truth labels. The last
loss response, call 38, was received and its usage counted, but budget failure
prevented content consumption; it is not an admitted localization result.

Source-based labels, exact evidence paths and SHA-256 hashes are frozen in the
local ignored [diagnostic artifact](../zig-out/b3-live-diagnostics/source-review-labels.json)
and [manifest](../zig-out/b3-live-diagnostics/manifest.json). The strict findings
are:

- Calls 33 and 35 claim a missing relationship whose `missing_obligation` is
  byte-identical to the selected candidate text. This excludes the claimed
  omission; it does not decide `supported` versus `candidate_invalid`.
- Call 20 accepts scenario coverage although both selected acceptance criteria
  describe successful renewal only. The original source also requires refusal,
  unchanged due date and `Renewal refused.`; its scope explicitly disallows
  surrounding functional requirements from filling missing selected scenarios.
- Call 27 also describes an already-present relationship as missing, but its
  mixed obligation text makes this a supplementary source-based category judgment.
  Call 18 is a qualified coverage concern because its generic task is narrower;
  call 37 adds a relationship qualifier whose equivalence remains unresolved.
  Those three are excluded from the strict metrics; 19 other units are unadjudicated.

On the deliberately defect-selected strict slices, omission precision is **0/2**
for the exact-presence category controls, and omission recall is **0/1** for the
clear scenario-coverage omission. The slices differ and are not population
estimates; overall precision, recall and accuracy remain unavailable. The immutable
[loan relationship capture](../test/calibration/source-review-advice/loan-borrower-relationship.capture.json)
retains call 33 and byte-equality facts without assigning a semantic truth label.

The four omission findings and their following localization sends cost eight
sends and 25,474 tokens. That is observed branch cost, not proven counterfactual
savings. No specification-content repair occurred in either run; the loan's one
repair was pre-generation reference reconciliation. No review-induced candidate
rewrite or harm was observed, and there is no final candidate assessment.

One upstream baseline observation limits coverage claims: the loan's retained
dispositions mark the original `Renewal refused.` claim 3 superseded by
`Loan renewed!` claim 2. Refusal prose remains in descriptions and functional
requirements, but only `Loan renewed!` appears in the canonical exact-value
witnesses. This is retained lineage evidence, **not a new B3 admission escape**.
It does not authorize a rewording phase. B2/W1/W2 approval is recorded above and
in §6; implementation and required offline checks are complete. Both separately approved
committed-build comparisons recorded above stopped before review; their review effects
remain unmeasured.

**Diagnosis before this cutover:** the model had to splice `exact_copy` insertions into its prose, and native coverage
credits only an insertion ([coverage](../src/domain/specification_coverage.zig#L77)).
A missing insertion has no repair route
([coverage repair](../src/domain/specification_coverage_repair.zig#L60)).

Runs have failed in both directions:

- values made only of insertions, or insertion syntax typed into prose (F10–F12, and
  again at 22:00 as `embedded_insertion_syntax`);
- values typed out with no insertion (F13, which blocked at coverage after 14 calls).

The presentation contradicts the rule: insertions "may supplement" prose and exact
copies "may carry" the obligation
([text_field_policy.zig](../src/domain/text_field_policy.zig#L75),
[:105](../src/domain/text_field_policy.zig#L105)), while coverage requires one.
Near-identical requests produced opposite failures. This contradicts the
[intent](../design/intent.md) that bookkeeping belongs to deterministic code. It also
supersedes the former R6 item 4 candidate of a simpler shared business-value
representation.

**Approved decision** (amends the [composition contract](../design/contracts/text-field-composition.md),
§7.1 and ADR 0020): recognise exact values natively.

- The model writes plain prose.
- Native code recognizes raw exact bytes before NFC in the current snapshot/request
  eligible occurrence scope, using the approved contextual delimiter policy.
  Competing lineages or overlapping eligible spans reject the whole field.
- Canonical exact nodes, field roles and repair evidence bounds remain; `S` is
  unchanged and recognized `E` contributes through the existing lineage owner.
- `exact_copy` leaves model-facing types, codecs and schemas.

The [offline prototype](../test/calibration/exact-value-recognition/README.md) replays
every retained capture with no model calls
([evidence](Z_FIX02.md#546-offline-native-exact-value-recognition-prototype)). Its
selected-membership and whole-word observations remain dated historical evidence;
the approved native scope and delimiter policies supersede them for production.

Open gates of the former Phases 1A.2 and 1A.3
([approved plan](Z_FIX02.md#phase-1a3-plan-and-decisions-as-approved)):

- The approved representation change replaces Phase 1A.3 steps 2–3: the
  21-send [attribution panel](../test/calibration/insertion-presentation/README.md)
  and the presentation rewording. Its implementation must address the mechanical
  coverage block without claiming semantic fulfillment.
- Close the live gate on a committed build with one separately
  approved hello-world diagnostic and one loan-renewal diagnostic.
  - Each must admit records with prose, or end in a typed composition failure after
    bounded protocol correction, with admission escape measured zero.
  - This also closes Phase 1A.2's gate.
  - At that historical gate, loan-renewal had not run since Phase 1A. The separately
    approved committed `dfae959` baseline above supersedes that absence; it does not
    establish publication or semantic benefit.
  - The two F13 hello-world runs count only if no further presentation or
    representation change follows.

### B4. Fixed per-call overhead exhausts a compiled budget

**Approved amendment — 17 October 2026:** the user selected post-R8 option 3
below. Option 1 was recorded here as selected in error; the user did not request
it, and it is withdrawn (see the removal record below). One 100,000-token total
budget covers all model work. Eligible service stops,
provider output stops and exhausted existing protocol correction produce explicit
incomplete advice; security, cancellation, deadlines, logging, native validation
and required-work failures remain terminal. Principle review assesses the whole
current subject set for one selected principle set in one assignment. Current
implementation and verification are recorded in [§9](#9-b4b9-implementation--17-october-2026).
The earlier budget/scope choices below are retained as proposal history; no
baseline freeze or live call is authorized by this implementation.

Input is 93% of tokens. Review sends average about 2,500 input tokens for
single-field subjects. The four response schemas are 11.9–14.1 KB each, with 15–32
definitions.

The 100,000-token budget is compiled into every policy profile
([core](../src/composition/core_workflow_operations.zig#L35),
[native](../src/composition/native_workflow_operations.zig#L638)); it is not case
configuration. The protocol's experiment-wide stops of 1,000 sends and 2,000,000
tokens cover fewer than 20 such workflows, against 144 development workloads. The
Phase 2 budget-feasibility report is `insufficient`.

**Decision** (required before any baseline freeze): choose the budget and scope. The
options are:

- raise the workflow budget, or make it a workflow or configuration parameter,
  through an explicit engine contract change;
- revise the experiment stops before freezing, with a recorded rationale;
- reduce review or repair cost through its owner (B2);
- narrow the qualified scope.

The former recommendation was generation-only diagnostic scope for Phases 2–3, with
controlled predecessors, deferring complete-workflow qualification until review
qualifies. Separately, measure the prompt, schema and evidence token contributions
per call before trimming anything. Add no local size ceilings (ADR 0011).

**Post-R8 evidence — 17 October 2026.** The first post-R8 hello-world run produced
faithful-looking content, then spent 89,283 tokens (86%) on advisory review and ran
out of budget in principle review (§1). Under ADR 0023 those findings can't change
the specification, so the budget is now being lost to work that cannot affect the
output. Options, each needing a decision:

1. **Separate allowance for advisory review.** When review exhausts its own
   allowance, it stops and records incomplete advice. Publication then proceeds on
   the native gates. This amends ADR 0023, §17.3 and this budget contract.
2. **Configurable review.** Make post-generation semantic review a configured stage,
   as `sourcePreservationCheck` already is for pre-generation review. Development
   cases would then judge quality through R8's rubric and human adjudication.
3. **Cheaper principle review.** Send the principle corpus once per call batch, or
   assess all subjects of a principle set in one call. Today every call resends
   seven documents (about 6,800 input tokens).
4. **Raise the workflow budget.** This alone leaves advice deciding whether anything
   publishes.

**Removal record — 17 October 2026.** Option 1 was recommended in this record and
then recorded as approved, but the user did not request it. It is withdrawn: **there
is one total limit**.

- **The single budget:** all model work, including post-generation advice, counts
  against one 100,000-token workflow budget under
  [ADR 0011's "Workflow token accounting"](../design/decisions/0011-provider-owned-request-limits.md#workflow-token-accounting).
- **Reaching it during review:** the workflow ends with `WorkflowTokenBudgetExceeded`,
  as in the post-R8 hello-world run. Advice is not marked incomplete.
- **What stays:** option 3, one assignment per complete principle set, and the
  advisory stops for provider output limits, provider failures and exhausted
  protocol correction, which aren't budget stops.

Governing documents updated to the single limit:

- ADR 0011 and ADR 0023;
- design invariant 32 and §31;
- contracts 12, 22 and 27;
- [e2e.md](../design/harness/e2e.md) and [acceptance.md](../design/harness/acceptance.md).

**Code removal complete.** The B4 option 3 and B9 implementation now uses the
single global budget and passes the corrected verification in §9. Removed:

- the 20,000-token advisory allowance in the policy profiles;
- the `allowance_exhausted` and `allowance_exceeded` stops in
  `workflow_token_budget.zig`, `advisory_completion.zig` and `required_authority.zig`;
- per-pool accounting in `workflow_token_accounting.zig`, its runner,
  `check-workflow-token-budget` and `reconcile-workflow-token-usage`;
- the per-pool report and feasibility fields in `test/harness/e2e/` and
  `test/harness/baseline/`;
- the tests that assert any of these.

The native advisory classification stays only where the non-budget advisory stops
still use it.

### B5. Authoring follows mechanical source groups

Evidence from former F1, F9 and F13:

- Each record batch re-authors the whole feature, which produced competing or
  duplicate records in four runs.
- The group holding only a preserved value gets its own batch.
- One assignment can still require interpreting obligations, choosing record
  families, preserving conditions, building scenarios and entities, and deciding
  whether uncertainty blocks drafting.
- Six model requests precede authoring even on a three-line source.

**Token-only record batches: B3 baseline evidence, 17 October.** In both B3
baselines, the second record batch was assigned only a preserved token, with no
behaviour to author: `Hello, World!` in hello-world and `Loan renewed!` in
loan-renewal. Each time the model re-authored the whole feature:

- in hello-world, as an exact duplicate that blocked the run;
- in loan-renewal, as near-duplicates. Reviewing them took 10 of 25 review calls and
  30,651 tokens (39.5% of review), plus 3,952 generation tokens.

The cause is native. [`recordCount`](../src/domain/specification_source_binding.zig#L131)
counts every question-eligible group, while
[`tokenOnly`](../src/domain/specification_source_binding.zig#L30) only shapes the
request presentation. Since B3, the behavioural batch already carries those values:
hello-world's first batch admitted `Hello, World!` as a recognized exact occurrence.
The post-B2/W1 hello-world rerun reproduced the block exactly, so it has now occurred
in 2 of 2 runs since B3 (§1).

**Decision** (amends the §17 record assignment and ADR 0020): don't schedule a record
batch for a group whose claims are all preserved tokens.

- Other records must carry those values as recognized occurrences.
- If they don't, the existing exact-coverage check blocks with a typed outcome.
- Test accepted and rejected cases at the session owner, including a token that no
  behavioural record mentions.

This is narrower than the A/C comparison and should come before the baseline.

**Approved implementation — 17 October 2026:** the user approved B5 together
with B8 under [ADR 0024](../design/decisions/0024-native-exact-token-authority.md).
The shared binding owner now excludes complete, nonempty all-preserved-token
groups from record count, dense iteration and direct group binding. Mixed groups
and every other semantic claim class retain their existing eligibility. Full
content/question catalogues, original signal IDs, exact recognition scope,
provenance and aggregate coverage remain intact. Existing obligation-bearing
narrative or record fields may satisfy an exact duty; incidental fields cannot.
Missing duties retain the typed `missing_exact_copy` failure. A nonempty token-only
catalogue blocks with `no_record_authoring_groups`, distinct from `empty_catalogue`;
it does not manufacture an empty checked unit. Current calibration preparations
identify scheduled seeds by native signal ID and report excluded historical seeds
without editing frozen inputs. Owning regressions and the required offline checks
passed; the B8 verification record below records commands and results.

**Proposal:** compare current per-group records (A) with one complete record
collection (C). Add a purpose-only acceptance-criterion diagnostic (B) or per-family
collections (D) only where measured failures justify them. Run it after B2 and B3,
which change every arm and dominate cost.

| Former phase | Status |
| --- | --- |
| 0 Evaluation protocol | Complete offline: [protocol, cases, specimens and scoring](../test/calibration/semantic-simplicity/README.md) |
| 1 Compatible execution | Live gate passed for the observed first request only ([record](Z_FIX02.md#phase-1-implementation-and-live-gate)) |
| 2 Baseline | [Harness](../test/harness/baseline/cli.zig) implemented; not frozen; needs B4's decision, B3's gate and a committed build |
| 3–6 A/C comparison, implementation, qualification, adoption | Not started |

Constraints carried from former F1–F8 and FIX04 §§4–5:

- Historical same-model panels ran under superseded contracts. They identify failure
  classes, not today's defect rate, so capture a fresh baseline on a frozen committed
  revision.
- Separate an oracle-premise capability test from a production handoff test.
  Evaluation expectations never enter generator inputs.
- Batching findings into one call, narrowing the semantic question and removing a
  required finding are different changes. Only the last changes authority.
- C needs disclosed, validated per-record support selection. Never bind every record
  to every group or discard lineage to make it pass.
- If C or D is selected, the production contract must define finite native
  assignments, complete content units, explicit supporting groups, exact assembly
  with origins, currentness and bounded correction, and it must keep every
  completion gate.
  - Generation parsing, session admission, provenance and readback, omission
    comparison and insertion, and entity ownership change together.
  - Replace superseded readers rather than keeping compatibility.
- If the baseline already meets the protocol's adequacy targets, retain it and stop
  the redesign.

### B6. Secondary failure classes to measure

- Extraction merging requirements is now tracked as B7, because both B3 baselines
  show it.
- The GPT-OSS envelope-prefix malformation (`{"token{`) recurs. It recurred at
  hello-world call 2 on the B3 build, and the protocol retry corrected it.
  **Resolved 18 October 2026:** the user approved normalizing the truncated
  member-name form after it appeared in 6 of 20 source-review responses in one run,
  causing 5 retries and one exhausted assignment (§12).
- Before B3, entity applicability was marked required for a feature with no business
  data, and the entity-name exception then admitted an insertion-only name. No native
  rule can judge applicability. Both B3 baselines judged it correctly:
  `not_applicable` for hello-world and `required` for loan-renewal.

Measure each as its own class in the baseline. Don't widen the normalizer or narrow
the entity-name exception without a decision.

### B7. Extraction collapses structured sources and weakens obligations

Evidence from both B3 baselines:

- **Collapsed lists.** Both sources are Markdown bullet lists of distinct
  requirements: three items in hello-world and five in loan-renewal. Extraction
  returned one claim for each whole list, citing lines 5–7 and 5–9. Hello-world has
  done this in every sample since Phase 1A.
- **Weakened obligation.** Loan-renewal's claim turned "A borrower must be able to
  renew" into "A borrower may renew". That is an obligation-strength change, which
  the intent says extraction must preserve. The weakened text flowed into the brief
  description, the story and the first functional requirement, and review judged
  them `supported` (calls 15, 17 and 23).
- **Downstream effect.** With one behavioural claim per feature there is one
  behavioural source group, and every record cites the same claim. Coverage is
  satisfied by any record that mentions that claim, and review subjects are whole
  paragraphs. Traceability suffers, and native checks could not see the missing
  refusal scenario.
- **Reproduced after B2/W1.** All four post-B3 runs collapse the list, and both
  loan-renewal runs write "may renew".

**Proposal** (measure first; then **Decision**, amending the §16 chunking and
extraction contracts): segment structured sources natively, starting with Markdown
list items, so the model extracts one requirement at a time instead of deciding how
to split a chunk. Source structure is deterministic, so this follows B3's principle.

First, replay both cases' retained extraction requests split per item, with
repetitions under bounded approval. Score claim count and obligation-strength
preservation.

### B8. The model classifies and disposes exact-value tokens

In the B3 baseline, loan-renewal's reconciliation asked the model to dispose its two
preserved tokens:

- **First attempt.** It marked both as duplicates of the business claim. Native rules
  rejected that, which cost two repair calls; calls 4–6 together used 4,100 tokens.
- **Repair.** The repair for `Renewal refused.` offered `retained` or `superseded` by
  claim 2 (`Loan renewed!`). The model chose `superseded`, and native rules accepted
  it because both claims are preserved tokens.
- **Consequence.** `Renewal refused.` lost its canonical exact-value witness (recorded
  under B3).

Exact tokens are byte facts. Whether two tokens are duplicates is computable. Whether
one distinct value supersedes another within a single source is a judgment the small
model got wrong here.

**Post-B2/W1 rerun, 17 October.**

- Token classification marked both inline-code values as `irrelevant`, even though
  extraction's admitted claim contains both strings verbatim ("displays the message
  "Loan renewed!"").
- Native forcing applies only when the extraction outcome forces a classification
  ([forced classifications](../src/actions/reference/construct_forced_token_classifications.zig)),
  so this was the model's free choice, and nothing checked it.
- The baseline run's same step had preserved both values.

Loan-renewal has now lost exact-value obligations in both post-B3 runs, each time
through a different model bookkeeping step.

**Decision** (amends the §16 extraction and reconciliation contracts and ADR 0020):
native code owns preserved-token bookkeeping.

- A token candidate whose exact bytes appear in an admitted business claim from the
  same chunk can't be classified as `irrelevant`; native code preserves it.
- Among preserved tokens, identical bytes are duplicates; any other token is
  retained.
- The model disposes only business claims.
- A genuine change of value across sources remains a business-claim conflict.

**Required pre-implementation capture audit — 17 October 2026:** the bounded
offline scan covered 107 captured contexts, 49 project prompt archives and two
retained calibration bundles. After separating provenance and removing archive
aliases, it found:

- 13 actual-provider current E2E exchanges containing nine classification decisions
  (seven `preserve`, two `irrelevant`) and seven token dispositions (four
  `retained`, two `duplicate`, one `superseded`). Multiple decisions may share one
  exchange.
- 17 archived provider-shaped exchanges with unverified live provenance, containing
  eight `preserve` classifications and nine `retained` dispositions. These are a
  separate evidence class, not additional verified live runs.

No correct, non-obvious model token decision was found. All recovered values were
`Hello, World!`, `Loan renewed!` or `Renewal refused.`, and all preserved kinds were
`business_exact_string`. There was no retained counterexample for legitimately
irrelevant code/link/fenced material inside a business claim, equal bytes with
different kinds, Unicode normalization or genuine cross-source value conflict.
Malformed-response suffixes record intentions only; scripted upstream fixtures and
semantic-review calls do not establish token-decision correctness. This scan is
not a population accuracy estimate or proof of universal semantic correctness.

The immutable ignored diagnostics are
[the inventory](../.zig-cache/b5-b8-capture-audit.json), SHA-256
`733ef4456f1de384caea8707e56691fc04d81e9314a59fe9efe9f9afd0594217`, and
[the audit note](../.zig-cache/b5-b8-capture-audit.md), SHA-256
`782ce2ffd6618cd284685f5fdce54323c8692f659c191ea8b88b56f35166afc3`.
They retain their pre-decision limitations and grant no runtime authority.

**Approved implementation — 17 October 2026:** the user subsequently settled the
audit's open boundaries and approved [ADR 0024](../design/decisions/0024-native-exact-token-authority.md):

- Exact captured bytes appearing in a literal run of canonical, already validated
  business or scope-constraint prose from the same original chunk force
  preservation. Literal fragments may join; passive/source insertions remain
  opaque. Case, whitespace and Unicode bytes are significant. This is substring
  matching of canonical prose after its existing NFC validation, separate from
  B3's contextual complete-value recognition.
- The model still selects semantic kind. A native appearance duty survives every
  kind, so choosing a weaker kind cannot remove required exact coverage or
  occurrence eligibility. Unmatched candidates keep existing semantic rules.
- Preserved tokens with identical bytes use the earliest original claim as the
  retained representative and direct duplicate edges for later occurrences,
  regardless of source or kind. Every original occurrence, citation and duty
  remains; a representative cannot weaken a duplicate's obligations. Distinct
  byte sequences remain retained.
- The model disposes all existing extracted semantic claim categories
  (`content.model`), with native token dispositions supplied only as facts.
  Token subjects, relationship targets and coupled conflict groups are excluded
  from model authority across initial admission, repair and source-omission paths.
- Completed and pending state advance to `specification-state/v17`. Readback
  recomputes candidate/classification/token accounting, native dispositions,
  duplicate identity and complete original-occurrence coverage. Earlier versions
  reject without migration or a compatibility reader.

**Offline verification completed — 17 October 2026:**

| Command | Result |
| --- | --- |
| `zig build test-specification-generation test-reference-extraction test-structured-tokens test-reference-reconciliation test-reference-model-input lint -j1 --summary all` | 979/979 tests; lint passed. |
| `zig build test-architecture -j1 --summary all` | 151/151 tests passed. |
| `zig build test-integration -j1 --summary all` | 122/122 tests passed; main workflow matrix 164/164 scenarios. |
| `zig build verify -j1 --summary all` | 163/163 steps; 1,826/1,826 tests passed, including clean packaged-executable smoke and offline network guard. |
| `git diff --check` | Passed. |

The `contract-reviewer` reviewed the complete diff and final fixture corrections;
no findings remain. Regressions exercise native preservation across every kind,
canonical literal/reference boundaries, byte-only cross-source duplicates,
original occurrence/citation duties, representative-only recognition without
support expansion, sparse record assignments and typed zero-authoring rejection,
repair boundaries, v16 rejection, full v17 readback and forged/missing obligations.
Calibration inputs and historical observations remain frozen; current preparation
records report their actual new admission population and excluded assignments.

No live rerun, budget change, new rewording phase or broad semantic quality claim
is authorized by this entry. These checks establish offline mechanics. Earlier B3
counts and live observations remain unchanged.

### B9. Model output can run away

**Approved amendment — 17 October 2026:** author entity records once per feature
with their applicability decision; non-entity record batches cannot emit them.
The 2,048-token generation and repair allowances were withdrawn on 18 October 2026:
no request carries an output-token allowance (§11). No array-cardinality ceiling or
additional retry is approved.
Required `output_limit` remains a typed failure; advisory `output_limit` ends
advice as incomplete under B4. [§9](#9-b4b9-implementation--17-october-2026) records
the implementation and offline evidence; the proposals below are historical.

Evidence:

- **Runaway batch.** The loan-renewal rerun's only record batch produced 286 entity
  records, most of them invented and increasingly degenerate, until it hit the
  provider's 16,384-token output limit (call 10).
- **Runaway review, post-R8.** The next loan-renewal run's third source-review call
  broke its JSON close and then emitted about 48,500 characters of blank lines until
  the same limit (call 13, 20,587 tokens). Runaways have ended 2 of the 3
  loan-renewal runs since B3, at two different stages.
- **No bound.** The records schema places no bound on the array, and every record
  batch may author entity records.
- **Same family, other failure.** In the B3 baseline the same entity family was
  instead duplicated across both batches (B5), costing review calls.
- **Repeated authoring.** Entity records are authored per batch, even though the
  entities unit decides applicability once per feature.

**Proposal** (measure first; then **Decision**, amending the §17 generation units):

- Author entity records once per feature, alongside the existing
  entity-applicability decision, rather than in every record batch.
- Decide separately whether the closed records schema should bound per-family
  cardinality. Whether such a bound is compatible with ADR 0011 needs an explicit
  decision; it must not become a disguised size ceiling.

Because the class now spans record authoring and review, two further choices need
decisions:

- **Lower output allowance.** ADR 0011 already permits an optional per-slot
  `maxOutputTokens`, a provider-enforced output allowance. A lower allowance bounds
  what a runaway costs, but the run still fails.
- **Bounded correction.** Decide whether a provider `output_limit` gets one bounded
  correction through the existing protocol-retry owner, as other malformed
  responses do. §7 discourages extra retries, so this needs an explicit rule, not a
  local exception.

Replay the runaway requests with repetitions to measure the rate before deciding.
Hello-world has no entities, so §7 also needs a second case that does. Don't answer
the runaway with sampling changes or extra retries (§7).

## 4. Spec workflow simplification

This section reviews [spec.workflow.yaml](../design/workflows/spec.workflow.yaml) at
`b2f10a3`. The workflow has 282 steps in 33 graphs. Of those, 157 (56%) only pass
`ok` to the next step and `failed` to the end. It has 18 model-request sites, 8 of
them repairs.

| Stage | Steps | Run-time cost in the measured runs |
| --- | ---: | --- |
| Deterministic preparation (toolchain, inputs, references) | 43 | No model calls; three subgraphs are fully linear |
| Extraction | 40 | One or two calls per chunk (classification is skipped when native code can classify it), plus text and selection repairs |
| Reconciliation | 54 | Four calls (summary, dispositions, signals and conflicts), even for a three-line source |
| Source-review gate and source-omission repair | 28 | See note below |
| Generation | 20 | Three calls plus one per source group |
| Review | 42 | 29 calls and about 77% of tokens |
| Publication and clarification | 30 | No model calls |
| Model-request plumbing | 25 | Runs on every call, plus 15 explicit release steps |

Note on the source-review row: the pre-generation review did not run in any measured
case. Both cases share a configuration with `sourcePreservationCheck: false`, and
otherwise it runs only when references aren't ready for generation. Its repair
subgraphs are shared with W1's post-generation path.

What already applies, and what to keep:

- A1 (request plumbing) and A2 (stage-level operations) apply here unchanged. A2
  covers the decision-free preparation and publication steps.
- W1, W3 and W4 also reduce model calls; W2 and W5 only reduce implementation effort.
- Keep typed outcomes, closed admission, all-or-nothing publication and
  clarification persistence as they are.

### W1. Review can restart the whole pipeline

When review attributes a loss upstream, [`review`](../design/workflows/spec.workflow.yaml#L151)
routes `more` to [`repair-upstream`](../design/workflows/spec.workflow.yaml#L888).
Its merges invalidate the whole generation session and its content
([`specification_dependents`](../src/domain/source_omission.zig#L328)). The run then
rebuilds the affected upstream stage, regenerates every unit and reviews everything
again, so one finding, possibly a wrong one, can repeat nearly the whole run.

The 10 October 14:24 run did exactly this (former FIX01 R6 evidence, at `b2f10a3`):

- its upstream repair re-inserted behaviour that had already been extracted;
- it invalidated dependent work and recreated the same description defect;
- it ended `workflow_invalid` after 44 calls and 77,818 tokens.

**Decision** (amends §22): a post-generation upstream finding ends as a typed outcome
that names the producer and the evidence, or becomes a clarification. It never
automatically rebuilds an upstream stage and regenerates every unit. Pre-generation
source repair discards no generated content, so it is unaffected. This complements
B2, under which post-generation semantic findings never authorize content repair,
and narrows R6.

### W2. The upstream-repair path exists twice

The top-level steps from
[`repair-source` to `merge-source-reconciliation`](../design/workflows/spec.workflow.yaml#L117)
duplicate the [`repair-upstream`](../design/workflows/spec.workflow.yaml#L888)
subgraph. They use the same authorization, the same repair subgraphs and the same
transitions.

The merge operations also come in pairs, with identical bodies (code-heuristics
groups 4 and 5):

- [`merge-source-extraction-repair`](../src/actions/reference/merge_source_extraction_repair.zig)
  and `merge-upstream-extraction-repair` (deleted in `b4c7b07`);
- their reconciliation counterparts.

Each pair differs only in its static invalidation set. The upstream variant adds
`specification_dependents`, which don't exist before generation.

**Approval — 17 October 2026; implemented and verified offline:** with B2/W1, delete the
unused post-generation upstream-repair path and its merge variants, bindings,
registry entries and tests. Preserve pre-generation source repair. This approved
deletion supersedes the earlier proposal to consolidate both paths into one
subgraph; no automatic post-generation rebuild remains to share it.

### W3. Eight repair routes repeat one shape

The eight repair request sites are:

- text repair;
- extraction repair;
- reconciliation repair;
- support repair;
- specification-unit repair;
- omission repair;
- source-extraction repair;
- source-reconciliation repair.

Each runs authorize, build input, request, parse, release and merge, which comes to
55 repair-related steps in all.

**Decision** (under A2, after A1): give each owning stage one repair operation that
performs its authorization, input, request, parse and merge internally. Keep every
owner's authorization and merge rules. The YAML keeps only the outcome edges.

### W4. Reconciliation always makes four calls

Even hello-world's three-line source needs two extraction calls and four
reconciliation calls before any authoring starts (B5). Reconciliation is also the
largest stage, at 54 steps. The split into summary, dispositions, signals and
conflicts was deliberate
([ADR 0016](../design/decisions/0016-configured-json-response-composition.md)), so
collapsing it needs evidence.

**Proposal** (measure first): replay retained captures to test, for small and
single-source inputs, whether separate dispositions, signals and conflicts calls
change the claims, groups or conflicts compared with one combined call. Follow the §7
rules, and count extraction's requirement merging (B6) as its own class.

### W5. Identical sibling steps

Two pairs of steps have the same target, parameters and transitions:

- [`source-gaps`](../design/workflows/spec.workflow.yaml#L164) and
  [`candidate-gaps`](../design/workflows/spec.workflow.yaml#L171);
- [`finish-native`](../design/workflows/spec.workflow.yaml#L352) and
  [`finish-model`](../design/workflows/spec.workflow.yaml#L355).

**Proposal** (no ADR change): merge each pair. Other steps already join several paths,
for example `validate-dispositions`. The incoming paths here carry different data,
though, so first confirm that the workflow compiler's data-flow checking accepts
these two joins.

## 5. Other carried open work

### R1. Group-level provenance precision

[Record binding](../src/domain/specification_source_binding.zig#L138) assigns a
complete accepted group, and [generation parsing](../src/domain/specification_generation.zig#L77)
attaches it to every returned record. Citations stay exact, but membership doesn't
mean each record expresses every linked claim. This follows ADR 0020 and is not a
defect.

**Decision:** first measure whether grouping and source review meet the intended
traceability claim. If record-specific support is required, approve one binding
change across generation, review, repair, omission insertion, readback and rendering.
Don't create a second provenance store or infer support from text matching. B5's
collection authoring would change the same binding.

### R2. Clarification answer recovery

**Confirmed implementation gap.** Fresh answers cannot complete the registered
recovery path:

- [Refresh](../src/domain/clarification_refresh.zig#L65) rejects new nonempty
  submissions with `AuthenticationRequired`.
- [Provenance](../src/domain/specification_provenance.zig#L84) rejects nonempty
  response-ID sets.
- Workflow preparation validates forms without authenticating answers, and the
  resolved-needs action constructs empty needs.
- Generation doesn't consume accepted answers.
- [Passive literal origins](../src/domain/passive_literals.zig#L16) are source-only.

Complete the [§17.4 lifecycle](../design/contracts/17-specify.md#174-specification-clarification-behavior):
authentication, response publication, current applicability, dependent invalidation,
response-owned literals, generation, review and readback.

**Decision first:** the trusted authentication source and the persistence model
(former FIX03 Phase 7: 7A decisions, 7B source-driven resolution, 7C fresh answers).
Don't treat a closed form as authenticated or fabricate reference citations.

Native [coverage](../src/domain/specification_coverage.zig#L45) cannot discover facts
that were never extracted. Keep ADR 0021's optional pre-generation source check, and
measure original-source omissions separately. Persistent semantic identity across
edits needs an explicit continuity contract, not line-number-derived IDs.

### R6. Semantic repair attribution and recovery

**Status.** Bound preservation comparisons were implemented under FIX01-01. All three
32-call comparisons failed the semantic gate; the best reached 16/16 admission and
14/16 correct attribution
([record](Z_FIX02.md#1-fix01-01--bound-preservation-comparisons-10-october-2026)). The
follow-ups ran as follows ([records](Z_FIX02.md#21-r6-follow-up-records-formerly-in-fix01)):

- explicit obligation (48 calls): failed;
- isolation (60 calls): failed;
- native-owned collections (72 calls): passed the diagnostic gates, as an admission
  gain rather than a judgment gain;
- citation completeness (76 calls): passed;
- actual source-review handoff (30 calls): failed.

**Remaining proposals.** Each needs a closed contract and coordinated tests. Re-scope
them under the approved B2 scope: post-generation semantic findings no longer drive
content repair.

1. **Source-authorized exact-reference repair eligibility** (former item 2).
   - Derive eligible choices from the target's current authorized assignment and
     omission evidence, through shared owners.
   - Preserve occurrence identity, old value, revision and dependencies.
   - Ambiguous same-text occurrences grant nothing.
   - This needs coordinated §22 and ADR 0020/0022 amendments. B3 would change it.
2. **Narrow correction of invalid loss evidence** (former item 3). The
   [support repair owner](../src/domain/specification_support_repair.zig#L94) rejects
   `invalid_loss`, and [`loss-collect`](../design/workflows/spec.workflow.yaml#L684)
   then ends the workflow `invalid`.
   - Correct malformed evidence while preserving the reviewed subject, the fixed
     omission and the current scope.
   - Use one selectable line catalogue.
   - Revalidate the corrected evidence before any content repair.
3. **Verdict reassessment** stays a separate, unapproved decision under
   [§22.1](../design/contracts/22-repair.md#221-definition-of-atomic). A proposal
   must state its trigger, current evidence, closed outcomes, one active finding, a
   stable allowance and disagreement handling. No voting or retry-until-positive.

Two recovery limits stay explicit:

- entity-applicability repair cannot change the entity decision;
- exact-reference repair cannot add an unselected claim because its text matches.

The outcome to prove is: defective description → established upstream preservation →
authorized description-only repair → impacted and full validation → continuation,
with unrelated upstream data unchanged. Genuine upstream losses must still reach the
correct producer.

### R7. Semantic reliability across models

Acceptance remains open. Explicit false `unsupported` decisions and wrong eligible
selections remain semantic errors. Automatic role reconsideration would need its own
trigger, target, invalidation and allowance contract.

The prepared but unexecuted comparisons are historical plans, not authorization:
record authoring (12 calls), signal grouping (12) and entity applicability (32)
([Z_FIX01 §9.12–§9.14](Z_FIX01.md#912-call-12-authoring-projection-and-loss-evidence-follow-up--9-october-2026)).
Verify their frozen inputs against the current candidate before proposing a run.

Broader evidence needs:

- initial, correction, repair and rebuild contexts;
- unrelated source families;
- optional and mandatory fields;
- supported paraphrases;
- negation, condition and modality changes;
- incomplete sources.

Score first-pass and recovered outcomes separately. Use repeated paired trials, with
labels kept outside prompts and separate development and held-out families. The
live-test policy permits only GPT-OSS-20B, so cross-model evidence needs a changed
scope.

### R8. Development acceptance policy

**Implemented offline. Human calibration review remains pending by user decision.**
[R8 development acceptance](../design/harness/acceptance.md) defines the shared
quality/critical gate, explicit per-case terminal outcome, grader independence
checks and hash-bound human calibration evidence. Both current cases require
publication; clarification remains a normal production outcome but cannot pass
those development cases. Lifecycle status alone no longer owns command success.

The user approved 80% aggregate with critical minimum 3/4, uncertainty unresolved,
and publication required for both source-complete cases. GPT-OSS-20B remains
advisory; explicit human adjudication of the exact published report owns acceptance.
The offline `zig build adjudicate-spec -- ...` command reapplies native mechanics
and validates the bound human rubric proposal. The paid-call policy is unchanged;
no new diagnostics or calibration calls have been authorized.

The [Hello World panel](../test/integration/fixtures/wf-001-hello-world/node-vitest/calibration/REVIEW.md)
has nine refreshed specimens covering UTC. The
[loan-renewal panel](../test/integration/fixtures/wf-002-loan-renewal/calibration/REVIEW.md)
has fifteen. Proposed labels, human approval and actual judge qualification are
separate; both real human-review and qualification records remain pending. No
human-reviewed labels, general grader accuracy or E2E quality is claimed.

### Summary hierarchy and cross-model variation

Former FIX01 §9.20 recommendations 1–2 are implemented
([Z_FIX01 §9.20](Z_FIX01.md#920-completed-summary-recommendations-and-supporting-review--10-october-2026)),
but their live acceptance is open. Execute the
[prepared summary comparison](../test/calibration/summary-coverage/README.md) only
under fresh approval. Assess meaning preservation with source-preservation review
both enabled and disabled, plus retained statement growth and downstream cost.

Open proposals, with their original numbering:

3. Classify meaning defects separately from representation and source gaps, reusing
   §12.8.1 and §22.2. A grouping error must not become a user question.
4. Extend repair only for genuinely coupled defects. That needs typed coupling
   evidence, deterministic membership and a maximum scope; shared claim IDs alone
   don't prove inseparability. Reassess the full-survivor condition for
   redundant-projection deletion.
5. Make cross-model variation part of acceptance evidence. Offline, cover variation
   cases at every summary level. Live, run repeated comparisons measuring valid
   meaning rejected, unsupported meaning accepted, recovery, cost and completion.

Constraints (former FIX01 §1):

- Summary admission is not per-summary semantic review.
- Loss localization has no summary target
  ([`Location`](../src/domain/source_omission.zig#L8)).
- Allowing overlap can retain misleading paraphrases.
- Duplicate normalization needs conserved evidence, obligations and occurrence
  identity.
- Single-child carry-forward must read the current validated history.
- Don't replace the general repair owner.

Summary-hierarchy measurement (former FIX03 Phase 10) ranks below the review and
repair workload.

### Wider scope retained

- **Evaluator responsibility transfer.** [Judgment](../test/harness/judgment.zig#L14)
  accepts criterion IDs and quoted strings, then checks coverage and substring
  presence. Define the assignment and occurrence contract first.
- **Retained-memory and scale evidence.** Measure growing review sets, retained
  bytes, allocations, validation and teardown time, cancellation and OOM, and
  dependent rebuilding.
- **Harness acceptance (former design/harness tickets H-012, H-013, H-017).**
  Publication process-interruption evidence; production Specify feature-log
  integration; live negative-path evidence for malformed generation, real
  missing/conflicting authority, clarification, cancellation and judge failure;
  and rerun replacement covering shorter output with no trailing bytes,
  unsubmitted drafts, concurrent closes, no duplicate subject IDs and an unrelated
  workflow. Also open: an unchanged prior `spec.md` must not be labelled new output
  after a blocked rerun; compiler rejection of skipped gates and undeclared
  resources; packaged execution without a `design/` fallback; the H-017 live
  generation-plus-grading milestone with stale-artifact rejection; live evaluator
  demonstration (H-004/H-006); and the provider-compatibility diagnostic, whose
  frozen binding the shipped cases now satisfy, since no allowance remains (§11). H-011's answer
  authentication is R2 and H-002/H-016 calibration is R8. The ticket text remains
  in git at `8ed40ba`.
- **Direct Anthropic provider.** [claude_connector.md](claude_connector.md) remains an
  unaccepted proposal. It needs an ADR, its §10 decisions and a changed live-test
  policy.
- Historical optional provider, reasoning-setting and principle-passage experiments
  are not current tasks.

## 6. Recommended order

**User-directed sequence — 17 October 2026:** the latest instruction supersedes
the earlier proposed order for B3, B2, W1 and W2:

1. Finish B3 offline: targeted tests, architecture checks, full verification and
   retained-capture replay through production admission. Record admitted or typed
   failed outcomes and admission escape. Obtain the `contract-reviewer` review,
   then commit. This establishes mechanics, not semantic improvement.
2. On that committed build, run one hello-world and one loan-renewal diagnostic,
   each only after its own explicit billed-run approval. Preserve generation
   failure as a baseline result under §7; do not open another rewording phase.
3. **Approved after both baselines; implemented and verified offline:** implement B2 and W1
   for all post-generation semantic reviews, including principles. Review whole
   units or collections with exact per-subject association, correction scope,
   origins and retry identity. All such findings remain advisory and confer
   no content-repair, mandatory Plan-obligation, clarification or upstream-rebuild
   authority. Current native facts and genuine supported human decisions remain
   mandatory. Include W2 by deleting the unused post-generation upstream path and
   merge variants. Add A4 rejection reasons only if debugging needs them.
4. **Two separately approved attempts complete on `b4c7b07`:** neither reached
   review, so comparative review cost and finding-type accuracy remain unmeasured.
   Governing amendments and their tests accompany the B2/W1 implementation; they
   are not part of the B3 change.

The approved follow-up and remaining proposals below authorize no live calls:

1. **B4 option 3 is approved:** one assignment per complete principle set. Option 1,
   a separate advisory allowance, was recorded here as approved in error; the user
   did not request it, and it is withdrawn, because there is one total limit (B4's
   removal record). Its removal is implemented and verified offline in §9.
   The next diagnostic pair still requires separate
   approval for each billed run.
2. **B9 is approved:** feature-owned entities, with no new cardinality cap or
   retries. Its 2,048-token output allowance was withdrawn on 18 October 2026 (§11). Retained-capture tests
   and the next separately approved pair establish different evidence; neither
   substitutes for R8 acceptance. B7 remains open.
3. R8 is implemented. Adjudicate the first published report under it; the advisory
   grader doesn't decide acceptance. Every report published so far (17 October 18:40
   onward) is `spec-e2e-report/v5`, so the current adjudicator cannot read it (§13).
4. **After the post-B4/B9 runs:** §10's forbidden-verdict fix, the grader's envelope
   parsing, the output-allowance removal and provider-stop logging are implemented
   offline (§11). The next billed pair still needs separate approval for each run.
   B7 is then the main requirement-preservation risk.
   **After the 18 October runs:** both cases publish (§1), and §13 replaces quote
   matching with line locators.
   - Done: the 12:10/12:11 v6 pair confirmed live locators. §14 fixes the
     loan-renewal membership block, and the 15:31/15:33 pair on `96fb905` confirms
     it no longer blocks (§1).
   - Done offline: the grader's one mechanical correction (§15).
   - Next: send each Bedrock model's documented maximum output (ADR 0011
     amendment), then review records per family (B2 approval of 18 October).
     Loan-renewal's 21 assignments exhaust the 100,000-token budget before
     publication.
   - Route 4 in §14: an unresolvable positive advisory verdict still blocks. The
     §10-style schema exclusion needs no ADR change.
   - Adjudicate its reports under `human-spec-adjudication/v2`.
   - Address B7, which also drives loan-renewal's record duplication.
   - Repeat both cases before claiming improvement (§7).
5. Consider A4's broader evidence gaps and W5's identical sibling steps separately
   from the debugging-only A4 scope above.
6. The experiment's Phase 2 budget/scope decision remains separate from B4's
   implementation. Its single-pool plan stands, because there is one total limit.
7. Decide A1–A3, W3 and A6's scope freeze before starting Plan. Implement A1 before
   adding operations for another workflow.
8. Freeze the Phase 2 baseline under B4's decision. Measure W4 on retained captures,
   and run B5's A/C comparison only if generation-boundary failures remain.
9. Treat R2 as a separate required feature. Decide R1 before promising stronger
   provenance. Gather R6 and R7 evidence after B2.

## 7. Acceptance and evidence rules

Keep these evidence statements separate: **implementation complete**, **mechanical
checks passed**, **semantic benefit demonstrated**, **brittleness reduced** and
**scope qualified**. More passing tests, fewer calls or higher schema admission alone
close none of the semantic gates.

Rules for every contract change (former FIX04 §1.1):

- Decide on at least two unrelated development cases, with replayed repetitions. A
  single run cannot decide a change.
- Never tune on the sixteen reserved qualification features.
- A model limitation under a coherent contract is a valid result. Don't answer it
  with field-, case- or model-specific rules, sampling changes, extra retries, a
  second model or a weaker admission rule. The development grader's single
  mechanical correction (§15, user decision of 18 October 2026) is an explicit
  exception for the harness, not engine policy.
- Budget-stopped, malformed and exhausted runs stay in the attempted-workload
  denominator.

The [evaluation protocol](../test/calibration/semantic-simplicity/README.md) owns
case partitions, scoring, the numeric gates and the experiment stops. Three further
measures, not yet in it, apply to full-workflow runs:

| Measure | Definition |
| --- | --- |
| Finding-type accuracy | Share of review findings whose type matches a frozen, source-based label for the assessed field. Report precision per predicted type and recall per labelled type, at original and final assessment. A real defect reported with the wrong type is a harmful diagnosis. |
| Stage resource share | Sends and actual tokens per stage (extraction and reconciliation, generation, review, repair) per attempted workload, including budget-stopped runs. |
| Admission escape | Share of attempted workloads in which a value violating a declared native rule reached review or publication, with the sends and tokens spent downstream of it. This is mechanical evidence, not semantic quality. |

Boundary gates carried from former FIX01 §5:

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

Offline unit and integration tests verify native mechanics. Live comparisons with
reviewed labels assess changed meaning. Run `zig build verify` and the clean
packaging checks when implementation boundaries change. Each live diagnostic needs
bounded approval, and each E2E run needs its own explicit approval
([live harness](../design/harness/e2e.md)).

## 8. Record history

- **17 October 2026:** this review was written, and FIX01 (from 11 October) and FIX04
  (from 15 October) were consolidated here and deleted. The Spec workflow
  simplification review (§4) was added the same day, and §1's subgraph-call count was
  corrected from 78 to 77; a step named `call` had been counted as one.
- **17 October 2026, after the B3 baselines:** added §1's post-B3 outcome assessment
  and the B7 and B8 items, and updated B2, B5, B6 and §6 from the two baseline runs.
- **17 October 2026, advisory allowance withdrawn:** the user did not request B4
  option 1's separate advisory allowance and directed its removal; there is one
  total limit. Recorded the removal in B4, §6 and §9, ADRs 0011 and 0023, design
  §§3.3 and 31, contracts 12, 22 and 27, and the harness docs. The code removal
  and its completed offline verification are recorded in §9.
- **17 October 2026, after the post-R8 runs:** added §1's post-R8 diagnostics and
  B4's post-R8 evidence, generalized B9 to all runaway output, and updated §6.
- **18 October 2026, after the post-B4/B9 runs:** added §1's post-B4/B9 diagnostics
  and §10's forbidden-verdict fix, and updated §6.
- **18 October 2026, prefix decision:** approved normalizing the truncated Bedrock
  GPT-OSS member-name prefix, logged as an engine fix. Added §12 and updated B6.
- **18 October 2026, after the §10–§12 runs:** added §1's §10–§12 live diagnostics and
  updated §6.
- **18 October 2026, grader locators:** approved option D. Added §13 and updated §1
  and §6.
- **18 October 2026, grader correction and B2 approvals:** added §15, recorded the
  record-family and maximum-output approvals under B2, and updated §6 and §7.
- **18 October 2026, after the §14 runs:** added §1's §14 live diagnostics and
  updated §6.
- **18 October 2026, membership at admission:** the user directed applying the best
  recommendation for the loan-renewal block. Added §1's §13 diagnostics and §14, and
  updated §6. After four contract reviews and the user's explicit confirmation, §14
  also covers parent-scoped guidance, the v8 request description and harness, the
  restriction guards, principle and preservation-comparison membership, and route 4
  as an open item.
- **18 October 2026, user decisions:** approved routing the grader through the
  canonical envelope parser. Directed that there be no output token limits and that
  provider-applied limits be logged. Added §11 and updated §1, B9, §5, §6 and §9.
- **17 October 2026, after the B2/W1 reruns:** added §1's post-B2/W1 diagnostics and
  the B9 item, extended B8 to token classification, and updated B5, B7 and §6.
- **Not carried forward:**
  - completed-execution narratives, already in Z_FIX01 and Z_FIX02;
  - the detailed FIX04 Phase 0–6 rollout text; the protocol and operator guide are
    in `test/calibration/semantic-simplicity/`;
  - superseded Luna-target research;
  - historical F1–F8 analysis, kept here only as the B5 constraints.
- **Retrieving the full text:** both deleted records remain in git at `b2f10a3`.
- **17 October 2026, design documentation review:** the design/harness ticket
  backlog was deleted and its open items carried into §5 "Wider scope retained".

## 9. B4/B9 implementation — 17 October 2026

This record originally said the user approved B4 options 1 and 3 and B9 as one
implementation change, amending ADRs 0011 and 0023 and §§12, 17, 22, 24 and 27. The
governing design remains proposed.

**Correction — 17 October 2026:** the user did not request option 1, the separate
advisory allowance. It is withdrawn: there is one total limit. B4's removal record
lists the removed code. The pool, allowance and per-pool report items below
describe the superseded uncommitted implementation, not the governing contract.

- **Withdrawn:** required work keeping 100,000 tokens while advice shared a
  separate 20,000. One 100,000-token total budget applies to all model work, and
  actual usage and overshoots remain fully recorded. Unknown usage prohibits further
  model calls. Native publication can continue only when the remaining required
  gates need no model work.
- Eligible provider/service stops and exhausted existing malformed-response
  correction produce an exact native incomplete-assignment suffix. Complete
  admitted prefixes, adverse findings and origins remain intact. Native evidence
  defects, security failures, cancellation, deadlines, logging and required-work
  failures keep their terminal behavior. No extra retry is added.
- Each selected principle set assesses all its current subjects in one assignment,
  with the corpus/context once and exact per-member findings and origins.
- The feature-wide entities unit owns applicability and independently supported
  entity records. Other record batches reject entities. Arrays gain no new caps.
  The 2,048-token slot allowances originally recorded here were withdrawn on
  18 October 2026 (§11).
- Current state is `specification-state/v18`; workflow reports are
  `spec-e2e-report/v5`, with incomplete advice and explicit unsent operations. The
  separate pool observations and feasibility pool evidence in the uncommitted
  implementation are withdrawn with the advisory allowance; the single-pool
  experiment plan stands.
  Historical captures and calibration/protocol bindings remain unchanged.

**Current implementation:** all inference uses one aggregate
`totalModelTokenBudget`; no advisory tokens, pools or usage subtotals are calculated.
A global-budget rejection
remains fatal during advice and required work. It is not an incomplete-advice stop.
The native advisory classification remains only for eligible non-budget
provider/protocol/missing-usage outcomes, with all publication gates unchanged.

The removed pre-send advice path creates no synthetic invocation result or
accounting row. Every remaining incomplete-advice reason requires an actual
producing inference origin. Required work and advice share the same pre-call
check, actual-usage reconciliation and failure on overshoot; equality admits the
current result but prohibits another model call.

**Current validation — corrected single-budget build:**

| Command | Result |
| --- | --- |
| `zig build test-model-request-workflow -j2 --summary all` | 3/3 steps; 446/446 tests. |
| `zig build test-architecture -j2 --summary all` | 3/3 steps; 156/156 tests. |
| `zig build smoke -j2 --summary all` | 95/95 steps, including the corrected missing-request protocol-closure fixture. |
| `zig build verify -j2 --summary all` | 168/168 steps; 1,890/1,890 tests, including offline integration and clean packaged-executable checks. |
| `git diff --check` | Pass. |

The current logs are `.zig-cache/global-token-requests.log`,
`.zig-cache/b4b9-commit-smoke.log`, `.zig-cache/b4b9-commit-architecture.log` and
`.zig-cache/b4b9-commit-verify.log`. All 164 main workflow scenarios and the
seven production fake-provider scenarios pass. The global-budget case crosses the
aggregate total to 100,001 and proves `WorkflowTokenBudgetExceeded`, no native
advice stop, no publication, no further sends and zero admission escapes.
The fresh pre-commit `contract-reviewer` review found one packaging-fixture edge
using `failed` where its operation declares `blocked`. That edge is corrected so
the negative test proves its intended missing-request boundary; smoke,
architecture and full verification pass after the correction. The final review
has no remaining findings, and the governing documentation matches the behavior.

The four requested commit gates have explicit regression coverage:

| Case | Evidence |
| --- | --- |
| Review crosses the global limit | `production workflow retains typed advice stops and enforces one global token budget` in `test/harness/integration/tests.zig`: aggregate usage reaches 100,001, yielding `WorkflowTokenBudgetExceeded` with no publication or later send. |
| Review reaches provider output limit | The same production test's source-output-limit mode requires incomplete advice with the actual origin and validates publication readback. |
| Entities are authored once per feature | `feature entities keep independent support and record batches reject every entity entry path` in `src/specification_generation_test.zig` exercises separate business groups and rejects entities in every record-batch entry path. |
| Each principle set is assessed in one call | `source units and complete principle sets preserve every record family and relationship member` in `src/specification_generation_test.zig` requires one complete assignment; production workflow tests require one physical review call per selected set. |

**Historical validation — superseded separate-pool build:** the following checks
passed before the user-directed removal. They do not verify the corrected build:

| Command | Result |
| --- | --- |
| `zig build lint test-architecture -j2 --summary all` | 5/5 steps; 156/156 tests; lint passes. |
| `zig build test-integration -j2 --summary all` | 8/8 steps; 127/127 tests, including all 164 main workflow scenarios. |
| `zig build test-provider-compatibility -j2 --summary all` | 3/3 steps; 197/197 tests. |
| `zig build verify -j2 --summary all` | 168/168 steps; 1,892/1,892 tests, including clean packaged-executable checks. |
| `git diff --check` | Pass. |

The historical logs are `.zig-cache/b4b9-final-architecture.log`,
`.zig-cache/b4b9-final-integration.log`,
`.zig-cache/b4b9-final-compatibility.log` and
`.zig-cache/b4b9-complete-verify.log`. The independent `contract-reviewer`
review covered that superseded implementation and its final fixture corrections;
the corrected single-budget change has the separate review recorded above.

That build's seven production fake-provider scenarios covered source output stop, advisory
overshoot followed by unsent principle advice, protocol exhaustion, required
generation/source stops, and provider/protocol stops during authorized
source/principle finding repair.
They required exact reasons and origins, current permit settlement, unchanged
published content where permitted, native readback and zero admission escapes.
Those results are integration mechanics, not live or semantic-quality evidence,
and do not establish the corrected global-budget failure behavior.

The retained exact-value admission replay records four available historical
captures as typed rejections under the current contract and admits an unrelated
scripted control, with zero admission escapes and zero model calls. The 20:33
historical capture remains unavailable; no substitute is presented as its replay.
The superseded conditional entity-batch experiment runner is removed; its frozen
inputs, labels and results remain historical evidence, with current feature-owner
regressions replacing its obsolete ownership assertions.

No billed calls, E2E reruns, baseline freeze or human acceptance are included.
R8 calibration review and human adjudication remain pending.

## 10. Advisory assignment verdict restriction — 18 October 2026

**Defect.** The 18:41 loan-renewal run blocked because post-generation source review
offered a verdict that admission always rejects. B2's whole-assignment packets used
`assignment_findings`, whose value schema includes `not_applicable`. Assignments exist
only in the advisory specification projection, where a current candidate fixes
applicability ([required_authority.zig](../src/domain/required_authority.zig)
`applicability`), so admission rejects that verdict as `invalid_decision`. No repair
applies, and the result is `UnsafeSupportRepair`. The single-finding path already
chose `finding` or `applicability_finding` from applicability. The evidence guidance
listed a `not_applicable` rule on every request except single source-preservation
findings, even where the verdict was forbidden.

**Authority.** F0100 §3.10: "Only unresolved entity applicability permits
`not_applicable` … requests select the permitted schema". §12.2 lets native
availability facts exclude tagged alternatives. ADR 0023 keeps native admission
mandatory and ends exhausted malformed-response correction as incomplete advice.

**Change.** In [specification_support.zig](../src/domain/specification_support.zig):

- one predicate, `permitsNotApplicable`, now answers whether a subject may receive
  `not_applicable`. Request definition, assignment exclusion, guidance, admission and
  readback all use it;
- each advisory source assignment derives one restriction from every member's native
  applicability, and excludes `not_applicable` unless all members permit it.
  Disagreeing members are rejected as an illegal assignment. That guard is currently
  unreachable, because unit formation never mixes applicability;
- the evidence guidance lists the `not_applicable` rule only where the verdict is
  permitted, for single findings and assignments alike;
- the source-preservation removal of that rule is deleted, because the shared
  derivation now covers it.

Admission's `invalid_decision` check and its absence of repair are unchanged. No
verdict is reassessed. A model that still returns `not_applicable` now gets the
existing schema correction, as single findings already did. Exhausting it ends the
advice as incomplete under ADR 0023. No schema, prompt, persisted shape or packaged
asset changed.

**Regression evidence:**

- `source review offers not_applicable only where native applicability permits it`
  in `src/specification_generation_test.zig` covers two unrelated sources. Before
  authoring, only entity applicability keeps the verdict and its rule. After
  authoring, with both entity dispositions, every assignment excludes the verdict.
  That covers feature-intent, entity-applicability, reference-meaning and
  preservation subjects. The restricted schema rejects a `not_applicable` finding as
  `unknown_variant` and accepts the same batch when it says `supported`. A
  readiness entity-applicability assignment keeps and accepts the verdict. The test
  fails without the fix.
- Two offline integration scenarios in `test/integration/workflow_tests.zig` return
  `not_applicable` from post-generation review:
  - once: corrected at `/kind` as `unknown_variant`, then published;
  - persistently: exhausted into incomplete advice, with publication.

  The test driver now derives the assignment's expected verdicts from native
  applicability instead of pinning the eight-variant schema. Integration fails
  without the fix.

**Follow-up (not done).** The single path picks a schema definition, while
assignments exclude a variant. The two definitions also order `candidate_invalid`
and `inconclusive` differently. Single source-preservation findings separately drop
the `negative` guidance rule in a projection-specific branch, the same guidance and
schema pairing. Unifying them on one mechanism would change the workflow schema
resource and retained request bindings, so it stays a separate change.

**Validation:**

| Command | Result |
| --- | --- |
| `zig build test-specification-generation -j2 --summary all` | 3/3 steps; 374/374 tests. |
| `zig build test-model-result-schema test-model-request-workflow test-workflow-repair-retry test-required-authority test-model-request-preparation -j2 --summary all` | All pass, including 446/446 model-request-workflow and 258/258 required-authority tests. |
| `zig build test-integration -j2 --summary all` | 8/8 steps; 127/127 tests, including the two new scenarios. |
| `zig build lint test-architecture -j2 --summary all` | 5/5 steps; 156/156 tests; lint passes. |
| `zig build verify -j2 --summary all` | 168/168 steps; 1,891/1,891 tests, including clean packaged-executable checks. |
| `git diff --check` | Pass. |

No billed calls, E2E reruns or human acceptance are included.

## 11. Grader envelope, no output allowance and provider-stop logging — 18 October 2026

User decisions on 18 October 2026:

- the advisory grader may use the engine's envelope parser;
- "there should be no output token limits";
- provider-applied output limits "must be logged";
- remove the control from the engine, not only from configurations.

ADR 0011 records these decisions; the design remains proposed.

**Grader envelope.** [evaluate.zig](../test/harness/evaluate.zig) passes each judge
response through `model_envelope.parseContent`, including the approved §22.6
opening-artifact exception, before judgment validation.

- A rejected envelope keeps its original bytes and parser diagnostic.
- Human adjudication proposals and `judgment.validate` itself stay strict.
- Raw evidence and the evaluation report schema are unchanged.
- [evaluator.md](../design/harness/evaluator.md) and §22.6 record the scope.

**No output allowance.**

- The optional slot `maxOutputTokens`, `OutputTokenAllowance` and the
  `supports_max_output_tokens` capability are removed. So are the Bedrock
  `inferenceConfig.maxTokens` encoding and the replay retention of the field.
- The closed configuration now rejects `maxOutputTokens`, so the provider applies
  the model's own maximum. AWS documents that an unset `maxTokens` defaults to the
  model's maximum.
- `InferenceControls.isValid` had nothing left to check and is removed with its
  callers.
- Request descriptions advance to `model-request-debug/v7`. No committed evidence
  used v6. §14 later advanced them to v8.
- The shared E2E configuration and the protocol fixture drop their allowances, and
  the semantic-simplicity protocol drops `max_output_tokens`. The shipped cases
  therefore now satisfy the frozen binding.
- Drift coverage now uses a new MOCK bad-input fixture,
  `test/integration/fixtures/baseline/mock-bad-input-drifted-effort.sddtoolkit.json`, whose generation
  slot changes a still-bound control: `reasoningEffort: "medium"`. It is test input
  only, never runtime configuration, and must be committed with this change.
- The historical v5 attribution reader keeps a frozen controls shape for reading
  retained evidence. Nothing encodes the retired field. Fidelity checks compare the
  current encoding with the retained bytes minus their single `maxTokens` member, a
  read-side projection.
- Committed calibration records are unchanged historical evidence.

**Provider-stop logging.** After `model.completed`, the runner logs a warning-level
`model.provider_stopped` for every provider non-candidate stop:
`OUTPUT_LIMIT`, `CONTENT_FILTERED`, `UNSUPPORTED_TOOL_REQUEST`, `MALFORMED_OUTPUT`
or `CONTEXT_LIMIT`. The event carries the outcome and the provider's reported
tokens. A logging failure stops the run; outcomes, accounting and retries are
unchanged. Contract 27 records the event.

**Regression evidence:**

- **Grader:** `{"` and repeated-key prefixes are scored. Since §12, so is a key start
  (`{"resu`). A non-matching start (`{"resx`) and doubled prefixes are rejected as
  `json`. The added Bedrock cases fail without the
  change. A separate guard test shows `judgment.validate` alone still rejects a
  prefixed proposal.
- **Configuration:** a `maxOutputTokens` value of 1, 2,048, 16,384 or null is
  rejected.
- **Bedrock encoding:** no request in either response mode contains `maxTokens`.
- **Request descriptions:** a description that carries a retired allowance, or the
  superseded v6 label, is rejected.
- **Provider stops:** both backends keep actual usage on a provider output stop.
- **Frozen binding and drift:**
  - the frozen-binding tests reject effort, slot and temperature drift;
  - the drift scenarios reject before any send;
  - the semantic-simplicity protocol rejects an added `max_output_tokens`.
- **Logging:**
  - `runner logs every provider-applied stop with its exact reason and stops on log
    failure` covers all five reasons, a complete-response control and log failure.
    The event must directly follow `model.completed` with the same correlation and
    outcome. The test fails without the runner change.
  - The production advice scenarios read the real feature log. Advisory source and
    repair output stops and required stops each log `OUTPUT_LIMIT`; budget and
    protocol modes log none. These scenarios fail without the change.

**Validation:**

| Command | Result |
| --- | --- |
| `zig build test-rubric-evaluator -j2 --summary all` | 3/3 steps; 385/385 tests. |
| `zig build test-model-request-workflow -j2 --summary all` | 3/3 steps; 448/448 tests. |
| `zig build test-integration -j2 --summary all` | 8/8 steps; 127/127 tests. |
| `zig build lint -j2 --summary all` | Pass. |
| `zig build verify -j2 --summary all` | 168/168 steps; 1,890/1,890 tests, including clean packaged-executable checks. |
| `git diff --check` | Pass. |

**Open:** `model.provider_stopped` is a warning-level event, so a configured
`logs.level` of `error` or `fatal` filters it out like any other warning.

The direct Anthropic proposal ([claude_connector.md](claude_connector.md)) assumes a
required `maxOutputTokens`. It stays unaccepted and would need a new decision. No
billed calls, E2E reruns or human acceptance are included.

## 12. Partial member-name prefix normalization — 18 October 2026

**Decision.** On 18 October the user approved normalizing the truncated opening artifact
that Bedrock GPT-OSS-20B emits. The engine must log each fix as a warning, and the
change must stay limited to the prefix.

**Evidence.** The 18 October 10:00 AEDT loan-renewal run
(`2026-10-17T23-00-08Z-5210055c5d2617259529446984f05612`) hit this artifact in 5 of
its 20 source-review calls, counting retries.
- Six responses began `{"find{"findings":…`: calls 11, 17, 19, 21, 29 and 30.
- They caused five protocol retries, which together cost 18,802 tokens.
- Call 30 was itself the retry for request 25 and failed again. The correction
  allowance was exhausted, so the advice for requirement ordinals 25–26 closed
  incomplete, with no source review for those subjects.
- The run exceeded the 100,000-token budget at 111,880. Without the retries it
  would have been about 93,000, assuming nothing else changed.
- The same form, `{"token{` and `{"find{`, appeared once per run from 16 October.

**Change.**
- In [model_envelope.zig](../src/domain/model_envelope.zig), the shared §22.6
  parser also accepts `{"name{` when `name` is a nonempty start of the next
  object's first key, rather than the whole key.
- That key must end at an unescaped quote followed by a colon.
- Everything else is unchanged:
  - only the opening fragment is removed;
  - escapes, control bytes and recursive or trailing artifacts still reject;
  - the remainder must strictly parse as one complete object;
  - schema and native validation still run;
  - the string-value opener still requires the exact name.
- The candidate records `removed_partial_field_prefix`. The runner logs the
  existing warning event `model.response_normalized`, which reports that the engine
  fixed the response, with diagnostic `REMOVED_PARTIAL_FIELD_PREFIX`.
- The request debugger shows every normalization rule from one note map; a test
  requires an entry for each rule.
- The engine and the grader share this parser.
- §22.6 and contract 27 record the amendment.

**Regression evidence:**

- **Envelope tests accept:**
  - `{"find{"findings":…}`, `{"token{"token_classifications":…}` and
    `{"kind{"kind_extra":…}` (the last was previously listed as rejected);
  - a whitespace-led key;
  - a UTF-8 key start (`{"é{"état":…}`).
- **Envelope tests reject:**
  - a non-matching start and a longer name;
  - a missing colon, a trailing fragment, a trailing comma and an incomplete
    remainder;
  - an escaped key and a recursive prefix;
  - a duplicate key, a control byte or invalid UTF-8 in the rest of the key, and a
    name that splits a character;
  - a truncated string-value opener.
- **Runner tests:**
  - The runner logs `REMOVED_PARTIAL_FIELD_PREFIX` once at warning level, and the
    request completes without protocol correction.
  - Partial-prefix responses that fail the schema or the remainder parse still use
    the protocol retry allowance.
  - The accepted-case test fails with partial prefixes rejected.

**Validation:**

| Command | Result |
| --- | --- |
| `zig build test-model-envelope test-model-request-workflow -j2 --summary all` | 6/6 steps; 511/511 tests. |
| `zig build test-rubric-evaluator -j2 --summary all` | 3/3 steps; 386/386 tests. The grader now accepts `{"resu` and rejects `{"resx`. |
| `zig build verify -j2 --summary all` | 168/168 steps; 1,890/1,890 tests, including clean packaged-executable checks. |
| `zig build lint` and `git diff --check` | Pass. |

No billed calls are included.

## 13. Grader evidence by line locator — 18 October 2026

**Decision.** On 18 October the user chose option D: the judge cites where its
evidence is, and the harness resolves the exact text.

**Evidence.** Every grader run in §1's 18 October diagnostics failed
`quote_not_found`.
- None of 21 specification quotes across the three published runs matched the
  captured bytes.
- After removing Markdown escapes and markup and folding case, only 2–3 per run
  matched.
- GPT-OSS-20B copies the start of a quote, then paraphrases.

**Change (test harness only).**
- **Judgment contract** ([judgment.zig](../test/harness/judgment.zig)):
  `rubric-judgment/v2` evidence is `{document_id, first_line, last_line}`, inclusive
  and 1-based.
- **Shared line handling:** one owner numbers lines (LF-terminated, with a final LF
  ending the last line). It resolves each locator's exact bytes and validates:
  - an unknown document;
  - `invalid_line_range` for zero, reversed or out-of-range lines;
  - `blank_evidence` when no cited line has text.
- **Judge packet** ([packet.zig](../test/harness/packet.zig)):
  - prompt revision `rubric-judge/v2`;
  - every source and the specification arrive as numbered lines of the exact
    captured bytes;
  - instructions ask for the narrowest supporting lines, without copied text.
- **Reports:**
  - `evaluation-report/v4` renders each locator with its resolved lines;
  - grader qualification reads the version from the report owner;
  - `spec-e2e-report/v6` embeds it;
  - human adjudication moves to `human-spec-adjudication/v2` and
    `spec-adjudication/v2`.
- **Review follow-ups (same change):**
  - Line boundaries now come from the engine's shared `source_coordinates.advance`:
    CR, LF and CRLF each end one line, and a final terminator ends the last line.
  - The protocol hash binds the numbering through a fixed probe document.
  - `reports.parse` revalidates a persisted judgment against its capture and
    rejects unresolvable locators or forged arithmetic. Rendering has no fallback,
    and qualification no longer revalidates separately.
  - The baseline contracts that embed judgments or the E2E report advanced:
    assessor schema `3`, `baseline-score/v4` and `baseline-acquisition/v4`.
  - acceptance.md gives humans the numbering rule.
- **Unchanged:**
  - the engine, the renderer and published bytes;
  - the baseline experiment's separate quote-based labels;
  - the pending grader-calibration and qualification records, which bind no
    judgment.
- **Docs:** evaluator.md, acceptance.md and e2e.md record the contract.

**Consequence.** Every report written before this change is historical. That covers
`spec-e2e-report/v5`, from the 17 October 18:40 hello-world run through all four 18
October runs.
- The current adjudicator rejects these reports, as the no-compatibility rule
  requires. They already carry the retired `quote_not_found` diagnostic, so a closed
  reader could not decode them anyway.
- Budget-feasibility evidence (`baseline/feasibility.zig`) also stops reading them.
- A fresh run produces a different specification. The only route to adjudicate
  those exact specifications is the historical adjudicator at commit `3d48334`,
  which is a user decision.

**Regression evidence:**

- **Line handling:** `evidence locators cite numbered lines that resolve to exact
  captured bytes` covers:
  - line counting, with and without a final terminator, and for an empty document;
  - CRLF, a lone CR, a trailing blank line, invalid UTF-8 and a `maxInt(u32)`
    locator;
  - exact spans, including a blank line and a multi-line range;
  - rejected zero, reversed and out-of-range locators;
  - an accepted range that spans a blank line;
  - packet numbering that matches validation;
  - report rendering of resolved text;
  - persisted and in-memory reports with an unresolvable locator, which are
    rejected.
- **Validator diagnostics:** reject out-of-range, blank, zero and reversed locators,
  an unknown document, and the retired `quote` field.
- **Converted suites:** the acceptance, gate, qualification, useful-completion and
  E2E acceptance tests now use locators. Their fabricated-evidence cases cite lines
  outside the document.
- **Version tests:** reject the immediately superseded versions (`spec-e2e-report/v5`,
  `human-spec-adjudication/v1` and `evaluation-report/v3`).

**Validation:**

| Command | Result |
| --- | --- |
| `zig build test-rubric-evaluator test-integration test test-baseline -j2 --summary all` | 78/78 steps; 2,547/2,547 tests, after the review follow-ups. |
| `zig build verify -j2 --summary all` | 168/168 steps; 1,891/1,891 tests, including clean packaged-executable checks. |
| `zig build lint` and `git diff --check` | Pass. |

No billed calls are included. The first v6 run is the live check that the judge
cites valid locators.

## 14. Assignment membership at response admission — 18 October 2026

**Decision.** On 18 October the user directed: "perform detail analysis on the issue,
and apply best recommendation, keeping with the code design principles". After the
first contract review, the user explicitly confirmed the ADR 0023 policy change and
chose to fix every review finding, including opting preservation comparisons into
the same admission rule.

**Analysis.** Four routes let a post-generation review-response defect stop a
workflow:

1. A whole-assignment membership defect (missing, repeated or foreign member).
   Native collection rejects the assignment with no candidate, support repair cannot
   authorize, and the run blocks. This was the 12:11 run.
2. A finding-level defect that native repair cannot authorize. This was 17
   October's `invalid_decision`, now excluded by §10's schema narrowing.
3. Exhausted finding repair, which ends the run with `retry_limit`.
4. A schema-valid positive verdict (`supported` or `not_applicable`) for a member
   whose claim set canonicalization cannot resolve: an eligible-subset rule with
   bound-claim evidence and no candidate provenance, whatever the eligible claim
   count. `claimsFor` raises a decode error before `admit`, which owns the typed
   `invalid_selection` rejection, sees the finding. The assignment is therefore
   rejected as `invalid_json` with no candidate and blocks. The contract review
   found this route; no run has observed it.

Accepted authority listed membership only as a native failure (ADR 0023's
assignment and principle-handoff paragraphs), with no non-terminal classification
for an advisory response defect (design-router gap C1). It explicitly keeps routes
2 and 3 terminal: §22.6 says "native finding-evidence validation and repair
exhaustion remain terminal", and ADR 0023 agrees ("Existing native finding-evidence
validation and bounded repair are preserved"). Route 4 is a finding-evidence
failure under that same rule, so it stays terminal. Its
`invalid_json` label is wrong, however. Making canonicalization total would not
help on its own: `admit` would classify the finding as an evidence-selection
defect, and selection repair cannot change a verdict, so it would spend repair
calls before blocking. The schema profile cannot express uniqueness, which stays a
native check.

**Change.** Membership becomes part of response admission for whole-unit review
assignments under advisory policy and preservation comparisons under required
policy. It sits on the shared contract rather than in
an advisory-only branch.
- `model_result_schema` gains an `exact_members` integer choice for an integer
  property of array items. It fixes the item count to the member count, which the
  guidance schema states (Bedrock's structural projection keeps only
  `minItems: 1`), and records the member set. A foreign ordinal already fails the
  narrowed choice.
- `model_payload_schema` rejects a repeated member natively as `duplicate_member`.
  A missing member then always appears as a count error or a repeat. Guidance
  locates the repeat at its item but scopes the expected contract to the parent
  array.
- Source and principle assignment packets mark their ordinal choice
  `exact_members`. So does the preservation-comparison packet, whose native
  admission already required exactly one assessment per comparison. Its binding
  always assigns the extracted-claims comparison, so a loss packet with no
  comparison is refused as an invariant violation. Grouped reconciliation
  dispositions are also one-per-claim responses but keep their native cardinality
  checks; they were not examined here.
- Membership defects take the existing bounded protocol correction of the complete
  response, with the same allowance and no new counter. Assignments exist only
  under advisory policy, so their exhaustion closes that assignment's advice as
  incomplete (`protocol_exhausted`). Preservation comparisons run under required
  policy, so their exhaustion stays terminal.
- Native collection still rejects membership defects atomically, as the authority
  behind admission. Routes 2, 3 and 4 are unchanged.
- The restriction refuses a key that is not a required, non-nullable scalar
  integer in every item variant. It also refuses a path through an optional
  property or a second array, a match that misses any alternative or reaches only
  a projection parent or another definition, and any later choice, path or
  tagged, that narrows the key below the member set. Clones keep the restriction.
- Request descriptions advance to `model-request-debug/v8` and record each applied
  member set. Debugger inspection, replay and the exact-value harness reapply it
  through the same `restrict` owner, so none of them reports a response that
  admission rejected as valid. A record that does not fit its captured schema, or
  that a pre-v8 harness capture claims to carry, is refused. No v7 reader remains.
- ADR 0023 records the classification, the confirmation and the supersession in
  its principle handoff. ADR 0019 records v8.
  §12.2, §12.7, §17.3, §22.1, §22.4, §22.6, §24 and F0100 match.

**Open decision (route 4).** In post-generation review, whether a positive verdict
can be resolved is uniform within each assignment:
- `projectRecords` requires a brief whenever generated content exists, so brief
  fields always resolve;
- the primary user story always resolves through its generated value;
- every other assignment unit shares one record, one collection slot, the entities
  basis or exact-set reference rules.

Excluding positive verdicts from that assignment's schema when they cannot be
resolved is therefore §10's move again: it needs no ADR change and cannot remove a
valid verdict from a sibling member. It is not implemented here. It needs a fixture
with a claimless record collection, and it is a separate change from membership.
The `invalid_json` label on this route also remains wrong until then.

**Regression evidence:**

- **Schema owner:**
  - complete member sets in any order are admitted;
  - partial, empty, over-count and foreign batches reject;
  - a repeated member rejects as `duplicate_member` even though the provider bytes
    alone admit it;
  - each restriction guard above refuses its case, while the same path under
    another carried definition is still admitted;
  - the recorded set survives cloning and rebuilds admission from provider bytes,
    while ill-fitting records are refused.
- **Payload correction flow:** a repeated member is reported at `/value/2` with the
  expected path pinned to `/value` (parent scope). Its schema pointer and outline
  are checked against the selected schema's projection.
- **Debugger, replay and harness:** a captured assignment request round-trips its
  member set through the feature log. Inspection and the exact-value harness reject
  the repeat, and accept the same bytes without the record. Ill-fitting records
  and the v7 label are refused.
- **Packets:** the principle-assignment and preservation-comparison schemas each
  admit the complete response and reject partial, repeated and foreign ones. The
  record calibration probe accepts only the complete batch.
- **Offline integration:**
  - Source and principle assignments with a partial or repeated member recover
    after one correction, or exhaust into incomplete advice for that projection
    only, and the run still publishes.
  - Source-loss runs that omit or repeat one comparison recover after one
    correction. A persistent omission ends the run with `retry_limit`, because
    this request runs under required policy.
  - Every assignment and comparison request asserts its bound count and exact
    member set. Every membership correction asserts the reason, located path,
    expected path, scope and schema pointer.
  - Without the packet change, the first source scenario blocks at
    `collect-specification-support`, as the live run did.

**Validation:**

| Command | Result |
| --- | --- |
| `zig build test-model-result-schema test-model-payload-schema test-specification-generation test-model-logging test-exact-value-replay -j2 --summary all` | 23/23 steps; 875/875 tests. |
| `zig build test-architecture --summary all` | 3/3 steps; 156/156 tests. |
| `zig build test-integration -j2 --summary all` | 8/8 steps; 127/127 tests. |
| `zig build verify -j2 --summary all` | 168/168 steps; 1,895/1,895 tests, including clean packaged-executable checks. |
| `zig build lint` and `git diff --check` | Pass. |

No billed calls are included.

## 15. Grader one-shot correction — 18 October 2026

**Decision.** Two consecutive live grades failed with `invalid_judgment`
(`missing_source_evidence` on `organization`, then `clarity-testability`), so no run
received an automated grade. On 18 October the user decided:

> Allow one correction attempt per invalid grader judgment. Limit correction to
> mechanical errors: missing evidence, invalid line references, missing criteria or
> malformed output. Send the exact validation diagnostic and identify the affected
> criterion. Keep the specification, sources, rubric, model and unaffected criterion
> results unchanged. Revalidate the complete corrected judgment using the existing
> canonical validator. Never retry a valid low score to obtain a passing grade. Count
> both attempts against the evaluator's token budget and retain their responses,
> diagnostics and usage. If correction fails or the budget is exhausted, report an
> evaluator error; do not accept the invalid grade. Add positive and negative tests
> before enabling this policy.

The user then chose the closed correctable list below and fixed protocol outside
`retry_limit`.

**Authority.** The grader is development-only harness code under R8: it grants no
workflow, publication or acceptance authority. No ADR or invariant governs grader
retries. The superseded text was harness documentation (evaluator.md "invalid
judgments are not retried") and the tests that pinned it.

**Change** (in `test/harness/`):
- `correction.zig` owns the policy:
  - correctable reasons: `json`, `invalid_shape`, `criterion_count`,
    `missing_criterion`, `missing_source_evidence`,
    `missing_specification_evidence`, `blank_evidence`, `unknown_document` and
    `invalid_line_range`;
  - model-visible guidance: the exact diagnostic, naming the criterion when one
    exists, a fixed explanation and instruction, and the rejected response;
  - the preservation check: every result the rejected response made readable and
    the diagnostic did not name must be returned equal after canonical decoding,
    or the correction is rejected as `changed_criterion`. After a shape defect
    each result that decodes on its own under a top-level `results` array is
    readable; unparseable JSON, a response without that array or one with no
    decodable result has none, and a readable duplicate is final. The user accepted
    validation-only correction of unreadable results on condition that it is
    logged: that attempt records `unconstrained` (`unparseable_json`,
    `no_results_array`, `no_readable_result` or `some_results_unreadable`) in JSON
    and Markdown, matching the defect.
- `judgment.validate` decodes through widened integers, so a negative or oversized
  score is `invalid_score` and such a line is `invalid_line_range`, not a shape
  defect. An evidence defect also pins the named result's
    disposition and score, and its guidance says so.
- `judgment.validate` detects repeated criteria before counts and order, so a
  duplicate is always final. Provider observations can no longer report judgment,
  budget or retry outcomes.
- `evaluate.zig` sends one correction after a correctable invalid judgment, through
  both the OpenAI and the Bedrock encoders. The correction is outside `retry_limit`;
  its transient failures use the remaining retries. Both attempts count against the
  evaluator budget, and an exhausted budget prevents the correction
  (`budget_exceeded`). An invalid correction is final (`invalid_judgment`).
  Valid judgments, including low scores, are never resent.
- `evaluation-report/v5` gives each attempt its purpose and diagnostic and drops the
  report-level diagnostic. The reader admits only metered transient retries within
  `retry_limit` and up to the hashed correction limit after a metered correctable
  defect. The outcome must be the final attempt's, a pending correction can stop
  only on the budget or cancellation, and `retries_exhausted` must follow a used-up
  metered retry. Budget stops must be justified by the recorded usage,
  cancellation needs a pending retry or correction, and attempts cannot carry
  evaluator-only failures.
- `rubric-judge/v3`: the protocol hash binds the correction instruction,
  explanations, correctable reasons, attempt count, preservation rule, grade-pinned
  reasons, provider placement and the exact envelope through fixed probes.
- Qualification accepts one correction; any other shape rejects.
- `spec-e2e-report/v7` and `baseline-acquisition/v5` follow the embedded report.
  evaluator.md, e2e.md and acceptance.md record the decision. With no
  compatibility reader, the retained 18 October `spec-e2e-report/v6` reports
  (12:10/12:11 and 15:31/15:33) can no longer be read by human adjudication or
  feasibility evidence. Adjudicate a v7 report from a new run.

**Known limit.** The validator reports the first defect only. A second defective
readable result cannot be changed, so such a judgment ends as `invalid_judgment`.
Missing, unknown and absent results can be fixed alongside the named defect. Both
observed failures had a single defect.

**Regression evidence** (`test/harness/tests.zig`, `grader_qualification_test.zig`):
- A missing-evidence judgment is corrected once and graded, with `retry_limit` 0.
  The correction resends the same model, instruction, schema and documents, then
  the diagnostic and the rejected response; the Bedrock body carries them once.
- Every listed mechanical defect gets one correction; repeating it ends with no
  grade. Score, explanation and disposition defects get none, and a valid low score
  is graded as is. The correctable set is pinned against the closed reason list.
- A correction that keeps the low sibling score is graded; one that raises it is
  rejected as `changed_criterion`. After a shape defect, the readable sibling is
  preserved the same way; unparseable JSON is constrained by validation alone.
- Fixing an invalid line reference while raising that criterion's score is
  rejected; fixing the reference alone is graded. Missing-criterion, count and
  missing-specification-evidence defects are corrected. Duplicates are final in
  every count and order. Correction requests carry the shared response-format
  framing once for both providers. A duplicate behind a shape defect is final; a
  root-array response gets the documented validation-only correction; a changed
  sibling explanation, evidence or absence claim is rejected; and corrected,
  budget-stopped, duplicate-stopped and regraded reports round-trip through the
  reader.
- Budget exhaustion prevents the correction. A transient failure of the correction
  request retries the same request within `retry_limit`, or exhausts it.
- The trace retains the correction request. Forged attempt sequences are rejected:
  a correction first, after a content defect or without a defect; two corrections;
  a judgment after a defect; a diagnostic without `invalid_judgment`;
  `changed_criterion` outside a correction; an unmetered or over-limit retry; and
  an outcome that is not the final attempt's.
- A report with one mechanical correction still qualifies. A correction after an
  uncorrectable defect, or a second correction, does not.

**Validation:**

| Command | Result |
| --- | --- |
| `zig build test-rubric-evaluator --summary all` | 3/3 steps; 398/398 tests. |
| `zig build lint` | Pass. |
| `zig build verify -j2 --summary all` | 168/168 steps; 1,906/1,906 tests, including clean packaged-executable checks. |

No live grading ran; whether GPT-OSS-20B fixes its own evidence omission is still
unmeasured.
