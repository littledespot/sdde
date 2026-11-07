# Z_FIX06 — Implemented FIX06 items

Implemented FIX06 items ([convention](README.md)), moved here from 31 October 2026 by the
user's instruction. Earlier completed FIX06 work (Q1, Q2, Q3, Q4's first attempt in full, Q6,
D7.1, D11.1/.2/.4/.5, DE6, T1, T5's measures) is `fixes/Z_FIX06.md` at git `194e29a`; Q10b
D10.2, reverted in full with D13.1 (ADR 0023:25-28), is here at git `388438e`.

## Q2b D2.3. Dispositions complete at response admission (ADR 0046)

**Implemented 31 October 2026; committed in `194e29a`. Kept 1 November 2026 (user: "apply best
recommendations").** ADR 0046 records the decision to implement it and the mechanism:
admission rejects a dispositions answer that omits or repeats an assigned claim
(`missing_member`, `duplicate_member`) under the request's retry limit, and the request the
model receives is unchanged.

- **Defect targeted:** lost source requirement: hello-world's UTC claim was lost when the
  dispositions insert repair answered `duplicate` of claim 1, the only requirement losses in
  20 hello-world publications 26–31 October.
- **Measurement** (12 runs, `evaluations/d23-12/measures-set.json`): 12 of 12 published; every
  first dispositions answer was complete, so the correction never fired; target "not enough
  evidence". No hello-world spec lost the UTC requirement (0 of 9 on D2.3 trees).

## Q4 D4.1. `uncovered_member` correction names the covering kinds

**Decided, implemented and kept 30 October 2026.** The correction names the covering kinds
from the compiled coverage rule, never hard-coded (`model_schema_diagnostic.zig`,
`model_protocol_retry.zig`); `required_preserve` unchanged. Evidence
`evaluations/e2e/d41-measures-set.json` (6 runs; correction never fired). Its live firings
since are in FIX06 Q14. The extension decided 3 November 2026 is open in FIX06 Q4.

## Q13 D13.1. Post-generation reviews removed

**Implemented 1 November 2026; committed in `2b3dc8b`.** Decided 1 November 2026 (user: "apply
best recommendations"); the decision and what it removed are ADR 0023's removal amendment
(0023:25-42). Effects: FIX06 §3's robustness track (runaways, re-sends, budget) and H4 (sends
and tokens).

## Q7 D7.4. No engine code span where the text already delimits an exact value

**Implemented 1 November 2026 on `2b3dc8b`; committed in `340261e`.** Decided 1 November 2026,
then "implement Q7 D7.4." (ADR 0036's decision authority); the user's ruling that D7.4 is not
a punctuation rule stays in FIX06 Q7. `delimitedByText` (`specification_projection.zig`)
gives an exact copy no code span when only literal text touches it and that text is directly
one balanced pair from the closed wrapper table (`exact_value_boundary.zig`), unless the copy
ends in terminal punctuation; passive values keep their span (ADR 0036 Decision 6;
23-rendering.md §23.1). No request carries the projection's spans (freeze `2b3dc8b-d74`
against `2b3dc8b`: `diff -r` empty). Every artefact-A occurrence so far is on a
development-case value that ends in punctuation, so none of them changes (FIX06 Q7). No
scripted scenario quotes an exact copy, so the freeze doesn't reach the new path.

## Q7 D7.2. ADR 0045 withdrawn

**Implemented 3 November 2026; docs only.** Decided 3 November 2026 (user: "apply
recommendations"; ADR 0036's decision authority records it): ADR 0036 Decision 6 stays, and
ADR 0045, accepted but on hold and never implemented, is withdrawn; its file is deleted (git
`388438e` keeps it). Plain values in entity meanings (rendering artefact B, FIX06 Q7) stay
plain.

## Q13. Inline source lines

**Implemented 1 November 2026 on `340261e`; committed in `6e543e6` with the D12.1 + D16.2 change
set (Q13 changes no request). Every publication since D12.1 shows the lines.**
- **User decisions, 1 November 2026:**
  - "the claims associate with the AC, FR and EN should be placed after each AC, FR and EN";
  - format: file and lines only, one line per item with the source file and merged line
    ranges, computed from the item's claims and their citations; several files join with "; ";
  - then "implement Q13,".
- **Change:** each AC, FR and EN record in `spec.md` shows those lines, for example
  `` - Source: `references/hello-world/stories.md` lines 5–7 ``; a single line reads
  `line N`, ranges join with ", ", and a record citing no source line shows none. The live
  projection and the reference-context snapshot share one trace (`traceRequirements`,
  `specification_projection.zig`); `source_coordinates.lines` turns a citation span into its
  lines, and `specification_markdown.zig` renders and parses the line (23-rendering.md §23.1,
  F0100 §5.6). An AC or FR line follows a blank line, because a two-space line directly under
  a field continues that field. No state or report version changes. The lines reduce no
  scored defect class; they make each record's links visible to the human reviewer (H1).
- **Proof:** codec, span-owner, projection and integration tests; freeze `340261e-q13`
  against `2b3dc8b` shows `diff -r` empty (129 scenarios, 1,702 calls).

## Q12 D12.1. Records requests receive no unpublished drafts

**Implemented 1 November 2026 on `340261e`; committed in `6e543e6`; approved 1 November 2026
as the first model-input change. Not kept alone (decided 2 November 2026, user: "the above
recommendations are approved"); its code is part of the D12.1 + Q16 change set, kept with
D16.2 on 2 November 2026 (Q16).**
- **Change:** only the entities unit receives an earlier draft (the brief); records authoring
  and repair packets receive neither the brief nor the entity decision
  (`specification_session.zig`); `records.prompt.md:1` no longer names the brief, and
  `generation.context.json`'s `sources` guidance drops "and prior drafts". No state, report or
  schema change.
- **Measurement, D12.1 alone** (`evaluations/d121-measures-set.json`, six runs): unsupported
  addition 10 → 11 and restatement 7 → 12 rose, as the loan-renewal records call wrote
  assumption, non-goal, prohibition and edge-case records that invented content or restated
  FRs (3 of 3 runs).
- **Copy route removed:** FR equal to an unpublished draft fell from 9 of 18 publications of
  31 October to 0 of 15 across the D12.1, D16.1 and D16.2 sets (p = 0.004).

## Q12 D12.2. Generated fields take obligation strength from one owner

**Implemented 2 November 2026 on the `b38628c` tree; committed in `388438e`; approved 1
November 2026. Kept 3 November 2026 (user: "apply recommendations") under AGENTS.md's one owner
per instruction, although its Keep if wasn't met as written; its watch items closed with Q12
(Q12 D12.3 below).**
- **Change:** `generation.context.json`'s `business_value`, bound to every generation and
  specification-unit repair request, owns "preserve source-backed conditions, obligations and
  obligation strength."; the story and functional-requirement purposes and
  `records.prompt.md` drop their copies. No code, state, report or schema change.
- **Set** (approved 2 November 2026, user: "approved"; ten runs `2026-11-02T09-15-27Z` to
  `09-33-46Z`, five per case after one approved extension; FIX06 §1's previous reference):
  story weakening 8 of 15 → 1 of 9 (p = 0.093; 9 events, at the evidence floor); against the
  D16.2 set, unsupported addition 6 → 19 and restatement 3 → 5, neither significant (pooled
  p = 0.16), and FR weakening 0 → 0. The loan-renewal story still fell in three modes: "may
  renew" (`09-15-30Z`), the five source lines joined with no separator (`09-15-27Z-d2ee…`,
  `09-15-32Z`) and invented steps (`09-33-44Z`, `09-33-46Z`).

## Q16 D16.1 and D16.2. Requirements own their claims (with D12.1)

**D16.1 implemented and measured 2 November 2026 on `340261e`; committed with D16.2 in
`6e543e6`. Its set failed the publication guard; D16.2 amended it the same day instead of
reverting it (FIX06 §2 rule 1's recorded exception), and the change set is kept (decided 2
November 2026, user: "keep D12.1 + D16.2") without the recommended three-run extension.** ADR
0038 (Decisions 2, 3 and 5, with the user's D16.1 and D16.2 decisions) and ADR 0035 record the
rule.
- **Defect targeted:** restatement, 5 of 18 publications of 31 October (7 defects): business
  rules paraphrasing the FR or the source, AC and edge-case repeats, the story repeating the
  FR. ADR 0035's exact equality catches none of them.
- **Change:** requirements (FR) own their claims and are never deleted or rejected by the
  rule; admission rejects a business rule, outcome, assumption, non-goal or prohibition that
  names both taken and untaken claims as `shared_member`, with a correction listing every
  taken naming; the session deletes a wholly taken one natively (`repeated_statement`),
  keeping a record that holds the batch's only copy of an exact value; FR, BR, UO and PB need
  a scenario; ADR 0035's in-batch record-versus-record deletion is deleted. Versions:
  `model-request-debug/v16`, `spec-e2e-report/v14`, `baseline-acquisition/v11`.
- **D16.1 set** (`evaluations/q16-measures-set.json`): loan-renewal published 1 of 3 against
  D2.3's 6 of 6 (p = 0.083); both failures exhausted the records retry limit on
  `shared_member`.
- **D16.2 set** (six runs `2026-11-02T02-27-46Z` to `02-29-15Z`,
  `evaluations/d162-measures-set.json`): its **Keep if** was not met: restatement 4 → 3 didn't
  fall (7 events, "not enough evidence"), and unsupported addition 6 → 6 (0.5 → 1.2 per
  publication) was undecided after three runs; FR equal to an unpublished draft 0 of 5.
  `02-29-06Z` exhausted reconciliation dispositions on `missing_member`, from a request
  byte-identical across D2.3, D16.1 and D16.2. No first records attempt in this set or the
  D12.2 set had a statement record, so the native delete first fired on 3 November
  (`2026-11-03T04-12-37Z`, seven deletes; since then `2026-11-06T22-45-22Z` and `22-45-46Z`,
  two each; the reports list one, one and none, FIX06 T8); the records prompt's "at most one" sentence (`records.prompt.md:9-11`), added
  with D16.1, coincides with the drop.

## Q19 D19.2. The engine composes the story (ADR 0047)

**Implemented 3 November 2026; committed in `f6ef0f6`. Kept 7 November 2026 with D12.3 (FIX06
§2 rule 3's recorded exception) on the 12 adjudicated runs since ADR 0047: no story defect
against 7 in the D12.2 reference's 9 publications; the other results are in FIX06 §1.**
- **Change:** ADR 0047. `compose-specification-story` (`src/domain/specification_story.zig`)
  quotes the catalogue's business claims in source order, the quotes joined into one paragraph
  (Decision 1); no story model call. A story with nothing to quote or failing unit validation
  blocks with `no_story_requirements` or `story_not_admissible`. The story prompt, the generation schema's story variant, the
  `authoring-guidance` corpus and the old authoring-associations `scorecard.json` are deleted
  (user: "YES"). `zig build verify` passed and the contract review found no remaining
  violation (3 November 2026).
- **Runs:** three per case on `28213a7` modified (`2026-11-03T04-1*`, skill `af394020…`) and
  three per case with D12.3 on `f6ef0f6` modified (`2026-11-06T22-4*`, report v15, skill
  `0b552067…`): no story defect in any, the story byte-identical per case. The D12.3 runs made
  9–10 first attempts each with no correction or re-send, and four native
  `repeated_statement` deletes (`22-45-22Z` two, one reported; `22-45-46Z` two, none
  reported; FIX06 T8).
- **Motivation** (moved from FIX06 Q19): before ADR 0047, 26 of 30 weakenings since 29 October
  were in the story; every loan-renewal story fell in one of three modes ("A borrower may
  renew…", the source lines joined with no separator, invented login and selection steps), all
  three in the D12.2 set; hello-world's story added timing, a display surface or an order in 4
  of 8 publications since D12.1.

## Q12 D12.3. The story leaves pre-generation source review

**Implemented 7 November 2026** (user: "apply recommendations", then "yes, advance both"; ADR
0047 Decision 5, amended that day). Kept with ADR 0047 (FIX06 §2 rule 3). Not yet exercised
live: none of the 12 runs since ADR 0047 reached source review.
- **Defect:** `2026-11-02T09-15-31Z` ended `workflow_invalid` after 34 calls: the second
  readiness pass filed the story purpose itself as a `candidate_omission`, which loss
  comparison couldn't localize. The engine composes the story, so a model review of it can
  only raise false findings.
- **Change:** `specification_authority.projectRecords` no longer seeds the story; the story's
  required-authority policy, slot and clarification question and its packet-guidance purpose
  are deleted; `packet-guidance/v3` and required-authority contract 2 (old versions reject).
  The `captured-story` case leaves the read source-loss corpus.
- **Q12 closed 7 November 2026.** Its last check, the story's invented-steps mode, didn't recur
  in the 12 runs since ADR 0047. Q12's leftover restatements stay: the one-owner hygiene
  change that removed them was reverted (FIX06 §3). Not recommended: a typed obligation-strength field (07-domain-representations.md:158
  forbids a duplicate modality field; making it matter needs a word check or engine-rendered
  modal text).

## Q8 D8.3. One piece of evidence is one claim

**Decided and implemented 7 November 2026** (user: "i accept recommendation", then "implement
D8.3", accepting the preflight's resolutions a–f; then "fix the issues", making an insertion
that adds no claim an unchanged merge).
- **Defect:** `2026-11-07T06-11-33Z-6897…`'s extraction returned five identical
  `{"category":"business","citations":[5,6,7,8,9]}` claims; the list-item split made 25, the
  story repeated every sentence five times (organization 2), and reconciliation made five
  summary calls and two `missing_member` corrections (about 26k tokens).
- **Change:** the rule is ADR 0036 Decisions 3 and 4 (16-reference-ingestion.md §16.3; the
  13-03 action text). Owner: `reference_extraction_text.appendDistinct`, used by extraction
  text validation and `reference_extraction_repair.Omission.merge`; the merge reports
  `changed = false` when its insertion adds no claim.
- **Tests:** accepted (identical proposals; duplicates per item after the split; a
  repair-inserted duplicate as an unchanged merge; a list-spanning insertion adding only its
  new item, with the repair's origin; duplicate claims keeping one exact-value duty) and
  rejected (same lines in two categories; different and partly overlapping lines; a repair
  insertion in another category). The generation fixture that built several claims by
  copying one now gives each claim its own line after a blank line, and a technical claim
  the first claim's lines.
- **Proof:** `zig build test`, `lint`, `test-architecture` and `test-integration` pass; the
  request projection is byte-identical to `entity-meaning-before`, since no offline scenario
  duplicates a claim.

## H1. Adjudication and `spec-e2e-report/v15`

- **Adjudicated 3 November 2026** (user-triggered `/evaluate-e2e`, skill `af394020…ec790`): the
  D12.2 set's nine publications and the six ADR 0047 runs, each scored, recorded and applied
  (`evaluations/e2e/<run>/`, `evaluations/adjudications/`; 15 applied decisions: 8 passed, 6
  `critical_failed`, 1 `admission_evidence_invalid`, FIX06 §7 H1). The unpublished
  `09-15-31Z` has a failure trace only.
- **v15, implemented 7 November 2026** (user: "implement items 1 and 2"): `spec-e2e-report/v15`
  and `baseline-acquisition/v12` carry ADR 0047's source-catalogue reasons and `issue`, the
  publication reason renamed `adjudication_required`, and an admission audit that accepts no
  story subject; design/harness/e2e.md's format history, deleted 7 November 2026, is in git
  (`8aa7fb5`). Retained v12–v14 runs stay readable only by the build that made them. The
  supplied-spec evaluator's decision (`evaluation-report/v8`) and the baseline's
  useful-completion state (`baseline-score/v4`) keep their own `human_adjudication_required`.
  `zig build verify` passed: 169 steps, 1,976 tests.

## T7. One evaluator version per comparison

**Closed 7 November 2026:** skills `af394020…` and `0b552067…` count as one evaluator (user:
"approved"; the edit between them changed no scoring rule), so the reference needs no re-score.
- **Skill edit, 3 November 2026** (user: "yes start item 2"): `e2e-assistant-evaluation/v4`
  records `skill_sha256` and gives each defect a `basis` (`link` or `content`), and the
  `restatement` class excludes a faithful one-paragraph story (D19.1), with the user's rulings
  (FIX06 §7 H1). Skill `5690d0f0…a8865`.
- **Readings made rules, 3 November 2026** (user: "YES"; now in SKILL.md §2): a link defect
  costs nothing beyond its content defect; a repeat that gives a requirement's value states it,
  one that gives none is a summary; a weaker restatement in a checkable outcome also costs
  `clarity-testability`; several minor additions stay minor; repeating the source's own
  wording, or an outcome without its verb, isn't weakening. The re-score they came from was
  superseded by H1's adjudication under `af394020…`.
- **Skill edit, 7 November 2026** (user: "update the out of date items"): the measures note no
  longer names a report version (SKILL.md:269-270); no scoring rule changed. Skill
  `0b552067…0ca43`.
- **Skill edit, 7 November 2026** (user: "yes"): citations of retired FIX06 IDs now point to
  ADR 0047 and Z_FIX06 T7, and the T5(b) citation is dropped; then (user: "you can start
  /evaluate-e2e if I give approval") the agent may start it on the user's approval for named
  runs. No scoring rule changed. Skill `1d66d882…fa3c3`.

## T5. Brittleness counts

**Implemented and taken 1 November 2026, on `30e0d2f` (the D10.2 tree), before D13.1;
committed in `93476e7`.** `zig build code-heuristics -- --freeze <dir>` writes them to the
`brittleness` member of `code-heuristics/v2` (`build/code_heuristics/brittleness.zig`).
- **Definitions** (approved 1 November 2026; exact matches only):
  - A is every `.md` and JSON string value under `design/workflows/`, whitespace-collapsed.
  - M is production literals outside tests, of 3+ whitespace-separated runs, whose decoded
    bytes occur in a freeze's `guidance` content parts, `protocol_prompt` or `schema` (the
    schema's decoded strings included), and whose collapsed bytes A lacks.
  - Literal roles are syntactic: a direct argument of `eql`, `startsWith` or `endsWith`; a
    direct argument of `indexOf`, `lastIndexOf` or `indexOfPos`, which is an absence
    assertion when compared `== null`; or the `.bytes` value of a `DefinitionId`
    initializer. An initializer is a typed declaration, a `return` from a function
    returning `DefinitionId`, `DefinitionId.parse` or `DefinitionId{…}`, or an anonymous
    `.{ .bytes = … }` argument at a position where a function of that name takes a
    `DefinitionId`. A value chosen by a `switch` inside it counts as its value.
- **User decisions, 1 November 2026:**
  - The freeze is read strictly by `request_projection.Projection` and `Manifest`, without
    a version check, because the freeze has none.
  - M reads only `guidance` parts, as decoded values; `src/test_fixtures/` isn't
    production.
  - M takes T5.1's 3-run minimum. Without it, about 80 JSON-schema keywords count.
  - T5.1 counts an absence assertion only when A or M holds its literal.
  - T5.4 is counted by hand, because the compiled Spec graph needs the composition root's
    native assembly.
- **Baseline** (freeze `q10b-2026-10-31`):

| Count | Value |
| --- | --- |
| T5.1 | 25 |
| T5.2 | 22 in 8 files, among them `specification_session.zig:253-256` (4), `reference_reconciliation_repair.zig:747-750` (4) and `specification_support.zig` (6); 118 test sites |
| T5.3 | 7 maximal repeats at 16 sites; 3 are variants of "conditions, negation and obligation strength." |
| T5.4 | 6, by hand: `spec.workflow.yaml:376`, `:413`, `:609`, `:814`, `:899`, `:913`, each binding `repair-prompt`; `:721` takes its review's prompt |
| T5.5 | 0 |
| T5.6 | 15 in 4 files: `model_schema_diagnostic.zig` 11, `strict_json.zig` 2, `model_controls.zig` 1, `model_protocol_retry.zig` 1 |

- **Limits:** a comparison through a helper isn't a direct operand
  (`reference_reconciliation_stage.zig:87` compares `definition(stage)`). A name routed
  through a local before `.{ .bytes = name }` isn't counted
  (`reference_reconciliation_repair.zig:324-327`, `specification_repair.zig:267-269`).
  Argument positions match functions by name only. Short absence
  literals match A by substring (`"id"`, `"$defs"`). The "native code" diagnostic texts
  reach requests only in `user` parts (2,832 in the freeze), so they aren't in M.

## T6. Structural counts in the measures

**Implemented 3 November 2026; committed in `f6ef0f6`.** Decided as FIX06 §2 rule 4 (H6.1) and
widened the same day (user: "Yes, count them") to extraction outcomes, claim categories and
fragments objects, so every scheduled screen has a count.
- **Change:** `measures.structure` (`test/harness/e2e/measures.zig`) reads each response
  through the production envelope parser and counts records by kind, the entities
  `disposition` and entity count, a `claims` response's claims by `category` or
  `no_feature_claim`, and every `{"fragments":[...]}` object, with those inserting no
  reference apart; wire names come from their owning types, and an unknown kind or category
  counts apart. Run measures keep every call (`e2e-measures/v2`), so a request whose last
  attempt is unreadable is never measured by an earlier one; the set summary
  (`e2e-measures-set/v2`) pools each request's last attempt; `e2e-call` trials record the same
  structure (`call-diagnostic-report/v3`). No engine or request change.
- **Baseline measured 3 November 2026** (offline, `evaluations/t6-baseline/`, one
  `<set>-set.json` per set; v12/v13 reports are `unavailable`, so the D12.1 and D16.1 counts
  come from call evidence only). Runs with the record kind or decision, loan-renewal (LR) and
  hello-world (HW):

  | Set | LR edge case | LR statement families (BR, AS, NG, PB) | LR outcome (UVO) | HW entities `required` | HW extraction `no_feature_claim` |
  | --- | --- | --- | --- | --- | --- |
  | D12.1 | 3 / 3 | 3 / 3 each | 1 / 3 | 3 / 3 | 0 / 3 |
  | D16.1 | 2 / 3 | 0 / 3 | 2 / 3 | 3 / 3 | 0 / 3 |
  | D16.2 | 1 / 3 | 0 / 3 | 0 / 3 | 1 / 2 | 1 / 3 |
  | D12.2 | 4 / 5 | 0 / 5 | 0 / 5 | 2 / 4 | 1 / 5 |

  Loan-renewal entities are `required` in every run of every set. Literal-only fragments:
  D12.1 3 of 30 (HW) and 3 of 30 (LR) responses; D16.1 1 of 30 and 2 of 34; D16.2 0 of 50 and
  2 of 30; D12.2 2 of 74 and 3 of 50.

## E6. Producerless rejection reported as a harness error

**Implemented 31 October 2026; committed in `dac4c4c`.** Three Q4 hello-world runs ended
`harness_error` `MissingProviderEvidence`: a source-omission repair turned a
`no_feature_claim` chunk into a claim, and the missing `preserve` classification had by rule
no origin, which the shared `attribution()` mapped to `missing_response`. Fix: the validator
names the rule (`producerless`, missing entries only) and `attribution()` gives `candidate`
(contract 27); a lost origin on a duplicate, unknown or forbidden entry still rejects.
Request projection byte-identical. Open parts stay in FIX06 E6.
