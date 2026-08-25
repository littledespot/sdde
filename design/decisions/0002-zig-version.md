# ADR 0002: Pin Zig 0.16.0

- **Status:** Accepted
- **Date:** 2026-08-26
- **Decision authority:** Explicit user direction to implement the Zig 0.16.x line
- **Supersedes:** The deferred compiler-version and upgrade-policy choice in
  [Section 32 of the design](../design.md#32-accepted-and-deferred-implementation-choices)

## Context

ADR 0001 selects Zig as the engine implementation language but defers the exact
compiler version. The governing design requires an exact repository-owned pin
before accepting the initial build scaffold. Zig build and standard-library APIs
may change incompatibly before Zig 1.0, so a floating compiler version would not
provide reproducible build behavior.

The accepted release line is Zig 0.16.x. At the time of this decision, Zig
0.16.0 is the current stable release in that line.

## Decision

SDDE pins Zig 0.16.0 exactly.

- `.zigversion` records the developer-toolchain pin.
- `build.zig.zon` records Zig 0.16.0 as the package's minimum version.
- `build.zig` rejects every compiler version other than 0.16.0.
- A later stable 0.16.x patch may replace the exact pin after the repository's
  complete verification passes. Minor-version upgrades require a new explicit
  decision.

## Consequences

- Developer and CI builds use the same Zig language, build-system, and standard-
  library contracts.
- The initial implementation may use Zig 0.16 `std.Io` APIs directly without a
  compatibility layer.
- Any accepted patch upgrade updates all three pinning locations together and
  records the verification evidence.
- This decision does not select dependencies, release modes, linking strategy,
  or a supported platform matrix.
