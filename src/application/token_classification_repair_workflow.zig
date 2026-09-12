//! Typed domain bindings into the shared request and atomic-repair contracts.
const std = @import("std");
const data = @import("../domain/pipeline_data.zig");
const pipeline = @import("../domain/pipeline.zig");
const repair = @import("../domain/token_classification_repair.zig");
const tokens = @import("structured_token_workflow.zig");
const extraction = @import("reference_extraction_workflow.zig");
const reference = @import("../domain/reference_candidate_value.zig");
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const owned = @import("retained_candidate.zig").Storage(union(enum) {
    authorization: repair.Authorization,
    replacement: repair.Replacement,
    rejected,
}, .rejected);
pub const authorization_schema = values.schema(.token_classification_repair_authorization, owned.Value, 1, null).captured();
pub const result_schema = values.schema(.token_classification_repair_result, owned.Value, 1, null).captured();
pub const schemas = [_]data.Schema{ authorization_schema, result_schema };
const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .invalid, .failed };

pub const Authorize = struct {
    pub const Action = @import("../actions/reference/authorize_token_classification_repair.zig").Action;
    pub const outcomes = @import("token_classification_repair_workflow.zig").outcomes;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        _ = try extraction.read(&input.step.data, tokens.classified_schema, .token_classification_rejected);
        const prior = try extraction.read(&input.step.data, extraction.text_schema, .text_validated);
        const source = values.read(&input.step.data, @import("reference_evidence_workflow.zig").inputs_schema, @import("../domain/reference_evidence.zig").Inputs) catch return error.OperationExecutionFailed;
        const candidates = values.read(&input.step.data, tokens.candidates_schema, @import("../domain/structured_tokens.zig").Candidates) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .authorization = self.action.execute(owner.arena.allocator(), source.*, candidates.*, prior.payload().text_validated) catch |err| return reject(self.allocator, authorization_schema, owner, err) };
        return owned.publish(self.allocator, authorization_schema, owner, .ok) catch error.OperationExecutionFailed;
    }
};
pub const BuildInput = struct {
    pub const Action = @import("../actions/reference/build_token_classification_repair_input.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const authorization = owned.read(&input.step.data, authorization_schema, .authorization) catch return error.OperationExecutionFailed;
        const prior = try extraction.read(&input.step.data, extraction.text_schema, .text_validated);
        const source = values.read(&input.step.data, @import("reference_evidence_workflow.zig").inputs_schema, @import("../domain/reference_evidence.zig").Inputs) catch return error.OperationExecutionFailed;
        const candidates = values.read(&input.step.data, tokens.candidates_schema, @import("../domain/structured_tokens.zig").Candidates) catch return error.OperationExecutionFailed;
        const literals = values.read(&input.step.data, @import("passive_literal_workflow.zig").registry_schema, @import("../domain/passive_literals.zig").Registry) catch return error.OperationExecutionFailed;
        const packet = self.action.execute(self.allocator, source.*, literals.*, candidates.*, prior.payload().text_validated, authorization) catch return error.OperationExecutionFailed;
        return @import("model_request_workflow.zig").publishPacket(self.allocator, packet);
    }
};
pub const Parse = struct {
    pub const Action = @import("../actions/reference/parse_token_classification_repair.zig").Action;
    pub const outcomes = @import("token_classification_repair_workflow.zig").outcomes;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const authorization = owned.read(&input.step.data, authorization_schema, .authorization) catch return error.OperationExecutionFailed;
        const packet = values.read(&input.step.data, @import("model_request_workflow.zig").packet_schema, @import("../domain/model_input_packet.zig").Packet) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .replacement = self.action.execute(owner.arena.allocator(), authorization, packet, try @import("model_candidate_handoff.zig").body(&input.step.data)) catch |err| return reject(self.allocator, result_schema, owner, err) };
        return owned.publish(self.allocator, result_schema, owner, .ok) catch error.OperationExecutionFailed;
    }
};
pub const Merge = struct {
    pub const Action = @import("../actions/reference/merge_token_classification_repair.zig").Action;
    pub const outcomes = @import("token_classification_repair_workflow.zig").outcomes;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const authorization = owned.read(&input.step.data, authorization_schema, .authorization) catch return error.OperationExecutionFailed;
        const replacement = owned.read(&input.step.data, result_schema, .replacement) catch return error.OperationExecutionFailed;
        const prior = try extraction.read(&input.step.data, extraction.text_schema, .text_validated);
        const owner = reference.create(self.allocator, prior) catch return error.OperationExecutionFailed;
        errdefer reference.destroy(owner);
        owner.payload = .{ .text_validated = self.action.execute(owner.arena.allocator(), prior.payload().text_validated, authorization, replacement) catch return error.OperationExecutionFailed };
        var delta: pipeline.NodeDelta = .{};
        delta.data_replacements[@intFromEnum(extraction.text_schema.key)] = values.adopt(self.allocator, extraction.text_schema, reference.Value, reference.Owner, owner, reference.view, reference.destroy, null) catch return error.OperationExecutionFailed;
        for (Action.contract.invalidates) |key| delta.data_invalidations.insert(key);
        return .{ .outcome = .ok, .delta = delta };
    }
};
fn reject(allocator: std.mem.Allocator, schema: data.Schema, owner: *owned.Owner, err: repair.Error) operations.Error!execution.Candidate {
    if (err == error.OutOfMemory) return error.OperationExecutionFailed;
    owner.payload = .rejected;
    return owned.publish(allocator, schema, owner, .invalid) catch error.OperationExecutionFailed;
}
