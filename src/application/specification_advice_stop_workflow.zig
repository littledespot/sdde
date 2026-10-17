const std = @import("std");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const support = @import("specification_support_workflow.zig");
const values = @import("required_authority_values.zig");
const authority = @import("../domain/required_authority.zig");
const native_stop = @import("advisory_request_completion_workflow.zig");
const stop_contract = @import("../domain/specification_advice_stop.zig");
const pipeline_values = @import("pipeline_values.zig");
const data = @import("../domain/pipeline_data.zig");
const requests = @import("model_request_workflow.zig");
const retry = @import("../domain/workflow_retry.zig");

pub const Stop = StopTypeFor(.physical);
pub const StopProtocol = StopTypeFor(.protocol);
pub const StopRepair = StopTypeFor(.physical_repair);
pub const StopProtocolRepair = StopTypeFor(.protocol_repair);

fn StopTypeFor(comptime transport_scope: stop_contract.Scope) type {
    return struct {
        pub const Action = switch (transport_scope) {
            .physical => @import("../actions/specification/stop_specification_advice.zig").Action,
            .protocol => @import("../actions/specification/stop_specification_protocol_advice.zig").Action,
            .physical_repair => @import("../actions/specification/stop_specification_repair_advice.zig").Action,
            .protocol_repair => @import("../actions/specification/stop_specification_protocol_repair_advice.zig").Action,
        };
        pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .advisory_completion = .{ .kind = .candidate, .subject = .specification_support_review, .evidence = .specification_support_review, .result = .specification_support_review } };
        pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .failed };
        pub const repair_role: @import("../domain/workflow_retry.zig").Role = .abandon_advice;
        allocator: std.mem.Allocator,
        action: Action = .{},

        pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
            const self = context.?;
            try validateTransport(transport_scope.isProtocol(), &input.step.data);
            const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
            const current = try support.progress(&input.step.data);
            const packet = request.packet() orelse return error.OperationExecutionFailed;
            if (transport_scope.isRepair() != (packet.repairPermit() != null)) return error.OperationExecutionFailed;
            inline for (.{ @import("../domain/specification_support.zig").Purpose.source, .principles }) |selected| if (support.purpose(current) == selected) {
                const permit = try currentPermit(selected, &input.step.data, request);
                if (permit) |expected| {
                    const active = input.step.repair_permit orelse return error.OperationExecutionFailed;
                    if (!std.meta.eql(active, expected)) return error.OperationExecutionFailed;
                } else if (input.step.repair_permit != null) return error.OperationExecutionFailed;
            };
            const facts = native_stop.read(&input.step.data) catch |err| switch (err) {
                error.OperationExecutionFailed => {
                    // This subgraph also serves required readiness. Preserve its
                    // failed request and unchanged review without claiming advice.
                    const owner = try values.create(self.allocator, input.step.data);
                    support.retain(owner, current);
                    var candidate = try support.publishProgress(self.allocator, owner, .failed);
                    for (Action.contract.invalidates) |key| candidate.delta.data_invalidations.insert(key);
                    return candidate;
                },
                else => return err,
            };
            const source = try support.inputs(&input.step.data, current);
            const scope = facts.request.packet().?.advisoryAssessment() orelse return error.OperationExecutionFailed;
            const context_value = try @import("specification_workflow.zig").readContext(&input.step.data);
            if (authority.assessmentPolicy(source.projection) != .advisory or scope.candidate_revision != source.revision or
                !std.mem.eql(u8, source.feature.bytes, scope.feature.bytes) or !context_value.inputs.corpus.state_id.eql(scope.reference_state)) return error.OperationExecutionFailed;
            const owner = try values.create(self.allocator, input.step.data);
            inline for (.{ @import("../domain/specification_support.zig").Purpose.source, .principles }) |selected| if (support.purpose(current) == selected) {
                const prior = support.prior(selected, current) catch |err| {
                    values.destroy(owner);
                    return err;
                };
                if (!(@import("../domain/specification_support.zig").Contract(selected).matchesAdvicePacket(owner.arena.allocator(), source, context_value, prior, facts.request.packet().?) catch |err| {
                    values.destroy(owner);
                    return err;
                })) {
                    values.destroy(owner);
                    return error.OperationExecutionFailed;
                }
                const stopped = self.action.execute(selected, owner.arena.allocator(), source, context_value, prior, facts.reason, facts.origin) catch |err| {
                    values.destroy(owner);
                    return err;
                };
                var candidate = try support.publish(selected, self.allocator, owner, current, stopped);
                errdefer for (candidate.delta.data_replacements) |value| if (value) |allocation| pipeline_values.destroy(allocation);
                if (candidate.outcome != .ok) return error.OperationExecutionFailed;
                for (Action.contract.invalidates) |key| candidate.delta.data_invalidations.insert(key);
                if (facts.request.packet().?.repairPermit()) |permit| candidate.delta.repair_transition = .{ .abandoned_advice = permit };
                return candidate;
            };
            values.destroy(owner);
            return error.OperationExecutionFailed;
        }
    };
}

