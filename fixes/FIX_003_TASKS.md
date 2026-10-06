# FIX_003 implementation tasks

Authority: user approval of [FIX_003](FIX_003.md) on 6 October 2026 and
[ADR 0022](../design/decisions/0022-native-reference-phase-handoffs.md).
This checklist tracks implementation; it adds no independent engine policy.

| Task | Dependencies | Owner and affected files | Acceptance / regression evidence | Status |
| --- | --- | --- | --- | --- |
| FIX3-01 | None | `candidate_validation_diagnostics`; reconciliation diagnostics/tests | Export the current role rule and actual origin after request retirement. | Implemented |
| FIX3-02 | D1/D2 decision | Native reconciliation stage contracts/actions/bindings; `spec.workflow.yaml` | Native validation precedes dependent requests. Pending/stale phases reject. Resolved receipts retire once; later-stage receipts remain pending. Repairs retire affected descendants and rebuild before full validation. | Implemented |
| FIX3-03 | FIX3-02 | Reconciliation projection/validation, role schema, native occurrence owner, source bindings and session packet owner | Replace copied claim-list joins with native handles; retain many-to-many roles, independent signals, token coverage and canonical readback. Completed repairs retire consumed authoring assignments; pending groups remain validated. Omission insertion and readback share the accepted-group check. | Implemented |
| FIX3-04 | D3 decision, FIX3-02 | Summary parser/projection, schema, atomic repair, fixtures | Remove keys/token echoes in initial and repair responses; preserve response order, insertion/deletion identity and exact tokens. | Implemented |
| FIX3-05 | D1/D5 decision | Forced-classification action, extraction repair, shared composition runtime/compiler, YAML | Distinguish forced/empty collections from semantic token-only claims; no fabricated origin or malformed-output fallback. | Implemented |
| FIX3-06 | D4 decision, FIX3-02 | Conflict-group owner, disposition/conflict validators, atomic/omission repair, schema | Preserve chain/triangle/overlap semantics; select groups once; reject foreign handles and grouped repair scope expansion. | Implemented |
| FIX3-07 | FIX3-01–06 | Prompts, packaged resources, contracts §§12/16/22, diagrams, implementation records | Remove superseded global composition and wire shapes. Separate semantic authoring selections from complete source evidence at the shared packet owner. Clarify shared field derivation without requiring finished wording in sources. Run owning tests, full offline verification, native packaging and diff review. | Verified including both follow-ups: 1301/1301 tests; 129/129 build steps (§12.5). |
| FIX3-08 | FIX3-07, separate approval for each run | Existing live E2E harness and explicit cases | Actual production publication and rubric evaluation; repeated cases establish semantic reliability separately from mechanical acceptance. | Last live run failed initialization with four roles unassigned by call 7. Shared role-purpose follow-up is verified offline; the next live publication/rubric run awaits its required approval. |

Initial requests and protocol corrections use the same named phase schemas and
immutable packets. Atomic and source-omission repairs use the same native
projections and group selections. Canonical persisted signal/token formats remain
unchanged; strict readback still validates their native joins. No compatibility
reader or parallel retry/continuation policy is retained.

Required commands are repository-owned: focused `zig build` test steps, then
`zig build verify` (including architecture, lint, integration and clean packaging)
and `git diff --check`. Exact commands and results are recorded in
[FIX_003 §12](FIX_003.md#12-implementation-record).

D6 remains the proposal's conditional investigation: retain existing principle
citation granularity until a precision-preserving representation is established.
The approved live run and its remaining acceptance gaps are recorded in
[FIX_003 §12.2](FIX_003.md#122-approved-live-execution); the implemented follow-up
and full offline checks are in [§12.3](FIX_003.md#123-assignment-projection-follow-up).
The newly approved follow-up run is recorded in
[§12.4](FIX_003.md#124-approved-follow-up-live-execution). No successful publication,
rubric result or improved live reliability is claimed by this checklist.
Resumed shared role-purpose work is recorded in
[§12.5](FIX_003.md#125-resumed-role-purpose-guidance-work).
