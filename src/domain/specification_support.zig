//! Specify's model-assisted evidence producer. Shared authority reconciliation
//! alone selects continuation; a citation join is not semantic proof.
const std = @import("std");
const a = @import("required_authority.zig");
const p = @import("specification_provenance.zig");
const spec = @import("specification.zig");
const packets = @import("model_input_packet.zig");
const r = @import("reference_reconciliation.zig");
pub const Error = a.Error || p.Error || packets.Error;
pub const Review = struct { entries: []const Finding };
pub const Finding = struct {
    requirement_ordinal: u32,
    finding: @FieldType(a.Evidence, "finding"),
    disposition: enum { supported, not_applicable },
    provenance: spec.Provenance,
};

pub fn packet(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context) Error!*packets.Packet {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const ledger = try a.build(scratch, inputs);
    const all = try p.items(context);
    if (inputs.projection != .specification or !a.contains(a.Authority, inputs.authorities, .{ .reference = all.state_id })) return error.InvalidRequiredAuthority;
    const slots = try scratch.alloc(struct { ordinal: u32, requirement: a.Id, permitted_not_applicable: ?a.Rule }, ledger.requirements.len);
    for (ledger.requirements, slots, 0..) |requirement, *slot, index| slot.* = .{ .ordinal = try r.ordinal(index), .requirement = requirement.seed.id, .permitted_not_applicable = if (requirement.registered_policy) |policy| policy.not_applicable else null };
    const body = try std.json.Stringify.valueAlloc(scratch, .{ .requirements = slots, .candidate = inputs.specification, .brief = inputs.brief, .claims = all.entries, .signals = context.references.records.signals, .conflicts = context.references.records.conflicts }, .{});
    return packets.create(allocator, body, .{ .semantic_review = .{ .parent_unit_owner_id = .{ .specification_unit = .{ .reference_state_id = .{ .bytes = all.state_id.bytes }, .feature_request_id = .{ .bytes = inputs.feature.bytes }, .unit_slot_id = .{ .bytes = "required-information" } } }, .review_slot_id = .{ .bytes = "source-support" } } }, .{ .semantic_review = .{ .bytes = "source-support" } });
}

pub fn collect(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context, bytes: []const u8) Error!a.Inputs {
    const proposed = @import("model_candidate_json.zig").decode(Review, allocator, bytes) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidJsonDocument => error.InvalidRequiredAuthority,
    };
    const ledger = try a.build(allocator, inputs);
    if (inputs.evidence.len != 0 or inputs.candidates.len != 0 or proposed.entries.len != ledger.requirements.len) return error.InvalidRequiredAuthority;
    const evidence = try allocator.alloc(a.Evidence, proposed.entries.len);
    const candidates = try allocator.alloc(a.Candidate, if (inputs.specification != null) proposed.entries.len else 0);
    for (ledger.requirements, evidence, 0..) |requirement, *entry, index| {
        const ordinal = try r.ordinal(index);
        var found: ?Finding = null;
        for (proposed.entries) |finding| if (finding.requirement_ordinal == ordinal) {
            if (found != null) return error.InvalidRequiredAuthority;
            found = finding;
        };
        const finding = found orelse return error.InvalidRequiredAuthority;
        if (finding.finding == .supported) {
            _ = try p.scopes(allocator, context, finding.provenance);
            if (inputs.brief) |brief| if (requirement.seed.id.unit == .feature) {
                const expected = switch (requirement.seed.id.slot) {
                    .description => brief.description.provenance,
                    .primary_goal => brief.primary_goal.provenance,
                    else => null,
                };
                if (expected) |scope| {
                    try r.sameSet(r.ClaimId, scope.claim_ids, finding.provenance.claim_ids);
                    try r.sameSet(r.CitationId, scope.citation_ids, finding.provenance.citation_ids);
                }
            };
            if (inputs.specification) |content| if (candidateProvenance(content, requirement.seed.id)) |expected| {
                try r.sameSet(r.ClaimId, expected.claim_ids, finding.provenance.claim_ids);
                try r.sameSet(r.CitationId, expected.citation_ids, finding.provenance.citation_ids);
            };
            switch (requirement.seed.id.unit) {
                .token => |id| {
                    const all = try p.items(context);
                    for (finding.provenance.claim_ids) |claim_id| {
                        const claim = (try r.item(all, claim_id)).claim;
                        if (claim.content == .preserved_token and claim.content.preserved_token.value.id.ordinal == id.ordinal) break;
                    } else return error.InvalidRequiredAuthority;
                },
                .signal => |id| {
                    for (context.references.records.signals) |signal| {
                        if (signal.id.ordinal == id.ordinal) {
                            try r.sameSet(r.ClaimId, signal.value.claim_ids, finding.provenance.claim_ids);
                            break;
                        }
                    } else return error.InvalidRequiredAuthority;
                },
                else => {},
            }
        } else if (finding.provenance.claim_ids.len != 0) {
            _ = try p.scopes(allocator, context, finding.provenance);
        } else if (finding.provenance.citation_ids.len != 0 or finding.provenance.clarification_response_ids.len != 0) return error.InvalidRequiredAuthority;
        const policy = requirement.registered_policy;
        if (finding.disposition == .not_applicable and (policy == null or policy.?.not_applicable != .no_business_data)) return error.InvalidRequiredAuthority;
        if (inputs.specification) |content| {
            if (requirement.seed.id.kind == .entity_applicability and
                (content.entities.disposition == .not_applicable) != (finding.disposition == .not_applicable)) return error.InvalidRequiredAuthority;
            candidates[index] = .{ .id = .{ .ordinal = ordinal, .revision = 1 }, .requirement = requirement.seed.id };
        }
        entry.* = .{
            .id = .{ .ordinal = ordinal },
            .requirement = requirement.seed.id,
            .authorities = requirement.seed.input_authorities,
            .resolution = if (finding.disposition == .not_applicable) .{ .not_applicable = .no_business_data } else if (inputs.specification != null) .{ .supported_candidate = candidates[index].id } else .{ .existing_authority = .{ .reference = context.inputs.corpus.state_id } },
            .finding = finding.finding,
            .method = .model_assisted,
        };
    }
    var result = inputs;
    result.evidence = evidence;
    result.candidates = candidates;
    return result;
}

fn candidateProvenance(content: spec.IdentifiedContent, id: a.Id) ?spec.Provenance {
    switch (id.unit) {
        .feature => return switch (id.slot) {
            .display_name => content.display_name.provenance,
            .primary_user_story => content.primary_user_story.provenance,
            .entities => content.entities.basis.provenance,
            else => null,
        },
        .record => |record_id| for (content.records) |record| {
            if (std.meta.eql(record.id, record_id)) return record.proposal.provenance;
        },
        else => {},
    }
    return null;
}
