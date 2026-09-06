const std = @import("std");
const r = @import("../domain/reference_reconciliation.zig");
const owned = @import("../domain/reference_candidate_value.zig");
const values = @import("pipeline_values.zig");
const data = @import("../domain/pipeline_data.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const extraction = @import("reference_extraction_workflow.zig");
const validation = @import("../domain/reference_reconciliation_validation.zig");

pub const items_schema = values.schema(.reference_reconciliation_items, owned.Value, 1, null);
pub const layout_schema = values.schema(.reference_reconciliation_layout, owned.Value, 1, null);
pub const plan_schema = values.schema(.reference_reconciliation_plan, owned.Value, 1, null);
pub const progress_schema = values.schema(.reference_reconciliation_progress, owned.Value, 1, null).captured();
pub const input_schema = values.schema(.reference_reconciliation_input, owned.Value, 1, null).captured();
pub const raw_schema = values.schema(.raw_reference_reconciliation, owned.Value, 1, null).captured();
pub const parsed_schema = values.schema(.parsed_reference_reconciliation, owned.Value, 1, null).captured();
pub const summary_schema = values.schema(.validated_reference_summary, owned.Value, 1, null).captured();
pub const summary_ids_schema = values.schema(.reference_summary_identities, owned.Value, 1, null).captured();
pub const dispositions_schema = values.schema(.validated_reference_dispositions, owned.Value, 1, null);
pub const signals_schema = values.schema(.validated_reference_signals, owned.Value, 1, null);
pub const conflicts_schema = values.schema(.validated_reference_conflicts, owned.Value, 1, null);
pub const identities_schema = values.schema(.reference_reconciliation_identities, owned.Value, 1, null);
pub const records_schema = values.schema(.reference_reconciliation_records, owned.Value, 1, null);
pub const accounted_schema = values.schema(.accounted_reference_reconciliation, owned.Value, 1, null);
pub const schemas = [_]data.Schema{ items_schema, layout_schema, plan_schema, progress_schema, input_schema, raw_schema, parsed_schema, summary_schema, summary_ids_schema, dispositions_schema, signals_schema, conflicts_schema, identities_schema, records_schema, accounted_schema };

pub const BuildItems = struct {
    pub const Action = @import("../actions/reference/build_reference_reconciliation_items.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const prior = try extraction.read(&input.step.data, extraction.accounted_schema, .accounted);
        const source = values.read(&input.step.data, @import("reference_evidence_workflow.zig").inputs_schema, r.evidence.Inputs) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, prior) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .reconciliation_items = self.action.execute(owner.arena.allocator(), source.*, prior.payload().accounted) catch return error.OperationExecutionFailed };
        return extraction.publish(self.allocator, items_schema, owner, .ok);
    }
};
pub const Partition = struct {
    pub const Action = @import("../actions/reference/partition_reference_reconciliation_items.zig").Action;
    pub const parameters = [_]@import("../domain/workflow_operation.zig").ParameterDescriptor{.{ .id = "group-size", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 2, .integer_max = std.math.maxInt(u32) }};
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const prior = try extraction.read(&input.step.data, items_schema, .reconciliation_items);
        var size: ?u32 = null;
        for (input.step.step.parameters) |parameter| {
            if (std.mem.eql(u8, parameter.id.bytes, "group-size") and parameter.value == .integer) size = std.math.cast(u32, parameter.value.integer);
        }
        const owner = owned.create(self.allocator, prior) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .reconciliation_layout = self.action.execute(owner.arena.allocator(), prior.payload().reconciliation_items, size orelse return error.OperationExecutionFailed) catch return error.OperationExecutionFailed };
        return extraction.publish(self.allocator, layout_schema, owner, .ok);
    }
};

// Closed compile-time bindings: each invokes exactly one named action. These
// share only ownership plumbing, not a workflow graph, dispatcher or capability.
pub const AssignPartitions = Unary(@import("../actions/reference/assign_reference_reconciliation_partitions.zig").Action, layout_schema, .reconciliation_layout, plan_schema, .reconciliation_plan);
pub const ValidatePartitions = Unary(@import("../actions/reference/validate_reference_reconciliation_partitions.zig").Action, plan_schema, .reconciliation_plan, progress_schema, .reconciliation_progress);
pub const BuildInput = Unary(@import("../actions/reference/build_reference_reconciliation_input.zig").Action, progress_schema, .reconciliation_progress, input_schema, .reconciliation_input);
pub const Parse = Unary(@import("../actions/reference/parse_reference_reconciliation_result.zig").Action, raw_schema, .reconciliation_raw, parsed_schema, .reconciliation_parsed);
pub const ValidateSummary = TextStage(@import("../actions/reference/validate_reference_reconciliation_summary.zig").Action, parsed_schema, .reconciliation_parsed, summary_schema, .reconciliation_summary);
pub const AssignSummary = Unary(@import("../actions/reference/assign_reference_summary_identities.zig").Action, summary_schema, .reconciliation_summary, summary_ids_schema, .reconciliation_summary_ids);
pub const ValidateDispositions = Unary(@import("../actions/reference/validate_reference_claim_dispositions.zig").Action, parsed_schema, .reconciliation_parsed, dispositions_schema, .reconciliation_dispositions);
pub const ValidateSignals = TextStage(@import("../actions/reference/validate_reference_signal_proposals.zig").Action, dispositions_schema, .reconciliation_dispositions, signals_schema, .reconciliation_signals);
pub const ValidateConflicts = TextStage(@import("../actions/reference/validate_reference_conflict_proposals.zig").Action, signals_schema, .reconciliation_signals, conflicts_schema, .reconciliation_conflicts);
pub const AssignRecords = Unary(@import("../actions/reference/assign_reference_reconciliation_identities.zig").Action, conflicts_schema, .reconciliation_conflicts, identities_schema, .reconciliation_record_ids);
pub const BuildRecords = Unary(@import("../actions/reference/build_reference_reconciliation_records.zig").Action, identities_schema, .reconciliation_record_ids, records_schema, .reconciliation_records);

