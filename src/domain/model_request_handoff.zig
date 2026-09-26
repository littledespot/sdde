const std = @import("std");
const identity = @import("model_request_identity.zig");
const binding_module = @import("llm_provider_binding.zig");
const compilation = @import("workflow_compilation.zig");
const preparation = @import("model_request_preparation.zig");
const provider = @import("llm_provider_operation.zig");
const packets = @import("model_input_packet.zig");
const composition = @import("json_composition_runtime.zig");
const retry = @import("model_protocol_retry.zig");
pub const Input = union(enum) { resource: compilation.CompiledResource, packet: *const packets.Packet };
pub const ResultSelection = enum { resource, input };

/// One immutable association, carried by typed pipeline keys. Canonical IDs are
/// retained through their ledger owner, never cloned into a second authority.
pub const Request = opaque {
    /// Authored resource aliases retained by this exact request selection.
    pub fn sourceResources(self: *const Request) SourceResources {
        const value = storage(self);
        return .{
            .prompt = value.prompt.id,
            .protocol_prompt = if (value.protocol_prompt) |resource| resource.id else null,
            .result = value.result.id,
            .input = if (value.input) |input_value| switch (input_value) {
                .resource => |resource| resource.id,
                .packet => null,
            } else null,
        };
    }

    pub fn selectedResultDefinition(self: *const Request) ?@import("model_result_schema.zig").DefinitionId {
        return storage(self).result_definition;
    }
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

    pub fn protocolPrompt(self: *const Request) ?[]const u8 {
        return if (storage(self).protocol_prompt) |resource| resource.content.prompt else null;
    }

    pub fn input(self: *const Request) ?[]const u8 {
        return switch (storage(self).input orelse return null) {
            .resource => |resource| resource.content.data,
            .packet => |value| value.body(),
        };
    }

    /// Project original immutable inputs for initial calls and corrections.
    pub fn content(self: *const Request, buffer: *[2]provider.ModelVisibleContent) []const provider.ModelVisibleContent {
        buffer[0] = .{ .guidance = self.prompt() };
        if (self.input()) |bytes| {
            buffer[1] = .{ .user = bytes };
            return buffer;
        }
        return buffer[0..1];
    }

    pub fn packet(self: *const Request) ?*const packets.Packet {
        return switch (storage(self).input orelse return null) {
            .resource => null,
            .packet => |value| value,
        };
    }

    pub fn part(self: *const Request) ?composition.Binding {
        return storage(self).composition;
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
            .composition = value.composition,
            .restriction = value.restriction,
        };
    }

    pub fn prepared(self: *const Request) ?*const provider.IdentifiedProviderNeutralModelRequest {
        return switch (storage(self).phase) {
            .prepared => |owned| owned.request,
            else => null,
        };
    }

    /// Only a response to this exact prepared correction can confirm recurrence.
    pub fn protocolRepetition(self: *const Request, rejected: *const @import("provider_invocation_validation.zig").Evidence, diagnostic: retry.Diagnostic) Error!retry.Repetition {
        const request = self.prepared() orelse return error.ModelRequestAssociationInvalid;
        if (rejected.request() != request) return error.ModelRequestAssociationInvalid;
        const previous = storage(self).protocol_rejection orelse return .unconfirmed;
        return if (previous.eql(diagnostic)) .confirmed else .unconfirmed;
    }

    pub fn buildSource(self: *const Request, input_id: *[32]u8) preparation.ValidationError!preparation.Source {
        const bytes = std.fmt.bufPrint(input_id, "input-{d}", .{self.ledger().revision().value}) catch return error.ModelRequestAssociationInvalid;
        return self.source(.{ .bytes = bytes });
    }
};

pub const SourceResources = struct {
    prompt: @import("workflow.zig").WorkflowResourceId,
    protocol_prompt: ?@import("workflow.zig").WorkflowResourceId,
    result: @import("workflow.zig").WorkflowResourceId,
    input: ?@import("workflow.zig").WorkflowResourceId,
};

const Storage = struct {
    allocator: std.mem.Allocator,
    ledger_owner: *identity.Owner,
    id: *const identity.ModelRequestId,
    binding: binding_module.ValidatedProviderModelBinding,
    prompt: compilation.CompiledResource,
    protocol_prompt: ?compilation.CompiledResource,
    result: compilation.CompiledResource,
    result_definition: ?@import("model_result_schema.zig").DefinitionId = null,
    input: ?Input,
    composition: ?composition.Binding = null,
    restriction: ?*@import("model_result_schema.zig").Restricted = null,
    protocol_rejection: ?retry.Diagnostic = null,
    phase: union(enum) {
        assigned,
        validated: *const identity.ModelRequestBindingEvidence,
        prepared: preparation.Owned,
    },
};

