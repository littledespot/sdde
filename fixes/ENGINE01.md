# ENGINE01 — Model input size, token spend and repair value

Analysis of 24 and 25 November 2026, kept at this path at the user's request ("do not guess, do full
analysis"). It answers five questions: how larger inputs are managed, where the conflict case's tokens
go, whether tokens are used efficiently, whether repairs help, and whether JSON is the right structure to
send to the model. Items use SPEC01's format. **Decision** marks a question only the user settles. A
recommendation here is not a decision, and nothing here grants approval. Closed and reverted work in §10 to §13
was cut to status lines on 27 November 2026 (`fixes/README.md`); §1 to §9 are the analysis as written.

## 1. Answers

1. **Larger inputs.** Extraction and reconciliation bound what one call carries. Nothing after them does:
   every review, generation and scenario call carries every source's full text, review adds the whole
   derived reference, and record generation adds every principle file. The number of those calls grows
   with the source, so input grows faster than the source does. The one stop is a fixed total budget,
   applied after the tokens are spent. Each part follows an accepted ADR, a contract or a recorded user
   decision, so this is a property of the design, not a code defect. The design's own clauses disagree on
   it, and the missing decision is what "bounded" means for a call's evidence (§4, §8, §10 item 7).
2. **Conflict case.** Source review takes 82% of a run. 91% of the tokens are input. By characters, 89% of
   what the 13 review calls send repeats a part an earlier review call already sent. Both budget-stopped
   runs had answered every review subject when the last answer crossed the limit, so the finished work was
   discarded (§3). The budget is not the case's only blocker: by code, no launch so far could have applied
   its answer in the second leg (§11). **Since conflicts first** (§13, 26 November 2026) these figures describe the
   earlier builds: a first leg now sends 2 or 3 review calls, 17,145 to 23,763 tokens, and totals 40,146 to 47,120.
3. **Efficiency.** No. Across the set 93% of tokens are input, and the source text is 1.0% to 2.7% of the
   characters sent. The rest is instructions, each result schema sent twice, principle files re-sent with
   every record-generation call, and derived evidence re-sent with every review call. 45% of the set's
   tokens went to runs that published nothing (§5).
4. **Repairs.** They buy completion at 0.5% of tokens: 17 of the 21 runs that sent a repair call since
   16 November published, and all 17 passed. They don't raise quality above the candidate's: a repair
   removes the one value the validator named. Of 23 graded repairs, 18 were helpful, 2 added a minor
   defect, 1 was neutral and 2 made no progress and ended their runs (§6).
5. **JSON.** It is the right structure for the answer: the provider holds the answer to the schema and the
   engine checks the rest, with no malformed answer in 1,806 calls. For the request the carrier is not the
   problem. What the engine puts in it is: engine bookkeeping, engine rules in engine vocabulary, each
   source line up to three times, and instructions in up to eight places (§7). Five changes, each a
   decision, would cut tokens by about half by estimate (§9). Prompt-only mode (`"json": false`) is to be
   removed (§10 item 1).

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
- **Fitted token rates.** §9's savings use a least-squares fit over the set's 113 calls that returned usage:
  119 tokens a call, plus 0.337 tokens a character of principle text, 0.485 of native schema and 0.439 of
  everything else. Its mean error is 67 tokens a call, against a mean call of 5,490. The characters a change
  removes come from re-encoding the retained requests by script. Both are indicative.
- **Retained answers.** §7's length and correction counts cover the 43 runs under `zig-out/e2e-spec/` on
  25 November 2026: 497 admitted answers and 6 correction attempts.
- **Outside sources.** Anthropic's
  [prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices),
  [Haiku 5.5 prompting guide](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-haiku-5-5)
  and [structured outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs) pages were
  fetched on 25 November 2026. §7's provider table is from web searches of each vendor's documentation that
  day; a row marked unconfirmed means the search found no official statement.
- **Not measured.** No run of a large source exists. The conflict case's second leg has never run. Review
  verdicts were read for two calls of run A only. No run has sent a request in any layout but today's.

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
- **Each schema is sent twice by contract.** The complete schema is system text in both response modes (before
  25 November 2026; native is now the only mode), and native mode adds the provider projection (12-model-boundary.md:210-213; ADR 0014:13-20; JSON.md §2). The
  text copy holds the length bounds the projection can't carry, and §7 shows what those bounds do. Whether
  dropping the text copy changes the rejection rate is not measured.
- **Principle files ride every record-generation call** by the user's decision D17.1 (ADR 0015:16-18). It was
  kept on guards alone: "no rubric criterion measures principle consistency" (Z_SPEC01 Q17).
- **A rejected answer re-sends the whole request.** Run `08-32-33Z` spent 16,876 tokens on a record-generation
  attempt rejected for `STRING_LENGTH`, then sent the request again with its principle files. Run `08-39-35Z`
  spent 3,093 on a superseded extraction attempt.
- **No request uses the provider's cache** (ADR 0028:116-117), and cached tokens would count in full against
  the budget anyway (ADR 0011:122-124; ADR 0028:145-146).

