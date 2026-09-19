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
    LEVEL -->|Yes| BODY{"Body capture enabled by debug/trace?"}
    BODY -->|Yes| SANITIZE["Redact credentials, then split complete selected bodies<br/>into ordered bounded fragments without truncation"]
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

[F0002](../features/F0002-LogService.md) and
[ADR 0018](../decisions/0018-debug-model-exchange-logging.md) own severity, debug/trace
exchange capture, redaction, limits and failure behavior.
The production invocation boundary captures requests before dispatch and available
raw responses before admission, including failed attempts. Log-tail recovery repairs log records;
it never resumes a workflow or establishes completion.
