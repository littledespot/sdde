High-level structure of the generated specification document.

```mermaid
flowchart TB
    TITLE["Feature title"] --> SCENARIOS["User Scenarios & Testing<br/>Required section"]
    SCENARIOS --> STORY["Primary User Story"]
    SCENARIOS --> AC["Acceptance Criteria<br/>GIVEN, WHEN, THEN"]
    SCENARIOS --> OUTCOMES["User-Visible Outcomes"]
    SCENARIOS --> EDGES["Edge Cases"]

    TITLE --> REQUIREMENTS["Requirements<br/>Required section"]
    REQUIREMENTS --> FUNCTIONAL["Functional Requirements"]
    REQUIREMENTS --> RULES["Business Rules"]
    REQUIREMENTS --> SCOPE["Assumptions & Scope Boundaries"]
    SCOPE --> ASSUMPTIONS["Assumptions"]
    SCOPE --> NONGOALS["Explicit Non-Goals"]
    SCOPE --> PROHIBITED["Prohibited Behaviors"]
    REQUIREMENTS --> ENTITIES["Key Entities<br/>Included when the feature involves business data"]
```

The engine renders these sections in order and assigns record identities.
Required content must be supported before publication. Missing knowledge goes
into clarification forms. Technical reference context is recorded separately
in `reference-context.md`.