fn protocolReceipt(view: *const data.View) operations.Error!bool {
    const decision = try pipeline_values.read(view, @import("workflow_model_accounting.zig").schema, @import("../domain/model_attempt_decision.zig").Decision);
    return decision.outcome() == .advisory_stopped;
}

fn validateTransport(protocol: bool, view: *const data.View) operations.Error!void {
    if (try protocolReceipt(view) != protocol) return error.OperationExecutionFailed;
    if (!protocol) _ = try @import("provider_observation_workflow.zig").readCurrent(view);
}

fn currentPermit(comptime selected: @import("../domain/specification_support.zig").Purpose, view: *const data.View, request: *const @import("../domain/model_request_handoff.zig").Request) operations.Error!?retry.Permit {
    const packet = request.packet() orelse return error.OperationExecutionFailed;
    const permit = packet.repairPermit() orelse return null;
    const state = try values.read(view, @import("specification_support_repair_workflow.zig").schema, if (selected == .source) .support_repair else .principle_support_repair);
    const authorized = state.authorization.retry orelse return error.OperationExecutionFailed;
    if (!std.meta.eql(authorized, permit)) return error.OperationExecutionFailed;
    return permit;
}

/// The outcome owner verifies this exact native result before removing failed
/// advisory references. A successful operation tag alone grants no authority.
pub fn validateCompletion(allocator: std.mem.Allocator, before: *const @import("../domain/pipeline_data.zig").View, after: *const @import("../domain/pipeline_data.zig").View) operations.Error!native_stop.Facts {
    const facts = try native_stop.read(before);
    try validateTransport(try protocolReceipt(before), before);
    const previous = try support.progress(before);
    const next = try support.progress(after);
    if (support.purpose(previous) != support.purpose(next)) return error.OperationExecutionFailed;
    inline for (.{ @import("../domain/specification_support.zig").Purpose.source, .principles }) |selected| if (support.purpose(next) == selected) {
        if (try currentPermit(selected, before, facts.request)) |_| if (after.contains(.specification_support_repair)) return error.OperationExecutionFailed;
        const value = try support.collection(selected, next);
        if (value != .accepted) return error.OperationExecutionFailed;
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const source = try support.inputs(before, previous);
        const context_value = try @import("specification_workflow.zig").readContext(before);
        const prior = try support.prior(selected, previous);
        const contract = @import("../domain/specification_support.zig").Contract(selected);
        if (!try contract.matchesAdvicePacket(a, source, context_value, prior, facts.request.packet().?)) return error.OperationExecutionFailed;
        const expected = try contract.stop(a, source, context_value, prior, facts.reason, facts.origin);
        if (!std.mem.eql(u8, try @import("../domain/canonical_json.zig").encode(contract.Collection, a, expected), try @import("../domain/canonical_json.zig").encode(contract.Collection, a, value))) return error.OperationExecutionFailed;
        const stop = value.accepted.inputs.advice_stop orelse return error.OperationExecutionFailed;
        const scope = facts.request.packet().?.advisoryAssessment() orelse return error.OperationExecutionFailed;
        if (stop.reason != facts.reason or stop.candidate_revision != scope.candidate_revision or !std.meta.eql(stop.origin, facts.origin)) return error.OperationExecutionFailed;
        return facts;
    };
    return error.OperationExecutionFailed;
}

pub fn validateUnchangedFailure(allocator: std.mem.Allocator, before: *const @import("../domain/pipeline_data.zig").View, after: *const @import("../domain/pipeline_data.zig").View) operations.Error!void {
    if (native_stop.read(before)) |_| return error.OperationExecutionFailed else |err| switch (err) {
        error.OperationExecutionFailed => {},
        else => return err,
    }
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const Progress = @import("../domain/specification_review.zig").Progress;
    if (!std.mem.eql(u8, try @import("../domain/canonical_json.zig").encode(Progress, arena.allocator(), try support.progress(before)), try @import("../domain/canonical_json.zig").encode(Progress, arena.allocator(), try support.progress(after)))) return error.OperationExecutionFailed;
}
