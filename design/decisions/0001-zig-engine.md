# ADR 0001: Implement SDDE in Zig

- **Status:** Accepted
- **Date:** 2026-08-26
- **Decision authority:** User decision, 26 August 2026
- **Supersedes:** The deferred engine language/runtime choice in
  [Section 32 of the design](../design.md#32-accepted-and-deferred-implementation-choices)

## Decision

- SDDE is implemented in Zig and packaged as a native executable using the Zig build
  system.
- Zig is the sole production implementation language for the engine.
- The engine does not require Node.js at runtime and does not use Node SEA for packaging.
- TypeScript and JavaScript are not engine implementation languages.
- JavaScript/TypeScript and Node toolchain presets remain supported target-project
  policies. They describe repositories SDDE may operate on; they do not determine SDDE's
  own implementation technology.
- [ADR 0002](0002-zig-version.md) pins the compiler version and its upgrade policy;
  [ADR 0007](0007-unicode-normalization.md) pins shared Unicode normalization and its
  static packaging.
- Other dependency, release-mode, linking and platform choices require their own recorded
  decisions.
- Packaging evidence runs the produced executable in a clean environment without the
  source tree, Zig toolchain, build cache or development-only assets.
