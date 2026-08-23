# Validation Standards

<!--
Section: validation
Priority: critical
Applies to: all projects
Dependencies: [core]
Version: 1.0.0
Last Updated: [YYYY-MM-DD]
Project: [PROJECT_NAME]
-->

## 1. Validation Outcomes

| Outcome                 | Requirement                     | Priority |
| ----------------------- | ------------------------------- | -------- |
| Behavioral Correctness  | [BEHAVIORAL_VALIDATION_POLICY]  | MUST     |
| Boundary Correctness    | [BOUNDARY_VALIDATION_POLICY]    | MUST     |
| Failure Behavior        | [FAILURE_VALIDATION_POLICY]     | MUST     |
| Accessibility           | [ACCESSIBILITY_VALIDATION_POLICY] | MUST   |
| Visual and Layout       | [VISUAL_VALIDATION_POLICY]      | MUST     |
| Regression Protection   | [REGRESSION_VALIDATION_POLICY]  | MUST     |

---

## 2. Validation Domain Applicability

| Domain       | Applicability Rule                          | Required Evidence              |
| ------------ | ------------------------------------------- | ------------------------------ |
| Unit         | [UNIT_VALIDATION_APPLICABILITY]             | [UNIT_VALIDATION_EVIDENCE]     |
| Contract     | [CONTRACT_VALIDATION_APPLICABILITY]         | [CONTRACT_VALIDATION_EVIDENCE] |
| Integration  | [INTEGRATION_VALIDATION_APPLICABILITY]      | [INTEGRATION_EVIDENCE]         |
| Security     | [SECURITY_VALIDATION_APPLICABILITY]         | [SECURITY_EVIDENCE]            |
| User Flow    | [FLOW_VALIDATION_APPLICABILITY]             | [FLOW_EVIDENCE]                |
| Performance  | [PERFORMANCE_VALIDATION_APPLICABILITY]      | [PERFORMANCE_EVIDENCE]         |

Exact paths, suffixes, include patterns, runners, and commands are not declared
by this principle.

---

## 3. Test Behavior Requirements

### Unit Validation

| Requirement           | Description                          | Priority |
| --------------------- | ------------------------------------ | -------- |
| Isolation             | [UNIT_ISOLATION_POLICY]              | MUST     |
| Observable Assertions | [UNIT_ASSERTION_POLICY]              | MUST     |
| External Boundaries   | [UNIT_EXTERNAL_BOUNDARY_POLICY]      | MUST     |
| Determinism           | [UNIT_DETERMINISM_POLICY]            | MUST     |

### Integration Validation

| Requirement          | Description                           | Priority |
| -------------------- | ------------------------------------- | -------- |
| Boundary Interaction | [INTEGRATION_BOUNDARY_POLICY]         | MUST     |
| Realistic Setup      | [INTEGRATION_SETUP_POLICY]            | MUST     |
| Failure Scenarios    | [INTEGRATION_FAILURE_POLICY]          | MUST     |
| Cleanup              | [INTEGRATION_CLEANUP_POLICY]          | MUST     |

### Contract Validation

| Requirement         | Description                          | Priority |
| ------------------- | ------------------------------------ | -------- |
| Interface Contract  | [CONTRACT_INTERFACE_POLICY]          | MUST     |
| Schema Conformance  | [CONTRACT_SCHEMA_POLICY]             | MUST     |
| Consumer Behavior   | [CONTRACT_CONSUMER_POLICY]           | SHOULD   |

---

## 4. Security Validation Outcomes

| Category              | Required Outcome                         | Priority |
| --------------------- | ---------------------------------------- | -------- |
| Authentication        | [AUTHENTICATION_VALIDATION_OUTCOME]      | MUST     |
| Authorization         | [AUTHORIZATION_VALIDATION_OUTCOME]       | MUST     |
| Untrusted Input       | [UNTRUSTED_INPUT_VALIDATION_OUTCOME]     | MUST     |
| Sensitive Data        | [SENSITIVE_DATA_VALIDATION_OUTCOME]      | MUST     |
| Dependency Risk       | [DEPENDENCY_RISK_VALIDATION_OUTCOME]     | MUST     |

---

## 5. Test Doubles and Isolation

| Context             | Policy                              | Priority |
| ------------------- | ----------------------------------- | -------- |
| Unit Boundaries     | [UNIT_TEST_DOUBLE_POLICY]           | MUST     |
| External Services   | [EXTERNAL_SERVICE_DOUBLE_POLICY]    | MUST     |
| Integration Scope   | [INTEGRATION_DOUBLE_POLICY]         | MUST     |
| Realistic Behavior  | [TEST_DOUBLE_REALISM_POLICY]        | MUST     |
| Interaction Checks  | [INTERACTION_VERIFICATION_POLICY]   | SHOULD   |

---

## 6. Execution Quality

| Requirement    | Description                       | Priority |
| -------------- | --------------------------------- | -------- |
| Isolation      | [TEST_ISOLATION_REQUIREMENTS]     | MUST     |
| Determinism    | [TEST_DETERMINISM_REQUIREMENTS]   | MUST     |
| Repeatability  | [TEST_REPEATABILITY_REQUIREMENTS] | MUST     |
| Parallel Safety | [PARALLEL_TEST_POLICY]            | SHOULD   |
