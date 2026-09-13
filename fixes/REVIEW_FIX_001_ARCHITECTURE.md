# FIX_001 — Source-to-publication architecture audit

Reviewed: 13 September 2026. Implementation: Git
`f880799bedc4a9d0a8ddcf6cbb86be0cebd2babb` (`Phase 3`).
Scope: the implemented engine and Specify production graph, all five shared
atomic-repair consumers, persistence readers and the live harness/evaluator path.
The working tree initially contained only the earlier R15 review changes in
`FIX_001.md`, `TODO_FIX_001.md` and `CONTRACT_FIX_001.md`.

This is an analysis, not implementation or a new source of engine policy.
Only review/rollout Markdown is changed. No engine, test, prompt, YAML, schema,
configuration, dependency, AGENTS or governing-design changes were made. No live
E2E run or model call was started. The final review also examined dependency-fact
construction, canonical readback predicates, composition lifetime ownership and
the proposed implementation's single-responsibility boundaries. It adds F9/F10
and extends F8. Offline verification and the separate final documentation checks
are recorded in §9.

## 1. Verdict and limits

**Phase 3 contains confirmed brittleness above its shared merge mechanism.**
The problems are broader than R15's mixed-kind signal: authorization can choose
an impossible replacement, model requests omit frozen dependencies, and repair
decisions sometimes reinterpret rules or equality independently of validation.
Closing only the latest signal case would leave the same defects elsewhere.

**No competing merge, operation-retry, token-budget or continuation authority was
found inside engine generation.** The evaluator has a separate configured budget
and retry policy for grading; it cannot grant workflow completion. This separation
is appropriate. It does not establish absence of duplicated
policy. Guidance applicability has demonstrably diverged from validation;
redundancy decisions use different equivalence; persisted acceptance validates
less than fresh construction. Those are concrete ownership inconsistencies even
though successful execution still passes through one runner and publication path.
F9 additionally establishes that some declared repair dependency snapshots omit
facts the validator actually reads. Sharing exact CAS does not prove that the
complete dependency contract has been captured.

The narrow write scope is not itself the defect. Design §22 requires the smallest
**independently valid** unit, with sufficient immutable context to preserve meaning.
The implementation protects unrelated fields more completely than it establishes
whether a replacement is possible and gives the model the facts needed to make it.

This review traced current code, producers, validators, authorization, serialized
requests, merge/invalidation, downstream checks, reporting and existing tests.
R15's retained evidence corroborates the impossible-content case. Other concrete
counterexamples below are source-derived; no new executable regression was added
or claimed. Existing tests independently demonstrate the downstream support seam.

Only Specify currently has a production definition under `design/workflows`.
The generic engine has unrelated-workflow conformance tests, but that is not
live evidence for future plan/tasks/implement behavior. No current report can
certify application-wide live reliability from the failed Specify runs.

Compiled-schema/native-parser compatibility is another bounded limitation:
schema compilation validates the supported schema profile, not equivalence with
every downstream native DTO. Built-in conformance tests exist in
[model_candidate_json_test.zig](../src/model_candidate_json_test.zig), lines
95–157 and subsequent rejection cases. No current built-in mismatch was found;
this is not evidence for introducing schema-generation machinery. The harness
and executable duplicate production adapter/binding setup (F10). The harness
invokes shared production components in process; it does not invoke the packaged
CLI or its complete assembly. Existing chunk 20 tracks consolidation. No current
assembly policy divergence was established.

