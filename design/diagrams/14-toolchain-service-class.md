```mermaid
classDiagram
    direction LR

    class ToolchainContracts {
        <<domain contracts>>
        +Capture
        +Project
        +Preset
        +Registry
        +Resolved
        +Composed
    }

    class ToolchainAccounting {
        <<domain accounting>>
        +validateCaptureBudget(project, presets)
    }

    class ToolchainSchema {
        <<domain schema conversion>>
        +parseProject(document) Project
        +parseRegistry(documents) Registry
    }

    class ToolchainInheritance {
        <<domain inheritance>>
        +validateCompleteRegistry(registry)
        +resolve(project, registry) Resolved
    }

    class ToolchainComposition {
        <<domain composition>>
        +compose(project, resolved) Composed
    }

    class ToolchainSafety {
        <<domain safety and ownership>>
        +validate(composed, registry) ToolchainOwner
        +value(owner) ValidToolchain
        +deinitOwner(owner) void
    }

    class ValidateToolchainSafetyAction {
        <<action>>
        -PolicyRegistry registry
        +execute(composed) ToolchainOwner
    }

    class ComposedToolchain {
        <<pre-publication candidate>>
        +string list packages
        +string list policies
    }

    class PolicyRegistry {
        +PolicyContract list contracts
    }

    class WorkflowRunner {
        <<application>>
        +invoke selected YAML operation
    }

    class PipelineEnvelope {
        <<sole workflow value owner>>
        +apply validated delta
        +destroy rejected or retired values
    }

    class ToolChainService {
        <<application service>>
        -ValidToolchain borrowedValue
        +init(validatedValue) ToolChainService
        +toolchain() ValidToolchain
    }

    class ToolchainOwner {
        <<opaque owner>>
    }

    class ValidToolchain {
        <<opaque immutable authority>>
        +packages() string list
        +policies() PolicyContract list
    }

    class PolicyContract {
        +string id
        +bool project_selectable
        +bool locked_required
    }

    ToolchainAccounting ..> ToolchainContracts : validates capture bounds
    ToolchainSchema ..> ToolchainContracts : converts closed documents
    ToolchainInheritance ..> ToolchainContracts : validates and resolves registry
    ToolchainComposition ..> ToolchainContracts : composes deterministically
    ToolchainSafety ..> ToolchainContracts : validates effective policy
    ValidateToolchainSafetyAction --> PolicyRegistry : uses compiler registry
    ValidateToolchainSafetyAction ..> ComposedToolchain : supplies candidate
    ValidateToolchainSafetyAction --> ToolchainSafety : delegates safety validation
    ToolchainSafety ..> ToolchainOwner : creates only after safety passes
    ToolchainSafety ..> ValidToolchain : owns immutable storage
    WorkflowRunner ..> ValidateToolchainSafetyAction : invokes when YAML reaches it
    WorkflowRunner --> PipelineEnvelope : applies delta or discards candidate
    PipelineEnvelope *-- ToolchainOwner : owns and deinitializes original result
    ToolchainOwner *-- ValidToolchain : owns hidden storage
    ToolChainService ..> ValidToolchain : returns borrowed const
    ValidToolchain o-- "0..*" PolicyContract : exposes compiled policies
    PolicyRegistry o-- "0..*" PolicyContract : defines

    note for ToolchainContracts "Shared types and limits only; no parsing, accounting, inheritance, composition or publication"
    note for ToolChainService "Read-only facade: toolchain() performs no I/O, parsing, merge, validation or allocation"
```

Fixed startup loads configuration, roots, and workflow definitions only. The
selected YAML graph explicitly orders the separate capture, inventory, parsing,
schema-validation, inheritance, composition, and safety operations. A workflow
without those operations never reads toolchain documents.
