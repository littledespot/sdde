High-level startup flow and workflow-selected toolchain preparation.

```mermaid
flowchart TD
    START["Run an sdd command"] --> CONFIG["Read .sddtoolkit.json from the invocation directory;<br/>validate configuration and configured roots"]
    CONFIG --> WORKFLOWS["Discover workflow definitions and declared resources;<br/>validate and compile their operations"]
    WORKFLOWS --> SELECT["Select the requested workflow"]
    SELECT --> MODEL{"Selected workflow requires a model provider?"}
    MODEL -->|Yes| PROVIDERS["Load the configured provider catalogue;<br/>validate permitted model bindings"]
    MODEL -->|No| INVOKE
    PROVIDERS -->|Ready| INVOKE["Validate arguments through the selected invocation contract"]
    PROVIDERS -->|Failed or cancelled| STOP["End with the corresponding outcome"]
    INVOKE --> EXECUTE["Start a fresh workflow execution"]
    EXECUTE --> TOOLCHAIN{"Workflow requests toolchain preparation?"}
    TOOLCHAIN -->|No| RUN["Continue the declared workflow"]
    TOOLCHAIN -->|Yes| PRESETS["Load and validate the complete preset registry<br/>and project toolchain configuration"]
    PRESETS --> INHERIT["Resolve preset inheritance<br/>and compose the project toolchain"]
    INHERIT --> SAFETY{"Effective paths, environments and command policies valid?"}
    SAFETY -->|Yes| PUBLISH["Make validated toolchain policy available<br/>to subsequent workflow operations"]
    PUBLISH --> RUN
    SAFETY -->|No| STOP
```

The selected workflow controls when toolchain preparation occurs and which
principles or repository facts it needs. Toolchain policy governs target-project
files and commands; semantic principles provide guidance only where applicable.
Templates remain inert during ordinary workflow execution.
