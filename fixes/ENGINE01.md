# ENGINE01 — Model input size, token spend and repair value

Analysis of 24 and 25 November 2026, kept at this path at the user's request ("do not guess, do full
analysis"). It answers five questions: how larger inputs are managed, where the conflict case's tokens
go, whether tokens are used efficiently, whether repairs help, and whether JSON is the right structure to
send to the model. Items use SPEC01's format. **Decision** marks a question only the user settles. A
recommendation here is not a decision, and nothing here grants approval.

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
   its answer in the second leg (§11).
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

- **Budget.** A alone puts the conflict case about 14,000 to 16,000 tokens under 125,000. A and B put it about
  39,000 under.
- **How B was sized.** The re-encoding stays JSON and only removes or merges members: coordinates, extractor
  metadata, each citation's repeated text, content wrappers, `evidence_rules` and repeated field rules. A
  designed layout could differ either way, and a dropped member may prove to be needed.
- **E is small here** because every source fits one chunk. Its purpose is large sources (§4).
- **Stating limits as field descriptions** was considered for C and dropped: §7 shows the limits do very little.

## 10. Decisions and open items

Each item needs `/preflight`, its phase approval and its own live approvals (SPEC01 §2). Items 3 to 7 change
model requests, so each is a measured phase with screens and a set. §11 reviews their feasibility and §12
orders them into phases.

1. **Prompt-only mode is removed. Decided** 25 November 2026 (user: "remove the "json": false, is bring limited
   values and bloats the code base"; "update the docss"). **Built** 25 November 2026 (user: "implement phase 1 and
   phase 2"; Phase 1 of §12). Offline checks passed on the final tree (§13). Not run live.
   - **Class:** tech debt. It targets no published-output defect: every E2E slot and the frozen protocol
     already use native mode (JSON.md §2; `test/calibration/semantic-simplicity/protocol.json:10`).
   - **What goes:** the catalogue's `json` member (`design/schemas/sddproviders.schema.json:38`, `:45-47`), the
     mode it selects (`src/domain/llm_provider_registry.zig:56`, `:183`; `ResponseGuidanceMode`,
     `src/domain/model_controls.zig:3`), the prompt-only capability (`src/domain/model_capabilities.zig:6`,
     `:33-34`) and the prompt-only request shape (`src/adapters/provider/model_text_request.zig:19-35`;
     `src/adapters/provider/request_replay.zig:42-43`). Native becomes the only mode, so a model whose
     registered contract lacks native JSON-schema output can't be bound.
   - **What it touches** (grep, 25 November 2026): the test-only provider contracts are prompt-only
     (`src/domain/llm_provider_contracts.zig:288`, `:328`, `:363`), so every fixture that binds one with
     `"json": false` changes (`src/llm_provider_registry_test.zig`, `src/model_provider_bootstrap_test.zig:518`,
     `src/domain/llm_provider_document_decode.zig:73`, `test/integration/workflow_tests.zig:4164`,
     `test/harness/integration/tests.zig:2274`, `test/harness/diagnostic_binding_test.zig`). Fifteen files under
     `test/calibration/` and the call evidence's `response_mode` (`model-call-evidence/v3`) name the mode.
   - **Amendments that land with the code:** ADR 0006:124-134, ADR 0014:18-20 and :43-46, ADR 0028:113-115 and
     :178-180, ADR 0029:84, F0006, F0007:54, design.md, 12-model-boundary.md:54 and :210-213, e2e.md:118-123,
     the catalogue schema, both shipped catalogues and JSON.md §2.
   - **Open for `/preflight`:** whether the retained calibration records and the call-evidence contract keep
     the member as history or drop it under a new version (SPEC01 §2 rule 12; ADR 0011:142-143 keeps frozen
     calibration settings unchanged), and how the test-only provider gets a native contract.
   - **Proof:** engine track (SPEC01 §2 rule 10). All three cases send native mode, so every accounted
     request's projection stays byte-identical.
   - **Consequences:** JSON.md D2 is settled, with no prompt-only GPT-OSS set. A vendor that documents JSON mode
     only (§7) can't be added without a new decision. Item 4 then has no prompt-only route to keep a text copy
     for.
2. **Decision: the defect class for review-cost work.**
   - **Class:** completion of a clarification-expected run. E7's measure is the conflict case's
     complete-publication rate (SPEC01:406-408); it is zero in six launches, four of them budget stops in
     source review.
   - **Why a decision:** without a named class, items 3 to 7 are cost-only changes, which AGENTS.md bars.
   - **Recommended:** name that rate as the target, with finding-type accuracy and the two development cases'
     accuracy counts as guards.
   - **Used by item 9** (decided 25 November 2026), which takes this class and that rate as its target. For the other
     items it stays a recommendation.
3. **Change A: one review subject for each conflicting claim group.** **Built** 25 November 2026 (Phase 2 of §12;
   offline checks passed, §13). Not run live.
   - **Class:** item 2's. By code it is also a completion defect of its own: with two records over one claim
     pair, no answer can be applied (§11).
   - **Owner:** the conflicts answer, one record for each group: the rule in `conflictSelectionAvailable`
     (`src/domain/reference_reconciliation_validation.zig:223-228`) and the request at
     `reconciliation-conflicts.prompt.md:2`. Seeding one requirement per group instead
     (`specification_authority.zig:43-49`) is ruled out by §11: the records would still share claims.
   - **Authority:** amends ADR 0022:136-137. It groups no review subjects, so SPEC01:537-538 is untouched.
   - **Evidence:** 4, 3, 5 and 4 records for 2, 1, 2 and 2 claim pairs in the four budget-stopped launches. A
     conflict subject's task is whether the pair's meanings are incompatible, the same question for every
     kind. Stage 5b already merges the gaps of one subject into one need (SPEC01:369-373).
   - **Arithmetic, not run:** with one subject per pair, runs A and B have 11 subjects, about 112,500 and
     110,600 tokens.
   - **Against it:** a verdict that depends on the kind would be lost. Two verdicts of run A were read and
     both were `conflicting`; the rest weren't read.
   - **Decision value:** a set where the case reaches its form, with review findings labelled, keeps it. A
     fall in finding-type accuracy reverts it.
4. **Change C: one schema copy. Built, measured and reverted** 25 November 2026 (user: "action Phase 3", then "revert
   phase 3"; §13). The tree is back to the build before it (1,626 of 1,628 recorded inputs byte-identical; the other two
   differ only by two Phase 1 wording fixes). Measured: tokens −12% to −15% on the development cases, but the text copy
   is an established factor in the scenarios call's Given rate (hello-world: a Given in all three criteria of all three
   runs, 0 of 4 runs before; replays 10 of 10 trials without the copy against 4 of 10 with it), so the keep-if "the
   accuracy counts don't worsen" failed. Q26's removal of the Given depended on the model seeing that text.
   - **A later attempt needs** the `given` conflict settled first as its own measured change: the packet says a criterion
     whose sources state no starting situation has none (`purpose`), and the field rule says "Write nonblank prose"
     (`model_field_presentation.zig`); Q26's record names that `prompt_conflict` as the likely cause of its retained
     repeats (Z_SPEC01 "Q26"). The same sensitivity may apply to other call kinds not screened.
   - **Read as covered by "action Phase 3"** (decisions taken, each open to correction; now moot): the defect class of
     item 2; all limits leaving the model's view; the correction locator moving to the native projection; no version
     advance; the conflict case left as written (SPEC01:414-415).
   - **Class:** none of its own. It widens every run's margin under the budget (loan-renewal reached 101,582
     of 125,000 in this set); otherwise it is a cost change, kept on guards.
   - **Owner:** the request layout (`src/adapters/provider/model_text_request.zig:19-35`), which sends the
     complete schema as guidance beside the native structure (before 25 November 2026).
   - **Authority:** amends 12-model-boundary.md:210-213, ADR 0006:130-132 and ADR 0014:45-46.
   - **Evidence:** §7. The text copy's only unique content is the limits; no retained answer came near a cap,
     and the one empty string was written with the rule shown. The provider adds its own description of the
     format.
   - **Against it:** every run so far stated the limits, so the rejection rate without them is unknown, and
     each rejection re-sends a whole request.
   - **Decision value:** it needs a build, since a replay sends the captured mode through the same layout
     (e2e.md:118-123). A set whose schema rejections per call don't rise and whose accuracy counts don't
     worsen keeps it.
