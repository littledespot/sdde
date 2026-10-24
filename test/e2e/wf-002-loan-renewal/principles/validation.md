# Validation Standards

<!--
Section: validation
Priority: critical
Applies to: wf-002 Node + Vitest fixture
Dependencies: [core]
Version: 1.0.0
Last Updated: 2026-10-24
Project: Library Lending
-->

## 1. Validation Outcomes

| Outcome                | Requirement                                             | Priority |
| ---------------------- | ------------------------------------------------------- | -------- |
| Behavioral Correctness | Verify required observable behavior and exact values.   | MUST     |
| Boundary Correctness   | Verify each domain operation's accepted and rejected outcomes. | MUST |
| Failure Behavior       | Verify that a rejected or failed operation changes no state. | MUST |
| Accessibility          | Not applicable beyond plain readable text.              | MUST     |
| Visual and Layout      | Not applicable.                                         | MUST     |
| Regression Protection  | Keep focused Vitest tests for required behavior.         | MUST     |

---

## 2. Validation Domain Applicability

| Domain      | Applicability Rule                                   | Required Evidence             |
| ----------- | ---------------------------------------------------- | ----------------------------- |
| Unit        | Applies to domain operations and their state changes. | Passing Vitest assertion.    |
| Contract    | Not applicable; no external contract exists.         | Not applicable.               |
| Integration | Not required for this single-process application.    | Not applicable.               |
| Security    | Applies only to absence of added unsafe behavior.    | Review of the bounded change. |
| User Flow   | Applies to submitting a request and observing its result. | Successful execution.    |
| Performance | Not applicable.                                      | Not applicable.               |

Exact paths, suffixes, include patterns, runners, and commands are not declared
by this principle.

---

## 3. Test Behavior Requirements

### Unit Validation

| Requirement           | Description                                          | Priority |
| --------------------- | ---------------------------------------------------- | -------- |
| Isolation             | Test behavior without external services.             | MUST     |
| Observable Assertions | Assert source-required exact values and resulting state. | MUST |
| External Boundaries   | Do not require filesystem, network, or database I/O. | MUST     |
| Determinism           | Use a fixed clock so the same input produces the same result. | MUST |

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

| Category       | Required Outcome                                         | Priority |
| -------------- | -------------------------------------------------------- | -------- |
| Authentication | Not applicable.                                          | MUST     |
| Authorization  | Not applicable.                                          | MUST     |
| Untrusted Input | Verify that invalid requests are rejected before any state change. | MUST |
| Sensitive Data | Verify that no sensitive data handling is added.         | MUST     |
| Dependency Risk | Use only the configured TypeScript/Vitest setup.        | MUST     |

---

## 5. Test Doubles and Isolation

| Context            | Policy                                             | Priority |
| ------------------ | -------------------------------------------------- | -------- |
| Unit Boundaries    | Use the real in-memory domain; replace only the clock. | MUST |
| External Services  | Do not add or mock external services.              | MUST     |
| Integration Scope  | Not applicable.                                    | MUST     |
| Realistic Behavior | Test the real behavior directly.                   | MUST     |
| Interaction Checks | Avoid interaction assertions without a boundary.   | SHOULD   |

---

## 6. Execution Quality

| Requirement     | Description                                     | Priority |
| --------------- | ----------------------------------------------- | -------- |
| Isolation       | Each test creates its own domain state.         | MUST     |
| Determinism     | Repeated runs must assert the same result.      | MUST     |
| Repeatability   | Tests must pass without manual setup.           | MUST     |
| Parallel Safety | No shared mutable test resource may be added.   | SHOULD   |
