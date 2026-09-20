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
const retry = @import("../domain/workflow_retry.zig");
const event_capture = @import("workflow_event_capture.zig");

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
    model_capture: @import("model_exchange_capture.zig").Capture,
    runtime: pipeline.NodeRuntime,
    model_provider_services: ?*const provider_services.ModelProviderBootstrapServices = null,
    resolve_provider_binding_action: resolve_provider_binding.Action = .{},
    envelope: envelope_module.PipelineEnvelope,
    token_accounting: workflow_token_runner.Runner,
    model_accounting: ?model_accounting.State = null,
    provider_clock: ?lease.Clock = null,
    publication_finalizer: ?@import("../ports/feature_log_activation.zig").Finalizer = null,
    retry_execution_counts: [definition.max_steps]u64 = [_]u64{0} ** definition.max_steps,
    repair_retry: retry.State,
    events_closed: bool = false,

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
            .model_capture = .{ .allocator = allocator, .logs = barrier },
            .runtime = runtime,
            .model_provider_services = model_provider_services,
            .envelope = .init(allocator, selected.graph.authority.data_schemas),
            .token_accounting = workflow_token_runner.Runner.init(
                allocator,
                selected.graph.authority.total_model_token_budget,
            ),
            .repair_retry = retry.State.init(allocator),
        };
    }

    pub fn deinit(self: *Runner) void {
        self.model_capture.deinit();
        self.repair_retry.deinit();
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
        const occurrence = self.envelope.beginOccurrence(authority.invocation_operation_id.bytes) catch return .{ .rejected = .{ .operation_failed = error.OperationExecutionFailed } };
        var candidate = entry.invoke(.{ .invocation = .{ .arguments = self.selected.invocation.arguments } }) catch |err| {
            return .{ .rejected = .{ .operation_failed = err } };
        };
        defer self.envelope.discard(&candidate.delta);
        if (runtimeTerminal(self.runtime)) |outcome| return .{ .rejected = outcome };
        if (!containsOutcome(entry.contract.outcomes, candidate.outcome)) return .{ .rejected = .authority };
        const contract: pipeline.NodeContract = .{
            .id = authority.invocation_operation_id.bytes,
            .kind = .action,
            .requires = &.{},
            .produces = authority.invocation_outputs,
            .side_effect = .none,
        };
        return self.applyCandidate(occurrence, contract, &candidate, .none);
    }

    fn invokeStep(self: *Runner, id: workflow.WorkflowStepId) execution.Applied {
        const started = self.eventsActive();
        if (started) if (self.events().action(id, null)) |failure| return .{ .rejected = .{ .logging = failure } };
        const result = self.executeStep(id);
        if (self.eventsActive()) {
            if (!started) if (self.events().action(id, null)) |failure| return .{ .rejected = .{ .logging = failure } };
            if (self.events().action(id, result)) |failure| return .{ .rejected = .{ .logging = failure } };
            if (result == .rejected and result.rejected == .retry_limit) {
                if (self.events().retryAttempt(id, result.rejected.retry_limit.completed_executions, true)) |failure| return .{ .rejected = .{ .logging = failure } };
            }
        }
        return result;
    }

    fn eventsActive(self: *const Runner) bool {
        return !self.events_closed and self.envelope.slots[@intFromEnum(pipeline.DataKey.activated_feature_directory)] != null;
    }

    fn events(self: *const Runner) event_capture.Capture {
        return .{ .barrier = self.barrier, .shortcode = self.selected.graph.shortcode };
    }

    fn executeStep(self: *Runner, id: workflow.WorkflowStepId) execution.Applied {
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
            ) orelse return .{ .rejected = .authority };
            if (!std.meta.eql(expected, step.model orelse return .{ .rejected = .authority })) return .{ .rejected = .authority };
        } else if (step.model != null) return .{ .rejected = .authority };
        for (step.capabilities) |capability| {
            if (std.mem.eql(u8, capability, @import("../domain/workflow_capability.zig").model_provider)) {
                self.token_accounting.check() catch |err| return .{ .rejected = .{ .token_budget = err } };
            }
        }
        const input_data = self.envelope.view(stepPipelineContract(step.*)) catch return .{ .rejected = .authority };
        const advances_request = request_lifecycle_selection.advances(step.replaces, step.produces);
        const completes_request = advances_request and request_lifecycle_selection.completes(step.requires);
        const invokes_operation = operation_selection.invokes(step.produces);
        const completes_operation = operation_selection.completes(step.produces);
        const calls_model = step.side_effect == .model_call;
        const calls_count = calls_model and @import("../domain/workflow_model_invocation.zig").counts(step.produces);
        const validates_observation = @import("../domain/workflow_model_invocation.zig").validates(step.produces);
        const validates_count = @import("../domain/workflow_model_invocation.zig").validatesCount(step.produces);
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
        ) orelse return .{ .rejected = .authority };
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
            _ = request_lifecycle_binding.readClosure(&input_data) catch return .{ .rejected = .authority };
            self.model_accounting.?.current_operations.validateRequestClosure(retained_request.?.id()) catch return .{ .rejected = .authority };
        }
        if (input_data.contains(.provider_authorization_result)) {
            const state = if (self.model_accounting) |*value| value else return .{ .rejected = .authority };
            const result = values.read(&input_data, authorization_workflow.schema, authorization_result.Result) catch return .{ .rejected = .authority };
            authorization_deadline = authorization_binding.validateConsumer(&state.authorization_leases, result, retained_request orelse return .{ .rejected = .authority }, operation_id orelse return .{ .rejected = .authority }, self.provider_clock, self.runtime) catch |err| return authorizationRejected(err);
            if ((advances_request and !completes_request) or invokes_operation or calls_model) authorization_binding.requirePrepared(result) catch |err| return authorizationRejected(err);
        }
        var resolved_binding = self.resolveModelBinding(step.*) catch {
            return .{ .rejected = .authority };
        };
        if (runtimeTerminal(self.runtime)) |outcome| return .{ .rejected = outcome };
        const call: ?invocation_validation.Call = if (calls_model or validates_observation or validates_count) call: {
            const request = retained_request orelse return .{ .rejected = .authority };
            const state = if (self.model_accounting) |*value| value else return .{ .rejected = .authority };
            const id_value = operation_id orelse return .{ .rejected = .authority };
            const invoked = state.current_operations.requireInvoked(id_value) catch return .{ .rejected = .authority };
            const valid = if (calls_count or validates_count) provider.validateCountInvocation(request.binding(), request.prepared().?, invoked) else provider.validateInferenceInvocation(request.binding(), request.prepared().?, invoked);
            if (!valid) return .{ .rejected = .authority };
            if (calls_model and !calls_count) self.token_accounting.prepare(id_value) catch return .{ .rejected = .{ .operation_failed = error.OperationExecutionFailed } };
            break :call .{ .request = request.prepared().?, .provider_binding = request.binding(), .operations = state.current_operations, .operation_id = id_value };
        } else null;
        const token_revision = self.token_accounting.current().revision();
        const repair_permit: ?retry.Permit = if (step.retry_authority) |authority| switch (authority.scope) {
            .operation => null,
            .repair => self.repair_retry.currentPermit() orelse return .{ .rejected = .authority },
            .model_request => permit: {
                const request = retained_request orelse return .{ .rejected = .authority };
                if (request.id().purpose != .atomic_repair) {
                    break :permit self.repair_retry.currentDependentPermit();
                }
                const packet = request.packet() orelse return .{ .rejected = .authority };
                const value = packet.repairPermit() orelse return .{ .rejected = .authority };
                var authorization: [32]u8 = undefined;
                std.crypto.hash.sha2.Sha256.hash(request.id().purpose.atomic_repair.bytes, &authorization, .{});
                if (!std.meta.eql(authorization, value.authorization)) return .{ .rejected = .authority };
                break :permit value;
            },
        } else null;
        const request_assignment: ?retry.Assignment = if (step.retry_authority) |authority| assignment: {
            if (authority.scope != .model_request) break :assignment null;
            const request = retained_request orelse return .{ .rejected = .authority };
            if (request.id().purpose == .atomic_repair) break :assignment null;
            break :assignment .{ .request = request.id(), .record = request.ledger().indexOf(request.id()) orelse return .{ .rejected = .authority }, .parent = if (repair_permit) |permit| permit.key else null };
        } else null;
        var attempt_input: @FieldType(operations.StepInput, "model_attempt") = null;
        var provider_input: @FieldType(operations.StepInput, "provider_operation") = null;
        var expected: ExpectedAccounting = .none;
        if (step.runner_accounting == .increment_model_attempt) {
            const current_requests = values.read(&input_data, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return .{ .rejected = .authority };
            if (self.model_accounting == null) self.model_accounting = model_accounting.State.init(self.allocator, current_requests) catch return .{ .rejected = .{ .operation_failed = error.OperationExecutionFailed } };
            const state = &self.model_accounting.?;
            const current = attempt.accounting(state.attempts);
            if (!current.stageRunEpochId().eql(current_requests.stageRunEpochId())) return .{ .rejected = .authority };
            const authority = step.retry_authority orelse return .{ .rejected = .authority };
            const executions = if (request_assignment) |assignment| self.repair_retry.completedAssignmentAttempts(step.id, assignment) else if (repair_permit) |permit| self.repair_retry.completedAttempts(step.id, permit.key) else self.retry_execution_counts[index];
            attempt_input = .{
                .accounting = current,
                .operations = state.current_operations,
                .attempt = if (current.attemptsReserved((retained_request orelse return .{ .rejected = .authority }).id()) == 0) .initial else .{ .retry = .{ .authority = authority, .completed_retries = if (executions == 0) 0 else executions - 1 } },
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
            var admitted_count: u64 = 0;
            if (request_assignment) |assignment| {
                const admitted = self.repair_retry.beginAssignmentAttempt(step.id, authority.limit, assignment) catch |err| return .{ .rejected = if (err == error.OutOfMemory) .{ .operation_failed = error.OperationExecutionFailed } else .authority };
                if (admitted == .exhausted) return .{ .rejected = .{ .retry_limit = retry.Exhaustion.init(step.id, authority.limit, admitted.exhausted) orelse return .{ .rejected = .authority } } };
                admitted_count = admitted.allowed;
            } else if (repair_permit) |permit| {
                const admitted = self.repair_retry.beginAttempt(step.id, authority.limit, permit) catch |err| return .{ .rejected = if (err == error.OutOfMemory) .{ .operation_failed = error.OperationExecutionFailed } else .authority };
                if (admitted == .exhausted) return .{ .rejected = .{ .retry_limit = retry.Exhaustion.init(step.id, authority.limit, admitted.exhausted) orelse return .{ .rejected = .authority } } };
                admitted_count = admitted.allowed;
            } else {
                if (self.retry_execution_counts[index] > authority.limit.value) return .{ .rejected = .{ .retry_limit = retry.Exhaustion.init(step.id, authority.limit, self.retry_execution_counts[index]) orelse return .{ .rejected = .authority } } };
                // Compiled limits are u32; exhaustion is checked before increment.
                self.retry_execution_counts[index] += 1;
                admitted_count = self.retry_execution_counts[index];
            }
            if (self.eventsActive()) if (self.events().retryAttempt(id, admitted_count, false)) |failure| return .{ .rejected = .{ .logging = failure } };
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
                error.OutOfMemory => .{ .rejected = .{ .operation_failed = error.OperationExecutionFailed } },
                else => |failure| authorizationRejected(failure),
            };
        }
        const occurrence = self.envelope.beginOccurrence(step.operation_id.bytes) catch return .{ .rejected = .{ .operation_failed = error.OperationExecutionFailed } };
        if (calls_model) {
            const invoked = call.?;
            const ledger = identity.ledger(self.model_accounting.?.requests);
            const origin = @import("../domain/model_candidate_origin.zig").Origin.from(ledger, invoked.operation_id) orelse return .{ .rejected = .authority };
            self.model_capture.begin(.{
                .workflow = self.selected.graph.shortcode,
                .workflow_id = .{ .bytes = self.selected.graph.authority.workflow_id.bytes },
                .node = .{ .bytes = step.id.bytes },
                .action = .{ .bytes = step.operation_id.bytes },
                .operation = .{ .bytes = invoked.provider_binding.operation_id.workflow_step_id.bytes },
                .model_slot = .{ .bytes = invoked.provider_binding.slot_id.bytes },
                .origin = origin,
                .kind = switch (invoked.operation_id.model_request_id.purpose) {
                    .atomic_repair => .repair,
                    .context_followup => .context_followup,
                    .initial_generation, .semantic_review, .clarification_resolution => .initial,
                },
                .source = if (retained_request.?.packet()) |packet| packet.repairOrigin() else null,
                .description = @import("../domain/model_request_description.zig").Description.from(invoked.request, invoked.provider_binding, invoked.operation_id.kind),
                .source_context = .{ .graph = self.selected.graph, .request = retained_request.? },
            });
            if (self.eventsActive()) if (self.events().model(id, .{ .origin = origin, .binding = invoked.provider_binding.* }, .model_requested, null, null, null)) |failure| {
                self.model_capture.end();
                return .{ .rejected = .{ .logging = failure } };
            };
        }
        defer if (calls_model) self.model_capture.end();
        if (step.side_effect == .workflow_publication) {
            const prepared_output = values.read(&input_data, @import("workflow_output_binding.zig").prepared_schema, @import("../domain/workflow_output.zig").Prepared) catch return .{ .rejected = .authority };
            self.events_closed = true;
            if (self.publication_finalizer) |finalizer| switch (finalizer.beforePublication(prepared_output.terminal_outcome)) {
                .execution => |outcome| if (outcome != .ok and outcome != .needs_user) return .{ .rejected = .authority },
                .execution_rejected => |reason| return .{ .rejected = reason },
                .bootstrap_failed, .invocation_invalid => return .{ .rejected = .authority },
            };
        }
        var candidate = entry.invoke(.{ .step = .{
            .data = input_data,
            .step = step,
            .resources = resources,
            .authority = &self.selected.graph.authority,
            .model_binding = if (retained_request) |request| request.binding() else if (resolved_binding) |*value| value else null,
            .repair_permit = self.repair_retry.currentPermit(),
            .log = pipeline.WorkflowLog.init(self.selected.graph.shortcode),
            .model_attempt = attempt_input,
            .model_request_lifecycle = if (advances_request) self.model_accounting.?.current_operations else null,
            .provider_invocation = if (validates_observation) call else null,
            .provider_token_count = if (validates_count) .{ .request = call.?.request, .provider_binding = call.?.provider_binding, .operations = call.?.operations, .operation_id = call.?.operation_id } else null,
            .provider_operation = provider_input,
            .provider_authorization = if (authorization) |bound| .{ .facts = bound.facts, .slot = bound.slot, .runtime = bound.runtime } else null,
        } }) catch |err| {
            if (calls_model and !calls_count) {
                const invoked = call.?;
                const rejection = model_invocation.reconcile(&self.token_accounting, token_revision, invoked, null);
                if (self.logModelCompletion(id, invoked, .failed)) |failure| return .{ .rejected = .{ .logging = failure } };
                if (self.model_capture.failure) |failure| return .{ .rejected = .{ .logging = failure } };
                if (rejection) |reason| return .{ .rejected = reason };
            }
            if (calls_model) if (self.model_capture.failure) |failure| return .{ .rejected = .{ .logging = failure } };
            return .{ .rejected = .{ .operation_failed = err } };
        };
        defer self.envelope.discard(&candidate.delta);
        if (calls_model) {
            const invoked = call.?;
            const rejection = if (calls_count) model_invocation.validateCount(invoked, &candidate) else model_invocation.reconcile(&self.token_accounting, token_revision, invoked, &candidate);
            if (self.logModelCompletion(id, invoked, if (rejection) |reason| reason.status() else candidate.outcome)) |failure| return .{ .rejected = .{ .logging = failure } };
            if (self.model_capture.failure) |failure| return .{ .rejected = .{ .logging = failure } };
            if (rejection) |reason| return .{ .rejected = reason };
            if (candidate.outcome != .cancelled) authorization_binding.checkDeadline(self.provider_clock.?, self.runtime, authorization_deadline.?) catch |err| return authorizationRejected(err);
        }
        if (runtimeTerminal(self.runtime)) |outcome| return .{ .rejected = outcome };
        if (!containsOutcome(step.outcomes, candidate.outcome)) return .{ .rejected = .authority };
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
        const applied = self.applyCandidate(occurrence, stepPipelineContract(step.*), &candidate, expected);
        authorization_published = prepared and applied == .outcome and applied.outcome == .ok;
        if (applied == .outcome and self.eventsActive()) {
            if (self.logDiagnostics(step.*, candidate)) |failure| return .{ .rejected = .{ .logging = failure } };
        }
        return applied;
    }

    fn logModelCompletion(self: *Runner, id: workflow.WorkflowStepId, call: invocation_validation.Call, status: workflow.OutcomeTag) ?@import("../domain/feature_log_stream.zig").FailureCode {
        if (!self.eventsActive()) return null;
        const origin = @import("../domain/model_candidate_origin.zig").Origin.from(identity.ledger(self.model_accounting.?.requests), call.operation_id) orelse return .LOG_SERIALIZATION_FAILURE;
        var usage: ?provider.ProviderUsage = null;
        for (self.tokenLedger().accounted_operations.items) |accounted| {
            if (accounted.id.eql(call.operation_id) and accounted.reconciliation == .exact_usage) usage = accounted.reconciliation.exact_usage;
        }
        return self.events().model(id, .{ .origin = origin, .binding = call.provider_binding.* }, .model_completed, status, null, usage);
    }

    fn logDiagnostics(self: *Runner, step: compilation.CompiledStep, candidate: execution.Candidate) ?@import("../domain/feature_log_stream.zig").FailureCode {
        const view: data.View = .{ .slots = self.envelope.slots };
        const decoded = @import("model_envelope_workflow.zig");
        const schema_check = @import("model_payload_schema_workflow.zig");
        const produces_decode = std.mem.indexOfScalar(pipeline.DataKey, step.produces, .model_envelope_result) != null;
        const produces_schema = std.mem.indexOfScalar(pipeline.DataKey, step.produces, .model_payload_schema_result) != null;
        if (produces_decode or produces_schema) {
            const request = requests.readCurrent(&view, requests.prepared_schema) catch return .LOG_SERIALIZATION_FAILURE;
            const evidence = values.read(&view, decoded.schema, decoded.Result) catch return .LOG_SERIALIZATION_FAILURE;
            const source = evidence.source();
            const origin = @import("../domain/model_candidate_origin.zig").Origin.from(identity.ledger(self.model_accounting.?.requests), source.operationId()) orelse return .LOG_SERIALIZATION_FAILURE;
            const info: event_capture.Model = .{ .origin = origin, .binding = request.binding().* };
            var reason: ?[]const u8 = null;
            var event: @import("../domain/telemetry.zig").EventType = .model_protocol_failed;
            if (produces_decode) switch (evidence.outcome()) {
                .protocol_rejected => |rejected| reason = @tagName(rejected.diagnostic.reason),
                .not_decoded => if (candidate.outcome == .invalid) {
                    reason = "MISSING_FINAL_TEXT";
                } else return null,
                .decoded => {},
            };
            if (produces_schema and reason == null) {
                const checked = values.read(&view, schema_check.schema, schema_check.Result) catch return .LOG_SERIALIZATION_FAILURE;
                if (checked.outcome() == .schema_rejected) {
                    reason = @tagName(checked.outcome().schema_rejected.reason);
                    event = .model_schema_failed;
                }
            }
            if (reason) |value| if (self.events().model(step.id, info, event, candidate.outcome, value, null)) |failure| return failure;
            if (self.events().validation(step.id, candidate.outcome, reason, origin)) |failure| return failure;
        }
        // Project only this operation's newly published evidence. Reading the
        // complete envelope here would repeatedly attribute historical defects.
        var produced: data.View = .{ .slots = @splat(null) };
        inline for (.{ step.produces, step.replaces }) |keys| for (keys) |key| {
            produced.slots[@intFromEnum(key)] = view.slots[@intFromEnum(key)];
        };
        const diagnostic = @import("candidate_validation_diagnostics.zig").read(&produced) catch return .LOG_SERIALIZATION_FAILURE;
        if (diagnostic) |value| {
            if (value == .support_findings) {
                if (self.events().emit(.{ .event_type = .review_rejected, .node_id = .{ .bytes = step.id.bytes }, .fields = .{ .outcome = event_capture.outcome(candidate.outcome) } })) |failure| return failure;
            }
            if (self.events().validation(step.id, candidate.outcome, @tagName(value), value.origin())) |failure| return failure;
        }
        if (candidate.delta.repair_transition) |transition| {
            if (transition == .validated) return self.events().validation(step.id, candidate.outcome, if (transition.validated.result == .recurring) "REPAIR_RECURRING" else null, null);
            const event: @import("../domain/telemetry.zig").EventType = switch (transition) {
                .authorized => .repair_requested,
                .merged => .repair_applied,
                .validated => unreachable,
                .merged_validated => |value| if (value.result == .resolved) .repair_applied else .repair_rejected,
            };
            if (self.events().repair(step.id, event, candidate.outcome, if (event == .repair_rejected) "REPAIR_RECURRING" else null)) |failure| return failure;
        }
        return null;
    }

    pub fn tokenLedger(self: *const Runner) *const @import("../domain/workflow_token_accounting.zig").Ledger {
        return self.token_accounting.current();
    }

    pub fn retryObservations(self: *const Runner, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const retry.Observation {
        var result: std.ArrayList(retry.Observation) = .empty;
        errdefer {
            for (result.items) |item| item.deinit(allocator);
            result.deinit(allocator);
        }
        for (self.selected.graph.authority.steps, 0..) |step, index| if (step.retry_authority) |authority| {
            const name = try allocator.dupe(u8, step.id.bytes);
            errdefer allocator.free(name);
            const defects = try self.repair_retry.observe(allocator, step.id);
            errdefer {
                for (defects) |defect| defect.deinit(allocator);
                allocator.free(defects);
            }
            const assignments = try self.repair_retry.observeAssignments(allocator, step.id);
            errdefer allocator.free(assignments);
            try result.append(allocator, .{ .step = name, .limit = authority.limit.value, .scope = authority.scope, .operation_executions = self.retry_execution_counts[index], .defects = defects, .assignments = assignments });
        };
        return result.toOwnedSlice(allocator);
    }

    pub fn validateModelBindings(self: *Runner) resolve_provider_binding.Error!void {
        for (self.selected.graph.authority.steps) |step| {
            if (step.model != null) _ = try self.resolveModelBinding(step);
        }
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

    fn applyCandidate(self: *Runner, occurrence: envelope_module.Occurrence, contract: pipeline.NodeContract, candidate: *execution.Candidate, expected: ExpectedAccounting) execution.Applied {
        var request_owner: ?*identity.Owner = null;
        defer if (request_owner) |owner| identity.deinitOwner(owner);
        if (candidate.delta.data_replacements[@intFromEnum(pipeline.DataKey.model_request_identity_ledger)] != null) {
            const input = self.envelope.view(contract) catch return .{ .rejected = .authority };
            const successor = request_lifecycle_binding.validateReplacement(&input, contract, &candidate.delta, candidate.outcome, if (self.model_accounting) |state| state.current_operations else null) catch return .{ .rejected = .authority };
            if (self.model_accounting != null) request_owner = identity.retainLedger(successor) catch return .{ .rejected = .{ .operation_failed = error.OperationExecutionFailed } };
        }
        var pending: ?model_accounting.Pending = null;
        defer if (pending) |unapplied| unapplied.discard();
        if (expected != .none) {
            const expected_outcome: workflow.OutcomeTag = if (expected == .completion) expected.completion.outcome else .ok;
            if (candidate.outcome != expected_outcome) return .{ .rejected = .authority };
            const transition = candidate.delta.runner_accounting_transition orelse return .{ .rejected = .authority };
            const key = @intFromEnum(@as(pipeline.DataKey, switch (expected) {
                .attempt => .accounted_model_attempt,
                .assignment => .assigned_provider_operation,
                .invocation => .invoked_provider_operation,
                .completion => .terminal_provider_operation,
                .none => unreachable,
            }));
            // Only application of the declared runner transition creates evidence.
            if (candidate.delta.data_writes[key] != null or candidate.delta.data_replacements[key] != null) return .{ .rejected = .authority };
            const view = self.envelope.view(contract) catch return .{ .rejected = .authority };
            const request = requests.readCurrent(&view, requests.prepared_schema) catch return .{ .rejected = .authority };
            const current = values.read(&view, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return .{ .rejected = .authority };
            const state = if (self.model_accounting) |*value| value else return .{ .rejected = .authority };
            switch (expected) {
                .attempt => |classification| {
                    if (transition != .increment_model_attempt) return .{ .rejected = .authority };
                    pending = state.prepare(current, request.id(), classification, transition.increment_model_attempt) catch |err| return if (err == error.OutOfMemory) .{ .rejected = .{ .operation_failed = error.OperationExecutionFailed } } else .{ .rejected = .authority };
                },
                .assignment => |kind| {
                    if (transition != .advance_provider_operation) return .{ .rejected = .authority };
                    pending = state.prepareAssignment(current, request.prepared().?, kind, transition.advance_provider_operation) catch |err| return if (err == error.OutOfMemory) .{ .rejected = .{ .operation_failed = error.OperationExecutionFailed } } else .{ .rejected = .authority };
                },
                .invocation => |invocation| {
                    if (transition != .advance_provider_operation or !candidate.delta.data_invalidations.contains(.assigned_provider_operation)) return .{ .rejected = .authority };
                    const assigned = values.read(&view, model_accounting.operation_schema, lifecycle.AssignedOperation) catch return .{ .rejected = .authority };
                    pending = state.prepareInvocation(current, request.prepared().?, assigned, invocation, transition.advance_provider_operation) catch |err| return if (err == error.OutOfMemory) .{ .rejected = .{ .operation_failed = error.OperationExecutionFailed } } else .{ .rejected = .authority };
                },
                .completion => |facts| {
                    if (transition != .advance_provider_operation or !candidate.delta.data_invalidations.contains(facts.source.key())) return .{ .rejected = .authority };
                    pending = state.prepareCompletion(current, request.prepared().?, facts, transition.advance_provider_operation) catch |err| return if (err == error.OutOfMemory) .{ .rejected = .{ .operation_failed = error.OperationExecutionFailed } } else .{ .rejected = .authority };
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
        if (!retry.permitsTransition(contract.repair_role, candidate.delta.repair_transition)) return .{ .rejected = .authority };
        const repair_required = switch (contract.repair_role) {
            .none, .validate => false,
            .authorize => candidate.outcome == .ok or candidate.outcome == .more,
            .merge => candidate.outcome == .ok or candidate.outcome == .more,
            .merge_validate => candidate.outcome == .ok or candidate.outcome == .invalid,
        };
        if (repair_required and candidate.delta.repair_transition == null) return .{ .rejected = .authority };
        const repair_pending = if (candidate.delta.repair_transition) |transition|
            self.repair_retry.prepare(transition) catch |err| return .{ .rejected = if (err == error.OutOfMemory) .{ .operation_failed = error.OperationExecutionFailed } else .authority }
        else
            null;
        self.envelope.applyOccurrence(occurrence, contract, &candidate.delta, candidate.outcome) catch |err| return if (err == error.OutOfMemory) .{ .rejected = .{ .operation_failed = error.OperationExecutionFailed } } else .{ .rejected = .authority };
        // No repair-state mutation occurs between preparation and this allocation-
        // free commit; the envelope and accepted native progress advance together.
        if (repair_pending) |prepared| self.repair_retry.commit(prepared) catch unreachable;
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
        // Workflow edges may inspect an operation outcome only after its delta
        // and runner transitions have been accepted and applied.
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
        .repair_role = step.repair_role,
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
        contract.repair_role == step.repair_role and
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
    return step.retry_authority.?.limit.within(contract.retry_limit.?.maximum) and
        step.retry_authority.?.scope == contract.retry_limit.?.scope;
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
