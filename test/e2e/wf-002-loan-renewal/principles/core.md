# Core Principles

<!--
Section: core
Priority: critical
Applies to: wf-002 Node + Vitest fixture
Version: 1.0.0
Last Updated: 2026-10-24
Project: Library Lending
-->

## 1. Technology Stack Standards

| Component            | Requirement                                                 | Priority |
| -------------------- | ----------------------------------------------------------- | -------- |
| **Runtime**          | Use the Node.js runtime supplied by the toolchain.           | MUST     |
| **Language**         | Use TypeScript supported by the configured toolchain.        | MUST     |
| Language Strictness  | Keep behavior and its boundaries type-safe.                  | MUST     |
| Language Linting     | Follow only the configured lint policy.                      | MUST     |
| **Compute Platform** | Run as a local Node.js process.                              | MUST     |
| **Database**         | No database is required; the domain holds its records in memory. | MUST |

### Technology Prohibitions (WON'T without RFC)

- Alternative runtimes
- JavaScript or another implementation language
- Dynamic code evaluation
- Additional compute platforms
- Databases or external storage services

---

## 2. Coding Standards

| Area               | Standard                                                              | Enforcement |
| ------------------ | --------------------------------------------------------------------- | ----------- |
| **Language**       | Use clear TypeScript supported by the configured toolchain.            | MUST        |
| **Type Safety**    | Model domain records and operation results with explicit types.       | MUST        |
| **Async Patterns** | Do not introduce asynchronous work.                                   | MUST        |
| **Modularity**     | Separate domain behavior from the process entry point and presentation. | MUST      |
| **Time**           | Read the current date and time through an injected clock.             | MUST        |
| **Error Handling** | Return expected rejections as typed results; let unexpected failures propagate to a non-successful process. | MUST |

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
- **Expected Outcomes**: Represent each expected rejection as a typed result with its reason.
