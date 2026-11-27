# ADR 0013: Reuse workflow structure and compact model inputs

- **Status:** Accepted
- **Date:** 2026-09-07
- **Decision authority:** User decisions, 7, 12 and 16 September and 21 November 2026
- **Amends:** ADRs 0005, 0006 and 0012; Design Sections 7, 9, 12.7, 14.1 and 28; F0005, F0006 and F0100
- **Amended by:** [ADR 0030](0030-engine-owned-model-request.md),
  [ADR 0043](0043-model-facing-exact-text-names.md)

## Decision

### Local subgraphs

- Workflow authors may declare definition-local `subgraphs`.
- A top-level step selects either one registered operation with `use`, or one subgraph
  with `call`.
- A subgraph has a `start` and `steps` selecting registered operations or other
  definition-local subgraphs. Calls may forward explicit parameters.
- Calls may nest: a subgraph composes operations and other subgraphs through this same
  compiler. Direct and indirect recursion reject; all expanded operations remain subject
  to the existing graph limits and validators.
- Its parameter references are closed `{param: name}` values.
- The call supplies every referenced parameter exactly once through `with`.
- The existing operation parameter contracts remain the sole type and bounds authority
  after substitution.
- There are no template expressions, defaults, external includes, aliases, executable
  macros, or additional operation registry.

- Subgraph `end.<outcome>` edges are exits.
- Each call explicitly binds exactly those outcomes through `on`; internal failure
  outcomes cannot become success.
- Local edges remain inside the subgraph, and authored top-level edges can name only
  top-level steps.
- Compilation expands each use into ordinary operations before applying the existing
  dependency, gate, capability, cycle and outcome validators.
- Expansion uses the same compiler-owned step ceiling as an explicit graph
  ([F0005 §4](../features/F0005-WorkflowDefinitionRegistryService.md#4-compiler-owned-bounds)).
- Unused subgraphs, identity collisions, missing bindings, recursion, invalid exits and
  expansion overflow reject.
- Expanded identities deterministically encode the complete call path and local step;
  ordering does not supply identity.
- The runtime executes only the resulting graph through the existing runner.
- No action acquires child-node execution and no new execution store is added.

### Local schemas and transport

- The result-schema compiler accepts optional root `$defs` and local `$ref:
  "#/$defs/<name>"` references.
- Definition names match `[a-z][a-z0-9_-]{0,63}`.
- References have no siblings and resolve only in the same captured resource.
- Every definition is validated, including unused definitions.
- Missing, cyclic, remote, escaped/path-like and over-limit references reject.
- Existing schema depth/node limits apply to each expanded definition and result; there
  is no remote loader.
- The previously accepted closed schema forms and candidate rejection rules remain
  unchanged.

- One compiled schema owner retains exact captured source and derives compact, expanded
  JSON for model transport.
- These are source and projection, not two authorities.
- Providers use the same compiled projection; they do not minify, infer schemas, or
  rewrite requests independently.
- The registry continues binding source bytes to captured resources.
- All clones own their source, compiled nodes and projections for their required
  lifetime.

- Named local definitions that are complete result shapes can also be selected from the
  same compiled resource.
- A request whose input is a native packet selects that packet's typed result-definition
  identity; a static or absent input selects nothing.
- The packet's producer supplies that identity from its current typed unit or authorized
  repair target; the model never selects it. A Spec-owned producer names the definition by a
  member of a closed enum declared for its schema resource
  (`src/domain/specification_result_definitions.zig`), never by a string literal or a computed
  name, and a test requires every member to be selectable in the shipped schema. The generic
  `DefinitionId` stays a parsed name (YAML-authored `json-composition/v1` selects by string).
- Missing or non-result definitions reject before invocation.
- Consumers retain that selected schema for the request's lifetime.
- A single known result variant omits the redundant root discriminator and is decoded
  using the retained typed variant; multiple allowed variants retain the existing closed
  `kind` encoding.

### Evidence projections

- Reference/model-input projections publish only fields needed to interpret and cite the
  evidence.
- A packet represents shared citations once, referenced by their existing typed IDs.
- Canonical evidence, validators and provenance joins remain unchanged.
- Generation, reconciliation, review and repair use the same projection owner.
- Complete evidence is retained when no deterministic rule proves a smaller scope; there
  is no similarity filter, arbitrary summary, truncation, new model-call size gate, or
  weakened coverage rule.

- Model-facing inputs and responses use the same ADR 0006 `kind` wire codec.
- Evidence projections unwrap validated text into its existing content contract; native
  validation wrappers never become model instructions.
- Claims, summary statements and signals use the same content shape.
- Preserved-token content is an ID reference; a separate deduplicated `exact_texts`
  collection (ADR 0043) retains the exact value, classification and citation.
- Generation, review and repair reuse these projections without changing native or
  persisted authority.

- Extraction selects scoped source-line IDs, not model-owned quotes or coordinates, as
  defined in [§16.3](../contracts/16-reference-ingestion.md#163-structured-facts-and-exact-tokens).
- The lossless line projection replaces the packet's duplicate whole-chunk text;
  canonical citations and exact-token spans retain their existing authority.

### Scope

- A definition's filename does not determine its workflow ID.
- Each use of a subgraph has its own request and retry identity.
- [F0005 §3.4](../features/F0005-WorkflowDefinitionRegistryService.md#34-definition-local-reuse)
  documents the authoring contract.
- Input optimization alone does not establish workflow completion or measured quality
  improvement.
