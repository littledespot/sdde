const std = @import("std");
const pipeline = @import("../domain/pipeline.zig");
const naming = @import("../domain/naming_policy.zig");
const safety = @import("../domain/toolchain_safety.zig");
const evidence = @import("../domain/reference_evidence.zig");
const grammar = @import("../domain/path_token_grammar.zig");
const literals = @import("../domain/passive_literals.zig");
const tokens = @import("../domain/structured_tokens.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const values = @import("pipeline_values.zig");
const toolchain_values = @import("toolchain_workflow_values.zig");
const evidence_values = @import("reference_evidence_workflow.zig");
const grammar_values = @import("path_token_workflow.zig");
const literal_values = @import("passive_literal_workflow.zig");
const token_values = @import("structured_token_workflow.zig");
const stage = @import("../actions/reference/prepare_reference_tokens.zig");

// One binding runs the one stage action. YAML owns where it sits in the graph; the stage's internal
// steps are functions, not operations, and its intermediates never become pipeline data.
pub const PrepareReferenceTokens = struct {
    pub const Action = stage.Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = values.read(&input.step.data, toolchain_values.valid, safety.ValidToolchain) catch |operation_error| return operation_error;
        const policy = values.read(&input.step.data, grammar_values.policy_schema, naming.Compiled) catch |operation_error| return operation_error;
        const source = values.read(&input.step.data, evidence_values.inputs_schema, evidence.Inputs) catch |operation_error| return operation_error;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        var diagnostic: stage.Diagnostic = .{};
        const result = self.action.execute(scratch.allocator(), input.step.runtime, &diagnostic, policy.*, current, source.*) catch |operation_error| {
            // The stage-owned slot is read before the unchanged error propagates; the runner
            // records the step in the failed action's event (ADR 0031).
            if (input.step.stage_step) |slot| slot.name = if (diagnostic.step) |step| @tagName(step) else null;
            return operation_error;
        };
        var delta: pipeline.NodeDelta = .{};
        errdefer for (delta.data_writes) |slot| if (slot) |written| values.destroy(written);
        delta.data_writes[@intFromEnum(grammar_values.grammar_schema.key)] = values.create(self.allocator, grammar_values.grammar_schema, grammar.Grammar, result.grammar) catch |operation_error| return operation_error;
        delta.data_writes[@intFromEnum(literal_values.registry_schema.key)] = values.create(self.allocator, literal_values.registry_schema, literals.Registry, result.registry) catch |operation_error| return operation_error;
        delta.data_writes[@intFromEnum(token_values.candidates_schema.key)] = values.create(self.allocator, token_values.candidates_schema, tokens.Candidates, result.candidates) catch |operation_error| return operation_error;
        return .{ .outcome = .ok, .delta = delta };
    }
};
