# FIX01 — Critical review of the revised Spec workflow handoff

**Review date:** 9 October 2026, Australia/Melbourne.

**Tracking status:** Sole active fix record. Completed implementation and dated
approval/run history are retained in [archive/](archive/); their old plans and
status statements are historical. This document owns the outstanding work below.

**Current architectural verdict:** Yes, the implemented items move the engineering
forward: business subjects and family meanings are clearer, incomplete role coverage
has a truthful typed outcome, and failure evidence is substantially better. They
have **not demonstrated improved completion or specification quality**. The latest
retained run, **9 October at 17:31:50 AEDT**, passed role selection, generated a
candidate, merged an upstream repair and regenerated, then exceeded the token
budget during its second source review. Its first clear content defect was call
10's user story containing only three greeting references; call 17 then attributed
that loss to an intact upstream signal. No specification was published or graded.
[§9.10](#910-first-authoring-error-and-its-consequences--9-october-2026)
records the evidence. Greater execution progress, offline correctness and completed
calibration are different outcomes from a reliable completed workflow.

The bounded R3 policy projection, R4 family meanings and R10 blocking handoff remain
implemented. R7's focused pilot and broader 48-call routing comparison are complete;
the candidate worsened required-role omissions, so production guidance is retained.
R9's main mechanisms and offline verification are complete, but this review
identifies **open evaluator failure-body
capture and simultaneous-failure evidence gaps**. Its blanket DONE claim is narrowed
below. The two subsequently authorized R4/§8 projection follow-ups are now
implemented: selected repair tasks survive every assignment shape, and completed
entity source review reuses the resolved business subject. Their implementation
and offline verification do not establish improved live model outcomes.
The authoring-input follow-up is also implemented and offline-verified (§9.11):
resolved requirements, concise active instructions and native singleton exact
references reduce work requested from the model. Live benefit remains unmeasured.

The remaining brittleness is principally semantic selection and review reliability,
repeated whole-context review cost, and incomplete answer recovery. The inspected
changes do not establish a new fixture-specific production workaround or weakened
success rule. They also do not remove those existing weaknesses. See [§9](#9-post-implementation-architectural-reassessment--9-october-2026)
for current findings, evidence limits and the proposed next work. The dated analyses
below remain historical; §9 supersedes their current-status claims where noted.

This review and tracking document introduces no engine policy, new test authority
or live-run authorization. The original review changed only this file; folder
cleanup is recorded in §8. The user subsequently authorized the bounded R3, R4,
R7, R9 and R10 work. Their implementation, calibration and verification are tracked
below. The reassessment itself changed only FIX01. The subsequent user instructions
authorized the two R4/§8 projection follow-ups, then the prepared 48-call routing
comparison and an evidence-supported production change. The comparison supports
retaining baseline guidance; it supplies no policy amendment or E2E authorization.
The subsequent complete-role-decision proposal is critically reviewed in
[§9.8](#98-complete-role-decisions-critical-review--9-october-2026). The user then
explicitly authorized its coordinated implementation and the §17/ADR amendments.
The mechanical cutover and comparison are tracked in
[§9.9](#99-complete-role-decision-implementation--9-october-2026). The prepared
48-call diagnostic comparison was subsequently approved explicitly; it grants
no whole-workflow E2E invocation.
The subsequent user-reported E2E failure is analysed in §9.10. That analysis changes
only this document and runs no new E2E or diagnostic model calls.
The subsequently requested authoring-input simplification is implemented in
[§9.11](#911-authoring-input-simplification--9-october-2026); it is an engineering
change with offline verification, not a demonstrated live semantic improvement.

**Material revisions:** corrected overstatements about the handoff and current
traceability, completed the clarification-path audit, separated implementation
feasibility from semantic reliability, and added a research-backed evaluation
method with explicit measurement limits. The current reassessment adds inspected
post-R9 evidence, corrects stale live/status statements, identifies missed sibling
and failure paths, and separates engineering progress from unproved product benefit.
Automatic upstream correction remains a separate policy decision.

## 1. Scope, baseline and evidence

The reviewed input is the pasted **“Spec workflow improvement handoff — revised
findings”**, supplied as `Pasted text.txt`. Its SHA-256 is
`2e0ce419e2f4e2022f029fc5526c9a347c9a83b025510359b7a8beab40ae6cbe`.
The pasted document is a proposal, not governing authority. Its instruction to
update FIX_003 and its task list describes future implementation work; this
review does not execute that instruction.

The handoff cites commit `cfb9873b5e2905a1f838c0757728f5e0170d0f4d`.
That object is unavailable in the local repository: `git cat-file -t` fails.
Its ancestry and exact contents could not be verified and were not fetched.
The original code assessment instead used HEAD
`3bcba773a28cfc65b5d4de5cdba870fc5feb2b46` and its working tree. The subsequent
R3 outcome analysis inspected HEAD `e0b86d15bf6e18927ac67d4c5bca3105056ff8b9`;
the worktree was clean before this documentation update.
The subsequent R4 analysis inspected HEAD
`3be4b5f1c359268996bb399b68bcf386d02ad6c7`; the staged R4 implementation was
preserved, and this analysis changes only FIX01.
The subsequent R4 implementation preserves those staged changes and adds the
bounded input projections recorded below.
The subsequent R10 evidence update preserves that staged implementation and
changes only this document; it authorizes no implementation or live execution.
The subsequently authorized R10 implementation preserves those staged changes
and implements the existing blocking option without adding automatic rework.

The current critical architectural review inspected clean HEAD
`073da87ea432e2e8c596a5c2a299fe19516a7d06`, the present code and the three locally
retained 9 October E2E bundles. Only this document is edited by the review.

Before the original review, the worktree contained an integration/build refactor in
`README.md`, `build.zig`, `build.zig.zon`, `build/test_registration.zig`,
`integration.zig`, `scripts/test-integration.sh`, `src/architecture_test.zig`,
`src/composition/root.zig`, `tests.zig` and untracked
`test/integration/workflow_tests.zig`. Those changes were preserved. Historical
test counts describe those dated implementation checks, not a fresh verification
performed during this documentation review.

Authority consulted:

- [AGENTS.md](../AGENTS.md): shared ownership, untrusted model candidates,
  separation of test layers and explicit live-run approval.
- [Design §§1, 3–4, 30–31](../design/design.md): concrete semantic assignments,
  deterministic enforcement, complete authority, atomic publication and acceptance.
  The governing design remains **Proposed design**, as amended by accepted ADRs.
- [§12](../design/contracts/12-model-boundary.md),
  [§17](../design/contracts/17-specify.md),
  [§21](../design/contracts/21-validation.md),
  [§22](../design/contracts/22-repair.md) and
  [§28.8](../design/contracts/28-testing.md#288-model-conformance-comparisons).
- [ADR 0011](../design/decisions/0011-provider-owned-request-limits.md),
  [ADR 0015](../design/decisions/0015-specification-principle-review.md),
  [ADR 0020](../design/decisions/0020-derived-exact-reference-lineage.md),
  [ADR 0021](../design/decisions/0021-optional-source-preservation-review.md) and
  [ADR 0022](../design/decisions/0022-native-reference-phase-handoffs.md).
- [FIX_003 §15](archive/FIX_003.md#15-latest-evidence-and-critical-review--8-october-2026) and
  [FIX_002's reassessment decision](archive/FIX_002.md#d2--reassessment-of-a-structurally-admitted-source-finding).

The most recent retained run started 9 October at **17:31:50 AEDT**
(`2026-10-09T06:31:50Z`), after the complete role-decision implementation. Six
9 October bundles are now locally inspectable, starting at 11:53:40, 13:01:41,
14:39:42, 15:19:22, 15:44:10 and 17:31:50 AEDT. Earlier R3/R4 and loan bundles
referenced below are no longer present in this checkout; their findings are retained
as dated review history, not independently revalidated raw evidence in this review.

| Evidence | Confirmed result | What it establishes |
| --- | --- | --- |
| [8 October, 18:35 run](../zig-out/e2e-spec/2026-10-08T07-35-30Z-7107d1f32946458299ddf2447658f947/report.json) | 37 exchanges; 105,405 / 100,000 tokens; no publication or rubric result. | The prior workload exceeded its execution budget. |
| [8 October, 20:52 run](../zig-out/e2e-spec/2026-10-08T09-52-37Z-975dd393a88db44ce1b06fb0f92fc8f4/report.json) | 39 exchanges; 101,476 / 100,000 tokens; no publication or rubric result. | Call 35 lacked final text; call 36 recovered JSON; call 39 hit the budget before admission. |
| [Pre-R3 call 36](../zig-out/e2e-spec/2026-10-08T09-52-37Z-975dd393a88db44ce1b06fb0f92fc8f4/evidence/generation/call-000036/model_output.txt) | Admitted explanation treats internal `feature: singleton` as a “singleton implementation.” | Structurally admitted review can assess invented product meaning. |
| [9 October, 07:59 run](../zig-out/e2e-spec/2026-10-08T20-59-10Z-043b83091ff4ee6016e285ca11a2af0c/report.json) | 37 exchanges; 105,735 / 100,000 tokens; seven policy findings admitted; no publication or rubric result. | R3's resolved inputs are in use; call 37 stops on budget without a correction retry or repair. |
| [9 October, 08:34 post-R4 run](../zig-out/e2e-spec/2026-10-08T21-34-58Z-08faa42fc180e22e11a0e27cd7f459d0/report.json) | 34 exchanges; 59,850 / 100,000 tokens; `workflow_invalid` at omission authorization; no policy review, publication or rubric result. | Shared meanings reached generation and source review, but call 12 omitted functional requirements and the positive source review did not supply an eligible omission repair. |
| [9 October, 09:07 run](../zig-out/e2e-spec/2026-10-08T22-07-58Z-81991f12973d8466095855fd3d3399e0/report.json) | 8 exchanges; 12,148 / 100,000 tokens; `workflow_failed` at generation initialization; no specification authoring, review, publication or rubric result. | Call 7 omitted `entity_basis` with byte-identical inputs to the preceding run; R10 traces the incomplete binding and generic failure. The latest R4 projections were not exercised. |
| [9 October, 11:53 post-R10 run](../zig-out/e2e-spec/2026-10-09T00-53-40Z-ab59e9144c1aff2ce96a9816c782f782/report.json) | 8 exchanges; 12,123 / 100,000 tokens; `workflow_blocked` at generation initialization; no authoring, clarification, repair, publication or rubric result. | R10 retains missing `entity_basis`, source state/revision, eligible groups and call 7's origin. The same role omission persists; explicit handling improves, completed-spec outcomes do not. |
| [9 October, 13:01 pre-R9 run](../zig-out/e2e-spec/2026-10-09T02-01-41Z-2abaff5b6f3e0d8e0604e340f9cfdcaa/report.json) | 31 exchanges; 54,298 tokens; `workflow_failed` at `g14-g6-review-omit-merge`; native cause rendered as `failed`. | Call 7 supplies all six roles under the same request used by the two blocked runs. The workflow reaches authoring and repair but still publishes no specification or rubric result. The thrown merge cause is unrecoverable from this old report. |
| [9 October, 14:39 post-R9 run](../zig-out/e2e-spec/2026-10-09T03-39-42Z-932157c58a866f39133651ca3f3e8bbb/report.json) | 8 exchanges; 12,123 tokens; `workflow_blocked` at `g8-generate-initialize-specification`; first captured defect at event 231; no authoring, repair, publication or grading. | Missing `entity_basis` is correctly attributed to call 7 rather than the latest exchange, call 8. All eight contexts, serialized requests and projected outputs match 11:53 byte-for-byte. R9 improves evidence on the reached path; it neither changes nor repairs the role omission. |
| [9 October, 17:31 post-role-contract run](../zig-out/e2e-spec/2026-10-09T06-31-50Z-d8b1413594de14f45b366c7242397e2e/report.json) | 55 exchanges; 100,043 / 100,000 tokens; `WorkflowTokenBudgetExceeded` during the second source review; no publication or rubric. | Calls 7 and 31 supply all six roles. Call 10 loses narrative meaning; call 17 selects an intact reconciliation signal for repair. Regeneration corrects the story but introduces literal-only records at call 35. Identical story request bytes produce different answers; §9.10 traces the shared boundaries and causal limits. |
| [Loan run](../zig-out/e2e-spec/2026-10-07T11-57-52Z-935b3be1a46109edb237ebb287867251/report.json), analysed in [FIX_003 §14.5](archive/FIX_003.md#145-three-approved-live-executions-after-fix3-0910) | An omission/localization sequence led to insertion of already-captured behavior and dependent rebuilding; terminal budget exhaustion. | Incorrect semantic premises can consume valid repair machinery. |

Both 8 October reports identify modified builds at revision
`dd5e6e80169c1c0ba359ca9951e222654e7edc6c`, with different source hashes.
The 07:59 report identifies a modified build at revision
`b021e9bfaeda53c6cda8c9896342a4776f77234b`, source hash
`65fe4bb339e123f961c991d8a598c5def7c72519b1baaf7a3fd365f217b8b14e`.
The 08:34 report identifies a modified build at revision
`3be4b5f1c359268996bb399b68bcf386d02ad6c7`, source hash
`cc09cc3999e374a0648ba243ca6b8c9be3413505673b43b639d13bd81faa1cc4`.
The 09:07 report identifies the same revision with a modified build, source hash
`d953c9cf8d0d7ffe431308802310f8667f78800882d339e7bc999c28c948bfe9`.
The 11:53 report identifies the same revision with a modified build, source hash
`e4e3ac20bf56d8c4c8c57a9f23994db2d8c161afe5f003e7366035feca4e4628`.
These are different captured builds, not a controlled comparison of one code
change. Captured request bytes independently establish the R3 and R4 projections
in the respective runs; R10 distinguishes unchanged requests from changed builds.

Call numbers are physical exchanges in those specific runs, not stable operation
identities. The exact provider-side cause of reasoning-only output is unknown.
The existing missing-answer correction worked in the 8 October, 20:52 run; accepting
reasoning as the answer would not address the observed semantic or workload gaps.

## 2. Validation of the handoff's central claims

| Handoff claim or proposal | Assessment against current code |
| --- | --- |
| Keep the generic engine and give the model precise semantic tasks. | Supported by the governing design. The evidence does not justify replacing the engine or moving Spec policy into the generic runner. |
| Small calls and valid IDs/citations do not guarantee correct meaning. | Confirmed. Call 36 and the loan omission sequence demonstrate the distinction. |
| Construct known IDs, joins and citations natively. | Substantially implemented. Preserve and audit the current owners; this is not a missing subsystem. |
| Require more than a document-level source citation. | Sound objective; current code already retains claim-to-span traceability. The remaining issue is whether each record's inherited claim set precisely describes its support. |
| Use stable location-based source-requirement identities. | Underspecified. Existing identities are snapshot-bound; location does not determine semantic segmentation or continuity across edits. |
| Define record-family contributions. | R4 implements shared meanings for all nine existing families, replacing generic and duplicated guidance. Semantic calibration remains R7 work. |
| Resolve policy assignments before asking the model. | R3 now implements scalar, record, collection and entity projections. Retained post-R3 policy packets confirm resolved business subjects; semantic reliability remains unproven. |
| Keep small calls as the default; group only with evidence. | Consistent with §12.5. A requirement cluster can be one responsibility; no fixed call size guarantees semantic reliability or budget feasibility. |
| Require evidenced, scoped repair. | Mostly present mechanically. Correctness of the admitted semantic premise remains unproven. New reconsideration would change accepted policy. |
| Add isolated semantic evaluation before full E2E. | Appropriate, and already contemplated by §28.8. Whole-spec rubric calibration alone does not evaluate production generation and review assignments. |
| Do not equate a zero exit code or completed score with quality acceptance. | Confirmed by the harness. It deliberately reports command completion separately from quality thresholds. |
| Improve causal diagnostics and reproducibility. | Supported. Much capture already exists; native cause loss and missing source bytes cannot be fixed only in the final report renderer. |

The revised principle should refer to **registered, accepted contracts and
supported configuration**. Workflow/toolchain configuration selects supported
policies; it cannot redefine invariants or create new validator capabilities.
Keeping implementation checks out of the business-writing task does not authorize
skipping required bootstrap, policy or publication gates.

## 3. Detailed code findings

Priorities reflect risk to the proposed outcome. A measurement gap or proposed
contract change is not automatically a defect in the currently accepted contract.

### R1 — Medium: group attribution does not establish precise per-record support

[specification_source_binding.record](../src/domain/specification_source_binding.zig#L93)
binds one records task to one accepted reconciliation group's complete selection.
[Generation parsing](../src/domain/specification_generation.zig#L77) assigns that
same selection to **every record returned by the task**. Native
[provenance](../src/domain/specification_provenance.zig#L82) then validates current
claims and constructs the exact citation union. The
[reference owner](../src/domain/reference_support.zig#L42) retains claim-to-citation
occurrences, and [rendering](../src/domain/reference_context.zig#L75) can expose
precise source spans.

Thus traceability is not absent or merely document-level. A group containing
claims A and B can produce records X and Y that both inherit A+B, even if X's
wording expresses only A and Y's only B. Those links establish the record's bound
evidence group; they do not establish that every linked claim is expressed by, or
individually entails, that record. Minimal support sets are not a current invariant.

This behavior follows the accepted
[ADR 0020 provenance-free amendment](../design/decisions/0020-derived-exact-reference-lineage.md#provenance-free-response-amendment-approved-27-september-2026):
one multi-claim group may produce several records; generated responses omit
provenance, and reassociation belongs to upstream rework. Reintroducing per-record
model-selected claim subsets would change that contract.

**Required clarification for package 2:** define whether the intended trace means
the bound evidence group or a semantically selected record-specific support set.
Do not label accepted group attribution a contract violation or require minimality
without a demonstrated need. First measure whether better semantic grouping within
the existing contract is sufficient. If it is not, choose and approve a narrower
assignment/selection contract once at the owning boundary. Thread it through generation, positive
review, value repair, omission insertion, canonical readback and rendering. Do not
add an independent traceability store or infer support from matching text.

**Feasibility:** high for auditing and presenting existing links; medium for
changing their granularity because of the coordinated contract surface. The
[existing trace test](../src/specification_generation_test.zig#L5358) constructs
separate record selections directly. It establishes representability/rendering,
not that production generation chooses the correct supporting subset. Acceptance
needs the actual reconciliation → binding → wire parsing → review → readback path.

### R2 — High: original-reference completeness and identity need narrower claims

[specification_coverage](../src/domain/specification_coverage.zig#L48) checks the
mapping of retained extracted claims and exact-token obligations. It cannot count
a requirement whose meaning was never extracted. Broad inherited selections can
also make a claim count as mapped while the generated prose omits its meaning.
The handoff correctly separates semantic evaluation from mechanical accounting;
its requirement to account for “every in-scope source requirement” needs that same
qualification throughout implementation acceptance.

[Source preservation](../src/domain/source_preservation.zig#L7) and the existing
source/omission review supply the semantic comparison. The optional pre-generation
check remains governed by ADR 0021; this proposal cannot silently make it mandatory
or replace it with a second coverage ledger. Existing disposition policy also
cannot be widened into an arbitrary “out of scope” exemption for business claims.

[Reference identities](../src/domain/reference_identity.zig#L11) are native ordinals
within a reference snapshot; `stateId` intentionally creates a fresh namespace.
Source coordinates locate captured bytes. They do not prove that an unnumbered
paragraph is exactly one requirement or that a requirement survives an edit with
the same identity. Any persistent semantic requirement identity needs an explicit
continuity/currentness contract, not just an ID derived from a line number.

The universal original-reference wording also needs to preserve accepted
clarification authority. [§17.3](../design/contracts/17-specify.md#173-llm-work)
permits current resolved clarification-response support without invented reference
citations. Derived titles, goals and stories need supported meaning, not a matching
prewritten source heading or sentence.

**Additional confirmed gap: the registered Spec path does not complete the answer
lifecycle.** Static tracing establishes the following:

- [Workflow preparation](../design/workflows/spec.workflow.yaml#L243) captures,
  parses and validates forms, then proceeds to reference preparation. It has no
  answer acceptance or resolution stage.
- [Form validation](../src/actions/clarification/validate_clarification_forms.zig#L37)
  preserves existing recorded responses; a fresh close becomes `.submitted`.
  [Refresh](../src/domain/clarification_refresh.zig#L31) rejects every fresh
  nonempty submission with `AuthenticationRequired`. Its remaining work copies
  history and opens/reopens needs, not authenticating or appending responses.
- The named [resolved-needs action](../src/actions/clarification/build_resolved_clarification_needs.zig#L5)
  constructs empty needs; it does not resolve an answered record.
- [Generation context](../src/domain/specification_provenance.zig#L9) and
  [packet construction](../src/domain/specification_session.zig#L103) have no answer
  input. Native bindings use empty response-ID sets, and
  [provenance resolution](../src/domain/specification_provenance.zig#L84) rejects
  nonempty sets. Already-recorded answers are not supplied as generation support.

This is incomplete implementation of accepted
[§17.4 answer handling](../design/contracts/17-specify.md#L362), which requires
authenticated submission, response publication, refresh and current resolution.
It also contradicts the usable rerun path implied by the
[CLI message](../src/main.zig#L35). It does **not** explain the latest budget failure
and must not be folded into the bounded policy-projection change.

The existing [clarification tests](../src/clarification_inputs_test.zig#L77)
establish preservation of prebuilt recorded answers and rejection of fresh closes,
not authenticated answer-to-generation completion. Completing the lifecycle also
affects passive text: [passive_literals.Origin](../src/domain/passive_literals.zig#L16)
currently represents source coordinates only, while §17.4 requires response-owned
passive occurrences. Scope this as separate shared lifecycle work. Establish the
concrete authentication and current-applicability contracts before implementation;
do not treat loaded forms as authenticated or manufacture reference citations.

**Feasibility:** reuse the existing snapshot, provenance and coverage contracts.
Do not promise native proof of original semantic completeness. A new persistent
source-requirement registry would materially expand scope and is not justified by
the current evidence. Full answer-supported generation is a separate cross-cutting
completion dependency, not a small provenance-field patch.

### R3 — COMPLETE: resolve the assigned policy-review subject

**Status — 9 October: COMPLETE.** All R3 implementation items are implemented
and verified offline. The subsequent live run confirms use of the new projection
and a narrow improvement in assignment interpretation; it does not establish
successful E2E execution or calibrated semantic accuracy.

At the review baseline,
[principle_assessment.packet](../src/domain/principle_assessment.zig#L82) sent one
raw `required_authority.Id` alongside the entire brief/candidate, entity basis and
selected policies. The model had to infer which business content that tuple denoted.
Pre-R3 call 36 supplies concrete evidence of the resulting metadata/content confusion.

**Implemented boundary:** the shared
[review-subject owner](../src/domain/specification_review_subject.zig#L51) resolves
policy assignments through
[specification_authority.projectRecords](../src/domain/specification_authority.zig#L44)
and the same canonical field lenses used by source review. Each packet contains
`task`, resolved `subject` and the unchanged
selected `principles`, rather than a native requirement tuple. Scalar subjects
carry displayed text; record subjects retain their business record ID and every
resolved sibling. Collection subjects identify the assessed slot; entity subjects
carry their disposition and resolved basis. Every subject retains the complete
resolved brief, candidate and entity basis as supporting context, because arbitrary
principles can compare requirements. Canonical provenance remains native authority.

The existing document projector supplies resolved record siblings and aggregate
context, retaining its complete business-view validation even for focused
packets; no second scalar resolver or family registry is introduced. Policy inputs
use their `context.business` view, without importing the source subject's
source-support instruction. Shared record descriptions are purpose-neutral; the
source and policy prompts own their respective review instructions. Initial
review, correction, finding insertion and detail/citation repair use the same
[packet dispatcher](../src/domain/specification_support.zig#L112). Selection,
cardinality, request/subject/revision binding, admission, verdict retention,
continuation and persistence are unchanged. R4's separate family-purpose
implementation is recorded below.

Regression coverage includes two unrelated business domains, literal/exact/passive
values, all nine record families, resolved conditions and entity relationships,
both applicability outcomes, legitimate “singleton” prose, foreign assignment and
invalid provenance and malformed candidate rejection, allocation failures, and
matching initial, correction, insertion and detail/citation-repair subjects. The
offline workflow driver identifies policy requests by their retained result
definition rather than the obsolete string-shaped subject.

**Verification:**

| Command | Result |
| --- | --- |
| `zig build test-specification-generation --summary all` | 252/252 passed on the final projection, including allocation-failure checks. |
| `zig build test-specification-generation test-required-authority --summary all` | 401/401 passed during iteration. |
| `zig build test-model-request-workflow test-architecture lint --summary all` | 441/441 passed; lint passed. |
| `zig build verify --summary all` | Final run: 129/129 steps and 1318/1318 tests passed, including separate offline integration, architecture and clean packaging checks. |

The first full run passed all tests but hit sandbox restrictions in two nested
Zig builds and a packaging smoke check. Full verification passed with the required
host access; no check or assertion was weakened. `git diff --check` and local
documentation-target/line-anchor checks also passed. Concurrent `build.zig`
changes are outside R3 and were preserved during verification.

**Live outcome analysis — 9 October:** compare semantic assignments, not physical
call numbers. The pre-R3 description assignment was call 35, followed by correction
call 36; the same description is assigned to
[latest call 31](../zig-out/e2e-spec/2026-10-08T20-59-10Z-043b83091ff4ee6016e285ca11a2af0c/evidence/generation/call-000031/context.json).
Its input now contains:

```json
{
  "task": "A description of intended user-visible behavior.",
  "subject": {
    "kind": "field",
    "slot": "description",
    "text": "The application must start successfully, display the text \"Hello, World!\", and output the current date and time in UTC."
  }
}
```

This excerpt omits the retained complete business context and selected principles.
The native `feature: singleton` tuple is absent. None of the seven admitted policy
findings repeats the earlier invented “singleton implementation.” This confirms
removal of that input ambiguity in this run. The display-name value is also
unchanged between baseline call 34 and latest call 30; the later goal, story and
acceptance-criterion wording changed upstream, so those are not identical-input
comparisons.

The [latest description response](../zig-out/e2e-spec/2026-10-08T20-59-10Z-043b83091ff4ee6016e285ca11a2af0c/evidence/generation/call-000031/model_output.txt)
still claims the application uses a single process, maintains no state and adheres
to Node.js/TypeScript. Those are policies, not implemented facts established by
the business description. Similar overclaims appear in calls 32, 33 and 36.
Compatibility may be reasonable; the explanations do not prove implementation
compliance. Whole-chunk citations remain broad, and call 36 asserts compliance
across seven categories while citing only architecture/core. These are remaining
semantic-quality concerns under R7 and §17.3.1, not evidence that R3's projection
is incomplete or that any particular compatible verdict is necessarily false.

There is also an earlier, separate candidate-quality issue:
[call 11](../zig-out/e2e-spec/2026-10-08T20-59-10Z-043b83091ff4ee6016e285ca11a2af0c/evidence/generation/call-000011/model_output.txt)
returned `not_applicable` entities with a basis resolving only to `Hello, World!`.
That literal does not explain why entities are unnecessary, despite the supplied
guidance distinguishing a literal from an explanation.
[Call 28's assignment](../zig-out/e2e-spec/2026-10-08T20-59-10Z-043b83091ff4ee6016e285ca11a2af0c/evidence/generation/call-000028/context.json)
was entity applicability, but its
[admitted response](../zig-out/e2e-spec/2026-10-08T20-59-10Z-043b83091ff4ee6016e285ca11a2af0c/evidence/generation/call-000028/model_output.txt)
justified matching functional requirements instead. The source-review aggregate
subject still uses `candidate_support`; R3 changed the policy projection, not this
source-review path. Retain this as an R7 generation-and-review evaluation case;
R4's shared meanings do not establish that the model interprets them correctly.
It is not an established cause of the terminal budget failure.

Both runs used the same case, reference, principle chunks, response schema and
configuration: Bedrock `openai.gpt-oss-20b-1:0`, low reasoning and temperature 0.
Among captured input files only `principle.prompt.md` changed, but builds and
generated candidates differ. The latest run also needed no correction retry;
known raw opening-prefix defects were normalized without a new model call. This
does not establish that R3 eliminated provider-format defects. A single uncontrolled
run pair, with no conflicting-policy cases or completed rubric, cannot establish
accuracy or repeatability. R3 remains implementation-complete; R5 workload and R7
semantic acceptance remain open.

### R4 — Explicit, shared record-family meanings

**Status — 9 October: COMPLETE for shared meanings and the authorized projection
follow-ups, including the two later gaps in §9.2.** Semantic calibration remains
R7 work. The 08:34 run below predates the earlier follow-ups; the 09:07 run stopped
before their affected calls (R10). Neither establishes their live improvement;
offline verification is recorded separately, with the latest changes in §9.6.

**Current review qualification:** the nine shared meanings remain implemented.
The cross-path audit found a separate selected-task projection defect for active
brief repairs, and an unresolved entity subject in source review. Both are now
implementation-complete under R4/§8; see §9.2 and §9.6 for the bounded changes and
verification. The clarification lifecycle and R9 evidence findings remain open.

The original gap was one generic `.text` description for several different
families, a records role describing only functional requirements and acceptance
criteria, and partial definitions repeated in the prompt. The handoff also omitted
`edge_case` and `entity` from the nine existing
[Kind variants](../src/domain/specification.zig#L9).

**Implemented owner:**
[required_authority_description](../src/domain/required_authority_description.zig)
now supplies family and field meanings, a selected-field task and whole-record
catalogues. Field membership reuses the existing native authority predicate;
catalogue field names derive from the canonical `Content` shape. No second kind,
field-membership or requiredness registry was introduced. User-visible outcomes
describe observable results/responses; business rules describe governing rules or
constraints. Assumptions, exclusions and prohibitions retain distinct meanings.

The existing [generation role](../src/domain/reference_reconciliation.zig)
projects all nine families and their fields into the bound source assignment.
The [records prompt](../design/workflows/spec/records.prompt.md) retains authoring
instructions, support/role preservation, legitimate requirement/criterion overlap
and the fixed entity decision; its duplicate family definitions were removed.
Focused source and policy review, correction, finding insertion and selected
detail/evidence repair reuse the same `task` owner. Their respective prompts still
own source support and policy assessment instructions.

[Native repair](../src/domain/specification_repair.zig) derives its field or
permitted-family purpose from the authorized target. The
[session packet owner](../src/domain/specification_session.zig) replaces the broad
authoring purposes with one explicit selected `task` for every repair shape while
preserving its source selection. It does not repeat the full catalogue or add a
second copy of the selected task. Initial authoring guidance remains unchanged.
[Reviewed omission repair](../src/domain/specification_coverage_repair.zig)
supplies the selected field or inserted family directly. Completed units retain
`source_assignment: null`; their repair task does not revive a consumed authoring
assignment. The superseded `packetForChoices` entry point was replaced by the
single options-based packet builder, preserving exact-choice restriction behavior.

Coverage exercises all nine families and every field/relationship across two
unrelated mock domains, generation, native value and membership repair, completed
omission value/insertion repair, and source/policy initial, correction, insertion,
detail and evidence repair. Allocation-failure coverage exercises the shared
descriptions. Negative cases reject invalid family/slot pairs and preserve ordinary
repair/provenance checks. Sparse required-family content remains accepted, and
identical wording across kinds remains structurally allowed. These tests establish
guidance delivery and unchanged native enforcement, not semantic correctness of
the mocked content.

Optional families remain optional. Entity applicability, native IDs, provenance,
schemas, cardinality, repair targets, retry allowances and continuation policy keep
their existing owners. No semantic reclassification, cross-kind deletion,
redundancy-review call or additional model call was added. Human-labelled cases
under R7 still need to distinguish useful records from unsupported repetition;
R5's observed token-budget failure remains separate.

**Original shared-definition verification — 9 October:**

| Command | Result |
| --- | --- |
| `zig build test-specification-generation test-required-authority --summary all` | 403/403 passed: generation 253, required authority 150. |
| `zig build test-model-request-workflow test-reference-reconciliation test-architecture lint --summary all` | 554/554 passed; lint passed. |
| `zig build verify --summary all` | 130/130 steps and 1320/1320 tests passed, including separate offline integration, architecture, formatting and clean packaging checks. |

Sandbox access to the compiler standard library and global cache required host
access; no validator, assertion or check was weakened.
`git diff --check`, 132 local documentation links with 84 heading/line anchors,
and parsing of the changed JSON context passed. The complete diff was reviewed
for scope, duplicate authority, obsolete paths and weakened enforcement. No live
E2E invocation was made during implementation. The subsequently retained run is
analysed below; calibrated model-quality improvement remains unestablished.

#### Post-R4 live outcome — 9 October, 08:34 AEDT

**Conclusion: guidance delivery improved; the run did not demonstrate a better
workflow outcome.** The
[records request, call 12](../zig-out/e2e-spec/2026-10-08T21-34-58Z-08faa42fc180e22e11a0e27cd7f459d0/evidence/generation/call-000012/context.json)
contains all nine shared meanings and structured field purposes. Calls 21–29
also carry the acceptance-criterion family plus selected-field purpose. Policy
review and atomic repair were not reached, so this run supplies no live evidence
for those R4 paths.

The initiating candidate defect is visible in
[call 12's output](../zig-out/e2e-spec/2026-10-08T21-34-58Z-08faa42fc180e22e11a0e27cd7f459d0/evidence/generation/call-000012/model_output.txt):
three acceptance criteria cover startup, greeting and UTC output, but there are
**zero functional requirements**. The immediate baseline returned one acceptance
criterion and three functional requirements. Required family coverage regressed;
the behavior still appears elsewhere, so this is not proof that the source's UTC
meaning disappeared.

The failure chain is:

1. **Generation, call 12:** the missing family passes per-group field/duplicate
   validation. Its response schema allows the record variants without an aggregate
   family-presence constraint.
2. **Source review, call 19 (logical request 18):** the
   [assigned functional-requirement task](../zig-out/e2e-spec/2026-10-08T21-34-58Z-08faa42fc180e22e11a0e27cd7f459d0/evidence/generation/call-000019/context.json)
   receives the whole candidate as `candidate_support`. Its
   [response](../zig-out/e2e-spec/2026-10-08T21-34-58Z-08faa42fc180e22e11a0e27cd7f459d0/evidence/generation/call-000019/model_output.txt)
   says `supported` because the behaviors occur in acceptance criteria and the
   story. That judgment does not establish a populated functional-requirement
   collection. All 20 source findings ultimately say `supported`.
3. **Native gate:**
   [specification_authority](../src/domain/specification_authority.zig#L67)
   retains the engine-observed missing-family defect despite positive review.
   [Events](../zig-out/e2e-spec/2026-10-08T21-34-58Z-08faa42fc180e22e11a0e27cd7f459d0/events.jsonl)
   652–653 record an invalid gate; event 655 records invalid omission authorization
   at `g14-g6-review-omit-authorize`.
4. **Repair cannot be authorized:** a native absence has `support: null` until a
   current `candidate_omission` supplies eligible evidence through the
   [shared candidate-defect owner](../src/domain/required_authority.zig#L449).
   [supportedOmission](../src/domain/required_authority.zig#L489) therefore supplies
   no repairable evidence, and
   [authorizeOmission](../src/domain/specification_coverage_repair.zig#L125) has no
   eligible insertion. Its code returns `UnsafeSpecificationOmissionRepair` in
   this case; the binding collapses domain errors to `invalid`. The report does
   not retain the exact Zig error or missing requirement, so this explanation is
   code-traced rather than a captured native diagnostic.

The last exchange, call 34, returned a supported exact-token finding; it was not
the initiating defect. The first protocol failure was call 14's reasoning-only
answer; call 31 had the same missing-final-answer condition. Existing corrections
recovered them at calls 15 and 32. Neither caused the terminal rejection. No
semantic repair, clarification, policy review, publication or rubric ran.
Call 11's entity basis remains the literal `Hello, World!`, unchanged from the
baseline; its source review again cites general behavior rather than explaining
entity applicability. That earlier R7 concern is not resolved by R4.

| Observed workload | Pre-R4, 07:59 | Post-R4, 08:34 |
| --- | ---: | ---: |
| Acceptance criteria / functional requirements | 1 / 3 | 3 / 0 |
| Record-field review assignments | 6 | 9 |
| Reference preparation and generation tokens | 19,103 | 19,374 |
| Distinct source findings / physical source calls | 17 / 17 | 20 / 22 |
| Source-review tokens | 32,317 | 40,476 |
| Policy calls / tokens | 8 / 54,315 | 0 / 0 |
| Total calls / accounted tokens | 37 / 105,735 | 34 / 59,850 |
| Terminal result | Token-budget failure | Invalid candidate; repair not authorized |
| Publication / rubric | Not reached / not run | Not reached / not run |

Fewer records created **more fields and source-review work**. The lower whole-run
total reflects stopping before policy review, not a demonstrated cost reduction.
Both runs use the same case, source, configuration, model settings, principle
chunks and evaluator settings. Among captured input files only `records.prompt.md`
and `generation.context.json` changed; compiled code/build identity and generated
text also differ. This single uncontrolled pair shows the observed regression,
but cannot isolate R4 as its cause or establish a success rate.

**Bounded follow-ups implemented after this run:**

- **Project existing requiredness alongside meanings.** The
  [session packet owner](../src/domain/specification_session.zig) now supplies
  `record_requirements` with `assembled_specification` scope and mandatory
  families from [the canonical specification contract](../src/domain/specification.zig#L51).
  The records prompt explains aggregate scope without repeating the family list.
  Bound source groups may supply different families; their schemas and admission
  checks impose no new per-group floor. Atomic repairs omit this aggregate
  authoring guidance and retain only their authorized task.
- **Resolve source collection assignments explicitly.** The shared
  [review subject](../src/domain/specification_review_subject.zig) now carries
  `collection.slot`, selected resolved `records` (including `[]`) and the complete
  business context. Source and policy reviews reuse that projection. Selection and
  [source-evidence aggregation](../src/domain/specification_support_evidence.zig)
  use one [native collection lens](../src/domain/specification_authority.zig),
  preserving AC/FR membership and the existing AC/edge-case/outcome scenario set.
  The source prompt distinguishes selected records from surrounding context.
  Initial/correction/insertion/detail/evidence requests retain the same source
  evidence and currentness rules. Partial pre-authoring assessments and separate
  dependency localization retain their existing projections.

The [aggregate-generation regressions](../src/specification_generation_test.zig#L820)
and [collection regressions](../src/specification_generation_test.zig#L4364) use
unrelated mock domains, split-family source groups, optional omissions, explicit
populated/empty collections despite matching prose elsewhere, legitimate
criterion/requirement overlap, and all nine kinds against the shared collection
lens. Disjoint per-family claims verify evidence selection independently; source
catalogues remain intact through correction and review repair. The tests preserve
rejection of missing mandatory families, invalid collection slots and repair based
only on a positive finding. No response schema, model call, retry allowance or new
recovery route was added.

**Follow-up verification — 9 October:**

| Command | Result |
| --- | --- |
| `zig build test-specification-generation test-required-authority --summary all` | 405/405 passed: generation 255, required authority 150. |
| `zig build test-model-request-workflow test-reference-reconciliation test-architecture lint --summary all` | 554/554 passed; lint passed. |
| `zig build verify --summary all` | 130/130 steps and 1322/1322 tests passed, including 84 separate offline integration tests and clean native packaging checks. |

Compiler/cache access and packaging checks used host access. The complete staged
and unstaged diff was reviewed for scope, duplicate authority, obsolete paths and
weakened enforcement. `git diff HEAD --check`, local documentation targets/anchors
and JSON context parsing passed. These are offline contract checks, not semantic
quality evidence.

The missing-family guard and refusal to invent repair evidence are correct safety
behavior. Native absence proves cardinality, not which source group supports a
replacement. Any new recovery from native-only absence requires a separate
evidence/authorization decision under R6; do not convert `supported` to omission,
clear the native defect, insert arbitrary filler or add a caller-local fallback.
Existing [mandatory-family negative tests](../src/specification_generation_test.zig#L1657)
already prove that an AC-only candidate remains invalid after positive review
across unrelated sources; the
[omission-repair tests](../src/specification_generation_test.zig#L4017) deliberately
reject insertion based only on that positive review. Passing offline checks are
therefore consistent with this live failure: they verify enforcement, not that
the model authors both families or recognizes the missing collection.
R4's shared meanings and these bounded projections are implementation-complete.
Successful live output, R5 workload feasibility and R7 semantic calibration remain
open. The retained failure is evidence for the pre-follow-up build, not a live
validation of the new inputs. No live E2E run was invoked during implementation.
The subsequently retained 09:07 run failed before authoring or review, so it also
leaves these inputs' live effect unmeasured; see R10. Its lower usage reflects an
earlier stop, not improved quality or efficiency.

### R5 — High: workload feasibility needs its own demonstration

The 8 October, 20:52 run grew from four to eight records relative to its predecessor. Native
[authority projection](../src/domain/specification_authority.zig#L50) creates eight
feature/entity obligations plus record-field obligations;
[policy subjects](../src/domain/principle_assessment.zig#L64) reuse those identities.
The result was 21 source-review exchanges and 18 policy subjects, rather than
17 and 14. Each policy request repeated seven principle chunks totalling 28,067
UTF-8 bytes. Ordinary policy exchanges used 6,643–6,646 input tokens.

In that pre-R3 run, reference preparation and generation consumed 19,214 tokens,
source review 40,491, and the six policy exchanges including correction 41,771.
Only four of eighteen policy subjects were admitted: the fifth was budget-stopped,
and thirteen were never reached. Subtracting the 6,952-token correction gives
94,524 tokens, but this is **accounting arithmetic, not an executable alternate
run**. Call 35 had no final answer; deleting its correction would prevent later
progress. The cost of a successful first-pass answer and the remaining work is
unknown. The captured cost and unfinished ledger establish a workload problem;
they do not establish that eliminating one retry would complete the workflow.

**Post-R3 evidence — 9 October:** the failure remains
`WorkflowTokenBudgetExceeded`, now at physical call **37**, reviewing the first
acceptance criterion's `given` field. Usage was **98,945** before that call;
its HTTP 200 response added **6,790** tokens, producing **105,735 / 100,000**.
The [runner](../src/application/workflow_pipeline_runner.zig#L420) reconciles actual
usage before applying the invocation result. Its budget rejection prevented final
text extraction and finding admission; `budget_stop` is not evidence of a missing
provider answer or invalid JSON. The raw response is retained. No correction retry,
repair or clarification explains this failure.

| Measured workload | Pre-R3, 8 October 20:52 | Post-R3, 9 October 07:59 |
| --- | ---: | ---: |
| Generated records | 8 | 4 |
| Reference preparation and generation tokens | 19,214 | 19,103 |
| Source-review calls / tokens | 21 / 40,491 | 17 / 32,317 |
| Policy calls / tokens, including correction or budget-stopped calls | 6 / 41,771 | 8 / 54,315 |
| Admitted policy findings / required subjects | 4 / 18 | 7 / 14 |
| Total calls / accounted tokens | 39 / 101,476 | 37 / 105,735 |
| Publication / rubric | Not reached / not run | Not reached / not run |

The post-R3, pre-R4 candidate has one acceptance criterion and three functional
requirements. Its 14 policy subjects comprise eight feature/entity obligations
and six record fields. All 17 source findings were admitted; seven policy findings
were admitted, the eighth was budget-stopped, and six further subjects were never
attempted. Each policy request still carries the same seven principle chunks
(28,067 UTF-8 bytes) and consumes **6,467–6,571 input tokens**. More admitted
findings is useful progress, but four fewer generated records reduced upstream
work independently of R3's later policy projection. The latest budget failure
without retries confirms that retry removal alone is insufficient. Prioritize
measuring complete review cost and designing the R5 coverage-preserving workload
change; do not treat more prompt wording or a higher budget as demonstrated fixes.

**Post-R4 evidence — 9 October, 08:34:** this run stopped on a missing mandatory
family before any policy request, at 59,850 tokens. Its source-review cost rose to
40,476 tokens across 22 calls. The R4 comparison above therefore neither resolves
R5 nor establishes that budget exhaustion would disappear for a valid candidate.
Address the newly observed authoring/collection projection gaps separately from
the still-unmeasured cost of a completed review and published specification.

Focused subjects may reduce ambiguity, but the repeated policy catalogue dominates
the request. The handoff appropriately treats grouping as conditional. A useful
proposal must separate **required evidence coverage** from **model-call
granularity**, and measure correctness and cost together. “Small calls” is not a
sufficient resource plan.

Canonical [principle selection](../src/domain/principle_registry.zig#L198) validates
the exact selected chunks. Dropping them through keyword filtering, replacing them
with a model summary, or sharing an unrelated positive finding would weaken policy.
A cluster review may be cohesive under §12.5, but
[§12.7's focused-review contract](../design/contracts/12-model-boundary.md#L290)
currently specifies one subject, one stable request slot, sequential retirement
and per-subject origins. Grouping requires an explicit amendment covering member
association, missing/partial results, correction scope, deterministic ordering,
admission, repair and persisted evidence. Regrouping or changing revisions must
not create new retry allowances. It is not merely a prompt or array-schema edit.
Reuse of current accepted findings must respect existing dependency/revision rules;
this handoff does not authorize a new cache or cross-execution resume mechanism.

**Feasibility:** medium and experimentally conditional. Preserve ADR 0011: report
actual usage, allow the existing accounted overshoot, and stop thereafter. Offline
request measurements must not become pre-call estimates, reservations or ceilings.

### R6 — High: repair protections exist; truth of the premise remains semantic

Package 4 correctly targets false and mislocalized findings, but most proposed
mechanical protections are already implemented:

| Protection | Existing owner |
| --- | --- |
| Current source/claim joins and permitted evidence | [specification_support_evidence](../src/domain/specification_support_evidence.zig#L121) |
| Fixed omission verdict in a separate localization assignment | [specification_support](../src/domain/specification_support.zig#L168) |
| Rejection of unlocalized or unsafe omissions | [source_omission.select](../src/domain/source_omission.zig#L124) |
| Mechanically available, source-bound producer locations | [source_omission.validate](../src/domain/source_omission.zig#L167) |
| Authorized target, dependency/revision/old-value preconditions | [atomic_repair](../src/domain/atomic_repair.zig#L56) |
| Dependent invalidation and subsequent validation | [source_omission](../src/domain/source_omission.zig#L265), [§22.5](../design/contracts/22-repair.md#225-merge-and-revalidation) |

The loan example shows that a false semantic conclusion can satisfy these
mechanical conditions. A source span, candidate value and explanation improve
inspectability, but do not turn entailment into a native fact. Also retain a
source-only omission with no extracted claim: requiring an existing claim for
every defect would make genuinely omitted meaning impossible to repair.

“A model assertion cannot authorize mutation” must mean **an assertion alone**.
The accepted design intentionally permits model-assisted findings to contribute
to native, narrow repair authorization once required evidence and preconditions
validate. Removing all such contributions would change the repair design.

Automatic reconsideration is explicitly inactive after the
[D2 rollback](archive/FIX_002.md#14-reverted-follow-up--23-september-2026).
[§22.1](../design/contracts/22-repair.md#221-definition-of-atomic) fixes the
localization premise and forbids a verdict as a repair target. The former D2
proposal concerned findings that proposed clarification; it is not automatic
authority to reassess every omission verdict.

**Required decision:** define the trigger, source/candidate evidence, closed
outcomes, stable bounded allowance, currentness, conflict handling and YAML routing
before adding reconsideration. Preserve the original evidence/history and one
active adjudicated finding. A replacement finding must pass ordinary admission;
a positive reassessment cannot clear a native forced defect or supply missing
source/policy evidence. Preserve the same semantic subject/family allowance across
verdict changes, revisions, repair and regrouping through runner-owned accounting.
Do not add a reviewer-owned counter or parallel agreement authority.

Unresolved or inconclusive disagreement must follow
[§12.8.1](../design/contracts/12-model-boundary.md#1281-clarification-admission-and-candidate-failure-precedence),
not invent a user question or vote until positive. Merely adding another call can
increase false repairs and cost; its benefit requires comparative evidence.

**Feasibility:** high for better projection and diagnostics within existing rules;
medium and approval-dependent for a new disputed-premise mechanism. No evidence
yet establishes that an extra reviewer would improve the intended model's results.

**New retained evidence — 9 October, 17:31:** §9.10 demonstrates a correct
candidate-omission finding followed by incorrect upstream localization. Native
source/claim joins admit the location but cannot prove that its content lost
meaning. The existing candidate-local story repair is already covered by a mock
regression; the observed failure is selection of the wrong repair path, not an
absence of local repair machinery. Keep this distinct from reconsidering the
correct omission verdict.

### R7 — High: focused role calibration complete; broader calibration remains open

**Complete — 9 October 2026: the requested focused semantic calibration of
authoring-role selection.** Tooling, human-reviewed labels, controlled and captured
premises, unchanged repeats, the fixed guidance comparison and held-out execution
are complete. This closes the bounded pilot, not broader generation/review/repair
calibration or production reliability. See the
[calibration instructions](../test/calibration/authoring-roles/README.md).

**Measurement limit identified before the routing follow-up:** the original live
cohort does not establish partial-role or multi-group routing accuracy. Supported mandatory
roles always point to group 1; the separate captured cohort covers one source
family. Broader claims need the order/selection cases described in §9.4, not more
unchanged repeats of the same answer topology.

**Routing follow-up complete — 9 October 2026:** broader cases, wrong-basis scoring,
packet/admission regressions, label approval and all 48 live comparison trials are
complete. The candidate reduces unsupported selections but worsens omissions overall
and on captured production inputs, so production guidance is retained. This closes
the bounded comparison; improved production outcomes and broader calibration remain open.
See [§9.7](#97-r7-routing-calibration-follow-up--9-october-2026).

- `zig build calibrate-roles` takes an explicit cohort, captured binding, split,
  repetition count and optional guidance comparison. `--live` is separate and
  requires human-reviewed labels. No default live case or E2E scenario was added.
- Controlled premises use native input builders and production role packets/schema
  restrictions; captured premises use the existing request-log loader. Labels and
  rationales stay outside model content. Family splits and optional/alternative
  support labels avoid exact-output targets.
- Native role membership/eligibility is factored into the shared
  `reference_role_assignment` owner, reused by production and calibration. Protocol
  admission and immutable request/response capture reuse diagnostic replay. No
  parallel validator, relaxed coverage rule or new provider client was introduced.
- Reports separate unusable answers, missing supported roles and unsupported pairs,
  with explicit denominators, paired rows, unchanged repeats, byte contributions,
  observed usage, provider latency and measured replay time. No retry/repair,
  workflow-state import, quality threshold or automatic prompt promotion was added.
- Reviewed cases cover required/not-applicable entity decisions, insufficient and
  ambiguous premises across unrelated families. A separate cohort labels the
  retained production call-7 failure. Production guidance is unchanged;
  `candidate.prompt.md` is an experiment only.

**Execution and approvals:** the user reviewed both cohorts and approved the initial
16 calls, then explicitly approved 12 replacement development calls and 16 held-out
calls. All 44 calls executed: 32 valid comparison trials and 12 invalid harness
trials retained as cost only. The captured binding stayed Bedrock
`openai.gpt-oss-20b-1:0`, low reasoning, temperature 0, native schema,
`ap-southeast-2`. Each trial used one physical send without correction or repair.
Development results were inspected before held-out execution; guidance and labels
were fixed throughout. No numerical acceptance threshold was invented.

**Valid comparison results:**

| Input set / evidence | Guidance | Trials | Missing / required roles | Unsupported / assigned pairs | Exact cases | Actual tokens |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| [Controlled development](../zig-out/role-calibration/2026-10-09T02-09-25Z-5992ebdd35fea5e6da8ba54ed15d0987/report.md) | Baseline | 6 | 10/24 | 9/23 | 2 | 6,706 |
| Same | Candidate | 6 | 4/24 | 0/20 | 4 | 6,704 |
| [Captured production input](../zig-out/role-calibration/2026-10-09T01-53-53Z-669e7ce2ce235512656ad7e42dc39433/report.md) | Baseline | 2 | 0/12 | 0/12 | 2 | 3,204 |
| Same | Candidate | 2 | 6/12 | 0/6 | 0 | 2,986 |
| [Held-out families](../zig-out/role-calibration/2026-10-09T02-10-04Z-a7c67ef5ce08bc67e73fef8b8aaa93e1/report.md) | Baseline | 8 | 0/34 | 2/38 | 6 | 8,514 |
| Same | Candidate | 8 | 0/34 | 2/36 | 6 | 8,623 |

All 32 valid trials passed protocol and native admission on their first attempt,
with complete usage and no operational failures. Inspection of actual provider
requests confirmed each controlled case's cited bytes match its own source, no
label/rationale leakage, byte-identical requests for unchanged repeats and guidance
as the sole paired difference. Reports retain exact requests, responses and timings.

**Assessment and selection:** retain production guidance; do not promote this
candidate. Across the 16 trials per variant, both missed 10/70 required roles and
had 10 exact cases. The candidate reduced unsupported pairs from 11/73 to 2/62,
but regressed on the retained production input. Development improvement did not
extend to the held-out comparison, where both falsely assigned `title` to the
isolated copied word. The ambiguity case's optional `entity_basis` assignment was
accepted with either choice; it was not counted as an omission or invention.

The UTC development baseline varied between two supported role pairs plus one
unsupported pair and no assignments on identical request bytes. The candidate
consistently omitted `title` and `entity_basis` there. On the captured input it
omitted `title`, `primary_user_story` and `entity_basis` in both repeats, while
baseline selected all six. This exposes remaining semantic errors and variability;
it does not justify changing model settings, weakening coverage or adding retries.

Valid trials used 36,737 tokens and 29.576 seconds of measured replay time;
provider latency was unavailable. Baseline used 18,424 tokens, candidate 18,313.
The slight aggregate token difference is not a quality improvement. These are
eight labelled assignments with correlated repeats, not independent population
samples. No successful whole-workflow publication or rubric result is established.

**Approved live execution and evidence defect:** the first
[12-call controlled run](../zig-out/role-calibration/2026-10-09T01-51-14Z-dbdd140afbe762defdb1683c8a8a252d/report.json)
is invalid calibration evidence. The new harness borrowed a temporary message
array during case preparation; later iterations overwrote earlier descriptions,
so every case sent the final runtime-context text. The earlier offline inspection
checked pair/repeat equality and label isolation, but failed to check source-to-case
fidelity. This was a harness ownership defect, not an LLM outcome. Immutable captures
are retained; exclude their semantic totals from comparisons. Their 12,276 actual
tokens and 10.105 seconds of measured replay time remain experiment cost.
`controlledDescription` now owns the message array, body and restricted schema.
A regression keeps multiple distinct cases alive after packet release and checks
their original meanings. The corrected preparation was independently inspected
against source bytes before the approved replacement run. Including invalid trials,
the experiment used 49,013 tokens; their cost was not discarded from accounting.

The subsequent [E2E run](../zig-out/e2e-spec/2026-10-09T02-01-41Z-2abaff5b6f3e0d8e0604e340f9cfdcaa/report.md)
selected all six roles in call 7. Its serialized role request is identical to the
previous run that omitted `entity_basis`; production guidance was unchanged.
This is observed variation, not evidence of improvement caused by R7. The later
story-generation call 10 returned only the preserved greeting, and execution
failed at omission-repair merging after call 31. No specification was published
or graded. That downstream failure is separate from this completed isolated
role-calibration pilot and does not expand its scope into story repair.

**Offline verification — 9 October:**
`zig build test-reference-reconciliation test-rubric-evaluator lint --summary all`
passed 226/226 tests before live execution; after the ownership correction,
`zig build test-rubric-evaluator lint build-role-calibration --summary all` passed
114/114 tests. Final `zig build verify --summary all` passed 135/135 steps and
1331/1331 tests, including architecture/schema checks and native startup smoke
tests. Regression coverage includes unrelated role-selection premises, optional
and alternative labels, native/protocol/operational rejection, closed cohorts,
family separation, multi-chunk source preservation and allocation-failure cleanup.
`git diff --check` passed. These checks verify the comparison machinery, not model
accuracy or production outcome improvement.

**Focused definition of done:** reviewed labels, unrelated positive/negative and
ambiguous premises, family separation, production packet/admission reuse, first-pass
protocol/semantic/cost reporting, unchanged repeats, controlled/captured/held-out
execution and a documented selection decision are complete. No trial in this plan
remains unexecuted and no live allowance remains. Broader R7 calibration and agreed
production quality thresholds remain open; automatic correction is separate.
Diagnostic and E2E evidence remain distinct. Production guidance is unchanged.

[§28.8](../design/contracts/28-testing.md#288-model-conformance-comparisons) already
requires controlled model-conformance comparisons through existing request capture,
binding, validation and replay owners. The handoff strengthens that approach; it
does not justify another provider client or production acceptance authority.

The cited [calibration README](../test/integration/fixtures/wf-001-hello-world/node-vitest/calibration/README.md#L3)
confirms that human review and live grading are pending. Its seven specimens were
assistant-authored before UTC became required, so **all omit UTC**, including the
two named “faithful.” Expected findings are proposed guidance, not approved labels.
Using these as current positive ground truth would miscalibrate the judge.

Completing that exercise evaluates supplied whole specifications. It does not
establish generation quality, reviewer false acceptance/rejection or localization
accuracy for production assignments. The existing single-request replay sends one
request and retains evidence; it does not execute workflow semantics or authorize
its result as workflow state. An assignment-level experiment must use production
packet/schema builders and the appropriate decode/admission path through a
development-only evaluation path, reusing the existing invocation and capture
mechanisms.

**Evaluate the assigned meaning, not only the verdict.** Call 36's `compatible`
could coincide with the correct verdict while its explanation concerns invented
implementation behavior. [Policy admission](../src/domain/principle_assessment.zig#L118)
checks citation membership/ranges, not whether the cited rule or explanation
applies to the assigned business subject. Labels must therefore cover subject
interpretation, evidence relevance and unsupported assertions as well as verdicts.
These are assessments of the returned answer, not demands to expose hidden reasoning.

Before declaring the smallest assignment demonstrated, specify:

- Human-reviewed source/candidate labels and genuine ambiguity; update or relabel
  outdated specimens. Split development and held-out cases by source/scenario
  family, so paraphrases of the same source do not masquerade as independent cases.
- Exact model/settings, packet/prompt/schema/policy versions, domains, sample and
  repetition plan, primary comparison and permitted live evaluation allowance.
  Keep labels and expected verdicts out of production model inputs.
- The branches affected by the claimed change. The existing
  [packet dispatcher](../src/domain/specification_support.zig#L112) distinguishes
  support, preservation, applicability, policy, correction and localization.
  Include required/not-applicable, genuine ambiguity/conflict and post-repair
  contexts where relevant; expand to all affected families before broader claims.
- Two downstream experiments where an upstream finding is a precondition:
  human-validated inputs to test the local task, and captured production inputs to
  test error propagation. Fixed-premise localization may correctly follow a false
  upstream omission; do not score that as an independent localization failure.
- First-pass outcomes separately from post-correction/repair outcomes. Count a
  repair as beneficial only when it fixes the labelled defect without introducing
  another or changing protected content. Track cumulative calls, tokens and time
  through terminal success, failure or clarification.

Use explicit units and denominators rather than one aggregate score:

| Measure | Required denominator or qualification |
| --- | --- |
| Missing obligations | Missing labelled obligations / all labelled source obligations, plus case-level fidelity; native claim count is not the human semantic denominator. |
| Unsupported additions | Unsupported candidate assertions / all candidate assertions, with raw counts and case-level fidelity so verbosity cannot hide invented behavior. |
| False acceptance / false rejection | Invalid / valid assigned candidates respectively. Report raw counts by task and truth class; do not mix policy conflict, source omission and applicability into one binary label. |
| Protocol admission and recovery | Physical attempts and logical assignments, including exhausted, unusable and inconclusive outcomes. Conditional semantic accuracy is allowed only when labelled as conditional. |
| Wrong interpretation or irrelevant evidence | All assessable review answers, reported beside unusable answers; a correct verdict with an invented rationale is still a defect. |
| False or harmful repair | Valid inputs changed unnecessarily, genuine defects repaired, new defects introduced and unresolved cases, each separately counted. |
| Workflow quality within limits | All declared live trials, including failures and clarification; report cost for unsuccessful trials as well as successful publication. |

Keep a fixed labelled cohort for before/after comparisons. Otherwise a better
upstream stage may admit harder downstream cases and make the downstream pass rate
look worse without a regression. Report case-level paired changes and unchanged
repeats; eighteen subjects in one feature are correlated observations, not eighteen
independent examples of workflow reliability. Human disagreement, evaluator
disagreement and confirmed production errors remain separate outcomes.

The handoff supplies no numerical acceptance targets. Agree critical-error rules,
aggregate thresholds and uncertainty reporting before comparing results. This
review does not invent or approve them. A whole-spec rubric model's agreement alone
is not independent ground truth for a production review model.

**Research validation and limits.** Primary sources support the measurement
approach, not a prediction that the configured model will pass:

- Anthropic's January 2026 engineering guidance distinguishes tasks, repeated
  trials, transcripts and outcomes; recommends unambiguous positive/negative cases,
  isolated trials and human calibration of model graders. Applied here, begin with
  a bounded assignment pilot and inspect its failures before building a broad
  evaluation platform. Semantic output should tolerate valid paraphrases; required
  native transition-order tests still enforce the engine's deterministic contract.
  [Demystifying evals for AI agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents).
- Zheng et al. document position, verbosity and self-enhancement biases and
  reasoning limits in LLM judges. This supports checking the judge against labelled
  near-misses and equally valid concise/verbose answers. If pairwise comparisons
  are introduced, control presentation order. Their benchmark results do not
  establish the accuracy of SDDE's current pointwise judge or configured model.
  [Judging LLM-as-a-Judge with MT-Bench and Chatbot Arena](https://arxiv.org/abs/2306.05685).
- NIST describes confidence intervals for proportions and exact binomial bounds
  for small samples. A low observed error count needs a sample size and uncertainty
  statement. For illustration only, under an independent, common-probability
  binomial model, zero failures in 20 trials gives a one-sided 95% upper confidence
  bound of about 13.9% (`1 - 0.05^(1/20)`). Repeated or correlated feature subjects
  cannot simply be pooled as independent trials. This is not a proposed sample
  size or threshold.
  [NIST: confidence intervals](https://www.itl.nist.gov/div898/handbook/prc/section2/prc241.htm).

**Feasibility:** bounded for a small human-reviewed pilot using existing capture;
medium for repeatable assignment-level evaluation and the full affected branch
matrix. No new evaluation framework or production dependency is justified yet.
Empirical success remains unknown. A failed pilot should constrain the claim or
motivate a scoped revision, not automatically add a reviewer, upgrade the model,
increase limits or expand the implementation.

R10 supplies a concrete additional assignment pilot: authoring-role selection,
including supported entity applicability, genuinely unsupported roles and repeated
identical inputs. Score missing supported roles separately from invented support;
measuring this variation does not itself provide a correction route.

### R8 — High: the proposed E2E quality gates need a test-policy contract

The handoff's exit-code warning is accurate.
[Status.commandSucceeded](../test/harness/e2e/contracts.zig#L70) returns true for
`evaluated` and `awaiting_clarification`.
[evaluation.apply](../test/harness/e2e/evaluation.zig#L29) records a completed score
as `evaluated` without requiring its aggregate threshold to pass. This is existing
documented CLI behavior, not by itself a runtime defect.

The current [greeting rubric](../test/e2e/wf-001-hello-world/node-vitest/rubric/spec.json)
has no configured aggregate pass threshold. The closed
[Rubric contract](../test/harness/contracts.zig#L34) supports an aggregate threshold,
not a general critical-error veto policy. The E2E Case also has no explicit expected
terminal-outcome field. Therefore “all critical criteria pass” and “clarification
cases explicitly expect clarification” require a declared acceptance contract or
human evaluation record; they are not already implemented by the listed commands.

[judgment.validate](../test/harness/judgment.zig#L33) checks criterion coverage,
scores and quoted evidence presence. Finding a quotation proves it exists, not
that it supports the judgment. Calibrated semantic evaluation remains necessary.

The current [judge packet](../test/harness/packet.zig#L16) contains reference
documents, published specification and rubric. It does not inspect the selected
principle catalogue, internal findings/repairs or sidecar lineage. A passing grade
cannot independently validate policy-review decisions or repair causality.
Evaluate those claims at their assignment boundary using the relevant captured
inputs, or explicitly scope the whole-spec quality claim to what the judge sees.
Do not silently expand the rubric's authority or its supplied evidence.

**Feasibility:** high for truthful separate reporting; medium for enforceable
critical-error/expected-outcome rules. Keep one development evaluation policy owner.
If adding those rules, extend the owning closed contracts and their reports/tests
together. Do not change CLI success semantics incidentally or make test thresholds
production workflow authority.

### R9 — Medium: preserve native diagnostics and reconstruction evidence

**Status — main implementation and offline verification complete on 9 October;
failure-path follow-ups OPEN after critical review.** The 14:39 retained live run
confirms role-producer attribution and build-input capture, but reaches no native
operation failure, provider rejection, repair or evaluator call. Inspection found
available evaluator failure bodies are dropped before capture, and secondary
accounting/logging failures can replace the original invocation cause in retained
diagnostics. See §9.3. The earlier blanket DONE/no-live statement is superseded.
These mechanisms improve evidence, not authoring-role selection, model quality or
workflow continuation policy.

The pre-implementation findings were upstream information loss: bindings collapsed
native causes to `OperationExecutionFailed`; its rendered diagnostic was `failed`.
Omission authorization returned `invalid` without the native cause or outstanding
requirements. Provider-content failures disappeared from the retained rejection
observer/events, and build provenance identified dirty inputs without retaining
those bytes. Supplied-spec grading bypassed the existing raw exchange store.

The 9 October, 08:34 run demonstrates the omission-authorization gap. The later
02:01:41 UTC run stopped at `g14-g6-review-omit-merge` with `operation_failed` /
`failed`, after 31 calls and 54,298 tokens. Its final model replacement and preceding
review establish the observed repair sequence, but cannot recover the thrown native
merge cause. New instrumentation cannot retroactively establish that cause.

| Required outcome | Implementation and owning boundary |
| --- | --- |
| Preserve native operation failures | [Closed operation error contract](../src/domain/operation_error.zig) combines declared domain/port error sets. Application bindings propagate native causes through the runner, CLI, telemetry and harness. Post-call accounting retains invocation failure when reconciliation succeeds and reports its own revision errors precisely. Retention of simultaneous causes remains open (§9.3). Error names are static; allocation failure needs no allocated diagnostic and applies no candidate delta. Explicit invariant guards retain their existing generic failure. |
| Keep expected rejection separate | [Candidate evidence](../src/domain/workflow_execution.zig) carries an optional closed native rejection outside the delta, only for existing rejecting outcomes. Success and disguised allocation failures reject at the runner. Existing outcome routing and publication gates remain authoritative. |
| Retain omission-authorization detail | [Omission authorization](../src/application/specification_omission_repair_workflow.zig) retains its native cause, reviewed revision, outstanding candidate-defect requirements and review origin. The [diagnostic projection](../src/domain/candidate_validation_diagnostic.zig) treats this as candidate-level evidence; a review call is not invented as the producer of the generation defect. |
| Retain provider failures | Existing [observer](../test/harness/e2e/observation.zig), [events](../test/harness/e2e/trace.zig) and reports preserve provider-content diagnostics and an independently owned latest provider rejection after transport retirement. Provider-diagnostic origin is separate from the latest exchange: pre-call authentication failures cannot inherit an earlier call's identity. Protocol rejection history remains separate. |
| Link observed progress | The runner exposes only accepted native data effects and repair transitions. The existing trace projects [first observation, correction history and invalidation/rebuild links](../test/harness/e2e/progress.zig), including target/family keys, permit/revision and unrebuilt data keys. Rejected deltas produce no applied effects. Each fresh invocation starts empty. |
| Preserve closed repair wire shapes | Native repair keys, permits and dependency snapshots serialize fixed digests as numeric arrays through the shared JSON byte-array writer. Their shape no longer varies with accidental UTF-8 validity; the closed decoder is unchanged. |
| Reconstruct allowlisted dirty sources | [Build provenance](../build/provenance.zig) embeds allowlisted source bytes, tracked/untracked status, deletions, permissions, source digest, revision, compiler version and dependency/build metadata in the development harness. The existing evidence store saves `build-inputs.json`, excludes credential paths before reading, redacts known run secrets and labels missing/redacted/non-UTF-8 inputs as incomplete. It creates no runtime authority or recovery path. |
| Capture supplied-spec evaluation | The [evaluator CLI](../test/harness/cli.zig) creates an exclusive per-invocation evidence directory and always uses the existing [evaluation trace](../test/harness/evaluation_trace.zig). Both live grading entry points require that store; capture failure prevents reporting a quality result. |

**Evidence interpretation:** `first_observed_defect` names the earliest captured
diagnostic, not a proven initiating semantic cause. Native repair permits and data
invalidation links establish only their explicit associations. `outstanding_work`
means invalidated data not rebuilt and can include intentionally retired transport;
it does not independently decide whether a workflow is complete. Historical recovered
errors stay distinct from current and terminal diagnostics. No attribution is inferred
from model prose or temporal proximity.

**Reconstruction limits:** a complete bundle retains captured Git-visible files
within the allowlist; it does not prove compiler-input closure (§9.3).
Compiler/toolchain availability, target/build settings and declared dependency
hashes remain necessary external build inputs; dependency downloads are not copied.
Missing, excluded or redacted bytes explicitly prevent exact source reconstruction.
[Exact replay](../src/application/request_replay.zig) separately verifies regenerated
request bytes and rejects redacted parents. Current encoding changes can invalidate
replay, and identical request bytes do not guarantee identical future provider output.
Modified replay retains its overrides and cannot establish unchanged behavior.

**Regression coverage:** unrelated reconciliation/omission failures and OOM cross the
shared runner boundary without a delta; expected rejecting outcomes retain their
cause while success rejects it. Post-call accounting retains the invocation cause
when reconciliation succeeds, records unknown usage and separately reports a stale
revision precisely. These tests do not establish retention of both simultaneous
causes. Provider rejection survives retirement and owner release, including
pre-call failure before and after earlier exchanges. Native repair progress
round-trips with exact revision/invalidation links and starts empty on fresh
invocation. Stale omission authorization retains outstanding requirements without
false response attribution.
Source capture covers dirty/untracked/deleted files, permissions, credential exclusion,
symlink rejection, explicit incompleteness, redaction and exclusive writes. UTF-8 and
binary repair digests share the same closed numeric-array wire shape. Evaluator trace
capture/retry/failure tests reuse the existing mechanism.

**Validation — 9 October:**

| Command | Result |
| --- | --- |
| `zig build test-model-request-workflow test-required-authority test-clarification-inputs test-architecture --summary all` | 12/12 steps; 627/627 tests passed. |
| `zig build test-integration build-e2e-harness --summary all` | 9/9 steps; 87/87 tests passed, including the final provider-origin regression. |
| `zig build verify build-e2e-harness build-rubric-evaluator --summary all` | 137/137 steps; 1,341/1,341 tests passed. Includes architecture/schema/format checks, native clean-environment packaging smoke tests and both development harness builds. |
| `git diff --check` | Passed. |

The complete diff was reviewed for scope, ownership, duplicate authority, failure
suppression and weakened validation. No new live outcome improvement is claimed.
Those dated passing tests did not cover the adapter-to-trace and simultaneous-failure
gaps identified in this review; they do not close the follow-ups in §9.3.
See [E2E evidence](../design/harness/e2e.md)
and [evaluator capture](../design/harness/evaluator.md) for the retained contracts.

### R10 — High: incomplete authoring-role coverage stops at the generation handoff

**Status — COMPLETE for the typed blocking handoff; full offline verification
passed on 9 October, and the 11:53 live run confirms that path. Successful
specification generation and rubric acceptance remain unachieved.**
The 9 October, 09:07 run exposes a dependency on variable model role selection
before any specification is authored. The native guard correctly rejects an
incomplete binding; the pre-implementation weakness was generic failure without
its missing-role cause. The implementation uses §17's existing blocking option.
It improves classification and diagnosis, not the model's role-selection accuracy.
This is separate from R4's record-family input corrections.

**Observed failure and attribution — before R10 implementation:**

- [Call 7's response](../zig-out/e2e-spec/2026-10-08T22-07-58Z-81991f12973d8466095855fd3d3399e0/evidence/generation/call-000007/model_output.txt)
  assigns signal 1 `title`, `description`, `primary_goal`, `primary_user_story`
  and `records`, but omits `entity_basis`. Call 8 returns no conflicts and is
  accepted. All eight model responses pass admission; no correction or repair runs.
- [Events](../zig-out/e2e-spec/2026-10-08T22-07-58Z-81991f12973d8466095855fd3d3399e0/events.jsonl)
  222 and 228 record successful role validation and source readiness. Event 230
  fails at `g8-generate-initialize-specification` with generic `operation_failed`.
  No authoring, semantic review, clarification, publication or rubric follows.
- The preceding run's [call 7](../zig-out/e2e-spec/2026-10-08T21-34-58Z-08faa42fc180e22e11a0e27cd7f459d0/evidence/generation/call-000007/model_output.txt)
  includes all six roles. Captured `context.json` and provider `request.json`
  files for calls 1–7 are byte-identical across the two runs. The extracted
  `model_output.txt` files for calls 1–6 and 8 are also byte-identical; raw provider
  responses differ. Case, source and model settings match.
  Only `records.prompt.md` and `support.prompt.md` changed among captured resource
  bytes; neither prompt was invoked. Build hashes differ as recorded in §1.
- R4's earlier nine-family role catalogue is present in both requests. The new
  aggregate `record_requirements` and explicit collection projection were never
  reached. This establishes output variation with unchanged reached inputs, not
  a causal regression from those new R4 paths. The exact reason the model omitted
  the role is not established. Lower whole-run usage is early termination: the
  first eight calls cost 12,148 tokens versus 12,054 previously.

**Coverage ownership and previous failure path:**

1. [Role admission](../src/domain/reference_reconciliation_validation.zig#L510)
   checks submitted assignments for eligible groups and unique roles/selections;
   it does not require every role to be assigned. This follows
   [§17.3](../design/contracts/17-specify.md#173-llm-work): unsupported roles may
   remain unassigned, while mandatory coverage blocks authoring.
2. [Source readiness](../src/domain/specification_provenance.zig#L38) checks
   complete accounting and at least one eligible claim. Its success deliberately
   does not establish support for every authoring role.
3. [Generation initialization](../src/domain/specification_session.zig)
   uses the [source-binding coverage owner](../src/domain/specification_source_binding.zig),
   which requires an active eligible selection for every `GenerationRole`.
   Previously, missing coverage raised `InvalidSpecificationBinding`, collapsed
   by the application binding into `OperationExecutionFailed`. The historical
   cause was code-traced rather than retained in that run's report. R10 now
   returns a typed `blocked` result for this expected domain rejection.

`entity_basis` supplies evidence for the required entity-applicability decision,
including a supported `not_applicable`; it does not require entity records. Its
supplied purpose already explains that behavior may support that decision without
an explicit declaration of absence. Native absence of a role proves incomplete
coverage, not whether the model overlooked support or the source lacks it.
Prior model assignment alone is not semantic proof of the correct replacement.
The [negative tests](../src/specification_generation_test.zig) still remove every
role individually across unrelated sources. Canonical validation continues to
reject the binding; initialization now identifies exactly which roles are absent.

**Implemented contract — 9 October:**

- `specification_source_binding.missingRoles` is the single coverage owner for
  initialization and canonical readback. It derives all missing roles from the
  existing `GenerationRole` enum and existing active-selection eligibility.
  Invalid or foreign evidence remains an error; incomplete valid assignments
  produce a gap. No role registry or completeness policy is duplicated.
- `specification_session.initialize` returns `ready` or `blocked`. The rejection
  retains every missing role in enum order, reference state, partition, current
  reconciliation revision, the roles field's producer request/attempt, and all
  current eligible signal IDs with their canonical claim selections. The later
  conflicts call does not replace role-selection attribution. The evidence is
  diagnostic, not an authorized replacement or semantic proof of support.
- The existing initialization action and application binding publish that typed
  result. The [workflow](../design/workflows/spec.workflow.yaml) explicitly routes
  `blocked` to `end.blocked` before brief/story/entity/record authoring. A blocked
  payload cannot be read as a generation session. Structural source readiness
  and role-admission rules remain unchanged.
- The shared `candidate_validation_diagnostic` gains `authoring_roles`, read
  through the existing application diagnostic owner. Existing telemetry and
  harness capture retain its producer attribution; harness JSON/Markdown/terminal
  reports retain the complete payload. The production invocation report copies
  candidate diagnostics before releasing source owners, and the CLI prints them
  for unsuccessful execution. This handles the expected handoff rejection without
  a new error channel or a parallel implementation of R9's shared error boundary.
- Initial assignments, repaired reconciliation and source invalidation still
  converge on this same initialization check. Canonical readback uses its strict
  `validate` wrapper; it cannot load incomplete coverage as successful authority.
  No prompt, schema, model slot, repair allowance, default assignment, fallback or
  internal-gap clarification was added.

**Automatic correction is outside this blocking contract.** Before adding an
upstream route, define its trigger, authorized unit, evidence, closed outcomes,
dependency invalidation and runner-owned allowance. Existing §17 permits blocking
or upstream rework but supplies no retry trigger or budget for this gap. R6's
disputed-review-premise proposal supplies no role-retry authority. A future route
must revalidate coverage before authoring and retain typed exhaustion; it must not
invent roles/entities, promote literal-only groups or retry until positive.

**Regression evidence:** generation unit tests cover each missing role, multiple
missing roles, no assignments, complete coverage split across eligible groups,
superseded-group exclusion, stale states and foreign claims across startup and
loan sources. They check revision/producer retention, diagnostic deep copying
after source release and allocation failures. Offline workflow integration injects
the observed missing `entity_basis` and an unrelated loan case with no roles;
both end `blocked` with the typed cause, no generation/review/repair calls, no
clarification or publication, and no active repair permit. Existing successful,
repair and upstream-rebuild scenarios remain in the separate integration suite.
Harness tests round-trip and render the rejection after releasing source memory.

**Verification — 9 October:**

- `zig build test-specification-generation --summary all`: **257/257 passed**.
- `zig build test-integration test-reference-model-input test-reference-reconciliation test-model-request-workflow test-architecture --summary all`: **passed**.
- `zig build verify --summary all`: **130/130 steps succeeded; 1,324/1,324 tests
  passed**, including formatting/AST checks, architecture tests, the separate
  offline integration suite and clean native packaging/runtime smoke tests.
- `git diff --check` and `git diff --cached --check`: **passed**.

No live run was launched during implementation. The subsequently retained live
run is analysed below. R7's approved repeated live trials must establish any
reduction in role omissions or improvement in completed, rubric-assessed
specifications; typed blocking alone establishes neither.

**Post-R10 live-result analysis — 9 October, 11:53 AEDT:**

The [report](../zig-out/e2e-spec/2026-10-09T00-53-40Z-ab59e9144c1aff2ce96a9816c782f782/report.json)
ends `workflow_blocked` at `g8-generate-initialize-specification`. This is R10's
expected result for incomplete coverage, not a new operational failure.

| Observation | Before R10, 09:07 | After R10, 11:53 |
| --- | --- | --- |
| Role assignment | Call 7 assigns five roles, omitting `entity_basis`. | The same five roles, again omitting `entity_basis`. |
| Terminal classification | `workflow_failed`; generic `failed` diagnostic. | `workflow_blocked`; typed `authoring_roles` diagnostic. |
| Retained cause | No `candidate_error` or attributed producer call. | `missing_roles: [entity_basis]`, reference state, partition 3, revision 1, eligible groups 1/2 and request 7 / attempt 1. |
| Origin attribution | Last model exchange is call 8, the conflicts request. | Last exchange is still call 8; `candidate_model_call: 7` correctly identifies the roles request. |
| Complete output | No authoring, publication or rubric grade. | No authoring, publication or rubric grade. |
| Calls / tokens | 8 / 12,148. | 8 / 12,123. |

**Where the gap originates:**

1. Call 1 extracts all three requested behaviors; calls 3/4 retain them, call 5
   retains all four native claims including the exact greeting token, and
   [call 6](../zig-out/e2e-spec/2026-10-09T00-53-40Z-ab59e9144c1aff2ce96a9816c782f782/evidence/generation/call-000006/model_output.txt)
   groups the three behavior claims. No earlier loss of behavior needed for the
   entity-applicability assessment is observed. Generated wording adds `the
   current` to the date/time claim; this is a captured variation, not evidence
   that it caused the role omission.
2. [Call 7's input](../zig-out/e2e-spec/2026-10-09T00-53-40Z-ab59e9144c1aff2ce96a9816c782f782/evidence/generation/call-000007/context.json)
   contains those behaviors and the existing `entity_basis` purpose: it supplies
   evidence to decide whether entities are required **or not applicable**.
   The prompt, all six purposes and selected response schema are unchanged from
   09:07. The [provider response](../zig-out/e2e-spec/2026-10-09T00-53-40Z-ab59e9144c1aff2ce96a9816c782f782/evidence/generation/call-000007/response.json)
   includes an explanation treating entity applicability as not applicable, then
   excludes that role from its final assignment. This supports a specific
   interpretation error: treating a negative applicability decision as absence
   of evidence for making that decision. The provider's explanation is evidence
   of its reported interpretation, not proof of its internal causal mechanism.
3. The [returned assignment](../zig-out/e2e-spec/2026-10-09T00-53-40Z-ab59e9144c1aff2ce96a9816c782f782/evidence/generation/call-000007/model_output.txt)
   already omits `entity_basis`; no native handoff or diagnostic projection
   removes it. Role admission accepts supported submitted assignments without
   asserting completeness, as required by §17. Call 8 finds no conflicts.
4. [Event 230](../zig-out/e2e-spec/2026-10-09T00-53-40Z-ab59e9144c1aff2ce96a9816c782f782/events.jsonl)
   is the first non-`ok`/`more` outcome: typed `blocked` with the exact missing
   role and call 7 attribution. Events 193/201/222 confirm role admission and
   validation; event 228 confirms structural source readiness. None claims
   complete authoring-role support. Provider prefixes were normalized and all
   eight responses admitted on their first attempts; JSON correction, retry
   exhaustion and the token budget did not stop this run.

**Causal comparison and limits:** the selected case is byte-identical. Captured
sources, configuration, model settings, prompts and context resources match;
the only changed captured input resource is the workflow's explicit `blocked`
edge. Call 1's context and provider request are byte-identical. Its output varies
in the date/time wording, which propagates into later request bytes: this is
**not** an unchanged-request comparison for calls 2–8. In call 7's dynamic data,
only that claim and its signal rendering differ. Both runs nevertheless return
the same role set. Both use `openai.gpt-oss-20b-1:0`, captured reasoning effort
`low`, native-schema mode and unchanged region/settings. Different build hashes
and one post-change observation do not establish a model success rate.

**Assessment:** R10 improved rejection classification, retained evidence and
producer attribution in live execution. It did not improve role selection or
completion, and was never an automatic-correction implementation. Its guard
already blocked the same incomplete coverage before R10. No R10 regression or
reason to weaken/revert the guard is supported by this run. The 25-token decrease
is generation variation during the same early stop, not an efficiency gain.
The focused role-selection pilot under R7 is now complete and measures negative
applicability versus missing support; it did not identify a uniformly better
guidance candidate. Broader calibration remains open. Any automatic return to
reconciliation still needs the separate bounded correction policy above.

## 4. Feasibility and decision matrix

Feasibility ratings above describe structural reuse and coupling, not delivery
estimates or probabilities of semantic success. “High” means an existing owner
offers a bounded implementation path; “medium” means coordinated contracts or
evaluation work remain. The intended model's reliability is empirically unproven
in every package. No numerical effort estimate is defensible from this review.

| Handoff package | Practical assessment | Decision or dependency before implementation |
| --- | --- | --- |
| 1 — Define/calibrate assignments | The focused authoring-role pilot is complete. Broader generation/review/repair calibration remains; existing whole-spec examples are insufficient and outdated. | Agree production quality thresholds before acceptance claims. Expand evaluation to all nine existing record families before full-scope claims, without requiring each family in every spec. |
| 2 — Native traceability | Existing group provenance can be audited immediately. Narrower association and complete answer authority are separate coordinated changes. | Define precision and identity lifetime; amend ADR 0020 only if changing binding. Complete the separate authentication/answer/currentness contract before claiming answer-supported generation. |
| 3 — Resolved projections/workload | R3's resolved policy inputs are implemented and observed live; R4 supplies shared family meanings. Complete workload feasibility remains unmet; grouping is a distinct, conditional experiment. | Preserve resolved scalar/record/collection/entity facts and separate instructions. A production cardinality or policy-selection change needs an explicit amendment and negative tests. |
| 4 — Evidenced repair | Projection/evidence improvements can preserve current policy. New premise reassessment is not active authority. | Define trigger, closed outcomes, currentness, one active finding and conserved allowance; obtain the required amendment before adding reconsideration. |
| 5 — Layered acceptance/reporting | R9 implements the main native-cause, progress, source-snapshot and evaluator-trace mechanisms. This review reopens evaluator failure-body and simultaneous-failure evidence follow-ups (§9.3). Acceptance rules remain separate work. | Complete capture at its adapter/observation boundary; preserve rejection precedence and redaction. Apply development acceptance policy separately. Diagnostic evidence does not establish model quality or publication success. |
| R10 role-coverage handoff | Typed blocking and evidence propagation are implemented using the existing coverage/diagnostic owners. | No new decision for blocking. Automatic upstream correction needs its own trigger, authorization and allowance contract; R7 owns live measurement. |

No engine replacement is indicated. The largest uncertainty is measured semantic
reliability under the chosen model and budget, not whether Zig can represent the
necessary types or execute the graph. Source-binding, answer lifecycle,
verdict-policy and shared failure-boundary changes have the highest coupling.
All are feasible in principle; none should be hidden inside a prompt cleanup.

## 5. Revised implementation sequence

1. **Preserve the baseline and prepare a bounded comparison.** Retain current
   production packets, source cases, settings and build inputs. Select the first
   assignment and human-review its labels, including the motivating failure and
   unrelated positive/negative cases. Declare metrics and approval needs. Record
   workload with full selected principles. Outdated “faithful” specimens are not
   positive ground truth. Preparation and offline tests do not require completion
   of a new evaluation platform or the whole cross-cutting diagnostic design.
2. **Implement the bounded projection and purpose corrections.** Resolve policy
   subjects through the existing business view and value lenses; complete all
   record-family purposes. Cover initial/insertion/repair paths and keep source and
   policy responsibilities separate. Measure projection and family-purpose changes
   independently so semantic improvements and record/call growth remain attributable.
   R3's resolved projection is complete, with the narrow live observation recorded
   above; R4's shared meanings and the requiredness/source-collection follow-ups
   are complete with regression coverage preserving existing authority.
   Generalized claims of live improvement still require the declared, approved
   comparison.
3. **R10 typed blocking is implemented.** The existing native guard now returns
   missing-role and producer evidence before authoring, verified across unrelated
   sources. Measure its live behavior separately from R4. Any automatic upstream
   correction still needs an explicit authorization and allowance contract; it is
   not part of the selected blocking behavior.
   The focused R7 calibration is complete, with reviewed labels, approved live
   development/captured/held-out comparisons and a decision to retain baseline
   guidance. Its mixed results do not establish production reliability or authorize
   an automatic correction route.
4. **Decide traceability precision using the observed gap.** Keep current lineage
   machinery. If group-level attribution is insufficient, amend the binding/selection
   contract and update its complete consumer surface together; do not add metadata
   that only makes broad attribution look more precise. Scope the confirmed answer
   lifecycle gap separately; it is required for full clarification recovery, not
   for diagnosing the already observed no-answer budget failure.
5. **Decide workload and disputed-premise changes separately.** Approve a concrete
   focused-review amendment before implementing production grouping; preserve
   per-member findings, correction scope and retry identity. Add no reassessment
   call until its authority and stable limit are explicitly approved. Prefer better
   generation and assignment interpretation before more review layers. Stop a
   proposed extension that fails its declared semantic/cost comparison; do not
   weaken required coverage to obtain a pass.
6. **Complete the applicable lifecycle and diagnostic work.** If claiming full
   answer-supported Spec execution, demonstrate authenticated answer acceptance
   through generation and readback, including source refresh and invalidation.
   R9's shared operational-cause and evidence changes are implemented, with their
   verification and reconstruction limits recorded above; the missed failure
   paths in §9.3 remain open. They do not implement the answer lifecycle or change
   acceptance policy. The current bounded priorities are refined in §9.5.
7. **Complete layered verification and approved live acceptance.** Use the current
   repository build steps, preserve separate unit/integration/live layers, and then
   run the explicitly approved E2E cases with actual publication and rubric evidence.
   Record failures and unresolved quality decisions without substituting another
   model, raised budget or altered judge.

Minimum sufficient diagnostics and retained evidence accompany each step. This
sequence is a proposed dependency order, not authorization to implement it now.
Track authorized implementation, remaining work and exact verification results in
this document. The former FIX_003 task checklist has been removed; its completed
work stays in the historical implementation record. FIX3-08's unmet live acceptance
and the proposed projection/purpose/workload follow-ups are covered here. Archiving
those records does not establish live acceptance or approve their proposals.

## 6. Required validation evidence

| Boundary | Accepted cases | Rejected/unresolved cases and required distinction |
| --- | --- | --- |
| Native source binding and lineage | Legitimate one-to-many/many-to-one groups; precise existing occurrences; exact and passive text. | Foreign/stale claims, invalid spans, changed source state, fabricated associations and unsupported reassociation. Valid broad links with distorted prose remain semantic negatives. |
| Role-coverage handoff (R10) | Complete eligible coverage across one or several groups; unchanged repaired/upstream paths re-enter the same check. | Every missing role and unassigned coverage ends typed `blocked`; stale/foreign evidence remains an error, ineligible groups do not count. No authoring/default assignment, retry or internal-gap clarification. Retain state, revision, role producer and eligible groups after source release. Any future correction route needs separate authorization/exhaustion tests. |
| Production trace precision | Real binding/parsing/readback/rendering under the current group-attribution contract; narrower support only after an approved change. | Directly constructing ideal test provenance proves neither production precision nor a violation of the accepted broad-binding contract. Include omitted meaning with apparently complete link coverage. |
| Clarification answer lifecycle | Authenticated close, durable response before refresh, exact protected bytes, current applicability, response-owned passive text and answer-supported generation/readback. | Unauthenticated/empty close, stale/foreign response or revision, changed source/policy and unsafe applicability. Prebuilt recorded-answer preservation does not demonstrate acceptance and resolution. |
| Review projection | Scalars, records with necessary siblings, collections, entity applicability and cross-requirement dependencies. | Internal identities treated as business text; source instructions leaking into policy review; stale/foreign assignments; accidental loss of required context. |
| Family semantics | Supported rules, outcomes, assumptions, exclusions, prohibitions, edge cases/entities and legitimate overlap. | Positive requirements relabelled as assumptions/non-goals, invented optional records, lost negation/obligation/timing, automatic equal-string deletion. |
| Semantic generation and review | Human-labelled paraphrases, equivalent order/structure and faithful exact text across unrelated domains; fixed cohorts and both clean and production upstream inputs. | Unsupported additions, false acceptance/rejection, irrelevant evidence, correct verdict with invented rationale, wrong localization, inconclusive output and protocol failures, reported separately. |
| Repair and invalidation | Genuine localized defect, smallest authorized replacement, current evidence and complete dependent/full validation. | Foreign target, old-value mismatch, unauthorized verdict change and allowance reset reject mechanically. A mechanically valid false premise or harmful repair needs semantic evaluation; scripted native tests prove routing, not recognition of falsity. |
| Workload | Complete native ledger coverage with actual serialized packets; grouped findings only under an accepted contract. | Missing/duplicate/foreign/stale findings, dropped selected policies, reused unrelated verdicts and measurements converted into pre-call limits. |
| Harness acceptance | Declared completed-spec and clarification expectations; calibrated output review and retained repeats. | Treating `evaluated`, low scores, unset thresholds, clarification, missing grading or a zero exit code as sufficient quality acceptance. |
| Diagnostics/reproducibility | Typed native causes, exact origin/repair links, reconstructible permitted build inputs and complete captures. | Reconstructed guesses labelled facts, lost causes, secret exposure, hash-only rebuild or deterministic live-output claims, and replay evidence imported as runtime authority. |

The repository-owned targeted steps include `test-specification-generation`,
`test-reference-reconciliation`, `test-required-authority`,
`test-model-request-workflow`, `test-rubric-evaluator`, `test-workflow-graph`,
`test-architecture` and `lint`, followed by the applicable full `verify` and native
packaging checks. Discover current commands from `build.zig`. No such test was
executed during the original documentation review or this retained-run analysis;
the subsequent R3, R4, R7, R9 and R10 verification is recorded above. The present
architectural reassessment adds inspection, not another implementation test run.

The two live case commands in the handoff exist, but no invocation is authorized
by this document. Isolated live comparisons require a bounded approval under
§28.8; each E2E invocation requires its own approval under AGENTS.md. The rubric
must assess the engine's actual published output. Calibration specimens and
scripted integration results remain distinct evidence.

## 7. Review conclusion and validation performed

The handoff is a useful direction for the next iteration and explicitly calls for
reuse of existing provenance and repair owners. Distinguish those implemented
protections from unresolved precision and semantic reliability gaps. R3 resolves
the policy projection defect, and R4 supplies shared purposes for every existing
record family, aggregate requiredness and explicit reviewed collections. R10
makes incomplete authoring roles an explicit blocked result with producer evidence.
R9 retains native causes and explicit repair/progress links and captures permitted
build inputs and evaluator exchanges. It improves observability without proving
the initiating semantic cause or improving model decisions.
Any automatic upstream correction requires its own bounded policy. Define the
claimed source-association precision and settle the applicable acceptance and
disputed-premise decisions. Semantic calibration and
complete workload feasibility remain; they do not require replacing the generic
engine or inventing another authority system.

The completed clarification audit adds a separate implementation gap: production
Spec execution does not accept and apply newly submitted answers. Preserve its
existing protections, but do not claim the full lifecycle works or describe it as
merely uninspected. This finding expands the known completion dependencies, not
the authorized scope of this documentation review.

Static code inspection and retained-artifact comparison support the findings above.
They establish implementation mechanisms and observed failures, not a probability
of future success. Feasibility is strongest for shared projection/guidance changes,
conditional for precise rebinding and review scheduling, and unproven for improved
model judgment. Successful publication, calibrated quality acceptance and unchanged
repeatability remain required evidence.

Critical-review checks before folder cleanup: current worktree/HEAD inventory,
cited source and contract inspection,
retained run evidence review, independent read-only audits of the source/projection,
repair and evaluation paths, and primary-source research cited in R7. Checks passed
for 95 local links, including 72 heading/line anchors, and document whitespace;
`git diff --check` and `git diff --cached --check` also passed. Implementation,
calibration and live E2E validation were not run during that review. Its unavailable
handoff baseline commit and missing numerical semantic acceptance policy remain
explicit limits. Subsequent R3 verification and retained live evidence are recorded
above; neither establishes the configured model's future success rate.

**R3 live-result analysis — 9 October:** inspected the latest and pre-R3 reports,
captured requests/responses and input/configuration equality; matched policy calls
by assigned business subject; recomputed stage usage from the attempt ledger; and
traced native projection, admission and budget-stop ordering. R3's input correction
is observed, while publication, grading, complete workload feasibility and reliable
semantic judgment remain unmet. This update changes only FIX01; no code changes,
test execution or new live invocation were needed for this evidence analysis.
All 101 local links, including 73 heading/line anchors, and `git diff --check`
passed for this update.

**R4 live-result analysis — 9 October:** inspected the 08:34 run and immediate
07:59 baseline, compared captured case/configuration/resources and model settings,
verified shared purposes in actual generation/source requests, recomputed stage
usage and subject counts, and traced missing-family validation and omission
authorization against the accepted contracts and existing negative tests. The
observed coverage regression and early stop establish no improved completion or
budget feasibility. This analysis changes only FIX01, preserves the staged R4
implementation, and performs no code changes, test execution or new live call.
All 119 local documentation targets, including 80 heading/line anchors, and
`git diff --check` / `git diff --cached --check` passed.

**R10 evidence update — 9 October:** compared the 09:07 and 08:34 retained cases,
resources, request/response bytes and usage; traced role admission, readiness,
initialization and cause loss against §17.3 and existing missing-role tests.
Independent read-only review checked attribution and policy limits. This update
changes only FIX01 and preserves all staged implementation changes. No code tests
or live executions were run for this documentation task.
All 135 local links, including 88 heading/line anchors, and `git diff --check` /
`git diff --cached --check` passed.

**R10 post-implementation live-result analysis — 9 October:** inspected the
11:53 report, all eight captured exchanges, provider explanation, 230 step events
and terminal diagnostic; compared case/configuration/resources and reached
requests against 09:07; and checked coverage ownership, admission and YAML
termination. Only this document changed during the analysis. No new live run or
code-test invocation was needed; the implementation verification above remains
historical evidence for the preceding code change.

## 8. Outstanding scope preserved during cleanup

The following work from the older records is not completed by the implemented
Spec changes. It remains visible here without expanding the immediate priority
beyond the projection and semantic-quality work above.

| Remaining item | Scope and existing authority |
| --- | --- |
| Architecture-wide deterministic responsibility audit | The [earlier user mandate](archive/LLM_REWORK.md#152-architecture-wide-responsibility-and-change-matrix) covers every registered model boundary, initial/correction/repair/rebuild path and evaluator. Include explicit ownership dispositions for proposed Plan/Tasks/Implement contracts; this does not mean implementing those workflows now. Preserve genuine semantic choices and remove determined echoes through their existing owners. |
| Determined exact-occurrence selectors | Complete the [selector transfer](archive/LLM_REWORK.md#155-claim-id-necessity-review--five-required-follow-ups) required by [ADR 0020](../design/decisions/0020-derived-exact-reference-lineage.md): omit the returned ID when the bound branch determines one occurrence, construct it natively, and retain genuine multi-occurrence choices. Audit schema, decoder, reconstruction, repair and readback together; this is not a request for another selector-specific prompt rule. |
| Evaluator responsibility transfer | The [C3 inventory](archive/LLM_REWORK.md#152-architecture-wide-responsibility-and-change-matrix) includes native criterion assignment/collection assembly and captured quotation-occurrence selection. Define the necessary assignment/occurrence contracts before changing them; preserve semantic scoring and evidence relevance. This differs from R7's calibration and R8's acceptance rules. |
| Retained-memory and scale evidence | The [existing evidence gap](archive/LLM_REWORK.md#143-remaining-architecture-traceability-and-effectiveness-work) covers growing review sets: retained bytes, allocations, validation time, teardown, OOM/cancellation and dependent rebuilding. Current prefix copying and retained parents motivate measurement; they do not prove a leak or authorize removing required dependencies. |

Optional provider-diagnosis, reasoning-setting and principle-passage experiments
remain historical proposals. They are not current implementation tasks or live
authorizations. Existing R1–R10 and §6 retain the unresolved clarification,
role-coverage, publication, calibration, workload and live repeatability requirements.

**Cleanup validation — 9 October 2026:** checked repository Markdown links against
the pre-move baseline; no new unavailable targets. FIX01's 98 local links and 76
heading/line anchors passed. All 12 experiment evidence files retain their original
SHA-256 hashes. Fix-record whitespace, `git diff --check` and
`git diff --cached --check` passed. The 262 already unavailable historical targets
remain unavailable; this cleanup does not reconstruct old run/cache artifacts.
No implementation tests or live executions were needed for the document relocation.

## 9. Post-implementation architectural reassessment — 9 October 2026

This reassessment answers whether the implemented items improve the application,
what was missed, and whether local fixes introduced brittleness. It inspects the
current owners and their sibling paths, with independent read-only audits of
R3/R4, R7/R10 and R9. Findings below refine the existing R1–R10 work; they do not
create a second implementation checklist or amend accepted architecture.

### 9.1 Progress is real, but the product outcome remains unproved

The comparisons in this subsection describe the earlier 14:39 reassessment.
The later 17:31 run passes authoring-role coverage and reaches regeneration;
§9.10 supersedes the early-stop description for the latest run. Neither run
publishes a specification or supplies a rubric result.

| Implemented item | Architectural progress | What remains unestablished |
| --- | --- | --- |
| R3 | Policy review receives resolved business fields, collections and entity applicability through one projection owner. Internal authority tuples are no longer the business subject. | Reliable semantic policy judgments and a completed review workload. Earlier live delivery observations cannot be rechecked against absent raw bundles here. |
| R4 | All nine family/field meanings share one owner across authoring and review. Native aggregate requiredness remains separate from optional per-group output. The two sibling projection gaps in §9.2 are now closed. | Correct classification and preservation of meaning. Shared wording and fake-port tests establish delivery/native behavior, not the model's interpretation or improved live completion. |
| R7 | A reusable bounded comparison separates native admission from human-labelled semantic accuracy. Mixed results prevented promotion of a guidance candidate that regressed on captured input. | Production reliability, partial-role/multi-group selection, other generation/review/repair tasks, and completed-spec quality. The pilot changed no production guidance. |
| R10 | One coverage owner produces an explicit block with missing roles, current source state and exact producer evidence before authoring. | Better selection or authorized recovery. Turning a generic failure into an actionable block was its intended outcome; it does not promise successful generation. |
| R9 | Native causes, observation history and permitted source bytes are substantially better retained. The latest report correctly distinguishes producer call 7 from latest exchange 8. | Complete failure-path capture (§9.3), stronger executed-source correspondence, or better model decisions. Latest live evidence exercises only part of the implementation. |

The latest run's eight contexts, serialized requests and projected outputs are
byte-identical to the 11:53 run. Against the 13:01 run, contexts and requests 1–7
are identical, but call 7 chooses a different role set. These comparisons show
unchanged reached inputs can produce complete or incomplete authoring bindings.
They do not establish the provider's internal reason or a causal R9 regression.
The early stop is semantic role omission, not a newly unhandled JSON prefix.

No presently inspectable run in this comparison publishes a specification or
reaches rubric evaluation. Consequently there is no defensible quality gain,
completion-rate estimate or complete-workflow cost improvement to report. More
truthful failures and rejected bad guidance are valuable engineering outcomes;
they do not satisfy the application's completed-spec acceptance criteria.

### 9.2 Projection follow-ups and remaining lifecycle gap

**Closed — active brief repairs silently dropped the selected task.**
[specification_repair.packet](../src/domain/specification_repair.zig#L217) derives
the authorized field's purpose and passes `PacketOptions.task` to the session.
Previously, [packetForOptions](../src/domain/specification_session.zig) replaced an
active purpose only for `.records` and emitted a separate task only when the
assignment was absent. Active brief repairs therefore lost the selected-field
purpose. The shared packet owner now emits the supplied `task` once for every
assignment shape. [Source-binding presentation](../src/domain/specification_source_binding.zig)
omits competing authoring purposes during repair while preserving claim/signal
selections. Completed units retain a null assignment; initial authoring retains
its original purposes. No new task authority, repair permission or prompt branch
was added.

The [boundary tests](../src/specification_generation_test.zig) now assert all three
brief fields, story and entity-basis repair, every record family/field and completed
units. They retain source selections and reconstruction evidence, verify authorized
replacement/merge, and preserve stale-target and sibling protections. This fixes
guidance delivery, not the latest live role-selection failure.

**Closed — completed entity source review required interpreting the raw candidate.**
[projectBusiness](../src/domain/specification_review_subject.zig) already supplied
policy review with disposition, resolved basis and business context. Focused source
review now reuses that projection and the same `EntityApplicability` payload, instead
of falling through to `candidate_support`. Initial review, correction, finding
insertion and detail/evidence repair use the existing shared projector. Source
reconstruction evidence remains complete; source and policy instructions remain
separate.

Tests cover required and not-applicable entities, literal/exact/passive bases,
invalid provenance, and allocation failures through the source packet path. Partial
pre-authoring subjects and dependency localization remain unchanged. This closes
the presentation asymmetry; no live evidence yet establishes better entity verdicts.

**High — confirmed, pre-existing: newly submitted answers cannot complete the
clarification recovery path (R2).** The current YAML preparation ends at
[form validation](../design/workflows/spec.workflow.yaml#L243), which distinguishes
submitted from recorded responses but does not authenticate/accept a new answer.
[refresh](../src/domain/clarification_refresh.zig#L31) rejects a submitted nonempty
answer with `AuthenticationRequired`, while
[specification provenance](../src/domain/specification_provenance.zig#L84) rejects
nonempty clarification-response IDs. The protections are intentional; the missing
acceptance/current-applicability and answer-to-generation integration is the defect.
This did not cause the latest no-clarification block, but prevents claiming a
complete workflow for cases that need user answers. Resolve the R2 authority
contract before implementation; never accept answers merely because a form is loaded
or closed.

### 9.3 R9 follow-ups: failure evidence is not yet complete

**Medium — confirmed: evaluator adapters discard available partial response bodies.**
[Bedrock's evaluator adapter](../test/harness/bedrock.zig#L52) does not supply the
transport's error-path response slot and copies a body only for `.received`.
The existing [transport](../src/adapters/provider/bedrock_transport.zig#L18) and
[HTTP adapter](../src/adapters/provider/bedrock_http.zig#L31) already retain body
prefixes and their completeness on failures. They are lost before reaching the
[evaluation trace](../test/harness/evaluation_trace.zig#L39).
The sibling [OpenAI evaluator HTTP path](../test/harness/http.zig#L95) also assigns
`response_body` only after its read finishes, so a failed read loses the prefix.
This is a shared evaluator-observation contract gap, not solely a missing Bedrock
conditional. The [current observation](../test/harness/provider.zig#L25) has no
body-completeness field or error-exit evidence channel.

Thread available bytes and completeness through the existing evaluator observation
and capture owner, including typed failures and error-union exits. Preserve task
joining, call-local ownership, credential redaction, original failure and scoring
rules. Existing [trace tests](../test/harness/tests.zig#L467) inject already-populated
fake observations; they cannot detect adapter evidence loss. Add fault cases through
native adapters and the trace for partial reads, timeout/cancellation, allocation failure,
full non-success responses and no received body. The evaluator documentation also
[says error bodies are not retained](../design/harness/evaluator.md#L249), while its
later capture section promises raw responses. Reconcile that stale statement with
the approved raw-capture/redaction contract when implementing this follow-up.

**Medium — confirmed limit: simultaneous failures need separate evidence.**
[Post-call accounting](../src/application/workflow_model_invocation.zig#L24) can
replace a thrown invocation cause with its own stale-revision or other accounting
error. Successful reconciliation of unavailable usage preserves that invocation
cause. Budget precedence is a different path: an admitted usage observation can
exceed the budget and supersede another candidate-classification rejection.
The [runner's invocation catch](../src/application/workflow_pipeline_runner.zig#L410)
can return a logging/capture rejection before the invocation's original cause.
These paths remain fail-closed; rejection precedence may be correct. However, R9
does not retain both causes, so the original diagnostic can still disappear when
accounting or evidence writing also fails. Retain bounded primary/secondary evidence
through the shared observation boundary and test combined failures. Preserve existing
terminal precedence; do not replace it with a second continuation rule or require
successful allocation/logging to record an allocation failure.

**Evidence limits, not demonstrated runtime defects:**

- The latest bundle contains 1,020 captured inputs and its recomputed source digest
  matches. [Build capture](../build/provenance.zig#L34) enumerates Git-visible files
  in an explicit allowlist, excluding ignored untracked files. The
  [build graph](../build.zig#L138) captures before compilation rather than compiling
  from the captured tree. `complete` therefore describes that permitted snapshot,
  not proven compiler-input closure or immunity to concurrent edits. No mismatch is
  observed here. State this limit; strengthen correspondence only if claiming exact
  executed-source reconstruction.
- The latest report has 107 `corrections`, zero native repair transitions and 19
  outstanding data keys. [Progress.observe](../test/harness/e2e/progress.zig#L37)
  includes routine invalidation/rebuild and transport retirement under those labels.
  They do not mean 107 semantic repairs or 19 completion failures. Distinguish repair
  actions from ordinary effects in presentation while retaining the existing facts.
  This is diagnostic noise, not workflow authority or the cause of the role omission.

### 9.4 Where brittleness remains, and what the changes did not cause

**Semantic routing is still a consequential model judgment.** Role membership and
coverage validators prove eligible, current bindings and detect missing roles;
they do not prove the model correctly recognized support. The
[entity purpose](../src/domain/required_authority_description.zig#L110) already
explains that source-backed behavior may justify `not_applicable` without an explicit
absence declaration. Repeating that instruction is not a newly identified missing
definition. An omitted role can represent genuine insufficiency or model oversight;
R10 correctly blocks both under current authority.

The role selector makes an additional semantic judgment about actor/benefit/entity
support before authoring makes related judgments again. This is no data-flow cycle,
but it adds an independently fallible gate. Single responsibility and smaller calls
do not remove that risk. [ADR 0020](../design/decisions/0020-derived-exact-reference-lineage.md#L50)
requires the pre-authoring binding; bypassing it, auto-filling all roles or moving
it elsewhere requires an explicit architecture decision. More self-agreement calls
would not constitute semantic proof.

**R7's original cohort was broader in wording/domain than in routing structure.** Every
mandatory supported role in the live cohorts selects group 1; positive cases mostly
require all six roles, negatives none. The
[ambiguous case](../test/calibration/authoring-roles/cohort.json#L379) permits either
entity-basis selection. That tests uncertainty without proving reliable partial-role
selection. Controlled inputs use [admitted builders](../test/harness/roles/input.zig#L19),
bypassing production extraction/grouping; the
[captured cohort](../test/calibration/authoring-roles/captured.cohort.json#L7) has one
source family. Add later-group support, group-order permutations, an earlier plausible
distractor, split-role support, contradictory/underspecified sources and captured
post-repair premises. Score wrong-basis selection separately from omission and
unusable output. This is an evaluation coverage gap, not evidence of fixture-specific
production branches. Keep labels outside requests and fix candidate guidance before
held-out comparisons. The bounded routing follow-up in §9.7 now closes this
case/scoring/comparison gap; genuine post-repair coverage remains unavailable.

**Complete review cost remains structurally unresolved (R5).** Each policy subject
[reconstructs the full business context](../src/domain/specification_review_subject.zig#L66)
and receives [all selected principles](../src/domain/principle_assessment.zig#L101).
More records/fields increase both subject count and repeated context. R3 clarifies
the subject; it does not make this workload cheaper, and clearer family guidance can
produce more content to review. Measure complete required coverage, retries, repairs,
tokens, latency and retained memory. If grouping is justified, amend its existing
assignment/correction contract first. Do not truncate dependencies, select policies
by keywords, add local size ceilings or raise the budget and label that a repair.

**Valid mechanics still permit wrong semantic premises (R1/R2/R6).** Native lineage,
current revision and atomic mutation prevent fabricated IDs, stale writes and excess
scope; they cannot establish faithful prose, extraction completeness or a correct
omission verdict. A false finding can initiate a mechanically valid harmful repair.
That needs assignment-level false-positive/false-negative and repair-harm measurement.
A new verdict-reconsideration route remains a separate accepted-policy amendment.

The inspected R3/R4/R10/R9 owners do not add a hardcoded greeting/loan continuation
rule, a parallel success validator or a weakened gate to make one case pass. The
concrete local incompleteness was the records-only repair-task branch in a shared
packet API; the authorized follow-up removes it at that API across all shapes.
The evidence does not justify attributing all semantic variability to recent edits,
or claiming that all existing brittleness has been repaired.

### 9.5 Suggested next work and feasibility

The complete role-decision implementation and comparison are recorded in §9.9.
The latest run now passes that handoff; its first demonstrated defect moves the
immediate investigation to **shared business-text authoring and incorrect loss
localization**, as specified in §9.10. Role-selection false negatives remain open
calibration findings, but repeating the completed cutover will not repair this
story. This order refines §5 without authorizing code, model calls or policy changes.

| Priority and existing item | Smallest architecturally complete next step | Feasibility and required evidence |
| --- | --- | --- |
| R4 / §8 — missed packet paths | Implemented: one selected repair task across assignment shapes, and shared resolved entity applicability in completed source review. | Closed by boundary regressions and offline verification (§9.6). Live model improvement remains unmeasured; these changes do not address the earlier role-selection blocker. |
| R9 — reopened evidence gaps | Complete evaluator response-prefix/completeness capture across both adapters; preserve simultaneous invocation/accounting/logging causes as evidence. Correct retention documentation. | High for adapter/trace capture; medium for shared dual-cause reporting. Fault tests must traverse native adapters/runner, not start with ideal populated observations. No scoring or terminal-precedence change. |
| R7 / R10 — observed authoring blocker | The guidance-only comparison remains rejected (§9.7). The separately authorized complete role-decision contract and its subsequent 48-call comparison are complete (§9.9). | Complete representation and shared admission work. Wrong-group selections fall to zero and captured cases improve, but observed omissions rise and two answers lack final JSON. The declared semantic promotion criterion is not met. Publication/rubric quality remains unverified. |
| R7 / R6 — literal-only authoring and incorrect localization | Compare complete authoring packets across story and record-field tasks; calibrate intact-upstream versus genuine-loss localization through existing packet/admission owners (§9.10). | Existing input and local repair machinery are usable. A new representation or stronger loss-evidence contract needs coordinated design and measured evidence; no greeting-specific guard, extra reviewer or new retry is justified by this run. |
| R5 / §8 — complete-workflow feasibility | Measure the full selected-policy workload and memory; evaluate one bounded scheduling/grouping alternative only under an accepted contract. | Measurement is feasible now. Production grouping is conditional on policy amendment and per-member findings, retry identity, invalidation and full coverage evidence. |
| R2 — answer recovery | Define and implement authenticated acceptance, durable/current applicability and response-backed generation/readback through existing lifecycle owners. | Medium; coordinated authority/state/typed-text work. Mandatory before claiming support for answer-dependent completion, independent of the latest no-answer failure. |
| R1 / R6 / R8 — quality and repair acceptance | Define required association precision, bounded disputed-premise policy if needed, and development quality/expected-outcome rules. Calibrate review/localization/repair tasks against human labels, then evaluate actual published output. | Conditional decisions, not prompt cleanup. Preserve the distinction between evaluator completion, semantic acceptance and production authority. |

Success for the next phase means measured fewer unsupported/missing selections and
harmful repairs, a complete feasible workload, actual publication, declared rubric
acceptance and unchanged live repeats. Test-count growth or the disappearance of one
error message is insufficient. Preserve the useful deterministic engine; improve and
measure its semantic boundaries before expanding the number of model decisions.

**Review validation:** inspected current source/contracts, all three locally retained
9 October E2E reports and reached request comparisons, current calibration cohorts
and their retained results, plus independent read-only audits. No code changes,
implementation tests, new research calls or live model executions were performed.
Earlier full-suite counts remain dated implementation evidence. Older unavailable
run bundles limit retrospective causal claims; current static findings are identified
separately from observed live failures and future risks.
`git diff --check` passed, all 28 newly introduced local link/anchor targets passed,
and the latest bundle's 1,020-input digest was independently reproduced. Only FIX01
is modified; unavailable historical targets were not reconstructed or counted as
newly validated evidence.

### 9.6 R4/§8 projection follow-up implementation — 9 October 2026

The two explicitly requested projection paths are implemented at the existing
session/source-binding and review-subject owners. The records-only task override
is removed. Repair guidance presents one selected task across brief, story, entity
and record assignments; source selections and completed-unit retirement remain
unchanged. Completed source entity review shares the policy review's resolved
entity-applicability payload. No response schemas, persisted state, model routes, retry
allowances, repair permissions or lifecycle transitions changed.

Generation/story instructions and the static generation context now accommodate
the selected repair purpose without requiring an authoring purpose that repair
intentionally omits. The model-request guidance documents the shared presentation.
Regression tests extend the existing repair/review matrices across two unrelated
mock domains, both entity dispositions, resolved literal/exact/passive text,
initial/correction/insertion/detail/evidence repair, completed units and partial
source/localization cases. Invalid provenance and allocation-failure checks remain
fail-closed.

| Offline command | Result |
| --- | --- |
| `zig build test-specification-generation --summary all` | 258/258 tests passed. |
| `zig build test-required-authority test-model-candidate-json test-architecture lint --summary all` | 336/336 tests passed; lint passed. |
| `zig build verify build-e2e-harness build-rubric-evaluator --summary all` | 137/137 steps and 1342/1342 tests passed, including separate offline integration, lint/architecture, clean native packaging and harness builds. |

Compiler/cache and clean packaging verification required host access. The complete
diff was reviewed for scope, duplicate authority, obsolete paths and weakened
enforcement. `git diff --check` passed; all 24 newly introduced local documentation
targets passed, and the changed generation JSON context parsed successfully.

These changes close the two presentation defects. No live E2E or calibration call
was run for this implementation, and no improved semantic verdict or published
specification is claimed. The latest retained authoring-role blocker precedes
these paths; the R7/R10, R9 and clarification findings remain separate.

### 9.7 R7 routing calibration follow-up — 9 October 2026

**Complete: local implementation, offline preparation and all 48 approved live
comparisons, with a documented decision to retain production guidance.** This
addresses the calibration coverage gap identified in §9.4. It does not add production
roles, change role meanings or bypass R10's mandatory authoring coverage gate.

The existing calibration owners now cover:

- [Ten controlled cases](../test/calibration/authoring-roles/routing.cohort.json),
  with six development and four held-out cases in disjoint source families.
  Later-group support and reversed sources test order dependence; same-kind
  competing business sources prevent a technical/business classification shortcut.
  Partial-role and split-role premises, undecided outcomes and contradictory prose
  extend the earlier all-or-none routing topology.
- [Two captured cases](../test/calibration/authoring-roles/routing-captured.cohort.json)
  retaining the latest and preceding production call-7 inputs. Both are initial
  requests from one development family. Their observed omissions are evidence to
  compare, not the source of expected labels.
- A separate `wrong_basis_pairs` count at the existing scorer/report boundary.
  It is a subset of `unsupported_pairs` when a role has allowed groups but selects
  another group. Assignments to roles with no allowed group remain unsupported;
  omission is independent. Native role membership and retained-claim eligibility
  validate first through the production admission owner; historical captures retain
  their historical facts rather than importing current workflow state.
- Captured task intake rejects duplicate role definitions and invalid/blank purposes,
  preserving captured wording rather than substituting another purpose registry.
  Boundary regressions cover partial support, incorrect bases, optional/alternative
  support, source/group/assignment permutations, unusable output and report totals.
  Dataset checks validate actual packet handles and label isolation without freezing
  the human review metadata in a particular review state.

At preparation time both new cohorts had `label_status: proposed`, `reviewer: null`.
The live approval and reviewed metadata are recorded below. The original
reviewed pilot, its immutable results, production guidance and experimental candidate
are unchanged. The [preparation commands](../test/calibration/authoring-roles/README.md#completed-routing-follow-up)
hold Bedrock `openai.gpt-oss-20b-1:0`, low reasoning, temperature 0, native schema and
`ap-southeast-2` fixed. Two repeats per case compare baseline with the same candidate:

| Prepared set | Planned calls | Offline evidence |
| --- | ---: | --- |
| Controlled development | 24 | [Report](../zig-out/role-calibration/2026-10-09T04-37-11Z-9325a5656eb8088e07d440b7e783483f/report.md) |
| Captured development | 8 | [Report](../zig-out/role-calibration/2026-10-09T04-37-24Z-61f163fa36980ce840959fec057e74ca/report.md) |
| Controlled held-out | 16 | [Report](../zig-out/role-calibration/2026-10-09T04-37-33Z-e1ea57d4933889a5310097856a41cfc8/report.md) |

All **48** immutable requests were inspected against their actual serialized provider
bodies. Controlled citations/claim text match each case's source bytes; captured user
content matches the original logs. Baseline/candidate pairs differ only in guidance;
unchanged repeats are byte-identical. Labels/rationales are absent from model content,
schema handles match native groups and every preparation outcome is `not_run`.
No API call, correction, repair, workflow publication or rubric evaluation ran
during this offline preparation.

**Remaining limits:** no genuine post-repair role capture exists in retained runs;
do not manufacture one by editing captured requests. The controlled builder produces
single-claim retained groups. The contradiction case tests unresolved prose, not
native conflicting dispositions or conflict admission; allowed group IDs are
alternatives, not a requirement to select every group. Partial cases test valid role
selection from incomplete premises, not successful complete specification generation.
These small, assistant-authored cohorts received user approval but cannot establish
population reliability or replace complete live E2E/rubric evidence.

The comparison held the candidate fixed on development/captured inputs and held-out
families. The selection below compares missing roles, unsupported/wrong-basis pairs,
unusable answers, repeated variability and actual costs together. Do not tune against
held-out results or promote guidance automatically.
Retain production guidance unless the measured comparison supports a change.
[§28.8](../design/contracts/28-testing.md#288-model-conformance-comparisons)
requires explicit bounded approval for external calls; the approved 48-call allowance
has now executed in full. Genuine post-repair coverage remains a separate evidence gap.

| Offline command | Result |
| --- | --- |
| `zig build test-rubric-evaluator --summary all` | 118/118 tests passed. |
| `zig build test-architecture lint smoke-role-calibration --summary all` | 123/123 architecture tests passed; lint and clean diagnostic startup passed. |
| `zig build verify build-role-calibration --summary all` | 136/136 steps and 1345/1345 tests passed, including separate offline integration and clean native packaging. |

The three documented `zig build calibrate-roles` commands completed without
`--live`; their planned allowances are 24, 8 and 16. Full verification used the
installed Zig compiler/cache with host access. Scope review preserves existing
staged R4 changes; this follow-up changes calibration data/intake/scoring/tests
and documentation only. No production prompt, schema, route, state or retry rule
changed.
`git diff --check`, both new JSON parses and all nine new local documentation
links/anchors passed. Independent review found no material code or approval-boundary
defect; its correction of an unsupported freshness claim is incorporated above.

**Latest E2E after the follow-up — 9 October, 04:44 UTC:** the
[retained run](../zig-out/e2e-spec/2026-10-09T04-44-10Z-351303ae95d313768b68b362cedf3248/report.md)
again blocked at generation initialization. Call 7's provider request and extracted
response are byte-identical to the 04:19 run: signal 1 receives only `title`,
`description` and `primary_goal`, omitting `primary_user_story`, `entity_basis`
and `records`. Eight calls consumed 11,990 tokens; no specification was published
or rubric evaluation performed. The comparison was unexecuted and both cohorts
were still proposed at that time. That E2E run demonstrates no production improvement
from the calibration tooling; the later diagnostic comparison is recorded below.

#### Live comparison and selection — 9 October 2026

The user's instruction to complete the prepared live comparison authorized its
reviewed labels and all **48** planned sends. Both cohorts record that review;
their label contents remained fixed. The three README commands subsequently ran
with `--live`, explicitly sourcing the dedicated `.env.e2e` credentials. All sends
executed once, without correction, repair or an additional allowance. This is
diagnostic model evidence, separate from live E2E and rubric evaluation.

| Live input set / evidence | Guidance | Trials | Missing / required roles | Unsupported / assigned pairs | Wrong-basis pairs | Exact trials | Actual tokens |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| [Controlled development](../zig-out/role-calibration/2026-10-09T05-06-02Z-f84d70dc1b9790a9fc93c79a4edc78d5/report.md) | Baseline | 12 | 14/62 | 35/87 | 34 | 0 | 15,547 |
| Same | Candidate | 12 | 20/62 | 17/61 | 15 | 3 | 15,596 |
| [Captured production inputs](../zig-out/role-calibration/2026-10-09T05-06-47Z-724ba34c545ad7140fc2b4bc8d03fee6/report.md) | Baseline | 4 | 1/24 | 4/27 | 4 | 0 | 6,603 |
| Same | Candidate | 4 | 8/24 | 0/16 | 0 | 0 | 6,038 |
| [Controlled held-out](../zig-out/role-calibration/2026-10-09T05-07-28Z-8f662480c06876d58dcb79816fee1368/report.md) | Baseline | 8 | 12/38 | 3/44 | 3 | 2 | 10,906 |
| Same | Candidate | 8 | 9/38 | 0/40 | 0 | 2 | 10,538 |
| **Total** | **Baseline** | **24** | **27/124** | **42/158** | **41** | **2** | **33,056** |
| **Total** | **Candidate** | **24** | **37/124** | **17/117** | **15** | **5** | **32,172** |

All 48 trials passed protocol and native admission, with complete usage and zero
operational failures. The existing Bedrock normalizer handled 47 prefixes; there
was no JSON retry. Independent inspection confirmed source/capture fidelity,
guidance-only paired differences, byte-identical unchanged repeats and no label or
rationale leakage. Binding, role purposes and response schema remained fixed:
Bedrock `openai.gpt-oss-20b-1:0`, low reasoning, temperature 0, native schema,
`ap-southeast-2`. Identical requests still produced different assignments.

**Selection: reject the candidate and retain production guidance.** It reduces
unsupported assignments but increases required-role omissions by 10 overall and
by 7 on captured inputs. All four captured candidate trials omit `entity_basis`;
two also omit title/story. The baseline supports all six roles in three of those
four trials, while wrongly assigning title or description to the copied-value
group in all four. Neither variant is reliable; fewer unsupported assignments
alone do not repair the production authoring blocker.

The held-out improvement does not establish order invariance: the candidate is
exact on both `spoken-timer-later` trials but omits title/records on both reversed
inputs. Same-kind lamp routing remains wrong, and both inventory candidate repeats
assign an unsupported story while omitting title/entity. These are unrelated
failure classes; the comparison does not support a greeting-specific rule,
forced role assignment or candidate promotion.

The experiment used **65,228 actual tokens** and **53.4424 seconds** of summed
measured replay duration. Provider latency was unavailable; no dollar cost is asserted. Counts
are descriptive for these small, correlated cohorts, not statistical reliability
or completed-spec quality. Missing-role and wrong-basis errors can overlap;
wrong-basis counts must not be added to unsupported counts as separate failures.

No production change is supported by these results, so none is introduced.
The bounded call-7 routing comparison is complete; genuine post-repair premises,
other generation/review/repair tasks and published-output quality remain open.
Another comparison requires a declared fixed intervention, labels, measurement
plan and fresh bounded approval. A new semantic correction or continuation route
also requires an explicit policy decision rather than a local workaround.

After execution, `zig build test-rubric-evaluator lint --summary all` passed
**118/118 tests** and lint. The preceding full verification remains the applicable
implementation evidence above; this execution changes reviewed cohort metadata
and documentation only. The experimental candidate and production guidance are
unchanged. `git diff --check` and all six changed documentation link/anchor targets
passed. Both cohorts parse with unchanged cases/labels; guidance bytes match HEAD.
Independent accounting and selection audits found no material discrepancy.

### 9.8 Complete role decisions: critical review — 9 October 2026

**Status at this review: proposed, not implemented.** The subsequently authorized
implementation is tracked in [§9.9](#99-complete-role-decision-implementation--9-october-2026).
This section preserves the dated review of the user's one-call
proposal: every registered authoring role returns selected supporting signal IDs
or an explicit unsupported decision. Scope is code analysis, primary-source research
and this tracking document; production code, configuration, schemas, prompts and
accepted contracts are unchanged. No new diagnostic or E2E model invocation ran.

**Verdict:** feasible as a coordinated closed response-contract change, with the
existing canonical source bindings and R10 gate retained. It is **not a demonstrated
fix for semantic role-selection failures**. The strongest mechanical shape is a
closed object containing one required property per registered role, with disjoint
supported/unsupported branches. A six-item array and prompt instructions alone
provide weaker provider-side completeness enforcement.

#### Evidence and causal limits

The [48-call comparison](#live-comparison-and-selection--9-october-2026) admitted
every response after existing normalization; its failures were incorrect semantic
selections, not missing JSON fields required by that schema. Both variants omitted
supported roles and selected wrong groups; identical requests varied, and
source-order permutations produced different outcomes. The rejected candidate
increased semantic omissions from 27/124 to 37/124. The evidence cannot establish
whether an omitted role was
overlooked, deliberately judged unsupported, or affected by another model error.

An explicit negative makes the *reported decision* distinguishable from a missing
decision. It does not prove that the model carefully assessed the role, make a
negative judgment correct, or diagnose the model's internal rationale. Requiring
six reported decisions can simply turn six silent omissions into six false
unsupported decisions. The expected improvement in selection is therefore a
hypothesis to measure, not the reason to declare this fix complete or effective.

The current assignment already has one cohesive responsibility: select semantic
support for authoring tasks. Its six roles do not establish a single-responsibility
violation. This proposal changes response completeness and orientation while
keeping one initial assessment; it does not split generation, infer semantic roles
in native code or add an independent reviewer.

#### Primary-source research and provider constraints

AWS documents structured outputs for this exact
[gpt-oss-20b model on bedrock-runtime](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-openai-gpt-oss-20b.html),
including InvokeModel. Its
[structured-output documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/structured-output.html)
uses `response_format` for open-weight InvokeModel requests, documents a restricted
JSON Schema subset, and permits only 0 or 1 for `minItems`. Unsupported schema
features can reject the request. New schema grammar compilation can add latency;
reported provider compilation/cache behavior is not a reason to change engine
caching. These are current documentation facts, not evidence that a new SDDE schema
has been exercised successfully. Do not import guarantees or request settings from
another model, endpoint, OpenAI-hosted API or Custom Model Import route.

The repository already implements this separation:
[Bedrock projection](../src/domain/model_schema_projection.zig#L156) reduces every
positive array minimum to 1 and omits its maximum; complete native schema validation
retains the original bounds. Object `required` properties and closed extra-field
rules survive both projections. Thus `minItems: 6` would not enforce six decisions
in this provider grammar. No adapter change or schema weakening is indicated.

The JSON Schema references distinguish
[required properties](https://json-schema.org/understanding-json-schema/reference/object#required-properties)
from optional ones, and
[array-item uniqueness](https://json-schema.org/understanding-json-schema/reference/array#uniqueness)
from length. Inference: different objects with the same role but different decisions
are distinct array items; `uniqueItems` alone would not enforce one decision per
role. The current closed [schema compiler](../src/domain/model_result_schema.zig#L538)
does not accept `uniqueItems`, `contains` or tuple/conditional schemas. Extending
that generic compiler merely to encode this role count is unnecessary.

[JSONSchemaBench](https://arxiv.org/abs/2501.10868) evaluates constraint coverage,
efficiency and task quality separately. Research on
[constrained generation](https://proceedings.mlr.press/v306/reddy26a.html) describes
how structurally valid generation can follow semantically incorrect trajectories.
Those studies support measuring validity and meaning separately; their models,
tasks and decoding implementations do not predict this Bedrock routing result.
They do not justify importing draft-generation calls, best-of-many selection or a
new repair mechanism into SDDE.

#### Recommended bounded contract

Retain the [registered `GenerationRole` catalogue](../src/domain/reference_reconciliation.zig#L99)
and [shared purposes](../src/domain/reference_model_input.zig#L104). The current
catalogue has six roles; derive/check completeness against that catalogue rather
than adding a second handwritten registry or relying on the literal number six.
Use one required property for each role, with a tagged support decision. For example,
this is an illustrative response shape, not validated source evidence:

```json
{
  "role_decisions": {
    "title": {"kind": "supported", "signal_ids": [17]},
    "description": {"kind": "supported", "signal_ids": [17]},
    "primary_goal": {"kind": "supported", "signal_ids": [17]},
    "primary_user_story": {"kind": "supported", "signal_ids": [17]},
    "entity_basis": {"kind": "unsupported"},
    "records": {"kind": "supported", "signal_ids": [17, 23]}
  }
}
```

Every property is required. `supported` carries a nonempty, unique selection from
the exact eligible native signal catalogue. `unsupported` carries no selection,
prose justification or generated field content. Both branches are closed and
disjoint, using the existing tagged-union/schema codec. Reject missing/unknown
roles, duplicate JSON keys, unsupported extra fields, empty positive selections
and the old sparse wire shape. Do not add defaults or a legacy reader.

`unsupported` means the model reports that the offered eligible evidence provides
no sufficient source-backed basis for the assigned authoring purpose. It is a
candidate judgment. It does not prove missing user information, authorize
clarification, or establish an entity
`not_applicable` result. Behavior supporting an applicability assessment of
`not_applicable` still supports `entity_basis` under its
[existing purpose](../src/domain/required_authority_description.zig#L110).

The shared role-assignment owner should admit the complete table and derive the
existing positive group-role assignments. Reject duplicate IDs before conversion;
never hide defects by deduplicating. Traverse native offered-group order and
registered role order so model key/selection permutations produce the same canonical
bindings. Preserve many-to-many support: roles can select multiple groups, and a
group can support several roles. Do not merge groups or create cross-group records.

The required map/type/schema must be mechanically checked against the existing
catalogue. A manually maintained list in the prompt, schema, decoder, validator and
scorer would recreate duplicate authority. Required nullable arrays are another
representable shape, but [optional fields with defaults](../src/domain/model_candidate_json.zig#L203)
admit omission, and null/array branches lack the existing tag-based exclusion for
empty choices. Select one wire shape; do not support alternatives simultaneously.

Keep native conversion and eligibility in the existing domain owner, parsing in the
existing codec, and coordination in the compiled workflow. One call means one
initial model-request operation containing all decisions; the existing
[two protocol corrections](../design/workflows/spec.workflow.yaml#L560) may still
cause additional physical sends. Missing fields are structural defects. A complete
unsupported decision is not a malformed response and must not trigger a newly
invented semantic retry. R10 still blocks missing positive mandatory coverage.

#### Brittleness and overlooked paths

| Risk | Code evidence and required treatment |
| --- | --- |
| Complete but semantically wrong answers | Schema completeness cannot detect false unsupported, wrong eligible groups or order-sensitive interpretation. Preserve semantic omission/wrong-basis measurement and the downstream review/coverage gates. Do not score a full decision map as quality success. |
| Empty eligible catalogue | [Current narrowing](../src/domain/model_result_schema.zig#L194) rejects restricting a nonempty support list to no IDs. Reuse the existing tagged variant exclusion to project a valid unsupported-only shape before narrowing. Test every role; do not emit an empty enum, catch the error as a fallback, invent IDs or silently construct model verdicts. |
| Eligible IDs confused with sufficient support | [Shared admission](../src/domain/reference_role_assignment.zig#L21) checks membership, retained claims and uniqueness. It does not prove that a group supports the role. Keep the complete evidence catalogue, original occurrence handles and semantic choice; no keyword or claim-kind routing shortcut. |
| Role/signal identity drift | Replace the [old restriction path](../src/domain/reference_reconciliation_stage.zig#L79) with the new support-branch path. Preserve exact assignment/state/revision checks during [collection](../src/domain/reference_reconciliation_stage.zig#L85). Equal numbers in another partition or changed group must not become current evidence. |
| Negative decisions lost during conversion | Canonical signals retain positive roles only. Keep the admitted response and its actual producer in existing captured evidence; do not claim negative verdicts survive [snapshot readback](../src/domain/reference_snapshot.zig#L121). Sparse canonical projection is permitted only after complete-table admission, never as a second independently editable candidate source. |
| Partial/default initialization masquerading as assessment | Before the role phase the decision table is pending, not an all-unsupported result. Missing fields must reject. Never initialize absent roles to unsupported or construct a positive role from a display value to satisfy coverage. |
| Stale decisions after upstream repair | Signal edits [clear roles and origins](../src/domain/reference_reconciliation_repair.zig#L469); disposition edits [retire affected signals and roles](../src/domain/reference_reconciliation_repair.zig#L668). The new candidate decisions and every derived binding must retire together and be reassessed through the same phase. Do not preserve old negatives while clearing positives. |
| Protocol correction becomes semantic reconsideration | Existing correction retains the immutable request/schema and responds to structural errors. An admitted unsupported judgment remains valid candidate data followed by R10 blocking; no correction-until-supported loop, new role-repair target or altered terminal transition belongs to this cutover. |
| Historical captures requested under the wrong contract | [Captured CLI cases](../test/harness/roles/cli.zig#L149) retain old schemas, while [scoring](../test/harness/roles/score.zig#L33) uses the current response type. Changing only the production schema would make those arms incompatible. Record any diagnostic reprojection explicitly and pair each arm with its actual decoder; preserve original captures/reports unchanged. |
| Evidence attribution unnecessarily redesigned | All decisions still come from one admitted response. Existing [collection origin](../src/domain/reference_reconciliation_stage.zig#L125) and [coverage rejection origin](../src/domain/specification_source_binding.zig#L189) remain appropriate. Do not invent six calls or provider origins, discard correction-attempt identity, or blame stale engine state on the model. |
| Sibling fixtures retain sparse responses | Update scripted [role responses](../src/test_fixtures/spec_generation_responses.zig#L899), initial/correction paths and [rebuilt-source role responses](../src/specification_generation_test.zig#L3153). Separate explicit-unsupported semantic faults from missing-decision protocol faults; retain MOCK business values and unchanged coverage expectations. |

#### Feasibility and coordinated implementation scope

| Owner | Smallest required change |
| --- | --- |
| Model wire/schema | Replace the role phase's [schema definition](../design/workflows/spec/reconciliation.schema.json#L454) and [typed response](../src/domain/reference_reconciliation_stage.zig#L139), with completeness tied to the registered role catalogue. Do not modify unrelated reconciliation phases or the generic parser profile. |
| Packet/presentation | Update role guidance and support-ID restrictions; reuse existing purposes and complete evidence. Explicitly describe the negative branch. No new prompt-context registry, caching change or model-slot change. |
| Native admission/conversion | Add complete-decision admission and deterministic inversion at the shared role-assignment owner; [production validation](../src/domain/reference_reconciliation_validation.zig#L510) and calibration reuse it. Keep parse/admit/convert responsibility separate from model dispatch. |
| Phase lifecycle and repair | Collect the new candidate and retire it with dependent role facts after upstream changes. Preserve phase snapshots, immutable correction packets, existing receipt retirement and YAML transitions. |
| Binding/persistence | Retain [R10's coverage owner](../src/domain/specification_source_binding.zig#L149), positive canonical `generation_roles`, final IDs and citation derivation. A wire-only change does not require a persisted-state version bump by default. If new persisted authority is proposed, declare that separate change explicitly. |
| Diagnostics/trace | Distinguish malformed/missing decisions from an admitted unsupported role and retain the actual response/attempt. Native completeness is proof of representation only. |
| Tests and calibration | Cut over fixtures and production decoder use, preserving immutable old evidence. Prepare a declared response-contract comparison; the existing guidance-only switch is insufficient. |
| Governing documentation | Amend [§17](../design/contracts/17-specify.md#L159), [ADR 0020](../design/decisions/0020-derived-exact-reference-lineage.md#L50) and the applicable [ADR 0022 handoff wording](../design/decisions/0022-native-reference-phase-handoffs.md#L9) before/together with implementation. Update guidance and call-tree documentation. |

**Feasibility assessment:** high for the mechanical one-call response cutover using
existing object/union/choice contracts; moderate for coordinated fixture and
diagnostic comparison work; unknown for semantic improvement. No production
dependency, provider mode, new evidence store, state-resume feature or separate
success validator is needed. Canonical source binding remains ahead of authoring.
Accepted contracts must distinguish explicit wire decisions from their derived
canonical assignments. This review does not amend those contracts or approve
implementation, new model calls, continuation rules or a semantic repair policy.

#### Validation and promotion conditions

1. Prove closed decoding and decision completeness at the owning boundary: every
   missing/unknown/duplicate property, malformed branch, positive empty/duplicate
   IDs, negative-with-IDs, old response shape and unsupported-only zero-choice case.
   Test both complete and actual Bedrock projections; a JSON example parsing is
   not evidence that the provider or native contract accepts it.
2. Prove native conversion across unrelated MOCK domains: one-to-many and
   many-to-one selections, inactive/mixed/foreign groups, reordered decisions and
   IDs, deterministic role/group order, stale packet/state/revision, allocation
   cleanup and exact producer attribution. Preserve existing group boundaries.
3. Exercise initial request, unchanged structural correction, correction exhaustion,
   authorized source/signal/disposition repair retirement and reassessment. All
   decisions unsupported must be a valid assessment on unsupported premises while
   R10 blocks mandatory authoring. Keep full candidate/readback coverage tests.
4. Freeze a single intervention and its schema/guidance before comparison. Hold
   model/settings, sources, purposes, eligible groups and labels fixed. Do not
   compare new requests using an old schema or silently decode old responses as new
   ones. Use separately pinned baseline/intervention builds or explicitly scoped
   diagnostic arms through existing replay owners, never a production dual reader.
   Reproject captured packets transparently or obtain fresh captures. The current
   [candidate switch](../test/harness/roles/cli.zig#L202) changes guidance only.
5. Preserve `missing_supported_roles`: the [current scorer](../test/harness/roles/score.zig#L38)
   counts a required role missing when no labelled supporting group was selected,
   including a selection made only on wrong groups. Add separate structural missing
   decisions, explicit false unsupported and false supported/wrong-basis counts.
   Optional/ambiguous labels must remain optional; unsupported verdicts on required
   roles are not quality passes. Keep unusable answers and all physical sends in
   declared denominators, with per-role/family results beside aggregate counts.
6. Existing `allowed_signal_ids` labels are alternatives: any one suffices. They do
   not establish cases needing combined groups. Add reviewed set-level evidence
   cases if collective support is part of the claimed outcome, plus multi-claim
   groups, actual native conflicting/inactive dispositions and genuine post-repair
   inputs. Do not fabricate captures or silently reinterpret existing labels.
7. The previous held-out cases are now inspected regression cases, not fresh blind
   confirmation for this intervention. Reserve new source families, review labels
   against their exact purposes/catalogue and check family separation across cohort
   files. Reuse approved labels only where meanings/facts are unchanged. The parser
   validates labels mechanically; it does not certify human entailment or approve
   another API allowance.
8. Before new calls, declare the bounded allowance and selection/tradeoff criteria.
   Compare semantic omissions and wrong selections together, with captured-case and
   unchanged-repeat regressions visible. Record request/schema/output bytes, actual
   tokens, all corrections, latency availability and measured durations. One initial
   request or zero missing decision fields is not a cost/quality improvement.
   Retain baseline if the comparison does not justify the intervention; add no
   automatic promotion or new application quality gate.
9. Only after those mechanics and a supported selection decision, verify complete
   live production publication, rubric grading of its actual specification and an
   unchanged repeat under [§28.7](../design/contracts/28-testing.md#287-end-to-end-tests)
   and [§28.8](../design/contracts/28-testing.md#288-model-conformance-comparisons).
   Diagnostic replay cannot supply workflow authority or substitute for E2E. Each
   diagnostic allowance and E2E invocation still needs its applicable explicit
   approval. Production quality remains open until that evidence exists.

**Review conclusion:** this is a bounded and testable candidate intervention at the
correct shared role boundary. Implementing only required fields would be local
incompleteness; reporting zero missing decisions as improved authoring would be
misleading. The proposed contract hardens observable completeness and preserves
fail-closed authority. Whether it reduces false negatives, wrong sources, ordering
sensitivity or actual E2E failure remains unproved.

**Research/verification limits:** reviewed current contracts, production and sibling
paths, retained 48-call results and independent code/evaluation audits; checked
primary AWS, JSON Schema and research sources above. No code changes, implementation
tests, live diagnostics or E2E runs were performed for this review. Earlier offline
test counts remain dated evidence for the existing implementation, not this proposal.
`git diff --check`, all 29 newly introduced local link/anchor targets and the
illustrative JSON's syntax check passed. The syntax check does not validate the
proposed native/provider contract. Independent evidence and cutover review found
no material discrepancy after the wording corrections above.

### 9.9 Complete role-decision implementation — 9 October 2026

**Authorization and status:** the user explicitly requested the coordinated
§9.8 cutover, including §17, ADR 0020 and ADR 0022 amendments. The implementation
is present across production, correction, repair, fixtures and calibration.
Offline evidence is recorded below. The user approved the prepared 48-call
diagnostic comparison after offline verification, and all 48 calls completed.
**Mechanical implementation and this bounded comparison are complete. Semantic
promotion is not supported by the results; production-quality acceptance remains
open.** Execution and results are recorded below.

#### Implemented contract and lifecycle

- The closed wire response requires `role_decisions`. Its native map derives its
  fields from the existing `GenerationRole` enum, with no defaults: every role is
  `supported` with nonempty unique eligible signal IDs, or `unsupported` without
  IDs. Native/provider schema agreement is mechanically tested. Sparse wire
  responses, missing/unknown/duplicate roles and malformed branches reject.
- [Shared role admission](../src/domain/reference_role_assignment.zig) checks the
  complete decisions, rejects duplicate/foreign selections and deterministically
  derives positive assignments in offered-group and registered-role order. It
  reuses existing retained-claim eligibility and assignment validation; production
  and calibration do not maintain separate semantic validators or conversions.
  Many-to-many support and existing group boundaries remain intact.
- [Phase packet projection](../src/domain/reference_reconciliation_stage.zig)
  narrows supported selections to eligible native occurrence IDs. With no eligible
  group it removes the supported branch, yielding a valid unsupported-only schema
  for every role; native code neither emits an empty enum nor fabricates verdicts.
  Current capture replay uses this same projection explicitly, preserving original
  facts, evidence, shared purposes and capture ancestry while refreshing
  contract-specific assignment instructions from the production context owner.
- Before assessment the complete table is `null`, meaning pending. Collection
  preserves exact packet/state/revision and producer checks. Signal or disposition
  repair retires the table and role origin before fresh assessment. Canonical
  snapshots retain derived positive `generation_roles`; captured responses retain
  negatives without adding a second persisted binding authority or state version.
- Existing immutable protocol correction and its two-correction allowance remain.
  Missing decisions are protocol defects. Complete unsupported answers are valid
  candidates and receive no correction-until-supported loop. **R10 is preserved:**
  absent mandatory positive coverage blocks authoring, with the actual role
  producer retained; unsupported does not authorize user clarification or entity
  `not_applicable`.
- Fixtures use complete mocked decisions. Reference-only repair tests supply an
  explicit fresh mocked assessment before normal validation; no production or
  fixture finish helper silently defaults pending state. Offline integration
  exercises an omitted decision recovering on attempt two and unchanged omission
  exhausting after three total sends, with no authoring or publication on failure.

The accepted wording in [§17](../design/contracts/17-specify.md),
[ADR 0020](../design/decisions/0020-derived-exact-reference-lineage.md) and
[ADR 0022](../design/decisions/0022-native-reference-phase-handoffs.md), the request
guidance and call-tree diagram are updated together. The overall design remains
Proposed. There is no new dependency, model slot, provider mode, cache behavior,
repair target, transition, default scenario or production compatibility reader.

#### Offline evidence

| Command | Result |
| --- | --- |
| `zig build test-reference-reconciliation test-reference-model-input test-model-candidate-json test-specification-generation --summary all` | 12/12 steps, 640/640 tests passed. |
| `zig build test-rubric-evaluator build-role-calibration --summary all` | 5/5 steps, 119/119 tests passed. The subsequent unscored Markdown-row correction also passed 119/119 evaluator tests. |
| `zig build test-integration --summary all` | 5/5 steps, 90/90 tests passed; fixed offline cases remain separate from live E2E. |
| `zig build lint --summary all` | 2/2 steps passed. |
| `zig build test-reference-model-input test-rubric-evaluator build-role-calibration --summary all` | Final shared-context projection and allocation-failure regression: 8/8 steps, 283/283 tests passed. |
| `zig build verify build-role-calibration --summary all` | Final complete offline CI: 136/136 steps, 1357/1357 tests passed, including architecture and packaged clean-environment smoke checks. |
| `git diff --check` | Passed. |

Owning-boundary regressions cover every missing role, duplicate and escaped JSON
keys, closed branches, empty/duplicate/foreign/inactive support IDs, empty/all-inactive
catalogues, native ordering under key/selection permutations, many-to-many bindings
and successful/rejected/allocation-failure cleanup. Existing state/revision,
upstream retirement, reassessment, R10 and canonical readback tests remain active.
Integration verifies immutable original request/schema bytes, correction origin,
unchanged exhaustion, exact usage accounting and failure propagation. Independent
code review found no blocking duplication, legacy reader, gate bypass or weakened
assertion. A sandbox restriction on Homebrew compiler library reads required
rerunning offline verification with read access enabled; it was not a code failure.
The paired-packet audit identified stale sparse-response assignment instructions
in historical calibration inputs. Production and replay now share the role-context
builder; replay refreshes only contract instructions while preserving exact facts,
evidence and purposes. A direct allocation-failure regression covers its uniformly
owned returned purposes. Final verification includes these follow-ups. Earlier
prepared current packets are superseded, not live evidence.
All 54 introduced local Markdown file targets and `git diff --check` pass. Twenty
pre-existing links to older generated E2E artifacts are unavailable in this
workspace; their historical statements are not new verification evidence. The
baseline and current comparison artifacts linked in this section are present.

#### Frozen comparison preparation and remaining acceptance

The [calibration plan](../test/calibration/authoring-roles/README.md) declares one
intervention: complete required decisions plus their branch instruction versus
the pre-cutover sparse contract. The old executable and runtime schema/prompt were
pinned before editing; their hashes and byte-identical cohort/capture copies are
retained in [the baseline manifest](../zig-out/role-contract-baseline/manifest.json).
Actual files preserve the filesystem adapter's no-symlink rule. Each arm uses its
own matching compiled production decoder; historical evidence is unchanged.
The [frozen paired-plan manifest](../zig-out/role-contract-comparison/manifest.json)
and [current executable/asset hashes](../zig-out/role-contract-comparison/implementation.json)
identify the exact prepared requests. All **24 paired trials** have identical
facts, evidence, purposes, labels, eligible IDs, settings, ancestry and repeat
bodies. Permitted differences are response schema, contract guidance and
`assignment.constraints`; the latter is deliberately reprojected for captures,
not mistaken for unchanged historical request bytes. These preparation artifacts
retain `not_run`; the distinct live reports below retain actual outcomes.

The prepared plan is **48 new physical diagnostic calls maximum**, split between
the two arms with two unchanged repeats per case: controlled development 24,
captured production inputs 8 and the formerly held-out regression cases 16.
Those known cases are not fresh blind confirmation. Settings, source bytes,
shared role purposes, eligible IDs and labels are held fixed. No experimental
guidance file, correction or repair is included. Offline preparation makes no API
call. The user subsequently approved exactly these 48 live calls under §28.8;
that allowance is now fully consumed, with no correction or repair sends.

Current reports separate structural missing decision fields, semantic required-role
omissions, explicit false unsupported decisions and wrong selections, with per-role,
family, repeat, protocol/native rejection and cost evidence. Unscored semantic rows
are unavailable, not zero. The sparse baseline cannot establish explicit false
unsupported decisions; that metric is unavailable there. Its semantic omissions
remain directly comparable. Rejected answers remain in all-trial denominators.

A full map is not the selection criterion. Improvement must reduce semantic
omissions without worsening wrong selections, or reduce wrong selections without
worsening omissions, while exposing captured, family and repeat regressions. If
the comparison is inconclusive or worse, it supports no semantic promotion claim.
The mechanical contract is implemented; **improved semantic outcomes are not yet
established**. Fresh-family, collective-support and genuine post-repair evidence
retain the limits identified in §9.8. Actual live workflow publication, rubric
quality and an unchanged E2E repeat require their separate approvals and remain
unmet acceptance evidence.

#### Live comparison and selection — 9 October 2026

All six approved invocations completed: **24 sparse-baseline and 24 complete-contract
physical sends**. All 48 have received response evidence and actual usage; there
were no transport/operational or native-selection rejections. Pinned hashes still
match. The old and new arms use their matching compiled production decoders, with
no production legacy path. Independent request/scoring/accounting audits and the
[aggregate results](../zig-out/role-contract-comparison/results.json) retain exact
cohort, case, role, unchanged-repeat, byte and cost evidence.

| Premises | Baseline report | Complete-contract report |
| --- | --- | --- |
| Controlled development, 12 calls per arm | [Sparse](../zig-out/role-contract-baseline/workspace/zig-out/role-calibration/2026-10-09T06-17-25Z-bbb4feab5c2f7d8f02411f265193584f/report.json) | [Complete](../zig-out/role-calibration/2026-10-09T06-18-19Z-d474da10eff0b18db73e705b556d797a/report.json) |
| Captured inputs, 4 calls per arm | [Sparse](../zig-out/role-contract-baseline/workspace/zig-out/role-calibration/2026-10-09T06-19-05Z-d3b7f1fc158a665ea6f026211e712495/report.json) | [Complete](../zig-out/role-calibration/2026-10-09T06-19-53Z-9ac586af01316a09b1bed7bebbb00172/report.json) |
| Known regression, 8 calls per arm | [Sparse](../zig-out/role-contract-baseline/workspace/zig-out/role-calibration/2026-10-09T06-21-08Z-d3f49e948f0262d1ce175571fc8f25fd/report.json) | [Complete](../zig-out/role-calibration/2026-10-09T06-22-26Z-01efd82726a97ecb832997b48385c38d/report.json) |

| Measure | Sparse baseline | Complete contract |
| --- | ---: | ---: |
| Declared physical calls / completed replays | 24/24 | 24/24 |
| Admitted and semantically scored answers | 24/24 | 22/24 |
| Protocol rejection: missing final text | 0 | 2 |
| Structural missing decisions | Not defined by sparse contract | 0/132 decisions across 22 answers; 2 answers unknown |
| Required-role omissions, conditional on admission | 35/124 | 38/117; 7 required-role premises unscored |
| Explicit false unsupported verdicts | Unavailable | 38/117 |
| Wrong-basis selected pairs | 39 | 0 |
| All unsupported / assigned pairs | 41/156 | 2/87 |
| Exact semantic trials / all trials | 4/24 | 4/24 |
| Provider-reported input / output tokens | 27,344 / 5,840 | 39,160 / 4,602 |
| Total provider-reported tokens | 33,184 | 43,762 |
| Sum of measured replay duration | 58.422 s | 46.448 s |

**Denominators matter:** the two rejected current answers represent seven required
role premises whose semantics are unknown. They are neither correct assessments
nor zero omissions. Current observed omissions exceed baseline even before those
unknown premises; unequal admitted denominators must not be presented as an
omission-rate improvement. Every observed current omission is an admitted explicit
unsupported judgment, not an absent decision field. The sparse response cannot
distinguish a deliberate negative from an unassessed role.

The whole comparison consumed **76,946 actual tokens**. Native request schema
contributions total 10,936 bytes for baseline versus 56,856 for complete; serialized
request bodies total 147,706 versus 246,890 bytes. Complete decisions increase
request and token cost in this sample. Thirty-seven answers use existing response
normalization (23 baseline, 14 complete). Duration is measured replay time including
preparation, dispatch, parsing and evidence recording; provider latency is absent
for every trial. No provider-speed or caching improvement is established.

| Premises | Required-role omissions: baseline → complete | Wrong-basis pairs: baseline → complete | Current false unsupported | Current unusable answers |
| --- | --- | --- | ---: | ---: |
| Development | 22/62 → 24/62 | 29 → 0 | 24 | 0 |
| Captured production inputs | 1/24 → 0/24 | 4 → 0 | 0 | 0 |
| Known regression | 12/38 → 14/31, with 7 premises unknown | 6 → 0 | 14 | 2 |

Both captured inputs are exact on both current repeats; that is a useful isolated
routing improvement. It does not erase unrelated regressions. Parcel omissions
move 9/24 → 10/24 across source-order variants; lamp omissions move 8/24 → 9/24.
The rule-only inventory's missing basis is recovered, but two unsupported optional
story selections remain. Wayfinding omissions rise 4/8 → 5/8. Coupon and incident
premises go from four exact baseline trials to two false-negative answers and two
unusable answers. Spoken-timer omissions fall 12/24 → 8/24 while order sensitivity
remains: current source-order variants miss 2/12 versus 6/12.

Across admitted answers, current missing decisions by purpose are title 16/22,
description 0/17, primary goal 0/18, story 5/16, entity basis 7/22 and records 10/22.
Some provider traces still interpret the absence of a ready-made title or complete
acceptance-criterion wording as absence of support, despite shared purposes and
guidance explicitly allowing derivation. This illustrates an observed semantic
misinterpretation; it does not establish the internal cause of every negative.
Unchanged repeats differ on both arms. The complete map makes negative decisions
observable; it does not establish reasoning fidelity or deterministic selection.
Independent recomputation confirms differing semantic/outcome results in 7/12
baseline case pairs and 4/12 complete-contract pairs; the latter includes two
scored/rejected pairs. A lower variation count does not establish correctness.

The two current unusable answers are `coupon-undecided-outcome` repeat 2 and
`incident-retention-conflict` repeat 1. Each raw provider response is HTTP 200 with
finish reason `stop`, containing only a leading reasoning block and no final
answer after its closing tag. The adapter therefore correctly reports
`missing_final_text`; this is **not a malformed JSON document, missing map property
or loss of JSON during normalization**. Reasoning is not a candidate decision and
cannot substitute for the missing final payload. These diagnostics exercise no
correction, so production recovery or exhaustion is not established by this sample.

**Selection:** the predeclared no-omission-regression condition is not met. Do not
promote this comparison as an overall semantic fix or infer publication/rubric
success. The requested mechanical hardening remains implemented in the working
tree, with R10 and all existing policy intact; no release or new success rule is
introduced. Do not force positive roles, reinterpret unsupported as a user gap,
accept reasoning as JSON, add a semantic retry or route by fixture/content-kind to
make these cases pass. The next semantic work needs a separately declared
false-negative experiment on the shared authoring purposes, plus the existing
generic missing-answer recovery investigation, with these regressions retained.
That follow-up is outside this contract cutover and grants no additional model calls.

### 9.10 First authoring error and its consequences — 9 October 2026

**Scope and status:** detailed analysis of the user-reported
[17:31:50 AEDT run](../zig-out/e2e-spec/2026-10-09T06-31-50Z-d8b1413594de14f45b366c7242397e2e/report.md),
with documentation changes only. Current HEAD is
`241a0c42653ecde998985548e1f86efe279cc0f5`. The executed build reports modified
revision `6e7eec648185a9711284c25e2829892d0c1c9d9c`, source digest
`34398c15ecfad9f2a0c44219c8154f7ff59eda561af321f8aa824997a596003f`.
The inspected generation, typed-text, provenance, coverage, projection, schema,
envelope and loss-admission source files, generation resources and workflow YAML
match their captured bytes in `build-inputs.json`. This binds the following code
analysis to the executed behavior without assuming that the two commit IDs match.

**Finding:** the first clear authored-content failure is **call 10**, which replaces
the user story with three exact references to the greeting. All required source
meaning reached that request. Shape and reference validation admit the response;
semantic review detects the omission at call 16. Incorrect localization at call
17 then sends that candidate defect to upstream repair. The terminal error at
call 55 is budget exhaustion, a consequence of the later workload rather than the
origin of the story defect.

The report's `first_observed_defect` names **call 26's missing final text**. That
field is the first captured protocol/native rejection in its event chronology,
not a claim that earlier authored content was semantically correct. Keep call 10's
bad candidate, call 16's finding, call 26's recoverable response defect and call
55's terminal budget rejection distinct.

#### Input, actual answer and expected meaning

[Call 10's captured context](../zig-out/e2e-spec/2026-10-09T06-31-50Z-d8b1413594de14f45b366c7242397e2e/evidence/generation/call-000010/context.json)
contains:

- Claims 1–3: successful startup, display `Hello, World!` when started, and output
  date/time in UTC. The original reference and citations are also present.
- Preserved-token claim 4: the exact greeting, available for insertion into prose.
- A story purpose requiring a source-backed actor, action and intended result;
  the source need not already use story format.
- Shared guidance defining the array as concatenated fragments, strings as prose,
  and an exact reference as an embedded literal that alone cannot express behavior.
- The focused instruction to express the behavior in one coherent narrative.

The normalized payload represented by the
[raw model output](../zig-out/e2e-spec/2026-10-09T06-31-50Z-d8b1413594de14f45b366c7242397e2e/evidence/generation/call-000010/model_output.txt)
is:

```json
{"kind":"primary_user_story","value":[
  {"kind":"exact_copy","claim_id":4},
  {"kind":"exact_copy","claim_id":4},
  {"kind":"exact_copy","claim_id":4}
]}
```

That resolves to `Hello, World!Hello, World!Hello, World!`. It contains neither a
startup action nor the UTC obligation, and no coherent actor/action/result story.
The expected result is meaningful source-backed prose with the literal inserted
where needed; there is no single required sentence. The later
[call 33](../zig-out/e2e-spec/2026-10-09T06-31-50Z-d8b1413594de14f45b366c7242397e2e/evidence/generation/call-000033/model_output.txt)
supplies one acceptable example:

```json
{"kind":"primary_user_story","value":[
  "As a user, when I start the application, it must start successfully and display ",
  {"kind":"exact_copy","claim_id":4},
  " and output the current date and time in UTC."
]}
```

Call 40 subsequently assesses that story as supported. This is an observed
semantic assessment, not deterministic proof or a new golden-output requirement.

#### Why it passed the early boundaries

| Boundary | Verified behavior | What it does not establish |
| --- | --- | --- |
| Shared text schema | [Business-value alternatives](../design/workflows/spec/generation.schema.json#L15) permit strings and eligible `exact_copy` objects. [Choice projection](../src/domain/reference_model_input.zig#L169) retains the string alternative. | A nonempty array need not contain prose or express its assigned purpose. |
| Provider schema | The captured `request.json` retains both alternatives. [Schema projection](../src/domain/model_schema_projection.zig#L162) converts the disjoint `oneOf` branches to `anyOf`. | There is no evidence this conversion forced reference-only output. Both correct and defective responses fit the offered alternatives. |
| Provider/envelope normalization | Call 10's raw provider response already contains the three references and no narrative in its final answer. The [prefix parser](../src/domain/model_envelope.zig#L29) slices the known malformed opening and preserves the remaining JSON. | Neither removal of leading reasoning nor prefix normalization explains missing prose; it was absent from the final payload before normalization. |
| Native story admission | [Generation validation](../src/domain/specification_generation.zig#L125) calls the shared attributed-text validator. [Typed text](../src/domain/typed_text.zig#L147) accepts each eligible exact reference and marks it visible. | It does not establish narrative meaning, and repeated references are not invalid under the current text contract. |
| Lineage and coverage | [Provenance](../src/domain/specification_provenance.zig#L81) combines bound claims 1–3 with referenced claim 4. [Coverage](../src/domain/specification_coverage.zig#L44) checks claim/token associations. | Attached lineage does not prove the text expresses each attached claim. Preserving the greeting is not preservation of the startup and UTC behavior. |
| Resolved text | [Projection](../src/domain/specification_projection.zig#L42) concatenates the supplied segments in order. | It cannot invent the missing narrative. Repetition is in the model payload, not introduced by rendering. |

These native checks enforce their current contracts. The architectural exposure
is that a shape-valid, source-bound candidate can still carry almost none of the
required meaning; its rejection depends on semantic review. Removing that
distinction or presenting lineage as entailment would weaken the authority model.

**What is known about the model's choice:** the retained
[call 10 provider response](../zig-out/e2e-spec/2026-10-09T06-31-50Z-d8b1413594de14f45b366c7242397e2e/evidence/generation/call-000010/response.json)
contains a reasoning summary recognizing the need for a narrative and both string
and exact-reference fragments. Its final answer contradicts that description.
That is evidence of an intention/output mismatch, not a reliable causal account
of decoding or provider behavior. The trace cannot prove why the final answer
chose only references, why it repeated them three times, or whether constrained
generation contributed. Claims of missing directions, unavailable facts or
adapter-deleted narrative are contradicted by the captured data.

**Strong within-run comparison:** calls 10 and 33 have byte-identical serialized
provider requests: **6,671 bytes**, SHA-256
`ec6594144dbe7681cac331198b91c55f8ccd7be8e8581512f81de2bfc9849877`.
Their context content and response schemas also match. Both use Bedrock
`openai.gpt-oss-20b-1:0`, low reasoning and temperature 0. Their answers differ.
Thus the upstream repair did not improve the story's instructions or data; the
second answer demonstrates output variation under the same captured request.
This pair cannot establish a failure rate or isolate the provider/model mechanism.

#### Why the first defect caused unnecessary upstream work

Call 16 correctly identifies a missing narrative, although its explanation also
mentions that the source is not itself a narrative. The request explicitly allows
deriving a story from requirements, so lack of prewritten story prose is not an
upstream source defect.

[Call 17's localization packet](../zig-out/e2e-spec/2026-10-09T06-31-50Z-d8b1413594de14f45b366c7242397e2e/evidence/generation/call-000017/context.json)
shows all three requirements in the original source, extracted claims and
reconciliation signal 1. Only the candidate story has collapsed to greetings.
The existing [loss prompt](../design/workflows/spec/support-loss.prompt.md) already
says to distinguish poor authoring from upstream loss and return `unlocalized`
when meaning survives the producers. Nevertheless, the response selects
`{"kind":"reconciliation_signal","ordinal":1}`. The supplied evidence supports
a candidate-local omission, not loss at that signal.

The code explains how this wrong attribution reaches repair:

1. [Available locations](../src/domain/source_omission.zig#L222) enumerate
   mechanically eligible producers, explicitly without judging semantic loss.
2. [Location binding](../src/domain/specification_support_model.zig#L90) derives
   diagnostic claims from the selected signal. The
   [validator](../src/domain/source_omission.zig#L193) checks that the signal exists,
   its claims match and they belong to the cited sources. It cannot prove the
   claimed content loss. The localization response carries only a location,
   without a distinct source-versus-producer loss explanation.
3. [Repair authorization](../src/domain/reference_reconciliation_repair.zig#L710)
   pins signal 1's content, old value, revision and dependencies. Those protections
   work, but do not reassess whether that signal is the defective producer.
4. Call 30 paraphrases the already-preserved requirements. The merge invalidates
   dependent role decisions, generation and review; it remains pending dependent
   validation rather than proving successful repair. Calls 31–35 rebuild them.

The existing candidate-local route is not missing. The
[repeated-display-text regression](../src/specification_generation_test.zig#L4251)
supplies a **mock** omission with no established upstream loss, selects a story-only
repair and verifies that sibling units remain unchanged. The
[workflow handoff](../design/workflows/spec.workflow.yaml#L850) already distinguishes
that route from upstream repair. This test proves the mechanics conditional on
correct review/localization; it cannot prove that the live model chooses them.

Regeneration fixes the story in this run but harms previously usable records:
call 12 wrote meaningful acceptance and functional text; call 35 replaces every
`given`/`when`/`then` and functional `text` field with the greeting reference alone.
Those requests share guidance, schemas, bound claims, original sources and record
purposes; only regenerated brief and entity-basis wording differs. Neither packet
contains the repaired signal's text. This is a second manifestation of the shared
authoring failure class, not evidence that a story-only patch would suffice.

Across the run, source review and localization consume **69,499 tokens in 37
calls**; three missing-final-text responses recover through correction. Call 55
adds 2,424 tokens to 97,619 already used, crossing 100,000. ADR 0011 requires that
accounted stop. Publication and rubric evaluation are not reached. Raising the
budget might permit more work; it would not establish valid content or correct
repair attribution.

#### Required follow-up and feasibility

These findings refine **R7, R6 and R5**, without reopening completed role-contract
mechanics or introducing another implementation checklist:

1. **R7 — investigate the shared authoring failure first.** Reuse production
   packet/schema/admission capture for a bounded comparison of complete story and
   record-field assignments. Include this failure, unchanged repeats, unrelated
   business domains, prose-only behavior, embedded literals and legitimate repeated
   literals. Label preservation of actor/action/outcome, conditions and obligations,
   separately from JSON admission and exact-byte preservation. Existing fake tests
   remain mechanical evidence, not semantic ground truth. Freeze one proposed
   change and its success criteria before approved live trials; do not claim a
   prompt, reasoning setting or schema rewrite is already a fix.
2. **R6 — measure and strengthen loss attribution through its existing owner.**
   Include intact producers with candidate-only loss, genuine extraction and signal
   loss, ambiguous ownership, and source-only meaning absent from all claims.
   Preserve the fixed correct omission verdict and use the existing candidate-local
   repair where no upstream defect is established. A richer closed loss-evidence
   response may make the comparison inspectable, but does not prove semantic truth;
   any proposed contract change must cover initial collection, correction, evidence
   validation, repair, invalidation and readback. New adjudication or retry policy
   still requires the R6 design decision. Another reviewer is not an established fix.
3. **R5 — measure the downstream cost and actual completion.** Compare unnecessary
   upstream repairs, regenerated valid siblings, repeated review and actual tokens
   as well as first-pass meaning. A diagnostic improvement must still be followed
   by separately approved E2E publication and rubric evaluation. Do not remove
   required validation, reuse stale findings or increase allowances to manufacture
   a passing result.

**Avoid brittle repairs:** do not ban this greeting, impose a specific story phrase,
deduplicate exact references, or require a prose fragment in every business value.
[ADR 0020](../design/decisions/0020-derived-exact-reference-lineage.md#L26)
explicitly preserves repeated text while deduplicating dependencies; legitimate
exact-only titles are covered by existing tests. A required string could contain
irrelevant prose and still omit behavior. Any justified representation change
belongs to the shared business-text/schema/codec boundary across initial authoring,
selected repairs and sibling fields, with explicit exceptions derived from field
purpose rather than this example. More instructions alone are unsupported as the
answer: the captured requests already state the rules that were violated.

**Validation of this analysis:** inspected both raw and projected responses,
captured contexts/provider schemas, report/attempt accounting and repair events;
compared call 10/33 request bytes and call 12/35 packet components; matched the
relevant code/resources to captured build inputs; independently audited authoring
admission and loss routing. Only FIX01 is changed. `git diff --check` and all 25
new local link/anchor checks passed; no implementation tests, new model calls or
E2E runs are claimed. The exact provider/model cause of the divergent final
answers and a proven production remedy remain unresolved.

### 9.11 Authoring-input simplification — 9 October 2026

**Scope:** implement the user's requested clearer inputs for less capable models,
while keeping the engine generic. This addresses the presentation and unnecessary
reference-selection work identified after §9.10. It does not claim to establish
the internal cause of call 10's answer or to fix semantic loss attribution.

**Implementation:**

| Change | Owning implementation and resulting behavior |
| --- | --- |
| Resolve assigned meaning beside field purpose | `model_evidence.requirement` resolves each validated claim into `claim_id`, semantic `kind`, `meaning` and `source_id`. `specification_source_binding.guidance` places these requirements beside the existing shared field purpose. It derives them from the retained ledger; it does not create another source of support. |
| Remove authoring bookkeeping | `specification_session.packetForOptions` presents unassigned semantic claims as `context_requirements`, excludes assigned duplicates from that list, and retains complete original source bytes. Citation coordinates, extractor identities and token bookkeeping stay native. Exact literals have one compact `preserved_tokens` catalogue with occurrence ID, value and source ID. |
| Give one active operation | Initial prompts say to write their assigned unit. Native unit repair selects the configured repair prompt and retains only its authorized task purpose. Protocol correction preserves the same operation, packet and selected schema. Repair insertion/replacement remains determined by its existing authorization. |
| Clarify narrative and text responsibilities | The shared purpose owner identifies a source-backed actor **or system**, action and result, without requiring a prewritten story or inventing a persona/benefit. Shared context explains ordered prose/reference fragments and the distinction between exact display values and behavior; it no longer carries simultaneous authoring/repair commands. |
| Construct a determined exact handle | The existing integer-choice contract explicitly marks native singleton construction. With exactly one eligible occurrence the selected schema omits `claim_id`, and the shared codec constructs it from the retained choices. Echoed IDs reject. With multiple eligible occurrences the model still selects an eligible ID; with none the exact-reference alternative is unavailable. Other singleton selectors are unchanged unless their owning contract explicitly opts in. |
| Apply the wire contract throughout its lifecycle | Initial generation collection, selected native repair, reviewed omission repair and generic atomic repair use the shared construction function. Composition retains canonical constructed content separately from immutable raw provider evidence; correction retains the original choices. Scripted offline fixture responses use the new wire form. Canonical/persisted values keep their existing exact claim IDs. |

The singleton rule implements the already accepted
[ADR 0020 representation](../design/decisions/0020-derived-exact-reference-lineage.md#boundary-and-representation).
It selects neither semantic support nor among several occurrences and does not
infer identity from matching text. The implementation uses the existing schema,
packet, codec and reference owners; no new model call, cache behavior, repair
policy, state version, compatibility reader or provider-specific branch is added.
The governing [§17](../design/contracts/17-specify.md),
[§22](../design/contracts/22-repair.md),
[request guidance](../design/reference-notes/model-request-guidance.md) and
[call tree](../design/diagrams/21-spec-model-call-tree.md) reflect the new projection
and active prompt selection. Historical references to combined writing/repair
prompts are superseded by this implementation.

**Offline evidence:** the regression suite checks resolved passive/source display
values, unchanged original sources and native bindings, absence of redundant
authoring bookkeeping, and shared purposes across authoring and selected repair.
Exact-reference coverage includes no/single/multiple choices, echoed and foreign
IDs, repeated exact segments, immutable protocol correction, composition and
allocation failures. Direct repair tests use literal shorthand payloads, verify
the reconstructed canonical ID and reject echoed handles. Omission repair proves
that the selected story changes while sibling units and lineage remain intact.
Unrelated sources are included; fake outputs establish mechanics only.

Targeted commands passed:

- `zig build test-reference-model-input --summary all`: **165/165** tests.
- `zig build test-model-result-schema test-model-candidate-json --summary all`:
  **119/119** tests; the final composition adjustment was rechecked through
  `zig build test-model-result-schema --summary all`: **55/55** tests.
- `zig build test-model-request-workflow --summary all`: **355/355** tests.
- `zig build test-specification-generation --summary all`: **251/251** tests.

**Status: implemented and offline-verified.** `zig build verify --summary all`
completed successfully (exit 0), including the complete unit suite, separate
offline integration harness, formatting/architecture checks and native packaged
clean-environment smoke checks. `git diff --check` passed. No tests or validators
were disabled or weakened. Initial sandbox restrictions on the installed Zig
compiler/cache required an approved tool escalation for offline verification.

**Remaining uncertainty:** a model can still return exact references without the
required narrative, or choose the wrong reference when several are eligible.
Repeated references and legitimate exact-only values remain legal; there is no
mandatory prose-fragment workaround. Source review, R10, exact coverage and
publication gates remain required. The new inputs reduce lookup and formatting
work, but improved first-pass meaning, repair routing, publication and rubric
quality require the separately approved comparisons described in §9.10. No live
model calls or E2E runs were made for this implementation.
