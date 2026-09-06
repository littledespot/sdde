//! Native bindings only. YAML owns model calls, branching, gates and retries.
const std = @import("std");
const data = @import("../domain/pipeline_data.zig");
const pipeline = @import("../domain/pipeline.zig");
const g = @import("../domain/specification_generation.zig");
const session = @import("../domain/specification_session.zig");
const p = @import("../domain/specification_provenance.zig");
const owned = @import("specification_values.zig").storage;
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const requests = @import("model_request_workflow.zig");
pub const session_schema = values.schema(.specification_generation_session, owned.Value, 1, null).captured();
pub const raw_schema = values.schema(.raw_specification_unit, owned.Value, 1, null).captured();
pub const parsed_schema = values.schema(.parsed_specification_unit, owned.Value, 1, null).captured();
pub const checked_schema = values.schema(.validated_specification_unit, owned.Value, 1, null).captured();
pub const ids_schema = values.schema(.specification_id_ledger, @import("../domain/specification_identity.zig").Ledger, 1, @sizeOf(@import("../domain/specification_identity.zig").Ledger));
pub const coverage_schema = values.schema(.specification_coverage, owned.Value, 1, null);
pub const schemas = [_]data.Schema{ session_schema, raw_schema, parsed_schema, checked_schema, ids_schema, coverage_schema };

pub const Initialize = struct {
    pub const Action = @import("../actions/specification/initialize_specification_generation.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const feature = values.read(&input.step.data, @import("feature_directory_workflow.zig").selector, @import("../domain/feature_directory.zig").Selector) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .session = self.action.execute(feature.feature_id, try readContext(&input.step.data)) catch return error.OperationExecutionFailed };
        return publish(self.allocator, session_schema, owner, .ok);
    }
};
pub const Check = struct {
    pub const Action = @import("../actions/specification/check_specification_generation_progress.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .failed };
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        return .{ .outcome = context.?.action.execute(try readSession(&input.step.data)), .delta = .{} };
    }
};
pub const BuildInput = struct {
    pub const Action = @import("../actions/specification/build_specification_model_input.zig").Action;
    pub const gates = [_][]const u8{"required-authority@1"};
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const packet = self.action.execute(self.allocator, try readSession(&input.step.data), try readContext(&input.step.data)) catch return error.OperationExecutionFailed;
        return requests.publishPacket(self.allocator, packet);
    }
};
pub const Collect = struct {
    pub const Action = @import("../actions/specification/collect_specification_model_result.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const packet = values.read(&input.step.data, requests.packet_schema, @import("../domain/model_input_packet.zig").Packet) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .raw = self.action.execute(owner.arena.allocator(), try readSession(&input.step.data), packet, try @import("model_candidate_handoff.zig").body(&input.step.data)) catch return error.OperationExecutionFailed };
        return publish(self.allocator, raw_schema, owner, .ok);
    }
};
pub const Parse = struct {
    pub const Action = @import("../actions/specification/parse_specification_unit.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .invalid, .failed };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = owned.read(&input.step.data, raw_schema, .raw) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .parsed = self.action.execute(owner.arena.allocator(), source) catch |err| return reject(self.allocator, parsed_schema, owner, err) };
        return publish(self.allocator, parsed_schema, owner, .ok);
    }
};
pub const Validate = struct {
    pub const Action = @import("../actions/specification/validate_specification_unit.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .invalid, .needs_user, .failed };
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const proposed = owned.read(&input.step.data, parsed_schema, .parsed) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        const checked = self.action.execute(owner.arena.allocator(), try readSession(&input.step.data), try readContext(&input.step.data), proposed) catch |err| return reject(self.allocator, checked_schema, owner, err);
        owner.payload = .{ .checked = checked };
        return publish(self.allocator, checked_schema, owner, if (checked.response == .clarification) .needs_user else .ok);
    }
};
pub const Advance = struct {
    pub const Action = @import("../actions/specification/advance_specification_generation.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const checked = owned.read(&input.step.data, checked_schema, .checked) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .session = self.action.execute(try readSession(&input.step.data), checked) catch return error.OperationExecutionFailed };
        var delta: pipeline.NodeDelta = .{};
        delta.data_replacements[@intFromEnum(session_schema.key)] = values.adopt(self.allocator, session_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch return error.OperationExecutionFailed;
        for (Action.contract.invalidates) |key| delta.data_invalidations.insert(key);
        return .{ .outcome = .ok, .delta = delta };
    }
};
pub const Assemble = struct {
    pub const Action = @import("../actions/specification/assemble_specification_content.zig").Action;
    allocator: std.mem.Allocator,
    action: Action,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const authority = @import("required_authority_values.zig");
        const owner = authority.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer authority.destroy(owner);
        const assigned = self.action.execute(owner.arena.allocator(), try readSession(&input.step.data), try readContext(&input.step.data)) catch return error.OperationExecutionFailed;
        owner.payload = .{ .content = assigned.content };
        var delta: pipeline.NodeDelta = .{};
        const ids = values.create(self.allocator, ids_schema, @import("../domain/specification_identity.zig").Ledger, assigned.ledger) catch return error.OperationExecutionFailed;
        errdefer values.destroy(ids);
        const schema = @import("required_authority_workflow.zig").content_schema;
        delta.data_writes[@intFromEnum(schema.key)] = values.adopt(self.allocator, schema, authority.Value, authority.Owner, owner, authority.view, authority.destroy, null) catch return error.OperationExecutionFailed;
        delta.data_writes[@intFromEnum(ids_schema.key)] = ids;
        return .{ .outcome = .ok, .delta = delta };
    }
};
pub const ValidateCoverage = struct {
    pub const Action = @import("../actions/specification/validate_specification_coverage.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .invalid, .failed };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = try readSession(&input.step.data);
        const references = try @import("reference_extraction_workflow.zig").read(&input.step.data, @import("reference_reconciliation_workflow.zig").accounted_schema, .reconciliation_accounted);
        const content = @import("required_authority_values.zig").read(&input.step.data, @import("required_authority_workflow.zig").content_schema, .content) catch return error.OperationExecutionFailed;
        const owner = owned.create(self.allocator, input.step.data) catch return error.OperationExecutionFailed;
        errdefer owned.destroy(owner);
        owner.payload = .{ .coverage = self.action.execute(owner.arena.allocator(), references.payload().reconciliation_accounted, (current.units[0] orelse return error.OperationExecutionFailed).response.content.brief, content) catch |err| switch (err) {
            error.OutOfMemory => return error.OperationExecutionFailed,
            error.InvalidSpecificationCoverage => return publish(self.allocator, coverage_schema, owner, .invalid),
        } };
        return publish(self.allocator, coverage_schema, owner, .ok);
    }
};

