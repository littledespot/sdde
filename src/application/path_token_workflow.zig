const std = @import("std");
const naming = @import("../domain/naming_policy.zig");
const grammar = @import("../domain/path_token_grammar.zig");
const scan = @import("../domain/path_token_scan.zig");
const safety = @import("../domain/toolchain_safety.zig");
const evidence = @import("../domain/reference_evidence.zig");
const toolchain_values = @import("toolchain_workflow_values.zig");
const evidence_values = @import("reference_evidence_workflow.zig");
const values = @import("pipeline_values.zig");
const publish = @import("workflow_candidate.zig").publish;
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");

// Policy/reference-derived collections only; scan text has a sealed owner and
// no model-call byte ceiling. Workflow resource capture owns resource bounds.
pub const policy_schema = values.schema(.compiled_naming_policy, naming.Compiled, 1, 64 * 1024 * 1024);
pub const grammar_schema = values.schema(.path_token_grammar, grammar.Grammar, 1, 64 * 1024 * 1024);
pub const scan_schema = values.schema(.path_token_scan, scan.Result, 1, null);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{ policy_schema, grammar_schema, scan_schema };

pub const Compile = struct {
    pub const Action = @import("../actions/toolchain/compile_naming_policy.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = values.read(&input.step.data, toolchain_values.valid, safety.ValidToolchain) catch return error.OperationExecutionFailed;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), current) catch return error.OperationExecutionFailed;
        return publish(self.allocator, policy_schema, naming.Compiled, result);
    }
};
pub const Build = struct {
    pub const Action = @import("../actions/reference/build_superset_path_token_grammar.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = values.read(&input.step.data, toolchain_values.valid, safety.ValidToolchain) catch return error.OperationExecutionFailed;
        const policy = values.read(&input.step.data, policy_schema, naming.Compiled) catch return error.OperationExecutionFailed;
        const source = values.read(&input.step.data, evidence_values.inputs_schema, evidence.Inputs) catch return error.OperationExecutionFailed;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const result = self.action.execute(scratch.allocator(), policy.*, current, source.*) catch return error.OperationExecutionFailed;
        return publish(self.allocator, grammar_schema, grammar.Grammar, result);
    }
};
pub const Scan = struct {
    pub const Action = @import("../actions/reference/scan_path_tokens.zig").Action;
    pub const parameters = [_]@import("../domain/workflow_operation.zig").ParameterDescriptor{
        .{ .id = "text", .kind = .resource, .resource_kind = .data, .required = true, .workflow_definition_safe = true },
    };
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const step = input.step;
        const current = values.read(&step.data, toolchain_values.valid, safety.ValidToolchain) catch return error.OperationExecutionFailed;
        const compiled = values.read(&step.data, grammar_schema, grammar.Grammar) catch return error.OperationExecutionFailed;
        const source = values.read(&step.data, evidence_values.inputs_schema, evidence.Inputs) catch return error.OperationExecutionFailed;
        var text: ?[]const u8 = null;
        for (step.step.parameters) |parameter| {
            if (!std.mem.eql(u8, parameter.id.bytes, "text") or parameter.value != .resource) continue;
            for (step.resources) |resource| if (std.mem.eql(u8, resource.id.bytes, parameter.value.resource.bytes) and resource.content == .data) {
                text = resource.content.data;
            };
        }
        const result = self.action.execute(self.allocator, compiled.*, current, source.*, text orelse return error.OperationExecutionFailed) catch return error.OperationExecutionFailed;
        errdefer scan.destroy(result);
        var delta: @import("../domain/pipeline.zig").NodeDelta = .{};
        delta.data_writes[@intFromEnum(scan_schema.key)] = values.adopt(self.allocator, scan_schema, scan.Result, scan.Owner, result, scan.view, scan.destroy, null) catch return error.OperationExecutionFailed;
        return .{ .outcome = .ok, .delta = delta };
    }
};
