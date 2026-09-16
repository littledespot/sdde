# Toolchain preset source material and authoring

The sibling YAML files, including `_structure.yaml`, retain the legacy toolkit's
technology examples as design source material. They can inform future policy work;
their presence does not make them executable presets or accepted engine policy.

Use [F0003 §3](../features/F0003-ToolChainService.md#3-closed-loading-and-publication-contract)
for the implemented YAML shape, exact package references, composition and safety gate.
The [project schema](../schemas/project-toolchain-v1.schema.json) and
[preset schema](../schemas/toolchain-preset-v1.schema.json) document that same contract.

- The project layer is exactly `<paths.principles>/toolchain.yaml`.
- Preset packages are direct regular `*.toolchain-preset.yaml` children of the
  configured `paths.toolchainPreset` root.
- Packages select registered policies; they cannot embed commands, paths or capabilities.
- [F0003 §3.2](../features/F0003-ToolChainService.md#32-exact-schemas) shows the
  current document fields. [Samples 15–20](../code.md#preset-identity-and-composition)
  retain richer proposed policy concepts, not additional runtime fields.

This directory is source material, not an installed registry or runtime fallback.
The legacy `version: "1.0"` examples and `_structure.yaml` do not satisfy the
current closed schemas and have no compatibility reader. Installing a runtime
package requires explicit authoring and validation under F0003.
