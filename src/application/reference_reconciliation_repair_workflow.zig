//! One-action runner bindings. YAML owns model calls, retirement and revalidation.
const std = @import("std");
const data = @import("../domain/pipeline_data.zig");
const pipeline = @import("../domain/pipeline.zig");
const r = @import("../domain/reference_reconciliation.zig");
const repair = @import("../domain/reference_reconciliation_repair.zig");
const repair_owner = @import("../domain/repair_owner.zig");
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

pub fn authorizationBlocked(view: *const data.View) values.Error!bool {
    const value = try values.read(view, state_schema, owned.Value);
    if (!owned.retainsCurrentInputs(value, view)) return error.InvalidCandidatePayload;
    return switch (owned.payload(value).*) {
        .authorized => false,
        .blocked => true,
        .rejected => error.InvalidCandidatePayload,
    };
}

const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .blocked, .failed };
const Stage = enum { summary, dispositions, signals, conflicts };
pub fn Authorize(comptime stage: Stage) type {
    return struct {
        pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .repair_authorize = .{ .kind = .candidate, .subject = .parsed_reference_reconciliation, .evidence = switch (stage) {
            .summary => .validated_reference_summary,
            .dispositions => .validated_reference_dispositions,
            .signals => .validated_reference_signals,
            .conflicts => .validated_reference_conflicts,
        }, .result = .reference_reconciliation_repair, .blocked_reader = .reference_reconciliation } };
        pub const repair_role: @import("../domain/workflow_retry.zig").Role = .authorize;
        /// Each phase's authorizer reads the phase's own rejected validation and invalidates it and
        /// every later phase that depended on it.
        pub const effects: repair_owner.Effects = .{
            .requires = switch (stage) {
                .summary => &.{ .parsed_reference_reconciliation, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain, .validated_reference_summary },
                .dispositions => &.{ .parsed_reference_reconciliation, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain, .validated_reference_dispositions },
                .signals => &.{ .parsed_reference_reconciliation, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain, .validated_reference_signals },
                .conflicts => &.{ .parsed_reference_reconciliation, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain, .validated_reference_conflicts },
            },
            .produces = &.{.reference_reconciliation_repair},
            .invalidates = switch (stage) {
                .summary => &.{.validated_reference_summary},
                .dispositions => &.{.validated_reference_dispositions},
                .signals => &.{ .validated_reference_dispositions, .validated_reference_signals },
                .conflicts => &.{ .validated_reference_dispositions, .validated_reference_signals, .validated_reference_conflicts },
            },
        };
        pub const outcomes = @import("reference_reconciliation_repair_workflow.zig").outcomes;
        allocator: std.mem.Allocator,
        pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
            const self = context.?;
            const prior = try extraction.readNative(&input.step.data, rec.parsed_schema, .reconciliation_parsed);
            const schema = switch (stage) {
                .summary => rec.summary_schema,
                .dispositions => rec.dispositions_schema,
                .signals => rec.signals_schema,
                .conflicts => rec.conflicts_schema,
            };
            const rejected = try extraction.readNative(&input.step.data, schema, .reconciliation_rejected);
            const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
            errdefer owned.destroy(owner);
            const decision = repair.authorize(owner.arena.allocator(), prior.payload().reconciliation_parsed, try rec.textContext(&input.step.data), rejected.payload().reconciliation_rejected) catch |operation_error| return operation_error;
            owner.payload = switch (decision) {
                .model => |value| .{ .authorized = .{ .authorization = value, .replacement = .pending } },
                .automatic => |value| .{ .authorized = .{ .authorization = value.authorization, .replacement = .{ .automatic = value.replacement } } },
                .blocked => |reason| result: {
                    var diagnostic_value = rejected.payload().reconciliation_rejected;
                    diagnostic_value.blocked = reason;
                    break :result .{ .blocked = .{ .reason = reason, .rejection = diagnostic_value } };
                },
            };
            const permit = if (owner.payload == .authorized) owner.payload.authorized.authorization.retry orelse return error.RepairPermitMissing else null;
            var result = owned.publish(self.allocator, state_schema, owner, switch (decision) {
                .model => .ok,
                .automatic => .more,
                .blocked => .blocked,
            }) catch |operation_error| return operation_error;
            for (effects.invalidates) |key| result.delta.data_invalidations.insert(key);
            if (permit) |selected| result.delta.repair_transition = .{ .authorized = selected };
            return result;
        }
    };
}
pub const BuildInput = struct {
    pub const effects: repair_owner.Effects = .{
        .requires = &.{ .parsed_reference_reconciliation, .reference_reconciliation_repair, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain, .packet_guidance },
        .produces = &.{.model_input_packet},
    };
    allocator: std.mem.Allocator,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const authorized = readAuthorization(&input.step.data) catch |operation_error| return operation_error;
        const prior = try extraction.readNative(&input.step.data, rec.parsed_schema, .reconciliation_parsed);
        const guidance = try @import("packet_guidance_workflow.zig").read(&input.step.data);
        const packet = repair.packet(self.allocator, prior.payload().reconciliation_parsed, try rec.textContext(&input.step.data), authorized, guidance.summary_purpose) catch |operation_error| return operation_error;
        return @import("model_request_workflow.zig").publishPacket(self.allocator, packet);
    }
};
pub const Parse = struct {
    pub const effects: repair_owner.Effects = .{
        .requires = &.{ .reference_reconciliation_repair, .model_input_packet, .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .terminal_provider_operation, .model_payload_schema_result },
        .replaces = &.{.reference_reconciliation_repair},
    };
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .preserve = .{ .kind = .candidate, .subject = .reference_reconciliation_repair, .evidence = .reference_reconciliation_repair, .result = .reference_reconciliation_repair } };
    allocator: std.mem.Allocator,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const state = owned.readNative(&input.step.data, state_schema, .authorized) catch |operation_error| return operation_error;
        if (state.replacement != .pending) return error.RepairStateMismatch;
        const packet = values.read(&input.step.data, @import("model_request_workflow.zig").packet_schema, @import("../domain/model_input_packet.zig").Packet) catch |operation_error| return operation_error;
        const candidate = try @import("model_candidate_handoff.zig").read(&input.step.data);
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        errdefer owned.destroy(owner);
        owner.payload = .{ .authorized = .{ .authorization = state.authorization, .replacement = .{ .model = .{ .value = repair.parse(owner.arena.allocator(), state.authorization, packet, candidate.body) catch |operation_error| return operation_error, .origin = candidate.origin } } } };
        var delta: pipeline.NodeDelta = .{};
        delta.data_replacements[@intFromEnum(state_schema.key)] = values.adopt(self.allocator, state_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch |operation_error| return operation_error;
        return .{ .outcome = .ok, .delta = delta };
    }
};
pub const Merge = struct {
    pub const effects: repair_owner.Effects = .{
        .requires = &.{ .parsed_reference_reconciliation, .reference_reconciliation_repair, .citable_reference_inputs, .reference_passive_literals, .valid_toolchain },
        .replaces = &.{.parsed_reference_reconciliation},
        .invalidates = &.{.reference_reconciliation_repair},
    };
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .repair_merge = .{ .kind = .candidate, .subject = .parsed_reference_reconciliation, .evidence = .reference_reconciliation_repair, .result = .parsed_reference_reconciliation } };
    pub const repair_role: @import("../domain/workflow_retry.zig").Role = .merge;
    allocator: std.mem.Allocator,
    normalizer: @import("../ports/unicode_normalizer.zig").Normalizer,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const state = owned.readNative(&input.step.data, state_schema, .authorized) catch |operation_error| return operation_error;
        const prior = try extraction.readNative(&input.step.data, rec.parsed_schema, .reconciliation_parsed);
        const owner = reference.create(self.allocator, prior) catch |operation_error| return operation_error;
        errdefer reference.destroy(owner);
        const chosen: struct { replacement: ?repair.Replacement, origin: ?Origin } = switch (state.replacement) {
            .pending => return error.RepairStateMismatch,
            .automatic => |value| .{ .replacement = value, .origin = null },
            .model => |value| .{ .replacement = value.value, .origin = value.origin },
        };
        const context_value = try rec.textContext(&input.step.data);
        const arena = owner.arena.allocator();
        var canonical = @import("../domain/typed_text.zig").CanonicalText.fromInputs(arena, self.normalizer, context_value.inputs) catch |operation_error| return operation_error;
        defer canonical.deinit(arena);
        owner.payload = .{ .reconciliation_parsed = repair.merge(arena, canonical, prior.payload().reconciliation_parsed, context_value, state.authorization, chosen.replacement, chosen.origin) catch |operation_error| return operation_error };
        var delta: pipeline.NodeDelta = .{};
        delta.repair_transition = try repair_owner.mergeTransition(owner.payload.reconciliation_parsed.source.last_repair, .native);
        delta.data_replacements[@intFromEnum(rec.parsed_schema.key)] = values.adopt(self.allocator, rec.parsed_schema, reference.Value, reference.Owner, owner, reference.view, reference.destroy, null) catch |operation_error| return operation_error;
        for (effects.invalidates) |key| delta.data_invalidations.insert(key);
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

