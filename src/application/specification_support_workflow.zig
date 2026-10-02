const std = @import("std");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const pipeline = @import("../domain/pipeline.zig");
const owned = @import("required_authority_values.zig");
const authority = @import("required_authority_workflow.zig");
const spec = @import("specification_workflow.zig");
const requests = @import("model_request_workflow.zig");
const values = @import("pipeline_values.zig");
pub const schema = values.schema(.specification_support_review, owned.Value, 1, null).captured();
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{schema};
const review = @import("../domain/specification_review.zig");
const purpose_contract = @import("../domain/specification_support.zig");
const a = @import("../domain/required_authority.zig");

pub fn progress(view: *const @import("../domain/pipeline_data.zig").View) operations.Error!review.Progress {
    const current = owned.payload(values.read(view, schema, owned.Value) catch return error.OperationExecutionFailed);
    return switch (current.*) {
        .support_initial => .initial,
        .support => |value| .{ .source = value },
        .principle_pending => |value| .{ .pending = value },
        .principle_support => |value| .{ .principles = value },
        else => error.OperationExecutionFailed,
    };
}
pub fn purpose(current: review.Progress) purpose_contract.Purpose {
    return switch (current) {
        .initial, .source => .source,
        .pending, .principles => .principles,
    };
}
pub fn pending(current: review.Progress) operations.Error!review.Pending {
    return switch (current) {
        .pending => |value| value,
        .principles => |value| value.pending,
        else => error.OperationExecutionFailed,
    };
}
pub fn inputs(view: *const @import("../domain/pipeline_data.zig").View, current: review.Progress) operations.Error!a.Inputs {
    return if (purpose(current) == .principles) (try pending(current)).inputs else owned.read(view, authority.inputs_schema, .inputs) catch error.OperationExecutionFailed;
}
pub fn collection(comptime selected: purpose_contract.Purpose, current: review.Progress) operations.Error!purpose_contract.Contract(selected).Collection {
    if (selected == .source) return if (current == .source) current.source else error.OperationExecutionFailed;
    return if (current == .principles) current.principles.result else error.OperationExecutionFailed;
}
pub fn prior(comptime selected: purpose_contract.Purpose, current: review.Progress) operations.Error!?purpose_contract.Contract(selected).Collection {
    if (selected == .source) return switch (current) {
        .initial => null,
        .source => |result| result,
        else => error.OperationExecutionFailed,
    };
    return switch (current) {
        .pending => null,
        .principles => |result| result.result,
        else => error.OperationExecutionFailed,
    };
}
pub fn retain(owner: *owned.Owner, current: review.Progress) void {
    owner.payload = switch (current) {
        .initial => .support_initial,
        .source => |value| .{ .support = value },
        .pending => |value| .{ .principle_pending = value },
        .principles => |value| .{ .principle_support = value },
    };
}
pub fn publishProgress(allocator: std.mem.Allocator, owner: *owned.Owner, outcome: @import("../domain/workflow.zig").OutcomeTag) operations.Error!execution.Candidate {
    errdefer owned.destroy(owner);
    var delta: pipeline.NodeDelta = .{};
    delta.data_replacements[@intFromEnum(schema.key)] = values.adopt(allocator, schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch return error.OperationExecutionFailed;
    return .{ .outcome = outcome, .delta = delta };
}
pub fn publish(comptime selected: purpose_contract.Purpose, allocator: std.mem.Allocator, owner: *owned.Owner, previous: review.Progress, result: purpose_contract.Contract(selected).Collection) operations.Error!execution.Candidate {
    if (selected == .source) owner.payload = .{ .support = result } else {
        const retained = pending(previous) catch {
            owned.destroy(owner);
            return error.OperationExecutionFailed;
        };
        owner.payload = .{ .principle_support = .{ .pending = retained, .result = result } };
    }
    return publishProgress(allocator, owner, switch (result) {
        .accepted => .ok,
        .pending => .more,
        .rejected => .invalid,
    });
}
pub const Initialize = struct {
    pub const Action = @import("../actions/specification/initialize_specification_review.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = owned.read(&input.step.data, authority.inputs_schema, .inputs) catch return error.OperationExecutionFailed;
        const current = self.action.execute(source) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        retain(owner, current);
        return owned.publish(self.allocator, schema, owner, .ok) catch error.OperationExecutionFailed;
    }
};
pub const BuildInput = struct {
    pub const Action = @import("../actions/specification/build_specification_support_input.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = try progress(&input.step.data);
        const source = try inputs(&input.step.data, current);
        inline for (.{ purpose_contract.Purpose.source, .principles }) |selected| if (purpose(current) == selected) {
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();
            const target = purpose_contract.Contract(selected).nextSubject(arena.allocator(), source, try prior(selected, current)) catch return error.OperationExecutionFailed;
            return requests.publishPacket(self.allocator, self.action.execute(selected, self.allocator, source, try spec.readContext(&input.step.data), target) catch return error.OperationExecutionFailed);
        };
        unreachable;
    }
};
pub const Collect = struct {
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .invalid, .failed };
    pub const Action = @import("../actions/specification/collect_specification_support.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = try progress(&input.step.data);
        const source = try inputs(&input.step.data, current);
        const packet = values.read(&input.step.data, requests.packet_schema, @import("../domain/model_input_packet.zig").Packet) catch return error.OperationExecutionFailed;
        const handoff = try @import("model_candidate_handoff.zig").read(&input.step.data);
        const source_context = try spec.readContext(&input.step.data);
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        inline for (.{ purpose_contract.Purpose.source, .principles }) |selected| if (purpose(current) == selected) {
            const result = self.action.execute(selected, owner.arena.allocator(), source, source_context, try prior(selected, current), packet, handoff.body, handoff.origin) catch {
                owned.destroy(owner);
                return error.OperationExecutionFailed;
            };
            return publish(selected, self.allocator, owner, current, result);
        };
        unreachable;
    }
};
pub const CheckLocalization = struct {
    pub const Action = @import("../actions/specification/check_specification_support_localization.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .invalid };
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        return .{ .outcome = switch (context.?.action.execute(try progress(&input.step.data))) {
            .complete => .ok,
            .next => .more,
            .localize => .invalid,
        }, .delta = .{} };
    }
};
pub const BuildLossInput = struct {
    pub const Action = @import("../actions/specification/build_specification_support_loss_input.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = try progress(&input.step.data);
        if (current != .source) return error.OperationExecutionFailed;
        return requests.publishPacket(self.allocator, self.action.execute(self.allocator, try inputs(&input.step.data, current), try spec.readContext(&input.step.data), current.source) catch return error.OperationExecutionFailed);
    }
};
pub const CollectLoss = struct {
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .invalid, .failed };
    pub const Action = @import("../actions/specification/collect_specification_support_loss.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = try progress(&input.step.data);
        if (current != .source) return error.OperationExecutionFailed;
        const packet = values.read(&input.step.data, requests.packet_schema, @import("../domain/model_input_packet.zig").Packet) catch return error.OperationExecutionFailed;
        const handoff = try @import("model_candidate_handoff.zig").read(&input.step.data);
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        const result = self.action.execute(owner.arena.allocator(), try inputs(&input.step.data, current), try spec.readContext(&input.step.data), current.source, packet, handoff.body) catch {
            owned.destroy(owner);
            return error.OperationExecutionFailed;
        };
        return publish(.source, self.allocator, owner, current, result);
    }
};
pub const Advance = struct {
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .failed };
    pub const Action = @import("../actions/specification/advance_specification_review.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = try progress(&input.step.data);
        const registry = values.read(&input.step.data, @import("principle_workflow.zig").registry_schema, @import("../domain/principle_registry.zig").Registry) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        const result = self.action.execute(owner.arena.allocator(), current, registry.*) catch {
            owned.destroy(owner);
            return error.OperationExecutionFailed;
        };
        retain(owner, result.progress);
        return publishProgress(self.allocator, owner, if (result.outcome == .more) .more else .ok);
    }
};

