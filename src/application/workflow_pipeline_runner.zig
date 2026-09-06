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
const model_accounting = @import("workflow_model_accounting.zig");
const attempt = @import("../domain/model_attempt_accounting.zig");
const requests = @import("model_request_workflow.zig");
const identity = @import("../domain/model_request_identity.zig");
const values = @import("pipeline_values.zig");
const lifecycle = @import("../domain/provider_operation_lifecycle.zig");
const operation_selection = @import("../domain/workflow_provider_operation.zig");
const authorization_selection = @import("../domain/workflow_provider_authorization.zig");
const authorization_binding = @import("workflow_provider_authorization.zig");
const authorization_workflow = @import("provider_authorization_workflow.zig");
const authorization_result = @import("../domain/provider_authorization_result.zig");
const lease = @import("../ports/provider_authorization_lease.zig");
const request_lifecycle_selection = @import("../domain/workflow_model_request_lifecycle.zig");
const request_lifecycle_binding = @import("workflow_model_request_lifecycle.zig");
const provider = @import("../domain/llm_provider_operation.zig");
const model_invocation = @import("workflow_model_invocation.zig");
const invocation_validation = @import("../domain/provider_invocation_validation.zig");
const operation_completion = @import("provider_operation_completion_workflow.zig");
const operation_termination = @import("provider_operation_termination_workflow.zig");

const ExpectedAccounting = union(enum) {
    none,
    attempt: attempt.Attempt,
    assignment: provider.ProviderOperationKind,
    invocation: lifecycle.Invocation,
    completion: model_accounting.Completion,
};

