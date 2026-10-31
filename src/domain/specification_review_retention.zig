//! Execution-local source receipts. Historical findings acquire current authority
//! only through the existing prefix collector and complete native admission.
const std = @import("std");
const authority = @import("required_authority.zig");
const source = @import("specification_support.zig").Source;
const provenance = @import("specification_provenance.zig");
const handoff = @import("model_request_handoff.zig");
const identity = @import("model_request_identity.zig");
const Origin = @import("model_candidate_origin.zig").Origin;
const packets = @import("model_input_packet.zig");
const references = @import("reference_reconciliation.zig");
pub const Error = source.Error || handoff.Error;

/// Slices and exact immutable request/proof pointers borrow the application
/// retained-candidate owner. This structure is never serialized or resumed.
pub const Receipt = struct {
    request: *const handoff.Request,
    origin: Origin,
    subjects: []const authority.Seed,
    applicability: []const source.Applicability,
    findings: []const source.Finding,
};
pub const Scope = struct {
    epoch: identity.StageRunEpochId,
    feature: @import("feature_identity.zig").FeatureId,
    reference: @import("reference_identity.zig").StateId,
    reference_records: @import("reference_support.zig").Records,
    input_revision: u64,
    sources: @import("reference_evidence.zig").Inputs,
    candidate: source.Candidate,
    origin_request: ?*const identity.ModelRequestId,
    occurrences: []const source.Occurrence,
};
pub const History = struct { receipts: []const Receipt = &.{}, scope: ?Scope = null };

fn eligibleInputs(inputs: authority.Inputs) bool {
    return inputs.projection == .specification and inputs.specification != null and inputs.brief != null;
}
fn sameScope(scope: Scope, inputs: authority.Inputs, ledger: *const identity.ModelRequestIdentityLedger) bool {
    const records = inputs.references orelse return false;
    return eligibleInputs(inputs) and scope.epoch.eql(ledger.stageRunEpochId()) and
        std.mem.eql(u8, scope.feature.bytes, inputs.feature.bytes) and scope.reference.eql(records.items.state_id) and
        sameSlice(references.Item, scope.reference_records.items.entries, records.items.entries) and sameSlice(references.extraction.ChunkResult, scope.reference_records.items.extraction, records.items.extraction) and
        sameSlice(references.ClaimDisposition, scope.reference_records.dispositions, records.dispositions) and sameSlice(references.Signal, scope.reference_records.signals, records.signals) and sameSlice(references.Conflict, scope.reference_records.conflicts, records.conflicts);
}
fn sameSlice(comptime T: type, left: []const T, right: []const T) bool {
    return left.ptr == right.ptr and left.len == right.len;
}
fn candidateOf(result: source.Collection) ?source.Candidate {
    return switch (result) {
        .accepted => |value| value.candidate,
        .pending => |value| value,
        .rejected => |value| value.candidate,
    };
}
fn equal(comptime T: type, a: std.mem.Allocator, left: T, right: T) std.mem.Allocator.Error!bool {
    const old = try std.json.Stringify.valueAlloc(a, left, .{});
    defer a.free(old);
    const current = try std.json.Stringify.valueAlloc(a, right, .{});
    defer a.free(current);
    return std.mem.eql(u8, old, current);
}

fn checkCurrent(a: std.mem.Allocator, inputs: authority.Inputs, context: provenance.Context, result: source.Collection, candidate: source.Candidate) Error!void {
    const current = try source.validateWorking(a, inputs, context.inputs, candidate);
    if (std.meta.activeTag(current) != std.meta.activeTag(result)) return error.InvalidRequiredAuthority;
    if (current == .rejected and !try equal(source.Rejection, a, current.rejected.rejection, result.rejected.rejection)) return error.InvalidRequiredAuthority;
}

