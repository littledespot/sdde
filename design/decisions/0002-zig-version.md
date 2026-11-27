# ADR 0002: Pin Zig 0.16.0

- **Status:** Accepted
- **Date:** 2026-08-26
- **Decision authority:** User decision, 26 August 2026
- **Supersedes:** The deferred compiler-version and upgrade-policy choice in
  [Section 32 of the design](../design.md#32-accepted-and-deferred-implementation-choices)

## Decision

SDDE pins Zig 0.16.0 exactly. Zig build and standard-library APIs may change incompatibly
before Zig 1.0, so a floating compiler version would not give reproducible builds.

- `.zigversion` records the developer-toolchain pin.
- `build.zig.zon` records Zig 0.16.0 as the package's minimum version.
- `build.zig` rejects every compiler version other than 0.16.0.
- A later stable 0.16.x patch may replace the exact pin after the repository's complete
  verification passes. The upgrade updates all three pinning locations together and
  records the verification evidence.
- Minor-version upgrades require a new explicit decision.
- The implementation may use Zig 0.16 `std.Io` APIs directly without a compatibility
  layer.
- This decision does not select dependencies, release modes, linking strategy or a
  supported platform matrix.
