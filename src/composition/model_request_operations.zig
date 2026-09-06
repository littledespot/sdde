const std = @import("std");
const requests = @import("../application/model_request_workflow.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const binding = @import("../application/workflow_operation_binding.zig");
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
const count_observation = @import("../application/model_token_count_observation_workflow.zig");

const transport = @import("../application/model_transport_workflow.zig");
pub const count = 24;
pub const schemas = requests.schemas ++ [_]@import("../domain/pipeline_data.zig").Schema{ accounting.schema, accounting.operation_schema, accounting.invoked_schema, accounting.terminal_schema, authorization.schema, invocation.schema, observation.schema, envelope.schema, payload.schema, invocation.count_schema, count_observation.schema };

/// Native bindings only; sequencing belongs to the selected YAML graph.
pub const Assembly = struct {
    initialize: requests.Initialize,
    assign: requests.Assign,
    validate: requests.Validate,
    build: requests.Build,
    advance_attempt: attempts.Advance,
    assign_operation: provider_operations.Assign,
    prepare_authorization: authorization.Prepare,
    advance_request: lifecycle.Advance,
    advance_operation: provider_lifecycle.Advance,
    invoke_model: invocation.Invoke,
    validate_observation: observation.Validate,
    decode_envelope: envelope.Decode,
    validate_payload: payload.Validate,
    complete_operation: completion.Complete,
    complete_request: request_completion.Complete,
    terminate_operation: termination.Terminate,
    terminate_request: request_termination.Terminate,
    count_model_input: invocation.Count,
    validate_count: count_observation.Validate,
    complete_count_operation: completion.CompleteCount,
    complete_count_request: request_completion.CompleteCount,
    retire_request: transport.Retire(.request),
    retire_attempt: transport.Retire(.rejected_attempt),
    retire_input: transport.Retire(.input),
    entries: [count]operations.Entry,

    pub fn init(self: *Assembly, allocator: std.mem.Allocator) void {
        self.* = .{
            .initialize = .{ .allocator = allocator },
            .assign = .{ .allocator = allocator },
            .validate = .{ .allocator = allocator },
            .build = .{ .allocator = allocator },
            .advance_attempt = .{},
            .assign_operation = .{},
            .prepare_authorization = .{ .allocator = allocator },
            .advance_request = .{ .allocator = allocator },
            .advance_operation = .{},
            .invoke_model = .{ .allocator = allocator },
            .validate_observation = .{ .allocator = allocator },
            .decode_envelope = .{ .allocator = allocator },
            .validate_payload = .{ .allocator = allocator },
            .complete_operation = .{},
            .complete_request = .{ .allocator = allocator },
            .terminate_operation = .{},
            .terminate_request = .{ .allocator = allocator },
            .count_model_input = .{ .allocator = allocator },
            .validate_count = .{ .allocator = allocator },
            .complete_count_operation = .{},
            .complete_count_request = .{ .allocator = allocator },
            .retire_request = .{},
            .retire_attempt = .{},
            .retire_input = .{},
            .entries = undefined,
        };
        self.entries = .{
            entry(requests.Initialize, &self.initialize),
            entry(requests.Assign, &self.assign),
            entry(requests.Validate, &self.validate),
            entry(requests.Build, &self.build),
            entry(attempts.Advance, &self.advance_attempt),
            entry(provider_operations.Assign, &self.assign_operation),
            entry(authorization.Prepare, &self.prepare_authorization),
            entry(lifecycle.Advance, &self.advance_request),
            entry(provider_lifecycle.Advance, &self.advance_operation),
            entry(invocation.Invoke, &self.invoke_model),
            entry(observation.Validate, &self.validate_observation),
            entry(envelope.Decode, &self.decode_envelope),
            entry(payload.Validate, &self.validate_payload),
            entry(completion.Complete, &self.complete_operation),
            entry(request_completion.Complete, &self.complete_request),
            entry(termination.Terminate, &self.terminate_operation),
            entry(request_termination.Terminate, &self.terminate_request),
            entry(invocation.Count, &self.count_model_input),
            entry(count_observation.Validate, &self.validate_count),
            entry(completion.CompleteCount, &self.complete_count_operation),
            entry(request_completion.CompleteCount, &self.complete_count_request),
            entry(transport.Retire(.request), &self.retire_request),
            entry(transport.Retire(.rejected_attempt), &self.retire_attempt),
            entry(transport.Retire(.input), &self.retire_input),
        };
    }
};

fn entry(comptime T: type, context: *T) operations.Entry {
    return .{ .contract = T.contract, .binding = binding.bind(T, context, T.invoke) };
}
