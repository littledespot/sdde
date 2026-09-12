# JSON quality verification — 2026-09-12

The shared projection and diagnostic changes are mechanically verified. Native
activation did **not** improve the configured Bedrock GPT OSS 20B workflow: both
native E2E attempts exhausted the 100,000-token execution budget during
extraction. Specify and the evaluator therefore retain their existing
`prompt-only` defaults. Native mode remains explicitly selectable through the
registered capability; it is not enabled as a reliability fix for this case.

## Retained run evidence

These are all retained E2E reports in this checkout, including the explicitly
approved follow-up run.
The acceptance counts come from distinct model calls with recorded payload
validation events, not reparsing responses with a different validator.
“Initial” means the call context records attempt 1. A valid payload proves
structure only. No listed run published a specification or reached rubric grading.

| UTC start | Mode | Calls | Tokens | Valid payload checks | Initial valid checks | Terminal finding |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| 06:25:53 | Prompt | 2 | 6,395 | 0/2 | 0/1 | Unknown field `/token_classifications/0/preserve/ordinal` repeated |
| 06:30:44 | Prompt | 5 | 13,180 | 3/5 | 2/4 | Reconciliation syntax failures at bytes 373 and 437 |
| 07:14:13 | Prompt | 1 | 0 | — | — | Sandbox transport failure; no model quality evidence |
| 07:15:23 | Prompt | 5 | 15,589 | 4/5 | 3/4 | Duplicate claim dispositions after structural validation |
| 07:17:26 | Prompt | 8 | 23,452 | 4/8 | 2/4 | Empty signals with retained claims after protocol recovery |
| 07:19:15 | Prompt | 4 | 8,638 | 2/3 | 1/2 | Extraction repair exhausted its owning limit |
| 07:23:28 | Prompt | 29 | 87,823 | 5/29 | 1/5 | Support review returned `needs_user` after 24 protocol rejections |
| 08:02:13 | Native | 1 | 0 | — | — | Sandbox transport failure; no model quality evidence |
| 08:04:14 | Native | 29 | 101,489 | 0/28 | 0/1 | Global token budget exhausted |
| 08:08:20 | Native, explicit object typing | 29 | 101,838 | 0/28 | 0/1 | Same failure; global token budget exhausted |
| 08:21:11 | Prompt, final diagnostics | 19 | 62,941 | 4/19 | 1/4 | Retained claims referenced themselves in `related_claim_ids` |

The final call in each native run was accounted before budget rejection, so it
has captured provider evidence but no payload-validation result. The report
must not label those unvalidated responses schema-valid or discard their usage.

The 07:23 run repeatedly produced duplicate keys within a statement object.
Its later schema-valid support review still blocked generation. These are
separate failure classes: response structure, candidate relationships and
semantic support. Changing JSON parsing cannot establish semantic correctness.

## Native provider investigation

[Bedrock documents native JSON Schema output](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html),
including `anyOf` and `const`. The actual captured requests used its documented
`outputConfig.textFormat.structure.jsonSchema` field. Nevertheless, responses
contained malformed prefixes such as `{"{ "kind":...`.

Small provider probes outside the workflow reproduced the problem with tagged
alternatives; a simple object succeeded. Explicit object types and equivalent
enum tags did not make root alternatives reliable. These probes isolate a
provider/schema interaction; they are **not E2E evidence**, and they do not prove
that every native schema or every provider is affected. No prefix stripping,
variant flattening, weaker acceptance rule or automatic response-mode fallback
was added. The ineffective explicit-object projection experiment was removed.

The native activation limitation must be resolved or a different configured
model must demonstrate this contract before enabling native mode for Specify.
The implementation remains usable by any workflow through shared schema
serialization and diagnostics; provider reliability must be established live.

## Implemented boundaries and remaining acceptance

- `model_schema_projection.zig` serializes the same compiled schema into complete
  guidance and Bedrock-supported structural constraints. Full bounds and tagged
  acceptance remain with the canonical validator. The obsolete exact-profile
  checker was removed; there is no second workflow schema.
- `strict_json.zig` retains native rejection reasons and cursor locations.
  Diagnostic-only token inspection adds container JSON Pointers, active keys and
  both duplicate-key locations. It does not repair or accept input. JSON Pointer
  escaping is shared with schema diagnostics.
- Correction requests, retained rejection snapshots, event evidence, terminal
  output and Markdown reports carry the same owned diagnostic context. Allocation
  failures and snapshot lifetimes have regression coverage.
- Existing candidate repair, semantic gates, accounting and publication authority
  remain unchanged. The approved follow-up exercised the final prompt-only
  configuration with these diagnostics, but failed before publication; quality
  improvement is **not established**.

Final mechanical verification passed: **120/120 steps, 1,349/1,349 tests**, including
architecture checks and packaged executable smoke checks. `git diff --check`
also passed. Exact commands:

```sh
TMPDIR="$PWD/.zig-cache/tmp" zig build --global-cache-dir .zig-cache/global --system zig-pkg verify --summary all
git diff --check
```

These checks do not substitute for missing live publication/rubric evidence.
Per the user's instruction recorded in `AGENTS.md`, each subsequent E2E run
requires explicit approval.

Local evidence: [first native report](../../zig-out/e2e-spec/2026-09-12T08-04-14Z-1fe73275aa91d2c8cfaeac6c1cbb08ac/report.md),
[second native report](../../zig-out/e2e-spec/2026-09-12T08-08-20Z-5f2f0187fdf97370329aa51eb39fa16e/report.md),
[final verification log](../../zig-out/native-schema-final-verified.log).
Raw probe requests and responses remain under `zig-out/native-schema-probe/`,
`zig-out/native-schema-variant-probe/` and `zig-out/native-schema-enum-probe/`.

## Approved prompt-only follow-up

The user explicitly approved one further E2E run. It ran the same configured
case at **08:21:11 UTC**, exited with failure, and stopped at
`validate-dispositions`. Of 19 calls, 13 had JSON syntax/duplicate-key errors and
2 had schema errors; 4 passed the canonical payload validator. Initial attempts
passed 1 of 4 times. Total accounted usage was **62,941 tokens**.

Call 19 finally passed JSON/schema validation, but supplied:

```json
{"claim_id":{"ordinal":1},"disposition":"retained","related_claim_ids":[{"ordinal":1}]}
```

Claim 2 likewise referenced itself. The existing claim-disposition validator
rejects self-relations and requires `related_claim_ids: []` for retained claims.
The workflow routes that domain rejection to failure, so it never publishes
`spec.md` or invokes the rubric evaluator. This is a candidate relationship error
after JSON validation, not another JSON parsing failure. The validator currently
emits a generic failure; the precise cause above was established by inspecting
the retained response and its owning validator, not a typed runtime diagnostic.

All five expected evidence files were checked for every call. Each retained
`model_output.txt` exactly matched the complete text in its captured provider
`response.json`. No subsequent E2E run was started.

Command (after loading the project's `.env.e2e`):

```sh
TMPDIR="$PWD/.zig-cache/tmp" zig build --global-cache-dir .zig-cache/global --system zig-pkg e2e-spec -- --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json
```

[Run report](../../zig-out/e2e-spec/2026-09-12T08-21-11Z-db6e32272690b41d790fdf5044c10fa3/report.md),
[final response](../../zig-out/e2e-spec/2026-09-12T08-21-11Z-db6e32272690b41d790fdf5044c10fa3/evidence/generation/call-000019/model_output.txt),
[owning validator](../../src/actions/reference/validate_reference_claim_dispositions.zig),
[command log](../../zig-out/approved-prompt-e2e-20260912.log).
