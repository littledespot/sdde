//! Bind native packets and accepted provider bodies to existing reference
//! validators. Sequencing and bounded iteration remain visible in YAML.
const std = @import("std");
const pipeline = @import("../domain/pipeline.zig");
const data = @import("../domain/pipeline_data.zig");
const owned = @import("../domain/reference_candidate_value.zig");
const source = @import("../domain/reference_evidence.zig");
const values = @import("pipeline_values.zig");
const extraction = @import("reference_extraction_workflow.zig");
const reconciliation = @import("reference_reconciliation_workflow.zig");
const requests = @import("model_request_workflow.zig");
const packets = @import("../domain/model_input_packet.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const handoff = @import("model_candidate_handoff.zig");

pub const progress_schema = values.schema(.reference_extraction_progress, owned.Value, 1, null).captured();
pub const schemas = [_]data.Schema{progress_schema};

pub const Initialize = struct {
    pub const Action = @import("../actions/reference/initialize_reference_extraction.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const inputs = try readInputs(&input.step.data);
        const owner = owned.create(self.allocator, null) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .extraction_progress = self.action.execute(owner.arena.allocator(), inputs.*) catch return error.OperationExecutionFailed };
        return extraction.publish(self.allocator, progress_schema, owner, .ok);
    }
};
pub const CheckExtraction = struct {
    pub const Action = @import("../actions/reference/check_reference_extraction_progress.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .failed };
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const prior = try extraction.read(&input.step.data, progress_schema, .extraction_progress);
        return .{ .outcome = context.?.action.execute(prior.payload().extraction_progress), .delta = .{} };
    }
};
pub const BuildExtractionInput = struct {
    pub const Action = @import("../actions/reference/build_reference_extraction_model_input.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const inputs = try readInputs(&input.step.data);
        const literals = try readLiterals(&input.step.data);
        const tokens = values.read(&input.step.data, @import("structured_token_workflow.zig").candidates_schema, @import("../domain/structured_tokens.zig").Candidates) catch return error.OperationExecutionFailed;
        const prior = try extraction.read(&input.step.data, progress_schema, .extraction_progress);
        const packet = self.action.execute(self.allocator, inputs.*, literals.*, tokens.*, prior.payload().extraction_progress) catch return error.OperationExecutionFailed;
        return requests.publishPacket(self.allocator, packet);
    }
};
pub const CollectExtraction = struct {
    pub const Action = @import("../actions/reference/collect_reference_extraction_result.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const prior = try extraction.read(&input.step.data, progress_schema, .extraction_progress);
        const packet = try readPacket(&input.step.data);
        const candidate = try handoff.read(&input.step.data);
        const owner = owned.create(self.allocator, prior) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .extraction_progress = self.action.execute(owner.arena.allocator(), prior.payload().extraction_progress, packet, candidate.body, candidate.origin) catch return error.OperationExecutionFailed };
        var delta: pipeline.NodeDelta = .{};
        delta.data_replacements[@intFromEnum(progress_schema.key)] = values.adopt(self.allocator, progress_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch return error.OperationExecutionFailed;
        return .{ .outcome = .ok, .delta = delta };
    }
};
pub const FinishExtraction = struct {
    pub const Action = @import("../actions/reference/build_reference_extraction_results.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const prior = try extraction.read(&input.step.data, progress_schema, .extraction_progress);
        const owner = owned.create(self.allocator, prior) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .raw = self.action.execute(owner.arena.allocator(), prior.payload().extraction_progress) catch return error.OperationExecutionFailed };
        return extraction.publish(self.allocator, extraction.raw_schema, owner, .ok);
    }
};
pub const BuildReconciliationInput = struct {
    pub const Action = @import("../actions/reference/build_reference_reconciliation_model_input.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const prior = try extraction.read(&input.step.data, reconciliation.input_schema, .reconciliation_input);
        const packet = self.action.execute(self.allocator, prior.payload().reconciliation_input, (try readInputs(&input.step.data)).*, (try readLiterals(&input.step.data)).*) catch return error.OperationExecutionFailed;
        return requests.publishPacket(self.allocator, packet);
    }
};
pub const CheckReconciliation = struct {
    pub const Action = @import("../actions/reference/check_reference_reconciliation_purpose.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .failed };
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const prior = try extraction.read(&input.step.data, reconciliation.input_schema, .reconciliation_input);
        return .{ .outcome = context.?.action.execute(prior.payload().reconciliation_input), .delta = .{} };
    }
};
pub const CollectReconciliation = struct {
    pub const Action = @import("../actions/reference/collect_reference_reconciliation_result.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const prior = try extraction.read(&input.step.data, reconciliation.input_schema, .reconciliation_input);
        const owner = owned.create(self.allocator, prior) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .reconciliation_raw = self.action.execute(owner.arena.allocator(), prior.payload().reconciliation_input, try readPacket(&input.step.data), (try handoff.read(&input.step.data)).body) catch return error.OperationExecutionFailed };
        return extraction.publish(self.allocator, reconciliation.raw_schema, owner, .ok);
    }
};
fn readInputs(view: *const data.View) operations.Error!*const source.Inputs {
    return values.read(view, @import("reference_evidence_workflow.zig").inputs_schema, source.Inputs) catch error.OperationExecutionFailed;
}
fn readLiterals(view: *const data.View) operations.Error!*const @import("../domain/passive_literals.zig").Registry {
    return values.read(view, @import("passive_literal_workflow.zig").registry_schema, @import("../domain/passive_literals.zig").Registry) catch error.OperationExecutionFailed;
}
fn readPacket(view: *const data.View) operations.Error!*const packets.Packet {
    return values.read(view, requests.packet_schema, packets.Packet) catch error.OperationExecutionFailed;
}
