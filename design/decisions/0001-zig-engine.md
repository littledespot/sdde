# ADR 0001: Implement SDDE in Zig

- **Status:** Accepted
- **Date:** 2026-08-26
- **Decision authority:** Explicit user direction
- **Supersedes:** The deferred engine language/runtime choice in
  [Section 32 of the design](../design.md#32-accepted-and-deferred-implementation-choices)

## Context

SDDE is intended to ship as a deterministic single executable. The repository
has no implementation scaffold yet, but its project instructions assumed a
future TypeScript/Node.js SEA implementation while the governing design still
listed the implementation language and runtime as deferred.

The implementation language must be settled before the build, module,
ownership, error-handling, dependency, testing, and packaging contracts can be
made concrete.

## Decision

SDDE will be implemented in Zig and packaged as a native executable using the
Zig build system.

- Zig is the sole production implementation language for the engine.
- The engine will not require Node.js at runtime and will not use Node SEA for
  packaging.
- TypeScript and JavaScript are not engine implementation languages.
- JavaScript/TypeScript and Node toolchain presets remain supported target-
  project policies. They describe repositories SDDE may operate on; they do
  not determine SDDE's own implementation technology.
- The exact Zig compiler version, upgrade policy, dependency set, release build
  modes, linking strategy, and supported platform matrix remain deferred until
  explicitly decided and recorded. The compiler version must be pinned before
  the implementation scaffold is accepted.

## Consequences

- The initial scaffold will use `build.zig`, repository-defined Zig build
  steps, and a Zig source/module layout.
- Closed workflow variants map to Zig tagged unions and exhaustive `switch`
  handling. Validated identifiers and capabilities use distinct wrapper types.
- Allocation, borrowing, ownership, cleanup, and error-union behavior become
  explicit parts of implementation contracts and tests.
- Filesystem, process, network/HTTP, C ABI, and provider integrations remain
  behind the existing narrow adapter boundaries.
- Packaging evidence must run the produced executable in a clean environment
  without the source tree, Zig toolchain, build cache, or development-only
  assets.

This decision changes implementation technology only. It does not accept the
remainder of the proposed design, add a production dependency, implement the
engine, or authorize running SDDE against a target project.
