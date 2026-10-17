//! Typed native source-review observations. Findings remain model judgments;
//! capture does not decide whether their semantic diagnoses are correct.
const std = @import("std");
const authority = @import("../../../src/domain/required_authority.zig");
const support = @import("../../../src/domain/specification_support.zig");
const source = support.Source;
const principles = @import("../../../src/domain/principle_assessment.zig");
const workflow = @import("../../../src/application/specification_support_workflow.zig");
const Origin = @import("../../../src/domain/model_candidate_origin.zig").Origin;
const data = @import("../../../src/domain/pipeline_data.zig");
const comparison = @import("../../../src/domain/source_omission.zig").comparisons;
const comparison_context = @import("../../../src/domain/source_omission_context.zig");

pub const Review = enum { source, principles, preservation };
pub const Kind = union(Review) { source: source.Decision, principles: principles.Decision, preservation: comparison.Verdict };
pub const ComparisonContext = struct {
    omission_ordinal: u32,
    omission_detail: []const u8,
    view: comparison.View,
    members: []const comparison_context.ClaimMeaning,
    sources: []const comparison.Span,
};
pub const Finding = struct {
    ordinal: u32,
    origin: Origin,
    requirement: authority.Id,
    kind: Kind,
    detail: []const u8,
    source_ids: []const @import("../../../src/domain/reference_identity.zig").SourceId,
    principle_citations: []const @import("../../../src/domain/principle_registry.zig").Citation,
    missing_obligation: ?[]const u8,
    question: ?[]const u8,
    authority_gap: ?authority.AuthorityGap,
    admission: enum { accepted, pending, rejected },
    comparison: ?ComparisonContext = null,
};
pub const Coverage = struct { origin: Origin, review: Review, complete: bool, expected_findings: ?u32 = null };

