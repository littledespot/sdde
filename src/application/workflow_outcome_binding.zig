//! Native facts for the shared execution-local outcome references. Native
//! validators and ledgers retain authority; this module grants no execution.
const std = @import("std");
const association = @import("../domain/workflow_outcome_association.zig");
const pipeline = @import("../domain/pipeline.zig");
const data = @import("../domain/pipeline_data.zig");
const execution = @import("../domain/workflow_execution.zig");
const provider = @import("../domain/llm_provider_operation.zig");
const lifecycle = @import("../domain/provider_operation_lifecycle.zig");
const identity = @import("../domain/model_request_identity.zig");
const retry = @import("../domain/workflow_retry.zig");
const gate = @import("../domain/workflow_gate.zig");
const envelope_module = @import("pipeline_envelope.zig");
const values = @import("pipeline_values.zig");
const requests = @import("model_request_workflow.zig");
const handoff = @import("../domain/model_request_handoff.zig");
const raw_invocation = @import("model_invocation_workflow.zig");
const observation = @import("provider_observation_workflow.zig");
const decoded = @import("model_envelope_workflow.zig");
const payload = @import("model_payload_schema_workflow.zig");
const authority = @import("required_authority_workflow.zig");
const authority_values = @import("required_authority_values.zig");
const clarification = @import("clarification_refresh_workflow.zig");
const packets = @import("../domain/model_input_packet.zig");
const composition = @import("../domain/json_composition_runtime.zig");

pub const Error = association.Error;

const Changes = struct {
    values: [16]association.Change = undefined,
    count: usize = 0,

    fn add(self: *Changes, value: association.Change) Error!void {
        if (self.count == self.values.len) return error.InvalidOutcomeAssociation;
        self.values[self.count] = value;
        self.count += 1;
    }

    fn slice(self: *const Changes) []const association.Change {
        return self.values[0..self.count];
    }
};

