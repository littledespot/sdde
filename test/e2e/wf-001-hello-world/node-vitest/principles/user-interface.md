# Constitution User Interface Standards

<!--
Section: user-interface
Priority: high
Applies to: wf-001 Node + Vitest fixture
Dependencies: [core]
Version: 1.0.0
Last Updated: 2026-08-30
Project: Hello World
-->

## 1. Component Experience Standards

| UI Area                 | Required Outcome                         | Priority |
| ----------------------- | ---------------------------------------- | -------- |
| Semantic Composition    | Present the greeting as plain text.             | MUST     |
| Reusable Interaction    | Not applicable; there is no interaction.        | MUST     |
| State Visibility        | Display only the Hello World greeting.          | MUST     |
| Loading and Failure     | Do not add loading or failure interface states. | MUST     |
| Focus and Input         | Not applicable; there is no input.              | MUST     |
| Component Consistency   | Do not introduce user-interface components.     | MUST     |

---

## 2. Design System and Visual Consistency

| Design Area       | Required Outcome                     | Priority | Review Evidence             |
| ----------------- | ------------------------------------ | -------- | --------------------------- |
| Design Tokens     | Not applicable.                      | MUST     | Not applicable.             |
| Color Palette     | Not applicable.                      | MUST     | Not applicable.             |
| Typography        | Use plain text output.               | MUST     | Exact output.               |
| Spacing           | Do not add visual spacing rules.     | MUST     | Exact output.               |
| Layout            | Not applicable.                      | MUST     | Not applicable.             |
| Icons and Assets  | Do not add icons or assets.          | SHOULD   | No assets.                  |
| Brand Identity    | Not applicable.                      | MUST     | Not applicable.             |

---

## 3. Accessibility Standards

| Accessibility Area  | Required Outcome                         | Priority | Review Evidence              |
| ------------------- | ---------------------------------------- | -------- | ---------------------------- |
| WCAG Compliance     | Not applicable to process output.              | MUST     | Not applicable.              |
| Semantic Structure  | Keep the output as readable text.               | MUST     | Exact output.                |
| Accessible Names    | Not applicable.                                | MUST     | Not applicable.              |
| Keyboard Operation  | Not applicable.                                | MUST     | Not applicable.              |
| Screen Readers      | Do not replace the greeting with non-text data. | MUST     | Exact output.                |
| Focus Visibility    | Not applicable.                                | MUST     | Not applicable.              |
| Color Contrast      | Do not apply color.                            | MUST     | Exact output.                |
| Text Alternatives   | Not applicable; the output is text.            | MUST     | Exact output.                |
| Reduced Motion      | Do not introduce motion.                       | MUST     | No motion.                   |

---

## 4. User Experience Standards

| UX Area              | Required Outcome                       | Priority |
| -------------------- | -------------------------------------- | -------- |
| Navigation           | Not applicable.                                 | MUST     |
| Loading Feedback     | Not applicable.                                 | MUST     |
| Error Communication  | Preserve unexpected failures as process errors. | MUST     |
| Form Feedback        | Not applicable.                                 | MUST     |
| Empty States         | Not applicable.                                 | SHOULD   |
| Motion               | Do not introduce motion.                        | SHOULD   |
| User Confirmation    | The greeting is the only success output.        | SHOULD   |

---

## 5. Responsive and Device Outcomes

| Area                 | Required Outcome                       | Priority |
| -------------------- | -------------------------------------- | -------- |
| Narrow Viewports     | Not applicable.                        | MUST     |
| Wide Viewports       | Not applicable.                        | MUST     |
| Content Reflow       | Not applicable.                        | MUST     |
| Touch Interaction    | Not applicable.                        | MUST     |
| Orientation          | Not applicable.                        | SHOULD   |
| Responsive Media     | Do not introduce media.                | SHOULD   |
| Supported Clients    | Use the configured Node.js runtime.    | MUST     |

---

## 6. Internationalization Outcomes

| Area                 | Required Outcome                       | Priority |
| -------------------- | -------------------------------------- | -------- |
| Language Support     | Output the required English greeting.  | MUST     |
| Text Direction       | Use the greeting's natural text order. | SHOULD   |
| Date and Time        | Not applicable.                        | MUST     |
| Number and Currency  | Not applicable.                        | MUST     |
| Pluralization        | Not applicable.                        | MUST     |
| Content Expansion    | Not applicable.                        | SHOULD   |