pub const BuildSummary = struct {
    pub const Action = @import("../actions/reference/build_reference_reconciliation_summary.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const prior = try extraction.read(&input.step.data, summary_ids_schema, .reconciliation_summary_ids);
        const owner = owned.create(self.allocator, prior) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .reconciliation_progress = self.action.execute(owner.arena.allocator(), prior.payload().reconciliation_summary_ids) catch return error.OperationExecutionFailed };
        var delta: @import("../domain/pipeline.zig").NodeDelta = .{};
        delta.data_replacements[@intFromEnum(progress_schema.key)] = values.adopt(self.allocator, progress_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch return error.OperationExecutionFailed;
        for (Action.contract.invalidates) |key| delta.data_invalidations.insert(key);
        return .{ .outcome = .ok, .delta = delta };
    }
};
pub const Account = struct {
    pub const Action = @import("../actions/reference/validate_reference_reconciliation_completeness.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .blocked, .failed };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const prior = try extraction.read(&input.step.data, records_schema, .reconciliation_records);
        const owner = owned.create(self.allocator, prior) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        const result = self.action.execute(owner.arena.allocator(), prior.payload().reconciliation_records) catch return error.OperationExecutionFailed;
        owner.payload = .{ .reconciliation_accounted = result };
        return extraction.publish(self.allocator, accounted_schema, owner, if (result.outcome == .complete) .ok else .blocked);
    }
};

const Tag = std.meta.Tag(owned.Payload);
fn Unary(comptime A: type, comptime from: data.Schema, comptime from_tag: Tag, comptime to: data.Schema, comptime to_tag: Tag) type {
    return struct {
        pub const Action = A;
        allocator: std.mem.Allocator,
        action: Action = .{},
        pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
            const self = context.?;
            const prior = try extraction.read(&input.step.data, from, from_tag);
            const owner = owned.create(self.allocator, prior) catch return error.OperationExecutionFailed;
            errdefer owned.destroy(owner);
            owner.payload = @unionInit(owned.Payload, @tagName(to_tag), self.action.execute(owner.arena.allocator(), @field(prior.payload(), @tagName(from_tag))) catch return error.OperationExecutionFailed);
            return extraction.publish(self.allocator, to, owner, .ok);
        }
    };
}
fn TextStage(comptime A: type, comptime from: data.Schema, comptime from_tag: Tag, comptime to: data.Schema, comptime to_tag: Tag) type {
    return struct {
        pub const Action = A;
        allocator: std.mem.Allocator,
        action: Action,
        pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
            const self = context.?;
            const prior = try extraction.read(&input.step.data, from, from_tag);
            const scope = try textContext(&input.step.data);
            const owner = owned.create(self.allocator, prior) catch return error.OperationExecutionFailed;
            errdefer owned.destroy(owner);
            owner.payload = @unionInit(owned.Payload, @tagName(to_tag), self.action.execute(owner.arena.allocator(), @field(prior.payload(), @tagName(from_tag)), scope) catch return error.OperationExecutionFailed);
            return extraction.publish(self.allocator, to, owner, .ok);
        }
    };
}
fn textContext(view: *const data.View) operations.Error!validation.TextContext {
    const inputs = values.read(view, @import("reference_evidence_workflow.zig").inputs_schema, r.evidence.Inputs) catch return error.OperationExecutionFailed;
    const registry = values.read(view, @import("passive_literal_workflow.zig").registry_schema, @import("../domain/passive_literals.zig").Registry) catch return error.OperationExecutionFailed;
    const current = values.read(view, @import("toolchain_workflow_values.zig").valid, @import("../domain/toolchain_safety.zig").ValidToolchain) catch return error.OperationExecutionFailed;
    return .{ .inputs = inputs.*, .registry = registry.*, .current = current };
}

/// A scripted or future provider producer attaches bytes to the exact engine
/// input. Models cannot choose a partition, current state, or canonical identity.
pub fn capture(allocator: std.mem.Allocator, input: *const owned.Value, bytes: []const u8) operations.Error!*owned.Owner {
    if (input.payload().* != .reconciliation_input) return error.OperationExecutionFailed;
    const owner = owned.create(allocator, input) catch return error.OperationExecutionFailed;
    errdefer owned.destroy(owner);
    owner.payload = .{ .reconciliation_raw = .{ .input = input.payload().reconciliation_input, .bytes = owner.arena.allocator().dupe(u8, bytes) catch return error.OperationExecutionFailed } };
    return owner;
}
