const std = @import("std");
const provider = @import("llm_provider_operation.zig");
const budget = @import("workflow_token_budget.zig");

pub const TotalTokenBudget = budget.TotalTokenBudget;

pub const Revision = struct {
    value: u64,

    pub const initial: Revision = .{ .value = 0 };

    pub fn eql(left: Revision, right: Revision) bool {
        return left.value == right.value;
    }
};

pub const ReservationTransition = struct {
    expected_revision: Revision,
    operation_id: provider.ProviderOperationId,
    count_operation_id: provider.ProviderOperationId,
    exact_input_tokens: u64,
    maximum_output_tokens: u64,
};

pub const Reconciliation = union(enum) {
    exact_usage: provider.ProviderUsage,
    not_sent,
    retain,
};

pub const ReconciliationTransition = struct {
    expected_revision: Revision,
    operation_id: provider.ProviderOperationId,
    reconciliation: Reconciliation,
};

const ReservationStatus = enum { active, committed, released, retained };

const Reservation = struct {
    operation_id: provider.ProviderOperationId,
    exact_input_tokens: u64,
    maximum_output_tokens: u64,
    amount: u64,
    status: ReservationStatus,
};

pub const Ledger = struct {
    allocator: std.mem.Allocator,
    total_budget: TotalTokenBudget,
    revision_value: Revision = .initial,
    committed_tokens: u64 = 0,
    reserved_tokens: u64 = 0,
    reservations: std.ArrayListUnmanaged(Reservation) = .empty,

    pub fn init(allocator: std.mem.Allocator, total_budget: TotalTokenBudget) ?Ledger {
        if (!total_budget.isValid()) return null;
        return .{ .allocator = allocator, .total_budget = total_budget };
    }

    pub fn deinit(self: *Ledger) void {
        self.reservations.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn revision(self: *const Ledger) Revision {
        return self.revision_value;
    }

    pub fn totalTokenBudget(self: *const Ledger) TotalTokenBudget {
        return self.total_budget;
    }

    pub fn committed(self: *const Ledger) u64 {
        return self.committed_tokens;
    }

    pub fn reserved(self: *const Ledger) u64 {
        return self.reserved_tokens;
    }

    pub fn applyReservation(
        self: *Ledger,
        transition: ReservationTransition,
    ) Error!void {
        const amount = try validateReservation(self, transition);
        const next_revision = std.math.add(u64, self.revision_value.value, 1) catch {
            return error.TokenAccountingRevisionExhausted;
        };
        try self.reservations.append(self.allocator, .{
            .operation_id = transition.operation_id,
            .exact_input_tokens = transition.exact_input_tokens,
            .maximum_output_tokens = transition.maximum_output_tokens,
            .amount = amount,
            .status = .active,
        });
        self.reserved_tokens = std.math.add(u64, self.reserved_tokens, amount) catch unreachable;
        self.revision_value = .{ .value = next_revision };
    }

    pub fn applyReconciliation(
        self: *Ledger,
        transition: ReconciliationTransition,
    ) Error!void {
        try validateReconciliation(self, transition);
        const reservation = self.findReservation(transition.operation_id).?;
        const next_revision = std.math.add(u64, self.revision_value.value, 1) catch {
            return error.TokenAccountingRevisionExhausted;
        };
        switch (transition.reconciliation) {
            .exact_usage => |usage| {
                const next_committed = std.math.add(u64, self.committed_tokens, usage.total_tokens) catch {
                    return error.WorkflowTokenBudgetExceeded;
                };
                self.reserved_tokens -= reservation.amount;
                self.committed_tokens = next_committed;
                reservation.status = .committed;
            },
            .not_sent => {
                self.reserved_tokens -= reservation.amount;
                reservation.status = .released;
            },
            .retain => reservation.status = .retained,
        }
        self.revision_value = .{ .value = next_revision };
    }

    fn findReservation(self: *Ledger, operation_id: provider.ProviderOperationId) ?*Reservation {
        for (self.reservations.items) |*reservation| {
            if (reservation.operation_id.eql(operation_id)) return reservation;
        }
        return null;
    }

    fn findReservationConst(self: *const Ledger, operation_id: provider.ProviderOperationId) ?*const Reservation {
        for (self.reservations.items) |*reservation| {
            if (reservation.operation_id.eql(operation_id)) return reservation;
        }
        return null;
    }
};

pub fn proposeReservation(
    ledger: *const Ledger,
    expected_revision: Revision,
    inference_operation_id: provider.ProviderOperationId,
    count_evidence: provider.ExactInputTokenCountEvidence,
    effective_maximum_output_tokens: u64,
) ProposalError!ReservationTransition {
    const transition: ReservationTransition = .{
        .expected_revision = expected_revision,
        .operation_id = inference_operation_id,
        .count_operation_id = count_evidence.count_operation_id,
        .exact_input_tokens = count_evidence.input_tokens,
        .maximum_output_tokens = effective_maximum_output_tokens,
    };
    _ = try validateReservation(ledger, transition);
    return transition;
}

pub fn proposeReconciliation(
    ledger: *const Ledger,
    expected_revision: Revision,
    inference_operation_id: provider.ProviderOperationId,
    reconciliation: Reconciliation,
) ProposalError!ReconciliationTransition {
    const transition: ReconciliationTransition = .{
        .expected_revision = expected_revision,
        .operation_id = inference_operation_id,
        .reconciliation = reconciliation,
    };
    try validateReconciliation(ledger, transition);
    return transition;
}

fn validateReservation(ledger: *const Ledger, transition: ReservationTransition) ProposalError!u64 {
    if (!ledger.revision_value.eql(transition.expected_revision)) return error.TokenAccountingRevisionConflict;
    const expected_amount = std.math.add(
        u64,
        transition.exact_input_tokens,
        transition.maximum_output_tokens,
    ) catch return error.WorkflowTokenBudgetExceeded;
    if (transition.operation_id.kind != .inference or
        transition.count_operation_id.kind != .input_token_count or
        !transition.operation_id.sameAttempt(transition.count_operation_id) or
        transition.maximum_output_tokens == 0 or expected_amount == 0)
    {
        return error.InvalidTokenReservation;
    }
    if (ledger.findReservationConst(transition.operation_id) != null) return error.TokenReservationAlreadyExists;
    const used = std.math.add(u64, ledger.committed_tokens, ledger.reserved_tokens) catch {
        return error.WorkflowTokenBudgetExceeded;
    };
    const next_used = std.math.add(u64, used, expected_amount) catch {
        return error.WorkflowTokenBudgetExceeded;
    };
    if (next_used > ledger.total_budget.value) return error.WorkflowTokenBudgetExceeded;
    return expected_amount;
}

fn validateReconciliation(ledger: *const Ledger, transition: ReconciliationTransition) ProposalError!void {
    if (!ledger.revision_value.eql(transition.expected_revision)) return error.TokenAccountingRevisionConflict;
    const reservation = ledger.findReservationConst(transition.operation_id) orelse return error.TokenReservationNotFound;
    if (reservation.status != .active) return error.TokenReservationAlreadyReconciled;
    switch (transition.reconciliation) {
        .exact_usage => |usage| {
            if (provider.ProviderUsage.init(usage.input_tokens, usage.output_tokens, usage.total_tokens) == null or
                usage.input_tokens != reservation.exact_input_tokens or
                usage.output_tokens > reservation.maximum_output_tokens or
                usage.total_tokens > reservation.amount)
            {
                return error.InvalidProviderTokenUsage;
            }
        },
        .not_sent, .retain => {},
    }
}

pub const ProposalError = error{
    InvalidTokenReservation,
    InvalidProviderTokenUsage,
    TokenAccountingRevisionConflict,
    TokenReservationAlreadyExists,
    TokenReservationNotFound,
    TokenReservationAlreadyReconciled,
    WorkflowTokenBudgetExceeded,
};

pub const Error = std.mem.Allocator.Error || ProposalError || error{
    TokenAccountingRevisionExhausted,
};
