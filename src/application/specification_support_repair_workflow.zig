//! Runner bindings for the shared review repair contract; YAML owns retries.
const std = @import("std");
const repair = @import("../domain/specification_support_repair.zig").Source;
const repair_owner = @import("../domain/repair_owner.zig");
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
        .support_repair => false,
        .rejected => (try authorizationRejectionOutcome(owned.rejection(value) orelse return error.InvalidCandidatePayload)) == .blocked,
        else => error.InvalidCandidatePayload,
    };
}

fn read(view: *const @import("../domain/pipeline_data.zig").View) operations.Error!repair.State {
    return owned.read(view, schema, .support_repair) catch |operation_error| operation_error;
}
/// The current rejected review the repair addresses.
fn rejected(view: *const @import("../domain/pipeline_data.zig").View) operations.Error!@FieldType(@import("../domain/specification_support.zig").Source.Collection, "rejected") {
    const progress = try support.progress(view);
    if (progress != .source or progress.source != .rejected) return error.OperationExecutionFailed;
    return progress.source.rejected;
}
pub const Authorize = struct {
    pub const effects: repair_owner.Effects = .{
        .requires = &.{ .required_authority_inputs, .specification_support_review, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .packet_guidance },
        .produces = &.{.specification_support_repair},
    };
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .repair_authorize = .{ .kind = .candidate, .subject = .specification_support_review, .evidence = .specification_support_review, .result = .specification_support_repair } };
    pub const repair_role: @import("../domain/workflow_retry.zig").Role = .authorize;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .blocked, .failed };
    allocator: std.mem.Allocator,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = try support.inputs(&input.step.data);
        const current = try rejected(&input.step.data);
        const context_value = try spec.readContext(&input.step.data);
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        errdefer owned.destroy(owner);
        const authorization = repair.authorize(owner.arena.allocator(), source, context_value, try @import("packet_guidance_workflow.zig").read(&input.step.data), current) catch |err| {
            const outcome = try authorizationRejectionOutcome(err);
            owner.rejection = err;
            return owned.publish(self.allocator, schema, owner, outcome) catch |operation_error| operation_error;
        };
        const permit = authorization.retry orelse return error.OperationExecutionFailed;
        owner.payload = .{ .support_repair = .{ .authorization = authorization } };
        var candidate = owned.publish(self.allocator, schema, owner, if (authorization.operation == .delete) .more else .ok) catch |operation_error| return operation_error;
        candidate.delta.repair_transition = .{ .authorized = permit };
        return candidate;
    }
};

