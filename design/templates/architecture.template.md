# Constitution Architecture Standards

<!--
Section: architecture
Priority: high
Applies to: all projects
Dependencies: [core]
Version: 1.0.0
Last Updated: [YYYY-MM-DD]
Project: [PROJECT_NAME]
-->

## 1. Architectural Principles

| Principle               | Description                        | Priority |
| ----------------------- | ---------------------------------- | -------- |
| **Design Pattern**      | [ARCHITECTURE_PATTERN]             | MUST     |
| Responsibility Boundaries | [RESPONSIBILITY_BOUNDARY_POLICY] | MUST     |
| State Ownership         | [STATE_OWNERSHIP_APPROACH]         | MUST     |
| Component Separation    | [COMPONENT_SEPARATION_PRINCIPLE]   | MUST     |
| External I/O Boundaries | [EXTERNAL_IO_BOUNDARY_POLICY]      | MUST     |
| Dependency Direction    | [DEPENDENCY_DIRECTION_POLICY]      | MUST     |

---

## 2. Responsibility Boundaries

| Boundary Category       | Responsibility                         | Constraint                 |
| ----------------------- | -------------------------------------- | -------------------------- |
| Entry/Orchestration     | [ENTRY_ORCHESTRATION_RESPONSIBILITY]   | [ENTRY_BOUNDARY_POLICY]    |
| Domain Behavior         | [DOMAIN_BEHAVIOR_RESPONSIBILITY]       | [DOMAIN_BOUNDARY_POLICY]   |
| Presentation            | [PRESENTATION_RESPONSIBILITY]          | [PRESENTATION_POLICY]      |
| External Adapters       | [EXTERNAL_ADAPTER_RESPONSIBILITY]      | [ADAPTER_BOUNDARY_POLICY]  |
| Persistence             | [PERSISTENCE_RESPONSIBILITY]           | [PERSISTENCE_POLICY]       |
| Shared Contracts        | [SHARED_CONTRACT_RESPONSIBILITY]       | [CONTRACT_BOUNDARY_POLICY] |

### Composition Flow

[ARCHITECTURE_COMPOSITION_FLOW]

---

## 3. State and Data Flow

| Area                  | Requirement                         | Priority |
| --------------------- | ----------------------------------- | -------- |
| State Source          | [STATE_SOURCE_POLICY]               | MUST     |
| State Transitions     | [STATE_TRANSITION_POLICY]           | MUST     |
| Derived State         | [DERIVED_STATE_POLICY]              | MUST     |
| Side Effects          | [SIDE_EFFECT_BOUNDARY_POLICY]       | MUST     |
| External Data         | [EXTERNAL_DATA_NORMALIZATION_POLICY] | MUST    |
| Error Propagation     | [ERROR_PROPAGATION_POLICY]          | MUST     |

---

## 4. Runtime Performance Boundaries

| Area                    | Requirement                            | Priority |
| ----------------------- | -------------------------------------- | -------- |
| Critical Operations     | [CRITICAL_OPERATION_BUDGET]            | MUST     |
| Resource Use            | [RESOURCE_USE_POLICY]                  | SHOULD   |
| Repeated Work           | [REPEATED_WORK_POLICY]                 | MUST     |
| Concurrency             | [CONCURRENCY_POLICY]                   | SHOULD   |
| Caching                 | [CACHE_OWNERSHIP_AND_INVALIDATION]     | SHOULD   |
| Payload and Data Volume | [DATA_VOLUME_BOUNDARY_POLICY]          | SHOULD   |
