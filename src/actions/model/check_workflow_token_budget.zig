const pipeline = @import("../../domain/pipeline.zig");
const accounting = @import("../../domain/workflow_token_accounting.zig");

pub const Error = accounting.BudgetError;

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "check-workflow-token-budget@1",
        .kind = .action,
        .requires = &.{},
        .produces = &.{},
        .side_effect = .none,
    };

    pub fn execute(_: Action, ledger: *const accounting.Ledger) Error!void {
        try accounting.checkBudget(ledger);
    }
};