pub const Tracker = struct {
    allocator: std.mem.Allocator,
    findings: std.ArrayList(Finding) = .empty,
    coverage: std.ArrayList(Coverage) = .empty,
    owners: std.ArrayList(std.heap.ArenaAllocator) = .empty,

    pub fn init(a: std.mem.Allocator) Tracker {
        return .{ .allocator = a };
    }
    pub fn deinit(self: *Tracker) void {
        for (self.owners.items) |*owner| owner.deinit();
        self.owners.deinit(self.allocator);
        self.findings.deinit(self.allocator);
        self.coverage.deinit(self.allocator);
    }

    pub fn observe(self: *Tracker, view: *const data.View) !void {
        if (!view.contains(workflow.schema.key)) return;
        const current = try workflow.progress(view);
        switch (current) {
            .initial => {},
            .source => |collection| try self.observeSource(view, try workflow.inputs(view, current), collection),
            .pending => |pending| try self.observeSource(view, pending.source.inputs, .{ .accepted = pending.source }),
            .principles => |reviewed| {
                try self.observeSource(view, reviewed.pending.source.inputs, .{ .accepted = reviewed.pending.source });
                try self.observeCollection(.principles, reviewed.pending.inputs, reviewed.result);
            },
        }
    }

    fn observeSource(self: *Tracker, view: *const data.View, inputs: authority.Inputs, collection: source.Collection) !void {
        try self.observeCollection(.source, inputs, collection);
        const current = switch (collection) {
            .accepted => |value| value.candidate,
            .pending => |value| value,
            .rejected => |value| value.candidate orelse return,
        };
        for (current.review.entries) |entry| if (entry.value.preservation) |proof| {
            const origin = proof.origin orelse return error.InvalidNativeReviewFinding;
            var already_captured = false;
            for (self.coverage.items) |coverage| if (std.meta.eql(coverage.origin, origin) and coverage.review == .preservation and coverage.complete) {
                already_captured = true;
            };
            if (already_captured) continue;
            var scratch: std.heap.ArenaAllocator = .init(self.allocator);
            defer scratch.deinit();
            const a = scratch.allocator();
            const context = try @import("../../../src/application/specification_workflow.zig").readContext(view);
            var complete = proof.response.assessments.len == proof.assignment.comparisons.len;
            for (proof.response.assessments, 0..) |assessment, index| {
                const native_view = for (proof.assignment.comparisons) |assigned| {
                    if (assigned.id.ordinal == assessment.comparison_id.ordinal) break assigned;
                } else {
                    complete = false;
                    continue;
                };
                for (proof.response.assessments[0..index]) |prior| if (prior.comparison_id.ordinal == assessment.comparison_id.ordinal) {
                    complete = false;
                };
                const members = try a.alloc(comparison_context.ClaimMeaning, native_view.members.len);
                for (native_view.members, members) |member, *meaning| meaning.* = try comparison_context.claimMeaning(a, proof.assignment.facts.records.items, member.claim_id, context);
                try self.retainComparison(origin, proof.assignment.finding, native_view, assessment, members, if (collection == .rejected) .rejected else if (collection == .accepted) .accepted else .pending);
            }
            try self.recordCoverage(origin, .preservation, complete);
            for (self.coverage.items) |*coverage| if (std.meta.eql(coverage.origin, origin)) {
                coverage.expected_findings = std.math.cast(u32, proof.assignment.comparisons.len) orelse return error.InvalidNativeReviewFinding;
            };
        };
    }

    /// Inputs and verdicts are supplied by the native comparison owner; the
    /// same claim-meaning projector builds the actual production assignment.
    pub fn retainComparison(self: *Tracker, origin: Origin, fixed: @FieldType(comparison.Assignment, "finding"), assigned: comparison.View, assessment: comparison.Assessment, members: []const comparison_context.ClaimMeaning, admission: @FieldType(Finding, "admission")) !void {
        if (origin.kind != .inference or origin.request.value == 0 or origin.attempt.value == 0 or
            assigned.id.ordinal == 0 or assigned.id.ordinal != assessment.comparison_id.ordinal or
            assigned.members.len != members.len) return error.InvalidNativeReviewFinding;
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        try self.retain(scratch.allocator(), .{
            .ordinal = assessment.comparison_id.ordinal,
            .origin = origin,
            .requirement = fixed.subject,
            .kind = .{ .preservation = assessment.result },
            .detail = assessment.explanation,
            .source_ids = fixed.source_ids,
            .principle_citations = &.{},
            .missing_obligation = fixed.missing_obligation,
            .question = null,
            .authority_gap = null,
            .admission = admission,
            .comparison = .{ .omission_ordinal = fixed.ordinal, .omission_detail = fixed.detail, .view = assigned, .members = members, .sources = assessment.sources },
        });
    }

    /// Observe only native, subject-bound source collections. Unsupported or
    /// malformed wire responses never acquire a fabricated finding or kind.
    pub fn observeCollection(self: *Tracker, comptime purpose: support.Purpose, inputs: authority.Inputs, collection: support.Contract(purpose).Collection) !void {
        var scratch: std.heap.ArenaAllocator = .init(self.allocator);
        defer scratch.deinit();
        const a = scratch.allocator();
        const population = try authority.build(a, inputs);
        const candidate: ?support.Contract(purpose).Candidate = switch (collection) {
            .accepted => |value| value.candidate,
            .pending => |value| value,
            .rejected => |value| value.candidate,
        };
        if (collection == .rejected) for (collection.rejected.rejection.diagnostics) |diagnostic| {
            if (diagnostic.origin) |origin| {
                var comparison_origin = false;
                if (purpose == .source) if (candidate) |value| for (value.review.entries) |entry| if (entry.value.preservation) |proof| {
                    if (proof.origin) |producing| {
                        if (std.meta.eql(producing, origin)) comparison_origin = true;
                    }
                };
                if (!comparison_origin) try self.recordCoverage(origin, if (purpose == .source) .source else .principles, false);
            }
        };
        const current = candidate orelse return;
        if (current.origins.len != current.review.entries.len) return error.InvalidNativeReviewFinding;
        for (current.review.entries, current.origins, 0..) |entry, native_origin, index| {
            const origin = native_origin orelse return error.InvalidNativeReviewFinding;
            if (origin.kind != .inference or origin.request.value == 0 or origin.attempt.value == 0) return error.InvalidNativeReviewFinding;
            if (entry.requirement_ordinal == 0 or entry.requirement_ordinal > population.requirements.len) {
                if (collection != .rejected) return error.InvalidNativeReviewFinding;
                try self.recordCoverage(origin, if (purpose == .source) .source else .principles, false);
                continue;
            }
            var admission: @FieldType(Finding, "admission") = switch (collection) {
                .accepted => .accepted,
                .pending, .rejected => .pending,
            };
            if (collection == .rejected) for (collection.rejected.rejection.diagnostics) |diagnostic| {
                if (diagnostic.entry_index == index or diagnostic.ordinal == entry.requirement_ordinal) admission = .rejected;
            };
            const value: Finding = .{
                .ordinal = entry.requirement_ordinal,
                .origin = origin,
                .requirement = population.requirements[entry.requirement_ordinal - 1].seed.id,
                .kind = if (purpose == .source) .{ .source = entry.value.kind } else .{ .principles = entry.value.decision },
                .detail = entry.value.detail,
                .source_ids = if (purpose == .source) entry.value.source_ids else &.{},
                .principle_citations = if (purpose == .principles) entry.value.citations else &.{},
                .missing_obligation = if (purpose == .source) entry.value.missing_obligation else null,
                .question = if (purpose == .source) entry.value.question else null,
                .authority_gap = if (purpose == .source) entry.value.authority_gap else null,
                .admission = admission,
            };
            try self.retain(a, value);
            try self.recordCoverage(origin, if (purpose == .source) .source else .principles, collection != .rejected);
        }
    }

    fn recordCoverage(self: *Tracker, origin: Origin, purpose: Review, complete: bool) !void {
        if (origin.kind != .inference or origin.request.value == 0 or origin.attempt.value == 0) return error.InvalidNativeReviewFinding;
        var expected: u32 = 0;
        if (complete) for (self.findings.items) |finding| if (std.meta.eql(finding.origin, origin)) {
            expected = std.math.add(u32, expected, 1) catch return error.InvalidNativeReviewFinding;
        };
        for (self.coverage.items) |*prior| if (std.meta.eql(prior.origin, origin)) {
            if (prior.review != purpose) return error.InvalidNativeReviewFinding;
            prior.complete = prior.complete or complete;
            if (complete) prior.expected_findings = expected;
            return;
        };
        try self.coverage.append(self.allocator, .{ .origin = origin, .review = purpose, .complete = complete, .expected_findings = if (complete) expected else null });
    }

    fn retain(self: *Tracker, scratch: std.mem.Allocator, value: Finding) !void {
        for (self.findings.items) |*prior| if (prior.ordinal == value.ordinal and std.meta.eql(prior.origin, value.origin)) {
            var comparable = value;
            comparable.admission = prior.admission;
            if (!std.mem.eql(u8, try std.json.Stringify.valueAlloc(scratch, prior.*, .{}), try std.json.Stringify.valueAlloc(scratch, comparable, .{}))) return error.InvalidNativeReviewFinding;
            prior.admission = value.admission;
            return;
        };
        var owner: std.heap.ArenaAllocator = .init(self.allocator);
        errdefer owner.deinit();
        const bytes = try std.json.Stringify.valueAlloc(scratch, value, .{});
        const retained = try @import("../../../src/domain/strict_json.zig").decode(Finding, owner.allocator(), bytes, .{ .maximum_depth = 128 });
        try self.findings.ensureUnusedCapacity(self.allocator, 1);
        try self.owners.ensureUnusedCapacity(self.allocator, 1);
        self.findings.appendAssumeCapacity(retained);
        self.owners.appendAssumeCapacity(owner);
    }
};

