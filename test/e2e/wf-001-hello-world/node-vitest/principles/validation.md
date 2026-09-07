# Validation Standards

<!--
Section: validation
Priority: critical
Applies to: wf-001 Node + Vitest fixture
Dependencies: [core]
Version: 1.0.0
Last Updated: 2026-08-30
Project: Hello World
-->

## 1. Validation Outcomes

| Outcome                | Requirement                                             | Priority |
| ---------------------- | ------------------------------------------------------- | -------- |
| Behavioral Correctness | Verify the exact Hello World greeting.                  | MUST     |
| Boundary Correctness   | Verify the application can start successfully.          | MUST     |
| Failure Behavior       | Preserve unexpected failures as failed execution.       | MUST     |
| Accessibility          | Not applicable beyond plain readable text.              | MUST     |
| Visual and Layout      | Not applicable.                                         | MUST     |
| Regression Protection  | Keep a focused Vitest test for the greeting behavior.   | MUST     |

---

## 2. Validation Domain Applicability

| Domain      | Applicability Rule                                | Required Evidence             |
| ----------- | ------------------------------------------------- | ----------------------------- |
| Unit        | Applies to the greeting behavior.                 | Passing Vitest assertion.     |
| Contract    | Not applicable; no external contract exists.      | Not applicable.               |
| Integration | Not required for this isolated application.       | Not applicable.               |
| Security    | Applies only to absence of added unsafe behavior. | Review of the bounded change. |
| User Flow   | Applies to starting and observing the greeting.   | Successful execution.         |
| Performance | Not applicable.                                   | Not applicable.               |

Exact paths, suffixes, include patterns, runners, and commands are not declared
by this principle.

---

## 3. Test Behavior Requirements

### Unit Validation

| Requirement           | Description                                         | Priority |
| --------------------- | --------------------------------------------------- | -------- |
| Isolation             | Test greeting behavior without external services.  | MUST     |
| Observable Assertions | Assert the exact greeting value.                    | MUST     |
| External Boundaries   | Do not require filesystem, network, or database I/O. | MUST    |
| Determinism           | The same test input must produce the same greeting. | MUST     |

### Integration Validation

| Requirement          | Description                            | Priority |
| -------------------- | -------------------------------------- | -------- |
| Boundary Interaction | Not applicable.                        | MUST     |
| Realistic Setup      | Not applicable.                        | MUST     |
| Failure Scenarios    | Do not add synthetic integration work. | MUST     |
| Cleanup              | No integration resources are created.  | MUST     |

### Contract Validation

| Requirement        | Description                 | Priority |
| ------------------ | --------------------------- | -------- |
| Interface Contract | Not applicable.             | MUST     |
| Schema Conformance | Not applicable.             | MUST     |
| Consumer Behavior  | Not applicable.             | SHOULD   |

---

## 4. Security Validation Outcomes

| Category       | Required Outcome                                     | Priority |
| -------------- | ---------------------------------------------------- | -------- |
| Authentication | Not applicable.                                      | MUST     |
| Authorization  | Not applicable.                                      | MUST     |
| Untrusted Input | Verify that no external application input is added. | MUST     |
| Sensitive Data | Verify that no sensitive data handling is added.     | MUST     |
| Dependency Risk | Use only the configured TypeScript/Vitest setup.    | MUST     |

---

## 5. Test Doubles and Isolation

| Context            | Policy                                        | Priority |
| ------------------ | --------------------------------------------- | -------- |
| Unit Boundaries    | No test double is needed for pure behavior.   | MUST     |
| External Services  | Do not add or mock external services.         | MUST     |
| Integration Scope  | Not applicable.                               | MUST     |
| Realistic Behavior | Test the real greeting behavior directly.     | MUST     |
| Interaction Checks | Avoid interaction assertions without a boundary. | SHOULD |

---

## 6. Execution Quality

| Requirement     | Description                                     | Priority |
| --------------- | ----------------------------------------------- | -------- |
| Isolation       | Tests must use no external state.               | MUST     |
| Determinism     | Repeated runs must assert the same greeting.    | MUST     |
| Repeatability   | Tests must pass without manual setup.           | MUST     |
| Parallel Safety | No shared mutable test resource may be added.   | SHOULD   |
