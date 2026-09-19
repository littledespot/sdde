# `.sddtoolkit.json` path contract

- The invocation working directory is the project root. Read only its exact
  `.sddtoolkit.json`; never search for another.
- The closed [configuration schema](schemas/sddtoolkit-config.schema.json)
  contains exactly eight path strings: seven directory roots and one provider file.
- [F0001](features/F0001-SDDToolKitConfigService.md) supplies immutable strings.
  [F0004](features/F0004-BootstrapRootRegistryService.md) normalizes and validates
  them against the canonical root before use; decoding grants no path authority.

## Configured locations

| Key | Purpose |
| --- | --- |
| `specs` | Feature views, clarification forms and logs. |
| `references` | Reference corpora supplied to specification workflows. |
| `specsArchive` | Archived feature views; excluded from active feature selection. |
| `workflows` | Closed declarative definitions, declared resources and reserved `features/` state. |
| `toolchainPreset` | Installed preset packages inherited by project `toolchain.yaml`. |
| `principles` | Free-text Markdown principles plus separately typed `toolchain.yaml`. |
| `templates` | Inert `*.template.md` inputs for a future accepted `sdde init`. |
| `providers` | Engine-read-only provider catalogue with exact basename `.sddproviders.json`. |

Containment and ownership:

- Directory roots are disjoint, except `specsArchive` may be beneath `specs`.
- The normalized project-relative provider file cannot equal, contain or be
  contained by a configured root.
- Configured paths must not alias or collide under the active portability policy.
- Presets remain candidates until parsed, composed and deterministically validated
  ([F0003](features/F0003-ToolChainService.md)).
- The exact principles-root child `toolchain.yaml` is a closed typed layer;
  never ingest it as free text.
- Normal bootstrap and feature workflows neither ingest nor copy templates. V1
  defines no init action/transaction; only a future accepted init may copy them
  into `principles` as ordinary project input.
- F0004 reserves the provider file without reading it; F0008 alone reads it and
  F0006 owns decoding. Catalogue membership never expands allowed `models.slots`.

## Workflow inventory

[F0005](features/F0005-WorkflowDefinitionRegistryService.md) owns inventory and
compilation against the [closed v1 schema](schemas/workflow-definition-v1.schema.json):

- Recursively admit an arbitrary bounded number of strict UTF-8 YAML 1.2 regular
  files with exact case-sensitive suffix `*.workflow.yaml` and declared resources.
- Validate unique content-owned `WorkflowId`s and logging shortcodes; filenames
  never determine identity.
- Compile graphs only from the single registry's generic operation contracts.
  Definitions cannot supply executable code/infrastructure/capabilities, weaken
  gates or bypass runner validation.
- The planned SDD suite's own predecessor gates enforce `specify -> plan -> tasks
  -> implement`. The supplied Specify example currently declares `spec-generation`.
- Reserve only the root child `features/`: account for its entry when present and
  exclude descendants from definition traversal. Other directories follow normal
  inventory rules; no transaction/recovery storage child exists.

## Derived storage

The engine derives these paths; they are not separate configuration fields.

| Path | Purpose |
| --- | --- |
| `<paths.workflows>/features/` | Canonical published feature/clarification state; no execution checkpoints. |
| `<paths.workflows>/features/<feature-directory>/state/workflow.json` | Fixed workflow-state singleton. |
| `<paths.workflows>/features/<feature-directory>/state/clarifications.json` | Native clarification registry and response input. |

- [F0100 §3.12](features/F0100-SpecWorkflow.md#312-clarification-refresh-and-registered-publication)
  owns Specify's separate capture/validation of `specification-state/v3`.
- [F0100 §3.2](features/F0100-SpecWorkflow.md#32-read-only-artifact-and-clarification-inputs)
  owns read-only clarification preparation, closed schema and limits.

## Feature directory

[ADR 0010](decisions/0010-explicit-feature-directory.md) defines feature identity:

- `--feature` is relative to `paths.specs`; resolve
  `<paths.specs>/<feature-directory>/`, excluding `paths.specsArchive`.
- The caller omits the configured root. Never hard-code `specs/` or guess/remove
  a prefix: `--feature hello-world` writes `<paths.specs>/hello-world/spec.md`.
- The normalized relative key also identifies canonical state. There is no
  reference-derived name or identity/ownership registry.

The [complete example](examples/.sddtoolkit.json) is source material. The engine
never searches `design/`, uses this copy as runtime fallback or copies it implicitly.
