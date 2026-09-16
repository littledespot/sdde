//! Model review admission. Shared authority classification owns continuation.
const std = @import("std");
const a = @import("required_authority.zig");
const p = @import("specification_provenance.zig");
const spec = @import("specification.zig");
const packets = @import("model_input_packet.zig");
const r = @import("reference_reconciliation.zig");
const admission = @import("specification_support_evidence.zig");
const Origin = @import("model_candidate_origin.zig").Origin;
pub const Error = @import("strict_json.zig").Error || a.Error || p.Error || packets.Error;
pub const Review = struct { entries: []const Finding };
pub const Finding = struct { requirement_ordinal: u32, value: Value };
pub const Value = struct {
    finding: a.Finding,
    disposition: enum { supported, not_applicable },
    provenance: spec.Selection,
    source_ids: []const @import("reference_identity.zig").SourceId,
    detail: []const u8,
};
pub const Candidate = struct {
    review: Review,
    revision: u64 = 1,
    origin: ?Origin,
    origins: []const ?Origin,
    last_repair: ?@import("atomic_repair.zig").Merge = null,
};
pub const Issue = enum { invalid_json, unknown_requirement, duplicate_requirement, missing_requirement, invalid_detail, invalid_provenance, invalid_disposition };
pub const Rejection = struct { issue: Issue, requirement: ?a.Id, ordinal: ?u32, revision: u64, origin: ?Origin };
pub const Collection = union(enum) {
    accepted: struct { inputs: a.Inputs, candidate: Candidate },
    rejected: struct { candidate: ?Candidate, rejection: Rejection },
};

// Correlate responses by ordinal; native identity/version and revision remain
// in the retained ledger. Only the applicable review subject reaches the model.
const Requirement = struct { ordinal: u32, kind: a.Kind, unit: a.Unit, slot: a.Slot, member: u32, permitted_not_applicable: ?a.Rule, selectable_claim_ids: []const r.ClaimId };
const Subject = union(enum) {
    source_preservation: struct {},
    candidate_support: struct { candidate: ?spec.IdentifiedContent, brief: ?spec.Brief },
};

pub fn packet(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context) Error!*packets.Packet {
    return packetFor(allocator, inputs, context, null);
}

pub fn packetFor(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context, target: ?a.Id) Error!*packets.Packet {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const ledger = try a.build(scratch, inputs);
    const records = inputs.references orelse return error.InvalidRequiredAuthority;
    const all = try p.items(context);
    if (inputs.projection != .specification or !a.contains(a.Authority, inputs.authorities, .{ .reference = all.state_id }) or !records.items.state_id.eql(all.state_id)) return error.InvalidRequiredAuthority;
    var slots: std.ArrayList(Requirement) = .empty;
    for (ledger.requirements, 0..) |requirement, index| {
        if (target) |selected| if (!std.meta.eql(selected, requirement.seed.id)) continue;
        const id = requirement.seed.id;
        try slots.append(scratch, .{ .ordinal = try r.ordinal(index), .kind = id.kind, .unit = id.unit, .slot = id.slot, .member = id.member, .permitted_not_applicable = if (requirement.registered_policy) |policy| policy.not_applicable else null, .selectable_claim_ids = try admission.choices(scratch, records, id) });
    }
    if (target != null and slots.items.len != 1) return error.InvalidRequiredAuthority;
    const projected = try @import("model_evidence.zig").project(scratch, all.entries);
    const sources = try scratch.alloc(struct { id: @import("reference_identity.zig").SourceId, text: []const u8 }, context.inputs.corpus.sources.len);
    for (context.inputs.corpus.sources, sources) |source, *copy| copy.* = .{ .id = source.id, .text = source.bytes };
    const subject: Subject = if (inputs.specification != null or inputs.brief != null) .{ .candidate_support = .{ .candidate = inputs.specification, .brief = inputs.brief } } else .{ .source_preservation = .{} };
    const payload = .{ .subject = subject, .requirements = slots.items, .sources = sources, .extraction = try @import("model_evidence.zig").extractionReview(scratch, context.inputs, all.extraction), .dispositions = records.dispositions, .claims = projected.claims, .citations = projected.citations, .preserved_tokens = projected.preserved_tokens, .signals = try @import("model_evidence.zig").signals(scratch, records.signals), .conflicts = try @import("model_evidence.zig").conflicts(scratch, records.conflicts) };
    const body = try @import("model_candidate_json.zig").encode(@TypeOf(payload), scratch, payload);
    return packets.create(allocator, body, .{ .semantic_review = .{ .parent_unit_owner_id = .{ .specification_unit = .{ .reference_state_id = .{ .bytes = all.state_id.bytes }, .feature_id = inputs.feature, .unit_slot_id = .{ .bytes = "required-information" } } }, .review_slot_id = .{ .bytes = "source-support" } } }, .{ .semantic_review = .{ .bytes = "source-support" } }, null);
}

pub fn collect(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context, bytes: []const u8, origin: ?Origin) Error!Collection {
    const proposed = @import("model_candidate_json.zig").decode(Review, allocator, bytes) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidJsonDocument => .{ .rejected = .{ .candidate = null, .rejection = .{ .issue = .invalid_json, .requirement = null, .ordinal = null, .revision = 1, .origin = origin } } },
    };
    const origins = try allocator.alloc(?Origin, proposed.entries.len);
    @memset(origins, origin);
    return validate(allocator, inputs, context.inputs, .{ .review = proposed, .origin = origin, .origins = origins });
}

