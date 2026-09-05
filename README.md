# SDDE

SDDE is being developed as a deterministic native Zig executable and generic
declarative workflow engine. Its accepted runtime direction is to load any
bounded set of validated workflow definitions from the configured
`paths.workflows` root, capture only their declared resources, compile graphs
through one registry of generic operations, and execute one selected workflow
by its compiled transitions. `specify`, `plan`, `tasks`, and `implement` are
the initial workflow suite, not a fixed engine registry.

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

Specify's registered invocation, read-only reference-selector preflight, and
deterministic identity derivation are implemented; they do not activate a
feature or generate `spec.md`. Identity derivation requires an explicit YAML
`max-length` (see [ADR 0008](design/decisions/0008-feature-naming-policy.md)).
Unicode NFC and naming folds use pinned
utf8proc compiled into the executable; `zig build` installs its license under
`zig-out/share/licenses/utf8proc/` (see [ADR 0007](design/decisions/0007-unicode-normalization.md)).
