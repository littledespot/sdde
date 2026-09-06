const std = @import("std");
const pipeline = @import("pipeline.zig");
const workflow = @import("workflow.zig");
const workflow_token_budget = @import("workflow_token_budget.zig");

pub const Kind = enum { invocation, step };
pub const ParameterKind = enum { boolean, integer, string, enumeration, registered_ref, resource, model_slot };
pub const ResourceKind = enum { prompt, result_schema, example, data };

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
    gates: []const []const u8 = &.{},
    retry_limit: ?RetryLimitDescriptor = null,

    // The typed slot is the sole binding declaration, not permission to call
    // a provider. Operational capabilities derive independently from ports.
    pub fn consumesPreparedRequest(self: Contract) bool {
        return @import("workflow_model.zig").consumesPreparedRequest(self.requires);
    }

    pub fn requiresModelBinding(self: Contract) bool {
        for (self.parameters) |parameter| if (parameter.kind == .model_slot) return true;
        return false;
    }
};

pub const PolicyProfile = struct {
    id: []const u8,
    allowed_capabilities: []const []const u8,
    allowed_terminal_outcomes: []const workflow.OutcomeTag,
    total_model_token_budget: workflow_token_budget.TotalTokenBudget,
};

pub fn validAccounting(capability: pipeline.RunnerAccountingCapability, requires: []const pipeline.DataKey, produces: []const pipeline.DataKey, effect: pipeline.SideEffect, retry: bool) bool {
    return switch (capability) {
        .none => for (produces) |key| {
            if (key == .accounted_model_attempt or key == .assigned_provider_operation or key == .invoked_provider_operation) break false;
        } else true,
        .increment_model_attempt => @import("workflow_model.zig").consumesPreparedRequest(requires) and
            std.mem.eql(pipeline.DataKey, produces, &.{.accounted_model_attempt}) and effect == .none and retry,
        .advance_provider_operation => @import("workflow_model.zig").consumesPreparedRequest(requires) and
            std.mem.indexOfScalar(pipeline.DataKey, requires, .accounted_model_attempt) != null and
            (std.mem.eql(pipeline.DataKey, produces, &.{.assigned_provider_operation}) or
                std.mem.eql(pipeline.DataKey, produces, &.{.invoked_provider_operation})) and effect == .none and !retry,
        // Token reconciliation is not yet integrated into YAML execution.
        .reconcile_workflow_tokens => false,
    };
}
