High-level flow for recording workflow activity and managing its log files.

```mermaid
flowchart TD
    START["Prepare logging for the selected workflow and feature"] --> HISTORY["Inspect and finalize prior log streams<br/>using their recorded policies"]
    HISTORY --> POLICY["Validate the current logging policy<br/>and authorized log locations"]
    POLICY --> OPEN["Prepare event streams and any enabled prompt streams;<br/>validate existing tails and apply retention"]
    OPEN --> READY["Logging ready"]

    READY --> FACT["Receive trusted workflow lifecycle facts<br/>and telemetry accepted by the runner"]
    FACT --> REDACT["Select permitted fields and redact sensitive values"]
    REDACT --> LEVEL{"Event meets the configured severity threshold?"}
    LEVEL -->|No| CONTINUE["Continue the workflow"]
    LEVEL -->|Yes| BODY{"Prompt or response capture explicitly enabled?"}
    BODY -->|Yes| SANITIZE["Redact and bound permitted body fragments"]
    BODY -->|No| METADATA["Keep metadata only"]
    SANITIZE --> RECORD["Validate and encode records in the fixed log format"]
    METADATA --> RECORD
    RECORD --> WRITE["Acquire the stream lock;<br/>rotate if needed, append and flush the record;<br/>release the lock"]
    WRITE -->|Recorded| CONTINUE
    WRITE -->|Failed| FAILURE["Report the logging failure<br/>and block the workflow"]
    RECORD -->|Unsafe or invalid| FAILURE
    HISTORY -->|Corrupt or inaccessible| FAILURE
    OPEN -->|Failed| FAILURE

    UPDATE["Logging policy changes"] --> SWITCH["Validate the change; close old streams<br/>and prepare successor streams before activation"]
    SWITCH -->|Ready| READY
    SWITCH -->|Failed| FAILURE
    FINISH["Workflow ends"] --> CLOSE["Flush and close active streams;<br/>apply retention to eligible closed segments"]
```

Metadata logging follows the validated severity policy. Body capture requires
explicit opt-in, redaction and limits. Logging failures prevent further workflow
progress. Log-tail recovery repairs log records only; it never resumes workflow
execution or establishes task completion.
