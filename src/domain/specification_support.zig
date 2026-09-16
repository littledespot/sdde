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
/// A review judges support or an explicitly permitted applicability exception.
/// Native authority evidence keeps the finding and resolution separate.
pub const Decision = enum {
    supported,
    ambiguous,
    conflicting,
    unsupported,
    candidate_omission,
    not_applicable,

    fn finding(self: Decision) a.Finding {
        return switch (self) {
            .not_applicable => .supported,
            inline else => |value| @field(a.Finding, @tagName(value)),
        };
    }
    fn fromFinding(value: a.Finding) Decision {
        return switch (value) {
            inline else => |tag| @field(Decision, @tagName(tag)),
        };
    }
};
pub const Value = struct {
    decision: Decision,
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
pub const Issue = enum { invalid_json, unknown_requirement, duplicate_requirement, missing_requirement, invalid_detail, invalid_evidence, invalid_decision };
pub const Rejection = struct { issue: Issue, requirement: ?a.Id, ordinal: ?u32, revision: u64, origin: ?Origin, evidence: ?admission.Rejection = null };
pub const Collection = union(enum) {
    accepted: struct { inputs: a.Inputs, candidate: Candidate },
    rejected: struct { candidate: ?Candidate, rejection: Rejection },
};

// Correlate responses by ordinal; native identity/version and revision remain
// in the retained ledger. Only the applicable review subject reaches the model.
const Requirement = struct { ordinal: u32, task: []const u8, permitted_not_applicable: ?a.Rule, evidence: admission.Requirements.Guidance };
const Subject = union(enum) {
    source_preservation: struct {},
    candidate_support: struct { candidate: ?spec.IdentifiedContent, brief: ?spec.Brief },
};

pub const Applicability = union(enum) { required, not_applicable: a.Rule, review: a.Rule };

/// One projection of registered policy and current candidate facts, shared by
/// requests, admission, insertion repair and persisted evidence re-admission.
pub fn applicability(inputs: a.Inputs, id: a.Id) Error!Applicability {
    const policy = a.policy(id) orelse return error.InvalidRequiredAuthority;
    const rule = policy.not_applicable orelse return .required;
    return switch (rule) {
        .no_business_data => if (inputs.specification) |content|
            if (content.entities.disposition == .not_applicable) .{ .not_applicable = rule } else .required
        else
            .{ .review = rule },
        .authenticated_exact_scope => error.InvalidRequiredAuthority,
    };
}

pub fn packet(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context) Error!*packets.Packet {
    return packetFor(allocator, inputs, context, .all);
}

pub const Scope = union(enum) { all, finding: a.Id, correction: a.Id };
pub fn packetFor(allocator: std.mem.Allocator, inputs: a.Inputs, context: p.Context, scope: Scope) Error!*packets.Packet {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const ledger = try a.build(scratch, inputs);
    const records = inputs.references orelse return error.InvalidRequiredAuthority;
    const all = try p.items(context);
    if (inputs.projection != .specification or !a.contains(a.Authority, inputs.authorities, .{ .reference = all.state_id }) or !records.items.state_id.eql(all.state_id)) return error.InvalidRequiredAuthority;
    var slots: std.ArrayList(Requirement) = .empty;
    var review_applicability = false;
    const target: ?a.Id = switch (scope) {
        .all => null,
        .finding, .correction => |id| id,
    };
    for (ledger.requirements, 0..) |requirement, index| {
        if (target) |selected| if (!std.meta.eql(selected, requirement.seed.id)) continue;
        const id = requirement.seed.id;
        const required = try applicability(inputs, id);
        review_applicability = review_applicability or required == .review;
        try slots.append(scratch, .{ .ordinal = try r.ordinal(index), .task = try task(scratch, id), .permitted_not_applicable = if (required == .review) required.review else null, .evidence = (try admission.requirements(scratch, inputs, id)).guidance() });
    }
    if (target != null and slots.items.len != 1) return error.InvalidRequiredAuthority;
    const projected = try @import("model_evidence.zig").project(scratch, all.entries);
    const sources = try scratch.alloc(struct { id: @import("reference_identity.zig").SourceId, text: []const u8 }, context.inputs.corpus.sources.len);
    for (context.inputs.corpus.sources, sources) |source, *copy| copy.* = .{ .id = source.id, .text = source.bytes };
    const subject: Subject = if (inputs.specification != null or inputs.brief != null) .{ .candidate_support = .{ .candidate = inputs.specification, .brief = inputs.brief } } else .{ .source_preservation = .{} };
    const payload = .{ .subject = subject, .evidence_rules = .{ .supported = admission.minimum(.supported), .not_applicable = admission.minimum(Decision.not_applicable.finding()), .candidate_omission = admission.minimum(.candidate_omission), .negative = admission.minimum(.unsupported) }, .requirements = slots.items, .sources = sources, .extraction = try @import("model_evidence.zig").extractionReview(scratch, context.inputs, all.extraction), .dispositions = records.dispositions, .claims = projected.claims, .citations = projected.citations, .preserved_tokens = projected.preserved_tokens, .signals = try @import("model_evidence.zig").signals(scratch, records.signals), .conflicts = try @import("model_evidence.zig").conflicts(scratch, records.conflicts) };
    const encoded = try @import("model_candidate_json.zig").encode(@TypeOf(payload), scratch, payload);
    var projected_input = try @import("strict_json.zig").decode(std.json.Value, scratch, encoded, .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth });
    for (projected_input.object.getPtr("requirements").?.array.items) |*requirement| {
        packets.omitAbsent(requirement.object.getPtr("evidence").?);
        packets.omitAbsent(requirement);
        // A correction preserves the decision; its retained diagnostic supplies
        // the selected evidence rule once. Insertion still needs all choices.
        if (scope == .correction) {
            _ = requirement.object.orderedRemove("evidence");
            _ = requirement.object.orderedRemove("permitted_not_applicable");
        }
    }
    if (scope == .correction) _ = projected_input.object.orderedRemove("evidence_rules");
    const body = try std.json.Stringify.valueAlloc(scratch, projected_input, .{});
    return packets.create(allocator, body, .{ .semantic_review = .{ .parent_unit_owner_id = .{ .specification_unit = .{ .reference_state_id = .{ .bytes = all.state_id.bytes }, .feature_id = inputs.feature, .unit_slot_id = .{ .bytes = "required-information" } } }, .review_slot_id = .{ .bytes = "source-support" } } }, .{ .semantic_review = .{ .bytes = "source-support" } }, .{ .bytes = if (review_applicability) "review_applicability" else "review" });
}