pub fn record(a: std.mem.Allocator, history: History, inputs: authority.Inputs, context: provenance.Context, guidance: *const @import("packet_guidance.zig").Guidance, result: source.Collection, request: *const handoff.Request, proof: *const @import("model_payload_schema.zig").Evidence, ledger: *const identity.ModelRequestIdentityLedger) Error!History {
    if (!eligibleInputs(inputs)) return history;
    const candidate = candidateOf(result) orelse return history;
    try checkCurrent(a, inputs, context, result, candidate);
    const packet = request.packet() orelse return error.InvalidRequiredAuthority;
    const prepared = request.prepared() orelse return error.InvalidRequiredAuthority;
    if (proof.candidate().association().request() != prepared) return error.InvalidRequiredAuthority;
    const origin = Origin.fromAccepted(ledger, proof) orelse return error.InvalidRequiredAuthority;
    const native = try authority.build(a, inputs);
    const definition = packet.resultDefinition() orelse return error.InvalidRequiredAuthority;
    const grouped = std.mem.eql(u8, definition.bytes, "assignment_findings");
    const payload = try @import("strict_json.zig").decode(std.json.Value, a, packet.body(), .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth });
    const count: usize = if (grouped) payload.object.get("requirements").?.array.items.len else 1;
    if (count > candidate.review.entries.len) return error.InvalidRequiredAuthority;
    const start = candidate.review.entries.len - count;
    const target = native.requirements[start].seed.id;
    const assigned = if (grouped) try source.assignmentSubjects(a, inputs, target) else try a.dupe(authority.Id, &.{target});
    if (assigned.len != count) return error.InvalidRequiredAuthority;
    const expected = try source.packetFor(a, inputs, context, guidance, if (grouped) .{ .assignment = target } else .{ .finding = target });
    defer packets.release(expected);
    if (!std.mem.eql(u8, expected.body(), packet.body()) or !identity.unitOwnerEql(expected.unit(), packet.unit()) or !identity.purposeEqlBounded(expected.purpose(), packet.purpose(), 1)) return error.InvalidRequiredAuthority;
    var prefix = candidate;
    prefix.review.entries = candidate.review.entries[0..start];
    prefix.origins = candidate.origins[0..start];
    prefix.pending_localization = source.pendingLocalization(inputs, prefix.review.entries);
    if (prefix.occurrences.next_ordinal != 0) prefix.occurrences.values = candidate.occurrences.values[0..start];
    const replayed = try source.collectFocused(a, inputs, context, guidance, .{ .pending = prefix }, packet, proof.candidate().content(), origin);
    const replayed_candidate = candidateOf(replayed) orelse return error.InvalidRequiredAuthority;
    if (!try equal([]const source.Finding, a, candidate.review.entries, replayed_candidate.review.entries)) return error.InvalidRequiredAuthority;
    for (candidate.origins[start..]) |finding_origin| if (finding_origin == null or !std.meta.eql(finding_origin.?, origin)) return error.InvalidRequiredAuthority;
    // Schema-accepted model data can still fail native admission. Authenticating
    // its original scope and occurrence identities grants no finding authority.
    var next = try observe(a, history, inputs, context, result, ledger);
    if (candidate.origin != null and std.meta.eql(candidate.origin.?, origin)) next.scope.?.origin_request = request.id();
    if (result == .rejected) return next;
    for (assigned, start..) |subject, index| {
        const finding = candidate.review.entries[index];
        if (!std.meta.eql(subject, native.requirements[index].seed.id) or finding.requirement_ordinal != index + 1) return error.InvalidRequiredAuthority;
        const finding_origin = candidate.origins[index] orelse return next;
        if (!std.meta.eql(finding_origin, origin) or (finding.value.kind != .supported and finding.value.kind != .not_applicable) or finding.value.preservation != null) return next;
    }
    // Native finding repairs and protocol correction need additional dependency
    // witnesses; this bounded implementation deliberately records neither.
    if (request.protocolCorrection() != null) return next;
    const subjects = try a.alloc(authority.Seed, count);
    errdefer a.free(subjects);
    const rules = try a.alloc(source.Applicability, count);
    errdefer a.free(rules);
    for (assigned, subjects, rules, start..) |subject, *seed, *rule, index| {
        seed.* = native.requirements[index].seed;
        rule.* = try source.applicability(inputs, subject);
    }
    const receipts = try a.alloc(Receipt, next.receipts.len + 1);
    @memcpy(receipts[0..next.receipts.len], next.receipts);
    receipts[next.receipts.len] = .{ .request = request, .origin = origin, .subjects = subjects, .applicability = rules, .findings = candidate.review.entries[start..] };
    next.receipts = receipts;
    return next;
}

