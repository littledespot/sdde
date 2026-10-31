const std = @import("std");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const pipeline = @import("../domain/pipeline.zig");
const owned = @import("required_authority_values.zig");
const authority = @import("required_authority_workflow.zig");
const spec = @import("specification_workflow.zig");
const requests = @import("model_request_workflow.zig");
const values = @import("pipeline_values.zig");
pub const schema = values.schema(.specification_support_review, owned.Value, 1, null).captured();
// Historical receipts are execution-local bookkeeping, never current authority.
// Only complete native re-admission can produce a current review from them.
pub const history_schema = values.schema(.specification_review_history, owned.Value, 1, null).executionControl();
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{ schema, history_schema };
const retention = @import("../domain/specification_review_retention.zig");
const review = @import("../domain/specification_review.zig");
const purpose_contract = @import("../domain/specification_support.zig");
const a = @import("../domain/required_authority.zig");

pub fn progress(view: *const @import("../domain/pipeline_data.zig").View) operations.Error!review.Progress {
    const current = owned.payload(values.read(view, schema, owned.Value) catch |operation_error| return operation_error);
    return switch (current.*) {
        .support_initial => .initial,
        .support => |value| .{ .source = value },
        .principle_pending => |value| .{ .pending = value },
        .principle_support => |value| .{ .principles = value },
        else => error.OperationExecutionFailed,
    };
}
pub fn purpose(current: review.Progress) purpose_contract.Purpose {
    return switch (current) {
        .initial, .source => .source,
        .pending, .principles => .principles,
    };
}
pub fn pending(current: review.Progress) operations.Error!review.Pending {
    return switch (current) {
        .pending => |value| value,
        .principles => |value| value.pending,
        else => error.OperationExecutionFailed,
    };
}
pub fn inputs(view: *const @import("../domain/pipeline_data.zig").View, current: review.Progress) operations.Error!a.Inputs {
    return if (purpose(current) == .principles) (try pending(current)).inputs else owned.read(view, authority.inputs_schema, .inputs) catch |operation_error| operation_error;
}
pub fn collection(comptime selected: purpose_contract.Purpose, current: review.Progress) operations.Error!purpose_contract.Contract(selected).Collection {
    if (selected == .source) return if (current == .source) current.source else error.OperationExecutionFailed;
    return if (current == .principles) current.principles.result else error.OperationExecutionFailed;
}
pub fn prior(comptime selected: purpose_contract.Purpose, current: review.Progress) operations.Error!?purpose_contract.Contract(selected).Collection {
    if (selected == .source) return switch (current) {
        .initial => null,
        .source => |result| result,
        else => error.OperationExecutionFailed,
    };
    return switch (current) {
        .pending => null,
        .principles => |result| result.result,
        else => error.OperationExecutionFailed,
    };
}
pub fn retain(owner: *owned.Owner, current: review.Progress) void {
    owner.payload = switch (current) {
        .initial => .support_initial,
        .source => |value| .{ .support = value },
        .pending => |value| .{ .principle_pending = value },
        .principles => |value| .{ .principle_support = value },
    };
}
pub fn publishProgress(allocator: std.mem.Allocator, owner: *owned.Owner, outcome: @import("../domain/workflow.zig").OutcomeTag) operations.Error!execution.Candidate {
    errdefer owned.destroy(owner);
    var delta: pipeline.NodeDelta = .{};
    delta.data_replacements[@intFromEnum(schema.key)] = values.adopt(allocator, schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch |operation_error| return operation_error;
    return .{ .outcome = outcome, .delta = delta };
}
pub fn publish(comptime selected: purpose_contract.Purpose, allocator: std.mem.Allocator, owner: *owned.Owner, previous: review.Progress, result: purpose_contract.Contract(selected).Collection) operations.Error!execution.Candidate {
    if (selected == .source) owner.payload = .{ .support = result } else {
        const retained = pending(previous) catch |native_failure| {
            owned.destroy(owner);
            return native_failure;
        };
        owner.payload = .{ .principle_support = .{ .pending = retained, .result = result } };
    }
    return publishProgress(allocator, owner, switch (result) {
        .accepted => .ok,
        .pending => .more,
        .rejected => .invalid,
    });
}

/// Seal historical bookkeeping while retaining the exact newly admitted review
/// owner and its immutable request dependencies. Callers own partial deltas.
pub fn attachHistory(allocator: std.mem.Allocator, input: @import("../domain/pipeline_data.zig").View, candidate: *execution.Candidate, history: retention.History) operations.Error!void {
    const owner = try owned.create(allocator, input);
    errdefer owned.destroy(owner);
    const index = @intFromEnum(schema.key);
    if (owner.parents[index]) |old| values.destroy(old);
    owner.parents[index] = null;
    owner.parents[index] = try values.retain(candidate.delta.data_replacements[index].?);
    owner.payload = .{ .review_history = history };
    candidate.delta.data_replacements[@intFromEnum(history_schema.key)] = try values.adopt(allocator, history_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null);
}
pub const Initialize = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .preserve = .{ .kind = .candidate, .subject = .required_authority_inputs, .evidence = .required_authority_inputs, .result = .specification_support_review } };
    pub const Action = @import("../actions/specification/initialize_specification_review.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const source = owned.read(&input.step.data, authority.inputs_schema, .inputs) catch |operation_error| return operation_error;
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        errdefer owned.destroy(owner);
        const current = self.action.execute(owner.arena.allocator(), source, try owned.read(&input.step.data, history_schema, .review_history), try values.read(&input.step.data, requests.ledger_schema, @import("../domain/model_request_identity.zig").ModelRequestIdentityLedger)) catch |operation_error| return operation_error;
        retain(owner, current);
        return owned.publish(self.allocator, schema, owner, .ok) catch |operation_error| operation_error;
    }
};
pub const InitializeHistory = struct {
    pub const Action = @import("../actions/specification/initialize_specification_review_history.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const owner = try owned.create(self.allocator, input.step.data);
        errdefer owned.destroy(owner);
        owner.payload = .{ .review_history = self.action.execute() };
        return owned.publish(self.allocator, history_schema, owner, .ok) catch |operation_error| operation_error;
    }
};

