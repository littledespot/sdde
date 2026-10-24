# Offline test performance

**Measured:** 24 October 2026, Australia/Melbourne. Apple M4 (10 cores, 24 GB),
macOS 27.0, Zig 0.16.0. **Reviewed twice the same day:**

- The first review added findings T10–T14 and proposals P9–P11, and corrected the
  `memset` share, T1, T3, T7, P2 and P8.
- The second review assessed every proposal (§4) and re-measured on a clean tree. It
  withdrew P5 and P11, cut the expected effects of P1 and P3, and found feasibility
  gaps in P2 and P9. It corrected T7, T8 and T12, and added T15 and P12. §7 lists the
  changes.

**Status:** investigation note, not an active fix record. [FIX05](FIX05.md) remains the
sole active fix record ([README](README.md)). This note holds findings and proposals only.
It authorizes no code, build or test change. Adopting a proposal means recording it in
FIX05 first.

**Evidence:**

- **Integration run.** One cold `zig build test-integration --summary all`, against an
  empty scratch `--cache-dir`, on the working tree later committed as `1a683aa`. A
  macOS `sample` profile of the test binary was taken every 2 ms, and the run's
  `scenario-cost` lines were kept.
- **Full verification.** Two consecutive `zig build verify --summary all` runs, each
  against a scratch cache, with `repository-tests` sampled. Memory was recorded with
  `memory_pressure`, `vm_stat` and `vm.swapusage`. Both runs used an uncommitted tree
  that was being edited at the time (§2).
- **Clean-tree re-measurement.** One cold `zig build test test-integration`, against a
  scratch cache, on a clean `d736d9a`, with `repository-tests` sampled. It was
  followed by a `zig build test-integration` rerun on the same unchanged tree, with
  the integration binary sampled.
- **Retained logs under `.zig-cache/`.** `test-integration.*` (9–22 October), the
  `*-verify.log`, `*-architecture.log` and `b2-final-targeted.log` files. These are
  git-ignored local files and are not kept anywhere else.
- **Source, contracts and disassembly.** Reading the repository source and contracts
  and the Zig 0.16 standard library and build runner, and disassembling the
  `ReleaseSafe` integration binary.

No model calls were made. A sampled run takes about 1.5 times longer than normal.
Profile categories overlap, so they don't sum to 100%.

## 1. Summary

`zig build verify` takes about 4 minutes after any source edit. That's the same as
from an empty cache (240 s against 241 s), and three things drive it:

1. **Every engine-sized artifact recompiles after a source edit.** There are about
   ten of them, and they are compiled independently. The critical path starts with
   the `ReleaseSafe` integration compile, which takes 2 minutes inside `verify` (T6).
   Build provenance also forces six harness compiles after documentation-only edits
   and commits (T8).
2. **Test runs never hit the cache.** Each `zig build` passes a new random `--seed`
   to the test binaries, so both one-minute test runs repeat every time. This was
   confirmed on an unchanged tree: the compile was `cached 79ms` and the run still
   took 1m (T10).
3. **The testing allocator dominates both runs.** It captures a 10-frame stack trace
   by DWARF unwinding on every allocation, resize and free. That is **73% of
   `repository-tests`** and **36–38% of the integration run** (T2).
   - The 109 exhaustive allocation-failure sweeps are 51% of the unit run (T12).
   - The 196-scenario Spec sweep is 90% of the integration run (T1).

Average CPU use during `verify` is only about 2.4 of 10 cores. Wall time is set by a
serial chain, not by machine capacity, and memory isn't the limit (T7).

The largest test-only lever is P1, scoped to those two sweeps. It is estimated to cut
the unit run by about 44% and the integration run by about 36%. It shortens `verify`
after an edit by only about 20–25 s, though, because the integration compile sets that
critical path; P4 addresses the compile. The largest lever for repeated runs is P9,
which needs a policy decision. All of these effects are estimates, not measurements
(§4).

## 2. Measurements

### Full `verify`

Both runs used scratch caches.

| Run | Wall | CPU (user + sys) | Result |
| --- | --- | --- | --- |
| Empty cache | 241 s | 586 s + 40 s | 1,915 of 1,916 tests passed (see caveat) |
| After a source edit | 240 s | 547 s + 41 s | 1,916 of 1,916 passed |

The second run was meant to be a no-op rerun. The tree changed in between, though:
about 20 files under `src/` and `design/` were edited after 08:10. So it measures a
rebuild after an edit, not a no-op.

Caveat: in the first run, one unit test failed (`authorization compiler and registry
reject hidden producers and a forged deadline parameter`). Its file,
`src/model_request_workflow_test.zig`, was being edited during that run. The failure
isn't attributed to anything, and the clean-tree run passed 1,920 of 1,920 tests.

Step costs inside `verify`. Parallel contention makes every compile slower than when
it runs alone. Zig's build summary truncates durations to whole minutes, so `1m` means
60–119 s and `2m` means 120–179 s.

| Step | Time | MaxRSS |
| --- | --- | --- |
| Integration test compile (`ReleaseSafe`) | 2m (about 110 s alone) | 3–4 GB |
| Integration test run | 1m | 0.9–3 GB |
| `repository-tests` compile | 44–52 s (35 s in older logs) | 3–4 GB |
| `repository-tests` run | 1m (93–95 s under the sampler) | 620 MB |
| `sdde`, `sdde-e2e-spec`, `sdde-provider-compatibility`, `sdde-baseline` | 17–27 s each, two compiles each | 1–2 GB |
| `sdde-e2e-call`, `sdde-evaluate-spec`, `sdde-adjudicate-spec`, `sdde-exact-value-replay`, `debugger-smoke` | 3–6 s each | 0.5–0.7 GB |
| Nested `zig build` steps (build isolation and registration) | 4–5 s each, cold | |
| `capture-build-provenance` run | 1 s | |
| Lint, packaged smoke runs, launcher shell tests | 0.03–0.5 s each | |

