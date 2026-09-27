# Constitution Architecture Standards

<!--
Section: architecture
Priority: high
Applies to: wf-001 Node + Vitest fixture
Dependencies: [core]
Version: 1.0.0
Last Updated: 2026-08-30
Project: Hello World
-->

## 1. Architectural Principles

| Principle                 | Description                                                    | Priority |
| ------------------------- | -------------------------------------------------------------- | -------- |
| **Design Pattern**        | Use a direct single-process application flow.                  | MUST     |
| State Ownership           | Keep no application state.                                     | MUST     |
| Dependency Direction      | The entry module may depend on domain behavior, not reverse.    | MUST     |

---

## 2. Responsibility Boundaries

| Boundary Category   | Responsibility                         | Constraint                             |
| ------------------- | -------------------------------------- | -------------------------------------- |
| Entry/Orchestration | Start the application once.            | Contains no business logic.            |
| Domain Behavior     | Provide application behavior.          | Has no process or filesystem access.   |
| Presentation        | Present required output.               | Does not change required content.      |
| External Adapters   | Not applicable.                        | Do not add external services.          |
| Persistence         | Not applicable.                        | Do not add persistent state.           |
| Shared Contracts    | Introduce only when shared behavior requires them. | Avoid unowned abstractions. |

---

## 3. State and Data Flow

| Area              | Requirement                                               | Priority |
| ----------------- | --------------------------------------------------------- | -------- |
| State Source      | No application state is required.                         | MUST     |
| State Transitions | No application state transitions are required.            | MUST     |
| Side Effects      | Keep output at the process boundary.                      | MUST     |
| External Data     | No external data is accepted.                             | MUST     |
| Error Propagation | Let unexpected startup or output errors fail the process. | MUST     |

---

## 4. Runtime Performance Boundaries

| Area                    | Requirement                                            | Priority |
| ----------------------- | ------------------------------------------------------ | -------- |
| Critical Operations     | No special performance budget is required.             | MUST     |
| Resource Use            | Use only the resources needed for required behavior.   | SHOULD   |
| Repeated Work           | Do not repeat output unnecessarily.                     | MUST     |
| Concurrency             | Keep execution sequential.                             | SHOULD   |
| Caching                 | Do not add caching.                                    | SHOULD   |