const fixture_seeds = [_]authority.Seed{.{ .id = .{ .kind = .reference_meaning, .unit = .{ .source = .{ .ordinal = 1 } }, .slot = .disposition }, .requiredness = .{ .obligation = .reference_accounting }, .input_authorities = &.{} }};
const fixture_sources = [_]@import("../../../src/domain/reference_identity.zig").SourceId{.{ .ordinal = 1 }};
fn testInputs() authority.Inputs {
    return .{ .feature = .{ .bytes = "source-review-boundary" }, .detected_at = .spec, .authorities = &.{}, .evidence = &.{}, .seeds = &fixture_seeds };
}

/// Candidate slices borrow this caller-owned fixture. init returns only inline
/// arrays; candidate() is called after the fixture reaches its final address.
const CandidateFixture = struct {
    entries: [1]source.Finding,
    origins: [1]?Origin,

    fn init(kind: source.Decision, origin: Origin) CandidateFixture {
        return .{
            .entries = .{.{ .requirement_ordinal = 1, .value = .{ .kind = kind, .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} }, .source_ids = &fixture_sources, .detail = "MOCK native source finding.", .missing_obligation = if (kind == .candidate_omission) "MOCK required source behavior." else null, .question = null } }},
            .origins = .{origin},
        };
    }
    fn candidate(self: *const CandidateFixture) source.Candidate {
        return .{ .review = .{ .entries = &self.entries }, .origin = self.origins[0], .origins = &self.origins };
    }
};

pub const Verification = enum { complete, unmeasured };
pub const VerifiedFinding = struct { finding: Finding, verification: Verification };

fn sameValue(comptime T: type, a: std.mem.Allocator, left: T, right: T) !bool {
    return std.mem.eql(u8, try std.json.Stringify.valueAlloc(a, left, .{}), try std.json.Stringify.valueAlloc(a, right, .{}));
}

