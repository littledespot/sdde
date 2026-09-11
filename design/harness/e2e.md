# Single-case Spec E2E test

Run the checked-in Hello World case from the repository root:

```sh
./scripts/e2e-spec.sh
```

The executable script requires the repository-pinned Zig compiler on `PATH`
and calls the existing build step. It locates the checkout from its own path,
so invoking it by absolute path also works from another directory. With no
arguments it selects the Hello World case. Arguments are forwarded unchanged
to the harness, including `--help` or an explicit single case:

```sh
./scripts/e2e-spec.sh --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json
```

Case paths remain relative to the repository root. The script preserves the
harness output and exit status. The equivalent direct command is:

```sh
zig build e2e-spec -- --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json
```

One invocation selects one case, copies only its declared inputs into one
isolated project, and invokes the ordinary workflow once. The production
bootstrap, provider catalogue validation, workflow selection, YAML transitions,
runner, validators and filesystem adapters execute. The provider boundary uses
shared scripted candidate transport and fake authorization material. Each case
supplies an authored `specification-script/v1` response fixture with explicit
extraction observations selected by exact reference-chunk bytes. Missing or
duplicate source bindings reject; multiple files/chunks use the same mechanism. It supplies a separate
expected specification for output comparison. Neither file is copied into the
target project or used by the production engine. No network or credential access
occurs. The regression driver's scenario loop, selection stubs and step interception are not used.

The current definition has ID `spec-generation` and uses `specify-invocation`.
The case names that exact ID, supplies `--feature hello-world --reference
hello-world`, and copies the unmodified definition and each declared resource
under the configured workflow root. Source examples are explicit fixture
inputs, never runtime fallbacks. The two original source requirements and
seven semantic principle files are preserved. The minimal mechanical fixture
selects only the already-registered mandatory safety policy; Node/Vitest
implementation or command execution is not part of this Specify test.

Each invocation retains:

```text
zig-out/e2e-spec/<UTC-date-time>-<unique-id>/
  report.json
  report.md
  project/
    ...declared configuration, workflow resources and reference...
    specs/hello-world/spec.md  # only when the workflow writes it
```

The UTC timestamp uses `YYYY-MM-DDTHH-MM-SSZ`. A unique suffix separates runs
started in the same second. The reported specification path is derived from
validated configuration and the selected feature; the tree above describes
the Hello World fixture, not a hard-coded production destination.

The closed `spec-e2e-case/v1` contract declares one workflow ID, feature,
reference selector, config source, explicit file mappings, empty directories
and the expected specification, sidecar, clarification state and workflow state.
It also requires repository-relative `provider_script` and
`expected_specification` input paths. Both inputs are captured and checked for
source changes alongside the reference/configuration files.
Unknown/duplicate fields, unsafe paths, destination collisions and pre-seeded
feature outputs reject. Inputs are captured before execution and their source
bytes are checked again afterwards. No previous run directory is reused.

The E2E outcome is distinct from the YAML terminal outcome. Passing requires
`ok`, runner-observed workflow publication and readable, nonempty expected
files, plus a match to the independently authored expected business content.
The comparator checks the published document's canonical formatting and valid
identities, then compares all business fields and record order while allowing
monotonic ID ordinals to advance on reruns. Missing or changed content fails;
this is fixture conformance, not a second semantic judge. A candidate rendering,
existing file or model success assertion cannot meet that requirement. Failure,
cancellation, clarification and missing output produce a failing report and nonzero exit status; the harness never copies a
candidate out of the runner or invokes a renderer to manufacture `spec.md`.
The isolated project is retained for inspection, including any partial files
left by a failed production write under ADR 0009. Such files are not reported
as successfully generated output. A publication that fails content comparison
is reported as `content_mismatch`, with its current path retained for inspection.
Reports separately expose `publication_check`, `fixture_content_check` and
`semantic_quality`. The last is `not_evaluated` for this offline command; a
scripted `supported` observation never becomes an independent quality score.

