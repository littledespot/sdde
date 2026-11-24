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
    var parts: std.ArrayList(Part) = .empty;
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
        try parts.append(allocator, .{
            .stage = gap.owner,
            .subject = subject,
            .answer = try answerFor(allocator, source_inputs, inputs.references, entry.requirement),
            .authority = entry.input_authorities,
            .question = if (questions.items.len != 0) try questions.toOwnedSlice(allocator) else try @import("required_authority_description.zig").question(allocator, guidance, entry.requirement),
            .reason = reason,
            .citations = try citations.toOwnedSlice(allocator),
            .sources = try sources.toOwnedSlice(allocator),
        });
    }
    if (parts.items.len == 0) return error.InvalidRequiredAuthority;
    const entries = try consolidate(allocator, if (inputs.references) |refs| refs.items.entries else &.{}, parts.items);
    return .{ .feature = inputs.feature, .original_sources = refresh.originalSources(allocator, source_inputs) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidRequiredAuthority, .entries = entries };
}
/// One gap's clarification before the gaps of one subject become one need: what the gap asks, why, which authorities it
/// binds and which source evidence it cites.
pub const Part = struct {
    stage: c.Stage,
    subject: c.Subject,
    /// What the user answers with: one option for each claim of a conflict, otherwise bounded business text.
    answer: c.AnswerSchema = .{ .bounded_business_text = c.max_text_bytes },
    authority: []const c.Authority,
    question: []const u8,
    reason: []const u8,
    citations: []const @import("reference_reconciliation.zig").CitationId,
    sources: []const @import("reference_identity.zig").SourceId,
};
/// One need for every stage and subject the parts name, in the order each is first named. The refresh opens one form for
/// a stage and subject and rejects two needs with both the same (§14.14), so several gaps over one subject are one need
/// here (§12.7's consolidation of the same engine-built subject): a part over other lines or of another stage stays its
/// own need. The caller's arena owns every allocation, as it does for the refresh.
pub fn consolidate(allocator: std.mem.Allocator, items: []const @import("reference_reconciliation.zig").Item, parts: []const Part) a.Error![]const refresh.Need {
    const taken = try allocator.alloc(bool, parts.len);
    defer allocator.free(taken);
    @memset(taken, false);
    var needs: std.ArrayList(refresh.Need) = .empty;
    for (parts, 0..) |lead, first| {
        if (taken[first]) continue;
        var members: std.ArrayList(Part) = .empty;
        defer members.deinit(allocator);
        for (parts[first..], first..) |part, at| {
            if (taken[at] or part.stage != lead.stage or !c.sameSubject(part.subject, lead.subject)) continue;
            taken[at] = true;
            try members.append(allocator, part);
        }
        try needs.append(allocator, try merged(allocator, items, members.items));
    }
    return needs.toOwnedSlice(allocator);
}
/// The one need the parts of one stage and subject make: it asks every distinct question and gives every distinct reason,
/// by exact bytes and in the order named, binds the union of the authorities and cites the union of the evidence. Text
/// beyond the form's bound, authorities beyond a record's and one canonical record at two revisions fail; nothing is
/// truncated or dropped.
fn merged(allocator: std.mem.Allocator, items: []const @import("reference_reconciliation.zig").Item, members: []const Part) a.Error!refresh.Need {
    const reconciliation = @import("reference_reconciliation.zig");
    const lead = members[0];
    var questions: std.ArrayList([]const u8) = .empty;
    defer questions.deinit(allocator);
    var reasons: std.ArrayList([]const u8) = .empty;
    defer reasons.deinit(allocator);
    var authority: std.ArrayList(c.Authority) = .empty;
    defer authority.deinit(allocator);
    var citations: std.ArrayList(reconciliation.CitationId) = .empty;
    defer citations.deinit(allocator);
    var sources: std.ArrayList(@import("reference_identity.zig").SourceId) = .empty;
    defer sources.deinit(allocator);
    // A form's evidence is its citations when any member cites one, and its sources otherwise. A member that names only
    // sources keeps its evidence beside a member that cites by expanding to the citations of those sources.
    var cited = false;
    for (members) |member| cited = cited or member.citations.len != 0;
    for (members) |member| {
        if (!containsText(questions.items, member.question)) try questions.append(allocator, member.question);
        if (!containsText(reasons.items, member.reason)) try reasons.append(allocator, member.reason);
        for (member.authority) |held| {
            for (authority.items) |prior| {
                if (prior.eql(held)) break;
                if (prior.sameRecord(held)) return error.InvalidRequiredAuthority;
            } else try authority.append(allocator, held);
        }
        for (member.citations) |citation| if (!reconciliation.contains(reconciliation.CitationId, citations.items, citation)) try citations.append(allocator, citation);
        for (member.sources) |source| if (!reconciliation.contains(@import("reference_identity.zig").SourceId, sources.items, source)) try sources.append(allocator, source);
        if (cited and member.citations.len == 0) for (items) |item| {
            if (!reconciliation.contains(@import("reference_identity.zig").SourceId, member.sources, item.source_id)) continue;
            for (item.citations) |citation| if (!reconciliation.contains(reconciliation.CitationId, citations.items, citation.id)) try citations.append(allocator, citation.id);
        };
    }
    if (authority.items.len > c.max_record_authorities) return error.InvalidRequiredAuthority;
    const question = try std.mem.join(allocator, "\n", questions.items);
    const reason = try std.mem.join(allocator, "\n", reasons.items);
    if (question.len > c.max_text_bytes or reason.len > c.max_text_bytes) return error.InvalidRequiredAuthority;
    const prepared = @import("clarification_preparation.zig").prepare(allocator, question, reason, items, .{ .citation_ids = citations.items, .source_ids = sources.items }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidRequiredAuthority;
    return .{
        .stage = lead.stage,
        .subject = lead.subject,
        .authority = try authority.toOwnedSlice(allocator),
        .question = prepared.question,
        .why_required = prepared.why_required,
        .answer_schema = try mergeAnswers(allocator, members),
    };
}
/// The user chooses among the claims of a conflict, and answers every other gap in text. The options come from the
/// conflict's own claims, so the form offers exactly what the sources say.
fn answerFor(allocator: std.mem.Allocator, source_inputs: @import("reference_evidence.zig").Inputs, references: ?@import("reference_support.zig").Records, id: a.Id) a.Error!c.AnswerSchema {
    const conflict = switch (id.unit) {
        .conflict => |value| value,
        else => return .{ .bounded_business_text = c.max_text_bytes },
    };
    const held = references orelse return error.InvalidRequiredAuthority;
    for (held.conflicts) |candidate| {
        if (candidate.id.ordinal != conflict.ordinal) continue;
        return .{ .select_one = @import("clarification_resolution.zig").conflictOptions(allocator, source_inputs.corpus.sources, held, candidate) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidRequiredAuthority };
    }
    return error.InvalidRequiredAuthority;
}
/// The members of one subject answer one way: text of one bound, or the options of their conflicts once each. A key the
/// members label differently, a mixture of answer kinds and more options than a form offers fail.
fn mergeAnswers(allocator: std.mem.Allocator, members: []const Part) a.Error!c.AnswerSchema {
    const lead = members[0].answer;
    switch (lead) {
        .bounded_business_text => |bound| {
            for (members[1..]) |member| switch (member.answer) {
                .bounded_business_text => |other| if (other != bound) return error.InvalidRequiredAuthority,
                else => return error.InvalidRequiredAuthority,
            };
            return lead;
        },
        .select_many => return error.InvalidRequiredAuthority,
        .select_one => {},
    }
    var options: std.ArrayList(c.Option) = .empty;
    defer options.deinit(allocator);
    for (members) |member| {
        const offered = switch (member.answer) {
            .select_one => |value| value,
            else => return error.InvalidRequiredAuthority,
        };
        next: for (offered) |option| {
            for (options.items) |prior| if (std.mem.eql(u8, prior.key, option.key)) {
                if (!std.mem.eql(u8, prior.label, option.label)) return error.InvalidRequiredAuthority;
                continue :next;
            };
            try options.append(allocator, option);
        }
    }
    if (options.items.len > c.max_options) return error.InvalidRequiredAuthority;
    return .{ .select_one = try options.toOwnedSlice(allocator) };
}
fn containsText(haystack: []const []const u8, text: []const u8) bool {
    for (haystack) |held| if (std.mem.eql(u8, held, text)) return true;
    return false;
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
