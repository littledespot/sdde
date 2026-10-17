# Library Loan Renewal

## User Scenarios & Testing

### Primary User Story

A borrower requests a loan renewal and receives the applicable outcome.

### Acceptance Criteria

- **AC-001**: **GIVEN** an active loan regardless of its previous renewals, **WHEN** the borrower requests renewal, **THEN** the borrower can renew the loan.
- **AC-002**: **GIVEN** a successful renewal, **THEN** the new due date is fourteen calendar days after the existing due date, and the borrower sees `Loan renewed!` and the new due date.
- **AC-003**: **GIVEN** an inactive loan, **WHEN** renewal is requested, **THEN** renewal is refused, its due date remains unchanged and `Renewal refused.` is displayed.

## Requirements

### Functional Requirements

- **FR-001**: A borrower MUST be able to renew an active loan, including a loan that has previously been renewed.
- **FR-002**: Successful renewal MUST extend the existing due date by fourteen calendar days.
- **FR-003**: After successful renewal, the application MUST display `Loan renewed!` and the new due date to the borrower.
- **FR-004**: A loan MAY be renewed repeatedly with no renewal-count limit.
- **FR-005**: For an inactive loan, the application MUST refuse renewal, leave its due date unchanged and display `Renewal refused.`.
