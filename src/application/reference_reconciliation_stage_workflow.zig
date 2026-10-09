//! Narrow bindings for native phase facts; sequencing is owned by YAML.
const std = @import("std");
const r = @import("../domain/reference_reconciliation.zig");
const stage = @import("../domain/reference_reconciliation_stage.zig");
const values = @import("pipeline_values.zig");
const extraction = @import("reference_extraction_workflow.zig");
const reconciliation = @import("reference_reconciliation_workflow.zig");
const owned = @import("../domain/reference_candidate_value.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
fn schema(comptime phase: stage.Stage) @import("../domain/pipeline_data.zig").Schema {
    return switch (phase) {
        .dispositions => reconciliation.input_schema,
        .signals => reconciliation.dispositions_schema,
        .roles => reconciliation.signals_schema,
        .conflicts => reconciliation.roles_schema,
    };
}
fn tag(comptime phase: stage.Stage) std.meta.Tag(owned.Payload) {
    return switch (phase) {
        .dispositions => .reconciliation_input,
        .signals => .reconciliation_dispositions,
        .roles => .reconciliation_signals,
        .conflicts => .reconciliation_roles,
    };
}
pub fn Build(comptime phase: stage.Stage) type {
    return struct {
        pub const Action = switch (phase) {
            .dispositions => @import("../actions/reference/build_reference_dispositions_assignment.zig").Action,
            .signals => @import("../actions/reference/build_reference_signals_assignment.zig").Action,
            .roles => @import("../actions/reference/build_reference_roles_assignment.zig").Action,
            .conflicts => @import("../actions/reference/build_reference_conflicts_assignment.zig").Action,
        };
        allocator: std.mem.Allocator,
        action: Action = .{},
        pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
            const self = context.?;
            const prior = try extraction.read(&input.step.data, schema(phase), tag(phase));
            const source = values.read(&input.step.data, @import("reference_evidence_workflow.zig").inputs_schema, r.evidence.Inputs) catch |operation_error| return operation_error;
            const registry = values.read(&input.step.data, @import("passive_literal_workflow.zig").registry_schema, @import("../domain/passive_literals.zig").Registry) catch |operation_error| return operation_error;
            const packet = self.action.execute(self.allocator, @unionInit(stage.Prior, @tagName(phase), @field(prior.payload(), @tagName(tag(phase)))), source.*, registry.*) catch |operation_error| return operation_error;
            return @import("model_request_workflow.zig").publishPacket(self.allocator, packet);
        }
    };
}
pub fn Collect(comptime phase: stage.Stage) type {
    return struct {
        pub const Action = switch (phase) {
            .dispositions => @import("../actions/reference/collect_reference_dispositions_candidate.zig").Action,
            .signals => @import("../actions/reference/collect_reference_signals_candidate.zig").Action,
            .roles => @import("../actions/reference/collect_reference_roles_candidate.zig").Action,
            .conflicts => @import("../actions/reference/collect_reference_conflicts_candidate.zig").Action,
        };
        allocator: std.mem.Allocator,
        action: Action = .{},
        pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
            const self = context.?;
            const prior = try extraction.read(&input.step.data, schema(phase), tag(phase));
            const packet = values.read(&input.step.data, @import("model_request_workflow.zig").packet_schema, @import("../domain/model_input_packet.zig").Packet) catch |operation_error| return operation_error;
            const accepted = (try @import("model_candidate_handoff.zig").readAccepted(&input.step.data)).candidate;
            const owner = owned.create(self.allocator, prior) catch |operation_error| return operation_error;
            errdefer owned.destroy(owner);
            owner.payload = .{ .reconciliation_parsed = self.action.execute(owner.arena.allocator(), @unionInit(stage.Prior, @tagName(phase), @field(prior.payload(), @tagName(tag(phase)))), packet, accepted.body, accepted.origin) catch |operation_error| return operation_error };
            var result = try extraction.publish(self.allocator, reconciliation.parsed_schema, owner, .ok);
            if (phase != .dispositions) {
                result.delta.data_replacements[@intFromEnum(reconciliation.parsed_schema.key)] = result.delta.data_writes[@intFromEnum(reconciliation.parsed_schema.key)];
                result.delta.data_writes[@intFromEnum(reconciliation.parsed_schema.key)] = null;
            }
            for (Action.contract.invalidates) |key| result.delta.data_invalidations.insert(key);
            return result;
        }
    };
}
pub const Check = struct {
    pub const Action = @import("../actions/reference/check_reference_reconciliation_phase.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .failed };
    pub const parameters = [_]@import("../domain/workflow_operation.zig").ParameterDescriptor{.{ .id = "phase", .kind = .enumeration, .required = true, .allowed_values = &.{ "dispositions", "signals", "roles", "complete" }, .workflow_definition_safe = true }};
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const prior = try extraction.read(&input.step.data, reconciliation.parsed_schema, .reconciliation_parsed);
        for (input.step.step.parameters) |parameter| if (std.mem.eql(u8, parameter.id.bytes, "phase") and parameter.value == .enumeration) {
            const expected = std.meta.stringToEnum(r.Phase, parameter.value.enumeration) orelse return error.OperationExecutionFailed;
            return .{ .outcome = context.?.action.execute(prior.payload().reconciliation_parsed, expected), .delta = .{} };
        };
        return error.OperationExecutionFailed;
    }
};
