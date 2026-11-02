# Z_FIX06 — Implemented FIX06 items

Implemented FIX06 items, moved here on 31 October 2026 by the user's instruction. Each
item's open parts and keep decision stay in [FIX06](FIX06.md) under the same ID. Earlier
completed FIX06 work (Q1, Q2, Q3, Q4's first attempt in full, Q6, D7.1, D11.1/.2/.4/.5,
DE6, T1, T5's measures) is `fixes/Z_FIX06.md` at git `194e29a`. This record grants no
approval and establishes no live acceptance.

## Q2b D2.3. Dispositions complete at response admission (ADR 0046)

**Implemented 31 October 2026; committed in `194e29a`. Keep not confirmed by the user.**

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

## Q10b D10.2. Advisory verdict set (first step)

**Implemented 31 October 2026; uncommitted. Not kept: the keep decision is the user's.**

- **Change:** post-generation source review offers only `supported`, `candidate_omission`
  and `candidate_invalid`, with a null `authority_gap` (ADR 0023 "Advisory verdict set").
  Typed owner `advisoryPermits` (`specification_support_evidence.zig`) feeds the withheld
  verdicts, native admission and stored readback; every advisory packet derives its excluded
  variants, `evidence_rules` keys, source-ID choices and question paths from one offered
  set. Advisory `candidate_invalid` corrections use the plain `detail`/`selection` shapes.
  `specification-state/v20`, no migration. `support.prompt.md`, `support.schema.json` and
  the workflow YAML unchanged. Required review unchanged.
- **Offline proof:** `zig build verify` 169/169 steps, 2,002 tests. Projection
  `q10b-2026-10-31` against `d23-2026-10-31`: all 167 pre-generation source-review requests
  and every generation, loss, principle and other request byte-identical; only
  post-generation source-review requests differ (schema text about 64% smaller, request text
  about 15% smaller). Contract review: no blocker; the required gap-correction coverage it
  found missing was moved to readiness inputs.
- **Measurement (6 runs, `evaluations/q10b/measures-set.json`):** 6 of 6 published; no
  withheld verdict emitted, no `unknown_variant`, no exhausted correction. Mean tokens
  against the D2.3 set (not Q1b): hello-world 68,786 → 53,374, loan-renewal 97,319 → 88,701;
  post-generation source-review input −28% and −13%.
- **Output scoring:** the specs are unchanged in quality, as designed (advisory review
  changes no output): hello-world 89.3 in 3 of 3, loan-renewal 85.7 / 78.6 / 82.1 (one below
  the 80% threshold, inside the earlier builds' range).

## Q7 D7.4. No engine code span where the text already delimits an exact value

**Implemented 1 November 2026 on `2b3dc8b`; uncommitted.** Targets the doubled delimiter
(rendering artefact A) on values that end without punctuation. Every artefact-A occurrence
so far is on a development-case value that ends in punctuation, so none of them changes.
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

## Q13. Inline source lines

**Implemented 1 November 2026 on `340261e`; uncommitted.**
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

**Implemented 1 November 2026 on `340261e`; uncommitted. Measured 1 November 2026: rule 6
recommends not kept (guards rise); the keep or revert decision is the user's (FIX06 D12.1).**
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

## Q16 D16.1 and D16.2. Requirements own their claims (with D12.1)

**D16.1 implemented and measured 2 November 2026 on `340261e`; uncommitted. Its set failed
the publication guard (FIX06 Q16 set result). D16.2 amends it the same day (user:
"approved", then "Yes, exempt FRs"); D16.2's measurement set ran the same day (FIX06 Q16
D16.2 set result) and the keep decision is outstanding.** D16.1 decisions: "the above recommendations are approved"; coverage kinds per
"No, behaviour kinds only"; "Yes, Q16 replaces it" (ADR 0035's in-batch deletion); "Yes,
list every location".
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

## T5. Brittleness counts

**Implemented and taken 1 November 2026, on HEAD `30e0d2f` (the D10.2 tree), before D13.1;
uncommitted.** `zig build code-heuristics -- --freeze <dir>` writes them to the
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
