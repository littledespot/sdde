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
| Responsibility Boundaries | Keep greeting creation separate from process entry and output. | MUST     |
| State Ownership           | Keep no application state.                                     | MUST     |
| Component Separation      | Add only the modules needed for the greeting and its test.     | MUST     |
| External I/O Boundaries   | Limit external I/O to writing the greeting.                    | MUST     |
| Dependency Direction      | The entry module may depend on greeting behavior, not reverse. | MUST     |

---

## 2. Responsibility Boundaries

| Boundary Category   | Responsibility                         | Constraint                             |
| ------------------- | -------------------------------------- | -------------------------------------- |
| Entry/Orchestration | Start the application once.            | Contains no greeting business logic.   |
| Domain Behavior     | Provide the Hello World greeting.      | Has no process or filesystem access.   |
| Presentation        | Write the greeting once.               | Does not change the greeting.          |
| External Adapters   | Not applicable.                        | Do not add external services.          |
| Persistence         | Not applicable.                        | Do not add persistent state.           |
| Shared Contracts    | Not applicable for this small fixture. | Do not introduce a shared abstraction. |

### Composition Flow

The entry module obtains the greeting from the greeting module and writes it
once. Tests exercise the greeting behavior without starting external services.

---

## 3. State and Data Flow

| Area              | Requirement                                               | Priority |
| ----------------- | --------------------------------------------------------- | -------- |
| State Source      | No application state is required.                         | MUST     |
| State Transitions | No application state transitions are required.            | MUST     |
| Derived State     | The greeting is constant behavior, not stored state.      | MUST     |
| Side Effects      | Keep output at the process boundary.                      | MUST     |
| External Data     | No external data is accepted.                             | MUST     |
| Error Propagation | Let unexpected startup or output errors fail the process. | MUST     |

---

## 4. Runtime Performance Boundaries

| Area                    | Requirement                                            | Priority |
| ----------------------- | ------------------------------------------------------ | -------- |
| Critical Operations     | No special performance budget is required.             | MUST     |
| Resource Use            | Use only the resources needed to start and write once. | SHOULD   |
| Repeated Work           | Do not repeat greeting generation or output.           | MUST     |
| Concurrency             | Keep execution sequential.                             | SHOULD   |
| Caching                 | Do not add caching.                                    | SHOULD   |
| Payload and Data Volume | Handle only the Hello World greeting.                  | SHOULD   |
