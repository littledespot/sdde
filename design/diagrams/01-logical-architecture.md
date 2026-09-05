High-level responsibilities and boundaries of the workflow engine.

```mermaid
flowchart TB
    ENTRY["CLI or API invocation"] --> STARTUP["Load configuration and workflow definitions;<br/>validate and compile registered operations"]
    STARTUP --> REGISTRY["Validated workflow registry"]
    REGISTRY --> ENGINE["Workflow engine and orchestrators<br/>Select the workflow and coordinate its declared transitions"]
    ENGINE -->|Request child execution| RUNNER["Runner<br/>Invoke nodes, validate results and apply accepted changes"]
    RUNNER -->|Typed outcomes| ENGINE
    RUNNER --> ACTIONS["Actions<br/>One domain responsibility per action"]
    ACTIONS --> PORTS["Narrow operation ports"]
    PORTS --> ADAPTERS["Adapters<br/>Filesystem, model providers, parsers and restricted commands"]
    ADAPTERS --> ENV["Project files and external systems"]

    YAML["Workflow YAML<br/>Steps, resources, model slots and outcomes"] --> STARTUP
    CONTRACTS["Registered operation contracts<br/>Allowed data, capabilities and transitions"] --> STARTUP
    AUTHORITY["Validated inputs<br/>References, applicable principles, toolchain policies and current state"] --> ACTIONS

    ROOT["Composition root<br/>Assemble concrete adapters and runner bindings"] --> STARTUP
    ROOT --> RUNNER
    ROOT --> ADAPTERS

    RUNNER --> LOGGING["Logging through runner-owned bindings<br/>Record trusted lifecycle facts and accepted telemetry"]
```

Workflow definitions select registered behavior. The runner owns execution;
orchestrators coordinate through its child bindings, and actions access side
effects through their declared ports. Model responses remain candidates until
engine validation accepts them. Publication requires whole-workflow success.
