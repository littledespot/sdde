# `.sddtoolkit.json` path contract

Every SDDE project has exactly one `.sddtoolkit.json` at its project root. The
file's location defines that root. The repository example defines the current
reader-facing JSON shape but is never itself runtime configuration or a
fallback.

The decoded `paths` object contains exactly eight strings: seven intended
project-relative directory roots and one provider-document file path. F0001
provides those strings as immutable configuration information. The path-policy
owner separately normalizes and validates each value against the canonical
project root before any path is used; decoding a string never grants path
authority.

| Key | Purpose |
| --- | --- |
| `specs` | Canonical feature-facing views, clarification forms, and logs. |
| `references` | Project reference corpora supplied to specification workflows. |
| `specsArchive` | Archived feature views. This is the sole configured-root nesting exception: it may be beneath `specs`, and its subtree is excluded from active feature discovery. |
| `workflows` | An arbitrary bounded number of closed declarative workflow definitions and their explicitly declared resources. V1 recursively admits only strict UTF-8 YAML 1.2 regular files with the exact case-sensitive `*.workflow.yaml` suffix and the formal closed [workflow-definition v1 structural schema](schemas/workflow-definition-v1.schema.json); `WorkflowId` comes from validated content, never the filename. Each definition has a unique validated `WorkflowId`, logging shortcode, and graph composed only from the single registry's generic operation contracts. Definitions cannot contain executable code, select infrastructure, grant capabilities, weaken registered gates, or bypass runner validation. The initial definitions are `specify`, `plan`, `tasks`, and `implement`, whose own predecessor gates enforce their order. This root also owns the engine-reserved `features/` child; its root entry is accounted when present and its descendants are excluded from definition traversal. |
| `toolchainPreset` | The installed toolchain preset packages from which the project's `toolchain.yaml` inherits. Presets remain candidate policy until parsed, composed, and deterministically validated. |
| `principles` | Project principles. Markdown files are free-text principle sources. The exact root child `toolchain.yaml` is also a project principle, but it is parsed separately as a closed typed project-toolchain layer and never ingested as free text. |
| `templates` | Inert `*.template.md` principle templates reserved for a future `sdd init` template-to-principles boundary. Current v1 defines no init action or transaction and normal bootstrap and feature workflows neither ingest nor copy these files. A future accepted init design may materialize copies in `principles`, where they would become ordinary project principle input. |
| `providers` | Engine-read-only LLM-provider catalogue document path. It is a normalized project-relative file path whose basename is exactly `.sddproviders.json`. F0004 reserves it without reading it; F0008 is its sole reader and F0006 owns later decoding. Catalogue membership does not add a model to the repository's allowed `models.slots` set. |

Except for `specsArchive` beneath `specs`, the seven configured directory
roots are disjoint. `paths.providers` may not equal, contain, or be contained
by a configured root. No configured path may alias or collide under an active
portability policy.

The engine derives, rather than separately configures, these storage children:

| Derived path | Purpose |
| --- | --- |
| `<paths.workflows>/features/` | Engine-owned canonical per-feature workflow and execution state. |

Only `features/` is reserved at the workflow root. There is no project-level
transaction storage child or replacement recovery location. Other directories
follow the ordinary workflow-definition/resource inventory rules.

The current reader-facing schema example is
[`examples/.sddtoolkit.json`](examples/.sddtoolkit.json). The engine never
searches `design/`, reads this repository copy as project configuration, or
copies it into a project implicitly.
