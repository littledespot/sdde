# 10. Development-environment presets

Part of the [proposed design](../design.md#10-development-environment-presets). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

- The runtime preset root is exactly `<projectRoot>/<paths.toolchainPreset>`, resolved directly
  from the root `.sddtoolkit.json`.
- It is the sole validated package registry from which the exact
  `<paths.principles>/toolchain.yaml` project layer may inherit.
- `design/toolchainPresets/` and `design/toolchainPresets/_structure.yaml` are design/source
  material only; runtime bootstrap never loads those source locations and has no
  packaged-example fallback.

[View the toolchain-preset bootstrap diagram](../diagrams/08-toolchain-preset-bootstrap.md).

**Current authoring boundary:** [F0003 §3](../features/F0003-ToolChainService.md#3-closed-loading-and-publication-contract)
and the [authoring guide](../toolchainPresets/README.md) document the implemented
closed package/project shapes and stable union of registered policy IDs. The richer
policy concepts below are proposed design, not additional currently accepted YAML
fields. The legacy examples remain useful source material; their format is not a
runtime contract.

- `design/toolchainPresets/_structure.yaml` inventories framework identity, package, build,
  test, path, quality, and AST concerns.
- It is a seed, not a v1 schema.
- Its “mandatory” rules exist only in comments, unresolved `<!-- IMPLEMENT -->` values are valid
  YAML strings, commands are raw strings, and AST resources are incompletely identified.
- A v1 preset and the project `toolchain.yaml` layer must instead pass their respective closed,
  versioned contracts; unresolved placeholders and missing mandatory values are rejected in both
  mechanical lanes.
- This placeholder rule does **not** apply to semantic Markdown principle bodies.

- None of the supplied `design/toolchainPresets/*.yaml` examples is directly executable engine
  policy.
- They lack the current `schema`, `package`, `layer`, `extends` and `policies`
  contract. The richer `apiVersion`/`metadata` illustration in sample 15 is also
  proposed policy notation, not an alternative accepted YAML shape.
- Several contain shell redirection, glob expansion, or nested quoting.
- Bootstrap therefore rejects these legacy shapes with `PRESET_LEGACY_SCHEMA_UNSUPPORTED`; it
  never silently upgrades them.
- Runtime packages must be authored and validated explicitly against F0003. Runtime
  bootstrap has no migration reader, automatic conversion or fallback. F0003 §5 retains
  the separate offline migration proposal; it is not an implemented runtime path.

The complete source-material treatment is:

| Legacy example | Useful seed layers | Mandatory migration findings |
| --- | --- | --- |
| `react-vite.yaml` | JavaScript/TypeScript language + Node runtime/package manager + React framework + Vite build + Vitest test | Split monolith; replace `npx`/raw commands and redirects; define package-manager ownership, exact parser/query packages, brace-glob semantics, effects, E2E command availability, and role-specific filenames. |
| `vue-vite.yaml` | Vue framework + JavaScript/TypeScript language + Node/npm + Vite build + Vitest test | Split monolith; replace `npx`/raw commands and redirects; fully identify the Vue SFC parser and import-query coverage; define effects, package-manager ownership, E2E command availability, and role-specific filenames. |
| `node-jest.yaml` | JavaScript/TypeScript + Node + npm + Jest | Split package manager/test layers; replace raw `npx`, placeholders, redirects, and detached `flags`; type lockfile ownership, scripts, command effects, parser/query versions, and content-reference coverage. |
| `node-pnpm-jest.yaml` | JavaScript/TypeScript + Node + pnpm + Jest | Same as Node/Jest; retain exclusive pnpm command/lockfile ownership and validate every command capability explicitly. |
| `node-vitest.yaml` | JavaScript/TypeScript + Node + npm + Vitest | Same as Node/Jest; bind build/lint/test IDs to proven project scripts or exact executables. |
| `node-express.yaml` | Express framework identity overlay | Migrate the legacy `framework` marker to an exact v1 framework identity and dependency detector; declare language/runtime/build/test dependencies separately without selecting a test runner. |
| `java-maven.yaml` | Java/JVM + Maven | Keep dependency addition explicitly unsupported until a manifest mutation adapter is selected; replace redirects/raw Maven text, fully identify the Java parser, and validate integration-goal semantics and module roots. |
| `java-gradle.yaml` | Java/JVM + Gradle | Keep dependency addition explicitly unsupported until a manifest mutation adapter is selected; type wrapper execution/tasks/effects and fully identify Java parser/source-root coverage. |
| `dotnet.yaml` | C# + .NET + MSBuild/dotnet test | Resolve each `*.csproj` to a project adapter rather than a raw manifest glob; type project-scoped package addition and dependency scope; replace redirects; declare missing E2E command as disabled; fully identify the C# parser. |
| `python-poetry.yaml` | Python + Poetry + pytest | Replace shell glob compilation and redirects; type Poetry-environment commands, manifest/lock mutation, scopes, executable capabilities, parser identity, and generated/cache roots. |
| `python-pytest.yaml` | Python + pip/requirements + pytest | `pip install` does not by itself update `requirements.txt`; migration must select a manifest mutation adapter or disable add/addDev. Replace shell glob/redirection and type every command/effect. |
| `php.yaml` | PHP + Composer + PHPUnit | Replace redirects/raw commands; type Composer plugin/script/network policy, manifest/lock effects, installed tool capabilities, and PHP parser identity. |
| `wordpress.yaml` | PHP/Composer base + WordPress framework + CSS | Split framework from PHP/Composer/CSS; replace the example `wp-content/` source root with discovered roots/file kinds; account separately for PHP/CSS parsers and vendor outputs; type lint arguments. |

- `.DS_Store` and any other non-preset file in the source example are not policy.
- Runtime bootstrap performs a bounded, completely accounted inventory of the derived root, but
  resolves environments only by exact configured preset ID/version after each candidate has been
  classified and validated.
- A YAML/JSON candidate that is not a closed v1 preset produces a stable inventory diagnostic;
  platform metadata is ignored only through a locked engine rule.
- No filename alone creates preset identity.

React, Node, Java, and .NET should not be four flat, monolithic alternatives. React is a framework, Node is a runtime, Java is a language/ecosystem, and .NET is a runtime/toolchain. Presets must therefore be composable.

### 10.1 Preset identity and composition

[View the Preset identity and composition sample](../code.md#preset-identity-and-composition).

- Every preset package is validated with a JSON Schema (YAML 1.2 parsing for YAML form), closed
  objects, explicit required fields, enums, anchored patterns, and semantic-version validation.
- The project `toolchain.yaml` layer uses its own closed schema and pins exact preset package
  identities/versions; ranges and implicit `latest` are invalid.
- Preset `metadata.layer` is one of `language`, `runtime`, `framework`, `build`, `test`, or
  `environment`; project-specific inheritance and overrides belong only to the separately typed
  project toolchain layer and are not a package kind.
- The inherited composition graph must be acyclic; a preset identity may occur only once in its
  transitive closure, and conflicting versions of one ID are an error.
- Layer-order constraints and every field's merge operator are schema-defined, so list position
  cannot silently change policy meaning.

- Preset-registry validation is independent of project selection: it proves the installed
  package/asset registry and every package-declared reference are internally closed without
  consulting environments or `toolchain.yaml`.
- Project-layer schema, inheritance, and operand validation then prove only exact direct
  bindings and typed override declarations.
- The engine must first compile those declarations with the ordered preset closure into a merged
  candidate and only then validate the effective merged result against compiler-locked safety
  policy.
- No environment policy, path pattern, command, capability, or effect consumer may receive the
  candidate before that post-composition safety gate succeeds.

- Complete-registry validation is deliberate in v1.
- The configured preset root is one installed authority registry, so a malformed or unresolved
  unselected package blocks bootstrap instead of being silently quarantined.
- Partial registries and package-quarantine semantics are outside v1 and require a separate
  versioned design; selection never changes whether the installed registry itself is valid.

### 10.2 Project discovery

A preset must support multiple manifests and project roots rather than the sample's single `package.configFiles.manifest` field. Manifest semantics vary too much for generic keys such as `sourceDirectoriesKey`, `structureType`, and `directoryTransformer` (`design/toolchainPresets/_structure.yaml:6-14`). Use registered, non-executable adapters:

- `npm-package-json`
- `npm-workspaces`
- `maven-pom`
- `gradle-project`
- `msbuild-project`
- `dotnet-solution`

[View the Project discovery policy sample](../code.md#project-discovery-policy).

- Each discovered project receives a `projectId`, canonical root, manifest adapter, language
  set, and compiled file-kind policies.
- Every v1 `ProjectPathCandidate` must name one engine-supplied `projectId`; omission is a
  schema error.
- The engine then proves that the path is contained by that project's environment/root and is
  not claimed by an equal-specificity conflicting owner.
- Equal ownership matches are a blocking `PRESET_SELECTION_AMBIGUOUS` diagnostic, not an LLM
  choice.

For a monorepo, environment resolution uses the longest matching configured root. An equal-length match is invalid configuration. A cross-environment task declares separate paths/operations for each environment.

### 10.3 File-kind policies

The sample has general source patterns and physical policies only for config and style (`design/toolchainPresets/_structure.yaml:26-38,81-91`). Filename validation needs an extensible role-aware map:

[View the File-kind policies sample](../code.md#file-kind-policies).

At minimum, the schema must support these kinds where relevant:

- source module;
- component/view/screen;
- hook/helper;
- state/schema/type;
- unit, integration, and end-to-end test;
- style;
- asset/resource;
- config;
- project/solution manifest;
- contract/interface artifact;
- migration;
- documentation;
- generated output.

Every policy-bearing path expression uses the closed `PathPattern` type; bare strings are invalid. Every pattern declares:

- a base domain: workspace, environment, project, source root, or command working directory;
- `patternType`: `glob`, `regex`, or exact;
- `target`: basename or path relative to the declared base;
- case sensitivity.

Every pattern matches its complete declared target; partial matching is not configurable. Planning-intent and runtime-capability applicability belongs to the containing file-kind, discovery, command-effect, generated, or forbidden rule and cannot be overridden by an individual pattern.

- The versioned `path-pattern/v1` glob grammar defines `*` as zero or more non-separator
  characters, `**` as zero or more complete path segments, and a terminal `/**` as the named
  directory itself plus every descendant.
- Thus `dist/**`, `coverage/**`, and `.cache/**` explicitly match their root directory as well
  as their contents; adapters may not substitute host-library glob semantics.
- Regex uses the pinned RE2 dialect and exact patterns are scalar-equal after the declared
  normalization/case policy.

- `base: source_root` is a post-discovery compiled form and requires an exact `sourceRootId`
  from the discovered project registry; it forbids an implicit nearest root.
- A reusable raw preset instead declares `SourceRootPathPatternTemplate {templateRuleId,
  sourceRootSelectorId, ...}` where the selector is a closed semantic role, not a path.
- Preset merge retains these templates.
- After manifests/projects identify roots, dedicated actions resolve every selector, materialize
  one bound pattern per matched root, and build/validate the final environment policy; a
  missing, ambiguous-for-singleton, extra, or unresolved binding blocks bootstrap.
- The bound instance rule identity is the tuple `(templateRuleId, sourceRootId)`, rendered
  unambiguously for diagnostics, so generic Java/Maven/Gradle/.NET presets never predict
  repository-specific IDs.

- All non-source-root bases forbid `sourceRootId`.
- `base: command_cwd` is valid only while compiling a particular command descriptor and resolves
  from that descriptor's separately validated owning-project `cwd` evidence; it is never
  ambient.
- Workspace/environment/project bases likewise resolve from explicit compiled identities.
- Before matching, the base-binding validator resolves exactly one contained root; a
  missing/stale/ambiguous module root or absent command binding is an environment diagnostic.
- Java package-directory, Maven/Gradle resource/test placement, and MSBuild project-relative
  rules consume that resolved root ID, and `PathGuidance` preserves it inside each applicable
  pattern.

- After project discovery and source-root binding, the engine compiles a finite
  `PathIntentOptionRegistry`.
- Each preset-declared option rule has a stable `optionRuleId`; its compiled model-visible
  `pathIntentOptionId` is the typed tuple of that rule ID, exact project ID, and any bound
  source-root IDs, never an array ordinal, display label, or content hash.
- Each option binds that ID to an exact environment, file kind, semantic role, applicable
  template IDs, and capability ceiling.
- A planning model selects the option ID; it cannot independently combine a permissive file kind
  with an unrelated semantic role or template.
- The validator also proves that every requested capability is a subset of the selected option's
  ceiling.

- Every path template names a compiler-owned, versioned `nameTransformId`.
- The transform consumes one engine-registered semantic name source and normatively defines its
  tokenization, normalization, case conversion, prefix/suffix handling, extension handling,
  invalid/empty result behavior, and fixed test vectors.
- It may not delegate those choices to a host-library default.
- Unknown transforms reject preset compilation.
- Exact fixed basenames such as `Dockerfile` are template literals and do not pass through a
  semantic transform.

- Candidate enumeration is complete and deterministic for one validated intent: templates are
  ordered by stable template ID, candidate paths are normalized and ordered by Unicode-scalar
  repository-relative path, duplicates are removed by canonical path equality, and only fully
  path-valid absent targets receive `pathCandidateId`s.
- The compiler-owned candidate-count ceiling is applied before any candidate registry is
  exposed.
- A missing/invalid template or unresolved root is an environment diagnostic; zero valid
  candidates for an otherwise valid semantic intent produces `PATH_CANDIDATE_UNAVAILABLE` owned
  by planning; exceeding the ceiling produces `PATH_CANDIDATE_LIMIT_EXCEEDED` and blocks the
  unit.
- Neither outcome enables raw fallback or invents a collision suffix.

- Every `PathPattern` carries an explicit stable `ruleId`, unique across the compiled
  environment policy.
- Each nonempty file-kind extension set likewise declares its own globally unique
  `extensionRuleId`; it is not synthesized from the kind name.
- IDs are versioned preset data, not derived from array position, display text, or a content
  hash; diagnostics, initial guidance, and repair authorization all cite the same ID and typed
  value.
- For a containing `{includes[], excludes[]}` set, empty `includes` means include by default,
  otherwise any include match is sufficient; any exclude match rejects and always wins.
- The final result is `(includes.empty || anyIncludeMatch) && !anyExcludeMatch`.
- Individual match actions emit rule evidence, and a set-level action alone emits the
  authorization result—an orchestrator never computes these booleans.

- The containing file-kind rule declares `namingEnforcement` for supported `create` and `update`
  intents.
- `strict` applies all basename and compound-extension rules.
- `existing_compatible`, normally used for legacy `update`, requires containment, existence,
  compatible kind, allowed extension, and unchanged canonical path but does not reapply
  create-only basename conventions.
- `read` and `delete` never consult this map: they always require an already registered,
  unchanged canonical path with compatible kind/extension; delete additionally requires its
  independent capability and global gate.
- The project `toolchain.yaml` layer may set update to `strict` for an explicit migration
  policy.
- There is no validator guess based on whether a filename looks old.

### 10.4 Structured commands

Raw command strings in `_structure.yaml` are shell-dependent and unsafe to template (`design/toolchainPresets/_structure.yaml:15-25,40-77,93-95`). Commands must be structured, capability-based values:

[View the Structured commands sample](../code.md#structured-commands).

Rules:

- commands execute without a shell;
- every placeholder is declared, typed, and provided by the engine;
- values are individual argv elements and are never string-interpolated into a shell command;
- working directory must be within the owning project;
- executable resolution follows an engine allowlist;
- time, output, environment, filesystem, and network limits are explicit;
- mutability is declared as `readOnly`, `workspaceWrite`, or `dependencyMutation`;
- every mutating command declares `effects.authorizedWrites` and disposable `effects.ephemeralWrites`; both are compiled path policies, not free-form model values;
- command write policies are ceilings: the persistent promotable set is exactly the task-approved write-file IDs whose resolved paths also match the command's authorized-write policy, never the union of those sets; each entry also carries engine-derived allowed delta kinds (`create`, `modify`, `delete`) from file capabilities and global policy, with delete separately gated;
- persistent and ephemeral effect languages must be disjoint. Preset compilation proves their intersection empty after compiling exact/glob/RE2 rules; an unprovable or nonempty intersection rejects the command. Runtime also rejects any delta that matches both classes—there is no precedence rule;
- ephemeral effect rules may target only preset-declared generated/cache/private-temp roots and may never overlap source, manifest/lockfile, VCS, engine, workflow, principles, toolchain-preset, or reference roots;
- a command delta has only three valid variants: persistent regular-file, ephemeral regular-file, or ephemeral structural-directory. A structural-directory create/delete must match an ephemeral rule (including its explicitly matched root), be contained below a validated ephemeral root, and is always disposable. It can never carry a `fileId`, satisfy a planned file operation, or enter promotion. Symlinks, hard-link aliases, devices, sockets, FIFOs, directory changes in the persistent class, and all other node types are rejected;
- the entire command process tree runs inside a required OS/container sandbox whose filesystem and network boundaries are enforceable by the adapter; child scripts cannot escape by spawning a shell or another executable;
- package-add commands distinguish package name, version, project, and dependency scope;
- validation commands cannot alias an install/add operation;
- the engine verifies that an npm script, Maven goal, Gradle task, or .NET target is available before exposing the command ID to the LLM;
- an unsupported capability is disabled with a reason rather than populated with a fake command.

The LLM may select from allowed command IDs supplied in context. It never returns executable text.

Bootstrap wires each descriptor through `ValidateCommandWorkingDirectoryAction`, `ResolveCommandExecutableAction`, `ValidateCommandPlaceholderContractAction`, `ValidateCommandMutabilityAliasAction`, persistent/ephemeral pattern compilation, effect-disjointness and ephemeral-root validation, sandbox and in-flight quota-capability validation, and only then `ProbeCommandCapabilityAction`. `AssembleCommandRegistryAction` requires every one of those evidence keys for a descriptor; a capability probe alone cannot expose a command.

### 10.5 AST and parser policy

The sample's extension-to-string AST maps do not identify parser versions, query captures, resolution rules, or missing-resource behavior (`design/toolchainPresets/_structure.yaml:97-101`). Use explicit parser descriptors:

[View the AST and parser policy sample](../code.md#ast-and-parser-policy).

- Preset loading verifies parser availability, grammar compatibility, query-resource
  containment, query compilation, and required captures.
- Every file kind that permits model `create`, `patch`, or `replace` also declares
  `contentReferencePolicy`: registered import/resource/link/path-literal extractors, a resolver,
  and a conservative fallback scanner for every body range the structured extractors do not
  claim.
- Bootstrap disables those write capabilities unless coverage is complete.
- After each proposed operation is applied in its savepoint, the engine extracts and resolves
  typed references, scans all remaining text ranges, and rejects unresolved path-like tokens.
- This includes Markdown, documentation, templates, stylesheets, configuration, and other
  non-AST formats; copy operations remain governed by their immutable-source policy.
- If a parser, query, resolver, or fallback scanner is unavailable, the preset fails at
  bootstrap; the LLM is not asked to compensate.

### 10.6 Generated and forbidden paths

Every compiled preset includes immutable deny rules for dependency caches, build output, source-control internals, engine internals, and any declared generated source:

[View the Generated and forbidden paths sample](../code.md#generated-and-forbidden-paths).

- A generated path can be a read-only input only when repository discovery and the preset
  produce an engine-issued `generated_existing` file ID.
- It is never accepted from a model path string.
- Regeneration requires a specific task, registered generator command adapter, and declared
  ephemeral/generated effect policy; those command bytes are diff-gated and are not hand-edited
  or promoted as arbitrary model source.
- Hand-editing compiled output is rejected.

### 10.7 Environment-specific expectations

#### React

- Compose JavaScript or TypeScript, Node, React, and the actual build/test overlay.
- Represent components, hooks, state, styles, assets, and tests as distinct file kinds.
- Typical PascalCase `.tsx`, `useXxx.ts[x]`, and colocated `*.test.tsx` conventions are defaults only when the selected project preset declares them; React itself does not mandate them.
- Validate JSX/TSX syntax, aliases, import resolution, package declarations, and configured test placement.
- Exclude build/cache paths such as `dist`, `.next`, and coverage output according to the selected tool overlay.

#### Node

- Compose JavaScript or TypeScript with ESM or CommonJS and the selected package manager/test runner.
- Detect `package.json`, its `type`, TypeScript configuration, scripts, and lockfiles.
- Do not require compilation for runtime JavaScript.
- Permit `.js`, `.mjs`, `.cjs`, or `.ts` only when the resolved variant allows them.
- Multiple unresolved lockfiles are a configuration ambiguity, not a model decision.

#### Java

- Compose Java/JVM with Maven or Gradle.
- Discover modules from `pom.xml`, `settings.gradle*`, and `build.gradle*`.
- Model `src/main/java`, `src/test/java`, and resource roots per module.
- Deterministically require a public top-level type to match its `.java` basename and its package declaration to match the source-root-relative directory when the preset enables those rules.
- Provide project-configurable `*Test.java`/`*Tests.java` policies.
- Treat `target/`, `build/`, and generated sources as non-writable by default.

#### .NET

- Compose C#/.NET with MSBuild/dotnet.
- Discover `.sln`, `.slnx`, `.csproj`, central package files, and project references.
- Associate every proposed source or test file with exactly one project.
- Provide typed `dotnet build`, `dotnet test`, and `dotnet add <project> package <package>` command definitions.
- Treat PascalCase and `*Tests.cs` as project policies, not universal language laws.
- Exclude `bin/` and `obj/`.
- Validate project ownership, references, and namespace/folder conventions when configured.

### 10.8 Normative matching and platform semantics

Preset compilation uses one portable matching contract:

- Persistent and policy paths are NFC-normalized, repository-relative POSIX paths with `/` separators. Matching is performed on Unicode scalar values after normalization.
- `exact` means full target equality. `regex` uses the RE2-compatible grammar, is implicitly anchored to the entire declared target, and must declare case sensitivity. Unsupported constructs fail preset compilation.
- `glob` uses `/` as the only separator: `*` matches zero or more non-`/` characters, `?` one non-`/` character, `[...]` one class character, and a complete segment `**` zero or more path segments. Brace expansion, extglobs, escaping by platform shell, and partial substring matching are not supported.
- Each path proposal explicitly declares a kind, and validators apply that kind's rules. Overlap with another kind is therefore not ambiguity. When the engine must infer a kind for an existing repository file, the highest unique `inferencePriority` wins; equal-priority matching kinds fail preset compilation for the relevant root/operation domain.
- File-kind policies explicitly declare planning intents (`read`, `create`, `update`, `delete`) and the narrower runtime capabilities (`read`, `create`, `patch`, `replace`, `copy_destination`, `delete`). Read-only repository context uses `read`; a write capability is never inferred from read permission. `update` does not imply whole-file `replace`, and `create`/`update` do not imply copy-destination permission.
- The environment declares target filesystems. The compiled cross-platform policy rejects Windows reserved device basenames, disallowed characters, trailing dots/spaces, and target-specific segment/path length violations when Windows is a target. It also checks normalization and case-fold collisions for every configured target, even when the engine host is more permissive.
- Maven and Gradle adapters evaluate effective module source/resource/test/generated-source sets through registered build-model adapters; directory-name heuristics alone are insufficient. MSBuild adapters evaluate SDK defaults plus explicit `Compile`, `Content`, `None`, `EmbeddedResource`, `Remove`, `Include`, and project-reference ownership rules. An unevaluable dynamic build model blocks path authorization or requires an explicit project `toolchain.yaml` rule.

- Plan-time validation is lexical and repository-structural.
- Content-dependent rules such as Java public-type/basename, Java package/directory, or
  configured namespace/declaration checks run only when source bytes or an explicit typed
  declaration proposal is available, and are mandatory again against the parsed generated source
  during implementation.
- The engine never claims to prove a content-dependent rule from a filename alone.

### 10.9 Legacy preset source material

- The files in `design/toolchainPresets/` are historical source examples reviewed by F0003.
- The [authoring guide](../toolchainPresets/README.md) distinguishes those inputs from
  the current closed runtime package contract.
- They do not satisfy the current package contract merely by being present.
- Runtime bootstrap accepts only the closed current project/preset schemas and performs no
  conversion, aliasing, migration or fallback.
- Author and validate complete current-format packages explicitly before installing them; source
  examples are not automatic runtime policy.
