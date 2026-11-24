# ENGINE01 — Model input size, token spend and repair value

Analysis of 24 November 2026, kept at this path at the user's request ("do not guess, do full
analysis"). It answers four questions: how larger inputs are managed, where the conflict case's tokens
go, whether tokens are used efficiently, and whether repairs help. Items use SPEC01's format. **Decision**
marks a question only the user settles. A recommendation here is not a decision, and nothing here grants
approval.

## 1. Answers

1. **Larger inputs.** Extraction and reconciliation bound what one call carries. Nothing after them does:
   every review, generation and scenario call carries every source's full text, review adds the whole
   derived reference, and record generation adds every principle file. The number of those calls grows
   with the source, so input grows faster than the source does. The one stop is a fixed total budget,
   applied after the tokens are spent. Each part follows an accepted ADR, a contract or a recorded user
   decision, so this is a property of the design, not a code defect. The design's own clauses disagree on
   it, and the missing decision is what "bounded" means for a call's evidence (§4, §7, §8 item 3).
2. **Conflict case.** Source review takes 82% of a run. 91% of the tokens are input. By characters, 89% of
   what the 13 review calls send repeats a part an earlier review call already sent. Both budget-stopped
   runs had answered every review subject when the last answer crossed the limit, so the finished work was
   discarded (§3).
3. **Efficiency.** No. Across the set 93% of tokens are input, and the source text is 1.0% to 2.7% of the
   characters sent. The rest is instructions, each result schema sent twice, principle files re-sent with
   every record-generation call, and derived evidence re-sent with every review call. 45% of the set's
   tokens went to runs that published nothing (§5).
4. **Repairs.** They buy completion at 0.5% of tokens: 17 of the 21 runs that sent a repair call since
   16 November published, and all 17 passed. They don't raise quality above the candidate's: a repair
   removes the one value the validator named. Of 23 graded repairs, 18 were helpful, 2 added a minor
   defect, 1 was neutral and 2 made no progress and ended their runs (§6).

## 2. Evidence and limits

- **Runs.** The nine launches of 24 November 2026 (`2026-11-24T08-24-38Z` to `08-39-35Z`), three per case,
  `anthropic` `claude-haiku-5-5`, build `da29d6b`, source `0e3181bc…`, `build.source.modified: true`. A
  modified build is not a measurement set (SPEC01 §2 rule 3), so these figures decide nothing.

  | Case | Runs | Published | Passed | Tokens per run | Outcome of the rest |
  | --- | --- | --- | --- | --- | --- |
  | hello-world | 3 | 3 | 3 | 38,654–39,739 | |
  | loan-renewal | 3 | 3 | 3 | 66,670–101,582 | |
  | loan-renewal-conflict | 3 | 0 | 0 | 44,328–128,678 | 2 `WorkflowTokenBudgetExceeded`, 1 HTTP 401 |

  Run A is `2026-11-24T08-29-03Z-fcfd0823…` and run B `2026-11-24T08-34-24Z-aa6dc0ea…`, the two budget-stopped
  conflict runs. The third, `08-39-35Z-727dac0e…`, ended on `authentication_failed` at call 10 and shows nothing
  about the engine.
- **Owning-step figures.** Sends, tokens and stage shares are `e2e-measures` values
  (`evaluations/e2e/<run>/measures.json`). Repair grades are `evaluate-e2e` values
  (`evaluations/e2e/<run>/evaluation.json`), advisory and given by the evaluating agent.
- **Indicative figures.** Per-step tokens, thinking tokens, characters by request part and repetition were
  counted by one-off reads of the retained `request.json`, `context.json` and `response.json`, which SPEC01 §9
  reserves for the owning steps. They are indicative and can't serve SPEC01 §2 rules 5 to 7. The per-step
  token sums equal each report's `total_tokens`.
- **Estimates.** No tokens were counted per request part (the engine counts none, ADR 0011:132-133). Where a
  token figure for a part is given, it is derived from the part's share of the call's characters and is marked
  as an estimate. The runs average 2.2 to 2.5 characters per input token.
