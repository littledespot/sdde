# Constitution Project Structure Standards

<!--
Section: project-structure
Priority: high
Applies to: wf-001 Node + Vitest fixture
Dependencies: [core, architecture]
Version: 1.0.0
Last Updated: 2026-08-30
Project: Hello World
-->

## 1. Directory Organization Principles

| Principle                  | Description                                                   | Priority |
| -------------------------- | ------------------------------------------------------------- | -------- |
| **Feature Grouping**       | Keep the single greeting feature together.                   | MUST     |
| Separation of Concerns     | Separate application behavior from validation assets.        | MUST     |
| Naming Conventions         | Use short, descriptive names.                                | MUST     |
| Depth Limits               | Avoid nesting that is unnecessary for this single feature.   | SHOULD   |
| Co-location                | Keep directly related implementation files together.         | SHOULD   |
| Generated Output Isolation | Keep generated output outside authored source responsibilities. | MUST   |

---

## 2. Responsibility Placement

This principle defines placement relationships without repeating exact roots,
filenames, suffixes, or include patterns.

| Content Category    | Placement Policy                                                 | Priority |
| ------------------- | ---------------------------------------------------------------- | -------- |
| Executable Source   | Keep entry and greeting behavior in the toolchain source area.   | MUST     |
| Validation Assets   | Keep Vitest validation separate from runtime entry behavior.     | MUST     |
| Shared Contracts    | Do not add shared contracts for this single feature.             | MUST     |
| Static Assets       | Not applicable.                                                  | SHOULD   |
| Configuration       | Keep only configuration required by TypeScript and Vitest.       | MUST     |
| Generated Artifacts | Do not place generated artifacts with authored source.           | MUST     |

---

## 3. Naming and Co-location

| Area                    | Requirement                                                  | Priority |
| ----------------------- | ------------------------------------------------------------ | -------- |
| Modules and Components  | Name modules for their one responsibility.                   | MUST     |
| Validation Files        | Make the tested greeting responsibility clear.               | MUST     |
| Shared Types            | Do not introduce shared types.                               | MUST     |
| Feature-local Assets    | Not applicable.                                              | SHOULD   |
| Cross-feature Utilities | Do not introduce utilities for a single greeting.            | SHOULD   |

---

## 4. Structural Anti-Patterns

| Anti-pattern                 | Policy                                             |
| ---------------------------- | -------------------------------------------------- |
| Mixed generated/source files | Keep generated output separate from authored code. |
| Circular dependencies        | Do not introduce dependency cycles.                |
| Unowned shared directories   | Do not create a shared directory.                  |
| Duplicate responsibility     | Keep one owner for greeting behavior.              |
| Excessive nesting            | Keep the small project shallow.                    |
