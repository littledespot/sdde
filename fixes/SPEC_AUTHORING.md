# Field-purpose authoring comparison — 30 September 2026

The shared generation request now presents each field's purpose beside its bound
claim IDs. It reuses `required_authority_description.task`; claim meaning, citations
and exact literals retain their existing owners. Generation and selected repair
use the same packet. This changes presentation, not source selection, schema
acceptance, repair authority or clarification routing.

**The reported semantic defect remains unresolved.** The configured model still
returned the greeting alone for title, description and goal in the revised call-9
request. Better structure improved some unrelated output, but did not establish
reliable, supported authoring. Neither tested extraction revision recovered the
source title. Revised role guidance still assigned records to the greeting token
and also lost required role coverage. Those producer prompt experiments were not
retained. Lost meaning must be repaired at its producer, without changing valid
generation bindings or treating missing generated prose as a user decision.

**3 October guidance update:** the [canonical extraction prompt](../design/workflows/spec/extraction-content.prompt.md)
now explicitly includes identity, goals, obligations, conditions and constraints,
while shrinking from 75 to 67 words. Citation rules, separate token classification
and the response contract remain intact. This revision has no live comparison or
E2E quality evidence yet; the observations below describe earlier prompt variants.

## Retained reproduction and method

Source run: `2026-09-29T21-07-24Z-0ad77a3a284df670f9f51d9173e07f46` under
`zig-out/e2e-spec/`. Its source names **Hello World Application** and requires
successful startup, `Hello, World!`, and UTC date/time output. Extraction call 1
omitted the title. Role call 7 assigned the behavior claim to title/description/
goal/story and the exact greeting claim to entity applicability and records.
Call 9 then used `exact_copy` of that greeting in all three brief fields. JSON
admission did not establish their meaning or support.

Thirteen explicitly bounded diagnostic calls ran through the existing native
debugger/replay owners, with one observation per variant and no automatic retries:

- Four baseline/revised brief pairs: captured Hello World; unrelated loan renewal;
  a source-required exact feature name, `Ready!`; and an undecided renewal duration.
- Captured/revised extraction plus a second, structured extraction experiment.
- Captured/structured role assignment.

Fixed settings: Bedrock `openai.gpt-oss-20b-1:0`, `ap-southeast-2`, reasoning `low`,
temperature `0`, native schema, slot `spec_generation`. Hello World's baseline is
an exact replay. Its revised request changes only guidance and the assignment
presentation; original input meaning and schema remain fixed. Other brief pairs
use packets and selected schemas exported by the native regression fixture.
Producer comparisons change guidance only. These are isolated observations, not
E2E execution, workflow validator results or a reliability estimate.

## Semantic observations

| Case | Baseline | Revised |
| --- | --- | --- |
| Hello World | Greeting alone in every field. | Same defect; startup and UTC behavior absent. |
| Loan renewal | Confirmation token alone in every field. | Description preserves renewal duration and refused-renewal behavior. Title still uses the confirmation as the feature name; goal adds claims about transparency/reduced confusion. |
| Required exact name | Correct exact title; token-only description/goal. | Correct exact title and behavioral description; goal repeats the description rather than expressing a distinct benefit. |
| Undecided duration | Preserves the undecided duration in description. | Also preserves it without inventing a duration. Both goals risk turning the owner's missing decision into product functionality; neither establishes a complete specification. |
| Extraction | One coupled behavior claim; no title. | First revision unchanged; structured revision splits behavior claims but still omits the title. |
| Role assignment | Greeting supplies entities/records. | Greeting still supplies records; title, story and entity roles are absent. Native coverage would reject this result. |

All thirteen responses passed the debugger's JSON/schema inspection after the
existing leading-prefix normalization. That observation is separate from the
semantic failures above. No new success transition, heuristic, exact-value ban,
fallback or reviewer was added.

## Measurements and retained evidence

| Assignment | Request bytes, baseline → revised | Input/output tokens, baseline → revised |
| --- | ---: | --- |
| Hello World brief | 7,130 → 7,116 | 1,173/88 → 1,167/106 |
| Loan renewal brief | 7,094 → 7,080 | 1,165/90 → 1,159/115 |
| Exact-name brief | 6,985 → 6,971 | 1,132/90 → 1,126/119 |
| Undecided brief | 5,214 → 5,200 | 866/100 → 860/98 |
| Extraction | 9,203 → 9,256 | 1,366/111 → 1,375/96 |
| Structured extraction | 9,276 | 1,378/160 |
| Role assignment | 6,763 → 6,820 | 1,297/293 → 1,307/327 |

Total actual provider usage: **15,371 input + 1,793 output = 17,164 tokens**.
Client request times ranged from 0.581 to 1.647 seconds, totaling 11.781 seconds;
provider latency was unavailable. Hello World's guidance shrank from 881 to 804
UTF-8 bytes; context grew from 1,515 to 1,573; validation schema stayed 2,035 bytes.
Wire size includes escaping and native schema projection, so these contributions
are not additive wire-byte measurements.

