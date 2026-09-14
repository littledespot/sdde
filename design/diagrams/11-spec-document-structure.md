High-level structure of the generated specification document.

```mermaid
flowchart TB
    TITLE["Feature Specification: title"] --> SCENARIOS["User Scenarios & Testing<br/>Required section"]
    SCENARIOS --> STORY["Primary User Story"]
    SCENARIOS --> AC["Acceptance Criteria<br/>Given, When, Then"]
    SCENARIOS --> OUTCOMES["User-Visible Outcomes<br/>Only with supported content"]
    SCENARIOS --> EDGES["Edge Cases<br/>Only with supported content"]

    TITLE --> REQUIREMENTS["Requirements<br/>Required section"]
    REQUIREMENTS --> FUNCTIONAL["Functional Requirements"]
    REQUIREMENTS --> RULES["Business Rules<br/>Only with supported content"]
    REQUIREMENTS --> SCOPE["Assumptions & Scope Boundaries<br/>Only with supported content"]
    SCOPE --> ASSUMPTIONS["Assumptions<br/>Only with supported content"]
    SCOPE --> NONGOALS["Explicit Non-Goals<br/>Only with supported content"]
    SCOPE --> PROHIBITED["Prohibited Behaviors<br/>Only with supported content"]
    REQUIREMENTS --> ENTITIES["Key Entities<br/>Included when the feature involves business data"]
```

[F0100 §5](../features/F0100-SpecWorkflow.md#5-specmd-projection-contract)
owns hierarchy, record IDs, mandatory content and optional-section omission.
Questions belong in `clarify/SNN.md`; technical detail belongs in
`reference-context.md`. Structure alone does not prove semantic quality.
