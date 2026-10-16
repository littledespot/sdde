# FIX04 Phase 1A implementation — 16 October 2026

The explicit implementation instruction settles the four policy decisions in
[the accepted composition contract](../design/contracts/text-field-composition.md).
It amends §§7.1, 17.3, 22 and ADR 0020 without changing the overall Proposed
design status. This is engine development and offline mechanical evidence;
no new live workflow, provider request or target-project execution is included.

| Required behavior | Owning contract and implementation |
| --- | --- |
| Explicit prose and insertion roles | `text_field_policy.zig` has an exhaustive field inventory. Narrative and behavior fields require nonblank prose; entity names are the sole identity-label exception. Only declared behavior/constraint fields carry obligation-bearing exact copies. |
| Native admission and protocol correction | `model_text_wire.zig` recognizes the closed insertion grammar in declared prose. `model_envelope.zig` uses existing bounded correction. `typed_text.zig` enforces field composition and the same source-aware wire rule after decoding. Explicit native selectors cover plain-string review clarification questions. |
| Exact original-source exception | Native packets, including reconstructed reconciliation-stage packets, preparation, correction and repair retain original source witnesses. Source-backed wire-object spans preserve their exact bytes during canonical normalization; surrounding prose uses the existing NFC owner. Matching display text and earlier model output do not supply a witness. |
| Coverage | `specification_coverage.zig` credits composition-valid obligation-bearing fields. Incidental insertions retain lineage but do not satisfy behavioral coverage. The obsolete whole-field literal-to-insertion coverage rewrite and its execution path are removed; unsupported reconstruction blocks. |
| Repair and progress | `atomic_repair.zig` compares canonical declared text for progress while keeping exact old-value and dependency preconditions. `workflow_retry.zig` and the runner exhaust unchanged repairs under the current defect key before applying their tentative deltas. Actual sends/tokens and completed counts remain charged; no successful repair, re-review or publication follows. |
| Presentation and readback | Generation/reference/repair packets project the field registry. Native and stored-value validators reuse its composition and source rules, including source-review questions. Source-aware clarification refresh, rendering and publication check retained questions against current original sources, including successful workflows with no new needs; user answers and protected-form bytes retain their own contracts. |
| Reporting | Current reports use `first_native_rejection`, separate `representation_admission` attribution and a native admitted-value audit. The primary escape denominator is invoked native workflows, including zero-send failures, with unknown coverage explicit; producer-origin incidence is secondary. Generation-arm scoring retains its existing dispatched-workload convention. Later sends/tokens measure chronological exposure, not causal cost. |

Native record-batch assembly retains per-field repair origins and stable occurrence
identities, including gaps from deleted records. The audit uses that same native
projection to deduplicate assembled views without conflating equal fields from
different records or attributing repaired text to its initial author.
Clarification projections retain their native IDs; a missing current producer
origin remains explicit rather than manufacturing attribution or measured zero.

Current debug descriptions use `model-request-debug/v4` and replay records use
`request-replay/v5` to retain the native source/prose metadata. E2E reports/events
and the affected baseline acquisition, scoring and assessment-input contracts
use their current closed versions. Unsupported historical versions are rejected;
there is no compatibility reader or rewrite of authentic captures.

## Retained replay

The [retained fixture](../test/calibration/representation-admission/README.md)
copies exact bytes and hashes from all five F10 diagnostics. Its integration
replay exercises native admission for 23 captured exchanges and 79 selected
values: 10 insertion-only values, 19 encoded insertion values and 50 prose-bearing
controls. The fixture is available from a clean checkout and does not depend on
ignored capture directories. It supplies no current workflow or semantic authority.

## Validation and remaining evidence

Verified with the repository-pinned Zig 0.16.0:

| Command | Result |
| --- | --- |
| `zig build test-model-envelope test-model-request-preparation --summary all` | 6/6 steps; 81/81 tests passed. |
| `zig build test-model-logging --summary all` | 9/9 steps; 204/204 tests passed. |
| `zig build test-clarification-inputs test-specification-generation test-baseline test-required-authority test-workflow-repair-retry test-atomic-execution test-architecture --summary all` | 29/29 steps; 1,317/1,317 tests passed on the final implementation. |
| `zig build verify --summary all` | 156/156 steps; 1,699/1,699 tests passed, including lint, the complete offline integration suite, architecture checks and clean-directory native packaging smoke tests. |
| `git diff --check` and `git diff --cached --check` | Passed. Existing staged work was preserved. |

The retained replay's machine result is
`.zig-cache/representation-admission/replay.json`: five runs, 23 exchanges,
79 values, 10 `reference_only`, 19 `embedded_insertion_syntax`, 50 admitted,
and zero provider calls. The final full-verification log is
`.zig-cache/phase1a-verify-complete.log`; the final owner-check log is
`.zig-cache/phase1a-final-owners.log`. Complete suites ran without a scenario
filter. Historical debug formats remain unsupported rather than supplying
current calibration evidence. No dependency, model binding or live budget changed.

Phase 1A's implementation and offline exit gate are complete. This evidence
establishes native admission enforcement and bounded no-progress handling.
The Phase 2 freeze still requires a committed build, renewed budget feasibility
and its recorded user decision. Separately approved live diagnostics and the
development-panel baseline remain outstanding; offline admission enforcement
does not establish semantic improvement, useful publication or reduced live cost.
