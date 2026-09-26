//! Policy assessment contributes native Plan-owned obligations, never business support.
const std = @import("std");
const a = @import("required_authority.zig");
const registry = @import("principle_registry.zig");
const packets = @import("model_input_packet.zig");
const p = @import("specification_provenance.zig");
pub const Error = registry.Error || a.Error || p.Error || packets.Error || @import("strict_json.zig").Error || @import("canonical_json.zig").Error;
pub const Business = struct {
    feature: @import("feature_identity.zig").FeatureId,
    revision: u64,
    brief: @import("specification.zig").Brief,
    content: @import("specification.zig").IdentifiedContent,
    references: @import("reference_support.zig").Records,
};
pub const Context = struct { business: Business, registry: registry.Registry, selection: registry.Selection };
pub fn businessInput(allocator: std.mem.Allocator, inputs: a.Inputs) Error!Business {
    if (inputs.projection != .specification or inputs.specification == null or inputs.brief == null or inputs.principle_context != null) return error.InvalidRequiredAuthority;
    const ledger = try a.build(allocator, inputs);
    if ((try a.reconcile(allocator, ledger, try a.buildObservations(allocator, ledger))).continuation != .all_resolved) return error.InvalidRequiredAuthority;
    return .{ .feature = inputs.feature, .revision = inputs.revision, .brief = inputs.brief.?, .content = inputs.specification.?, .references = inputs.references orelse return error.InvalidRequiredAuthority };
}
pub const Canonical = struct {
    registry: registry.Registry,
    selection: registry.Selection,
    candidate_revision: u64,
    requirements: []const a.Id,
    evidence: []const a.Evidence,
    result: a.Result,
};
pub const Value = struct { decision: Decision, citations: []const registry.Citation, detail: []const u8 };
pub const Decision = enum {
    compatible,
    conflicting,
    uncertain,
    pub fn finding(self: Decision) a.Finding {
        return switch (self) {
            .compatible => .supported,
            .conflicting => .conflicting,
            .uncertain => .ambiguous,
        };
    }
    pub fn fromFinding(finding_value: a.Finding) Error!Decision {
        return switch (finding_value) {
            .supported => .compatible,
            .conflicting => .conflicting,
            .ambiguous => .uncertain,
            else => error.InvalidRequiredAuthority,
        };
    }
};
pub const Issue = enum { invalid_principle_citation, missing_evidence, invalid_selection };
pub const Rule = struct {
    citations_required: bool,
    permitted_chunks: []const registry.ChunkId,
    pub const Guidance = @This();
    pub fn guidance(self: Rule) Guidance {
        return self;
    }
};
pub const CitationRejection = struct { index: usize, diagnostic: registry.CitationDiagnostic };
pub const Rejection = struct { issue: Issue, rule: Rule, citation: ?CitationRejection = null };
pub const Admission = union(enum) { accepted: a.ReviewEvidence, rejected: Rejection };

