//! One-action runner bindings. YAML owns model calls, retirement and revalidation.
const std = @import("std");
const data = @import("../domain/pipeline_data.zig");
const pipeline = @import("../domain/pipeline.zig");
const r = @import("../domain/reference_reconciliation.zig");
const repair = @import("../domain/reference_reconciliation_repair.zig");
const rec = @import("reference_reconciliation_workflow.zig");
const extraction = @import("reference_extraction_workflow.zig");
const reference = @import("../domain/reference_candidate_value.zig");
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const Origin = @import("../domain/model_candidate_origin.zig").Origin;
const Replacement = union(enum) { pending, automatic: ?repair.Replacement, model: struct { value: repair.Replacement, origin: Origin } };
const Payload = union(enum) {
    authorized: struct { authorization: repair.Authorization, replacement: Replacement },
    blocked: struct { reason: repair.Block, rejection: r.diagnostic.Rejection },
    rejected,
};
const owned = @import("retained_candidate.zig").Storage(Payload, .rejected);
pub const state_schema = values.schema(.reference_reconciliation_repair, owned.Value, 1, null).captured();
pub const schemas = [_]data.Schema{state_schema};
const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .blocked, .failed };
const Stage = enum { summary, dispositions, signals, conflicts };
pub fn Authorize(comptime stage: Stage) type {
    return struct {
        pub const repair_role: @import("../domain/workflow_retry.zig").Role = .authorize;
        pub const Action = switch (stage) {
            .summary => @import("../actions/reference/authorize_reference_summary_repair.zig").Action,
            .dispositions => @import("../actions/reference/authorize_reference_dispositions_repair.zig").Action,
            .signals => @import("../actions/reference/authorize_reference_signals_repair.zig").Action,
            .conflicts => @import("../actions/reference/authorize_reference_conflicts_repair.zig").Action,
        };
        pub const outcomes = @import("reference_reconciliation_repair_workflow.zig").outcomes;
        allocator: std.mem.Allocator,
        action: Action = .{},
        pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
            const self = context.?;
            const prior = try extraction.read(&input.step.data, rec.parsed_schema, .reconciliation_parsed);
            const schema = switch (stage) {
                .summary => rec.summary_schema,
                .dispositions => rec.dispositions_schema,
                .signals => rec.signals_schema,
                .conflicts => rec.conflicts_schema,
            };
            const rejected = try extraction.read(&input.step.data, schema, .reconciliation_rejected);
            const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
            errdefer owned.destroy(owner);
            const decision = self.action.execute(owner.arena.allocator(), prior.payload().reconciliation_parsed, try rec.textContext(&input.step.data), rejected.payload().reconciliation_rejected) catch return error.OperationExecutionFailed;
            owner.payload = switch (decision) {
                .model => |value| .{ .authorized = .{ .authorization = value, .replacement = .pending } },
                .automatic => |value| .{ .authorized = .{ .authorization = value.authorization, .replacement = .{ .automatic = value.replacement } } },
                .blocked => |reason| result: {
                    var diagnostic_value = rejected.payload().reconciliation_rejected;
                    diagnostic_value.blocked = reason;
                    break :result .{ .blocked = .{ .reason = reason, .rejection = diagnostic_value } };
                },
            };
            const permit = if (owner.payload == .authorized) owner.payload.authorized.authorization.retry orelse return error.OperationExecutionFailed else null;
            var result = owned.publish(self.allocator, state_schema, owner, switch (decision) {
                .model => .ok,
                .automatic => .more,
                .blocked => .blocked,
            }) catch return error.OperationExecutionFailed;
            for (Action.contract.invalidates) |key| result.delta.data_invalidations.insert(key);
            if (permit) |selected| result.delta.repair_transition = .{ .authorized = selected };
            return result;
        }
    };
}
pub const BuildInput = struct {
    pub const Action = @import("../actions/reference/build_reference_reconciliation_repair_input.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const authorized = readAuthorization(&input.step.data) catch return error.OperationExecutionFailed;
        const prior = try extraction.read(&input.step.data, rec.parsed_schema, .reconciliation_parsed);
        const packet = self.action.execute(self.allocator, prior.payload().reconciliation_parsed, try rec.textContext(&input.step.data), authorized) catch return error.OperationExecutionFailed;
        return @import("model_request_workflow.zig").publishPacket(self.allocator, packet);
    }
};
pub const Parse = struct {
    pub const Action = @import("../actions/reference/parse_reference_reconciliation_repair.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const state = owned.read(&input.step.data, state_schema, .authorized) catch return error.OperationExecutionFailed;
        if (state.replacement != .pending) return error.OperationExecutionFailed;
        const packet = values.read(&input.step.data, @import("model_request_workflow.zig").packet_schema, @import("../domain/model_input_packet.zig").Packet) catch return error.OperationExecutionFailed;
        const candidate = try @import("model_candidate_handoff.zig").read(&input.step.data);
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .authorized = .{ .authorization = state.authorization, .replacement = .{ .model = .{ .value = self.action.execute(owner.arena.allocator(), state.authorization, packet, candidate.body) catch return error.OperationExecutionFailed, .origin = candidate.origin } } } };
        var delta: pipeline.NodeDelta = .{};
        delta.data_replacements[@intFromEnum(state_schema.key)] = values.adopt(self.allocator, state_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch return error.OperationExecutionFailed;
        return .{ .outcome = .ok, .delta = delta };
    }
};
pub const Merge = struct {
    pub const repair_role: @import("../domain/workflow_retry.zig").Role = .merge;
    pub const Action = @import("../actions/reference/merge_reference_reconciliation_repair.zig").Action;
    pub const parameters = [_]@import("../domain/workflow_operation.zig").ParameterDescriptor{.{ .id = "retry-limit", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 0, .integer_max = std.math.maxInt(u32) }};
    pub const retry_limit: @import("../domain/workflow_operation.zig").RetryLimitDescriptor = .{ .maximum = std.math.maxInt(u32), .scope = .repair };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const state = owned.read(&input.step.data, state_schema, .authorized) catch return error.OperationExecutionFailed;
        const prior = try extraction.read(&input.step.data, rec.parsed_schema, .reconciliation_parsed);
        const owner = reference.create(self.allocator, prior) catch return error.OperationExecutionFailed;
        errdefer reference.destroy(owner);
        const replacement: ?repair.Replacement = switch (state.replacement) {
            .pending => return error.OperationExecutionFailed,
            .automatic => |value| value,
            .model => |value| value.value,
        };
        const origin: ?Origin = switch (state.replacement) {
            .pending => unreachable,
            .automatic => null,
            .model => |value| value.origin,
        };
        owner.payload = .{ .reconciliation_parsed = self.action.execute(owner.arena.allocator(), prior.payload().reconciliation_parsed, try rec.textContext(&input.step.data), state.authorization, replacement, origin) catch return error.OperationExecutionFailed };
        var delta: pipeline.NodeDelta = .{};
        delta.repair_transition = .{ .merged = .{ .permit = state.authorization.retry orelse return error.OperationExecutionFailed, .revision_after = owner.payload.reconciliation_parsed.source.revision } };
        delta.data_replacements[@intFromEnum(rec.parsed_schema.key)] = values.adopt(self.allocator, rec.parsed_schema, reference.Value, reference.Owner, owner, reference.view, reference.destroy, null) catch return error.OperationExecutionFailed;
        for (Action.contract.invalidates) |key| delta.data_invalidations.insert(key);
        return .{ .outcome = .ok, .delta = delta };
    }
};
pub fn diagnostic(view: *const data.View) values.Error!?r.diagnostic.Rejection {
    if (!view.contains(state_schema.key)) return null;
    return switch (owned.payload(try values.read(view, state_schema, owned.Value)).*) {
        .authorized => |value| value.authorization.rule.rejection,
        .blocked => |value| value.rejection,
        .rejected => null,
    };
}

pub fn readAuthorization(view: *const data.View) (values.Error || error{InvalidCandidatePayload})!repair.Authorization {
    return (try owned.read(view, state_schema, .authorized)).authorization;
}
