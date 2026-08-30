# Constitution Observability Standards

<!--
Section: observability
Priority: high
Applies to: wf-001 Node + Vitest fixture
Dependencies: [core]
Version: 1.0.0
Last Updated: 2026-08-30
Project: Hello World
-->

## 1. Logging Standards

### Mandatory Log Fields

| Field   | Requirement                         |
| ------- | ----------------------------------- |
| Message | Include only the unexpected failure. |

### Optional Context Fields

No optional context fields are required.

### Error-Specific Fields

| Field | Requirement                                  |
| ----- | -------------------------------------------- |
| Name  | Include the error name when one is available. |

### Logging Patterns

| Situation          | Pattern                            |
| ------------------ | ---------------------------------- |
| Successful startup | Do not emit a diagnostic log.      |
| Unexpected failure | Write one concise error to stderr. |

### Logging Prohibitions

- Do not add routine debug or informational logs.
- Do not log the Hello World application output as diagnostic telemetry.
- Do not add a logging dependency.

---

## 2. Log Implementation Standards

| Requirement             | Description                                            | Priority |
| ----------------------- | ------------------------------------------------------ | -------- |
| **Structured Format**   | Structured logging is not required.                    | MUST     |
| Correlation ID          | No correlation ID is required for this local process.  | MUST     |
| Consistent Fields       | Use the same concise error representation when needed. | MUST     |
| **Environment Config**  | No logging configuration is required.                  | MUST     |
| Test Environment        | Tests must not emit logs during a successful run.      | MUST     |
| Production Environment  | Write unexpected failures to stderr only.              | MUST     |
| Log Levels              | Only error-level diagnostic output is needed.          | MUST     |
| **Log Sampling**        | Sampling is not applicable.                            | SHOULD   |

---

## 3. Metrics Standards

### Metric Categories

No application metrics are required.

### Metric Requirements

| Requirement           | Description                 | Priority |
| --------------------- | --------------------------- | -------- |
| **Consistent Naming** | Not applicable.             | MUST     |
| **Appropriate Tags**  | Not applicable.             | MUST     |
| **Thresholds**        | Not applicable.             | MUST     |
| Cardinality Control   | Do not introduce metrics.   | MUST     |
| **Unit Consistency**  | Not applicable.             | MUST     |

## 4. Distributed Tracing Standards

| Requirement           | Description                    | Priority |
| --------------------- | ------------------------------ | -------- |
| **Trace Propagation** | Not applicable.                | MUST     |
| **Span Creation**     | Do not introduce tracing.      | MUST     |
| Span Attributes       | Not applicable.                | MUST     |
| **Sampling Strategy** | Not applicable.                | MUST     |
| Sampling Rate         | Not applicable.                | MUST     |
| **Error Tracking**    | Not applicable.                | MUST     |
| Trace Completeness    | Not applicable.                | SHOULD   |

### Tracing Best Practices

| Practice             | Requirement                 | Priority |
| -------------------- | --------------------------- | -------- |
| Semantic Conventions | Not applicable.             | SHOULD   |
| Context Enrichment   | Do not add trace context.   | SHOULD   |
| Performance Impact   | Do not introduce tracing.   | MUST     |
| Trace Analysis       | Not applicable.             | SHOULD   |