/// Only admission of a completed review advances authority inputs. Repair keeps
/// the source projection unchanged, preserving its generation and lineage.
pub const Apply = struct {
    pub const repair_role: @import("../domain/workflow_retry.zig").Role = .validate;
    pub const Action = @import("../actions/specification/apply_specification_support.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const reviewed = owned.read(&input.step.data, schema, .support) catch return error.OperationExecutionFailed;
        if (reviewed == .accepted and reviewed.accepted.candidate.pending_localization != null) return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .inputs = self.action.execute(reviewed) catch return error.OperationExecutionFailed };
        var delta: pipeline.NodeDelta = .{};
        if (input.step.repair_permit) |active| {
            delta.repair_transition = @import("../domain/specification_coverage_repair.zig").admittedOmissionValidation(owner.arena.allocator(), active, reviewed.accepted) catch return error.OperationExecutionFailed;
            if (delta.repair_transition == null)
                delta.repair_transition = @import("../domain/source_omission.zig").admittedValidation(owner.arena.allocator(), active, reviewed.accepted) catch return error.OperationExecutionFailed;
        }
        delta.data_replacements[@intFromEnum(authority.inputs_schema.key)] = values.adopt(self.allocator, authority.inputs_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch return error.OperationExecutionFailed;
        return .{ .outcome = .ok, .delta = delta };
    }
};
