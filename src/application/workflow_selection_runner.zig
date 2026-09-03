const std = @import("std");
const execution = @import("../domain/workflow_execution.zig");
const pipeline = @import("../domain/pipeline.zig");
const registry = @import("../domain/workflow_registry.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const parse_invocation = @import("../actions/workflow/parse_workflow_invocation.zig");
const select_workflow = @import("../actions/workflow/select_compiled_workflow.zig");
const validate_operations = @import("../actions/workflow/validate_workflow_operation_registry.zig");
const bindings = @import("workflow_engine_child_bindings.zig");

comptime {
    pipeline.validateLinear(
        &.{ .workflow_definition_registry, .workflow_operation_registry },
        &.{
            validate_operations.Action.contract,
            parse_invocation.Action.contract,
            select_workflow.Action.contract,
        },
    );
}

pub const Runner = struct {
    runtime: pipeline.NodeRuntime,
    arguments: []const []const u8,
    operation_registry: *const operations.Registry,
    parse_action: parse_invocation.Action = .{},
    select_action: select_workflow.Action,
    validate_action: validate_operations.Action = .{},
    envelope: pipeline.PipelineEnvelope = .init(&.{ .workflow_definition_registry, .workflow_operation_registry }),
    invocation: ?execution.Invocation = null,
    selected_workflow: ?execution.SelectedWorkflow = null,

    pub fn init(
        runtime: pipeline.NodeRuntime,
        arguments: []const []const u8,
        workflow_registry: *const registry.ValidatedWorkflowDefinitionRegistry,
        operation_registry: *const operations.Registry,
    ) Runner {
        return .{
            .runtime = runtime,
            .arguments = arguments,
            .operation_registry = operation_registry,
            .select_action = .{ .registry = workflow_registry },
        };
    }

    pub fn invokeValidateOperationRegistry(self: *Runner) bindings.SelectionStepOutcome {
        if (self.runtimeTerminal()) |outcome| return outcome;
        self.envelope.validateInvocation(validate_operations.Action.contract) catch return .failed;
        self.validate_action.execute(self.operation_registry) catch return .failed;
        return self.finish(validate_operations.Action.contract);
    }

    pub fn invokeParseInvocation(self: *Runner) bindings.SelectionStepOutcome {
        if (self.runtimeTerminal()) |outcome| return outcome;
        self.envelope.validateInvocation(parse_invocation.Action.contract) catch return .failed;
        std.debug.assert(self.invocation == null);
        self.invocation = self.parse_action.execute(self.arguments) catch return .invocation_invalid;
        return self.finish(parse_invocation.Action.contract);
    }

    pub fn invokeSelectWorkflow(self: *Runner) bindings.SelectionStepOutcome {
        if (self.runtimeTerminal()) |outcome| return outcome;
        self.envelope.validateInvocation(select_workflow.Action.contract) catch return .failed;
        std.debug.assert(self.invocation != null);
        std.debug.assert(self.selected_workflow == null);
        self.selected_workflow = self.select_action.execute(self.invocation.?) catch return .invocation_invalid;
        return self.finish(select_workflow.Action.contract);
    }

    pub fn selected(self: *const Runner) *const execution.SelectedWorkflow {
        return &self.selected_workflow.?;
    }

    fn finish(self: *Runner, contract: pipeline.NodeContract) bindings.SelectionStepOutcome {
        if (self.runtimeTerminal()) |outcome| return outcome;
        self.envelope = self.envelope.apply(contract, pipeline.NodeDelta.successful(contract)) catch return .failed;
        return .ok;
    }

    fn runtimeTerminal(self: *const Runner) ?bindings.SelectionStepOutcome {
        return switch (self.runtime.status()) {
            .active => null,
            .cancelled => .cancelled,
            .deadline_exhausted => .failed,
        };
    }
};
