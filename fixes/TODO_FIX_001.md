# FIX_001 phased rollout

Status: Proposed implementation plan. Created: 13 September 2026.
Source: [FIX_001.md](FIX_001.md). Governing authority remains
[AGENTS.md](../AGENTS.md), [design.md](../design/design.md) and accepted ADRs.
This checklist does not approve design amendments or live runs. No implementation,
tests or model calls were performed while preparing it. All chunks are pending.

## Outcome and delivery rules

The first milestone is one complete run of the existing live base case that
publishes the official `spec.md` and all required artifacts, passes publication
identity checks, and receives a scored rubric evaluation of those exact bytes.
The [rubric](../test/e2e/wf-001-hello-world/node-vitest/rubric/spec.json) has no
adopted pass threshold. Execution completion, evaluation completion and quality
acceptance remain separate conclusions. Repeated reliability and A/B comparisons
follow the first completed baseline.

Each numbered chunk is a reviewable, testable change with its own dependencies,
positive and negative evidence, cleanup and exit gate. Complete its producers,
consumers and tests together; do not land unused contracts, parallel response
formats, disabled checks or a half-wired success path. A diagnostic-only chunk
may deliberately retain a terminal failure until its dependent repair chunk
lands; it must expose that failure accurately and cannot claim recovery.

Use the existing engine owners. The model proposes; canonical validation,
authorization, accounting and workflow transitions decide what can happen.
Keep raw/model, checked, authorized and published data distinct. Remove superseded
code and fixtures in the same contract change, while retaining historical run
evidence. Do not weaken a schema, judge, gate or source requirement to pass the
base case. Do not add output-token caps, hidden model fallback, a second repair
framework, a rule DSL, transaction recovery or a logging service.

Finish each chunk with its targeted checks and diff review. Before closing a
cross-cutting phase, run the full verification gate below. Record commands and
actual results against the chunk; a previous pass is not a new result. Native
packaging verification is mandatory when runtime, resources, composition,
filesystem or build behavior changes. These are implementation instructions,
not claims that the checks have already run.

## Phase map

| Phase | Chunks | Entry dependency | Observable exit |
| --- | --- | --- | --- |
| 0 — Settle contracts | 00 | None | Reviewed classification, target and authority decisions; blocking amendments explicitly approved before dependent edits. |
| 1 — Trustworthy guidance and rejection | 01–04 | Applicable decisions in 00 | No synthetic response examples; precise native failures and separately attributed exchanges survive to reports. |
| 2 — Final proposal contracts | 05–07 | 01, 03, 04 | Deterministic facts are reconstructed once; selected schemas and native candidates agree. |
| 3 — Complete authorized repair | 08–12 | Final contracts from phase 2 | Repairable units recover through shared authorization and complete validation; siblings and authority remain protected. |
| 4 — Support and clarification | 13–15 | Typed rejections and applicable repair units | Supported omissions and genuine source gaps take distinct shared paths; genuine gaps publish actionable needs. |
| 5 — Evidence and readiness | 16–18 | Per-chunk dependencies below | Publication, evaluation and provenance evidence are trustworthy; complete offline verification passes. |
| 6 — First live baseline | 19 | 00–15, 17–18; transport operational; approval for this run | Engine-published and independently scored baseline retained. |
| 7 — Follow-up and comparison | 20–21 | 19; separate scope/run approvals where required | Scoped assembly cleanup and measured comparisons, with all failures retained. |

Chunk 16 is an independent transport-observation track: it can land alongside
earlier phases and need not delay an otherwise working baseline. Chunk 20 is
follow-up cleanup unless an actual assembly divergence blocks execution. Neither
changes the completion requirements for the full set of agreed rollout work.

The intended sequence settles and simplifies response contracts **before** new
shape-dependent repairs. This avoids building repairs for citation echoes or
retained relationship fields that phase 2 removes. Guidance/diagnostic work does
not depend on those semantic field choices. Parallel implementation is suitable
only for disjoint owners; serialize changes to shared schema, diagnostic,
registry and YAML contracts.

## Validation commands and evidence

Run from the repository root with the pinned Zig 0.16.0 toolchain. The existing
project-local invocation documented in [E2E instructions](../design/harness/e2e.md)
keeps temporary work and caches in the project. In each chunk, replace the build
step names in this example with the listed **Checks**:

```sh
TMPDIR="$PWD/.zig-cache/tmp" zig build --global-cache-dir .zig-cache/global --system zig-pkg test-model-payload-schema test-model-candidate-json --summary all
```

The named steps below exist in [build.zig](../build.zig); they are not new commands
to implement. There is no separate changed-scope aggregate, `test-architecture`,
`test-publication` or `test-bedrock-http` step. Use owning-boundary steps during
iteration, then the full gate:

```sh
TMPDIR="$PWD/.zig-cache/tmp" zig build --global-cache-dir .zig-cache/global --system zig-pkg verify --summary all
git diff --check
```