Each of these costs follows a contract or a decision. None is known to buy output quality, and none is shown to
lack it: the second schema copy was found to affect the Given rate (§13), the principle files' benefit is unmeasured
and their leakage is zero (§10 item 6), and for the review packet no measurement has been made.

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

## 7. What the model is sent

**The answer** is JSON through the provider's native format. Since the cases moved to the current route on
17 November 2026 (162 measured runs, 1,806 calls; `measures.json`): no malformed answer, and 14 schema
rejections, each followed by a correction: 9 `DISAGREEING_ITEMS`, 3 `STRING_LENGTH` and 2 `ARRAY_LENGTH`.

**Four requests of the set** (indicative):

| Request | Input tokens | Times each source line appears | Payload that is JSON structure, keys and numbers | Coordinate numbers | Places carrying instructions or the answer shape |
| --- | --- | --- | --- | --- | --- |
| Extraction (`08-26-45Z` call 1) | 2,707 | 1 | 47% | 15 | 6 |
| Review of one conflict (run A call 18) | 8,088 | 3 | 48% | 77 | 8 |
| Record generation (`08-26-45Z` call 8) | 16,654 | 2 | 5%; the rest is mostly principle files | 0 | 8 |
| Scenarios (`08-26-45Z` call 11) | 2,130 | 1 or 2 | 20% | 0 | 8 |

- **Engine bookkeeping is sent.** Each citation in a review packet carries source, block, byte, line and column
  numbers and repeats its claim's text as `verbatim`, so a requirement is in the source text, its claim and its
  citation. The extraction review adds extractor IDs and byte ranges. ADR 0013:89-90 says projections publish
  "only fields needed to interpret and cite the evidence", and 17-specify.md:348-349 keeps "citation
  coordinates, extractor metadata and redundant token IDs" native for authoring; F0100:764-766 gives review the
  source coordinates.
- **Engine rules are sent in engine vocabulary.** `evidence_rules` holds `"supported":"claim_required"`, the
  requirement holds `"positive_evidence":"bound_claims"`, and the instruction reads "A retained authority_gap
  selects its own source evidence under the existing negative rule." AGENTS.md ("Model output, prompts and
  evidence") says prompts carry no engine vocabulary and no restated engine-enforced rules; ADR 0023:137-138
  makes the packet share the evidence rule.
- **The question comes first and the instructions are scattered.** The review payload opens with the subject and
  puts the evidence after it. Instructions sit in the system prompt, the response rule, the schema text,
  `assessment_scope`, `evidence_rules`, the requirement's task and `field_rules`, where one sentence repeats for
  each field.
- **Extraction's source lines already work the other way:** numbered lines go in, line IDs come back, and the
  engine derives the coordinates (ADR 0013:107-111).

**What the length limits do** (retained answers):

| Field, capped at 2,000 characters | Answers | Shortest | Median | Longest |
| --- | --- | --- | --- | --- |
| Review `detail` | 50 | 206 | 565 | 928 |
| Review `question` | 21 | 121 | 214 | 387 |

- No retained answer was rejected for exceeding a cap. Of 2,493 strings in the 497 admitted answers, one is
  empty.
- The six retained corrections: four `disagreeing_items`; one `array_length`, a record that named 12 claim IDs
  where at most 4 were allowed; one `string_length`, an empty last fragment written with `minLength: 1` in
  front of the model, which the correction replaced with a full stop.
- About 7% of the schema text is bounds equal to 4294967295, which state no limit.
- A bound that states a fact about the assignment has caught a wrong answer. A character count has not.

**What the provider's guidance says:**

- Wrapping instructions, context and input in their own tags "reduces misinterpretation". JSON against tagged
  text for the input is not addressed.
- For inputs of 20k tokens or more, long material goes first and the question last: "Queries at the end can
  improve response quality by up to 30 percent in tests". This set's requests are 2k to 17k tokens.
- With structured outputs, "Claude automatically receives an additional system prompt explaining the expected
  output format". `minLength`, `maxLength`, numeric bounds and array bounds beyond `minItems` of 0 or 1 are
  unsupported. The page's examples pass the schema only as the output format.

**Which vendors document schema-enforced output** (their own APIs):

| Support | Vendors |
| --- | --- |
| Schema-enforced | Claude; Google Gemini; Meta Llama API; Mistral, except `codestral-mamba`; Qwen on Alibaba Cloud, some models; Moonshot Kimi, in its own schema dialect, with a documented weakness on `oneOf` and `$ref` for one model |
| Partly confirmed | Tencent Hunyuan: its Responses-compatible API only |
| JSON mode only, or schema support unconfirmed | DeepSeek; Zhipu GLM; MiniMax |
| Depends on the model | Microsoft Foundry, by catalogue entry; Amazon Nova, through tool use |

Documented is not the same as held: Bedrock documents enforcement for GPT-OSS-20B, and a fragment opened 93%
of its answers (JSON.md J1).

## 8. Best practice against the engine

