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
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");

pub const progress_schema = values.schema(.reference_extraction_progress, owned.Value, 1, null).captured();
pub const schemas = [_]data.Schema{progress_schema};

pub const Initialize = struct {
    pub const Action = @import("../actions/reference/initialize_reference_extraction.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const inputs = try readInputs(&input.step.data);
        const owner = owned.create(self.allocator, null) catch |operation_error| return operation_error;
        errdefer owned.destroy(owner);
        owner.payload = .{ .extraction_progress = self.action.execute(owner.arena.allocator(), inputs.*) catch |operation_error| return operation_error };
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
        const tokens = values.read(&input.step.data, @import("structured_token_workflow.zig").candidates_schema, @import("../domain/structured_tokens.zig").Candidates) catch |operation_error| return operation_error;
        const prior = try extraction.read(&input.step.data, progress_schema, .extraction_progress);
        const packet = self.action.execute(self.allocator, inputs.*, literals.*, tokens.*, prior.payload().extraction_progress) catch |operation_error| return operation_error;
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
        const candidate = try @import("json_composition_workflow.zig").readValidated(&input.step.data);
        const owner = owned.create(self.allocator, prior) catch |operation_error| return operation_error;
        errdefer owned.destroy(owner);
        const producers: @import("../domain/reference_extraction.zig").ProducerOrigins = .{
            .content = candidate.producer(&.{"claims"}) orelse candidate.producer(&.{"reason"}) orelse return error.OperationExecutionFailed,
            .classifications = candidate.producer(&.{"token_classifications"}),
        };
        owner.payload = .{ .extraction_progress = self.action.execute(owner.arena.allocator(), prior.payload().extraction_progress, candidate.base, candidate.body, candidate.origin orelse return error.OperationExecutionFailed, producers) catch |operation_error| return operation_error };
        var delta: pipeline.NodeDelta = .{};
        delta.data_replacements[@intFromEnum(progress_schema.key)] = values.adopt(self.allocator, progress_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch |operation_error| return operation_error;
        for (Action.contract.invalidates) |key| delta.data_invalidations.insert(key);
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
        const owner = owned.create(self.allocator, prior) catch |operation_error| return operation_error;
        errdefer owned.destroy(owner);
        owner.payload = .{ .raw = self.action.execute(owner.arena.allocator(), prior.payload().extraction_progress) catch |operation_error| return operation_error };
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
        const packet = self.action.execute(self.allocator, prior.payload().reconciliation_input, (try readInputs(&input.step.data)).*, (try readLiterals(&input.step.data)).*) catch |operation_error| return operation_error;
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
        const owner = owned.create(self.allocator, prior) catch |operation_error| return operation_error;
        errdefer owned.destroy(owner);
        const candidate = try @import("json_composition_workflow.zig").readValidated(&input.step.data);
        owner.payload = .{ .reconciliation_raw = self.action.execute(owner.arena.allocator(), prior.payload().reconciliation_input, candidate) catch |operation_error| return operation_error };
        var result = try extraction.publish(self.allocator, reconciliation.raw_schema, owner, .ok);
        for (Action.contract.invalidates) |key| result.delta.data_invalidations.insert(key);
        return result;
    }
};
fn readInputs(view: *const data.View) operations.Error!*const source.Inputs {
    return values.read(view, @import("reference_evidence_workflow.zig").inputs_schema, source.Inputs) catch |operation_error| operation_error;
}
fn readLiterals(view: *const data.View) operations.Error!*const @import("../domain/passive_literals.zig").Registry {
    return values.read(view, @import("passive_literal_workflow.zig").registry_schema, @import("../domain/passive_literals.zig").Registry) catch |operation_error| operation_error;
}

/// The domain constructor provides native data; the composition owner performs
/// structural admission and retains the original model evidence separately.
pub const ForceClassifications = struct {
    pub const Action = @import("../actions/reference/construct_forced_token_classifications.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .failed };
    pub const parameters = [_]@import("../domain/workflow_operation.zig").ParameterDescriptor{
        .{ .id = "source-part", .kind = .string, .required = true, .workflow_definition_safe = true },
        .{ .id = "native-composition-part", .kind = .string, .required = true, .workflow_definition_safe = true },
    };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const composition = @import("json_composition_workflow.zig");
        const state = try composition.readState(&input.step.data);
        var source_part: ?usize = null;
        var target_part: ?usize = null;
        for (input.step.step.parameters) |parameter| if (parameter.value == .string) {
            const part = state.plan.part(.{ .bytes = parameter.value.string });
            if (std.mem.eql(u8, parameter.id.bytes, "source-part")) source_part = part;
            if (std.mem.eql(u8, parameter.id.bytes, "native-composition-part")) target_part = part;
        };
        const candidates = values.read(&input.step.data, @import("structured_token_workflow.zig").candidates_schema, @import("../domain/structured_tokens.zig").Candidates) catch |operation_error| return operation_error;
        const owner = try composition.Owner.create(self.allocator, &input.step.data, &.{.json_composition});
        errdefer owner.destroy();
        const outcome: @import("../domain/workflow.zig").OutcomeTag = switch (self.action.execute(owner.arena.allocator(), state.*, source_part orelse return error.OperationExecutionFailed, target_part orelse return error.OperationExecutionFailed, (try readInputs(&input.step.data)).*, candidates.*) catch |operation_error| return operation_error) {
            .semantic => semantic: {
                owner.payload = .{ .state = state.* };
                break :semantic .more;
            },
            .native => |next| native: {
                owner.payload = .{ .state = next };
                break :native .ok;
            },
        };
        var candidate = try composition.publish(owner, composition.state_schema, true, &.{});
        candidate.outcome = outcome;
        return candidate;
    }
};