Local exact requests, responses, parsed results, replay IDs, hashes, component
sizes and timings are under `.zig-cache/authoring-comparison/` (`manifest.json`,
`results.json`, `producer-results.json`, and each `*-result.json`). Native immutable
replay records are beneath the source run's
`project/specs/hello-world/logs/debugger/`. No replay changed published artifacts
or workflow authority. Credential setup failures before these calls sent no
provider request and are excluded from usage totals.

## Remaining model-settings comparison

The user requested a separate settings test if the revised assignment still
failed. Two **unsent** reviewable requests are prepared in the comparison folder:
`settings-medium.request.json` and `settings-high.request.json`, described by
`settings-plan.json`. Each retains the revised Hello World request byte-for-byte
except `reasoning_effort`. No model/configuration default has been changed.

The existing replay contract cannot dispatch those variants:
[ADR 0019](../design/decisions/0019-single-request-debugger.md#replay) says
“Provider, model and settings remain those of the selected call”.
[§28.8](../design/contracts/28-testing.md#288-model-conformance-comparisons)
requires the existing request/replay owners. Forging captured metadata, weakening
authorization or adding a separate sender would evade those boundaries.

The smallest required decision is an explicit diagnostic-only amendment allowing
the user to select a currently configured model binding for modified replay, while
preserving immutable parent settings, recording the override, reauthorizing at
dispatch and retaining one-call/no-workflow behavior. That amendment is **not
implemented or accepted** here. There is no evidence yet that higher reasoning
effort or a larger model resolves the defect. A full E2E run and output grading
also remain unperformed and separately require approval.

## Regression coverage

The generation tests cover all four source cases across brief, story, entity and
record packets; preserve bound claims and original source meaning; and check the
same assignment presentation in selected repair. The captured literal-only
candidate remains structurally legal, as does a legitimate exact feature name.
Existing stale/unknown-provenance and repair-scope rejection remains enforced.
These tests establish packet and authority behavior, not model semantics.

Validation on the retained changes:

- `zig build test-specification-generation test-architecture lint --summary all`:
  **346/346 passed**, all eight build steps passed.
- `zig build --summary all`: passed, including the native executable.
- `git diff --check`: passed.
- `zig build verify --summary all`: **1,271/1,272 tests passed**, 126/129 build
  steps succeeded. Offline integration and native packaged smoke checks passed.
  The remaining failure is `configured specification generation YAML executes
  native references models and authority gates`, scenario 103: expected `ok`,
  received `OperationExecutionFailed` with source-support findings at revision 6.
  The full suite is not green; this result does not establish that failure's cause.
  Log: `.zig-cache/authoring-verify-final.log`.

The existing architecture test was also aligned with the current native conflict
contract: model `ConflictProposal` has no `resolution` field; native
`ValidatedConflict.resolution` retains its single admitted variant. Both
assertions are enforced. Temporary debugger instrumentation was fully removed.

## Optional source-preservation review — 3 October 2026

[ADR 0021](../design/decisions/0021-optional-source-preservation-review.md)
records the implemented opt-in `validation.sourcePreservationCheck` and shared
`models.slots.repair` entry. The early check compares captured sources with
extraction/reconciliation, using the existing authority, localization and bounded
repair owners. Disabled or omitted skips the extra check; mandatory review remains.

Offline verification:

- `zig build test-specification-generation test-required-authority test-model-request-workflow test-architecture lint -j2 --global-cache-dir .zig-cache/global --summary all`:
  **799/799 passed**.
- `zig build test-specification-generation lint -j2 --global-cache-dir .zig-cache/global --summary all`:
  **227/227 passed**, including rejection of changed source bytes.
- `zig build verify -j2 --global-cache-dir .zig-cache/global --summary all`:
  **1,276/1,277 passed**, with all three new workflow cases, offline integration
  and packaged smoke checks passing. The sole failure remains the previously
  recorded scenario 103. Log: `.zig-cache/source-preservation-verify-final.log`.
- `git diff --check`: passed.
- No live model-quality evaluation was run.

Review cleanup keeps the same contracts and workflow behavior. The required-authority
owner now shares seed comparison across source, specification and principle
projections. Source review owns projection eligibility and evidence admission owns
the permitted-verdict rule; initialization, packet generation and repair reuse
those decisions. Each request projects one assigned requirement and computes its
evidence rules once. Stable feature/source repair subjects share one typed variant.
Unused fixed-positive fixture state, obsolete `*_fixed` response-schema branches
and an unused repair-slot binding in the independent provider smoke case were removed.

Cleanup checks:

- `zig build test-specification-generation test-required-authority test-architecture lint -j2 --global-cache-dir .zig-cache/global --summary all`:
  **491/491 passed**, including foreign projections, tampered seeds and forbidden
  verdicts with malformed text that cannot authorize repair.
- `zig build test-model-request-workflow -j2 --global-cache-dir .zig-cache/global --summary all`:
  **308/308 passed**.
- `zig build verify -j2 --global-cache-dir .zig-cache/global --summary all`:
  **1276/1277 passed**, **126/129 build steps succeeded**. The sole failure is
  the previously recorded scenario 103 (`OperationExecutionFailed`, source-support
  revision 6). The three preservation workflow cases, offline integration tests,
  lint and clean packaged smoke checks passed.
  Log: `.zig-cache/source-preservation-review-verify.log`.
- `git diff HEAD --check`: passed for the complete staged and unstaged change.
