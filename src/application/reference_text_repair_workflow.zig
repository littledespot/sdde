//! Typed domain bindings into the shared request and atomic-repair contracts.
const std = @import("std");
const data = @import("../domain/pipeline_data.zig");
const pipeline = @import("../domain/pipeline.zig");
const repair = @import("../domain/reference_extraction_text_repair.zig");
const extraction = @import("reference_extraction_workflow.zig");
const reference = @import("../domain/reference_candidate_value.zig");
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const owned = @import("retained_candidate.zig").Storage(union(enum) {
    authorization: repair.Authorization,
    replacement: struct { value: repair.Replacement, origin: @import("../domain/model_candidate_origin.zig").Origin },
    rejected,
}, .rejected);
pub const authorization_schema = values.schema(.reference_text_repair_authorization, owned.Value, 1, null).captured();
pub const result_schema = values.schema(.reference_text_repair_result, owned.Value, 1, null).captured();
pub const schemas = [_]data.Schema{ authorization_schema, result_schema };
const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .invalid, .failed };

pub const Authorize = struct {
    pub const Action = @import("../actions/reference/authorize_reference_text_repair.zig").Action;
    pub const outcomes = @import("reference_text_repair_workflow.zig").outcomes;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const prior = try extraction.read(&input.step.data, extraction.parsed_schema, .parsed);
        const rejected = try extraction.read(&input.step.data, extraction.text_schema, .text_rejected);
        const rejection = rejected.payload().text_rejected;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .authorization = self.action.execute(owner.arena.allocator(), try facts(&input.step.data, prior.payload().parsed), rejection) catch |err| return reject(self.allocator, authorization_schema, owner, err) };
        return owned.publish(self.allocator, authorization_schema, owner, .ok) catch error.OperationExecutionFailed;
    }
};
pub const BuildInput = struct {
    pub const Action = @import("../actions/reference/build_reference_text_repair_input.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const authorization = owned.read(&input.step.data, authorization_schema, .authorization) catch return error.OperationExecutionFailed;
        const prior = try extraction.read(&input.step.data, extraction.parsed_schema, .parsed);
        const candidates = values.read(&input.step.data, @import("structured_token_workflow.zig").candidates_schema, @import("../domain/structured_tokens.zig").Candidates) catch return error.OperationExecutionFailed;
        const literals = values.read(&input.step.data, @import("passive_literal_workflow.zig").registry_schema, @import("../domain/passive_literals.zig").Registry) catch return error.OperationExecutionFailed;
        const current = values.read(&input.step.data, @import("toolchain_workflow_values.zig").valid, @import("../domain/toolchain_safety.zig").ValidToolchain) catch return error.OperationExecutionFailed;
        const packet = self.action.execute(self.allocator, try facts(&input.step.data, prior.payload().parsed), literals.*, current, candidates.*, authorization) catch return error.OperationExecutionFailed;
        return @import("model_request_workflow.zig").publishPacket(self.allocator, packet);
    }
};
pub const Parse = struct {
    pub const Action = @import("../actions/reference/parse_reference_text_repair.zig").Action;
    pub const outcomes = @import("reference_text_repair_workflow.zig").outcomes;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const authorization = owned.read(&input.step.data, authorization_schema, .authorization) catch return error.OperationExecutionFailed;
        const packet = values.read(&input.step.data, @import("model_request_workflow.zig").packet_schema, @import("../domain/model_input_packet.zig").Packet) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        const candidate = try @import("model_candidate_handoff.zig").read(&input.step.data);
        owner.payload = .{ .replacement = .{ .value = self.action.execute(owner.arena.allocator(), authorization, packet, candidate.body) catch |err| return reject(self.allocator, result_schema, owner, err), .origin = candidate.origin } };
        return owned.publish(self.allocator, result_schema, owner, .ok) catch error.OperationExecutionFailed;
    }
};
pub const Merge = struct {
    pub const Action = @import("../actions/reference/merge_reference_text_repair.zig").Action;
    pub const outcomes = @import("reference_text_repair_workflow.zig").outcomes;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const authorization = owned.read(&input.step.data, authorization_schema, .authorization) catch return error.OperationExecutionFailed;
        const replacement = owned.read(&input.step.data, result_schema, .replacement) catch return error.OperationExecutionFailed;
        const prior = try extraction.read(&input.step.data, extraction.parsed_schema, .parsed);
        const owner = reference.create(self.allocator, prior) catch return error.OperationExecutionFailed;
        errdefer reference.destroy(owner);
        owner.payload = .{ .parsed = self.action.execute(owner.arena.allocator(), try facts(&input.step.data, prior.payload().parsed), authorization, replacement.value, replacement.origin) catch return error.OperationExecutionFailed };
        var delta: pipeline.NodeDelta = .{};
        delta.data_replacements[@intFromEnum(extraction.parsed_schema.key)] = values.adopt(self.allocator, extraction.parsed_schema, reference.Value, reference.Owner, owner, reference.view, reference.destroy, null) catch return error.OperationExecutionFailed;
        for (Action.contract.invalidates) |key| delta.data_invalidations.insert(key);
        return .{ .outcome = .ok, .delta = delta };
    }
};
fn reject(allocator: std.mem.Allocator, schema: data.Schema, owner: *owned.Owner, err: repair.Error) operations.Error!execution.Candidate {
    if (err == error.OutOfMemory) return error.OperationExecutionFailed;
    owner.payload = .rejected;
    return owned.publish(allocator, schema, owner, .invalid) catch error.OperationExecutionFailed;
}

fn facts(view: *const data.View, candidate: @import("../domain/reference_extraction.zig").Parsed) operations.Error!repair.Facts {
    const source = values.read(view, @import("reference_evidence_workflow.zig").inputs_schema, @import("../domain/reference_evidence.zig").Inputs) catch return error.OperationExecutionFailed;
    const registry = values.read(view, @import("passive_literal_workflow.zig").registry_schema, @import("../domain/passive_literals.zig").Registry) catch return error.OperationExecutionFailed;
    const current = values.read(view, @import("toolchain_workflow_values.zig").valid, @import("../domain/toolchain_safety.zig").ValidToolchain) catch return error.OperationExecutionFailed;
    return @import("../domain/reference_extraction_context.zig").textFacts(source.*, registry.*, current, candidate) catch return error.OperationExecutionFailed;
}
