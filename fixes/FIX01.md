# FIX01 — Critical review of the revised Spec workflow handoff

**Review date:** 9 October 2026, Australia/Melbourne.

**Tracking status:** Sole active fix record. Completed implementation and dated
approval/run history are retained in [archive/](archive/); their old plans and
status statements are historical. This document owns the outstanding work below.

**Verdict:** The handoff identifies the right reliability problem and is broadly
compatible with the generic engine. It is feasible as a staged improvement
programme, but is **not yet a complete implementation specification**. Several
items already exist; source-association precision, semantic acceptance criteria,
review grouping and disputed-verdict handling still need explicit decisions.
The bounded R3 policy projection and R4 shared family meanings are complete within
existing boundaries, with full offline verification. The first 9 October live
evidence for R3 confirms resolved inputs and no recurrence of the observed
`singleton` confusion, but still ends at the token budget without publication or
grading. Its remaining semantic and workload limits are recorded in R3 and R5.
The later post-R4 run confirms delivery of the shared meanings but omits every
functional-requirement record. Native validation rejects the candidate before
policy review; no improvement in completion or rubric quality is established.
R4 now implements the requiredness/collection projections identified by that run;
their live effect remains unmeasured.
The subsequent 09:07 run stopped earlier: role assignment omitted `entity_basis`
despite unchanged request bytes, and generation initialization rejected the
incomplete binding. R10 records this separate role-coverage handoff weakness;
the latest R4 projections were not reached. R10 now implements an explicit typed
blocking result with missing-role and producer evidence. The 11:53 post-R10 run
confirms that handling and correct attribution to call 7, but the model again
omits `entity_basis`; generation, publication and grading remain unachieved.
A separate, confirmed
clarification-answer lifecycle gap prevents
claiming complete support for answer-derived requirements.
No evidence currently establishes that the proposed changes will produce a
completed, faithful specification with the configured model and execution budget.

This review and tracking document introduces no engine policy, new test authority
or live-run authorization. The original review changed only this file; folder
cleanup is recorded in §8. The user subsequently authorized the bounded R3, R4
and R10 implementations. Their code, prompt and offline verification are tracked
below; R3, R4 and R10 also record subsequent retained live-run analysis. The other
findings remain separate work.

**Material revisions:** corrected overstatements about the handoff and current
traceability, completed the clarification-path audit, separated implementation
feasibility from semantic reliability, and added a research-backed evaluation
method with explicit measurement limits. R10 adds the observed incomplete-role
handoff and implements its typed blocking contract. Automatic upstream correction
remains a separate policy decision.

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

Before the original review, the worktree contained an integration/build refactor in
`README.md`, `build.zig`, `build.zig.zon`, `build/test_registration.zig`,
`integration.zig`, `scripts/test-integration.sh`, `src/architecture_test.zig`,
`src/composition/root.zig`, `tests.zig` and untracked
`test/integration/workflow_tests.zig`. Those changes were preserved. Historical
test counts are not verification of this current dirty tree.

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

The local raw run bundles are available, unlike the handoff's GitHub-only review.
The most recent retained run started 9 October at **11:53:40 AEDT**
(`2026-10-09T00:53:40Z`), after R10 implementation. The preceding run started at
09:07:58 AEDT; the earlier post-R4 run started at 08:34:58 AEDT;
its pre-R4 baseline started at 07:59:10 AEDT. The earlier R3 comparison uses
8 October at 20:52:37 AEDT:

