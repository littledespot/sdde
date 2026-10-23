# Offline test performance

**Measured:** 24 October 2026, Australia/Melbourne. Apple M4 (10 cores, 24 GB),
macOS 27.0, Zig 0.16.0. **Reviewed:** the same day. The review added findings T10–T14
and proposals P9–P11, and corrected the `memset` share, T1, T3, T7, P2 and P8 (§7).

**Status:** investigation note, not an active fix record. [FIX05](FIX05.md) remains the
sole active fix record ([README](README.md)). This note holds findings and proposals only.
It authorizes no code, build or test change.

**Evidence:**

- **Integration run.** One cold `zig build test-integration --summary all`, run against
  an empty scratch `--cache-dir`. It used the working tree later committed as `1a683aa`.
  A macOS `sample` profile of the test binary was taken every 2 ms, and the run's
  `scenario-cost` lines were kept.
- **Full verification.** Two consecutive `zig build verify --summary all` runs, each
  against a scratch cache. The `repository-tests` binary was sampled in both. Memory
  was recorded with `memory_pressure`, `vm_stat` and `vm.swapusage`. Both runs used an
  uncommitted working tree that was being edited at the time (§2).
- **Retained logs under `.zig-cache/`.** `test-integration.*` (9–22 October),
  `global-token-verify.log`, `b4b9-complete-verify.log` and `b4b9-commit-verify.log`.
  These are git-ignored local files and are not kept anywhere else.
- **Source and disassembly.** Reading the Zig 0.16 standard library, and disassembling
  the `ReleaseSafe` integration binary.

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
   to the test binaries, so both one-minute test runs repeat every time, even when
   nothing changed (T10).
3. **The testing allocator dominates both runs.** It captures a 10-frame stack trace
   by DWARF unwinding on every allocation, resize and free. That is **73% of
   `repository-tests`** and **36% of the integration run** (T2). Exhaustive
   allocation-failure sweeps (T12) and the 196-scenario Spec sweep (T1) multiply it.

Average CPU use during `verify` is only about 2.4 of 10 cores. Wall time is set by a
serial chain, not by machine capacity, and memory isn't the limit (T7).

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
isn't attributed to anything and isn't a performance finding.

Step costs inside `verify`. Parallel contention makes every compile slower than when
it runs alone.

| Step | Time | MaxRSS |
| --- | --- | --- |
| Integration test compile (`ReleaseSafe`) | 2m (1m alone) | 4 GB |
| Integration test run | 1m | 3 GB |
| `repository-tests` compile | 48–52 s (35 s in older logs) | 3 GB |
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

### Integration run, standalone and cold

| Measure | Value |
| --- | --- |
| Wall time | 222 s (190.9 s user, 21.1 s sys) |
| Test binary started | after 116 s |
| Compile (`ReleaseSafe`) | `1m`, MaxRSS 5 GB |
| Run | `1m`, MaxRSS 2 GB, 129/129 passed; 87 s under the sampler (43,357 samples) |

Retained runs agree: 9 October, 84 tests in 51–54 s; 18 and 21 October, 127 tests in
`1m` at about 3 GB.

### Where the integration run spends its time

| Inclusive share | Frames |
| --- | --- |
| 89.4% | `testSpecificationWorkflows` |
| 75.3% | `workflow_engine_orchestrator.run` (execution) |
| 36.4% | Stack-trace capture (`debug.SelfUnwinder`, `debug.Dwarf.*`, `StackIterator`) |
| 16.9% | Feature-log persistence (`persistEventBinding`, `LogService.process`) |
| 15.8% | Filesystem syscalls; `openat` alone 10.6%, `fsync` 0.3% |
| 15.6% | `runInProjectWithRegistry` (bootstrap) |
| 13.3% | Workflow compilation and validation (`workflow_subgraphs.Compiler`, `Registry.validate`, `workflow_data_flow.analyze`) |
| 10.8% | JSON parsing |
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

From the sampled `verify` runs; the two runs agree to within 1.2 points.

