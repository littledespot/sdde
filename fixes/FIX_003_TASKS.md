# FIX_003 implementation tasks

Authority: user approval of [FIX_003](FIX_003.md) on 6 October 2026 and
[ADR 0022](../design/decisions/0022-native-reference-phase-handoffs.md).
The subsequent full-implementation instruction authorizes §12.12's scoped extension.
This checklist tracks implementation; it adds no independent engine policy. Current
remaining-work scope and acceptance are defined in [§13.3](FIX_003.md#133-remaining-work-and-acceptance).

| Task | Dependencies | Owner and affected files | Acceptance / regression evidence | Status |
| --- | --- | --- | --- | --- |
| FIX3-01 | None | `candidate_validation_diagnostics`; reconciliation diagnostics/tests | Export the current role rule and actual origin after request retirement. | Implemented |
| FIX3-02 | D1/D2 decision | Native reconciliation stage contracts/actions/bindings; `spec.workflow.yaml` | Native validation precedes dependent requests. Pending/stale phases reject. Resolved receipts retire once; later-stage receipts remain pending. Repairs retire affected descendants and rebuild before full validation. | Implemented |
| FIX3-03 | FIX3-02 | Reconciliation projection/validation, role schema, native occurrence owner, source bindings and session packet owner | Replace copied claim-list joins with native handles; retain many-to-many roles, independent signals, token coverage and canonical readback. Completed repairs retire consumed authoring assignments; pending groups remain validated. Omission insertion and readback share the accepted-group check. | Implemented |
| FIX3-04 | D3 decision, FIX3-02 | Summary parser/projection, schema, atomic repair, fixtures | Remove keys/token echoes in initial and repair responses; preserve response order, insertion/deletion identity and exact tokens. | Implemented |
| FIX3-05 | D1/D5 decision | Forced-classification action, extraction repair, shared composition runtime/compiler, YAML | Distinguish forced/empty collections from semantic token-only claims; no fabricated origin or malformed-output fallback. | Implemented |
| FIX3-06 | D4 decision, FIX3-02 | Conflict-group owner, disposition/conflict validators, atomic/omission repair, schema | Preserve chain/triangle/overlap semantics; select groups once; reject foreign handles and grouped repair scope expansion. | Implemented |
| FIX3-07 | FIX3-01–06 | Prompts, packaged resources, contracts §§12/16/22, diagrams, implementation records | Remove superseded global composition and wire shapes. Separate semantic authoring selections from complete source evidence at the shared packet owner. Clarify shared field derivation without requiring finished wording in sources. Run owning tests, full offline verification, native packaging and diff review. | Implemented and verified, including the loss-evidence follow-up: 1306/1306 tests; 129/129 build steps (§12.10). |
| FIX3-08 | FIX3-07, FIX3-09/10, separate approval for each run | Existing live E2E harness and explicit cases | Actual production publication and rubric evaluation; repeated cases establish semantic reliability separately from mechanical acceptance. See §13.3. | The three approved post-implementation live runs also failed (§14.5): both greetings had reasoning-only responses; loan rebuilding exceeded the token budget after a misdirected omission repair. No publication or rubric; all listed approvals are consumed. |
| FIX3-09 | Scoped §12.2 amendment during implementation | Shared compiled result-schema and packet restriction owners; native eligibility producers | Shared scalar/collection and selected-schema restrictions; complete acceptance in §12.12 and §13.3. | Implemented and offline verified: 1314/1314 tests; 129/129 build steps (§14). Live acceptance remains FIX3-08. |
| FIX3-10 | Existing semantic/native boundary; independent of FIX3-09 | Review subject, requirement-description and packet projection owners | Focused target/purpose and distinct localization assignment; complete acceptance in §13.3. | Implemented and offline verified (§14). Live semantic benefit unverified. |

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

The latest approved live run and the shared positive-support handoff correction
are recorded in [§12.6](FIX_003.md#126-latest-approved-live-execution) and
[§12.7](FIX_003.md#127-positive-support-handoff-completion).
The additional explicit live case and its offline capture verification are in
[§12.8](FIX_003.md#128-additional-explicit-live-case).
The three follow-up live executions and current shared loss-evidence correction
are in [§12.9](FIX_003.md#129-three-approved-live-executions) and
[§12.10](FIX_003.md#1210-shared-loss-evidence-follow-up).
The separately approved loss-evidence live execution and authorized schema extension
are in [§12.11](FIX_003.md#1211-approved-loss-evidence-live-execution) and
[§12.12](FIX_003.md#1212-shared-id-schema-extension--authorized-scope).
The critical review and current remaining-work plan are in
[§13](FIX_003.md#13-critical-review-of-remaining-work--7-october-2026).
The shared ID and semantic-assignment implementation and current evidence are in
[§14](FIX_003.md#14-remaining-implementation--7-october-2026).
The three approved post-implementation live attempts and their unresolved content,
attribution and budget failures are in
[§14.5](FIX_003.md#145-three-approved-live-executions-after-fix3-0910).
Code/offline completion is distinct from FIX3-08's unmet live acceptance.
