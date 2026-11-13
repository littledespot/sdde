const std = @import("std");
const pipeline = @import("pipeline.zig");
const workflow = @import("workflow.zig");

pub const Kind = enum { invocation, step };
pub const ParameterKind = enum { boolean, integer, string, enumeration, registered_ref, resource, model_slot };
pub const ResourceKind = enum { prompt, result_schema, json_composition, packet_guidance, example, data };

pub const ParameterDescriptor = struct {
    id: []const u8,
    kind: ParameterKind,
    required: bool,
    workflow_definition_safe: bool,
    integer_min: i64 = std.math.minInt(i64),
    integer_max: i64 = std.math.maxInt(i64),
    string_max_bytes: usize = 128,
    allowed_values: []const []const u8 = &.{},
    resource_kind: ?ResourceKind = null,
};

pub const RetryLimitDescriptor = struct {
    maximum: u32,
    scope: @import("workflow_retry.zig").Scope = .operation,
};

/// One closed variant of a contract that has variants (ADR 0030 "Contract variants"). A variant is
/// a complete contract: its type has no defaulted field, so each one states every field, and
/// nothing is partial or merged from another variant. Its `parameters` are the whole parameter list
/// of a step that selects it, the selector's descriptor included.
pub const Variant = struct {
    /// The selector parameter's value that picks this variant.
    value: []const u8,
    parameters: []const ParameterDescriptor,
    requires: []const pipeline.DataKey,
    optional: []const pipeline.DataKey,
    produces: []const pipeline.DataKey,
    replaces: []const pipeline.DataKey,
    invalidates: []const pipeline.DataKey,
    outcomes: []const workflow.OutcomeTag,
    side_effect: pipeline.SideEffect,
    runner_accounting: pipeline.RunnerAccountingCapability,
    repair_role: @import("workflow_retry.zig").Role,
    outcome_association: @import("workflow_outcome_association.zig").Descriptor,
    gates: []const []const u8,
    retry_limit: ?RetryLimitDescriptor,
    iteration: ?@import("workflow_iteration.zig").Descriptor,
};

pub const Contract = struct {
    id: []const u8,
    kind: Kind,
    parameters: []const ParameterDescriptor = &.{},
    requires: []const pipeline.DataKey = &.{},
    optional: []const pipeline.DataKey = &.{},
    produces: []const pipeline.DataKey = &.{},
    replaces: []const pipeline.DataKey = &.{},
    invalidates: []const pipeline.DataKey = &.{},
    outcomes: []const workflow.OutcomeTag,
    side_effect: pipeline.SideEffect,
    runner_accounting: pipeline.RunnerAccountingCapability = .none,
    repair_role: @import("workflow_retry.zig").Role = .none,
    outcome_association: @import("workflow_outcome_association.zig").Descriptor = .independent,
    gates: []const []const u8 = &.{},
    retry_limit: ?RetryLimitDescriptor = null,
    iteration: ?@import("workflow_iteration.zig").Descriptor = null,
    /// The one closed enumeration step parameter that selects a variant at compile time. A contract
    /// with variants states every other field only in its variants (its own are then empty), and a
    /// step that leaves the selector out is rejected: no variant is selected by its absence.
    selector: ?[]const u8 = null,
    variants: []const Variant = &.{},

    // The typed slot is the sole binding declaration, not permission to call
    // a provider. Operational capabilities derive independently from ports.
    pub fn consumesPreparedRequest(self: Contract) bool {
        return @import("workflow_model.zig").consumesPreparedRequest(self.requires);
    }

    pub fn requiresModelBinding(self: Contract) bool {
        for (self.parameters) |parameter| if (parameter.kind == .model_slot) return true;
        return false;
    }

    pub fn hasVariants(self: Contract) bool {
        return self.variants.len != 0;
    }

    /// The contract a step is checked against, flat as any single-shape contract is. A contract with
    /// variants needs the selector's value and yields exactly that variant, never a union; a
    /// contract without variants takes no selector.
    pub fn resolve(self: Contract, selected: ?[]const u8) ?Contract {
        if (!self.hasVariants()) return if (selected == null and self.selector == null) self else null;
        const value = selected orelse return null;
        for (self.variants) |variant| if (std.mem.eql(u8, variant.value, value)) return .{
            .id = self.id,
            .kind = self.kind,
            .parameters = variant.parameters,
            .requires = variant.requires,
            .optional = variant.optional,
            .produces = variant.produces,
            .replaces = variant.replaces,
            .invalidates = variant.invalidates,
            .outcomes = variant.outcomes,
            .side_effect = variant.side_effect,
            .runner_accounting = variant.runner_accounting,
            .repair_role = variant.repair_role,
            .outcome_association = variant.outcome_association,
            .gates = variant.gates,
            .retry_limit = variant.retry_limit,
            .iteration = variant.iteration,
        };
        return null;
    }

    /// A contract with variants carries no shape of its own: only its id, kind, selector and
    /// variants. Anything else would be a second contract beside them.
    pub fn isShell(self: Contract) bool {
        return self.hasVariants() and self.selector != null and self.parameters.len == 0 and self.requires.len == 0 and
            self.optional.len == 0 and self.produces.len == 0 and self.replaces.len == 0 and self.invalidates.len == 0 and
            self.outcomes.len == 0 and self.side_effect == .none and self.runner_accounting == .none and
            self.repair_role == .none and self.outcome_association == .independent and self.gates.len == 0 and
            self.retry_limit == null and self.iteration == null;
    }
};

pub fn validRepair(role: @import("workflow_retry.zig").Role, retry: ?@import("workflow_retry.zig").Scope, accounting: pipeline.RunnerAccountingCapability, effect: pipeline.SideEffect) bool {
    if (role != .none and (effect != .none or accounting != .none)) return false;
    if (accounting == .increment_model_attempt and retry != .model_request) return false;
    if (retry) |scope| switch (scope) {
        .operation => if (role == .merge or role == .merge_validate) return false,
        .repair => if (role != .merge and role != .merge_validate) return false,
        .model_request => if (accounting != .increment_model_attempt or role != .none) return false,
    };
    return true;
}

pub const PolicyProfile = struct {
    id: []const u8,
    allowed_capabilities: []const []const u8,
    allowed_terminal_outcomes: []const workflow.OutcomeTag,
};

pub fn validAccounting(capability: pipeline.RunnerAccountingCapability, requires: []const pipeline.DataKey, produces: []const pipeline.DataKey, effect: pipeline.SideEffect, retry: bool) bool {
    return switch (capability) {
        .none => for (produces) |key| {
            if (key == .accounted_model_attempt or key == .assigned_provider_operation or key == .invoked_provider_operation or key == .terminal_provider_operation) break false;
        } else true,
        .increment_model_attempt => @import("workflow_model.zig").consumesPreparedRequest(requires) and
            std.mem.eql(pipeline.DataKey, produces, &.{.accounted_model_attempt}) and effect == .none and retry,
        .advance_provider_operation => @import("workflow_model.zig").consumesPreparedRequest(requires) and
            std.mem.indexOfScalar(pipeline.DataKey, requires, .accounted_model_attempt) != null and
            (std.mem.eql(pipeline.DataKey, produces, &.{.assigned_provider_operation}) or
                std.mem.eql(pipeline.DataKey, produces, &.{.invoked_provider_operation}) or
                std.mem.eql(pipeline.DataKey, produces, &.{.terminal_provider_operation})) and effect == .none and !retry,
        // Token reconciliation is not yet integrated into YAML execution.
        .reconcile_workflow_tokens => false,
    };
}
