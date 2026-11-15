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
const Source = @import("../domain/specification_support.zig").Source;
const a = @import("../domain/required_authority.zig");

pub fn progress(view: *const @import("../domain/pipeline_data.zig").View) operations.Error!review.Progress {
    const current = owned.payload(values.read(view, schema, owned.Value) catch |operation_error| return operation_error);
    return switch (current.*) {
        .support_initial => .initial,
        .support => |value| .{ .source = value },
        else => error.InvalidCandidatePayload,
    };
}
pub fn inputs(view: *const @import("../domain/pipeline_data.zig").View) operations.Error!a.Inputs {
    return owned.read(view, authority.inputs_schema, .inputs) catch |operation_error| operation_error;
}
pub fn prior(current: review.Progress) ?Source.Collection {
    return switch (current) {
        .initial => null,
        .source => |result| result,
    };
}
pub fn retain(owner: *owned.Owner, current: review.Progress) void {
    owner.payload = switch (current) {
        .initial => .support_initial,
        .source => |value| .{ .support = value },
    };
}
pub fn publishProgress(allocator: std.mem.Allocator, owner: *owned.Owner, outcome: @import("../domain/workflow.zig").OutcomeTag) operations.Error!execution.Candidate {
    errdefer owned.destroy(owner);
    var delta: pipeline.NodeDelta = .{};
    delta.data_replacements[@intFromEnum(schema.key)] = values.adopt(allocator, schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch |operation_error| return operation_error;
    return .{ .outcome = outcome, .delta = delta };
}
pub fn publish(allocator: std.mem.Allocator, owner: *owned.Owner, result: Source.Collection) operations.Error!execution.Candidate {
    owner.payload = .{ .support = result };
    return publishProgress(allocator, owner, switch (result) {
        .accepted => .ok,
        .pending => .more,
        .rejected => .invalid,
    });
}

pub const Initialize = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .preserve = .{ .kind = .candidate, .subject = .required_authority_inputs, .evidence = .required_authority_inputs, .result = .specification_support_review } };
    pub const Action = @import("../actions/specification/initialize_specification_review.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = owned.read(&input.step.data, authority.inputs_schema, .inputs) catch |operation_error| return operation_error;
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        errdefer owned.destroy(owner);
        const current = self.action.execute(source) catch |operation_error| return operation_error;
        retain(owner, current);
        return owned.publish(self.allocator, schema, owner, .ok) catch |operation_error| operation_error;
    }
};
pub const BuildInput = struct {
    pub const Action = @import("../actions/specification/build_specification_support_input.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = try progress(&input.step.data);
        const source = try inputs(&input.step.data);
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const target = Source.nextSubject(arena.allocator(), source, prior(current)) catch |operation_error| return operation_error;
        return requests.publishPacket(self.allocator, self.action.execute(self.allocator, source, try spec.readContext(&input.step.data), try @import("packet_guidance_workflow.zig").read(&input.step.data), target) catch |operation_error| return operation_error);
    }
};
pub const Collect = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .diagnostic_admission = .{ .kind = .candidate, .subject = .specification_support_review, .evidence = .specification_support_review, .result = .specification_support_review } };
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .invalid, .failed };
    pub const Action = @import("../actions/specification/collect_specification_support.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = try progress(&input.step.data);
        const source = try inputs(&input.step.data);
        const packet = values.read(&input.step.data, requests.packet_schema, @import("../domain/model_input_packet.zig").Packet) catch |operation_error| return operation_error;
        const handoff = (try @import("model_candidate_handoff.zig").readAccepted(&input.step.data)).candidate;
        const source_context = try spec.readContext(&input.step.data);
        const guidance = try @import("packet_guidance_workflow.zig").read(&input.step.data);
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        const result = self.action.execute(owner.arena.allocator(), source, source_context, guidance, prior(current), packet, handoff.body, handoff.origin) catch |native_failure| {
            owned.destroy(owner);
            return native_failure;
        };
        return publish(self.allocator, owner, result);
    }
};
pub const CheckLocalization = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .observe = .{ .kind = .candidate, .subject = .specification_support_review, .evidence = .specification_support_review } };
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
        if (current != .source) return error.SupportReviewStateInvalid;
        return requests.publishPacket(self.allocator, self.action.execute(self.allocator, try inputs(&input.step.data), try spec.readContext(&input.step.data), try @import("packet_guidance_workflow.zig").read(&input.step.data), current.source) catch |operation_error| return operation_error);
    }
};
pub const CollectLoss = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .diagnostic_admission = .{ .kind = .candidate, .subject = .specification_support_review, .evidence = .specification_support_review, .result = .specification_support_review } };
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .invalid, .failed };
    pub const Action = @import("../actions/specification/collect_specification_support_loss.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = try progress(&input.step.data);
        if (current != .source) return error.SupportReviewStateInvalid;
        const packet = values.read(&input.step.data, requests.packet_schema, @import("../domain/model_input_packet.zig").Packet) catch |operation_error| return operation_error;
        const handoff = try @import("model_candidate_handoff.zig").read(&input.step.data);
        const source = try inputs(&input.step.data);
        const source_context = try spec.readContext(&input.step.data);
        const guidance = try @import("packet_guidance_workflow.zig").read(&input.step.data);
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        const result = self.action.execute(owner.arena.allocator(), source, source_context, guidance, current.source, packet, handoff.body, handoff.origin) catch |native_failure| {
            owned.destroy(owner);
            return native_failure;
        };
        return publish(self.allocator, owner, result);
    }
};
/// Only admission of a completed review advances authority inputs. Repair keeps
/// the source projection unchanged, preserving its generation and lineage.
pub const Apply = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .repair_validate = .{ .kind = .candidate, .subject = .specification_support_review, .evidence = .specification_support_review, .result = .required_authority_inputs } };
    pub const repair_role: @import("../domain/workflow_retry.zig").Role = .validate;
    pub const Action = @import("../actions/specification/apply_specification_support.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .invalid, .failed };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const reviewed = owned.read(&input.step.data, schema, .support) catch |operation_error| return operation_error;
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        errdefer owned.destroy(owner);
        if (reviewed == .accepted and reviewed.accepted.candidate.pending_localization != null) return rejected(self.allocator, owner);
        owner.payload = .{ .inputs = self.action.execute(reviewed) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidRequiredAuthority => return rejected(self.allocator, owner),
        } };
        var delta: pipeline.NodeDelta = .{};
        if (input.step.repair_permit) |active| {
            delta.repair_transition = @import("../domain/source_omission.zig").admittedValidation(owner.arena.allocator(), active, reviewed.accepted) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidRequiredAuthority => return rejected(self.allocator, owner),
            };
        }
        delta.data_replacements[@intFromEnum(authority.inputs_schema.key)] = values.adopt(self.allocator, authority.inputs_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch |operation_error| return operation_error;
        return .{ .outcome = .ok, .delta = delta };
    }

    fn rejected(allocator: std.mem.Allocator, owner: *owned.Owner) operations.Error!execution.Candidate {
        owner.payload = .{ .rejected = .invalid_contract };
        owner.rejection = error.InvalidRequiredAuthority;
        var delta: pipeline.NodeDelta = .{};
        delta.data_replacements[@intFromEnum(authority.inputs_schema.key)] = try values.adopt(allocator, authority.inputs_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null);
        return .{ .outcome = .invalid, .delta = delta, .diagnostic = error.InvalidRequiredAuthority };
    }
};
