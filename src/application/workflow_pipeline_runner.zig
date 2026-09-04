const std = @import("std");
const pipeline = @import("../domain/pipeline.zig");
const execution = @import("../domain/workflow_execution.zig");
const workflow = @import("../domain/workflow.zig");
const definition = @import("../domain/workflow_definition.zig");
const compilation = @import("../domain/workflow_compilation.zig");
const operation = @import("../domain/workflow_operation.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const telemetry_barrier = @import("../ports/telemetry_barrier.zig");
const child_bindings = @import("workflow_pipeline_child_bindings.zig");
const provider_binding = @import("../domain/llm_provider_binding.zig");
const provider_services = @import("model_provider_bootstrap_services.zig");
const resolve_provider_binding = @import("../actions/provider/resolve_provider_model_binding.zig");
const workflow_token_runner = @import("workflow_token_accounting_runner.zig");

pub const Runner = struct {
    selected: execution.SelectedWorkflow,
    operation_registry: *const operations.Registry,
    barrier: telemetry_barrier.Barrier,
    runtime: pipeline.NodeRuntime,
    model_provider_services: ?*const provider_services.ModelProviderBootstrapServices = null,
    resolve_provider_binding_action: resolve_provider_binding.Action = .{},
    envelope: pipeline.PipelineEnvelope = pipeline.PipelineEnvelope.init(&.{}),
    token_accounting: workflow_token_runner.Runner,
    retry_execution_counts: [definition.max_steps]u64 = [_]u64{0} ** definition.max_steps,

    pub fn init(
        allocator: std.mem.Allocator,
        selected: execution.SelectedWorkflow,
        operation_registry: *const operations.Registry,
        barrier: telemetry_barrier.Barrier,
        runtime: pipeline.NodeRuntime,
        model_provider_services: ?*const provider_services.ModelProviderBootstrapServices,
    ) Runner {
        return .{
            .selected = selected,
            .operation_registry = operation_registry,
            .barrier = barrier,
            .runtime = runtime,
            .model_provider_services = model_provider_services,
            .token_accounting = workflow_token_runner.Runner.init(
                allocator,
                selected.graph.authority.total_model_token_budget,
            ),
        };
    }

    pub fn deinit(self: *Runner) void {
        self.token_accounting.deinit();
        self.* = undefined;
    }

    pub fn bindings(self: *Runner) child_bindings.ChildBindings {
        return .{ .context = self, .vtable = &vtable };
    }

    fn invokeInvocation(self: *Runner) execution.Applied {
        if (runtimeTerminal(self.runtime)) |outcome| return .{ .outcome = outcome };
        const authority = self.selected.graph.authority;
        const entry = self.operation_registry.resolveOperation(authority.invocation_operation_id) orelse {
            return .{ .outcome = .failed };
        };
        if (entry.contract.kind != .invocation or
            !std.mem.eql(pipeline.DataKey, entry.contract.produces, authority.invocation_outputs))
        {
            return .{ .outcome = .failed };
        }
        const candidate = entry.invoke(.{ .invocation = .{ .arguments = self.selected.invocation.arguments } }) catch {
            return .{ .outcome = .failed };
        };
        if (!containsOutcome(entry.contract.outcomes, candidate.outcome)) return .{ .outcome = .failed };
        const contract: pipeline.NodeContract = .{
            .id = authority.invocation_operation_id.bytes,
            .kind = .action,
            .requires = &.{},
            .produces = authority.invocation_outputs,
            .side_effect = .none,
        };
        return self.applyCandidate(contract, candidate);
    }

    fn invokeStep(self: *Runner, id: workflow.WorkflowStepId) execution.Applied {
        if (runtimeTerminal(self.runtime)) |outcome| return .{ .outcome = outcome };
        const index = findStepIndex(self.selected.graph.authority.steps, id) orelse return .{ .outcome = .failed };
        if (index >= self.retry_execution_counts.len) return .{ .outcome = .failed };
        const step = &self.selected.graph.authority.steps[index];
        if (step.retry_authority) |authority| {
            if (self.retry_execution_counts[index] > @as(u64, authority.limit.value)) return .{ .outcome = .failed };
            self.retry_execution_counts[index] = std.math.add(u64, self.retry_execution_counts[index], 1) catch {
                return .{ .outcome = .failed };
            };
        }
        const entry = self.operation_registry.resolveOperation(step.operation_id) orelse return .{ .outcome = .failed };
        if (!contractMatchesStep(entry.contract, step.*)) return .{ .outcome = .failed };
        var resource_buffer: [definition.max_parameters]compilation.CompiledResource = undefined;
        const resources = bindStepResources(
            step.parameters,
            self.selected.graph.authority.resources,
            &resource_buffer,
        ) orelse return .{ .outcome = .failed };
        var resolved_binding = self.resolveModelBinding(step.*) catch {
            return .{ .outcome = .failed };
        };
        const candidate = entry.invoke(.{ .step = .{
            .step = step,
            .resources = resources,
            .model_binding = if (resolved_binding) |*value| value else null,
            .log = pipeline.WorkflowLog.init(self.selected.graph.shortcode),
        } }) catch return .{ .outcome = .failed };
        if (!containsOutcome(step.outcomes, candidate.outcome)) return .{ .outcome = .failed };
        return self.applyCandidate(stepPipelineContract(step.*), candidate);
    }

    pub fn tokenLedger(self: *const Runner) *const @import("../domain/workflow_token_accounting.zig").Ledger {
        return self.token_accounting.current();
    }

    fn resolveModelBinding(
        self: *Runner,
        step: compilation.CompiledStep,
    ) resolve_provider_binding.Error!?provider_binding.ValidatedProviderModelBinding {
        if (!hasModelSlot(step.parameters)) return null;
        const services = self.model_provider_services orelse {
            return error.ProviderModelBindingInvalid;
        };
        var binding_envelope = pipeline.PipelineEnvelope.init(&.{
            .selected_compiled_workflow,
            .llm_provider_registry,
            .repository_model_allowlist,
        });
        binding_envelope.validateInvocation(resolve_provider_binding.Action.contract) catch {
            return error.ProviderModelBindingInvalid;
        };
        const resolved = try self.resolve_provider_binding_action.execute(
            self.selected.graph,
            step.id,
            services.registry(),
            services.allowlist(),
        );
        binding_envelope = binding_envelope.apply(
            resolve_provider_binding.Action.contract,
            pipeline.NodeDelta.successful(resolve_provider_binding.Action.contract),
        ) catch return error.ProviderModelBindingInvalid;
        std.debug.assert(binding_envelope.contains(.validated_provider_model_binding));
        return resolved;
    }

    fn applyCandidate(self: *Runner, contract: pipeline.NodeContract, candidate: execution.Candidate) execution.Applied {
        const next = self.envelope.apply(contract, candidate.delta) catch return .{ .outcome = .invalid };
        self.envelope = next;
        for (candidate.delta.addedTelemetryFacts()) |fact| {
            const logging_result = self.barrier.process(fact);
            if (logging_result.outcome != .ok) return .{ .outcome = logging_result.outcome };
        }
        return .{ .outcome = candidate.outcome };
    }
};

fn stepPipelineContract(step: compilation.CompiledStep) pipeline.NodeContract {
    return .{
        .id = step.operation_id.bytes,
        .kind = .action,
        .requires = step.requires,
        .produces = step.produces,
        .replaces = step.replaces,
        .invalidates = step.invalidates,
        .side_effect = step.side_effect,
    };
}
fn contractMatchesStep(
    contract: operation.Contract,
    step: compilation.CompiledStep,
) bool {
    return contract.kind == .step and
        std.mem.eql(pipeline.DataKey, contract.requires, step.requires) and
        std.mem.eql(pipeline.DataKey, contract.produces, step.produces) and
        std.mem.eql(pipeline.DataKey, contract.replaces, step.replaces) and
        std.mem.eql(pipeline.DataKey, contract.invalidates, step.invalidates) and
        std.mem.eql(workflow.OutcomeTag, contract.outcomes, step.outcomes) and
        contract.side_effect == step.side_effect and
        equalStrings(contract.gates, step.gates) and
        equalStrings(contract.capabilities, step.capabilities) and
        retryContractMatches(contract, step);
}
fn retryContractMatches(contract: operation.Contract, step: compilation.CompiledStep) bool {
    if (contract.retry_limit == null or step.retry_authority == null) {
        return contract.retry_limit == null and step.retry_authority == null;
    }
    return step.retry_authority.?.limit.within(contract.retry_limit.?.maximum);
}
fn equalStrings(left: []const []const u8, right: []const []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |left_value, right_value| {
        if (!std.mem.eql(u8, left_value, right_value)) return false;
    }
    return true;
}
fn invokeInvocation(context: *anyopaque) execution.Applied {
    return cast(context).invokeInvocation();
}
fn invokeStep(context: *anyopaque, id: workflow.WorkflowStepId) execution.Applied {
    return cast(context).invokeStep(id);
}
fn cast(context: *anyopaque) *Runner {
    return @ptrCast(@alignCast(context));
}
const vtable: child_bindings.ChildBindings.VTable = .{
    .invoke_invocation = invokeInvocation,
    .invoke_step = invokeStep,
};

fn findStepIndex(steps: []const compilation.CompiledStep, id: workflow.WorkflowStepId) ?usize {
    for (steps, 0..) |step, index| if (std.mem.eql(u8, step.id.bytes, id.bytes)) return index;
    return null;
}
fn bindStepResources(
    parameters: []const compilation.CompiledParameter,
    resources: []const compilation.CompiledResource,
    buffer: *[definition.max_parameters]compilation.CompiledResource,
) ?[]const compilation.CompiledResource {
    var count: usize = 0;
    for (parameters) |parameter| {
        if (parameter.value != .resource) continue;
        const id = parameter.value.resource;
        var duplicate = false;
        for (buffer[0..count]) |bound| {
            if (std.mem.eql(u8, bound.id.bytes, id.bytes)) {
                duplicate = true;
                break;
            }
        }
        if (duplicate) continue;
        const resource = findResource(resources, id) orelse return null;
        if (count == buffer.len) return null;
        buffer[count] = resource;
        count += 1;
    }
    return buffer[0..count];
}
fn findResource(resources: []const compilation.CompiledResource, id: workflow.WorkflowResourceId) ?compilation.CompiledResource {
    for (resources) |resource| {
        if (std.mem.eql(u8, resource.id.bytes, id.bytes)) return resource;
    }
    return null;
}
fn containsOutcome(outcomes: []const workflow.OutcomeTag, outcome: workflow.OutcomeTag) bool {
    for (outcomes) |allowed| if (allowed == outcome) return true;
    return false;
}
fn hasModelSlot(parameters: []const compilation.CompiledParameter) bool {
    for (parameters) |parameter| if (parameter.value == .model_slot) return true;
    return false;
}
fn runtimeTerminal(runtime: pipeline.NodeRuntime) ?workflow.OutcomeTag {
    return switch (runtime.status()) {
        .active => null,
        .cancelled => .cancelled,
        .deadline_exhausted => .failed,
    };
}
