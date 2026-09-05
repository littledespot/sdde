High-level flow for generating, validating and repairing model-produced content.

```mermaid
flowchart TD
    START["Workflow reaches a model operation"] --> AUTH{"Required authority resolved?"}
    AUTH -->|Yes| REQUEST["Build a request from current evidence,<br/>declared guidance and the required result schema"]
    AUTH -->|Missing or conflicting| GAP["Route the gap to its owning workflow;<br/>request clarification or upstream rework"]
    REQUEST --> ALLOW{"Token budget and operation authorization<br/>permit the next call?"}
    ALLOW -->|Yes| CALL["Invoke the selected model"]
    ALLOW -->|No| STOP["End blocked or failed;<br/>retain no successful output"]
    CALL --> OBSERVE["Validate response association<br/>and account actual token usage"]
    OBSERVE -->|Eligible complete result within budget| PARSE{"Response matches the required schema?"}
    OBSERVE -->|Failure or exhausted budget| STOP

    PARSE -->|No| RETRY{"Protocol retry available?"}
    RETRY -->|Yes: retain the same request| ALLOW
    RETRY -->|No| STOP
    PARSE -->|Yes| RESULT{"Content or clarification request?"}
    RESULT -->|Clarification| NEED["Validate the clarification request"]
    NEED -->|Valid| GAP
    NEED -->|Repairable defect| REPAIR
    NEED -->|Non-repairable| STOP
    RESULT -->|Content or repair| APPLY["Validate content and any repair authorization;<br/>merge only authorized changes"]
    APPLY --> CHECK{"Impacted units and complete candidate valid<br/>with current supporting authority?"}
    CHECK -->|Yes| ACCEPT["Accept the typed candidate<br/>for the remaining workflow steps"]
    CHECK -->|Repairable mechanical defect| REPAIR["Authorize the smallest repair within its retry limit;<br/>preserve valid content and create a distinct repair request"]
    REPAIR -->|Authorized| ALLOW
    REPAIR -->|Stale, disallowed or exhausted| STOP
    CHECK -->|Missing authority| GAP
    CHECK -->|Non-repairable defect| STOP
    CHECK -->|Unsupported asserted content| REPLACE["Allow one authorized replacement<br/>with a valid clarification request"]
    REPLACE -->|Valid clarification| GAP
    REPLACE -->|Rejected or exhausted| STOP
    GAP --> END["End the current execution;<br/>preserve clarification questions and answers"]
```

A request retains its originating workflow-step identity, model binding and
resources as it passes between steps. Protocol retries retain that request;
repairs receive distinct requests. Every model call follows the declared
authorization, token accounting and retry rules. Provider failure or cancellation
keeps its own outcome. Semantic review is model-assisted; accepted content is
published only after the complete workflow succeeds.