`verify` runs lint, all unit/integration tests, architecture checks and clean
native packaging smoke. `test-provider-conformance` includes the HTTP tests.
Publication-write failure tests in [composition/root.zig](../src/composition/root.zig)
run through `test`/`verify`; `test-atomic-execution` alone does not cover them.
Harness/evaluator/launcher tests and startup smoke steps are offline and cannot
be reported as live E2E evidence.

For each completed chunk record: implementation revision, actual check commands,
results, regression case names, removed legacy paths and any remaining limitation.
Keep completion unchecked when a required check or acceptance case is missing.

## Phase 0 — Establish the shared contract

### 00 — Review the classification and repair-unit matrix

- [ ] Complete chunk 00.

**Scope and owners:** review [design §§12, 17, 21–22, 25, 27–28 and 31](../design/design.md)
against FIX_001 §§4 and 6. Use the existing validator, schema, authorization,
workflow and observation owners; this chunk does not introduce runtime behavior.

**Deliverables:**

- Classify every affected boundary: extraction text/classifications/selections/
  claims; reconciliation summaries/dispositions/signals/conflicts; specification
  generation/provenance/coverage; support collection; repair merge; publication.
  Record candidate rejection, source-authority gap, or operational/context
  failure, plus its current and intended transition.
- For each repairable class, identify the smallest independently valid target,
  permitted operation, old-value/revision preconditions, dependency read facts,
  impacted validators, and positive/rejection tests. Include missing, extra and
  duplicate entries; a replacement-only example is not a complete cardinality
  repair contract.
- Distinguish mechanically redundant deletion from competing non-equivalent
  claims/dispositions. Never retain the first/last entry merely to erase a conflict.
  A semantic survivor choice needs a bounded, validated candidate decision before
  deletion; no deletion may remove required coverage. Gate any target whose safe
  scope or ordering cannot be established from current authority.
- Settle final model-facing choices before implementing new repair types:
  engine-derived membership/citation unions and supported tagged dispositions.
  Preserve genuine evidence selections and canonical/persisted provenance.
- Prepare the narrow §12.5/§22.6 amendment replacing fabricated examples with
  precise schema guidance, and §17.3 wording for engine-derived citation unions.
  Preserve §17.5's canonical union and all non-negotiable invariants. Obtain
  explicit approval for the amendments before dependent implementation.
- State the shared distinction between established-source candidate defects and
  genuine authority gaps before changing forced-gap semantics. A positive model
  review cannot authorize missing content or remove a forced gap.
- Resolve any target-algebra decision under §§22.1–22.3. Existing atomic code
  implements replacement; accepted design also describes insert/delete. Do not
  assume the implementation already supports them or widen a repair to a whole
  graph. A coupled group is permitted only within the accepted single-record/file
  boundary. An unresolved scope decision blocks that target, not this planning work.

**Review checks:** every boundary above maps to a later chunk and at least one
accepted and rejected case; no broad error name automatically means repairable;
no rule is independently specified in YAML, prompt prose and validator code.
Check document links and `git diff --check`. Preserve the design's Proposed status.

**Exit:** concrete reviewed decisions and acceptance matrix exist. The TODO itself
is not approval. Unaffected offline work may proceed while a specific decision
is pending; dependent code may not silently choose its own policy.

## Phase 1 — Make guidance and rejection trustworthy

### 01 — Replace synthetic correction examples and their test dependency

- [ ] Complete chunk 01. **Depends on:** 00's example amendment.

**Owners:** [model_protocol_retry.zig](../src/domain/model_protocol_retry.zig),
[model_schema_diagnostic.zig](../src/domain/model_schema_diagnostic.zig),
[model_schema_projection.zig](../src/domain/model_schema_projection.zig), and
their payload-schema/native-codec tests and protocol documentation.

**Change:** replace generator-dependent conformance inputs with independent
contract cases; use the retained expected schema node and parent/value scope for
correction guidance. Preserve original assignment, schema, evidence, latest exact
rejected bytes and immutable request association. Delete synthetic example
generation, superseded assertions and example-specific descriptions together.
Do not replace it with empty-array defaults or another semantic example generator.

**Evidence:** each selected response definition and nested variant has accepted
wire/native cases. Missing `kind`, mixed/unknown fields, duplicate keys, invalid
numbers and out-of-range values reject. Preserve exact integer spellings such as
`7`, `7.0` and `70e-1`, ordinary whitespace and property-order variation; fractional
integer values still reject. Applicable omission/null and empty-struct cases are
explicit. Domain cases still reject structurally valid self-relations.
Correction tests prove exact rejected bytes, diagnostic locations, alternatives,
schema bounds and request identity survive without fabricated business values.

**Checks:** `test-model-result-schema`, `test-model-payload-schema`,
`test-model-candidate-json`, `test-model-envelope`, `test-model-request-workflow`.
**Exit:** correction guidance is truthful, and deleting the generator does not
delete conformance coverage. No live acceptance or prompt-size improvement is claimed.

### 02 — Separate exchange attribution from candidate attribution

