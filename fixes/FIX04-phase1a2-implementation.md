# FIX04 Phase 1A.2 implementation — 16 October 2026

This implements the user's approved offline remediation in
[FIX04 Phase 1A.2](FIX04.md#phase-1a2--make-model-facing-presentation-consistent-with-admission).
The accepted [composition contract](../design/contracts/text-field-composition.md)
and ADR 0020 retain the exact-copy prohibition for descriptive fields, the entity-name
exception and the existing passive/source roles. The overall design remains Proposed.
No model binding, temperature, retry allowance, workflow budget or dependency changes.

| Required behavior | Owning contract and implementation |
| --- | --- |
| Per-field schemas | Native wire declarations bind returned text leaves to `text_field_policy.zig`. `model_candidate_json.zig` derives their paths; `model_text_field.zig` filters insertion alternatives through the registry. The shared schema owner applies this to initial generation, narrowed/composed results, protocol correction and every repair route. A closed repair field selection distinguishes a replacement's wire contract from a separately selected native wire member, matching its existing decoder. Descriptive exact-copy insertions also reject at native admission and stored readback. |
| Selected guidance | `model_field_presentation.zig` derives plain field rules and permitted insertion targets from the actual selected schema, intersecting its remaining alternatives with the registry. A plain-string question advertises no insertion alternatives. The unconditional exact-copy sentence and whole-inventory tables are removed. Clarification guidance remains when that schema permits a clarification response. |
| Usable choices | Native packet producers declare insertion catalogues and token-only source-group entries. The shared presenter offers them only when a returned field permits their insertion kind. Original source evidence retains its separate purpose. Projection retains exact original array indices and leaves the immutable native packet unchanged. |
| Rendered composition repairs | `atomic_repair.zig` distinguishes structured diagnostic repair from native composition repair. Composition packets show the canonically rendered defect and registry rule, omitting the rejected wire value and raw containing candidate. Record rendering uses the same shared lineage as native record validation. Fixed non-question detail facts remain available without echoing the rejected question. Exact compare-and-swap witnesses, dependencies, repair permits and unchanged-repair exhaustion remain native and unchanged. Extraction, reconciliation, specification and source-question repair use this owner. |
| Native origins | The audit's producer is a closed model/native/unavailable union. Native summary reuse links to an earlier audited value and the real native validation digest. Clarification refresh retains validated native state identity. Missing model receipts and missing native parents remain unknown. Complete native-origin audits can report measured zero without inventing model calls. |
| Capture and replay | `model-request-debug/v5` and `request-replay/v6` retain native wire-field bindings. Affected E2E reports, baseline acquisition and baseline scoring use v3. Events and assessment inputs retain their unchanged versions. Historical captures are immutable; no compatibility reader or migration is added. |

Removing exact-copy alternatives does not make the grammar express prose presence
where passive or source insertions remain permitted. Native admission still owns
that check. A selected string-only contract enforces a string through its grammar.
These are mechanical checks, not semantic adequacy or source-fidelity judgments.

## Retained evidence

The [F10/F11 replay fixture](../test/calibration/representation-admission/README.md)
contains six runs, 25 captured exchanges and 83 selected values. It retains exact
original request, response, outcome and model-output bytes with SHA-256 bindings.
Stronger-policy expectations are 7 `reference_only`, 5 `prohibited_exact`,
19 `embedded_insertion_syntax` and 52 admitted controls. No captured bytes are
corrected or promoted into current workflow authority. The replay makes zero
provider calls.

## Validation

Validation uses the repository-pinned Zig 0.16.0, through `build.zig`, without
scenario filters.

| Command | Result |
| --- | --- |
| `zig build test-reference-reconciliation test-specification-generation test-integration -j2 --summary all` | 14/14 steps; 640/640 tests passed. Includes all 164 configured specification-generation scenarios, prepared repair requests across every reconciliation content kind, ordinary and false-empty extraction omissions, and the complete retained replay. |
| `zig build verify -j2 --summary all` | 156/156 steps; 1,718/1,718 tests passed. Includes 1,597 repository unit tests, 115 integration tests, architecture checks, lint and clean-directory native packaging smoke tests. |
| `git diff --check` and `git diff --cached --check` | Passed. |

The final full-verification log is `.zig-cache/phase1a2-verify-complete.log`;
the final repair/integration log is `.zig-cache/phase1a2-final-integration.log`.
The retained replay's machine result is
`.zig-cache/representation-admission/replay.json`: six runs, 25 exchanges,
83 values, 31 rejected defects, 52 admitted controls and zero provider calls.
Regression coverage also includes selected-schema guidance and catalogue omission,
plain question fields, native exclusions, record-wide lineage, fixed question-repair
facts, unchanged protocol-correction inputs, stale CAS, stored readback, native producer
proofs, missing model receipts and allocation failures.

Phase 1A.2's offline implementation and verification are complete. The diff retains
the existing source exception, no-progress exhaustion, provider API, model settings
and resource allowances. There are no approved deviations or compatibility readers.

## Remaining live evidence

This offline implementation does not close the separately approved live exit gate.
FIX04 still requires one hello-world and one loan-renewal diagnostic on a committed
build. Each must admit brief/story prose or end in a typed composition failure after
a materially different repair presentation, with admission escape measured zero.
No live run was performed for this implementation request. Phase 2 still requires
renewed budget-feasibility evidence, the user's recorded budget/scope decision and
a committed baseline build. Semantic improvement, useful publication and reduced
live cost remain unmeasured.
