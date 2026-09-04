const std = @import("std");
const operation = @import("../domain/llm_provider_operation.zig");
const lifecycle = @import("../domain/provider_operation_lifecycle.zig");
const binding = @import("../domain/llm_provider_binding.zig");
const registry = @import("../domain/llm_provider_registry.zig");
const preparation = @import("../ports/provider_operation_authorization.zig");
const lease = @import("../ports/provider_authorization_lease.zig");
const pipeline = @import("../domain/pipeline.zig");
const references = @import("../domain/execution_reference.zig");
const data = @import("../domain/pipeline_data.zig");
const values = @import("pipeline_values.zig");

const State = enum { allocated, prepared, published, consumed, finalized };
const Entry = struct {
    next: ?*Entry,
    reference: operation.ValidatedProviderAuthorizationLeaseRef,
    operation_id: operation.ProviderOperationId,
    registry_entry: *const registry.Entry,
    binding_id: binding.ProviderModelBindingId,
    input_id: operation.ModelVisibleInputId,
    deadline: u64,
    state: State = .allocated,
    capability: ?lease.Capability = null,
};

/// One execution's sole owner of unconsumed capabilities and lease identities.
/// Ledger/binding/input authorities outlive this table. Entries are tombstoned
/// until deinit, so an old reference can never become a new lease in this run.
pub const Table = struct {
    allocator: std.mem.Allocator,
    operations: *const lifecycle.Ledger,
    first: ?*Entry = null,

    pub fn init(allocator: std.mem.Allocator, operations: *const lifecycle.Ledger) Table {
        return .{ .allocator = allocator, .operations = operations };
    }

    pub fn deinit(self: *Table) void {
        var next = self.first;
        while (next) |entry| {
            next = entry.next;
            finalize(entry);
            entry.reference.identity.release();
            self.allocator.destroy(entry);
        }
        self.first = null;
    }

    /// Called by the lifecycle runner after publishing each immutable successor.
    pub fn update(self: *Table, current: *const lifecycle.Ledger) void {
        self.operations = current;
        var next = self.first;
        while (next) |entry| : (next = entry.next) {
            const record = current.record(entry.operation_id) orelse {
                finalize(entry);
                continue;
            };
            if (record.state == .terminal) finalize(entry);
        }
    }

    pub fn allocate(self: *Table, facts: preparation.Facts) preparation.Error!preparation.AllocatedSlot {
        try self.validateAssigned(facts);
        var next = self.first;
        while (next) |entry| : (next = entry.next) {
            if (entry.operation_id.eql(facts.operation_id)) return error.AuthorizationDenied;
        }
        const entry = try self.allocator.create(Entry);
        errdefer self.allocator.destroy(entry);
        const identity = try references.create(self.allocator);
        const record = self.operations.record(facts.operation_id).?;
        entry.* = .{
            .next = self.first,
            .reference = .{ .identity = identity },
            .operation_id = facts.operation_id,
            .registry_entry = facts.provider_binding.registry_entry,
            .binding_id = record.binding_id,
            .input_id = record.model_visible_input_id,
            .deadline = facts.deadline_monotonic_ms,
        };
        self.first = entry;
        return .{ .deposit = .{ .context = @ptrCast(self), .identity = @ptrCast(entry), .deposit_fn = deposit }, .publish_fn = publishValue };
    }

    fn publish(self: *Table, slot: preparation.Slot) lease.Error!*const operation.ValidatedProviderAuthorizationLeaseRef {
        const entry = self.findSlot(slot) orelse return error.AuthorizationDenied;
        if (entry.state != .prepared or entry.capability == null) return error.AuthorizationDenied;
        const record = self.operations.record(entry.operation_id) orelse return error.AuthorizationDenied;
        if (record.state != .assigned) return error.AuthorizationDenied;
        entry.state = .published;
        return &entry.reference;
    }

    pub fn canonicalReference(self: *Table, reference: operation.ValidatedProviderAuthorizationLeaseRef) lease.Error!*const operation.ValidatedProviderAuthorizationLeaseRef {
        var next = self.first;
        while (next) |entry| : (next = entry.next) {
            if (entry.reference.identity.eql(reference.identity) and entry.state == .published) return &entry.reference;
        }
        return error.AuthorizationDenied;
    }

    pub fn cancel(self: *Table, slot: preparation.AllocatedSlot) void {
        if (self.findSlot(slot.deposit)) |entry| finalize(entry);
    }

    pub fn port(self: *Table, clock: lease.Clock, runtime: pipeline.NodeRuntime) lease.Port {
        return .{ .context = @ptrCast(self), .clock = clock, .runtime = runtime, .consume_fn = consume };
    }

    fn validateAssigned(self: *const Table, facts: preparation.Facts) lease.Error!void {
        facts.request.validate() catch return error.AuthorizationDenied;
        if (facts.deadline_monotonic_ms == 0 or
            facts.operation_id.model_request_id != facts.request.model_request_id or
            !facts.request.binding_id.eql(facts.provider_binding.bindingId())) return error.AuthorizationDenied;
        const record = self.operations.record(facts.operation_id) orelse return error.AuthorizationDenied;
        if (record.state != .assigned or !record.binding_id.eql(facts.request.binding_id) or
            !record.model_visible_input_id.eql(facts.request.model_visible_input_id)) return error.AuthorizationDenied;
    }

    fn findSlot(self: *Table, slot: preparation.Slot) ?*Entry {
        if (slot.context != @as(*preparation.Context, @ptrCast(self))) return null;
        var next = self.first;
        while (next) |entry| : (next = entry.next) {
            if (slot.identity == @as(*const preparation.SlotIdentity, @ptrCast(entry))) return entry;
        }
        return null;
    }

    fn deposit(context: *preparation.Context, id: *const preparation.SlotIdentity, facts: preparation.Facts, capability: *lease.Capability) lease.Error!void {
        const self: *Table = @ptrCast(@alignCast(context));
        const entry = self.findSlot(.{ .context = context, .identity = id, .deposit_fn = deposit }) orelse return error.AuthorizationDenied;
        if (entry.state != .allocated or capability.payload == null) return error.AuthorizationDenied;
        try self.validateAssigned(facts);
        if (!entry.operation_id.eql(facts.operation_id) or !matches(entry, facts.provider_binding, facts.request, facts.deadline_monotonic_ms)) return error.AuthorizationDenied;
        entry.capability = try capability.take();
        entry.state = .prepared;
    }

    fn publishValue(context: *preparation.Context, id: *const preparation.SlotIdentity) preparation.Error!*data.Value {
        const self: *Table = @ptrCast(@alignCast(context));
        const reference = try self.publish(.{ .context = context, .identity = id, .deposit_fn = deposit });
        return values.create(self.allocator, preparation.value_schema, operation.ValidatedProviderAuthorizationLeaseRef, reference.*) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.AuthorizationDenied,
        };
    }

    fn consume(
        context: *lease.Context,
        reference: *const operation.ValidatedProviderAuthorizationLeaseRef,
        provider_binding: *const binding.ValidatedProviderModelBinding,
        request: *const operation.IdentifiedProviderNeutralModelRequest,
        invoked: *const operation.InvokedProviderOperation,
        now: lease.Error!u64,
    ) lease.Error!lease.Capability {
        const self: *Table = @ptrCast(@alignCast(context));
        var next = self.first;
        while (next) |entry| : (next = entry.next) {
            if (!reference.identity.eql(entry.reference.identity)) continue;
            if (entry.state != .published) return error.AuthorizationDenied;
            errdefer finalize(entry);
            const current_time = try now;
            if (current_time >= entry.deadline) return error.AuthorizationExpired;
            const current = self.operations.requireInvoked(entry.operation_id) catch return error.AuthorizationDenied;
            if (current != invoked or !entry.operation_id.eql(invoked.id) or
                request.model_request_id != invoked.id.model_request_id or
                !matches(entry, provider_binding, request, invoked.deadline_monotonic_ms)) return error.AuthorizationDenied;
            var capability = entry.capability orelse return error.AuthorizationDenied;
            entry.capability = null;
            entry.state = .consumed;
            return capability.take();
        }
        return error.AuthorizationDenied;
    }
};

fn matches(entry: *const Entry, provider_binding: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, deadline: u64) bool {
    return entry.registry_entry == provider_binding.registry_entry and
        entry.binding_id.eql(provider_binding.bindingId()) and entry.binding_id.eql(request.binding_id) and
        entry.input_id.eql(request.model_visible_input_id) and entry.deadline == deadline;
}

fn finalize(entry: *Entry) void {
    if (entry.capability) |*capability| capability.deinit();
    entry.capability = null;
    entry.state = .finalized;
}
