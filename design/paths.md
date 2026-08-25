# `.sddtoolkit.json` path contract

Every SDDE project has exactly one `.sddtoolkit.json` at its project root. The
file's location defines that root; the abridged source sample elsewhere in this
repository is neither the complete normative schema nor a runtime fallback.

The closed `paths` object contains exactly seven project-relative directory
roots. Each value is normalized and validated against the canonical project
root before any path is used.

| Key | Purpose |
| --- | --- |
| `specs` | Canonical feature-facing views, clarification forms, and logs. |
| `references` | Project reference corpora supplied to specification workflows. |
| `specsArchive` | Archived feature views. This is the sole configured-root nesting exception: it may be beneath `specs`, and its subtree is excluded from active feature discovery. |
| `workflows` | Closed, declarative definitions for the runnable `specify`, `plan`, `tasks`, and `implement` workflows. The definitions cannot weaken compiler-locked stage order, action/orchestrator boundaries, validation, or capabilities. This root also owns the engine-reserved `features/` and `transactions/` children; workflow definitions cannot collide with them. |
| `toolchainPreset` | The installed toolchain preset packages from which the project's `toolchain.yaml` inherits. Presets remain candidate policy until parsed, composed, and deterministically validated. |
| `principles` | Project principles. Markdown files are free-text principle sources. The exact root child `toolchain.yaml` is also a project principle, but it is parsed separately as a closed typed project-toolchain layer and never ingested as free text. |
| `templates` | Inert `*.template.md` principle templates reserved for a future `sdd init` template-to-principles boundary. Current v1 defines no init action or transaction and normal bootstrap and feature workflows neither ingest nor copy these files. A future accepted init design may materialize copies in `principles`, where they would become ordinary project principle input. |

Except for `specsArchive` beneath `specs`, the seven configured roots are
disjoint: they cannot be equal, nested, aliased, or collide under any active
portability policy.

The engine derives, rather than separately configures, these storage children:

| Derived path | Purpose |
| --- | --- |
| `<paths.workflows>/features/` | Engine-owned canonical per-feature workflow and execution state. |
| `<paths.workflows>/transactions/` | Engine-owned project activation and recovery transaction collection. |

The abridged source sample is
[`examples/.sddtoolkit.json`](examples/.sddtoolkit.json). It illustrates selected
fields of the mandatory project-root file; it is not the complete normative
schema. The engine never searches `design/` or copies the sample into a project
implicitly.
