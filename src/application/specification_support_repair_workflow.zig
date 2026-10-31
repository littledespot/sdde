//! Runner bindings for the shared review repair contract; YAML owns retries.
const std = @import("std");
const repair = @import("../domain/specification_support_repair.zig");
const Purpose = @import("../domain/specification_support.zig").Purpose;
const support = @import("specification_support_workflow.zig");
const owned = @import("required_authority_values.zig");
const spec = @import("specification_workflow.zig");
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
pub const schema = values.schema(.specification_support_repair, owned.Value, 1, null).captured();
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{schema};

pub fn authorizationBlocked(view: *const @import("../domain/pipeline_data.zig").View) values.Error!bool {
    const value = try values.read(view, schema, owned.Value);
    if (!owned.retainsCurrentInputs(value, view)) return error.InvalidCandidatePayload;
    return switch (owned.payload(value).*) {
        .support_repair, .principle_support_repair => false,
        .rejected => (try authorizationRejectionOutcome(owned.rejection(value) orelse return error.InvalidCandidatePayload)) == .blocked,
        else => error.InvalidCandidatePayload,
    };
}

fn read(comptime selected: Purpose, view: *const @import("../domain/pipeline_data.zig").View) operations.Error!repair.Contract(selected).State {
    return owned.read(view, schema, if (selected == .source) .support_repair else .principle_support_repair) catch |operation_error| operation_error;
}
fn retain(comptime selected: Purpose, owner: *owned.Owner, state: repair.Contract(selected).State) void {
    owner.payload = if (selected == .source) .{ .support_repair = state } else .{ .principle_support_repair = state };
}
pub const Authorize = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .repair_authorize = .{ .kind = .candidate, .subject = .specification_support_review, .evidence = .specification_support_review, .result = .specification_support_repair } };
    pub const repair_role: @import("../domain/workflow_retry.zig").Role = .authorize;
    pub const Action = @import("../actions/specification/authorize_specification_support_repair.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .blocked, .failed };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const progress = try support.progress(&input.step.data);
        const source = try support.inputs(&input.step.data, progress);
        inline for (.{ Purpose.source, .principles }) |selected| if (support.purpose(progress) == selected) {
            const current = try support.collection(selected, progress);
            if (current != .rejected) return error.OperationExecutionFailed;
            const context_value = try spec.readContext(&input.step.data);
            const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
            errdefer owned.destroy(owner);
            const authorization = self.action.execute(selected, owner.arena.allocator(), source, context_value, try @import("packet_guidance_workflow.zig").read(&input.step.data), current.rejected) catch |err| {
                const outcome = try authorizationRejectionOutcome(err);
                owner.rejection = err;
                return owned.publish(self.allocator, schema, owner, outcome) catch |operation_error| operation_error;
            };
            const permit = authorization.retry orelse return error.OperationExecutionFailed;
            retain(selected, owner, .{ .authorization = authorization });
            var candidate = owned.publish(self.allocator, schema, owner, if (authorization.operation == .delete) .more else .ok) catch |operation_error| return operation_error;
            candidate.delta.repair_transition = .{ .authorized = permit };
            return candidate;
        };
        unreachable;
    }
};

