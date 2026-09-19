const std = @import("std");
const pipeline = @import("pipeline.zig");
const telemetry = @import("telemetry.zig");
const workflow = @import("workflow.zig");
const operation = @import("workflow_operation.zig");
const provider_identity = @import("llm_provider_identity.zig");
const workflow_retry = @import("workflow_retry.zig");
const workflow_token_budget = @import("workflow_token_budget.zig");

pub const CompiledParameterValue = union(enum) {
    boolean: bool,
    integer: i64,
    string: []const u8,
    enumeration: []const u8,
    registered_ref: workflow.RegisteredRef,
    resource: workflow.WorkflowResourceId,
    model_slot: provider_identity.ModelSlotId,
};

pub const CompiledParameter = struct {
    id: workflow.WorkflowParameterId,
    value: CompiledParameterValue,
};

pub const CompiledResource = struct {
    id: workflow.WorkflowResourceId,
    content: union(operation.ResourceKind) {
        prompt: []const u8,
        result_schema: *const @import("model_result_schema.zig").Schema,
        json_composition: *const @import("json_composition.zig").Plan,
        example: []const u8,
        data: []const u8,
    },

    pub fn kind(self: CompiledResource) operation.ResourceKind {
        return std.meta.activeTag(self.content);
    }

    pub fn bytes(self: CompiledResource) []const u8 {
        return switch (self.content) {
            .result_schema => |schema| schema.bytes(),
            .json_composition => |plan| plan.bytes(),
            inline else => |value| value,
        };
    }

    pub fn clone(self: CompiledResource, allocator: std.mem.Allocator, canonical: ?*const @import("model_result_schema.zig").Schema) @import("json_composition.zig").Error!CompiledResource {
        return .{
            .id = .{ .bytes = try allocator.dupe(u8, self.id.bytes) },
            .content = switch (self.content) {
                .result_schema => |schema| .{ .result_schema = try schema.clone(allocator) },
                .json_composition => |plan| .{ .json_composition = try plan.clone(allocator, canonical orelse return error.InvalidJsonComposition) },
                inline else => |value, tag| @unionInit(@FieldType(CompiledResource, "content"), @tagName(tag), try allocator.dupe(u8, value)),
            },
        };
    }
};

pub fn validResourceBindings(resources: []const CompiledResource) bool {
    for (resources) |resource| if (resource.content == .json_composition) {
        const plan = resource.content.json_composition;
        const canonical = findResultSchema(resources, plan.resultAlias()) orelse return false;
        if (canonical != plan.resultSchema()) return false;
    };
    return true;
}

pub fn findResultSchema(resources: []const CompiledResource, id: workflow.WorkflowResourceId) ?*const @import("model_result_schema.zig").Schema {
    for (resources) |resource| if (std.mem.eql(u8, resource.id.bytes, id.bytes)) {
        return if (resource.content == .result_schema) resource.content.result_schema else null;
    };
    return null;
}

pub const CompiledStep = struct {
    id: workflow.WorkflowStepId,
    operation_id: workflow.OperationId,
    parameters: []const CompiledParameter,
    requires: []const pipeline.DataKey,
    optional: []const pipeline.DataKey = &.{},
    produces: []const pipeline.DataKey,
    replaces: []const pipeline.DataKey,
    invalidates: []const pipeline.DataKey,
    outcomes: []const workflow.OutcomeTag,
    side_effect: pipeline.SideEffect,
    runner_accounting: pipeline.RunnerAccountingCapability = .none,
    repair_role: workflow_retry.Role = .none,
    gates: []const @import("workflow_gate.zig").Contract,
    capabilities: []const []const u8,
    retry_authority: ?workflow_retry.CompiledAuthority,
    // Compiler-proven immutable model-binding requirements, including for pure
    // preparation steps without a provider-call capability.
    model: ?@import("workflow_model.zig").Requirements = null,
};

pub const SemanticAuthority = struct {
    allowed_capabilities: []const []const u8 = &.{},
    data_schemas: []const @import("pipeline_data.zig").Schema = &.{},
    workflow_id: workflow.WorkflowId,
    workflow_version: u32,
    invocation_operation_id: workflow.OperationId,
    policy_profile_id: workflow.RegisteredRef,
    total_model_token_budget: workflow_token_budget.TotalTokenBudget,
    start_step_id: workflow.WorkflowStepId,
    invocation_outputs: []const pipeline.DataKey,
    resources: []const CompiledResource,
    steps: []const CompiledStep,
    transitions: []const workflow.Transition,
    maximum_step_executions: usize,
};

pub const CompiledWorkflow = struct {
    source_ordinal: u16,
    shortcode: telemetry.WorkflowShortcode,
    authority: SemanticAuthority,
};

pub const ValidatedGraphs = struct { values: []const CompiledWorkflow };

pub fn calculateExecutionLimit(steps: []const CompiledStep) ?usize {
    if (steps.len == 0) return null;
    var total_retry_limit: usize = 0;
    for (steps) |step| {
        if (step.retry_authority) |authority| {
            const visits: usize = if (authority.scope == .operation) authority.limit.value else bounded: {
                const per_key = std.math.add(usize, authority.limit.value, 1) catch return null;
                const keys = std.math.add(usize, workflow_retry.maximum_repair_keys, if (authority.scope == .model_request) workflow_retry.maximum_request_assignments else 0) catch return null;
                break :bounded std.math.mul(usize, per_key, keys) catch return null;
            };
            total_retry_limit = std.math.add(usize, total_retry_limit, visits) catch return null;
        }
    }
    const rounds = std.math.add(usize, total_retry_limit, 1) catch return null;
    return std.math.mul(usize, steps.len, rounds) catch return null;
}
