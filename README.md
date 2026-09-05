# SDDE

SDDE is being developed as a deterministic native Zig executable and generic
declarative workflow engine. Its accepted runtime direction is to load any
bounded set of validated workflow definitions from the configured
`paths.workflows` root, capture only their declared resources, compile graphs
through one registry of generic operations, and execute one selected workflow
by its compiled transitions. `specify`, `plan`, `tasks`, and `implement` are
the initial workflow suite, not a fixed engine registry.

The accepted execution contract is [one atomic workflow from beginning to
end](design/decisions/0009-atomic-workflow-execution.md). Non-success abandons
its candidate output; a new invocation starts at `start`. There are no
project/feature transactions, provider-effect journals or saved continuations.
Clarifications and relevant answers survive without duplication.

[Provider APIs own model-call size limits](design/decisions/0011-provider-owned-request-limits.md).
SDDE adds no request/response byte ceilings or size-estimation gates. It records
actual API input/output token usage against the workflow execution's total
budget and stops subsequent calls at or above that budget. The legacy capacity
types, size parameters and static-capacity action have been removed.

Bootstrap loads the exact `.sddtoolkit.json` in the invocation working
directory, validates configured roots, compiles all concise `workflow/v1`
definitions, and publishes the immutable workflow registry before selection.
Provider configuration is read only after selection when the compiled graph
requires model binding or provider calls. Pure preparation steps receive only
immutable binding data; provider calls require a separate policy-permitted port.
[Workflow-owned requests](design/decisions/0012-workflow-owned-model-request.md)
now have native YAML initialization, assignment, binding-validation and building
operations. One request retains its originating slot/resources across steps;
generic preparation needs no SDD feature or task. Inference integration and
Bedrock remain separate work.

## Requirements

- Zig 0.16.0 exactly

## Commands

```sh
zig build
zig build run
zig build lint
zig build test
zig build test-atomic-execution
zig build test-model-result-schema
zig build test-reference-preflight
zig build test-feature-directory
zig build test-clarification-inputs
zig build smoke
zig build verify
```

`zig build lint` uses the pinned Zig compiler to check formatting and AST
validity for the repository's Zig and ZON sources. `zig build verify` runs that
lint step and the unit tests, then copies the built executable into a clean
temporary directory, clears its environment, and verifies its exact standard
output. The temporary package directory is removed by the Zig build runner
after a successful build.

Concrete domain operations and the full initial SDD workflow suite remain
incremental work under `design/design.md` and their feature contracts.

Specify's registered invocation requires `--feature <directory> --reference <selector>`.
The read-only preflight resolves the feature beneath `.sddtoolkit.json`'s
`paths.specs`, independently of its reference source: `--feature hello-world`
selects `<paths.specs>/hello-world/`
([ADR 0010](design/decisions/0010-explicit-feature-directory.md)). Shared path
validation rejects traversal, archive targets and filesystem aliases/symlinks.
Missing targets remain absent; no ownership registry or generated-name operation
exists. YAML-selected feature-input preparation also resolves fixed artifact
paths and reads bounded clarification state/forms. It preserves closed files,
rejects stale/malformed submissions, and distinguishes submitted from recorded
answers without accepting either as current authority. See
[F0100's input contract](design/features/F0100-SpecWorkflow.md#32-read-only-artifact-and-clarification-inputs).
Full `spec.md` generation remains unfinished. Shared NFC uses statically
linked utf8proc with packaged license notices
([ADR 0007](design/decisions/0007-unicode-normalization.md)).

Transaction-ID modules, provider journal projections, and logging transaction
stabilization/events have been removed under ADR 0009. Provider lifecycle and
authorization remain in memory for one execution. Only the root `features/`
directory is reserved during workflow discovery. Rerun output replacement and protected
clarifications follow Design Sections 25 and 23.2.