/// Partial native repairs retain their old verdict through the packet's typed
/// repairOrigin. Only an already raw-verified predecessor can supply inherited
/// fields; the history must precede this send in transport receipt order.
pub fn verifyWithHistory(a: std.mem.Allocator, finding: Finding, raw: []const u8, definition: ?@import("../../../src/domain/model_result_schema.zig").DefinitionId, repair_origin: ?Origin, history: []const VerifiedFinding) !Verification {
    const direct = try verifyRaw(a, finding, raw, definition);
    if (direct == .complete) return .complete;
    const selected = definition orelse return .unmeasured;
    const is_detail = std.mem.eql(u8, selected.bytes, "detail") or std.mem.eql(u8, selected.bytes, "invalid_detail") or std.mem.eql(u8, selected.bytes, "omission_detail") or std.mem.eql(u8, selected.bytes, "gap_detail");
    const is_selection = std.mem.eql(u8, selected.bytes, "selection") or std.mem.eql(u8, selected.bytes, "invalid_selection") or std.mem.eql(u8, selected.bytes, "principle_selection");
    if (!is_detail and !is_selection) return .unmeasured;
    const prior_origin = repair_origin orelse return .unmeasured;
    if (std.meta.eql(prior_origin, finding.origin)) return error.ReviewOutputMismatch;
    var previous: ?VerifiedFinding = null;
    for (history) |entry| if (std.meta.eql(entry.finding.origin, prior_origin) and entry.finding.ordinal == finding.ordinal and std.meta.eql(entry.finding.requirement, finding.requirement)) {
        if (previous != null) return error.ReviewOutputMismatch;
        previous = entry;
    };
    const preceding = previous orelse return .unmeasured;
    if (preceding.verification != .complete) return .unmeasured;
    if (!std.meta.eql(preceding.finding.kind, finding.kind)) return error.ReviewOutputMismatch;
    var scratch: std.heap.ArenaAllocator = .init(a);
    defer scratch.deinit();
    const temporary = scratch.allocator();
    var envelope = try @import("../../../src/domain/model_envelope.zig").parseContent(temporary, raw, null);
    defer envelope.deinit();
    const codec = @import("../../../src/domain/model_candidate_json.zig");
    const model = @import("../../../src/domain/specification_support_model.zig");
    const repair = @import("../../../src/domain/specification_support_repair.zig");
    var expected = preceding.finding;
    expected.origin = finding.origin;
    expected.admission = finding.admission;
    switch (finding.kind) {
        .source => |kind| {
            if (is_detail) {
                const expected_definition = if (kind == .candidate_invalid) "invalid_detail" else if (kind == .candidate_omission) "omission_detail" else if (@import("../../../src/domain/specification_support_evidence.zig").questionRequired(kind.finding())) "gap_detail" else "detail";
                if (!std.mem.eql(u8, selected.bytes, expected_definition)) return error.ReviewOutputMismatch;
                const value = try model.decodeDetail(temporary, envelope.content, kind);
                expected.detail = value.detail;
                expected.missing_obligation = value.missing_obligation;
                expected.question = value.question;
                expected.authority_gap = value.authority_gap;
                if (preceding.finding.authority_gap) |prior_gap| {
                    const current_gap = value.authority_gap orelse return error.ReviewOutputMismatch;
                    if (prior_gap.kind != current_gap.kind) return error.ReviewOutputMismatch;
                    @import("../../../src/domain/reference_reconciliation.zig").sameSet(@import("../../../src/domain/reference_identity.zig").SourceId, prior_gap.source_ids, current_gap.source_ids) catch return error.ReviewOutputMismatch;
                } else if (value.authority_gap != null) return error.ReviewOutputMismatch;
            } else if (kind == .candidate_invalid) {
                if (!std.mem.eql(u8, selected.bytes, "invalid_selection")) return error.ReviewOutputMismatch;
                const value = try codec.decode(model.InvalidSelection, temporary, envelope.content);
                expected.source_ids = value.source_ids;
                if (expected.authority_gap) |*gap| {
                    gap.source_ids = value.authority_gap_source_ids orelse return error.ReviewOutputMismatch;
                } else if (value.authority_gap_source_ids != null) return error.ReviewOutputMismatch;
            } else {
                if (!std.mem.eql(u8, selected.bytes, "selection")) return error.ReviewOutputMismatch;
                const value = try model.decodeSelection(temporary, envelope.content, &.{});
                expected.source_ids = value.source_ids;
            }
        },
        .principles => {
            if (is_detail) {
                if (!std.mem.eql(u8, selected.bytes, "detail")) return error.ReviewOutputMismatch;
                const value = try codec.decode(@FieldType(repair.Contract(.principles).Replacement, "detail"), temporary, envelope.content);
                expected.detail = value.detail;
            } else {
                if (!std.mem.eql(u8, selected.bytes, "principle_selection")) return error.ReviewOutputMismatch;
                const value = try codec.decode(@FieldType(repair.Contract(.principles).Replacement, "selection"), temporary, envelope.content);
                expected.principle_citations = value.citations;
            }
        },
        .preservation => return error.ReviewOutputMismatch,
    }
    if (!try sameValue(Finding, temporary, expected, finding)) return error.ReviewOutputMismatch;
    return .complete;
}