/// Presentation of the native subject, not another requirement or routing policy.
fn task(allocator: std.mem.Allocator, id: a.Id) Error![]const u8 {
    return switch (id.unit) {
        .feature => switch (id.slot) {
            .display_name => "A name identifying the feature's purpose.",
            .description => "A description of intended user-visible behavior.",
            .primary_goal => "The intended user benefit.",
            .primary_user_story => "The actor, action and intended result.",
            .acceptance_criteria => "Observable pass/fail outcomes.",
            .functional_requirements => "Required application behavior.",
            .scenario_coverage => "Source-required triggers, outcomes and exact copy.",
            .entities => "Whether business entities/data are involved.",
            else => error.InvalidRequiredAuthority,
        },
        .record => |id_record| std.fmt.allocPrint(allocator, "Source support for {s} {d}, field {s}, member {d}.", .{ @tagName(id_record.kind), id_record.ordinal, @tagName(id.slot), id.member }),
        .signal => |signal| std.fmt.allocPrint(allocator, "Source meaning preserved by signal {d}.", .{signal.ordinal}),
        .conflict => |conflict| std.fmt.allocPrint(allocator, "Source evidence and unresolved meaning of conflict {d}.", .{conflict.ordinal}),
        .token => |token| std.fmt.allocPrint(allocator, "Exact token {d} and its source-required use.", .{token.ordinal}),
        .decision => error.InvalidRequiredAuthority,
    };
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
        const required = try applicability(inputs, requirement.seed.id);
        if (finding.value.decision == .not_applicable and required != .review) return reject(proposed, .invalid_decision, requirement.seed.id, ordinal, origin);
        const semantic = finding.value.decision.finding();
        if (!admission.validDetail(semantic, finding.value.detail)) return reject(proposed, .invalid_detail, requirement.seed.id, ordinal, origin);
        const reviewed = try admission.admit(allocator, inputs, sources, requirement.seed.id, semantic, finding.value.provenance, finding.value.source_ids, finding.value.detail);
        if (reviewed == .rejected) {
            var rejection = reject(proposed, .invalid_evidence, requirement.seed.id, ordinal, origin);
            rejection.rejected.rejection.evidence = reviewed.rejected;
            return rejection;
        }
        const not_applicable: ?a.Rule = if (required == .not_applicable) required.not_applicable else if (finding.value.decision == .not_applicable) required.review else null;
        if (inputs.specification != null) {
            candidates[index] = .{ .id = .{ .ordinal = ordinal, .revision = inputs.revision }, .requirement = requirement.seed.id };
        }
        entry.* = .{
            .id = .{ .ordinal = ordinal },
            .requirement = requirement.seed.id,
            .authorities = requirement.seed.input_authorities,
            .resolution = if (not_applicable) |rule| .{ .not_applicable = rule } else if (inputs.specification != null and semantic != .candidate_omission) .{ .supported_candidate = candidates[index].id } else .{ .existing_authority = .{ .reference = sources.corpus.state_id } },
            .finding = semantic,
            .review = reviewed.accepted,
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
        const required = try applicability(inputs, requirement.seed.id);
        const decision = if (required == .review and evidence.resolution == .not_applicable) blk: {
            if (evidence.finding != .supported) return error.InvalidRequiredAuthority;
            break :blk Decision.not_applicable;
        } else Decision.fromFinding(evidence.finding);
        finding.* = .{ .requirement_ordinal = @intCast(index + 1), .value = .{ .decision = decision, .provenance = .{ .claim_ids = review.provenance.claim_ids, .clarification_response_ids = review.provenance.clarification_response_ids }, .source_ids = review.source_ids, .detail = review.detail } };
    }
    var empty = inputs;
    empty.evidence = &.{};
    empty.candidates = &.{};
    const checked = try validate(allocator, empty, sources, .{ .review = .{ .entries = findings }, .origin = null, .origins = origins });
    if (checked != .accepted) return error.InvalidRequiredAuthority;
    if (!std.mem.eql(u8, try std.json.Stringify.valueAlloc(allocator, checked.accepted.inputs.evidence, .{}), try std.json.Stringify.valueAlloc(allocator, inputs.evidence, .{})) or
        !std.mem.eql(u8, try std.json.Stringify.valueAlloc(allocator, checked.accepted.inputs.candidates, .{}), try std.json.Stringify.valueAlloc(allocator, inputs.candidates, .{}))) return error.InvalidRequiredAuthority;
}
