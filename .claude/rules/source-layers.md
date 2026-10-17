---
paths:
  - "src/**/*.zig"
  - "tests.zig"
  - "integration.zig"
---

# Source layers and test wiring

`zig build test-architecture` (`src/architecture_test.zig`) enforces these
boundaries mechanically; run it after changing imports or moving code. The governing
rules are AGENTS.md "Actions, orchestrators, and runner" and
`design/contracts/29-package-structure.md`.

| Location | Mechanical constraint |
| --- | --- |
| `src/domain/`, `src/ports/` | Import nothing from `actions/`, `application/` or `adapters/`. |
| `src/actions/` | Import only `std`, `builtin`, `../../domain/...` and `../../ports/...`. Each file declares exactly one `pub const Action = struct` and one `pub const contract: pipeline.NodeContract`. |
| `src/application/*_orchestrator.zig`, `*_coordinator.zig` | Capability-free: no `/actions/`, `/adapters/` or `/ports/` imports and no `std.Io`. |
| `src/application/*_runner.zig` | No `/adapters/` imports and no `std.Io`. |
| `src/adapters/` | The only place for filesystem, process, network/HTTP and provider-client access. Native model HTTP goes through the test-disabled connection owner. |
| `src/composition/` | The only place that constructs concrete adapters and binds registered node implementations. |

Test wiring:

- Unit tests are reached from `tests.zig` through `src/root.zig` and
  `src/runtime_tests.zig`. A new `*_test.zig` that is not imported from that tree
  never runs. Owning boundaries usually also have a targeted `zig build test-<area>`
  step in `build.zig`.
- Workflow scenarios in `test/integration/` and `test/harness/integration/` run under
  `zig build test-integration` and must not be imported from unit roots.
- `zig build test-build-registration` rejects test executions that are missing from,
  or added outside, the full-suite registration in `build.zig`.
