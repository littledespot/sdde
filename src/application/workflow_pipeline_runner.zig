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
const envelope_module = @import("pipeline_envelope.zig");
const data = @import("../domain/pipeline_data.zig");

pub const Runner = struct {
    selected: execution.SelectedWorkflow,
    operation_registry: *const operations.Registry,
    barrier: telemetry_barrier.Barrier,
    runtime: pipeline.NodeRuntime,
    model_provider_services: ?*const provider_services.ModelProviderBootstrapServices = null,
    resolve_provider_binding_action: resolve_provider_binding.Action = .{},
    envelope: envelope_module.PipelineEnvelope,
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
            .envelope = .init(selected.graph.authority.data_schemas),
            .token_accounting = workflow_token_runner.Runner.init(
                allocator,
                selected.graph.authority.total_model_token_budget,
            ),
        };
    }

    pub fn deinit(self: *Runner) void {
        self.envelope.deinit();
        self.token_accounting.deinit();
        self.* = undefined;
    }

    pub fn bindings(self: *Runner) child_bindings.ChildBindings {
        return .{ .context = self, .vtable = &vtable };
    }

    fn invokeInvocation(self: *Runner) execution.Applied {
        if (runtimeTerminal(self.runtime)) |outcome| return .{ .rejected = outcome };
        if (!self.authorityMatches()) return .{ .rejected = .authority };
        const authority = self.selected.graph.authority;
        const entry = self.operation_registry.resolveOperation(authority.invocation_operation_id) orelse {
            return .{ .rejected = .authority };
        };
        if (entry.contract.kind != .invocation or
            !std.mem.eql(pipeline.DataKey, entry.contract.produces, authority.invocation_outputs))
        {
            return .{ .rejected = .authority };
        }
        var candidate = entry.invoke(.{ .invocation = .{ .arguments = self.selected.invocation.arguments } }) catch {
            return .{ .outcome = .failed };
        };
        defer self.envelope.discard(&candidate.delta);
        if (runtimeTerminal(self.runtime)) |outcome| return .{ .rejected = outcome };
        if (!containsOutcome(entry.contract.outcomes, candidate.outcome)) return .{ .outcome = .failed };
        const contract: pipeline.NodeContract = .{
            .id = authority.invocation_operation_id.bytes,
            .kind = .action,
            .requires = &.{},
            .produces = authority.invocation_outputs,
            .side_effect = .none,
        };
        return self.applyCandidate(contract, &candidate);
    }

    fn invokeStep(self: *Runner, id: workflow.WorkflowStepId) execution.Applied {
        if (runtimeTerminal(self.runtime)) |outcome| return .{ .rejected = outcome };
        if (!self.authorityMatches()) return .{ .rejected = .authority };
        const index = findStepIndex(self.selected.graph.authority.steps, id) orelse return .{ .rejected = .authority };
        if (index >= self.retry_execution_counts.len) return .{ .rejected = .authority };
        const step = &self.selected.graph.authority.steps[index];
        const entry = self.operation_registry.resolveOperation(step.operation_id) orelse return .{ .rejected = .authority };
        if (!contractMatchesStep(entry.contract, step.*) or
            !equalStrings(entry.binding.capabilities(), step.capabilities) or
            !@import("../domain/workflow_capability.zig").permits(self.selected.graph.authority.allowed_capabilities, entry.binding.capabilities())) return .{ .rejected = .authority };
        for (step.gates) |gate| {
            if (runtimeTerminal(self.runtime)) |outcome| return .{ .rejected = outcome };
            const current = self.operation_registry.resolveGate(gate.id) orelse return .{ .rejected = .authority };
            if (!gate.eql(current.*)) return .{ .rejected = .authority };
            if (self.envelope.checkGate(gate)) |reason| return .{ .rejected = .{ .gate = reason } };
        }
        if (runtimeTerminal(self.runtime)) |outcome| return .{ .rejected = outcome };
        if (entry.contract.model_capacity) |capacity| {
            const expected = @import("../domain/workflow_model.zig").resolve(
                self.operation_registry.model_capacity orelse return .{ .outcome = .failed },
                capacity,
                step.parameters,
            ) orelse return .{ .outcome = .failed };
            if (!std.meta.eql(expected, step.model orelse return .{ .outcome = .failed })) return .{ .outcome = .failed };
        } else if (step.model != null) return .{ .outcome = .failed };
        const input_data = self.envelope.view(stepPipelineContract(step.*)) catch return .{ .outcome = .invalid };
        var resource_buffer: [definition.max_parameters]compilation.CompiledResource = undefined;
        const resources = bindStepResources(
            step.parameters,
            self.selected.graph.authority.resources,
            &resource_buffer,
        ) orelse return .{ .outcome = .failed };
        var resolved_binding = self.resolveModelBinding(step.*) catch {
            return .{ .outcome = .failed };
        };
        if (runtimeTerminal(self.runtime)) |outcome| return .{ .rejected = outcome };
        if (step.retry_authority) |authority| {
            if (self.retry_execution_counts[index] > @as(u64, authority.limit.value)) return .{ .outcome = .failed };
            self.retry_execution_counts[index] = std.math.add(u64, self.retry_execution_counts[index], 1) catch {
                return .{ .outcome = .failed };
            };
        }
        var candidate = entry.invoke(.{ .step = .{
            .data = input_data,
            .step = step,
            .resources = resources,
            .model_binding = if (resolved_binding) |*value| value else null,
            .log = pipeline.WorkflowLog.init(self.selected.graph.shortcode),
        } }) catch return .{ .outcome = .failed };
        defer self.envelope.discard(&candidate.delta);
        if (runtimeTerminal(self.runtime)) |outcome| return .{ .rejected = outcome };
        if (!containsOutcome(step.outcomes, candidate.outcome)) return .{ .outcome = .failed };
        return self.applyCandidate(stepPipelineContract(step.*), &candidate);
    }

    pub fn tokenLedger(self: *const Runner) *const @import("../domain/workflow_token_accounting.zig").Ledger {
        return self.token_accounting.current();
    }

    fn resolveModelBinding(
        self: *Runner,
        step: compilation.CompiledStep,
    ) resolve_provider_binding.Error!?provider_binding.ValidatedProviderModelBinding {
        if (!@import("../domain/workflow_model.zig").validProjection(step)) return error.ProviderModelBindingInvalid;
        if (step.model == null) return null;
        const services = self.model_provider_services orelse {
            return error.ProviderModelBindingInvalid;
        };
        var binding_envelope = pipeline.DataShape.init(&.{
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
            pipeline.DataEffects.fromContract(resolve_provider_binding.Action.contract),
        ) catch return error.ProviderModelBindingInvalid;
        std.debug.assert(binding_envelope.contains(.validated_provider_model_binding));
        return resolved;
    }

    fn authorityMatches(self: *const Runner) bool {
        if (!self.operation_registry.validate()) return false;
        const authority = self.selected.graph.authority;
        const policy = self.operation_registry.resolvePolicy(authority.policy_profile_id) orelse return false;
        if (!equalStrings(policy.allowed_capabilities, authority.allowed_capabilities) or
            policy.total_model_token_budget.value != authority.total_model_token_budget.value) return false;
        for (self.selected.graph.authority.data_schemas) |schema| {
            const current = data.find(self.operation_registry.data_schemas, schema.key) orelse return false;
            if (!schema.eql(current)) return false;
        }
        return true;
    }

    fn applyCandidate(self: *Runner, contract: pipeline.NodeContract, candidate: *execution.Candidate) execution.Applied {
        self.envelope.apply(contract, &candidate.delta, candidate.outcome) catch return .{ .outcome = .invalid };
        for (candidate.delta.addedTelemetryFacts()) |fact| {
            const logging_result = self.barrier.process(fact);
            if (logging_result == .blocked) return .{ .rejected = .{ .logging = logging_result.blocked } };
        }
        return .{ .outcome = candidate.outcome };
    }
};

