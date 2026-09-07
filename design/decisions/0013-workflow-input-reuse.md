# ADR 0013: Reuse workflow structure and compact model inputs

- **Status:** Accepted; implemented
- **Date:** 2026-09-07
- **Decision authority:** Explicit user instruction to implement TODO001's recommendations with single responsibility, no duplicate authority, and removal of superseded code
- **Amends:** ADRs 0005, 0006 and 0012; Design Sections 7, 9, 12.7, 14.1 and 28; F0005, F0006 and F0100

## Decision

Workflow authors may declare definition-local `subgraphs`. A top-level step
selects either one registered operation with `use`, or one subgraph with
`call`. A subgraph has a `start` and ordinary operation `steps`; it cannot call
another subgraph. Its parameter references are closed `{param: name}` values.
The call supplies every referenced parameter exactly once through `with`.
The existing operation parameter contracts remain the sole type and bounds
authority after substitution. There are no template expressions, defaults,
external includes, aliases, executable macros, or additional operation registry.

Subgraph `end.<outcome>` edges are exits. Each call explicitly binds exactly
those outcomes through `on`; internal failure outcomes cannot become success.
Local edges remain inside the subgraph, and authored top-level edges can name
only top-level steps. Compilation expands each use into ordinary operations
before applying the existing dependency, gate, capability, cycle and outcome
validators. Expansion has the same 256-step ceiling as an explicit graph.
Unused subgraphs, identity collisions, missing bindings, recursion, invalid
exits and expansion overflow reject. Expanded identities deterministically
encode the call identity and local step; ordering does not supply identity.
The runtime executes only the resulting graph through the existing runner.
No action acquires child-node execution and no new execution store is added.

The result-schema compiler accepts optional root `$defs` and local
`$ref: "#/$defs/<name>"` references. Definition names match `[a-z][a-z0-9_-]{0,63}`.
References have no siblings and resolve only in the same captured resource.
Every definition is validated, including unused definitions. Missing, cyclic,
remote, escaped/path-like and over-limit references reject. Existing schema
depth/node limits apply to each expanded definition and result; there is no remote loader.
The previously accepted closed schema forms and candidate rejection rules
remain unchanged.

One compiled schema owner retains exact captured source and derives compact,
expanded JSON for model transport. These are source and projection, not two
authorities. Providers and optional counting use the same compiled projection;
they do not minify, infer schemas, or rewrite requests independently. The
registry continues binding source bytes to captured resources. All clones own
their source, compiled nodes and projections for their required lifetime.

Named local definitions that are complete result shapes can also be selected
from the same compiled resource. An explicit originating request parameter
opts into selection from the input packet's typed result-definition identity.
The packet's producer supplies that identity from its current typed unit or
authorized repair target; the model never selects it. Missing or non-result
definitions reject before invocation. Consumers retain that selected schema
for the request's lifetime. A single known result variant omits the redundant
root discriminator and is decoded using the retained typed variant; multiple
allowed variants retain the existing closed `kind` encoding.

Reference/model-input projections publish only fields needed to interpret and
cite the evidence. A packet represents shared citations once, referenced by
their existing typed IDs. Canonical evidence, validators and provenance joins
remain unchanged. Generation, reconciliation, review and repair use the same
projection owner. Complete evidence is retained when no deterministic rule
proves a smaller scope; there is no similarity filter, arbitrary summary,
truncation, new model-call size gate, or weakened coverage rule.

Workflow examples use block YAML. Prompts remain short and task-specific.
The specification example is `spec.workflow.yaml`; its filename does not
determine its workflow ID. Configuration, provider catalogue, toolchain and
reference authorities remain separate. Whole-output publication and answer
application are outside this change; ADR 0009 remains unchanged.

## Validation

- Equivalent explicit/expanded graphs, unrelated workflow representatives,
  per-use request/retry isolation, and rejection of invalid boundaries.
- Schema source/projection lifetime, local-reference failures, exact bounds,
  compact/native/prompt-only consistency, and selected-variant rejection.
- Complete citation/claim/token projection, preserved uncertainty, immutable
  canonical evidence, and allocation-failure cleanup.
- Full fake-provider workflow tests, architecture checks, and clean native
  packaging through `zig build verify`.
- Measured authored/expanded sizes and actual serialized model inputs; no
  unmeasured token/cost-saving claims or live provider evaluation without its
  separate authorization.

Implementation measurements and the complete execution-file inventory are in
[TODO001](../TODO001.md). Overall specification publication remains tracked by
F0100; it is not implied by this input optimization.
