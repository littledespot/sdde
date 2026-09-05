Main responsibilities and relationships for project configuration.

```mermaid
classDiagram
    direction LR
    class BootstrapConfigRunner
    class DecodeSDDToolKitConfigAction
    class BootstrapServices
    class SDDToolKitConfigService
    class SDDToolKitConfig
    class LogsConfig
    class ModelsConfig
    class PathsConfig

    BootstrapConfigRunner --> DecodeSDDToolKitConfigAction : invokes configuration decoding
    DecodeSDDToolKitConfigAction ..> SDDToolKitConfig : produces validated configuration
    BootstrapServices *-- SDDToolKitConfigService : owns for the invocation
    SDDToolKitConfigService *-- SDDToolKitConfig : retains immutable configuration
    SDDToolKitConfig *-- LogsConfig : logging settings
    SDDToolKitConfig *-- ModelsConfig : model slot selections
    SDDToolKitConfig *-- PathsConfig : configured locations

    note for SDDToolKitConfigService "Provides read-only access to the configuration loaded for this invocation"
    note for SDDToolKitConfig "Unknown fields and malformed values are rejected before consumers use the configuration"
```

Startup reads the invocation's `.sddtoolkit.json`. Dedicated validators resolve
the logging, model and path policies from the same immutable configuration.