fn stepPipelineContract(step: compilation.CompiledStep) pipeline.NodeContract {
    return .{
        .id = step.operation_id.bytes,
        .kind = .action,
        .requires = step.requires,
        .optional = step.optional,
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
        std.mem.eql(pipeline.DataKey, contract.optional, step.optional) and
        std.mem.eql(pipeline.DataKey, contract.produces, step.produces) and
        std.mem.eql(pipeline.DataKey, contract.replaces, step.replaces) and
        std.mem.eql(pipeline.DataKey, contract.invalidates, step.invalidates) and
        std.mem.eql(workflow.OutcomeTag, contract.outcomes, step.outcomes) and
        contract.side_effect == step.side_effect and
        gateIdsMatch(contract.gates, step.gates) and
        retryContractMatches(contract, step);
}
fn gateIdsMatch(ids: []const []const u8, gates: []const @import("../domain/workflow_gate.zig").Contract) bool {
    if (ids.len != gates.len) return false;
    for (ids, gates) |id, gate| if (!std.mem.eql(u8, id, gate.id.bytes)) return false;
    return true;
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
fn runtimeTerminal(runtime: pipeline.NodeRuntime) ?execution.Rejection {
    return switch (runtime.status()) {
        .active => null,
        .cancelled => .cancelled,
        .deadline_exhausted => .deadline_exhausted,
    };
}
