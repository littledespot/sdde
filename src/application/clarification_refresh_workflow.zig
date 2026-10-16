const std = @import("std");
const c = @import("../domain/clarification_inputs.zig");
const refresh = @import("../domain/clarification_refresh.zig");
const views = @import("../domain/clarification_views.zig");
const values = @import("pipeline_values.zig");
const inputs = @import("clarification_input_workflow.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const publish = @import("workflow_candidate.zig").publish;
// Current corpus witnesses are execution-local and retain the already bounded
// reference-input size in addition to the existing clarification-state size.
const maximum = @import("reference_evidence_workflow.zig").inputs_schema.maximum_bytes.? + c.max_state_bytes * 4;
pub const needs_schema = values.schema(.clarification_needs, refresh.Needs, 2, maximum);
pub const state_schema = values.schema(.refreshed_clarification_state, refresh.Result, 2, maximum);
pub const views_schema = values.schema(.clarification_views, []const views.View, 1, c.max_forms * c.max_form_bytes * 4);
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{ needs_schema, state_schema, views_schema };

pub const BuildSpecificationNeed = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .clarification_route = .{ .kind = .candidate, .subject = .validated_specification_unit, .evidence = .validated_specification_unit, .result = .clarification_needs } };
    pub const Action = @import("../actions/clarification/build_specification_clarification_need.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const checked = @import("specification_values.zig").storage.read(&input.step.data, @import("specification_workflow.zig").checked_schema, .checked) catch |operation_error| return operation_error;
        const feature = values.read(&input.step.data, @import("feature_directory_workflow.zig").selector, @import("../domain/feature_directory.zig").Selector) catch |operation_error| return operation_error;
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const result = self.action.execute(arena.allocator(), feature.feature_id, try @import("specification_workflow.zig").readContext(&input.step.data), checked) catch |operation_error| return operation_error;
        return publish(self.allocator, needs_schema, refresh.Needs, result);
    }
};
pub const Refresh = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .clarification_refresh = .{ .kind = .clarification, .subject = .clarification_needs, .evidence = .clarification_needs, .result = .refreshed_clarification_state } };
    pub const Action = @import("../actions/clarification/refresh_clarifications.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .blocked, .failed };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const captured = values.read(&input.step.data, inputs.inputs_schema, c.Inputs) catch |operation_error| return operation_error;
        const needs = values.read(&input.step.data, needs_schema, refresh.Needs) catch |operation_error| return operation_error;
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        var rejection: ?operations.Error = null;
        const result: refresh.Result = result: {
            const state = self.action.execute(arena.allocator(), captured.*, needs.*) catch |err| switch (err) {
                error.AuthenticationRequired => {
                    rejection = err;
                    break :result .{ .blocked = .authentication_required };
                },
                error.ProtectedClarification => {
                    rejection = err;
                    break :result .{ .blocked = .protected_clarification };
                },
                error.ClarificationLimitExceeded => {
                    rejection = err;
                    break :result .{ .blocked = .limit_exceeded };
                },
                else => return err,
            };
            break :result .{ .ready = state };
        };
        var candidate = try publish(self.allocator, state_schema, refresh.Result, result);
        candidate.outcome = if (result == .ready) .ok else .blocked;
        candidate.diagnostic = rejection;
        return candidate;
    }
};
pub const Render = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .preserve = .{ .kind = .clarification, .subject = .refreshed_clarification_state, .evidence = .refreshed_clarification_state, .result = .clarification_views } };
    pub const Action = @import("../actions/clarification/render_clarification_forms.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const captured = values.read(&input.step.data, inputs.inputs_schema, c.Inputs) catch |operation_error| return operation_error;
        const state = values.read(&input.step.data, state_schema, refresh.Result) catch |operation_error| return operation_error;
        if (state.* != .ready) return error.OperationExecutionFailed;
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const result = self.action.execute(arena.allocator(), state.ready, captured.*) catch |operation_error| return operation_error;
        return publish(self.allocator, views_schema, []const views.View, result);
    }
};

pub const Check = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .preserve = .{ .kind = .clarification, .subject = .refreshed_clarification_state, .evidence = .refreshed_clarification_state } };
    pub const Action = @import("../actions/clarification/check_clarification_progress.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .needs_user, .blocked };
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const result = values.read(&input.step.data, state_schema, refresh.Result) catch |operation_error| return operation_error;
        return .{ .outcome = context.?.action.execute(result.*), .delta = .{} };
    }
};

pub const BuildAuthorityNeeds = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .clarification_route = .{ .kind = .authority, .subject = .required_authority_inputs, .evidence = .required_authority_result, .result = .clarification_needs } };
    pub const Action = @import("../actions/clarification/build_required_authority_clarification_needs.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .blocked, .failed };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const authority = @import("required_authority_workflow.zig");
        const owned = @import("required_authority_values.zig");
        const sources = try values.read(&input.step.data, @import("reference_evidence_workflow.zig").inputs_schema, @import("../domain/reference_evidence.zig").Inputs);
        const source = owned.read(&input.step.data, authority.inputs_schema, .inputs) catch |operation_error| return operation_error;
        const observations = owned.read(&input.step.data, authority.observations_schema, .observations) catch |operation_error| return operation_error;
        const result = owned.read(&input.step.data, authority.result_schema, .result) catch |operation_error| return operation_error;
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const needs = self.action.execute(arena.allocator(), sources.*, source, observations, result) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidRequiredAuthority => .{ .outcome = .blocked, .delta = .{}, .diagnostic = err },
        };
        return publish(self.allocator, needs_schema, refresh.Needs, needs);
    }
};
