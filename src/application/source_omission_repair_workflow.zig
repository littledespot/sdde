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
const owned = @import("retained_candidate.zig").Storage(union(enum) { repair: loss.Repair, rejected }, .rejected);
pub const schema = values.schema(.source_omission_repair, owned.Value, 1, null).captured();
pub const schemas = [_]data.Schema{schema};
pub fn read(view: *const data.View) operations.Error!loss.Repair {
    return owned.read(view, schema, .repair) catch error.OperationExecutionFailed;
}
pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .invalid, .failed };
fn support(view: *const data.View) operations.Error!loss.Support {
    const review = authority_values.read(view, @import("specification_support_workflow.zig").schema, .support) catch return error.OperationExecutionFailed;
    if (review != .accepted) return error.OperationExecutionFailed;
    return .{ .review = review.accepted.candidate, .inputs = authority_values.read(view, authority.inputs_schema, .inputs) catch return error.OperationExecutionFailed, .observations = authority_values.read(view, authority.observations_schema, .observations) catch return error.OperationExecutionFailed, .result = authority_values.read(view, authority.result_schema, .result) catch return error.OperationExecutionFailed };
}
fn facts(view: *const data.View) operations.Error!ex.Facts {
    const source = values.read(view, @import("reference_evidence_workflow.zig").inputs_schema, @import("../domain/reference_evidence.zig").Inputs) catch return error.OperationExecutionFailed;
    const candidates = values.read(view, @import("structured_token_workflow.zig").candidates_schema, @import("../domain/structured_tokens.zig").Candidates) catch return error.OperationExecutionFailed;
    const candidate = try extraction.read(view, extraction.text_schema, .text_validated);
    return .{ .extraction = .{ .inputs = source.*, .candidates = candidates.*, .candidate = candidate.payload().text_validated }, .support = try support(view) };
}
fn parsed(view: *const data.View) operations.Error!@import("../domain/reference_reconciliation.zig").Parsed {
    return (try extraction.read(view, rec.parsed_schema, .reconciliation_parsed)).payload().reconciliation_parsed;
}
pub const Authorize = struct {
    pub const Action = @import("../actions/reference/authorize_source_omission_repair.zig").Action;
    pub const outcomes = @import("source_omission_repair_workflow.zig").outcomes;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        const state = self.action.execute(owner.arena.allocator(), try facts(&input.step.data), try parsed(&input.step.data), try rec.textContext(&input.step.data)) catch |err| {
            if (err == error.OutOfMemory) return error.OperationExecutionFailed;
            return owned.publish(self.allocator, schema, owner, .invalid) catch error.OperationExecutionFailed;
        };
        owner.payload = .{ .repair = state };
        return owned.publish(self.allocator, schema, owner, if (state.authorization == .extraction) .ok else .more) catch error.OperationExecutionFailed;
    }
};
pub const BuildInput = struct {
    pub const Action = @import("../actions/reference/build_source_omission_repair_input.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const state = owned.read(&input.step.data, schema, .repair) catch return error.OperationExecutionFailed;
        const packet = self.action.execute(self.allocator, try facts(&input.step.data), try parsed(&input.step.data), try rec.textContext(&input.step.data), state) catch return error.OperationExecutionFailed;
        return @import("model_request_workflow.zig").publishPacket(self.allocator, packet);
    }
};
pub const Parse = struct {
    pub const Action = @import("../actions/reference/parse_source_omission_repair.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const state = owned.read(&input.step.data, schema, .repair) catch return error.OperationExecutionFailed;
        const packet = values.read(&input.step.data, @import("model_request_workflow.zig").packet_schema, @import("../domain/model_input_packet.zig").Packet) catch return error.OperationExecutionFailed;
        const handoff = try @import("model_candidate_handoff.zig").read(&input.step.data);
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .repair = self.action.execute(owner.arena.allocator(), state, packet, handoff.body, handoff.origin) catch return error.OperationExecutionFailed };
        var delta: pipeline.NodeDelta = .{};
        delta.data_replacements[@intFromEnum(schema.key)] = values.adopt(self.allocator, schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch return error.OperationExecutionFailed;
        return .{ .outcome = .ok, .delta = delta };
    }
};
pub fn Merge(comptime kind: enum { extraction, reconciliation }, comptime scope: loss.Scope) type {
    return struct {
        pub const Action = switch (kind) {
            .extraction => if (scope == .references) @import("../actions/reference/merge_source_extraction_repair.zig").Action else @import("../actions/reference/merge_upstream_extraction_repair.zig").Action,
            .reconciliation => if (scope == .references) @import("../actions/reference/merge_source_reconciliation_repair.zig").Action else @import("../actions/reference/merge_upstream_reconciliation_repair.zig").Action,
        };
        pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ if (kind == .reconciliation and scope == .specification) .more else .ok, .failed };
        pub const parameters = [_]@import("../domain/workflow_operation.zig").ParameterDescriptor{.{ .id = "retry-limit", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 0, .integer_max = std.math.maxInt(u32) }};
        pub const retry_limit: @import("../domain/workflow_operation.zig").RetryLimitDescriptor = .{ .maximum = std.math.maxInt(u32) };
        allocator: std.mem.Allocator,
        action: Action,
        pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
            const self = context.?;
            const state = owned.read(&input.step.data, schema, .repair) catch return error.OperationExecutionFailed;
            const target = if (kind == .extraction) extraction.text_schema else rec.parsed_schema;
            const prior = try extraction.read(&input.step.data, target, if (kind == .extraction) .text_validated else .reconciliation_parsed);
            const owner = reference.create(self.allocator, prior) catch return error.OperationExecutionFailed;
            errdefer reference.destroy(owner);
            owner.payload = if (kind == .extraction) .{ .text_validated = self.action.execute(owner.arena.allocator(), try facts(&input.step.data), try rec.textContext(&input.step.data), state) catch return error.OperationExecutionFailed } else .{ .reconciliation_parsed = self.action.execute(owner.arena.allocator(), try parsed(&input.step.data), try rec.textContext(&input.step.data), try support(&input.step.data), state) catch return error.OperationExecutionFailed };
            var delta: pipeline.NodeDelta = .{};
            delta.data_replacements[@intFromEnum(target.key)] = values.adopt(self.allocator, target, reference.Value, reference.Owner, owner, reference.view, reference.destroy, null) catch return error.OperationExecutionFailed;
            for (Action.contract.invalidates) |key| delta.data_invalidations.insert(key);
            return .{ .outcome = if (kind == .reconciliation and scope == .specification) .more else .ok, .delta = delta };
        }
    };
}
pub const Check = struct {
    pub const Action = @import("../actions/reference/check_source_omission.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .failed };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const source = values.read(&input.step.data, @import("reference_evidence_workflow.zig").inputs_schema, @import("../domain/reference_evidence.zig").Inputs) catch return error.OperationExecutionFailed;
        return .{ .outcome = if (self.action.execute(arena.allocator(), source.*, try support(&input.step.data)) catch return error.OperationExecutionFailed) .more else .ok, .delta = .{} };
    }
};
