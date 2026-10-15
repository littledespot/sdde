# Phase 1 offline implementation evidence — 15 October 2026

**Status:** the bounded compatibility scenario is **complete offline** and final
verification passed. The authentic
Bedrock exchange is **not run**; Phase 1's live exit gate remains pending.

This implements the four requested local deliverables in
[FIX04 Phase 1](../../../fixes/FIX04.md#phase-1--establish-compatible-current-model-execution):
a fresh production request, at most one physical send, retained compatibility
reports and offline regression checks. It changes development harness behavior,
not production generation assignments, semantic acceptance, provider codecs or
workflow transitions. The governing boundaries are Design §§3.3/12/28.8/31:
untrusted model data, native request authority and accounting, diagnostic evidence
separate from E2E qualification, and whole-workflow publication authority.

## Implementation and evidence boundary

- [The command](../../harness/compatibility/cli.zig) requires an explicit case and
  `--live`. Configuration preflight checks every slot against the existing
  Luna-only cost policy and requires debug/trace capture before credentials.
- [Production invocation](../../harness/e2e/invoke.zig) reuses fixture materialization,
  composition `Runtime`, workflow compilation, request preparation and authorization.
  The first assignment remains the selected workflow's actual first request.
- [The trace](../../harness/e2e/trace.zig) consumes a one-send permit immediately
  before forwarding inference. Count requests, another send, changed bindings or
  controls, and publication-capable children reject. Native usage accounting
  finishes before typed cancellation; original runner rejections remain preserved.
- [Inspection](../../harness/compatibility/inspection.zig) reuses canonical capture
  readback, catalogue/binding validation, request encoding, Converse decoding and
  payload-schema inspection. Trace transport metadata owns HTTP status/request ID.
  Native origin, byte readback and actual accounting must agree. SHA-256 values
  retained from the transport observation reject substituted external copies;
  these are diagnostic byte identities, not engine state/predecessor authority.
- [Reports](../../harness/compatibility/report.zig) retain build revision/settings,
  request/response/outcome files, identity, digests, stops, usage, schema diagnostics
  and supplied reasoning. Unknown actual consumption is `null` with
  `usage_complete: false`; accounted tokens remain separate. Partial responses
  retain their exact bytes without candidate/schema eligibility. HTTP rejection
  alone remains inconclusive. No result grants semantic or publication authority.

The frozen binding remains `aws-bedrock / global.openai.gpt-6-luna /
ap-southeast-2 / Converse / native JSON Schema`, with strict output, omitted
temperature/explicit reasoning controls and 16,384 requested output tokens.
No fallback model, mode or historic capture is used. No production dependency,
accepted decision or invariant changed; the governing design remains proposed.

## Offline coverage

[Four integration tests](../../integration/provider_compatibility_tests.zig) cover
**22 scenarios** across hello-world and loan-renewal: schema-valid synthetic responses,
cancellation, transport failure, both partial-response forms, failed pre-send
capture, missing usage, malformed provider JSON, output stop, invalid payload
schema and malformed candidate JSON. They prove one-send accounting, native usage
before stop, separate reasoning, exact capture readback and absence of later
validation/repair/publication. **24 additional negative checks** reject substituted
bytes, origins, usage, HTTP metadata and missing/incorrect observed digests.

[Unit checks](../../harness/compatibility/tests.zig) and trace tests cover argument
selection/preflight, the dispatch/publication guards, conservative failure
accounting, partial retention, byte identity and report write/sync failures.
The [launcher test](../../harness/integration/compatibility_launcher_test.sh) uses
fake Zig to check quoting, root discovery, credential-file behavior and exit codes.
The standalone smoke uses an executable with native model connections disabled,
from a clean temporary directory. Manual live execution is excluded from all
automated test/verification dependencies.

**Actual provider calls and consumption: zero.** Fixed responses, their usage and
offline report origin are synthetic evidence. No quality, reduced brittleness,
current-model compatibility or E2E qualification is established by these checks.

## Verification

All checks use the pinned Zig 0.16.0 and registered `build.zig` steps.

- `ZIG_GLOBAL_CACHE_DIR=/private/tmp/sdde-zig-global-cache zig build --global-cache-dir /private/tmp/sdde-zig-global-cache test-provider-compatibility test-rubric-evaluator -j2 --summary all`:
  **passed, 6/6 steps and 243/243 tests** (73 compatibility; 170 evaluator).
- `ZIG_GLOBAL_CACHE_DIR=/private/tmp/sdde-zig-global-cache zig build --global-cache-dir /private/tmp/sdde-zig-global-cache smoke-provider-compatibility test-provider-compatibility-launcher test-provider-conformance test-provider-invocation-validation test-model-request-preparation test-model-request-workflow -j2 --summary all`:
  **passed, 22/22 steps and 569/569 tests** during implementation; the final full
  run below covers the final source as well.
- `ZIG_GLOBAL_CACHE_DIR=/private/tmp/sdde-zig-global-cache zig build --global-cache-dir /private/tmp/sdde-zig-global-cache test-integration -j2 --summary all`:
  passed, 7/7 steps and 102/102 tests before the final observed-digest extension.
- `ZIG_GLOBAL_CACHE_DIR=/private/tmp/sdde-zig-global-cache zig build --global-cache-dir /private/tmp/sdde-zig-global-cache test-provider-compatibility test-rubric-evaluator verify -j2 --summary all`:
  **passed, 155/155 build steps and 1,786/1,786 tests**, including the observed-digest
  extension, all 102 integration tests, architecture/contract checks, standalone
  compatibility startup, manual/automated build isolation and clean-directory
  native executable packaging/debugger smoke. The build roots report 1,435 repository,
  73 compatibility, 170 evaluator, 102 integration and two three-test dependency
  suites; these totals include overlapping targeted roots, not independent semantic
  samples. Retained command output: `/private/tmp/sdde-phase1-verify-final.log`.

The final full command used approved sandbox escalation for nested compiler and
localhost debugger probes, with the writable temporary Zig global cache. Native
model connections remain disabled in automated tests; this was an offline run.

Targeted and integration failures during implementation exposed production archive
HTTP/body-provenance distinctions and report-number projection differences. The
fixes reuse the owning contracts; no schema, assertion, test or policy was weakened.
Final whitespace and local-reference audits passed. The complete diff was reviewed
for scope, ownership, fallback paths, policy weakening and authority bypasses.

## Remaining live gate

After separate bounded approval, the prepared one-send probe is:

```sh
./scripts/provider-compatibility.sh \
  --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json --live
```

It requires the selected Bedrock credential and retains
`zig-out/provider-compatibility/<UTC-run>/report.json` and `report.md` plus the
fresh project/capture. No live dispatch has been approved or executed here. A
compatible authentic result qualifies only its observed request/settings; all
baseline semantic comparisons, qualification and full E2E gates remain separate.
