# 11. Filename and path validation algorithm

Part of the [proposed design](../design.md#11-filename-and-path-validation-algorithm). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

Workflow artifacts and project files use two separate policy domains:

- **Workflow artifact policy** owns canonical files beneath `paths.specs`: `spec.md`, the `clarify/` collection and its engine-numbered controlled forms, `reference-context.md`, `plan.md`, `research.md`, `data-model.md`, `quickstart.md`, optional feature-local contracts, and `tasks.md`.
- **Environment preset policy** owns proposed repository implementation files: source, tests, configuration, styles, assets, project manifests, migrations, documentation, and related files.

This distinction prevents a language preset from incorrectly rejecting `spec.md` because Markdown is not a source extension.

For every model-returned path-like field, the engine executes these checks in order:

1. Validate response field type and UTF-8; reject NUL/control characters.
2. Decode only the response's required UTF-8 layer, normalize the Unicode path to NFC, normalize literal separators to `/`, and remove literal `.` segments. This is canonicalization, not repair.
3. Never URL/percent-decode a path. Reject empty paths, absolute paths, drive prefixes, UNC paths, URI schemes, literal `..` segments, and any ASCII-case-insensitive encoded dot/separator token matching `%(?:25)*(?:2e|2f|5c)` (including repeatedly encoded forms such as `%252F`).
4. Join to the canonical workspace root without following model-controlled indirection.
5. Resolve existing ancestors and symlinks; reject any real path that escapes the workspace or owning environment.
6. Apply the compiled root access class. Reject every project operation against engine config, workflow definitions/spec/reference, canonical-state, semantic principles, project-toolchain/preset/template roots, VCS, and dependency-cache roots. Reject every generated/build write. An existing generated/build file may enter context only through an engine-issued `generated_existing` read-only ID allowed by the preset; a model-returned raw path never obtains that exception.
7. Resolve `projectId` and environment. Reject no match or multiple matches.
8. Validate the explicitly declared `kind`; do not infer a different kind to make a proposal pass.
9. Check whether the planning intent is allowed for that kind and stage, then compile its preset/task-authorized runtime capability subset; never infer `replace` or `copy_destination` from a generic update intent.
10. Check allowed roots using segment-aware matching, never string-prefix containment.
11. Apply exact/regex/glob basename rules using declared case sensitivity when the containing file-kind's create/update `namingEnforcement` is `strict`; under `existing_compatible`, or for read/delete, prove the operation keeps the already registered canonical basename unchanged.
12. When a file kind declares a nonempty extension set, require its explicit `extensionCaseSensitive` boolean and match with that rule using longest-suffix semantics for every intent, so `.test.tsx` is not reduced to `.tsx`. The active-host-plus-target portability collision pass remains independently stricter where required. When `extensions` is omitted, `extensionCaseSensitive` is forbidden and the kind must have at least one full basename exact/glob/regex rule; that rule is authoritative, and omission never means “any extension.” This supports deliberate extensionless names such as `Dockerfile`.
13. Apply include and exclude rules to the declared target domain.
14. Apply placement/mapping rules, such as colocated tests or mirrored `src` to `test` structure.
15. Apply environment-specific content rules only when typed declaration facts or source bytes are present; otherwise record them as mandatory implementation-time validators.
16. Detect case-fold collisions on case-insensitive filesystems.
17. For `update`, require an existing regular file. For `create`, require an absent target. Upsert is not a v1 intent or capability.
18. Apply the stage-specific authorization gate: planning validates the current plan-unit proposal scope before minting a `FileRecord`; tasks may select only plan-authorized file IDs; implementation requires both the plan capability and the approved task read/write set.
19. Immediately before any commit, re-resolve every existing ancestor with descriptor-relative/no-follow operations or the platform-equivalent safe primitive, compare parent identities captured during preparation, and fail if an ancestor or target was swapped. Lexical validation performed earlier never authorizes a race-prone write.

- An accepted planning `ProjectPathCandidate` is create-only and must name an absent target; it
  becomes an engine-assigned `plan_declared` `FileRecord`.
- Existing files are selected only by discovered `fileId`, so an update/delete proposal cannot
  collide with the registry while trying to mint a second identity.
- `FileRegistryState` stores identity, path, kind, existence, provenance, and the deterministic
  policy-capability ceiling—but no plan intent or authorization.
- `PlanState.fileGrants` separately binds each approved file ID to one planned intent and exact
  capability subset.
- Tasks and implementation intersect that grant with task scope and current policy.
- The `fileId` remains the only project-file identity downstream workflow model operations may
  use.

- Raw model path strings are discarded after normalization and diagnostic reporting.
- Every `FileReference` is checked against the current workflow operation/unit's allowed file-ID
  set as well as the global registry; every `SourceReference` is checked against the current
  reference state and workflow operation/unit source allowlist.
- A known but unauthorized file/source therefore cannot enter later context.
- `PassiveLiteralReference` is checked against the exact registry state and unit allowlist and
  is valid only in a display-capable prose field.
- It is forbidden from `ProjectPathCandidate`, `FileRecord`, file-operation/command/copy
  payloads, import/resource resolution, context selectors, URI fetching, and every
  filesystem/network adapter.
- Business specification fields cannot carry operational file/source nodes.
- An exact-copy value resolves only through the current snapshot's token/citation registry; the
  model cannot inline arbitrary bytes or emit a textual marker and claim that it was
  engine-rendered.
- Renderers resolve valid nodes and tokens to engine-controlled display labels/bytes.

- As defense in depth, every model-authored `LiteralText.value` and `BusinessLiteralText.value`
  is rejected when a token bounded by whitespace/punctuation matches `(segment/)+basename`,
  `(segment\\)+basename`, a drive/UNC/URI form, a basename ending in any compiled compound
  extension, or any root-level basename accepted by a compiled exact/name rule or known-manifest
  rule.
- The last set includes extensionless or dotfile names such as `Dockerfile`, `Makefile`, and
  `.env` when a selected preset admits them.
- Segments use the same NFC and allowed-character policy as path normalization.
- `BuildSupersetPathTokenGrammarAction` compiles this detector from every resolved environment
  extension/exact/name rule, manifest/reserved name, path/URI grammar, and current identified
  reference-manifest basename—not merely the current unit's allowed kinds—and binds the exact
  policy/repository/reference identities and scanner version.
- Workflow-operation/unit allowlists are applied only after detection and can never shrink the
  lexeme detector.

- The lexer never turns a token into a path.
- An inline match produces `UNBOUND_PATH_REFERENCE`; an atomic repair may choose only an exact
  unit-allowlisted passive literal ID, locally allowed file/source ID, or non-path replacement
  text.
- Unknown/stale/cross-unit passive IDs produce closed diagnostics and the model cannot register
  one.
- A valid passive reference or `ExactBusinessCopy` bypasses inline-literal rejection only as
  inert display content.
- In technical prose, a passive literal whose exact bytes resolve to a locally allowed project
  file produces `FILE_REFERENCE_REQUIRED`; business prose may retain the display literal because
  lexical shape cannot decide business relevance.
- Operational use of the same bytes must independently pass normal path/file-ID authorization.

- Plans and tasks refer to stable `fileId` values once a path is accepted.
- Filename repair occurs in planning, before the file record is approved.
- One canonical path record changes and renderers update all human-facing references; the model
  is not asked to repair repeated prose occurrences.

- Generated source is a separate structured path surface.
- Registered AST queries extract import/export specifiers, resource references, project-file
  includes, and statically decidable filesystem literals.
- Relative/module references are resolved against the validated file registry, manifest aliases,
  and preset rules; a new project target must already have a plan-approved `fileId`.
- Dynamic path construction that cannot be resolved mechanically is reported under the preset's
  semantic/security policy rather than declared valid.
- Thus a filename embedded in code cannot bypass validation merely because it was not a
  top-level response field.

### 11.1 Cross-stage filename write gate

No model-authored filename or path is written to `spec.md`, `plan.md`, `tasks.md`, canonical state, or a source overlay merely because its response passed JSON schema. The stage-specific representation is deliberately narrower:

| Stage | Model representation | Deterministic authority before rendering/writing |
| --- | --- | --- |
| Specify | Ordinary prose plus unit-allowlisted `PassiveLiteralReference` IDs; no inline filename/path/URI and no operational project path | Passive registry scalar/origin validation, unbound-path lexer, business-boundary rules, and optional exact existing source IDs |
| Plan | Existing `fileId`; an allowed `pathIntentOptionId` plus semantic `nameSourceId`, followed by an engine-generated `pathCandidateId` for a new file; raw create-path only under explicit disabled-by-default fallback | Exact option membership/capability subset, versioned name transform, full preset kind/root/name/extension/placement rules, active-host-plus-target portability, collision/containment, path-candidate registry, and plan-file grant |
| Tasks | Approved read/write `fileId`s and capabilities only | Exact `PlanState.fileGrants`, sole file registry, task-unit scope, and graph/coverage validation |
| Implement | Approved `fileId`/copy `sourceId`/operation-intent ID only | Plan grant ∩ task scope ∩ current preset/global capability, descriptor/no-follow target state, and content reference validation |

- The visible filename in every artifact is renderer-owned.
- It is resolved from the exact `FileRegistryState` or inert passive registry bound by the
  canonical state; the model never repeats it in task prose.
- Therefore a nano-model spelling, separator, case, extension, or directory variation cannot
  propagate from plan into tasks or implementation.

Every generation unit follows the same pre-write loop:

1. Build initial guidance from the exact compiled preset/policy. Normal path-intent and candidate-selection operations receive only complete bounded option/candidate ID choices plus engine-rendered labels and minimal valid examples; full mechanical path rules are included only for an explicitly authorized raw-path fallback field.
2. Decode the response into a candidate held only in memory; no artifact or workspace write is authorized.
3. Run schema, typed-reference, unbound-path-token, preset path, portability, authorization, and stage-specific validators.
4. If a path-related rule fails, order diagnostics and select one; build a single-pointer repair authorization containing the exact rejected value, compiled policy state, stable rule ID and typed rule value, permitted candidate IDs/format, and immutable siblings.
5. Invoke the bounded repair operation selected explicitly by the workflow, validate authorization/revision/scope, merge only that atomic replacement, and rerun the impacted validators followed by the complete unit validator set.
6. Repeat only through the workflow-selected repair operation and within that
   exact operation instance's explicit compiler-validated `retry-limit`.
   Exhaustion blocks with the last exact diagnostics; it never writes a
   best-effort value or broadens scope.
7. Only a fully valid canonical unit may be merged. Only a fully valid canonical stage may be rendered, fully validated, and published.

- A repair in specify cannot introduce a plan path; a task repair cannot rename a file; and an
  implementation repair cannot change its target ID.
- A real rename or relocation returns to planning, creates a new candidate/file/grant state,
  clears descendant approvals, and regenerates task views.