pub fn readAuthorization(view: *const data.View) operations.Error!repair.Authorization {
    return (try owned.readNative(view, state_schema, .authorized)).authorization;
}

test "a blocked authorization of any phase stays decided though it retires the evidence it judged" {
    const binding = @import("workflow_outcome_binding.zig");
    const envelope_module = @import("pipeline_envelope.zig");
    inline for ([_]Stage{ .summary, .dispositions, .signals, .conflicts }) |stage| {
        const authorize = Authorize(stage);
        const descriptor = authorize.outcome_association;
        const evidence_key = descriptor.repair_authorize.evidence;
        const subject_schema = values.schema(.parsed_reference_reconciliation, u8, 1, 16).captured();
        const evidence_schema = values.schema(evidence_key, u8, 1, 16).captured();
        var envelope = envelope_module.PipelineEnvelope.init(std.testing.allocator, &.{ subject_schema, evidence_schema, state_schema });
        defer envelope.deinit();
        var subject_delta: pipeline.NodeDelta = .{};
        defer envelope.discard(&subject_delta);
        subject_delta.data_writes[@intFromEnum(subject_schema.key)] = try values.create(std.testing.allocator, subject_schema, u8, 1);
        try envelope.apply(.{ .id = "test.subject", .kind = .action, .requires = &.{}, .produces = &.{subject_schema.key}, .side_effect = .none }, &subject_delta, .ok);
        var evidence_delta: pipeline.NodeDelta = .{};
        defer envelope.discard(&evidence_delta);
        evidence_delta.data_writes[@intFromEnum(evidence_schema.key)] = try values.create(std.testing.allocator, evidence_schema, u8, 2);
        try envelope.apply(.{ .id = "test.evidence", .kind = .action, .requires = &.{subject_schema.key}, .produces = &.{evidence_schema.key}, .side_effect = .none }, &evidence_delta, .ok);
        const read: data.View = .{ .slots = envelope.slots };
        // The phase's validation rejected the candidate: the run is invalid until the authorizer reclassifies it.
        const validation_occurrence = try envelope.beginOccurrence("test.validate");
        var rejection: execution.Candidate = .{ .outcome = .invalid, .delta = .{} };
        var rejected = try binding.prepare(&envelope, validation_occurrence, .{ .observe = .{ .kind = .candidate, .subject = subject_schema.key, .evidence = subject_schema.key } }, &rejection);
        defer rejected.deinit();
        try envelope.outcomes.commit(&rejected);
        try std.testing.expect(!envelope.outcomes.compatible(.blocked));
        const occurrence = try envelope.beginOccurrence("test.authorize");
        // The decision was made against the current evidence and retires it, as every authorizer does. Its
        // rejection is never read here, only that the decision is a block.
        const owner = try owned.create(std.testing.allocator, read);
        owner.payload = .{ .blocked = .{ .reason = .no_independent_target, .rejection = undefined } };
        var decided = try owned.publish(std.testing.allocator, state_schema, owner, .blocked);
        defer envelope.discard(&decided.delta);
        for (authorize.effects.invalidates) |key| decided.delta.data_invalidations.insert(key);
        try std.testing.expect(decided.delta.data_invalidations.contains(evidence_key));
        var prepared = try binding.prepare(&envelope, occurrence, descriptor, &decided);
        defer prepared.deinit();
        try std.testing.expect(prepared.compatible(.blocked));
        // The same decision through a descriptor that names no reader is refused: the reader is the one difference.
        var unread = descriptor.repair_authorize;
        unread.blocked_reader = null;
        try std.testing.expectError(error.InvalidOutcomeAssociation, binding.prepare(&envelope, occurrence, .{ .repair_authorize = unread }, &decided));
        // A decision made against other evidence than the run holds is still stale.
        const other = try values.create(std.testing.allocator, evidence_schema, u8, 9);
        defer values.destroy(other);
        var foreign = read;
        foreign.slots[@intFromEnum(evidence_key)] = other;
        const stale_owner = try owned.create(std.testing.allocator, foreign);
        stale_owner.payload = .{ .blocked = .{ .reason = .no_independent_target, .rejection = undefined } };
        var stale = try owned.publish(std.testing.allocator, state_schema, stale_owner, .blocked);
        defer envelope.discard(&stale.delta);
        for (authorize.effects.invalidates) |key| stale.delta.data_invalidations.insert(key);
        try std.testing.expectError(error.InvalidOutcomeAssociation, binding.prepare(&envelope, occurrence, descriptor, &stale));
        // Only the evidence the step retires is put back: an input it replaces stays stale.
        const successor = try values.create(std.testing.allocator, subject_schema, u8, 7);
        const replacing_owner = try owned.create(std.testing.allocator, read);
        replacing_owner.payload = .{ .blocked = .{ .reason = .no_independent_target, .rejection = undefined } };
        var replacing = try owned.publish(std.testing.allocator, state_schema, replacing_owner, .blocked);
        defer envelope.discard(&replacing.delta);
        replacing.delta.data_replacements[@intFromEnum(subject_schema.key)] = successor;
        for (authorize.effects.invalidates) |key| replacing.delta.data_invalidations.insert(key);
        try std.testing.expectError(error.InvalidOutcomeAssociation, binding.prepare(&envelope, occurrence, descriptor, &replacing));
    }
}
