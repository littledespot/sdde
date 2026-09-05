Main responsibilities and relationships for configured project locations.

```mermaid
classDiagram
    direction LR
    class BootstrapRootRunner
    class BuildBootstrapRootRegistryAction
    class BootstrapRootRegistryCandidate
    class ValidateBootstrapRootRegistryAction
    class BootstrapServices
    class BootstrapRootRegistryService
    class BootstrapRootRegistry
    class ConfiguredBaseRootCapability
    class LLMProviderConfigCapability

    BootstrapRootRunner --> BuildBootstrapRootRegistryAction : invokes root assembly
    BuildBootstrapRootRegistryAction ..> BootstrapRootRegistryCandidate : produces configured locations
    BootstrapRootRunner --> ValidateBootstrapRootRegistryAction : invokes root validation
    ValidateBootstrapRootRegistryAction ..> BootstrapRootRegistryCandidate : checks containment and separation
    ValidateBootstrapRootRegistryAction ..> BootstrapRootRegistry : produces validated registry
    BootstrapServices *-- BootstrapRootRegistryService : owns for the invocation
    BootstrapRootRegistryService *-- BootstrapRootRegistry : retains immutable registry
    BootstrapRootRegistry *-- ConfiguredBaseRootCapability : exposes authorized directory roles
    BootstrapRootRegistry *-- LLMProviderConfigCapability : exposes the configured provider file

    note for BootstrapRootRegistryService "Provides read-only access to validated project locations"
    note for ConfiguredBaseRootCapability "Binds a configured root to its declared role and permitted access"
```

Directory roles cover specifications, references, archives, workflows, toolchain
presets, principles and templates. Consumers use the capability for their
declared operation. Configured locations alone do not grant unrestricted access.
