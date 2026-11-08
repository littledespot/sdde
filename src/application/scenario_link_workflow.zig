//! Native bindings only (ADR 0038 Decision 7). YAML owns the model call, its retries and the
//! loop over the edge cases that need a choice; the population is frozen by the plan.
const std = @import("std");
const data = @import("../domain/pipeline_data.zig");
const pipeline = @import("../domain/pipeline.zig");
const workflow = @import("../domain/workflow.zig");
const owned = @import("specification_values.zig").storage;
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const spec = @import("specification_workflow.zig");
const requests = @import("model_request_workflow.zig");
const session = @import("../domain/specification_session.zig");
const link = @import("../domain/scenario_link.zig");
const request = @import("../domain/scenario_link_request.zig");

pub const progress_schema = values.schema(.scenario_link_progress, owned.Value, 1, null).captured();
pub const schemas = [_]data.Schema{progress_schema};

/// The choices admitted so far, in the plan's order. A blocked plan holds none.
pub fn chosen(view: *const data.View) operations.Error![]const link.Link {
    return owned.read(view, progress_schema, .links) catch |operation_error| operation_error;
}

/// Every edge case's link, once each pending one has its admitted choice.
pub fn resolved(allocator: std.mem.Allocator, view: *const data.View, current: session.Session) operations.Error![]const link.Link {
    return link.resolve(allocator, try request.planFor(allocator, current), try chosen(view)) catch |operation_error| operation_error;
}

pub const Plan = struct {
    pub const Action = @import("../actions/specification/plan_scenario_links.zig").Action;
    pub const iteration: @import("../domain/workflow_iteration.zig").Descriptor = .{ .kind = .initialize, .scope = .specification_generation_session, .progress = .scenario_link_progress };
    pub const outcomes = [_]workflow.OutcomeTag{ .ok, .blocked, .failed };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        errdefer owned.destroy(owner);
        const planned = self.action.execute(owner.arena.allocator(), try spec.readSession(&input.step.data), try spec.readContext(&input.step.data)) catch |operation_error| return operation_error;
        owner.payload = switch (planned) {
            .ready => .{ .links = &.{} },
            .blocked => |rejection| .{ .binding_rejected = rejection },
        };
        var output = owned.publish(self.allocator, progress_schema, owner, if (planned == .ready) .ok else .blocked) catch |operation_error| return operation_error;
        if (planned == .ready) output.iteration = .{ .limit = planned.ready, .before = 0, .after = 0 };
        return output;
    }
};

pub const Check = struct {
    pub const Action = @import("../actions/specification/check_scenario_link_progress.zig").Action;
    pub const outcomes = [_]workflow.OutcomeTag{ .ok, .more, .failed };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        return .{ .outcome = self.action.execute(arena.allocator(), try spec.readSession(&input.step.data), try chosen(&input.step.data)) catch |operation_error| return operation_error, .delta = .{} };
    }
};

pub const BuildInput = struct {
    pub const Action = @import("../actions/specification/build_scenario_link_input.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const packet = self.action.execute(self.allocator, try spec.readSession(&input.step.data), try spec.readContext(&input.step.data), try chosen(&input.step.data)) catch |operation_error| return operation_error;
        return requests.publishPacket(self.allocator, packet);
    }
};

pub const Admit = struct {
    pub const Action = @import("../actions/specification/admit_scenario_link_choice.zig").Action;
    pub const iteration: @import("../domain/workflow_iteration.zig").Descriptor = .{ .kind = .advance, .scope = .specification_generation_session, .progress = .scenario_link_progress };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const packet = values.read(&input.step.data, requests.packet_schema, @import("../domain/model_input_packet.zig").Packet) catch |operation_error| return operation_error;
        const source = try @import("model_candidate_handoff.zig").read(&input.step.data);
        const before = try chosen(&input.step.data);
        const current = try spec.readSession(&input.step.data);
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        errdefer owned.destroy(owner);
        const next = self.action.execute(owner.arena.allocator(), current, try spec.readContext(&input.step.data), before, packet, source.body) catch |operation_error| return operation_error;
        const limit = request.limit(owner.arena.allocator(), current) catch |operation_error| return operation_error;
        owner.payload = .{ .links = next };
        var delta: pipeline.NodeDelta = .{};
        delta.data_replacements[@intFromEnum(progress_schema.key)] = values.adopt(self.allocator, progress_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch |operation_error| return operation_error;
        return .{ .outcome = .ok, .delta = delta, .iteration = .{ .limit = limit, .before = before.len, .after = next.len } };
    }
};
