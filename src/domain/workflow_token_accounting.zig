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

// Only validated provider observations enter this boundary. Missing usage is
// never estimated; only proven non-delivery permits a zero-charge disposition.
pub const Reconciliation = union(enum) {
    exact_usage: provider.ProviderUsage,
    not_sent,
    unavailable,
};

pub const ReconciliationTransition = struct {
    expected_revision: Revision,
    operation_id: provider.ProviderOperationId,
    reconciliation: Reconciliation,
};

pub const BudgetStatus = enum { available, exhausted, exceeded, usage_unavailable };

pub const Ledger = struct {
    allocator: std.mem.Allocator,
    total_budget: TotalTokenBudget,
    revision_value: Revision = .initial,
    // One API report is u64; a cumulative total may exceed even a u64 budget.
    committed_tokens: u128 = 0,
    usage_unavailable: bool = false,
    accounted_operations: std.ArrayListUnmanaged(provider.ProviderOperationId) = .empty,

    pub fn init(allocator: std.mem.Allocator, total_budget: TotalTokenBudget) ?Ledger {
        if (!total_budget.isValid()) return null;
        return .{ .allocator = allocator, .total_budget = total_budget };
    }

    pub fn deinit(self: *Ledger) void {
        self.accounted_operations.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn revision(self: *const Ledger) Revision {
        return self.revision_value;
    }

    pub fn totalTokenBudget(self: *const Ledger) TotalTokenBudget {
        return self.total_budget;
    }

    pub fn committed(self: *const Ledger) u128 {
        return self.committed_tokens;
    }

    pub fn status(self: *const Ledger) BudgetStatus {
        if (self.usage_unavailable) return .usage_unavailable;
        if (self.committed_tokens > self.total_budget.value) return .exceeded;
        if (self.committed_tokens == self.total_budget.value) return .exhausted;
        return .available;
    }

    pub fn applyReconciliation(self: *Ledger, transition: ReconciliationTransition) Error!BudgetStatus {
        try validateReconciliation(self, transition);
        const next_revision = std.math.add(u64, self.revision_value.value, 1) catch
            return error.TokenAccountingRevisionExhausted;
        const amount: u64 = switch (transition.reconciliation) {
            .exact_usage => |usage| usage.total_tokens,
            .not_sent, .unavailable => 0,
        };
        // At most u64 revisions, each adding at most u64 tokens, fits u128.
        const next_total = self.committed_tokens + @as(u128, amount);
        try self.accounted_operations.append(self.allocator, transition.operation_id);
        self.committed_tokens = next_total;
        if (transition.reconciliation == .unavailable) self.usage_unavailable = true;
        self.revision_value = .{ .value = next_revision };
        return self.status();
    }

    fn contains(self: *const Ledger, id: provider.ProviderOperationId) bool {
        for (self.accounted_operations.items) |prior| if (prior.eql(id)) return true;
        return false;
    }
};

pub fn checkBudget(ledger: *const Ledger) BudgetError!void {
    switch (ledger.status()) {
        .available => {},
        .exhausted, .exceeded => return error.WorkflowTokenBudgetExceeded,
        .usage_unavailable => return error.ProviderTokenUsageUnavailable,
    }
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

fn validateReconciliation(ledger: *const Ledger, transition: ReconciliationTransition) ProposalError!void {
    if (!ledger.revision_value.eql(transition.expected_revision)) return error.TokenAccountingRevisionConflict;
    if (transition.operation_id.kind != .inference or
        transition.operation_id.model_attempt_ordinal.value == 0) return error.InvalidTokenAccountingOperation;
    if (ledger.contains(transition.operation_id)) return error.TokenUsageAlreadyAccounted;
    switch (transition.reconciliation) {
        .exact_usage => |usage| {
            if (provider.ProviderUsage.init(usage.input_tokens, usage.output_tokens, usage.total_tokens) == null)
                return error.InvalidProviderTokenUsage;
        },
        .not_sent, .unavailable => {},
    }
}

pub const BudgetError = error{ WorkflowTokenBudgetExceeded, ProviderTokenUsageUnavailable };
pub const ProposalError = error{
    InvalidTokenAccountingOperation,
    InvalidProviderTokenUsage,
    TokenAccountingRevisionConflict,
    TokenUsageAlreadyAccounted,
};
pub const Error = std.mem.Allocator.Error || ProposalError || error{TokenAccountingRevisionExhausted};
