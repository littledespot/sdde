//! Structural authority gaps projected into the existing clarification lifecycle.
const std = @import("std");
const a = @import("required_authority.zig");
const c = @import("clarification_inputs.zig");
const refresh = @import("clarification_refresh.zig");
pub fn build(allocator: std.mem.Allocator, inputs: a.Inputs, observations: a.Observations, result: a.Result) a.Error!refresh.Needs {
    if (try a.validate(allocator, inputs, observations, result)) return error.InvalidRequiredAuthority;
    var needs: std.ArrayList(refresh.Need) = .empty;
    for (result.entries) |entry| {
        const gap: a.Gap = switch (entry.outcome) {
            .clarification_required => |value| value,
            .upstream_rework_required => |value| .{ .owner = value.owner, .reason = value.reason },
            .administrative_block => return error.InvalidRequiredAuthority,
            .resolved_exactly_one, .resolved_explicit_not_applicable, .resolved_explicit_exception => continue,
        };
        const registered = a.policy(entry.requirement) orelse return error.InvalidRequiredAuthority;
        if (registered.owner != gap.owner or entry.input_authorities.len == 0) return error.InvalidRequiredAuthority;
        // Wording, finding order and execution revision never identify a form.
        const subject = try subjectFor(allocator, entry.requirement);
        var questions: std.ArrayList(u8) = .empty;
        defer questions.deinit(allocator);
        var details: std.ArrayList(u8) = .empty;
        defer details.deinit(allocator);
        var sources: std.ArrayList(@import("reference_identity.zig").SourceId) = .empty;
        defer sources.deinit(allocator);
        var citations: std.ArrayList(@import("reference_reconciliation.zig").CitationId) = .empty;
        defer citations.deinit(allocator);
        for (inputs.evidence) |evidence| {
            if (!std.meta.eql(evidence.requirement, entry.requirement) or evidence.finding == .supported) continue;
            if (evidence.review) |review| {
                if (!c.validText(review.detail, c.max_text_bytes)) return error.InvalidRequiredAuthority;
                if (review.principle_registry == null) {
                    const question = review.question orelse return error.InvalidRequiredAuthority;
                    if (!c.validText(question, c.max_text_bytes)) return error.InvalidRequiredAuthority;
                    if (questions.items.len != 0) try questions.appendSlice(allocator, "\n");
                    try questions.appendSlice(allocator, question);
                }
                if (details.items.len != 0) try details.appendSlice(allocator, "\n");
                try details.appendSlice(allocator, review.detail);
                for (review.provenance.citation_ids) |citation| {
                    if (!@import("reference_reconciliation.zig").contains(@import("reference_reconciliation.zig").CitationId, citations.items, citation)) try citations.append(allocator, citation);
                }
                for (review.source_ids) |source| {
                    if (!@import("reference_reconciliation.zig").contains(@import("reference_identity.zig").SourceId, sources.items, source)) try sources.append(allocator, source);
                }
            }
        }
        if (details.items.len > c.max_text_bytes or questions.items.len > c.max_text_bytes) return error.InvalidRequiredAuthority;
        const reason = if (details.items.len != 0) try details.toOwnedSlice(allocator) else switch (gap.reason) {
            .missing => "Required source information is missing.",
            .ambiguous => "The source leaves more than one interpretation.",
            .conflicting, .multiple_non_equivalent => "The sources disagree; an authoritative decision is required.",
            .stale => "The earlier decision no longer applies to the current inputs.",
            .unsupported => "The review could not establish support for this decision.",
            .unregistered_ownership_or_policy => return error.InvalidRequiredAuthority,
        };
        const prepared = @import("clarification_preparation.zig").prepare(allocator, if (questions.items.len != 0) questions.items else try @import("required_authority_description.zig").question(allocator, entry.requirement), reason, if (inputs.references) |refs| refs.items.entries else &.{}, .{ .citation_ids = citations.items, .source_ids = sources.items }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidRequiredAuthority;
        try needs.append(allocator, .{
            .stage = gap.owner,
            .subject = subject,
            .authority = entry.input_authorities,
            .question = prepared.question,
            .why_required = prepared.why_required,
            .answer_schema = .{ .bounded_business_text = c.max_text_bytes },
        });
    }
    if (needs.items.len == 0) return error.InvalidRequiredAuthority;
    return .{ .feature = inputs.feature, .entries = try needs.toOwnedSlice(allocator) };
}
pub fn subjectFor(allocator: std.mem.Allocator, id: a.Id) a.Error!c.Subject {
    if (a.policy(id) == null) return error.InvalidRequiredAuthority;
    return .{
        .requirement = try std.fmt.allocPrint(allocator, "{s}@{d}", .{ @tagName(id.kind), id.contract_version }),
        .unit = switch (id.unit) {
            .feature => "feature",
            .record => |record| try std.fmt.allocPrint(allocator, "{s}.{d}", .{ @tagName(record.kind), record.ordinal }),
            inline .signal, .conflict, .token, .decision => |value, tag| try std.fmt.allocPrint(allocator, "{s}.{d}", .{ @tagName(tag), value.ordinal }),
        },
        .slot = if (id.member == 0) @tagName(id.slot) else try std.fmt.allocPrint(allocator, "{s}.{d}", .{ @tagName(id.slot), id.member }),
    };
}
