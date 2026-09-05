Main responsibilities and relationships for target-project toolchain policy.

```mermaid
classDiagram
    direction LR
    class ToolchainSchema
    class ToolchainInheritance
    class ToolchainComposition
    class ComposedToolchain
    class ValidateToolchainSafetyAction
    class ToolchainSafety
    class PolicyRegistry
    class WorkflowRunner
    class PipelineEnvelope
    class ToolChainService
    class ValidToolchain

    ToolchainSchema --> ToolchainInheritance : supplies parsed project and preset data
    ToolchainInheritance --> ToolchainComposition : supplies resolved inheritance
    ToolchainComposition ..> ComposedToolchain : produces a candidate
    WorkflowRunner --> ValidateToolchainSafetyAction : invokes the declared validation step
    ValidateToolchainSafetyAction ..> ComposedToolchain : consumes the candidate
    ValidateToolchainSafetyAction --> PolicyRegistry : uses registered policy authority
    ValidateToolchainSafetyAction --> ToolchainSafety : delegates safety validation
    ToolchainSafety ..> ValidToolchain : produces validated policy
    PipelineEnvelope *-- ValidToolchain : retains accepted policy for the workflow
    ToolChainService ..> ValidToolchain : exposes read-only access

    note for ToolChainService "Consumers use the same validated toolchain policy for target-project decisions"
    note for ToolchainSafety "Rejects invalid composition, ownership and policy selections before use"
```

Separate workflow-selected actions perform capture, parsing, inheritance,
composition and validation. The diagram shows their data relationships.
The service reads validated results; it does not load or combine toolchain files.
