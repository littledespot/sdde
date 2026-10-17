//! Runner bindings for source-backed repair; YAML owns rebuilding and review.
const std = @import("std");
const loss = @import("../domain/source_omission.zig");
const ex = @import("../domain/reference_extraction_repair.zig").Omission;
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const data = @import("../domain/pipeline_data.zig");
const pipeline = @import("../domain/pipeline.zig");
const extraction = @import("reference_extraction_workflow.zig");
const rec = @import("reference_reconciliation_workflow.zig");
const reference = @import("../domain/reference_candidate_value.zig");
const authority = @import("required_authority_workflow.zig");
const authority_values = @import("required_authority_values.zig");
const Rejection = struct { reason: loss.Rejection, support: loss.Support };
const owned = @import("retained_candidate.zig").Storage(union(enum) { repair: loss.Repair, rejected: ?Rejection }, .{ .rejected = null });
pub const schema = values.schema(.source_omission_repair, owned.Value, 1, null).captured();
pub const schemas = [_]data.Schema{schema};
pub fn rejection(view: *const data.View) values.Error!?Rejection {
    if (!view.contains(schema.key)) return null;
    const value = owned.payload(try values.read(view, schema, owned.Value));
    return if (value.* == .rejected) value.rejected else null;
}
pub fn read(view: *const data.View) operations.Error!loss.Repair {
    return owned.read(view, schema, .repair) catch |operation_error| operation_error;
}
pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .invalid, .failed };
fn support(view: *const data.View) operations.Error!loss.Support {
    const review = authority_values.read(view, @import("specification_support_workflow.zig").schema, .support) catch |operation_error| return operation_error;
    if (review != .accepted) return error.OperationExecutionFailed;
    return .{ .repair_phase = (try @import("specification_generation_facts.zig").read(view)).phase(), .review = review.accepted.candidate, .inputs = authority_values.read(view, authority.inputs_schema, .inputs) catch |operation_error| return operation_error, .observations = authority_values.read(view, authority.observations_schema, .observations) catch |operation_error| return operation_error, .result = authority_values.read(view, authority.result_schema, .result) catch |operation_error| return operation_error };
}
fn facts(view: *const data.View) operations.Error!ex.Facts {
    const source = values.read(view, @import("reference_evidence_workflow.zig").inputs_schema, @import("../domain/reference_evidence.zig").Inputs) catch |operation_error| return operation_error;
    const candidates = values.read(view, @import("structured_token_workflow.zig").candidates_schema, @import("../domain/structured_tokens.zig").Candidates) catch |operation_error| return operation_error;
    const candidate = try extraction.read(view, extraction.text_schema, .text_validated);
    return .{ .extraction = .{ .inputs = source.*, .candidates = candidates.*, .candidate = candidate.payload().text_validated }, .support = try support(view) };
}
fn parsed(view: *const data.View) operations.Error!@import("../domain/reference_reconciliation.zig").Parsed {
    return (try extraction.read(view, rec.parsed_schema, .reconciliation_parsed)).payload().reconciliation_parsed;
}
pub const Authorize = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .repair_authorize = .{ .kind = .authority, .subject = .required_authority_inputs, .evidence = .required_authority_result, .result = .source_omission_repair } };
    pub const repair_role: @import("../domain/workflow_retry.zig").Role = .authorize;
    pub const Action = @import("../actions/reference/authorize_source_omission_repair.zig").Action;
    pub const outcomes = @import("source_omission_repair_workflow.zig").outcomes;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        errdefer owned.destroy(owner);
        const current = try facts(&input.step.data);
        const state = self.action.execute(owner.arena.allocator(), current, try parsed(&input.step.data), try rec.textContext(&input.step.data)) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            owner.rejection = err;
            owner.payload = .{ .rejected = .{ .reason = if (err == error.UnlocalizedSourceOmission) .unlocalized_omission else if (err == error.PostGenerationSourceRepairForbidden) .post_generation_source_repair_forbidden else .invalid_repair_authority, .support = current.support } };
            return owned.publish(self.allocator, schema, owner, .invalid) catch |operation_error| operation_error;
        };
        owner.payload = .{ .repair = state };
        const permit = switch (state.authorization) {
            inline else => |auth| auth.retry orelse return error.OperationExecutionFailed,
        };
        var result = owned.publish(self.allocator, schema, owner, if (state.authorization == .extraction) .ok else .more) catch |operation_error| return operation_error;
        result.delta.repair_transition = .{ .authorized = permit };
        return result;
    }
};
pub const BuildInput = struct {
    pub const Action = @import("../actions/reference/build_source_omission_repair_input.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const state = owned.read(&input.step.data, schema, .repair) catch |operation_error| return operation_error;
        const packet = self.action.execute(self.allocator, try facts(&input.step.data), try parsed(&input.step.data), try rec.textContext(&input.step.data), state) catch |operation_error| return operation_error;
        return @import("model_request_workflow.zig").publishPacket(self.allocator, packet);
    }
};
pub const Parse = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .preserve = .{ .kind = .authority, .subject = .source_omission_repair, .evidence = .source_omission_repair, .result = .source_omission_repair } };
    pub const Action = @import("../actions/reference/parse_source_omission_repair.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const state = owned.read(&input.step.data, schema, .repair) catch |operation_error| return operation_error;
        const packet = values.read(&input.step.data, @import("model_request_workflow.zig").packet_schema, @import("../domain/model_input_packet.zig").Packet) catch |operation_error| return operation_error;
        const handoff = try @import("model_candidate_handoff.zig").read(&input.step.data);
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        errdefer owned.destroy(owner);
        owner.payload = .{ .repair = self.action.execute(owner.arena.allocator(), state, packet, handoff.body, handoff.origin) catch |operation_error| return operation_error };
        var delta: pipeline.NodeDelta = .{};
        delta.data_replacements[@intFromEnum(schema.key)] = values.adopt(self.allocator, schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch |operation_error| return operation_error;
        return .{ .outcome = .ok, .delta = delta };
    }
};
pub fn Merge(comptime kind: enum { extraction, reconciliation }) type {
    return struct {
        pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .repair_merge = .{ .kind = .candidate, .subject = if (kind == .extraction) .text_validated_reference_extraction else .parsed_reference_reconciliation, .evidence = .source_omission_repair, .result = if (kind == .extraction) .text_validated_reference_extraction else .parsed_reference_reconciliation } };
        pub const repair_role: @import("../domain/workflow_retry.zig").Role = .merge;
        pub const Action = switch (kind) {
            .extraction => @import("../actions/reference/merge_source_extraction_repair.zig").Action,
            .reconciliation => @import("../actions/reference/merge_source_reconciliation_repair.zig").Action,
        };
        pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .failed };
        pub const parameters = [_]@import("../domain/workflow_operation.zig").ParameterDescriptor{.{ .id = "retry-limit", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 0, .integer_max = std.math.maxInt(u32) }};
        pub const retry_limit: @import("../domain/workflow_operation.zig").RetryLimitDescriptor = .{ .maximum = std.math.maxInt(u32), .scope = .repair };
        allocator: std.mem.Allocator,
        action: Action,
        pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
            const self = context.?;
            const state = owned.read(&input.step.data, schema, .repair) catch |operation_error| return operation_error;
            const target = if (kind == .extraction) extraction.text_schema else rec.parsed_schema;
            const prior = try extraction.read(&input.step.data, target, if (kind == .extraction) .text_validated else .reconciliation_parsed);
            const owner = reference.create(self.allocator, prior) catch |operation_error| return operation_error;
            errdefer reference.destroy(owner);
            owner.payload = if (kind == .extraction) .{ .text_validated = self.action.execute(owner.arena.allocator(), try facts(&input.step.data), try rec.textContext(&input.step.data), state) catch |operation_error| return operation_error } else .{ .reconciliation_parsed = self.action.execute(owner.arena.allocator(), try parsed(&input.step.data), try rec.textContext(&input.step.data), try support(&input.step.data), state) catch |operation_error| return operation_error };
            var delta: pipeline.NodeDelta = .{};
            const merged = (if (kind == .extraction) owner.payload.text_validated.last_repair else owner.payload.reconciliation_parsed.source.last_repair) orelse return error.OperationExecutionFailed;
            delta.repair_transition = merged.transition(.dependent_review) catch return error.OperationExecutionFailed;
            delta.data_replacements[@intFromEnum(target.key)] = values.adopt(self.allocator, target, reference.Value, reference.Owner, owner, reference.view, reference.destroy, null) catch |operation_error| return operation_error;
            for (Action.contract.invalidates) |key| delta.data_invalidations.insert(key);
            return .{ .outcome = .ok, .delta = delta };
        }
    };
}
