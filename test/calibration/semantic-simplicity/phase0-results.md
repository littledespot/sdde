# Phase 0 retained evidence — 15 October 2026

**Status:** **Phase 0 complete (offline)**; dry run and full verification passed.
Base revision: `5816d9bed631acabcb256025e911bb565b8f9771` plus the current working
changes. This record does not claim a committed revision or live qualification.

The [protocol](protocol.json), [inventory](cases.json), [labelled specimens](specimens.json)
and [operating contract](README.md) are retained with the generated
[dry-run snapshot](phase0-dry-run.json). Regenerate the latter through the registered
integration step; do not edit its scores by hand.

| Evidence | Observed result |
| --- | --- |
| Independent features/domains | 24 / 24 |
| Feature sizes | 12 small / 12 medium |
| Development / reserved qualification | 8 / 16 features |
| Variants / source-backed duty labels | 72 / 225 |
| Base sufficient / gap-or-conflict cases | 18 / 6; development 6 / 2 |
| Prepared development inputs / exported qualification inputs | 24 / 0 |
| Planned / accounted synthetic workloads | 144 / 144, zero unattempted |
| Required faithful/paraphrase/omission/invention/false-gap/harmful-repair specimens | 6 checked |
| Simulated physical sends / tokens | 216 / 172,800 |
| Actual model sends / tokens | **0 / 0** |
| Useful completions / workflow authority | **0 / none** |
| Semantic benefit / reduced brittleness | **not measured** |

The fixture SHA-256 identities are included in the generated snapshot. Tests also
check corrected initial errors remain counted as harm, initially faithful work
is not blamed for a later harmful repair, per-arm resources remain workload-based,
missing observations reject, partial panels remain inconclusive, unknown usage and
disputes require stopping, and an exact-limit complete panel differs from an
overshoot. Seeded uncertainty and qualification-sizing examples are synthetic
accounting checks, not observed model-quality estimates.

The independent source/variant/specimen label review was **model-assisted**.
Quotation/literal membership is mechanically verified; correctness of meaning is
not deterministic proof or human approval. Qualification source projections and
model responses have not been used for tuning. No current-model response exists
in this evidence set.

## Coordinated transport and test policy

The user separately requested Bedrock Converse and provider reasoning availability.
The shared codecs now cover inference, supported CountTokens, capture/replay and
harness consumers. Common controls, native schema projection, registered reasoning
policies, cached usage, typed stops, exact request identity and allocation cleanup
have positive/negative offline tests. Legacy provider chat replay bodies reject
without changing their immutable parent or dispatching a request.

Provider-supplied reasoning text, optional signatures and opaque redacted blocks
are retained as owned diagnostics on production complete/stopped/rejected results
and exposed in the debugger. They are excluded from candidate JSON and semantic
or publication authority. Signatures are preserved, not independently verified;
no readable text is invented for redacted content.

Phase 0, canonical live generation fixtures, diagnostics and evaluation select
only **Bedrock `global.openai.gpt-6-luna` from Sydney**, using native JSON Schema
with Luna's required additional strict-output field. Temperature and explicit
reasoning effort are omitted; the freeze records AWS's documented default medium
without guessing a Converse effort mapping. The global inference profile does
not promise AU-only routing. The live cost guard excludes Sonnet/Sol/Haiku,
historical models, other profile aliases and direct OpenAI API selection before
credentials/network. The rubric judge preserves its native-schema gate. The same
model's evaluation is a separately labelled role, not independent model evidence.

## Verification

All commands use pinned Zig 0.16.0 and registered `build.zig` steps. Offline fake
transports and startup rejection probes made no provider calls.

- `zig build --global-cache-dir /private/tmp/sdde-zig-global-cache test-rubric-evaluator --summary all`:
  passed, 147/147 tests, including the closed comparison contracts and Luna-only guard.
- `zig build --global-cache-dir /private/tmp/sdde-zig-global-cache test-provider-conformance test-provider-invocation-validation test-model-logging --summary all`:
  passed during reasoning implementation, 321/321 tests for provider observations,
  ownership and logging. Final Luna/profile/routing coverage is also included in
  the full run below.
- `zig build test-model-payload-schema`, `zig build test-specification-generation`,
  `zig build test-model-request-workflow`: passed during the owning fixture cutover.
- `zig build --global-cache-dir /private/tmp/sdde-zig-global-cache test-architecture`:
  passed with the targeted harness run.
- `zig build --global-cache-dir /private/tmp/sdde-zig-global-cache smoke-rubric-evaluator`:
  passed after updating cost/capability/credential rejection fixtures.
- `zig build --global-cache-dir /private/tmp/sdde-zig-global-cache test-provider-conformance --summary all`:
  passed, 89/89 tests, including exhaustive registered-model/region HTTP routing.
- `zig build --global-cache-dir /private/tmp/sdde-zig-global-cache test-integration`:
  passed; final full verification confirms 98/98 integration tests.
- `ZIG_GLOBAL_CACHE_DIR=/private/tmp/sdde-zig-global-cache zig build --global-cache-dir /private/tmp/sdde-zig-global-cache test-rubric-evaluator verify -j2 --summary all`:
  **passed, 145/145 build steps and 1,671/1,671 tests**, including architecture,
  closed contract checks, offline integration, standalone harness rejection probes
  and native executable clean-directory packaging/debugger smoke.

The first sandboxed full run passed all 1,671 tests but could not finish two
nested compiler probes and the localhost debugger smoke. The final rerun supplied
the temporary global-cache environment and used approved sandbox escalation;
it passed without modifying the checks or making provider calls. Expected
fault-injection logging failures and rejected-fixture event logs are retained
test evidence, not failed assertions. Final whitespace, local-reference and
fixture-hash consistency audits passed.

The API audit found no legacy inference endpoint, decoder, API selector or fallback
in the active Bedrock adapter, harness, replay and current provider documentation.
Inference routes exclusively to `/converse`; supported token counting remains
the separate `/count-tokens` operation. Luna cannot acquire a count capability.
Generic workflow `invoke-model` actions/interfaces and immutable archive records
are not an alternative AWS transport.

Initial integration/full verification exposed a remaining repair-wire scan of
the old developer-message slot. Labelled diagnostics identified it despite
optimized traceback ambiguity; it now inspects Converse `system[]` while retaining
exact schema, prompt and repair-policy checks. The read-only eligibility fixture
also asserts unchanged slots, inputs and model accounting under its no-delta
contract; summary-builder invalidation and provenance checks remain intact.
Evaluator startup probes now preserve credential/input rejection with permitted
Bedrock Luna and reject disallowed models before credentials. These are fixture
contract corrections, not weakened engine acceptance rules.

## Remaining gates

Phase 1's authentic current-model exchange, Phases 2/3's baseline and paired
diagnostics, and Phase 5's complete production generation/review/repair/publication
remain unexecuted. No live debugger replay or E2E test was run. Each live run still
requires its concrete bounded manifest and separate explicit approval. A Phase 0
pass qualifies measurement preparation only; it cannot qualify generation quality,
less brittleness, a model tier or a production decomposition.