/// Updating a native-validated historical snapshot retires receipts changed by
/// repair. Rejected typed candidates preserve only authenticated scope metadata;
/// they gain no current authority and never create reusable receipts.
pub fn observe(a: std.mem.Allocator, history: History, inputs: authority.Inputs, context: provenance.Context, result: source.Collection, ledger: *const identity.ModelRequestIdentityLedger) Error!History {
    if (!eligibleInputs(inputs)) return history;
    const candidate = candidateOf(result) orelse return history;
    try checkCurrent(a, inputs, context, result, candidate);
    const native = try authority.build(a, inputs);
    const previous = if (history.scope) |scope| if (sameScope(scope, inputs, ledger) and try equal(@import("reference_evidence.zig").Inputs, a, scope.sources, context.inputs)) scope else null else null;
    if (previous) |scope| if (inputs.revision < scope.input_revision) return error.InvalidRequiredAuthority;
    var occurrences: std.ArrayList(source.Occurrence) = .empty;
    errdefer occurrences.deinit(a);
    if (previous) |scope| for (scope.occurrences) |old| {
        // A prior subject may no longer occur in the current prefix. Its native
        // occurrence remains reserved and cannot be minted for another subject.
        var present = false;
        for (native.requirements[0..candidate.review.entries.len]) |current| if (std.meta.eql(current.seed.id, old.subject)) {
            present = true;
            break;
        };
        if (!present) try occurrences.append(a, old);
    };
    for (candidate.review.entries, 0..) |finding, index| {
        if (finding.requirement_ordinal != index + 1) return error.InvalidRequiredAuthority;
        const occurrence = candidate.occurrences.at(index, candidate.review.entries.len) catch return error.InvalidRequiredAuthority;
        for (occurrences.items) |old| if (std.meta.eql(old.occurrence, occurrence)) return error.InvalidRequiredAuthority;
        try occurrences.append(a, .{ .subject = native.requirements[index].seed.id, .occurrence = occurrence });
    }
    var receipts: std.ArrayList(Receipt) = .empty;
    errdefer receipts.deinit(a);
    if (previous != null) for (history.receipts) |receipt| {
        if (receipt.subjects.len != receipt.findings.len or receipt.subjects.len != receipt.applicability.len) return error.InvalidRequiredAuthority;
        var current = true;
        for (receipt.subjects, receipt.findings) |subject, finding| for (candidate.review.entries, candidate.origins, 0..) |entry, origin, index| {
            if (!std.meta.eql(subject.id, native.requirements[index].seed.id)) continue;
            if (!try equal(source.Finding, a, finding, entry) or origin == null or !std.meta.eql(origin.?, receipt.origin)) current = false;
        };
        if (current) try receipts.append(a, receipt);
    };
    const owned_occurrences = try occurrences.toOwnedSlice(a);
    errdefer a.free(owned_occurrences);
    return .{ .receipts = try receipts.toOwnedSlice(a), .scope = .{ .epoch = ledger.stageRunEpochId(), .feature = inputs.feature, .reference = context.inputs.corpus.state_id, .reference_records = inputs.references.?, .input_revision = inputs.revision, .sources = context.inputs, .candidate = candidate, .origin_request = if (previous) |scope| if (std.meta.eql(scope.candidate.origin, candidate.origin)) scope.origin_request else null else null, .occurrences = owned_occurrences } };
}

