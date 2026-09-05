const std = @import("std");
const invocation_types = @import("../domain/specify_invocation.zig");
const pipeline = @import("../domain/pipeline.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const values = @import("pipeline_values.zig");
const schemas = @import("specify_invocation_values.zig");
const publish = @import("workflow_candidate.zig").publish;
const Envelope = @import("pipeline_envelope.zig").PipelineEnvelope;
const children = @import("specify_invocation_child_bindings.zig");
const orchestrator = @import("specify_invocation_orchestrator.zig");

pub const ParseInvocation = struct {
    pub const Action = @import("../actions/specify/parse_specify_invocation.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const arguments = switch (input) {
            .invocation => |value| value.arguments,
            .step => return error.OperationExecutionFailed,
        };
        const result = self.action.execute(arguments) catch return error.OperationExecutionFailed;
        return publish(self.allocator, schemas.parsed, invocation_types.ParsedInvocation, result);
    }
};

pub const ValidateArguments = struct {
    pub const Action = @import("../actions/specify/validate_specify_arguments.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        return context.?.run(input.step.data);
    }
    fn run(self: *@This(), view: @import("../domain/pipeline_data.zig").View) operations.Error!execution.Candidate {
        const parsed = values.read(&view, schemas.parsed, invocation_types.ParsedInvocation) catch return error.OperationExecutionFailed;
        const result = self.action.execute(parsed.*) catch return error.OperationExecutionFailed;
        return publish(self.allocator, schemas.invocation, invocation_types.Invocation, result);
    }
};

pub const Invocation = struct {
    allocator: std.mem.Allocator,
    pub const contract: @import("../domain/workflow_operation.zig").Contract = .{
        .id = "specify-invocation@1",
        .kind = .invocation,
        .produces = ValidateArguments.Action.contract.produces,
        .outcomes = &.{.ok},
        .side_effect = .none,
    };

    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const arguments = switch (input) {
            .invocation => |value| value.arguments,
            .step => return error.OperationExecutionFailed,
        };
        var runner: InvocationRunner = .{
            .parser = .{ .allocator = context.?.allocator },
            .validator = .{ .allocator = context.?.allocator },
            .arguments = arguments,
        };
        defer runner.envelope.deinit();
        if (orchestrator.run(.{ .context = &runner, .parse_fn = InvocationRunner.parse, .validate_fn = InvocationRunner.validate }) != .ok) return error.OperationExecutionFailed;
        // Transfer only the validated output; parsed arguments remain private.
        const slot = &runner.envelope.slots[@intFromEnum(schemas.invocation.key)];
        var delta: pipeline.NodeDelta = .{};
        delta.data_writes[@intFromEnum(schemas.invocation.key)] = slot.*;
        slot.* = null;
        return .{ .outcome = .ok, .delta = delta };
    }
};

const InvocationRunner = struct {
    parser: ParseInvocation,
    validator: ValidateArguments,
    arguments: []const []const u8,
    envelope: Envelope = .init(&schemas.schemas),

    fn parse(context: *anyopaque) children.Outcome {
        const self: *@This() = @ptrCast(@alignCast(context));
        _ = self.envelope.view(ParseInvocation.Action.contract) catch return .failed;
        var candidate = ParseInvocation.invoke(&self.parser, .{ .invocation = .{ .arguments = self.arguments } }) catch return .failed;
        defer self.envelope.discard(&candidate.delta);
        self.envelope.apply(ParseInvocation.Action.contract, &candidate.delta, candidate.outcome) catch return .failed;
        return .ok;
    }

    fn validate(context: *anyopaque) children.Outcome {
        const self: *@This() = @ptrCast(@alignCast(context));
        const view = self.envelope.view(ValidateArguments.Action.contract) catch return .failed;
        // Use the same action and publication path as its standalone YAML binding.
        var candidate = self.validator.run(view) catch return .failed;
        defer self.envelope.discard(&candidate.delta);
        self.envelope.apply(ValidateArguments.Action.contract, &candidate.delta, candidate.outcome) catch return .failed;
        return .ok;
    }
};