The practices are from Anthropic's guidance on
[prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching),
[token counting](https://platform.claude.com/docs/en/build-with-claude/token-counting) and
[batch processing](https://platform.claude.com/docs/en/build-with-claude/batch-processing), read on 24 November
2026 from the Claude API reference available to the agent, not re-fetched from the site.

| Practice | The engine today | What governs |
| --- | --- | --- |
| Send each call the evidence its decision needs | Extraction and reconciliation do. Every later call gets every source's full text, and review gets the whole reference; a conflict subject is told not to assess "unrelated generated fields or collections" and is still sent them | ADR 0013:94-96 allows a smaller scope only on a deterministic rule; SPEC01:525 bars truncating required evidence. **Decision** (§10 item 7) |
| Ask each question once | One contradiction becomes 2 or 3 review subjects, one per conflict kind | ADR 0022:136-137. **Decision** (§10 item 3) |
| Put the stable part first and cache it | Not used. The stable part is 89% of review characters, but the varying subject comes first in the payload | ADR 0028:116-117 and :181-183 put caching out of scope; cached tokens count in full, so the budget wouldn't move. Cost only (AGENTS.md "Model output, prompts and evidence") |
| Several decisions over one context in one call | Not done | Ruled out for source review: SPEC01:537-538; 12-model-boundary.md:410-412 |
| Reduce a large corpus in levels | Done for reconciliation (groups of 8, then summaries). Not for review or record generation | 16-reference-ingestion.md:250 |
| Count before sending | Not done | Ruled out: ADR 0011:52-53, :132-133; design.md:222-223; SPEC01:524 |
| A limit that tracks the work | One fixed total per project | ADR 0037; "no larger token budget: a budget failure is fixed at its cause, such as review cost" (SPEC01:523-525) |
| Don't re-send fixed context with every call | The principle files ride every record-generation call, and every schema is sent twice | D17.1 (ADR 0015); 12-model-boundary.md:210-213. **Decision** (§10 item 4 reverted; item 6 dropped) |
| Keep instructions, evidence and the question apart, with the question last | Instructions sit in up to eight places and the review payload opens with the question (§7) | F0100:764-766; ADRs 0016 and 0023. **Decision** (§10 item 5) |
| Half-price asynchronous batches | Not used; each step needs the previous step's result | ADR 0028:181-183. Cost only |

Within the standing rules, two practices are open: asking each question once, and sending each call the
evidence its decision needs. The first acts on review cost, the cause SPEC01 §9 says to fix. The second needs
a decision the design doesn't hold.

## 9. Changes and estimated savings

Five changes would shrink what is sent. Each alters model requests, so each is a decision and a measured phase
(§10). The savings are estimates from fitted rates (§2): they are not token counts and not runs, and they say
nothing about output quality.

| | Change | Saving per run | Main risk | Needs |
| --- | --- | --- | --- | --- |
| A | Review each contradiction once, not once per conflict kind | Conflict case: −14% | A verdict that depends on the kind is lost | Amend ADR 0022 (§10 item 3) |
| B | Model view: each source line stated once, no coordinates or engine rules, fixed order | Publishing cases: −6% to −8%. Conflict case: −19% | A dropped field turns out to matter | Amend F0100 and ADRs 0016 and 0023, one call kind at a time (§10 item 5) |
| C | One schema copy, no limits stated | −13% to −17% on every run | More rejected answers, not measurable until built | Amend ADRs 0006 and 0014; a new build (§10 item 4) |
| D | Stop sending principle files in Spec. **Dropped 26 November 2026** (§10 item 6) | hello-world: −25%. Loan-renewal: −30% to −40% | Quality: a story naming a principle-defined term would reach the model without its definition | Reverses the user's decision D17.1 |
| E | Scope a review's evidence to its subject | Conflict case: −2% to −3% | Review misses context | The "bounded" decision (§10 item 7) |

**What each change sends and keeps:**

| | The model gets | The engine keeps |
| --- | --- | --- |
| A | One review call for each conflicting claim group | The group's conflict kinds |
| B | Numbered source lines, each claim stated once by line number, one instruction text, evidence before the question | Coordinates, extractor and block IDs, wrappers, evidence rules |
| C | The native schema, with no length limits stated | The complete schema, limits included, as the acceptance check |
| D (dropped) | Nothing in place of the principle files | The captured registry |
| E | A review subject's own claims | The whole reference |

**Estimated tokens saved per run:**

| Change | hello-world | loan-renewal | conflict (runs A, B) |
| --- | --- | --- | --- |
| A | none | none | 17,400–17,800 |
| B | 2,700 | 5,200–6,400 | 24,300–24,500 |
| C | 6,600 | 9,200–13,300 | 18,600 |
| D (dropped) | 9,700 | 20,300–40,500 | none |
| E | none | none | 2,300–3,500 |

| Case | Now | Estimated after |
| --- | --- | --- |
| hello-world | 38,654–39,739 | B and C: 29,400–30,400 (D dropped) |
| loan-renewal | 66,670–101,582 | B and C: 52,300–81,900 (D dropped) |
| conflict | 126,513–128,678 | A: 109,100–110,900. A and B: 84,800–86,400. A, B and C: 66,200–67,800. All: 63,900–64,300 |

- **Superseded for the conflict case** (27 November 2026 review). The conflict rows above, and the two budget figures
  below, were sized on 13 or 14 review calls a run. Conflicts first cut a first leg to 2 or 3 review calls and 40,146 to
  47,120 tokens in 3 of 3 launches (§13), so they no longer describe the build. B's estimate for the development cases
  (2,700 and 5,200 to 6,400 tokens) stands as an estimate; B2 and B3 are dropped and B1 is parked (§10 item 5).
- **Budget.** A alone puts the conflict case about 14,000 to 16,000 tokens under 125,000. A and B put it about
  39,000 under.
- **How B was sized.** The re-encoding stays JSON and only removes or merges members: coordinates, extractor
  metadata, each citation's repeated text, content wrappers, `evidence_rules` and repeated field rules. A
  designed layout could differ either way, and a dropped member may prove to be needed.
- **E is small here** because every source fits one chunk. Its purpose is large sources (§4).
- **Stating limits as field descriptions** was considered for C and dropped: §7 shows the limits do very little.

## 10. Decisions and open items

Each open item needs `/preflight`, its phase approval and its own live approvals (SPEC01 §2). A closed item keeps a
status line so the references above still hold; its build and review record was deleted on 27 November 2026
(`fixes/README.md`), and a decision recorded in an ADR is cited, not restated.

1. **Prompt-only mode is removed.** Built 25 November 2026 (Phase 1). Closed.
2. **The defect class for review-cost work. Recommended, not decided:** completion of a clarification-expected run.
   E7's measure is the conflict case's complete-publication rate (SPEC01:406-408), still zero; finding-type accuracy and
   the two development cases' accuracy counts are the guards. Item 9 used it. For any other review-path change it stays a
   recommendation, and while item 13 stands such a change has no live proof route (§11 finding 3).
3. **Change A: one review subject for each conflicting claim group.** Built 25 November 2026 (Phase 2); ADR 0022
   amended. In the tree. Closed, with one open decision:
   - **Open, a decision:** the source-omission conflict-group repair binds only `claim_dispositions[].claim_id` (as exact
     members) and `conflict_groups[].claim_ids` (`reference_model_input.zig:251-254`), and its `conflicts` pass
     `groups.explain` unbound (`reference_reconciliation_repair.zig:741`), so its answer can omit or repeat an
     explanation (read from the code on 25 November 2026, not run). ADR 0022 ("Conflict groups", Scope) keeps two repair
     paths for that case: the group-without-record insert (`Target.insert_conflict`) and the duplicate-record deletion
     (`competing_entries`). Either bind `conflicts[].group_id` as exact members in that repair (the choice
     `reference_reconciliation_stage.zig:84` already makes for the conflicts request), which would let both paths go, or
     accept that such an answer is an invariant failure. Binding is the smaller change.
4. **Change C: one schema copy. Built, measured and reverted** 25 November 2026 (user: "action Phase 3", then "revert
   phase 3"). The result later work relies on is §13 "Request text moves the Given rate".
   - **A later attempt needs** the `given` conflict settled first as its own measured change: the packet says a criterion
     whose sources state no starting situation has none (`purpose`), and the field rule says "Write nonblank prose"
     (`src/domain/text_field_policy.zig:84-114`); Q26's record names that `prompt_conflict` as the likely cause of its
     retained repeats (Z_SPEC01 "Q26"). C is a cost change (−12% to −15% measured on the development cases), so it also
     needs a reason beyond cost.
   - **The residual the `given` change would address:** loan-renewal carries 2 minor `unsupported_addition` Givens a run,
     in 4 of 4 runs of the last two sets (each 96.43% where 100% is the ceiling); hello-world had none in
     `2026-11-25T22-06-04Z`. It is the only recurring accuracy defect in the development cases. Owner:
     `fixes/Z_SPEC01.md` Q26 ("kept, benefit not demonstrated"). Not proposed: a rule or prompt change there needs
     repeated runs of both cases.
5. **Change B: a model view of each request. B1 parked; B2 and B3 dropped. Decided** 27 November 2026 (user: "update the
   documentation with the review verdicts"). Nothing built.
   - **B1 (the review packet, Phase 4):** its need was the budget, which conflicts first removed (§13); its keep-if
     ("the first leg still ends `clarification`") can't be met while item 13 stands; and its proof needed conflict-case
     launches, which item 13 stopped. It returns only with a defect class that review-packet content causes and a case
     that can show it.
   - **B2 and B3 (the evidence projection and the field rules, Phase 6):** no output-quality class was ever named for
     them, and AGENTS.md bars a cost-only change; request text moves output (§13); B3 edits the field rules, where the
     `given` conflict lives (item 4). A later attempt needs a quality target and a case that can show it first.
   - **Owners if reopened:** `packetForContext` (`src/domain/specification_support.zig:105-160`), the evidence
     projections (`src/domain/model_evidence.zig`), the generation packets (`src/domain/specification_session.zig`), the
     scenario packet (`src/domain/scenario_request.zig`) and the field presenter
     (`src/domain/model_field_presentation.zig:78-113`). It would amend F0100:764-766, ADR 0023's packet evidence rule
     and ADR 0016's packet guidance, and a packet shape change advances each closed contract it touches (ADR 0030
     "Versions").
6. **Change D: no principle files in Spec. Dropped** 26 November 2026 (user: "update the documentation as per
   recommendation"). The principle files stay in the records request (D17.1; ADR 0015:16-18; 17-specify.md:332-339).
   - **Why:** removal has no quality case. Leakage is 0 in every output observed (Q17's nine runs and 20 replays, and the
     publications since). Spec is built so a principle can't become content: the records prompt says principles "are not
     sources", records cite only source claims, and a principle supplies no passive literal or exact value
     (17-specify.md:337-339). And removal could lose quality: a story that names a term a principle defines (a UI
     principle's colour, say) would reach the model without its definition. No run covers that case, since AGENTS.md keeps
     story values out of case principle files.
   - **Gap that remains:** only the records call carries the files; the scenarios call writes a criterion for the same
     requirement without them. Unmeasured; the user's, not proposed.
   - **A later attempt** needs a quality target (a defect class the files cause or prevent) and a case that can show it,
     then a paired replay of the records call.
7. **Change E, and the decision it needs: what "bounded" means for the evidence a call carries.** Not scheduled.
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
   - **Effect:** not estimated; no scoped packet has been built or run. Its effect on review accuracy is unknown.
   - **Need and order:** last. Source-text scoping waits for a case with a large source (the two loan sources are 470
     and 501 characters), and review scoping has lost the budget need that conflicts first removed.
8. **PLAN01 PD8 uses an earlier token figure.** No Spec change. PD8's "about 20 carrying requests" becomes
   about 11 to 13 at this set's measured request size (§4). The user's when Plan is actioned (ADR 0034). Item 6 keeps
   Spec's principle files, so the figure stands unchanged by it.
9. **Conflicts first, repair-aware. Built** 26 November 2026 (user: "implement conflicts first", then "implement (b),
   update the documentation"). The rule is F0100 §3.10 and ADR 0023: a first pass over a held conflict projects the
   conflict records and their forced gaps alone, and a dependent pass (the review that validates a pending source repair)
   and a conflict-free reconciliation keep the full projection. Live result: §13.
   - **Kept. Decided** 27 November 2026 (user: "keep conflicts first"). Reverting would have restored the full review,
     which ended at the budget in 5 of the 6 earlier runs that reached it on this request text (the two that finished it
     ran the Phase 3 build's smaller requests). Its target criterion was not met, for item 13's reason.
   - **Accepted limit** (27 November 2026, user: "update the documentation with the recommendations"): after a repair
     that leaves a real conflict held, the full dependent pass can raise feature forms beside the conflict's form, as
     every blocked pass did before (the two launches that finished a full review with a real conflict held raised 4 and
     3 forms). 0 of 3 launches reached a dependent pass. Reopened by a launch that repairs a false group and then raises
     feature forms beside a real conflict's form.
   - **Other limits:** an unrelated gap isn't asked while a conflict is open, and in a first pass only the conflict
     subject can localize a false conflict (likely, unmeasured). The rule covers the conflict branch only: with no
     conflict held (the no-eligible-claim branch) several feature subjects can still each raise a form about one missing
     decision. No case shows it.
   - **Closed reading** (27 November 2026, same instruction): the amended 12-model-boundary.md:745-748 needs no edit. Its
     exhaustive projection concerns successful publication, which a first pass over a conflict never reaches.
   - **Hardening: decided and built 27 November 2026** (user: "update docs with recommendations", then "implement the
     option (b) hardening", after the preflight of that day). It fixes no output defect; it removes representable illegal
     states (AGENTS.md:193-194) and covers a recovery path end to end (28-testing.md:557-558). Closed. Built as scoped
     below, with these results:
     - **Built:** `build` rejects a pass other than `first` off a readiness projection (`required_authority.zig:186-187`);
       `admittedValidation` rejects a review whose pass is not `passFor(projection)`, beside its projection comparison and
       before the conflict-group branch (`source_omission_authority.zig:124`), where `passFor` is the one owner of the
       mapping that `reviewPass` also uses; `specification_authority.project` is deleted and its callers use
       `projectFor(..., .first)`; the Rejects lines of 13-10 (:48-50) and 13-05 (:304-305) carry the rejections. The 13-05
       line states only the new rejection, and `admittedValidation`'s older ones (projection, target and revision mismatch,
       reused ordinal) stay unstated there.
     - **Scenario:** `source-repair-two_false_conflicts`, scenario 92 of the `existing` group, appended so no other
       scenario's projection moved. One `stories.md` (a heading, 70 identical lines and a token line, the existing fixture
       pattern) gives two disjoint pairs; two groups are repaired in turn through one permit scope and the run publishes.
       It observed 25 readiness reviews, 23 of them dependent and 11 of those while the second conflict was held, 2
       reconciliation repairs and 47 provider calls. Asserted: published, permit cleared, 0 conflicts left, no execution
       rejection, 2 repairs, at least 2 dependent reviews, at least one over a held conflict and fewer than all, and 1
       conflicts request (a rule: a group repair keeps an independent group's explanation, so the re-pass asks for none).
       It uses one source because the scripted review names only `sources[0]`, a fixture limit.
     - **Tests:** 1 new gate test (readiness first and dependent, preservation and registered first accepted;
       preservation and registered dependent rejected); `admittedValidation` accepted and rejected on the ordinary and the
       conflict-group branches, with the Apply binding pinned (`invalid`, no repair transition); `reviewPass` for an
       extraction-owned readiness permit. The regression test's first-pass follow-on is now rejected by the pass check; the
       outcome it used to pin, `recurring` from the group branch with `InvalidRepairProgress` on the second authorization,
       is restored on a dependent review that leaves the first group's claims unsupported (the contract review found that
       pin lost). `checkSourceOmissionProgress` validates a readiness repair with the dependent pass.
     - **Proof:** `zig build verify` 146 of 146 steps, 2,536 of 2,536 tests (2,535 before); test-required-authority 368,
       test-specification-generation 500, test-integration 158; lint and test-architecture clean. The freeze
       `evaluations/request-projection/hardening-before` against `hardening-after` differs only in
       `existing/source-repair-two_false_conflicts` and the manifest (scenarios 146 to 147, calls 1,818 to 1,865). Mutations
       that each fail the intended tests: no `build` check, no `admittedValidation` check (ordinary and group branches),
       `projectRecords` ignoring `dependent` (fails the scenario), and a group branch that is always `resolved` (found by
       the lead, fails the restored pin; it survived every test before the follow-up).
     - **Contract review** (`contract-reviewer`, read only, 27 November 2026): no blocker. Fixed: the lost `recurring` pin
       (major), a wrong comment, the missing Apply-binding pin and the duplicated rule (now `passFor`). The follow-up that
       fixed them was read by the lead, mutation-checked and verified, and not re-reviewed. Not mutated: the Apply-binding
       pin itself.
     - **Not done:** nothing live, by decision 1.
     - **Scope.**
       - `build` rejects a pass other than `first` off a readiness projection. No valid producer sets one: only
         `projectRecords` writes the pass, and every other `Inputs` literal defaults to `first`.
       - `admittedValidation` rejects a readiness review whose pass is not `dependent`, placed beside its projection
         comparison, because its conflict-group branch returns before `build` runs. The scripted driver already asserts
         on every readiness review that the pass is `dependent` exactly when a readiness permit is pending, so the check
         can't fire in a valid flow. `checkSourceOmissionProgress` validates a readiness repair with a first-pass review,
         a state the runner never produces, and moves to the dependent pass.
       - One scripted scenario with two false conflict groups that share no claim (groups that share one are refused,
         item 13), each judged `candidate_omission` and repaired in turn through the runner, ending published. It is the
         first scenario to hold a conflict in a follow-on pass, and it is appended to its group so no other scenario's
         projection offsets shift (e2e.md:773-777). It needs a source of at least four model claims and scripted findings
         for feature subjects in a dependent pass over a held conflict.
       - `reviewPass` gets its extraction-owned readiness permit case. The scripted `.empty` scenario already exercises
         that permit end to end.
       - `dependent` with no pending permit stays representable: the gate holds no permit to check it against, and it
         only widens the review.
     - **Decided (1): offline only, no live run.** The development cases send no review request and item 13 stops
       conflict-case launches, so no live run can exercise it (SPEC01 rule 10 otherwise asks for one live run of each
       case). The proof is the tests and a request-projection freeze before and after whose diff is the new scenario's
       directory and the manifest alone (`fixes/Z_SPEC01.md:326-327`).
     - **Decided (2): delete `project`.** It is an alias of `projectFor(..., .first)` with no production caller
       (AGENTS.md:196-198; `fixes/Z_SPEC01.md:619`). About 31 test call sites and one fixture
       (`src/test_fixtures/source_loss_calibration.zig:425`) move to `projectFor(..., .first)`.
     - **Decided (3): documentation.** F0100 §3.10's sentence that a resolved conflict "gets no readiness review" was
       corrected on 27 November 2026: a pending source repair's dependent review still runs (22-repair.md:473-475,
       ADR 0023:132). The two rejections went into the Rejects lines of 13-10 (:48-49) and 13-05 (:304) with the code,
       not before it: an action's Rejects line states what the code does.
     - **Decided (4): no ADR amendment.** The checks enforce ADR 0023's definition (the runner's pending repair selects
       the pass, :61-63) and add no policy. A likely reading: no clause states the checks in words.
     - **Recorded, not proposed.** One `InvalidRequiredAuthority` ends `blocked` at the ledger and gate steps (13-10:48-49,
       :78) and `invalid` at apply-specification-support
       (`src/application/specification_support_workflow.zig:173-187`; 13-05:304 states no outcome), where F0100:732 says
       structural accounting errors block. It predates this work, and the new `admittedValidation` check inherits it.
       Separately, design.md §31 item 39 asks every validation boundary to rebuild "the complete reconciliation
       projection"; whether a conflict-only first pass meets it is unaddressed (ADR 0023, accepted, outranks §31).
     - **Why now.** A false group appeared in 3 of 3 launches of 26 November and in none of the ten earlier launches
       that reached the review; the dependent pass has no live execution, and with groups that share a claim the
       repair refuses before it.
   - **Not recommended:** a narrower dependent pass (conflict seeds plus the signals and tokens citing the repaired
     claims). It has no equivalent for extraction-owned repairs, is a new design decision, and no run shows the
     sequence it would help.
10. **Recorded limit: a mismatch between `conflict_groups` and the `conflicting` dispositions blocks the run**
    (`2026-11-25T08-23-17Z`, 1 of the 7 conflict-case launches since Phase 2). A group naming a `retained` claim is
    rejected at canonical validation, and the `dispositions` unit has no repair route
    (`src/domain/reference_reconciliation_repair.zig:162`, ADR 0046). **Decision, not proposed:** derive the groups'
    claims from the dispositions, correct the mismatch at admission as ADR 0046 does for a missing disposition, or leave
    it as a valid model limitation. A fix would let such a launch reach the review, where item 13 stops it, so it can't
    change a decision while item 13 stands.
11. **The incomplete specification printed claims with their source markup escaped. Built** 26 November 2026 (user:
    "accept recommendation 1, 2 and 3"). The rule, with its accepted code-span limit, is ADR 0017 and ADR 0036
    Decision 2. Closed. Untested: a reading with an unmatched backtick, a reading that starts with a span, and an
    escaped first backtick.
12. **Stale status text. Fixed** 27 November 2026: F0100:28-30, :221-223, :975-976, :985-986, :1293-1294 and
    :1559-1560 and design.md:1145 now say generation uses a reference conflict's answer and no other answer (ADR
    0025:3-6); the sentence "Response acceptance and applicability remain open" at F0100:215 was deleted, since :221-223
    states it. F0100:117-118 was still true and is unchanged. Closed. design.md:1145 does not name the response-owned
    passive literals that ADR 0025:5 and F0100:29, :1560 name.
13. **Decided (a) 26 November 2026 (user: "item 13 accept a"): conflict groups that share a claim stop the first leg at
    `repair-source`, so no form is raised. Accepted as a valid model limitation and an unmet criterion; no engine
    change.** In 3 of 3 launches of 26 November the reconciliation declared `[[4,5],[1,5]]`: the intended pair (stories
    8 and 9) and a second pair that joins stories 5 ("has not previously been renewed") to stories 9 ("up to twice"),
    which share claim 5. The review judged the intended pair `conflicting` and the second `candidate_invalid` (2
    launches) or `candidate_omission` (1), and the gate's `invalid` outranks the real conflict's `needs_user`:
    - `candidate_invalid` has no repair route (22-repair.md:42-44; `select`, `source_omission_authority.zig:149-172`),
      so the run ends `InvalidRequiredAuthority`;
    - `candidate_omission`, localized to `reconciliation_conflict` 2, reaches the group repair, which refuses with
      `InvalidAtomicRepair`: `selectedValue` (`src/domain/reference_reconciliation_repair.zig:770-795`) rejects a
      target whose groups or dispositions reach a claim outside it, and group `[4,5]` reaches claim 4 (likely; which
      guarded line fired was not executed).

    The conflict case stays as it is, its second leg stays unreached, and no more conflict-case launches run on this
    build. **Not taken:** (b) rewording stories 5 in a new case version, which ends the case's comparability and works
    around a model limitation; (c) a design change for a false group that overlaps a real one, which would help only a
    `candidate_omission` verdict (1 of 3) and needs authority work first (`22-repair.md`, ADR 0046, a rule for the repair
    target). **Known contract gap, not fixed:** the reconciliation guidance says "overlapping groups are allowed"
    (`design/workflows/spec/reconciliation-dispositions.prompt.md:5`) and 12-model-boundary.md:877 says overlapping groups
    preserve many-to-many links, while the group repair refuses a target that overlaps another group; no clause covers
    repairing one of two overlapping groups. **Reopened by** a one-group first-leg launch of the conflict case, or a false
    group overlapping another in a different domain.

**Not proposed.**

- A larger budget (SPEC01:523-525), batching review subjects (SPEC01:537-538), token ceilings or pre-call
  counting (ADR 0011), and any model change (SPEC01:521).
- Prompt caching, while it changes no accounted token and no output. If it is ever taken up, it needs an ADR
  0028 amendment and a payload whose shared members come before the subject.
- Removing the length limits from the engine. They stay in the complete schema as the acceptance check.
- Any change to repair (§6).

**Open uncertainty.**

- The conflict case's second leg has never run, so its cost, its output and answer application after an answer have no
  live evidence.
- No large source has been run. §4's growth is read from code and contracts and sized on three small cases.
- §9's savings are estimates. Only A and C were built; C measured −12% to −15% on the development cases (§13).
- Two of the three `STRING_LENGTH` rejections since 17 November are no longer retained, so which limit they
  broke is unknown.

## 11. Feasibility review

Read-only review of 25 November 2026; the code was read, not executed. Its per-change table was superseded by the
decisions in §10 and deleted on 27 November 2026. Its findings stand:

1. **The conflict case can't apply its answer to a conflict that shares a claim with another.** An answer is applied
   only to a conflict none of whose claims is in another conflict record (`src/domain/answered_reconciliation.zig:7-9`;
   its test says so at `src/answered_reconciliation_test.zig:104`); otherwise the form is raised again. Not executed: no
   launch has reached its second leg. §10 item 13 accepted the consequence.
2. **The model declares a second conflict.** Beside the intended pair (stories 8 and 9) it pairs "not previously been
   renewed" (stories 5) with "up to twice" (stories 9): 5 of 6 launches of 24 November, and 3 of 3 of 26 November.
   Since conflicts first such a launch stops at `repair-source` with no form (§10 item 13).
3. **Review requests never occur in the two development cases.** Those cases have no conflict and set
   `sourcePreservationCheck` false (§4), so a review-request change alters none of their requests and can't be decided
   "on both development cases" (AGENTS.md). The conflict case was conflicts first's live proof; for any other
   review-path change there is no live proof route while item 13 stands.
4. **One projection serves reconciliation, review and repair** (ADR 0013:93; `src/domain/model_evidence.zig`).
   Stating claims by line number changes the reconciliation requests of all three cases together with the
   review requests.
5. **One presenter writes `field_rules` and `insertion_fields` into every packet**
   (`src/domain/model_field_presentation.zig:78-113`). Grouping repeated rules changes every call kind at once.
6. **Fifty review verdicts are retained** from the five conflict launches that reached review before conflicts first.
   Labelling them as a finding-type accuracy reference is not needed now: its consumers, Phase 4 and Phase 7's review
   half, are parked and unscheduled.

## 12. Order

**Nothing is queued** (27 November 2026). Phases 1 and 2, conflicts first (kept) and the option (b) hardening are built
(§10 item 9), Phase 3 (C) was reverted, Phase 4 (B1) is parked, Phases 5 and 6 (D, B2 and B3) are dropped, and Phase 7
(E) is unscheduled (§10). Only the `given` residual that `fixes/Z_SPEC01.md` Q26 owns remains (§10 item 4). Two decisions
are open and unscheduled: binding `conflicts[].group_id` in the conflict-group repair (§10 item 3) and a mismatch between
`conflict_groups` and the `conflicting` dispositions (§10 item 10).

Any later phase follows SPEC01 §2: `/preflight`; offline tests at the owning boundary; `zig build verify`; one
change set for each measured build, on a committed, unmodified build; each replay batch, launch and set approved
on its own; kept or reverted on accuracy counts, never on cost. A request-text change first needs a paired replay
screen of hello-world's scenarios call (§13).

## 13. Results later work relies on

The build, review and live-set records of Phases 1 to 3, conflicts first and item 11 were deleted on 27 November 2026;
each run's evaluation stays under `evaluations/e2e/<run>/`.

- **Request text moves the Given rate** (Phase 3, 25 November 2026). Removing the schema's text copy (build `9802ec9`,
  modified) cut development-case tokens by 12% to 15%, and every hello-world run then gave each of its three criteria a
  Given, where the four runs before had none. A paired replay of the scenarios call (`call-000009` of
  `2026-11-25T08-07-42Z`, ten repeats an arm, `claude-haiku-5-5`, effort `low`; edit file
  `evaluations/replay-screen/hello-world-call9-with-schema-text.edit.json`) gave a Given in 10 of 10 answers as captured,
  without the copy, against 4 of 10 with the complete schema added back as a guidance part; the arms differ only by that
  text (one-sided exact p about 0.005, a derived figure). So the text copy is an established factor in that call's
  Given rate, and Phase 3 was reverted. Limits: one call, one case, one source run, and the edit puts the text before the
  framing where the old layout put it after. Captures of the Phase 3 build (`2026-11-25T08-*`) fail exact replay on the
  reverted tree.
- **Conflicts first, live set of 26 November 2026** (user: `/live-e2e hello-world loan-renewal loan-renewal-conflict
  loan-renewal-conflict loan-renewal-conflict`). Five launches on build `fc57ddc`, modified, `source_sha256`
  `fa1ca937…e4a7`, `claude-haiku-5-5`. hello-world passed at 100% with no accuracy defect; loan-renewal passed at 96.43%
  with 2 minor Given additions. The conflict case raised no form and reached no second leg in 3 of 3 launches; each
  declared the groups `[[4,5],[1,5]]` (§10 item 13). The first pass reviewed the conflict subjects alone, 2 or 3 review
  calls, and first legs took 40,146 to 47,120 tokens, against 111,673 to 132,040 in the earlier launches that reached
  the review. Semantic benefit on the target criterion: not demonstrated. Evaluations: `evaluations/e2e/2026-11-25T22-*`.
- **Option (b), offline.** The request-projection freeze `evaluations/request-projection/conflicts-first-repair-aware`
  equals `conflicts-first-after` (146 scenarios, 1,818 calls); `conflicts-first-before` has 1,856 calls, and the
  difference is the non-conflict review requests a blocked pass no longer sends.
