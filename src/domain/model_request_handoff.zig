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
pub const ContentBuffer = [3]provider.ModelVisibleContent;

/// One immutable association, carried by typed pipeline keys. Canonical IDs are
/// retained through their ledger owner, never cloned into a second authority.
pub const Request = opaque {
    /// Authored resource aliases retained by this exact request selection.
    pub fn sourceResources(self: *const Request) SourceResources {
        const value = storage(self);
        return .{
            .prompt = value.prompt.id,
            .context = if (value.context) |resource| resource.id else null,
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
        if (storage(self).presented_input) |bytes| return bytes;
        return switch (storage(self).input orelse return null) {
            .resource => |resource| resource.content.data,
            .packet => |value| value.body(),
        };
    }

    /// Project original immutable inputs for initial calls and corrections.
    pub fn content(self: *const Request, buffer: *ContentBuffer) []const provider.ModelVisibleContent {
        var count: usize = 0;
        if (storage(self).context) |resource| {
            buffer[count] = .{ .guidance = resource.content.prompt };
            count += 1;
        }
        buffer[count] = .{ .guidance = self.prompt() };
        count += 1;
        if (self.input()) |bytes| {
            buffer[count] = .{ .user = bytes };
            count += 1;
        }
        return buffer[0..count];
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
            .original_sources = if (self.packet()) |packet_value| packet_value.originalSources() else &.{},
            .prose_fields = if (self.packet()) |packet_value| packet_value.proseFields() else &.{},
            .field_policies = if (self.packet()) |packet_value| packet_value.fieldPolicies() else &.{},
        };
    }

    pub fn prepared(self: *const Request) ?*const provider.IdentifiedProviderNeutralModelRequest {
        return switch (storage(self).phase) {
            .prepared => |owned| owned.request,
            else => null,
        };
    }

    /// The exact rejected inference retained by this prepared correction.
    /// Its identity borrows this request's canonical ledger owner.
    pub fn protocolCorrection(self: *const Request) ?provider.ProviderOperationId {
        return if (storage(self).protocol_rejection) |rejected| rejected.operation_id else null;
    }

    /// Only a response to this exact prepared correction can confirm recurrence.
    pub fn protocolRepetition(self: *const Request, rejected: *const @import("provider_invocation_validation.zig").Evidence, diagnostic: retry.Diagnostic) Error!retry.Repetition {
        const request = self.prepared() orelse return error.ModelRequestAssociationInvalid;
        if (rejected.request() != request) return error.ModelRequestAssociationInvalid;
        const previous = storage(self).protocol_rejection orelse return .unconfirmed;
        return if (previous.diagnostic.eql(diagnostic)) .confirmed else .unconfirmed;
    }

    pub fn buildSource(self: *const Request, input_id: *[32]u8) preparation.ValidationError!preparation.Source {
        const bytes = std.fmt.bufPrint(input_id, "input-{d}", .{self.ledger().revision().value}) catch return error.ModelRequestAssociationInvalid;
        return self.source(.{ .bytes = bytes });
    }
};

