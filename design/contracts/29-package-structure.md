# 29. Suggested package/module structure

Part of the [proposed design](../design.md#29-suggested-packagemodule-structure). This section retains the
baseline's authority and is subject to the accepted amendments in [§32](../design.md#32-accepted-and-deferred-implementation-choices).

The logical dependency boundaries map to this Zig source/build layout:

[View the Suggested package structure sample](../code.md#suggested-package-structure).

- Domain modules have no infrastructure dependencies.
- The composition root is the only location that constructs concrete adapters and binds
  registered operation implementations.
- It also assembles the one fixed, nonselectable engine-startup graph.
- The workflow compiler alone constructs immutable executable project-workflow graph descriptors
  from validated definitions and registered contracts.

- Zig unit tests may remain beside the owning declarations.
- Cross-module architecture, fixture, failpoint, packaged-executable, and end-to-end tests live
  under the top-level test tree shown in the sample.
- Runtime workflow definitions, toolchain presets, the project `toolchain.yaml` layer, and
  semantic principles load only from their validated configured roots; the initial SDD workflows
  do not load templates, and the executable never falls back to design examples or the source
  tree.
