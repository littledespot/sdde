//! Structural authority gaps projected into the existing clarification lifecycle.
const std = @import("std");
const a = @import("required_authority.zig");
const c = @import("clarification_inputs.zig");
const refresh = @import("clarification_refresh.zig");
pub fn build(allocator: std.mem.Allocator, source_inputs: @import("reference_evidence.zig").Inputs, inputs: a.Inputs, observations: a.Observations, result: a.Result, guidance: *const @import("packet_guidance.zig").Guidance) a.Error!refresh.Needs {
    if (!std.mem.eql(u8, source_inputs.corpus.feature_id.bytes, inputs.feature.bytes)) return error.InvalidRequiredAuthority;
    if (inputs.references) |references| if (!source_inputs.corpus.state_id.eql(references.items.state_id)) return error.InvalidRequiredAuthority;
    if (try a.validate(allocator, inputs, observations, result)) return error.InvalidRequiredAuthority;
    for (result.entries) |entry| if (entry.candidate_defect != null) return error.InvalidRequiredAuthority;
    var needs: std.ArrayList(refresh.Need) = .empty;
    for (result.entries) |entry| {
        const gap: a.Gap = switch (entry.outcome) {
            .clarification_required => |value| value,
            // An earlier owner's gap is the rework route's (§14.14, §24.5), not a form; the gate blocks such a set first.
            .upstream_rework_required, .administrative_block => return error.InvalidRequiredAuthority,
            .resolved_exactly_one, .resolved_explicit_not_applicable, .resolved_explicit_exception => continue,
        };
        const registered = a.policy(entry.requirement) orelse return error.InvalidRequiredAuthority;
        if (registered.owner != gap.owner or entry.input_authorities.len == 0) return error.InvalidRequiredAuthority;
        // Wording, finding order and execution revision never identify a form.
        const subject = try subjectFor(allocator, source_inputs, inputs.references, entry.requirement);
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
                const question = review.question orelse return error.InvalidRequiredAuthority;
                if (!c.validText(question, c.max_text_bytes)) return error.InvalidRequiredAuthority;
                if (questions.items.len != 0) try questions.appendSlice(allocator, "\n");
                try questions.appendSlice(allocator, question);
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
        // A descriptor can phrase a mechanically missing decision, but cannot
        // manufacture a question for an unresolved semantic assessment.
        if (questions.items.len == 0) switch (gap.reason) {
            .missing, .stale => {},
            else => return error.InvalidRequiredAuthority,
        };
        const prepared = @import("clarification_preparation.zig").prepare(allocator, if (questions.items.len != 0) questions.items else try @import("required_authority_description.zig").question(allocator, guidance, entry.requirement), reason, if (inputs.references) |refs| refs.items.entries else &.{}, .{ .citation_ids = citations.items, .source_ids = sources.items }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidRequiredAuthority;
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
    return .{ .feature = inputs.feature, .original_sources = refresh.originalSources(allocator, source_inputs) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidRequiredAuthority, .entries = try needs.toOwnedSlice(allocator) };
}
/// What a requirement's clarification is about: its kind and slot, and the unit's kind with the source text the unit
/// concerns. A unit built from the sources names that text, whole for a source and by the lines its claims cite for a
/// signal, a conflict or a token. The contract version and the ordinals of generated units differ from one run to the
/// next and never identify a subject (design.md §3.3, item 31). A record or a decision has no source text: no workflow
/// that owns one exists yet, so it keeps its ordinal.
pub fn subjectFor(allocator: std.mem.Allocator, source_inputs: @import("reference_evidence.zig").Inputs, references: ?@import("reference_support.zig").Records, id: a.Id) a.Error!c.Subject {
    if (a.policy(id) == null) return error.InvalidRequiredAuthority;
    const derivation = @import("clarification_subject.zig");
    const corpus = source_inputs.corpus.sources;
    const named: struct { unit: []const u8, spans: []const c.SourceSpan } = switch (id.unit) {
        .feature => .{ .unit = "feature", .spans = &.{} },
        .record => |record| .{ .unit = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ @tagName(record.kind), record.ordinal }), .spans = &.{} },
        .decision => |decision| .{ .unit = try std.fmt.allocPrint(allocator, "decision.{d}", .{decision.ordinal}), .spans = &.{} },
        .source => |source| .{ .unit = "source", .spans = derivation.wholeSource(allocator, corpus, source) catch |err| return mapped(err) },
        .signal, .conflict, .token => cited: {
            const held = references orelse return error.InvalidRequiredAuthority;
            const ids = (try citationsOf(allocator, held, id.unit)) orelse return error.InvalidRequiredAuthority;
            defer allocator.free(ids);
            break :cited .{ .unit = @tagName(id.unit), .spans = derivation.fromCitations(allocator, corpus, held.items.entries, ids) catch |err| return mapped(err) };
        },
    };
    return .{ .requirement = @tagName(id.kind), .unit = named.unit, .slot = @tagName(id.slot), .sources = named.spans };
}

fn mapped(err: @import("clarification_subject.zig").Error) a.Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidClarificationInput => error.InvalidRequiredAuthority,
    };
}

/// The citations of the claims a signal, a conflict or a token holds, from the engine's accounted evidence, or none when
/// the evidence holds no such unit. The caller frees them.
fn citationsOf(allocator: std.mem.Allocator, references: @import("reference_support.zig").Records, unit: a.Unit) a.Error!?[]const @import("reference_reconciliation.zig").CitationId {
    switch (unit) {
        .signal => |signal| {
            for (references.signals) |candidate| if (candidate.id.ordinal == signal.ordinal) return try allocator.dupe(@import("reference_reconciliation.zig").CitationId, candidate.value.citation_ids);
            return null;
        },
        .conflict => |conflict| {
            for (references.conflicts) |candidate| if (candidate.id.ordinal == conflict.ordinal) return try allocator.dupe(@import("reference_reconciliation.zig").CitationId, candidate.value.citation_ids);
            return null;
        },
        .token => |token| {
            for (references.items.entries) |item| {
                if (item.claim.content != .preserved_token or item.claim.content.preserved_token.value.id.ordinal != token.ordinal) continue;
                const ids = try allocator.alloc(@import("reference_reconciliation.zig").CitationId, item.citations.len);
                for (item.citations, ids) |citation, *target| target.* = citation.id;
                return ids;
            }
            return null;
        },
        .feature, .record, .source, .decision => return null,
    }
}
