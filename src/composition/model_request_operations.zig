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

/// The operations a workflow selects, one field each and one registered entry each, in field order: the
/// request ledger's initialization, the two releases of a `request-model` step's request (they retire only
/// what the kernel leaves current) and the four JSON-composition operations. The `request-model` kernel entry
/// follows them (ADR 0030). Every request stage is a native binding the kernel entry holds, never an operation
/// a workflow can select.
pub const Selectable = struct {
    initialize: requests.Initialize,
    release_request: transport.Retire(.released_request),
    release_transport: transport.Retire(.released_request_and_input),
    initialize_composition: composition.Initialize,
    retain_part: composition.Retain,
    assemble_json: composition.Assemble,
    validate_assembled_json: composition.Validate,
};
/// The selectable operations and the kernel entry.
pub const count = std.meta.fields(Selectable).len + 1;
pub const stage_count = std.enums.values(kernel.Stage).len;

/// One context for each stage of the kernel, a field named by its stage (`kernel.Stage`): the stage rows and the
/// kernel binding's capabilities derive from these types in stage order, and a stage without a context or a
/// context without a stage does not compile.
pub const Stages = struct {
    prepare_request: requests.Prepare,
    advance_attempt: attempts.Advance,
    assign_operation: provider_operations.Assign,
    prepare_authorization: authorization.Prepare,
    check_phase: protocol.Check,
    advance_request: lifecycle.Advance,
    advance_operation: provider_lifecycle.Advance,
    invoke_model: invocation.Invoke,
    validate_observation: observation.Validate,
    complete_operation: completion.Complete,
    admit_response: payload.Admit,
    check_runaway: protocol.Runaway,
    build_protocol_retry: protocol.Build,
    build_runaway_resend: protocol.Resend,
    close_request: request_completion.Complete,
    terminate_operation: termination.Terminate,
    terminate_request: request_termination.Terminate,
};
comptime {
    if (std.meta.fields(Stages).len != stage_count) @compileError("every request stage has exactly one stage context");
}
/// Every stage context's type, in stage order; the kernel binding's capabilities derive from these.
const stage_types: [stage_count]type = types: {
    var result: [stage_count]type = undefined;
    for (std.enums.values(kernel.Stage), 0..) |tag, index| result[index] = @FieldType(Stages, @tagName(tag));
    break :types result;
};

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
    .retry_limit = .{ .maximum = kernel.maximum_retry_limit, .scope = .model_request },
};

pub const schemas = requests.schemas ++ composition.schemas ++ [_]@import("../domain/pipeline_data.zig").Schema{ accounting.schema, accounting.operation_schema, accounting.invoked_schema, accounting.terminal_schema, authorization.schema, invocation.schema, observation.schema, envelope.schema, payload.schema };

/// Native bindings only; sequencing belongs to the selected YAML graph, and a request's stages to
/// the `request-model` kernel.
pub const Assembly = struct {
    selectable: Selectable,
    stages: Stages,
    /// One row for each stage, in stage order, bound to its context in `stages`.
    request_stages: [stage_count]operations.StageEntry,
    /// One row for each selectable operation, in field order, bound to its context in `selectable`, then the
    /// kernel entry.
    entries: [count]operations.Entry,

    /// The contexts are written here by hand, which the compiler checks against the fields; the rows derive.
    pub fn init(self: *Assembly, allocator: std.mem.Allocator) void {
        self.* = .{
            .selectable = .{
                .initialize = .{ .allocator = allocator },
                .release_request = .{},
                .release_transport = .{},
                .initialize_composition = .{ .allocator = allocator },
                .retain_part = .{ .allocator = allocator },
                .assemble_json = .{ .allocator = allocator },
                .validate_assembled_json = .{ .allocator = allocator },
            },
            .stages = .{
                .prepare_request = .{ .allocator = allocator },
                .advance_attempt = .{ .allocator = allocator },
                .assign_operation = .{},
                .prepare_authorization = .{ .allocator = allocator },
                .check_phase = .{},
                .advance_request = .{ .allocator = allocator },
                .advance_operation = .{},
                .invoke_model = .{ .allocator = allocator },
                .validate_observation = .{ .allocator = allocator },
                .complete_operation = .{},
                .admit_response = .{ .allocator = allocator },
                .check_runaway = .{},
                .build_protocol_retry = .{ .allocator = allocator },
                .build_runaway_resend = .{ .allocator = allocator },
                .close_request = .{ .allocator = allocator },
                .terminate_operation = .{},
                .terminate_request = .{ .allocator = allocator },
            },
            .request_stages = undefined,
            .entries = undefined,
        };
        inline for (std.enums.values(kernel.Stage), 0..) |tag, index| {
            self.request_stages[index] = stage(tag, @FieldType(Stages, @tagName(tag)), &@field(self.stages, @tagName(tag)));
        }
        inline for (std.meta.fields(Selectable), 0..) |field, index| {
            self.entries[index] = entry(field.type, &@field(self.selectable, field.name));
        }
        self.entries[count - 1] = .{ .contract = request_model_contract, .binding = binding.bindRequestKernel(&stage_types), .request_stages = &self.request_stages };
    }
};

fn stage(comptime tag: kernel.Stage, comptime T: type, context: *T) operations.StageEntry {
    return .{ .stage = tag, .contract = T.contract, .binding = binding.bind(T, context, T.invoke) };
}

fn entry(comptime T: type, context: *T) operations.Entry {
    return .{ .contract = T.contract, .binding = binding.bind(T, context, T.invoke) };
}