pub fn subjects(allocator: std.mem.Allocator, business: Business) Error![]const a.Id {
    const ledger = try a.build(allocator, try @import("specification_authority.zig").projectRecords(allocator, business.feature, business.references, business.content, business.brief));
    var ids: std.ArrayList(a.Id) = .empty;
    for (ledger.requirements) |requirement| if (requirement.seed.id.kind == .feature_intent or requirement.seed.id.kind == .entity_applicability) try ids.append(allocator, requirement.seed.id);
    return ids.toOwnedSlice(allocator);
}
pub fn project(allocator: std.mem.Allocator, context: Context) Error!a.Inputs {
    try registry.validateSelection(allocator, context.registry, context.selection);
    if (context.selection.scope.stage != .spec or context.selection.scope.environment != null or context.selection.scope.fileKind != null) return error.InvalidRequiredAuthority;
    const assigned = try subjects(allocator, context.business);
    const authorities = try allocator.dupe(a.Authority, &.{ .{ .reference = context.business.references.items.state_id }, policyAuthority(context.registry) });
    const seeds = try allocator.alloc(a.Seed, if (context.selection.chunks.len == 0) 0 else assigned.len);
    for (seeds, 0..) |*seed, index| seed.* = .{ .id = .{ .kind = .policy_predicate, .unit = .{ .decision = .{ .ordinal = @intCast(index + 1) } }, .slot = .compliance }, .requiredness = .{ .policy = .compliance }, .input_authorities = authorities };
    return .{ .feature = context.business.feature, .projection = .principle_assessment, .principle_context = context, .detected_at = .spec, .authorities = authorities, .seeds = seeds, .evidence = &.{}, .references = context.business.references, .revision = context.business.revision };
}
pub fn policyAuthority(value: registry.Registry) a.Authority {
    return .{ .canonical = .{ .kind = .principles, .ordinal = value.id.ordinal, .revision = value.id.revision } };
}
pub fn packet(allocator: std.mem.Allocator, inputs: a.Inputs, source_context: p.Context, scope: @import("specification_support.zig").Contract(.principles).Scope) Error!*packets.Packet {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const context = inputs.principle_context orelse return error.InvalidRequiredAuthority;
    try p.validateStored(scratch, source_context.inputs, .{ .records = source_context.registry.records, .occurrences = source_context.registry.occurrences }, context.business.references, context.business.brief, context.business.content);
    const assigned = try subjects(scratch, context.business);
    const ledger = try a.build(scratch, inputs);
    const Requirement = struct { ordinal: u32, subject: a.Id };
    var requirements: std.ArrayList(Requirement) = .empty;
    for (ledger.requirements, 0..) |requirement, index| {
        const matches = switch (scope) {
            .all => true,
            .finding, .correction => |id| std.meta.eql(id, requirement.seed.id),
        };
        if (matches) try requirements.append(scratch, .{ .ordinal = @intCast(index + 1), .subject = assigned[index] });
    }
    if (scope != .all and requirements.items.len != 1) return error.InvalidRequiredAuthority;
    const projection = @import("specification_projection.zig");
    const payload = .{
        .subject = @as([]const u8, "principle_consistency"),
        .requirements = requirements.items,
        .brief = .{ .title = try projection.scalar(scratch, source_context, context.business.brief.title), .description = try projection.scalar(scratch, source_context, context.business.brief.description), .primary_goal = try projection.scalar(scratch, source_context, context.business.brief.primary_goal) },
        .candidate = try projection.project(scratch, source_context, context.business.content),
        .entity_basis = try projection.scalar(scratch, source_context, context.business.content.entities.basis),
        .principles = try registry.guidance(scratch, context.registry, context.selection),
    };
    const body = try @import("model_candidate_json.zig").encode(@TypeOf(payload), scratch, payload);
    const state = source_context.inputs.corpus.state_id;
    return packets.create(allocator, body, .{ .semantic_review = .{ .parent_unit_owner_id = .{ .specification_unit = .{ .reference_state_id = .{ .bytes = state.bytes }, .feature_id = inputs.feature, .unit_slot_id = .{ .bytes = "required-information" } } }, .review_slot_id = .{ .bytes = "principle-consistency" } } }, .{ .semantic_review = .{ .bytes = "principle-consistency" } }, .{ .bytes = "principle_review" });
}
pub fn rule(inputs: a.Inputs, finding: a.Finding) Error!Rule {
    return .{ .citations_required = finding != .supported, .permitted_chunks = (inputs.principle_context orelse return error.InvalidRequiredAuthority).selection.chunks };
}
pub fn admit(allocator: std.mem.Allocator, inputs: a.Inputs, id: a.Id, value: Value) Error!Admission {
    const context = inputs.principle_context orelse return error.InvalidRequiredAuthority;
    try registry.validateSelection(allocator, context.registry, context.selection);
    const rules = try rule(inputs, value.decision.finding());
    if (id.kind != .policy_predicate or id.unit != .decision or id.slot != .compliance or id.unit.decision.ordinal == 0 or id.unit.decision.ordinal > inputs.seeds.len) return error.InvalidRequiredAuthority;
    for (value.citations, 0..) |citation, index| {
        if (try registry.validateCitation(context.registry, context.selection, citation)) |diagnostic| return .{ .rejected = .{ .issue = .invalid_principle_citation, .rule = rules, .citation = .{ .index = index, .diagnostic = diagnostic } } };
        for (value.citations[0..index]) |previous| if (std.meta.eql(previous, citation)) return .{ .rejected = .{ .issue = .invalid_selection, .rule = rules } };
    }
    if (rules.citations_required and value.citations.len == 0) return .{ .rejected = .{ .issue = .missing_evidence, .rule = rules } };
    return .{ .accepted = .{ .detail = value.detail, .provenance = .{ .claim_ids = &.{}, .citation_ids = &.{}, .clarification_response_ids = &.{} }, .source_ids = &.{}, .principle_citations = value.citations, .principle_registry = context.registry.id } };
}
pub fn canonical(allocator: std.mem.Allocator, inputs: a.Inputs) Error!Canonical {
    const context = inputs.principle_context orelse return error.InvalidRequiredAuthority;
    const ledger = try a.build(allocator, inputs);
    const observations = try a.buildObservations(allocator, ledger);
    const result = try a.reconcile(allocator, ledger, observations);
    for (result.entries) |entry| switch (entry.outcome) {
        .resolved_exactly_one => {},
        .clarification_required => |gap| if (gap.owner != .plan or (gap.reason != .ambiguous and gap.reason != .conflicting)) return error.InvalidRequiredAuthority,
        else => return error.InvalidRequiredAuthority,
    };
    return .{ .registry = context.registry, .selection = context.selection, .candidate_revision = context.business.revision, .requirements = try subjects(allocator, context.business), .evidence = inputs.evidence, .result = result };
}
pub fn validate(allocator: std.mem.Allocator, inputs: a.Inputs, sources: @import("reference_evidence.zig").Inputs, evidence: a.Evidence) Error!void {
    const review = evidence.review orelse return error.InvalidRequiredAuthority;
    if (review.loss != null) return error.InvalidRequiredAuthority;
    if (review.principle_registry == null or !std.meta.eql(review.principle_registry.?, (inputs.principle_context orelse return error.InvalidRequiredAuthority).registry.id)) return error.InvalidRequiredAuthority;
    if (!(inputs.references orelse return error.InvalidRequiredAuthority).items.state_id.eql(sources.corpus.state_id) or evidence.method != .model_assisted or
        review.question != null or review.provenance.claim_ids.len != 0 or review.provenance.citation_ids.len != 0 or review.provenance.clarification_response_ids.len != 0 or review.source_ids.len != 0 or
        !@import("specification_support_evidence.zig").validDetail(evidence.finding, review.detail)) return error.InvalidRequiredAuthority;
    if ((try admit(allocator, inputs, evidence.requirement, .{ .decision = try Decision.fromFinding(evidence.finding), .citations = review.principle_citations, .detail = review.detail })) != .accepted) return error.InvalidRequiredAuthority;
    if (inputs.authorities.len != evidence.authorities.len) return error.InvalidRequiredAuthority;
    for (inputs.authorities) |authority| if (!a.contains(a.Authority, evidence.authorities, authority)) return error.InvalidRequiredAuthority;
}
pub fn validateStored(allocator: std.mem.Allocator, business: a.Inputs, sources: @import("reference_evidence.zig").Inputs, value: Canonical) Error!void {
    if (business.revision != value.candidate_revision) return error.InvalidRequiredAuthority;
    var inputs = try project(allocator, .{ .business = try businessInput(allocator, business), .registry = value.registry, .selection = value.selection });
    inputs.evidence = value.evidence;
    try @import("specification_support.zig").Contract(.principles).validateStored(allocator, inputs, sources);
    const expected = try canonical(allocator, inputs);
    const expected_bytes = try @import("canonical_json.zig").encode(Canonical, allocator, expected);
    defer allocator.free(expected_bytes);
    const actual = try @import("canonical_json.zig").encode(Canonical, allocator, value);
    defer allocator.free(actual);
    if (!std.mem.eql(u8, expected_bytes, actual)) return error.InvalidRequiredAuthority;
}