Governing basis: [design §§1, 3–4](../design/design.md#1-executive-summary),
[§12.8](../design/design.md#128-closed-authority-reconciliation-boundary),
[§17](../design/design.md#17-specify-stage-design),
[§§21–22](../design/design.md#21-deterministic-validation-catalogue),
[§24](../design/design.md#24-state-sequence-and-recovery-without-fingerprints),
[§25](../design/design.md#25-atomic-workflow-execution-and-output),
[§§27–28](../design/design.md#27-observability), and §31 acceptance criteria
1, 12–19, 30–31, 33–34 and 36–41. Accepted ADRs 0006, 0009, 0011, 0013 and
0014 and approved A1–A3 remain unchanged. The design remains **Proposed design**.

## 2. End-to-end ownership trace

| Boundary | Current authority and inspection result |
| --- | --- |
| Configuration and executable graph | Registered contracts constrain project definitions. `compile_workflow_graphs.zig:269–283` requires exact declared outcomes and rejects a failure relabelled as a success terminal. Compiled graph validation checks data/gate availability. The generic orchestrator follows typed compiled transitions; it contains no Specify-name dispatcher. |
| Runtime values and gates | `workflow_pipeline_runner.zig` validates operation bindings, capability policy, required inputs, gate evidence and request associations. `pipeline_envelope.zig` owns delta application and declared slot-generation lineage. Those controls reject stale gate generations; they do not establish that every domain repair snapshot contains every field its validator reads (F9). |
| Source and model evidence | Extraction selects scoped source references; canonical evidence resolves quotations and token identity. Reconciliation validates membership, dispositions, content, coverage and lineage. Models do not construct canonical citation unions or choose filesystem capabilities. |
| Initial request and schema | `model_request_handoff.zig:107–115` selects one compiled response schema. `model_request_preparation.zig:82–90`, provider encoding and payload validation preserve that exact association. Prompt and provider-native schema projections are guidance from the selected schema, not alternative acceptance rules. |
| Protocol correction | `model_protocol_retry.zig:7–26` retains the original assignment and adds the latest exact rejected bytes and native syntax/schema diagnosis. It neither merges semantic data nor selects a larger target. Runner-owned accounting remains in force. |
| Semantic repair | Domain authorizers select targets from native rejections; `atomic_repair.zig` binds owner, revision, exact old value and supplied dependencies. Five consumers share its parsing/CAS/receipt behavior. F1–F4 concern feasibility/projection/equivalence; F9 concerns missing declared dependency facts. |
| Revalidation | Repair deltas invalidate affected products; YAML returns through producing and dependent validators. `specification_session.zig:95–110` revalidates every accepted unit before assembly. A revision increment or `changed` receipt is not acceptance. |
| Support and authority | Specify contributes requirement/evidence projections. `required_authority.zig` owns the shared ownership registry, resolution and routing, reused before and after generation. §4 identifies incomplete inputs and transitions, not a second router. |
| Rendering and publication | `build_specification_state.zig:16–38` checks current authority, content, coverage and ready clarification state. `prepare_specification_output.zig:16–36` validates deterministic rendering, round-trip bytes and registered output shape. Output paths are engine-owned. Under ADR 0009, writes are sequential and completion state is last; a partial write failure cannot report a new successful completion. |
| Fresh invocation | `spec.workflow.yaml:69–74` parses prior canonical state before new generation. Current prior consumers use its ID ledger and revision. §5 identifies materially weaker persisted validation; old review evidence was not found to bypass the new review path. |
| Observation and grading | `candidate_repair_observations.zig` copies native merge receipts and deduplicates authorization IDs. The harness assembles production components and invokes their runner/provider/output ports. Its oracle independently rereads published files and compares them with engine-prepared bytes; this is publication integrity, not a prewritten golden spec. Evaluation has separate grading retry/budget/status and cannot grant engine completion. |

Principal owners:
[compiler](../src/actions/workflow/compile_workflow_graphs.zig),
[compiled graph checks](../src/actions/workflow/validate_compiled_workflow_graphs.zig),
[orchestrator](../src/application/workflow_engine_orchestrator.zig),
[runner](../src/application/workflow_pipeline_runner.zig),
[envelope](../src/application/pipeline_envelope.zig),
[request handoff](../src/domain/model_request_handoff.zig),
[request preparation](../src/domain/model_request_preparation.zig),
[protocol correction](../src/domain/model_protocol_retry.zig),
[atomic repair](../src/domain/atomic_repair.zig),
[authority](../src/domain/required_authority.zig),
[state construction](../src/actions/specification/build_specification_state.zig),
[publication preparation](../src/actions/specification/prepare_specification_output.zig),
[harness invocation](../test/harness/e2e/invoke.zig),
[publication oracle](../test/harness/e2e/oracle.zig),
[evaluation handoff](../test/harness/e2e/evaluation.zig).

Repeated validation at a trust boundary is necessary. It becomes divergent
authority when the same accepted fact is independently interpreted with different
rules. A read-only report projection is not authority; deciding eligibility or
redundancy again inside that projection or an authorizer is a different matter.

## 3. Confirmed repair defects

### F1 — Authorization does not consistently establish a feasible target

**Effect:** the engine can spend a bounded repair operation on a field for which
no permitted replacement can satisfy the frozen mechanical dependencies.

[Content validation](../src/domain/reference_reconciliation_validation.zig),
lines 29–56, permits model content only when every selected claim has that model
kind. Preserved-token content requires exactly one matching token claim.
[Authorization](../src/domain/reference_reconciliation_repair.zig), lines 72–78
and 137–141, maps a content rejection directly to statement/signal content repair.
It freezes the selected claim list without retaining whether any content is valid
for that list. R15 selected a business claim and a token claim together. No member
of the content union can satisfy that combination. Mixed model kinds and multiple
token claims expose the same defect in both summary and signal consumers.

There are independently observable siblings beyond content compatibility:

- [Conflict validation](../src/actions/reference/validate_reference_conflict_proposals.zig),
  lines 22–27, requires at least two mutually conflicting claims. An extra conflict
  record with all dispositions retained has no valid selection. Authorization
  nevertheless chooses `conflict_selection` at line 158.
- [Signal validation](../src/actions/reference/validate_reference_signal_proposals.zig),
  lines 24–27, rejects conflicting support. A malformed signal when every available
  claim is conflicting has no valid nonempty selection. Authorization still
  chooses `signal_selection` at lines 137–140.

These source counterexamples do not require predicting model behavior. The fixed
eligible sets make the requested mechanical outcome impossible. They establish
that a signal-only or mixed-kind-only correction would be incomplete.

**Owning correction:** native validators retain compatibility, eligible-choice and
coverage facts. Authorization consumes them to choose an already approved
independent target, or returns the existing precise block before provider dispatch.
Where selection can safely change independently, use the existing selection unit
and revalidate its full dependencies. An empty admissible set cannot be solved
by inventing support, deleting a meaningful conflict or widening to the whole graph.

This requires checks for mechanically known impossibility, not a general solver
or proof that an LLM can find good prose. Semantic quality still requires proposal,
validation/review and live evidence. G1 remains the boundary for an unestablished
survivor choice or coupled write. Rollout: 08–10.

### F2 — Immutable dependencies are retained internally but missing from requests

**Effect:** safe write isolation coexists with inadequate read context. A fake
provider can return a correct value using fixture knowledge unavailable to the
actual model.

[Specification candidate context](../src/domain/specification_candidate_context.zig),
lines 8–25, captures the current candidate and dependencies for CAS. But
[specification repair packet](../src/domain/specification_repair.zig), lines 52–67,
uses [session packet](../src/domain/specification_session.zig), lines 60–68, which
contains source evidence and the previously accepted brief, not the rejected
current candidate. [Atomic packet](../src/domain/atomic_repair.zig), lines 84–92,
adds target/rule/expected replacement only.

Consequently:

- A provenance repair receives the bad claim IDs without the unchanged business
  field or record fields those IDs must support.
- A value repair receives the bad value without its unchanged provenance, which
  controls eligible exact tokens and scoped passive references.
- During initial brief generation, the accepted brief is `null`; it cannot supply
  the missing rejected description incidentally.

The same failure class exists in extraction. In
[reference_extraction_repair.zig](../src/domain/reference_extraction_repair.zig),
line 48 returns the classification packet before projecting the current chunk
outcome. [Classification validation](../src/domain/token_classification_validation.zig),
line 67, forbids `preserve` under unchanged `no_feature_claim`. If a classification
is missing, the request lists the missing ID but omits that frozen outcome and
its restricted choices; the selected schema permits both decision variants.
Citation repair at lines 49–61 already projects the unchanged claim correctly.

**Owning correction:** domain packet builders project minimal immutable dependent
content from the existing authorization-bound candidate. The narrow response
schema remains narrow. Choices/restrictions derive from the native owner, not a
second prompt table. A record sharing provenance may require several unchanged
fields as read context; that does not authorize changing those fields.
Rollout: shared requirement in 08, specification in 11, classification in 12.

### F3 — Guidance independently narrows or omits valid contract choices

[reference_model_input.zig](../src/domain/reference_model_input.zig), lines 77–84,
selects applicable constraint IDs separately from validation. Summary guidance
contains `matching_claim_content` and `exact_selected_token`; global guidance
omits them even though global signal validation enforces both. Rule descriptions
are shared, but applicability is independently maintained and has already drifted.

[specification_repair.zig](../src/domain/specification_repair.zig), line 41, says an
exact-copy repair must select a preserved token supported by unchanged provenance.
The selected response type is the broader `BusinessValue` union.
[specification_provenance.zig](../src/domain/specification_provenance.zig), lines
72–90, also permits normalized business text. If the unchanged provenance contains
only ordinary claims, the instruction demands a nonexistent token choice while
the native contract still permits normalized text. This is impossible guidance,
not proof that the replacement target itself is impossible.

Specification packet generation also independently filters retained claims at
`specification_session.zig:53–55`, while provenance enforces retained eligibility
at `specification_provenance.zig:40–48`. Those currently agree; this is a drift
risk, not an additional demonstrated mismatch.

**Owning correction:** applicable rules and eligible alternatives come from the
contract that validates them, then feed initial guidance, rejection and repair.
Keep text/schema rendering separate from rule ownership. Do not add a third
compatibility table to an authorizer or repeat constraints throughout YAML.
Rollout: 08–11, with the shared consumer audit in 12.

The shared [repair prompt](../design/workflows/spec/repair.prompt.md), line 2,
also says “Correct repair.rule”, although the rule is immutable input. Clarify
that the replacement must satisfy the rule. R15 does not prove this wording
caused the model to echo the repair envelope; changing it alone cannot cure F1.

### F4 — Redundancy decisions disagree with canonical equivalence

[typed_text.zig](../src/domain/typed_text.zig), lines 96–114, joins adjacent literal
nodes and normalizes text. Summary/signal/conflict validation uses that canonical
representation. Reconciliation authorization instead compares raw native JSON
at [reference_reconciliation_repair.zig](../src/domain/reference_reconciliation_repair.zig),
lines 71, 84, 134, 155 and 183–186.

Two statements with identical claim IDs and otherwise identical content can
represent the same sentence as one literal or two adjacent literals. Both have
the same canonical text and evidence. Raw equality fails and overlapping entries
become `competing_entries` instead of mechanically redundant occurrences. Signals
and conflict summaries have the same representation-dependent comparison.

**Effect:** conservative blocking of an equivalent representation, not unsafe
acceptance. Nevertheless, the repair decision independently defines equivalence
and is brittle under permitted LLM variation.

**Owning correction:** retain canonical equivalence and coverage facts from the
owning validator and consume those in deletion authorization. Text equality alone
is insufficient: different evidence, obligations or meanings must still block.
Specification duplicate handling already uses normalized content/evidence facts.
**Keep atomic old-value/dependency equality exact**; normalizing `atomic.equal`
would weaken the correct CAS boundary. Rollout: 08–10.

### F9 — Dependency binding depends on a lossy presentation and partial fact copies

**Final-review finding.** This differs from F2: F2 concerns information hidden
from the model; F9 concerns validation inputs missing from the engine's own
authorization preconditions.

[specification_candidate_context.zig](../src/domain/specification_candidate_context.zig),
lines 6–24, calls `session.packet`, copies its serialized model input into
`Facts.input`, then snapshots those bytes plus selected policy fields and candidate
state. Building a dependency binding therefore performs model-packet construction;
repair packet construction later performs it again. A presentation-only change
can affect authorization identity even when native validation inputs are unchanged.
More importantly, a lossy projection is not a complete validation dependency set.

Two source-derived fault-injection cases establish missing inputs:

1. Change only `context.registry.grammar.reference_names[0].basename` after a
   valid rejection, preserving source paths, policy rules, passive records and
   candidate. Specification packet projection does not read that field, so its
   snapshot remains unchanged. Yet
   [path_token_grammar.validateBinding](../src/domain/path_token_grammar.zig),
   lines 34–40, rejects it before candidate text validation.
2. With `summary_count > 0`, change only reconciliation progress's `latest` to
   `null`. The specification snapshot does not retain the summary chain and
   its model packet is unchanged. But
   [specification_provenance.bind](../src/domain/specification_provenance.zig),
   lines 22–27, calls the owning history validator, which rejects the broken chain.

The same fields are missing from
[specification_coverage_repair.Facts](../src/domain/specification_coverage_repair.zig),
lines 11–36. Its precondition can also remain unchanged before merge's native
revalidation detects invalid context. Extraction text facts retain reference
names, and reconciliation facts retain names and summary history:
[extraction context](../src/domain/reference_extraction_context.zig), lines 12–22;
[reconciliation context](../src/domain/reference_reconciliation_context.zig),
lines 5–41. These sibling differences demonstrate drift in independently authored
dependency projections. They do not justify copying an entire runtime context.

**Effect and limit:** under these domain-boundary mutations, authorization can
accept an unchanged snapshot even though context no longer satisfies its validator.
Failure may surface only after a repair call or at revalidation. These are source
counterexamples, not executed regressions or evidence of an ordinary live mutable
context exploit. The runner's immutable value ownership and subsequent validation
still matter; no successful invalid publication was demonstrated.

**Owning correction:** dependency capture consumes typed native evidence, lineage
and text-policy facts. The existing owners supply complete serializable facts
for the checks they perform; affected consumers reuse those projections.
Snapshotting and model-input rendering are separate consumers of those facts.
Keep process-local capability/current-policy identity checks at their existing
boundaries; never serialize ports, pointers or an entire runtime service object.

Remove `Facts.input` and dependency capture's call to `session.packet` once typed
capture replaces them. Replace the duplicated partial text-fact projections at
all affected consumers in the same change. Do not merely append the two observed
fields, hash a larger prompt, weaken exact CAS or create a new dependency registry.
Trace all actual validator reads, including lineage, before choosing the complete
projection. This is shared chunk 08 work with specification consumers 11–12.

## 4. Downstream interfaces that remain unfinished

### F5 — Review evidence eligibility conflicts with reconciliation obligations

[Signal validation](../src/actions/reference/validate_reference_signal_proposals.zig),
lines 41–43, requires projection of every nonconflicting token, including a
superseded token. [Specification authority](../src/domain/specification_authority.zig),
lines 47–63, creates review obligations for accepted signals and preservation
claims. [Support collection](../src/domain/specification_support.zig), lines 50–51
and 75–79, requires exactly the signal's claims, but validates them using business
provenance, which rejects every non-retained claim.

A required superseded-token signal cannot receive a supported review through
this interface. The packet exposes all claims while the support prompt asks for
retained IDs. This is already reached by the existing production-graph test at
[composition/root.zig](../src/composition/root.zig), lines 1430–1438: native cycle
repair completes reconciliation, then support fails with `operation_failed`.
The test deliberately records the incomplete downstream behavior; it is not a
successful workflow-recovery test.

**Owning correction:** establish evidence eligibility by review purpose and
requirement under the existing support/provenance contract, then use it for
packet choices, collection and obligation projection. Preserve the existing
signal/token obligations and stricter business content provenance. Do not remove
obligations or add a global “allow superseded claims” escape hatch.
This seam predates the latest Phase 3 follow-up. It remains Phase 4, 13–14.

The support domain owns review-purpose eligibility; the existing structural
requirement identity supplies its discriminator. Business provenance continues
to own retained business support. Both reuse canonical ID/citation/scope joins.
An additional configurable eligibility registry is unnecessary. Conflict evidence
can explain a negative finding without becoming permitted business support.

### F6 — Support review cannot check completeness against unseen source material

[Support packet](../src/domain/specification_support.zig), lines 23–28, exposes
extracted claims, their citations, surviving tokens, signals and conflicts.
[model_evidence.zig](../src/domain/model_evidence.zig), lines 67–97, builds this
view from claim items. The packet does not provide the full captured source scope
or extraction decisions that discarded a token or omitted a source flow.

Coverage and required-token obligations are derived from surviving claims. A flow
omitted during extraction may therefore be absent from both the review evidence
and its obligation set. Downstream review cannot independently detect an omission
in source content it cannot inspect. This is a structural limit, not a claim that
R14/R15 reached review and falsely passed; neither did.

**Owning correction:** give the existing review the relevant bounded source scope
and extraction/reconciliation decisions alongside proposed output. Preserve source
IDs and partitioning rather than repeatedly dumping the entire corpus. Review
should distinguish correctly irrelevant content, incorrectly discarded meaning,
wrong preservation kind and unsupported additions across unrelated domains.
Semantic completeness remains model-assisted, not deterministic proof. Phase 4,
13–14; independent final rubric evaluation remains required.

### F7 — Review findings lose causal detail and genuine gaps lack actionable output

[specification_support.zig](../src/domain/specification_support.zig), lines 10–16,
defines only a coarse finding, disposition, requirement ordinal and selection.
The ordinal identifies the structural requirement, including its field/member,
but carries no concise missing datum or distinction between absent source
information and candidate non-preservation. Collection retains the requirement
and verdict while discarding the validated claim/source selection supporting
that finding in `required_authority.Evidence` at lines 95–102.

Mechanical collection failures become `OperationExecutionFailed` at
[specification_support_workflow.zig](../src/application/specification_support_workflow.zig),
line 31. The precise rejection/repair flow implemented upstream stops here.
The shared authority router consequently lacks the information needed to treat
a supported candidate omission differently from genuine missing authority.

Separately, [spec.workflow.yaml](../design/workflows/spec.workflow.yaml), lines
355–356 and 459–460, sends pre/post authority `needs-user` directly to the terminal.
The registered clarification-output path at lines 509–526 accepts generation
clarification results, not these authority-gap findings. The engine stops safely
but does not produce a specific question for such a gap.

**Owning correction:** preserve a typed finding with exact requirement, candidate,
source association and concise cause; keep execution-local origin distinct from
persisted evidence. Repair malformed review data through its candidate contract.
A substantive negative verdict must not be retried until it becomes positive.
Use the existing authority classifier/router and convert genuine gap results into
existing clarification needs/refresh/render/publication. Do not fabricate a
generation response, add another clarification registry or invent source answers.
Phase 4, 13–15. H-011's answer-authentication decision remains unapproved.

The existing [model candidate handoff](../src/application/model_candidate_handoff.zig),
lines 7–16, already supplies `{body, origin}` after exact association. The support
binding currently passes only `.body` onward. Retain that origin for execution-local
findings rather than inventing a second request identity mechanism.

## 5. Persisted acceptance is weaker than fresh construction

### F8 — Readers do not re-establish all canonical record associations

[Fresh state construction](../src/actions/specification/build_specification_state.zig),
lines 16–23, validates the authority result against current inputs and recomputes
coverage. [specification_state.zig](../src/domain/specification_state.zig), lines
33–58, parses the closed shape but only checks a subset of those associations:
feature, top-level `all_resolved`, references, required record families, record IDs,
ledger and clarification ordinals.

Concrete source-level counterexample: starting with a valid serialized state,
empty `review.seeds`, `review.evidence`, `review.candidates`, `review.observations.entries`
and `review.result.entries`, leaving its feature and `all_resolved` tag unchanged.
Those empty arrays satisfy their structural types; the complete reader validator
does not inspect their contents. It also does not validate persisted content
provenance or coverage associations. [reference_snapshot.zig](../src/domain/reference_snapshot.zig),
lines 42–114, checks source/citation/ordinal joins but not the full disposition
graph, signal compatibility and exact citation unions established in production.

The final review found another counterexample under this same ownership defect:
[live source accounting](../src/actions/reference/validate_reference_accounting.zig),
lines 49–56, requires contiguous blocks from byte zero through the complete source.
Persisted snapshot validation, lines 58–76, rejects overlap/out-of-range spans but
allows uncovered gaps and suffixes. Appending uncited text to a previously valid
persisted `source.bytes` while retaining blocks, chunks and citations leaves their
existing checks satisfied. The reader never checks that the last block reaches
the new source length. This source-derived case needs the same canonical coverage
predicate at both boundaries, not a special suffix check added only to the reader.

**Current effect:** a fresh Specify invocation can accept an internally weakened
prior state. Its current consumers reuse only the ID ledger and revision, then
perform fresh generation/review. No path was established that imports its old
review as authority to bypass those checks or publish unsupported output.
Future downstream authority consumption would magnify this gap; that is a risk,
not an already demonstrated bypass.

This is producer/reader acceptance divergence. The validators predate Phase 3;
the state checks trace to September 11 commits `5d93faf1`/`e9c20799`. They should
not be blamed on the latest narrow repair change or silently ignored when richer
review evidence is added.

**Owning correction:** reuse pure canonical record predicates beneath live action
and history wrappers. Intrinsic record validity and current execution authority
are separate checks. The parser has no saved `ValidToolchain`, live path grammar
or model-request ledger; it must not fabricate them. Current-policy checks remain
at the existing boundary where those inputs are available. If sequencing requires
parsed and fully validated values to remain distinct, preserve that distinction
rather than labelling a structural parse complete authority.

The concrete reuse boundaries are:

| Existing implementation | Cohesive shared responsibility |
| --- | --- |
| `reference_evidence.resolve`, `source_citations.validate`, `reference_reconciliation.item/citationUnion/unique/sameSet` | Canonical scope, quotation, ID and membership joins. Snapshot validation already correctly reuses citation validation. These functions do not establish semantic support or decide review-purpose eligibility. |
| `validate_reference_accounting.zig:49–56` | Complete canonical source/block coverage and position agreement. Retain live inventory/debit checks in their current owner; reuse the source-span predicate for persisted records. |
| `build_reference_reconciliation_items.zig:8–29` | Canonical claim/citation join. Move the required pure core into domain ownership if readers need it; a domain parser cannot call the action or copy its implementation. |
| `validate_reference_claim_dispositions.zig:23–61,69–99` | Relationship/cardinality/cycle predicates over canonical claim/disposition data. Factor those once for reuse; the live action retains candidate/context attribution. |
| `specification_provenance.resolve`, `specification_coverage.check`, `specification_authority.project` | Respective eligibility, coverage and structural-obligation rules. Give their reusable cores the narrow typed canonical records they read instead of manufacturing the historical `r.Accounted` envelope. They remain separate responsibilities. |
| `required_authority.policy/reconcile/validate` | Existing ownership/resolution authority. Persisted validation must not introduce another interpretation of `all_resolved`. |

Reusing the disposition loop alone is insufficient. The model proposal's closed
union in [reference_reconciliation.zig](../src/domain/reference_reconciliation.zig),
lines 49–65, structurally guarantees zero related IDs for `retained` and one for
`duplicate`. The flattened persisted record does not. The live action relies on
those guarantees at lines 42–44 and uses `unreachable` for retained-with-relations
at line 53. The shared canonical boundary must establish those legal cardinalities
before graph traversal, as well as the existing nonempty/unique/member rules for
other variants. Reject retained-with-relations and duplicate-with-zero/multiple
targets; never import trusted-proposal assumptions into an untrusted stored record.
This is a requirement for the proposed refactor, not a demonstrated current parser
crash: current readback never runs that action loop.

References: [canonical item construction](../src/actions/reference/build_reference_reconciliation_items.zig),
[disposition checks](../src/actions/reference/validate_reference_claim_dispositions.zig),
[coverage](../src/domain/specification_coverage.zig),
[requirement projection](../src/domain/specification_authority.zig).

Live `input/history/bind` checks retain partition, summary-chain, current-policy
and execution associations. Persisted readers must not construct fake `Progress`,
`Input`, `Parsed`, origins or accepted-stage flags to satisfy those functions.
A canonical record view, where needed, is data rather than a new authority service.
Do not remove live lineage validation while removing unnecessary reader coupling.
Integrate persisted review associations in 13 and complete snapshot/content/
coverage validation in 17, before readiness in 18. No replay, journal or parallel
reader/validator is needed.

## 6. Why the phase kept reopening

Git history separates the defects:

| Implementation point | What it establishes |
| --- | --- |
| Content validation before Phase 3 (`5e5ce7d7`; typed diagnostics later in `a5db1bda`) | Content-kind and exact-token restrictions already existed. The current model is not introducing a new validation rule. |
| Phase 2 (`139c427e`) | Stage-specific rule projection introduced separately maintained applicability lists; global content guidance is incomplete. |
| Phase 3 (`4294c639`) | Narrow reconciliation target mapping, raw redundancy comparisons and narrower specification targets were added without complete feasibility/dependent-context checks. These are confirmed brittleness introduced with that implementation. |
| R14 follow-up (`f880799b`) | Typed-text diagnostics and shared merge observations were threaded through consumers. Those fixes preserve useful evidence; no second CAS/retry authority was found. They did not complete the broader feasibility/context contract. |
| Existing downstream/persistence code | Support eligibility, review detail, clarification and readback validation remain incomplete separately. Fixing the first rejection allows later gaps to become reachable. |

The architecture tests check capability boundaries and shared imports/CAS calls.
At [architecture_test.zig](../src/architecture_test.zig), lines 1893–1917, all five
consumers must use `atomic_repair` and one `checkMerge`, without a private retry
limit. Those assertions are valuable but cannot prove that a selected target is
possible or that a request contains sufficient facts.

Existing repair tests strongly cover owner/revision/sibling safety. At
[specification_generation_test.zig](../src/specification_generation_test.zig),
lines 333–378, the test obtains a correct replacement from `good.provenance` in
its fixture. It does not establish that the serialized request supplies the
unchanged description needed to choose that evidence. Merely changing the fixture
sentence does not vary the missing architectural dependency.

Reconciliation tests reject wrong kinds and demonstrate selected repairs, but
do not establish feasible authorization for mixed kinds or empty eligible sets.
The initial-guidance test at `reference_reconciliation_test.zig:736–776` checks a
specific disposition rule appears, not completeness of all applicable rules.
Some graph tests intentionally end at a known downstream failure (F5).

Thus passing tests established particular safety and branch properties, while
phase closure implied a more complete repair contract. The changing live failure
does not prove previous fixes reverted. It reflects both LLM variation and
different unclosed boundaries becoming the first stopping point.

### F10 — CLI and harness duplicate production assembly wiring

[composition/root.zig](../src/composition/root.zig), lines 87–127, and
[harness invoke.zig](../test/harness/e2e/invoke.zig), lines 9–23 and 45–61,
separately construct adapters, supply the native binding list, bind publication
and prior-state ports, bind roots, and assemble provider bootstrap, clock, runtime
and invocation. This is duplicated functionality and a maintenance risk, even
though both currently select the same production implementations and policies.
No current divergence or causal link to R15 was established.

Chunk 20 should own adapter construction, binding and lifetime once in the existing
composition layer, exposing only the narrow inputs genuinely different between
callers. Keep CLI argument/environment/exit behavior in the executable. Keep fixture
checks, trace storage, publication oracle and grading in the harness. Preserve
isolated test credentials without weakening production environment validation.
Do not introduce a universal runtime service or hidden execution dispatcher.

The evaluator is a separate consumer, not duplicate engine authority. It already
reuses provider request/response/HTTP primitives through
[harness bedrock.zig](../test/harness/bedrock.zig). Its configured grading attempts
and token budget in [evaluate.zig](../test/harness/evaluate.zig), lines 18–97,
remain independent; the E2E handoff requires successful publication before grading
starts. The standalone evaluator may grade a separately supplied specification.
Forcing evaluation through workflow repair authorization or the generation ledger
would mix responsibilities. Consolidation remains chunk 20, after the first
baseline unless an actual assembly divergence blocks it.

## 7. Smallest complete correction and closure evidence

Complete the existing interfaces. The following responsibility allocation guides
implementation; these rows do not require a new module or action for every row.

| Responsibility | Existing owning boundary and limit |
| --- | --- |
| Define a relation | The narrow domain contract defines eligibility, content compatibility, canonical equivalence, source coverage or graph validity. Share its pure predicate/facts where multiple consumers need the same rule; do not build one engine-wide validation service. |
| Validate a candidate | The owning validator applies those rules to current candidate/context and retains checked facts or a precise rejection. It does not choose a successor or plan a repair sequence. |
| Capture dependencies | Existing context owners capture typed inputs actually read by validation. Shared text/lineage facts are projected once by their owners. No model-packet serialization or capability container is needed (F9). |
| Authorize a unit | The domain authorizer consumes retained facts and selects an approved target or existing block. It does not reinterpret relation predicates, enumerate all possible repairs or introduce new policy on retry. |
| Build model input | The packet builder projects the authorization's model-relevant facts and minimal immutable context; the compiled selected schema defines the response. Presentation neither establishes native dependency validity nor decides eligibility. |
| Parse and merge | Existing selected decoding and atomic association/CAS guard the permitted operation; the domain merge applies it to the candidate. Canonical redundancy and exact old-value equality remain different operations. Neither grants validation acceptance. |
| Execute and account | YAML declares transitions and local limits; the capability-free orchestrator follows them; the runner invokes bindings, validates/applies deltas and enforces accounting. A repair helper gains none of those responsibilities. |
| Admit support evidence | Support collection decodes, validates and constructs a bound review finding. Those checks serve one trust boundary. Reuse its canonical association predicates where needed without adding an action per field or a second review orchestrator. |
| Validate persisted records | Pure canonical record predicates check stored associations. Current-policy and live-history wrappers remain at their existing execution boundaries; readers cannot fabricate their inputs (F8). |
| Assemble runtime resources | The composition layer owns production adapter construction/binding/lifetime. CLI behavior and harness evidence/grading remain in their own callers (F10). |

A repair module exposing cohesive `authorize`, `parse` and `merge` helpers is not
by itself a single-responsibility violation. The demonstrated split is dependency
capture constructing model presentation; the demonstrated policy drift is the
independent applicability/equivalence/dependency selection. Extract only reusable
logic with a proven shared owner, not a file or interface for each target variant.

Feasibility facts are narrow facts for the selected relation/rejection. Do not
enumerate every claim subset, conflict clique, target combination or repair
sequence. There is no new generic fact registry, dynamic dependency graph,
feasibility callback in `atomic.Contract`, semantic solver or convergence proof.
Known impossibility must block under existing policy; accepted independent repairs
must remain usable. The ordinary validator still judges the proposed replacement.

A normalized `BusinessValue` is an allowed model choice only where its existing
contract and source obligations allow it. Fixing F3 does not authorize automatic
exact-copy-to-prose conversion or weakening a preservation obligation.

Detailed remaining cases, delivery order, cleanup and checks have one home in
[the rollout follow-up](TODO_FIX_001.md#phase-3-architecture-audit-follow-up), with
later support/persistence/assembly checks in chunks 13–17/20. The accepted target
and decision boundaries remain in [the contract review](CONTRACT_FIX_001.md#3-authorized-repair-targets-and-dependency-checks).
This report owns findings and evidence; it does not maintain a parallel task matrix.

Each missing case needs an owning-boundary regression plus the affected production
graph path. For cases that invoke a model, assertions must inspect the actual
serialized request rather than supply hidden context solely inside the fake.
Deterministic coverage/readback tests inspect native authorization, validation and
publication boundaries. Do not replace existing safety tests or label these live
E2E evidence.

A single repair need not eliminate every candidate diagnostic. A selection change
may expose missing coverage that an existing independently authorized insertion
can restore. Preserve valid siblings, keep the candidate unaccepted until all
required validation passes, and require an established safe single-record order.
Otherwise G1 applies; this is not automatic scope expansion.

Phase 3 chunks **08–12 are reopened for the specified gaps**. Phase 4/5 retain
their existing responsibilities; the audit does not move every unfinished feature
into Phase 3. The next Phase 3 delivery must cover F1–F4 and F9 as one coherent contract
completion with testable owning-boundary chunks. A signal-only patch is insufficient.

## 8. Logging, retained run evidence and quality limits

The [R15 analysis](FIX_001.md#13-post-follow-up-live-run-review) remains the exact
run account. Its 13 calls have all 65 expected evidence files; 254 events are
readable. Calls 12 and 13 contain the selected content schema. Call 13 also has
the original repair assignment, the latest exact rejected bytes and native schema
diagnosis. The terminal malformed envelope is not evidence of missing schema,
engine-imposed output truncation or lost raw response. No replacement merged and
no spec or rubric evaluation was produced.

Additional **native facts**, not another raw-body log, are needed:

| Information | Existing owner/channel and purpose |
| --- | --- |
| Feasibility/blocked reason and eligible choices | Validator/rejection/authorization, projected into the request and existing candidate diagnostic. Distinguish an impossible assignment from an invalid model answer. |
| Dependent context supplied | Existing retained request body. Tests verify its relation to bound candidate facts; reports must not derive their own eligibility or feasible-target decision. |
| Canonical redundancy decision | Owning validator's equivalence/coverage fact, linked to authorization. Exact CAS data remains unchanged. |
| Review cause and source/candidate association | Typed support finding retained through collection, shared authority routing and reports; preserve precise mechanical collection rejection instead of `operation_failed` alone. |
| Stage acceptance | Existing native validation outcomes and merge origins. A merged or changed replacement remains separate from a validation pass and published completion. |
| Executed build identity | Existing harness run metadata, including relevant dirty-source identity. Captured prompt/resource equality does not establish which executable build ran. No production Git dependency is required. |

Keep candidate origin, latest model exchange and merged replacement distinct.
Deduplicate repeated projections of one decode/schema failure rather than counting
events as separate failed calls. Preserve execution-local request correlation and
canonical persisted evidence as separate lifetimes. Existing protected logging
rules apply; these findings do not authorize unrestricted production prompt,
response, secret or free-form metadata logging.

First close the required offline contracts and downstream baseline prerequisites,
then request approval for one concrete live baseline run. It must use the configured
LLM, publish `spec.md` and required artifacts, and grade those exact bytes against
the rubric. The first completed/scored baseline precedes repeatability and A/B
comparisons. A score is not a quality pass without an adopted acceptance threshold.
Subsequent approved runs and independent cases measure reliability; passing the
mechanical matrix cannot guarantee model convergence or semantic completeness.

## 9. Validation performed for this audit

The earlier architecture-review pass ran the full repository gate against this
unchanged implementation:

```sh
TMPDIR="$PWD/.zig-cache/tmp" zig build --global-cache-dir .zig-cache/global --system zig-pkg verify --summary all > .zig-cache/architecture-review-verify.log 2>&1
```

Result: **120/120 steps succeeded; 1,393/1,393 tests passed**, including lint,
architecture, unit/integration checks and native packaging smoke. The command
needed the existing approved escalation to read the installed Zig toolchain.
Log: [architecture-review-verify.log](../.zig-cache/architecture-review-verify.log).
No live harness invocation occurred. No new regression tests were written or run
for these findings; the source counterexamples and missing evidence are identified
above. The final documentation review did not rerun engine tests or make live calls.
This pass establishes the current suite's result, not closure of those findings.

The earlier documentation pass checked 301 inline links and corrected 75 historical
root-relative evidence links after the original report's move under `fixes/`.
The final pass checked **323 local inline links and 22 reference links**, with no
missing targets/anchors or unbalanced code fences. `git diff --check` and
`git diff --cached --check` passed. Diff/scope review confirmed that only the four
review/rollout Markdown files differ from the implementation revision. The final
cleanup removes duplicated action tables and obsolete operation-introduction
instructions; governing target and approval decisions remain in their existing
contract record. Implementation files remain unchanged.

Review documentation is linked from [FIX_001](FIX_001.md#14-full-architecture-review)
and mapped into [the rollout](TODO_FIX_001.md#phase-3-architecture-audit-follow-up).
Applicable governing decisions remain unchanged. The required next evidence is
completion of these shared contracts and their tests, followed by an explicitly
approved successful and scored live run.