/// A retained native result definition selects the canonical wire contract.
/// Partial repair schemas cannot independently restate the inherited verdict.
pub fn verifyRaw(a: std.mem.Allocator, finding: Finding, raw: []const u8, definition: ?@import("../../../src/domain/model_result_schema.zig").DefinitionId) !Verification {
    const selected = definition orelse return .unmeasured;
    const source_single = std.mem.eql(u8, selected.bytes, "finding") or std.mem.eql(u8, selected.bytes, "preservation_finding") or std.mem.eql(u8, selected.bytes, "applicability_finding");
    const source_record = std.mem.eql(u8, selected.bytes, "record_findings");
    const principle_single = std.mem.eql(u8, selected.bytes, "principle_finding");
    const preservation = std.mem.eql(u8, selected.bytes, "preservation_comparisons");
    if (!source_single and !source_record and !principle_single and !preservation) return .unmeasured;
    var scratch: std.heap.ArenaAllocator = .init(a);
    defer scratch.deinit();
    const temporary = scratch.allocator();
    var envelope = try @import("../../../src/domain/model_envelope.zig").parseContent(temporary, raw, null);
    defer envelope.deinit();
    const codec = @import("../../../src/domain/model_candidate_json.zig");
    if (preservation) {
        if (finding.kind != .preservation or finding.comparison == null) return error.ReviewOutputMismatch;
        const response = try codec.decode(comparison.Response, temporary, envelope.content);
        var selected_assessment: ?comparison.Assessment = null;
        for (response.assessments) |entry| if (entry.comparison_id.ordinal == finding.ordinal) {
            if (selected_assessment != null) return error.ReviewOutputMismatch;
            selected_assessment = entry;
        };
        const value = selected_assessment orelse return error.ReviewOutputMismatch;
        if (value.result != finding.kind.preservation or !std.mem.eql(u8, value.explanation, finding.detail) or
            finding.comparison.?.view.id.ordinal != finding.ordinal or
            !std.mem.eql(u8, try std.json.Stringify.valueAlloc(temporary, value.sources, .{}), try std.json.Stringify.valueAlloc(temporary, finding.comparison.?.sources, .{}))) return error.ReviewOutputMismatch;
    } else if (principle_single) {
        if (finding.kind != .principles) return error.ReviewOutputMismatch;
        const value = try codec.decode(principles.Value, temporary, envelope.content);
        if (value.decision != finding.kind.principles or !std.mem.eql(u8, value.detail, finding.detail) or
            !std.mem.eql(u8, try std.json.Stringify.valueAlloc(temporary, value.citations, .{}), try std.json.Stringify.valueAlloc(temporary, finding.principle_citations, .{}))) return error.ReviewOutputMismatch;
    } else {
        if (finding.kind != .source) return error.ReviewOutputMismatch;
        const model = @import("../../../src/domain/specification_support_model.zig");
        const value = if (source_record) found: {
            const batch = try codec.decode(model.Batch, temporary, envelope.content);
            var result: ?model.Value = null;
            for (batch.findings) |entry| if (entry.requirement_ordinal == finding.ordinal) {
                if (result != null) return error.ReviewOutputMismatch;
                result = entry.value;
            };
            break :found result orelse return error.ReviewOutputMismatch;
        } else try codec.decode(model.Value, temporary, envelope.content);
        switch (value) {
            inline else => |payload, tag| {
                const actual = .{
                    .kind = @field(source.Decision, @tagName(tag)),
                    .detail = payload.detail,
                    .source_ids = payload.source_ids,
                    .missing_obligation = if (tag == .candidate_omission) @as(?[]const u8, payload.missing_obligation) else @as(?[]const u8, null),
                    .question = if (tag == .ambiguous or tag == .conflicting or tag == .unsupported) @as(?[]const u8, payload.question) else @as(?[]const u8, null),
                    .authority_gap = if (tag == .candidate_invalid) payload.authority_gap else @as(?authority.AuthorityGap, null),
                };
                const expected = .{ .kind = finding.kind.source, .detail = finding.detail, .source_ids = finding.source_ids, .missing_obligation = finding.missing_obligation, .question = finding.question, .authority_gap = finding.authority_gap };
                if (!std.mem.eql(u8, try std.json.Stringify.valueAlloc(temporary, actual, .{}), try std.json.Stringify.valueAlloc(temporary, expected, .{}))) return error.ReviewOutputMismatch;
            },
        }
    }
    return .complete;
}

test "native source review capture retains initial and corrected typed findings independently" {
    var tracker = Tracker.init(std.testing.allocator);
    defer tracker.deinit();
    const first: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const corrected: Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    const initial_fixture = CandidateFixture.init(.candidate_omission, first);
    const initial = initial_fixture.candidate();
    try tracker.observeCollection(.source, testInputs(), .{ .pending = initial });
    try tracker.observeCollection(.source, testInputs(), .{ .pending = initial });
    try std.testing.expectEqual(@as(usize, 1), tracker.findings.items.len);
    const corrected_fixture = CandidateFixture.init(.supported, corrected);
    try tracker.observeCollection(.source, testInputs(), .{ .accepted = .{ .inputs = testInputs(), .candidate = corrected_fixture.candidate() } });
    try std.testing.expectEqual(@as(usize, 2), tracker.findings.items.len);
    try std.testing.expectEqual(source.Decision.candidate_omission, tracker.findings.items[0].kind.source);
    try std.testing.expectEqual(source.Decision.supported, tracker.findings.items[1].kind.source);
    try std.testing.expectEqualDeep(testInputs().seeds[0].id, tracker.findings.items[0].requirement);
    try std.testing.expectEqual(@as(usize, 2), tracker.coverage.items.len);
    try std.testing.expect(tracker.coverage.items[0].complete and tracker.coverage.items[1].complete);
}

test "native review rejections retain typed facts and explicitly incomplete projection coverage" {
    var tracker = Tracker.init(std.testing.allocator);
    defer tracker.deinit();
    const origin: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const diagnostic: source.Diagnostic = .{ .issue = .invalid_detail, .requirement = testInputs().seeds[0].id, .ordinal = 1, .revision = 1, .origin = origin, .entry_index = 0 };
    const fixture = CandidateFixture.init(.candidate_invalid, origin);
    try tracker.observeCollection(.source, testInputs(), .{ .rejected = .{ .candidate = fixture.candidate(), .rejection = .{ .diagnostics = &.{diagnostic} } } });
    try std.testing.expectEqual(@as(usize, 1), tracker.findings.items.len);
    try std.testing.expectEqual(.rejected, tracker.findings.items[0].admission);
    try std.testing.expect(!tracker.coverage.items[0].complete);
    var malformed = diagnostic;
    malformed.origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    malformed.issue = .invalid_json;
    try tracker.observeCollection(.source, testInputs(), .{ .rejected = .{ .candidate = null, .rejection = .{ .diagnostics = &.{malformed} } } });
    try std.testing.expectEqual(@as(usize, 1), tracker.findings.items.len);
    try std.testing.expectEqual(@as(usize, 2), tracker.coverage.items.len);
    try std.testing.expect(!tracker.coverage.items[1].complete);
}

