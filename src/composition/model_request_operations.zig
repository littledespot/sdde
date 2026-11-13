const std = @import("std");
const requests = @import("../application/model_request_workflow.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const binding = @import("../application/workflow_operation_binding.zig");
const kernel = @import("../domain/model_request_kernel.zig");
const attempts = @import("../application/model_attempt_workflow.zig");
const provider_operations = @import("../application/provider_operation_workflow.zig");
const accounting = @import("../application/workflow_model_accounting.zig");
const authorization = @import("../application/provider_authorization_workflow.zig");
const lifecycle = @import("../application/model_request_lifecycle_workflow.zig");
const provider_lifecycle = @import("../application/provider_operation_lifecycle_workflow.zig");
const invocation = @import("../application/model_invocation_workflow.zig");
const observation = @import("../application/provider_observation_workflow.zig");
const envelope = @import("../application/model_envelope_workflow.zig");
const payload = @import("../application/model_payload_schema_workflow.zig");
const completion = @import("../application/provider_operation_completion_workflow.zig");
const request_completion = @import("../application/model_request_completion_workflow.zig");
const termination = @import("../application/provider_operation_termination_workflow.zig");
const request_termination = @import("../application/model_request_termination_workflow.zig");

const transport = @import("../application/model_transport_workflow.zig");
const protocol = @import("../application/model_protocol_retry_workflow.zig");
const composition = @import("../application/json_composition_workflow.zig");
/// The operations a workflow selects: the request ledger's initialization, the four JSON-composition
/// operations, the two releases of a `request-model` step's request (they retire only what the kernel
/// leaves current) and the `request-model` kernel entry (ADR 0030). Every request stage is a native
/// binding the kernel entry holds, never an operation a workflow can select.
pub const count = 8;
pub const stage_count = std.enums.values(kernel.Stage).len;

/// The kernel operation's contract: its parameters are the preparation stage's and the accounting
/// stage's `retry-limit`; its data effects are fixed by the domain (`model_request_kernel.zig`).
pub const request_model_contract: @import("../domain/workflow_operation.zig").Contract = .{
    .id = kernel.operation_id,
    .kind = .step,
    .parameters = &(requests.preparation_parameters ++ [_]@import("../domain/workflow_operation.zig").ParameterDescriptor{attempts.Advance.contract.parameters[0]}),
    .requires = &kernel.requires,
    .optional = &kernel.optional,
    .produces = &kernel.produces,
    .replaces = &kernel.replaces,
    .outcomes = &kernel.outcomes,
    .side_effect = .model_call,
    .retry_limit = .{ .maximum = std.math.maxInt(u32), .scope = .model_request },
};

/// Every stage context of the kernel, in stage order; the kernel binding's capabilities derive from
/// these types.
const stage_types = [_]type{
    requests.Prepare,      attempts.Advance,              provider_operations.Assign, authorization.Prepare, protocol.Check,
    lifecycle.Advance,     provider_lifecycle.Advance,    invocation.Invoke,          observation.Validate,  completion.Complete,
    payload.Admit,         protocol.Runaway,              protocol.Build,             protocol.Resend,       request_completion.Complete,
    termination.Terminate, request_termination.Terminate,
};
comptime {
    if (stage_types.len != stage_count) @compileError("every request stage has exactly one stage context");
}
pub const schemas = requests.schemas ++ composition.schemas ++ [_]@import("../domain/pipeline_data.zig").Schema{ accounting.schema, accounting.operation_schema, accounting.invoked_schema, accounting.terminal_schema, authorization.schema, invocation.schema, observation.schema, envelope.schema, payload.schema };

/// Native bindings only; sequencing belongs to the selected YAML graph, and a request's stages to
/// the `request-model` kernel.
pub const Assembly = struct {
    initialize: requests.Initialize,
    prepare: requests.Prepare,
    advance_attempt: attempts.Advance,
    assign_operation: provider_operations.Assign,
    prepare_authorization: authorization.Prepare,
    advance_request: lifecycle.Advance,
    advance_operation: provider_lifecycle.Advance,
    invoke_model: invocation.Invoke,
    validate_observation: observation.Validate,
    admit_response: payload.Admit,
    complete_operation: completion.Complete,
    complete_request: request_completion.Complete,
    terminate_operation: termination.Terminate,
    terminate_request: request_termination.Terminate,
    protocol_retry: protocol.Build,
    check_phase: protocol.Check,
    check_runaway: protocol.Runaway,
    runaway_resend: protocol.Resend,
    release_request: transport.Retire(.released_request),
    release_transport: transport.Retire(.released_request_and_input),
    initialize_composition: composition.Initialize,
    retain_part: composition.Retain,
    assemble_json: composition.Assemble,
    validate_assembled_json: composition.Validate,
    request_stages: [stage_count]operations.StageEntry,
    entries: [count]operations.Entry,

    pub fn init(self: *Assembly, allocator: std.mem.Allocator) void {
        self.* = .{
            .initialize = .{ .allocator = allocator },
            .prepare = .{ .allocator = allocator },
            .advance_attempt = .{ .allocator = allocator },
            .assign_operation = .{},
            .prepare_authorization = .{ .allocator = allocator },
            .advance_request = .{ .allocator = allocator },
            .advance_operation = .{},
            .invoke_model = .{ .allocator = allocator },
            .validate_observation = .{ .allocator = allocator },
            .admit_response = .{ .allocator = allocator },
            .complete_operation = .{},
            .complete_request = .{ .allocator = allocator },
            .terminate_operation = .{},
            .terminate_request = .{ .allocator = allocator },
            .protocol_retry = .{ .allocator = allocator },
            .check_phase = .{},
            .check_runaway = .{},
            .runaway_resend = .{ .allocator = allocator },
            .release_request = .{},
            .release_transport = .{},
            .initialize_composition = .{ .allocator = allocator },
            .retain_part = .{ .allocator = allocator },
            .assemble_json = .{ .allocator = allocator },
            .validate_assembled_json = .{ .allocator = allocator },
            .request_stages = undefined,
            .entries = undefined,
        };
        self.request_stages = .{
            stage(.prepare_request, requests.Prepare, &self.prepare),
            stage(.advance_attempt, attempts.Advance, &self.advance_attempt),
            stage(.assign_operation, provider_operations.Assign, &self.assign_operation),
            stage(.prepare_authorization, authorization.Prepare, &self.prepare_authorization),
            stage(.check_phase, protocol.Check, &self.check_phase),
            stage(.advance_request, lifecycle.Advance, &self.advance_request),
            stage(.advance_operation, provider_lifecycle.Advance, &self.advance_operation),
            stage(.invoke_model, invocation.Invoke, &self.invoke_model),
            stage(.validate_observation, observation.Validate, &self.validate_observation),
            stage(.complete_operation, completion.Complete, &self.complete_operation),
            stage(.admit_response, payload.Admit, &self.admit_response),
            stage(.check_runaway, protocol.Runaway, &self.check_runaway),
            stage(.build_protocol_retry, protocol.Build, &self.protocol_retry),
            stage(.build_runaway_resend, protocol.Resend, &self.runaway_resend),
            stage(.close_request, request_completion.Complete, &self.complete_request),
            stage(.terminate_operation, termination.Terminate, &self.terminate_operation),
            stage(.terminate_request, request_termination.Terminate, &self.terminate_request),
        };
        self.entries = .{
            entry(requests.Initialize, &self.initialize),
            entry(transport.Retire(.released_request), &self.release_request),
            entry(transport.Retire(.released_request_and_input), &self.release_transport),
            entry(composition.Initialize, &self.initialize_composition),
            entry(composition.Retain, &self.retain_part),
            entry(composition.Assemble, &self.assemble_json),
            entry(composition.Validate, &self.validate_assembled_json),
            .{ .contract = request_model_contract, .binding = binding.bindRequestKernel(&stage_types), .request_stages = &self.request_stages },
        };
    }
};

fn stage(comptime tag: kernel.Stage, comptime T: type, context: *T) operations.StageEntry {
    return .{ .stage = tag, .contract = T.contract, .binding = binding.bind(T, context, T.invoke) };
}

fn entry(comptime T: type, context: *T) operations.Entry {
    return .{ .contract = T.contract, .binding = binding.bind(T, context, T.invoke) };
}
