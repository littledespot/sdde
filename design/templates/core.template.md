# Core Principles

<!--
Section: core
Priority: critical
Applies to: all projects
Version: 1.0.0
Last Updated: [YYYY-MM-DD]
Project: [PROJECT_NAME]
-->

## 1. Technology Stack Standards

| Component            | Requirement                       | Priority |
| -------------------- | --------------------------------- | -------- |
| **Runtime**          | [RUNTIME_TECHNOLOGY]              | MUST     |
| **Language**         | [LANGUAGE] [VERSION_REQUIREMENT]  | MUST     |
| Language Strictness  | [LANGUAGE_STRICTNESS_REQUIREMENT] | MUST     |
| Language Linting     | [LANGUAGE_LINTING_REQUIREMENT]    | MUST     |
| **Compute Platform** | [COMPUTE_PLATFORM]                | MUST     |
| **Database**         | [DATABASE_TECHNOLOGY]             | MUST     |

### Technology Prohibitions (WON'T without RFC)

- Alternative runtimes without formal RFC approval
- [PROHIBITED_LANGUAGE_PRACTICE]
- [DEPRECATED_LANGUAGE_FEATURE]
- Alternative compute platforms without RFC approval
- Alternative databases without RFC approval

---

## 2. Coding Standards

| Area               | Standard                      | Enforcement |
| ------------------ | ----------------------------- | ----------- |
| **Language**       | [LANGUAGE_STANDARD]           | MUST        |
| **Type Safety**    | [TYPE_SAFETY_REQUIREMENTS]    | MUST        |
| **Async Patterns** | [ASYNC_PATTERN_REQUIREMENTS]  | MUST        |
| **Modularity**     | [MODULARITY_STANDARDS]        | MUST        |
| **Error Handling** | [ERROR_HANDLING_PATTERN]      | MUST        |
| **Data Models**    | [MODEL_NAMING_CONVENTIONS]    | MUST        |

### Error Handling Example

```pseudocode
try:
  result = operation()
  return result
catch error:
  logger.error("Operation failed", {correlationId, error})
  re-raise error
```

### Core Requirements

- **Error Handling**: Use language-appropriate error handling mechanism, log with correlation ID, provide context
- **Data Models**: Clear naming, type safety (if language supports it), immutability preferred, validation methods
