# ADR 0012: Retain one workflow-owned model request across YAML steps

- **Status:** Accepted
- **Date:** 2026-09-05
- **Decision authority:** Explicit user direction
- **Amends:** Design Sections 7.3 and 12, ADRs 0004/0005, and F0005/F0006

## Decision

A generic request belongs to its current execution, originating compiled YAML
step and request ordinal. It does not require a fabricated SDD feature, section
or task. Existing SDD owner variants and purpose validation remain required by
operations that use those domain authorities; generic ownership cannot stand
in for semantic-review, repair or clarification authority.

The originating step declares the repository slot, response controls, prompt,
result schema and optional input resource once. Separate registered identity,
binding-validation and request-building operations exchange immutable typed
pipeline values. Consumers retain the originating request identity, binding,
resources and content; they do not rebind to their own step or repeat selection
parameters. The existing data-dependency compiler proves the required handoff.
There is no new route registry, implicit graph or YAML transport syntax.
The internal request content contract is `model-request/v1`; it is not a second
YAML schema resource. Prompt content and the result schema remain explicitly
workflow-selected, never packaged defaults.

Only a typed slot selects a new model binding. A registered consumer of the
prepared-request data contract can use its retained binding instead. Provider
capabilities still derive from narrow ports, require policy permission and do
not follow merely from access to immutable request data. A consumer cannot also
select another slot, resource or response control for that request.

Request-ledger initialization creates a fresh process-local execution identity.
The runner owns every value and applies or discards each delta; shared canonical
identity owners remain alive until their last consumer is destroyed. Neither
identities nor prepared requests are persisted, restored or reused by a rerun.
No provider invocation, counting, retry or successor selection occurs during
request preparation. ADRs 0009 and 0011 remain unchanged.

Native sealed pipeline values may omit a byte cap when their owning contract
has none. Their ownership transfer remains typed and opaque; ordinary copying
values and contracts with explicit resource bounds retain their existing checks.
This is not a second request store or a model-call size policy.

## Acceptance

Compile and execute arbitrary YAML using the native preparation bindings and
test-only provider contracts. Prove exact identity/resource retention across
different steps, missing-input and rebinding rejection, malformed SDD owners,
cancellation, allocation cleanup and isolation between executions. Test-only
provider contracts do not enter production composition. Provider invocation
integration and Bedrock remain separate increments.