pub const SourceResources = struct {
    prompt: @import("workflow.zig").WorkflowResourceId,
    context: ?@import("workflow.zig").WorkflowResourceId,
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
    context: ?compilation.CompiledResource = null,
    protocol_prompt: ?compilation.CompiledResource,
    result: compilation.CompiledResource,
    result_definition: ?@import("model_result_schema.zig").DefinitionId = null,
    input: ?Input,
    /// Model-visible projection of the immutable native packet. Keep the
    /// original packet for exact assignment, retention and repair authority.
    presented_input: ?[]const u8 = null,
    composition: ?composition.Binding = null,
    restriction: ?*@import("model_result_schema.zig").Restricted = null,
    protocol_rejection: ?struct { diagnostic: retry.Diagnostic, operation_id: provider.ProviderOperationId } = null,
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
    context: ?compilation.CompiledResource = null,
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
        return assign(allocator, assignment.owner, assignment.model_request_id, self);
    }

    /// Compare one actual accepted semantic assignment with its current native
    /// selection. The pure admission step may differ from the producing inference
    /// step; its workflow/version and complete semantic selection must agree.
    /// This creates no request or origin; the caller still owns current finding
    /// admission. Composed and resource inputs have no retention contract here.
    pub fn acceptsRetained(self: Selection, allocator: std.mem.Allocator, ledger: *const identity.ModelRequestIdentityLedger, request: *const Request, origin: @import("model_candidate_origin.zig").Origin) Error!bool {
        const prior = storage(request);
        const current = self.input orelse return false;
        const old = prior.input orelse return false;
        if (self.composition != null or prior.composition != null or current != .packet or old != .packet or
            current.packet.purpose() != .semantic_review or old.packet.purpose() != .semantic_review or
            self.result_selection != .input or prior.result_definition == null or prior.phase != .prepared or
            current.packet.repairPermit() != null or current.packet.repairOrigin() != null or
            old.packet.repairPermit() != null or old.packet.repairOrigin() != null) return false;
        if (!ledger.stageRunEpochId().eql(request.id().stage_run_epoch_id) or origin.kind != .inference) return false;
        const record = ledger.record(request.id()) orelse return false;
        if (record.status != .terminal or record.terminal_reason != .accepted or
            origin.request.value != (ledger.indexOf(request.id()) orelse return false).value) return false;
        const accepted_attempt: u32 = if (request.protocolCorrection()) |previous|
            std.math.add(u32, previous.model_attempt_ordinal.value, 1) catch return false
        else
            1;
        var comparable_binding = self.binding.bindingId();
        comparable_binding.operation_id.workflow_step_id = prior.binding.operation_id.workflow_step_id;
        if (origin.attempt.value != accepted_attempt or !self.binding.operation_id.isValid() or
            self.binding.registry_entry != prior.binding.registry_entry or
            !comparable_binding.eql(prior.binding.bindingId())) return false;
        _ = identity.validateBinding(ledger, ledger.revision(), request.id(), self.unit(), prior.binding.operation_id, self.purpose()) catch return false;
        if (!resourceEql(self.prompt, prior.prompt) or !optionalResourceEql(self.context, prior.context) or
            !optionalResourceEql(self.protocol_prompt, prior.protocol_prompt) or
            self.result.content != .result_schema or !std.mem.eql(u8, self.result.id.bytes, prior.result.id.bytes) or
            !optionalBytesEql(self.result.source_path, prior.result.source_path)) return false;
        const definition = current.packet.resultDefinition() orelse return false;
        if (!std.mem.eql(u8, definition.bytes, prior.result_definition.?.bytes) or
            !std.mem.eql(u8, current.packet.body(), old.packet.body())) return false;
        const canonical = self.result.content.result_schema.select(definition) orelse return false;
        if (canonical != prior.result.content.result_schema) return false;
        const Restrictions = struct {
            excluded: []const @import("model_result_schema.zig").ExcludedVariant,
            choices: []const @import("model_result_schema.zig").IntegerChoice,
            fields: []const @import("model_text_field.zig").Binding,
            omissions: []const @import("model_field_presentation.zig").Omission,
        };
        const codec = @import("canonical_json.zig");
        const current_restrictions = codec.encode(Restrictions, allocator, .{ .excluded = current.packet.excludedVariants(), .choices = current.packet.integerChoices(), .fields = current.packet.fieldPolicies(), .omissions = current.packet.presentationOmissions() }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false;
        defer allocator.free(current_restrictions);
        const old_restrictions = codec.encode(Restrictions, allocator, .{ .excluded = old.packet.excludedVariants(), .choices = old.packet.integerChoices(), .fields = old.packet.fieldPolicies(), .omissions = old.packet.presentationOmissions() }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false;
        defer allocator.free(old_restrictions);
        if (!std.mem.eql(u8, current_restrictions, old_restrictions)) return false;
        const effective = if (current.packet.excludedVariants().len != 0 or current.packet.integerChoices().len != 0 or current.packet.fieldPolicies().len != 0)
            @import("model_result_schema.zig").restrictFieldPolicies(allocator, canonical, current.packet.excludedVariants(), current.packet.integerChoices(), current.packet.fieldPolicies()) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false
        else
            null;
        defer if (effective) |restricted| restricted.release();
        const expected_schema = if (effective) |restricted| restricted.selected() else canonical;
        return std.mem.eql(u8, expected_schema.modelBytes(), prior.phase.prepared.request.response_schema.modelBytes());
    }
};

fn optionalBytesEql(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}

fn resourceEql(left: compilation.CompiledResource, right: compilation.CompiledResource) bool {
    return left.kind() == right.kind() and std.mem.eql(u8, left.id.bytes, right.id.bytes) and
        optionalBytesEql(left.source_path, right.source_path) and std.mem.eql(u8, left.bytes(), right.bytes());
}

fn optionalResourceEql(left: ?compilation.CompiledResource, right: ?compilation.CompiledResource) bool {
    if (left == null or right == null) return left == null and right == null;
    return resourceEql(left.?, right.?);
}

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
    var parts: ContentBuffer = undefined;
    var owned = try preparation.build(allocator, try checked.buildSource(&input_id), checked.content(&parts));
    errdefer owned.deinit();
    const built = try prepared(checked, owned, null);
    return .{ .owner = assignment.owner, .assigned = assigned, .validated = checked, .request = built };
}

