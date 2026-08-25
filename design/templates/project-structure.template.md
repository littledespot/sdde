# Constitution Project Structure Standards

<!--
Section: project-structure
Priority: high
Applies to: all projects
Dependencies: [core, architecture]
Version: 1.0.0
Last Updated: [YYYY-MM-DD]
Project: [PROJECT_NAME]
-->

## 1. Directory Organization Principles

| Principle                | Description                        | Priority |
| ------------------------ | ---------------------------------- | -------- |
| **Feature Grouping**     | [FEATURE_GROUPING_APPROACH]        | MUST     |
| Separation of Concerns   | [SEPARATION_OF_CONCERNS_PRINCIPLE] | MUST     |
| Naming Conventions       | [DIRECTORY_NAMING_CONVENTIONS]     | MUST     |
| Depth Limits             | [MAX_DIRECTORY_DEPTH]              | SHOULD   |
| Co-location              | [CO_LOCATION_PRINCIPLE]            | SHOULD   |
| Generated Output Isolation | [GENERATED_OUTPUT_POLICY]         | MUST     |

---

## 2. Responsibility Placement

This principle defines placement relationships without repeating exact roots,
filenames, suffixes, or include patterns.

| Content Category       | Placement Policy                         | Priority |
| ---------------------- | ---------------------------------------- | -------- |
| Executable Source      | [SOURCE_RESPONSIBILITY_PLACEMENT]        | MUST     |
| Validation Assets      | [VALIDATION_ASSET_PLACEMENT]             | MUST     |
| Shared Contracts       | [SHARED_CONTRACT_PLACEMENT]              | MUST     |
| Static Assets          | [STATIC_ASSET_PLACEMENT]                 | SHOULD   |
| Configuration          | [CONFIGURATION_PLACEMENT]                | MUST     |
| Generated Artifacts    | [GENERATED_ARTIFACT_PLACEMENT]           | MUST     |

---

## 3. Naming and Co-location

| Area                    | Requirement                        | Priority |
| ----------------------- | ---------------------------------- | -------- |
| Modules and Components  | [MODULE_NAMING_POLICY]             | MUST     |
| Validation Files        | [VALIDATION_NAMING_RELATIONSHIP]   | MUST     |
| Shared Types            | [SHARED_TYPE_NAMING_POLICY]        | MUST     |
| Feature-local Assets    | [FEATURE_ASSET_COLOCATION_POLICY]  | SHOULD   |
| Cross-feature Utilities | [CROSS_FEATURE_UTILITY_POLICY]     | SHOULD   |

---

## 4. Structural Anti-Patterns

| Anti-pattern                 | Policy                                  |
| ---------------------------- | --------------------------------------- |
| Mixed generated/source files | [GENERATED_SOURCE_MIXING_POLICY]        |
| Circular dependencies        | [CIRCULAR_DEPENDENCY_POLICY]            |
| Unowned shared directories   | [SHARED_DIRECTORY_OWNERSHIP_POLICY]     |
| Duplicate responsibility     | [DUPLICATE_RESPONSIBILITY_POLICY]       |
| Excessive nesting            | [EXCESSIVE_NESTING_POLICY]              |
