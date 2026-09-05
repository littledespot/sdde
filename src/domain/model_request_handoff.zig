const std = @import("std");
const identity = @import("model_request_identity.zig");
const binding_module = @import("llm_provider_binding.zig");
const compilation = @import("workflow_compilation.zig");
const preparation = @import("model_request_preparation.zig");
const provider = @import("llm_provider_operation.zig");

/// One immutable association, carried by typed pipeline keys. Canonical IDs are
/// retained through their ledger owner, never cloned into a second authority.
pub const Request = opaque {
    pub fn id(self: *const Request) *const identity.ModelRequestId {
        return storage(self).id;
    }

    pub fn binding(self: *const Request) *const binding_module.ValidatedProviderModelBinding {
        return &storage(self).binding;
    }

    pub fn ledger(self: *const Request) *const identity.ModelRequestIdentityLedger {
        return identity.ledger(storage(self).ledger_owner);
    }

    pub fn prompt(self: *const Request) []const u8 {
        return storage(self).prompt.content.prompt;
    }

    pub fn input(self: *const Request) ?[]const u8 {
        const resource = storage(self).input orelse return null;
        return resource.content.data;
    }

    pub fn source(self: *const Request, input_id: provider.ModelVisibleInputId) preparation.ValidationError!preparation.Source {
        const value = storage(self);
        const evidence = switch (value.phase) {
            .validated => |evidence| evidence,
            else => return error.ModelRequestAssociationInvalid,
        };
        return .{
            .request_binding = evidence,
            .provider_binding = &value.binding,
            .request_schema_id = .{ .bytes = "model-request/v1" },
            .model_visible_input_id = input_id,
            .result_resource = &value.result,
        };
    }

    pub fn prepared(self: *const Request) ?*const provider.IdentifiedProviderNeutralModelRequest {
        return switch (storage(self).phase) {
            .prepared => |owned| owned.request,
            else => null,
        };
    }
};

const Storage = struct {
    allocator: std.mem.Allocator,
    ledger_owner: *identity.Owner,
    id: *const identity.ModelRequestId,
    binding: binding_module.ValidatedProviderModelBinding,
    prompt: compilation.CompiledResource,
    result: compilation.CompiledResource,
    input: ?compilation.CompiledResource,
    phase: union(enum) {
        assigned,
        validated: *const identity.ModelRequestBindingEvidence,
        prepared: preparation.Owned,
    },
};

pub const Error = identity.Error || preparation.ValidationError;

pub fn assign(allocator: std.mem.Allocator, ledger_owner: *identity.Owner, id: *const identity.ModelRequestId, selected: binding_module.ValidatedProviderModelBinding, prompt: compilation.CompiledResource, result: compilation.CompiledResource, input: ?compilation.CompiledResource) Error!*Request {
    if (prompt.content != .prompt or result.content != .result_schema or
        (input != null and input.?.content != .data) or
        !identity.ledger(ledger_owner).containsRequest(id) or
        !id.model_operation_id.eql(selected.operation_id)) return error.ModelRequestAssociationInvalid;
    return create(.{
        .allocator = allocator,
        .ledger_owner = ledger_owner,
        .id = id,
        .binding = selected,
        .prompt = prompt,
        .result = result,
        .input = input,
        .phase = .assigned,
    });
}

pub fn validated(current: *const Request, evidence: *const identity.ModelRequestBindingEvidence) Error!*Request {
    var next = storage(current).*;
    if (next.phase != .assigned or evidence.modelRequestId() != next.id) return error.ModelRequestAssociationInvalid;
    next.phase = .{ .validated = evidence };
    return create(next);
}

/// Transfers the prepared allocation only on success. Registry and resource
/// references borrow the immutable selected execution, which outlives its data.
pub fn prepared(current: *const Request, owned: preparation.Owned) Error!*Request {
    var next = storage(current).*;
    try preparation.validateRequest(try current.source(owned.request.model_visible_input_id), owned.request);
    next.phase = .{ .prepared = owned };
    return create(next);
}

pub fn destroy(request: *Request) void {
    const value: *Storage = @ptrCast(@alignCast(request));
    if (value.phase == .prepared) value.phase.prepared.deinit();
    identity.deinitOwner(value.ledger_owner);
    value.allocator.destroy(value);
}

pub fn view(request: *const Request) *const Request {
    return request;
}

fn create(value: Storage) Error!*Request {
    const result = try value.allocator.create(Storage);
    errdefer value.allocator.destroy(result);
    try identity.retainOwner(value.ledger_owner);
    result.* = value;
    return @ptrCast(result);
}

fn storage(request: *const Request) *const Storage {
    return @ptrCast(@alignCast(request));
}