pub const Reuse = struct {
    pub const Action = @import("../actions/specification/reuse_specification_review.zig").Action;
    pub const parameters = requests.preparation_parameters;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .failed };
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .preserve = .{ .kind = .candidate, .subject = .specification_support_review, .evidence = .specification_support_review, .result = .specification_support_review } };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = try progress(&input.step.data);
        const owner = try owned.create(self.allocator, input.step.data);
        retain(owner, current);
        const result = self.assess(owner, input.step, current) catch |err| {
            owned.destroy(owner);
            return err;
        };
        var candidate = try publishProgress(self.allocator, owner, result.outcome);
        errdefer for (candidate.delta.data_replacements) |value| if (value) |allocation| values.destroy(allocation);
        try attachHistory(self.allocator, input.step.data, &candidate, result.history);
        return candidate;
    }
    fn assess(self: *@This(), owner: *owned.Owner, step: operations.StepInput, current: review.Progress) operations.Error!struct { outcome: @import("../domain/workflow.zig").OutcomeTag, history: retention.History } {
        const history = try owned.read(&step.data, history_schema, .review_history);
        // Policy context intentionally remains broad and is always reassessed.
        if (purpose(current) == .principles) return .{ .outcome = .more, .history = history };
        const source = try inputs(&step.data, current);
        const source_context = try spec.readContext(&step.data);
        const guidance = try @import("packet_guidance_workflow.zig").read(&step.data);
        const ledger = try values.read(&step.data, requests.ledger_schema, @import("../domain/model_request_identity.zig").ModelRequestIdentityLedger);
        const population = try a.build(owner.arena.allocator(), source);
        var previous = try prior(.source, current);
        var retained_history = history;
        // Consume only the finite unchanged prefix. A miss returns to ordinary
        // model preparation; completion returns through the source-review gate.
        // Each append is fully admitted and strictly advances native membership.
        for (0..population.requirements.len) |_| {
            const before = if (previous) |value| switch (value) {
                .pending => |candidate| candidate.review.entries.len,
                else => return error.OperationExecutionFailed,
            } else 0;
            const target = try purpose_contract.Source.nextSubject(owner.arena.allocator(), source, previous);
            const packet = try purpose_contract.Source.packetFor(self.allocator, source, source_context, guidance, purpose_contract.Source.assignmentScope(source, target));
            defer @import("../domain/model_input_packet.zig").release(packet);
            const selection = try requests.selectionForPacket(self.allocator, owner.arena.allocator(), step, packet);
            defer selection.deinit();
            const reused = try self.action.execute(owner.arena.allocator(), retained_history, source, source_context, guidance, previous, selection.value, ledger) orelse
                return .{ .outcome = .more, .history = retained_history };
            const candidate = switch (reused.collection) {
                .accepted => |value| value.candidate,
                .pending => |value| value,
                .rejected => return error.OperationExecutionFailed,
            };
            if (candidate.review.entries.len <= before or candidate.review.entries.len > population.requirements.len or candidate.pending_localization != null)
                return error.OperationExecutionFailed;
            owner.payload = .{ .support = reused.collection };
            retained_history = reused.history;
            if (reused.collection == .accepted) return .{ .outcome = .ok, .history = retained_history };
            previous = reused.collection;
        }
        return error.OperationExecutionFailed;
    }
};
pub const BuildInput = struct {
    pub const Action = @import("../actions/specification/build_specification_support_input.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = try progress(&input.step.data);
        const source = try inputs(&input.step.data, current);
        inline for (.{ purpose_contract.Purpose.source, .principles }) |selected| if (purpose(current) == selected) {
            var arena = std.heap.ArenaAllocator.init(self.allocator);
            defer arena.deinit();
            const target = purpose_contract.Contract(selected).nextSubject(arena.allocator(), source, try prior(selected, current)) catch |operation_error| return operation_error;
            return requests.publishPacket(self.allocator, self.action.execute(selected, self.allocator, source, try spec.readContext(&input.step.data), try @import("packet_guidance_workflow.zig").read(&input.step.data), target) catch |operation_error| return operation_error);
        };
        unreachable;
    }
};
pub const Collect = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .diagnostic_admission = .{ .kind = .candidate, .subject = .specification_support_review, .evidence = .specification_support_review, .result = .specification_support_review } };
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .invalid, .failed };
    pub const Action = @import("../actions/specification/collect_specification_support.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = try progress(&input.step.data);
        const source = try inputs(&input.step.data, current);
        const packet = values.read(&input.step.data, requests.packet_schema, @import("../domain/model_input_packet.zig").Packet) catch |operation_error| return operation_error;
        const admitted = try @import("model_candidate_handoff.zig").readAccepted(&input.step.data);
        const handoff = admitted.candidate;
        const source_context = try spec.readContext(&input.step.data);
        const guidance = try @import("packet_guidance_workflow.zig").read(&input.step.data);
        const history = try owned.read(&input.step.data, history_schema, .review_history);
        const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        const ledger = try values.read(&input.step.data, requests.ledger_schema, @import("../domain/model_request_identity.zig").ModelRequestIdentityLedger);
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        inline for (.{ purpose_contract.Purpose.source, .principles }) |selected| if (purpose(current) == selected) {
            const previous = prior(selected, current) catch |err| {
                owned.destroy(owner);
                return err;
            };
            const result = self.action.execute(selected, owner.arena.allocator(), source, source_context, guidance, previous, packet, handoff.body, handoff.origin, history, request, admitted.evidence, ledger) catch |native_failure| {
                owned.destroy(owner);
                return native_failure;
            };
            var published = try publish(selected, self.allocator, owner, current, result.collection);
            errdefer for (published.delta.data_replacements) |value| if (value) |allocation| values.destroy(allocation);
            try attachHistory(self.allocator, input.step.data, &published, result.history);
            return published;
        };
        unreachable;
    }
};
pub const CheckLocalization = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .observe = .{ .kind = .candidate, .subject = .specification_support_review, .evidence = .specification_support_review } };
    pub const Action = @import("../actions/specification/check_specification_support_localization.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .invalid };
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        return .{ .outcome = switch (context.?.action.execute(try progress(&input.step.data))) {
            .complete => .ok,
            .next => .more,
            .localize => .invalid,
        }, .delta = .{} };
    }
};
pub const BuildLossInput = struct {
    pub const Action = @import("../actions/specification/build_specification_support_loss_input.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = try progress(&input.step.data);
        if (current != .source) return error.OperationExecutionFailed;
        return requests.publishPacket(self.allocator, self.action.execute(self.allocator, try inputs(&input.step.data, current), try spec.readContext(&input.step.data), try @import("packet_guidance_workflow.zig").read(&input.step.data), current.source) catch |operation_error| return operation_error);
    }
};
pub const CollectLoss = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .diagnostic_admission = .{ .kind = .candidate, .subject = .specification_support_review, .evidence = .specification_support_review, .result = .specification_support_review } };
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .invalid, .failed };
    pub const Action = @import("../actions/specification/collect_specification_support_loss.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = try progress(&input.step.data);
        if (current != .source) return error.OperationExecutionFailed;
        const packet = values.read(&input.step.data, requests.packet_schema, @import("../domain/model_input_packet.zig").Packet) catch |operation_error| return operation_error;
        const handoff = try @import("model_candidate_handoff.zig").read(&input.step.data);
        const source = try inputs(&input.step.data, current);
        const source_context = try spec.readContext(&input.step.data);
        const guidance = try @import("packet_guidance_workflow.zig").read(&input.step.data);
        const history = try owned.read(&input.step.data, history_schema, .review_history);
        const ledger = try values.read(&input.step.data, requests.ledger_schema, @import("../domain/model_request_identity.zig").ModelRequestIdentityLedger);
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        const result = self.action.execute(owner.arena.allocator(), source, source_context, guidance, current.source, packet, handoff.body, handoff.origin, history, ledger) catch |native_failure| {
            owned.destroy(owner);
            return native_failure;
        };
        var published = try publish(.source, self.allocator, owner, current, result.collection);
        errdefer for (published.delta.data_replacements) |value| if (value) |allocation| values.destroy(allocation);
        try attachHistory(self.allocator, input.step.data, &published, result.history);
        return published;
    }
};
pub const Advance = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .preserve = .{ .kind = .candidate, .subject = .specification_support_review, .evidence = .specification_support_review, .result = .specification_support_review } };
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .failed };
    pub const Action = @import("../actions/specification/advance_specification_review.zig").Action;
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const current = try progress(&input.step.data);
        const registry = values.read(&input.step.data, @import("principle_workflow.zig").registry_schema, @import("../domain/principle_registry.zig").Registry) catch |operation_error| return operation_error;
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        const result = self.action.execute(owner.arena.allocator(), current, registry.*) catch |native_failure| {
            owned.destroy(owner);
            return native_failure;
        };
        retain(owner, result.progress);
        return publishProgress(self.allocator, owner, if (result.outcome == .more) .more else .ok);
    }
};