## Current result

The Hello World invocation executes 17 scripted model calls, publishes through
the registered production writer and reports `passed` with exit status 0.
The successful YAML branch validates and prepares `spec.md`,
`reference-context.md`, `clarifications.json` and `workflow.json`. Canonical
state is written last and contains the accepted source snapshot, specification,
provenance, record-ID ledger, clarification revision and model-assisted review
evidence. A separate registered capture/parse step validates prior state before
generation; fresh reruns retain its ID counters and replace all registered views.

Regression tests also use an unrelated library reference, a renamed workflow
and a nested Unicode feature directory, with independently authored loan content
and a business entity spread across two reference files. They reject malformed
prior state before model invocation and exercise every registered publication write failure. The
H-012 feature-log integration and H-015 evaluator handoff remain separate work;
scripted publication does not establish semantic quality.

## Separate verification commands

- `zig build test-e2e-harness --summary all` tests case parsing, invocation
  selection, dated run isolation, fixture safety, publication/file checks and
  independent expected-content comparison.
- `zig build test` and `zig build verify` retain the independent engine
  regression suite and include harness mechanical tests. They do not run an
  implicitly selected E2E case or export regression scenarios for review.
- `zig build e2e-spec -- --case ...` performs the selected E2E invocation and
  reports its actual success/failure. Passing mechanical tests does not make
  this command pass.
- `zig build evaluate-spec -- ... --live` remains the separate supplied-spec
  evaluator described in [evaluator.md](evaluator.md). This E2E command performs
  neither a paid evaluation nor semantic quality scoring.

The former `zig-out/spec-review/.../case-*` artifacts were regression exports.
Their exporter and build step have been removed; those older files are not E2E
results and are not used by the new command.

## Template alignment verification (2026-09-11)

The amended format, shared completeness obligations, persisted-state checks,
authored provider fixtures and independent output comparison were verified with:

- `zig build test-specification-contract test-specification-generation test-required-authority test-e2e-harness lint --summary all`
  — 14/14 steps and 529/529 tests passed.
- `zig build test-e2e-harness --summary all`
  — 375/375 tests passed after extending the authored fixture to multiple
  reference chunks. The unrelated loan example uses two reference files.
- `zig build verify --summary all`
  — 114/114 steps and 1305/1305 tests passed, including architecture, lint,
  native engine packaging and standalone evaluator smoke checks.
- `zig build e2e-spec -- --case test/e2e/wf-001-hello-world/node-vitest/workflow.case.json`
  — passed with 17 scripted model calls; publication passed and independently
  authored business content matched. Retained output:
  `zig-out/e2e-spec/2026-09-10T23-08-29Z-8de09c00ec0fd9935e0a96d326b6f4ad/project/specs/hello-world/spec.md`.
- `git diff --check` — passed.

Regression evidence includes all 128 optional-section combinations, exact code
spans containing criterion labels, malformed/missing mandatory structure,
positive model findings unable to override mandatory-content gaps, unsupported
scenario coverage, tampered persisted content, source/script mismatch, and a
successful publication failing its independent expected-content check. These
are mechanical and scripted checks; live generation and semantic rubric quality
were not evaluated.

## Prior publication increment verification (2026-09-10)

- `zig build test-e2e-harness test-specification-generation --summary all`
  — 425/425 tests passed, including native publication, rerun and rejection cases.
- `zig build verify --summary all` — 114/114 steps and 1299/1299 tests passed,
  including lint, architecture and packaged-executable smoke checks.
- `./scripts/e2e-spec.sh` — exited 0 with `E2E result: passed`; one invocation
  and 17 scripted model calls. Report:
  `zig-out/e2e-spec/2026-09-10T21-51-07Z-53b6b95c460f6bdd78171653ac51e928/report.md`.
- `git diff --check` — passed.

These results establish scripted production publication. They do not establish
semantic quality of generated content or live provider/evaluator acceptance.
