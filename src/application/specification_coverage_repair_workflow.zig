const std = @import("std");
const data = @import("../domain/pipeline_data.zig");
const repair = @import("../domain/specification_coverage_repair.zig");
const owned = @import("specification_values.zig").storage;
const spec = @import("specification_workflow.zig");
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
pub const schema = values.schema(.specification_coverage_repair, owned.Value, 1, null).captured();
pub const schemas = [_]data.Schema{schema};

pub fn authorizationBlocked(view: *const data.View) values.Error!bool {
    const value = try values.read(view, schema, owned.Value);
    if (!owned.retainsCurrentInputs(value, view)) return error.InvalidCandidatePayload;
    return switch (owned.payload(value).*) {
        .coverage_repair => |decision| decision == .blocked,
        else => error.InvalidCandidatePayload,
    };
}

pub const Authorize = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .repair_authorize = .{ .kind = .candidate, .subject = .specification_generation_session, .evidence = .specification_coverage, .result = .specification_coverage_repair } };
    pub const repair_role: @import("../domain/workflow_retry.zig").Role = .authorize;
    pub const Action = @import("../actions/specification/authorize_specification_coverage_repair.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .blocked, .failed };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const rejection = owned.read(&input.step.data, spec.coverage_schema, .coverage_rejected) catch |operation_error| return operation_error;
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        errdefer owned.destroy(owner);
        const decision = self.action.execute(owner.arena.allocator(), try spec.readSession(&input.step.data), try spec.readContext(&input.step.data), try content(&input.step.data), rejection) catch |operation_error| return operation_error;
        owner.payload = .{ .coverage_repair = decision };
        return owned.publish(self.allocator, schema, owner, .blocked) catch |operation_error| return operation_error;
    }
};
fn content(view: *const data.View) operations.Error!@import("../domain/specification.zig").IdentifiedContent {
    return @import("required_authority_values.zig").read(view, @import("required_authority_workflow.zig").content_schema, .content) catch |operation_error| operation_error;
}