fn authorizationRejectionOutcome(err: execution.OperationError) error{OutOfMemory}!@import("../domain/workflow.zig").OutcomeTag {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    return .blocked;
}
pub const BuildInput = struct {
    pub const Action = @import("../actions/specification/build_specification_support_repair_input.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const progress = try support.progress(&input.step.data);
        const source = try support.inputs(&input.step.data, progress);
        inline for (.{ Purpose.source, .principles }) |selected| if (support.purpose(progress) == selected) {
            const state = try read(selected, &input.step.data);
            const current = try support.collection(selected, progress);
            if (current != .rejected or current.rejected.candidate == null) return error.OperationExecutionFailed;
            return @import("model_request_workflow.zig").publishPacket(self.allocator, self.action.execute(selected, self.allocator, source, try spec.readContext(&input.step.data), try @import("packet_guidance_workflow.zig").read(&input.step.data), current.rejected.candidate.?, state.authorization) catch |operation_error| return operation_error);
        };
        unreachable;
    }
};
pub const Parse = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .preserve = .{ .kind = .candidate, .subject = .specification_support_repair, .evidence = .specification_support_repair, .result = .specification_support_repair } };
    pub const Action = @import("../actions/specification/parse_specification_support_repair.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const payload = owned.payload(values.read(&input.step.data, schema, owned.Value) catch |operation_error| return operation_error);
        inline for (.{ Purpose.source, .principles }) |selected| if (payload.* == (if (selected == .source) .support_repair else .principle_support_repair)) {
            const state = try read(selected, &input.step.data);
            const packet = values.read(&input.step.data, @import("model_request_workflow.zig").packet_schema, @import("../domain/model_input_packet.zig").Packet) catch |operation_error| return operation_error;
            const handoff = try @import("model_candidate_handoff.zig").read(&input.step.data);
            const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
            errdefer owned.destroy(owner);
            retain(selected, owner, .{ .authorization = state.authorization, .response = .{ .value = self.action.execute(selected, owner.arena.allocator(), state.authorization, packet, handoff.body) catch |operation_error| return operation_error, .origin = handoff.origin } });
            var delta: @import("../domain/pipeline.zig").NodeDelta = .{};
            delta.data_replacements[@intFromEnum(schema.key)] = values.adopt(self.allocator, schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch |operation_error| return operation_error;
            return .{ .outcome = .ok, .delta = delta };
        };
        return error.OperationExecutionFailed;
    }
};
pub const Merge = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .repair_validate = .{ .kind = .candidate, .subject = .specification_support_review, .evidence = .specification_support_repair, .result = .specification_support_review } };
    pub const repair_role: @import("../domain/workflow_retry.zig").Role = .merge_validate;
    pub const Action = @import("../actions/specification/merge_specification_support_repair.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .invalid, .failed };
    pub const parameters = [_]@import("../domain/workflow_operation.zig").ParameterDescriptor{.{ .id = "retry-limit", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 0, .integer_max = std.math.maxInt(u32) }};
    pub const retry_limit: @import("../domain/workflow_operation.zig").RetryLimitDescriptor = .{ .maximum = std.math.maxInt(u32), .scope = .repair };
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const progress = try support.progress(&input.step.data);
        const source = try support.inputs(&input.step.data, progress);
        inline for (.{ Purpose.source, .principles }) |selected| if (support.purpose(progress) == selected) {
            const current = try support.collection(selected, progress);
            if (current != .rejected or current.rejected.candidate == null) return error.OperationExecutionFailed;
            const state = try read(selected, &input.step.data);
            const context_value = try spec.readContext(&input.step.data);
            const history = try owned.read(&input.step.data, support.history_schema, .review_history);
            const ledger = try values.read(&input.step.data, @import("model_request_workflow.zig").ledger_schema, @import("../domain/model_request_identity.zig").ModelRequestIdentityLedger);
            const guidance = try @import("packet_guidance_workflow.zig").read(&input.step.data);
            const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
            const merged = self.action.execute(selected, owner.arena.allocator(), source, context_value, guidance, current.rejected.candidate.?, state, history, ledger) catch |native_failure| {
                owned.destroy(owner);
                return native_failure;
            };
            const result = merged.collection;
            var candidate = try support.publish(selected, self.allocator, owner, progress, result);
            errdefer for (candidate.delta.data_replacements) |value| if (value) |allocation| values.destroy(allocation);
            try support.attachHistory(self.allocator, input.step.data, &candidate, merged.history);
            const repaired = switch (result) {
                .accepted => |value| value.candidate,
                .pending => |value| value,
                .rejected => |value| value.candidate orelse return error.OperationExecutionFailed,
            };
            const merge = repaired.last_repair orelse return error.OperationExecutionFailed;
            candidate.delta.repair_transition = merge.validatedTransition(repair.Contract(selected).progress(state.authorization, result)) catch return error.OperationExecutionFailed;
            for (Action.contract.invalidates) |key| candidate.delta.data_invalidations.insert(key);
            return candidate;
        };
        unreachable;
    }
};
