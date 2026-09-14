# SDDE

SDDE is a native Zig workflow engine under development. It loads validated
`*.workflow.yaml` definitions from the configured `paths.workflows` root and
executes a selected graph of registered operations. Workflow definitions supply
data and transitions, never executable code or capabilities.

The initial SDD suite is `specify -> plan -> tasks -> implement`. Those are
workflow definitions with predecessor gates, not a fixed engine registry.
Models propose candidate data; deterministic validators, explicit approvals
and publication evidence control workflow authority.

## Current implementation

- Configuration and root validation, workflow discovery/compilation, generic
  execution, toolchain composition and conditional provider bootstrap are implemented.
- Workflow-owned model requests retain their identity, binding, resources and
  schema across explicit YAML operations. Production Bedrock inference and
  optional token counting use the same provider boundary. Calls account actual
  API token usage against the execution budget; providers own per-call limits.
- Specify connects Markdown ingestion, source-backed extraction, reconciliation,
  specification generation, validation, authorized atomic repair and registered
  output publication. Evidence selections resolve to engine-owned citations;
  repair retains exact old values, revisions, dependencies and producing-call evidence.
- Phase 3 still has known selection-feasibility, disposition-equivalence and
  shared-eligibility gaps recorded in the [15 September review](fixes/REVIEW_FIX_001_ARCHITECTURE.md#15-september-2026-critical-review).
  Authenticated clarification-answer application, feature-log integration and
  remaining support-review/publication assurance work are also open. Connected
  generation does not establish complete Specify acceptance. See
  [F0100](design/features/F0100-SpecWorkflow.md) and the
  [active FIX_001 rollout](fixes/TODO_FIX_001.md).
- The development harness runs real generation and grades the actual published
  specification through the selected OpenAI or Bedrock evaluator. A successful
  scored live baseline, human rubric calibration and broader acceptance remain
  outstanding. Offline tests are not E2E evidence.
- Plan, Tasks and Implement remain proposed workflow work.

Each invocation starts its selected workflow at `start`. Candidate output stays
private until complete validation permits publication. Publication failure may
leave replaced files, but cannot report success or record new successful
completion. There is no transaction/recovery store or saved continuation.
Reruns overwrite registered replaceable outputs and unresolved clarification
forms at the same paths, retain clarification identities and applicable answers,
and preserve user-closed forms byte-for-byte. See
[ADR 0009](design/decisions/0009-atomic-workflow-execution.md).

## Build and verify

Use **Zig 0.16.0 exactly**, as pinned in [.zigversion](.zigversion),
[build.zig.zon](build.zig.zon) and [build.zig](build.zig).

```sh
zig build
zig build lint
zig build test
zig build smoke
zig build verify
```

`verify` runs formatting/AST checks, all unit and integration tests, architecture
checks and clean native packaging smoke tests. It makes no live API calls and
needs no credentials. Packaging smoke runs the executable in isolated temporary
projects with a cleared environment and no source-tree fallback.

Use `zig build --help` for the repository's individual test steps. There is no
separate changed-scope aggregate; run the relevant owning-boundary steps during
iteration and `zig build verify` before completing cross-cutting work.

## Configure and run a workflow

Run the executable from the target project's root. Bootstrap reads only that
working directory's exact `.sddtoolkit.json`, validates its configured locations,
and compiles every discovered workflow before selecting the requested ID.
It does not search parent directories or use repository examples as defaults.

Specify's registered invocation takes independent target and reference selectors:

```text
sdde <workflow-id> --feature <feature-directory> --reference <reference-selector>
```

The workflow ID comes from the definition's `id`, not its filename. The supplied
[Spec definition](design/workflows/spec.workflow.yaml) declares `spec-generation`.
`--feature hello-world` selects `<paths.specs>/hello-world/`; `--reference`
selects beneath `paths.references`. Other workflows use their own registered
invocation contracts. See the [path contract](design/paths.md) and
[workflow configuration](design/features/F0100-SpecWorkflow.md#2-closed-yaml-shape).

Provider configuration is captured only when the selected compiled graph needs
model binding or provider calls. Repository slots authorize exact catalogue
entries; binding data alone grants no provider capability. Production Bedrock
credentials come from `AWS_BEARER_TOKEN_BEDROCK`. Models, regions and supported
controls are described in [F0007](design/features/F0007-AWSBedrockProvider.md).
The engine does not load `.env.e2e` or use internal `TEST_` credentials.

## Development evaluation

[Live E2E instructions](design/harness/e2e.md) cover credential setup, case
selection, retained evidence and result interpretation. Each agent-initiated
E2E run requires explicit user approval under [AGENTS.md](AGENTS.md).

```sh
./scripts/e2e-spec.sh
```

The launcher loads the checkout's optional `.env.e2e` and selects the Hello World
case by default. It uses real APIs for both generation and grading. The
[supplied-spec evaluator](design/harness/evaluator.md) separately grades a given
specification; it cannot establish engine-generation success. Neither harness
ships with the production executable.

## Documentation

| Document | Purpose |
| --- | --- |
| [Governing design](design/design.md) | Proposed implementation baseline, invariants and acceptance criteria. Accepted ADRs amend the named contracts without accepting the whole design. |
| [Accepted decisions](design/design.md#32-accepted-and-deferred-implementation-choices) | Language, compiler, runtime, provider, request and publication decisions. |
| [Contract samples](design/code.md) | Illustrative shapes and links to their owners; not an alternate runtime schema. |
| [Feature contracts](design/features/) | Component responsibilities, implementation scope and verification requirements. |
| [Diagrams](design/diagrams/) | Markdown-fenced Mermaid views of the architecture and workflows. |
| [Harness backlog](design/harness/README.md) | Remaining integration, calibration and live acceptance work. |
| [FIX_001 rollout](fixes/TODO_FIX_001.md) | Current repair/support/evidence work and links to historical findings. |

[Templates](design/templates/), [legacy preset source examples](design/toolchainPresets/)
and [configuration examples](design/examples/) are design inputs. They are not
an engine constitution, automatically installed policy or runtime fallback.
This checkout develops SDDE; running it against a target project requires an
explicit target and workflow.
