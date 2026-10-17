---
paths:
  - "**/*.zig"
  - "build.zig.zon"
---

# Zig 0.16 idioms

The compiler is pinned to Zig 0.16.0 (`.zigversion`, enforced by
`build/zig_version.zig`). Its standard library differs substantially from the
releases most published examples target. Copy idioms from neighbouring code in this
repository rather than from memory, and compile before relying on an unfamiliar API.

Patterns this codebase already uses:

- Entry points take `std.process.Init`
  (`pub fn main(init: std.process.Init) !void`) and pass `init.io`, `init.gpa` and
  `init.arena` explicitly.
- I/O goes through an explicit `std.Io` value: `std.Io.Dir.cwd().openDir(io, ...)`
  and `dir.readFileAlloc(io, name, allocator, .limited(max))`. Tests use
  `std.testing.io`.
- `std.ArrayList(T)` is unmanaged: initialise with `.empty` and pass the allocator
  to each `append`/`deinit` call.
- Text is built with `std.Io.Writer.Allocating`.

A project hook runs `zig fmt` on each edited repository `.zig` file; `zig build lint`
remains the authoritative format and AST check. Filesystem, process, network and
provider-client access belong only in `src/adapters/` (see `source-layers.md`).