pub const Error = packets.Error || preparation.ValidationError;

/// Compiled selections shared by detailed and consolidated preparation.
pub const Selection = struct {
    binding: binding_module.ValidatedProviderModelBinding,
    prompt: compilation.CompiledResource,
    result: compilation.CompiledResource,
    input: ?Input,
    protocol_prompt: ?compilation.CompiledResource,
    result_selection: ResultSelection,
    composition: ?composition.Binding = null,

    pub fn unit(self: Selection) identity.ImmutableUnitOwnerId {
        return if (self.input != null and self.input.? == .packet) self.input.?.packet.unit() else .workflow_step;
    }

    pub fn purpose(self: Selection) identity.RequestPurposeBinding {
        return if (self.input != null and self.input.? == .packet) self.input.?.packet.purpose() else .initial_generation;
    }

    pub fn bind(self: Selection, allocator: std.mem.Allocator, assignment: identity.Assignment) Error!*Request {
        return assign(allocator, assignment.owner, assignment.model_request_id, self.binding, self.prompt, self.result, self.input, self.protocol_prompt, self.result_selection, self.composition);
    }
};

pub const Prepared = struct {
    owner: *identity.Owner,
    assigned: *Request,
    validated: *Request,
    request: *Request,

    pub fn deinit(self: Prepared) void {
        destroy(self.request);
        destroy(self.validated);
        destroy(self.assigned);
        identity.deinitOwner(self.owner);
    }
};

pub fn prepare(allocator: std.mem.Allocator, current: *const identity.ModelRequestIdentityLedger, revision: identity.LedgerRevision, selected: Selection) (Error || identity.Error)!Prepared {
    const assignment = try identity.createSuccessor(current, revision, selected.unit(), selected.binding.operation_id, selected.purpose());
    errdefer identity.deinitOwner(assignment.owner);
    const assigned = try selected.bind(allocator, assignment);
    errdefer destroy(assigned);
    const ledger = identity.ledger(assignment.owner);
    const evidence = try identity.validateBinding(ledger, ledger.revision(), assignment.model_request_id, selected.unit(), selected.binding.operation_id, selected.purpose());
    const checked = try validated(assigned, evidence);
    errdefer destroy(checked);
    var input_id: [32]u8 = undefined;
    var parts: [2]provider.ModelVisibleContent = undefined;
    var owned = try preparation.build(allocator, try checked.buildSource(&input_id), checked.content(&parts));
    errdefer owned.deinit();
    const built = try prepared(checked, owned, null);
    return .{ .owner = assignment.owner, .assigned = assigned, .validated = checked, .request = built };
}

