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

The engine renders [F0100 §5.1's hierarchy](../features/F0100-SpecWorkflow.md#51-ownership-and-hierarchy)
in order and assigns record identities. Acceptance criteria and functional
requirements need supported content. Empty optional families and an empty scope
group are omitted; missing mandatory content remains a shared authority gap.
Missing required knowledge goes into `clarify/SNN.md`, never an `Open Questions` specification section.
Technical reference context is recorded separately in `reference-context.md`.
This diagram describes structure, not deterministic proof of semantic quality;
the native content/view contract is recorded in F0100 §5.6.