/// Only admission of a completed review advances authority inputs. Repair keeps
/// the source projection unchanged, preserving its generation and lineage.
pub const Apply = struct {
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .repair_validate = .{ .kind = .candidate, .subject = .specification_support_review, .evidence = .specification_support_review, .result = .required_authority_inputs } };
    pub const repair_role: @import("../domain/workflow_retry.zig").Role = .validate;
    pub const Action = @import("../actions/specification/apply_specification_support.zig").Action;
    pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .invalid, .failed };
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const reviewed = owned.read(&input.step.data, schema, .support) catch |operation_error| return operation_error;
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        errdefer owned.destroy(owner);
        if (reviewed == .accepted and reviewed.accepted.candidate.pending_localization != null) return rejected(self.allocator, owner);
        owner.payload = .{ .inputs = self.action.execute(reviewed) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidRequiredAuthority => return rejected(self.allocator, owner),
        } };
        var delta: pipeline.NodeDelta = .{};
        if (input.step.repair_permit) |active| {
            delta.repair_transition = @import("../domain/source_omission.zig").admittedValidation(owner.arena.allocator(), active, reviewed.accepted) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidRequiredAuthority => return rejected(self.allocator, owner),
            };
        }
        delta.data_replacements[@intFromEnum(authority.inputs_schema.key)] = values.adopt(self.allocator, authority.inputs_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch |operation_error| return operation_error;
        return .{ .outcome = .ok, .delta = delta };
    }

    fn rejected(allocator: std.mem.Allocator, owner: *owned.Owner) operations.Error!execution.Candidate {
        owner.payload = .{ .rejected = .invalid_contract };
        owner.rejection = error.InvalidRequiredAuthority;
        var delta: pipeline.NodeDelta = .{};
        delta.data_replacements[@intFromEnum(authority.inputs_schema.key)] = try values.adopt(allocator, authority.inputs_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null);
        return .{ .outcome = .invalid, .delta = delta, .diagnostic = error.InvalidRequiredAuthority };
    }
};