pub fn readSession(view: *const data.View) operations.Error!session.Session {
    return owned.read(view, session_schema, .session) catch error.OperationExecutionFailed;
}
pub fn readContext(view: *const data.View) operations.Error!p.Context {
    const references = @import("reference_extraction_workflow.zig").read(view, @import("reference_reconciliation_workflow.zig").accounted_schema, .reconciliation_accounted) catch return error.OperationExecutionFailed;
    return .{
        .references = references.payload().reconciliation_accounted,
        .inputs = (values.read(view, @import("reference_evidence_workflow.zig").inputs_schema, @import("../domain/reference_evidence.zig").Inputs) catch return error.OperationExecutionFailed).*,
        .registry = (values.read(view, @import("passive_literal_workflow.zig").registry_schema, @import("../domain/passive_literals.zig").Registry) catch return error.OperationExecutionFailed).*,
        .current = values.read(view, @import("toolchain_workflow_values.zig").valid, @import("../domain/toolchain_safety.zig").ValidToolchain) catch return error.OperationExecutionFailed,
    };
}
fn publish(allocator: std.mem.Allocator, schema: data.Schema, owner: *owned.Owner, outcome: @import("../domain/workflow.zig").OutcomeTag) operations.Error!execution.Candidate {
    return owned.publish(allocator, schema, owner, outcome) catch error.OperationExecutionFailed;
}
fn reject(allocator: std.mem.Allocator, schema: data.Schema, owner: *owned.Owner, err: g.Error) operations.Error!execution.Candidate {
    if (err == error.OutOfMemory) return error.OperationExecutionFailed;
    owner.payload = .{ .rejected = .invalid_unit };
    return publish(allocator, schema, owner, .invalid);
}