pub fn assign(allocator: std.mem.Allocator, ledger_owner: *identity.Owner, id: *const identity.ModelRequestId, selected: Selection) Error!*Request {
    const prompt = selected.prompt;
    const result = selected.result;
    const input = selected.input;
    const protocol_prompt = selected.protocol_prompt;
    const selection = selected.result_selection;
    const part_binding = selected.composition;
    if (selected.context) |resource| if (resource.content != .prompt) return error.ModelRequestAssociationInvalid;
    if (protocol_prompt) |resource| if (resource.content != .prompt) return error.ModelRequestAssociationInvalid;
    if (prompt.content != .prompt or result.content != .result_schema or
        (input != null and input.? == .resource and input.?.resource.content != .data) or
        !identity.ledger(ledger_owner).containsRequest(id) or
        !id.model_operation_id.eql(selected.binding.operation_id)) return error.ModelRequestAssociationInvalid;
    if (input) |value| if (value == .packet) {
        const current = identity.ledger(ledger_owner);
        _ = identity.validateBinding(current, current.revision(), id, value.packet.unit(), selected.binding.operation_id, value.packet.purpose()) catch return error.ModelRequestAssociationInvalid;
    };
    var bound_result = result;
    if (part_binding) |part| {
        if (selection != .resource or !part.valid() or result.content.result_schema != part.plan.resultSchema() or
            !std.mem.eql(u8, result.id.bytes, part.plan.resultAlias().bytes) or
            !part.epoch.eql(identity.ledger(ledger_owner).stageRunEpochId())) return error.ModelRequestAssociationInvalid;
        const current = identity.ledger(ledger_owner);
        _ = identity.validateBinding(current, current.revision(), id, part.base.unit(), selected.binding.operation_id, part.base.purpose()) catch return error.ModelRequestAssociationInvalid;
    }
    if (selection == .input) {
        const packet = input orelse return error.ModelRequestAssociationInvalid;
        if (packet != .packet or result.content != .result_schema) return error.ModelRequestAssociationInvalid;
        const definition_id = packet.packet.resultDefinition() orelse return error.ModelRequestAssociationInvalid;
        bound_result.content = .{ .result_schema = result.content.result_schema.select(definition_id) orelse return error.ModelRequestAssociationInvalid };
    }
    const excluded = if (input != null and input.? == .packet) input.?.packet.excludedVariants() else &.{};
    const integer_choices = if (input != null and input.? == .packet) input.?.packet.integerChoices() else &.{};
    const field_policies = if (input != null and input.? == .packet) input.?.packet.fieldPolicies() else &.{};
    const restriction = if (excluded.len != 0 or integer_choices.len != 0 or field_policies.len != 0)
        @import("model_result_schema.zig").restrictFieldPolicies(allocator, if (part_binding) |part| part.schema else bound_result.content.result_schema, excluded, integer_choices, field_policies) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidModelRequestSource
    else
        null;
    defer if (restriction) |owned| owned.release();
    const presented: ?[]const u8 = if (input != null and input.? == .packet and
        (field_policies.len != 0 or input.?.packet.presentationOmissions().len != 0))
    presented: {
        const packet = input.?.packet;
        const response = if (restriction) |value| value.selected() else if (part_binding) |part| part.schema else bound_result.content.result_schema;
        break :presented @import("model_field_presentation.zig").project(allocator, packet.body(), response.root(), packet.fieldPolicies(), packet.presentationOmissions()) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidModelRequestSource;
    } else null;
    defer if (presented) |bytes| allocator.free(bytes);
    return create(.{
        .allocator = allocator,
        .ledger_owner = ledger_owner,
        .id = id,
        .binding = selected.binding,
        .prompt = prompt,
        .context = selected.context,
        .protocol_prompt = protocol_prompt,
        .result = bound_result,
        .result_definition = if (selection == .input) input.?.packet.resultDefinition() else null,
        .input = input,
        .presented_input = presented,
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
        const operation_id = value.rejected.operationId();
        if (operation_id.model_request_id != current.id() or operation_id.kind != .inference or operation_id.model_attempt_ordinal.value == 0)
            return error.ModelRequestAssociationInvalid;
        // Retain only this diagnostic and call identity, not the prior body chain.
        next.protocol_rejection = .{ .diagnostic = value.diagnostic, .operation_id = operation_id };
    }
    next.phase = .{ .prepared = owned };
    return create(next);
}

pub fn destroy(request: *Request) void {
    const value: *Storage = @ptrCast(@alignCast(request));
    if (value.phase == .prepared) value.phase.prepared.deinit();
    if (value.restriction) |restriction| restriction.release();
    if (value.protocol_rejection) |rejected| rejected.diagnostic.deinit(value.allocator);
    if (value.presented_input) |bytes| value.allocator.free(bytes);
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
    if (value.presented_input) |bytes| result.presented_input = try value.allocator.dupe(u8, bytes);
    errdefer if (result.presented_input) |bytes| value.allocator.free(bytes);
    if (value.composition) |part| {
        result.composition.?.prerequisites = try value.allocator.dupe(composition.Prerequisite, part.prerequisites);
        errdefer value.allocator.free(result.composition.?.prerequisites);
        _ = try packets.retain(part.base);
    }
    errdefer if (value.composition) |part| {
        packets.release(part.base);
        value.allocator.free(result.composition.?.prerequisites);
    };
    if (value.protocol_rejection) |rejected| result.protocol_rejection = .{
        .diagnostic = try rejected.diagnostic.copy(value.allocator),
        .operation_id = rejected.operation_id,
    };
    if (value.restriction) |restriction| restriction.retain();
    return @ptrCast(result);
}

fn storage(request: *const Request) *const Storage {
    return @ptrCast(@alignCast(request));
}
