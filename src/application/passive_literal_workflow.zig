const std = @import("std");
const literals = @import("../domain/passive_literals.zig");
const grammar = @import("../domain/path_token_grammar.zig");
const evidence = @import("../domain/reference_evidence.zig");
const safety = @import("../domain/toolchain_safety.zig");
const values = @import("pipeline_values.zig");
const publish = @import("workflow_candidate.zig").publish;
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const toolchain_values = @import("toolchain_workflow_values.zig");
const evidence_values = @import("reference_evidence_workflow.zig");
const grammar_values = @import("path_token_workflow.zig");

// These collections derive only from bounded captured references, never model
// response bytes. The ordinary runner constructor owns all slices/identities.
pub const candidates_schema = values.schema(.passive_literal_candidates, literals.Candidates, 1, 64 * 1024 * 1024);
pub const assigned_schema = values.schema(.passive_literal_identities, literals.Assigned, 1, 64 * 1024 * 1024);
pub const registry_schema = values.schema(.reference_passive_literals, literals.Registry, 1, 64 * 1024 * 1024);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{ candidates_schema, assigned_schema, registry_schema };

pub const Scan = struct {
    pub const Action = @import("../actions/reference/scan_reference_passive_literals.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = values.read(&input.step.data, toolchain_values.valid, safety.ValidToolchain) catch return error.OperationExecutionFailed;
        const compiled = values.read(&input.step.data, grammar_values.grammar_schema, grammar.Grammar) catch return error.OperationExecutionFailed;
        const source = values.read(&input.step.data, evidence_values.inputs_schema, evidence.Inputs) catch return error.OperationExecutionFailed;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), compiled.*, current, source.*) catch return error.OperationExecutionFailed;
        return publish(self.allocator, candidates_schema, literals.Candidates, result);
    }
};
pub const Assign = struct {
    pub const Action = @import("../actions/reference/assign_passive_literal_identities.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const candidates = values.read(&input.step.data, candidates_schema, literals.Candidates) catch return error.OperationExecutionFailed;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), candidates.*) catch return error.OperationExecutionFailed;
        return publish(self.allocator, assigned_schema, literals.Assigned, result);
    }
};
pub const Validate = struct {
    pub const Action = @import("../actions/reference/validate_reference_passive_literals.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const assigned = values.read(&input.step.data, assigned_schema, literals.Assigned) catch return error.OperationExecutionFailed;
        const current = values.read(&input.step.data, toolchain_values.valid, safety.ValidToolchain) catch return error.OperationExecutionFailed;
        const source = values.read(&input.step.data, evidence_values.inputs_schema, evidence.Inputs) catch return error.OperationExecutionFailed;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), assigned.*, current, source.*) catch return error.OperationExecutionFailed;
        return publish(self.allocator, registry_schema, literals.Registry, result);
    }
};