pub fn assign(allocator: std.mem.Allocator, ledger_owner: *identity.Owner, id: *const identity.ModelRequestId, selected: binding_module.ValidatedProviderModelBinding, prompt: compilation.CompiledResource, result: compilation.CompiledResource, input: ?Input, protocol_prompt: ?compilation.CompiledResource, selection: ResultSelection, part_binding: ?composition.Binding) Error!*Request {
    if (protocol_prompt) |resource| if (resource.content != .prompt) return error.ModelRequestAssociationInvalid;
    if (prompt.content != .prompt or result.content != .result_schema or
        (input != null and input.? == .resource and input.?.resource.content != .data) or
        !identity.ledger(ledger_owner).containsRequest(id) or
        !id.model_operation_id.eql(selected.operation_id)) return error.ModelRequestAssociationInvalid;
    if (input) |value| if (value == .packet) {
        const current = identity.ledger(ledger_owner);
        _ = identity.validateBinding(current, current.revision(), id, value.packet.unit(), selected.operation_id, value.packet.purpose()) catch return error.ModelRequestAssociationInvalid;
    };
    var bound_result = result;
    if (part_binding) |part| {
        if (selection != .resource or !part.valid() or result.content.result_schema != part.plan.resultSchema() or
            !std.mem.eql(u8, result.id.bytes, part.plan.resultAlias().bytes) or
            !part.epoch.eql(identity.ledger(ledger_owner).stageRunEpochId())) return error.ModelRequestAssociationInvalid;
        const current = identity.ledger(ledger_owner);
        _ = identity.validateBinding(current, current.revision(), id, part.base.unit(), selected.operation_id, part.base.purpose()) catch return error.ModelRequestAssociationInvalid;
    }
    if (selection == .input) {
        const packet = input orelse return error.ModelRequestAssociationInvalid;
        if (packet != .packet or result.content != .result_schema) return error.ModelRequestAssociationInvalid;
        const definition_id = packet.packet.resultDefinition() orelse return error.ModelRequestAssociationInvalid;
        bound_result.content = .{ .result_schema = result.content.result_schema.select(definition_id) orelse return error.ModelRequestAssociationInvalid };
    }
    const excluded = if (input != null and input.? == .packet) input.?.packet.excludedVariants() else &.{};
    const integer_choices = if (input != null and input.? == .packet) input.?.packet.integerChoices() else &.{};
    const restriction = if (excluded.len != 0 or integer_choices.len != 0)
        @import("model_result_schema.zig").restrict(allocator, if (part_binding) |part| part.schema else bound_result.content.result_schema, excluded, integer_choices) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidModelRequestSource
    else
        null;
    defer if (restriction) |owned| owned.release();
    return create(.{
        .allocator = allocator,
        .ledger_owner = ledger_owner,
        .id = id,
        .binding = selected,
        .prompt = prompt,
        .protocol_prompt = protocol_prompt,
        .result = bound_result,
        .result_definition = if (selection == .input) input.?.packet.resultDefinition() else null,
        .input = input,
        .composition = part_binding,
        .restriction = restriction,
        .phase = .assigned,
    });
}

pub fn validated(current: *const Request, evidence: *const identity.ModelRequestBindingEvidence) Error!*Request {
    var next = storage(current).*;
    if (next.phase != .assigned or evidence.modelRequestId() != next.id) return error.ModelRequestAssociationInvalid;
    next.phase = .{ .validated = evidence };
    return create(next);
}

pub const Correction = struct {
    previous: *const Request,
    rejected: *const @import("provider_invocation_validation.zig").Evidence,
    diagnostic: retry.Diagnostic,
};

/// Transfers the prepared allocation only on success. Registry and resource
/// references borrow the immutable selected execution, which outlives its data.
pub fn prepared(current: *const Request, owned: preparation.Owned, correction: ?Correction) Error!*Request {
    var next = storage(current).*;
    try preparation.validateRequest(try current.source(owned.request.model_visible_input_id), owned.request);
    if (correction) |value| {
        if (current.id() != value.previous.id() or value.rejected.request().response_schema != owned.request.response_schema) return error.ModelRequestAssociationInvalid;
        _ = try value.previous.protocolRepetition(value.rejected, value.diagnostic);
        // Retain only this rejection, not the previous request/body chain.
        next.protocol_rejection = value.diagnostic;
    }
    next.phase = .{ .prepared = owned };
    return create(next);
}

pub fn destroy(request: *Request) void {
    const value: *Storage = @ptrCast(@alignCast(request));
    if (value.phase == .prepared) value.phase.prepared.deinit();
    if (value.restriction) |restriction| restriction.release();
    if (value.protocol_rejection) |diagnostic| diagnostic.deinit(value.allocator);
    if (value.input) |input| if (input == .packet) packets.release(input.packet);
    if (value.composition) |part| {
        packets.release(part.base);
        value.allocator.free(part.prerequisites);
    }
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
    errdefer identity.deinitOwner(value.ledger_owner);
    if (value.input) |input| if (input == .packet) {
        _ = try packets.retain(input.packet);
    };
    errdefer if (value.input) |input| if (input == .packet) packets.release(input.packet);
    result.* = value;
    if (value.composition) |part| {
        result.composition.?.prerequisites = try value.allocator.dupe(composition.Prerequisite, part.prerequisites);
        errdefer value.allocator.free(result.composition.?.prerequisites);
        _ = try packets.retain(part.base);
    }
    errdefer if (value.composition) |part| {
        packets.release(part.base);
        value.allocator.free(result.composition.?.prerequisites);
    };
    if (value.protocol_rejection) |diagnostic| result.protocol_rejection = try diagnostic.copy(value.allocator);
    if (value.restriction) |restriction| restriction.retain();
    return @ptrCast(result);
}

fn storage(request: *const Request) *const Storage {
    return @ptrCast(@alignCast(request));
}
