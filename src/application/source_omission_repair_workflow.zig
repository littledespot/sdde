//! Runner bindings for source-backed repair; YAML owns rebuilding and review.
const std = @import("std");
const loss = @import("../domain/source_omission.zig");
const source_repair = @import("../domain/source_omission_repair.zig");
const repair_owner = @import("../domain/repair_owner.zig");
const ex = @import("../domain/reference_extraction_repair.zig").Omission;
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
const data = @import("../domain/pipeline_data.zig");
const pipeline = @import("../domain/pipeline.zig");
const extraction = @import("reference_extraction_workflow.zig");
const rec = @import("reference_reconciliation_workflow.zig");
const reference = @import("../domain/reference_candidate_value.zig");
const authority = @import("required_authority_workflow.zig");
const authority_values = @import("required_authority_values.zig");
const Rejection = struct { reason: loss.Rejection, support: loss.Support };
const owned = @import("retained_candidate.zig").Storage(union(enum) { repair: loss.Repair, rejected: ?Rejection }, .{ .rejected = null });
pub const schema = values.schema(.source_omission_repair, owned.Value, 1, null).captured();
pub const schemas = [_]data.Schema{schema};
pub fn rejection(view: *const data.View) values.Error!?Rejection {
    if (!view.contains(schema.key)) return null;
    const value = owned.payload(try values.read(view, schema, owned.Value));
    return if (value.* == .rejected) value.rejected else null;
}
pub fn read(view: *const data.View) operations.Error!loss.Repair {
    return owned.readNative(view, schema, .repair) catch |operation_error| operation_error;
}
pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .more, .invalid, .failed };
fn support(view: *const data.View) operations.Error!loss.Support {
    const review = authority_values.read(view, @import("specification_support_workflow.zig").schema, .support) catch |operation_error| return operation_error;
    if (review != .accepted) return error.RepairOwnerMismatch;
    return .{ .repair_phase = (try @import("specification_generation_facts.zig").read(view)).phase(), .review = review.accepted.candidate, .inputs = authority_values.read(view, authority.inputs_schema, .inputs) catch |operation_error| return operation_error, .observations = authority_values.read(view, authority.observations_schema, .observations) catch |operation_error| return operation_error, .result = authority_values.read(view, authority.result_schema, .result) catch |operation_error| return operation_error };
}
fn facts(view: *const data.View) operations.Error!ex.Facts {
    const source = values.read(view, @import("reference_evidence_workflow.zig").inputs_schema, @import("../domain/reference_evidence.zig").Inputs) catch |operation_error| return operation_error;
    const candidates = values.read(view, @import("structured_token_workflow.zig").candidates_schema, @import("../domain/structured_tokens.zig").Candidates) catch |operation_error| return operation_error;
    const candidate = try extraction.readNative(view, extraction.text_schema, .text_validated);
    return .{ .extraction = .{ .inputs = source.*, .candidates = candidates.*, .candidate = candidate.payload().text_validated }, .support = try support(view) };
}
fn parsed(view: *const data.View) operations.Error!@import("../domain/reference_reconciliation.zig").Parsed {
    return (try extraction.readNative(view, rec.parsed_schema, .reconciliation_parsed)).payload().reconciliation_parsed;
}
/// What every source-omission step reads besides its own repair state: the phase witness's optional
/// facts, present only while the specification is being generated.
const phase_optional = &@import("../domain/specification_generation_phase.zig").optional;
pub const Authorize = struct {
    pub const effects: repair_owner.Effects = .{
        .requires = &.{ .citable_reference_inputs, .structured_token_candidates, .text_validated_reference_extraction, .parsed_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .required_authority_inputs, .required_authority_observations, .required_authority_result, .specification_support_review },
        .optional = phase_optional,
        .produces = &.{.source_omission_repair},
    };
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .repair_authorize = .{ .kind = .authority, .subject = .required_authority_inputs, .evidence = .required_authority_result, .result = .source_omission_repair } };
    pub const repair_role: @import("../domain/workflow_retry.zig").Role = .authorize;
    pub const outcomes = @import("source_omission_repair_workflow.zig").outcomes;
    allocator: std.mem.Allocator,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        errdefer owned.destroy(owner);
        const current = try facts(&input.step.data);
        const state = source_repair.authorize(owner.arena.allocator(), current, try parsed(&input.step.data), try rec.textContext(&input.step.data)) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            owner.rejection = err;
            owner.payload = .{ .rejected = .{ .reason = if (err == error.UnlocalizedSourceOmission) .unlocalized_omission else if (err == error.PostGenerationSourceRepairForbidden) .post_generation_source_repair_forbidden else .invalid_repair_authority, .support = current.support } };
            return owned.publish(self.allocator, schema, owner, .invalid) catch |operation_error| operation_error;
        };
        owner.payload = .{ .repair = state };
        const permit = switch (state.authorization) {
            inline else => |auth| auth.retry orelse return error.RepairPermitMissing,
        };
        var result = owned.publish(self.allocator, schema, owner, if (state.authorization == .extraction) .ok else .more) catch |operation_error| return operation_error;
        result.delta.repair_transition = .{ .authorized = permit };
        return result;
    }
};
pub const BuildInput = struct {
    pub const effects: repair_owner.Effects = .{
        .requires = &.{ .citable_reference_inputs, .structured_token_candidates, .text_validated_reference_extraction, .parsed_reference_reconciliation, .reference_passive_literals, .valid_toolchain, .required_authority_inputs, .required_authority_observations, .required_authority_result, .specification_support_review, .source_omission_repair, .packet_guidance },
        .optional = phase_optional,
        .produces = &.{.model_input_packet},
    };
    allocator: std.mem.Allocator,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const state = owned.readNative(&input.step.data, schema, .repair) catch |operation_error| return operation_error;
        const packet = source_repair.packet(self.allocator, try facts(&input.step.data), try parsed(&input.step.data), try rec.textContext(&input.step.data), state, try @import("packet_guidance_workflow.zig").read(&input.step.data)) catch |operation_error| return operation_error;
        return @import("model_request_workflow.zig").publishPacket(self.allocator, packet);
    }
};
pub const Parse = struct {
    pub const effects: repair_owner.Effects = .{
        .requires = &.{ .source_omission_repair, .model_input_packet, .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .terminal_provider_operation, .model_payload_schema_result },
        .replaces = &.{.source_omission_repair},
    };
    pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .preserve = .{ .kind = .authority, .subject = .source_omission_repair, .evidence = .source_omission_repair, .result = .source_omission_repair } };
    allocator: std.mem.Allocator,
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const state = owned.readNative(&input.step.data, schema, .repair) catch |operation_error| return operation_error;
        const packet = values.read(&input.step.data, @import("model_request_workflow.zig").packet_schema, @import("../domain/model_input_packet.zig").Packet) catch |operation_error| return operation_error;
        const handoff = try @import("model_candidate_handoff.zig").read(&input.step.data);
        const owner = owned.create(self.allocator, input.step.data) catch |operation_error| return operation_error;
        errdefer owned.destroy(owner);
        owner.payload = .{ .repair = source_repair.parse(owner.arena.allocator(), state, packet, handoff.body, handoff.origin) catch |operation_error| return operation_error };
        var delta: pipeline.NodeDelta = .{};
        delta.data_replacements[@intFromEnum(schema.key)] = values.adopt(self.allocator, schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null) catch |operation_error| return operation_error;
        return .{ .outcome = .ok, .delta = delta };
    }
};
pub fn Merge(comptime kind: enum { extraction, reconciliation }) type {
    return struct {
        /// The extraction merge replaces the validated extraction and invalidates everything built on
        /// it; the reconciliation merge replaces the parsed reconciliation and invalidates what it fed.
        pub const effects: repair_owner.Effects = .{
            .requires = switch (kind) {
                .extraction => &loss.extraction_requires,
                .reconciliation => &loss.reconciliation_requires,
            },
            .optional = phase_optional,
            .replaces = switch (kind) {
                .extraction => &.{.text_validated_reference_extraction},
                .reconciliation => &.{.parsed_reference_reconciliation},
            },
            .invalidates = switch (kind) {
                .extraction => &loss.extraction_dependents,
                .reconciliation => &loss.reconciliation_dependents,
            },
        };
        pub const outcome_association: @import("../domain/workflow_outcome_association.zig").Descriptor = .{ .repair_merge = .{ .kind = .candidate, .subject = if (kind == .extraction) .text_validated_reference_extraction else .parsed_reference_reconciliation, .evidence = .source_omission_repair, .result = if (kind == .extraction) .text_validated_reference_extraction else .parsed_reference_reconciliation } };
        pub const repair_role: @import("../domain/workflow_retry.zig").Role = .merge;
        pub const outcomes = [_]@import("../domain/workflow.zig").OutcomeTag{ .ok, .failed };
        pub const parameters = [_]@import("../domain/workflow_operation.zig").ParameterDescriptor{.{ .id = "retry-limit", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 0, .integer_max = std.math.maxInt(u32) }};
        pub const retry_limit: @import("../domain/workflow_operation.zig").RetryLimitDescriptor = .{ .maximum = std.math.maxInt(u32), .scope = .repair };
        allocator: std.mem.Allocator,
        /// What canonicalizing the repaired text needs: the extraction merge validates the text with
        /// the full text validator, the reconciliation merge only normalizes it.
        text: switch (kind) {
            .extraction => @import("../domain/reference_reconciliation.zig").text.Validator,
            .reconciliation => @import("../ports/unicode_normalizer.zig").Normalizer,
        },
        pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
            const self = context.?;
            const state = owned.readNative(&input.step.data, schema, .repair) catch |operation_error| return operation_error;
            const target = if (kind == .extraction) extraction.text_schema else rec.parsed_schema;
            const prior = try extraction.readNative(&input.step.data, target, if (kind == .extraction) .text_validated else .reconciliation_parsed);
            const owner = reference.create(self.allocator, prior) catch |operation_error| return operation_error;
            errdefer reference.destroy(owner);
            owner.payload = if (kind == .extraction) .{ .text_validated = source_repair.mergeExtraction(owner.arena.allocator(), self.text, try facts(&input.step.data), try rec.textContext(&input.step.data), state) catch |operation_error| return operation_error } else .{ .reconciliation_parsed = source_repair.mergeReconciliation(owner.arena.allocator(), self.text, try parsed(&input.step.data), try rec.textContext(&input.step.data), try support(&input.step.data), state) catch |operation_error| return operation_error };
            var delta: pipeline.NodeDelta = .{};
            delta.repair_transition = try repair_owner.mergeTransition(if (kind == .extraction) owner.payload.text_validated.last_repair else owner.payload.reconciliation_parsed.source.last_repair, .dependent_review);
            delta.data_replacements[@intFromEnum(target.key)] = values.adopt(self.allocator, target, reference.Value, reference.Owner, owner, reference.view, reference.destroy, null) catch |operation_error| return operation_error;
            for (effects.invalidates) |key| delta.data_invalidations.insert(key);
            return .{ .outcome = .ok, .delta = delta };
        }
    };
}