Memory during both runs:

- Free memory never fell below 39%.
- Nothing swapped, and there were only 2–18 pageouts per run.
- The memory compressor did handle 1.5–2.1 million pages per run.

### Clean-tree runs (`d736d9a`)

| Run | Result |
| --- | --- |
| Cold `zig build test test-integration`, both binaries sampled | 270 s wall, 465 s user; 1,920/1,920 passed. Integration compile 2m (3 GB), `repository-tests` compile 44 s (4 GB). |
| `zig build test-integration` rerun on the unchanged tree | Compile `cached 79ms`; run `1m` (98 s under the sampler). Seeds `0x4eb44d95`, then `0x71ccdc78`. |

### Integration run, standalone and cold

| Measure | Value |
| --- | --- |
| Wall time | 222 s (190.9 s user, 21.1 s sys) |
| Test binary started | after 116 s |
| Compile (`ReleaseSafe`) | `1m`; about 110 s in practice, since the binary started 116 s in. MaxRSS 5 GB |
| Run | `1m`, MaxRSS 2 GB, 129/129 passed; about 106 s under the sampler (43,357 samples cover 87 s of it) |

Retained runs agree: 9 October, 84 tests in 51–54 s; 18 and 21 October, 127 tests in
`1m` at about 3 GB.

### Where the integration run spends its time

The `1a683aa` profile is shown; the `d736d9a` rerun agrees where it was checked.

| Inclusive share | Frames |
| --- | --- |
| 89.4% (89.6%) | `testSpecificationWorkflows` |
| 75.3% | `workflow_engine_orchestrator.run` (execution) |
| 36.4% (37.5%) | Stack-trace capture (`debug.SelfUnwinder`, `debug.Dwarf.*`, `StackIterator`); 35.9% of the run is inside the sweep |
| 16.9% | Feature-log persistence (`persistEventBinding`, `LogService.process`) |
| 15.8% | Filesystem syscalls; `openat` alone 10.6%, `fsync` 0.3% |
| 15.6% | `runInProjectWithRegistry` (bootstrap) |
| 13.3% | Workflow compilation and validation (`workflow_subgraphs.Compiler`, `Registry.validate`, `workflow_data_flow.analyze`) |
| 10.8% | JSON parsing (T15) |
| 9.0% | `mem.eqlBytes` (self time) |
| 6.9% | JSON writing, including canonical JSON |
| 6.4% | `std.sort.block` |
| 5.3% | `Runner.authorityMatches` (T11) |
| 4.2% | Test driver work outside the engine step; 3.3% is `atomic_repair.snapshot` |
| 1.2% | The four cancellation-checkpoint sweeps |
| 1.0% | Temporary-directory cleanup |

`memset` was the top-of-stack frame in 36.4% of samples. Its main immediate callers:

| Caller | Samples |
| --- | --- |
| DWARF unwinding: `computeRules` | 7,276 |
| DWARF unwinding: Column list growth | 774 |
| DWARF unwinding: `evalInstructions` | 678 |
| `sort.block` | 2,536 |
| Buffer growth | the remainder |

### Where `repository-tests` spends its time

From three sampled runs, which agree to within 1.2 points. The sweep figures come from
the `d736d9a` run and are measured by call stack.

| Inclusive share | Frames or tests |
| --- | --- |
| 72.7–73.9% | Stack-trace capture |
| 51.0% | Inside `checkAllAllocationFailures` sweeps (T12) |
| 44.5% | Stack-trace capture inside those sweeps |
| 28.3% | Stack-trace capture outside the sweeps; the three largest tests hold 8.4%, the rest is a long tail |
| 11.7% | JSON parsing; `strict_json.parse` alone 7.1% (T15) |
| 12.8% | The most expensive sweep: `composition application handoffs release retained parts and requests at every allocation failure` |
| 0.9% | `std.sort.block` |
| 0.7% | `architecture_test` |
| 0.6% | Filesystem syscalls |

### Scenario costs

`testSpecificationWorkflows` reports one `scenario-cost` line per scenario. These
figures are from the sampled run.

| Cases | Fixture | Bootstrap | Execution | Assertions | Cleanup | Total | Slowest |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 196 | 0.8 s | 10.8 s | 75.8 s | 1.6 s | 4.2 s | 93.6 s | 990 ms |

One test accounts for 177 of these scenarios (83.9 s): `configured specification
generation YAML executes native references models and authority gates`. The other
seven tests share the remaining 19, about 10 s. The other 121 integration tests take
roughly 12 s together. Both figures are under the sampler.

### Retained logs

- **Cold `verify`** (`global-token-verify.log`):
  - integration test: compile 1m at 4 GB, run 1m;
  - `repository-tests`: compile 35 s, run 1m;
  - engine-sized executables: 13–17 s each, two compiles each.
- **Warm `verify`, after a commit** (`b4b9-commit-verify.log`): every step was cached
  except `sdde-e2e-spec` (16 s, 15 s) and `sdde-provider-compatibility` (15 s, 14 s).
  The two test runs still took 1m each (T10).