- **Not measured.** No run of a large source exists. The conflict case's second leg has never run. Review
  verdicts were read for two calls of run A only.

## 3. Conflict case: where the tokens went

The case is the loan-renewal stories with one pair of contradictory bullets (SPEC01 §5 E7 stage 7). Its
first leg should end in one clarification form. It uses the hello-world configuration
(`test/e2e/wf-003-loan-renewal-conflict/workflow.case.json:9`), so its budget is 125,000 tokens
(`test/e2e/wf-001-hello-world/.sddtoolkit.json:6`).

**By stage** (`measures.json`):

| Stage | Run A sends | Run A tokens | Run B sends | Run B tokens |
| --- | --- | --- | --- | --- |
| Extraction and reconciliation | 6 | 23,272 (18.1%) | 6 | 22,777 (18.0%) |
| Source review | 13 | 105,406 (81.9%) | 13 | 103,736 (82.0%) |
| Generation, repair, clarification | 0 | 0 | 0 | 0 |
| Total | 19 | 128,678 | 19 | 126,513 |

**By step** (indicative; input + output):

| Step | Run A | Run B |
| --- | --- | --- |
| `g24-g13-assess-source-assess-model` (13 calls) | 97,578 + 7,828 | 96,349 + 7,387 |
| `g9-reconcile-dispositions` | 4,014 + 1,156 | 4,059 + 564 |
| `g8-validate-request-conflicts` | 3,582 + 877 | 3,642 + 779 |
| `g8-validate-request-signals` | 3,756 + 534 | 3,804 + 632 |
| `g9-reconcile-summary` | 2,957 + 952 | 2,957 + 839 |
| `g7-extract-content` | 2,741 + 101 | 2,741 + 101 |
| `g7-extract-classifications` | 2,369 + 233 | 2,369 + 290 |

**Review by subject kind** (indicative). A subject is one requirement the review must decide, and each gets
its own model call (12-model-boundary.md:410-412; `spec.workflow.yaml:582-584`).

| Subject kind | Run A calls | Run A tokens | Run B calls | Run B tokens | Input per call |
| --- | --- | --- | --- | --- | --- |
| Feature requirement (description, primary goal, acceptance criteria, functional requirements, scenario coverage) | 5 | 43,006 (33.4%) | 5 | 43,714 (34.6%) | 7,911–7,954 |
| Signal (business claim group or exact text) | 4 | 27,151 (21.1%) | 5 | 33,834 (26.7%) | 6,418–6,420 |
| Conflict record | 4 | 35,249 (27.4%) | 3 | 26,188 (20.7%) | 8,086–8,164 |

The code seeds six feature requirements (`src/domain/specification_authority.zig:29`); the entities one
received no call in either run, and why was not traced.

**What the 13 review calls of run A sent, by part** (indicative; 213,169 characters, 97,578 input tokens):

| Part | Characters | Share | Same in all 13 calls |
| --- | --- | --- | --- |
| Instructions (`support.prompt.md`) | 27,586 | 12.9% | yes |
| Response rule (ADR 0014) | 1,300 | 0.6% | yes |
| Result schema as system text | 42,484 | 19.9% | yes |
| Result schema as native format | 33,371 | 15.7% | yes |
| Payload: citations | 22,490 | 10.6% | yes |
| Payload: claims | 15,379 | 7.2% | yes |
| Payload: conflicts (9 calls) | 13,167 | 6.2% | same where sent |
| Payload: assessment scope, evidence rules, field rules, insertion fields | 22,825 | 10.7% | up to three variants |
| Payload: signals (9 calls) | 7,245 | 3.4% | same where sent |
| Payload: extraction review (9 calls) | 7,056 | 3.3% | same where sent |
| Payload: source text | 6,903 | 3.2% | yes |
| Payload: dispositions (9 calls) | 4,671 | 2.2% | same where sent |
| Payload: exact texts | 3,510 | 1.6% | yes |
| Payload: the subject and its requirement | 5,182 | 2.4% | no |

