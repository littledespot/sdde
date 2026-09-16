# Design reading guide

[design.md](design.md) is the **Proposed design** baseline. Its
[decision index](design.md#32-accepted-and-deferred-implementation-choices)
records accepted amendments without accepting the remaining proposal. Feature
implementation status and verification records are evidence, not new authority.

## Start here

1. Read the [executive summary](design.md#1-executive-summary),
   [goals and invariants](design.md#3-goals-non-goals-and-invariants), and
   [acceptance criteria](design.md#31-acceptance-criteria-for-the-design-implementation).
2. Use the topic sections in [design.md](design.md) to reach detailed
   [contracts](contracts/) and [action catalogues](contracts/actions/).
   Existing numbered section links remain stable; the linked detail belongs to
   the same proposed baseline.
3. Check the applicable [ADRs](decisions/) and [feature contract](features/) for
   accepted amendments, current implementation status and validation evidence.

## Find a document

| Need | Read |
| --- | --- |
| Architecture, rules and acceptance | [Design overview and section map](design.md) |
| Detailed requirements and action responsibilities | [Contracts](contracts/), [action catalogues](contracts/actions/) |
| Decision context, scope and consequences | [ADRs](decisions/) |
| Feature-specific contracts and implementation status | [Feature contracts](features/) |
| Illustrative types and native owners | [Contract/data-shape samples](code.md) |
| Configured roots and derived storage | [Path contract](paths.md) |
| Visual control/data flow | [Mermaid diagrams](diagrams/) |
| Model input, response and retry guidance | [Request guidance](reference-notes/model-request-guidance.md) |
| Harness operation and recorded validation | [Harness guide](harness/README.md) |
| Closed document shapes | [Schemas](schemas/) |
| Example inputs and workflow resources | [Examples](examples/), [workflows](workflows/) |
| Target-project source material | [Preset examples](toolchainPresets/), [preset authoring guide](toolchainPresets/README.md), [principle templates](templates/) |

Schemas, examples, presets and templates retain their existing roles; design
source material is not automatic runtime configuration. Templates are not an
instantiated engine constitution. Keep diagram `.md` files and Mermaid fences
for Markdown-preview rendering.
