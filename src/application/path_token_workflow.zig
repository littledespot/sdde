const std = @import("std");
const naming = @import("../domain/naming_policy.zig");
const grammar = @import("../domain/path_token_grammar.zig");
const safety = @import("../domain/toolchain_safety.zig");
const toolchain_values = @import("toolchain_workflow_values.zig");
const values = @import("pipeline_values.zig");
const publish = @import("workflow_candidate.zig").publish;
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");

// Policy/reference-derived collections only. Workflow resource capture owns resource bounds.
pub const policy_schema = values.schema(.compiled_naming_policy, naming.Compiled, 1, values.max_value_bytes);
pub const grammar_schema = values.schema(.path_token_grammar, grammar.Grammar, 1, values.max_value_bytes);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{ policy_schema, grammar_schema };

pub const Compile = struct {
    pub const Action = @import("../actions/toolchain/compile_naming_policy.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = values.read(&input.step.data, toolchain_values.valid, safety.ValidToolchain) catch |operation_error| return operation_error;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), current) catch |operation_error| return operation_error;
        return publish(self.allocator, policy_schema, naming.Compiled, result);
    }
};