- 189,171 of the 213,169 characters (88.7%) repeat a part that an earlier review call of the run had sent.
  Run B: 186,163 of 210,293 (88.5%). As an estimate, that is about 86,500 of run A's 97,578 review input
  tokens.
- The part that says what is being decided is 2.4% of the characters. The source text is 3.2%.
- Four fixed parts, the instructions, the response rule and the schema twice, are 49.1% of the characters.
- The requests share only their first 5,503 characters (the three system blocks), because the payload's
  first member is the subject.

**Input, output and thinking** (indicative):

| | Run A | Run B |
| --- | --- | --- |
| Input | 116,997 (90.9%) | 115,921 (91.6%) |
| Output | 11,681 (9.1%) | 10,592 (8.4%) |
| Thinking tokens, inside output | 7,206 (61.7% of output) | 6,000 (56.6% of output) |
| Review output: thinking + visible | 4,796 + 3,032 | 4,329 + 3,058 |

**What the tokens bought.** Nothing was published.

- In both runs the 13th review call was the last subject. Its response took the run to 128,678 and 126,513,
  that is 3,678 and 1,513 over. An overshoot is fatal (ADR 0011:127-129), and a budget stop publishes nothing
  (17-specify.md:150-152; ADR 0041 is on hold).
- After review the workflow raises the form with no further model call (`spec.workflow.yaml:126-136`,
  `:202-209`, `:992-1003`), unless a finding needs a localization call (`:582-596`), which was not reached.
- At the measured means, 23,000 tokens before review and 8,050 per subject, 12 subjects fit under 125,000.
  These runs had 13. The two launches on build `59da1b5` needed 13 and 14 and stopped at 132,040 and 131,446.
- One contradiction makes several subjects. The conflict prompt says "several different kinds may apply to
  one group" (`reconciliation-conflicts.prompt.md:2`; ADR 0022:136-137), and each record is its own review
  subject (`specification_authority.zig:43-49`). Run A had 4 records for 2 claim pairs, run B 3 records for
  1 pair, and the two earlier launches 5 and 4 records for 2 pairs.

## 4. How input grows with the source

| Stage | Model calls | Each call carries | Bound on one call |
| --- | --- | --- | --- |
| Extraction | 2 per chunk | One chunk | A chunk is one Markdown block of at most 64 lines and 16 KiB (`src/adapters/parsers/markdown_reference.zig:48-59`; `src/domain/reference_ingestion.zig:14`; `src/actions/reference/prepare_reference_evidence.zig:243-255`) |
| Reconciliation | Per partition, then per level of summaries | One partition's claims | `group-size: 8` claims (`spec.workflow.yaml:406`); the bound counts claims, not tokens (16-reference-ingestion.md:250) |
| Source review | 1 per subject: 5 feature requirements, each signal, each conflict record | Every source's full text, and all claims, citations and exact texts; for every subject but a signal also the extraction review, dispositions, signals and conflicts (`src/domain/specification_support.zig:125-134`) | None |
| Brief, entities | 1 each | Every source's full text and every signal group's requirements; entities also the brief | None |
| Record generation | 1 per record group (17-specify.md:277-278) | Every source's full text, the group, and every principle file (17-specify.md:332-339) | None |
| Scenarios | 1 per record group with a scenario slot | Every source's full text and the group's requirements | None |
| Repair | 1 per rejected unit | The unit and its context | The unit |

**The three multipliers.**

- **The source text.** It is chunked for extraction and then sent whole with every later call:
  `sources` copies each corpus source's bytes (`src/domain/model_evidence.zig:79-81`) into the review packet
  (`specification_support.zig:126`), the brief, entities and record packets (`specification_session.zig:365`)
  and the scenario packet (`scenario_request.zig:123`). The cost is later calls × the corpus. In this set the
  source is 198 to 531 characters, 1.0% to 2.7% of what a run sends, so it doesn't show. No run has a large
  source.
