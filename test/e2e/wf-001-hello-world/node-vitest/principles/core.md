# Core Principles

<!--
Section: core
Priority: critical
Applies to: wf-001 Node + Vitest fixture
Version: 1.0.0
Last Updated: 2026-08-30
Project: Hello World
-->

## 1. Technology Stack Standards

| Component            | Requirement                                             | Priority |
| -------------------- | ------------------------------------------------------- | -------- |
| **Runtime**          | Use the Node.js runtime supplied by the toolchain.       | MUST     |
| **Language**         | Use TypeScript supported by the configured toolchain.    | MUST     |
| Language Strictness  | Keep the greeting and its boundaries type-safe.          | MUST     |
| Language Linting     | Follow only the configured lint policy.                  | MUST     |
| **Compute Platform** | Run as a local Node.js process.                          | MUST     |
| **Database**         | No database is required.                                | MUST     |

### Technology Prohibitions (WON'T without RFC)

- Alternative runtimes
- JavaScript or another implementation language
- Dynamic code evaluation
- Additional compute platforms
- Databases or persistent storage

---

## 2. Coding Standards

| Area               | Standard                                                        | Enforcement |
| ------------------ | --------------------------------------------------------------- | ----------- |
| **Language**       | Use clear TypeScript supported by the configured toolchain.      | MUST        |
| **Type Safety**    | Keep values simple and avoid unnecessary type conversion.       | MUST        |
| **Async Patterns** | Do not introduce asynchronous work.                             | MUST        |
| **Modularity**     | Separate greeting behavior from the process entry point.         | MUST        |
| **Error Handling** | Let unexpected failures propagate to a non-successful process.   | MUST        |
| **Data Models**    | Do not introduce data models for the constant greeting.          | MUST        |

### Error Handling Example

```typescript
try {
  runApplication();
} catch (error) {
  console.error(error);
  process.exitCode = 1;
}
```

### Core Requirements

- **Error Handling**: Report an unexpected error once and preserve failure.
- **Data Models**: Do not add a model when the greeting can remain a constant value.
