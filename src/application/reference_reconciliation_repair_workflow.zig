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
        }, .result = .reference_reconciliation_repair } };
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
    pub const parameters = [_]@import("../domain/workflow_operation.zig").ParameterDescriptor{.{ .id = "retry-limit", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 0, .integer_max = std.math.maxInt(u32) }};
    pub const retry_limit: @import("../domain/workflow_operation.zig").RetryLimitDescriptor = .{ .maximum = std.math.maxInt(u32), .scope = .repair };
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
