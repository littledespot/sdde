const std = @import("std");
const action = @import("../actions/model/prepare_provider_operation_authorization.zig");
const table_module = @import("provider_authorization_lease_table.zig");
const pipeline = @import("../domain/pipeline.zig");
const operation = @import("../domain/llm_provider_operation.zig");
const preparation = @import("../ports/provider_operation_authorization.zig");
const lease = @import("../ports/provider_authorization_lease.zig");
const binding = @import("../domain/llm_provider_binding.zig");
const envelope_module = @import("pipeline_envelope.zig");
const values = @import("pipeline_values.zig");
const data = @import("../domain/pipeline_data.zig");

// Pipeline evidence references the immutable registry; it never copies config.
const binding_schema = values.schema(.validated_provider_model_binding, binding.ProviderModelBindingId, 1, 1024);
const input_contract: pipeline.NodeContract = .{
    .id = "provider-authorization-input@1",
    .kind = .action,
    .requires = &.{},
    .produces = &.{.validated_provider_model_binding},
    .side_effect = .none,
};

pub const Outcome = union(enum) {
    prepared: *const operation.ValidatedProviderAuthorizationLeaseRef,
    failed: operation.ProviderFailure,
    cancelled,
};

/// Runs one preparation child. The lifecycle runner owns the private table;
/// this binding publishes only its opaque reference, never its capability.
pub const Runner = struct {
    table: *table_module.Table,
    prepare_action: action.Action,
    clock: lease.Clock,
    runtime: pipeline.NodeRuntime = .{},

    pub fn prepare(self: *Runner, facts: preparation.Facts) std.mem.Allocator.Error!Outcome {
        self.check(facts.deadline_monotonic_ms) catch |err| return rejected(facts.operation_id, err);
        var envelope = envelope_module.PipelineEnvelope.init(&.{ binding_schema, preparation.value_schema });
        defer envelope.deinit();
        var input_delta: pipeline.NodeDelta = .{};
        defer envelope.discard(&input_delta);
        input_delta.data_writes[@intFromEnum(pipeline.DataKey.validated_provider_model_binding)] = values.create(self.table.allocator, binding_schema, binding.ProviderModelBindingId, facts.provider_binding.bindingId()) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return rejected(facts.operation_id, error.AuthorizationDenied),
        };
        envelope.apply(input_contract, &input_delta, .ok) catch return rejected(facts.operation_id, error.AuthorizationDenied);
        const input_view = envelope.view(action.Action.contract) catch return rejected(facts.operation_id, error.AuthorizationDenied);
        const bound_id = values.read(&input_view, binding_schema, binding.ProviderModelBindingId) catch return rejected(facts.operation_id, error.AuthorizationDenied);
        if (!bound_id.eql(facts.request.binding_id)) return rejected(facts.operation_id, error.AuthorizationDenied);
        const slot = self.table.allocate(facts) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => |failure| return rejected(facts.operation_id, failure),
        };
        var published = false;
        defer if (!published) self.table.cancel(slot);
        const outcome = try self.prepare_action.execute(facts, slot, self.runtime);
        var delta = switch (outcome) {
            .failed => |failure| return .{ .failed = failure },
            .cancelled => return .cancelled,
            .prepared => |delta| delta,
        };
        defer envelope.discard(&delta);
        self.check(facts.deadline_monotonic_ms) catch |err| return rejected(facts.operation_id, err);
        envelope.apply(action.Action.contract, &delta, .ok) catch return rejected(facts.operation_id, error.AuthorizationDenied);
        const view: data.View = .{ .slots = envelope.slots };
        const value = values.read(&view, preparation.value_schema, operation.ValidatedProviderAuthorizationLeaseRef) catch return rejected(facts.operation_id, error.AuthorizationDenied);
        const reference = self.table.canonicalReference(value.*) catch |err| return rejected(facts.operation_id, err);
        published = true;
        return .{ .prepared = reference };
    }

    fn check(self: *Runner, deadline: u64) lease.Error!void {
        switch (self.runtime.status()) {
            .cancelled => return error.Cancelled,
            .deadline_exhausted => return error.AuthorizationExpired,
            .active => {},
        }
        if (deadline == 0 or try self.clock.now() >= deadline) return error.AuthorizationExpired;
    }
};

fn rejected(id: operation.ProviderOperationId, err: lease.Error) Outcome {
    if (err == error.Cancelled) return .cancelled;
    return .{ .failed = .{
        .operation_id = id,
        .cause = if (err == error.AuthorizationExpired) .timeout else .authorization_denied,
        .retry_class = .never,
        .delivery = .not_sent,
    } };
}