pub fn restart(a: std.mem.Allocator, history: History, inputs: authority.Inputs, ledger: *const identity.ModelRequestIdentityLedger) Error!?source.Collection {
    const scope = history.scope orelse return null;
    if (!sameScope(scope, inputs, ledger)) return null;
    if (inputs.revision < scope.input_revision) return error.InvalidRequiredAuthority;
    const original = scope.candidate;
    const origin = original.origin orelse return null;
    const origin_request = scope.origin_request orelse return null;
    const original_record = ledger.record(origin_request) orelse return error.InvalidRequiredAuthority;
    if (!origin_request.stage_run_epoch_id.eql(ledger.stageRunEpochId()) or original_record.status != .terminal or original_record.terminal_reason != .accepted or
        !origin.matches(ledger, .{ .model_request_id = origin_request, .model_attempt_ordinal = origin.attempt, .kind = .inference })) return error.InvalidRequiredAuthority;
    var next_ordinal = original.occurrences.next_ordinal;
    if (next_ordinal == 0) next_ordinal = std.math.cast(u32, original.review.entries.len + 1) orelse return error.InvalidRequiredAuthority;
    const seed: source.Candidate = .{ .review = .{ .entries = &.{} }, .revision = std.math.add(u64, original.revision, 1) catch return error.InvalidRequiredAuthority, .working = true, .origin = origin, .origins = &.{}, .occurrences = .{ .next_ordinal = next_ordinal }, .occurrence_history = scope.occurrences, .omission_conflict_claims = original.omission_conflict_claims, .last_repair = original.last_repair };
    return try source.validateWorking(a, inputs, scope.sources, seed);
}

pub fn reuse(a: std.mem.Allocator, history: History, inputs: authority.Inputs, context: provenance.Context, guidance: *const @import("packet_guidance.zig").Guidance, prior: ?source.Collection, selection: handoff.Selection, ledger: *const identity.ModelRequestIdentityLedger) Error!?source.Collection {
    const scope = history.scope orelse return null;
    if (!sameScope(scope, inputs, ledger)) return null;
    if (inputs.revision < scope.input_revision) return error.InvalidRequiredAuthority;
    if (!try equal(@import("reference_evidence.zig").Inputs, a, scope.sources, context.inputs)) return null;
    const target = try source.nextSubject(a, inputs, prior);
    const packet = try source.packetFor(a, inputs, context, guidance, source.assignmentScope(inputs, target));
    defer packets.release(packet);
    const selected_packet = selection.input orelse return error.InvalidRequiredAuthority;
    if (selected_packet != .packet or !std.mem.eql(u8, selected_packet.packet.body(), packet.body())) return error.InvalidRequiredAuthority;
    const native = try authority.build(a, inputs);
    const start = if (prior) |value| value.pending.review.entries.len else 0;
    const assigned = if (source.assignmentScope(inputs, target) == .assignment) try source.assignmentSubjects(a, inputs, target) else try a.dupe(authority.Id, &.{target});
    var remaining = history.receipts.len;
    while (remaining != 0) {
        remaining -= 1;
        const receipt = history.receipts[remaining];
        if (receipt.subjects.len != assigned.len or receipt.findings.len != assigned.len or receipt.applicability.len != assigned.len) continue;
        var matches = true;
        for (receipt.subjects, receipt.findings, receipt.applicability, assigned, start..) |old, finding, rule, id, index| {
            if (!std.meta.eql(old.id, id) or finding.requirement_ordinal != index + 1 or
                !try equal(authority.Seed, a, old, native.requirements[index].seed) or
                !std.meta.eql(rule, try source.applicability(inputs, id))) matches = false;
        }
        if (!matches or !try selection.acceptsRetained(a, ledger, receipt.request, receipt.origin)) continue;
        return try source.appendAdmitted(a, inputs, context, guidance, prior, packet, receipt.findings, receipt.origin);
    }
    return null;
}
