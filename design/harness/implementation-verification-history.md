# Harness implementation verification history

[Current backlog](README.md) · [E2E instructions](e2e.md) ·
[Supplied-spec evaluator](evaluator.md).

These are the recorded command results from the named implementation increments.
Test counts and then-open work describe those increments; they are not new
verification or evidence that unchecked acceptance criteria now pass. Live and
human-evaluation exclusions are retained with their original records.

## H-007 — Specification contract verification

Recorded targeted verification: `zig build test-specification-contract
test-rubric-evaluator test-typed-text --summary all` passed 76 tests (12 contract,
29 evaluator, 35 shared typed-text tests). `git diff --check` is clean.

Final combined verification: `zig build test-specification-contract
test-rubric-evaluator test-typed-text verify --summary all` passed all 853 test
executions and 93 build steps, including lint, architecture checks and native
engine/evaluator packaging smoke tests. No human or live API evaluation ran.

## H-008 — Required-authority verification

Verification: `zig build test-required-authority verify --summary all` passed
103/103 build steps and 927/927 test executions (83 in the targeted authority
suite), including lint, architecture checks and clean native-package smoke
tests. `git diff --check` passed. No live provider calls were made.

## H-009/H-010 — Offline verification (2026-09-07)

Offline verification (2026-09-07):

- `zig build test-model-candidate-json test-specification-generation test-reference-extraction test-reference-reconciliation test-structured-tokens --summary all`
  — 15/15 steps, 226/226 test executions passed.
- `zig build verify --summary all` — 104/104 steps, 889/889 tests passed,
  including architecture/lint and native packaging. The packaged generation
  definition/resources load from configured roots; absent credentials fail
  closed without a live call. Fake-provider tests execute generation, repair and
  the response-correction/exhaustion paths (24 scripted workflow scenarios).
- `git diff HEAD --check` — passed.

These checks do not grade business quality; that remains the LLM rubric
evaluator. They do not claim H-011/H-012 publication or H-013 completion.

## H-011/H-012 implementation checks

- `zig build test-specification-generation --global-cache-dir .zig-cache/global --summary all`
  — 52 tests passed (projection, exact/passive values and generation contracts).
- `zig build verify --global-cache-dir .zig-cache/global --summary all`
  — 104/104 steps and 898/898 tests passed, including lint, architecture and
  packaged execution checks. Two fake-provider knowledge-gap scenarios persist
  forms without a spec; filesystem tests exercise all three clarification stages.
- `git diff --check` — passed.

These checks verify the implemented increment, not all unchecked acceptance
criteria or live/human evaluation. H-011/H-012 remain partial.

## Evaluator — Offline verification (2026-09-06)

Recorded offline verification (2026-09-06):

- `zig build test-rubric-evaluator --summary all`: 29 tests passed, including
  capture of all seven calibration specimens without semantic prefiltering.
- `zig build verify --summary all`: 781 tests, lint and native smoke checks passed.
- `zig build evaluate-spec -- --help`: passed without an API call.
- `git diff --check`: clean. Local documentation links resolve; original stories
  and principle files are unchanged.