pub fn validate(allocator: std.mem.Allocator, inputs: a.Inputs, sources: r.evidence.Inputs, proposed: Candidate) Error!Collection {
    const ledger = try a.build(allocator, inputs);
    if (inputs.evidence.len != 0 or inputs.candidates.len != 0 or proposed.revision == 0 or proposed.origins.len != proposed.review.entries.len) return error.InvalidRequiredAuthority;
    for (proposed.review.entries, 0..) |finding, index| {
        if (finding.requirement_ordinal == 0 or finding.requirement_ordinal > ledger.requirements.len) return reject(proposed, .unknown_requirement, null, finding.requirement_ordinal, proposed.origins[index]);
        for (proposed.review.entries[0..index]) |prior| if (finding.requirement_ordinal == prior.requirement_ordinal) return reject(proposed, .duplicate_requirement, ledger.requirements[finding.requirement_ordinal - 1].seed.id, finding.requirement_ordinal, proposed.origins[index]);
    }
    const evidence = try allocator.alloc(a.Evidence, ledger.requirements.len);
    const candidates = try allocator.alloc(a.Candidate, if (inputs.specification != null) ledger.requirements.len else 0);
    const origins = try allocator.alloc(?Origin, evidence.len);
    for (ledger.requirements, evidence, origins, 0..) |requirement, *entry, *entry_origin, index| {
        const ordinal = try r.ordinal(index);
        const position = for (proposed.review.entries, 0..) |finding, selected| {
            if (finding.requirement_ordinal == ordinal) break selected;
        } else return reject(proposed, .missing_requirement, requirement.seed.id, ordinal, proposed.origin);
        const finding = proposed.review.entries[position];
        const origin = proposed.origins[position];
        if (!admission.validDetail(finding.value.finding, finding.value.detail)) return reject(proposed, .invalid_detail, requirement.seed.id, ordinal, origin);
        const reviewed = admission.admit(allocator, inputs, sources, requirement.seed.id, finding.value.finding, finding.value.provenance, finding.value.source_ids, finding.value.detail) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else reject(proposed, .invalid_provenance, requirement.seed.id, ordinal, origin);
        const policy = requirement.registered_policy;
        if (finding.value.disposition == .not_applicable and (policy == null or policy.?.not_applicable != .no_business_data)) return reject(proposed, .invalid_disposition, requirement.seed.id, ordinal, origin);
        if (inputs.specification) |content| {
            if (requirement.seed.id.kind == .entity_applicability and (content.entities.disposition == .not_applicable) != (finding.value.disposition == .not_applicable)) return reject(proposed, .invalid_disposition, requirement.seed.id, ordinal, origin);
            candidates[index] = .{ .id = .{ .ordinal = ordinal, .revision = inputs.revision }, .requirement = requirement.seed.id };
        }
        entry.* = .{
            .id = .{ .ordinal = ordinal },
            .requirement = requirement.seed.id,
            .authorities = requirement.seed.input_authorities,
            .resolution = if (finding.value.disposition == .not_applicable) .{ .not_applicable = .no_business_data } else if (inputs.specification != null and finding.value.finding != .candidate_omission) .{ .supported_candidate = candidates[index].id } else .{ .existing_authority = .{ .reference = sources.corpus.state_id } },
            .finding = finding.value.finding,
            .review = reviewed,
            .method = .model_assisted,
        };
        entry_origin.* = origin;
    }
    var result = inputs;
    result.evidence = evidence;
    result.candidates = candidates;
    result.review_origin = proposed.origin;
    result.review_origins = origins;
    return .{ .accepted = .{ .inputs = result, .candidate = proposed } };
}
fn reject(candidate: Candidate, issue: Issue, requirement: ?a.Id, ordinal: ?u32, origin: ?Origin) Collection {
    return .{ .rejected = .{ .candidate = candidate, .rejection = .{ .issue = issue, .requirement = requirement, .ordinal = ordinal, .revision = candidate.revision, .origin = origin } } };
}

/// Re-admit self-contained published findings without any prior call ledger.
pub fn validateStored(allocator: std.mem.Allocator, inputs: a.Inputs, sources: r.evidence.Inputs) Error!void {
    const ledger = try a.build(allocator, inputs);
    if (inputs.evidence.len != ledger.requirements.len) return error.InvalidRequiredAuthority;
    const findings = try allocator.alloc(Finding, ledger.requirements.len);
    const origins = try allocator.alloc(?Origin, findings.len);
    @memset(origins, null);
    for (ledger.requirements, inputs.evidence, findings, 0..) |requirement, evidence, *finding, index| {
        if (evidence.id.ordinal != index + 1 or !std.meta.eql(evidence.requirement, requirement.seed.id)) return error.InvalidRequiredAuthority;
        try admission.validate(allocator, inputs, sources, evidence);
        const review = evidence.review.?;
        finding.* = .{ .requirement_ordinal = @intCast(index + 1), .value = .{ .finding = evidence.finding, .disposition = if (evidence.resolution == .not_applicable) .not_applicable else .supported, .provenance = .{ .claim_ids = review.provenance.claim_ids, .clarification_response_ids = review.provenance.clarification_response_ids }, .source_ids = review.source_ids, .detail = review.detail } };
    }
    var empty = inputs;
    empty.evidence = &.{};
    empty.candidates = &.{};
    const checked = try validate(allocator, empty, sources, .{ .review = .{ .entries = findings }, .origin = null, .origins = origins });
    if (checked != .accepted) return error.InvalidRequiredAuthority;
    if (!std.mem.eql(u8, try std.json.Stringify.valueAlloc(allocator, checked.accepted.inputs.evidence, .{}), try std.json.Stringify.valueAlloc(allocator, inputs.evidence, .{})) or
        !std.mem.eql(u8, try std.json.Stringify.valueAlloc(allocator, checked.accepted.inputs.candidates, .{}), try std.json.Stringify.valueAlloc(allocator, inputs.candidates, .{}))) return error.InvalidRequiredAuthority;
}