- **`/verify` ladder pre-steps:** `zig build test-architecture` compiles in 2 s and runs
  in 1 s. Targeted `zig build test-<area>` steps compile in 2–16 s and run in under 5 s
  (`b2-final-targeted.log`).

## 3. Findings

### T1. One serial scenario sweep dominates the integration run

Eight tests ([workflow_tests.zig:1145-1173](../test/integration/workflow_tests.zig#L1145-L1173))
call `testSpecificationWorkflows`
([workflow_tests.zig:1237](../test/integration/workflow_tests.zig#L1237)). Together they
run 196 scenarios, 177 of them inside one test.

Each scenario:

- creates a temporary project;
- bootstraps through the production `runInProjectWithRegistry`;
- assembles the production feature-logging runtime;
- runs the production pipeline runner and engine orchestrator.

A scripted fake provider stands in for the model. A test driver
(`spec_generation_driver.Driver`) injects faults and checks each step. The driver's own
work is about 4% of the run, mostly the snapshots that back preservation assertions.

The Zig test runner executes the tests in a binary one after another in a single
process. The build runner only spreads work across processes for fuzzing. So
scenarios never overlap. T2–T5, T11 and T15 are the costs inside each scenario.

### T2. The testing allocator captures a stack trace on every allocation

`std.testing.allocator` is a `DebugAllocator` configured with `stack_trace_frames = 10`
and `resize_stack_traces = true` (`lib/zig/std/testing.zig:22`). That setting is fixed,
not tied to the optimize mode. So every allocation, resize and free captures a 10-frame
trace, in Debug and `ReleaseSafe` alike.

On aarch64 Darwin, Zig 0.16 rates frame-pointer unwinding `.safe` but not `.ideal`
(`StackIterator.fp_usability` in `lib/zig/std/debug.zig`). So it always unwinds through
DWARF debug data when that data is present, and uses frame pointers only as a fallback.
The result is 73% of `repository-tests` and 36–38% of the integration run. Moving the
integration suite to `ReleaseSafe` in `b021e9b` (9 October) doesn't avoid it.

Test builds can't change this through `std_options`, because the Zig test runner is the
root module and declares its own. The narrowest fix is the allocator a test passes
down:

- **The sweep:** it binds its allocator once, `const allocator = std.testing.allocator;`
  ([workflow_tests.zig:1239](../test/integration/workflow_tests.zig#L1239)), and uses it
  106 times. The driver backs two arenas with `std.testing.allocator`
  ([spec_generation_driver.zig:156](../src/test_fixtures/spec_generation_driver.zig#L156),
  [:225](../src/test_fixtures/spec_generation_driver.zig#L225)).
- **Allocation-failure sweeps:** 107 of the 109 `checkAllAllocationFailures` calls pass
  `std.testing.allocator` as the backing allocator (T12).
- **Everything else:** the repository contains 3,496 references to
  `std.testing.allocator`.

Leak detection currently comes from the test runner, not the tests. After each test the
runner calls `testing.allocator_instance.detectLeaks()` and fails the test on a leak
(`lib/zig/compiler/test_runner.zig`, `run_test` handler). `checkAllAllocationFailures`
relies on that runner check to report leaks from its failing iterations. Any
replacement allocator therefore has to take over that check itself (P1).

### T3. The feature log does a full lock and file cycle for every event

`feature_log_orchestrator.processEvent`
([feature_log_orchestrator.zig:6](../src/application/feature_log_orchestrator.zig#L6))
handles each emitted event in this order:

1. Acquire the stream lock
   ([feature_log_lock.zig:8](../src/adapters/filesystem/feature_log_lock.zig#L8)): open,
   stat and `flock` the lock file.
2. Persist the row through the segment store, called from
   [feature_log_sink.zig:190](../src/adapters/filesystem/feature_log_sink.zig#L190):
   open, stat, write and close the segment file.
3. Release the lock: unlock and close.

The two opens account for 1,717 and 1,647 `openat` samples, about 8% of the run.
Logging overall is 17%, including stack-trace capture for its allocations. `fsync` is
negligible.

Scenarios log at debug level, and the sweep asserts on those events. It reads the event
log and checks that `action.started` balances the completed, invalid and failed events
([workflow_tests.zig:1797-1798](../test/integration/workflow_tests.zig#L1797-L1798)).
Lowering the sweep's log level would therefore weaken an assertion.

The per-event cycle is contract behaviour, not an adapter detail:

- **§13.9 action sequence.** `AcquireFeatureLogStreamLockAction` makes one attempt with
  a fixed deadline, and every lock is released on every path
  ([13-09-logging.md:14-41](../design/contracts/actions/13-09-logging.md#L14-L41)).
- **§26 lock and identity rules.** One exclusive lock exists per
  `(featureId, runId, stream)` "while a writer is … appending"
  ([26-security.md:209-212](../design/contracts/26-security.md#L209-L212)).
  Target identity checks must be repeated at commit with no-follow operations
  ([26-security.md:21](../design/contracts/26-security.md#L21)). Today's per-append
  `openFile` with `follow_symlinks = false` and `resolve_beneath = true`, plus the size
  check, is how the code meets that.
- **Shared lock.** Retention
  ([ADR 0026](../design/decisions/0026-header-identity-log-retention.md)) and
  historical finalization
  ([14-orchestration.md:302](../design/contracts/14-orchestration.md#L302)) take the same
  per-run stream lock.

### T4. Every scenario bootstraps the engine again

Each scenario reads configuration, enumerates and captures workflow resources, and
compiles and validates the workflow registry. That takes about 55 ms per scenario,
10.8 s across the sweep. This is the production path the tests exist to exercise.

### T5. `std.sort.block` fills a 512-element buffer on every call

`std.sort.block`, which is what `std.mem.sort` uses, declares
`var cache: [512]T = undefined;` (`lib/zig/std/sort/block.zig:116`). Safety-checked
builds fill `undefined` memory with `0xAA`. That is confirmed for `ReleaseSafe`: the
integration binary's `sort.block` contains `mov w1, #0xaa` followed by
`bl _compiler_rt.memset`. So every call writes 512 × `@sizeOf(T)` bytes, however short
the input.

Engine source calls `std.mem.sort` at 37 sites. Element types include large structs,
such as `DeclarativeStep` in
[workflow_subgraphs.zig:33](../src/domain/workflow_subgraphs.zig#L33). The heavy
callers are `workflow_subgraphs.Compiler.scope` (recursive), `canonical_json.write` and
`required_authority.build`. This is 6.4% of the integration run and 0.9% of
`repository-tests`.

### T6. The integration suite compiles in `ReleaseSafe`, at the start of the critical path

[build.zig:348](../build.zig#L348) compiles the root integration module, meaning the
engine and tests imported by relative path, in `ReleaseSafe`. That takes about 110 s
alone and `2m` (120–179 s) inside `verify`, at 3–5 GB. With the run that follows (60–119
s), the integration chain accounts for most of the 4 minutes `verify` takes after an
edit. The `repository-tests` chain is shorter: a 44–52 s compile, then a run of about a
minute.

The choice is deliberate and documented. [README.md:82](../README.md#L82) states that
the integration executable always uses `ReleaseSafe`. `b021e9b` made the switch in the
same commit that moved the workflow scenarios into this suite.

The dependency modules (`yaml`, `bounded_yaml_syntax`, `unicode_normalization`,
`exact_value_unicode`) still compile in Debug, because they take the default optimize
mode.

Not measured: how long this module takes to compile and run in Debug.

### T7. Each offline harness application is compiled in two configurations

`offlineExecutable` ([build.zig:916](../build.zig#L916)) wraps an application in a new
root ([test/packaging/offline.zig](../test/packaging/offline.zig)) that sets
`live_model_connections = false`. That comptime switch disables
`native_model_http` ([native_model_http.zig:7](../src/adapters/provider/native_model_http.zig#L7)).
It applies to `sdde`, `sdde-e2e-spec`, `sdde-provider-compatibility`, `sdde-baseline`,
`sdde-e2e-call` and `sdde-evaluate-spec`.

The smoke steps also depend on the unwrapped executables
([build.zig:331](../build.zig#L331), [build.zig:415](../build.zig#L415),
[build.zig:447](../build.zig#L447)). Those are the only offline compile of the live
configuration, so the second compile is coverage, not duplication. In `verify`, the
four engine-sized pairs cost 17–27 s per compile.

These compiles cost CPU and memory but sit off the critical path (T6), and memory is
not the bottleneck. Free memory stayed at or above 39% with no swap.

### T8. Build provenance invalidates harness compiles after any edit

`capture-build-provenance` ([build/provenance.zig](../build/provenance.zig)) hashes the
contents of `src`, `test`, `design`, `scripts` and the root build files, and records
the Git revision. Its step runs on every build (`has_side_effects`,
[build.zig:255](../build.zig#L255)). The output is embedded through
`@embedFile("build_provenance")` in the e2e, compatibility and baseline harnesses, in
both configurations (T7).

The comment at [build.zig:257](../build.zig#L257) says offline builds must not be
invalidated by provenance. But `test` and `smoke` depend on those executables through
their smoke steps ([build.zig:427](../build.zig#L427),
[build.zig:450](../build.zig#L450), [build.zig:847](../build.zig#L847)). So any edit to
`design/`, or any commit, recompiles six executables at about 15–27 s and 1–2 GB each.
`b4b9-commit-verify.log` shows exactly this: nothing else in that run recompiled.

The coverage is a contract requirement.
[design/harness/e2e.md:492-502](../design/harness/e2e.md#L492-L502) requires live
reports to embed a build-time digest covering "build, engine, harness, test, design and
script inputs".

### T9. The local cache was inconsistent

At measurement time, `.zig-cache` held 15 GB:

| Path | Size |
| --- | --- |
| `.zig-cache/o` | 18 MB |
| `.zig-cache/h` | 62 MB |
| `.zig-cache/fresh` | 13 GB (`o` 7.5 GB, `tmp` 5.6 GB of leftover test temporary directories) |

`zig build test-integration` failed after 8 s with `C import failed: FileNotFound` and
`failed to open .zig-cache/o/28c50b3b…/utf8proc.o`. The same build succeeded against an
empty cache directory. The likely cause is that objects under `o/` were deleted while
their manifests under `h/` were kept. This was inferred from the cache state, not
reproduced. A `fix04-stale-manifests/` directory in the cache suggests this has
happened before. No script, skill or hook in the repository refers to
`.zig-cache/fresh`.

`.zig-cache` also holds material that isn't build cache:

- this note's retained logs (`*.log`);
- experiment directories: `authoring-associations/`, `authoring-comparison/`,
  `b2-advisory-*`, `fix04-stale-manifests/`, `llm-rework-phase4/`, `phase6-global/`,
  `global/` and `workflow-step-trace/`;
- `workflow-operation-sample.txt`.

### T10. Test runs re-execute on every build

A test `Run` step can be cached: `.zig_test` stdio reports no side effects
(`lib/zig/std/Build/Step/Run.zig:707`). However, `enableTestRunnerMode`
(`Run.zig:244`) adds `--seed=0x<random>` to the test's arguments, and `zig build`
picks a new random seed on each invocation unless `--seed` is passed. So the
arguments change every time, the cache always misses, and both one-minute runs repeat
even when compiles are cached. On the unchanged `d736d9a` tree, a rerun showed the
compile `cached 79ms` and the run `1m`, with different seeds.

No test uses `std.testing.random_seed`. The one PRNG in the test harness uses a fixed
protocol seed. So the random seed buys these suites nothing.

A fixed seed alone would make the cache unsafe, though:

- 14 run steps set their working directory to the repository root.
- Tests read repository files at runtime, including
  `design/workflows/spec.workflow.yaml`, the `test/e2e/*` cases and the
  `test/integration/fixtures/baseline/*` files.
- `architecture_test` walks the `src`, `src/actions` and `src/application` trees
  ([architecture_test.zig:49](../src/architecture_test.zig#L49),
  [:192](../src/architecture_test.zig#L192), [:218](../src/architecture_test.zig#L218)).
  A newly added file that nothing imports changes no compile.
- None of those inputs is declared with `addFileInput`, so a cached run could pass
  against stale inputs or miss a new file.

The main suites pass explicit `Environ.Map` values instead of reading the inherited
environment, so environment leakage is a smaller risk.

### T11. Execution re-derives facts that are fixed at bootstrap

- **Per-step registry validation.** `Runner.authorityMatches`
  ([workflow_pipeline_runner.zig:687](../src/application/workflow_pipeline_runner.zig#L687))
  runs a full `operation_registry.validate()`, plus policy and schema comparison,
  before every step and every invocation (lines 116 and 169). That is 5.3% of the
  sweep. The runner holds the registry as `*const`, but owners can still change the
  entries, and tests do exactly that to check rejection.
- **Repeated data-flow analysis.** `specification_state.validateReference` calls
  `reference_extraction_contract.capture`, which re-runs `workflow_data_flow.analyze`
  over the whole workflow authority on each parse, output preparation and state build
  ([reference_extraction_contract.zig:27](../src/domain/reference_extraction_contract.zig#L27)).
  That is 2.5% of the sweep.

No contract clause requiring per-step revalidation was found.
[14-orchestration.md:33](../design/contracts/14-orchestration.md#L33) requires
registry validation before workflow-specific work. Both costs apply to production runs
too. Much of the 9% `mem.eqlBytes` self time comes from linear, string-keyed lookups in
these validators, in bootstrap compilation and in `findTransition`.

### T12. Allocation-failure sweeps are quadratic, and every allocation is traced

`std.testing.checkAllAllocationFailures` runs a case once to count its allocations,
then once more for each allocation with a failure injected at that index. The
repository has 109 such sweeps. On `d736d9a`, frames inside the sweeps were 51.0% of
the `repository-tests` run, and stack-trace capture inside them was 44.5%. The most
expensive single sweep is 12.8%. Each pass allocates through the 10-frame tracing
allocator (T2).

The earlier figure (24 tests, 30.8%) counted tests by name and missed sweeps whose names
don't mention allocation failure.

The four integration cancellation sweeps have the same shape but cost only 1.2%.

### T13. Fixture configs mirror every log event to stderr

Fixture configs with `"console": true` route every emitted event row to stderr through
the console sink. The only such fixtures are frozen protocol or live-case inputs:

- `test/integration/fixtures/baseline/protocol.sddtoolkit.json` and its drifted mock,
  which [frozen_protocol_fixture.zig](../test/integration/frozen_protocol_fixture.zig)
  binds and the immutable protocol validator checks;
- `test/e2e/wf-001-hello-world/.sddtoolkit.json`, the live case's configuration.

The sink is [log_output.zig](../src/adapters/system/log_output.zig), called from
[feature_log_runner.zig:231](../src/application/feature_log_runner.zig#L231) and
[:337](../src/application/feature_log_runner.zig#L337). Each integration or `verify`
run therefore prints about 7,800 rows, 8–9 MB, even when every test passes. No stderr
writes show up in the profile, so the cost is output size, not time. It is why
`scripts/test-integration.sh` redirects the full log to a file.

### T14. Checked and not material, or not viable

| Item | Finding |
| --- | --- |
| Lint | 0.4 s |
| Packaged smoke runs | 27–473 ms each |
| Launcher shell tests | 0.1–0.5 s each; they use a fake `zig` |
| Provenance capture | 1 s |
| Nested `zig build` fixtures | 4–5 s cold |
| `/verify` pre-steps (`test-architecture`, targeted `test-<area>`) | 2–16 s compile and under 5 s run each; their binaries can't be reused by `verify`, but the cost is small |
| `architecture_test` | 0.7% of the unit run |
| Temporary-directory cleanup | 1% of the integration run |
| `fsync` | 0.3% of the integration run |
| Self-hosted aarch64 backend (`-fno-llvm`) | Not viable: with `-fno-lld` the binary failed with "exec format error"; with the default linker a hello-world compile ran past two minutes and was stopped |

None of these is worth pursuing.

### T15. Strict JSON decoding reads every document three times

`strict_json.decode`
([strict_json.zig:83-93](../src/domain/strict_json.zig#L83-L93)) makes three passes:

1. `validateTransport` runs a full scanner pass to check nesting depth
   ([:182-188](../src/domain/strict_json.zig#L182-L188)).
2. `parseDocument` builds a complete `std.json.Value` tree with `.alloc_always`
   ([:167-180](../src/domain/strict_json.zig#L167-L180)). That copies every string,
   and under the testing allocator traces every copy.
3. `wireTypes` checks that tree, and `parseFromSliceLeaky` parses the bytes a third time
   into the closed type.

JSON parsing is 10.8% of the integration run and 11.7% of the unit run.
`strict_json.parse` alone is 7.1% of the unit run, and packet building
(`specification_support.packetFor`, `model_candidate_json.encodeFor`) is the main
caller in the sweep. Production runs pay the same cost. The passes exist to reject what
Zig's typed parser would otherwise accept: quoted numbers, numeric enum tags and byte
arrays.

## 4. Proposals and their assessment

None may drop scenarios, skip or focus tests, weaken assertions or relax leak
detection (AGENTS.md, Prohibited shortcuts). Each code change also needs the AGENTS.md
"Before editing" analysis (`/preflight`), targeted tests, `zig build verify` and a
`contract-reviewer` pass. IDs are kept stable.

| ID | Verdict | Scope | Measured or estimated effect |
| --- | --- | --- | --- |
| P1 | Recommended, in phases | Test-only | Phase 1: about 44% of the unit run and 36% of the integration run (estimate from profile shares) |
| P2 | Defer until after P1 | Test and build | About 40 s ÷ shards after P1; needs gating |
| P3 | Low value; needs decision | Build | Three compiles per docs-only edit or commit, not six |
| P4 | Measure after P1 | Build and docs | Up to 1–1.5 min off the critical path; unmeasured |
| P5 | **Withdrawn** | | Would remove the only offline compile of the live configuration |
| P6 | Needs contract decision; low priority | Engine contract | Under 8% of the integration run |
| P7 | Recommended | Engine (shared helper) | About 6% of the integration run, plus production |
| P8 | User's call | Local cache | Working builds; up to 15 GB |
| P9 | Highest payoff for repeated runs; needs decision | Build and policy | No-op and docs-only reruns drop from at least 1 min to seconds |
| P10 | Needs contract decision | Engine | About 8% of the integration run, plus production |
| P11 | **Withdrawn** | | Would edit frozen protocol and live-case inputs |
| P12 | Candidate after P1 | Engine (canonical validator) | Part of the 7–12% JSON parsing share, plus production |

### P1. Untraced leak-checking allocator for the hot sweeps (T2, T12)

- **Change.** Add one shared test helper that wraps a `DebugAllocator` with
  `stack_trace_frames = 0` and fails the test when `deinit` or `detectLeaks` reports a
  leak. Use it in three places: the sweep's allocator binding, the driver's two arena
  backings, and as the backing allocator of the 107 allocation-failure sweeps.
- **Effect.** Stack-trace capture inside those scopes is 44.5% of the unit run and
  35.9% of the integration run. The remaining 28.3% of the unit run is spread across
  many tests. Replacing all 3,496 references (a second phase) would chase a long tail
  and isn't recommended without its own decision.
- **Conditions.**
  - Leak detection must move with the allocator (T2). A call site that skips the check
    silently loses leak detection, which would be a weakened check. One owning helper
    therefore beats per-site `DebugAllocator` code.
  - Add a regression test proving the helper fails on a deliberate leak and passes when
    the case frees everything.
  - Optionally, add an architecture check that rejects ad hoc `DebugAllocator`
    construction in test code.
  - Leak reports lose allocation stack traces. To diagnose a leak, temporarily switch
    the call site back to `std.testing.allocator`.
- **Rejected alternatives.**
  - A custom test runner with `allow_stack_tracing = false` or a `debug.SelfInfo`
    override would also strip symbols from failure traces.
  - Non-checking allocators would drop leak detection.

### P2. Shard the 177-scenario test (T1)

- **Change.** Several `Run` steps of the one compiled integration binary, each given a
  shard selector.
- **Gaps found in review.**
  - The test runner panics on any unrecognized argument
    (`lib/zig/compiler/test_runner.zig:52-62`). The selector would have to arrive
    through the environment (`Run.setEnvironmentVariable`, read via
    `std.testing.environ`).
  - Each shard `Run` step runs every test in the binary. Without gating, the other 128
    tests (about 20 s under the sampler, including the other seven sweep tests' 19
    scenarios) would run once per shard. That breaks the exactly-once rule that
    `test-build-registration` enforces ([build.zig:899](../build.zig#L899),
    [build/test_registration.zig](../build/test_registration.zig)).
  - So every test needs a shard owner, or the non-sweep tests must run in shard 0 only.
- **Conditions.**
  - Prove that the shards partition the scenario set exactly once.
  - Keep one `scenario-cost` report per shard.
  - Update the registration check.
- **Effect.** After P1 the integration run is estimated at about 40 s, so the remaining
  gain is about 40 s × (1 − 1/shards), plus memory for concurrent test processes
  (0.9–3 GB each). Separate test executables cost a full 2-minute compile each, so they
  aren't an alternative.

### P3. Drop provenance from the offline smoke variants (T8)

- **Review finding.** Only the three offline variants (e2e, compatibility, baseline) can
  lose provenance:
  - The live variants must embed it
    ([e2e.md:492-502](../design/harness/e2e.md#L492-L502)).
  - The live variants must keep compiling in `test` as the live-configuration check
    (T7, P5).
  - Docs-only edits and commits would therefore still recompile three executables, not
    zero.
- **Conditions.**
  - The harness code embeds `build_provenance` unconditionally, so offline variants
    still need some bytes, for example a fixed fixture bundle. That is a second
    embedding source, so it needs a decision. No fallback or dual path.
  - Offline binaries can't make model calls, so they can't produce evidence, but that
    has to stay true.
  - Keep the live-step isolation tests passing.

### P4. Reconsider `ReleaseSafe` for the integration suite (T6)

- **Change.** Measure Debug compile and run times for the integration module, after P1,
  since P1 removes the cost that Debug would otherwise amplify.
- **Conditions.**
  - The `ReleaseSafe` choice is documented ([README.md:82](../README.md#L82)) and
    deliberate (`b021e9b`). A change updates the README in the same commit.
  - `test-exact-value-admission` shares this module and changes with it.
- **Checked alternative.** The self-hosted backend isn't viable on this platform (T14).

### P5. Smoke-test only the offline variants — withdrawn (T7)

The unwrapped executables are the only offline compile of `live_model_connections =
true` code. Removing them would leave live-only code unchecked until a billed live run.
The cost is coverage, not waste.

### P6. Hold the feature-log lock and segment file across appends (T3)

- **Review finding.** §26 allows one lock held "while a writer is … appending", so
  holding it is compatible in principle. But:
  - §26.21 still requires identity checks at commit. A held descriptor needs a
    per-append identity check (path against descriptor), so part of the open cost
    returns.
  - The §13.9 per-event action sequence must change.
  - Retention and historical finalization share the lock.
- **Verdict.** A contract change with a saving under 8%. Low priority. Lowering the
  sweep's log level isn't an alternative: the sweep asserts on debug events.

### P7. A shared stable sort without the fixed buffer (T5)

- **Change.** Add one domain helper that replaces the 37 direct `std.mem.sort` calls.
  For example: insertion sort below a small threshold, and block sort, or sorting
  indices, above it.
- **Why output stays byte-identical.** Every stable sort produces the same order for
  the same strict weak ordering. Unstable sorts (`pdq`, `heap`) don't guarantee that,
  and are excluded.
- **Conditions.**
  - Add a property test that the helper matches `std.mem.sort` on inputs with ties.
  - Keep the canonical-rendering byte-identity tests.
  - Optionally, add an architecture check against direct `std.mem.sort` in `src/`.
- **Effect.** About 6% of the integration run and 1% of the unit run, plus production
  `ReleaseSafe` builds.

### P8. Repair the local cache (T9)

- **Change.** Clear only the Zig-owned directories: `o/`, `h/`, `z/`, `tmp/` and
  `fresh/`, which nothing in the repository refers to. Move the retained logs and
  experiment directories first if they matter.
- **Notes.** The tool that removed `o/` without `h/` couldn't be identified. The next
  build is fully cold.

### P9. Make test runs cacheable (T10)

- **Change.** Fix the seed and declare every runtime input.
- **Effect.** Directly measured: an unchanged-tree rerun spent 1m in a test run whose
  compile was cached. P9 would turn that, and the `repository-tests` run, into cache
  hits.
- **Gaps found in review.**
  - **Seed.** It comes from `zig build --seed`, or a new random seed per invocation.
    Every entry point (`scripts/test-integration.sh`, the `/verify` skill, manual runs)
    would have to pass it, or `build.zig` would need a supported way to pin it.
  - **Inputs.** `addFileInput` tracks files, not directory contents. `build.zig` would
    have to enumerate the trees that `architecture_test` walks, at configure time, so
    that adding a file changes the input set. It must also list every fixture, workflow
    and case file the tests read.
- **Conditions.**
  - Add negative tests: editing a runtime-read fixture reruns the suite, and adding an
    unimported file under `src/` reruns `architecture_test`.
  - Decide how the `/verify` report states cached runs: AGENTS.md says never claim a
    check ran when it didn't, and the commit rule asks for `verify` "on the exact tree".
  - Decision needed.

### P10. Derive bootstrap facts once (T11)

- **Change.** Validate the registry and compute the data-flow facts once, when the
  runner and specification state are built, and make the registry immutable by
  construction.
- **Review finding.** The unit test that tampers with a graph before the run expects
  failure before any prepare. A one-time check at runner start still meets that. Only a
  registry changed in the middle of a run would no longer be caught, so immutability
  has to replace the per-step check.
- **Conditions.** Engine change. The contract owner decides; keep every existing
  rejection test.

### P11. Turn off console output in fixtures — withdrawn (T13)

Every `"console": true` fixture is a frozen protocol input or a live-case
configuration. Editing them risks frozen-binding drift and changes live runs, for an
output-size problem that `scripts/test-integration.sh` already handles.

### P12. Single-pass strict JSON decoding (T15)

- **Change.** Enforce the strict wire rules during one typed parse, for example with
  `jsonParse` overrides or a validating token pass, instead of building a throwaway
  dynamic tree. The owner is [strict_json.zig](../src/domain/strict_json.zig).
- **Conditions.**
  - Every rejection must survive: empty document, byte limit, UTF-8, byte-order mark,
    depth, duplicate fields, unknown fields, quoted numbers, numeric enum tags and byte
    arrays.
  - Keep the existing accepted and rejected fixtures and add any that are missing.
  - This is the canonical validator, so it needs high scrutiny and a contract-reviewer
    pass.
- **Effect.** Part of the 7–12% JSON parsing share. P1 already removes the tracing part
  of the dynamic tree's allocations.

### Suggested order and expected combined effect

1. **P1 phase 1.** Test-only, with a measured scope.
2. **P9.** Decision first; the biggest gain for repeated runs.
3. **P4 measurement**, after P1.
4. **P7 and P12.** Shared owners, with a production benefit.
5. **P2,** only if the integration run still matters after 1–4.
6. **P3, P6 and P10** wait on their decisions.

Expected combined effect (estimates from profile shares, not measurements):

- **P1 phase 1:** about 25 s off the unit run and about 20–25 s off the integration run.
  `zig build test` and `test-integration` speed up by those amounts, and CPU use drops.
- **`verify` after a source edit:** only about 20–25 s faster, roughly 3.5 minutes
  instead of 4. The integration compile (120–179 s) still sets the critical path, so P4
  is the lever for `verify` wall time. P2 adds little once P1 is in.
- **P9:** an unchanged-input rerun drops to seconds, plus the provenance recompiles
  (T8).

## 5. Re-measuring

- **Scenario costs:** `./scripts/test-integration.sh` keeps the full log in
  `.zig-cache/test-integration.*`. Its `^scenario-cost` and `^scenario-total` lines give
  per-scenario phase times.
- **Cold timings:** run `zig build <step> --summary all --cache-dir <empty directory>`.
  This leaves the shared cache untouched.
- **No-op timings:** run the same command twice with no edits in between. Record
  `git rev-parse HEAD` and `git status --porcelain` before and after; a concurrent edit
  turns the second run into a rebuild (§2). Until P9 lands, test runs repeat regardless.
- **Profile:** find the test binary with `pgrep -f '/o/[0-9a-f]+/<name> --cache-dir'`,
  then run `sample <pid> 180 2 -mayDie -file <output>`.
  - Under `zig build test`, other small binaries are also named `test`. Profile the
    integration binary from `zig build test-integration` alone.
  - Confirm that the sample's call graph contains the expected `test.` frames.
  - Unsymbolicated hot addresses resolve with `nm -n <binary>`.
  - Aggregate inclusive samples by outermost `test.` frame to rank tests, and by
    ancestor frame (for example `checkAllAllocationFailures`) to size a proposal's
    scope.
- **Memory:** poll `memory_pressure -Q` and `sysctl vm.swapusage`, and diff `vm_stat`
  pageouts and swapouts across the run.
- **Comparing changes:** report wall time, CPU time, per-step compile and run times, and
  MaxRSS, for a cold build, a rebuild after a source edit, a rebuild after a
  documentation-only edit, and a no-op rerun.

## 6. Open uncertainty

- Each profile comes from one to three sampled runs. The sampler slowed them by about
  1.5 times; relative shares should hold, and repeated runs agree.
- Not measured directly: a complete no-op `verify`. The test-run rerun was measured for
  the integration suite (T10); the rest is inferred.
- Not measured: the integration module's Debug compile and run times (P4), and the
  actual savings from P1, P2, P7, P10 and P12. The figures in §4 are estimates from
  profile shares.
- Unresolved: whether per-step registry revalidation (T11) is an intended contract
  defence.
- Unattributed: the unit-test failure in the first `verify` run (§2), which happened
  while its file was being edited. The clean-tree run passed.

## 7. Review corrections

**First review**, same day:

- The `memset` share is 36.4%, not 32%; its caller counts were corrected.
- T7's memory-pressure claim was withdrawn; free memory stayed at or above 39% with no
  swap.
- T1 now records the scripted provider, the test driver, and the 177 of 196 scenarios
  in one test.
- T2 now explains the cost in every optimize mode and on this platform.
- T3 now cites its contract clauses.
- P2 now prefers sharding one binary.
- P8 no longer proposes deleting all of `.zig-cache`.
- The `0xAA` fill was confirmed by disassembly, and the month-old `repository-tests`
  sample was replaced.
- Added T10–T14 and P9–P11.

**Second review**, assessing the proposals:

- **T7 corrected.** The second compile uses a different comptime configuration and is
  the only offline compile of the live build, so it is coverage, not duplication.
- **P5 withdrawn** for the same reason.
- **T8 and P3 corrected.** Provenance coverage is contract-required, and P3 saves three
  compiles, not six.
- **T12 corrected.** The sweeps are 51.0% of the unit run by call stack, not 30.8% by
  name.
- **P1 rescoped.** Its expected effect was "up to about 70%" for a scope that covers
  44.5%. It now requires the replacement allocator to take over leak detection, with a
  regression test.
- **P2 gaps.** Selectors must come through the environment, and unsharded tests would
  run once per shard.
- **P9 gaps.** The seed must be pinned at every entry point, directory trees must be
  tracked, and cached runs must be reported honestly.
- **P6 constraints added** from §26 identity re-checks; lowering the sweep's log level
  was ruled out because the sweep asserts on debug events.
- **P7 condition added:** keep the sort stable; there are 37 call sites.
- **P10:** no contract clause requiring per-step revalidation was found.
- **P11 withdrawn:** its fixtures are frozen or live-case inputs.
- **Minute truncation.** Zig's summary truncates to whole minutes. The standalone
  integration compile was about 110 s, not 1 minute. The combined-effect estimate was
  also corrected: P1 shortens `verify` by about 20–25 s, not to 2.7 minutes.
- **Added:** T15 and P12 (strict JSON triple pass), the `/verify` pre-step and
  self-hosted-backend rows in T14, the clean-tree measurements, and the direct
  confirmation of T10.