test "native review capture rejects missing attribution and changed values for the same response ordinal" {
    var tracker = Tracker.init(std.testing.allocator);
    defer tracker.deinit();
    const origin: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const original = CandidateFixture.init(.supported, origin);
    const changed = CandidateFixture.init(.inconclusive, origin);
    try tracker.observeCollection(.source, testInputs(), .{ .pending = original.candidate() });
    try std.testing.expectError(error.InvalidNativeReviewFinding, tracker.observeCollection(.source, testInputs(), .{ .pending = changed.candidate() }));
    var missing = CandidateFixture.init(.supported, origin);
    missing.origins[0] = null;
    try std.testing.expectError(error.InvalidNativeReviewFinding, tracker.observeCollection(.source, testInputs(), .{ .pending = missing.candidate() }));
    var empty = Tracker.init(std.testing.allocator);
    defer empty.deinit();
    try empty.observe(&.{});
    try std.testing.expectEqual(@as(usize, 0), empty.findings.items.len);
}

fn allocationScenario(a: std.mem.Allocator) !void {
    var tracker = Tracker.init(a);
    defer tracker.deinit();
    const fixture = CandidateFixture.init(.supported, .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } });
    try tracker.observeCollection(.source, testInputs(), .{ .pending = fixture.candidate() });
}

test "native review capture cleans allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}

test "native principle findings retain their own decisions and verify exact selected wire contracts" {
    var tracker = Tracker.init(std.testing.allocator);
    defer tracker.deinit();
    var inputs = testInputs();
    inputs.seeds = &.{.{ .id = .{ .kind = .policy_predicate, .unit = .{ .decision = .{ .ordinal = 1 } }, .slot = .compliance }, .requiredness = .{ .policy = .compliance }, .input_authorities = &.{} }};
    const origin: Origin = .{ .request = .{ .value = 3 }, .attempt = .{ .value = 1 } };
    const native: support.Contract(.principles).Candidate = .{ .review = .{ .entries = &.{.{ .requirement_ordinal = 1, .value = .{ .decision = .compatible, .citations = &.{}, .detail = "MOCK native policy finding." } }} }, .origin = origin, .origins = &.{origin} };
    try tracker.observeCollection(.principles, inputs, .{ .pending = native });
    try std.testing.expectEqual(principles.Decision.compatible, tracker.findings.items[0].kind.principles);
    try std.testing.expectEqual(Review.principles, tracker.coverage.items[0].review);
    var scratch: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer scratch.deinit();
    const a = scratch.allocator();
    const raw = try @import("../../../src/domain/model_candidate_json.zig").encode(principles.Value, a, native.review.entries[0].value);
    try std.testing.expectEqual(Verification.complete, try verifyRaw(a, tracker.findings.items[0], raw, .{ .bytes = "principle_finding" }));
    var changed = tracker.findings.items[0];
    changed.kind = .{ .principles = .conflicting };
    try std.testing.expectError(error.ReviewOutputMismatch, verifyRaw(a, changed, raw, .{ .bytes = "principle_finding" }));
}

test "native source finding wire verification normalizes syntax and preserves batch membership" {
    var tracker = Tracker.init(std.testing.allocator);
    defer tracker.deinit();
    const origin: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const fixture = CandidateFixture.init(.supported, origin);
    try tracker.observeCollection(.source, testInputs(), .{ .pending = fixture.candidate() });
    const finding = tracker.findings.items[0];
    var scratch: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer scratch.deinit();
    const a = scratch.allocator();
    const model = @import("../../../src/domain/specification_support_model.zig");
    const codec = @import("../../../src/domain/model_candidate_json.zig");
    const value: model.Value = .{ .supported = .{ .source_ids = finding.source_ids, .detail = finding.detail } };
    const raw = try codec.encode(model.Value, a, value);
    try std.testing.expectEqual(Verification.complete, try verifyRaw(a, finding, raw, .{ .bytes = "finding" }));
    const prefixed = try std.mem.concat(a, u8, &.{ "{\"", raw });
    try std.testing.expectEqual(Verification.complete, try verifyRaw(a, finding, prefixed, .{ .bytes = "finding" }));
    const batch = try codec.encode(model.Batch, a, .{ .findings = &.{.{ .requirement_ordinal = 1, .value = value }} });
    try std.testing.expectEqual(Verification.complete, try verifyRaw(a, finding, batch, .{ .bytes = "record_findings" }));
    var foreign = finding;
    foreign.ordinal = 2;
    try std.testing.expectError(error.ReviewOutputMismatch, verifyRaw(a, foreign, batch, .{ .bytes = "record_findings" }));
    foreign = finding;
    foreign.detail = "MOCK substituted detail.";
    try std.testing.expectError(error.ReviewOutputMismatch, verifyRaw(a, foreign, raw, .{ .bytes = "finding" }));
    try std.testing.expectEqual(Verification.unmeasured, try verifyRaw(a, finding, "{\"detail\":\"MOCK partial correction\"}", .{ .bytes = "detail" }));
}

fn sourceHistoryFixture(kind: source.Decision, origin: Origin) Finding {
    return .{
        .ordinal = 1,
        .origin = origin,
        .requirement = fixture_seeds[0].id,
        .kind = .{ .source = kind },
        .detail = "MOCK original review explanation.",
        .source_ids = &fixture_sources,
        .principle_citations = &.{},
        .missing_obligation = if (kind == .candidate_omission) "MOCK original missing restriction." else null,
        .question = if (kind == .unsupported) "MOCK what source decision is required?" else null,
        .authority_gap = if (kind == .candidate_invalid) .{ .kind = .unsupported, .source_ids = &fixture_sources, .detail = "MOCK unresolved decision.", .question = "MOCK what decision is required?" } else null,
        .admission = .rejected,
    };
}

