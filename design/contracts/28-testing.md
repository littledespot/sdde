# 28. Testing strategy

Part of the [proposed design](../design.md#28-testing-strategy). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

### 28.1 Action unit tests

Each action is tested with immutable fixtures and fake narrow ports. Required cases include:

- schema rejection of unknown keys, missing required fields, and unresolved `<!-- IMPLEMENT -->` placeholders;
- **Configuration paths:**
  - Resolve the exact current-working-directory `.sddtoolkit.json` without parent/child search.
  - Fail terminally for a missing file; reject aliases.
  - Require the exact eight-key `paths` set, all configured locations and the fixed
    `<paths.workflows>/features/` child.
  - Reject `design/examples/` and packaged-source fallbacks.
- only the root `features/` directory is engine-reserved; every other directory
  follows ordinary definition/resource traversal, including unrelated names;
- **Activation:**
  - Perform no project-journal, transaction-ledger or collection-lock operation.
  - A failure after any activation write cannot issue an active-feature capability.
  - Revalidate ownership before a rerun repeats authorized writes.
- **Workflow inventory and compilation:**
  - Validate complete workflow-root collisions and stable inventory ordinals.
  - Require one terminal account per entry and exact captured-source joins.
  - Accept arbitrary bounded definition counts with unique workflow IDs and logging shortcodes.
  - Enforce reserved-child collision checks and descendant exclusion.
  - Require closed definition schemas and registered-operation/declared-resource resolution.
  - Prove graph/outcome closure and bounded cycles.
  - Reject executable payloads, infrastructure selection, capability additions,
    gate weakening and runner bypasses.
  - Retain feature-bound workflow IDs; a missing/changed bound graph blocks migration.
  - Keep unrelated definition changes compatible with registry refresh, including
    an earlier-sorting source that shifts existing inventory ordinals.
- **Preset registry:**
  - Resolve packages directly from `paths.toolchainPreset`.
  - Validate the complete registry independently of project/environment selection,
    including unselected package-declared references.
  - Reject legacy/source preset fallback.
- **Project toolchain:**
  - Validate exact `<paths.principles>/toolchain.yaml` capture, schema, direct
    inheritance and typed overrides without claiming pre-merge safety.
  - Reject a schema-valid override when its effective merged result weakens a compiler lock.
- **Principle inventory:**
  - Account for the complete principles root.
  - Give exact `toolchain.yaml` one `mechanical_toolchain_layer_excluded` account
    and no semantic reservation/source/map/module/chunk.
  - Admit only validated normalized Markdown candidates into semantic capture budgets.
- inert `paths.templates` behavior across all four runtime stages, including proof that an identically named `*.template.md` is not captured until an explicit accepted init operation has copied it into `paths.principles`;
- config path overlap and environment-root ambiguity;
- **Specify invocation:**
  - Require exact CLI grammar with `--feature` and `--reference`.
  - Reject missing, duplicate, unknown and positional inputs.
  - Derive the brief from references independently of the selected directory.
- **Feature directory:**
  - Validate explicit-directory normalization/containment and reject invalid aliases/symlinks.
  - Exercise same-directory reruns with changed references.
  - Prove no ownership-registry access or generated-name fallback.
- path traversal, absolute/drive/UNC paths, encoded separators, NUL/control characters, and symlink escape;
- segment-prefix traps such as `src2` matching `src` incorrectly;
- case-fold collisions;
- compound extensions such as `.test.tsx`;
- create versus update behavior for legacy filenames;
- co-located and mirrored test mappings;
- path-intent option membership that rejects kind/role/template/capability recombination, including overlapping file kinds with different capability ceilings;
- **Registered name transforms:**
  - Check every transform's fixed vectors; reject unknown transforms and invalid/empty results.
  - Prove stable template/path ordering and duplicate elimination.
  - Cover zero candidates and candidate-limit exhaustion.
- **Model path guidance:**
  - Supply bounded normal option/candidate guidance and complete fallback-only path guidance.
  - Apply no local model-call size gate.
  - Propagate provider size failures without truncation.
- generated/forbidden path rejection;
- Java package/path and public-type/basename rules;
- .NET project ownership and test naming;
- command placeholder typing and metacharacters passed as literal argv;
- direct-equality bootstrap reuse versus planning-owned pre-`specified` deferral, including rejection when either closed route variant is substituted for the other;
- **Bootstrap blueprints:**
  - Keep aggregate blueprints identity-free and limited to typed candidate references.
  - Materialize leaves before grammar, and grammar before policy.
  - Reject unresolved/cyclic references; bind every derived handle.
- reference MIME mismatch, unsupported reader, corrupt file, and exact accounting;
- citation bounds and verbatim mismatch;
- requirement/task ID assignment and renderer escaping;
- coverage for requirements, guards, copy, states, and preserved tokens, including visual-token checks where applicable;
- **Shared authority reconciliation:**
  - Exercise required slots across unrelated domains with zero candidates, one
    current candidate, directly equivalent duplicates and multiple non-equivalent candidates.
  - Cover ambiguous semantic support, stale authority, scoped/unscoped exceptions,
    allowed/disallowed `not_applicable`, unknown ownership and downstream discovery
    of an upstream-owned gap.
  - Require the same closed outcomes and routing semantics in every domain.
- task unknown dependency, cycle, phase violation, read/write conflict, and exclusive command;
- patch scope, patch failure, unexpected file changes, and evidence predicates;
- create/update/replace/copy/delete expected-state rules and copy-source authorization;
- **Semantic Markdown principle capture:**
  - Use filename-only category hints and deterministic applicable-category selection.
  - Require complete chunk accounting and exact mechanical `toolchain.yaml` exclusion.
  - Supply current selected spans to the focused Spec policy assessment (§17.3.1),
    keeping extraction, source-preservation and business generation authority separate.
  - Cover the UTC/greeting conflict and unrelated privacy/retention constraints:
    preserve clear requirements, cite mandatory Plan obligations and resolve them only
    at the owning gate. Genuine business gaps remain SNN; source loss remains a defect.
  - Reject omitted/foreign/stale assessment evidence and lost downstream obligations.
    Changed principles refresh dependent assessments and approvals without rewriting
    business intent. Empty/unrelated principles invent neither requirements nor questions.
  - Prove no Spec-to-PNN predecessor cycle, no policy approval inferred from review,
    and no old no-conflict result certifying Plan's current policy compliance.
  - Distinguish principle capture from assessment execution on a source-gap pause;
    do not report an unexecuted assessment as passed. Preserve supported business
    intent where selected principles conflict; route policy obligations to their owner.
  - Include requirements supported only by validated answers and authenticated Spec
    edits; their current bindings and policy assessment cannot be skipped on rerun.
- **Clarifications:**
  - Prove subject-key equality/deduplication, `S/P/T` ordinal ceilings and execution-private allocation.
  - Distinguish open-submission from closed-audit view editability.
  - Require exact complete conflict-set/view projection.
  - Reject stale answers; exercise authority/user resolution on rerun.
  - An open Spec clarification prevents all planning/model work; an open Spec or
    Plan clarification prevents all task-generation/model work. Test policy-obligation
    handoffs alongside open questions and reject attempts to relabel or drop those
    questions. Closed file status without current validated resolution cannot pass.
  - Both need producers prepare identifiable subjects, current evidence and exact user
    decisions through §12.7. Identical review text for different S/P/T subjects must
    not produce indistinguishable questions or shared answer authority. Preserve IDs,
    controlled-region readback and closed/concurrently closed bytes; add no summary call.
  - Cover source text that supports several specification categories without separate
    headings, and genuinely missing actors/decisions in unrelated domains. Questions
    identify known facts and the specific missing answer; diagnostic copying and
    asking for already-supported behavior fail the actionability assessment.
- **Logging:**
  - Production execution must emit registered lifecycle/validation/retry events;
    an empty event stream with complete prompt bodies is not complete logging.
    Compare executed operations and exchanges with attributed records across
    recovery, exhaustion, needs-user, failed publication and cancellation.
  - Reconstruct every debug/trace request and available response from fragments,
    including rejected JSON and partial transport. Prove capture/append/flush
    failures cannot become success or silently lose diagnostics.
  - Cover the §27 publication/finalization ordering decision: pre-write intent is
    never reported as successful publication and no record is appended after close.
  - Normalize log-level case and `CRITICAL`/`WARN` aliases.
  - Use fixed `.log` feature event/prompt paths.
  - Write `feature-log/v2` column headings and control rows exactly once.
  - Prove deterministic pipe-delimited escaping/null encoding.
  - Reject heading/row-width corruption.
  - Exercise threshold filtering and prior-tail recovery.
  - Redact before truncation; fail closed on sink failure.
- `red_then_green` intended-failure matching and required later green evidence;
- post-command declared, ephemeral, and undeclared delta handling;
- **Execution leases and locks:**
  - Exercise process-lease acquisition, rejection and validation cleanup.
  - Exercise feature-lock acquisition, contention and validation cleanup.
  - Require exact three-variant lock-terminal evidence and release ordering.
  - Prove process-death release and nonrebindable lease IDs.
  - Reject PID/time/heartbeat-only liveness.
- **Changed-reference specification authority:** prove that the successor snapshot, reference
  view, descendant/runtime/evidence invalidation, cleared downstream pointers
  and reference-dominant bootstrap mutation form one complete validated output
  set under §25.
- **Prior-run logging:**
  - Exercise active, already-closed, mixed, duplicate, missing-release,
    wrong-binding and orphan-release groups.
  - Keep fresh policy/binding construction unreachable until total finalization
    evidence validates.
- transient unauthorized command writes that are restored before exit, which must still terminate the command and invalidate its evidence;
- **Publication:**
  - Validate output before publication.
  - Unrepaired JSON/schema rejection with existing open forms ends in error with no
    publication calls. A successful correction may reach a valid clarification pause.
  - Source, generation, candidate-review and residual open-registry pauses all publish
    the validated incomplete specification through the same path, remain ungraded,
    and keep Plan/Tasks gates closed. Rejected response bytes never enter that view.
  - Inject failure/interruption at every write; record no new successful completion afterward.
  - Exercise fresh reruns without rollback.

### 28.2 Property-based tests

Configured JSON composition must satisfy the shared
[ADR 0016 acceptance matrix](../decisions/0016-configured-json-response-composition.md#6-implementation-acceptance).
Test extraction and unrelated nested-object/tagged-variant/whole-array contracts
through the same owners. The matrix includes final-review counterexamples for
schema ownership after registry cloning, prerequisite placements, request closure,
atomic handoff and native repair/provenance. These are required regression cases, not evidence supplied
by the design review. Compiler-bound increases require at/beyond-limit, overflow
and storage/runtime checks, not removal of the expansion guard.

Generate large path/task/requirement spaces to prove invariants:

- normalized paths never escape the root;
- accepted create paths always match exactly one environment/project and pass their declared kind;
- task graphs accepted as DAGs remain acyclic after ID assignment;
- calculated parallel pairs never have declared write/write conflicts;
- editable-spec render then parse preserves normalized specification IR;
- every generated view equals deterministic rendering of canonical IR;
- atomic repair never changes immutable sibling pointers;
- every generated required-authority ledger is exhaustively partitioned one-to-one into closed outcomes, and no non-success outcome can satisfy a stage gate;
- adding arbitrary registered requirement kinds cannot change reconciliation cardinality, earliest-owner routing, or the prohibition on default/approximate/local continuation;
- stable inputs plus the same accepted model payload render identical bytes.
- every schema-valid workflow definition compiles to one closed graph that:
  - contains only YAML-referenced registered operation contracts;
  - handles every declared outcome;
  - has no unbounded cycle;
  - cannot add a capability or weaken a referenced gate;
- adding or removing an unrelated valid workflow does not change the compiled
  semantic authority selected for another `WorkflowId`, even when provenance
  ordinals and registry validation evidence change;
- the initial `plan`, `tasks`, and `implement` graphs retain their required
  predecessor gates under every accepted definition parameter combination.

### 28.3 Orchestrator tests

Use spy child nodes; no real filesystem/model ports are available to the orchestrator.

- bootstrap failure prevents every model action;
- the workflow-engine orchestrator:
  - resolves an explicit workflow ID once;
  - invokes the selected registered invocation-contract binding once;
  - follows only compiled typed transitions through spy child bindings;
  - returns the compiled terminal outcome;
  - contains no branch for `specify`, `plan`, `tasks`, `implement` or any unrelated workflow name;
- the YAML-named `specify` invocation operation coordinates its parser then
  validator through runner-owned bindings, returns only validated typed run
  context, and makes graph entry unreachable after either child rejects;
- an unknown workflow ID, missing registered operation binding, or child outcome
  without a compiled transition prevents every selected-graph child;
- startup, unknown-workflow, and invocation-contract rejection paths acquire no
  feature transaction lock; selected SDD setup validates its supplied directory
  without an ownership registry or cross-feature scan;
- an unrelated compiled workflow that does not reference SDD target-context
  setup never invokes feature-directory, preset, principle, or
  feature-lock children;
- the fixed engine-startup graph is runnable before any project graph exists,
  is absent from the selectable registry, and cannot be extended or replaced by
  a project definition;
- provider bootstrap:
  - derives its requirement only from the exactly selected compiled graph's
    registered effective capabilities;
  - cannot be activated by workflow/node names, parameters, configuration or
    policy allowance alone;
  - exposes only runner-owned child bindings on the fixed provider-bootstrap orchestrator;
  - makes every provider-file child unreachable for `not_required`;
  - captures a required document once and keeps the derived immutable registry/
    allowlist authoritative without active-run reread or refresh;
- invalid reference preflight prevents artifact creation;
- the generic engine executes the exactly selected compiled graph without
  workflow-name branches;
- the initial SDD workflows enforce `specify -> plan -> tasks -> implement`
  through predecessor validation under every accepted registry containing
  those definitions;
- predecessor revalidation occurs at every boundary;
- authority reconciliation:
  - runs before generation and commit;
  - routes every gap to the compiler-locked earliest owner;
  - makes all model/repair/write children unreachable on clarification,
    upstream-rework and administrative-block outcomes;
- open clarification prefix gates return nonzero `ERROR` before downstream model/write children (`S` blocks plan, `S/P` blocks tasks, and `S/P/T` blocks implement);
- clarification reruns:
  - reuse exact subject identities and reconsider current allowed authorities/controlled answers;
  - commit resolution before regeneration;
  - invoke every owning-stage generation child again, retaining no partial candidates;
- one invalid filename creates one repair request for one pointer;
- valid sibling units are retained across repairs;
- a repair outside scope is rejected;
- retry exhaustion returns blocked/failed, not success;
- stage commit occurs only after full validation;
- a failed task blocks dependents and cannot mark `[X]`;
- independent parallel failures aggregate correctly;
- task status persistence failure prevents completion;
- interruption abandons the whole execution; a new invocation starts at start with fresh run-local state;

Architecture tests also:

- reject action fields/constructors typed as any node, dispatcher, node runner,
  executor callback or service locator;
- reject node `execute` calls outside orchestrator modules;
- enforce the orchestrator import allowlist;
- require orchestrators to receive only child bindings and the capability-free `NodeRuntime`.

### 28.4 Model fault-injection tests

Stub model operations deliberately return:

- malformed JSON;
- a wrong request/diagnostic ID;
- extra schema fields;
- a foreign absolute path;
- wrong React casing/extension;
- a misplaced unit test;
- a Java public class/file mismatch;
- a .NET file under no project;
- a hallucinated command;
- an unknown requirement ID;
- a missing coverage item;
- unsupported content offered instead of `clarification_needed`;
- a plausible default for a zero-candidate requirement;
- a closest-match selection;
- a current-stage answer for an upstream-owned gap;
- a caller-specific exception for one fixture;
- a task dependency cycle;
- two parallel tasks writing one manifest;
- a patch touching two files;
- an unbound filename hidden in a task/plan prose field;
- a copy operation with an unknown/raw-path source;
- a code repair outside the authorized target;
- a claim with a fabricated source citation;
- repeated identical invalid repairs.

Each test asserts that only a genuinely malformed authorized candidate reaches atomic repair; missing/unreconciled authority reaches clarification/rework/block instead, and invalid output never reaches a write/command action.

For protocol correction, inspect the serialized provider request, not only retained
logs or diagnostics. Under [§22.6.2](22-repair.md#2262-explicit-error-guidance), cover:

- Explicit failure wording and accurate explanations for every schema reason,
  decoder failures and missing final answers. Preserve the latest typed diagnostic,
  original assignment, selected schema, applicable outline and latest rejected body.
  Include root/escaped pointers, parent-scoped union errors, optional objects,
  bounds, named schemas, configured parts and narrowed repair responses.
- First correction, confirmed repeated rejection, alternating errors and successful
  recovery. A changed payload with the same diagnostic must not be called identical.
  Attempt count, an unrelated assignment, stale/foreign evidence or another execution
  must not establish recurrence. The optional notice remains one sentence; previous
  bodies/prompts are not accumulated, and missing answers have no rejected body.
- Full schema/native validation, unaffected siblings and provenance, exact retry/token
  accounting and terminal no-publication behavior. Reuse existing conformance cases,
  including unrelated shapes; wording alone is not evidence of live effectiveness.

### 28.5 Preset conformance fixtures

Ship golden valid/invalid repositories for:

- React + TypeScript + Vite;
- Node JavaScript ESM;
- Node TypeScript;
- Java + Maven, including multi-module;
- Java + Gradle;
- .NET single project;
- .NET solution with application and test projects;
- monorepo containing more than one environment.

Tests verify schema validity, detection ambiguity, roots, extensions, naming, placement, generated exclusions, parser/query resources, command capability, and cross-platform argv.

### 28.6 Renderer and artifact tests

- golden `spec.md`, `reference-context.md`, plan artifacts, and `tasks.md`;
- Markdown escaping and code-fence safety;
- exact token/copy preservation;
- fixed heading order;
- exact compact `Given`/`When`/`Then` acceptance-criterion rendering and
  parser rejection of unlabeled, free-form, wrong-case, missing,
  duplicate, additional, and reordered criterion fields;
- correct engine-derived checklist/progress state;
- no `tasks.md` during plan;
- editable `spec.md` parse/render round trip and provenance rejoin/invalidation after edits;
- exact generated-view equality, tamper detection, and regeneration without importing edits.
- open clarification views permit only the two registered regions;
- closed views permit no edits;
- plan/task views reject every direct edit;
- editable `spec.md` retains its authenticated round-trip path.

### 28.7 End-to-end tests

- Live E2E runs execute the complete production path with the real LLM and external services
  selected by the test configuration, then evaluate the actual published output against the
  required rubric.
- Each run requires explicit user approval.
- Fakes, prewritten output and golden-document comparison cannot substitute for live execution
  or semantic evaluation.
- Report incomplete live acceptance separately from offline checks; see [the
  harness](../harness/e2e.md).

- Clarification regressions must retain and consume resolved answers across successful and
  failed reruns, reuse one ID after wording/authority/gap changes, keep different subjects
  distinct, and reject ambiguous continuity.
- Test each open `SNN`, `PNN` and `TNN` independently and together: `implement` must invoke zero
  task/model/command/overlay operations until every required answer is validated and closed; the
  normal approval gates must still pass afterward.

- Rerun tests MUST prove that all registered replaceable output files are completely overwritten
  at the same paths without append, merge, skipping, filename suffixes, or extra overwrite
  approval.
- Unresolved clarification forms MUST also be completely overwritten at the same subject
  IDs/paths, including unchanged questions and open forms containing unsubmitted draft answers.
- Assert that old file contents and trailing bytes do not survive a shorter replacement.
- Clarification-pause runs must replace their unresolved forms without publishing partial
  successful stage output.
- Cover Specify and an unrelated registered workflow to prove the shared rule.
- Assert byte-identical user-closed forms before and after response ingestion, authority
  refresh, output commit, failure, and cancellation; include a concurrent user close, a
  stale/invalid close, and a new unrelated clarification.
- A protected answer that cannot resolve a current required subject blocks without reopening or
  allocating a duplicate ID.

The following temporary-repository cases may use a fake `LLMProviderInterface`
for integration/fault-injection evidence. They are not E2E results:

1. run a feature with the mandatory smallest valid reference corpus through all four stages;
2. run mixed Markdown/CSS/image/PDF references and verify full accounting;
3. inject an authoritative conflict and verify specification blocks;
4. force an invalid planned filename and verify atomic repair;
5. generate missing task coverage and repair only one task;
6. fail compilation, repair one code unit, and verify revalidation;
7. interrupt execution before and after model/task work; prove abandonment without partial successful output and a new invocation beginning at start;
8. complete implementation and verify every `[X]` has evidence.
9. approve plan/tasks by plan/task-definition ID, reject stale approvals, and exercise upstream rework invalidation;
10. prove whole-workflow complete-output-or-abandonment behavior without transaction storage or checkpoint recovery.
11. Require explicit feature and reference directories:
    - Keep the supplied directory as the target across reruns and changed references.
    - Prove no slug generation, ownership lookup, unrelated writes or user-closed
      clarification overwrite.
12. Exercise new, duplicate, deferred, stale, user-resolved, authority-resolved,
    reopened and exhausted `SNN`/`PNN`/`TNN` forms:
    - Prove exact filenames and controlled edit regions.
    - Reject duplicate subjects.
    - Regenerate the full owning stage.
    - Check each downstream prefix gate's nonzero `ERROR`.
13. Run with mixed-case `FATAL`/`CRITICAL`/`ERROR`/`WARNING`/`WARN`/`INFO`/`DEBUG`/`TRACE`:
    - Verify canonical threshold behavior and exact per-feature paths.
    - Crash each event/prompt stream phase.
    - Prove tail recovery or fail-closed blocking without using logs as authority.
14. Relocate all seven configured directory roots and `paths.providers`, including
    nested `specsArchive`:
    - Definitions and published state use only `paths.workflows`.
    - Provider bytes use only the configured `.sddproviders.json` path.
    - Presets use only `paths.toolchainPreset`.
    - `toolchain.yaml` and semantic Markdown use only their distinct lanes beneath
      `paths.principles`.
    - Templates remain inert.
    - Ignore `design/examples/`, `design/toolchainPresets/` and `design/templates/`
      as runtime fallbacks.
15. Exercise artifact edits:
    - Tamper with `plan.md` and `tasks.md`; verify rejection/regeneration without import.
    - Edit `spec.md` through its authenticated path; prove ordinary downstream
      invalidation/review.
16. interrupt SDD and unrelated YAML workflows; prove fresh execution state, full reruns, preserved/deduplicated clarifications and no transaction/provider-recovery preflight.
17. Exercise required authority across unrelated requirement kinds:
    - Cover missing, ambiguous, conflicting, multiply matched, stale, unsupported,
      explicitly excepted and explicitly not-applicable authority.
    - Prove identical shared reconciliation semantics and earliest-owner `S/P/T` routing.
    - Prove complete downstream invalidation.
    - Allow no plausible/local substitute to reach plan, tasks, implementation or repair.
18. Verify native packaging:
    - Build the executable with the pinned Zig toolchain.
    - Copy only declared release artifacts into a clean temporary directory.
    - Run the CLI/config-discovery smoke suite without the source tree, Zig
      toolchain, build cache, Node.js or development-only assets.
19. Exercise registry variation:
    - Load different valid definition counts.
    - Execute an unrelated workflow composed only from registered operations.
    - Reject duplicate IDs/shortcodes, unknown operations, illegal transitions,
      unbounded cycles and capability escalation.
    - Prove that adding the workflow changes no initial SDD graph.

### 28.8 Model-conformance comparisons

Assess the [request-guidance proposals](../reference-notes/model-request-guidance.md#proposed-conformance-improvements--20-september-2026)
through existing request capture, provider binding, validators and the harness.
Scripted fault/recovery tests establish enforcement, sibling/provenance preservation,
dependency freshness and exact accounting; they do not establish live reliability.

- Declare retained failure cases, unrelated shapes, sufficient/insufficient source
  cases, settings and repetition counts before comparing. Include unchanged invalid
  corrections, structural recovery that drops content, and fully supported recovery.
- Change one factor at a time: hold model/settings fixed for guidance or composition
  comparisons, and hold schema/evidence/guidance fixed for model or response-mode
  comparisons. Retain actual serialized requests, responses and validation results.
- Report initial JSON/schema admission, correction recovery/exhaustion, unchanged
  responses, omitted requirements, unsupported evidence and false clarification gaps
  separately. A parseable response or a genuine clarification is not scored completion.
- Measure complete request bytes and prompt/schema/evidence contributions; label
  estimated tokens separately from actual provider usage. Record calls, total tokens,
  latency and final outcome. Larger inputs are acceptable when measured correctness
  improves; no local token ceiling or budget exemption is introduced.
- Live diagnostic comparisons require an explicit bounded approval and are not E2E
  evidence. They use existing request/replay owners, never import a replayed result as
  workflow authority and never change model/mode silently. Each whole-workflow E2E
  run retains §28.7's separate approval and actual-output grading requirements.

Use measured improvements to select a change; keep unrepaired JSON/schema rejection
terminal with no publication. A completed, published and scored run remains distinct from a
successful isolated request, valid incomplete specification or passing fake-provider suite.
