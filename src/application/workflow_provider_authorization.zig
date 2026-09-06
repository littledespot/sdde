const std = @import("std");
const table_module = @import("provider_authorization_lease_table.zig");
const preparation = @import("../ports/provider_operation_authorization.zig");
const lease = @import("../ports/provider_authorization_lease.zig");
const result = @import("../domain/provider_authorization_result.zig");
const handoff = @import("../domain/model_request_handoff.zig");
const provider = @import("../domain/llm_provider_operation.zig");
const workflow = @import("../domain/workflow.zig");
const pipeline = @import("../domain/pipeline.zig");

/// One pending preparation binding. No action dispatch or provider access.
pub const Binding = struct {
    table: *table_module.Table,
    facts: preparation.Facts,
    slot: preparation.AllocatedSlot,
    clock: lease.Clock,
    runtime: pipeline.NodeRuntime,

    pub fn allocate(table: *table_module.Table, request: *const handoff.Request, id: provider.ProviderOperationId, timeout_ms: u64, clock: lease.Clock, runtime: pipeline.NodeRuntime) preparation.Error!Binding {
        const now = try currentTime(clock, runtime);
        const deadline = std.math.add(u64, now, timeout_ms) catch return error.AuthorizationExpired;
        if (timeout_ms == 0) return error.AuthorizationExpired;
        const facts: preparation.Facts = .{ .provider_binding = request.binding(), .request = request.prepared() orelse return error.AuthorizationDenied, .operation_id = id, .deadline_monotonic_ms = deadline };
        return .{ .table = table, .facts = facts, .slot = try table.allocate(facts), .clock = clock, .runtime = runtime };
    }

    pub fn cancel(self: Binding) void {
        self.table.cancel(self.slot);
    }

    pub fn validate(self: Binding, value: *const result.Result, outcome: workflow.OutcomeTag) lease.Error!bool {
        try checkDeadline(self.clock, self.runtime, self.facts.deadline_monotonic_ms);
        switch (value.outcome().*) {
            .prepared => |reference| {
                if (outcome != .ok) return error.AuthorizationDenied;
                try self.table.validatePublication(self.slot, reference);
                _ = try self.table.validateReference(reference, self.facts.provider_binding, self.facts.request, self.facts.operation_id, currentTime(self.clock, self.runtime));
                return true;
            },
            .failed => |failure| {
                if (outcome != .failed) return error.AuthorizationDenied;
                try validateFailure(failure, self.facts.operation_id);
                return false;
            },
            .cancelled => |id| {
                if (outcome != .cancelled or !id.eql(self.facts.operation_id)) return error.AuthorizationDenied;
                return false;
            },
        }
    }
};

pub fn validateConsumer(table: *table_module.Table, value: *const result.Result, request: *const handoff.Request, id: provider.ProviderOperationId, clock: lease.Clock, runtime: pipeline.NodeRuntime) lease.Error!?u64 {
    switch (value.outcome().*) {
        .prepared => |reference| return try table.validateReference(reference, request.binding(), request.prepared().?, id, currentTime(clock, runtime)),
        .failed => |failure| try validateFailure(failure, id),
        .cancelled => |operation_id| if (!operation_id.eql(id)) return error.AuthorizationDenied,
    }
    return null;
}

pub fn requirePrepared(value: *const result.Result) lease.Error!void {
    return switch (value.outcome().*) {
        .prepared => {},
        .failed => error.AuthorizationDenied,
        .cancelled => error.Cancelled,
    };
}

fn validateFailure(failure: provider.ProviderFailure, id: provider.ProviderOperationId) lease.Error!void {
    if (!failure.operation_id.eql(id) or failure.delivery != .not_sent or failure.retry_class != .never) return error.AuthorizationDenied;
}

fn currentTime(clock: lease.Clock, runtime: pipeline.NodeRuntime) lease.Error!u64 {
    return switch (runtime.status()) {
        .active => clock.now(),
        .cancelled => error.Cancelled,
        .deadline_exhausted => error.AuthorizationExpired,
    };
}

pub fn checkDeadline(clock: lease.Clock, runtime: pipeline.NodeRuntime, deadline: u64) lease.Error!void {
    if (try currentTime(clock, runtime) >= deadline) return error.AuthorizationExpired;
}