fn fullSourceFixture(a: std.mem.Allocator, finding: Finding) ![]const u8 {
    const model = @import("../../../src/domain/specification_support_model.zig");
    const value: model.Value = switch (finding.kind.source) {
        .supported => .{ .supported = .{ .detail = finding.detail, .source_ids = finding.source_ids } },
        .unsupported => .{ .unsupported = .{ .detail = finding.detail, .source_ids = finding.source_ids, .question = finding.question.? } },
        .candidate_omission => .{ .candidate_omission = .{ .detail = finding.detail, .source_ids = finding.source_ids, .missing_obligation = finding.missing_obligation.? } },
        .candidate_invalid => .{ .candidate_invalid = .{ .detail = finding.detail, .source_ids = finding.source_ids, .authority_gap = finding.authority_gap } },
        .ambiguous, .conflicting, .inconclusive, .not_applicable => return error.InvalidFixtureKind,
    };
    return @import("../../../src/domain/model_candidate_json.zig").encode(model.Value, a, value);
}

test "native source partial repairs prove inherited verdict and exact changed and unchanged fields" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const codec = @import("../../../src/domain/model_candidate_json.zig");
    const model = @import("../../../src/domain/specification_support_model.zig");
    const original: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const corrected: Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    const other_sources = [_]@import("../../../src/domain/reference_identity.zig").SourceId{.{ .ordinal = 2 }};
    for ([_]struct { kind: source.Decision, definition: []const u8, detail: bool }{
        .{ .kind = .supported, .definition = "detail", .detail = true },
        .{ .kind = .unsupported, .definition = "gap_detail", .detail = true },
        .{ .kind = .candidate_omission, .definition = "omission_detail", .detail = true },
        .{ .kind = .candidate_invalid, .definition = "invalid_detail", .detail = true },
        .{ .kind = .supported, .definition = "selection", .detail = false },
        .{ .kind = .candidate_invalid, .definition = "invalid_selection", .detail = false },
    }) |example| {
        const previous = sourceHistoryFixture(example.kind, original);
        const full = try fullSourceFixture(a, previous);
        const history = [_]VerifiedFinding{.{ .finding = previous, .verification = try verifyRaw(a, previous, full, .{ .bytes = "finding" }) }};
        var current = previous;
        current.origin = corrected;
        current.admission = .accepted;
        const raw = if (example.detail) detail: {
            current.detail = "MOCK corrected explanation.";
            switch (example.kind) {
                .candidate_omission => {
                    current.missing_obligation = "MOCK corrected missing restriction.";
                    break :detail try codec.encode(struct { detail: []const u8, missing_obligation: []const u8 }, a, .{ .detail = current.detail, .missing_obligation = current.missing_obligation.? });
                },
                .candidate_invalid => {
                    current.authority_gap.?.detail = "MOCK corrected gap explanation.";
                    current.authority_gap.?.question = "MOCK corrected decision question?";
                    break :detail try codec.encode(struct { detail: []const u8, authority_gap: ?authority.AuthorityGap }, a, .{ .detail = current.detail, .authority_gap = current.authority_gap });
                },
                .unsupported => {
                    current.question = "MOCK corrected source decision question?";
                    break :detail try codec.encode(struct { detail: []const u8, question: []const u8 }, a, .{ .detail = current.detail, .question = current.question.? });
                },
                .supported => break :detail try codec.encode(struct { detail: []const u8 }, a, .{ .detail = current.detail }),
                .ambiguous, .conflicting, .inconclusive, .not_applicable => return error.InvalidFixtureKind,
            }
        } else selection: {
            current.source_ids = &other_sources;
            if (example.kind == .candidate_invalid) {
                current.authority_gap.?.source_ids = &other_sources;
                break :selection try codec.encode(model.InvalidSelection, a, .{ .source_ids = current.source_ids, .authority_gap_source_ids = current.authority_gap.?.source_ids });
            }
            break :selection try codec.encode(model.Selection, a, .{ .source_ids = current.source_ids });
        };
        const definition: @import("../../../src/domain/model_result_schema.zig").DefinitionId = .{ .bytes = example.definition };
        try std.testing.expectEqual(.complete, try verifyWithHistory(a, current, raw, definition, original, &history));
        try std.testing.expectEqual(.unmeasured, try verifyWithHistory(a, current, raw, definition, null, &history));
        try std.testing.expectEqual(.unmeasured, try verifyWithHistory(a, current, raw, definition, original, &.{}));
        var unverified = history;
        unverified[0].verification = .unmeasured;
        try std.testing.expectEqual(.unmeasured, try verifyWithHistory(a, current, raw, definition, original, &unverified));
        var changed = current;
        if (example.detail) changed.source_ids = &other_sources else changed.detail = "MOCK unauthorized concurrent field edit.";
        try std.testing.expectError(error.ReviewOutputMismatch, verifyWithHistory(a, changed, raw, definition, original, &history));
        changed = current;
        changed.kind = .{ .source = if (example.kind == .supported) .inconclusive else .supported };
        try std.testing.expectError(error.ReviewOutputMismatch, verifyWithHistory(a, changed, raw, definition, original, &history));
        try std.testing.expectError(error.ReviewOutputMismatch, verifyWithHistory(a, current, raw, definition, corrected, &history));
    }
}