- **Review** costs subjects × (fixed parts + the whole reference). The subject count and the reference both
  grow with the source. It runs only when the references aren't ready for generation
  (`spec.workflow.yaml:107-118`; ADR 0023:46-48) or when `validation.sourcePreservationCheck` is true
  (`src/actions/validation/check_source_preservation_policy.zig:7-9`). Both development cases set it false
  (`test/e2e/wf-001-hello-world/.sddtoolkit.json:23`), which is why they send no review.
- **Record generation** costs groups × the principle files. One call is 16,023 to 17,175 input tokens for
  sources of three and five requirements, and the principle files are 68% of its characters (28,719 and
  30,055 characters; an estimated 9,700 to 11,300 tokens). Loan-renewal made 2 or 3 groups, so 2 to 4 such
  calls a run. At the measured size, seven groups' record calls alone come to 112,000 to 117,000 tokens.

**The stops.**

- One total budget per execution, with no default, set per project (ADR 0037:42-44, :52-55; design.md:229-232).
  It doesn't change with the size of the source.
- The engine doesn't count, predict or narrow a request (ADR 0011:52-53, :132-133; design.md:222-223), so a
  workload that can't fit is found only after its tokens are spent.
- 128 request-assignment counters per execution (22-repair.md:761-762), which Z_SPEC01:3771-3776 puts at
  about 30 groups with source review and ten exact values.
- Ingestion limits: 1 MiB a file, 8 MiB a corpus, 1,024 blocks a file (`reference_ingestion.zig:7-16`).
- The provider's context window. Past it the call returns `context_limit` (ADR 0028:138). The largest
  request of the set was 17,175 input tokens.

**Authority for the shape.**

- One subject per review request: 12-model-boundary.md:410-412, and the user's standing rule "Never batch or
  group source-review subjects" (SPEC01:537-538).
- The whole source and the whole reference in a packet follow ADR 0013's default: "Complete evidence is
  retained when no deterministic rule proves a smaller scope" (:94-96). ADR 0016 adds that "Higher input token
  counts are acceptable; existing execution-budget enforcement remains" (:6-7) and that contexts "cannot filter
  evidence" (:119-121). "Review receives the original source" (17-specify.md:458-459). No clause says in words
  that a review packet must hold every claim and citation.
- Against that, the design asks for "a small typed assignment … the relevant evidence" (design.md:34-35),
  "concrete, bounded assignments" (design.md:118), requests that contain "only what the current unit needs"
  (12-model-boundary.md:58) and "bounded data" (AGENTS.md "LLM boundary"). No clause says what "bounded" means
  for a packet outside §16, and none defines ADR 0013's "deterministic rule" for a review subject or a record
  group.

**Other workflows.** Only Spec exists, and no Plan, Tasks or Implement work may start (ADR 0034:32-36). Their
contracts bound each call by unit: "bounded plan units" (18-plan.md:165), "one related obligation cluster"
(19-tasks.md:45), "bounded current contents of target and directly related files" (20-implement.md:68). The
sections read (§18.3, §19.2, §20.3, §20.6) set no bound on the fixed context sent with each call. PLAN01 PD8
recommends sending every principle file to every Plan
model request and puts the cost at 5.5k to 6k tokens a request, "about 20 carrying requests" to use the whole
budget (PLAN01:382-394). On this set the principle files are an estimated 9,700 to 11,300 tokens of the
carrying request, so that count is nearer 11 to 13.

## 5. Are the tokens used efficiently?

Indicative, per run of the set; the conflict column is runs A and B.

| | hello-world | loan-renewal | conflict |
| --- | --- | --- | --- |
| Input share of tokens | 92.8–95.5% | 93.9–95.1% | 90.9–91.6% |
| Thinking share of output | 46.0–66.0% | 45.0–54.0% | 56.6–61.7% |
| Characters sent: instructions and response rule | 4.7% | 3.5–3.9% | 12.1–12.2% |
| Characters sent: schema as system text | 24.6% | 17.4–19.9% | 19.8–20.0% |
| Characters sent: schema as native format | 14.7% | 10.3–11.4% | 15.3–15.4% |
| Characters sent: payload | 55.8–55.9% | 64.8–68.8% | 52.3–52.8% |
| of which principle files | 33.1% | 39.3–49.6% | none sent |
| of which source text | 1.0% | 1.9–2.0% | 2.7% |
| Record generation's share of the run's tokens | 40.7–41.9% | 50.5–67.0% | not reached |
| Published `spec.md` | 1,208–1,220 bytes | 2,994–3,102 bytes | none |