- [ ] Complete chunk 02. **Depends on:** 00's observation contract.

**Owners:** [trace.zig](../test/harness/e2e/trace.zig),
[observation.zig](../test/harness/e2e/observation.zig), existing harness contracts,
invocation projection and report renderers.

**Change:** represent current exchange and rejected-candidate origin separately.
Attach usage to its exchange; retain terminal failing step/diagnostic independently
of the last model step. Use real request/attempt associations and existing evidence
paths. Preserve fail-closed evidence writes and one structured report/human projection.

**Evidence:** reproduce R06's old candidate plus newer repair response; both origins
and correct usage remain visible. A deterministic failure after the last model call
names its actual step. Foreign/missing joins fail explicitly. JSON, schema, candidate,
retry and evaluator failures remain distinct. No raw-response reparsing supplies
domain verdicts. Current unavailable text projections are reported honestly.

**Checks:** `test-e2e-harness`, `test-model-request-workflow`.
**Exit:** existing diagnostic variants are correctly attributed. New domain facts
arrive with 03/04; the harness does not invent a missing rule.

### 03 — Preserve reconciliation rejections through the full boundary

- [ ] Complete chunk 03. **Depends on:** 00, 02.

**Owners:** reference reconciliation validators, native candidate values,
[reference_reconciliation_workflow.zig](../src/application/reference_reconciliation_workflow.zig),
shared candidate diagnostic projections and registered operation contracts.

**Change:** distinguish checked proposals, typed candidate rejections and trusted
context/operational failures. Retain rule, affected unit, observed/expected
constraint, revision and producing origin through action, binding and observation.
Use existing rule owners; define final shape-specific variants with 06/07 instead
of expanding obsolete echo-field diagnostics. Terminal failure may remain until
09/10 add authorized correction, but must retain its precise cause.

**Evidence:** duplicate dispositions, invalid references, self/cyclic relationships,
missing signal coverage and summary membership errors reach the native rejection
and report. Invalid corpus/history, stale partition/context, allocation failure
and cancellation cannot become model-repair requests. Evidence survives request
release; reporting grants no repair authority.

**Checks:** `test-reference-reconciliation`, `test-reference-model-input`,
`test-model-request-workflow`, `test-e2e-harness`; full `verify` for registry changes.
**Exit:** each reconciliation boundary is diagnosable without reading its model
response to infer the failed rule. No caller-specific exception is introduced.

### 04 — Retain specification/extraction rejections and eliminate rediscovery

- [ ] Complete chunk 04. **Depends on:** 00, 02, shared contracts from 03.

**Owners:** [specification_generation.zig](../src/domain/specification_generation.zig),
[specification_repair.zig](../src/domain/specification_repair.zig),
[reference_extraction_repair.zig](../src/domain/reference_extraction_repair.zig),
existing specification/extraction actions, application values and diagnostics.

**Change:** validators discover failures once; authorizers consume the retained
native rejection and verify its current association. Remove duplicated traversal
and record-kind/duplicate-content rejection from authorization. Extraction's
authorizer consumes its retained selection rejection rather than rediscovering it.
Keep canonical post-merge validation. Capture specification-unit origins from
the existing handoff before releasing bodies; retain unchanged siblings' origins.

**Evidence:** candidate provenance defects receive their rule; inconsistent
reference-state/corpus binding never becomes `.provenance` repair. Foreign
rejection, wrong unit, stale revision and mismatched request reject. Origins survive
request release and intervening calls. Existing repair behavior still revalidates
after merge; invalid unchanged replacements remain invalid.

**Checks:** `test-specification-generation`, `test-reference-extraction`,
`test-reference-evidence`, `test-e2e-harness`, `test-model-request-workflow`.
**Exit:** one owner discovers each rule violation; native authorization does not
consume serialized diagnostic JSON. Narrower targets are implemented in 11.

## Phase 2 — Simplify the final proposal contracts

### 05 — Use one deterministic citation-union constructor

- [ ] Complete chunk 05. **Depends on:** 03, 04.

**Owners:** [reference_reconciliation_validation.zig](../src/domain/reference_reconciliation_validation.zig),
[specification_provenance.zig](../src/domain/specification_provenance.zig), and the
narrow shared reference-evidence construction boundary.

**Change:** consolidate stable unique union construction and use it at both current
consumers. Preserve stage-specific claim eligibility, current-state and exact-copy
checks. Keep the existing model shape in this chunk; 06 removes the echoes.

**Evidence:** overlapping selected claims yield first-occurrence order in selected
claim order, without missing or duplicated citations. Reordered and repeated inputs
have explicitly tested semantics. Unknown/foreign/ineligible claims reject at their
owner; clarification-response evidence never gets fabricated source citations.

**Checks:** `test-reference-reconciliation`, `test-specification-generation`,
`test-reference-evidence`, `test-reference-model-input`.
**Exit:** both consumers use one construction function, with no duplicate algorithm
or change to accepted domain policy.