test "native principle partial repair history supports chained detail and selection without replacing verdict" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const codec = @import("../../../src/domain/model_candidate_json.zig");
    const repair = @import("../../../src/domain/specification_support_repair.zig").Contract(.principles);
    var original = sourceHistoryFixture(.supported, .{ .request = .{ .value = 10 }, .attempt = .{ .value = 1 } });
    original.kind = .{ .principles = .compatible };
    original.source_ids = &.{};
    const raw = try codec.encode(principles.Value, a, .{ .decision = .compatible, .detail = original.detail, .citations = original.principle_citations });
    var history: [2]VerifiedFinding = undefined;
    history[0] = .{ .finding = original, .verification = try verifyRaw(a, original, raw, .{ .bytes = "principle_finding" }) };
    var first = original;
    first.origin.request.value = 11;
    first.detail = "MOCK corrected principle explanation.";
    const detail = try codec.encode(@FieldType(repair.Replacement, "detail"), a, .{ .detail = first.detail });
    history[1] = .{ .finding = first, .verification = try verifyWithHistory(a, first, detail, .{ .bytes = "detail" }, original.origin, history[0..1]) };
    try std.testing.expectEqual(.complete, history[1].verification);
    const citations = [_]@import("../../../src/domain/principle_registry.zig").Citation{.{ .chunk = .{ .ordinal = 1 }, .first_line = 2, .last_line = 3 }};
    var second = first;
    second.origin.request.value = 12;
    second.principle_citations = &citations;
    const selection = try codec.encode(@FieldType(repair.Replacement, "selection"), a, .{ .citations = second.principle_citations });
    try std.testing.expectEqual(.complete, try verifyWithHistory(a, second, selection, .{ .bytes = "principle_selection" }, first.origin, &history));
    var changed = second;
    changed.detail = original.detail;
    try std.testing.expectError(error.ReviewOutputMismatch, verifyWithHistory(a, changed, selection, .{ .bytes = "principle_selection" }, first.origin, &history));
    changed = second;
    changed.kind = .{ .principles = .conflicting };
    try std.testing.expectError(error.ReviewOutputMismatch, verifyWithHistory(a, changed, selection, .{ .bytes = "principle_selection" }, first.origin, &history));
    try std.testing.expectError(error.ReviewOutputMismatch, verifyWithHistory(a, second, selection, .{ .bytes = "selection" }, first.origin, &history));
}

test "native preservation findings retain compared meanings and verify exact verdict membership" {
    var tracker = Tracker.init(std.testing.allocator);
    defer tracker.deinit();
    const origin: Origin = .{ .request = .{ .value = 4 }, .attempt = .{ .value = 1 } };
    const fixed: @FieldType(comparison.Assignment, "finding") = .{
        .ordinal = 1,
        .revision = 2,
        .subject = testInputs().seeds[0].id,
        .detail = "MOCK source omission diagnosis.",
        .missing_obligation = "MOCK retain the required behavior.",
        .source_ids = &.{.{ .ordinal = 1 }},
    };
    const assigned: comparison.View = .{ .id = .{ .ordinal = 1 }, .purpose = "MOCK native extraction collection", .members = &.{.{ .id = .{ .ordinal = 1 }, .claim_id = .{ .ordinal = 1 } }} };
    const members = [_]comparison_context.ClaimMeaning{.{ .meaning = "MOCK actual compared source behavior.", .source_id = .{ .ordinal = 1 } }};
    const observed: comparison.Assessment = .{ .comparison_id = assigned.id, .result = .lost, .sources = &.{}, .explanation = "MOCK bound lost assessment." };
    try tracker.retainComparison(origin, fixed, assigned, observed, &members, .rejected);
    try tracker.recordCoverage(origin, .preservation, true);
    try std.testing.expectEqual(comparison.Verdict.lost, tracker.findings.items[0].kind.preservation);
    try std.testing.expectEqualStrings(members[0].meaning, tracker.findings.items[0].comparison.?.members[0].meaning);
    try std.testing.expectEqualDeep(fixed.subject, tracker.findings.items[0].requirement);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const raw = try @import("../../../src/domain/model_candidate_json.zig").encode(comparison.Response, a, .{ .assessments = &.{observed} });
    try std.testing.expectEqual(Verification.complete, try verifyRaw(a, tracker.findings.items[0], raw, .{ .bytes = "preservation_comparisons" }));
    var altered = tracker.findings.items[0];
    altered.kind = .{ .preservation = .preserved };
    try std.testing.expectError(error.ReviewOutputMismatch, verifyRaw(a, altered, raw, .{ .bytes = "preservation_comparisons" }));
    altered = tracker.findings.items[0];
    altered.ordinal = 2;
    try std.testing.expectError(error.ReviewOutputMismatch, verifyRaw(a, altered, raw, .{ .bytes = "preservation_comparisons" }));
    var foreign_view = assigned;
    foreign_view.id.ordinal = 2;
    try std.testing.expectError(error.InvalidNativeReviewFinding, tracker.retainComparison(origin, fixed, foreign_view, observed, &members, .rejected));
}
