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