- **Set totals.** 669,188 tokens: 620,392 input (92.7%) and 48,796 output, of which 27,986 are thinking tokens.
  299,519 tokens (44.8%) went to the three runs that published nothing.
- **Each schema is sent twice by contract.** The complete schema is system text in both response modes, and
  native mode adds the provider projection (12-model-boundary.md:210-213; ADR 0014:13-20; JSON.md §2). The
  text copy holds the length bounds the projection can't carry. Whether the text copy changes output under
  native mode is not measured.
- **Principle files ride every record-generation call** by the user's decision D17.1 (ADR 0015:16-18). It was
  kept on guards alone: "no rubric criterion measures principle consistency" (Z_SPEC01 Q17).
- **A rejected answer re-sends the whole request.** Run `08-32-33Z` spent 16,876 tokens on a record-generation
  attempt rejected for `STRING_LENGTH`, then sent the request again with its principle files. Run `08-39-35Z`
  spent 3,093 on a superseded extraction attempt.
- **No request uses the provider's cache** (ADR 0028:116-117), and cached tokens would count in full against
  the budget anyway (ADR 0011:122-124; ADR 0028:145-146).

Each of these costs follows a contract or a decision. None is known to buy output quality: for the principle
files and the second schema copy no measurement exists, and for the review packet none has been made.

## 6. Do repairs help?

Three mechanisms spend tokens to recover a rejected answer:

- **Protocol correction:** a response that fails decoding or the schema is re-sent with its diagnostic, inside
  the step's `retry-limit` (ADR 0030:187-190; 22-repair.md §22.6).
- **Runaway re-send:** one identical re-send after an `output_limit` stop (ADR 0039).
- **Atomic repair:** a separate model call that replaces one engine-selected unit, followed by full validation
  (design.md:148-149; 22-repair.md:21; ADR 0033:224-227).

**Since 16 November 2026** (174 measured runs, 26 builds, 10,098,120 tokens; `measures.json` and
`evaluation.json`). The period starts where every recorded repair is a model call.

| Measure | Value |
| --- | --- |
| Runs that sent a repair call | 21 of 174 |
| Repair calls and tokens | 26 calls, 53,175 tokens (0.53%) |
| Calls that changed a value | 21; the other 5 recorded no repair |
| Grades | 18 helpful, 2 harmful, 1 neutral, 2 no progress |
| Outcome of the 21 runs | 17 published and passed, 2 blocked, 2 `RepairNoProgress` |
| Protocol corrections | 15 (ungraded) |
| Runaway re-sends | 0 |

- **What they fix.** 20 of the 21 runs repaired one field of an acceptance criterion that native validation
  rejected for holding another requirement's exact value (`foreign_exact`). The other repaired a token
  classification.
- **Completion.** A rejected unit has no route to publication except through repair
  (`spec.workflow.yaml:774-783`, `:807`). The 17 publications are what the repairs bought.
- **Quality.** A repair removes the value the validator named, not the cause, a criterion that reaches into
  another requirement.
  - `2026-11-24T08-37-05Z`: graded helpful; the repaired Then still restates the fourteen-day extension.
  - `2026-11-23T02-59-26Z`: graded harmful; the repaired Then gained "the borrower is shown the renewal
    result", a minor `unsupported_addition`.
  - `2026-11-16T07-18-12Z`: graded harmful; the repaired Given became the requirement's own wording, a
    `restatement`.
  - No evaluation in the period traces a lost or weakened requirement to a repair.
