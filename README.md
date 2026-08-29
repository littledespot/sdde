# SDDE

SDDE is being developed as a deterministic native Zig executable and generic
declarative workflow engine. Its accepted runtime direction is to load any
bounded set of validated workflow definitions from the configured
`paths.workflows` root, compile graphs only from registered pipeline-node
contracts, and execute one selected workflow. `specify`, `plan`, `tasks`, and
`implement` are the initial workflow suite, not a fixed engine registry.

The current increment only loads the exact `.sddtoolkit.json` in the invocation
working directory. A missing or unreadable file exits with
`ENGINE_CONFIG_READ_ERROR`; malformed or structurally invalid v2 content exits
with `ENGINE_CONFIG_PARSE_ERROR` before workflow work begins.

## Requirements

- Zig 0.16.0 exactly

## Commands

```sh
zig build
zig build run
zig build lint
zig build test
zig build smoke
zig build verify
```

`zig build lint` uses the pinned Zig compiler to check formatting and AST
validity for the repository's Zig and ZON sources. `zig build verify` runs that
lint step and the unit tests, then copies the built executable into a clean
temporary directory, clears its environment, and verifies its exact standard
output. The temporary package directory is removed by the Zig build runner
after a successful build.

The workflow engine described in `design/design.md` is not implemented by this
initial scaffold.
