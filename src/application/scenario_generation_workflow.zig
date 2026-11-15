//! Native bindings only (ADR 0038 Decision 3). YAML owns the model call, its retries, the validation
//! and repair of the written criteria, and the loop over the groups that have a slot; the population
//! is frozen by the plan. The request, collection, parsing and validation steps are the shared
//! specification-unit operations. While scenarios are written the session's records unit is the
//! group's batch: collection and validation run on it unchanged, and the operations that build the
//! request and parse the answer switch on the session's scenarios phase. Each transition has one
//! owner: the plan writes the population, an advance joins one group's criteria, and one completion
//! merges the batches.
const std = @import("std");
const data = @import("../domain/pipeline_data.zig");
const pipeline = @import("../domain/pipeline.zig");
const workflow = @import("../domain/workflow.zig");
const owned = @import("specification_values.zig").storage;
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const spec = @import("specification_workflow.zig");
const session = @import("../domain/specification_session.zig");

pub const progress_schema = values.schema(.scenario_generation_progress, owned.Value, 1, null).captured();
pub const schemas = [_]data.Schema{progress_schema};

/// The step's iteration progress: it carries no value (the session counts the admitted groups).
fn progressValue(allocator: std.mem.Allocator, inputs: data.View) operations.Error!*data.Value {
    const owner = owned.create(allocator, inputs) catch |operation_error| return operation_error;
    errdefer owned.destroy(owner);
    owner.payload = .scenarios;
    return values.adopt(allocator, progress_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch |operation_error| return operation_error;
}

/// Plans the step: its iteration is the groups with a slot, one advance for each. The session is unchanged.
pub const Plan = struct {
    pub const Action = @import("../actions/specification/plan_scenario_generation.zig").Action;
    pub const iteration: @import("../domain/workflow_iteration.zig").Descriptor = .{ .kind = .initialize, .scope = .accounted_reference_reconciliation, .progress = .scenario_generation_progress };
    pub const outcomes = [_]workflow.OutcomeTag{ .ok, .failed };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const population = self.action.execute(try spec.readSession(&input.step.data)) catch |operation_error| return operation_error;
        var delta: pipeline.NodeDelta = .{};
        delta.data_writes[@intFromEnum(progress_schema.key)] = try progressValue(self.allocator, input.step.data);
        return .{ .outcome = .ok, .delta = delta, .iteration = .{ .limit = population, .before = 0, .after = 0 } };
    }
};

/// `more` while a group awaits its scenarios; once every group has them, `invalid` when the criterion
/// family is missing, else `ok`. It reads the session and changes nothing.
pub const Check = struct {
    pub const Action = @import("../actions/specification/check_scenario_generation_progress.zig").Action;
    pub const outcomes = [_]workflow.OutcomeTag{ .ok, .more, .invalid, .failed };
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        return .{ .outcome = context.?.action.execute(try spec.readSession(&input.step.data)), .delta = .{} };
    }
};

/// Joins the validated criteria of one group to its batch and advances the step's iteration.
pub const Advance = struct {
    pub const Action = @import("../actions/specification/advance_scenario_generation.zig").Action;
    pub const iteration: @import("../domain/workflow_iteration.zig").Descriptor = .{ .kind = .advance, .scope = .accounted_reference_reconciliation, .progress = .scenario_generation_progress };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const checked = owned.read(&input.step.data, spec.checked_schema, .checked) catch |operation_error| return operation_error;
        const current = try spec.readSession(&input.step.data);
        const advanced = advanced: {
            const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
            errdefer owned.destroy(owner);
            const next = self.action.execute(owner.arena.allocator(), current, checked) catch |operation_error| return operation_error;
            owner.payload = .{ .session = next };
            const adopted = values.adopt(self.allocator, spec.session_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch |operation_error| return operation_error;
            break :advanced .{ .replacement = adopted, .cursor = next.scenario_cursor };
        };
        const replacement = advanced.replacement;
        errdefer values.destroy(replacement);
        var delta: pipeline.NodeDelta = .{};
        delta.data_replacements[@intFromEnum(spec.session_schema.key)] = replacement;
        delta.data_replacements[@intFromEnum(progress_schema.key)] = try progressValue(self.allocator, input.step.data);
        for (Action.contract.invalidates) |key| delta.data_invalidations.insert(key);
        return .{ .outcome = .ok, .delta = delta, .iteration = .{ .limit = session.scenarioPopulation(current), .before = current.scenario_cursor, .after = advanced.cursor } };
    }
};

/// The one completion of the records unit: it merges the batches once every group with a slot has
/// its criteria.
pub const Complete = struct {
    pub const Action = @import("../actions/specification/complete_scenario_generation.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = try spec.readSession(&input.step.data);
        const replacement = completed: {
            const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
            errdefer owned.destroy(owner);
            owner.payload = .{ .session = self.action.execute(owner.arena.allocator(), current) catch |operation_error| return operation_error };
            break :completed values.adopt(self.allocator, spec.session_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch |operation_error| return operation_error;
        };
        errdefer values.destroy(replacement);
        var delta: pipeline.NodeDelta = .{};
        delta.data_replacements[@intFromEnum(spec.session_schema.key)] = replacement;
        return .{ .outcome = .ok, .delta = delta };
    }
};
