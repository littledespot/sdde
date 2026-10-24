# Constitution Architecture Standards

<!--
Section: architecture
Priority: high
Applies to: wf-002 Node + Vitest fixture
Dependencies: [core]
Version: 1.0.0
Last Updated: 2026-10-24
Project: Library Lending
-->

## 1. Architectural Principles

| Principle                 | Description                                                         | Priority |
| ------------------------- | ------------------------------------------------------------------- | -------- |
| **Design Pattern**        | Use a single-process application with a domain module behind a thin entry point. | MUST |
| State Ownership           | The domain module owns application state; no other module changes it. | MUST   |
| Dependency Direction      | The entry module may depend on domain behavior, not reverse.         | MUST     |

---

## 2. Responsibility Boundaries

| Boundary Category   | Responsibility                                  | Constraint                               |
| ------------------- | ----------------------------------------------- | ---------------------------------------- |
| Entry/Orchestration | Receive a request and invoke one domain operation. | Contains no business logic.           |
| Domain Behavior     | Apply business rules and own application state. | Has no process or filesystem access.     |
| Presentation        | Present domain results as text.                 | Does not change or add business content. |
| External Adapters   | Not applicable.                                 | Do not add external services.            |
| Persistence         | In-memory only.                                 | Do not add databases or files.           |
| Shared Contracts    | Introduce only when shared behavior requires them. | Avoid unowned abstractions.           |

---

## 3. State and Data Flow

| Area              | Requirement                                                          | Priority |
| ----------------- | -------------------------------------------------------------------- | -------- |
| State Source      | The domain holds application state in memory for the process lifetime. | MUST   |
| State Transitions | Change state only through domain operations.                         | MUST     |
| Atomicity         | An operation either completes all of its state changes or makes none. | MUST    |
| Side Effects      | Keep output at the process boundary.                                 | MUST     |
| External Data     | Validate each request at the domain boundary before changing state.  | MUST     |
| Error Propagation | Return expected rejections as typed results; let unexpected errors fail the process. | MUST |

---

## 4. Runtime Performance Boundaries

| Area                    | Requirement                                            | Priority |
| ----------------------- | ------------------------------------------------------ | -------- |
| Critical Operations     | No special performance budget is required.             | MUST     |
| Resource Use            | Use only the resources needed for required behavior.   | SHOULD   |
| Repeated Work           | Do not repeat output unnecessarily.                     | MUST     |
| Concurrency             | Keep execution sequential.                             | SHOULD   |
| Caching                 | Do not add caching.                                    | SHOULD   |
