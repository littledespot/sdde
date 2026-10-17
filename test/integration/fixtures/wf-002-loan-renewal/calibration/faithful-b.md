# Library Loan Renewal

## User Scenarios & Testing

### Primary User Story

Borrowers can renew their active, never-renewed loans once. The due date and the displayed outcome reflect whether renewal succeeds or is refused.

### Acceptance Criteria

- **AC-001**: **GIVEN** a loan is active and has never been renewed, **WHEN** its borrower asks to renew it, **THEN** renewal is available, its existing due date moves forward by fourteen calendar days, and the borrower is shown the new due date with `Loan renewed!`.
- **AC-002**: **GIVEN** a loan has already been renewed or is inactive, **WHEN** a renewal is requested, **THEN** it is refused, its due date does not change, and `Renewal refused.` is shown.

## Requirements

### Functional Requirements

- **FR-001**: The borrower MUST be able to renew a loan if it is active and has not been renewed before; only one renewal is permitted.
- **FR-002**: On successful renewal, the existing due date MUST move forward by fourteen calendar days. The borrower MUST be shown the resulting due date and `Loan renewed!`.
- **FR-003**: An inactive loan or a loan renewed before MUST be refused renewal. Refusal MUST retain the existing due date and display `Renewal refused.`.
