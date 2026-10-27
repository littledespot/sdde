# Z_FIX05 — Completed FIX05 work and dated evidence

Moved from FIX05 on 23 and 26 October 2026, and on 28 October 2026 when FIX05 was retired
(§21, with an ID map). [FIX06](FIX06.md) keeps the open work; this file keeps completed
implementation, dated live diagnostics and the full decision records, under their original
FIX05 IDs and headings.

This record is historical. Its proposals, status statements and checklists grant no
approval and establish no live acceptance. Accepted contracts and ADRs remain the
governing authority. Section references in the moved text use FIX05's numbering when the
text was written: §1, §6, §8 and §§9–17 are reproduced here under the same numbers, and
§§2–5 and §7 remain in FIX05.

## Contents

- [§1 Live diagnostics, 16–18 October 2026](#1-live-diagnostics-1618-october-2026)
- [Decision records, 22 October 2026](#decision-records-22-october-2026): A1, A2, A3, A6 and
  W3
- [Completed brittleness items](#completed-brittleness-items): B2, B3, B4, B5, B6, B7's
  original record, B8 and B9
- [Completed workflow items](#completed-workflow-items): W1 and W2
- [R8 record](#r8-record)
- [§6 Recommended order as of 22 October 2026](#6-recommended-order-as-of-22-october-2026)
- [§8 Record history to 22 October 2026](#8-record-history-to-22-october-2026)
- §§9–17 implementation records, 17–21 October 2026:
  [§9](#9-b4b9-implementation--17-october-2026),
  [§10](#10-advisory-assignment-verdict-restriction--18-october-2026),
  [§11](#11-grader-envelope-no-output-allowance-and-provider-stop-logging--18-october-2026),
  [§12](#12-partial-member-name-prefix-normalization--18-october-2026),
  [§13](#13-grader-evidence-by-line-locator--18-october-2026),
  [§14](#14-assignment-membership-at-response-admission--18-october-2026),
  [§15](#15-grader-one-shot-correction--18-october-2026),
  [§16](#16-model-maximum-output--18-october-2026) and
  [§17](#17-e2e-grader-removal-and-assistant-evaluation-skill--19-october-2026)
- [§18 Offline test performance P1 and P9, 24 October 2026](#18-offline-test-performance-p1-and-p9--24-october-2026)
- [§19 FIX05 records moved on 26 October 2026](#19-fix05-records-moved-on-26-october-2026):
  the 25 October state and runs, A1's settled choices and slices 1–3, B4's configured
  budget, B5's and B7's records, B9's runaway evidence and decision, the §6 sequence to
  26 October and the 23–25 October history
- [§20 ADRs 0039–0043 and live runs, 26 October 2026](#20-adrs-00390043-and-live-runs--26-october-2026)

## 1. Live diagnostics, 16–18 October 2026

| Measure | Value |
| --- | --- |
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
| §16 live diagnostics, 18 October (AEDT), committed `3e53153` | Both cases publish (25 calls / 66,297 and 31 / 97,475 tokens). Both grades end `invalid_judgment` after the §15 correction: each first judgment cites no source lines for three criteria, the validator names only the first, and the correction may change only that one. The user then removed the grader from E2E (§17). |
| B2/W1 live diagnostics, 17 October (AEDT), committed `b4c7b07` | Neither reaches review. Hello-world blocks on the token-only record batch again (11 calls, 17,754 tokens); loan-renewal fails at its first record batch on the provider output limit after runaway entity output (10 calls, 32,333 tokens). Neither publishes (§1). |

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

## Decision records, 22 October 2026

### A1 decision record

**Decision** (amends ADRs 0005 and 0012): make one model request a single registered
operation. The YAML still chooses the slot, prompt, schema, context, retry limit and
outcome transitions. The engine owns accounting, authorization, invocation, admission
and lifecycle internally. This keeps visible what is asked and removes kernel
mechanics from project-authored graphs.

The workflow-authoring simplification (former FIX03 Phase 8) and the
architecture-wide responsibility audit (former FIX01 §8) belong to this decision. A
supported no-consolidation decision remains a valid outcome.

**Approved — 22 October 2026; documentation updated, implementation not started.** After
reviewing the pros and cons of keeping the subgraph, the user directed: "A1, replace the
subgraph as suggested, update documentations. do not make any code change yet". The user's
stated goal is simpler workflow YAML.
[ADR 0030](../design/decisions/0030-engine-owned-model-request.md) records the decision:

- **The step.** One `request-model` step per model request, and one `count-model-tokens`
  step per token count. A `request-model` step declares the slot, resources,
  `retry-limit`, `timeout-ms` and every outcome. The count step's contract is deferred.
- **The stages.** A fixed, capability-free kernel orchestrator runs the lifecycle, including
  the request-phase check and the request's own protocol correction, through runner-owned
  child bindings. The runner keeps its duties. Each stage stays a separate action with its own
  narrow ports.
- **What stays in YAML.** Consumers, release, advisory routing, `retain-json-part` and ledger
  initialization. Release stays because sites choose different retirements.
- **Derived, awaiting confirmation:**
  - the kernel-orchestrator form;
  - including token counting;
  - keeping `timeout-ms` as a step parameter;
  - keeping release and advisory routing in YAML.

  ADR 0030 listed them under "Derived under existing rules"; that section became
  "Choices settled on 23 October 2026" when the user settled them.
- **Documents.** These now point to ADR 0030:
  - ADRs 0005, 0009, 0011, 0012, 0016, 0019 and 0023;
  - design.md;
  - contracts §§6.2, 7.3, 12, 13.4, 14, 21, 22, 24, 27 and 28, and the operation catalogue;
  - F0005–F0007 and F0100;
  - diagrams 17 and 21;
  - the E2E harness.

  A contract review corrected the first draft: the missing phase-check stage, the retry
  scopes, capability derivation, the call-site counts and the line estimate.
- **Expected effect.** The 159-line request region goes, including the 61-line body; the
  measure above counted 14 body nodes, and the body now has 16 steps, at
  [spec.workflow.yaml](../design/workflows/spec.workflow.yaml#L1030). Call sites still route
  advisory outcomes and repeat `protocol-prompt` and `timeout-ms`, directly or through thin
  wrappers, so the estimated net saving is about 35–90 lines (3–8%). The larger gains are no
  body copy per future workflow, no runner policing of lifecycle order, and lifecycle changes
  confined to the engine. Model calls, tokens and reliability are not expected to change.
- **Still open.** Implementation, with the offline acceptance in ADR 0030; whether the engine
  should also take over release; and whether non-advisory request steps could omit their
  advisory mappings.

### A2 decision record

**Decision** (node granularity under §§5–6): let one registered operation own a
cohesive stage, such as extraction together with its own admission. Keep single
responsibility at the module and function level. Measure the files touched per
change before and after.

**Approved — 22 October 2026, option (b); documentation updated, implementation not
started.** The user compared two forms:

- (a) keep each small action and hide runs of them behind a fixed coordinator;
- (b) one stage action whose internal steps are ordinary typed functions.

The user put "best possible outcomes" for this proof of concept first and directed:
"update the documentation with the recommendations for option B".
[ADR 0031](../design/decisions/0031-stage-actions.md) records it:

- **The rule.** One registered stage action may own a deterministic sequence of internal steps
  that routes no outcome. Its internal
  steps are functions, each with one responsibility and only the port it uses. Values between
  them are function-local; only stage-edge data is pipeline data.
- **What stays out of stages.** Model requests (ADR 0030), writes, publication, commands,
  clarification persistence, feature-log activation, gate issuers, repairs and every routed
  outcome stay their own actions or YAML transitions. The "extraction together with its own
  admission" example above is therefore narrowed. A stage action never calls a model or reads
  a retained model request; it may process a typed candidate that a separate collect action
  produced.
- **Policy.** AGENTS.md's action, port and testing lines now carry the stage-action wording.
  The unconfirmed read-only limit is kept out of AGENTS.md until the user confirms it.
- **Documents.** ADRs 0003, 0005, 0016 and 0030, design.md, contracts §§5, 6, 13 (13-01), 27
  and 28, F0003 and F0005 point to ADR 0031.
- **Cost recorded.** Absorbed steps are no longer composable from YAML; a different
  combination needs a new stage action and a rebuild.
- **Review.** A contract review added mechanical port narrowness inside a stage, contract-field
  limits, cancellation between internal steps, unchanged failure representation, the
  composability cost and the two-workflow equivalence evidence.
- **Derived, awaiting confirmation:**
  - read-only stages;
  - the absorption rule;
  - ADR 0030's kernel form for model requests;
  - the scope left to A3;
  - the restated W3;
  - `prepare-toolchain` first;
  - offline evidence for structural conversions;
  - the contract-field and model-output limits.
- **Next.** Convert `prepare-toolchain` and record the A2 measure before converting another
  stage.

### A3 decision record

**Proposal:** where an orchestrator's sequence is fixed, as in bootstrap and feature
logging, call typed steps with explicit inputs and outputs. Keep spy tests through a
typed interface. This changes design §14's orchestrator pattern, so confirm its
scope first.

**Approved — 22 October 2026, option (b); documentation updated, implementation not
started.** The user compared two forms:

- (a) a typed orchestrator that keeps the orchestrator and step split;
- (b) one typed engine routine per fixed sequence, in the pattern of ADR 0031.

The user directed: "update the docs around yes, form b".
[ADR 0032](../design/decisions/0032-engine-routines.md) records it:

- **The rule.** A fixed engine sequence is an engine routine in
  `src/application/*_routine.zig`. Each step is a typed function with only the port it uses,
  and values pass as typed arguments. There are no erased child bindings, vtables, shared
  optional fields or per-step envelope tracking. Only the composition root or a runner-owned
  child binding reaches a routine.
- **Order.** Startup (bootstrap, provider config and provider bootstrap) converts first and
  is measured. Feature logging follows only under preconditions: baseline tests for
  cancellation under a lock and the emergency-line count, lock release on every path, one
  emergency line, one finalization owner and the retention order.
- **Out of scope.** The workflow-engine orchestrator, and ADR 0030's request coordinator,
  which keeps its form. Specify invocation becomes an ADR 0031 stage action. The earlier "keep
  spy tests" idea is superseded: routines get fake-port tests.
- **Policy.** AGENTS.md gains the engine-routine line, its testing line and the review-rule
  safe path; "startup graph" becomes "startup routine".
- **Documents.** These point to ADR 0032:
  - ADRs 0003, 0004, 0018, 0026, 0030 and 0031;
  - design.md;
  - contracts §§5, 6, 14, 15, 27, 28 and 29, and the 13-01, 13-02 and 13-09 catalogues;
  - F0001, F0002, F0004, F0005, F0006 and F0008.
- **Derived, awaiting confirmation:**
  - the category and location;
  - internal branches on typed facts;
  - reaching a routine through the composition root or a binding;
  - logging second;
  - specify invocation as a stage action;
  - ADR 0030's form kept;
  - fake-port testing.

### A6 decision record

**Decision** (scope): add no contracts for Plan, Tasks or Implement until Specify
publishes on both development cases.

**Decided — 22 October 2026, with a higher bar.** The user directed: "The plan will not
start until spec workflow is stable and producing high quality output".
[ADR 0034](../design/decisions/0034-spec-quality-gate.md) records it:

- **What waits.** No Plan, Tasks or Implement contracts, workflow definitions or code until
  the gate passes.
- **Quality** means each counted published specification passes R8 human adjudication.
- **Stability** means repeated runs of both cases on one committed build, counting every
  attempted run.
- **There is no fixed run threshold.** The user judges the evidence and decides when Plan is
  actioned ("I will decide, when plan must be actioned, no need to ask again").
- **Status on 22 October.** The gate isn't met: no run has been adjudicated, and since
  20 October loan-renewal has published in only 2 of 6 attempts.

The proposal above, applying the §7 evidence rules to every contract change, stands.

### W3 decision record

**Decision** (under A2, after A1): give each owning stage one repair operation that
performs its authorization, input, request, parse and merge internally. Keep every
owner's authorization and merge rules. The YAML keeps only the outcome edges.

**Needs restating (22 October 2026).** As written, this puts a model request inside one
operation, which ADR 0030 (one `request-model` step per request) and ADR 0031 (no model
call inside a stage action) both forbid. ADR 0031's derived choice 5 proposes the form that
fits:

- an authorize action as its own YAML step, because it has a repair role and routes
  `more`, `invalid` and `blocked`;
- optionally, a stage action that builds the repair input;
- a `request-model` step;
- separate parse and merge actions.

That restated W3 needs its own decision. (Decided below.)

**Approved — 22 October 2026, as generic repair operations; documentation updated,
implementation not started.** The user directed: "update the documentation on the yes, ass
suggested". [ADR 0033](../design/decisions/0033-generic-repair-operations.md) records it:

- **The rule.** Four generic operations, `authorize-repair`, `build-repair-input`,
  `parse-repair` and `merge-repair`, replace the 29 per-owner ones. Each takes a closed
  `owner` enum, selected only through an exhaustive switch. The `owner` is checked against
  native facts and selects no policy, scope or defect identity. Owner rules stay in owner
  modules.
- **Today's counts.** "Eight routes" above is the count at `b2f10a3`. Today there are 29
  per-owner operations, which become 29 variants across 13 owners, and 7 repair model-call
  sites.
- **Contract variants.** Each operation's contract is a set of complete per-owner variants,
  each validated independently: outcomes, all data effects, association, role, retry
  authority, maximum and key population. That keeps today's differences:
  - the no-model `more` paths;
  - the three reconciliation authorizers;
  - source omission's two merges, as separate owners;
  - coverage's `blocked`/`failed` only;
  - specification support's `merge_validate`;
  - merges that forbid or require a `retry-limit`.
- **A mismatched `owner`** is a terminal runner rejection.
- **Retry identity.** The compiled step instance, as the code already keys it.
- **Unchanged.** `request-model`, release and the advisory repair stops stay YAML steps,
  and every repair boundary rule is unchanged.
- **Sequence.** Converts after ADR 0030 is implemented and ADR 0031's first conversion is
  measured. All Specify owners convert in one change, on offline equivalence evidence.
- **Documents.** These point to ADR 0033:
  - ADRs 0005, 0023 and 0031;
  - design.md (§22 summary, §32);
  - contracts §22.1, §22.7, §14.4 and the §13.4 repair entries;
  - F0005 and F0100.
- **Derived, awaiting confirmation:**
  - owner-specialized contracts;
  - the 13-owner list;
  - the `owner` check;
  - "compiled operation" meaning the step instance;
  - the §22.1 reading;
  - advisory stops outside the four operations;
  - one Specify-only conversion;
  - offline evidence.

## Completed brittleness items

### B2 records

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
amendment. The maximum-output change is implemented offline (§16).

**Record families implemented offline — 20 October 2026.** The user confirmed the
scope: the three collection-coverage subjects, the brief, the story, entity
applicability and reference subjects keep their own assignments; entity records form
their own family; a family above the 1,024-member choice bound gets a typed failure
and is never split; restatements conform and only `specification-state` advances
(to v19). The grouping key in `specification_review_subject.zig` changed from record
ID to record kind; the ledger's kind-major order makes each family one contiguous
member run, so admission, correction, atomic stop, retention and stored validation
follow unchanged. Each member now carries its own record in its subject instead of
one hoisted assignment record. ADR 0023 ("Record families"), §§12, 17.3, 22.4, 24 and
28, the §32 index, F0100, diagram 21 and `support.prompt.md` match.

- **Bound and memory.** An over-bound family now fails with the schema owner's
  closed `ChoiceBoundExceeded` error before any member packet is built, through one
  predicate shared with the schema restriction. It previously failed later, at
  request handoff, as `InvalidModelRequestSource`. Each member's
  single packet is built in its own arena, and only its entry is kept. Before this,
  building a 1,024-member family held about 6 GB of repeated shared evidence.
- **Tests:**
  - accepted: a two-criterion family, two-entity and two-requirement families,
    separate entity applicability, per-member records, the bound control;
  - rejected: a response covering one complete record of a family, family-only
    start, a stop forged at a record boundary inside a family (with a valid-boundary
    control), an over-bound family, and v18 state.
- **Baseline harness.** It now verifies `assignment_findings` and
  `principle_assignment_findings`. It had recognised only the removed
  `record_findings`, so batched review output was always unmeasured.
- **Still to measure live.** Each member repeats its own record, roughly 18 KB more
  for a 21-criterion family, against the saved shared context. No live run has
  measured the net cost change yet.

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

### B4 records

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

### B5 token-only record batches

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

### B6 GPT-OSS envelope prefix

- The GPT-OSS envelope-prefix malformation (`{"token{`) recurs. It recurred at
  hello-world call 2 on the B3 build, and the protocol retry corrected it.
  **Resolved 18 October 2026:** the user approved normalizing the truncated
  member-name form after it appeared in 6 of 20 source-review responses in one run,
  causing 5 retries and one exhausted assignment (§12).

### B7 original record

Superseded on 21 October 2026 by the list-item extraction trial and its revert; FIX05 B7
records both.

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

### B9 records

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

## Completed workflow items

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

## R8 record

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

**Amended 19 October 2026 (§17):** the advisory grader is removed from E2E. Human
adjudication is the only rubric evaluation of a published run; GPT-OSS-20B grading
and the calibration panels remain with the standalone supplied-spec evaluator.

## 6. Recommended order as of 22 October 2026

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
   - Done offline: each Bedrock model's documented maximum output is sent, for
     generation and the grader (§16).
   - Done offline: the grader is removed from E2E, and the `/evaluate-e2e` skill gives
     advisory rubric and defect-origin analysis of retained runs (§17). The 22:22 and
     22:25 v8 reports can't be adjudicated; adjudicate a v9 run.
   - Done offline: source review assigns one record family per call (B2 approval of
     18 October, implemented 20 October). Measure its effect on loan-renewal's
     budget in the next separately approved pair.
   - Done offline: route 4 in §14 is a typed response-admission defect (ADR 0023,
     20 October 2026).
   - Adjudicate its reports under `human-spec-adjudication/v2`.
   - Address B7, which also drives loan-renewal's record duplication.
   - Repeat both cases before claiming improvement (§7).
5. Consider A4's broader evidence gaps and W5's identical sibling steps separately
   from the debugging-only A4 scope above.
6. The experiment's Phase 2 budget/scope decision remains separate from B4's
   implementation. Its single-pool plan stands, because there is one total limit.
7. Decide A1–A3, W3 and A6's scope freeze before starting Plan. Implement A1 before
   adding operations for another workflow. A1 was decided on 22 October 2026
   (ADR 0030); its implementation is pending. A2 was decided the same day as option (b)
   (ADR 0031); its first conversion, `prepare-toolchain`, is pending. W3 now needs
   restating to fit both. A3 was decided the same day as option (b) (ADR 0032); its
   first conversion, startup, is pending. W3 was restated and decided the same day as
   generic repair operations (ADR 0033); it converts after A1 and A2's first conversion.
   A6 was decided the same day with a higher bar (ADR 0034). Plan starts only once the
   Spec workflow is stable and producing human-adjudicated, high-quality output on both
   cases, and the user decides when Plan is actioned. There is no fixed run threshold.
8. Freeze the Phase 2 baseline under B4's decision. Measure W4 on retained captures,
   and run B5's A/C comparison only if generation-boundary failures remain. If ADR 0030
   advances a capture or event contract, measure W4 before A1 lands, or from raw response
   bytes.
9. Treat R2 as a separate required feature. Decide R1 before promising stronger
   provenance. Gather R6 and R7 evidence after B2.

## 8. Record history to 22 October 2026

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
- **19 October 2026, E2E grader removal:** the user removed the advisory grader from
  E2E only and asked for a Claude Code evaluation skill that yields engine and prompt
  improvements. Added §1's §16 live diagnostics, §17 and the R8 amendment, and
  updated §6.
- **18 October 2026, grader locators:** approved option D. Added §13 and updated §1
  and §6.
- **18 October 2026, model maximum output:** added §16 and updated the B2 approval
  note and §6.
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
- **22 October 2026, A1 decided:** the user approved replacing the request subgraph with one
  engine-owned step per model request. Added ADR 0030 and the A1 approval record, pointed the
  governing documents to it, and updated §6 item 7. No code or workflow YAML changed.
- **22 October 2026, A2 decided:** the user approved option (b), stage actions whose
  internal steps are typed functions. Added ADR 0031 and the A2 approval record, changed
  AGENTS.md's action, port and testing wording, and pointed the governing documents to it.
  Also marked W3 as needing restatement and narrowed the §4 publication note. No code or
  workflow YAML changed.
- **22 October 2026, A3 decided:** the user approved option (b), typed engine routines for
  fixed engine sequences. Added ADR 0032 and the A3 approval record, changed AGENTS.md's
  startup, routine, testing and review-rule wording, and pointed the governing documents to
  it. No code or workflow YAML changed.
- **22 October 2026, W3 decided:** the user approved generic repair operations with
  owner-supplied rules. Added ADR 0033 and the W3 approval record, and pointed the governing
  documents to it. AGENTS.md was unchanged, because its shared-mechanism rule already covers
  this. No code or workflow YAML changed.

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
- State was then `specification-state/v18` (v19 since 20 October); workflow reports were
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
resolved is therefore §10's move again: it cannot remove a valid verdict from a
sibling member.

**Route 4 implemented offline — 20 October 2026.** The user chose to treat it as a
typed response-admission defect: protocol correction of the whole assignment, with
exhaustion ending that assignment's advice as incomplete. ADR 0023 ("Unresolvable
positive verdicts at response admission") records the amendment, and §§12.2, 12.7,
17.3 and 22.6 match.
- **Premise checked again.** Record families did not break the uniformity above.
  A record always binds its own provenance, and the specification validator refuses
  a record with no effective claim. The reachable case is a coverage subject whose
  collection has no records, such as acceptance criteria or scenario coverage when
  only functional requirements are authored. One integration scenario reaches it.
- **Mechanism.** `specification_support_model.resolves` exposes the
  canonicalization rule, which no longer duplicates it. The assignment packet
  withholds each unresolvable positive verdict with the existing excluded-variant
  restriction and omits its guidance rule. One withheld set per assignment
  replaces the former `not_applicable`-only flag. Members that disagree are
  refused before invocation. A withheld verdict rejects at admission as
  `unknown_variant`. Request descriptions record the restricted provider schema,
  which already omits withheld verdicts, so `model-request-debug` stays at v9.
- **Follow-up review (20 October 2026).**
  - The integration driver now checks that every required-review subject resolves
    a positive verdict, so the "required review is unchanged" premise is enforced.
  - `ChoiceBoundExceeded` belongs to the support contract. Only principle
    assessment's two forwarding wrappers name it.
  - The unit test also covers an acceptance-criteria-only candidate, whose empty
    collection is functional requirements.
- **Tests:**
  - accepted: negative verdicts are admitted for the unresolvable subjects, and
    the functional-requirement collection and its record family keep `supported`;
  - rejected: `supported` and `not_applicable` fail admission for both
    acceptance-criteria and scenario coverage, across two unrelated sources;
  - the integration driver now derives the expected variants and guidance from
    the same predicate;
  - the test fails when resolution is not checked.
- Required review is unchanged; its subjects all resolve.

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

## 16. Model maximum output — 18 October 2026

**Decision.** ADR 0011 had removed every output allowance on the premise that an
omitted Bedrock `maxTokens` applies the model's own maximum. The 10:44 loan-renewal
run disproved it: call 22 sent no allowance and stopped at exactly 4,096 output
tokens (`stopReason: max_tokens`). On 18 October the user chose to "Send model's max
output", extended it to the grader ("yes, allow the max"), and, after the contract
review found retained runs that reached a 16,384 allowance on this model and
region, chose 16,384 over 16,000 for `openai.gpt-oss-20b-1:0` (AWS documents
"16K"). The user also chose to record the maximum in the frozen protocol and check
it.

**Change:**
- **Catalogue.** Each Bedrock catalogue entry requires
  `config.maxOutputTokens`: positive, exact, with no default, lookup or clamp
  (`llm_provider_config_schema`, `ValidatedProviderConfig.aws_bedrock`).
- **One maximum type.** The value is a `ModelMaximumOutput`: one non-zero integer
  admitted only through its single parse rule. The catalogue, persisted
  descriptions, grader configuration, frozen protocol and encoder share it, so no
  decoder re-checks zero by hand. Its wire form is one integer-written JSON number,
  as the catalogue requires, whichever JSON decoder runs. `strict_json` checks a
  wrapper's declared scalar wire kind before its parse hook runs. A wrapper that
  declares a wire kind without a parse hook, or names a non-scalar kind, fails to
  compile.
- **Encoder.** Every Bedrock inference request sends it as
  `inferenceConfig.maxTokens`, after `temperature`; CountTokens carries none. The
  adapter takes the value from the selected binding, so no slot or request can
  narrow it.
- **Replay.** Request descriptions advance to `model-request-debug/v9`, whose
  provider configuration carries the value, so replay sends the same request. No
  v8 reader remains. Production replay authorization compares a description with
  the current binding through one `Description.matchesBinding`, so a capture
  whose maximum or region no longer matches the catalogue is refused.
- **Grader.** `evaluation-config/v2` requires the judge model's
  `max_output_tokens`, sent as Bedrock `maxTokens` or OpenAI `max_output_tokens`.
  The reports that embed that configuration advance: `evaluation-report/v6`,
  `spec-e2e-report/v8` and `baseline-acquisition/v6`. No retained report uses the
  superseded labels.
- **Persisted descriptions.** A description recording a zero, negative, quoted,
  fractional or nested maximum is refused at readback by the same type.
- **Shipped configs.** The shipped catalogue, design example, E2E evaluator config
  and packaged smoke config record 16,384.
- **Frozen protocol.** The semantic-simplicity protocol advances to schema 2 with
  a required `max_output_tokens` of 16,384. Frozen-binding checks compare the whole
  provider configuration and the sent `maxTokens` against it, so a drifted
  catalogue maximum is rejected before transport.
- **Historical evidence.** Attribution replay reads retained v5 captures through
  an explicit historical provider configuration. Retained v5 request bytes are
  reproduced exactly, except that the retired allowance is replaced by the frozen
  model's maximum. That maximum is read from the frozen protocol. The source-loss
  projection resolves it from the shipped catalogue through the production decode,
  registry build and validation, so no code literal restates the value.
- **Docs.** ADR 0011 (new "Model maximum output" section), ADR 0019, ADR 0023,
  design invariant 32 and §31.12, §12, §24, F0006, F0007, e2e.md, evaluator.md,
  acceptance.md and the semantic-simplicity README match. ADR 0011 names the
  catalogue as the authority for the maximum: the engine does not verify the
  recorded value against the provider.

**Open points from the contract review:**
- **Shipped value: resolved.** The user switched to 16,384 after the review found
  retained runs that reached it
  (`test/calibration/authoring-associations/remediations/results.md`, and the
  insertion-presentation request sources).
- **Frozen binding: resolved.** The protocol now records the maximum and the
  binding checks it.
- **Second review: resolved.** A second contract review found nothing blocking.
  Its seven minor findings were all fixed:
  - an allocation failure while reading a frozen wire body stays `OutOfMemory`;
  - three stale doc sentences (evaluator.md, ADR 0011, the semantic-simplicity
    README);
  - two restated 16,384 literals;
  - six scattered zero checks, replaced by `ModelMaximumOutput`;
  - an untested production replay match, now `Description.matchesBinding` with
    accepted and rejected tests.
- **Third review: resolved.** A third review confirmed those fixes. It found no
  blocker and four minor items, all fixed:
  - a missing `controls` rejection case;
  - float-written maxima (`16384.0`, `1.6384e4`) that strict decoding accepted;
  - no compile-time guard or owning-boundary test for the wrapper wire rule;
  - a stale test comment.

  An optional nit was also applied: the source-loss maximum now uses the full
  registry path.

**Regression evidence:**
- **Catalogue.** It accepts `{"region","maxOutputTokens":16000}` (a test value)
  and rejects a
  missing, zero, negative, oversized, string or fractional maximum, as well as
  unknown fields beside a valid maximum.
- **The value comes from configuration.** Every boundary is proven with 8,192 as
  well as 16,000: the adapter's sent body through the fake transport, the replay
  body from the description, and the grader's Bedrock and OpenAI bodies. Replay
  authorization rejects a description whose maximum differs from the catalogue's.
- **Encoder.** Every registered model's inference request carries exactly
  the configured `maxTokens`, with temperature where supported; Luna's inference
  config holds only the maximum; CountTokens carries none.
- **Maximum type.** `ModelMaximumOutput.parse` accepts 1 through the u32 maximum
  and rejects zero, negatives and out-of-range values. Strict decoding accepts a
  plain integer and round-trips it. It rejects zero, negative, oversized, quoted,
  fractional, float-written (`16384.0`, `1.6384e4`, `16384e0`), `-0`, null,
  boolean, nested and missing values. Plain `std.json` decoding also rejects quoted
  and float-written values. Description readback rejects the same malformed values.
- **Wrapper wire rule.** A `strict_json` test uses an unrelated boolean wrapper. It
  accepts `true` and rejects `false` (refused by the hook), quoted, numeric,
  object, null and missing values. A struct without a declared wire kind keeps its
  closed object shape.
- **Replay authority.** `Description.matchesBinding` accepts the exact binding. It
  rejects a drifted maximum, a drifted region, a non-Bedrock configuration, and a
  changed slot, provider, model, reasoning effort, controls or response mode.
- **Replay and records.** Replay requests carry the description's value. The v8
  label is refused. Integration and compatibility probe requests carry the shipped
  16,384.
- **Frozen protocol.** It rejects a missing, zero or string maximum and schema 1. A
  description or sent body with 4,096, or with no `maxTokens`, fails the frozen
  binding.
- **Grader.** The grader config rejects a missing, zero, negative or string
  maximum. OpenAI and Bedrock grader requests carry the configured value.

**Validation:**

| Command | Result |
| --- | --- |
| `zig build test-provider-conformance test-rubric-evaluator test-e2e-call test-attribution-replay` | Pass. |
| `zig build test-integration --summary all` | 8/8 steps; 127/127 tests. |
| `zig build test-architecture --summary all` | 3/3 steps; 156/156 tests. |
| `zig build verify -j2 --summary all` | 168/168 steps; 1,909/1,909 tests, including clean packaged-executable checks. |

Retained calibration runs show Bedrock accepted 16,384 for GPT-OSS-20B; no run on
this build has yet confirmed it.

## 17. E2E grader removal and assistant evaluation skill — 19 October 2026

**Decision.** Both 18 October 22:22/22:25 runs on `3e53153` published, and both
grades still ended `invalid_judgment` (§1). Each first judgment cited no source lines
for `clarity-testability`, `organization` and `proportionate-business-scope`. The
validator names only the first defect and §15 lets the correction change only that
result, so any judgment with two or more defects cannot be corrected. Seven of the
eight retained first judgments had three or four such defects. Every parsed score
was 4/4 (70 of 70), including on the 22:25 loan-renewal specification, whose
repetition and invented prohibition the rubric names as defects. After that review
the user directed: "remove the grader, only the grader, so add a skill that can be used
to evaluate the e2e tests"; "it should produce meaningful output that can be used to
improve the engine or prompts"; and "make sure only the e2e grader is removed".

**Authority.** No ADR or invariant requires an in-run model grader. AGENTS.md and §28
require rubric evaluation of actual published output, which R8's human adjudication
supplies. The decision amends R8's "GPT-OSS-20B advisory grading" for E2E only
(acceptance.md). Accepted ADR grader text (0011, 0014) governs the standalone
evaluator, which is unchanged.

**Removed from E2E** (`test/harness/e2e/`):
- the judge call, its `TEST_EVALUATION_*` selection and credential, judge
  configuration, grader-qualification inspections, independence check and model
  acceptance gate;
- `spec-e2e-case/v3` drops `evaluation_config`; `test/e2e/config/evaluation.json` is
  deleted;
- `spec-e2e-report/v9` drops `evaluation`, `evaluation_configuration`,
  `grader_qualification`, `semantic_quality` and the `evaluated` and
  `evaluator_failed` statuses. A published run ends `generated` with acceptance
  `human_adjudication_required`. `quality_unresolved` is renamed
  `threshold_unconfigured`: the rubric has no threshold, checked before any send;
- `judge_independence.zig` keeps only the `Result` type the standalone gate reports.
  `fromObserved` (E2E's only use) and the uncalled `fromConfigured` are removed with
  their tests.
- **Resolved 20 October 2026** (user: "remove all legacy or unused code"): the
  standalone CLI passed only `unknown_generation`, and the gate's `decide` ignored
  its inputs. `judge_independence.zig` is deleted. The gate keeps raw quality and
  qualification, and its decision is one unresolved enum (`not_evaluated`,
  `input_changed`, `human_adjudication_required`). `evaluation-report/v7` drops
  `independence` and the never-produced passed or failed decision, and its reader
  rejects v6, an `independence` field and the old decision union. A completed
  evaluation exits 2 as before.

**Unused code removed with it** (no behavior change): the unreferenced canonical
value, provenance and completed-unit replacement functions left by W2's deleted
post-generation repair paths; the test-only prompt-batch API and its runner method;
`claimRequired`, a parallel of `itemRequired`; `recordForGroup`, a parallel of
`record`; `selectGroups`; `parseProposal`, whose closed-type tests now decode
directly; two unused feature-log ID constants; an unused alias, fixture method and
test helper. The evaluator capture's `recorded` and `scripted_generation` origins and
its non-`completed` workflow statuses had no producer and now reject, in place: no
written report carries them, so retained `spec-e2e-report/v9` runs stay adjudicable.
Accessors and test seams used only by tests remain.

**Found, not dead code — unimplemented contract.** Design §26 requires log
retention after recovery and rotation (the only authorized destructive log
operation), and F0002 §6.4 fixes `retentionDays = 14`. `LogService.retainHistorical`
and the filesystem segment-pruner facet have only test callers, so production never
prunes. This needs its own change, not deletion. **Built 20 October 2026** as
[ADR 0026](../design/decisions/0026-header-identity-log-retention.md) (user choice:
header-identity retention). A contract review then found that the first version
skipped invalid groups, contrary to §26.5, and could prune a crashed run's closed
stream. It was reworked:
- invalid prior history blocks;
- a run with an active tail in either stream is kept whole;
- discovery and the under-lock prune share recovery's segment inspector;
- the historical adapter covers one stream and offers lock, prune and release only;
- cancellation while opening stays distinct, and every failure writes the emergency line;
- the runner builds the authorization as its first child step.

A second review led to more changes:
- a last segment torn during creation counts as a crash and keeps its run;
- sequence arithmetic on persisted bytes is checked;
- only the expired ordinal prefix is deleted;
- the current run's unused prune facet is gone;
- multi-segment, crash-shape and coordinator tests were added.

A third review led to these changes:
- a rotation crash (a torn last segment behind closed ones) is tested;
- a lone torn segment must be ordinal 1 and have valid binding directory names;
- torn bytes must be a prefix of the stream's `segment_header` row, within the
  row size limit;
- the binding directory opens beneath the locked run directory;
- a prune failure stays the reported cause when release also fails.

**Amended 21 October 2026** (user decision): a stray regular file in the log folders,
such as Finder's `.DS_Store`, no longer blocks every later run. Two entry classifiers
now serve every listing of `logs/events` and `logs/prompts`: one for collection and
run directories, one for binding directories. The listings they serve are prior-run
discovery, the under-lock check and prune, the current run's recovery and segment
account, and the debugger. They leave alone a regular file whose name is not a
segment name. These still block:
- symlinks and other special entries;
- directories inside a binding directory;
- segment-named files outside one.

The current run's two scans of its other bindings are now one pass.

Two shared logging gaps stay as known work:
- cancellation during segment reads and under the lock is reported as a logging
  failure;
- the lock action reports every acquire failure as a timeout.

Prior-run crash finalization (§14.10) stays open: it needs a persisted bootstrap
authority that does not exist. Similarly, §26 and F0002 name the
compiler-owned `redaction/default-v1` policy, but no code or persisted record carries
that ID; the removed constant was never read.

**Kept:** the standalone `evaluate-spec` evaluator with its correction, qualification,
calibration panels, configuration and environment; rubrics; `rubric-judgment/v2`;
rubric acceptance; `adjudicate-spec`; baseline supplied-judgment scoring. E2E still
captures the exact source, rubric and published bytes as `evaluation_inputs` for
adjudication.

**Version consequences** (no compatibility readers): `baseline-freeze/v2` and
`baseline-acquisition/v7` embed the case and report. None of the 19 retained runs,
including 22:22/22:25, can be read by `adjudicate-spec` (v8 or older reports),
replayed by `e2e-call` (14 `spec-e2e-case/v2` and 5 v1 `case.json` files) or used as
budget-feasibility evidence. Each needs a fresh run.

**Skill.** [`/evaluate-e2e`](../.claude/skills/evaluate-e2e/SKILL.md) reads a retained
run offline. It scores the captured specification against the captured rubric with
line citations and the canonical acceptance arithmetic. It traces each defect to the
generation call that first produced it, classifies the origin, and maps it to the
prompt, schema, composition or renderer `path:line`. It ranks generalized changes
with expected effect, risk and verification, and profiles cost per stage. `--panel`
checks its discrimination against a calibration panel, scoring specimens copied to
opaque names before it reads any label. Output goes to the
Git-ignored `evaluations/` as `evaluation.md` and `evaluation.json`. It is advisory
assistant analysis, not a grade, human review or adjudication input, and it makes no
provider calls.

**Regression evidence:**
- E2E acceptance: a published run is `human_adjudication_required` and passes only
  through a source-bound human judgment. Every non-`generated` status rejects a human
  pass. An unconfigured threshold stays `grading_unresolved`. Rendering names no
  grader or judge.
- Human adjudication reads only v9. A v8 label, or a report carrying any retired
  grader field or status (`evaluated`, `evaluator_failed`, `quality_unresolved`), is
  rejected.
- Baseline freezes reject the retired `config_source`/`config_bytes`; acquisition
  rejects a workflow report carrying an adjudication capture.
- Cases reject `spec-e2e-case/v2` and a retired `evaluation_config` field.
- Integration: the publication handoff captures poor output unchanged, and saved
  reports round-trip the captured inputs. Compatibility and baseline reports carry
  no adjudication capture. The launcher test forwards the generation credential.
- The standalone evaluator's tests and smoke are unchanged and pass.

## 18. Offline test performance P1 and P9 — 24 October 2026

These proposals come from the investigation note
[improve_test_performance.md](improve_test_performance.md) (findings T2, T10 and T12), and
the user implemented them on 24 October 2026. The note requires a proposal to be recorded
in FIX05 before it is adopted; they were committed without that record, and this entry,
added on 25 October 2026, closes the gap. Only test and build code changed; no engine
contract changed.

**P1, untraced leak-checking allocator** (`bf8a297` and `2bafdb0`).

- One owning helper, `src/test_fixtures/untraced_allocator.zig`: a `DebugAllocator`
  without stack-trace capture that still fails the test on a leak.
- `bf8a297` uses it for the integration sweep (`test/integration/workflow_tests.zig`) and
  for the driver's arena backings (`spec_generation_driver.zig`,
  `global_protocol_sequence.zig`).
- `2bafdb0` moves the exhaustive allocation-failure sweeps onto it: 108 call sites in
  46 files. One sweep still uses the traced `std.testing.allocator`:
  `src/adapters/text/unicode_normalization.zig:68`.
- The helper's six regression tests prove that:
  - a scope that frees everything passes, and a live allocation is reported as a leak;
  - a body that keeps an allocation is rejected;
  - a sweep runs every failure index;
  - the helper rejects a counting-pass leak that the standard sweep accepts.
- The note's second phase, replacing every `std.testing.allocator` reference, is not
  adopted.

**P9, opt-in test-run reuse** (`269410b`).

- Default builds still rerun every test. With `-Dreuse-test-runs`, a test run that
  already passed is skipped when nothing in its key changed:
  - the binary, its arguments and its working directory;
  - every Git-listed file, by content and executable bit;
  - the ignored locations listed in `build/test_run_inputs.zig`;
  - the Git revision and the `git` version;
  - `PATH` and `HOME`.
- Each keyed run is confirmed against edits made while it ran. Credential-like paths are
  keyed by size and modification time and are never read. The README documents the
  option.
- `zig build verify` and `./scripts/test-integration.sh` refuse the option, so
  verification evidence always comes from fresh runs. This settles the note's open
  condition on how `/verify` reports cached runs.
- `zig build test-build-reuse` proves these rules in a throwaway repository.

**Effect.** Not re-measured. The note's estimates (its §4) were:

- for P1, about 44% of the unit run and 36% of the integration run;
- for P9, seconds instead of about a minute for an unchanged opt-in rerun.

Re-measure by the note's §5 before relying on them.

**Not adopted.** P2–P4, P6–P8, P10 and P12 remain proposals in the note. P5 and P11 are
withdrawn there.

## 19. FIX05 records moved on 26 October 2026

Moved from FIX05 on 26 October 2026 by user direction, after ADRs 0035–0043 were
committed (`39a06ea`, merged as PR #10). The text is as it stood in FIX05 on 26 October,
so its status words ("uncommitted", "not yet implemented") describe that moment; FIX05
section and item references are to its numbering then.

### Current state as of 25 October 2026


**Done and moved to Z_FIX05.** These are implemented and verified offline. Their live
semantic benefit is not demonstrated (§7).

| Item | State | Record |
| --- | --- | --- |
| B2 | Advisory post-generation review (ADR 0023) and one record family per source-review call; live effect open (B2 below) | [B2 records](Z_FIX05.md#b2-records) |
| B3 | Native exact-value recognition; mechanical live gate closed 17 October | [B3](Z_FIX05.md#b3-exact-value-bookkeeping-is-left-to-the-model) |
| B4 | Option 3 and the single workflow budget. Implemented 25 October, uncommitted: the budget is `.sddtoolkit.json`'s required `workflowTokenBudget`, 125,000 for E2E (ADR 0037). Open: experiment stops and qualified scope (B4 below) | [B4 records](Z_FIX05.md#b4-records), §9 |
| B5 | No record batch for token-only groups (ADR 0024). Implemented 25 October: cross-kind restatement in the native duplicate rule (ADR 0035). Implemented 25 October, uncommitted: records name their claims and a functional requirement's claims need a scenario (ADR 0038). One records call per feature not adopted (B5 below) | [B5 token-only batches](Z_FIX05.md#b5-token-only-record-batches) |
| B6 | GPT-OSS envelope prefix normalized; entity applicability open (B6 below) | [B6 envelope prefix](Z_FIX05.md#b6-gpt-oss-envelope-prefix), §12 |
| B7 | List-item chunking tried and reverted on 21 October. Implemented 25 October, uncommitted: source-quoted claim wording and code-delimiter removal (ADR 0036); the native list-item claim split was withdrawn the same day and reinstated by ADR 0038 (B7 below) | [B7 original record](Z_FIX05.md#b7-original-record) |
| B8 | Native preserved-token bookkeeping (ADR 0024) | [B8](Z_FIX05.md#b8-the-model-classifies-and-disposes-exact-value-tokens) |
| B9 | Feature-owned entity records and no output allowance; runaway class open (B9 below) | [B9 records](Z_FIX05.md#b9-records), §§9, 11, 16 |
| W1, W2 | No post-generation upstream rebuild; the duplicate path is deleted | [W1](Z_FIX05.md#w1-review-can-restart-the-whole-pipeline), [W2](Z_FIX05.md#w2-the-upstream-repair-path-exists-twice) |
| R8 | Acceptance policy implemented offline; adjudication and calibration open (R8 below) | [R8 record](Z_FIX05.md#r8-record), §17 |
| §§9–17 | Implementation records, 17–21 October | [Z_FIX05](Z_FIX05.md#9-b4b9-implementation--17-october-2026) |
| Test performance P1, P9 | Untraced leak-checking allocator and opt-in test-run reuse, implemented 24 October (`bf8a297`, `2bafdb0`, `269410b`); no verify result or re-measurement recorded | [Z_FIX05 §18](Z_FIX05.md#18-offline-test-performance-p1-and-p9--24-october-2026) |

Section references §9–§18 point to Z_FIX05.

**Live runs since 21 October 2026 (AEDT).** Every run in the table used GPT-OSS-20B on
Bedrock, ran once and was separately approved. The eleven Claude Haiku 5.5 attempts of
24 October, all `authorization_denied` before any output, are in the §8 log. Advisory scores are `/evaluate-e2e` analysis under
`evaluations/`, not grades or acceptance.

| Run | Build | Calls / tokens | Outcome |
| --- | --- | --- | --- |
| [Hello-world](../zig-out/e2e-spec/2026-10-20T21-16-50Z-e36938ea061e468db9f9b2c6c5efc94c/report.json), 21 Oct 08:16 | `7a88804` | 25 / 65,896 | Published; advisory 89.29% |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-20T21-29-05Z-984a39676411cca90510cd014f625a4f/report.json), 21 Oct 08:29 | `7a88804` | 25 / 76,501 | Published; advisory 78.57%, below threshold |
| [Hello-world](../zig-out/e2e-spec/2026-10-21T00-38-18Z-b39db999214e70a1e97993ec1f3a5d00/report.json), 21 Oct 11:38 | `2bf5ca6` (B7), modified | 27 / 75,669 | Published; advisory 89.29% |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-21T00-45-18Z-3d0adef9037fc6708573f4b4bf2d3a34/report.json), 21 Oct 11:45 | `2bf5ca6` (B7), modified | 27 / 100,793 | `WorkflowTokenBudgetExceeded` in source review |
| [Hello-world](../zig-out/e2e-spec/2026-10-21T00-55-40Z-871ef5835db845f998a02fa87553dfed/report.json), 21 Oct 11:55 | `2bf5ca6` (B7), modified | 30 / 86,111 | Published; advisory 60.71%, with critical failures |
| [Hello-world](../zig-out/e2e-spec/2026-10-21T07-17-06Z-cbd566225c37b59539b17e81b88d7052/report.json), 21 Oct 18:17 | `2bf5ca6` (B7), modified | 19 / 35,869 | Failed: source-review `timeout` at 60 s (B9) |
| [Hello-world](../zig-out/e2e-spec/2026-10-21T07-40-30Z-35c394a473ad918f326a57351bb1b25a/report.json), 21 Oct 18:40 | `527f870` (B7 reverted), modified | 25 / 67,485 | Published; advisory 89.29% |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-21T07-45-38Z-1bde6e1800ab1c0ef972767b4101a3e9/report.json), 21 Oct 18:45 | `527f870`, modified | 24 / 63,190 | Failed: source-review `timeout` at 60 s (B9) |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-21T07-52-36Z-d390b591aa68651da4e0bf27d99b51ed/report.json), 21 Oct 18:52 | `527f870`, modified | 22 / 56,571 | Failed: source-review `timeout` at 60 s (B9) |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-21T08-13-29Z-c349baea793fb60355880e989bb740d6/report.json), 21 Oct 19:13 | `527f870`, 180 s deadline, modified | 25 / 92,825 | Published; advisory 82.14%; one review call ended `output_limit` (B9) |
| [Hello-world](../zig-out/e2e-spec/2026-10-21T21-30-07Z-73f19805794c3c63535e6c175ec0c103/report.json), 22 Oct 08:30 | `fee2f39`, modified | 24 / 63,918 | Published; not evaluated |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-21T21-31-00Z-aee04c3ee1ac6e061551be002d987027/report.json), 22 Oct 08:31 | `fee2f39`, modified | 32 / 100,763 | `WorkflowTokenBudgetExceeded` in principle review |
| [Hello-world](../zig-out/e2e-spec/2026-10-24T06-49-59Z-172d37237530ce1fdd29108d598ab447/report.json), 24 Oct 17:49 | `8a600d7` | 24 / 63,402 | Published; advisory 89.29% |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-24T06-58-47Z-67dd5ecc82bd3aa1d1ccdc1b6a3be752/report.json), 24 Oct 17:58 | `8a600d7` | 31 / 99,098 | Published, 902 tokens under budget; one bounded protocol correction in source review; advisory 82.14% |
| [Hello-world](../zig-out/e2e-spec/2026-10-24T20-52-24Z-920d6f61f4f754ba0febe016a63a0d73/report.json), 25 Oct 07:52 (step 0) | `269410b` | 24 / 63,013 | Published; advisory 89.29% |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-24T20-52-59Z-2eea9516eda639fe5f16f42ea5f8d431/report.json), 25 Oct 07:52 (step 0) | `269410b`, own principles | 29 / 109,327 | `WorkflowTokenBudgetExceeded` in principle review, after a source-review runaway (`output_limit`, 19,404 tokens) on `Renewal refused.` (B9) |
| [Hello-world](../zig-out/e2e-spec/2026-10-24T22-15-43Z-30b8b0c83633333af9b587cffd04a72f/report.json), 25 Oct 09:15 (B5) | `47723fd` | 24 / 63,479 | Published; advisory 82.14%; no restatement to delete |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-24T22-16-19Z-66cb68e78884933cdbb32c75a15a6314/report.json), 25 Oct 09:16 (B5) | `47723fd` | 25 / 80,195 | Published; advisory 82.14%; no restatement to delete |
| [Hello-world](../zig-out/e2e-spec/2026-10-25T02-14-59Z-affe7e5515d88a93ea871e6cac782617/report.json), 25 Oct 13:14 (B7) | `47723fd`, ADR 0036 uncommitted | 24 / 65,021 | Published; advisory 82.14%; escaped backticks around the greeting |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-25T02-15-01Z-67214efa45244f986e884838c171a5c5/report.json), 25 Oct 13:15 (B7) | `47723fd`, ADR 0036 uncommitted | 27 / 109,967 | `WorkflowTokenBudgetExceeded` in policy review, after a source-review runaway (`output_limit`, 19,270 tokens) on `Loan renewed!` (B9) |
| [Hello-world](../zig-out/e2e-spec/2026-10-25T03-31-56Z-8ad5e999fcf1b2bd4f7c2fdeba3a0fab/report.json), 25 Oct 14:31 (B7 + Decision 6) | `47723fd`, ADR 0036 uncommitted | 27 / 75,877 | Published; advisory 71.43%, critical failure on source-grounding (filler assumption, non-goal and prohibition) |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-25T03-31-57Z-b94ba811af124b3c5fc699618cae4e01/report.json), 25 Oct 14:31 (B7 + Decision 6) | `47723fd`, ADR 0036 uncommitted | 18 / 112,532 | `WorkflowTokenBudgetExceeded` in source review, after a records runaway (294 edge cases) (B9) |

- **Completion.** Hello-world published in 10 of 11 attempts and loan-renewal in 4 of 11.
  All sixteen reports are `spec-e2e-report/v9`, so the published ones can be adjudicated,
  but none has been. No run counts toward the
  [ADR 0034](../design/decisions/0034-spec-quality-gate.md) gate yet. Three pairs (one run
  of each case) used an unmodified committed build:
  - `7a88804` (21 October 08:16 and 08:29 AEDT);
  - `8a600d7` (24 October 17:49 and 17:58);
  - `269410b` (25 October 07:52, the step 0 baseline of §6 step 4).

  The rest were modified builds.
- **Run-to-run variation.** Hello-world's step 0 text differed noticeably from
  `8a600d7`, though nothing affecting hello-world had changed:
  - its title became concise and its BR-001 disappeared;
  - FR-001 gained the startup obligation;
  - the acceptance criterion gained an implementation detail.

  The advisory score stayed at 89.29%. Single runs therefore can't attribute a change, so
  each measurement round needs repetitions (§7).
- **Loan-renewal's own principles.** Principle review judged all 19 subjects `compatible`
  on `269410b`, where `8a600d7` had 4 `conflicting` and 3 `uncertain`. The output wasn't
  admitted, because the budget ran out first.
- **Content.** Loan-renewal's published output still weakens "must be able to renew" to
  "may renew" and has no refusal acceptance criterion (B7). On 24 October FR-001 kept
  "must allow", but the story, a business rule and the entity say "may renew"; FR-001
  covers both refusal conditions, and an edge case now covers the already-renewed one.
- **Budget.** Loan-renewal ran out of the 100,000-token budget in review in 3 of its 8
  attempts (B4). The 24 October run published with 902 tokens left, review taking 81.3%.
  The 25 October step 0 run reached 109,327 tokens after a runaway, and would have
  published under the approved 125,000 budget.
- **Runaway output** caused all three timeouts; the 180 s deadline made it visible (B9).

**Providers.** [ADR 0028](../design/decisions/0028-anthropic-messages-provider.md)
(21 October) added the Anthropic Messages API provider on shared provider owners.
[ADR 0029](../design/decisions/0029-bedrock-model-families.md) (22 October) lets a Bedrock
catalogue entry name any model with a compiled family. The E2E catalogue lists Claude
Haiku 5.5 through both, and the live-test policy permits it for generation. On 23 October
the user chose Claude Haiku 5.5 on Bedrock (`au.anthropic.claude-haiku-5-5`, low effort)
for every E2E slot. All eleven attempts ended `authorization_denied`, because the account
lacks access to the model, and on 24 October the user switched the slots back to
GPT-OSS-20B (ADR 0029, amended; see the 24 October log entry). No live Claude run has
completed. All
live evidence in this record so far comes from GPT-OSS-20B, and which failure classes
are model limitations is unmeasured (R7).

### A1 settled choices and slices 1–3

**Choices settled — 23 October 2026.** The user asked for "the best possible solution,
remember this is a POC and best outcomes is the primary goal", then directed "update docs
with" the resulting table. ADR 0030's "Choices settled on 23 October 2026" records it:

| Choice | Derived on 22 October | Settled |
| --- | --- | --- |
| 1. Form | Kernel orchestrator | **Kept** |
| 2. Token counting | Rebuild as `count-model-tokens` | **Removed**: no workflow, fixture or registered model uses it |
| 3. Deadline | `timeout-ms` on every request step | **Moved to each catalogue entry** as a required `requestTimeoutMs` |
| 4a. Release | Explicit YAML step | **Kept** |
| 4b. Advisory routing | Every step maps all six outcomes | **Only steps marked `advisory: allowed` map `more` and `blocked`**; they may carry both kinds of request |

The global token count is unchanged: the workflow budget, report totals and per-call
usage come from actual inference usage, never from counting. The amendment points ADRs
0005, 0011, 0014, 0019, 0023, 0028 and 0029, design.md, contracts §§6, 9, 12, 14, 27 and
28, the operation catalogue, F0005–F0007, F0100, diagram 16 and the README to it. No code,
workflow YAML or catalogue changed.

**Implementation progress.**

- **Slice 1, freeze — done 23 October 2026 (`5ce2af4`).** The Specify integration matrix
  writes one step trace and summary per scenario to `.zig-cache/workflow-step-trace/`
  (`src/test_fixtures/workflow_step_trace.zig`). A request-lifecycle step inside a request
  wrapper is keyed by its call site plus the stage's operation ID, the form `request-model`
  keeps; a lifecycle body reached without a wrapper fails the run. Each summary records
  the outcome, the canonical rejection diagnostic, step and call counts, token totals,
  every accounted inference (call site, purpose, request and attempt ordinals) and the
  hashes of the published and state files. 195 scenarios: 147 ok, 36 failed, 6 invalid,
  5 needs-user and 1 blocked. Two consecutive runs produced 1,018 identical files. The
  baseline is reproducible by running `zig build test-integration` at `5ce2af4`; a copy
  goes to `evaluations/adr0030-freeze/5ce2af4/`.
- **Slice 2, token counting removed — done 24 October 2026.** The four count
  operations, the `input_token_count` operation kind (`ProviderOperationKind` is now
  `{ inference }`; every persisted kind field stays), the `assign-provider-operation`
  `kind` parameter (assignment takes no parameters and assigns inference), the count
  capability, the `exact_token_count_unavailable` failure cause, the two count data keys,
  Bedrock CountTokens encoding, decoding and endpoint, the provider port's
  `countInputTokens`, every fake and spy count path, the two count test files and their
  build steps, and the packaging smoke's count cases are deleted. Actual-usage accounting
  is unchanged. Tests that looped over both kinds keep their inference case; forged-kind
  rejections became forged-attempt rejections. The inference-then-authorization closure
  test, the option (b) baseline for that case, was converted to a second attempt whose
  authorization fails or is cancelled, rather than deleted. Superseded count text was
  removed from contracts §12, the operation catalogue, F0006, F0007, `code.md`, diagram 16
  and the README; the ADR notes and design.md mark the removal implemented. The Specify
  step traces are identical to the slice 1 freeze, and the production-admission report is
  unchanged. Left for later:
  - ADRs 0006 and 0013 mention optional counting in their historical text; each now
    carries an ADR 0030 pointer (user-approved 24 October 2026);
  - F0007's model table predates ADR 0029's families;
  - trivially true `.inference` guards in files slice 2 did not edit, including the
    harness's now-unreachable `CaptureNotInference`, go with `request-model` (slice 4);
  - a pre-existing conformance case (`provider_conformance_test.zig`, forged operation)
    is rejected for being a copy before its foreign attempt is checked; it needs its own
    fix.
- **Slice 3, deadline in the catalogue — done 24 October 2026.** Every `.sddproviders.json`
  entry's `config` requires `requestTimeoutMs` (a `RequestTimeout` of 1 to 2^32-1 ms, so a
  monotonic deadline can always be formed), read through one `requestTimeout()` accessor;
  the test-only config schema `empty_object` is now `deadline_only`. Authorization
  preparation takes no parameters: the runner binds the request's catalogue deadline to
  every provider operation of the request, including protocol corrections, and a YAML
  `timeout-ms` is rejected at compilation. Replay uses the captured deadline instead of a
  fixed 300,000 ms. Shipped values: 180,000 ms for GPT-OSS-20B and an interim 180,000 ms for
  both Claude Haiku 5.5 entries (B9), 60,000 ms in the packaging fixture's catalogue; the
  frozen calibration protocol records 180,000 ms and advances to schema 4, so an older
  protocol is rejected as a version mismatch (both user-approved). `model-request-debug`
  advanced to v11 and `model-call-evidence` to v3, with v2 and v1 kept readable as
  historical evidence. Retained runs captured before this change can no longer be read by
  `e2e-call`, the compatibility inspection, the baseline or the frozen binding. **Freeze
  recheck:** the Specify step traces and summaries are identical to the slice 1 baseline
  (all 545 entries), and the production-admission report is unchanged; the deadline
  changed nothing observable in the matrix.

### B4 configured budget record

**Done.** Option 3 (one principle assignment per complete principle set) and the single
workflow budget are implemented; since ADR 0037 the budget is the configured
`workflowTokenBudget`. Option 1, a separate advisory allowance,
was withdrawn: there is one total limit. Records are in
[Z_FIX05](Z_FIX05.md#b4-records) and §9.

Input is 93% of tokens. Review sends average about 2,500 input tokens for
single-field subjects. The four response schemas are 11.9–14.1 KB each, with 15–32
definitions.

Until ADR 0037 the 100,000-token budget was compiled into every policy profile and was
not case configuration. The protocol's experiment-wide stops of 1,000 sends and 2,000,000
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

**Approved 25 October 2026: a configurable workflow budget, raised to 125,000 tokens.**
The user directed "make budget configurable and increase to 125000", and set the
priority: "the key of the entire app is to ensure quality … if budget has to be
increased in favour of quality it is fine", then "quality over cost, but never waste".
- Token cost is not a reason to drop or weaken a quality check.
- Spending that buys no quality is waste, to remove at its owner.

This settles the budget half of the decision above.

- **Change.**
  - The single workflow token budget stops being compiled into the policy profiles
    ([core](../src/composition/core_workflow_operations.zig#L35),
    [native](../src/composition/native_workflow_operations.zig#L638)).
  - It becomes a validated configuration value, read once at bootstrap.
  - It remains one total limit for the run, as option 3 left it.
- **Value.** 125,000 in the shipped E2E configuration, which both cases use, and in the
  example configuration.
- **Design points for the ADR.** It amends ADR 0011's budget contract, as ADR 0023
  amended it.
  - Where the value lives: the project configuration or the workflow definition.
  - It is a closed, required, positive value with no engine default (AGENTS.md: no
    fallbacks).
  - Offline tests that exhaust the budget, and fixtures read by the step-trace freeze,
    set their own explicit values, so the ADR 0030 freeze stays comparable.
  - Persisted values that carry the budget, such as a report's
    `token_accounting.total_budget`, take the configured value.
- **Implemented 25 October 2026, uncommitted
  ([ADR 0037](../design/decisions/0037-configured-workflow-token-budget.md)).** The user
  directed "make the token cap an external setting, that is stored and loaded from
  .sddtoolkit.json, to the e2e test set the token cap to 125000".
  - `.sddtoolkit.json` has a required root `workflowTokenBudget`, an integer from 1 to
    4,294,967,295, decoded through the positive-integer rule the catalogue's limits
    now share (moved to `positive_json_integer.zig`). It sits at the root so model-slot
    consumers don't depend on it.
  - The composition root passes it to the pipeline runner's per-execution ledger.
    Policy profiles (nine copies of 100,000) and compiled graph authority no longer
    carry a budget, and the runner's policy cross-check compares capabilities only.
  - Values: 125,000 in the E2E configuration and the example; 100,000 in the baseline
    protocol and unit fixtures; 90,000 in the scripted budget test, which shows the
    ledger reads the configuration.
  - The baseline harness reads the configured value; its feasibility report's field is
    now `configured_workflow_budget` (`baseline-budget-feasibility/v2`,
    `baseline-freeze/v3`). The E2E report is unchanged at v9.
  - Checks: `zig build test` 1,813 of 1,813 and integration 129 of 129 passed.
  - **Live pair, 25 October 18:19** (advisory analyses in `evaluations/e2e/`): both
    published, each at advisory 85.71% with no critical failure; reports record the
    configured 125,000. Hello-world used 61,885 tokens; loan-renewal 98,492, under the old
    100,000 too, so the larger budget wasn't decisive. Loan-renewal's source-review call
    24 ran to the 16,384-token maximum on `Renewal refused.` (B9), and its refusal
    behaviour still has no scenario (B5). Records: 2 per case, no filler.
- **Still open, before any baseline freeze: the experiment stops and the qualified
  scope.** At 125,000 tokens per workflow, the protocol's 2,000,000-token stop covers
  16 workflows, so the Phase 2 feasibility report stays `insufficient`.

**Evidence since 21 October.** Loan-renewal ended `WorkflowTokenBudgetExceeded` in review
at 21 October 11:45 (100,793 tokens) and 22 October 08:31 (100,763), and published at
76,501, 92,825 and, on 24 October, 99,098 tokens (§1). A larger budget gives quality
changes room; on its own it doesn't make review cheaper or runs more reliable.

### B5 records, 24–25 October 2026

Evidence from former F1, F9 and F13:

- Each record batch re-authors the whole feature, which produced competing or
  duplicate records in four runs.
- The group holding only a preserved value gets its own batch.
- One assignment can still require interpreting obligations, choosing record
  families, preserving conditions, building scenarios and entities, and deciding
  whether uncertainty blocks drafting.
- Six model requests precede authoring even on a three-line source.
- **24 October (`8a600d7`).** Each case formed one real group, because extraction merged
  each list into one claim (B7), so each made exactly one records call (call 10). Today's
  per-group authoring and a single collection therefore behave the same on both cases.
  - Native coverage
    ([specification_coverage.zig](../src/domain/specification_coverage.zig)) accepts a
    claim mapped to any target, whether the story, the brief or any record.
  - Loan-renewal's refusal behaviour had no acceptance criterion in all three evaluated
    runs (`7a88804`, `527f870`, `8a600d7`).

**Done.** Token-only groups no longer get a record batch (approved 17 October with B8,
under [ADR 0024](../design/decisions/0024-native-exact-token-authority.md)). The record is
in [Z_FIX05](Z_FIX05.md#b5-token-only-record-batches).

**Original proposal:** compare current per-group records (A) with one complete record
collection (C). Add a purpose-only acceptance-criterion diagnostic (B) or per-family
collections (D) only where measured failures justify them. Run it after B2 and B3,
which change every arm and dominate cost.

**Proposal: one complete record collection with native acceptance-criterion coverage.**
This is the recommended option, recorded on 25 October 2026 by user direction. It
replaces running the A/C comparison and needs a decision and an ADR before
implementation.

1. **One authoring call per feature (C).** It writes the complete record collection, and
   each record names the claims it supports. The engine validates those links, under the
   constraints below.
2. **Coverage that knows record families.** Extend native coverage so that every
   behavioural claim must be cited by at least one acceptance criterion or edge case. A
   gap is a typed defect that takes the existing bounded correction. Context-only claims
   are exempt.

- **Why C over A.**
  - Per-group batches re-authored the whole feature and produced duplicates.
  - Records bind their whole group (R1), so a per-claim check can't be made.
  - Calls grow with group count, which lengthens the chain (B1).
  - C has one author, explicit support links, and a call count that doesn't depend on
    the source's structure.
- **Why native coverage over B and D.** B is model-facing guidance, which the model can
  ignore. Once support links are explicit, coverage is computable, so deterministic code
  owns it. D adds calls without measured need.
- **Why not run the comparison.** On both current cases A and C produce the same single
  records call, so it can't decide anything, and its baseline is blocked on B4.
- **What it depends on to pay off.**
  - **Requirement-level claims.** With one merged claim, one acceptance criterion
    already satisfies coverage, so the missing refusal criterion is still not caught.
    B7's native list-item split, which supplied them, was withdrawn on 25 October after
    the records call inflated with more claims. With C, more claims no longer add
    records calls.
  - **Review headroom (B2, B4).** More claims mean more review subjects. The 21 October
    list-item run exhausted the budget in source review. The approved 125,000-token
    budget (B4) provides headroom; whether it is enough is unmeasured.
- **Cost and risk.**
  - It is a large contract change; the constraints below list what changes together.
  - It amends ADR 0020's group binding, which would settle R1.
  - One larger call has a larger output and an all-or-nothing failure, and a correction
    re-sends the whole collection.
- **Evidence required (§7).**
  - Offline, multi-claim features: a behavioural claim without an acceptance criterion
    or edge case is rejected; an acceptance criterion that paraphrases a functional
    requirement is accepted; context-only claims are exempt.
  - Then repeated live runs of both cases, counting every attempt.
- **Order.** The configurable budget (B4) first, then requirement-level claims (B7), then
  this.

**Implemented 25 October 2026, uncommitted ([ADR 0038](../design/decisions/0038-record-claims-and-scenario-coverage.md)).** The user directed
"implement B5 as per recommendation" and approved four choices ("APPROVED. Implement
B5"). ADR 0038 is authoritative where the proposal above differs.
- **Records name their claims.** Each non-entity record carries `claim_ids`, a native
  unique-subset choice of its batch group's claims. Parsing keeps them in group order;
  validation and readback require an ordered subset of the one group, which stays the
  record's association. Repairs stay content-only.
- **Scenario rule.** In one records response, every claim a functional requirement
  names must also be named by an acceptance criterion or edge case. It is a native
  admission constraint beside `exact_members` (`Coverage` on the records array,
  `uncovered_member` at `/records/<i>/claim_ids/<j>`), so a gap takes the records step's
  existing protocol correction and exhaustion fails. Request descriptions record it for
  replay (`model-request-debug/v12`).
- **Claim granularity.** ADR 0036's list-item split is reinstated (B7).
- **Not adopted.** One records call per feature: a group's scenarios are all in its own
  batch, and both live cases already form one group.
- **Checks.** `zig build verify` on the final tree: 164 of 164 steps, 1,946 of 1,946
  tests (unit 1,817, integration 129). A contract review found no blocker; its findings
  (coverage effects, competing records, harness parity, tests at each boundary) are
  fixed or recorded in ADR 0038.
- **Live pair, 25 October 21:20** (advisory analyses in `evaluations/e2e/`):
  - **Hello-world** published, advisory 82.14%. The split made three claims; records
    named them and passed the scenario rule first time. New: business rules restating
    FR-001 one claim at a time.
  - **Loan-renewal** failed `RepairNoProgress` at the principles-review merge (99,194
    tokens). The scenario rule caught the missing refusal scenario; after two
    corrections the model added the refusal claim to the success acceptance criterion
    instead of writing a scenario (the "links, not meaning" limit). The failure came
    from an `uncertain` principles verdict without citations whose repair made no
    progress, which ADR 0023 keeps terminal. Source review also ran away on
    `Loan renewed!` (B9).
- **Limits.** Prose requirements in one sentence stay one claim. The rule checks links,
  not meaning.

**Implemented 25 October 2026: cross-kind restatement in the native duplicate rule
([ADR 0035](../design/decisions/0035-cross-kind-restatement.md)).** The user answered
"YES" to the recommended option. In the preflight they decided three rules:
- a restatement is deleted only when the kept occurrence covers its evidence;
- an uncovered one is left as today;
- a functional requirement is kept, and otherwise the earlier record.

Same-kind duplicate checks run first, so a competing pair still blocks. A restatement
has its own `restatement` repair rule. The text below is the approved proposal; ADR
0035 is authoritative where they differ. Follow-up: no offline integration scenario yet
exercises a records-batch native delete, whether duplicate or restatement.

- **Today.** `duplicate_record`
  ([specification_generation.zig:291-305](../src/domain/specification_generation.zig#L291-L305))
  compares whole typed content, record kind included, and compares records only with
  other records.
  - Identical text in two kinds passes, and so does a record that repeats the primary
    user story.
  - Its remedy is a native delete of the redundant record
    ([specification_repair.zig:82-87](../src/domain/specification_repair.zig#L82-L87)),
    with old-value and revision preconditions. A delete builds no model request
    ([atomic_repair.zig:128](../src/domain/atomic_repair.zig#L128)).
- **Change.**
  - Compare normalized statement text across the single-statement record kinds:
    functional requirements, business rules, assumptions, non-goals, prohibitions and
    user-visible outcomes.
  - Also compare them against the primary user story, which is never the deleted
    occurrence.
  - Acceptance criteria and edge cases keep today's same-kind comparison.
  - Reuse the native delete and the coverage revalidation unchanged.
- **Evidence.** On `8a600d7`, BR-001 equals the primary user story word for word in both
  cases: hello-world specification lines 7 and 21, and loan-renewal lines 7 and 31.
- **Effect.**
  - It deletes those business rules with no model call.
  - It removes their review subjects, which saves tokens where loan-renewal's budget is
    tight.
  - B7's source-quoted wording would make restatements word for word more often, so this
    rule would catch more of them.
- **Limits.**
  - It catches exact restatement only. Paraphrased filler still passes, such as
    loan-renewal's non-goal restating the one-renewal limit, or a restated prohibition.
  - An entity description identical to the story can't be deleted, because deleting the
    entity would change the entity decision (R6). It needs a bounded rewrite of that
    field, under its own decision.
  - Deleting a record can remove an obligation's last mention in the records:
    hello-world's BR-001 is the only record that says "start successfully". Coverage
    still passes through the story; B5's acceptance-criterion coverage would catch real
    gaps in testing.
- **Evidence required (§7).**
  - Offline, at the rule:
    - a business rule identical to the story is deleted natively, and coverage holds;
    - a functional requirement identical to a business rule loses the later one;
    - an acceptance criterion that paraphrases a functional requirement is kept;
    - an entity description identical to the story isn't deleted.
  - Then repeated live runs of both cases.

| Former phase | Status |
| --- | --- |
| 0 Evaluation protocol | Complete offline: [protocol, cases, specimens and scoring](../test/calibration/semantic-simplicity/README.md) |
| 1 Compatible execution | Live gate passed for the observed first request only ([record](Z_FIX02.md#phase-1-implementation-and-live-gate)) |
| 2 Baseline | [Harness](../test/harness/baseline/cli.zig) implemented; not frozen; needs B4's decision and a committed build (B3's gate closed on 17 October) |
| 3–6 A/C comparison, implementation, qualification, adoption | Not started; the recommended option above replaces the comparison |

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

### B7 records, 21–25 October 2026

Evidence from GPT-OSS-20B runs, 17–24 October:

- **Collapsed lists.** Both sources are Markdown bullet lists of distinct requirements:
  three items in hello-world and five in loan-renewal. Through 20 October, extraction
  returned one claim for each whole list in every sample.
- **Weakened obligation.** Loan-renewal's claim turns "A borrower must be able to renew"
  into "may renew". It happened in at least five loan-renewal runs from 17 to
  21 October, and review judged the weakened text `supported` each time it was reviewed.
  On 21 October at 19:13 it appeared at extraction call 1 and review call 12 accepted it,
  and the published specification had no refusal acceptance criterion. The 18 October
  10:44 publication preserved the obligation.
- **Downstream effect.** With one behavioural claim per feature, every record cites the
  same claim, coverage is satisfied by any record that mentions it, and native checks
  cannot tell distinct duties from paraphrases.
- **24 October (`8a600d7`).** Both cases again extracted one claim per list (lines 5–7
  and 5–9), and loan-renewal's claim again read "may renew".
  - Every later loan-renewal call received both the cited source text ("must be able to
    renew") and the weakened claim. The guidance says that original sources establish
    obligations and that claims are derived evidence
    ([required_authority_description.zig:10-11](../src/domain/required_authority_description.zig#L10-L11)).
  - Yet the story, BR-001 and the entity followed the claim while FR-001 followed the
    source, so the published specification contradicts itself.
  - Review calls 12 and 14 judged the weakened text accurate.
  - The extraction guidance already asks for one fact per claim and for each fact's
    obligation strength to be kept
    ([extraction.context.json:4](../design/workflows/spec/extraction.context.json#L4)).

**Tried and reverted — 21 October 2026.** On the user's instruction "implement B7",
`2bf5ca6` extracted each top-level Markdown list item as its own chunk, under ADR 0027
(`git show 2bf5ca6:design/decisions/0027-list-item-extraction-chunks.md`). Extraction
then returned one verbatim claim per item, but the outcome didn't improve:

- hello-world at 11:38 scored the same advisory 89.29% at 75,669 tokens, against 65,896
  before;
- loan-renewal at 11:45 ran out of budget at 100,793 tokens, against a 76,501-token
  publication before;
- on the same build, a later hello-world run scored 60.71% with critical failures, and
  another failed on a 60 s timeout (B9).

The user then directed "Revert B7, then do a live run". `527f870` reverted it, deleted
ADR 0027 and restored `source_blocks_v1` chunking and `specification-state/v19`. Its
message records the reason: the remaining defects come from generation, which already
received each item as its own requirement and which B7 does not change.

**Status.** Per-item chunking before extraction (ADR 0027) stays withdrawn by that revert.
One pair cannot decide a contract change under §7, so the revert is a user decision, not
evidence that segmentation can't help. Source-quoted claim wording, for the
obligation-weakening half, is implemented
([ADR 0036](../design/decisions/0036-source-quoted-claims.md)). The native list-item split
for the list-collapse half was implemented, withdrawn and, the same day, reinstated by
[ADR 0038](../design/decisions/0038-record-claims-and-scenario-coverage.md): the withdrawal's evidence was misread, since the same five-claim input
produced both 2 and 304 records, and B5's scenario rule needs one claim per requirement. The original record is in [Z_FIX05](Z_FIX05.md#b7-original-record).

**Implemented 25 October 2026, uncommitted (ADR 0036, option 1).** The user directed
"implement B7 with option 1". ADR 0036 is authoritative where the approved text below
differs.

- **Contract.** A model claim is `{category, citations}`, where `citations` is a set of
  line IDs. Admission restricts them to the chunk's citable lines, decided by one shared
  predicate.
  - One function at extraction text validation quotes the cited lines as written,
    Markdown included. A run continues across uncited blank lines and is trimmed only at
    its ends.
  - The list-item split described in the reviews below was withdrawn (see "Split
    withdrawn") and reinstated by ADR 0038 (B5).
- **Deleted.** Claim-text repair (text repair keeps only the `no_feature_claim` reason),
  citation repair, the `source_selections` diagnostic, `business_text_replacement`, the
  `retain-reference-claim-rejection` operation and the write-only claim citation origins.
  `validate-reference-claims` now ends `ok` or `failed`.
- **Defects found and fixed.**
  - In implementation:
    - A citation choice scoped to the `claim` definition couldn't bind the whole
      extraction response, so every initial request would have failed at handoff. The
      initial request now bounds `/claims/*/citations`, and the omission claim repair
      bounds its own `citations`.
    - The source-omission merge kept only the first claim of a split proposal; it then
      inserted every claim. With the split withdrawn, it inserts its one claim again.
  - In two contract reviews:
    - **Rewriting the quote was fragile.** The first draft removed markers and code
      delimiters and changed whitespace. Its line-by-line parsing ignored fenced code,
      multi-line code spans and wrapped numbers such as `2024.`. Some admitted citations
      quoted to nothing and failed the run, words fused and delimiters leaked. A code
      block with a blank line lost its exact-value duty.
      - The quote is now the cited source bytes as written, which removes that class.
      - List structure was given one Markdown owner (withdrawn with the split).
    - **Quadratic cost.** Rebuilding the whole source's scan for every chunk was
      quadratic: 777 MB held at 256 chunks. Each source's fenced code is now scanned once
      per validation.
    - **C1 control characters** passed ingestion but fail the text validator. The
      Markdown reader now uses the typed-text scalar rule.
  - In a third review:
    - Trimming a run's ends could strip a fenced block's own bytes and lose its
      exact-value duty. Code lines are no longer trimmed.
    - Joining runs with a line break could form a JSON insertion object absent from the
      source and fail the run. Runs are now joined by an ellipsis line.
    - Other fixes:
      - Each chunk's first line is found by binary search.
      - The test helpers use the shared citable predicate.
      - List-structure fixes (HTML blocks, one marker parser) went with the split.
- **Tests.**
  - New coverage:
    - quoting, one claim per proposal, including lines cited out of order, a heading with
      a nested list, runs across blank lines, fenced code, leading indentation, and chunks
      starting inside and after a fenced block in two sources;
    - the exact-value duty for a multi-line code span and a fenced block with a blank
      line;
    - an allocation bound across 128 chunks;
    - admission bounds, including blank lines, for the initial request and omission
      repair;
    - rejection of model wording;
    - an omission repair over two list items, inserting one quoted claim;
    - C1 rejection at ingestion;
    - a reason-repair test that keeps the deleted claim-text test's packet, origin,
      progress and stale-authority coverage.
  - Deleted: four unit tests and six integration scenarios for the deleted routes.
  - **Scripted fixtures:**
    - claims cite only citable lines;
    - the omit-exact scenario authors distinct text per claim;
    - the classification-loss scenario keeps its token on an unquoted line;
    - the omission repair cites one line.
  - **Retained GPT-OSS exchange:** the debugger replays it with its retained wire shape;
    the provider-compatibility test now expects the current schema to reject it.
- **Checks.**
  - `zig build test`: 1,809 of 1,809 passed. Fix3's `test-build-reuse` fails only with a
    repository-relative cache.
  - Integration: 129 of 129 passed.
  - `zig build lint`, `zig build test-architecture` and `zig build verify` (out-of-repo
    cache) passed.
- **Open, from the contract review.**
  - Stored readback doesn't re-quote claim text from its citations. It would need the
    Unicode normalizer at readback.
  - Admission caps the citation count but admits a repeated ID; the quote ignores the
    repeat.
  - The extraction reason's text-repair route now has unit coverage only.
  - No synthetic current-schema exchange replaces the retained one's `compatible`
    assessment.
  - Claim wording now carries Markdown (list markers, backticks) into later calls. The
    first live pair showed generation copying backticks around exact values; Decision 6
    removes them at admission. Other Markdown effects are unmeasured.
  - `source_selections`'s typed rejection detail is read only by tests now, and the
    `validate-reference-selections` operation and its value key validate token
    classifications only. Renaming or trimming them was left out of scope.
- **Live pair, 25 October 13:14–13:15, on the uncommitted tree** (advisory analyses in
  `evaluations/e2e/`):
  - **Extraction:** both cases cited a whole list as one claim, and the engine split it
    into one quoted claim per item (3 and 5). Reconciliation grouped each case's claims
    back into one signal.
  - **Hello-world** published at 65,021 tokens, advisory 82.14% (unchanged). Its "should
    output" weakening didn't recur. A new defect appeared: generation copied the
    quoted Markdown and wrapped the greeting in backticks, which render escaped beside
    the exact-value code span.
  - **Loan-renewal** failed `WorkflowTokenBudgetExceeded` at 109,967 tokens, after a
    source-review runaway on the preserved-token subject `Loan renewed!`. This is the
    third runaway on a preserved-token subject (B9).
    - Before failing, its records batch authored 12 records against 2 in the previous
      run, including both refusal conditions as edge cases.
    - Generation still wrote "may renew" in the brief, story and entity, although every
      claim and signal it received said "must be able to renew". The weakening's source
      is now generation.
    - Under the approved 125,000 budget (B4) the run would have continued.
- **Backtick fix, 25 October (user: "apply recommendations as per above", ADR 0036
  Decision 6):** the exact-value recogniser reports equal backtick runs directly around a
  value, and admission drops them with it. The value becomes an exact copy in an
  obligation-bearing field and stays text elsewhere. Nothing else in the text changes.
  - Fixed during implementation: prohibited fields used the unit's lineage for the first
    recognition and every value for the re-check, so their stored value no longer
    matched. They now always use every eligible value.
  - Fixed after contract review:
    - Removing delimiters could join a longer value across the gap, so the re-check
      turned ambiguous and escaped as an untyped error. Delimiters now stay unless
      removing them leaves the same matches, and the re-check reports a typed issue.
    - A backtick between two values could be claimed by both, panicking in a prohibited
      field. It now belongs to neither, and every caller cuts one outer span.
    - Tests now catch both cases and a reverted composition cut.
    - A second review found that repairs recognise with a narrower lineage than the
      re-check, so the guard could approve a removal that the re-check then found
      ambiguous. Removal is now a separate recogniser step, checked against every
      eligible value. A repair-path test catches the narrow-set mutation.
  - Checks: `zig build test` 1,812 of 1,812, integration 129 of 129, lint and
    architecture passed. The typed re-check in `valueIn` has no reachable test once the
    guard shares one set; it stays as a typed outcome.
  - The other open items affect no outcome, so they stay open: readback re-quoting, the
    repeated citation ID and reason-repair integration coverage.
- **Live pair, 25 October 14:31, B7 + Decision 6** (advisory analyses in
  `evaluations/e2e/`):
  - **Hello-world** published, advisory 71.43%, with a critical failure on
    source-grounding.
    - Decision 6 worked: the greeting renders once.
    - The records call added a filler assumption ("system clock is set to UTC"), a
      non-goal forbidding any other output and a crash prohibition. It also wrote
      business rules that restate the quoted claims. Source review flagged the three
      fillers, as advice only and filed as `candidate_omission`.
  - **Loan-renewal** failed on budget. Its records call ran away with 294 edge cases
    (9,318 output tokens) enumerating loan-state combinations, which source review then
    had to assess.
    - This is a new form of the B9 runaway class, in generation.
    - B9's open "cardinality bounds" choice is its owner.
    - The 125,000 budget alone would not have saved it.
  - Across the four B7 runs, generation output varies widely: loan-renewal's records went
    from 12 to 304 (294 of them edge cases), and hello-world's from 3 to 8.
- **Split withdrawn, 25 October (user: "make the changes as suggested").** Quoting stays;
  the native list-item split is removed, so one proposal is one claim again.
  - **Why.** In the four B7 runs the records call authored 3, 12, 8 and 304 records,
    against 2 to 4 for the same cases with one claim per list. The extra records were
    unsupported fillers and restatements, and once a runaway enumeration. The evidence is
    correlational and small; it says requirement-level claims don't pay off while the
    records call is unbounded (B9).
  - **Changed.**
    - [reference_extraction_text.zig](../src/domain/reference_extraction_text.zig) quotes
      each proposal as one claim. It keeps a per-validation cache of each source's fenced
      code blocks, which the quote needs for the code-line trimming rule.
    - `markdown_code_spans.zig` is back to its committed form: `listSegments`, `ListLine`
      and the shared marker parser are deleted.
    - The source-omission merge inserts its one claim.
    - The extraction `citations` guidance again asks for the lines of "the complete
      claim", and drops "and no others", which pushed toward narrow claims.
  - **Tests.** The quoting test now asserts one claim per proposal, including a two-item
    list cited out of order, a heading with a nested list and trimmed indentation. The
    chunk-boundary case uses two sources, with chunks starting inside and after fenced
    blocks; a cache keyed to the wrong source fails it. The omission-repair test inserts
    one claim over two items and checks its quote; the authoring test quotes
    hello-world's whole chunk; the post-generation advice test uses the default
    whole-chunk claim again.
  - **Checks.** `zig build verify` (out-of-repo cache): 164 of 164 steps, 1,941 of 1,941
    tests. A contract review found no code defect; its document and coverage findings
    are fixed.
  - **Live pair, 25 October 16:46** (advisory analyses in `evaluations/e2e/`):
    - **Hello-world** published, advisory 85.71% (71.43% before), no critical failure.
      Extraction itself cited one line per claim; reconciliation merged them. The
      records call wrote 3 records and the native restatement rule deleted one. No
      filler families. The invented entity persists, and review judged it supported.
    - **Loan-renewal** failed on budget at 101,424, after the last source-review subject.
      Generation received one merged quoted claim, yet the records call wrote 40 records:
      five near-repeats of all eight families, fillers included. Native deletes removed
      17 exact copies; 23 reached review. The 125,000 budget would probably have let it
      publish, with filler.
    - Extraction returned five claims each citing all five lines. Under quoting they are
      identical; reconciliation marked four as duplicates.
    - **Reading.** Withdrawing the split didn't stop loan-renewal's records inflation, so
      claim count isn't its only driver. The records cardinality bound (B9) is the open
      owner. Identical citation sets are a new, computable duplicate (decision open).
  - **Open, found in review (predates the withdrawal).** A fenced block whose first or
    last interior line is blank can escape the exact-value duty: citing every other
    line quotes the block without that blank line, so the token's bytes aren't in the
    quote. Whether ADR 0036's "cites in full" means every citable interior line needs a
    decision.
- **Next:** the user decides on the commit, and on B9's cardinality bound.

**Approved 25 October 2026: source-quoted claim wording.** The user answered "YES" to
the recommended option. It needs an ADR amending the §16 extraction contract, written
with the implementation; the native list-item split below is part of the same ADR.

The model keeps the semantic work: it selects each claim's cited source lines and
classifies the claim. The engine supplies the wording, taking each claim's statement text
natively from its cited lines, so no paraphrase can change obligation strength, conditions
or negation. [ADR 0024](../design/decisions/0024-native-exact-token-authority.md) applies
the same pattern to exact values.

- **Why this owner.** The weakened claim adds no information the source lacks, because
  every downstream call already receives the cited source text. It only adds a second,
  conflicting wording, which the model follows despite explicit guidance. Removing the
  paraphrase removes the conflict by construction, without keyword rules, for any
  modality or language.
- **What it fixes.** Obligation changes that start at extraction and are copied
  downstream, which is every observed case.
- **What it doesn't fix.**
  - List collapse: citations are whole lines, so a merged selection stays merged, though
    its wording is correct. The native list-item split below was tried and withdrawn.
  - Repetition across record kinds. B5's cross-kind duplicate rule handles that.
  - Defects introduced at generation.
- **Design points for the ADR.**
  - Normalize list markers and Markdown in the quoted text, and keep ADR 0024's native
    authority for exact values inside it.
  - Claim text validation
    ([reference_extraction_text.zig](../src/domain/reference_extraction_text.zig)) checks
    a source-derived value instead of model prose.
  - Decide whether reconciliation statements and signals, which also restate claims,
    must reference claim text natively. Otherwise they can reintroduce a paraphrase.
  - A cited line that holds two facts stays one claim.
- **Alternatives considered.**
  - Comparing modal verbs between claim and source is a keyword rule. It is fragile with
    negation and phrasing such as "is required to", which AGENTS.md's anti-overfitting
    rule forbids.
  - Review can't fix it. Source review is already told to check obligation strength
    ([required_authority_description.zig:20](../src/domain/required_authority_description.zig#L20))
    and missed it, and under ADR 0023 it can't change the output.
- **Evidence required (§7).**
  - Offline, accepted and rejected extraction fixtures where the proposed text differs
    from the cited source, including negation and conditions ("must not", "only if") in
    unrelated sources.
  - Then repeated live runs of both cases, counting every attempt.

**Approved 25 October 2026, implemented and withdrawn the same day: one claim per source
requirement, by native list-item split.** The user directed "apply the best option" for
B7's list-collapse half, then "make the changes as suggested" to withdraw it (see "Split
withdrawn" above). The approved text follows as history.

- **Change.** When a claim's citation spans more than one top-level Markdown list item,
  the engine splits it into one claim per item. Each new claim:
  - cites its own item's lines;
  - quotes that item's text, under source-quoted wording;
  - keeps the merged claim's category, and the token classifications for its own lines.

  A claim inside one item, a heading claim and prose are unchanged. No model call is
  added.
- **Why this option.**
  - Per-item chunking (ADR 0027, reverted on 21 October) gave the model one item per call.
    That added extraction calls: hello-world rose from 65,896 to 75,669 tokens.
  - Rejecting a merged claim for a bounded correction costs a call per claim, and the
    model can merge again.
  - With source-quoted wording the engine already owns each claim's text. Splitting at the
    source's own Markdown structure is therefore deterministic, works for any structured
    source and costs nothing at extraction.
- **Depends on.** Source-quoted wording, in the same change and the same §16 ADR.
- **Limits.**
  - It acts on explicit structure only. Several requirements in one prose sentence or
    paragraph stay one claim.
  - If the items of one merged claim need different categories, the copied category is
    wrong. The ADR decides whether such a split is rejected for correction instead.
  - Nested list items stay with their top-level item.
- **Cost interaction.**
  - Reconciliation still makes four calls, but signals may form more groups. Until B5's
    single collection lands, each group gets its own records call.
  - More claims and records also mean more source-review subjects. The 21 October
    list-item run ran out of budget in source review.
  - The approved 125,000-token budget (B4) provides that headroom; whether it is enough
    is unmeasured.
- **Evidence required (§7).**
  - Offline:
    - a merged claim over *n* top-level items becomes *n* claims, with each item's text,
      citations, category and token classifications;
    - a claim inside one item, a heading claim, prose and nested items are unchanged.
  - Then repeated live runs of both cases, counting every attempt.

### B9 runaway evidence and re-send decision

**Done.** Approved on 17 October: entity records are authored once per feature with the
applicability decision, and non-entity batches can't emit them. Required `output_limit`
stays a typed failure; advisory `output_limit` closes that advice as incomplete (B4). The
2,048-token output allowance was withdrawn on 18 October, and each request now sends its
catalogue model's documented maximum (16,384 tokens for GPT-OSS-20B; ADR 0011 "Model
maximum output"). Records are in [Z_FIX05](Z_FIX05.md#b9-records), §9, §11 and §16.

Evidence of runaways under schema-constrained decoding at temperature 0.1 (GPT-OSS-20B):

- **17 October.** One record batch wrote 286 mostly invented entity records until the
  output limit. A source-review call broke its JSON close, then emitted about 48,500
  characters of blank lines.
- **18 October 10:44.** A source-review call stopped at Bedrock's then-default 4,096-token
  cap after a whitespace runaway.
- **21 October, 60 s deadline.** Three runs failed on a source-review `timeout` (18:17
  hello-world, 18:45 and 18:52 loan-renewal). A non-streaming response arrives only after
  generation ends, and a 16,384-token response takes about 37–74 s, so the deadline hid
  the cause.
- **21 October, 180 s deadline.** The user raised the request deadline to 180 s
  (`timeout-ms: 180000` in the Specify workflow, committed in `9719dc7`; since ADR 0030
  slice 3 the value lives in each catalogue entry's `requestTimeoutMs`). In the 19:13 loan-renewal run, call 24 wrote a valid `supported`
  finding for `Renewal refused.`, then about 40,000 newline and space characters until the
  16,384-token limit, in 74.1 s. The engine recorded `output_limit`, closed that advice as
  incomplete and published. The call cost 19,402 tokens (21% of the budget). The same
  subject was under review when both earlier loan-renewal runs that day timed out, which
  suggests, speculatively, a subject-linked trigger.
- **25 October, step 0 (`269410b`).** Source-review call 28 reviewed the same subject, the
  exact value `Renewal refused.`. Its reasoning concluded "supported"; it then ran to the
  16,384-token maximum in 69 s, costing 19,404 tokens.
  - That advice closed incomplete. Principle review then pushed the run to 109,327
    tokens, so it ended `WorkflowTokenBudgetExceeded`.
  - This is a second completed runaway on that subject, so the subject-linked trigger
    remains a hypothesis with more support. It isn't established.
- `/evaluate-e2e` found the whitespace pattern on 6 of about 700 retained calls, mostly in
  source review. That count is advisory analysis.

**Decided and implemented 26 October 2026 ([ADR 0039](../design/decisions/0039-configured-temperatures-and-runaway-resend.md)),
uncommitted.** A runaway (`output_limit`) discards its partial text and re-sends
the identical request once at the configured `temperatureRunawayRetry`, outside
`retry-limit`, and logs `model.runaway_resent`. Its response passes exactly the checks
a first response does. A runaway on the re-send fails required work with
`RunawayRepeated`; in review it ends that advice incomplete.
[ADR 0040](../design/decisions/0040-incomplete-review-published-marked-logged.md) then
publishes incomplete review marked as incomplete in `spec.md` and `reference-context.md`,
and logs it as `review.incomplete`, and
[ADR 0041](../design/decisions/0041-failed-run-incomplete-publication.md) makes a failed
required step publish its validated content as a failed incomplete specification, marked
and logged; the run still fails. `.sddtoolkit.json` now requires `temperature` and
`temperatureRunawayRetry` (E2E: `0.1` and `1`). This is the user's recorded exception to
§7's rule against sampling changes and extra retries; it covers only `output_limit`.

### 6. Recommended order as of 26 October 2026

The 17–22 October sequence and its completed steps are in
[Z_FIX05 §6](Z_FIX05.md#6-recommended-order-as-of-22-october-2026). Under ADR 0034, Spec
quality is the critical path, and Plan starts only when the user declares the gate
passed. Nothing below authorizes a live call; each E2E run needs its own approval.

1. **Adjudicate.** No run counts toward the gate until a human adjudicates a published v9
   report under R8.
2. **Measure on a committed build.** Repeat both cases on one committed, unmodified build,
   counting every attempt (§7). Two pairs have used an unmodified committed build
   (`7a88804` and `8a600d7`). Use `/evaluate-e2e` for advisory defect origins.
3. **Model choice is the user's decision (R7).** All live evidence comes from GPT-OSS-20B.
   The user decides when to change or compare models, and B7 doesn't wait on that. If the
   user selects Claude Haiku 5.5, measure its latency for its `requestTimeoutMs` first
   (B9, ADR 0030).
4. **Implement the approved Spec changes (25 October 2026), each with `/preflight`:**
   - first, B5's cross-kind restatement in the native duplicate rule, which is
     independent of the others (done: ADR 0035);
   - the configurable workflow budget at 125,000 tokens (B4), which gives the later
     changes room in loan-renewal's live runs (done, uncommitted: ADR 0037);
   - then B7's source-quoted claim wording, under one ADR amending §16 (done,
     uncommitted: ADR 0036). Its native list-item split was implemented and withdrawn.

   Quality over cost, but never waste (user, 25 October): token cost is not a reason to
   drop a check, and spending that buys no quality is removed at its owner.
5. **Implement the 26 October 2026 decisions, in this order** (approved: "1 yes, 2 yes,
   3 yes, 4 yes", "update with recommendations and implement"):
   - ADR 0039 (configured temperatures, the runaway re-send, its logging and identical
     checks for every retry response) together with ADR 0042 (principle verdicts need
     citations at response admission, and the prompt defines `uncertain`), sharing
     `model-request-debug/v13`;
   - ADR 0040 (incomplete review published, marked and logged);
   - ADR 0041 (a failed or blocked run publishes its validated content marked
     incomplete, `specification-state/v20`);
   - ADR 0043 (model-facing `exact_text` names);
   - then an approved live pair of both cases, reporting runaways, re-sends and
     incomplete reviews separately.

   Progress (26 October 2026, uncommitted, each verified with `zig build verify`):
   ADRs 0039, 0042, 0040 and 0043 are implemented. ADR 0041's mechanism (a declared
   workflow failure output) awaits the user's decision.
6. **Then decide the open Spec failure classes:**
   - B2's finding-type accuracy and false assessments;
   - B4's experiment stops and qualified scope, before any baseline freeze;
   - B5's proposed single record collection with native acceptance-criterion coverage;
   - B9's open choices.
7. **Architecture, in ADR order and independent of 1–6.** Implement ADR 0030 (A1), as
   amended on 23 October, before adding operations for another workflow. Slices 1–3 are
   done; the catalogue deadline already made pre-24-October runs unreadable to replay
   tools, so W4 uses raw response bytes or newer captures. Adjudicate the existing v9
   runs before `request-model` lands if it advances the report contract.
   Convert `prepare-toolchain` (ADR 0031) and record its measure, convert startup
   (ADR 0032), then convert repairs (ADR 0033). Fold A4's closed reasons and A5's rule
   style into each conversion, and check whether a conversion absorbs W5's pairs.
8. **Separate work.** R2 (ADR 0025) is a required feature that hasn't started. Decide R1
   before promising stronger provenance. Freeze the Phase 2 baseline only after B4's
   budget and scope decision. B5's proposal replaces its A/C comparison. Gather R6
   evidence after B2's live effect is measured.

### 8. Record history, 23–25 October 2026

- **23 October 2026, completed work moved:** the user directed updating this record and
  moving completed items to Z_FIX05.
  - Moved: §1's dated diagnostics; the A1–A3, A6 and W3 decision records; B2's completed
    records; B3; B4's completed records; B5's token-only change; B6's prefix resolution;
    B7's original record; B8; B9's completed records; W1; W2; R8's record; the 17–22
    October §6 sequence; the §8 history; and §§9–17.
  - Recorded: B7's trial and revert; ADRs 0028 and 0029; the 21 October deadline change
    and runaway evidence; R7's policy change; the 21–22 October runs; the follow-ups
    carried from §§10, 11 and 17.
  - Rewrote §6.
  - Elsewhere: added the design.md §32 rows for ADRs 0028 and 0029, pointed the B3
    links in two calibration READMEs and Z_FIX02 to Z_FIX05, and updated
    `fixes/README.md`, the fix-records rule and `.claude/known-work.md`.
- **23 October 2026, ADR 0030 choices settled:** the user directed the best option for
  each derived choice (A1). ADR 0030 now keeps the kernel orchestrator and YAML release,
  removes provider token counting, moves the request deadline to each catalogue entry as
  `requestTimeoutMs`, and lets only `role: advisory` steps map `more` and `blocked`
  (renamed and made one-directional later the same day; see the next entry). Updated A1,
  A2, B9 and §6, the affected ADRs, design.md, contracts, features, diagram 16, the
  README and known-work. No code, workflow YAML or catalogue changed.
- **23 October 2026, ADR 0030 review fixes:** a contract review of the amendment found
  factual, pointer and wording defects. Fixed: Claude Haiku 5.5's interim 180,000 ms
  deadline, the count-path claim, unconditional retained-evidence breakage, ADR 0012's
  note, contract §9 in the amends list, ADR 0028's named clauses, the catalogue's count
  operations, the replay deadline, an oversized-deadline rejection and line wrapping.
- **23 October 2026, one-directional advisory check:** the review found that
  `assess-support` serves both the required pre-generation review and post-generation
  advice, so a two-directional `role: advisory` check would fail every run. The user
  directed "update documentations" with the one-directional form: a step marked
  `advisory: allowed` maps `more` and `blocked` and may carry both kinds of request, and
  only an advisory request at an unmarked step is rejected, at preparation, before any
  attempt. A second review confirmed it safe against the code. Its framing as two
  `request-model` contract variants was then confirmed (next entry). Updated ADR 0030,
  ADRs 0005 and 0023, design.md, contracts §§12, 28 and the operation catalogue, F0005,
  F0006, F0100, A1 and known-work. No code, workflow YAML or catalogue changed.
- **23 October 2026, shared contract-variant mechanism:** after comparing a shared
  variant mechanism, separate operations, a compiler special case and a union contract,
  the user directed "update the documentation around option 1". ADR 0030 builds one
  mechanism (complete closed variants, one closed selector parameter at compile time,
  per-variant admission, compiler and runner checks against the compiled variant), and
  ADR 0033 reuses it; this confirms ADR 0033's derived choice 1. Updated ADRs 0030, 0033
  and 0005, design.md, F0005, A1, W3 and known-work. No code, workflow YAML or catalogue
  changed.
- **23 October 2026, second review of ADR 0030:** a contract review found ADR 0030's
  selector sentence ("selects no … owner rule") contradicting ADR 0033's owner rules.
  Fixed: the selector grants no policy, scope or defect identity, and each operation's
  ADR owns any rule selection and run-time selector check. Also added optional selectors
  and per-outcome descriptors to the mechanism, registry-wide checks, compiled-graph and
  publication rechecks, testable acceptance cases, and a loss-localization case; updated
  ADRs 0005 and 0033, contract 28, F0005, known-work and a stale Z_FIX05 link. ADR 0033's
  derived choices 2–8 still await confirmation. No code, workflow YAML or catalogue
  changed.
- **23 October 2026, `zig build verify` restored after ADR 0029:** verify failed on `main`
  with 17 failing steps, all from the ADR 0029 change: the baseline harness still built a
  Region-only transport request, the rubric-evaluator smoke expected the error text from
  before `TEST_EVALUATION_FAMILY`, the example catalogue had no `family`, the packaging
  smoke's invalid-Region case used a Region ADR 0029 made valid, a capture test's legacy
  version edit changed the archive row length, and the compatibility test expected the
  E2E configuration to select Claude Haiku 5.5. The user chose Haiku via Bedrock for
  every E2E slot; the other fixes are test and fixture corrections.
- **23 October 2026, ADR 0030 slice 1 (`5ce2af4`, committed with the verify repair):** the
  freeze instrumentation and its baseline; A1 records it and the open points for slice 4.
  The user chose option (b) for the pre-call termination, cancellation and authorization
  failure baseline. Corrected §1, A6 and §6: the first 21 October pair ran on an
  unmodified committed build (`7a88804`).
- **24 October 2026, ADR 0030 slice 2:** provider token counting removed from code,
  tests, build steps and documentation; A1 records the scope, the kept persisted kind
  fields and the converted inference-then-authorization closure test.
- **24 October 2026, ADR 0030 slice 3:** the provider-operation deadline moved to each
  catalogue entry's `requestTimeoutMs`; A1 and B9 record the scope, versions, shipped
  values and the freeze recheck.
- **24 October 2026, Claude Haiku 5.5 route:** the first live Haiku runs on clean `cbabda6`
  (nine attempts, one call and 0 tokens each) all ended `authorization_denied` while the
  account's IAM policy and model access were set up. Runs 8 and 9 showed the AU
  cross-Region profile `au.anthropic.claude-haiku-5-5` routing to `ap-southeast-4`. For the
  user's Sydney-only requirement, `2014df4` pinned the in-Region ID
  `anthropic.claude-haiku-5-5`; run 10 also ended `authorization_denied` (Bedrock 403: "not
  available for this account"). The AWS model card (checked 24 October) lists Claude Haiku
  5.5 in `ap-southeast-2` only through the AU geo and global profiles. The user then chose
  the AU profile, accepting routing to `ap-southeast-4` and relaxing the Sydney-only
  requirement, and the pin was reverted (`7da8ef0`). Run 11, through the AU profile, got the
  same 403, so the denial is the account's access to the model (an AWS Marketplace
  subscription is the likely prerequisite), not the Region. The user then switched every
  E2E slot back to GPT-OSS-20B; ADR 0029 records both changes. All eleven attempts count
  as attempted workloads.
- **24 October 2026, GPT-OSS pair on `8a600d7`:** the first runs since ADR 0030 slices 1–3
  both published on an unmodified committed build: hello-world (24 calls, 63,402 tokens,
  advisory 89.29%, unchanged from 21 October) and loan-renewal (31 calls, 99,098 tokens,
  902 under budget, advisory 82.14%, unchanged from 21 October). §1 and A6 record the pair; neither run is
  adjudicated.
- **24 October 2026, loan-renewal principles:** loan-renewal copied hello-world's principles,
  whose "State Ownership: Keep no application state" made the policy review mark the
  stateful loan behaviour `conflicting` (four findings on `8a600d7`). By user direction the
  case now supplies its own project principles, `test/e2e/wf-002-loan-renewal/principles/`,
  for a "Library Lending" project: same seven files and `toolchain.yaml`, with domain-owned
  in-memory state, atomic operations and typed rejections, and no rule taken from the
  renewal story. Principles reach only the policy review, not generation. Loan-renewal
  principle findings before this change come from hello-world's principles.
- **24 October 2026, test performance P1 and P9 (recorded 25 October):** from the
  investigation note `improve_test_performance.md`:
  - `bf8a297` and `2bafdb0` implemented P1, the untraced leak-checking allocator;
  - `269410b` implemented P9, opt-in test-run reuse, which `verify` refuses.
  They were committed without the FIX05 record the note requires; Z_FIX05 §18 now holds
  it. The note's other proposals remain unadopted.
- **25 October 2026, B7 proposal:** by user direction, B7 records source-quoted claim
  wording as the recommended option, with the 24 October evidence that every later call
  received the source text and followed the weakened claim. It needs a decision and an
  ADR amending §16. §6 now records that model choice is the user's decision, and B7 no
  longer waits on a model comparison.
- **25 October 2026, B5 proposal:** by user direction, B5 records the recommended option.
  It is one complete record collection per feature, each record naming the claims it
  supports, with native coverage requiring every behavioural claim to be cited by an
  acceptance criterion or edge case. It replaces the A/C comparison, which can't
  discriminate while each case forms one group. It needs a decision and an ADR, and it
  depends on requirement-level claims (B7) and review headroom (B2/B4). §1 and §6 point
  to it.
- **25 October 2026, cross-kind duplicate proposal:** by user direction, B5 records the
  recommended option for repetition across record kinds. It widens the native
  `duplicate_record` rule to compare statement text across single-statement record kinds
  and against the user story, keeping its native delete, which makes no model call. It
  needs a decision and is independent of B7, B2 and B4. Known-work's "Record authoring
  duplicates" entry carries both B5 proposals.
- **25 October 2026, approvals:** the user approved three changes. None is implemented
  yet.
  - B5's cross-kind restatement in the native duplicate rule ("YES").
  - B7's source-quoted claim wording ("YES").
  - For B7's list-collapse half, "apply the best option", recorded as a native split of
    claims at top-level list-item boundaries. It adds no model call and builds on the
    quoted wording; ADR 0027's per-item chunking stays withdrawn.

  §1, §6 (a new step 4, "Implement the approved Spec changes") and known-work record
  them. B7's two changes share one ADR amending §16.
- **25 October 2026, budget and priority:** the user approved making the workflow token
  budget configurable and raising it to 125,000 (B4), instead of making source review
  optional. The priority is "quality over cost, but never waste": token cost is not a
  reason to drop a check, and spending that buys no quality is removed at its owner.
  - B4 records the change and its ADR design points.
  - B2 records that source review stays, and that its waste and accuracy remain open.
  - B5 and B7 now name the budget as their headroom.
  - §6 step 4 adds the budget to the approved changes, and step 5 keeps B4's experiment
    stops and qualified scope open.
- **25 October 2026, step 0 baseline on `269410b`:** both cases ran once on an unmodified
  build, as the reference for the approved changes (§6 step 4).
  - **Hello-world** published: 24 calls, 63,013 tokens, advisory 89.29%. Its text varied
    noticeably from `8a600d7` with nothing relevant changed, so later rounds need
    repetitions.
  - **Loan-renewal** failed `WorkflowTokenBudgetExceeded` at 109,327 tokens. A
    source-review runaway on `Renewal refused.` cost 19,404 tokens, the second on that
    subject (B9). Under the approved 125,000 budget it would have published.
  - Its own principles brought principle review to 19 `compatible` decisions, though the
    output wasn't admitted.

  Advisory analyses are in `evaluations/e2e/`.
- **25 October 2026, B5 cross-kind restatement implemented (ADR 0035):** the user's
  preflight decisions were to delete only covered restatements, leave uncovered ones, and
  keep the functional requirement (otherwise the earlier record).
  - **Code:** `restatement`/`restatesStory` in `specification_generation.zig`.
    Restatements run in the session consistency check after every same-kind check, with
    a closed `restatement` repair rule using the native delete.
  - **Tests:** two existing tests now give the deletable kinds their own wording. The
    R46 competing pair still blocks. The scripted complete story in the integration
    fixture gained leading words, so review-advice scenarios don't trip the delete. New
    tests cover the story, superset evidence, ordering and uncovered cases.
  - **Status:** `zig build verify` passes. The integration scenario for a records-batch
    delete remains a follow-up.
- **25 October 2026, B5 live pair on `47723fd`:** both cases published, at advisory 82.14%
  each.
  - **Hello-world:** 24 calls and 63,479 tokens. Its score fell from 89.29% because the
    story wrote "should output" and invented an entity.
  - **Loan-renewal:** 25 calls and 80,195 tokens. It used fewer review calls because the
    model wrote fewer records.
  - **ADR 0035 didn't fire.** Neither records call produced a restating business rule,
    assumption, non-goal, prohibition or user-visible outcome. The pair is therefore
    run-to-run variation, not evidence about B5. B5's effect needs repetitions that
    produce restatements.
  - **Persisting defects:**
    - obligation weakening in the story and entity: "may renew", "should output" (B7);
    - an entity that copies the story or is invented (outside ADR 0035; B6, R6);
    - a paragraph title;
    - no refusal acceptance criterion (B5 collection proposal).
- **25 October 2026, B7 implemented (ADR 0036):** the user directed "implement B7 with
  option 1". Claims are a category and admission-bounded line IDs; one pure function
  quotes their wording and, until its withdrawal below, split them at top-level list
  items. Claim-text and citation repair are deleted.
  - Implementation found and fixed two defects: the citation bound's scope at handoff,
    and the omission merge dropping split claims. A contract review then found four
    major issues and a second review four more. Claims now quote the cited source bytes
    as written, with list structure from one Markdown owner built once per source. The
    reader rejects C1 controls, and the split follows "one claim per item" when a
    heading is cited. The omission bound gained rejected cases. Re-quoting at readback
    stays open.
  - **Documents:** ADR 0036 and the design.md §32 row, ADR 0016's amended-by note,
    F0100 §§3.7–3.8, contracts §§12.7, 13, 16.3–16.4 and 22, text-field composition,
    diagrams 05 and 21, and known-work.
  - **Status:** uncommitted at the user's direction. Unit, integration, lint,
    architecture and full `verify` checks pass.
- **25 October 2026, B7 live pair on the uncommitted ADR 0036 tree:** by user direction,
  before deciding on the commit.
  - **Hello-world** published, advisory 82.14%, with a new escaped-backtick defect.
  - **Loan-renewal** ran out of budget after a runaway on a preserved-token subject.
    Its records now cover each requirement, but generation still weakens "must be able
    to renew".
  - The B7 block records the details.
- **25 October 2026, B7 kept and backtick fix:** the user asked whether to fix or
  abandon B7, and then directed "apply recommendations as per above". B7 is kept. ADR 0036
  Decision 6 makes admission drop the Markdown code delimiters directly around a
  recognised exact value. The text-field composition contract and the §32 row record
  it. The open items that affect no outcome stay open.
- **25 October 2026, second B7 live pair (with Decision 6):** by user direction.
  - **Hello-world** published at advisory 71.43%, with a critical failure from filler
    records; the backtick defect is fixed.
  - **Loan-renewal** failed on budget after a records runaway of 294 edge cases, a new
    B9 form.
  - The B7 block records the details.
- **25 October 2026, list-item split withdrawn:** the user directed "make the changes as
  suggested". Source quoting and Decision 6 stay; one proposal is one claim again, and the
  extraction `citations` guidance again asks for the complete claim. ADR 0036 Decision 3
  records the withdrawal and its evidence. Unit, integration, lint, architecture and full
  `verify` checks pass. The B7 block records the details.
- **25 October 2026, live pair after the split's withdrawal:** by user direction.
  Hello-world published at advisory 85.71% with no filler records; loan-renewal failed on
  budget after a 40-record batch with repeats. The B7 block records the details.
- **25 October 2026, B4 implemented (ADR 0037):** the user directed that the token cap
  be stored in and loaded from `.sddtoolkit.json`, at 125,000 for E2E. The budget is a
  required root `workflowTokenBudget`; policy profiles and compiled graphs no longer
  carry it. The B4 block records the details.
- **25 October 2026, live pair at the configured 125,000 budget:** by user direction.
  Both cases published at advisory 85.71%. The B4 block records the details.
- **25 October 2026, B5 implemented (ADR 0038):** the user approved four choices. Records
  name their claims within their group, a functional requirement's claims need an
  acceptance criterion or edge case (a native admission rule that takes protocol
  correction), and the list-item split is reinstated. One records call per feature is
  not adopted. The B5 block records the details.

## 20. ADRs 0039–0043 and live runs — 26 October 2026

The user decided ADRs 0039–0043 on 26 October 2026 and directed "update with
recommendations and implement". ADRs 0039, 0042, 0040 and 0043 were implemented in that
order, each verified with `zig build verify` before the next, then reviewed. ADR 0041 is
documented but not implemented (FIX05 B10). Everything below is committed as `39a06ea`
and merged as PR #10 (`1261106`). The ADRs are authoritative where this summary differs.

**ADR 0039: configured temperatures and one re-send after a runaway.**
- `.sddtoolkit.json` requires root `temperature` and `temperatureRunawayRetry` (a JSON
  number, zero or greater, no default); E2E sets `0.1` and `1`. `Temperature` became a
  validated value; requests and provider operations record their sampling (`configured`
  or `runaway_resend`), and `model-request-debug/v13` records both temperatures and the
  sampling. Models that take no temperature omit it on every attempt.
- A first runaway (`output_limit` with valid usage, not itself a re-send) admits as
  `invalid` with no candidate. `check-model-runaway` routes it to
  `build-model-runaway-resend`, which builds the identical request with only the sampling
  changed; attempt accounting reserves it outside `retry-limit`, one per attempt. A
  runaway on the re-send fails required work with `RunawayRepeated`; advisory work ends
  incomplete with `provider_output_limit`. Every retry response passes the same checks.
- `model.runaway_resent` (warning) is logged at the re-send's provider-call step, after
  every send check and immediately before the send. The E2E report (`spec-e2e-report/v10`)
  marks each re-send with `resends`.
- The standalone evaluator's Bedrock temperature comes from its own configuration; the
  frozen calibration value is one literal `0.1`, and a frozen experiment rejects a
  re-send capture.

**ADR 0042: principle verdicts need citations at admission.** A generic native admission
constraint (`RequiredWhen` on the governed array, naming its required sibling string
property) rejects an empty list as `missing_required_item`. Principle packets derive the
triggering decisions from `principle_assessment.citationsRequired`; descriptions record the
constraint in v13 and replay reapplies it. The principle prompt gained "Use uncertain only
when a supplied principle applies but compliance can't be decided; if no principle
addresses the subject, it is compatible." The citation-only repair route stays for
invalid citations.

**ADR 0040: incomplete review published, marked and logged.** `spec.md` carries
`**Review status: Incomplete — N of M review subjects were not assessed.** See
reference-context.md for what was not assessed and why.` under its title, which its reader
accepts only in that exact form. `reference-context.md` has a `## Review Status` section for
source and principle review. Each incomplete review logs `review.incomplete`, and the E2E
report lists `incomplete_reviews`.

**ADR 0043: model-facing exact-text names.** A union may declare `model_tags`, making the
declared name the only one the model codec emits or accepts; the reference content kind is
`exact_text`, and model-facing projections name the collection `exact_texts`. The
exact-value harness picks the key by capture contract: `exact_texts` for v13,
`preserved_tokens` for earlier captures.

**Contract review and fixes.** A contract review found no blocker. Fixed with accepted and
rejected tests:
- a first runaway was also logged as `MISSING_FINAL_TEXT`;
- the exact-value harness dropped current captures without native exact scope;
- a workflow could route around the re-send (now a compiler rule; an admission whose
  `invalid` ends the run is exempt);
- the re-send's identity check covered fewer fields than a first attempt's, and the
  one-per-attempt bound lived in the runner;
- `model.runaway_resent` could be logged for a re-send that was then refused;
- harness temperature sources and range check.

Docs were aligned to the code (two actions, `RunawayRepeated`, sampling, `resends`, the
emission point, the compiler rule). Final checks: `zig build verify` 164 of 164 steps,
1,968 of 1,968 tests; lint and architecture passed.

**Live runs** (GPT-OSS-20B, advisory analyses in `evaluations/e2e/2026-10-26T*`):

- 17:57 AEDT: both cases ended `authorization_denied` on their first call (expired Bedrock
  API key), 0 tokens each.
- 18:06, `54ce8fa` modified: hello-world published, 24 calls, 66,358 tokens, advisory
  82.14%; loan-renewal published, 26 calls, 91,129 tokens, advisory 78.57%. Every call was
  admitted first time. Loan-renewal's title was judged `compatible` ("No principle
  addresses naming"), where on 25 October `uncertain` had failed the run, and its refusal
  behaviour had its own acceptance criterion (AC-002) for the first time.
- 19:09, `39a06ea` unmodified: hello-world published, 25 calls, 84,951 tokens, advisory
  82.14%. Source-review call 21 on `Hello, World!` ran to 16,384 output tokens (18,823
  tokens); call 22, byte-identical except `temperature` 0.1 → 1, returned an admitted
  `supported` finding. The feature log shows `model.provider_stopped` (`OUTPUT_LIMIT`)
  then `model.runaway_resent`, with no false missing-answer row. Loan-renewal published,
  26 calls, 89,887 tokens, advisory 78.57%, with AC-002 again.
- Across the four: principle citations on `compatible` findings fell to 17 of 76 (FIX05
  B11); business rules restated FR-001 in every run; "may renew" persisted in
  loan-renewal's story; review took 41–58% of tokens and passed defects.

## 21. FIX05 retired — 28 October 2026

By the user's direction of 28 October 2026 ("review outstanding items that need to be
implemented in FIX05 and move them to FIX06 … move the closed items in FIX05 to Z_FIX05
and delete FIX05"), FIX05 was retired. Its open items moved to [FIX06](FIX06.md), the sole
active fix record, under their original IDs and in one ordered sequence; its closed items,
state snapshots and history are below. The last committed FIX05 text is at `28ff156`
(`git show 28ff156:fixes/FIX05.md`); its 27–28 October additions were never committed and
are preserved here. Section and item references inside the copied text are FIX05's.

### FIX05 item map

| FIX05 ID | Now |
| --- | --- |
| §1 Verdict | [FIX06 §1](FIX06.md#1-why) (summary); [verdict record](#fix05-verdict-and-measures-17-october-2026) |
| §1 Current state | [state on 26–27 October](#fix05-state-on-2627-october-2026) |
| A1 | [FIX06 E1](FIX06.md#e1-engine-owned-model-request-a1-adr-0030-slice-4), [R-A1](FIX06.md#r-a1-engine-owned-release); records: [A1 decision record](#a1-decision-record), [slices 1–3](#a1-settled-choices-and-slices-13) |
| A2 | [FIX06 E2](FIX06.md#e2-stage-actions-a2-adr-0031-and-identical-sibling-steps-w5); [A2 decision record](#a2-decision-record) |
| A3 | [FIX06 E3](FIX06.md#e3-engine-routines-a3-adr-0032); [A3 decision record](#a3-decision-record) |
| A4 | [FIX06 E5](FIX06.md#e5-rejections-say-why-a4) |
| A5 | [FIX06 T4](FIX06.md#t4-architecture-rules-and-replay-a5) |
| A6 | Closed (ADR 0034): [A6 record](#a6-adr-0034-and-gate-status-26-october-2026), [A6 decision record](#a6-decision-record); gate status in [FIX06 §1](FIX06.md#1-why) and [H1](FIX06.md#h1-adjudication-r8) |
| B1 | Merged into [FIX06 §2](FIX06.md#2-rules-for-every-phase) measures; [B1 record](#b1-a-long-fail-closed-chain-of-model-judgments) |
| B2 | [FIX06 Q10a](FIX06.md#q10a-publish-source-review-findings-as-advice-b2), [Q10b](FIX06.md#q10b-simplify-the-source-review-taxonomy-b2), [H2](FIX06.md#h2-review-label-confirmation-b2); [B2 records](#b2-records), [B2 measurement, 26–27 October](#b2-measurement-and-the-reverted-support-line-2627-october-2026) |
| B3, B8 | Closed earlier: [B3](#b3-exact-value-bookkeeping-is-left-to-the-model), [B8](#b8-the-model-classifies-and-disposes-exact-value-tokens) |
| B4 | [FIX06 H4](FIX06.md#h4-experiment-stops-qualified-scope-and-the-formal-baseline-b4-b5); [B4 records](#b4-records), [B4 configured budget](#b4-configured-budget-record), [B4 to B6 notes](#b4-b5-and-b6-26-october-2026) |
| B5 | [FIX06 Q1](FIX06.md#q1-remove-the-rejected-patches-and-take-the-clean-baseline) (D1.2), [Q6](FIX06.md#q6-scope-the-obligation-instruction-to-obligation-bearing-fields), [Q8](FIX06.md#q8-source-claim-granularity-b7), [H4](FIX06.md#h4-experiment-stops-qualified-scope-and-the-formal-baseline-b4-b5), [T3](FIX06.md#t3-coverage-gaps-b5-b7); [B5 records](#b5-records-2425-october-2026), [B4 to B6 notes](#b4-b5-and-b6-26-october-2026) |
| B6 | [FIX06 §2](FIX06.md#2-rules-for-every-phase) measures and §9; [B6 envelope prefix](#b6-gpt-oss-envelope-prefix), [B4 to B6 notes](#b4-b5-and-b6-26-october-2026) |
| B7 | [FIX06 Q1](FIX06.md#q1-remove-the-rejected-patches-and-take-the-clean-baseline) (D1.1), [Q7](FIX06.md#q7-exact-values), [Q8](FIX06.md#q8-source-claim-granularity-b7), [T3](FIX06.md#t3-coverage-gaps-b5-b7), [R leftovers](FIX06.md#b7-contract-review-leftovers); [B7 records, 26–27 October](#b7-records-2627-october-2026) |
| B9 | [FIX06 T1](FIX06.md#t1-repeated-runaway-debug-capture-b9), [H5](FIX06.md#h5-model-choice-r7); [B9 records, 26–27 October](#b9-records-2627-october-2026) |
| B10 | [FIX06 E0](FIX06.md#e0-failed-and-blocked-runs-publish-validated-content-b10-adr-0041); [B10 decision history](#b10-decision-history-2627-october-2026) |
| B11 | Closed (prompt line withdrawn): [B11 record](#b11-principle-citations-2627-october-2026) |
| B12 | [FIX06 Q1](FIX06.md#q1-remove-the-rejected-patches-and-take-the-clean-baseline) (hold), [Q7](FIX06.md#q7-exact-values) (D7.2), [Q11](FIX06.md#q11-remaining-rules-and-design-text) (D11.2); [B12 record](#b12-renderer-artefacts-27-october-2026) |
| W1, W2 | Closed earlier: [W1](#w1-review-can-restart-the-whole-pipeline), [W2](#w2-the-upstream-repair-path-exists-twice) |
| W3 | [FIX06 E4](FIX06.md#e4-generic-repair-operations-w3-adr-0033); [W3 decision record](#w3-decision-record) |
| W4 | [FIX06 Q9](FIX06.md#q9-reconciliation-call-structure-w4) |
| W5 | [FIX06 E2](FIX06.md#e2-stage-actions-a2-adr-0031-and-identical-sibling-steps-w5) |
| §4 stage review | [Spec workflow stage review](#spec-workflow-stage-review-17-october-2026) |
| R1 | [FIX06 R1](FIX06.md#r1-group-level-provenance-precision) |
| R2 | [FIX06 E7](FIX06.md#e7-clarification-answer-recovery-r2-adr-0025) |
| R6 | [FIX06 R6](FIX06.md#r6-semantic-repair-attribution-and-recovery) |
| R7 | [FIX06 H5](FIX06.md#h5-model-choice-r7) |
| R8 | [FIX06 H1](FIX06.md#h1-adjudication-r8), [H3](FIX06.md#h3-calibration-panels-r8); [R8 record](#r8-record) |
| Summary hierarchy | [FIX06 summary hierarchy](FIX06.md#summary-hierarchy-and-cross-model-variation) |
| Wider scope retained | [FIX06 wider scope](FIX06.md#wider-scope-retained) |
| Follow-up: schema selection (§10) | [FIX06 Q10b](FIX06.md#q10b-simplify-the-source-review-taxonomy-b2) |
| Follow-ups: provider-stop visibility (§11), logging gaps (§17) | [FIX06 E6](FIX06.md#e6-logging-and-visibility-gaps) |
| §6 Recommended order | Superseded by [FIX06 §3](FIX06.md#3-sequence); [order as of 27 October](#fix05-recommended-order-27-october-2026) |
| §7 Acceptance and evidence rules | Merged into [FIX06 §2](FIX06.md#2-rules-for-every-phase) |
| §8 Record history | [history, 26–28 October](#fix05-record-history-2628-october-2026) |

### FIX05 verdict and measures, 17 October 2026

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

| Measure, at the 17 October review | Value |
| --- | --- |
| Hello-world reference | 189 bytes, three requirements ([stories.md](../test/e2e/wf-001-hello-world/reference/stories.md)) |
| Code | 63,889 production and 82,792 test lines, for one of four planned workflows |
| Spec workflow | 1,168 YAML lines; 282 steps in 33 graphs (205 operation nodes, 77 subgraph calls); 185 distinct operations; 18 model-request sites (§4) |
| History | 199 commits in 8 weeks; 297,901 Zig lines inserted and 148,709 surviving; 22 ADRs between 26 August and 6 October |

The dated live diagnostics of 16–18 October are in
[Z_FIX05 §1](Z_FIX05.md#1-live-diagnostics-1618-october-2026).

### FIX05 state on 26–27 October 2026

**Done, committed and moved to Z_FIX05.** Everything below is on `39a06ea`, merged as
PR #10 (`1261106`), and verified offline. Live semantic benefit is not demonstrated
unless a row says so (§7).

| Item | State | Record |
| --- | --- | --- |
| B2 | Advisory post-generation review (ADR 0023); one record family per source-review call | [B2 records](Z_FIX05.md#b2-records) |
| B3, B8 | Native exact-value recognition and bookkeeping (ADR 0024) | [B3](Z_FIX05.md#b3-exact-value-bookkeeping-is-left-to-the-model), [B8](Z_FIX05.md#b8-the-model-classifies-and-disposes-exact-value-tokens) |
| B4 | One principle assignment per principle set; one budget, configured as `workflowTokenBudget` (ADR 0037, 125,000 for E2E) | [B4 records](Z_FIX05.md#b4-records), [B4 configured budget](Z_FIX05.md#b4-configured-budget-record) |
| B5 | No batch for token-only groups (ADR 0024); cross-kind restatement deleted natively (ADR 0035); records name their claims and functional requirements need a scenario (ADR 0038) | [B5 token-only batches](Z_FIX05.md#b5-token-only-record-batches), [B5 records](Z_FIX05.md#b5-records-2425-october-2026) |
| B6 | GPT-OSS envelope prefix normalized | [B6 envelope prefix](Z_FIX05.md#b6-gpt-oss-envelope-prefix) |
| B7 | Source-quoted claim wording and code-delimiter removal (ADR 0036); list-item claim split (ADR 0038) | [B7 records](Z_FIX05.md#b7-records-2125-october-2026) |
| B9 | Feature-owned entity records; no output allowance; one re-send after a runaway at the configured `temperatureRunawayRetry`, logged (ADR 0039) | [B9 records](Z_FIX05.md#b9-records), [B9 runaway evidence](Z_FIX05.md#b9-runaway-evidence-and-re-send-decision) |
| Review publication | Incomplete review published, marked and logged (ADR 0040); principle verdicts need citations at admission (ADR 0042) | [Z_FIX05 §20](Z_FIX05.md#20-adrs-00390043-and-live-runs--26-october-2026) |
| Vocabulary | Model-facing `exact_text` names (ADR 0043) | [Z_FIX05 §20](Z_FIX05.md#20-adrs-00390043-and-live-runs--26-october-2026) |
| A1 | ADR 0030 slices 1–3 (freeze, token counting removed, catalogue deadline) | [A1 slices 1–3](Z_FIX05.md#a1-settled-choices-and-slices-13) |
| W1, W2 | No post-generation upstream rebuild; the duplicate path is deleted | [W1](Z_FIX05.md#w1-review-can-restart-the-whole-pipeline), [W2](Z_FIX05.md#w2-the-upstream-repair-path-exists-twice) |
| R8 | Acceptance policy implemented offline; adjudication and calibration open (R8 below) | [R8 record](Z_FIX05.md#r8-record) |
| Test performance P1, P9 | Untraced leak-checking allocator and opt-in test-run reuse | [Z_FIX05 §18](Z_FIX05.md#18-offline-test-performance-p1-and-p9--24-october-2026) |

The 21–25 October runs and the record as it stood on 25 October are in
[Z_FIX05](Z_FIX05.md#current-state-as-of-25-october-2026).

**Live runs on 26 October 2026 (AEDT), GPT-OSS-20B on Bedrock, each user-approved.**
Advisory scores are `/evaluate-e2e` analysis under `evaluations/e2e/`, not grades or
acceptance.

| Run | Build | Calls / tokens | Outcome |
| --- | --- | --- | --- |
| Hello-world and loan-renewal, 17:57 | `54ce8fa`, modified | 1 / 0 each | `authorization_denied`: the Bedrock API key had expired |
| [Hello-world](../zig-out/e2e-spec/2026-10-26T07-06-24Z-2bcbb4d769b998b2249210be1e590348/report.json), 18:06 | `54ce8fa`, modified (the ADR 0038–0043 tree) | 24 / 66,358 | Published; advisory 82.14% |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-26T07-06-25Z-a5ac7cc3a13b9dc94d84828648c7eaba/report.json), 18:06 | `54ce8fa`, modified | 26 / 91,129 | Published; advisory 78.57%, below threshold, no critical failure |
| [Hello-world](../zig-out/e2e-spec/2026-10-26T08-09-02Z-314509c4e65f3bb4bc6a15fc2d3dd4ed/report.json), 19:09 | `39a06ea` | 25 / 84,951 | Published; advisory 82.14%; one source-review runaway recovered by the re-send |
| [Loan-renewal](../zig-out/e2e-spec/2026-10-26T08-09-03Z-a89fd748b0ce942ddd496ba3e42469c3/report.json), 19:09 | `39a06ea` | 26 / 89,887 | Published; advisory 78.57%, below threshold, no critical failure |

- **Completion since 21 October**, counting every attempt: hello-world published 15 of
  17, loan-renewal 7 of 17. All four completed 26 October runs published, every call was
  admitted first time apart from the one runaway, and no review ended incomplete.
- **What held across the four runs:**
  - loan-renewal's refusal behaviour has its own acceptance criterion (AC-002), written
    on the first records attempt, which no earlier build achieved (B5);
  - the 25 October `uncertain` title verdict that failed loan-renewal didn't recur, but
    principle citations collapsed (B11);
  - business rules restate the functional requirement in every run of both cases (B5);
  - invented or restating entities (B6), "may renew" in loan-renewal's story (B7), the
    renderer artefacts (B12), and source review passing defects (B2).
- **The re-send worked once.** Hello-world's source review of `Hello, World!` ran to the
  16,384-token maximum (18,823 tokens). The identical request at temperature 1 returned
  an admitted finding, and the log recorded `model.provider_stopped` then
  `model.runaway_resent` (B9).
- **Vocabulary.** "The preserved token" is gone from both cases (ADR 0043). Hello-world's
  brief now says "display the exact text …", which reads as plain English; watch it.
- **Evidence status.** One pair ran on an unmodified committed build of the current engine
  (`39a06ea`). No run has been adjudicated (R8, A6).

**Decided 27 October 2026, awaiting implementation:** ADR 0041's four mechanism choices
(B10) and B12's entity exact values (ADR 0045). Also decided: a second runaway in review
doesn't stop the run (B9), the retained v9 reports stay unadjudicated (R8), and B9's two
output caps are withdrawn. **Awaiting the user's decision:** B4's experiment stops and
B7's two citation questions. B5's business-rule guidance, B12's clause join, ADR 0044's
rule and its 27 October fix (B7) are implemented; B11's prompt line is withdrawn.

**Providers.** ADR 0028 (Anthropic Messages API) and ADR 0029 (Bedrock model families) are
implemented. All live evidence so far comes from GPT-OSS-20B; the account has no Claude
Haiku 5.5 access, and model choice is the user's decision (R7).

### Closed FIX05 item records

#### A6, ADR 0034 and gate status, 26 October 2026

- There were 22 ADRs between 26 August and 6 October.
- Design and fix records saw 139,051 lines written and 91,493 deleted.
- Phases 1A.2 and 1A.3 were each opened by a single hello-world run, while
  near-identical requests produced opposite failures (F13).

AGENTS.md requires every fix at the shared owning contract, with no backward
compatibility, so each amendment becomes a large cross-cutting diff.

**Proposal:** apply the evidence rules in §7 to every contract change.

**Decided 22 October 2026, with a higher bar.**
[ADR 0034](../design/decisions/0034-spec-quality-gate.md): no Plan, Tasks or Implement
contracts, workflow definitions or code until the Spec workflow is stable and producing
high-quality output on both development cases. Quality means each counted published
specification passes R8 human adjudication. Stability means repeated runs of both cases
on one committed build, counting every attempted run. There is no fixed run threshold;
the user judges the evidence and decides when Plan is actioned. The full record is in
[Z_FIX05](Z_FIX05.md#a6-decision-record).

**Status on 26 October.** The gate isn't met:
- no run has been adjudicated (R8);
- four pairs used an unmodified committed build: `7a88804`, `8a600d7`, `269410b` and,
  for the current engine, `39a06ea` (26 October 19:09);
- since 21 October loan-renewal published in 7 of 17 attempts and hello-world in 15 of 17,
  with all four completed 26 October runs published (§1).

#### B1. A long fail-closed chain of model judgments

Publication requires the whole workflow to pass every validator across 40 or more
sends. As an illustration, not a measurement: if each call produced acceptable
output 97% of the time after its retries, 41 calls would succeed together about 29%
of the time; at 95%, about 12%. Splitting work into more calls lengthens the chain
unless each call's success rate rises enough to compensate (former F5 and F7).

**Proposal:** treat call count per feature as a reliability cost. B2, B4 option 3, B5 and
W1 have shortened the chain. Of the open items, W4 and B5's collection authoring would
shorten it further; ADRs 0030–0033 change workflow steps, not model calls. Judge progress
by useful completion per attempted workload (§7), never by per-call admission.

#### B2 measurement and the reverted support line, 26–27 October 2026

Post-generation review took 75–80% of workflow tokens, reported invented content as
omissions, judged byte-identical text both supported and omitted, accepted an
obligation-strength change, and once wrote a harmful repair that re-review accepted. The
evidence and records are in [Z_FIX05](Z_FIX05.md#b2-records).

**Done.** Approved on 17 October and implemented offline under
[ADR 0023](../design/decisions/0023-advisory-post-generation-review.md): every
post-generation semantic finding is advice, reviewed as whole units or collections. It
never authorizes content repair, an upstream rebuild, a mandatory Plan obligation or a
clarification. Source review assigns one record family per call (approved 18 October,
built 20 October, `specification-state/v19`).

**Still open: accuracy and waste.** On 25 October the user set quality above cost and
approved the 125,000-token budget instead of making source review optional, so source
review stays. On 26 October review took 41–58% of each run's tokens and:
- passed "may renew" in loan-renewal's story (B7), invented timing words in hello-world's
  story and invented entities (B6);
- made false statements, such as that the source defines an entity or that it says
  "may renew";
- filed unsupported additions as `candidate_omission`, a harmful diagnosis under §7;
- in loan-renewal returned `supported` for every source-review subject.

**Measured 26 October 2026 (offline, advisory labels;
[summary](../evaluations/b2-review-accuracy/2026-10-26/summary.md)).** All 240 review
findings from the six published 26 October runs were labelled against the source:
- **Source review:** 132 findings; 77% finding-type accuracy, but it caught 1 of 28
  defective subjects with the right type (4% recall), missed 26, raised 4 false positives
  and wrote 26 false statements. Loan-renewal's source review never reported a real
  defect: "may renew" passed in 8 subjects.
- **Principle review:** 108 findings; verdicts 97% right, but no citation names the rule
  that governs the subject (31 blanket, 77 none, with a rule applying in 71), and 4 false
  "no principle applies" statements.
- **Cost:** review was 79% of loan-renewal's tokens over the three runs; 26% of its review
  tokens went to subjects whose defect it then approved.
- **Uncovered:** no review subject checks repetition across records or rendering.

**Tried and reverted (26–27 October 2026).** A `support.prompt.md` line telling source
review to check each statement against the source ("must never becomes may") was added on
26 October and removed on 27 October by the user's direction ("apply the follow
recommendations"). **Measured on one pair (26 October 10:23; [hello-world](../evaluations/b2-review-accuracy/2026-10-26-after-support-prompt/hello-world/notes.md),
[loan-renewal](../evaluations/b2-review-accuracy/2026-10-26-after-support-prompt/loan-renewal/notes.md)):
no improvement.** Source review caught 0 of 6 defective subjects; it approved "may renew"
although the new line names that case, and raised a new false positive claiming the source
omits UTC. The principle review wrote a templated "No supplied principle addresses …" for
every subject in both runs (20 false statements).

#### B4, B5 and B6, 26 October 2026

**B4.**
**Done.** One principle assignment per principle set, and one total budget, configured
since ADR 0037 as `.sddtoolkit.json`'s `workflowTokenBudget` (125,000 for E2E). The records
are in [Z_FIX05](Z_FIX05.md#b4-records) and
[Z_FIX05](Z_FIX05.md#b4-configured-budget-record).

Since 25 October no run has stopped on the budget: the 26 October runs used 66,358–91,129
tokens.

**B5.**
**Done.** Token-only groups get no record batch (ADR 0024), covered cross-kind
restatements are deleted natively (ADR 0035), and each non-entity record names the
claims it supports, with every claim a functional requirement names also named by an
acceptance criterion or edge case (ADR 0038). One records call per feature was not
adopted. The records are in [Z_FIX05](Z_FIX05.md#b5-token-only-record-batches) and
[Z_FIX05](Z_FIX05.md#b5-records-2425-october-2026).

**Live effect, 26 October.** Loan-renewal's refusal behaviour has its own acceptance
criterion in both runs, on the first records attempt; the scenario rule didn't need to
fire. ADR 0038's limit stands: the rule checks links, not meaning.

Open:

- **Business rules restate functional requirements** (every 26 October run of both cases;
  loan-renewal states one requirement up to five times across the story, FR-001, business
  rules and the entity). ADR 0035 deletes only exact, covered restatements.
  **Implemented 26 October 2026 (prompt only, ADR 0038 amended):** the records prompt says
  "A business rule states a constraint that no functional requirement in this response
  already states; never restate a requirement claim by claim." Next: confirm on an
  approved pair that organization recovers without losing the refusal scenario.

**B6.**
- **Entity applicability.** No native rule can judge it. Hello-world has invented a
  required entity in most publications ("Application Start", "Greeting", "Application",
  and "HelloWorldApplication" in both 26 October runs). Loan-renewal's entity restates
  the behaviour, and source review has passed it with false claims about the source.
- The GPT-OSS envelope-prefix malformation is resolved
  ([Z_FIX05](Z_FIX05.md#b6-gpt-oss-envelope-prefix)).

Measure entity applicability as its own class in the baseline and in B2's labelling.
Don't narrow the entity-name exception without a decision.

#### B7 records, 26–27 October 2026

**Done.** Claims are a category and admission-bounded source lines whose wording the engine
quotes (ADR 0036, with Decision 6 dropping code delimiters around exact values), and list
sources yield one claim per top-level item (ADR 0038). Per-item chunking (ADR 0027) stays
withdrawn. The records are in [Z_FIX05](Z_FIX05.md#b7-original-record) and
[Z_FIX05](Z_FIX05.md#b7-records-2125-october-2026).

Open:

- **Weakened obligation, now at generation.** Claims carry the source's "must be able to
  renew" since ADR 0036, yet generation still writes "may renew": the brief, story and
  FR-001 in the first 26 October run, the story only in the second. Source review passed
  it each time. The owner is now ADR 0044's native rule (below); measure its catches and
  false positives on live runs.
- **Markdown in claim wording** reaches later calls. Backticks around exact values are
  removed at admission (Decision 6); other effects are unmeasured.

**Decided 27 October 2026 ([ADR 0044](../design/decisions/0044-generated-text-keeps-obligation-strength.md)):**
a native unit-validation rule flags a generated field that weakens a linked claim's
`must`/`shall` into `may`/`might`/`should`/`could`, for the existing unit repair. It is a
closed word list, chosen by the user despite its brittleness; measure its false positives
on live runs.

**First live pair (27 October 2026, [loan-renewal](../evaluations/e2e/2026-10-27T05-06-43Z-338b9bb45bdc146d5696675404a8b7d1/evaluation.md)):
both triggers did harm.** The story's "may renew" was a true weakening, but the repair
("changing nothing else") turned it into "A borrower must renew", a duty the source doesn't
state. The entity relationship "A loan may be renewed only once." is the source's own
restriction (source L8, no "must"), flagged through another claim in the same group; the
repair replaced it with FR-001's text. Hello-world didn't trigger.

**Fix implemented 27 October 2026 (ADR 0044 amended; uncommitted).** In
`obligation_strength.zig`, the repair requirement quotes the linked claim's text and no
longer says "changing nothing else". A whole field sentence that is a whole sentence of a
linked claim (ignoring case, whitespace, a list marker and the closing break) has its
weaker markers ignored; its mandatory markers still count. A contract review found that
the first version matched part of a claim's sentence (so "a borrower may renew" passed as
the tail of a conditional claim) and dropped a copied sentence's "must"; both were
corrected, with tests, before verification. `zig build verify`: 164 of 164 steps, 1,980 of
1,980 tests. Next: measure catches, false positives and repair outcomes on the next
approved pair.

**Second live pair (27 October 2026, 08:31, the fix tree): loan-renewal failed.** The story
again said "may renew"; the check fired with the quoted requirement, and the repair (call
9) returned the story unchanged, so the run ended `RepairNoProgress` after 9 calls and
13,900 tokens ([analysis](../evaluations/e2e/2026-10-27T08-31-41Z-c6ffd06de92ac4d1241102b5fa595c87/evaluation.md)).
The model's trace reads the requirement's last clause as the goal ("prose reflecting claim
1 as \"may\""); the requirement ends on "weakens its \"must\" to \"may\"", and nothing says an
unchanged value fails. Before ADR 0044 this run would very likely have published with "may
renew"; under ADR 0041 it would publish its brief, marked incomplete. Hello-world published
(82.14% advisory) and didn't trigger. The copied-sentence exemption wasn't exercised.
**Implemented 27 October 2026 (wording within Decision 4, uncommitted):** the requirement
leads with the action: "Restate linked claim N's obligation as the claim states it:
\"…\". This text uses \"may\" where the claim uses \"must\"." The quote closes with its own
full stop, so an unpunctuated claim can't run into the next sentence. Next: an approved
pair, to see whether the repair now restores "must be able to renew" and, separately,
whether it keeps the field's other content (the requirement no longer says to keep the
rest; a repair that replaced the field with the quote would pass native validation). If
the model still returns the text unchanged, the generic repair-prompt line "an unchanged
replacement fails" (every repair route) is the next candidate and needs evidence from both
cases.

**Third live pair (27 October 2026, 09:40): the repair replaced the story with the quote.**
Loan-renewal published (85.71% advisory). The check fired once, on the story's "may renew"
(true positive), and the repair returned only the quoted claim, list marker included:
"\- A borrower must be able to renew an active loan that has not previously been renewed."
The story lost its outcomes (FR-001 and AC-001/002 still carry them); native revalidation
passed it and both reviews approved it. No false positives: the copied "may be renewed only
once" in the entity basis and FR-001 passed. The three wordings have now failed three ways
on single runs: a one-word duty swap, an unchanged value (`RepairNoProgress`), and wholesale
replacement ([analysis](../evaluations/e2e/2026-10-27T09-40-42Z-e1d68c88d8f613700d047807691f0187/evaluation.md)).
**Decisions proposed:** (1) a generic repair guard in revalidation, rejecting a repair whose
new value loses linked-claim coverage or exact values the old value had, unless the defect
concerns them (amends contract 22 and ADR 0044 Decision 4); (2) quote the claim without its
list marker and ask for the current text to be corrected, not replaced. Per CLAUDE.md, decide
on repeated runs across both cases.

**Hello-world, same pair: the UTC requirement was lost at reconciliation.** The dispositions
call returned one of four claims; the insert repair for "must also output date and time in
UTC" answered `duplicate` of "must start successfully". The repair request carried only the
three-line `repair.prompt.md`, not the dispositions prompt that defines `duplicate`
(`repair-reconciliation-candidate`, `spec.workflow.yaml:595-608`). Source review flagged the
loss three times, but ADR 0023 publishes no source advice, so the spec omits UTC (60.71%
advisory, critical failure). One runaway was recovered by its re-send, and debug logs hold
both attempts in full ([analysis](../evaluations/e2e/2026-10-27T09-40-42Z-26e5a21c5438c853bbfb338b62d42247/evaluation.md)).

#### B9 records, 26–27 October 2026

**Done.** Entity records are authored once per feature; no request carries an output
allowance below the model's documented maximum; and since ADR 0039 a runaway is re-sent
once with the identical request at the configured `temperatureRunawayRetry`, outside
`retry-limit`, and logged. A runaway on the re-send fails required work with
`RunawayRepeated` and ends advice incomplete (ADR 0040). The records are in
[Z_FIX05](Z_FIX05.md#b9-records) and
[Z_FIX05](Z_FIX05.md#b9-runaway-evidence-and-re-send-decision).

**Live effect.** One runaway in the four 26 October runs, on hello-world's `Hello, World!`
(call 21), was recovered by its re-send. Every completed source-review runaway so far
has been on an exact-value subject (`Renewal refused.`, `Loan renewed!`, `Hello, World!`).
One recovery is one sample: keep reporting each runaway, its re-send and what the re-send
returned.

**Debug logging (27 October 2026).** The user directed that every runaway, and a repeated
one before the stop, be logged in full at `debug`. ADR 0018's capture already does this,
and ADR 0039 Decision 4 and §27 now say so: the 26 October hello-world log keeps the
runaway's request at `0.1`, its full output (`max_tokens`, 16,384 tokens), and the re-send
at `1` with its response. No live run has had a repeated runaway, and no offline test
asserts its capture: add ADR 0039's debug-capture test.

Open:

- **Withdrawn 27 October 2026.** The two earlier output caps, a lower per-slot output
  allowance and a per-family records cardinality bound, conflicted with the user's
  directions of 18 October (no output token limits) and 25–26 October (no limits that
  discard useful output); the user accepted their withdrawal.
- **Decided 27 October 2026:** a second runaway in a review step doesn't stop the run; the
  advice ends incomplete and is published, marked and logged (ADR 0039 Decision 3, ADR
  0040). Required work still stops with `RunawayRepeated`.
- **Claude Haiku 5.5's deadline.** Its catalogue maximum is 128,000 tokens under an
  interim 180,000 ms deadline; measure it only if the user selects that model.

#### B10 decision history, 26–27 October 2026

**Decided 26 October 2026 ([ADR 0041](../design/decisions/0041-failed-run-incomplete-publication.md));
mechanism accepted 27 October 2026; docs updated, implementation pending.** A Specify run that fails because
model work couldn't be completed, or ends `blocked`, should publish only its validated
content as an incomplete specification, marked in `spec.md` and `reference-context.md` and
logged as `run.incomplete_published`, while still ending `failed` or `blocked`.

A read-only design pass found that the commonest loan-renewal failures (exhausted
correction, `RepairNoProgress`, the token budget) are runner rejections that end the run
before any YAML edge, and that publication today requires `ok` or `needs_user`. The user
accepted all four of its decisions on 27 October 2026 ("update the docs with the above
recommendations"), and ADR 0041 records them:

1. **Mechanism:** a YAML-declared workflow-level `failure-output` subgraph, run by the
   engine through the runner after an eligible failure, with a model-free runner
   failure-output mode. It amends ADRs 0005, 0009 and 0030.
2. **Eligibility:** YAML `failed`, `blocked` and `invalid` terminals and the
   `retry_limit` and `token_budget` rejections; cancellation, authority, logging,
   capture, operational and deadline failures publish nothing.
3. **No final requirement IDs** in the incomplete view, as ADR 0017's view already does.
4. **`workflow/v2`** for the new definition member.

When implemented, two tests that assert a required repeated runaway publishes nothing must
flip, and `spec.md`'s reader needs a slot for the failure status line beside ADR 0040's.

#### B11 principle citations, 26–27 October 2026

ADR 0042 added "if no principle addresses the subject, it is compatible" to the principle
prompt, and the 25 October `uncertain` title verdict didn't recur. But citations on
`compatible` findings fell from 481 of 481 in 33 earlier principle-review responses to 17 of
76 in the four 26 October runs (three runs cited none). Loan-renewal's second run gave a
false reason, "No principle governs user-visible behavior descriptions", although the
supplied user-interface principle covers them.

**Resolved 27 October 2026: the line is withdrawn** (ADR 0042 Decision 4). A reworded
line brought citations back in one run of four, and the principle review then wrote a
templated "No supplied principle addresses …" for every subject (20 false statements in
one pair). The principle prompt is the pre-ADR text; ADR 0042's admission constraint still
turns an uncited `conflicting` or `uncertain` verdict into a whole-response correction.
Principle-citation precision (blanket or missing citations) stays a B2 accuracy measure.

#### B12 renderer artefacts, 27 October 2026

Deterministic and present in most runs: the acceptance-criterion clause join renders
"…\., **When**" (`specification_markdown.zig:40-44`), and exact values appear as quoted
code spans with an extra full stop. These are code defects at the renderer with no
contract change; they need only the user's go-ahead.

**27 October 2026:** the clause join is fixed (renderer). Exact values in an entity's
meaning are plain prose by contract: `text-field-composition.md` gives entity meaning and
relationship a **prohibited** exact-copy role, and ADR 0036 Decision 6 strips the model's
backticks, which leaves "Renewal refused.." in loan-renewal's entity.

**Decided 27 October 2026 ([ADR 0045](../design/decisions/0045-entity-description-exact-values-as-code-spans.md)):**
entity meaning and each relationship take the incidental role, rendered as code spans
with no coverage credit; the contract is updated. **Implementation pending**, at the field
policy owner (`src/domain/text_field_policy.zig`), with ADR 0045's tests. Readability
only: it removes one recurring clarity defect and changes no score while bigger defects
hold clarity down, so it can go with the next engine change.

#### Spec workflow stage review, 17 October 2026

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
  covers the decision-free preparation and publication steps. Under ADR 0031, A2 covers
  the read-only parts of publication preparation, such as rendering and validation; the
  publication writes stay their own action.
- W1 and W4 reduce model calls; W2, W3 and W5 only reduce implementation effort.
- Keep typed outcomes, closed admission, all-or-nothing publication and
  clarification persistence as they are.

W1 and W2 are done; their records are in [Z_FIX05](Z_FIX05.md#w1-review-can-restart-the-whole-pipeline).

### FIX05 recommended order, 27 October 2026

Earlier sequences are in [Z_FIX05 §6](Z_FIX05.md#6-recommended-order-as-of-22-october-2026)
and [Z_FIX05](Z_FIX05.md#6-recommended-order-as-of-26-october-2026). Under ADR 0034, Spec
quality is the critical path, and Plan starts only when the user declares the gate passed.
Accuracy comes first; token cost is never a reason to drop a check, and spending that buys
no quality is removed at its owner. Nothing below authorizes a live call; each E2E run
needs its own approval.

1. **Adjudicate (R8).** No run counts toward the gate until a human adjudicates one. The
   26 and 27 October v10 reports can be adjudicated; the retained v9 runs stay
   unadjudicated.
2. **Implement the 27 October decisions**, each with `/preflight`:
   - B7, ADR 0044's fix: done 27 October (uncommitted);
   - B12, ADR 0045's incidental entity meaning and relationships (readability only; it
     can go with the next engine change);
   - B9, ADR 0039's debug-capture test for a repeated runaway;
   - B10, ADR 0041 with its accepted mechanism (about the size of ADR 0039);
   - then measure ADR 0044's catches and false positives, B5's business-rule guidance and
     the clause-join fix on the next approved pair.
3. **Measure on a committed build.** Repeat both cases on one committed, unmodified build,
   counting every attempt and reporting runaways, re-sends and incomplete reviews
   separately (§7). One pair has run on `39a06ea`. Use `/evaluate-e2e` for advisory defect
   origins.
4. **Measure review accuracy (B2)** by offline labelling before any change that lets review
   alter output; label B7's obligation weakening and B6's entity applicability as their
   own classes.
5. **Model choice is the user's decision (R7).** All live evidence comes from GPT-OSS-20B.
6. **Close the remaining Spec decisions:** B4's experiment stops and qualified scope before
   any baseline freeze; B7's fenced-block and duplicate-citation questions.
7. **Architecture, in ADR order and independent of 1–6.** ADR 0030 slice 4 (A1), which
   absorbs ADR 0039's re-send steps, before adding operations for another workflow; then
   `prepare-toolchain` (ADR 0031) with its measure, startup (ADR 0032) and repairs
   (ADR 0033). Fold A4's closed reasons and A5's rule style into each conversion, and check
   whether a conversion absorbs W5's pairs.
8. **Separate work.** R2 (ADR 0025) is a required feature that hasn't started. Decide R1
   before promising stronger provenance. Freeze the Phase 2 baseline only after B4's
   decision. Gather R6 evidence after B2's labelling.

### FIX05 record history, 26–28 October 2026

- **26 October 2026, decisions:** the user decided ADR 0039 (configured `temperature` and
  `temperatureRunawayRetry`; one re-send after a runaway, logged; every retry response
  passes the same checks), ADR 0040 (incomplete review published, marked and logged),
  ADR 0041 (failed and blocked runs publish their validated content, marked and logged),
  ADR 0042 (principle verdicts need citations at admission; the prompt defines
  `uncertain`) and ADR 0043 (model-facing `exact_text` names). CLAUDE.md and §7 record the
  re-send as the one engine exception to the rule against sampling changes and extra
  retries.
- **26 October 2026, implementation:** ADRs 0039, 0042, 0040 and 0043 implemented in that
  order, then a contract review's two major and four minor findings fixed (a false
  missing-final-text log on a first runaway, exact-value harness measurement, a compiler
  rule for the re-send route, full re-send identity, logging only an actual re-send,
  harness temperatures). `zig build verify`: 164 of 164 steps, 1,968 of 1,968 tests.
  Committed as `39a06ea` and merged as PR #10. ADR 0041 awaits its decisions (B10).
  [Z_FIX05 §20](Z_FIX05.md#20-adrs-00390043-and-live-runs--26-october-2026) holds the
  record.
- **26 October 2026, live runs:** two attempts denied by an expired Bedrock key, then two
  published pairs (§1).
- **26 October 2026, record review:** by user direction, completed work moved to Z_FIX05
  §§19–20 (the 25 October state and runs, A1's settled choices and slices 1–3, B4's
  configured budget, B5's and B7's records, B9's runaway evidence and decision, the
  23–26 October §6 sequence and the 23–25 October history). The open items were checked
  for relevance and alignment: B10–B12 are new; B9's lower output allowance and
  cardinality bound are flagged as conflicting with the user's no-limits direction; B2's
  separate assessment model is recorded as the user's model choice.
- **27 October 2026, decision:** the user chose B12's option 1, recorded as ADR 0045 (entity
  meaning and each relationship show exact values as code spans, with no coverage credit).
  The contract, ADRs 0020 and 0036 and the §32 index are updated; the code is not.
- **27 October 2026, direction:** runaways are logged in full at `debug`, the first and a
  repeated one before the stop. Already true under ADR 0018; ADR 0039 Decision 4, §12 and
  §27 now state it, and a debug-capture test for a repeated runaway is to be added (B9).
- **27 October 2026, decisions** ("update the docs with the above recommendations"):
  ADR 0044 is fixed rather than withdrawn (the repair quotes the linked claim; a sentence
  copied verbatim from a linked claim is exempt); a second runaway in review doesn't stop
  the run; ADR 0041's four mechanism choices are accepted; the retained v9 runs stay
  unadjudicated; B9's two output caps are withdrawn. ADRs 0039, 0041 and 0044, contract 17,
  F0100, the §32 index, known-work and the ADR 0041 governing documents are updated.
- **27 October 2026, implementation:** ADR 0044's fix (B7), after a contract review's two
  major findings were corrected; `zig build verify` 164 of 164 steps, 1,980 of 1,980
  tests. Uncommitted.
- **28 October 2026, direction:** the user rejected ADR 0044 as "an extremely poor
  direction"; the 27 October audits found the same single-run pattern in prompts, fragile
  text rules and tests. [FIX06](FIX06.md) was written as a phased rollout, each phase
  validated by repeated E2E runs on a committed build, and FIX05's open items were moved
  into it in one ordered sequence. FIX05 was retired; this section holds its closed items.
