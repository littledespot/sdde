# Constitution Security Standards

<!--
Section: security
Priority: critical
Applies to: wf-001 Node + Vitest fixture
Dependencies: [core]
Version: 1.0.0
Last Updated: 2026-08-30
Project: Hello World
-->

## 1. Core Security Principles

| Principle              | Requirement                                             | Priority |
| ---------------------- | ------------------------------------------------------- | -------- |
| **Least Privilege**    | Request no filesystem, network, or elevated privilege. | MUST     |
| **Zero Trust**         | No external trust relationship is required.            | MUST     |
| **Defense in Depth**   | Do not add layers without a protected boundary.        | MUST     |
| **Fail Secure**        | Preserve an unexpected failure as process failure.     | MUST     |
| **Complete Mediation** | No protected resource access is required.              | MUST     |

---

## 2. Authentication & Authorization

| Security Control      | Requirement                                  | Priority |
| --------------------- | -------------------------------------------- | -------- |
| **Authentication**    | Not applicable.                              | MUST     |
| Multi-Factor Auth     | Not applicable.                              | MUST     |
| Token Management      | Do not introduce tokens.                     | MUST     |
| Session Expiration    | Not applicable.                              | MUST     |
| **Authorization**     | Not applicable.                              | MUST     |
| RBAC Implementation   | Do not introduce roles.                      | MUST     |
| Permission Boundaries | Use only normal local process capabilities. | MUST     |
| Token Rotation        | Not applicable.                              | MUST     |

---

## 3. Data Protection

| Protection Type           | Requirement                           | Priority |
| ------------------------- | ------------------------------------- | -------- |
| **Encryption at Rest**    | Not applicable; no data is persisted. | MUST     |
| **Encryption in Transit** | Not applicable; no network is used.   | MUST     |
| **PII Handling**          | Do not collect personal information.  | MUST     |
| Data Minimization         | Retain no application data.           | MUST     |
| **Data Classification**   | The fixed greeting is non-sensitive.  | MUST     |
| Data Retention            | Do not retain application data.       | MUST     |
| Secure Deletion           | Not applicable.                       | MUST     |
| **Key Management**        | Do not introduce encryption keys.     | MUST     |

---

## 4. Input Validation & Output Sanitization

| Security Control     | Requirement                                         | Priority |
| -------------------- | --------------------------------------------------- | -------- |
| **Input Validation** | Accept no external application input.               | MUST     |
| Injection Prevention | Do not evaluate dynamic code or construct commands. | MUST     |
| XSS Prevention       | Not applicable; no web content is produced.         | MUST     |
| Command Injection    | Do not invoke a shell or build commands from data.  | MUST     |
| **Output Encoding**  | Output only the fixed greeting.                      | MUST     |
| CSP Headers          | Not applicable.                                     | MUST     |
| Path Traversal       | Do not accept or construct application paths.       | MUST     |
| **Type Validation**  | Keep the greeting a string.                          | MUST     |

---

## 5. Secret Management

| Secret Type              | Requirement                                    | Priority |
| ------------------------ | ---------------------------------------------- | -------- |
| **API Keys**             | Do not introduce API keys.                     | MUST     |
| **Database Credentials** | Do not introduce database credentials.         | MUST     |
| **Encryption Keys**      | Do not introduce encryption keys.              | MUST     |
| **JWT Secrets**          | Do not introduce JWT secrets.                  | MUST     |
| **Secret Rotation**      | Not applicable.                                | MUST     |
| Environment Separation   | No secret-bearing environments are required.   | MUST     |

### Secret Prohibitions

- Do not add secrets, credential files, or secret-bearing environment values.

---

## 6. Security Event Signals

| Event Category        | Required Security Signal | Priority |
| --------------------- | ------------------------ | -------- |
| Authentication Events | Not applicable.          | MUST     |
| Authorization Failures | Not applicable.         | MUST     |
| Privilege Changes     | Not applicable.          | MUST     |
| Sensitive Data Access | Not applicable.          | MUST     |
| Privileged Operations | Not applicable.          | MUST     |
| Security Anomalies    | Not applicable.          | SHOULD   |

This principle defines which security-relevant events require evidence. It does
not define log formats, transport, retention, metrics, traces, or alert tooling.

---

## 7. Secure Development Requirements

| Practice Area       | Requirement                                                        | Priority |
| ------------------- | ------------------------------------------------------------------ | -------- |
| Dependency Risk     | Add no dependency beyond the configured TypeScript/Vitest setup.  | MUST     |
| Unsafe Capabilities | Do not add network, shell, filesystem, or dynamic-eval access.     | MUST     |
| Threat Modeling     | Not required while there is no input or external I/O.              | SHOULD   |
| Review Triggers     | Reassess if input, storage, network, or secrets are added.         | MUST     |