### 06 — Remove deterministic echoes from model response contracts

- [ ] Complete chunk 06. **Depends on:** 00's selection decision, 01, 04, 05.

**Owners:** reconciliation/specification proposal and canonical types, input
projections, parsers/builders, existing repair and support consumers, and
[selected workflow schemas](../design/workflows/spec).

**Change:** derive summary membership and exact citation unions from validated
input/selections. Change model DTOs, selected schemas, decoders, validators,
builders, repair/support responses and tests together. Canonical provenance and
rendered outputs retain complete evidence. Remove old echoed fields and readers;
keep meaningful evidence choices, exact-copy selections and keyed claim identity.

**Evidence:** missing model echoes cannot drop canonical members/citations; canonical
output retains the required stable union. Wrong/out-of-scope IDs and meaningful
selection omissions reject. Old fields and mixed old/new responses reject. Every
new selected response and repair shape decodes, and full candidate validation still
checks current authority and exact tokens. Rendering remains byte-stable for the
same canonical content, without requiring identical wording from different models.

**Checks:** `test-model-candidate-json`, `test-model-payload-schema`,
`test-reference-model-input`, `test-reference-reconciliation`,
`test-specification-generation`, `test-specification-contract`,
`test-structured-tokens`, `test-typed-text`; full `verify`.
**Exit:** candidate choices and engine-constructed facts have distinct types; no
parallel citation-echo repair schema remains. Update §17.3 and related docs with
the approved change, preserving §17.5 canonical evidence requirements.

### 07 — Express disposition choices and guidance through their owning contract

- [ ] Complete chunk 07. **Depends on:** 00's shape decision, 01, 03, 06.

**Owners:** reconciliation proposal types/schema, input/guidance construction,
disposition validator and consumers, including schema/native conformance cases.

**Change:** use supported nested `kind` variants: retained has an empty struct
payload; duplicate has one selected target; other decisions expose only their
required selections. Derive canonical empty retained relationships from an accepted
variant. Format cross-record guidance using canonical rule identities/current
facts; do not maintain another rules table in YAML or verbose prompt prose.

**Evidence:** each variant and boundary decodes; old relationship fields, mixed
variants and incompatible shapes reject. Self-reference, incompatible targets,
cycles, asymmetric conflicts and missing signal/token coverage still fail domain
validation. Retained-with-relationships is no longer expressible in an accepted
proposal; no invalid candidate is silently rewritten to retained-empty.

**Checks:** `test-model-result-schema`, `test-model-candidate-json`,
`test-model-payload-schema`, `test-reference-model-input`,
`test-reference-reconciliation`; full `verify`.
**Exit:** final disposition choices and precise initial/repair guidance agree.
No unsupported schema feature or alternative discriminator is introduced.

## Phase 3 — Complete authorized repair and revalidation

### 08 — Bind shared repair preconditions through existing consumers

- [ ] Complete chunk 08. **Depends on:** 00's target matrix, 04, 06, 07.

**Owners:** [atomic_repair.zig](../src/domain/atomic_repair.zig), native candidate
owners and focused domain repair input/authorization builders.

**Change:** use the existing extraction/specification consumers to bind and verify
replacement association/CAS, immutable dependency facts, complete native rule values
and their validator/engine-policy provenance. Keep dependency read scope separate
from write targets. Guidance consumes authorization-bound facts; it must not
re-query ambient policy after rejection. Reuse existing bindings where they already
prove this contract rather than adding another dependency registry.

New insert/delete variants required by 00 land **with their first real consumer
in 09 or 10**, including their shared contract tests, not as unused APIs here.
Extend only the same accepted closed algebra. Do not replace a whole valid
collection to sidestep missing support. The engine selects operation, target and
old-value/collection preconditions; the model supplies only permitted content
when a semantic choice is needed. Do not add model confirmation fields for an
operation with no candidate choice.

**Evidence:** scoped replacement preserves every unrelated unit. Foreign owner,
stale candidate/dependency revision, wrong old value, changed dependency membership,
wrong replacement kind and model-supplied target/operation reject. Required read
context is complete, while reading neighbors does not authorize editing them.
Allocation failure leaves the original candidate unchanged. The first insert/delete
consumer adds equivalent precondition, scope and failure tests for that operation.

**Checks:** `test-reference-reconciliation`, `test-specification-generation`,
`test-reference-extraction`, `test-model-candidate-json`, `test-atomic-execution`;
full `verify` for shared changes.
**Exit:** the shared preconditions are exercised by real existing consumers. No
unused target operation, graph solver, generic capability bag, hidden retry owner
or unauthorized multi-record coupled group is added. Missing authority for a target
remains a gate.

### 09 — Repair reconciliation summaries before appending derived state

- [ ] Complete chunk 09. **Depends on:** 03, 06, 08.

**Owners:** current summary candidate/validator/builder, focused authorization,
input/parse/merge actions, reconciliation bindings and registered YAML operations.

