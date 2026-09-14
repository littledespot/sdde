# ADR 0001: Implement SDDE in Zig

- **Status:** Accepted
- **Date:** 2026-08-26
- **Decision authority:** Explicit user direction
- **Supersedes:** The deferred engine language/runtime choice in
  [Section 32 of the design](../design.md#32-accepted-and-deferred-implementation-choices)

## Context

SDDE is intended to ship as a deterministic single executable. At the time of this decision, the repository had no implementation scaffold,
and its project instructions assumed a future TypeScript/Node.js SEA
implementation while the governing design listed the language/runtime as deferred.

The implementation language must be settled before the build, module,
ownership, error-handling, dependency, testing, and packaging contracts can be
made concrete.

## Decision

- SDDE will be implemented in Zig and packaged as a native executable using the Zig
  build system.

- Zig is the sole production implementation language for the engine.
- The engine will not require Node.js at runtime and will not use Node SEA for
  packaging.
- TypeScript and JavaScript are not engine implementation languages.
- JavaScript/TypeScript and Node toolchain presets remain supported target-project
  policies.
- They describe repositories SDDE may operate on; they do not determine SDDE's own
  implementation technology.
- Subsequent decisions settle individual implementation choices: [ADR
  0002](0002-zig-version.md) pins Zig 0.16.0 and its upgrade policy; [ADR
  0007](0007-unicode-normalization.md) pins shared Unicode normalization and its static
  packaging.
- Other dependency, release-mode, linking and platform choices require their own
  recorded decisions.

## Consequences

- The initial scaffold will use `build.zig`, repository-defined Zig build steps, and a
  Zig source/module layout.
- Closed workflow variants map to Zig tagged unions and exhaustive `switch` handling.
- Validated identifiers and capabilities use distinct wrapper types.
- Allocation, borrowing, ownership, cleanup, and error-union behavior become explicit
  parts of implementation contracts and tests.
- Filesystem, process, network/HTTP, C ABI, and provider integrations remain behind the
  existing narrow adapter boundaries.
- Packaging evidence must run the produced executable in a clean environment without the
  source tree, Zig toolchain, build cache, or development-only assets.

- This decision changes implementation technology only.
- It does not accept the remainder of the proposed design, add a production dependency,
  implement the engine, or authorize running SDDE against a target project.