/// Prepare after canonical native transitions have been validated, and before
/// the complete delta is applied. Commit only with the accepted envelope delta.
pub fn prepare(
    envelope: *envelope_module.PipelineEnvelope,
    occurrence: envelope_module.Occurrence,
    descriptor: association.Descriptor,
    candidate: *const execution.Candidate,
) Error!association.State.Prepared {
    const scope = envelope.scope orelse return error.InvalidOutcomeAssociation;
    if (!scope.eql(occurrence.scope) or occurrence.ordinal == 0 or occurrence.ordinal > envelope.occurrence_count)
        return error.InvalidOutcomeAssociation;
    var changes: Changes = .{};
    const binding = descriptor.binding() orelse {
        if (association.prohibiting(candidate.outcome)) try changes.add(.{ .observe = .{
            .subject = .{ .operation = .{ .ordinal = occurrence.ordinal } },
            .outcome = candidate.outcome,
        } });
        return envelope.outcomes.prepare(descriptor, candidate.outcome, changes.slice());
    };
    const before: data.View = .{ .slots = envelope.slots };
    const after = proposedView(envelope, candidate);
    const subject: association.Subject = if (binding.kind == .request) request_subject: {
        const request = requests.readCurrent(&before, requests.prepared_schema) catch return error.InvalidOutcomeAssociation;
        const evidence_view = if (changed(candidate, binding.evidence)) &after else &before;
        const operation_id = try requestOperation(evidence_view, binding.evidence, request.id()) orelse {
            // A logical phase check has no provider-operation identity. Preserve
            // existing references; a fresh failure remains an opaque occurrence.
            if (association.prohibiting(candidate.outcome)) try changes.add(.{ .observe = .{
                .subject = .{ .operation = .{ .ordinal = occurrence.ordinal } },
                .outcome = candidate.outcome,
            } });
            return envelope.outcomes.prepare(descriptor, candidate.outcome, changes.slice());
        };
        break :request_subject .{ .request = operation_id };
    } else try nativeSubject(envelope, occurrence, candidate, binding.kind, binding.subject, false);

    if (binding.kind != .request) {
        // A replaced subject retains its exact native identity through the
        // accepted replacement. Input evidence must originate from this source.
        if (changed(candidate, binding.subject)) {
            const next = try nativeSubject(envelope, occurrence, candidate, binding.kind, binding.subject, true);
            try changes.add(.{ .associate = .{ .source = subject, .target = next } });
        }
        if (binding.evidence != binding.subject) {
            const survives = hasValue(&after, binding.evidence);
            const consumed = candidate.delta.data_invalidations.contains(binding.evidence) and hasValue(&before, binding.evidence);
            if (survives or consumed) {
                // Retirement does not remove the obligation to validate the
                // consumed input witness. Its exact native repair reference
                // can bridge the replacement without restoring its data slot.
                const evidence = try nativeSubject(envelope, occurrence, candidate, binding.kind, binding.evidence, survives);
                const native_repair = repairMergeEvidence(envelope, descriptor, candidate, binding.subject, evidence);
                if (!changed(candidate, binding.evidence) and !dependsOn(envelope, binding.evidence, subject) and
                    !native_repair) return error.InvalidOutcomeAssociation;
                if (survives or native_repair) try changes.add(.{ .associate = .{ .source = subject, .target = evidence } });
            }
        }
        if (binding.result) |key| if (changed(candidate, key)) {
            const result = try nativeSubject(envelope, occurrence, candidate, if (descriptor == .clarification_route) .clarification else binding.kind, key, true);
            try changes.add(.{ .associate = .{ .source = subject, .target = result } });
        };
    }

    switch (descriptor) {
        .independent => unreachable,
        .observe => {},
        .preserve => {
            if (subject == .request) {
                if (candidate.outcome == .more and binding.evidence == .provider_invocation_validation_result) {
                    // Optional-stop routing does not relabel the failed raw
                    // request. Only this exact sealed observation can carry
                    // its unchanged failure toward native advisory closure.
                    const source = observation.readCurrent(&after) catch return error.InvalidOutcomeAssociation;
                    if (observation.status(source) != .more or !source.operationId().eql(subject.request)) return error.InvalidOutcomeAssociation;
                } else try changes.add(.{ .preserve = subject });
            }
        },
        .request_decode => {
            const result = decoded.readCurrent(&after) catch return error.InvalidOutcomeAssociation;
            if (!result.source().operationId().eql(subject.request)) return error.InvalidOutcomeAssociation;
            if (decoded.status(result) != candidate.outcome) return error.InvalidOutcomeAssociation;
            try missingFinalText(&changes, result.source(), candidate.outcome);
        },
        .request_admission => {
            const result = payload.readCurrent(&after) catch return error.InvalidOutcomeAssociation;
            if (!result.source().source().operationId().eql(subject.request)) return error.InvalidOutcomeAssociation;
            if (payload.status(result) != candidate.outcome) return error.InvalidOutcomeAssociation;
            if (candidate.outcome == .ok) {
                if (result.outcome() != .valid) return error.InvalidOutcomeAssociation;
                try changes.add(.{ .resolve = .{ .request_admitted = subject } });
            } else {
                // Consolidated admission retains the same sealed decode source.
                try missingFinalText(&changes, result.source().source(), candidate.outcome);
            }
        },
        .request_protocol => {
            if (candidate.outcome == .ok) {
                const previous = requests.readCurrent(&before, requests.prepared_schema) catch return error.InvalidOutcomeAssociation;
                const next = requests.readCurrent(&after, requests.prepared_schema) catch return error.InvalidOutcomeAssociation;
                const rejected = payload.readCurrent(&before) catch return error.InvalidOutcomeAssociation;
                const correction = next.protocolCorrection() orelse return error.InvalidOutcomeAssociation;
                if (previous == next or previous.id() != next.id() or !correction.eql(rejected.source().source().operationId()) or payload.status(rejected) != .invalid)
                    return error.InvalidOutcomeAssociation;
            }
        },
        .request_resend => {
            if (candidate.outcome == .ok) {
                const previous = requests.readCurrent(&before, requests.prepared_schema) catch return error.InvalidOutcomeAssociation;
                const next = requests.readCurrent(&after, requests.prepared_schema) catch return error.InvalidOutcomeAssociation;
                const rejected = payload.readCurrent(&before) catch return error.InvalidOutcomeAssociation;
                const runaway = next.runawayResend() orelse return error.InvalidOutcomeAssociation;
                if (previous == next or previous.id() != next.id() or !runaway.eql(rejected.source().source().operationId()) or payload.status(rejected) != .invalid)
                    return error.InvalidOutcomeAssociation;
            }
        },
        .advisory_request_closure => {
            const facts = @import("advisory_request_completion_workflow.zig").closing(&before) catch return error.InvalidOutcomeAssociation;
            if (!facts.operation.eql(subject.request)) return error.InvalidOutcomeAssociation;
            const protocol_stop = if (@import("workflow_model_accounting.zig").readAdvisoryStop(&before)) |_| true else |_| false;
            if (candidate.outcome != (if (protocol_stop) @import("../domain/workflow.zig").OutcomeTag.blocked else .more)) return error.InvalidOutcomeAssociation;
            const next = values.read(&after, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return error.InvalidOutcomeAssociation;
            const record = next.record(facts.request.id()) orelse return error.InvalidOutcomeAssociation;
            if (record.status != .terminal or record.terminal_reason != .failed) return error.InvalidOutcomeAssociation;
            try changes.add(.{ .advisory_request_failed = facts.operation });
        },
        .request_closure => {
            const next = values.read(&after, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return error.InvalidOutcomeAssociation;
            const record = next.record(subject.request.model_request_id) orelse return error.InvalidOutcomeAssociation;
            if (record.status != .terminal or record.terminal_reason == null) return error.InvalidOutcomeAssociation;
            if (association.prohibiting(candidate.outcome)) try changes.add(.{ .seal = .{ .subject = subject, .outcome = candidate.outcome } });
        },
        .repair_authorize => {
            if (candidate.delta.repair_transition) |transition| {
                if (transition != .authorized) return error.InvalidOutcomeAssociation;
                try changes.add(.{ .authorize = .{ .subject = subject, .transition = transition } });
            } else if (candidate.outcome == .blocked) {
                const result_key = binding.result orelse return error.InvalidOutcomeAssociation;
                if (!changed(candidate, result_key) or !try authorizationBlocked(&after, result_key)) return error.InvalidOutcomeAssociation;
                const result = try nativeSubject(envelope, occurrence, candidate, binding.kind, result_key, true);
                try changes.add(.{ .reclassify = .{ .repair_blocked = .{ .subject = subject.native, .result = result.native } } });
            }
        },
        .repair_merge => {},
        .repair_validate => {
            if (candidate.delta.repair_transition) |transition| switch (transition) {
                .validated => |progress| if (progress.result == .resolved) try changes.add(.{ .resolve = .{ .repair_resolved = .{ .subject = subject, .transition = transition } } }),
                .merged_validated => |progress| if (progress.changed and progress.result == .resolved) try changes.add(.{ .resolve = .{ .repair_resolved = .{ .subject = subject, .transition = transition } } }),
                .authorized, .merged, .abandoned_advice => return error.InvalidOutcomeAssociation,
            };
        },
        .diagnostic_admission => {
            if (candidate.outcome == .ok and envelope.outcomes.permitsDiagnosticAdmission(subject)) {
                const decision = try diagnosticAdmission(&after, binding.evidence);
                if (decision == .accepted) try changes.add(.{ .resolve = .{ .diagnostic_admitted = .{ .subject = subject, .evidence = decision } } });
            }
        },
        .advisory_completion => {
            if (candidate.outcome == .failed) {
                if (candidate.delta.repair_transition != null) return error.InvalidOutcomeAssociation;
                @import("specification_advice_stop_workflow.zig").validateUnchangedFailure(envelope.allocator, &before, &after) catch return error.InvalidOutcomeAssociation;
            } else {
                if (candidate.outcome != .ok) return error.InvalidOutcomeAssociation;
                const facts = @import("specification_advice_stop_workflow.zig").validateCompletion(envelope.allocator, &before, &after) catch return error.InvalidOutcomeAssociation;
                const permit = facts.request.packet().?.repairPermit();
                if (permit) |expected| {
                    const transition = candidate.delta.repair_transition orelse return error.InvalidOutcomeAssociation;
                    if (transition != .abandoned_advice or !std.meta.eql(transition.abandoned_advice, expected)) return error.InvalidOutcomeAssociation;
                } else if (candidate.delta.repair_transition != null) return error.InvalidOutcomeAssociation;
                try changes.add(.{ .resolve = .{ .advice_stopped = .{ .subject = subject, .request = facts.operation, .permit = permit } } });
            }
        },
        .authority_reconcile => {
            const value = values.read(&after, authority.result_schema, authority_values.Value) catch return error.InvalidOutcomeAssociation;
            const owner_payload = authority_values.payload(value);
            if (owner_payload.* != .result) return error.InvalidOutcomeAssociation;
            const result = &owner_payload.result;
            const decision = values.read(&after, authority.gate_schema, gate.Decision) catch return error.InvalidOutcomeAssociation;
            if (candidate.outcome == .ok) {
                if (decision.* != .accepted or result.continuation != .all_resolved) return error.InvalidOutcomeAssociation;
                try changes.add(.{ .resolve = .{ .authority_reconciled = subject } });
            } else if (candidate.diagnostic == null) {
                if (decision.* != .rejected) return error.InvalidOutcomeAssociation;
                try changes.add(.{ .reclassify = .{ .authority_result = .{ .subject = subject, .result = result } } });
            }
        },
        .clarification_route => {
            if (candidate.outcome == .ok or candidate.outcome == .needs_user) {
                const needs = values.read(&after, clarification.needs_schema, @import("../domain/clarification_refresh.zig").Needs) catch return error.InvalidOutcomeAssociation;
                if (needs.entries.len == 0) return error.InvalidOutcomeAssociation;
                if (binding.evidence == .required_authority_result) {
                    const result = authority_values.read(&before, authority.result_schema, .result) catch return error.InvalidOutcomeAssociation;
                    if (result.continuation != .needs_user) return error.InvalidOutcomeAssociation;
                } else if (binding.evidence == .validated_specification_unit) {
                    const result = @import("specification_values.zig").storage.read(&before, @import("specification_workflow.zig").checked_schema, .checked) catch return error.InvalidOutcomeAssociation;
                    if (result.response != .clarification) return error.InvalidOutcomeAssociation;
                } else return error.InvalidOutcomeAssociation;
                const need_subject = try nativeSubject(envelope, occurrence, candidate, .clarification, .clarification_needs, true);
                try changes.add(.{ .resolve = .{ .clarification_routed = .{ .subject = subject, .needs = need_subject } } });
            }
        },
        .clarification_refresh => {
            if (candidate.outcome == .ok or candidate.outcome == .blocked) {
                const result = values.read(&after, clarification.state_schema, @import("../domain/clarification_refresh.zig").Result) catch return error.InvalidOutcomeAssociation;
                if ((result.* == .ready) != (candidate.outcome == .ok)) return error.InvalidOutcomeAssociation;
                if (result.* == .blocked) try changes.add(.{ .reclassify = .{ .clarification_result = .{ .subject = subject, .result = result } } });
            }
        },
    }
    if (association.prohibiting(candidate.outcome) and descriptor != .request_closure and descriptor != .advisory_request_closure) {
        const recurring: ?retry.Transition = if (descriptor == .repair_validate) progress: {
            const transition = candidate.delta.repair_transition orelse break :progress null;
            break :progress switch (transition) {
                .validated => |value| if (value.result == .recurring) transition else null,
                .merged_validated => |value| if (value.changed and value.result == .recurring) transition else null,
                .authorized, .merged, .abandoned_advice => return error.InvalidOutcomeAssociation,
            };
        } else null;
        try changes.add(.{ .observe = .{ .subject = subject, .outcome = candidate.outcome, .repair_progress = recurring } });
    }
    return envelope.outcomes.prepare(descriptor, candidate.outcome, changes.slice());
}

pub fn permitsPublication(envelope: *const envelope_module.PipelineEnvelope, prepared: *const @import("../domain/workflow_output.zig").Prepared) bool {
    const binding = @import("workflow_output_binding.zig");
    const current = values.read(&.{ .slots = envelope.slots }, binding.prepared_schema, @import("../domain/workflow_output.zig").Prepared) catch return false;
    if (current != prepared) return false;
    const origin = envelope.origins[@intFromEnum(binding.prepared_schema.key)] orelse return false;
    if (origin.lineage_conflicts.count() != 0) return false;
    return envelope.outcomes.permitsPublication(.{ .kind = .clarification, .key = binding.prepared_schema.key, .generation = origin.generation, .occurrence = origin.occurrence }, switch (prepared.terminal_outcome) {
        .ok => .ok,
        .needs_user => .needs_user,
    });
}

/// Only an exact correction, authorized repair, dependent regeneration or
/// diagnostic review of current inputs may invoke a provider with outcomes.
pub fn permitsModel(envelope: *const envelope_module.PipelineEnvelope, request: *const handoff.Request, repair_state: *const retry.State) bool {
    const current = requests.readCurrent(&.{ .slots = envelope.slots }, requests.prepared_schema) catch return false;
    if (current != request or request.prepared() == null) return false;
    if (envelope.outcomes.firstUnresolved() == null) return true;
    const correction = request.retriedAttempt();
    // A native protocol correction or runaway re-send (ADR 0039) uses this exact
    // prepared request and admits no payload.
    if (correction != null and envelope.outcomes.permitsRequest(request.id(), correction, null, &.{})) return true;
    if (request.id().purpose == .atomic_repair) {
        const packet = request.packet() orelse return false;
        const bound = packet.repairPermit() orelse return false;
        const current_permit = repair_state.currentPermit() orelse return false;
        if (!std.meta.eql(bound, current_permit)) return false;
        return envelope.outcomes.permitsRequest(request.id(), correction, .{ .owner = repair_state, .permit = current_permit }, &.{});
    }
    const packet = request.packet() orelse return false;
    const request_origin = envelope.origins[@intFromEnum(pipeline.DataKey.prepared_model_request)] orelse return false;
    if (request_origin.lineage_conflicts.count() != 0) return false;
    return permitsPacket(envelope, request.id(), correction, packet, request.part(), repair_state);
}

fn permitsPacket(envelope: *const envelope_module.PipelineEnvelope, request: *const identity.ModelRequestId, correction: ?provider.ProviderOperationId, packet: *const packets.Packet, part: ?composition.Binding, repair_state: *const retry.State) bool {
    if (!identity.purposeEqlBounded(request.purpose, packet.purpose(), 1) or !identity.unitOwnerEql(request.immutable_unit_owner_id, packet.unit())) return false;
    switch (request.purpose) {
        .initial_generation, .semantic_review => {},
        .atomic_repair, .clarification_resolution, .context_followup => return false,
    }
    var subjects: [data.key_count]association.NativeSubject = undefined;
    const covered = packetSubjects(envelope, packet, part, &subjects) orelse return false;
    if (repair_state.currentDependentPermit()) |permit| {
        return envelope.outcomes.permitsRequest(request, correction, .{ .owner = repair_state, .permit = permit, .mode = .dependent_regeneration }, covered);
    }
    return request.purpose == .semantic_review and envelope.outcomes.permitsRequest(request, correction, null, covered);
}

/// Native scope belongs to this current sealed packet. Request preparation may
/// borrow additional binding context; those dependencies cannot enlarge scope.
fn packetSubjects(envelope: *const envelope_module.PipelineEnvelope, packet: *const packets.Packet, part: ?composition.Binding, subjects: *[data.key_count]association.NativeSubject) ?[]const association.NativeSubject {
    const current = values.read(&.{ .slots = envelope.slots }, requests.packet_schema, packets.Packet) catch return null;
    if (part) |binding| {
        // A composed request derives its packet from this exact retained base.
        // The native composition owner checks current plan, epoch, schema and
        // prerequisite snapshots; an arbitrary derived packet has no scope.
        const state = @import("json_composition_workflow.zig").readState(&.{ .slots = envelope.slots }) catch return null;
        if (binding.base != current or !state.validBinding(binding) or
            !identity.unitOwnerEql(packet.unit(), current.unit()) or
            !identity.purposeEqlBounded(packet.purpose(), current.purpose(), 1)) return null;
    } else if (current != packet) return null;
    const packet_origin = envelope.origins[@intFromEnum(pipeline.DataKey.model_input_packet)] orelse return null;
    if (packet_origin.lineage_conflicts.count() != 0) return null;
    var count: usize = 0;
    for (envelope.origins, 0..) |origin_value, index| {
        const origin = origin_value orelse continue;
        if (origin.occurrence == 0) continue;
        if (!covers(packet_origin, index, origin.generation)) continue;
        subjects[count] = .{ .kind = .candidate, .key = @enumFromInt(index), .generation = origin.generation, .occurrence = origin.occurrence };
        count += 1;
    }
    return subjects[0..count];
}

fn proposedView(envelope: *const envelope_module.PipelineEnvelope, candidate: *const execution.Candidate) data.View {
    var result: data.View = .{ .slots = envelope.slots };
    for (candidate.delta.data_writes, candidate.delta.data_replacements, 0..) |write, replacement, index| {
        if (candidate.delta.data_invalidations.contains(@enumFromInt(index))) result.slots[index] = null;
        if (write) |value| result.slots[index] = value;
        if (replacement) |value| result.slots[index] = value;
    }
    return result;
}

fn hasValue(view: *const data.View, key: pipeline.DataKey) bool {
    return view.slots[@intFromEnum(key)] != null;
}

fn changed(candidate: *const execution.Candidate, key: pipeline.DataKey) bool {
    const index = @intFromEnum(key);
    return candidate.delta.data_writes[index] != null or candidate.delta.data_replacements[index] != null;
}

fn nativeSubject(envelope: *const envelope_module.PipelineEnvelope, occurrence: envelope_module.Occurrence, candidate: *const execution.Candidate, kind: association.Kind, key: pipeline.DataKey, prefer_proposed: bool) Error!association.Subject {
    const index = @intFromEnum(key);
    if ((!prefer_proposed or !changed(candidate, key)) and envelope.origins[index] != null and envelope.slots[index] != null) {
        const origin = envelope.origins[index].?;
        if (origin.generation == 0 or origin.occurrence == 0) return error.InvalidOutcomeAssociation;
        return .{ .native = .{ .kind = kind, .key = key, .generation = origin.generation, .occurrence = origin.occurrence } };
    }
    if (!changed(candidate, key)) return error.InvalidOutcomeAssociation;
    return .{ .native = .{ .kind = kind, .key = key, .generation = std.math.add(u64, envelope.generation, 1) catch return error.InvalidOutcomeAssociation, .occurrence = occurrence.ordinal } };
}

fn covers(origin: *const data.Origin, index: usize, generation: u64) bool {
    return origin.inputs[index] == generation or origin.lineage[index] == generation;
}

fn dependsOn(envelope: *const envelope_module.PipelineEnvelope, evidence: pipeline.DataKey, subject: association.Subject) bool {
    if (subject != .native) return false;
    const origin = envelope.origins[@intFromEnum(evidence)] orelse return false;
    const source = envelope.origins[@intFromEnum(subject.native.key)] orelse return false;
    if (source.generation != subject.native.generation or source.occurrence != subject.native.occurrence) return false;
    if (covers(origin, @intFromEnum(subject.native.key), subject.native.generation) or
        covers(source, @intFromEnum(evidence), origin.generation)) return true;
    // Current-retention provenance records the immediate authority frontier.
    // Reuse committed native carrier aliases for its transitive relationship,
    // restricted to exact current references rather than replacement history.
    if (envelope.checkCurrentAuthority(evidence) != null or envelope.checkCurrentAuthority(subject.native.key) != null) return false;
    var current: [data.key_count]association.NativeSubject = undefined;
    var count: usize = 0;
    for (envelope.origins, envelope.slots, 0..) |current_origin, slot, index| {
        const value = current_origin orelse continue;
        if (slot == null) continue;
        current[count] = .{ .kind = subject.native.kind, .key = @enumFromInt(index), .generation = value.generation, .occurrence = value.occurrence };
        count += 1;
    }
    return envelope.outcomes.associatedCurrentNative(subject.native, .{ .kind = subject.native.kind, .key = evidence, .generation = origin.generation, .occurrence = origin.occurrence }, current[0..count]);
}

// The canonical retry owner validates this native transition before prepare.
// A parsed captured authorization retains its exact repair reference even when
// replacement provenance no longer directly names the affected candidate.
fn repairMergeEvidence(envelope: *const envelope_module.PipelineEnvelope, descriptor: association.Descriptor, candidate: *const execution.Candidate, key: pipeline.DataKey, evidence: association.Subject) bool {
    if (evidence != .native or candidate.delta.data_replacements[@intFromEnum(key)] == null) return false;
    const transition = candidate.delta.repair_transition orelse return false;
    const permit: retry.Permit = switch (descriptor) {
        .repair_merge => if (transition == .merged and transition.merged.changed) transition.merged.permit else return false,
        .repair_validate => if (transition == .merged_validated and transition.merged_validated.changed) transition.merged_validated.permit else return false,
        else => return false,
    };
    return envelope.outcomes.referencesRepair(evidence.native, permit.key);
}

fn requestOperation(view: *const data.View, evidence: pipeline.DataKey, request: *const identity.ModelRequestId) Error!?provider.ProviderOperationId {
    const id: ?provider.ProviderOperationId = switch (evidence) {
        .provider_invocation_result => (values.read(view, raw_invocation.schema, @import("../domain/model_invocation_result.zig").Result) catch return error.InvalidOutcomeAssociation).operationId(),
        .provider_invocation_validation_result => (observation.readCurrent(view) catch return error.InvalidOutcomeAssociation).operationId(),
        .model_envelope_result => (decoded.readCurrent(view) catch return error.InvalidOutcomeAssociation).source().operationId(),
        .model_payload_schema_result => (payload.readCurrent(view) catch return error.InvalidOutcomeAssociation).source().source().operationId(),
        .assigned_provider_operation => (values.read(view, @import("workflow_model_accounting.zig").operation_schema, lifecycle.AssignedOperation) catch return error.InvalidOutcomeAssociation).record().id,
        .invoked_provider_operation => (values.read(view, @import("workflow_model_accounting.zig").invoked_schema, lifecycle.InvokedOperation) catch return error.InvalidOutcomeAssociation).operation().id,
        .terminal_provider_operation => (values.read(view, @import("workflow_model_accounting.zig").terminal_schema, lifecycle.TerminalOperation) catch return error.InvalidOutcomeAssociation).record().id,
        .provider_authorization_result => result: {
            const result = values.read(view, @import("provider_authorization_workflow.zig").schema, @import("../domain/provider_authorization_result.zig").Result) catch return error.InvalidOutcomeAssociation;
            break :result switch (result.outcome().*) {
                .failed => |failure| failure.operation_id,
                .cancelled => |operation_id| operation_id,
                .prepared => null,
            };
        },
        .accounted_model_attempt => stopped: {
            const stop = @import("workflow_model_accounting.zig").readAdvisoryStop(view) catch return error.InvalidOutcomeAssociation;
            break :stopped stop.request().protocolCorrection();
        },
        .model_request_identity_ledger => null,
        else => return error.InvalidOutcomeAssociation,
    };
    if (id) |operation_id| {
        if (operation_id.model_request_id != request) return error.InvalidOutcomeAssociation;
        if (operation_id.model_attempt_ordinal.value == 0) return error.InvalidOutcomeAssociation;
        return operation_id;
    }
    // A kind alone cannot mint the canonical native attempt identity.
    return null;
}

/// A missing final answer or a first runaway (ADR 0039) is admitted as
/// correctable, never as a failed attempt.
fn missingFinalText(changes: *Changes, source: *const observation.Result, outcome: @import("../domain/workflow.zig").OutcomeTag) Error!void {
    if (outcome != .invalid) return;
    switch (source.outcome()) {
        .validated => |evidence| if (evidence.missingFinalText())
            try changes.add(.{ .reclassify = .{ .missing_final_text = evidence } })
        else if (evidence.runaway() == .first)
            try changes.add(.{ .reclassify = .{ .runaway = evidence } }),
        .rejected, .cancelled, .advisory_stopped => {},
    }
}

fn diagnosticAdmission(view: *const data.View, evidence: pipeline.DataKey) Error!gate.Decision {
    if (evidence != .specification_support_review) return error.InvalidOutcomeAssociation;
    const value = values.read(view, @import("specification_support_workflow.zig").schema, authority_values.Value) catch return error.InvalidOutcomeAssociation;
    return switch (authority_values.payload(value).*) {
        .support => |collection| if (collection == .accepted and collection.accepted.candidate.pending_localization == null) .accepted else .rejected,
        .principle_support => |review| if (review.result == .accepted and review.result.accepted.candidate.pending_localization == null) .accepted else .rejected,
        else => .rejected,
    };
}

/// Each registered native owner reads its retained decision. This projection
/// neither reconstructs eligibility nor treats an operation tag as evidence.
fn authorizationBlocked(view: *const data.View, result: pipeline.DataKey) Error!bool {
    const blocked = switch (result) {
        .specification_coverage_repair => @import("specification_coverage_repair_workflow.zig").authorizationBlocked(view),
        .reference_reconciliation_repair => @import("reference_reconciliation_repair_workflow.zig").authorizationBlocked(view),
        .specification_repair_authorization => @import("specification_repair_workflow.zig").authorizationBlocked(view),
        .specification_support_repair => @import("specification_support_repair_workflow.zig").authorizationBlocked(view),
        else => return error.InvalidOutcomeAssociation,
    };
    return blocked catch |cause| if (cause == error.OutOfMemory) error.OutOfMemory else error.InvalidOutcomeAssociation;
}

const subject_schema = values.schema(.parsed_reference_extraction, u8, 1, 16).captured();
const evidence_schema = values.schema(.text_validated_reference_extraction, u8, 1, 16).captured();
const unrelated_schema = values.schema(.canonical_log_level, u8, 1, 16);
const subject_contract: pipeline.NodeContract = .{ .id = "test.native-subject", .kind = .action, .requires = &.{}, .produces = &.{subject_schema.key}, .side_effect = .none };
const observe_subject: association.Descriptor = .{ .observe = .{ .kind = .candidate, .subject = subject_schema.key, .evidence = subject_schema.key } };

fn nativeTestValue(envelope: *envelope_module.PipelineEnvelope, descriptor: data.Schema, value: u8) !void {
    var delta: pipeline.NodeDelta = .{};
    defer envelope.discard(&delta);
    delta.data_writes[@intFromEnum(descriptor.key)] = try values.create(std.testing.allocator, descriptor, u8, value);
    const contract: pipeline.NodeContract = .{ .id = "test.initial-value", .kind = .action, .requires = &.{}, .produces = &.{descriptor.key}, .side_effect = .none };
    try envelope.apply(contract, &delta, .ok);
}

test "native outcome preparation applies exact generation only with the whole accepted delta" {
    var envelope = envelope_module.PipelineEnvelope.init(std.testing.allocator, &.{subject_schema});
    defer envelope.deinit();
    const occurrence = try envelope.beginOccurrence(subject_contract.id);
    var candidate: execution.Candidate = .{ .outcome = .invalid, .delta = .{} };
    defer envelope.discard(&candidate.delta);
    candidate.delta.data_writes[@intFromEnum(subject_schema.key)] = try values.create(std.testing.allocator, subject_schema, u8, 1);
    var pending = try prepare(&envelope, occurrence, observe_subject, &candidate);
    defer pending.deinit();
    const expected: association.Subject = .{ .native = .{ .kind = .candidate, .key = subject_schema.key, .generation = 1, .occurrence = occurrence.ordinal } };
    try std.testing.expect((try pending.firstUnresolved()).?.subject.eql(expected));
    try std.testing.expect(envelope.outcomes.firstUnresolved() == null);
    try std.testing.expectEqual(@as(u64, 0), envelope.generation);
    // An invalid complete delta cannot apply any of the prepared references.
    var wrong = subject_contract;
    wrong.produces = &.{};
    try std.testing.expectError(error.UndeclaredWrite, envelope.applyOccurrence(occurrence, wrong, &candidate.delta, candidate.outcome));
    try std.testing.expect(envelope.outcomes.firstUnresolved() == null);
    try envelope.applyOccurrence(occurrence, subject_contract, &candidate.delta, candidate.outcome);
    try envelope.outcomes.commit(&pending);
    const actual = envelope.origins[@intFromEnum(subject_schema.key)].?;
    try std.testing.expectEqual(expected.native.generation, actual.generation);
    try std.testing.expectEqual(expected.native.occurrence, actual.occurrence);
    try std.testing.expect(envelope.outcomes.firstUnresolved().?.subject.eql(expected));
}

test "unrelated native success retains every prohibiting outcome and opaque occurrence" {
    for ([_]@import("../domain/workflow.zig").OutcomeTag{ .invalid, .failed, .blocked, .needs_user, .cancelled }) |outcome| {
        for ([_]bool{ false, true }) |is_opaque| {
            var envelope = envelope_module.PipelineEnvelope.init(std.testing.allocator, &.{ subject_schema, unrelated_schema });
            defer envelope.deinit();
            try nativeTestValue(&envelope, subject_schema, 1);
            const rejected_occurrence = try envelope.beginOccurrence("test.rejection");
            var rejection: execution.Candidate = .{ .outcome = outcome, .delta = .{} };
            var rejected = try prepare(&envelope, rejected_occurrence, if (is_opaque) .independent else observe_subject, &rejection);
            defer rejected.deinit();
            try envelope.outcomes.commit(&rejected);
            const original = envelope.outcomes.firstUnresolved().?;
            const success_occurrence = try envelope.beginOccurrence("test.unrelated-success");
            var success: execution.Candidate = .{ .outcome = .ok, .delta = .{} };
            defer envelope.discard(&success.delta);
            success.delta.data_writes[@intFromEnum(unrelated_schema.key)] = try values.create(std.testing.allocator, unrelated_schema, u8, 2);
            var pending = try prepare(&envelope, success_occurrence, .independent, &success);
            defer pending.deinit();
            try std.testing.expect(!pending.compatible(.ok));
            try std.testing.expect(pending.compatible(outcome));
            try envelope.outcomes.commit(&pending);
            try std.testing.expectEqual(outcome, envelope.outcomes.firstUnresolved().?.outcome);
            try std.testing.expect(envelope.outcomes.firstUnresolved().?.subject.eql(original.subject));
        }
    }
}

test "native evidence alias requires exact current generation in either dependency direction" {
    var envelope = envelope_module.PipelineEnvelope.init(std.testing.allocator, &.{ subject_schema, evidence_schema });
    defer envelope.deinit();
    try nativeTestValue(&envelope, subject_schema, 1);
    var evidence: pipeline.NodeDelta = .{};
    defer envelope.discard(&evidence);
    evidence.data_writes[@intFromEnum(evidence_schema.key)] = try values.create(std.testing.allocator, evidence_schema, u8, 2);
    try envelope.apply(.{ .id = "test.evidence", .kind = .action, .requires = &.{subject_schema.key}, .produces = &.{evidence_schema.key}, .side_effect = .none }, &evidence, .ok);
    const occurrence = try envelope.beginOccurrence("test.related");
    var candidate: execution.Candidate = .{ .outcome = .ok, .delta = .{} };
    var related = try prepare(&envelope, occurrence, .{ .preserve = .{ .kind = .candidate, .subject = subject_schema.key, .evidence = evidence_schema.key } }, &candidate);
    defer related.deinit();
    var reverse = try prepare(&envelope, occurrence, .{ .preserve = .{ .kind = .candidate, .subject = evidence_schema.key, .evidence = subject_schema.key } }, &candidate);
    defer reverse.deinit();
    // The captured evidence still exists, but targets the prior generation.
    var replacement: pipeline.NodeDelta = .{};
    defer envelope.discard(&replacement);
    replacement.data_replacements[@intFromEnum(subject_schema.key)] = try values.create(std.testing.allocator, subject_schema, u8, 3);
    try envelope.apply(.{ .id = "test.new-generation", .kind = .action, .requires = &.{}, .produces = &.{}, .replaces = &.{subject_schema.key}, .side_effect = .none }, &replacement, .ok);
    const stale_occurrence = try envelope.beginOccurrence("test.stale-evidence");
    try std.testing.expectError(error.InvalidOutcomeAssociation, prepare(&envelope, stale_occurrence, .{ .preserve = .{ .kind = .candidate, .subject = subject_schema.key, .evidence = evidence_schema.key } }, &candidate));
    try std.testing.expectError(error.InvalidOutcomeAssociation, prepare(&envelope, stale_occurrence, .{ .preserve = .{ .kind = .candidate, .subject = evidence_schema.key, .evidence = subject_schema.key } }, &candidate));
}

test "transitive native carriers require current generations rather than historical replacement aliases" {
    for ([_]bool{ false, true }) |captured| {
        var source_schema = values.schema(.parsed_reference_extraction, u8, 1, 16);
        var carrier_schema = values.schema(.text_validated_reference_extraction, u8, 1, 16);
        var result_schema = values.schema(.canonical_log_level, u8, 1, 16);
        const foreign_schema = values.schema(.logging_policy, u8, 1, 16);
        if (captured) {
            source_schema = source_schema.captured();
            carrier_schema = carrier_schema.captured();
            result_schema = result_schema.captured();
        }
        var envelope = envelope_module.PipelineEnvelope.init(std.testing.allocator, &.{ source_schema, carrier_schema, result_schema, foreign_schema });
        defer envelope.deinit();
        try nativeTestValue(&envelope, source_schema, 1);
        try nativeTestValue(&envelope, foreign_schema, 4);
        const rejected_occurrence = try envelope.beginOccurrence("test.source-rejection");
        var rejection: execution.Candidate = .{ .outcome = .invalid, .delta = .{} };
        var rejected = try prepare(&envelope, rejected_occurrence, observe_subject, &rejection);
        defer rejected.deinit();
        try envelope.outcomes.commit(&rejected);
        const original = envelope.outcomes.firstUnresolved().?;
        const schemas = [_]data.Schema{ source_schema, carrier_schema, result_schema };
        for (schemas[0..2], schemas[1..3]) |input, output| {
            const contract: pipeline.NodeContract = .{ .id = "test.native-carrier", .kind = .action, .requires = &.{input.key}, .produces = &.{output.key}, .side_effect = .none };
            const occurrence = try envelope.beginOccurrence(contract.id);
            var candidate: execution.Candidate = .{ .outcome = .ok, .delta = .{} };
            defer envelope.discard(&candidate.delta);
            candidate.delta.data_writes[@intFromEnum(output.key)] = try values.create(std.testing.allocator, output, u8, 2);
            var pending = try prepare(&envelope, occurrence, .{ .preserve = .{ .kind = .candidate, .subject = input.key, .evidence = input.key, .result = output.key } }, &candidate);
            defer pending.deinit();
            try envelope.applyOccurrence(occurrence, contract, &candidate.delta, candidate.outcome);
            try envelope.outcomes.commit(&pending);
        }
        const result_origin = envelope.origins[@intFromEnum(result_schema.key)].?;
        try std.testing.expect(!covers(result_origin, @intFromEnum(source_schema.key), original.subject.native.generation));
        const occurrence = try envelope.beginOccurrence("test.transitive-evidence");
        var candidate: execution.Candidate = .{ .outcome = .ok, .delta = .{} };
        {
            var forward = try prepare(&envelope, occurrence, .{ .preserve = .{ .kind = .candidate, .subject = source_schema.key, .evidence = result_schema.key } }, &candidate);
            defer forward.deinit();
            var reverse = try prepare(&envelope, occurrence, .{ .preserve = .{ .kind = .candidate, .subject = result_schema.key, .evidence = source_schema.key } }, &candidate);
            defer reverse.deinit();
            try std.testing.expect((try forward.firstUnresolved()).?.subject.eql(original.subject));
            try std.testing.expect(!forward.compatible(.ok));
        }
        try std.testing.expectError(error.InvalidOutcomeAssociation, prepare(&envelope, occurrence, .{ .preserve = .{ .kind = .candidate, .subject = foreign_schema.key, .evidence = result_schema.key } }, &candidate));
        // Keep the historical alias from the source to its replacement. It
        // preserves failure identity but cannot validate prior native evidence.
        const replacement_contract: pipeline.NodeContract = .{ .id = "test.carrier-replacement", .kind = .action, .requires = &.{source_schema.key}, .produces = &.{}, .replaces = &.{source_schema.key}, .side_effect = .none };
        const replacement_occurrence = try envelope.beginOccurrence(replacement_contract.id);
        var replacement: execution.Candidate = .{ .outcome = .ok, .delta = .{} };
        defer envelope.discard(&replacement.delta);
        replacement.delta.data_replacements[@intFromEnum(source_schema.key)] = try values.create(std.testing.allocator, source_schema, u8, 3);
        var replaced = try prepare(&envelope, replacement_occurrence, .{ .preserve = .{ .kind = .candidate, .subject = source_schema.key, .evidence = source_schema.key } }, &replacement);
        defer replaced.deinit();
        try envelope.applyOccurrence(replacement_occurrence, replacement_contract, &replacement.delta, replacement.outcome);
        try envelope.outcomes.commit(&replaced);
        if (captured) try std.testing.expect(envelope.checkCurrentAuthority(result_schema.key) == null);
        const stale_occurrence = try envelope.beginOccurrence("test.stale-transitive-evidence");
        try std.testing.expectError(error.InvalidOutcomeAssociation, prepare(&envelope, stale_occurrence, .{ .preserve = .{ .kind = .candidate, .subject = source_schema.key, .evidence = result_schema.key } }, &candidate));
        try std.testing.expectError(error.InvalidOutcomeAssociation, prepare(&envelope, stale_occurrence, .{ .preserve = .{ .kind = .candidate, .subject = result_schema.key, .evidence = source_schema.key } }, &candidate));
        try std.testing.expect(envelope.outcomes.firstUnresolved().?.subject.eql(original.subject));
    }
}

test "native merges carry only the exact authorized repair reference through captured replacement" {
    for ([_]bool{ false, true }) |combined_validation| for ([_]bool{ false, true }) |same_target| {
        const authorization_schema = values.schema(.canonical_log_level, u8, 1, 16).captured();
        const foreign_schema = values.schema(.logging_policy, u8, 1, 16).captured();
        var envelope = envelope_module.PipelineEnvelope.init(std.testing.allocator, &.{ subject_schema, evidence_schema, authorization_schema, foreign_schema });
        defer envelope.deinit();
        var native_retry = retry.State.init(std.testing.allocator);
        defer native_retry.deinit();
        var foreign_retry = retry.State.init(std.testing.allocator);
        defer foreign_retry.deinit();
        const permit: retry.Permit = .{ .key = .{ .scope = @splat(1), .target = @splat(2), .family = @splat(3) }, .authorization = @splat(4), .revision = 1, .maximum_targets = 2 };
        const foreign: retry.Permit = .{ .key = .{ .scope = @splat(5), .target = @splat(6), .family = @splat(7) }, .authorization = @splat(8), .revision = 1, .maximum_targets = 2 };
        try nativeTestValue(&envelope, subject_schema, 1);
        try nativeTestValue(&envelope, evidence_schema, 2);
        try nativeTestValue(&envelope, foreign_schema, 3);
        for ([_]pipeline.DataKey{ subject_schema.key, foreign_schema.key }, [_]retry.Permit{ permit, foreign }) |key, bound| {
            const occurrence = try envelope.beginOccurrence("test.native-repair-rejection");
            var rejected_candidate: execution.Candidate = .{ .outcome = .invalid, .delta = .{} };
            var rejected = try prepare(&envelope, occurrence, .{ .observe = .{ .kind = .authority, .subject = key, .evidence = key } }, &rejected_candidate);
            defer rejected.deinit();
            try envelope.outcomes.commit(&rejected);
            const authorization_occurrence = try envelope.beginOccurrence("test.native-authorization");
            var authorization: execution.Candidate = .{ .outcome = .ok, .delta = .{ .repair_transition = .{ .authorized = bound } } };
            defer envelope.discard(&authorization.delta);
            if (key == subject_schema.key) authorization.delta.data_writes[@intFromEnum(authorization_schema.key)] = try values.create(std.testing.allocator, authorization_schema, u8, 4);
            const retry_owner = if (key == subject_schema.key) &native_retry else &foreign_retry;
            const native_progress = try retry_owner.prepare(authorization.delta.repair_transition.?);
            var authorized = try prepare(&envelope, authorization_occurrence, .{ .repair_authorize = .{ .kind = .authority, .subject = key, .evidence = key, .result = if (key == subject_schema.key) authorization_schema.key else null } }, &authorization);
            defer authorized.deinit();
            try envelope.applyOccurrence(authorization_occurrence, .{ .id = "test.native-authorization", .kind = .action, .requires = &.{ subject_schema.key, evidence_schema.key, foreign_schema.key }, .produces = if (key == subject_schema.key) &.{authorization_schema.key} else &.{}, .side_effect = .none, .repair_role = .authorize }, &authorization.delta, authorization.outcome);
            try envelope.outcomes.commit(&authorized);
            try retry_owner.commit(native_progress);
        }
        // Native parsing keeps the sealed authorization while replacing its
        // captured transport slot. The old carrier remains only in reference
        // history, so it cannot qualify as ordinary current provenance.
        const parse_occurrence = try envelope.beginOccurrence("test.parse-native-authorization");
        var parsed: execution.Candidate = .{ .outcome = .ok, .delta = .{} };
        defer envelope.discard(&parsed.delta);
        parsed.delta.data_replacements[@intFromEnum(authorization_schema.key)] = try values.create(std.testing.allocator, authorization_schema, u8, 5);
        var parsed_outcomes = try prepare(&envelope, parse_occurrence, .{ .preserve = .{ .kind = .authority, .subject = authorization_schema.key, .evidence = authorization_schema.key, .result = authorization_schema.key } }, &parsed);
        defer parsed_outcomes.deinit();
        try envelope.applyOccurrence(parse_occurrence, .{ .id = "test.parse-native-authorization", .kind = .action, .requires = &.{authorization_schema.key}, .produces = &.{}, .replaces = &.{authorization_schema.key}, .side_effect = .none }, &parsed.delta, parsed.outcome);
        try envelope.outcomes.commit(&parsed_outcomes);
        const target = if (same_target) subject_schema else evidence_schema;
        const merge_occurrence = try envelope.beginOccurrence("test.native-merge");
        const original_subject = try nativeSubject(&envelope, merge_occurrence, &parsed, .candidate, target.key, false);
        try std.testing.expect(!dependsOn(&envelope, authorization_schema.key, original_subject));
        var merged: execution.Candidate = .{ .outcome = .ok, .delta = .{} };
        defer envelope.discard(&merged.delta);
        merged.delta.data_replacements[@intFromEnum(target.key)] = try values.create(std.testing.allocator, target, u8, 6);
        merged.delta.data_invalidations.insert(authorization_schema.key);
        const binding: association.Binding = .{ .kind = .candidate, .subject = target.key, .evidence = authorization_schema.key, .result = target.key };
        const descriptor: association.Descriptor = if (combined_validation) .{ .repair_validate = binding } else .{ .repair_merge = binding };
        const transition: retry.Transition = if (combined_validation)
            .{ .merged_validated = .{ .permit = permit, .changed = true, .revision_after = 2, .result = .resolved } }
        else
            .{ .merged = .{ .permit = permit, .changed = true, .revision_after = 2, .validation = .dependent_review } };
        const state_revision = envelope.outcomes.revision;
        // Neither missing native progress, another transition kind, nor a
        // disconnected parent's authorization permits this candidate bridge.
        try std.testing.expectError(error.InvalidOutcomeAssociation, prepare(&envelope, merge_occurrence, descriptor, &merged));
        merged.delta.repair_transition = .{ .validated = .{ .permit = permit, .revision = 1, .result = .resolved } };
        try std.testing.expectError(error.InvalidOutcomeAssociation, prepare(&envelope, merge_occurrence, descriptor, &merged));
        merged.delta.repair_transition = if (combined_validation) .{ .merged_validated = .{ .permit = foreign, .changed = true, .revision_after = 2, .result = .resolved } } else .{ .merged = .{ .permit = foreign, .changed = true, .revision_after = 2, .validation = .dependent_review } };
        try std.testing.expectError(error.InvalidOutcomeAssociation, prepare(&envelope, merge_occurrence, descriptor, &merged));
        merged.delta.repair_transition = transition;
        var foreign_binding = binding;
        foreign_binding.evidence = foreign_schema.key;
        try std.testing.expectError(error.InvalidOutcomeAssociation, prepare(&envelope, merge_occurrence, if (combined_validation) .{ .repair_validate = foreign_binding } else .{ .repair_merge = foreign_binding }, &merged));
        try std.testing.expectError(error.InvalidOutcomeAssociation, prepare(&envelope, merge_occurrence, .{ .preserve = binding }, &merged));
        try std.testing.expectEqual(state_revision, envelope.outcomes.revision);
        try std.testing.expectEqual(@as(usize, 2), envelope.outcomes.entries.items.len);
        const native_progress = try native_retry.prepare(transition);
        var merged_outcomes = try prepare(&envelope, merge_occurrence, descriptor, &merged);
        defer merged_outcomes.deinit();
        try envelope.applyOccurrence(merge_occurrence, .{ .id = "test.native-merge", .kind = .action, .requires = &.{ target.key, authorization_schema.key }, .produces = &.{}, .replaces = &.{target.key}, .invalidates = &.{authorization_schema.key}, .side_effect = .none, .repair_role = if (combined_validation) .merge_validate else .merge }, &merged.delta, merged.outcome);
        try envelope.outcomes.commit(&merged_outcomes);
        try native_retry.commit(native_progress);
        try std.testing.expectEqual(@as(usize, if (combined_validation) 1 else 2), envelope.outcomes.entries.items.len);
        if (combined_validation) {
            try std.testing.expectEqual(foreign_schema.key, envelope.outcomes.firstUnresolved().?.subject.native.key);
        } else {
            try std.testing.expectEqual(subject_schema.key, envelope.outcomes.firstUnresolved().?.subject.native.key);
        }
        try std.testing.expect(!envelope.outcomes.compatible(.ok));
    };
}

test "clarification outcome changes only with its sealed canonical refresh result" {
    const needs_schema = values.schema(.clarification_needs, u8, 1, 16);
    var envelope = envelope_module.PipelineEnvelope.init(std.testing.allocator, &.{ needs_schema, clarification.state_schema });
    defer envelope.deinit();
    try nativeTestValue(&envelope, needs_schema, 1);
    const rejected_occurrence = try envelope.beginOccurrence("test.needs-user");
    var rejected_candidate: execution.Candidate = .{ .outcome = .needs_user, .delta = .{} };
    var rejected = try prepare(&envelope, rejected_occurrence, .{ .observe = .{ .kind = .clarification, .subject = .clarification_needs, .evidence = .clarification_needs } }, &rejected_candidate);
    defer rejected.deinit();
    try envelope.outcomes.commit(&rejected);
    const occurrence = try envelope.beginOccurrence("test.refresh");
    var candidate: execution.Candidate = .{ .outcome = .blocked, .delta = .{} };
    defer envelope.discard(&candidate.delta);
    candidate.delta.data_writes[@intFromEnum(clarification.state_schema.key)] = try values.create(std.testing.allocator, clarification.state_schema, @import("../domain/clarification_refresh.zig").Result, .{ .blocked = .protected_clarification });
    const descriptor = clarification.Refresh.outcome_association;
    var blocked = try prepare(&envelope, occurrence, descriptor, &candidate);
    defer blocked.deinit();
    try std.testing.expect(blocked.compatible(.blocked));
    try std.testing.expect(!blocked.compatible(.needs_user));
    try std.testing.expect(envelope.outcomes.compatible(.needs_user));
    candidate.outcome = .ok;
    try std.testing.expectError(error.InvalidOutcomeAssociation, prepare(&envelope, occurrence, descriptor, &candidate));
    try std.testing.expect(envelope.outcomes.compatible(.needs_user));
}

test "diagnostic admission requires the sealed accepted source or principle collection" {
    const support_schema = @import("specification_support_workflow.zig").schema;
    const support = @import("../domain/specification_support.zig");
    const native_inputs: @import("../domain/required_authority.zig").Inputs = .{
        .feature = .{ .bytes = "fixture" },
        .detected_at = .spec,
        .authorities = &.{},
        .seeds = &.{},
        .evidence = &.{},
    };
    for (0..5) |mode| {
        var envelope = envelope_module.PipelineEnvelope.init(std.testing.allocator, &.{support_schema});
        defer envelope.deinit();
        const initial_owner = try authority_values.create(std.testing.allocator, .{});
        var initial = try authority_values.publish(std.testing.allocator, support_schema, initial_owner, .ok);
        defer envelope.discard(&initial.delta);
        try envelope.apply(.{ .id = "test.support-source", .kind = .action, .requires = &.{}, .produces = &.{support_schema.key}, .side_effect = .none }, &initial.delta, .ok);
        const rejection_occurrence = try envelope.beginOccurrence("test.support-rejection");
        var invalid: execution.Candidate = .{ .outcome = .invalid, .delta = .{} };
        var pending = try prepare(&envelope, rejection_occurrence, .{ .observe = .{ .kind = .candidate, .subject = support_schema.key, .evidence = support_schema.key } }, &invalid);
        defer pending.deinit();
        try envelope.outcomes.commit(&pending);
        const source: @FieldType(support.Source.Collection, "accepted") = .{ .inputs = native_inputs, .candidate = .{
            .review = .{ .entries = &.{} },
            .origin = null,
            .origins = &.{},
            .pending_localization = if (mode == 3) 1 else null,
        } };
        const owner = try authority_values.create(std.testing.allocator, .{ .slots = envelope.slots });
        owner.payload = switch (mode) {
            0 => .support_initial,
            1, 3 => .{ .support = .{ .accepted = source } },
            2, 4 => .{ .principle_support = .{ .pending = .{ .source = source, .inputs = native_inputs }, .result = .{ .accepted = .{
                .inputs = native_inputs,
                .candidate = .{ .review = .{ .entries = &.{} }, .origin = null, .origins = &.{}, .pending_localization = if (mode == 4) 1 else null },
            } } } },
            else => unreachable,
        };
        var reviewed = try authority_values.publish(std.testing.allocator, support_schema, owner, .ok);
        defer envelope.discard(&reviewed.delta);
        const index = @intFromEnum(support_schema.key);
        reviewed.delta.data_replacements[index] = reviewed.delta.data_writes[index];
        reviewed.delta.data_writes[index] = null;
        const occurrence = try envelope.beginOccurrence("test.support-admission");
        var accepted = try prepare(&envelope, occurrence, .{ .diagnostic_admission = .{ .kind = .candidate, .subject = support_schema.key, .evidence = support_schema.key, .result = support_schema.key } }, &reviewed);
        defer accepted.deinit();
        try std.testing.expectEqual(mode == 1 or mode == 2, accepted.compatible(.ok));
        try std.testing.expect(envelope.outcomes.firstUnresolved() != null);
        try std.testing.expectEqual(@as(u64, 1), envelope.generation);
    }
}

test "semantic review scope covers exact packet inputs and cannot inherit newer binding context" {
    // These are native provenance values; no request or provider is fabricated.
    const context_schema = values.schema(.prepared_model_request, u8, 1, 16).captured();
    var envelope = envelope_module.PipelineEnvelope.init(std.testing.allocator, &.{ subject_schema, requests.packet_schema, context_schema });
    defer envelope.deinit();
    try nativeTestValue(&envelope, subject_schema, 1);
    const original = envelope.origins[@intFromEnum(subject_schema.key)].?;
    const original_subject: association.NativeSubject = .{ .kind = .candidate, .key = subject_schema.key, .generation = original.generation, .occurrence = original.occurrence };
    const packet = try packets.create(std.testing.allocator, "{}", .workflow_step, .{ .semantic_review = .{ .bytes = "native-review" } }, null);
    _ = try packets.retain(packet);
    defer packets.release(packet);
    var packet_delta: pipeline.NodeDelta = .{};
    defer envelope.discard(&packet_delta);
    packet_delta.data_writes[@intFromEnum(requests.packet_schema.key)] = try requests.adoptPacket(std.testing.allocator, packet);
    try envelope.apply(.{ .id = "test.review-packet", .kind = .action, .requires = &.{subject_schema.key}, .produces = &.{requests.packet_schema.key}, .side_effect = .none }, &packet_delta, .ok);
    var storage: [data.key_count]association.NativeSubject = undefined;
    try std.testing.expect(packetContains(packetSubjects(&envelope, packet, null, &storage).?, original_subject));

    var replacement: pipeline.NodeDelta = .{};
    defer envelope.discard(&replacement);
    replacement.data_replacements[@intFromEnum(subject_schema.key)] = try values.create(std.testing.allocator, subject_schema, u8, 2);
    try envelope.apply(.{ .id = "test.new-candidate", .kind = .action, .requires = &.{}, .produces = &.{}, .replaces = &.{subject_schema.key}, .side_effect = .none }, &replacement, .ok);
    const current = envelope.origins[@intFromEnum(subject_schema.key)].?;
    const current_subject: association.NativeSubject = .{ .kind = .candidate, .key = subject_schema.key, .generation = current.generation, .occurrence = current.occurrence };
    var context: pipeline.NodeDelta = .{};
    defer envelope.discard(&context);
    context.data_writes[@intFromEnum(context_schema.key)] = try values.create(std.testing.allocator, context_schema, u8, 3);
    try envelope.apply(.{ .id = "test.binding-context", .kind = .action, .requires = &.{ subject_schema.key, requests.packet_schema.key }, .produces = &.{context_schema.key}, .side_effect = .none }, &context, .ok);
    try std.testing.expect(covers(envelope.origins[@intFromEnum(context_schema.key)].?, @intFromEnum(subject_schema.key), current_subject.generation));
    const stale_scope = packetSubjects(&envelope, packet, null, &storage).?;
    try std.testing.expect(!packetContains(stale_scope, original_subject));
    try std.testing.expect(!packetContains(stale_scope, current_subject));

    const fresh = try packets.create(std.testing.allocator, "{}", .workflow_step, .{ .semantic_review = .{ .bytes = "native-review" } }, null);
    packet_delta.data_replacements[@intFromEnum(requests.packet_schema.key)] = try requests.adoptPacket(std.testing.allocator, fresh);
    try envelope.apply(.{ .id = "test.fresh-review-packet", .kind = .action, .requires = &.{subject_schema.key}, .produces = &.{}, .replaces = &.{requests.packet_schema.key}, .side_effect = .none }, &packet_delta, .ok);
    try std.testing.expect(packetSubjects(&envelope, packet, null, &storage) == null);
    try std.testing.expect(packetContains(packetSubjects(&envelope, fresh, null, &storage).?, current_subject));
}

test "dependent regeneration requires native merged authority and current packet scope" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const schema_bytes = "{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":10}},\"required\":[\"value\"],\"additionalProperties\":false}";
    const plan_bytes = "{\"schema\":\"json-composition/v1\",\"result\":\"result\",\"parts\":{\"value\":{\"paths\":[\"/value\"],\"input-context\":\"value\"}}}";
    const raw_schema = try std.json.parseFromSlice(std.json.Value, allocator, schema_bytes, .{});
    const raw_plan = try std.json.parseFromSlice(std.json.Value, allocator, plan_bytes, .{});
    const canonical = try @import("../domain/model_result_schema.zig").compile(allocator, raw_schema.value, schema_bytes);
    const plan = try @import("../domain/json_composition.zig").compile(allocator, raw_plan.value, plan_bytes, canonical);
    const compositions = @import("json_composition_workflow.zig");
    for ([_]retry.ValidationMode{ .native, .dependent_review }) |validation| {
        var envelope = envelope_module.PipelineEnvelope.init(std.testing.allocator, &.{ subject_schema, unrelated_schema, requests.packet_schema, compositions.state_schema });
        defer envelope.deinit();
        var native_retry = retry.State.init(std.testing.allocator);
        defer native_retry.deinit();
        const owner = try identity.createInitial(std.testing.allocator, identity.RequestPurposeRegistry.all());
        defer identity.deinitOwner(owner);
        const assignment = try identity.createSuccessor(identity.ledger(owner), .initial, .workflow_step, .{ .workflow_id = .{ .bytes = "native-regeneration" }, .workflow_version = 1, .workflow_step_id = .{ .bytes = "model-call" } }, .initial_generation);
        defer identity.deinitOwner(assignment.owner);
        const permit: retry.Permit = .{ .key = .{ .scope = @splat(1), .target = @splat(2), .family = @splat(3) }, .authorization = @splat(4), .revision = 1, .maximum_targets = 1 };
        try nativeTestValue(&envelope, subject_schema, 1);
        try nativeTestValue(&envelope, unrelated_schema, 2);
        const rejected_occurrence = try envelope.beginOccurrence("test.regeneration-rejection");
        var rejection: execution.Candidate = .{ .outcome = .invalid, .delta = .{} };
        var rejected = try prepare(&envelope, rejected_occurrence, observe_subject, &rejection);
        defer rejected.deinit();
        try envelope.outcomes.commit(&rejected);
        const authorization_occurrence = try envelope.beginOccurrence("test.regeneration-authorization");
        var authorization: execution.Candidate = .{ .outcome = .ok, .delta = .{ .repair_transition = .{ .authorized = permit } } };
        const authorized_progress = try native_retry.prepare(authorization.delta.repair_transition.?);
        var authorized = try prepare(&envelope, authorization_occurrence, .{ .repair_authorize = .{ .kind = .candidate, .subject = subject_schema.key, .evidence = subject_schema.key } }, &authorization);
        defer authorized.deinit();
        try envelope.applyOccurrence(authorization_occurrence, .{ .id = "test.regeneration-authorization", .kind = .action, .requires = &.{subject_schema.key}, .produces = &.{}, .side_effect = .none, .repair_role = .authorize }, &authorization.delta, authorization.outcome);
        try envelope.outcomes.commit(&authorized);
        try native_retry.commit(authorized_progress);
        const original = try packets.create(std.testing.allocator, "{}", .workflow_step, .initial_generation, null);
        _ = try packets.retain(original);
        defer packets.release(original);
        var packet_delta: pipeline.NodeDelta = .{};
        defer envelope.discard(&packet_delta);
        packet_delta.data_writes[@intFromEnum(requests.packet_schema.key)] = try requests.adoptPacket(std.testing.allocator, original);
        try envelope.apply(.{ .id = "test.regeneration-packet", .kind = .action, .requires = &.{subject_schema.key}, .produces = &.{requests.packet_schema.key}, .side_effect = .none }, &packet_delta, .ok);
        // Authorization alone is insufficient for a generation continuation.
        try std.testing.expect(!permitsPacket(&envelope, assignment.model_request_id, null, original, null, &native_retry));
        const merge_occurrence = try envelope.beginOccurrence("test.regeneration-merge");
        var merged: execution.Candidate = .{ .outcome = .ok, .delta = .{ .repair_transition = .{ .merged = .{ .permit = permit, .changed = true, .revision_after = 2, .validation = validation } } } };
        defer envelope.discard(&merged.delta);
        merged.delta.data_replacements[@intFromEnum(subject_schema.key)] = try values.create(std.testing.allocator, subject_schema, u8, 3);
        merged.delta.data_invalidations.insert(unrelated_schema.key);
        const merged_progress = try native_retry.prepare(merged.delta.repair_transition.?);
        var merged_outcomes = try prepare(&envelope, merge_occurrence, .{ .repair_merge = .{ .kind = .candidate, .subject = subject_schema.key, .evidence = subject_schema.key, .result = subject_schema.key } }, &merged);
        defer merged_outcomes.deinit();
        try envelope.applyOccurrence(merge_occurrence, .{ .id = "test.regeneration-merge", .kind = .action, .requires = &.{subject_schema.key}, .produces = &.{}, .replaces = &.{subject_schema.key}, .invalidates = &.{unrelated_schema.key}, .side_effect = .none, .repair_role = .merge }, &merged.delta, merged.outcome);
        try envelope.outcomes.commit(&merged_outcomes);
        try native_retry.commit(merged_progress);
        // A sealed packet built before replacement cannot cover the new source.
        try std.testing.expect(!permitsPacket(&envelope, assignment.model_request_id, null, original, null, &native_retry));
        const base = try packets.create(std.testing.allocator, "{}", .workflow_step, .initial_generation, null);
        defer packets.release(base);
        const fresh = try packets.withAssignmentContexts(std.testing.allocator, base, &.{.{ .id = .{ .bytes = "value" }, .body = "{\"purpose\":\"State the value\"}" }});
        packet_delta.data_replacements[@intFromEnum(requests.packet_schema.key)] = try requests.adoptPacket(std.testing.allocator, fresh);
        try envelope.apply(.{ .id = "test.current-regeneration-packet", .kind = .action, .requires = &.{subject_schema.key}, .produces = &.{}, .replaces = &.{requests.packet_schema.key}, .side_effect = .none }, &packet_delta, .ok);
        const generation = envelope.generation;
        const revision = envelope.outcomes.revision;
        try std.testing.expectEqual(validation == .dependent_review, permitsPacket(&envelope, assignment.model_request_id, null, fresh, null, &native_retry));
        try std.testing.expect(!permitsPacket(&envelope, assignment.model_request_id, null, original, null, &native_retry));
        var composed = construct: {
            const composition_owner = try compositions.Owner.create(std.testing.allocator, &.{ .slots = envelope.slots }, &.{.model_input_packet});
            errdefer composition_owner.destroy();
            composition_owner.payload = .{ .state = try composition.State.init(composition_owner.arena.allocator(), plan, fresh, identity.ledger(assignment.owner).stageRunEpochId()) };
            break :construct try compositions.publish(composition_owner, compositions.state_schema, false, &.{});
        };
        defer envelope.discard(&composed.delta);
        try envelope.apply(.{ .id = "test.native-composition", .kind = .action, .requires = &.{requests.packet_schema.key}, .produces = &.{compositions.state_schema.key}, .side_effect = .none }, &composed.delta, composed.outcome);
        const state = try compositions.readState(&.{ .slots = envelope.slots });
        const part = try state.select(allocator, 0);
        const projected = try state.packet(std.testing.allocator, part);
        defer packets.release(projected);
        try std.testing.expect(projected != fresh);
        try std.testing.expect(!permitsPacket(&envelope, assignment.model_request_id, null, projected, null, &native_retry));
        try std.testing.expectEqual(validation == .dependent_review, permitsPacket(&envelope, assignment.model_request_id, null, projected, part, &native_retry));
        var foreign_part = part;
        foreign_part.base = original;
        try std.testing.expect(!permitsPacket(&envelope, assignment.model_request_id, null, projected, foreign_part, &native_retry));
        foreign_part = part;
        const foreign_owner = try identity.createInitial(std.testing.allocator, identity.RequestPurposeRegistry.all());
        defer identity.deinitOwner(foreign_owner);
        foreign_part.epoch = identity.ledger(foreign_owner).stageRunEpochId();
        try std.testing.expect(!permitsPacket(&envelope, assignment.model_request_id, null, projected, foreign_part, &native_retry));
        // Permission is a read-only query and never clears the repair fault.
        try std.testing.expectEqual(generation + 1, envelope.generation);
        try std.testing.expectEqual(revision, envelope.outcomes.revision);
        try std.testing.expect(envelope.outcomes.firstUnresolved() != null);
        const independent_occurrence = try envelope.beginOccurrence("test.unrelated-regeneration-fault");
        var independent: execution.Candidate = .{ .outcome = .invalid, .delta = .{} };
        var blocked = try prepare(&envelope, independent_occurrence, .independent, &independent);
        defer blocked.deinit();
        try envelope.outcomes.commit(&blocked);
        try std.testing.expect(!permitsPacket(&envelope, assignment.model_request_id, null, fresh, null, &native_retry));
    }
}

fn packetContains(subjects: []const association.NativeSubject, expected: association.NativeSubject) bool {
    for (subjects) |subject| if ((association.Subject{ .native = subject }).eql(.{ .native = expected })) return true;
    return false;
}
