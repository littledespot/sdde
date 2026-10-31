# Design reading guide

[design.md](design.md) is the **Proposed design** baseline. Accepted
[ADRs](decisions/) amend only their stated scope; the index is
[§32](design.md#32-accepted-and-deferred-implementation-choices). Open work and
implementation gaps live in [FIX06](../fixes/FIX06.md), not here.

Start with the [executive summary](design.md#1-executive-summary),
[invariants](design.md#3-goals-non-goals-and-invariants) and
[acceptance criteria](design.md#31-acceptance-criteria-for-the-design-implementation),
then follow the section links in design.md.

| Need | Read |
| --- | --- |
| Purpose and success measures (orientation, not authority) | [Engine intent](intent.md) |
| Architecture, invariants and acceptance | [design.md](design.md) |
| Detailed section contracts | [contracts/](contracts/), [action catalogues](contracts/actions/) |
| Accepted amendments | [decisions/](decisions/) |
| Feature contracts | [features/](features/) |
| Illustrative types | [code.md](code.md) |
| Configured roots and derived storage | [paths.md](paths.md) |
| Control and data flow | [diagrams/](diagrams/) |
| Development harness and acceptance | [harness/](harness/README.md) |
| Closed document shapes | [schemas/](schemas/) |
| Example configuration and the Spec workflow | [examples/](examples/), [workflows/](workflows/) |
| Target-project source material | [preset examples](toolchainPresets/), [principle templates](templates/) |

Examples, presets and templates are source material; schemas document contracts.
None of them is runtime configuration or fallback. Templates are not an instantiated engine constitution.
Tests load [workflows/](workflows/) and `examples/.sddproviders.json` directly.
Keep diagram `.md` files and their Mermaid fences so they render in Markdown preview.
