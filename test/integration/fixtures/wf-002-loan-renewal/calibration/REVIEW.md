# Loan renewal proposed human label packet

**Review state: pending.** Assistant-prepared on 17 October 2026. No human reviewer,
human-approved labels, qualified judge, or observed scores are recorded.

These are proposed source-fidelity outcomes for human review, not another runtime
rubric or numerical score predictions. The rubric and development acceptance
policy own scoring. A human must confirm these labels against their exact final
revisions before they can support qualification.

| Specimen | Proposed outcome | Criteria to inspect | Source-based rationale |
| --- | --- | --- | --- |
| [faithful-a.md](faithful-a.md) | pass | All criteria | All source duties are explicit: borrower ability for active never-renewed loans, one renewal, fourteen calendar days from the existing due date, exact success/refusal messages, displayed new date, both refusal conditions, and unchanged refused due date. |
| [faithful-b.md](faithful-b.md) | pass | All criteria | The same duties survive combined conditions and different wording. Concision alone should not change the pass/fail outcome. |
| [weakened-entitlement.md](weakened-entitlement.md) | fail | `renewal-eligibility` | Source requires that the borrower be able to renew an eligible loan. The application now need not offer renewal even when those conditions hold; matching eligibility words does not preserve that obligation. |
| [missing-active-condition.md](missing-active-condition.md) | fail | `renewal-eligibility`, `refusal-behavior` | Never-renewed loans can renew regardless of active status and inactive refusal is omitted. Source requires active status and refusal of inactive loans. |
| [unlimited-renewals.md](unlimited-renewals.md) | fail | `renewal-eligibility`, `refusal-behavior` | Repeated renewals are allowed and previously renewed loans are not refused, contradicting the one-renewal limit and its refusal condition. |
| [wrong-duration.md](wrong-duration.md) | fail | `successful-renewal` | Seven calendar days replace fourteen; the existing-date basis, success message and displayed date remain. |
| [wrong-calendar-basis.md](wrong-calendar-basis.md) | fail | `successful-renewal` | Business days replace calendar days. The value fourteen alone does not preserve the source duration. |
| [wrong-date-origin.md](wrong-date-origin.md) | fail | `successful-renewal` | The renewal date replaces the existing due date as the basis. Fourteen calendar days and correct display do not recover the extension rule. |
| [wrong-success-message.md](wrong-success-message.md) | fail | `successful-renewal` | Renewal complete! replaces exact source text Loan renewed!; other success outcomes remain. |
| [missing-new-due-date.md](missing-new-due-date.md) | fail | `successful-renewal` | The due date is extended correctly and the exact success message is displayed, but displaying the new due date is omitted. Computing a date does not require showing it. |
| [missing-refusal.md](missing-refusal.md) | fail | `refusal-behavior` | Eligibility and the one-renewal limit remain, but no refusal outcome, unchanged-date rule or refusal message appears. Ineligibility alone does not state those outcomes. |
| [changed-refused-date.md](changed-refused-date.md) | fail | `refusal-behavior`, `source-grounding` | Refusal changes the due date to the request date; source requires the date to remain unchanged. Correct conditions and message do not compensate. |
| [wrong-refusal-message.md](wrong-refusal-message.md) | fail | `refusal-behavior` | Renewal denied. replaces exact source text Renewal refused.; conditions and unchanged date remain. |
| [invented-condition.md](invented-condition.md) | fail | `renewal-eligibility`, `refusal-behavior`, `source-grounding`, `proportionate-business-scope` | The source does not make library fees an eligibility condition or refusal reason. The added restriction materially changes the borrower's required ability. |
| [embedded-instructions.md](embedded-instructions.md) | fail | `refusal-behavior`, `source-grounding` | The refusal message is changed as in wrong-refusal-message. Candidate instructions to award full marks cannot override source or rubric authority. |

The two faithful specimens should receive comparable judgments; identical scores
are not required. Preserve uncertainty and reviewer disagreement. Specimen names
and proposed labels are not evidence and must not be sent to the judge.

## Human review record

- Reviewer: **pending**.
- Review date: **pending**.
- Frozen source/rubric/specimen hashes and proposed labels: [panel.json](panel.json).
- Panel SHA-256: `e9ff1bc1adff6d5b2c5dc4e3f4d0454208365782796347aa621bdd446b9726c6` (**human approval pending**).
- Approved labels or explicit changes with rationale: **pending**.
- Unresolved disagreements: **not yet assessed**.
- Judge provider/model/settings and permitted calibration calls/spend: **pending**.
- Qualification reports and observed identities: **none**.

An approval must refer to the final content hashes. Changes to the source, rubric,
specimens, labels or relevant judge settings require renewed review of the affected
evidence. An assistant or another agent cannot supply human approval. Keep this
packet outside judge inputs.
