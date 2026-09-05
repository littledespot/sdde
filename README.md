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

Bootstrap loads the exact `.sddtoolkit.json` in the invocation working
directory, validates configured roots, compiles all concise `workflow/v1`
definitions, and publishes the immutable workflow registry before selection.
Provider configuration is read only after selection when the compiled graph
requires model binding or provider calls. Pure preparation steps receive only
immutable binding data; provider calls require a separate policy-permitted port.

## Requirements

- Zig 0.16.0 exactly

## Commands

```sh
zig build
zig build run
zig build lint
zig build test
zig build test-model-result-schema
zig build test-reference-preflight
zig build test-feature-identity
zig build test-transaction-id-ledger
zig build test-transaction-id-ledger-codec
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

Specify's read-only reference-selector preflight exists. The design now requires
a feature directory relative to `.sddtoolkit.json`'s `paths.specs`, independent
of its reference source: `--feature hello-world` selects `<paths.specs>/hello-world/`
([ADR 0010](design/decisions/0010-explicit-feature-directory.md)). The reference-only
invocation and derived-name operation remain superseded code to replace; there
is no feature-ownership registry to implement. Full `spec.md` generation remains
unfinished. Shared NFC uses statically linked utf8proc with packaged license
notices ([ADR 0007](design/decisions/0007-unicode-normalization.md)).

Existing transaction-ID ledger/codec code is superseded by ADR 0009 and is
not a persistence foundation to extend. Removing that code is separate from
this documentation amendment. Only the root `features/` directory is reserved
during workflow discovery. Rerun output replacement and protected
clarifications follow Design Sections 25 and 23.2.
