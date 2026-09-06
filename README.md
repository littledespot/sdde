# SDDE

SDDE is being developed as a deterministic native Zig executable and generic
declarative workflow engine. Its accepted runtime direction is to load any
bounded set of validated workflow definitions from the configured
`paths.workflows` root, capture only their declared resources, compile graphs
through one registry of generic operations, and execute one selected workflow
by its compiled transitions. `specify`, `plan`, `tasks`, and `implement` are
the initial workflow suite, not a fixed engine registry.

The accepted execution contract is [one atomic workflow from beginning to
end](design/decisions/0009-atomic-workflow-execution.md). Non-success abandons
its candidate output; a new invocation starts at `start`. There are no
project/feature transactions, provider-effect journals or saved continuations.
Clarifications and relevant answers survive without duplication.

[Provider APIs own model-call size limits](design/decisions/0011-provider-owned-request-limits.md).
SDDE adds no request/response byte ceilings or size-estimation gates. It records
actual API input/output token usage against the workflow execution's total
budget and stops subsequent calls at or above that budget. The legacy capacity
types, size parameters and static-capacity action have been removed.

Bootstrap loads the exact `.sddtoolkit.json` in the invocation working
directory, validates configured roots, compiles all concise `workflow/v1`
definitions, and publishes the immutable workflow registry before selection.
Provider configuration is read only after selection when the compiled graph
requires model binding or provider calls. Pure preparation steps receive only
immutable binding data; provider calls require a separate policy-permitted port.
[Workflow-owned requests](design/decisions/0012-workflow-owned-model-request.md)
now have native YAML initialization, assignment, binding-validation and building
operations. One request retains its originating slot/resources across steps;
generic preparation needs no SDD feature or task. Native inference, observation
validation, JSON decoding and payload-schema validation are YAML-callable;
Bedrock remains separate work.