fn authorizationRejectionOutcome(err: execution.OperationError) error{OutOfMemory}!@import("../domain/workflow.zig").OutcomeTag {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    return .blocked;
}
pub const BuildInput = struct {
    pub const effects: repair_owner.Effects = .{
        .requires = &.{ .required_authority_inputs, .specification_support_review, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .specification_support_repair, .packet_guidance },
        .produces = &.{.model_input_packet},
    };
    allocator: std.mem.Allocator,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = try support.inputs(&input.step.data);
        const state = try read(&input.step.data);
        const candidate = (try rejected(&input.step.data)).candidate orelse return error.OperationExecutionFailed;
        return @import("model_request_workflow.zig").publishPacket(self.allocator, repair.packet(self.allocator, source, try spec.readContext(&input.step.data), try @import("packet_guidance_workflow.zig").read(&input.step.data), candidate, state.authorization) catch |operation_error| return operation_error);
    }
};
pub const Parse = struct {
    pub const effects: repair_owner.Effects = .{
        .requires = &.{ .specification_support_repair, .model_request_identity_ledger, .prepared_model_request, .model_input_packet, .model_payload_schema_result },
        .replaces = &.{.specification_support_repair},
    };
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .preserve = .{ .kind = .candidate, .subject = .specification_support_repair, .evidence = .specification_support_repair, .result = .specification_support_repair } };
    allocator: std.mem.Allocator,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const state = try read(&input.step.data);
        const packet = values.read(&input.step.data, @import("model_request_workflow.zig").packet_schema, @import("../domain/model_input_packet.zig").Packet) catch |operation_error| return operation_error;
        const handoff = try @import("model_candidate_handoff.zig").read(&input.step.data);
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        errdefer owned.destroy(owner);
        owner.payload = .{ .support_repair = .{ .authorization = state.authorization, .response = .{ .value = repair.parse(owner.arena.allocator(), state.authorization, packet, handoff.body) catch |operation_error| return operation_error, .origin = handoff.origin } } };
        var delta: @import("../domain/pipeline.zig").NodeDelta = .{};
        delta.data_replacements[@intFromEnum(schema.key)] = values.adopt(self.allocator, schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch |operation_error| return operation_error;
        return .{ .outcome = .ok, .delta = delta };
    }
};
pub const Merge = struct {
    pub const effects: repair_owner.Effects = .{
        .requires = &.{ .required_authority_inputs, .specification_support_review, .model_request_identity_ledger, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .specification_support_repair, .packet_guidance },
        .replaces = &.{.specification_support_review},
        .invalidates = &.{.specification_support_repair},
    };
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .repair_validate = .{ .kind = .candidate, .subject = .specification_support_review, .evidence = .specification_support_repair, .result = .specification_support_review } };
    pub const repair_role: @import("../domain/workflow_retry.zig").Role = .merge_validate;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .invalid, .failed };
    pub const parameters = [_]@import("../domain/workflow_operation.zig").ParameterDescriptor{.{ .id = "retry-limit", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 0, .integer_max = std.math.maxInt(u32) }};
    pub const retry_limit: @import("../domain/workflow_operation.zig").RetryLimitDescriptor = .{ .maximum = std.math.maxInt(u32), .scope = .repair };
    allocator: std.mem.Allocator,
    normalizer: @import("../ports/unicode_normalizer.zig").Normalizer,

    /// The canonical text is built and released inside the merge, before the caller owns the result.
    fn merged(self: *@This(), a: std.mem.Allocator, source: @import("../domain/required_authority.zig").Inputs, context_value: @import("../domain/specification_provenance.zig").Context, guidance: *const @import("../domain/packet_guidance.zig").Guidance, candidate: @import("../domain/specification_support.zig").Source.Candidate, state: repair.State) repair.Error!@import("../domain/specification_support.zig").Source.Collection {
        var canonical = try @import("../domain/typed_text.zig").CanonicalText.fromInputs(a, self.normalizer, context_value.inputs);
        defer canonical.deinit(a);
        return repair.merge(a, canonical, source, context_value, guidance, candidate, state.authorization, if (state.response) |response| response.value else null, if (state.response) |response| response.origin else null);
    }

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = try support.inputs(&input.step.data);
        const current = (try rejected(&input.step.data)).candidate orelse return error.OperationExecutionFailed;
        const state = try read(&input.step.data);
        const context_value = try spec.readContext(&input.step.data);
        const guidance = try @import("packet_guidance_workflow.zig").read(&input.step.data);
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        const result = self.merged(owner.arena.allocator(), source, context_value, guidance, current, state) catch |native_failure| {
            owned.destroy(owner);
            return native_failure;
        };
        var candidate = try support.publish(self.allocator, owner, result);
        errdefer for (candidate.delta.data_replacements) |value| if (value) |allocation| values.destroy(allocation);
        const repaired = switch (result) {
            .accepted => |value| value.candidate,
            .pending => |value| value,
            .rejected => |value| value.candidate orelse return error.OperationExecutionFailed,
        };
        const merge = repaired.last_repair orelse return error.OperationExecutionFailed;
        candidate.delta.repair_transition = merge.validatedTransition(repair.progress(state.authorization, result)) catch return error.OperationExecutionFailed;
        for (effects.invalidates) |key| candidate.delta.data_invalidations.insert(key);
        return candidate;
    }
};