| Evidence | Confirmed result | What it establishes |
| --- | --- | --- |
| [8 October, 18:35 run](../zig-out/e2e-spec/2026-10-08T07-35-30Z-7107d1f32946458299ddf2447658f947/report.json) | 37 exchanges; 105,405 / 100,000 tokens; no publication or rubric result. | The prior workload exceeded its execution budget. |
| [8 October, 20:52 run](../zig-out/e2e-spec/2026-10-08T09-52-37Z-975dd393a88db44ce1b06fb0f92fc8f4/report.json) | 39 exchanges; 101,476 / 100,000 tokens; no publication or rubric result. | Call 35 lacked final text; call 36 recovered JSON; call 39 hit the budget before admission. |
| [Pre-R3 call 36](../zig-out/e2e-spec/2026-10-08T09-52-37Z-975dd393a88db44ce1b06fb0f92fc8f4/evidence/generation/call-000036/model_output.txt) | Admitted explanation treats internal `feature: singleton` as a “singleton implementation.” | Structurally admitted review can assess invented product meaning. |
| [9 October, 07:59 run](../zig-out/e2e-spec/2026-10-08T20-59-10Z-043b83091ff4ee6016e285ca11a2af0c/report.json) | 37 exchanges; 105,735 / 100,000 tokens; seven policy findings admitted; no publication or rubric result. | R3's resolved inputs are in use; call 37 stops on budget without a correction retry or repair. |
| [9 October, 08:34 post-R4 run](../zig-out/e2e-spec/2026-10-08T21-34-58Z-08faa42fc180e22e11a0e27cd7f459d0/report.json) | 34 exchanges; 59,850 / 100,000 tokens; `workflow_invalid` at omission authorization; no policy review, publication or rubric result. | Shared meanings reached generation and source review, but call 12 omitted functional requirements and the positive source review did not supply an eligible omission repair. |
| [9 October, 09:07 run](../zig-out/e2e-spec/2026-10-08T22-07-58Z-81991f12973d8466095855fd3d3399e0/report.json) | 8 exchanges; 12,148 / 100,000 tokens; `workflow_failed` at generation initialization; no specification authoring, review, publication or rubric result. | Call 7 omitted `entity_basis` with byte-identical inputs to the preceding run; R10 traces the incomplete binding and generic failure. The latest R4 projections were not exercised. |
| [9 October, 11:53 post-R10 run](../zig-out/e2e-spec/2026-10-09T00-53-40Z-ab59e9144c1aff2ce96a9816c782f782/report.json) | 8 exchanges; 12,123 / 100,000 tokens; `workflow_blocked` at generation initialization; no authoring, clarification, repair, publication or rubric result. | R10 retains missing `entity_basis`, source state/revision, eligible groups and call 7's origin. The same role omission persists; explicit handling improves, completed-spec outcomes do not. |
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

**Status — 9 October: COMPLETE for shared meanings and the two input-projection
follow-ups.** Semantic calibration remains R7 work. The 08:34 run below predates
the follow-ups; the 09:07 run stopped before their affected calls (R10). Neither
establishes their live improvement; offline verification is recorded separately.

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
records purpose for an active repair while preserving its source selection. It
does not repeat the full catalogue or add a second copy of the selected task.
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

### R7 — High: focused role calibration complete; broader calibration remains open

**Complete — 9 October 2026: the requested focused semantic calibration of
authoring-role selection.** Tooling, human-reviewed labels, controlled and captured
premises, unchanged repeats, the fixed guidance comparison and held-out execution
are complete. This closes the bounded pilot, not broader generation/review/repair
calibration or production reliability. See the
[calibration instructions](../test/calibration/authoring-roles/README.md).

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

**Status — DONE for implementation and offline verification on 9 October.
No new live E2E or model comparison has been run for R9.** This improves retained
evidence, not authoring-role selection, model quality or workflow continuation policy.

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
| Preserve native operation failures | [Closed operation error contract](../src/domain/operation_error.zig) combines declared domain/port error sets. Application bindings propagate the original cause through the runner, CLI, telemetry and harness. Post-call token accounting retains invocation failure and reports its own revision errors precisely. Error names are static; allocation failure needs no allocated diagnostic and applies no candidate delta. Explicit invariant guards retain their existing generic failure. |
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

**Reconstruction limits:** a complete bundle retains the allowlisted source set.
Compiler/toolchain availability, target/build settings and declared dependency
hashes remain necessary external build inputs; dependency downloads are not copied.
Missing, excluded or redacted bytes explicitly prevent exact source reconstruction.
[Exact replay](../src/application/request_replay.zig) separately verifies regenerated
request bytes and rejects redacted parents. Current encoding changes can invalidate
replay, and identical request bytes do not guarantee identical future provider output.
Modified replay retains its overrides and cannot establish unchanged behavior.

**Regression coverage:** unrelated reconciliation/omission failures and OOM cross the
shared runner boundary without a delta; expected rejecting outcomes retain their
cause while success rejects it. Post-call accounting retains the invocation cause,
records unknown usage and reports a stale revision without replacing it with generic
failure. Provider rejection survives retirement and owner release, including
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
| 5 — Layered acceptance/reporting | R9 implements native cause propagation, linked observations, source reconstruction evidence and supplied-spec exchange capture, with full offline verification above. Acceptance rules remain separate work. | Apply the development acceptance contract separately. Diagnostic evidence does not establish model quality or publication success. |
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
   verification and reconstruction limits recorded above. They do not implement
   the answer lifecycle or change acceptance policy.
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
the subsequent R3, R4 and R10 implementation verification is recorded above.

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