**Change:** route typed summary candidate failures through the normal model request
and authorized unit repair path. Bind partition membership, claims, evidence and
revision. Repair before accepting/appending the summary; invalidate any already
derived dependent state. YAML owns calls, retries, retirement and typed branches.
Land any newly required insert/delete operation with this first consumer and its
scope/old-value/collection-precondition tests under 08's shared contract.

**Evidence:** bad statement selection/content/coverage can recover without replacing
valid sibling statements or losing member accounting. Wrong partition, stale
summary lineage, changed source context and foreign repair calls cannot repair.
Spy bindings prove authorization → request → parse → merge → producing/dependent
validation → full summary validation. Repeated invalid responses terminate under
existing limits with no partial summary acceptance.

**Checks:** `test-reference-reconciliation`, `test-reference-model-input`,
`test-model-request-workflow`, `test-e2e-harness`; full `verify`.
**Exit:** summary candidate recovery is observable and complete for its failure
class, not a retry for one retained fixture response.

### 10 — Repair the global reconciliation candidate with graph dependencies

- [ ] Complete chunk 10. **Depends on:** 03, 07–09.

**Owners:** disposition, signal and conflict validators; native global candidate;
focused shared-repair actions, operation contracts and reconciliation YAML.

**Change:** authorize units from native rejections using the final response shape.
Supply relevant current graph, claim kinds, evidence and coverage obligations as
read context. Disposition changes invalidate dependent signal/conflict/accounting
checks. Preserve valid siblings and revalidate the full global result before
assigning accepted reference authority. Handle missing/extra/duplicate entries
under 00/08's explicit operation contract; add a required shared operation here
only if this is its first consumer, with accepted/rejected contract tests. Never
expand scope opportunistically or delete a competing semantic claim by position.

**Evidence:** recover invalid target selection, duplicate dispositions and missing
retained/token coverage. Reject cycles, incompatible targets, asymmetric conflicts,
conflicting signal support, stale dependency snapshots and invalid repair scope.
Test the reported classes and an unrelated relationship/coverage example. Repeated
identical and alternating invalid repairs terminate and retain exact diagnostics;
revision increments are not counted as acceptance.

**Checks:** `test-reference-reconciliation`, `test-reference-model-input`,
`test-model-request-workflow`, `test-model-attempt-accounting`,
`test-e2e-harness`; full `verify`.
**Exit:** all global reconciliation validators participate in one complete
rejection/authorization/revalidation contract; no disposition-only continuation fix.

### 11 — Narrow existing specification repair to independently valid units

- [ ] Complete chunk 11. **Depends on:** 04, 06, 08.

**Owners:** specification generation/provenance/repair/session, existing repair
actions and bindings, selected repair schema and diagnostic origin projection.

**Change:** authorize evidence-selection/provenance-only repairs without exposing
valid business text where those parts are independent. Keep record-level repair
only for an inseparable defect. Use retained rejection facts, current authority,
exact old value and per-unit origin. The repaired target receives the replacement
origin even when its bytes are identical; unchanged siblings retain their origins.
Record changed-value status separately and discard affected derived validation
after merge.

**Evidence:** provenance-only repair preserves valid text and sibling origins;
inseparable record repair has an explicit scope case. Foreign/stale rejection,
wrong unit/kind/old value, extra fields and lost source authority reject. An
unchanged invalid replacement still fails; correct replacement passes producing,
dependent and whole-candidate validation before publication.

**Checks:** `test-specification-generation`, `test-specification-contract`,
`test-model-candidate-json`, `test-model-request-workflow`, `test-e2e-harness`;
full `verify`.
**Exit:** valid content cannot change as a side effect of repairing independent
provenance; superseded broad targets and schemas are removed.

### 12 — Close the remaining candidate-validation routes

- [ ] Complete chunk 12. **Depends on:** 03–04, 08–11.

**Owners:** extraction text/claim validation, specification coverage, their
application bindings, shared diagnostic/repair contracts and explicit YAML edges.

**Change:** complete the remaining mechanical rows from 00's matrix. Mechanically invalid
source-supported candidates with a safe target use shared repair; genuine source
gaps go through shared authority routing; context/operational failures remain
typed failures. Complete producers and transitions together, without mapping
every error to `.invalid` or routing every invalid outcome into a model call.
Preserve existing authority routing here; 14 separately refines the supported
omission versus source-gap distinction across all relevant producers.

**Evidence:** one recoverable and one non-repairable representative for each
affected validator. Preserve exact tokens, source selections and business authority.
No unknown/missing rule or unsafe target becomes a fallback. Workflow tests prove
full validation, bounded repetition and truthful terminal diagnostics across
unrelated requirement kinds.

**Checks:** `test-reference-extraction`, `test-reference-evidence`,
`test-typed-text`, `test-path-tokens`, `test-structured-tokens`,
`test-specification-generation`, `test-required-authority`,
`test-model-request-workflow`; full `verify`.
**Exit:** mechanical rows have no unexplained terminal candidate branch. A
deliberately non-repairable case has a typed reason and negative test. Shared
authority refinements and actionable gap publication remain assigned to 14–15.

