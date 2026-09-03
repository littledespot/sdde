const std = @import("std");
const compilation = @import("../domain/workflow_compilation.zig");
const execution = @import("../domain/workflow_execution.zig");
const pipeline = @import("../domain/pipeline.zig");
const registry = @import("../domain/workflow_registry.zig");
const implementations = @import("../ports/workflow_node_implementation.zig");
const parse_invocation = @import("../actions/workflow/parse_workflow_invocation.zig");
const select_workflow = @import("../actions/workflow/select_compiled_workflow.zig");
const validate_implementations = @import("../actions/workflow/validate_workflow_implementation_registry.zig");
const bindings = @import("workflow_engine_child_bindings.zig");

comptime {
    pipeline.validateLinear(
        &.{ .workflow_definition_registry, .workflow_implementation_registry, .workflow_compiler_registry },
        &.{
            validate_implementations.Action.contract,
            parse_invocation.Action.contract,
            select_workflow.Action.contract,
        },
    );
}

pub const Runner = struct {
    runtime: pipeline.NodeRuntime,
    arguments: []const []const u8,
    implementation_registry: implementations.Registry,
    compiler_registry: compilation.CompilerRegistry,
    parse_action: parse_invocation.Action = .{},
    select_action: select_workflow.Action,
    validate_action: validate_implementations.Action = .{},
    envelope: pipeline.PipelineEnvelope = .init(&.{ .workflow_definition_registry, .workflow_implementation_registry, .workflow_compiler_registry }),
    invocation: ?execution.Invocation = null,
    selected_workflow: ?execution.SelectedWorkflow = null,

    pub fn init(
        runtime: pipeline.NodeRuntime,
        arguments: []const []const u8,
        workflow_registry: *const registry.ValidatedWorkflowDefinitionRegistry,
        implementation_registry: implementations.Registry,
        compiler_registry: compilation.CompilerRegistry,
    ) Runner {
        return .{
            .runtime = runtime,
            .arguments = arguments,
            .implementation_registry = implementation_registry,
            .compiler_registry = compiler_registry,
            .select_action = .{ .registry = workflow_registry },
        };
    }

    pub fn invokeValidateImplementationRegistry(self: *Runner) bindings.SelectionStepOutcome {
        if (self.runtimeTerminal()) |outcome| return outcome;
        self.envelope.validateInvocation(validate_implementations.Action.contract) catch return .failed;
        self.validate_action.execute(self.implementation_registry, self.compiler_registry) catch return .failed;
        return self.finish(validate_implementations.Action.contract);
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
