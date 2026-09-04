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
    gates: []const []const u8 = &.{},
    capabilities: []const []const u8 = &.{},
    retry_limit: ?RetryLimitDescriptor = null,
};

pub const PolicyProfile = struct {
    id: []const u8,
    allowed_capabilities: []const []const u8,
    allowed_terminal_outcomes: []const workflow.OutcomeTag,
    total_model_token_budget: workflow_token_budget.TotalTokenBudget,
};