- **Association, not cause.** Runs that needed a repair score lower than runs that didn't.

  | Case | Repair call | Runs | Published | Mean aggregate | Accuracy defects per publication |
  | --- | --- | --- | --- | --- | --- |
  | loan-renewal | yes | 19 | 16 | 91.5 | 1.56 |
  | loan-renewal | no | 64 | 60 | 95.1 | 0.95 |
  | hello-world | yes | 2 | 1 | 89.3 | 2.00 |
  | hello-world | no | 83 | 80 | 96.9 | 0.23 |

  The 26 builds differ, and a candidate that needs a repair is already a weaker one, so this doesn't show that
  repair lowers quality.
- **Protocol corrections** aren't graded. In this set two were sent and both second attempts were admitted
  (§5).

**Whole history** (440 measured runs, 17,707,988 tokens): the repair stage is 71 calls and 198,752 tokens (1.1%).
`evaluation.json` holds 193 grades: 187 helpful, 3 harmful, 2 no progress and 1 neutral. Most of the helpful
grades before 16 November are deletions of repeated records that sent no model call, a mechanism no run has
recorded since. Eight defects have a `repair_harm` origin. Four are from the ADR 0044 repairs of 27 October,
one of which turned "may renew" into a duty; two are restatements from inserted criteria (12 and 13 November);
two are the 23 November addition above and its link.

**Answer.** Repairs are worth their tokens for completion. They don't improve what is published beyond
removing the rejected value, and about one in eleven graded repairs since 16 November added a minor defect.
"Mechanical repair acceptance does not prove semantic recovery" (22-repair.md:417-418) matches what the runs
show. No change is proposed.

## 7. Best practice against the engine

