# FIX04 Phase 1A.3 — admission routing and attribution preparation

Authority: the approved decision 4(a) in
[FIX04 Phase 1A.3](FIX04.md#phase-1a3--attribute-insertion-presentation-and-repair-collapsed-units-as-units),
[the composition amendment](../design/contracts/text-field-composition.md#phase-1a3-amendment--composition-defects-are-corrected-as-a-unit)
and [§22.4](../design/contracts/22-repair.md#224-repair-request-and-response).
The design remains Proposed. This work changes engine development contracts;
it does not run a workflow against a target project.

The causal defect is shared response admission: it rejected embedded wire syntax,
but admitted insertion-only values that then reached field-level unit repair.
The request already retains native field identities, original sources and the
complete assignment. Composition rejection belongs at that shared boundary,
before stage-specific validation, using the request's existing protocol correction.

The applicable baseline is design §§1, 3–4, 12, 21–22, 27–28 and 30–31, especially
the candidate-data boundary, native mechanical validation, local bounded retries,
unchanged-repair exhaustion and immutable diagnostic replay. Persistence,
publication, executable capabilities, provider settings and retry allowances do
not change. Presentation wording is reserved for the separately approved
attribution experiment.

## Admission and repair

The shared response checker follows native field bindings and reports concrete
JSON pointers, field identities and typed composition reasons together. It reuses
the canonical composition policy and source-aware wire grammar. Envelope decoding
retains this diagnostic separately from JSON syntax failures; the existing
protocol-correction owner includes it with the complete original request.
The owners are [model_text_composition.zig](../src/domain/model_text_composition.zig),
[model_envelope.zig](../src/domain/model_envelope.zig),
[model_protocol_retry.zig](../src/domain/model_protocol_retry.zig) and the existing
`typed_text.zig` / `model_text_wire.zig` policy and grammar owners.

Generation, extraction, reconciliation, clarification questions and replacement
responses use that admission boundary. Composition defects cannot authorize unit
repair. The obsolete composition-specific rendered repair presentation is removed;
other repair kinds retain their authorization, old-value/revision checks, progress
comparison and bounded exhaustion. Native/stored-value composition checks remain.
Harness reports, retired-request snapshots, first-rejection evidence and receipt
records retain the grouped composition diagnostic separately from JSON syntax.
Terminal and Markdown views expose every rejected field.

## Retained offline evidence

The [retained replay](../test/calibration/representation-admission/README.md) adds
the authentic 18:58 diagnostic's calls 8–14. It binds unchanged request, response,
output, context, transport and source bytes with SHA-256. Its historical selected
schemas do not retain the current native field bindings, so it reports wire-syntax
rejection separately from per-field composition validation. It does not invent
historical metadata or claim replay of current whole-response admission.

## Attribution preparation

The [prepared experiment](../test/calibration/insertion-presentation/README.md)
retains call 13 (records) and call 1 (extraction) from
`2026-10-16T07-58-59Z-ec56ff4bc24a21c0082210cf6caa8f31`.
Records have five presentation arms; extraction has two. Three repetitions per
arm make exactly 21 single-request sends, all pending explicit approval.
Model, settings, evidence and selected schema remain fixed. The offline tool
prepares requests and scores immutable debugger results; it cannot send a request.
Mechanical insertion-only rates and native admission diagnostics do not assess
semantic quality or supply workflow authority.
The canonical strict JSON decoder now handles explicitly declared inert JSON
evidence leaves recursively, as it already did at the root. Closed enclosing
metadata, wire types, unknown fields and duplicate rejection remain enforced;
the calibration tool adds no parallel or coercing reader.

## Validation and remaining gate

**Offline gate passed, 16 October 2026.**

| Command or evidence | Result |
| --- | --- |
| `zig build verify -j1 --summary all` | 156/156 steps and 1,734/1,734 tests passed, including 120/120 integration tests, architecture, formatting and clean native packaging smoke. Full log: `.zig-cache/fix04-phase1a3-verify-complete.log`. |
| Retained replay within that verification | Seven runs, 32 captures and 100 selected values: 13 `reference_only`, five `prohibited_exact`, 20 embedded-syntax rejections and 62 admitted controls. Eleven complete responses reject the schema-only wire-syntax guard. Zero provider calls. |
| `zig build attribution-replay -- prepare test/calibration/insertion-presentation/prepared` | Seven arms, 14 edit/request artifacts and the 21-trial plan materialized offline. |
| `zig build attribution-replay -- validate test/calibration/insertion-presentation/prepared` | Deterministic regeneration, original request reconstruction and all source pins passed. |
| `zig build attribution-replay -- score test/calibration/insertion-presentation/prepared test/calibration/insertion-presentation/receipts.template.json zig-out/insertion-presentation.unattempted.score.json` | All 21 trials remain unattempted; zero sends and no inferred success. |
| `git diff --check` | Passed. |

Owner-focused build steps also passed during iteration: model-envelope admission
(46 tests), model-request workflow correction/recovery/exhaustion (420), repair
retry (32), real extraction/reconciliation/specification producers (609 combined)
and the offline attribution helper (15). The final full suite includes the later
strict-decoder and report-retention regressions.

The integration matrix preserves native scalar/identity repair coverage using an
invalid-scalar fixture where the former blank fixture now belongs to protocol
correction. The intentional blank story omission response instead proves bounded
protocol exhaustion, grouped `/value` diagnostics, charged sends, zero merges and
no publication. No test was skipped or assertion weakened.

Earlier verification attempts exposed installed-compiler/cache and loopback
sandbox restrictions, a stale fixture assertion, and exhausted disk space.
The final run used the same checks serially with the required system access.
Generated Zig scratch and task-created standalone test caches were cleared; stale
cache manifests were archived before rebuilding. Source and retained live-run
evidence were preserved. No production dependency, provider setting, retry budget,
normalizer or architecture exception changed.

No model calls or E2E runs occurred. The attribution sends,
the evidence-based change in `model_field_presentation.zig`, and the separately
approved committed-build hello-world and loan-renewal diagnostics remain open.