## Phase 4 — Preserve support findings and route genuine gaps

### 13 — Retain inspectable support findings and their origin

- [ ] Complete chunk 13. **Depends on:** 00's classification decision, 04, 06.

**Owners:** [specification_support.zig](../src/domain/specification_support.zig),
support schema/prompt/actions/bindings, native authority evidence projection,
[specification_state.zig](../src/domain/specification_state.zig) and its existing
state build/parse/publication consumers.

**Change:** represent concise source-gap, candidate non-preservation and malformed
review findings as appropriate typed candidate facts. Bind requirement, candidate
revision, current authority, supplied references and producing origin. Carry the
validated finding association through collection to diagnostics; do not add an
explanation only to the raw model response or overload signal/conflict IDs as
claim/citation provenance. A model finding does not select its continuation.

Separate execution-local call correlation from published evidence. Current
`State.review.evidence` persists authority evidence, while `Origin` resolves only
against the current execution ledger. Keep published finding/provenance data
self-contained under its canonical authority; do not persist a prior-run request
ordinal as resolvable authority. Change closed state producers/readers with the
evidence projection, without legacy dual readers or a new persistence subsystem.

**Evidence:** source absence can be reported without invented citations. Unknown
requirements, foreign references, stale candidate/authority bindings and incomplete
finding coverage reject. Valid negative findings survive collection and request
release, with actionable missing datum/conflict/omission and exact subject.
Build and parse the resulting closed state in a fresh execution; published support
remains verifiable without the old request ledger. Invalid/foreign persisted
associations reject, and call correlation never grants cross-run authority.

**Checks:** `test-specification-generation`, `test-specification-contract`,
`test-required-authority`, `test-model-candidate-json`, `test-model-payload-schema`,
`test-e2e-harness`, `test`; full `verify` for state/publication changes.
**Exit:** downstream policy/reporting can inspect the same validated finding;
semantic judgments remain explicitly model-assisted.

### 14 — Distinguish supported candidate omissions from source-authority gaps

- [ ] Complete chunk 14. **Depends on:** 00, 11–13.

**Owners:** [required_authority.zig](../src/domain/required_authority.zig),
[specification_authority.zig](../src/domain/specification_authority.zig), shared
classification/authorization, coverage bindings and pre/post support transitions.

**Change:** classify deterministic missing-content projections and semantic findings
consistently. An established-source candidate omission may use an explicitly safe
authorized repair; a genuine missing/ambiguous/conflicting source decision remains
clarification/upstream rework. Correct a malformed review record under its own
contract; never retry a substantive verdict until positive. Retain required-content
obligations instead of deleting forced gaps to allow success.

**Evidence:** source-supported UTC omission and an unrelated omission can repair;
actual source absence after generation cannot. Missing mandatory AC/FR content
still blocks despite positive review, and dropping a forced gap rejects. Stale
support, unknown ownership and unsafe targets cannot repair. Test shared routing
across unrelated registered requirement kinds, not a Specify-name branch.

**Checks:** `test-required-authority`, `test-specification-generation`,
`test-model-request-workflow`, `test-e2e-harness`; full `verify`.
**Exit:** the same complete shared classification applies before and after
generation. No authority gap enters ordinary repair under §22.2/§31(36–40).

### 15 — Convert genuine authority gaps into registered clarification needs

- [ ] Complete chunk 15. **Depends on:** 13–14.

**Owners:** shared authority result/finding association,
[clarification_refresh.zig](../src/domain/clarification_refresh.zig), a focused
registered conversion action, existing refresh/render/publication bindings and YAML.

**Change:** convert validated gaps to existing `Needs`, preserving structural
requirement identity, earliest owner, current authority and stable subject.
Reuse refresh, IDs, rendering, registered writes and protected-answer handling.
Keep the generation-specific need constructor for actual generation clarification
responses; do not fabricate a generation result to reuse it.

**Evidence:** pre/post genuine gaps publish specific questions; multiple gaps stay
distinct and fully accounted. Reordered findings and changed wording retain stable
subjects. Unknown ownership and ambiguous/duplicate identities reject; downstream
gaps retain earliest-owner routing. Open forms are fully replaced, shorter content
leaves no suffix, and user-closed forms stay unchanged under concurrent close.
Clarification publication cannot publish partial successful spec output.

**Checks:** `test-required-authority`, `test-clarification-inputs`,
`test-specification-generation`, `test-e2e-harness`, and `test`/full `verify`
for concrete publication and concurrent-close regressions.
**Exit:** `needs_user` has actionable registered output and a fresh invocation
starts at `start`. This is not a claim of completed authenticated answer ingestion.