| Inclusive share | Frames or tests |
| --- | --- |
| 72.7–73.9% | Stack-trace capture |
| 11.7% | JSON parsing |
| 30.8% | 24 allocation-failure sweep tests (T12) |
| 53.8% | The 10 most expensive tests |
| 12.8% | `composition application handoffs release retained parts and requests at every allocation failure` |
| 10.4% | `reconciliation assignments scope instructions while retaining complete source evidence` |
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
seven tests share the remaining 19.

### Retained `verify` logs

- **Cold** (`global-token-verify.log`):
  - integration test: compile 1m at 4 GB, run 1m;
  - `repository-tests`: compile 35 s, run 1m;
  - engine-sized executables: 13–17 s each, two compiles each.
- **Warm, after a commit** (`b4b9-commit-verify.log`): every step was cached except
  `sdde-e2e-spec` (16 s, 15 s) and `sdde-provider-compatibility` (15 s, 14 s). The two
  test runs still took 1m each (T10).

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
process, so scenarios never overlap. T2–T5 and T11 are the costs inside each scenario.

### T2. The testing allocator captures a stack trace on every allocation

`std.testing.allocator` is a `DebugAllocator` configured with `stack_trace_frames = 10`
and `resize_stack_traces = true` (`lib/zig/std/testing.zig:22`). That setting is fixed,
not tied to the optimize mode. So every allocation, resize and free captures a 10-frame
trace, in Debug and `ReleaseSafe` alike.

On aarch64 Darwin, Zig 0.16 rates frame-pointer unwinding `.safe` but not `.ideal`
(`StackIterator.fp_usability` in `lib/zig/std/debug.zig`). So it always unwinds through
DWARF debug data when that data is present, and uses frame pointers only as a fallback.
The result is 73% of `repository-tests` and 36% of the integration run. Moving the
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
negligible. Scenarios log at debug level.

The per-event cycle is contract behaviour, not an adapter detail:

