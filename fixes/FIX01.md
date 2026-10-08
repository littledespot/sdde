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
The bounded R3 policy projection is complete within existing boundaries. The
9 October live evidence confirms resolved inputs and no recurrence of the observed
`singleton` confusion, but still ends at the token budget without publication or
grading. Its remaining semantic and workload limits are recorded in R3 and R5.
A separate, confirmed
clarification-answer lifecycle gap prevents
claiming complete support for answer-derived requirements.
No evidence currently establishes that the proposed changes will produce a
completed, faithful specification with the configured model and execution budget.

This review and tracking document introduces no engine policy, new test authority
or live-run authorization. The original review changed only this file; folder
cleanup is recorded in §8. The user subsequently authorized the bounded R3
implementation. Its code, prompt, offline verification and subsequent retained
live-run analysis are tracked in R3;
the other findings remain separate work.

**Material revisions:** corrected overstatements about the handoff and current
traceability, completed the clarification-path audit, separated implementation
feasibility from semantic reliability, and added a research-backed evaluation
method with explicit measurement limits.

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
The most recent retained run started 9 October at **07:59:10 AEDT**
(`2026-10-08T20:59:10Z`). The comparison baseline is 8 October at 20:52:37 AEDT:

| Evidence | Confirmed result | What it establishes |
| --- | --- | --- |
| [8 October, 18:35 run](../zig-out/e2e-spec/2026-10-08T07-35-30Z-7107d1f32946458299ddf2447658f947/report.json) | 37 exchanges; 105,405 / 100,000 tokens; no publication or rubric result. | The prior workload exceeded its execution budget. |
| [8 October, 20:52 run](../zig-out/e2e-spec/2026-10-08T09-52-37Z-975dd393a88db44ce1b06fb0f92fc8f4/report.json) | 39 exchanges; 101,476 / 100,000 tokens; no publication or rubric result. | Call 35 lacked final text; call 36 recovered JSON; call 39 hit the budget before admission. |
| [Pre-R3 call 36](../zig-out/e2e-spec/2026-10-08T09-52-37Z-975dd393a88db44ce1b06fb0f92fc8f4/evidence/generation/call-000036/model_output.txt) | Admitted explanation treats internal `feature: singleton` as a “singleton implementation.” | Structurally admitted review can assess invented product meaning. |
| [9 October, 07:59 run](../zig-out/e2e-spec/2026-10-08T20-59-10Z-043b83091ff4ee6016e285ca11a2af0c/report.json) | 37 exchanges; 105,735 / 100,000 tokens; seven policy findings admitted; no publication or rubric result. | R3's resolved inputs are in use; call 37 stops on budget without a correction retry or repair. |
| [Loan run](../zig-out/e2e-spec/2026-10-07T11-57-52Z-935b3be1a46109edb237ebb287867251/report.json), analysed in [FIX_003 §14.5](archive/FIX_003.md#145-three-approved-live-executions-after-fix3-0910) | An omission/localization sequence led to insertion of already-captured behavior and dependent rebuilding; terminal budget exhaustion. | Incorrect semantic premises can consume valid repair machinery. |

Both 8 October reports identify modified builds at revision
`dd5e6e80169c1c0ba359ca9951e222654e7edc6c`, with different source hashes.
The 9 October report identifies a modified build at revision
`b021e9bfaeda53c6cda8c9896342a4776f77234b`, source hash
`65fe4bb339e123f961c991d8a598c5def7c72519b1baaf7a3fd365f217b8b14e`.
These are different captured builds, not a controlled comparison of one code
change. The latest request bytes independently establish that R3 was active.

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
| Define record-family contributions. | Useful remaining work. The proposed table omits two existing families and some shared guidance still collapses distinct meanings. |
| Resolve policy assignments before asking the model. | R3 now implements scalar, record, collection and entity projections. Latest live packets confirm resolved business subjects; semantic reliability remains unproven. |
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
continuation and persistence are unchanged. R4's family-purpose improvements are
still separate.

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
source-review path. Retain this as an R4/R7 generation-and-review evaluation case.
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

### R4 — Medium: the record-family proposal is incomplete and partly redundant

The current [Kind enum](../src/domain/specification.zig#L9) has nine variants.
The handoff lists seven, omitting `edge_case` and `entity`, and calls the existing
`user_visible_outcome` family “Outcome.” Use existing names and meanings rather
than adding aliases or a competing registry.

The [records prompt](../design/workflows/spec/records.prompt.md) already defines
functional requirements and acceptance criteria, distinguishes assumptions,
exclusions and prohibitions, and rejects filler. The real gap is the generic
`.text` purpose in
[required_authority_description](../src/domain/required_authority_description.zig#L35),
and incomplete family guidance supplied by the records role. Generation, source
review, policy review and selected repairs should project one coherent definition
from their existing shared owners.

Include edge cases as supported boundary/exceptional conditions and outcomes;
include entities only under the current applicability decision, with their
business meaning and relationships. Neither is permission to invent missing cases
or data structures. Preserve legitimate overlap: acceptance criteria can test the
same obligation that a functional requirement states.

The handoff's business-rule and outcome descriptions still overlap ordinary
requirements and the feature goal. Labels alone will not resolve this ambiguity;
the human-labelled cases must show when a separate record adds supported meaning
and when it only repeats another representation.

[equalContent](../src/domain/specification_generation.zig#L145) compares complete
tagged content. Identical wording under different kinds is not automatically a
native duplicate. The extra business rules in the 8 October, 20:52 run establish increased
workload and a redundancy concern, not authority for cross-kind string deletion.

**Feasibility:** high for complete shared purposes and calibration; conditional
for any new semantic rejection, reclassification or deletion policy. Measure the
generation improvement before adding a dedicated redundancy-review call.

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

The latest candidate has one acceptance criterion and three functional
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

### R7 — High: semantic calibration is essential but not yet specified or prepared

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

### R9 — Medium: diagnostics and reproducibility require upstream changes

The proposed capture work should be a gap-driven extension. Existing
[E2E trace](../test/harness/e2e/trace.zig),
[observation](../test/harness/e2e/observation.zig),
[model exchange capture](../src/application/model_exchange_capture.zig#L65) and
[report contracts](../test/harness/e2e/contracts.zig#L111) already retain substantial
request, schema, response, origin, usage, retry, repair and source-snapshot evidence.

There are concrete projection gaps: the
[event projection](../test/harness/e2e/trace.zig#L226) omits
`provider_content_diagnostic`, although the report holds it; the
[retained rejection observer](../test/harness/e2e/observation.zig#L25) tracks the
latest model-protocol rejection and does not capture provider-content failures
such as missing final text. The report also lacks a complete linked first-defect,
repair, invalidation/rebuild and outstanding-work projection. Reuse native evidence
for those additions instead of inferring the missing data from prose.

The cause-loss claim is confirmed:
[reference_reconciliation_workflow](../src/application/reference_reconciliation_workflow.zig#L137)
collapses operational errors to `OperationExecutionFailed`, and
[workflow_execution](../src/domain/workflow_execution.zig#L49) renders that as
`failed`. A harness renderer cannot reconstruct the discarded cause. Fix the
narrowest shared typed failure boundary and audit sibling bindings. Existing
[reconciliation diagnostics](../src/domain/reference_reconciliation_diagnostic.zig#L128)
and [candidate diagnostics](../src/domain/specification_candidate.zig#L16) already
retain typed field/rule/target evidence; this is not absence of all diagnostics.

The [operation binding signature](../src/ports/workflow_operation_registry.zig#L58)
returns the narrow `OperationError!Candidate` contract. Preserving richer causes
affects its producers, runner failure handling, cleanup/lifetime ownership and
CLI/telemetry/harness consumers. Allocation failure must remain reportable without
requiring another allocation. Keep expected typed domain rejection separate from
operational failures; do not publish a failed delta to transport a diagnostic.
This is cross-cutting work, not a report-field patch. No reconciliation-only
exception, arbitrary error/payload channel or diagnostic capability bag is warranted.

Chronology alone is not causation. Extend existing native origin, repair-target,
revision and invalidation links where absent; label inferred attribution. An early
recovered protocol error need not be the initiating semantic defect, and the first
semantic defect may remain unprovable without human review.

[build/provenance.zig](../build/provenance.zig#L4) records revision, a source hash and
a modified flag. It does not retain the modified source bytes. A hash identifies a
build input set but cannot reconstruct it. A reproducible bundle needs the relevant
allowlisted build inputs or a complete patch against an available exact base,
plus untracked/deleted-file evidence and declared compiler/dependency/build
metadata. Preserve existing redaction and
credential exclusion; report any missing or redacted bytes rather than claiming
exact reproducibility. This belongs to development evidence, not runtime authority
or checkpoint recovery.

Distinguish **source/build reconstruction**, **exact request resubmission** and
**reproduction of live output**. Existing
[exact replay](../src/application/request_replay.zig#L20) verifies regenerated
request bytes and rejects redacted parents; it uses current adapters and may reject
after encoding changes. A source snapshot improves reconstruction, but neither it
nor identical request bytes guarantees an identical future provider response.
Modified replay must retain its overrides and cannot establish unchanged behavior.

The supplied-spec evaluator also needs scrutiny before calibration: its
[CLI live invocation](../test/harness/cli.zig#L74) does not pass an exchange store.
Reuse the existing [evaluation trace store](../test/harness/evaluation_trace.zig)
for raw per-call evidence instead of implementing another capture system.

**Feasibility:** high for specific capture/report gaps; medium for preserving typed
causes across the shared operation boundary and packaging reproducible dirty builds.

## 4. Feasibility and decision matrix

Feasibility ratings above describe structural reuse and coupling, not delivery
estimates or probabilities of semantic success. “High” means an existing owner
offers a bounded implementation path; “medium” means coordinated contracts or
evaluation work remain. The intended model's reliability is empirically unproven
in every package. No numerical effort estimate is defensible from this review.

| Handoff package | Practical assessment | Decision or dependency before implementation |
| --- | --- | --- |
| 1 — Define/calibrate assignments | A bounded pilot is practical; full calibration is real remaining work. Existing whole-spec examples are insufficient and outdated. | Labels, task-specific metrics and a comparison plan for the pilot; approved thresholds/live allowance before live acceptance claims. Expand to all nine existing families before full-scope claims, without requiring each family in every spec. |
| 2 — Native traceability | Existing group provenance can be audited immediately. Narrower association and complete answer authority are separate coordinated changes. | Define precision and identity lifetime; amend ADR 0020 only if changing binding. Complete the separate authentication/answer/currentness contract before claiming answer-supported generation. |
| 3 — Resolved projections/workload | R3's resolved policy inputs are implemented and observed live. Complete workload feasibility remains unmet; grouping is a distinct, conditional experiment. | Preserve resolved scalar/record/collection/entity facts and separate instructions. A production cardinality or policy-selection change needs an explicit amendment and negative tests. |
| 4 — Evidenced repair | Projection/evidence improvements can preserve current policy. New premise reassessment is not active authority. | Define trigger, closed outcomes, currentness, one active finding and conserved allowance; obtain the required amendment before adding reconsideration. |
| 5 — Layered acceptance/reporting | Specific reporting gaps are bounded. Rich operation causes, dirty-source reconstruction and new acceptance rules have broader surfaces. | Extend existing capture first; separately design shared failure propagation and the development acceptance contract. A complete diagnostic redesign is not a prerequisite for the bounded projection pilot. |

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
   above; R4's family-purpose work remains open. These implementation steps can
   progress while separate acceptance decisions are pending; generalized claims
   of live improvement still require the declared, approved comparison.
3. **Decide traceability precision using the observed gap.** Keep current lineage
   machinery. If group-level attribution is insufficient, amend the binding/selection
   contract and update its complete consumer surface together; do not add metadata
   that only makes broad attribution look more precise. Scope the confirmed answer
   lifecycle gap separately; it is required for full clarification recovery, not
   for diagnosing the already observed no-answer budget failure.
4. **Decide workload and disputed-premise changes separately.** Approve a concrete
   focused-review amendment before implementing production grouping; preserve
   per-member findings, correction scope and retry identity. Add no reassessment
   call until its authority and stable limit are explicitly approved. Prefer better
   generation and assignment interpretation before more review layers. Stop a
   proposed extension that fails its declared semantic/cost comparison; do not
   weaken required coverage to obtain a pass.
5. **Complete the applicable lifecycle and diagnostic work.** If claiming full
   answer-supported Spec execution, demonstrate authenticated answer acceptance
   through generation and readback, including source refresh and invalidation.
   Handle shared operational-cause changes as their own reviewed contract change.
6. **Complete layered verification and approved live acceptance.** Use the current
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
the separate R3 implementation verification is recorded above.

The two live case commands in the handoff exist, but no invocation is authorized
by this document. Isolated live comparisons require a bounded approval under
§28.8; each E2E invocation requires its own approval under AGENTS.md. The rubric
must assess the engine's actual published output. Calibration specimens and
scripted integration results remain distinct evidence.

## 7. Review conclusion and validation performed

The handoff is a useful direction for the next iteration and explicitly calls for
reuse of existing provenance and repair owners. Distinguish those implemented
protections from unresolved precision and semantic reliability gaps. Complete the
record-family scope, define the claimed source-association precision and settle
the applicable acceptance and disputed-premise decisions. R3 has resolved the
policy projection defect; shared purpose clarity and complete workload feasibility
remain. Neither requires replacing the generic engine or inventing another
authority system.

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
authorizations. Existing R1–R9 and §6 retain the unresolved clarification,
publication, calibration, workload and live repeatability requirements.

**Cleanup validation — 9 October 2026:** checked repository Markdown links against
the pre-move baseline; no new unavailable targets. FIX01's 98 local links and 76
heading/line anchors passed. All 12 experiment evidence files retain their original
SHA-256 hashes. Fix-record whitespace, `git diff --check` and
`git diff --cached --check` passed. The 262 already unavailable historical targets
remain unavailable; this cleanup does not reconstruct old run/cache artifacts.
No implementation tests or live executions were needed for the document relocation.
