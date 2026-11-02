# Z_FIX06 — Implemented FIX06 items

Implemented FIX06 items, moved here on 31 October 2026 by the user's instruction. Each
item's open parts and keep decision stay in [FIX06](FIX06.md) under the same ID. Earlier
completed FIX06 work (Q1, Q2, Q3, Q4's first attempt in full, Q6, D7.1, D11.1/.2/.4/.5,
DE6, T1, T5's measures) is `fixes/Z_FIX06.md` at git `194e29a`; Q10b D10.2, reverted in full
with D13.1 (ADR 0023:25-28), is here at git `388438e`. This record grants no approval and
establishes no live acceptance.

## Q2b D2.3. Dispositions complete at response admission (ADR 0046)

**Implemented 31 October 2026; committed in `194e29a`. Kept 1 November 2026 (user: "apply best
recommendations") on the measurement below.**

- **Defect targeted:** lost source requirement. Hello-world's UTC claim was lost when the
  dispositions insert repair answered `duplicate` of claim 1 (27 October 09:40, 29 October
  `20-47-23Z-6e8e…`): the only requirement losses in 20 hello-world publications 26–31
  October.
- **Mechanism:** a dispositions assignment binds its semantic claim IDs as `exact_members`
  with a native count (`IntegerChoice.member_count = .native`), so the request the model
  receives is unchanged. Admission rejects an omitted claim as `missing_member` (the
  correction names it as `member`) and a repeat as `duplicate_member`, under the dispositions
  request's `retry-limit` (2); exhaustion fails the run. The source-omission conflict-group
  repair shares the binding (`retry-limit` 1). Deleted: the per-claim insert, the
  redundant-record deletion, the competing block and the foreign replacement. Replay
  reapplies member sets natively, so `model-request-debug/v13` captures still decode.
- **Request projection:** `d23-2026-10-31` against the D4.1 freeze: dispositions requests
  differ only in the recorded `members`; model-visible differences only in rescripted
  scenarios.
- **Measurement (12 runs on `dac4c4c` plus the working tree, whose captured build inputs
  equal commit `194e29a`; `evaluations/d23-12/measures-set.json`):** 12 of 12 published;
  every first dispositions answer was complete, so the correction never fired and no
  reconciliation repair ran; target "not enough evidence" (0 of 6 hello-world omissions
  against 4 of 18 earlier, within chance). Sends hello-world 23–25, loan-renewal 25–29;
  tokens 60,761–84,067 and 85,943–123,519.
- **Output scoring (advisory, `evaluations/e2e/<run>/evaluation.json`):** hello-world mean
  89.9 (85.7–100), loan-renewal 86.3 (82.1–92.9), no threshold failure. No hello-world spec
  lost the UTC requirement (0 of 9 on D2.3 trees, the Q10b runs included).

## Q4 D4.1. `uncovered_member` correction names the covering kinds

**Decided, implemented and kept 30 October 2026.** The correction names the covering kinds
from the compiled coverage rule, never hard-coded (`model_schema_diagnostic.zig:34`,
`model_protocol_retry.zig:59-71`); `required_preserve` unchanged. Evidence
`evaluations/e2e/d41-measures-set.json` (6 runs; correction never fired).

**First live firings (31 October 2026 scoring):** loan-renewal `07-35-27Z-0669…` and
`07-37-18Z-61b3…`. Both times the corrected records answer only added the refusal and
limit claim IDs to the success-only AC-001, which passed admission with a false link
(ADR 0038:76-77, "checks links, not meaning"); both published specs still have no refusal
scenario (`lost_source_requirement`).

**Q4's first attempt** (removing engine vocabulary and schema-stated rules) was built,
measured and reverted on 31 October 2026: hello-world's first extraction returned
`no_feature_claim` in 5 of 6 runs after the second `citations` sentence
(`extraction.context.json:14`) was removed (`evaluations/q4/measures-set.json`). The retry
stays open in FIX06.

## Q13 D13.1. Post-generation reviews removed

**Implemented 1 November 2026; committed in `2b3dc8b`.** Decided 1 November 2026 (user: "apply
best recommendations"); the decision and what it removed are ADR 0023's removal amendment
(0023:25-41). Effects: FIX06 §1 (runaways, re-sends) and H4 (sends and tokens).

## Q7 D7.4. No engine code span where the text already delimits an exact value

**Implemented 1 November 2026 on `2b3dc8b`; committed in `340261e`.** The user's ruling that
D7.4 is not a punctuation rule stays in FIX06 Q7. Targets the doubled delimiter (rendering
artefact A) on values that end without punctuation. Every artefact-A occurrence so far is on a
development-case value that ends in punctuation, so none of them changes (FIX06 Q7).
- **Change:** `delimitedByText` (`specification_projection.zig`) gives an exact copy no code
  span when only literal text touches it and that text is directly one balanced pair from the
  closed wrapper table (`Utf8Prose.directlyWrapped`, `exact_value_boundary.zig`, on
  `evaluate`'s accepted evidence), unless the copy ends in terminal punctuation
  (`endsWithTerminal`). Passive values keep their span. No model bytes, canonical state,
  lineage, report or state version change. Rule: ADR 0036 Decision 6; 23-rendering.md §23.1.
- **Offline proof:** no request carries the projection's spans. By the code: `brief` and
  `entities` drop them, the clarification question uses only its bytes, and the projection's
  `modelValue` and `modelRecord` have no production caller. Freeze `2b3dc8b-d74` against
  `2b3dc8b` shows `diff -r` empty (129 scenarios, 1,702 calls), but no scripted scenario
  quotes an exact copy, so the freeze doesn't reach the new path. Tests: the boundary pairs
  (`exact_value_boundary.zig`); the projection with both development-case values (span
  kept) and an unrelated value, with and without a direct pair, through rendering and the
  parse round trip; touching a passive value, or an exact copy whose bytes begin with the
  closer (fails without the guard); and a backtick run Decision 6 keeps
  (`specification_generation_test.zig`). FIX06's re-render of retained `spec.md` files
  couldn't run: every run directory was removed from `zig-out/e2e-spec/` on 1 November 2026.
- **Not changed:** the design.md §32 index row for ADR 0036 doesn't name this rule (a
  design edit).

## Q7 D7.2. ADR 0045 withdrawn

**Implemented 3 November 2026; docs only.** Decided 3 November 2026 (user: "apply
recommendations"): ADR 0036 Decision 6 stays, and ADR 0045, accepted but on hold and never
implemented, is withdrawn. Its file is deleted (git `388438e` keeps it), with its "Amended by"
entries in ADRs 0020 and 0036 and its design.md §32 row; ADR 0036's decision authority records
the decision. Plain values in entity meanings (rendering artefact B, FIX06 Q7) stay plain.

## Q13. Inline source lines

**Implemented 1 November 2026 on `340261e`; committed in `6e543e6` with the D12.1 + D16.2 change
set (Q13 changes no request). Every publication since D12.1 shows the lines.**
- **User decisions, 1 November 2026:**
  - "the claims associate with the AC, FR and EN should be placed after each AC, FR and EN";
  - format: file and lines only, one line per item with the source file and merged line
    ranges, computed from the item's claims and their citations; several files join with "; ";
  - then "implement Q13,".

Each AC, FR and EN record in `spec.md` now shows those lines, for example
`` - Source: `references/hello-world/stories.md` lines 5–7 ``. The inline lines reduce no
scored defect class; they make each record's links visible to the human reviewer (H1).
- **Change:** `traceRequirements` (`specification_projection.zig`) now takes the inputs and
  reference records, so the live projection and the snapshot (`traceSnapshot`, used by
  reference-context) share one trace. `project` attaches typed `SourceLines`
  (`specification.zig`, validated as ascending, merged, one entry per file, AC/FR/EN only) and
  takes the reference directory; `project-specification-document` now requires
  `reference_directory`. `source_coordinates.lines` turns a citation span into its lines and
  `mergeLines` joins them. `specification_markdown.zig` renders and parses the line.
  `reference_ingestion.displayPath` is the one path join both views use. The baseline
  candidate JSON is `baseline-native-specification-candidate/v2` (records gain `sources`; it
  has no reader). No state or report version changes.
- **Choices forced by the code:**
  - An AC or FR line follows a blank line, because a two-space line directly under a field
    continues that field (F0100 §5.6).
  - The snapshot can't be built before `project-document`: the pending branch builds it too,
    and the data-flow check rejects producing a key twice. The live records give the same
    trace.
  - A single line reads `line N`; ranges join with ", ".
  - Pending views and reference-context's own section are unchanged.
  - A record citing no source line shows none.
- **Contracts:** 23-rendering.md §23 (replaces "Reference citations are not rendered into the
  business-only file" and "grammar is unchanged"), F0100 §5.6 and its parsing sentence,
  17-specify.md's artifact boundary, design.md §31.21.
- **Offline proof:**
  - **Codec** (`specification_contract_test.zig`): AC, FR (beside a multiline exact
    continuation) and EN lines, several files and a path containing a backtick, all round
    trip. Thirteen rejected spellings, a source line on a business rule, and two continuation
    placements that don't round-trip.
  - **Span owner** (`source_coordinates.zig`): whole lines, line runs, a token ending
    mid-line, a last line without its ending, and two rejected spans.
  - **Projection** (`specification_generation_test.zig`):
    - `line 4`, `lines 1–2`, and a sorted, merged `lines 1–2, 4`;
    - overlapping, nested, touching, duplicate and separated ranges;
    - the live lines equal the persisted snapshot's lines exactly, the exact token's mid-line
      citation included;
    - an occurrence whose source isn't in the corpus rejects.

    Two source files are covered at the codec, not the projection; the fixture reads one file.
  - **Integration** (`workflow_tests.zig`): the published `spec.md` shows source lines for
    every AC and FR, under the reference directory.
  - **Baseline harness:** the candidate document carries them.
  - **Requests:** freeze `340261e-q13` against `2b3dc8b` shows `diff -r` empty (129
    scenarios, 1,702 calls); no commit since `2b3dc8b` changes a request.
  - FIX06's proof against the D13.1 live states couldn't run: those run directories were
    removed.

## Q12 D12.1. Records requests receive no unpublished drafts

**Implemented 1 November 2026 on `340261e`; committed in `6e543e6`. Measured 1 November 2026:
rule 6 recommends not kept (guards rise); kept with D16.2 on 2 November 2026 (Q16).**
Approved 1 November 2026 as the first model-input change.
- **Change:**
  - `specification_session.zig`: only the entities unit receives an earlier draft (the brief).
    Records authoring and repair packets (repair goes through `packetForOptions`) receive
    neither the brief nor the entity decision.
  - The session-order check stays: a records packet still needs an accepted entities unit.
  - `EntityDecision` and `entities()` are deleted from `specification_projection.zig`.
  - `records.prompt.md:1` no longer names the brief, and `generation.context.json`'s `sources`
    guidance drops "and prior drafts".
  - 17-specify.md's draft rule is amended.
  - No state, report or schema change.
- **Offline proof:**
  - Freeze `340261e-d121` against `340261e-q13`: the same 1,702 calls in the same order. 520
    requests differ, and every difference is expected:
    - all 520 generation requests carry the changed `sources` sentence;
    - the 169 records requests also lose `brief` and `entities` and carry the new prompt line;
    - none is unexplained.
  - Tests: only the entities packet carries the brief, resolved through exact and passive
    values. Records authoring and task packets carry neither draft and are byte-identical
    across both entity decisions. In assembled repair packets for every record family, only
    an entity repair carries the brief and none carries the entity decision. A records packet
    without an accepted entities unit still rejects.
- **Measurement, D12.1 alone** (set 1 November 2026, `evaluations/d121-measures-set.json`; six
  runs on source `732665ccc30f…`): unsupported addition 10 → 11 and restatement 7 → 12 rose,
  as the loan-renewal records call wrote assumption, non-goal, prohibition and edge-case
  records that invented content or restated FRs (3 of 3 runs). Decided 2 November 2026 (user:
  "the above recommendations are approved"): not kept alone; its code is part of the D12.1 +
  Q16 change set, kept with D16.2 (Q16).
- **Copy route removed:** the records request had received the brief and the entity decision
  with its basis. FR equal to an unpublished draft fell from 9 of 18 reference publications to
  0 of 15 across the D12.1, D16.1 and D16.2 sets (p = 0.004).

## Q12 D12.2. Generated fields take obligation strength from one owner

**Implemented 2 November 2026 on the `b38628c` tree; committed in `388438e`; approved 1
November 2026. Kept 3 November 2026 (user: "apply recommendations") under AGENTS.md's one owner
per instruction, although its Keep if wasn't met as written; its watch items are in FIX06
Q12.**
- **Change:**
  - `generation.context.json` `business_value`, bound to every generation and
    specification-unit repair request, ends "preserve source-backed conditions, obligations
    and obligation strength."
  - `packet-guidance.json`: the story purpose drops "Preserve conditions and obligations;" and
    the functional-requirement purpose drops "and obligation strength".
  - `records.prompt.md:6-7` keeps "Preserve each statement's role." and drops "and obligation
    strength".
  - Kept: `generation.prompt.md:2` (optional in D12.2; kept so the set changes only the story
    and FR owners), `packet-guidance.json:27` (`expected_outcome`, outside D12.2), `:61`,
    `:65`, and the records prompt's "at most one" sentence (ADR 0038:116-117).
  - No code, state, report or schema change; no contract quotes the moved texts.
  - The purposes also reach, through `required_authority_description.task`, the
    source-omission repairs (`source_omission_comparison.zig:55-67`;
    `spec.workflow.yaml:821-851`, which bind no generation context) and a missing or stale FR
    gap's clarification question (`required_authority_clarifications.zig:60-64`; form identity
    ignores wording, `:21`). No scripted scenario reaches either with a story or FR subject,
    so the freeze doesn't show them.
- **Offline proof:**
  - Freeze `b38628c-d122` against `b38628c`: the same 1,714 calls in 130 scenarios. 569
    requests differ, each explained by the four texts, none unexplained:
    - 525 generation (499) and specification-unit repair (26) requests carry the changed
      context sentence; 105 story requests also carry the story purpose, and 171 records
      requests the FR purpose and records prompt;
    - 32 pre-generation source-review and 12 source-loss comparison requests carry the
      changed story or FR purpose as a subject description (`required_authority_description.task`),
      without the context.
  - T5 on the change equals HEAD's (FIX06 §6 T5): no new repeated instruction.
  - The driver already asserts the context in every generation and specification-unit repair
    request (`spec_generation_driver.zig:734-741`, `:774`); no phrase test is added (T2).
- **Why:** the story request (call 8) receives the claims verbatim ("must be able to renew") and
  no drafts. Before D12.2 the FR purpose named obligation strength (`packet-guidance.json:15`)
  and FRs kept "must"; the story and description purposes (`:7`, `:5`) didn't. **Keep if** the
  story's weakening falls, FR weakening doesn't rise (FR's wording owner moves) and unsupported
  addition and restatement don't rise.
- **Set** (approved 2 November 2026, user: "approved"; recorded before it ran): target, story
  weakening of an obligation, events per publication, direction down, pooled over both cases;
  guards, FR weakening, unsupported addition, restatement, lost source requirement, a critical
  criterion below its minimum, harmful repair, publication rate per case; three runs per case,
  extendable by two or three with approval to eight. Baseline (same approval): the target
  compares with the 15 publications since D12.1 (hello-world 2 of 8, loan-renewal 6 of 7), whose
  story requests are byte-identical across the D12.1, D16.1 and D16.2 freezes; the guards
  compare with the D16.2 set.
- **Set result** (2 November 2026; ten runs `2026-11-02T09-15-27Z` to `09-33-46Z`, five per case
  after one approved extension, on source `bacfcd9ae368…`, `modified` true; measures in
  `evaluations/e2e/<run>/measures.json`, the first six summarised in
  `evaluations/d122-measures-set.json`):
  - publication: hello-world 4 of 5, loan-renewal 5 of 5. `09-15-31Z` ended `workflow_invalid`:
    extraction returned `no_feature_claim` (an unchanged request), then the pre-generation story
    review returned a false `candidate_omission` from a request differing from `02-28-14Z`'s
    only by D12.2's story purpose, and `repair-source` found no upstream producer. Plausibly
    D12.2, not established (one pair, temperature 0.1);
  - target, story weakening: 8 of 15 → 1 of 9 (hello-world 2/8 → 0/4, loan-renewal 6/7 → 1/5),
    p = 0.093; 9 events, at the evidence floor. Three hello-world stories are byte-identical to
    pre-D12.2 stories;
  - guards against the D16.2 set (5 publications → 9): unsupported addition 6 → 19 (1.2 → 2.1
    per publication, p = 0.16; loan-renewal 4 → 16, p = 0.08 alone); restatement 3 → 5; FR
    weakening 0 → 0; lost source requirement 0 → 0; critical criterion below minimum 1 → 3 runs
    (loan-renewal source-grounding, p = 0.55); harmful repair 0 → 0;
  - loan-renewal unsupported additions by field, D16.2 → D12.2: story 0 → 4, edge case 2 → 6, AC
    2 → 4, entity 0 → 2. Edge cases (4 of 5 publications against 1 of 3) explain at most 4 of
    the 12 added events, and the story's new invented-steps mode 4;
  - loan-renewal story modes: "may renew" (`09-15-30Z`), the five source lines joined with no
    separator (`09-15-27Z-d2ee…`, `09-15-32Z`) and invented steps (`09-33-44Z`, `09-33-46Z`);
  - advisory scores: hello-world 89.3, 92.9, 100, 92.9; loan-renewal 89.3, 78.6, 89.3, 78.6,
    78.6.
- **Keep if, read:** story weakening fell (9 events, "not enough evidence" under rule 6's floor);
  unsupported addition rose 6 → 19 and restatement 3 → 5, neither significant (pooled
  p = 0.16); FR weakening didn't rise.

## Q16 D16.1 and D16.2. Requirements own their claims (with D12.1)

**D16.1 implemented and measured 2 November 2026 on `340261e`; committed with D16.2 in
`6e543e6`. Its set failed the publication guard. D16.2 amends it the same day (user:
"approved", then "Yes, exempt FRs"); D16.2's set ran the same day, and the change set is kept
(decided 2 November 2026, user: "keep D12.1 + D16.2") without the recommended three-run
extension. Its set was FIX06's reference until D12.2 was kept on 3 November 2026.** D16.1
decisions: "the above
recommendations are approved"; coverage kinds per "No, behaviour kinds only"; "Yes, Q16
replaces it" (ADR 0035's in-batch deletion); "Yes, list every location".
- **Defect targeted:** restatement, 5 of 18 reference publications (7 defects): business rules
  paraphrasing the FR or the source, AC and edge-case repeats, the story repeating the FR.
  ADR 0035's exact equality catches none of them.
- **D16.1 set** (`evaluations/q16-measures-set.json`; six runs on source `6b37001bfce8…`):
  loan-renewal published 1 of 3 against D2.3's 6 of 6 (p = 0.083); both failures exhausted the
  records retry limit on `shared_member`, because the FRs named every claim and no claim ID
  could satisfy the located position. Not kept as built.
- **D16.2 decision** (an exception to FIX06 §2 rule 1): amend the change set instead of
  reverting it. Requirements are never deleted or rejected by the rule, since one prose claim
  can hold two obligations. After the contract review (user: "Yes, keep it", twice) a repeated
  statement holding the batch's only copy of an exact value is kept, and the records prompt's
  "at most one" sentence stays unchanged for the set. Evidence: in the D12.1 and D16.1 runs' first
  records attempts, 24 statements were wholly taken (9 business rules, 6 outcomes, 3
  assumptions, 3 non-goals, 3 prohibitions), all scored as restatements or inventions; none
  was partly taken and no two requirements shared a claim. Both failed D16.1 runs' rejected
  records are wholly taken outcomes, so the amended rule deletes them and the batch admits.
- **Change (as amended by D16.2):**
  - `ItemCoverage` (`model_result_schema.zig`) has `exclusive` and `owning` kinds, both
    required, distinct, offered by the items, never covering kinds and disjoint from each
    other. A rule on arrays nested in an outer array rejects.
  - A value is taken for an exclusive item when an owning item names it anywhere or an
    earlier exclusive item does. Admission (`model_payload_schema.zig`) rejects an exclusive
    item naming taken and untaken values as `shared_member` at the item, before coverage;
    one naming only taken values is admitted. Owning items are unconstrained.
  - The diagnostic carries the compiled rule and its property (`coverage`) for both
    cross-item reasons. The `shared_member` correction offers the record's shape, names the
    exclusive and owning kinds (`exclusive`) and lists every taken value's naming in partly
    taken items (`shared`). The correction owner (`model_protocol_retry.zig`) finds them
    with admission's allocation-free `nextSharedNaming`, and refuses a response whose first
    partly taken item isn't the rejected one.
  - The session (`specification_session.zig` `repeatedStatementIssue`) deletes a wholly
    taken business rule, outcome, assumption, non-goal or prohibition natively, with no
    model call (`repeated_statement`, `specification_candidate.zig`;
    `specification_repair.zig` gives its requirement and native delete). It runs after the
    cross-batch duplicate check and ADR 0035's story comparison, and keeps a record holding
    an exact copy no other record of the batch holds (`exactCopiesHeldElsewhere`, over
    `specification_provenance.recordValues`).
  - `scenario_coverage`: FR owns; BR, UO, AS, NG and PB are exclusive; FR, BR, UO and PB
    need a scenario. The roles come from an exhaustive switch (`recordRole`).
  - ADR 0035's in-batch record-versus-record deletion is deleted (`restatement`, the
    in-batch loop and their tests); the story comparison and the same-kind delete stay,
    and the story restatement's repair text names the story as the kept occurrence.
  - `records.prompt.md:9-13` states the at-most-one-record and coverage rules for assigned
    requirements. It is unchanged by D16.2, so the model sees what the D16.1 set saw.
  - Versions: `model-request-debug/v16` (the recorded rule's owning kinds),
    `spec-e2e-report/v14` (the new repair rule in reports' diagnostics) and
    `baseline-acquisition/v11`, which embeds the report.
  - The scripted records fixture puts the exact value in the FR instead of a second outcome
    record.
  - Amended: ADR 0038 (title, Decisions 2, 3 and 5), ADR 0035, ADR 0019, 12-model-boundary,
    17-specify, 21-validation, 22-repair, 24-workflow-state, 27-observability, F0100,
    e2e.md and acceptance.md, the evaluate-e2e skill's report version, the design.md §32
    rows for 0035, 0038 and 0039, and FIX06 §2 rule 1's recorded exception.
- **Offline proof:**
  - **Freezes** (each taken with the scripted Q16 scenarios left out, so numbering
    matches):
    - `340261e-q16` against `340261e-q13`: the same 1,702 calls in order, 520 differing,
      every difference explained (D12.1's sentence in all 520 generation requests; in the
      169 records requests, the drafts removed, the new prompt lines and the recorded rule;
      in 22 later records batches, one fewer present family, the fixture change).
    - `340261e-d162` against `340261e-q16`: 1,533 identical; the 169 records requests
      differ only in the recorded rule (FR moved from exclusive to owning).
  - **Replay** (offline re-implementation over the 12 retained runs' first records
    responses): both failed D16.1 batches admit with their two outcome records deleted; the
    D12.1 loan-renewal batches delete 4, 8 and 8 restating records; none is partly taken or
    uncovered.
  - **Tests:**
    - **Result-schema rule:** accepted and rejected exclusivity, owning items unconstrained
      and taking values before or after, wholly taken items admitted, replay restoring the
      rule, and invalid exclusive and owning configurations.
    - **Admission and correction:** the correction names the exclusive and owning kinds and
      lists every taken value's naming (several items, two in one item, behind a §22.6
      opening artefact, none in a wholly taken item), only for `shared_member`; a response
      whose first partly taken item differs, whose only shared item is wholly taken, or
      with none is refused (both guards mutation-checked).
    - **Replay:** the request debugger rejects a partly taken response and admits a wholly
      taken one from the record; a record without `exclusive` or `owning` doesn't decode.
    - **Records packet:** every behaviour kind needs a scenario; assumptions and non-goals
      need none; each non-requirement statement kind rejects when partly taken, by a
      requirement before or after it or an earlier statement; wholly taken ones and two
      requirements sharing a claim are admitted.
    - **Session:** a loan-renewal-shaped batch (outcomes restating requirements before and
      after them, a second requirement on one claim) has both outcomes deleted natively,
      one at a time, refuses a model value for the delete, and keeps the requirements and
      scenarios. Fixtures whose sibling statements shared a claim now name distinct claims
      (`proposalNaming`, `proposalGroup`), and two outcome records on one claim became
      requirements.
    - **Exact copies:** a repeated statement holding the batch's only copy of an exact value
      is kept (the scripted fixture's old shape: an FR without the value, an outcome with
      it); one whose value a requirement also holds is deleted; of two holders the first
      goes and the last stays (mutation-checked).
    - **Real schema:** against the restricted records generation schema, a partly taken
      record's rejection locates and outlines the record node, carries the compiled rule
      and lists the taken naming.
    - **Same-kind duplicates:** acceptance criteria, edge cases and business rules are still
      deleted as `duplicate_record`.
    - **Integration:** a scripted BR restating an FR publishes with the rule deleted and no
      correction. Every scripted records batch has one claim, so a partly taken record is
      proven only at admission.
- **D16.2 set**, recorded before it ran against the D2.3 reference: targets restatement, FR
  equal to an unpublished draft and FR weakening (event counts, direction down, pooled over
  both cases); guards lost source requirement, unsupported addition, a critical criterion
  below its minimum, harmful repair, publication rate per case, exhausted records retries and
  false links; three runs per case, extendable by two or three with approval to eight; also
  counted, `repeated_statement` deletions and `shared_member` corrections per records batch.
  **Keep if** restatement and FR-draft copies fall and FR weakening doesn't rise, with no
  guard rising under rule 6.
- **D16.2 set result** (2 November 2026, six runs `2026-11-02T02-27-46Z` to `02-29-15Z`;
  `evaluations/d162-measures-set.json`, evaluations in `evaluations/e2e/<run>/`):
  - **Rule activity:** none. No first records attempt had a business rule, outcome,
    assumption, non-goal or prohibition, so nothing was deleted or corrected. The D12.2 set
    had none either (no publication carries one and no report names `repeated_statement` or
    `shared_member`), so the native rule hasn't fired live; the records prompt's "at most
    one" sentence (`records.prompt.md:9-11`), added with D16.1, coincides with the drop.
  - **Publication:** loan-renewal 3 of 3; hello-world 2 of 3. `02-29-06Z` exhausted
    reconciliation dispositions on `missing_member` (claim 2 omitted three times), from a
    request byte-identical across D2.3, D16.1 and D16.2: a model limitation in an unchanged
    step (hypergeometric p = 0.33).
  - **Cost:** 10 sends, 14.6k (hello-world) and 18.3–18.5k (loan-renewal) tokens. One outlier,
    `02-28-14Z`, used 34 sends and 67k tokens: extraction returned `no_feature_claim` and the
    pre-generation source review's repair loop recovered it (a helpful repair).
  - **Advisory scores:** hello-world 89.3, 89.3; loan-renewal 89.3, 78.6, 89.3 (D2.3 means 89.9
    and 86.3). One critical criterion below its minimum: `02-28-51Z` source-grounding, from
    two invented edge cases.
  - **Targets** (D2.3, 12 publications → set, 5): restatement 4 → 3, no fall (p = 0.88), all
    three outside the rule's reach (a title sentence, a story equal to its single FR, an edge
    case repeating an acceptance criterion); FR equal to an unpublished draft 0 of 5 (p = 0.11
    alone; across three sets, D12.1 above); FR weakening 0.
  - **Guards:** unsupported addition 6 → 6, 0.5 → 1.2 per publication (p = 0.109), 4 from the
    records call (two AC "records the renewal" additions, two invented edge cases) and 2 from
    story calls with unchanged requests; lost source requirement 2 → 0; critical criterion
    below minimum 0 → 1 run; harmful repair 0; exhausted records retries 0 (D16.1: 2); false
    links AC 2 of 11, EC 2 of 2, FR 0 of 15, EN 0 of 4. The reference was scored under
    evaluation v2 and the set under v3 (FIX06 §1).
  - **Keep if:** not met; restatement didn't fall. Under rule 6 the restatement target had 7
    events across both states ("not enough evidence"), and the unsupported-addition guard was
    undecided after three runs.

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

## E6. Producerless rejection reported as a harness error

**Implemented 31 October 2026; committed in `dac4c4c`.** Three Q4 hello-world runs ended
`harness_error` `MissingProviderEvidence`: a source-omission repair turned a
`no_feature_claim` chunk into a claim, and the missing `preserve` classification had by rule
no origin, which the shared `attribution()` mapped to `missing_response`. Fix: the validator
names the rule (`producerless`, missing entries only) and `attribution()` gives `candidate`
(contract 27); a lost origin on a duplicate, unknown or forbidden entry still rejects.
Tests: `src/structured_token_test.zig`, `test/harness/integration/tests.zig`,
`test/integration/workflow_tests.zig`. Request projection byte-identical. Open parts stay in
FIX06 E6.