YAML, the registry and runner use [unversioned operation IDs](design/decisions/0005-workflow-defined-operations.md#unversioned-operation-ids-accepted-2026-09-06).
Each ID selects one current contract; version suffixes are rejected without aliases.

`advance-model-attempt-accounting` now accounts that prepared request through
the same YAML runner. Its explicit `retry-limit` permits retries after the
initial execution; applied attempt evidence and ledgers remain execution-local.
`assign-provider-operation` then explicitly selects `inference` or
`input-token-count` and publishes sealed assignment evidence for that attempt.
Assignment makes no API call, prepares no authorization and charges no tokens.
`prepare-provider-operation-authorization` explicitly prepares the assigned
operation's single-use lease, with a required `timeout-ms` and the separate
`provider-authorization` capability. Preparation uses only a preloaded port;
it performs no I/O, refresh, provider call or token charge. The runner owns
lease cleanup; YAML receives only an opaque result. Bedrock composition remains
separate, and an unbound authorization adapter fails closed.
`advance-model-request-lifecycle` with `transition: invoked` then explicitly
advances the logical request through its existing immutable ledger. It requires
that same prepared authorization and changes no request content, attempt, lease
or provider-operation state. No API call occurs in this step.
`advance-provider-operation-lifecycle` with `transition: invoked` advances the
assigned operation next. It retains the prepared lease's original deadline;
only the runner publishes sealed invoked-operation evidence and removes the
assignment evidence. It does not consume the lease, call an API or charge tokens.

`invoke-model` makes one provider call using that retained request and lease,
with no repeated parameters. The runner accounts actual input/output usage
before publishing the untrusted result, including stopped output. Budget
overshoots retain the full usage, return `WorkflowTokenBudgetExceeded` and block
later calls. Failures and cancellation remain distinct; no counting, retry,
response decoding or lifecycle terminalization is implicit. The native binding
is fake-provider tested and fails closed until a real adapter is bound.

`count-model-input-tokens` and `validate-model-token-count-observation` are
parameter-free YAML bindings of the existing actions. Their typed results retain
the original request/binding owners. `complete-count-operation` terminalizes the
exact invoked operation from validated count/failure/cancellation evidence;
`complete-count-request` closes the logical request only after count failure or
cancellation and only when every associated operation is terminal. Successful
counting does not accept a request or authorize inference. Missing, foreign,
stale or reused completion evidence rejects. These operations reuse the existing
ledgers, single-use lease cleanup and explicit YAML retry rules; they add no
capacity gate or token charge. Actual inference-usage accounting remains mandatory.

`validate-provider-invocation-observation` checks the retained response against
the exact call using the existing association, usage and UTF-8 validator. It has
no parameters, provider capability or token charge. Its owned result preserves
complete, stopped, failed and cancelled outcomes; only validated complete
observations expose decoder input. This is not JSON or payload-schema validation.

`decode-model-envelope` parses only that complete branch using the existing strict
JSON decoder. It retains the original evidence with its owned parse tree and
returns `invalid` for malformed JSON; stops, failures and cancellation stay
unchanged. The inference profile permits `end.invalid`, without converting it
to failure or success. No schema check, provider call, retry or token charge is
implicit, and the operation has no parameters.

`validate-model-payload-schema` checks decoded candidates against only their
original request's compiled result schema. Its parameter-free result retains the
candidate and publishes valid evidence or typed schema rejection. Protocol errors,
provider stops/failures and cancellation pass through unchanged. It neither
reparses nor charges tokens; schema validity grants no semantic or commit authority.

`complete-provider-operation` explicitly closes an invoked inference operation
using its validated provider observation. It takes no parameters and retains
completed, stopped, failed or cancelled facts in the existing in-memory ledger.
Only the runner publishes terminal evidence and removes the old invocation
evidence; response values and token usage stay unchanged. Provider completion
does not accept the payload or complete the logical request/workflow.

`complete-model-request` explicitly closes an invoked logical request using its
retained payload-validation result and terminal provider-operation evidence.
It has no parameters and requires every associated operation to be terminal.
Schema-valid candidates close as request `accepted`; content rejection and
provider stops/failures close as `failed`; cancellation closes as `cancelled`.
Content rejection keeps its `invalid` YAML outcome and original diagnostics.
Request acceptance grants no semantic, approval, commit or workflow-success
authority. Ownership and token usage stay unchanged.

`terminate-provider-operation` closes an assigned operation from its retained
authorization result: failure becomes `preparation_failed`, and cancellation
becomes `cancelled(not_sent)`. It takes no parameters, rejects prepared or
missing/foreign/stale evidence, and uses the same terminal ledger publication
and lease cleanup. It makes no provider call, charges no tokens and leaves the
logical request unchanged.

`terminate-model-request` then explicitly closes that logical request using the
matching terminal operation and retained authorization result. Authorization
failure closes an assigned request as `not_invoked_authorization_failure` or an
invoked request as `failed`; cancellation closes either as `cancelled`.
It is parameter-free and requires every associated operation to be terminal.
Prepared, missing, foreign, stale, duplicate or inconsistent evidence rejects.
The existing lifecycle action and runner publish only the request-ledger successor;
retained evidence, lease cleanup and token usage stay unchanged.

## Requirements

- Zig 0.16.0 exactly

## Commands

```sh
zig build
zig build run
zig build lint
zig build test
zig build test-atomic-execution
zig build test-model-result-schema
zig build test-count-model-input-tokens
zig build test-reference-preflight
zig build test-reference-ingestion
zig build test-reference-evidence
zig build test-reference-extraction
zig build test-reference-reconciliation
zig build test-structured-tokens
zig build test-path-tokens
zig build test-typed-text
zig build test-feature-directory
zig build test-clarification-inputs
zig build test-rubric-evaluator
zig build build-rubric-evaluator
zig build smoke-rubric-evaluator
zig build evaluate-spec -- --help
zig build smoke
zig build verify
```

`zig build lint` uses the pinned Zig compiler to check formatting and AST
validity for the repository's Zig and ZON sources. `zig build verify` runs that
lint step and the unit tests, then copies the built executable into a clean
temporary directory, clears its environment, and verifies its exact standard
output. The temporary package directory is removed by the Zig build runner
after a successful build.

The development-only [rubric evaluator](design/harness/evaluator.md) grades a
supplied specification through OpenAI using the checked-in Hello World rubric
or another closed case/rubric. It writes evidence-backed JSON/Markdown reports
without running Specify or changing workflow authority. Live calls require
explicit settings, `OPENAI_API_KEY` and `--live`; ordinary tests/verification
remain offline. The rubric is an uncalibrated draft and live API acceptance has
not yet been demonstrated. This executable is not installed with `sdde`.

Concrete domain operations and the full initial SDD workflow suite remain
incremental work under `design/design.md` and their feature contracts.

Specify's registered invocation requires `--feature <directory> --reference <selector>`.
The read-only preflight resolves the feature beneath `.sddtoolkit.json`'s
`paths.specs`, independently of its reference source: `--feature hello-world`
selects `<paths.specs>/hello-world/`
([ADR 0010](design/decisions/0010-explicit-feature-directory.md)). Shared path
validation rejects traversal, archive targets and filesystem aliases/symlinks.
Missing targets remain absent; no ownership registry or generated-name operation
exists. YAML-selected feature-input preparation also resolves fixed artifact
paths and reads bounded clarification state/forms. It preserves closed files,
rejects stale/malformed submissions, and distinguishes submitted from recorded
answers without accepting either as current authority. See
[F0100's input contract](design/features/F0100-SpecWorkflow.md#32-read-only-artifact-and-clarification-inputs).
Reference preparation now captures Markdown once, accounts every source, assigns
reference identities and builds source-mapped extraction chunks. Citation checks
reject foreign states/IDs, out-of-chunk spans and altered quotations against the
captured bytes. The [ingestion YAML fixture](src/test_fixtures/reference-ingestion.workflow.yaml)
tests these read-only preparation steps; it is not an additional required user
workflow. Native extraction-result parsing, citation-backed candidate validation,
engine-assigned claim/citation IDs and complete chunk accounting are also tested
through YAML with scripted results. Hierarchical reconciliation now preserves
claim membership, validates dispositions and signal/conflict joins, assigns
engine IDs and blocks unresolved conflicts. Live model extraction/reconciliation,
semantic review and snapshot publication remain future work. See
[F0100](design/features/F0100-SpecWorkflow.md#35-extraction-candidate-accounting).
Registered toolchain naming rules now feed a shared, YAML-addressable path-token
grammar and detector, including current reference basenames. Source-backed
display IDs and shared typed-text validation now gate extraction candidates;
raw-string extraction text is rejected. These are read-only, execution-local
values, not file authority or semantic proof. See
[F0100's text contract](design/features/F0100-SpecWorkflow.md#37-typed-reference-text-and-source-backed-display-literals).
Markdown inline-code spans now become source-backed exact-value candidates;
prose, quoted text and fenced code do not qualify through that extractor.
Scripted `preserve`/`irrelevant` classifications are complete and chunk-scoped.
Preserved bytes bypass NFC and enter the existing claim/citation ledger with
engine-assigned token and obligation identities. No new persisted registry or
prompt is added. See [F0100's preservation contract](design/features/F0100-SpecWorkflow.md#38-exact-value-preservation).
Full `spec.md` generation remains unfinished. Shared NFC uses statically
linked utf8proc with packaged license notices
([ADR 0007](design/decisions/0007-unicode-normalization.md)).

Transaction-ID modules, provider journal projections, and logging transaction
stabilization/events have been removed under ADR 0009. Provider lifecycle and
authorization remain in memory for one execution. Only the root `features/`
directory is reserved during workflow discovery. Rerun output replacement and protected
clarifications follow Design Sections 25 and 23.2.