- The §13.9 catalogue defines `AcquireFeatureLogStreamLockAction` as one attempt with a
  fixed deadline, and requires every lock to be released on every path
  ([13-09-logging.md:14-41](../design/contracts/actions/13-09-logging.md#L14-L41)).
- Retention ([ADR 0026](../design/decisions/0026-header-identity-log-retention.md)) and
  historical finalization
  ([14-orchestration.md:302](../design/contracts/14-orchestration.md#L302)) take the same
  per-run stream lock.

### T4. Every scenario bootstraps the engine again

Each scenario reads configuration, enumerates and captures workflow resources, and
compiles and validates the workflow registry. That takes about 55 ms per scenario,
10.8 s across the sweep. This is the production path the tests exist to exercise.

### T5. `std.sort.block` fills a 512-element buffer on every call

`std.sort.block` declares `var cache: [512]T = undefined;`
(`lib/zig/std/sort/block.zig:116`). Safety-checked builds fill `undefined` memory with
`0xAA`. That is confirmed for `ReleaseSafe`: the integration binary's `sort.block`
contains `mov w1, #0xaa` followed by `bl _compiler_rt.memset`. So every call writes
512 × `@sizeOf(T)` bytes, however short the input.

The heavy callers are `workflow_subgraphs.Compiler.scope` (recursive),
`canonical_json.write` and `required_authority.build`. This is 6.4% of the integration
run and 0.9% of `repository-tests`.

### T6. The integration suite compiles in `ReleaseSafe`, at the start of the critical path

[build.zig:348](../build.zig#L348) compiles the root integration module, meaning the
engine and tests imported by relative path, in `ReleaseSafe`. That takes 1 minute alone
and 2 minutes inside `verify`, at 4–5 GB. With the run that follows, the integration
chain is about 3 of the 4 minutes `verify` takes after an edit. The `repository-tests`
chain is shorter: a 48–52 s compile, then a 1-minute run.

The dependency modules (`yaml`, `bounded_yaml_syntax`, `unicode_normalization`,
`exact_value_unicode`) still compile in Debug, because they take the default optimize
mode.

Not measured: how long this module takes to compile and run in Debug.

### T7. Each offline harness executable is compiled twice

`offlineExecutable` ([build.zig:916](../build.zig#L916)) wraps an application as a new
root module. That is a second full compile of the same code. It applies to `sdde`,
`sdde-e2e-spec`, `sdde-provider-compatibility`, `sdde-baseline`, `sdde-e2e-call` and
`sdde-evaluate-spec`. The smoke steps also depend on the unwrapped executables
([build.zig:331](../build.zig#L331), [build.zig:415](../build.zig#L415),
[build.zig:447](../build.zig#L447)), so both variants are always built. In `verify`,
the four engine-sized pairs cost 17–27 s per compile.

These compiles cost CPU and memory but sit off the critical path (T6), and memory is
not the bottleneck. Free memory stayed at or above 39% with no swap, so the earlier
claim that they push the machine into memory pressure was wrong.

### T8. Build provenance invalidates harness compiles after any edit

`capture-build-provenance` ([build/provenance.zig](../build/provenance.zig)) hashes the
contents of `src`, `test`, `design`, `scripts` and the root build files. Its step runs
on every build (`has_side_effects`, [build.zig:255](../build.zig#L255)). The output is
embedded through `@embedFile("build_provenance")` in the e2e, compatibility and
baseline harnesses.

The comment at [build.zig:257](../build.zig#L257) says offline builds must not be
invalidated by provenance. But `test` and `smoke` depend on those executables through
their smoke steps ([build.zig:427](../build.zig#L427),
[build.zig:450](../build.zig#L450), [build.zig:847](../build.zig#L847)). So any edit to
`design/`, or any commit, recompiles six executables at about 15–27 s and 1–2 GB each.
`b4b9-commit-verify.log` shows exactly this: nothing else in that run recompiled.

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
happened before.

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
even when compiles are cached. The 21 October log shows this: compile `cached 59ms`,
run `1m`. A no-op `verify` therefore costs at least about one minute.

No test uses `std.testing.random_seed`. The one PRNG in the test harness uses a fixed
protocol seed. So the random seed buys these suites nothing.

A fixed seed alone would make the cache unsafe, though:

- 14 run steps set their working directory to the repository root.
- Tests read repository files at runtime, including
  `design/workflows/spec.workflow.yaml`, the `test/e2e/*` cases, the
  `test/integration/fixtures/baseline/*` files and the `src/actions` and
  `src/application` trees.
- None of those files is declared with `addFileInput`, so a cached run could pass
  against stale inputs.

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

Both costs apply to production runs too. Much of the 9% `mem.eqlBytes` self time comes
from linear, string-keyed lookups in these validators, in bootstrap compilation and in
`findTransition`.

### T12. Allocation-failure sweeps are quadratic, and every allocation is traced

`std.testing.checkAllAllocationFailures` runs a case once to count its allocations,
then once more for each allocation with a failure injected at that index. The
repository has 109 such sweeps. The 24 that appear in the profile account for 30.8% of
the `repository-tests` run, and the most expensive single sweep for 12.8%. Each pass
allocates through the 10-frame tracing allocator (T2).

The four integration cancellation sweeps have the same shape but cost only 1.2%.

### T13. Fixture configs mirror every log event to stderr

Fixture configs with `"console": true` route every emitted event row to stderr through
the console sink:

- `test/integration/fixtures/baseline/*.sddtoolkit.json`;
- `test/e2e/wf-001-hello-world/.sddtoolkit.json`.

The sink is [log_output.zig](../src/adapters/system/log_output.zig), called from
[feature_log_runner.zig:231](../src/application/feature_log_runner.zig#L231) and
[:337](../src/application/feature_log_runner.zig#L337). Each integration or `verify`
run therefore prints about 7,800 rows, 8–9 MB, even when every test passes. No stderr
writes show up in the profile, so the cost is output size, not time. It is why
`scripts/test-integration.sh` redirects the full log to a file.

### T14. Checked and not material

| Step | Cost |
| --- | --- |
| Lint | 0.4 s |
| Packaged smoke runs | 27–473 ms each |
| Launcher shell tests | 0.1–0.5 s each; they use a fake `zig` |
| Provenance capture | 1 s |
| Nested `zig build` fixtures | 4–5 s cold |
| `architecture_test` | 0.7% of the unit run |
| Temporary-directory cleanup | 1% of the integration run |
| `fsync` | 0.3% of the integration run |

None of these is worth pursuing.

## 4. Proposals

None may drop scenarios, skip or focus tests, weaken assertions or relax leak
detection (AGENTS.md, Prohibited shortcuts). IDs are kept stable; the suggested order
follows the table.

| ID | Proposal | Addresses | Expected effect | Constraint or decision needed |
| --- | --- | --- | --- | --- |
| P1 | Use a `DebugAllocator` with `stack_trace_frames = 0` instead of `std.testing.allocator`. Start with the sweep's binding and its driver arenas, and the backing allocators of the 107 allocation-failure sweeps. | T2, T12 | Up to about 70% of `repository-tests` and about a third of the integration run. The sweep change is a few lines; the allocation-failure sweeps are 107 one-argument changes. | Leak and double-free detection stay; leak reports lose allocation stack traces. The user decides whether that trade is acceptable. A custom test runner that disables tracing globally (`allow_stack_tracing = false`, or a `debug.SelfInfo` override) would also strip symbols from failure traces, so it is the weaker option. |
| P2 | Shard the 177-scenario test inside one compiled integration binary: several `Run` steps of the same artifact, each given a shard selector. | T1 | The integration run's wall time divided by the shard count; cores are mostly idle (§1). No extra compile. | Splitting into separate test executables costs a full compile each (2 minutes and 4 GB inside `verify`). Splitting by test doesn't help, because one test holds 177 of the 196 scenarios. The selector is a new test input and needs a decision. Update the full-suite registration check ([build.zig:899](../build.zig#L899), [build/test_registration.zig](../build/test_registration.zig)) and keep `test-integration` complete. |
| P3 | Remove the provenance dependency from the offline smoke executables. Only the live steps need the checkout identity. | T8 | Six compiles (15–27 s and 1–2 GB each, partly in parallel) saved on each docs-only edit or commit. | Build provenance is harness evidence. Choosing how offline smoke binaries satisfy `@embedFile("build_provenance")` is a decision. No fallback or dual path. Keep live-step isolation tests passing. |
| P4 | Measure the integration module's compile and run time in Debug. If the compile is much faster, reconsider `ReleaseSafe` after P1. | T6 | Up to about 1–1.5 minutes off the critical path after every source edit. | Unmeasured. The Debug run may be slower; decide on both numbers. |
| P5 | Avoid compiling each smoke application twice, for example by smoke-testing only the offline variant. | T7 | Fewer compiles and less CPU. Off the critical path, so little wall-time gain. | `smoke-*` steps currently prove both variants build. Decide whether building the unwrapped executable is a required check. |
| P6 | Hold the feature-log stream lock and segment file across appends within a binding. | T3 | Up to about 8% of the integration run, plus a production benefit. | This changes the §13.9 per-event action sequence and the lock that ADR 0026 retention and §14 historical finalization rely on. It needs a contract decision, a `/preflight` analysis, and failure and recovery tests. Not a test-only change. |
| P7 | Replace the stable sort in hot paths with one that doesn't fill a fixed 512-element buffer, or sort indices instead of large values. | T5 | About 6% of the integration run. | Order must stay byte-identical (canonical JSON, deterministic rendering). |
| P8 | Clear the Zig-owned cache directories (`o/`, `h/`, `z/`, `tmp/` and `fresh/`), and find out which tool removed `o/` without `h/`. | T9 | Restores working builds; reclaims up to 15 GB. | Don't delete the whole of `.zig-cache`: it holds retained logs and experiment directories (T9). Move them first if they matter. The next build is fully cold. |
| P9 | Make test runs cacheable: pass a fixed `--seed`, and declare every file the tests read at runtime with `addFileInput`, or embed those files. | T10 | Unchanged test runs become cache hits. A no-op or docs-only `verify` drops from about 1 minute or more to seconds. | Incomplete input declarations give stale passes, so this needs a test proving that editing a runtime-read file reruns the suite. It also changes what "ran `verify` on the exact tree" means for the commit rule in AGENTS.md. Decision needed. |
| P10 | Validate the operation registry and derive the data-flow facts once, when the runner and specification state are built, and make the registry immutable by construction. | T11 | About 8% of the integration run, plus a production benefit. | Engine change. Per-step revalidation may be an intended defence against registries changed after bootstrap, and tests rely on that rejection. The contract owner decides whether a one-time check plus immutability gives the same guarantee. |
| P11 | Turn console output off in test fixtures that don't assert on it. | T13 | Smaller logs and readable `verify` output; no measurable time. | Keep `"console": true` wherever a test checks console behaviour. Fixtures under `test/e2e/` are live-case inputs, so change them only with the case owner's agreement. |

**Suggested order:**

1. **P1:** the largest saving, with a test-only scope.
2. **P9 and P3:** they remove the reruns that happen when nothing relevant changed.
3. **P2, then P4:** they shorten the critical path.
4. **P6, P7 and P10:** engine changes, each needing its owning contract.

T4 is intentional coverage of the production path, so no proposal targets it.

## 5. Re-measuring

- **Scenario costs:** `./scripts/test-integration.sh` keeps the full log in
  `.zig-cache/test-integration.*`. Its `^scenario-cost` and `^scenario-total` lines give
  per-scenario phase times.
- **Cold timings:** run `zig build <step> --summary all --cache-dir <empty directory>`.
  This leaves the shared cache untouched.
- **No-op timings:** run the same command twice with no edits in between. Check that
  `git status` and file modification times didn't change; a concurrent edit turns the
  second run into a rebuild (§2). Until P9 lands, test runs repeat regardless.
- **Profile:** while the step runs, find the test binary with
  `pgrep -f '/o/[0-9a-f]+/(test|repository-tests) --cache-dir'`, then run
  `sample <pid> 150 2 -mayDie -file <output>`. Unsymbolicated hot addresses resolve with
  `nm -n <binary>`; in this run the top one was `memset`. Aggregate inclusive samples
  by outermost `test.` frame to rank tests.
- **Memory:** poll `memory_pressure -Q` and `sysctl vm.swapusage`, and diff `vm_stat`
  pageouts and swapouts across the run.
- **Comparing changes:** report wall time, CPU time, per-step compile and run times, and
  MaxRSS, for a cold build, a rebuild after a source edit, a rebuild after a
  documentation-only edit, and a no-op rerun.

## 6. Open uncertainty

- Each profile comes from one or two sampled runs. The sampler slowed them by about
  1.5 times; relative shares should hold, and the two `repository-tests` runs agree.
- Not measured directly: a true no-op `verify`. The roughly one-minute floor comes from
  retained logs and the `Run.zig` seed handling.
- Not measured: the integration module's Debug compile and run times (P4), and the
  saving from P1 and P2.
- Unresolved: whether per-step registry revalidation (T11) is a contract requirement.
- Unattributed: the unit-test failure in the first `verify` run (§2), which happened
  while its file was being edited.

## 7. Review corrections

Changes to the first version of this note, made the same day:

- The `memset` share is 36.4%, not 32%; its caller counts were corrected. The first
  count included one address outside `memset`.
- T7 claimed the parallel compiles pushed the machine into memory pressure. Measurement
  showed free memory at or above 39% and no swap.
- T1 now says that execution uses a scripted provider and a test driver, and that one
  test holds 177 of the 196 scenarios.
- T2 now explains why the cost appears in every optimize mode and on this platform, and
  sizes the change. Its frame-pointer question was resolved.
- T3 now cites the contract clauses that make the per-event lock a contract matter.
- P2 now prefers sharding one binary, since separate executables each cost a 2-minute
  compile.
- P8 no longer proposes deleting all of `.zig-cache`, which holds retained evidence.
- The `0xAA` fill is confirmed by disassembly instead of inferred.
- The month-old `repository-tests` sample was replaced by two fresh profiles.
- Added: T10 (test runs never cached), T11 (bootstrap facts re-derived during
  execution), T12 (quadratic allocation-failure sweeps), T13 (console mirroring) and
  T14 (items checked and found immaterial), with P9–P11.
