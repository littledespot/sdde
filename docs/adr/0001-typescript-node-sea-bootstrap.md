# ADR 0001: TypeScript/Node SEA bootstrap

**Status:** Accepted for the bootstrap by the explicit user request to set up a basic TypeScript project that produces a Node SEA. This decision does not accept or amend `design/design.md`, which remains proposed.

## Decision

The bootstrap uses npm with an `npm` lockfile, TypeScript 7.0.2, Node 24.x (built and tested with 24.2.0), Node16 module resolution with CommonJS output, Node's `--experimental-sea-config` preparation flow, and `postject` 1.0.0-alpha.6 injection. The generated executable is named `dist/sdde` (`dist/sdde.exe` on Windows) and targets only the operating system and CPU architecture of the Node executable used to build it.

The SEA entry point is a single compiled CommonJS file. The application has no runtime npm dependencies, embedded assets, runtime configuration, dynamic loading, or native dependencies. The package build script invokes child processes with `shell: false`; the application does not execute commands.

macOS builds remove the copied binary's signature before injection and apply an ad-hoc signature afterwards, as required by Node's SEA build flow. Linux and Windows paths follow Node's platform-specific injection convention, but this bootstrap's only supported release artifact is the current build host's artifact. Cross-platform release matrices, signing policy, release checksums, source maps, structured diagnostics, shutdown/signal behavior, configuration discovery, and runtime asset policy require a later ADR before implementation relies on them.

## Consequences

- `npm run build:sea` compiles TypeScript, prepares a SEA blob, injects it into a copy of the current Node executable, and emits one host-platform binary.
- `npm test` rebuilds that binary and runs it from a fresh temporary directory, proving it does not need the source tree or `node_modules` at runtime.
- Node SEA is still an actively developed Node feature and supports a single embedded CommonJS script. Future modular runtime code must be bundled to that format before SEA preparation.
- This is only an executable bootstrap. It does not implement the workflow engine, configuration/preset authority, model boundary, or acceptance criteria in the proposed design.