pub const Runner = struct {
    allocator: std.mem.Allocator,
    selected: execution.SelectedWorkflow,
    operation_registry: *const operations.Registry,
    barrier: telemetry_barrier.Barrier,
    runtime: pipeline.NodeRuntime,
    model_provider_services: ?*const provider_services.ModelProviderBootstrapServices = null,
    resolve_provider_binding_action: resolve_provider_binding.Action = .{},
    envelope: envelope_module.PipelineEnvelope,
    token_accounting: workflow_token_runner.Runner,
    model_accounting: ?model_accounting.State = null,
    provider_clock: ?lease.Clock = null,
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
            .allocator = allocator,
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
        if (self.model_accounting) |*state| state.deinit();
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
            return .{ .rejected = .operation_failed };
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
        return self.applyCandidate(contract, &candidate, .none);
    }

    fn invokeStep(self: *Runner, id: workflow.WorkflowStepId) execution.Applied {
        if (runtimeTerminal(self.runtime)) |outcome| return .{ .rejected = outcome };
        if (!self.authorityMatches()) return .{ .rejected = .authority };
        const index = findStepIndex(self.selected.graph.authority.steps, id) orelse return .{ .rejected = .authority };
        if (index >= self.retry_execution_counts.len) return .{ .rejected = .authority };
        const step = &self.selected.graph.authority.steps[index];
        if (!@import("../domain/workflow_model_invocation.zig").validProjection(step.*) or
            !operation_selection.validProjection(step.*) or
            !request_lifecycle_selection.validProjection(step.*)) return .{ .rejected = .authority };
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
        if (entry.contract.requiresModelBinding()) {
            const expected = @import("../domain/workflow_model.zig").resolve(
                step.parameters,
            ) orelse return .{ .outcome = .failed };
            if (!std.meta.eql(expected, step.model orelse return .{ .outcome = .failed })) return .{ .outcome = .failed };
        } else if (step.model != null) return .{ .outcome = .failed };
        for (step.capabilities) |capability| {
            if (std.mem.eql(u8, capability, @import("../domain/workflow_capability.zig").model_provider)) {
                self.token_accounting.check() catch |err| return .{ .rejected = .{ .token_budget = err } };
            }
        }
        const input_data = self.envelope.view(stepPipelineContract(step.*)) catch return .{ .outcome = .invalid };
        const advances_request = request_lifecycle_selection.advances(step.replaces, step.produces);
        const completes_request = advances_request and request_lifecycle_selection.completes(step.requires);
        const invokes_operation = operation_selection.invokes(step.produces);
        const completes_operation = operation_selection.completes(step.produces);
        const calls_model = step.side_effect == .model_call;
        const validates_observation = @import("../domain/workflow_model_invocation.zig").validates(step.produces);
        if (self.model_accounting) |state| {
            if (input_data.contains(.model_request_identity_ledger)) {
                const current = values.read(&input_data, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return .{ .rejected = .authority };
                if (current != identity.ledger(state.requests)) return .{ .rejected = .authority };
            }
        }
        var resource_buffer: [definition.max_parameters]compilation.CompiledResource = undefined;
        const resources = bindStepResources(
            step.parameters,
            self.selected.graph.authority.resources,
            &resource_buffer,
        ) orelse return .{ .outcome = .failed };
        const retained_request = if (entry.contract.consumesPreparedRequest())
            @import("model_request_workflow.zig").readCurrent(&input_data, @import("model_request_workflow.zig").prepared_schema) catch return .{ .rejected = .authority }
        else
            null;
        if (retained_request) |request| {
            if (request.prepared() == null) return .{ .rejected = .authority };
        }
        if (input_data.slots[@intFromEnum(pipeline.DataKey.accounted_model_attempt)] != null) {
            const state = if (self.model_accounting) |*value| value else return .{ .rejected = .authority };
            const evidence = values.read(&input_data, model_accounting.schema, attempt.AccountedAttempt) catch return .{ .rejected = .authority };
            const request = retained_request orelse return .{ .rejected = .authority };
            const current = attempt.accounting(state.attempts);
            if (evidence.requestId() != request.id() or current.attemptsReserved(request.id()) != evidence.ordinal().value or
                !current.stageRunEpochId().eql(request.id().stage_run_epoch_id)) return .{ .rejected = .authority };
        }
        var operation_id: ?provider.ProviderOperationId = null;
        var authorization_deadline: ?u64 = null;
        if (input_data.contains(.assigned_provider_operation)) {
            const state = if (self.model_accounting) |*value| value else return .{ .rejected = .authority };
            const evidence = values.read(&input_data, model_accounting.operation_schema, lifecycle.AssignedOperation) catch return .{ .rejected = .authority };
            const request = retained_request orelse return .{ .rejected = .authority };
            state.validateAssignment(evidence, request.prepared().?) catch return .{ .rejected = .authority };
            operation_id = evidence.record().id;
        }
        if (input_data.contains(.invoked_provider_operation)) {
            if (operation_id != null) return .{ .rejected = .authority };
            const state = if (self.model_accounting) |*value| value else return .{ .rejected = .authority };
            const evidence = (values.read(&input_data, model_accounting.invoked_schema, lifecycle.InvokedOperation) catch return .{ .rejected = .authority }).operation();
            state.validateInvocation(evidence, (retained_request orelse return .{ .rejected = .authority }).prepared().?) catch return .{ .rejected = .authority };
            operation_id = evidence.id;
        }
        if (input_data.contains(.terminal_provider_operation)) {
            if (operation_id != null) return .{ .rejected = .authority };
            const state = if (self.model_accounting) |*value| value else return .{ .rejected = .authority };
            const evidence = values.read(&input_data, model_accounting.terminal_schema, lifecycle.TerminalOperation) catch return .{ .rejected = .authority };
            state.validateTerminal(evidence, (retained_request orelse return .{ .rejected = .authority }).prepared().?) catch return .{ .rejected = .authority };
            operation_id = evidence.record().id;
        }
        if (completes_request) {
            _ = @import("model_request_completion_workflow.zig").readCurrent(&input_data) catch return .{ .rejected = .authority };
            self.model_accounting.?.current_operations.validateRequestClosure(retained_request.?.id()) catch return .{ .rejected = .authority };
        }
        if (input_data.contains(.provider_authorization_result)) {
            const state = if (self.model_accounting) |*value| value else return .{ .rejected = .authority };
            const result = values.read(&input_data, authorization_workflow.schema, authorization_result.Result) catch return .{ .rejected = .authority };
            authorization_deadline = authorization_binding.validateConsumer(&state.authorization_leases, result, retained_request orelse return .{ .rejected = .authority }, operation_id orelse return .{ .rejected = .authority }, self.provider_clock, self.runtime) catch |err| return authorizationRejected(err);
            if (advances_request or invokes_operation or calls_model) authorization_binding.requirePrepared(result) catch |err| return authorizationRejected(err);
        }
        var resolved_binding = self.resolveModelBinding(step.*) catch {
            return .{ .outcome = .failed };
        };
        if (runtimeTerminal(self.runtime)) |outcome| return .{ .rejected = outcome };
        const call: ?invocation_validation.Call = if (calls_model or validates_observation) call: {
            const request = retained_request orelse return .{ .rejected = .authority };
            const state = if (self.model_accounting) |*value| value else return .{ .rejected = .authority };
            const id_value = operation_id orelse return .{ .rejected = .authority };
            const invoked = state.current_operations.requireInvoked(id_value) catch return .{ .rejected = .authority };
            if (!provider.validateInferenceInvocation(request.binding(), request.prepared().?, invoked)) return .{ .rejected = .authority };
            if (calls_model) self.token_accounting.prepare(id_value) catch return .{ .rejected = .operation_failed };
            break :call .{ .request = request.prepared().?, .provider_binding = request.binding(), .operations = state.current_operations, .operation_id = id_value };
        } else null;
        const token_revision = self.token_accounting.current().revision();
        var attempt_input: @FieldType(operations.StepInput, "model_attempt") = null;
        var provider_input: @FieldType(operations.StepInput, "provider_operation") = null;
        var expected: ExpectedAccounting = .none;
        if (step.runner_accounting == .increment_model_attempt) {
            const current_requests = values.read(&input_data, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return .{ .rejected = .authority };
            if (self.model_accounting == null) self.model_accounting = model_accounting.State.init(self.allocator, current_requests) catch return .{ .rejected = .operation_failed };
            const state = &self.model_accounting.?;
            const current = attempt.accounting(state.attempts);
            if (!current.stageRunEpochId().eql(current_requests.stageRunEpochId())) return .{ .rejected = .authority };
            const authority = step.retry_authority orelse return .{ .rejected = .authority };
            const executions = self.retry_execution_counts[index];
            attempt_input = .{
                .accounting = current,
                .operations = state.current_operations,
                .attempt = if (executions == 0) .initial else .{ .retry = .{ .authority = authority, .completed_retries = executions - 1 } },
            };
            expected = .{ .attempt = attempt_input.?.attempt };
        }
        if (step.runner_accounting == .advance_provider_operation) {
            const current_requests = values.read(&input_data, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return .{ .rejected = .authority };
            const state = if (self.model_accounting) |*value| value else return .{ .rejected = .authority };
            provider_input = .{ .ledger = state.current_operations, .authority = state.operationAuthority(current_requests) };
            if (invokes_operation) {
                if (!operation_selection.invokesTransition(step.parameters)) return .{ .rejected = .authority };
                const invocation: lifecycle.Invocation = .{ .deadline_monotonic_ms = authorization_deadline orelse return .{ .rejected = .authority } };
                provider_input.?.invocation = invocation;
                expected = .{ .invocation = invocation };
            } else if (completes_operation) {
                expected = .{ .completion = (if (operation_selection.terminatesAssigned(step.requires)) operation_termination.readCurrent(&input_data) else operation_completion.readCurrent(&input_data)) catch return .{ .rejected = .authority } };
            } else {
                expected = .{ .assignment = operation_selection.resolve(step.parameters) orelse return .{ .rejected = .authority } };
            }
        }
        if (step.retry_authority) |authority| {
            if (self.retry_execution_counts[index] > @as(u64, authority.limit.value)) return .{ .outcome = .failed };
            self.retry_execution_counts[index] = std.math.add(u64, self.retry_execution_counts[index], 1) catch {
                return .{ .outcome = .failed };
            };
        }
        var authorization: ?authorization_binding.Binding = null;
        var authorization_published = false;
        defer if (authorization) |bound| {
            if (!authorization_published) bound.cancel();
        };
        if (authorization_selection.prepares(step.produces)) {
            const state = if (self.model_accounting) |*value| value else return .{ .rejected = .authority };
            const evidence = values.read(&input_data, model_accounting.operation_schema, lifecycle.AssignedOperation) catch return .{ .rejected = .authority };
            authorization = authorization_binding.Binding.allocate(&state.authorization_leases, retained_request orelse return .{ .rejected = .authority }, evidence.record().id, authorization_selection.timeout(step.parameters) orelse return .{ .rejected = .authority }, self.provider_clock orelse return .{ .rejected = .authority }, self.runtime) catch |err| return switch (err) {
                error.OutOfMemory => .{ .rejected = .operation_failed },
                else => |failure| authorizationRejected(failure),
            };
        }
        var candidate = entry.invoke(.{ .step = .{
            .data = input_data,
            .step = step,
            .resources = resources,
            .model_binding = if (retained_request) |request| request.binding() else if (resolved_binding) |*value| value else null,
            .log = pipeline.WorkflowLog.init(self.selected.graph.shortcode),
            .model_attempt = attempt_input,
            .model_request_lifecycle = if (advances_request) self.model_accounting.?.current_operations else null,
            .provider_invocation = if (validates_observation) call else null,
            .provider_operation = provider_input,
            .provider_authorization = if (authorization) |bound| .{ .facts = bound.facts, .slot = bound.slot, .runtime = bound.runtime } else null,
        } }) catch {
            if (calls_model) {
                const invoked = call.?;
                if (model_invocation.reconcile(&self.token_accounting, token_revision, invoked, null)) |reason| return .{ .rejected = reason };
            }
            return .{ .rejected = .operation_failed };
        };
        defer self.envelope.discard(&candidate.delta);
        if (calls_model) {
            const invoked = call.?;
            if (model_invocation.reconcile(&self.token_accounting, token_revision, invoked, &candidate)) |reason| return .{ .rejected = reason };
            if (candidate.outcome != .cancelled) authorization_binding.checkDeadline(self.provider_clock.?, self.runtime, authorization_deadline.?) catch |err| return authorizationRejected(err);
        }
        if (runtimeTerminal(self.runtime)) |outcome| return .{ .rejected = outcome };
        if (!containsOutcome(step.outcomes, candidate.outcome)) return .{ .outcome = .failed };
        if (advances_request and !completes_request) {
            const result = values.read(&input_data, authorization_workflow.schema, authorization_result.Result) catch return .{ .rejected = .authority };
            const assigned = values.read(&input_data, model_accounting.operation_schema, lifecycle.AssignedOperation) catch return .{ .rejected = .authority };
            const deadline = authorization_binding.validateConsumer(&self.model_accounting.?.authorization_leases, result, retained_request.?, assigned.record().id, self.provider_clock.?, self.runtime) catch |err| return authorizationRejected(err);
            if (deadline != authorization_deadline) return .{ .rejected = .authority };
        }
        const prepared = if (authorization) |bound| prepared: {
            const result = values.read(&.{ .slots = candidate.delta.data_writes }, authorization_workflow.schema, authorization_result.Result) catch return .{ .rejected = .authority };
            break :prepared bound.validate(result, candidate.outcome) catch |err| return authorizationRejected(err);
        } else false;
        const applied = self.applyCandidate(stepPipelineContract(step.*), &candidate, expected);
        authorization_published = prepared and applied == .outcome and applied.outcome == .ok;
        return applied;
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

    fn applyCandidate(self: *Runner, contract: pipeline.NodeContract, candidate: *execution.Candidate, expected: ExpectedAccounting) execution.Applied {
        var request_owner: ?*identity.Owner = null;
        defer if (request_owner) |owner| identity.deinitOwner(owner);
        if (candidate.delta.data_replacements[@intFromEnum(pipeline.DataKey.model_request_identity_ledger)] != null) {
            const input = self.envelope.view(contract) catch return .{ .rejected = .authority };
            const successor = request_lifecycle_binding.validateReplacement(&input, contract, &candidate.delta, candidate.outcome, if (self.model_accounting) |state| state.current_operations else null) catch return .{ .rejected = .authority };
            if (self.model_accounting != null) request_owner = identity.retainLedger(successor) catch return .{ .rejected = .operation_failed };
        }
        var pending: ?model_accounting.Pending = null;
        defer if (pending) |unapplied| unapplied.discard();
        if (expected != .none) {
            const expected_outcome: workflow.OutcomeTag = if (expected == .completion) expected.completion.outcome else .ok;
            if (candidate.outcome != expected_outcome) return .{ .outcome = .invalid };
            const transition = candidate.delta.runner_accounting_transition orelse return .{ .outcome = .invalid };
            const key = @intFromEnum(@as(pipeline.DataKey, switch (expected) {
                .attempt => .accounted_model_attempt,
                .assignment => .assigned_provider_operation,
                .invocation => .invoked_provider_operation,
                .completion => .terminal_provider_operation,
                .none => unreachable,
            }));
            // Only application of the declared runner transition creates evidence.
            if (candidate.delta.data_writes[key] != null or candidate.delta.data_replacements[key] != null) return .{ .outcome = .invalid };
            const view = self.envelope.view(contract) catch return .{ .outcome = .invalid };
            const request = requests.readCurrent(&view, requests.prepared_schema) catch return .{ .rejected = .authority };
            const current = values.read(&view, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return .{ .rejected = .authority };
            const state = if (self.model_accounting) |*value| value else return .{ .rejected = .authority };
            switch (expected) {
                .attempt => |classification| {
                    if (transition != .increment_model_attempt) return .{ .outcome = .invalid };
                    pending = state.prepare(current, request.id(), classification, transition.increment_model_attempt) catch |err| return if (err == error.OutOfMemory) .{ .rejected = .operation_failed } else .{ .outcome = .invalid };
                },
                .assignment => |kind| {
                    if (transition != .advance_provider_operation) return .{ .outcome = .invalid };
                    pending = state.prepareAssignment(current, request.prepared().?, kind, transition.advance_provider_operation) catch |err| return if (err == error.OutOfMemory) .{ .rejected = .operation_failed } else .{ .outcome = .invalid };
                },
                .invocation => |invocation| {
                    if (transition != .advance_provider_operation or !candidate.delta.data_invalidations.contains(.assigned_provider_operation)) return .{ .outcome = .invalid };
                    const assigned = values.read(&view, model_accounting.operation_schema, lifecycle.AssignedOperation) catch return .{ .rejected = .authority };
                    pending = state.prepareInvocation(current, request.prepared().?, assigned, invocation, transition.advance_provider_operation) catch |err| return if (err == error.OutOfMemory) .{ .rejected = .operation_failed } else .{ .outcome = .invalid };
                },
                .completion => |facts| {
                    if (transition != .advance_provider_operation or !candidate.delta.data_invalidations.contains(facts.source.key())) return .{ .outcome = .invalid };
                    pending = state.prepareCompletion(current, request.prepared().?, facts, transition.advance_provider_operation) catch |err| return if (err == error.OutOfMemory) .{ .rejected = .operation_failed } else .{ .outcome = .invalid };
                },
                .none => unreachable,
            }
            candidate.delta.data_writes[key] = pending.?.value;
            if (expected == .invocation) {
                const result = values.read(&view, authorization_workflow.schema, authorization_result.Result) catch return .{ .rejected = .authority };
                const assigned = values.read(&view, model_accounting.operation_schema, lifecycle.AssignedOperation) catch return .{ .rejected = .authority };
                const deadline = authorization_binding.validateConsumer(&state.authorization_leases, result, request, assigned.record().id, self.provider_clock orelse return .{ .rejected = .authority }, self.runtime) catch |err| return authorizationRejected(err);
                if (deadline != expected.invocation.deadline_monotonic_ms) return .{ .rejected = .authority };
            }
        }
        if (runtimeTerminal(self.runtime)) |outcome| return .{ .rejected = outcome };
        self.envelope.apply(contract, &candidate.delta, candidate.outcome) catch return .{ .outcome = .invalid };
        if (request_owner) |owner| {
            self.model_accounting.?.replaceRequests(owner);
            request_owner = null;
        }
        if (pending) |applied| {
            self.model_accounting.?.commit(applied);
            pending = null;
        }
        for (candidate.delta.addedTelemetryFacts()) |fact| {
            const logging_result = self.barrier.process(fact);
            if (logging_result == .blocked) return .{ .rejected = .{ .logging = logging_result.blocked } };
        }
        return .{ .outcome = candidate.outcome };
    }
};

fn authorizationRejected(err: lease.Error) execution.Applied {
    return .{ .rejected = switch (err) {
        error.Cancelled => .cancelled,
        error.AuthorizationExpired => .deadline_exhausted,
        error.AuthorizationDenied, error.ClockUnavailable => .authority,
    } };
}

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
        .runner_accounting = step.runner_accounting,
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
        contract.runner_accounting == step.runner_accounting and
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