5. **Change B: a model view of each request.**
   - **Class:** item 2's for review. None named for the other call kinds.
   - **Owner:** the packet builders: `packetForContext` (`src/domain/specification_support.zig:105-160`), the
     evidence projections (`src/domain/model_evidence.zig`), the generation packets
     (`src/domain/specification_session.zig`) and the scenario packet (`src/domain/scenario_request.zig`). §11
     splits it into three parts by owner, because the evidence projection and the field rules are each shared by
     several call kinds.
   - **Authority:** it follows ADR 0013:89-91. It amends F0100:764-766 (coordinates in review), ADR 0023:137-138
     (the evidence rule in the packet) and ADR 0016's packet guidance.
   - **Against it:** no run has used another layout, and the provider's figure for question-last ordering is
     for inputs of 20k tokens or more.
   - **Decision value:** replay retained review requests as captured and in the view, about ten each, and
     compare verdicts; then a set on all three cases. Whether the replay tool's `--edit` takes a payload that
     isn't JSON was not checked.
6. **Change D: no principle files in Spec. Dropped. Decided** 26 November 2026 (user: "update the documentation as per
   recommendation", on the recommendation to keep the files). Nothing built, nothing to revert. The principle files
   stay in the records request (D17.1; ADR 0015:16-18; 17-specify.md:332-339).
   - **Why it was proposed.** The files are 68% of a record-generation call's characters (an estimated 9,700 to 11,300
     tokens a call, §4), and D17.1's set found "no content traces to a principle file" in nine runs and reported "the
     model ignores the principle text" (Z_SPEC01:2143-2158). That is a cost argument and a leakage measure.
   - **Why it is dropped.** The goal is output quality, and removal has no quality case:
     - **Class:** none (cost only), and it reverses the user's decision. AGENTS.md bars a cost-only change.
     - **Expected quality gain from removal: 0.** Leakage is already 0 in every output observed: Q17's nine runs and 20
       replays, and the eight publications of 25 November 2026. Spec is built so a principle can't become content: the
       records prompt says principles "are not sources: they add no requirement or condition of this feature", records
       cite only source claims and a principle supplies no passive literal or exact value (17-specify.md:337-339), and
       the rubric scores technical prescription down (`proportionate-business-scope`, `source-grounding`).
     - **A concrete way removal could lose quality.** A story that names a project term the principles define (a UI
       principle's colour, say) would reach the model with only the story's words. Today the records call can read the
       definition and keep the term as a reference; without it the model could weaken the term, invent a value or keep
       words it can't interpret. No run covers this: AGENTS.md keeps story values out of case principle files, so no case
       has a story that depends on one. The 37 outputs show that principles don't leak into stories that never reference
       them, and nothing more.
     - **What is not measured, either way.** Whether the files prevent invented storage or UI content, and whether
       removing text the model seems to ignore moves anything. Phase 3 showed the second can happen: the schema text
       looked redundant and removing it moved the Given rate from 12 of 30 scenarios to 30 of 30 (§13).
   - **A gap that remains with the files kept.** Only the records call carries them; the scenarios call writes an
     acceptance criterion for the same requirement without them. Whether that causes defects is unmeasured, and measuring
     it needs a case the testing rule forbids today. The user's decision, not proposed.
   - **A later attempt** would need a quality target first (a defect class the files cause or prevent) and a case that
     can show it, then a paired replay of the records call.
7. **Change E, and the decision it needs: what "bounded" means for the evidence a call carries.**
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
   - **Need:** review scoping serves item 2's class. Source-text scoping has no case that needs it yet: the
     three cases' sources are under 600 characters each.
   - **Order:** last. It saves 2% to 3% on today's cases (§9) and waits for a case with a large source.
8. **PLAN01 PD8 uses an earlier token figure.** No Spec change. PD8's "about 20 carrying requests" becomes
   about 11 to 13 at this set's measured request size (§4). The user's when Plan is actioned (ADR 0034). Item 6 keeps
   Spec's principle files, so the figure stands unchanged by it.
9. **One contradiction raises several forms: conflicts first. Decided** 25 November 2026 (user: "update the
   documentaion with the recommendations", on the two recommendations below). Not built. Found by the 25 November set
   (§13); independent of Phase 3. The amendments to F0100, ADR 0023 and 17-specify.md land with the code.
   - **What happens** (code and the two launches that reached forms):
     - Any conflict record makes the reconciliation `blocked` (`src/domain/reference_snapshot.zig:25`), so
       `generationReady` is false (`src/domain/specification_provenance.zig:38-44`) and the workflow takes the full
       source-readiness review (`spec.workflow.yaml:107-124`): every seed of `projectRecords`
       (`src/domain/specification_authority.zig:29-56`), which is six feature requirements, each signal, each conflict
       record and each exact token. That was 14 review calls and about 88,000 tokens in each launch.
     - A feature-requirement subject sees every source's full text and may return `conflicting` like any other subject
       (`support.schema.json` `finding`; `support.prompt.md:21-24`). Its flow or description does depend on the undecided
       limit, so the verdict is a fair reading and not a fault of the model: 3 and 2 feature subjects returned it, beside
       the conflict subject.
     - One need is made for each stage and subject, and a subject is `{requirement, unit, slot, sources}` (ADR 0025:152-166;
       14-orchestration.md:339-345). Each feature slot is its own subject and none is the conflict's, so the forms can't
       merge. Only the conflict's form is `select_one`; the others are free text
       (`src/domain/required_authority_clarifications.zig:167-171`).
   - **Consequences.** The launcher needs exactly one open form (`test/harness/e2e/answer.zig:46-49`), so no second leg
     runs. For a user, three of four forms ask what the fourth asks; a text answer to them "applies nothing" (ADR 0025:205-207),
     and publication needs no open form (F0100:1457-1458), so each must still be closed.
   - **Correction.** This item first said the forms were "about the same claims" and could merge by "an engine rule over
     typed claim IDs". That was wrong: a feature subject's negative finding holds source IDs and no claim IDs
     (`src/domain/specification_support_evidence.zig:117`), and merging across subjects is barred
     (12-model-boundary.md:651-654; design.md:969; 28-testing.md:147-148).
   - **Authority.** No clause says who owns a source contradiction. For the conflict record: 16-reference-ingestion.md:254
     ("exactly one conflict-bound `SNN`"), :364-365, 12-model-boundary.md:882-884, 21-validation.md:43. Against any
     cross-subject sharing: the three clauses above.
   - **Options weighed.**
     - *Fold a feature verdict into the conflict's need by claim IDs:* needs the model to select claims, which
       12-model-boundary.md:849-851 and ADR 0023:138 bar, an approved answer-sharing contract, and a rule for a select
       answer settling a text gap (ADR 0025:195). Model-dependent, and the review cost stays. No.
     - *Feature subjects may not return `conflicting`:* the model may return `ambiguous` or `unsupported` instead, which
       still makes a form (speculative), and a contradiction reconciliation missed would have no route. No.
     - *Leave conflict lines out of feature packets:* filtering evidence, barred by ADR 0013:94-95, ADR 0016:120 and
       17-specify.md:458-459. No.
     - *Leave it as a model limitation* (SPEC01:413-415): needs nothing, but the duplication is the engine's rule applied
       to a fair verdict, and the second leg never runs. No.
   - **Recommended: conflicts first.** The readiness projection of a blocked reconciliation is its conflict records and
     their forced gaps, nothing else. A complete reconciliation with no eligible claim keeps today's projection (it holds
     no conflict). So the two reasons readiness can fail get two disjoint projections.
     - **Owner:** `projectRecords`. It has one production caller
       (`src/actions/authority/build_specification_authority_requirements.zig:7`), and the gate rebuilds the projection
       through the same function (`src/domain/required_authority.zig:181-184`), so builder and gate can't disagree.
     - **Why it is safe, checked in code.** While a conflict record exists the gate can't return `all_resolved`: a
       conflict's forced gap is discharged only by an established `conflicting` finding, which needs the user, or it is a
       candidate defect, which goes to repair (`required_authority.zig:492-494`, `:513-531`). So in a blocked pass the
       other subjects' reviews can't lead to generation; they can only add forms or repairs. After the choice is applied
       (`apply-answers`, before `source-readiness`) the reconciliation is complete, and the run generates with no review,
       the path every source without a conflict takes today. The incomplete specification of leg 1 lists the eligible
       claims and doesn't use the other subjects' verdicts (observed in `2026-11-25T08-11-23Z`).
     - **Fits the rules:** it groups no subjects (SPEC01:537-538), filters no evidence (the conflict subject keeps its
       whole packet), shares no answer, judges no prose, and sends the decision through the `select_one` form
       (ADR 0025:189).
     - **Amends:** F0100:680-683 (what the projection holds), with ADR 0023:46-48 and 17-specify.md stating the rule.
     - **Expected** (estimates from this set's per-call sizes, not runs): one form for each conflict group; leg 1 at about
       32,000 tokens for one group and 41,000 for two (today 111,673 to 126,129), so the first leg's budget stop goes
       without any request text changing; leg 2 about 70,000 if the choice applies.
   - **Limits found while validating.**
     - **Leg 2 reconciles again.** It re-runs extraction and reconciliation (`spec.workflow.yaml:80-99`), so the choice
       applies only if the new reconciliation draws a conflict over the same lines. If it draws none, "the choice is unused
       and the report does not say so" (ADR 0025:207-208), and both claims would be generated from. If it draws two groups
       sharing a claim, neither is answerable and the need is re-raised as `ProtectedClarification`. ADR 0025:268 leaves this
       "until stage 7's case shows whether an answered subject matches on a rerun": conflicts first is what lets that case
       run.
     - **It covers the conflict branch only.** In the other branch (no eligible claim) several feature subjects could
       still each raise a form about one missing decision. No case shows it.
     - **A gap unrelated to the conflict isn't asked while a conflict is open.** A source without a conflict isn't
       reviewed for it either.
     - **A second conflict group still means two forms** (1 of the 3 latest launches), the model limitation SPEC01 names.
     - **Tests.** About 19 call sites in `src/specification_generation_test.zig` and the scripted conflict scenarios read
       the projection; `src/test_fixtures/source_loss_calibration.zig:425` does too, and whether a frozen calibration
       record depends on it must be checked at `/preflight`.
   - **Proof.** Tests at the owner (blocked: conflicts only; complete with no eligible claim: today's projection). A
     request-projection freeze before and after: only the conflict scenarios' review requests should go, and the
     development cases send no review request, so theirs stay byte-identical (SPEC01 rule 10). Then three launches of the
     conflict case: forms per launch, whether leg 2 runs, and its adjudication.
   - **Decided (1): adopt conflicts first,** with those amendments. Reasons:
     - **Need.** Class: completion of a clarification-expected run (item 2). The conflict case has published in none of
       its launches and its second leg has never run, so answer application and publication after an answer have no live
       evidence. It is also a defect for a user: one decision asked in 3 or 4 forms, of which only the select answer is
       applied.
     - **Cause at its owner.** The verdicts are fair; the duplication comes from reviewing every subject while a conflict is
       open. One function owns that, and the gate rebuilds from it.
     - **Deterministic and inside the rules.** It keys on a typed fact, with no prose rule and no reliance on the model; it
       groups no subjects, filters no evidence and shares no answer.
     - **No request text changes.** Phase 3 failed because changing request text moved the Given rate. This changes which
       requests a blocked pass sends, not their content, and the development cases send no review request.
     - **The alternatives are worse** (above). The lower first-leg cost is a side effect, not the reason.
   - **Decided (2): the conflict case is the live proof for this change.** Reasons: the development cases never review
     (§11 finding 3), so they can show only that nothing changed for them; the class is completion of a clarification run, so
     its measure is this case's own criterion; and the case stays "neither a reserved qualification feature nor a tuning
     target" (SPEC01:413-415) because its text and rubric don't change and the criteria below are fixed first. It is no
     exception to AGENTS.md: both development cases still decide that their requests and output are unchanged.
   - **Fixed before any launch** (SPEC01 rule 6):
     - **Target:** forms raised by a first leg equal the conflict groups its reconciliation declares; a first leg with
       one group reaches its second leg; the case's complete-publication rate (zero so far).
     - **Guards.** Development cases: the request projection byte-identical before and after (offline), and one live run of
       each that publishes with no `lost_source_requirement`. Second-leg publications, on the case rubric: the chosen bullet
       kept (`lost_source_requirement`), the other absent (`contradiction`), no invented resolution
       (`unsupported_addition`), which are E7's guards (SPEC01 §5).
     - **Watch, reported apart and never retried:** a second leg whose reconciliation draws no conflict, so the choice is
       unused; a `ProtectedClarification` block; a launch with two conflict groups; item 10's block.
     - **Runs:** three launches of the conflict case, extended to at most eight with approval; every attempt counts.
     - **Reporting.** Counts, not a rate claim: fewer than about ten events is "not enough evidence" (SPEC01 rule 6), and one
       case qualifies the scope to this source. The unrelated member of the class is an offline scripted fixture in another
       domain; a second live conflict case is not planned.
10. **Open: a mismatch between `conflict_groups` and the `conflicting` dispositions blocks the run** (one launch, §13). A
    group naming a `retained` claim is rejected at canonical validation, and the `dispositions` unit has no repair route
    (`src/domain/reference_reconciliation_repair.zig:157`, ADR 0046). Not a Phase 2 or Phase 3 effect. **Decision:** derive
    the groups' claims from the dispositions, correct the mismatch at admission as ADR 0046 does for a missing
    disposition, or leave it as a valid model limitation. Not proposed; one run.
11. **Open: the incomplete specification prints claims with their source markup escaped** (seen in both first legs that
    published one, `2026-11-25T08-11-23Z` and `08-17-33Z`: 4 of 4 supported requirements each). A claim keeps its source
    line's list marker and code spans, and the incomplete-specification renderer
    (`src/domain/incomplete_specification_markdown.zig`) escapes them, so a requirement reads
    ``- \- A borrower must …`` and ``\`Loan renewed!\```. Class: `rendering_artefact` in the ADR 0017 publication, which no
    evaluation scores because a first leg is never evaluated. The cause (the claim text keeping the marker, or the escape)
    was not traced. Not proposed.
12. **Stale status text.** F0100:28-29, :961-962, :971-972 and :1544, and design.md:1145, still say ADR 0025's answer
    application isn't implemented; ADR 0025:3-5 says the conflict answer is. A documentation fix for whenever those files
    are next amended.

**Not proposed.**

- A larger budget (SPEC01:523-525), batching review subjects (SPEC01:537-538), token ceilings or pre-call
  counting (ADR 0011), and any model change (SPEC01:521).
- Prompt caching, while it changes no accounted token and no output. If it is ever taken up, it needs an ADR
  0028 amendment and a payload whose shared members come before the subject.
- Removing the length limits from the engine. They stay in the complete schema as the acceptance check.
- Any change to repair (§6).

**Open uncertainty.**

- The conflict case's second leg has never run, so its cost and its output are unknown.
- No large source has been run. §4's growth is read from code and contracts and sized on three small cases.
- §9's savings are estimates. No change has been built, replayed or run.
- Two of the three `STRING_LENGTH` rejections since 17 November are no longer retained, so which limit they
  broke is unknown.
- Why the HTTP 401 occurred is outside the run's records.

## 11. Feasibility review

Read-only review of 25 November 2026. The code was read, not executed. "Grep" marks a count taken from a
search.

**What the review found.**

1. **The conflict case can't apply its answer today, whatever the budget.** An answer is applied only to a
   conflict none of whose claims is in another conflict record (`src/domain/answered_reconciliation.zig:112-123`;
   its test says so at `src/answered_reconciliation_test.zig:104`). Two records over one claim pair, which the
   prompt invites, each see the other as another conflict, so neither is answered and the form is raised again
   (`answered_reconciliation.zig:7-9`). A pair had more than one kind in 4 of the 5 launches that reached
   conflict explanations. Not executed: no launch has reached its second leg.
2. **The model declares a second conflict in 5 of 6 launches.** Beside the intended pair (stories 8 and 9) it
   pairs "not previously been renewed" (stories 5) with "up to twice" (stories 9). Two pairs that share a claim
   are unanswerable under the same rule, and they raise two forms, where the launcher runs the second leg only
   on exactly one (SPEC01:419-420). Change A doesn't remove this. The evaluation of `2026-11-24T07-41-20Z` calls
   it a defensible reading of the case text. Whether stories 5 is reworded is the user's.
3. **Review requests never occur in the two development cases.** Those cases have no conflict and set
   `sourcePreservationCheck` false (§4), so changes A, B1 and E alter none of their requests. A review-request
   change therefore can't be decided "on both development cases" (AGENTS.md). The conflict case is the only
   live member, and SPEC01:413-415 says it is not a tuning target. **Decided** 25 November 2026 for conflicts first
   (§10 item 9): the conflict case is its live proof, and the development cases show only that nothing changed for
   them. For any other review-path change this is still open.
4. **One projection serves reconciliation, review and repair** (ADR 0013:93; `src/domain/model_evidence.zig`).
   Stating claims by line number changes the reconciliation requests of all three cases together with the
   review requests.
5. **One presenter writes `field_rules` and `insertion_fields` into every packet**
   (`src/domain/model_field_presentation.zig:78-113`). Grouping repeated rules changes every call kind at once.
6. **Fifty review verdicts are retained** from the five conflict launches that reached review. They can be
   labelled as the reference for finding-type accuracy (evaluate-e2e §7) before any change.

**By change.** Findings 4 and 5 split change B into three parts.

| Change | Verdict | What it touches | Requests that change | Proof | Needs first |
| --- | --- | --- | --- | --- | --- |
| A | Feasible and small. Required for the conflict case to complete | The uniqueness rule (`src/domain/reference_reconciliation_validation.zig:223-228`, also used on snapshot readback at `reference_snapshot.zig:140`), the prompt line and ADR 0022:136-137. No schema or persisted shape changes: a record keeps one `kind` | The conflict case's conflict-explanation request | Rule 10 for the development cases; launches of the conflict case | Phase 0 |
| B1: review packet | Feasible, medium | `packetForContext` (`src/domain/specification_support.zig:105-160`): member order, `evidence_rules`, the requirement's evidence terms, and the extraction review's coordinates | Review requests, so the conflict case only | Replays with `--edit`; launches of the conflict case | A |
| B2: evidence projection | Feasible, large | `src/domain/model_evidence.zig` and its readers; 56 lines of `src/specification_generation_test.zig` name the members (grep) | Reconciliation in all three cases, and review | Replays for each call kind, then a set | C |
| B3: field rules | Feasible, medium | `model_field_presentation.zig:78-113` and the packet-guidance contract | Every call kind | A set | C |
| C | Feasible. One line of layout, wide test impact. **Built and reverted** (§10 item 4, §13) | `layout` (`src/adapters/provider/model_text_request.zig`) and the `guidance` member of `TextSchema` | Every request | A set. No replay can precede it: the replay tool sends its content through the same layout (e2e.md:83-91) | §10 item 1 |
| D | **Dropped 26 November 2026** (§10 item 6). Was: feasible and small, a revert of a known change set | `src/domain/specification_principles.zig` (about 25 lines), its call at `src/actions/specification/build_specification_model_input.zig:10-16`, `records.prompt.md:14-15`, and the architecture pin and tests that Z_SPEC01 Q17 lists. Capture stays (ADR 0015) | Record-generation requests | Replays with and without `principles`, then a set | The user's reversal of D17.1, not made |
| E | Not yet | Nothing until the "bounded" decision. Its review half overlaps B1 | None yet | None yet | A case with a large source |

- **A's form.** `conflictSelectionAvailable` rejects a second record only when both its kind and its members
  match an earlier one. Dropping the kind test makes a second record for the same claims a `duplicate_conflict`,
  which the existing repair handles (`src/domain/reference_reconciliation_repair.zig:194`). The prompt then asks
  for one kind. The kind is printed in `reference-context.md` (`src/domain/reference_context.zig:60`) and sent
  to review; no code branches on its value (grep).
- **A's expected effect.** With one record for each pair, a launch shaped like run B could apply its answer. The
  other five keep finding 2's second pair.
- **C after §10 item 1.** With one mode left, C deletes the guidance text and its member; it adds no branch.
- **B's versions.** A packet shape change advances each closed contract it touches, with no compatibility
  reader (ADR 0030 "Versions"): packet guidance, the required-authority contract and the request description.
- **Unverified:** whether `--edit` accepts a user part that isn't JSON. B1's replays can stay JSON.

## 12. Phased rollout (recommended; not decided)

Every phase follows SPEC01 §2: `/preflight`; offline tests at the owning boundary; `zig build verify`; one
change set for each measured build, on a committed, unmodified build; each replay batch, launch and set approved
on its own; kept or reverted on accuracy counts, never on cost. A phase that isn't kept is reverted in full.
Token figures are §9's estimates.

**Order after 25 November 2026** (item 1 is decided, the rest is recommended; Phases 1 and 2 are built and Phase 3 is
reverted):

1. **Conflicts first** (§10 item 9; decided, not built). It removes the duplicate forms, lets the second leg run for the first time, and takes
   the first leg under the budget without changing any request text. It comes before Phase 4, whose saving in the review
   packet matters far less once a blocked pass reviews only the conflict records.
2. **The group and disposition mismatch** (§10 item 10), which blocked one launch in three.
3. **Phase 4, 6 and 7** (Phase 5 is dropped), each with a paired replay screen of hello-world's scenarios call first:
   Phase 3 showed that the Given rate rides on request text (§13).
4. **One schema copy again** only after the `given` conflict is settled as its own change (§10 item 4).

**Phase 0. Decisions and reference.** No code.

- **Decisions:** the defect class (§10 item 2); the conflict-case question of finding 2, to reword stories 5 or
  to accept two forms as an unmet criterion; what evidence decides a review-request change (finding 3); the
  amendments each later phase names. The reversal of D17.1 is not made (§10 item 6).
- **Reference:** label the 50 retained review verdicts, and take a request-projection freeze on the base commit
  (e2e.md:758-792).
- **Exit:** each later phase has its decision or is dropped.

**Phase 1. Remove prompt-only mode** (§10 item 1). Engine track. **Built 25 November 2026** (§13).

- **Proof:** rule 10. The freeze diff is empty, then one live run of each case.
- **Tokens:** no change.

**Phase 2. Change A.** One record for each conflict group. **Built 25 November 2026** (§13).

- **Builds:** the rule, the prompt line, the ADR 0022 amendment, and a scripted scenario whose first conflict
  answer lists two kinds for one pair.
- **Proof:** rule 10 for the development cases, and three launches of the conflict case.
- **Keep if:** the first leg ends `clarification` under the budget, no pair has two records, and finding-type
  accuracy doesn't fall against the reference.
- **Expected:** 109,100 to 110,900 tokens on the conflict case. Complete publication also needs finding 2
  settled. **Not met, 25 November 2026:** the one launch after A took 126,129 tokens, 13 subjects, every one assessed
  (§13). The estimate counted 13 subjects before A and 11 after; the earlier launches had 16 and were cut at 13.

**Phase 3. Change C.** One schema copy. **Built, measured and reverted 25 November 2026** (§10 item 4, §13): the
keep-if failed for hello-world. Not scheduled again until the `given` conflict is settled. The plan below is the one
that was run.

- **Builds:** the layout change, the amendments to 12-model-boundary.md:210-213, ADR 0006:130-132 and
  ADR 0014:45-46. **Corrected 25 November 2026:** no new freeze. The projection records each request's
  `model_request_description`, which keeps the complete schema, so a freeze diff of this change is empty and
  proves nothing; the proof is the encoders' wire tests and the set.
- **Proof:** a set of three runs for each case, extended to eight if undecided.
- **Keep if:** schema rejections per call don't rise above the reference (14 in 1,806 calls since 17 November),
  publication doesn't fall and the accuracy counts don't worsen.
- **Expected:** hello-world 32,000–33,100; loan-renewal 57,500–88,300; conflict 90,500–92,300. **Revised
  25 November 2026** for the conflict case, from the 25 November launch's per-call sizes (the text schema is 3,268
  characters in each review call and 864 to 1,383 in each of the six earlier calls, an estimated 1,440 and 2,850
  tokens in all; not a run): about 104,600 tokens for 13 subjects and 111,100 for 14, before any other change.
  That is 14,000 to 20,000 under the budget, room for two or three re-sent review requests (about 6,550 tokens
  each); a 15th subject leaves about 7,000.

**Phase 4. Change B1.** The review packet.

- **Needs:** Phase 2 kept.
- **Builds:** evidence before the subject, no `evidence_rules` or evidence vocabulary, and no coordinates in
  the extraction review. Amends F0100:764-766 and ADR 0023:137-138.
- **Proof:** replays of retained review requests, as captured and edited, about ten each (captures of the Phase 3
  build, `2026-11-25T08-*`, fail exact replay on the reverted tree; the earlier ones replay); then three launches
  of the conflict case.
- **Keep if:** verdicts match the reference labels at least as often, and the first leg still ends
  `clarification`.
- **Expected:** not sized apart from B2 and B3.

**Phase 5. Change D.** No principle files in Spec. **Dropped 26 November 2026** (§10 item 6): removal has no quality
case, and the principle files stay. Not scheduled; a later attempt needs a quality target and a case that can show it
first.

**Phase 6. Changes B2 and B3.** The evidence projection, then the field rules, as two change sets.

- **Builds:** claims by line number with no citation coordinates or repeated text; repeated field rules
  grouped; the contract versions.
- **Proof:** replays for each call kind, then a set for each change set.
- **Keep if:** as Phase 3, and reconciliation rejections don't rise.
- **Expected with every earlier phase kept:** hello-world 19,700–20,800; loan-renewal 32,000–41,400; conflict
  66,200–67,800.

**Phase 7. Change E.** Needs the "bounded" decision (§10 item 7) and a case with a large source. Not scheduled.

**Live cost.** Phases 1 and 2 are built and live-checked. What remains needs at least two sets (B2 and B3), conflicts
first's three conflict-case launches (§10 item 9), a group of conflict-case launches for B1, and two replay batches (B1
and B2), each with its own approval.

## 13. Build record, Phases 1 to 3

Built 25 November 2026 (user: "implement phase 1 and phase 2"). Offline only: no live run.

**Phase 2, Change A.**
- `conflictSelectionAvailable` no longer takes the kind (`src/domain/reference_reconciliation_validation.zig`;
  readback in `src/domain/reference_snapshot.zig:140`); the `duplicate_conflict` redundancy test no longer needs an equal
  kind. The conflicts packet binds `conflicts[].group_id` as exact members
  (`src/domain/reference_reconciliation_stage.zig`), so a repeated group is `duplicate_member` and an omitted one
  `missing_member`, each corrected as the whole answer. The prompt asks for one kind per group.
- Amended: ADR 0022 ("Conflict groups"), ADR 0046 Decision 6, F0100, contract 16 step 10.
- Tests: a new admission test (`src/reference_model_input_test.zig`); the old kind-conflating test is rewritten, and the
  conflict-selection repair packet keeps its own test (`src/reference_reconciliation_test.zig`).
- **Coverage moved.** The `conflict_coverage` integration scenario used to reach the coverage insert with an empty
  conflicts answer. That answer is now an admission defect, so the scenario's first attempt omits the group and its
  correction supplies it (`src/test_fixtures/spec_generation_responses.zig`). `insert_conflict` is reachable only after
  a repair removes a record.

**Phase 1, prompt-only mode removed.**
- Removed: `ResponseGuidanceMode`, `StructuredResponse` and `Capabilities.structured_response`, the catalogue's
  `json` member (schema, decoder, both shipped catalogues), the request's and the lease key's mode, and the
  description's `response_mode`. `TextSchema` became one native struct (deleted in Phase 3). Anthropic, Bedrock and Luna always send their
  native structure.
- Versions advanced with no compatibility reader: `model-request-debug/v21` to `v22`, `model-call-evidence/v3` to
  `v4`. Captures of the older versions can't be replayed with `e2e-call`. The retained v1 and v2 evidence readers
  keep parsing a recorded mode into a private `RecordedResponseMode`; that is the one place the old name survives.
- Frozen history is unchanged: `test/calibration/**`, the frozen protocol type in
  `test/harness/generation_comparison.zig` and its tamper test.
- A catalogue entry carrying `json` (true, false, null or a duplicate) is rejected by a new test in
  `src/domain/llm_provider_document_decode.zig`. No registration path remains that could register a model without
  native output, so that rule is structural and has no test of its own.
- Amended: ADRs 0006, 0012, 0013, 0014, 0019, 0028, 0029, 0030; contracts 09, 12, 24, 27, 28; F0005, F0006, F0007;
  `design/harness/e2e.md` and `evaluator.md`; JSON.md §2 and D2.

**Checks on the final tree:** `zig build lint`, `test-architecture`, `test-integration` (158 of 158) and
`zig build verify` (146 of 146 steps, 2,522 of 2,522 tests, smoke included) pass. The request-projection freeze diff
(e2e.md:758-792) was not taken, so "every accounted request's projection stays byte-identical" is not shown beyond the
passing scripted scenarios. One live run of each case, which §12 asks for before Phase 3, has not been made.
**Live check, 25 November 2026** (one launch of each case, build `9802ec9`, modified, `source_sha256` `5f2debec…`; user:
`/live-e2e hello-world loan-renewal loan-renewal-conflict`; an earlier launch of the same set stopped on an HTTP 401 at call 1):
- hello-world `2026-11-25T06-50-34Z`: published, 9 calls, 38,857 tokens, passed 100%, no defect.
- loan-renewal `2026-11-25T06-51-59Z`: published, 11 calls, 64,928 tokens, passed 96.43%, two minor Givens as before.
- conflict `2026-11-25T06-53-34Z`: `WorkflowTokenBudgetExceeded` at source review, 19 calls, 126,129 tokens (1,129 over).
  Phase 2 did what it was built to do: two records for the two declared groups, no correction, no rejection. Review still
  took 13 calls (103,837 tokens), because other subjects (three signals, two token subjects) set the count, so §9's estimate
  that Change A alone puts the case about 15,000 under budget did not hold on this launch. The groups were `[4,5]` and `[1,5]`
  again, so a first leg that finished would raise two forms. The request projection is unchanged for the two publishing cases
  (tokens within 0.5% of the earlier runs). One run each: no reliability claim.

**Review.** `contract-reviewer` ran on both phases (read only; it executed nothing and had no before text for the deleted
tests). It found no blocker. Its four minor findings:
- **Conflict repair paths.** The reviewer and I judged the duplicate-record deletion, the coverage insert and the
  conflict-selection replacement unreachable once admission binds each group. **Partly wrong.** Deleted on the user's
  instruction (25 November 2026: "delete the unreachable conflict repair paths"), after the agent re-checked each path:
  - **Deleted:** `Target.conflict_selection`, `Relations.conflicting_pairs`, the pair-insert branch of the coverage
    repair, and the `repair_conflict_selection` result definition (schema and `specification_result_definitions.zig`).
    Any other rule on a conflict record (cardinality, claim selection, relationship) is now `InvalidAtomicRepair`.
  - **Kept, because reachable:** the group-without-record insert (`Target.insert_conflict`, `repair_conflict_detail`) and
    the duplicate-record deletion with `competing_entries`. The source-omission conflict-group repair
    (`src/domain/reference_reconciliation_repair.zig:728-741`) binds only `claim_dispositions[].claim_id` and
    `conflict_groups[].claim_ids` (`src/domain/reference_model_input.zig:237-254`), and its answer's `conflicts` pass
    `groups.explain` unbound. That answer can omit or repeat an explanation and reach ordinary conflicts validation. Read
    from the code, not run.
  - **Open, a decision:** delete those two as well by binding `conflicts[].group_id` as exact members in the omission
    repair (the same one-line choice as `src/domain/reference_reconciliation_stage.zig`), or by accepting that such an
    answer is an invariant failure. Binding is the smaller change, and would then let both paths go.
  - Tests: a conflicting claim in no group is covered as blocked `no_required_member`; the duplicate test now builds a
    true duplicate and asserts `competing_entries`; the pair-selection test is deleted; the coverage-insert unit test
    stays. ADR 0022 "Conflict groups" states all of this.
- **Historical mode enum.** `RecordedResponseMode` kept the retired `prompt_only` value. **Fixed:** it is
  `enum { native_schema }`, and a v1 capture recording prompt-only is rejected (`test/harness/call/capture_test.zig`).
- **Persisted snapshots.** A snapshot with two kinds over one claim set no longer reads back. **Fixed:** stated in
  ADR 0022 "Conflict groups"; no state version advanced.
- **Stale phrase** in §5. **Fixed.**

Optional, not done: pin in `src/architecture_test.zig` that `Capabilities` has no response field and a catalogue entry
has no `json`. The ladder was re-run after these fixes: `lint`, `test-architecture` and `zig build verify` (146 of 146
steps, 2,523 of 2,523 tests) pass.

### Phase 3, Change C: one schema copy (built, measured, reverted)

Built 25 November 2026 (user: "action Phase 3"), measured below, and **reverted** the same day (user: "revert phase 3").
The revert restored the 31 files Phase 3 touched from the recorded inputs of the build before it (run
`2026-11-25T06-50-34Z`, `build-inputs.json`, source `5f2debec…`) and deleted the one file it added
(`src/test_fixtures/native_schema_wire.zig`). Checked against that record: 1,626 of 1,628 inputs equal; the two that
differ keep the 25 November Phase 1 wording fixes in ADR 0016 and F0006, nothing else. `fixes/JSON.md` was reworded by
hand. `zig build lint`, `test-architecture` and `zig build verify` (146 of 146 steps, 2,523 of 2,523 tests, the same count
as before Phase 3) pass. Kept as evidence: the nine runs and their evaluations, the replay screen's reports and its edit
file (`evaluations/replay-screen/`). The conflict case's first leg is back to about 126,000 tokens, over the budget.
The description below is of what was built.

- **What the model is sent.** The native projection only, at the provider's structured-output position. `TextSchema`,
  `schemaFor` and `freeSchema` are gone; `layout` has no schema part (system and guidance parts, then the framing once);
  `nativeStructure` renders the projection. The complete schema, limits included, stays the acceptance check and stays in
  `description.schema`, so `model-request-debug/v22` is unchanged. The judge wire (`test/harness/bedrock.zig`) lost
  its duplicate too.
- **Consequences the plan did not name** (the contract review found them): a correction's `schema_pointer` now locates in
  the native projection (`anyOf`, not `oneOf`), because the complete schema is no longer sent
  (`src/domain/model_schema_projection.zig`, 22-repair.md §22.6); every assignment-derived item bound (an exact-member
  count, a unique-subset maximum) and every length or range bound reaches the model only through a correction's `shape`.
  Before, one retained `array_length` correction was for 12 claim IDs where at most 4 were allowed (§7).
- **Replays.** Every capture taken before this build fails exact replay and `e2e-call`, including the three runs of
  25 November 2026, whatever its version label says (ADR 0019:139-146; ADR 0030 "Versions" now states it). Phases 4
  to 6's replay proofs need captures from this build.
- **Docs.** Amended (dated, "action Phase 3"): ADRs 0006, 0014, 0023, 0028, 0030; contracts 12 and 22; e2e.md (a
  freeze observes the description only) and evaluator.md; F0006, F0007; JSON.md. Stale Phase 1 leftovers in ADR 0016
  and F0006 fixed.
- **Review** (`contract-reviewer`; read only, no live run): no blocker. Fixed: stale vocabulary and a doc comment on
  `modelBytes()`, an orphaned test comment, a transient citation in a test helper, the debugger's schema label, contract
  12's count rationale (and four repeats of one sentence reduced to one), e2e.md's freeze wording, and a new negative
  test: a pre-change body (the complete schema as a third system block) is rejected by exact replay with no provider call.
  Not done: renaming `modelBytes()`, advancing `model-request-debug`, and the judge protocol hash
  (`test/harness/packet.zig:43-62`), which doesn't bind the request layout, so a later qualification wouldn't go
  stale on this change (no qualification record carries a hash today).
- **Not shown.** Whether the model's rejection rate rises without the bounds: the keep-if is 14 schema rejections in 1,806
  calls. The development cases' slots are all Anthropic `claude-haiku-5-5`; the Bedrock GPT-OSS and Luna routes are
  covered by encoder tests only, and JSON.md J1 has a fragment opening 93% of GPT-OSS answers, so that route may depend
  on the text it no longer receives. A set also needs a committed, unmodified build (SPEC01 rule 3), which the user
  provides.
- **Checks on the final tree, after the review fixes:** `zig build lint`, `test-architecture` and `zig build verify`
  (146 of 146 steps, 2,527 of 2,527 tests, smoke included) pass; the agents also ran `test`, `test-integration` (158),
  `test-e2e-call`, `test-provider-compatibility` and `test-baseline`. No freeze was taken (it can't see this change).

#### Phase 3 set, 25 November 2026 (user: `/live-e2e hello-world loan-renewal loan-renewal-conflict --repeat 3`)

Nine launches, one build: revision `9802ec9`, **modified**, `source_sha256` `62bfb30c…` (SPEC01 rule 3 asks for an
unmodified committed build, so this is a measured set only as far as the user accepts that). All Anthropic
`claude-haiku-5-5`. Targets, guards, watch items and the run maximum (SPEC01 rule 6) were **not recorded before the
set**; the keep-if is the one in §12 Phase 3. Every run is evaluated under `evaluate-e2e` `2b3fb8de…`.

| Case | Runs | Published | Accepted | Calls | Tokens | Accuracy (content defects) |
| --- | --- | --- | --- | --- | --- | --- |
| hello-world | 3 | 3 | 3, 96.43% each | 9, 9, 9 | 32,884; 32,950; 32,911 | `unsupported_addition` 3, 3, 3 |
| loan-renewal | 3 | 3 | 3, 96.43% each | 11, 11, 9 | 56,808; 56,526; 38,629 | `unsupported_addition` 2, 2, 2 |
| conflict | 3 | 0 | none | 21, 21, 4 | 111,673; 112,902; 13,119 | not applicable |

- **Tokens.** hello-world −15% against the previous build's run (38,857); loan-renewal −12.5% on the two runs of the
  same shape (previous 64,928), the third made fewer record groups. As estimated (§12): hello-world 32,000–33,100.
- **Conflict case.** For the first time the first leg completed under the 125,000 budget (2 of 3; 12,098 and 13,327
  to spare, against the estimate of about 111,100 at 14 subjects), with one conflict group and one conflict record
  each (Phase 2 held). The criterion is still unmet in all three, and the second leg has never run:
  - leg 1 of `08-11-23Z` raised **four forms** and `08-17-33Z` **three**, one contradiction each. Each form is a
    `conflicting` verdict of a different review subject (three feature requirements and the conflict subject, or two and
    the conflict subject), with the same question about the same contradiction. The feature verdicts name sources, not
    claims, and forms of different subjects never merge (§10 item 9). The launcher continues on exactly one form;
  - `08-23-17Z` was **blocked** at call 4: the dispositions answer declared a second group (claims 1 and 6) but left
    claim 1 `retained`, which canonical validation rejects (`relationship`), and the `dispositions` unit has no repair route
    (`reference_reconciliation_repair.zig:157`, ADR 0046). Not a Phase 2 or Phase 3 effect by code; one run.
- **Schema rejections.** 2 in 104 calls (1.9%), both `DISAGREEING_ITEMS` at call 1 of the two conflict runs that
  completed, none `STRING_LENGTH` or `ARRAY_LENGTH`; the reference is 14 in 1,806 (0.8%). Fewer than ten events: not
  enough evidence either way (SPEC01 rule 6).
- **Accuracy: the keep-if is not met for hello-world.** Every hello-world run of this build gave each of its three
  acceptance criteria a generic Given ("available to start …"), a minor `unsupported_addition` with a partial link, so
  `source-grounding` fell from 4 to 3 and the aggregate from 100% to 96.43%. The four runs before this build had no Given
  (3 on 24 November, 1 on the 25 November build before Phase 3); of 19 earlier retained hello-world runs, 2 had one. The
  scenario call's user payload is the same length in this build and the one before (1,598 characters), and the only
  difference in its request is the removed text schema (1,138 characters): so the Givens are a candidate effect of Phase 3,
  **likely, not established**. Also seen in two of three runs: "typed exactly as `Hello, World!`", which one 24 November
  run also had. loan-renewal is unchanged (the same two minor Givens in every run of this and the previous build);
  `lost_source_requirement` is 0 in all six publications and the publication rate is 6 of 6.
- **Replay screen, 25 November 2026** (user: "run the paired replay screen"; SPEC01 rule 4; billed, 20 provider calls,
  about 41,300 tokens, `anthropic` / `claude-haiku-5-5`, effort `low`, no retry). Source: `call-000009` (the scenarios call)
  of the hello-world run `2026-11-25T08-07-42Z-3e138a3e…`, ten repeats each:
  - **Arm A, as captured** (`zig-out/e2e-call/2026-11-25T08-32-54Z-5b7b4885…`): **10 of 10** answers gave a Given to all
    three scenarios (30 of 30), the same as the three live runs.
  - **Arm B, the complete schema added as a guidance part** (`--edit
    evaluations/replay-screen/hello-world-call9-with-schema-text.edit.json`; `zig-out/e2e-call/2026-11-25T08-33-41Z-ce5612d2…`):
    **4 of 10** answers gave Givens (12 of 30 scenarios); 6 gave none. Within an answer the model gave all three or none.
  - The arms differ only by the text copy (the edit file's other three parts equal the capture byte for byte; input
    tokens 1,566 against 2,049). Trial counts 10 of 10 against 4 of 10: one-sided exact p about 0.005, a derived figure,
    not a SPEC01 rule. **So the removed text copy is an established factor in this call's Given rate.**
  - **Limits.** Arm B puts the text before the framing, where the old layout put it after, so it may understate the
    old condition (production gave no Given in the four runs before; arm B gave none in 6 of 10). One call, one case, one
    source run; the loan-renewal scenario call already gave Givens on every build and wasn't screened; call 8's "typed
    exactly as" wasn't screened. Protocol checks only; no semantic rating of the answers beyond whether `given` is present.