The practices are from Anthropic's guidance on
[prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching),
[token counting](https://platform.claude.com/docs/en/build-with-claude/token-counting) and
[batch processing](https://platform.claude.com/docs/en/build-with-claude/batch-processing), read on 24 November
2026 from the Claude API reference available to the agent, not re-fetched from the site.

| Practice | The engine today | What governs |
| --- | --- | --- |
| Send each call the evidence its decision needs | Extraction and reconciliation do. Every later call gets every source's full text, and review gets the whole reference; a conflict subject is told not to assess "unrelated generated fields or collections" and is still sent them | ADR 0013:94-96 allows a smaller scope only on a deterministic rule; SPEC01:525 bars truncating required evidence. **Decision** (§8 item 3) |
| Ask each question once | One contradiction becomes 2 or 3 review subjects, one per conflict kind | ADR 0022:136-137. **Decision** (§8 item 2) |
| Put the stable part first and cache it | Not used. The stable part is 89% of review characters, but the varying subject comes first in the payload | ADR 0028:116-117 and :181-183 put caching out of scope; cached tokens count in full, so the budget wouldn't move. Cost only (AGENTS.md "Model output, prompts and evidence") |
| Several decisions over one context in one call | Not done | Ruled out for source review: SPEC01:537-538; 12-model-boundary.md:410-412 |
| Reduce a large corpus in levels | Done for reconciliation (groups of 8, then summaries). Not for review or record generation | 16-reference-ingestion.md:250 |
| Count before sending | Not done | Ruled out: ADR 0011:52-53, :132-133; design.md:222-223; SPEC01:524 |
| A limit that tracks the work | One fixed total per project | ADR 0037; "no larger token budget: a budget failure is fixed at its cause, such as review cost" (SPEC01:523-525) |
| Don't re-send fixed context with every call | The principle files ride every record-generation call, and every schema is sent twice | D17.1 (ADR 0015); 12-model-boundary.md:210-213. Cost reported |
| Half-price asynchronous batches | Not used; each step needs the previous step's result | ADR 0028:181-183. Cost only |

Within the standing rules, two practices are open: asking each question once, and sending each call the
evidence its decision needs. The first acts on review cost, the cause SPEC01 §9 says to fix. The second needs
a decision the design doesn't hold.

## 8. Open items

Items 1 to 3 are ranked by expected effect on the conflict case's completion. Each needs `/preflight`, its
phase approval and its own live approvals (SPEC01 §2). Items 2 and 3 change model requests, so each is a
measured phase with screens and a set.

1. **Decision: the defect class for review-cost work.**
   - **Class:** completion of a clarification-expected run. E7's measure is the conflict case's
     complete-publication rate (SPEC01:406-408); it is zero in six launches, four of them budget stops in
     source review.
   - **Why a decision:** without a named class, items 2 and 3 are cost-only changes, which AGENTS.md bars.
   - **Recommended:** name that rate as the target, with finding-type accuracy and the two development cases'
     accuracy counts as guards.
2. **One review subject for each conflicting claim group.**
   - **Class:** item 1's.
   - **Owner:** the conflicts answer (`reconciliation-conflicts.prompt.md:2`, `reconciliation.schema.json`) or
     the requirement seeds (`specification_authority.zig:43-49`). `/preflight` chooses between them.
   - **Authority:** amends ADR 0022:136-137. The user decides whether seeding one requirement per group meets
     "never batch or group" (SPEC01:537-538).
   - **Evidence:** 4, 3, 5 and 4 records for 2, 1, 2 and 2 claim pairs in the four budget-stopped launches. A
     conflict subject's task is whether the pair's meanings are incompatible, the same question for every
     kind. Stage 5b already merges the gaps of one subject into one need (SPEC01:369-373).
   - **Arithmetic, not run:** with one subject per pair, runs A and B have 11 subjects, about 112,500 and
     110,600 tokens.
   - **Against it:** a verdict that depends on the kind would be lost. Two verdicts of run A were read and
     both were `conflicting`; the rest weren't read.
   - **Decision value:** a set where the case reaches its form, with review findings labelled, keeps it. A
     fall in finding-type accuracy reverts it.
3. **Decision: what "bounded" means for the evidence a call carries.**
   - **Missing authority:** ADR 0013:94-96 and ADR 0016:119-121 keep complete evidence in every packet unless
     "a deterministic rule proves a smaller scope", and no clause defines that rule. design.md:34-35,
     design.md:118 and 12-model-boundary.md:58 ask for the relevant evidence only. Neither side is quantified.
   - **Why a local reading is unsafe:** either reading changes every review, generation and scenario request,
     and SPEC01:525 bars truncating required evidence.
   - **Smallest decision:** whether the claims the engine assigns to a call, with their validated citations,
     are that deterministic rule, so that a call for one group or one subject carries the source chunks and
     derived evidence those claims cite, and a feature-wide call keeps the whole reference
     (17-specify.md:458-459). If yes, it is recorded in an ADR amending 0013 and 0016.
   - **Owners if decided:** `sources` (`src/domain/model_evidence.zig:79-81`) and its three callers;
     `packetForContext` (`src/domain/specification_support.zig:105-160`), which already leaves four members
     out for signal subjects (`:128-134`).
   - **Evidence:** a conflict subject names its claims as an exact set, and its packet also holds every source,
     the extraction review, dispositions, signals, the other conflict records and every other claim and
     citation (§3).
   - **Effect:** not estimated; no scoped packet has been built or run. For the conflict case the fixed parts,
     49% of review characters, stay either way. Its effect on review accuracy is unknown.
   - **Need:** review scoping serves item 1's class. Source-text scoping has no case that needs it yet: the
     three cases' sources are under 600 characters each.
   - **Order:** after item 2, which changes fewer requests.
4. **PLAN01 PD8 uses an earlier token figure.** No Spec change. PD8's "about 20 carrying requests" becomes
   about 11 to 13 at this set's measured request size (§4). The user's when Plan is actioned (ADR 0034).

**Not proposed.**

- A larger budget (SPEC01:523-525), batching review subjects (SPEC01:537-538), token ceilings or pre-call
  counting (ADR 0011), and any model change (SPEC01:521).
- Prompt caching, while it changes no accounted token and no output. If it is ever taken up, it needs an ADR
  0028 amendment and a payload whose shared members come before the subject.
- Dropping the schema's text copy (JSON.md owns that question) or the principle files (D17.1).
- Any change to repair (§6).

**Open uncertainty.**

- The conflict case's second leg has never run, so its cost and its output are unknown.
- No large source has been run. §4's growth is read from code and contracts and sized on three small cases.
- Tokens per request part are estimates.
- Why the HTTP 401 occurred is outside the run's records.
