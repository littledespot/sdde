const std = @import("std");
const tokens = @import("../domain/structured_tokens.zig");
const evidence = @import("../domain/reference_evidence.zig");
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const source_values = @import("reference_evidence_workflow.zig");
const extraction_values = @import("reference_extraction_workflow.zig");
const owned = @import("../domain/reference_candidate_value.zig");

// Source-derived bounds only. Model candidate values use the sealed owner below.
pub const facts_schema = values.schema(.structured_reference_facts, tokens.Facts, 1, 64 * 1024 * 1024);
pub const candidates_schema = values.schema(.structured_token_candidates, tokens.Candidates, 1, 64 * 1024 * 1024);
pub const assigned_schema = values.schema(.preserved_token_identities, owned.Value, 1, null);
pub const prepared_schema = values.schema(.prepared_reference_claims, owned.Value, 1, null);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{ facts_schema, candidates_schema, assigned_schema, prepared_schema };

pub const Extract = struct {
    pub const Action = @import("../actions/reference/extract_structured_reference_facts.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = values.read(&input.step.data, source_values.inputs_schema, evidence.Inputs) catch return error.OperationExecutionFailed;
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const result = self.action.execute(arena.allocator(), source.*) catch return error.OperationExecutionFailed;
        return @import("workflow_candidate.zig").publish(self.allocator, facts_schema, tokens.Facts, result);
    }
};
pub const AssignCandidates = struct {
    pub const Action = @import("../actions/reference/assign_structured_token_candidate_identities.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = values.read(&input.step.data, source_values.inputs_schema, evidence.Inputs) catch return error.OperationExecutionFailed;
        const facts = values.read(&input.step.data, facts_schema, tokens.Facts) catch return error.OperationExecutionFailed;
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const result = self.action.execute(arena.allocator(), source.*, facts.*) catch return error.OperationExecutionFailed;
        return @import("workflow_candidate.zig").publish(self.allocator, candidates_schema, tokens.Candidates, result);
    }
};
pub const AssignTokens = struct {
    pub const Action = @import("../actions/reference/assign_preserved_token_identities.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const prior = try extraction_values.read(&input.step.data, extraction_values.selections_schema, .selections_validated);
        const owner = owned.create(self.allocator, prior) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .tokens_assigned = self.action.execute(owner.arena.allocator(), prior.payload().selections_validated) catch return error.OperationExecutionFailed };
        return extraction_values.publish(self.allocator, assigned_schema, owner, .ok);
    }
};
pub const BuildClaims = struct {
    pub const Action = @import("../actions/reference/build_preserved_token_claims.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const prior = try extraction_values.read(&input.step.data, assigned_schema, .tokens_assigned);
        const owner = owned.create(self.allocator, prior) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .prepared = self.action.execute(owner.arena.allocator(), prior.payload().tokens_assigned) catch return error.OperationExecutionFailed };
        return extraction_values.publish(self.allocator, prepared_schema, owner, .ok);
    }
};
