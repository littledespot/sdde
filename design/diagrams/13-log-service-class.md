Main responsibilities and relationships for workflow logging.

```mermaid
classDiagram
    direction LR
    class BootstrapServices
    class LogService
    class CompiledLoggingPolicy
    class FeatureLogRuntimeLifecycle
    class WorkflowPipelineRunner
    class TelemetryBarrier
    class FeatureLogChildBindings
    class FeatureLogRunner
    class FeatureLogActions
    class FeatureLogSink

    BootstrapServices *-- LogService : owns for the invocation
    LogService *-- CompiledLoggingPolicy : retains validated policy
    LogService *-- FeatureLogRuntimeLifecycle : manages the active lifecycle
    LogService ..> TelemetryBarrier : exposes telemetry entry
    WorkflowPipelineRunner --> TelemetryBarrier : submits trusted workflow facts
    TelemetryBarrier --> FeatureLogRuntimeLifecycle : forwards accepted telemetry
    FeatureLogRuntimeLifecycle o-- FeatureLogChildBindings : coordinates through runner bindings
    FeatureLogRunner ..> FeatureLogChildBindings : supplies execution bindings
    FeatureLogRunner *-- FeatureLogActions : invokes logging actions
    FeatureLogActions --> FeatureLogSink : writes through narrow ports
    FeatureLogRunner --> CompiledLoggingPolicy : applies the current policy

    note for LogService "Exposes policy and delegates activation, policy changes, finalization and retention"
    note for FeatureLogActions "Filter, redact, validate and persist records within their declared responsibilities"
```

Workflow code contributes telemetry facts. The logging runtime owns safe
recording and stream management. A logging failure blocks further workflow
progress; logs do not establish workflow authority or completion.
