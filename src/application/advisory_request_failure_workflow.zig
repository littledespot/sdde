const operations = @import("../ports/workflow_operation_registry.zig");
pub const Propagate = struct {
    pub const Action = @import("../actions/model/propagate_advisory_request_failure.zig").Action;
    pub const contract: @import("../domain/workflow_operation.zig").Contract = .{
        .id = Action.contract.id,
        .kind = .step,
        .requires = Action.contract.requires,
        .outcomes = &.{.failed},
        .side_effect = .none,
        .outcome_association = .{ .preserve = .{ .kind = .request, .subject = .prepared_model_request, .evidence = .model_request_identity_ledger } },
    };
    action: Action = .{},
    pub fn invoke(context: ?*@This(), _: operations.Input) operations.Error!@import("../domain/workflow_execution.zig").Candidate {
        return .{ .outcome = context.?.action.execute(), .delta = .{} };
    }
};
