# SDDE

SDDE is being developed as a deterministic native Zig executable. The current
implementation scaffold prints:

```text
Hello, world!
```

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
