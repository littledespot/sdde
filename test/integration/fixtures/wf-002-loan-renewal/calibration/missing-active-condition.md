# Library Loan Renewal

## User Scenarios & Testing

### Primary User Story

A borrower requests a loan renewal and receives the applicable outcome.

### Acceptance Criteria

- **AC-001**: **GIVEN** a loan that has not previously been renewed, **WHEN** the borrower requests renewal, **THEN** the borrower can renew the loan.
- **AC-002**: **GIVEN** a successful renewal, **THEN** the new due date is fourteen calendar days after the existing due date, and the borrower sees `Loan renewed!` and the new due date.
- **AC-003**: **GIVEN** a previously renewed loan, **WHEN** renewal is requested, **THEN** renewal is refused, its due date remains unchanged and `Renewal refused.` is displayed.

## Requirements

### Functional Requirements

- **FR-001**: A borrower MUST be able to renew a loan that has not previously been renewed.
- **FR-002**: Successful renewal MUST extend the existing due date by fourteen calendar days.
- **FR-003**: After successful renewal, the application MUST display `Loan renewed!` and the new due date to the borrower.
- **FR-004**: A loan MUST be renewed no more than once.
- **FR-005**: For a previously renewed loan, the application MUST refuse renewal, leave its due date unchanged and display `Renewal refused.`.