**Existing decision boundary:** [H-011](../design/harness/02-spec-workflow.md#h-011--complete-specification-clarification-handling)
still requires selection of a trusted authentication mechanism for accepting new
submissions. Do not infer authentication from a file or invent answers for the
base case. This choice does not block an authority-complete base case. If a live
case needs newly accepted answers, report the blocker and obtain that concrete
decision/scope before implementing acceptance; protected form handling remains required.

## Phase 5 — Complete observation and baseline readiness

### 16 — Preserve transport failure detail and evidence availability

- [ ] Complete chunk 16. **Depends on:** 02. Independent of semantic repair.

**Owners:** [bedrock_http.zig](../src/adapters/provider/bedrock_http.zig),
[bedrock_transport.zig](../src/adapters/provider/bedrock_transport.zig), current
provider outcome, evidence store and report projections.

**Change:** retain a closed known failure phase and safe cause category without
changing delivery/retry policy. Distinguish absent response, retained raw response,
budget stop before text projection, evidence-write failure and complete capture.
Reuse HTTP status, exception and request ID already captured. Do not infer DNS,
TLS or sandbox causes from `transport_failed`/`not_sent`.

**Evidence:** failures before send, during send, in response headers/body and timeout
retain only known facts. Unknown causes remain unknown. Final raw response survives
budget rejection even without text projection. Capture errors cannot produce a
passing run; redaction, actual usage and no-hidden-resend behavior remain unchanged.

**Checks:** `test-provider-conformance`, `test-model-request-workflow`,
`test-e2e-harness`, `test-atomic-execution`; full `verify`.
**Exit:** future environmental failures can be isolated without a new logger or
model retry path. Historical lost detail is not retrospectively invented.

### 17 — Prove complete publication and evaluator handoff

- [ ] Complete chunk 17. **Depends on:** 10–12, 14–15.

**Owners:** [workflow_output.zig](../src/domain/workflow_output.zig), output adapter,
publication bindings, [oracle.zig](../test/harness/e2e/oracle.zig), evaluator handoff
and existing integration/publication tests.

**Change:** preserve and extend existing failure coverage; fix only demonstrated
gaps. Require whole-output validation and engine-observed complete publication;
completion state is last. The evaluator grades exact published bytes. Earlier
written files may remain after a failed replacement without becoming success.

**Evidence:** inject failure at every publication write, including completion state;
no new success survives. Fresh invocations replace the complete registered output
set. Prior/stale `spec.md`, missing/changed artifacts, stale captures, partial forms
and evidence failures cannot pass. Evaluator failure retains the published spec
but leaves full E2E incomplete; low scored output remains scored, not silently
rejected or regenerated. Include an unrelated registered workflow and protected
clarification-close races.

**Checks:** `test-e2e-harness`, `test-rubric-evaluator`, `test-e2e-launcher`,
`test`, `smoke`; full `verify` covers the complete gate.
**Exit:** publication identity and evaluator status remain independent. No rollback,
checkpoint, candidate export or golden-spec shortcut is introduced.

### 18 — Capture baseline provenance and pass complete readiness verification

- [ ] Complete chunk 18. **Depends on:** 01–15, 17; 16 if it changed shared contracts.

**Owners:** existing harness run capture/report/evidence store, build provenance,
case documentation, all changed test owners and native packaging.

**Change:** capture exact source/build identity, including local source changes,
with already captured configuration, workflow/prompt/schema, source, generation
model and rubric/evaluator settings. Reuse existing run metadata; do not add a
production Git dependency, artifact-freshness authority or benchmark platform.
Record the unresolved first-live acceptance criterion explicitly.

**Evidence:** clean and modified source identities are distinguishable; captured
identity names the build actually run. Credentials/environment dumps are excluded.
Provenance cannot change workflow gates. Publication and diagnostic evidence joins
remain exact. Review every changed contract for dead code, duplicate policy,
unregistered operations, old response formats and weakened assertions.

**Checks:** `test-e2e-harness`, `test-e2e-launcher`, `test-rubric-evaluator`,
`smoke-e2e-harness`, `smoke-rubric-evaluator`; full `verify` and `git diff --check`.
**Exit:** all required offline/architecture/packaging checks pass on the proposed
baseline build, and its concrete run configuration is ready for approval. No live
call is made automatically as part of this gate.

**Logging boundary for all chunks:** rich native diagnostics and permitted harness
evidence/report data are not unrestricted production metadata logs. Preserve
design §26's closed metadata registry and body opt-ins/redaction; no free-form
`actual`/`expected`, secrets or raw prompt bodies are added to metadata events.

## Phase 6 — Produce the first official scored specification

### 19 — Run and assess one explicitly approved live base case

- [ ] Complete chunk 19. **Depends on:** 18 and explicit approval for this run.

**Case:** [workflow.case.json](../test/e2e/wf-001-hello-world/node-vitest/workflow.case.json).
Use its configured real generation LLM and declared evaluator settings. Keep the
source requirements and rubric unchanged to manufacture no easier success case.
Ask for permission only after the build/configuration and readiness evidence are
concrete. Prior-run approval and approval of this TODO do not authorize this run.

After that approval, the documented project-local invocation is:

```sh
. ./.env.e2e
TMPDIR="$PWD/.zig-cache/tmp" zig build --global-cache-dir .zig-cache/global --system zig-pkg e2e-spec -- --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json
```

Loading the file does not authorize printing credentials. Do not automatically
loop this command. Retries inside the approved invocation remain the engine's
declared operation-local behavior and cumulative token accounting; another E2E
invocation requires another explicit approval.

**Acceptance:** retain workflow `ok`, engine-observed publication, passed artifact
identity checks for specification/reference context/clarification state/workflow
state, and a completed scored evaluation of that exact `spec.md`. Retain all calls,
failures, diagnostics, usage, captured inputs and build identity in the run folder.
Review the specification and criterion findings for source fidelity, including
startup, exact greeting and UTC output. Report concerns without inventing a score
threshold or changing output to satisfy the judge.

**Failure handling:** identify the exact phase, native rule, call/candidate origins
and retained evidence; return the failure to its owning chunk. Obtain fresh run
approval after any remedy and required verification. A genuine source gap remains
a clarification; no manual candidate export, fabricated answer or stale spec can
close this checkbox. Evaluator failure means generation progressed but full E2E
remains incomplete. A first pass proves feasibility, not reliability.

**Exit:** link the actual published `spec.md`, structured/human reports and scored
evaluation here, with the exact command and build identity. Until those artifacts
exist, the initial objective remains open regardless of mechanical test results.

## Phase 7 — Follow-up improvements and comparisons

### 20 — Consolidate duplicated runtime assembly within existing boundaries

- [ ] Complete chunk 20 when this follow-up scope is taken. **Depends on:** 19,
  unless a demonstrated assembly divergence blocked it.

**Owners:** [composition/root.zig](../src/composition/root.zig),
[harness invoke.zig](../test/harness/e2e/invoke.zig), narrow assembly interfaces
and production/launcher/packaging tests.

**Change:** expose one production assembly boundary with narrow project, credential,
runtime and observation inputs. Keep fixture assertions, evidence capture and
rubric evaluation in the harness. Preserve production environment validation and
direct isolated test credentials. Remove duplicated setup in the same change;
do not expose a capability bag or reimplement startup policy in the harness.

**Evidence:** both callers use the same bindings; unrelated workflows retain
behavior; wrong credentials/configuration and unavailable providers still reject.
CLI argument/error/exit and clean package behavior remain covered separately from
in-process execution. Trace wrapping cannot choose a model answer or workflow edge.

**Checks:** `test-provider-conformance`, `test-model-request-workflow`,
`test-e2e-harness`, `test-e2e-launcher`, `test`, `smoke`; full `verify`.
**Exit:** one assembly implementation and unchanged authority boundaries. Live
comparison, if needed, follows 21's approval rules; this cleanup alone is not
evidence of improved model output.

### 21 — Establish repeatability and compare declared code/prompt changes

- [ ] Complete chunk 21 for an explicitly defined comparison. **Depends on:** 19;
  20 only if assembly is the change being compared.

**Scope:** preserve the successful implementation as A and declare the intended
code/prompt/schema change as B. Fix unrelated case inputs, model settings, source,
rubric and evaluator configuration. A coupled code/schema change is one declared
treatment; do not attribute its effects to an isolated prompt line. Record planned
repetitions and comparison measures before observing results; each live run needs
its own approval. Start with existing run reports rather than a new framework.

**Evidence:** repeated A executions expose natural model/judge variation; repeated
A/B executions retain failures as well as successes. Compare first-pass JSON/schema
acceptance, recovery by rule, repeated/no-progress rejections, completion, calls/
tokens per attempt and completed output, criterion scores and clarification outcomes.
Do not equate fewer tokens in an early failed run with better output quality.
Use the retained spec as observed output, never a golden answer for new wording.

**Checks:** validate each proposed implementation with its owning checks and full
`verify` before requesting a live run. Audit provenance/input equality and report
joins offline; compare actual completed run artifacts afterward. Keep uncalibrated
rubric results qualified. Any adopted quality threshold needs its own explicit
decision and must not be chosen after seeing the scores it will judge.

**Exit:** report the defined experiment, all run identities, implementation/config
differences, completed and failed results, uncertainty and any supported conclusion.
Broader workflow acceptance requires its own real cases; this chunk cannot claim
plan/tasks/implement reliability from the Specify base case.

## Completion record

The initial milestone closes only with chunk 19's actual published/scored evidence.
Track chunk 16 and agreed phase 7 work separately if still pending; do not label
the whole rollout complete because the baseline passes. Do not label baseline
work blocked by optional benchmarking/assembly work. Every implementation chunk
must leave the repository verifiable and remove the legacy behavior it supersedes.

For the final handoff, list completed chunk IDs, changed owners/contracts,
actual targeted/full/packaging results, approved design changes, live run IDs and
artifact links, remaining decisions and unverified behavior. Link existing run
evidence rather than duplicating prompts or outputs into this checklist.
