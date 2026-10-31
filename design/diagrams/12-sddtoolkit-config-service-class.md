Main responsibilities and relationships for project configuration.

```mermaid
classDiagram
    direction LR
    class BootstrapConfigRunner
    class LocateExactEngineConfigAction
    class ReadEngineConfigAction
    class DecodeSDDToolKitConfigAction
    class BootstrapServices
    class SDDToolKitConfigService
    class SDDToolKitConfig
    class LogsConfig
    class ModelsConfig
    class PathsConfig
    class PrinciplesConfig

    BootstrapConfigRunner --> LocateExactEngineConfigAction : invokes exact file location
    BootstrapConfigRunner --> ReadEngineConfigAction : invokes bounded read
    BootstrapConfigRunner --> DecodeSDDToolKitConfigAction : invokes configuration decoding
    DecodeSDDToolKitConfigAction ..> SDDToolKitConfig : produces structurally decoded configuration
    BootstrapServices *-- SDDToolKitConfigService : owns for the invocation
    SDDToolKitConfigService *-- SDDToolKitConfig : retains immutable configuration
    SDDToolKitConfig *-- LogsConfig : logging settings
    SDDToolKitConfig *-- ModelsConfig : model slot selections
    SDDToolKitConfig *-- PathsConfig : configured locations
    SDDToolKitConfig *-- PrinciplesConfig : optional principle selection policy

    note for SDDToolKitConfigService "Provides read-only access to the configuration loaded for this invocation"
    note for SDDToolKitConfig "Also holds workflowTokenBudget, temperature, temperatureRunawayRetry and optional validation; unknown fields and malformed values are rejected before consumers use the configuration"
```

[F0001](../features/F0001-SDDToolKitConfigService.md) owns the invocation's
immutable `.sddtoolkit.json` input. Dedicated consumers validate logging,
model and path policy.
