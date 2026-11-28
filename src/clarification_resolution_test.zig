const std = @import("std");
const c = @import("domain/clarification_inputs.zig");
const r = @import("domain/reference_reconciliation.zig");
const support = @import("domain/reference_support.zig");
const resolution = @import("domain/clarification_resolution.zig");
const fixture = @import("test_fixtures/clarification_inputs.zig");
const f = @import("test_fixtures/reference_reconciliation.zig");
const reconciled = @import("reference_reconciliation_test.zig");

const authority = @import("domain/required_authority.zig");

/// A form's subject as the engine writes it for `id`, naming `sources`.
fn subjectOf(id: authority.Id, sources: []const c.SourceSpan) c.Subject {
    const names = authority.subjectNames(id);
    return .{ .requirement = names.requirement, .unit = names.unit, .slot = names.slot, .sources = sources };
}

/// `path` is comptime so the returned subject's `sources` is a constant, never a pointer into this frame.
fn conflictAt(comptime path: []const u8) c.Subject {
    return subjectOf(authority.conflictDisposition(.{ .ordinal = 1 }), &.{.{ .path = path, .lines = null }});
}

const conflict_subject = subjectOf(authority.conflictDisposition(.{ .ordinal = 1 }), &.{});

test "a conflict offers one option for each claim, named by the lines it cites and labelled by its quotation" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const reference = try reconciled.prepare(allocator, &.{ "Confirm immediately.\n", "Request approval first.\n" });
    defer reference.deinit();
    const final = try f.summaries(allocator, try f.initialize(allocator, reference.inputs, reference.extracted, 2), reference.context());
    const accounted = (try f.finish(allocator, final, try reconciled.conflicting(allocator, final), reference.context())).valid;
    const held = support.records(accounted);
    const corpus = reference.inputs.corpus.sources;
    const options = try resolution.conflictOptions(allocator, corpus, held, held.conflicts[0]);
    try std.testing.expectEqual(@as(usize, 2), options.len);
    try std.testing.expect(!std.mem.eql(u8, options[0].key, options[1].key));
    for (options, [_][]const u8{ "Confirm immediately.", "Request approval first." }) |option, quote| {
        try std.testing.expect(c.validToken(option.key) and c.validText(option.label, c.max_text_bytes));
        try std.testing.expectEqualStrings(quote, option.label);
    }
    // The key is the cited source and line, so another run over the same sources offers the same keys, and no claim number is in it.
    const expected = try std.fmt.allocPrint(allocator, "{s}.1", .{try dotted(allocator, corpus[0].path.bytes)});
    try std.testing.expectEqualStrings(expected, options[0].key);
    const again = try resolution.conflictOptions(allocator, corpus, held, held.conflicts[0]);
    for (options, again) |before, after| try std.testing.expectEqualStrings(before.key, after.key);
    // An option key selects its claim, and a key the conflict does not offer selects none.
    for (options, held.conflicts[0].value.claim_ids) |option, claim| {
        const chosen = (try resolution.chosenClaim(allocator, corpus, held, held.conflicts[0], option.key, option.label)).?;
        try std.testing.expectEqual(claim.ordinal, chosen.ordinal);
    }
    try std.testing.expect((try resolution.chosenClaim(allocator, corpus, held, held.conflicts[0], "no-such-option", options[0].label)) == null);
    // The text under the lines is what the user chose: a label the claim no longer shows selects nothing.
    try std.testing.expect((try resolution.chosenClaim(allocator, corpus, held, held.conflicts[0], options[0].key, "Confirm later.")) == null);
    // A key that two claims of the conflict carry selects none.
    var shared = held.conflicts[0];
    shared.value.claim_ids = &.{ held.conflicts[0].value.claim_ids[0], held.conflicts[0].value.claim_ids[0] };
    try std.testing.expect((try resolution.chosenClaim(allocator, corpus, held, shared, options[0].key, options[0].label)) == null);
    // Two claims that cite the same lines cannot be told apart by key, so they are not options.
    var doubled = held.conflicts[0];
    doubled.value.claim_ids = &.{ held.conflicts[0].value.claim_ids[0], held.conflicts[0].value.claim_ids[0] };
    try std.testing.expectError(error.InvalidClarificationInput, resolution.conflictOptions(allocator, corpus, held, doubled));
    var empty = held.conflicts[0];
    empty.value.claim_ids = &.{};
    try std.testing.expectError(error.InvalidClarificationInput, resolution.conflictOptions(allocator, corpus, held, empty));
}

fn dotted(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const result = try allocator.dupe(u8, path);
    for (result) |*byte| if (byte.* == '/') {
        byte.* = '.';
    };
    return result;
}

fn answered(id: []const u8, status: c.EngineStatus, schema: c.AnswerSchema, subject: c.Subject, response_id: ?u64) c.Record {
    var record = fixture.record(id);
    record.subject = subject;
    record.answer_schema = schema;
    record.status = status;
    record.response_id = response_id;
    return record;
}

fn response(id: u64, clarification: []const u8, answer: c.Answer) c.Response {
    return .{ .id = id, .clarification_id = clarification, .input_state_ordinal = 1, .input_state_revision = 1, .input_record_revision = 1, .submitted_form_bytes = "form", .answer = answer, .actor_id = "fixture-user", .authentication_evidence_id = "AE-1", .answered_at = "2026-09-05T00:00:00Z" };
}

test "only a resolved Specify conflict form that offered options grants a choice, and everything else stays protected and unused" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const options: c.AnswerSchema = .{ .select_one = &.{ .{ .key = "first", .label = "First." }, .{ .key = "second", .label = "Second." } } };
    const text: c.AnswerSchema = .{ .bounded_business_text = 2000 };
    const other = subjectOf(.{ .kind = .reference_meaning, .unit = .{ .signal = .{ .ordinal = 1 } }, .slot = .disposition }, &.{});
    const records = [_]c.Record{
        answered("S01", .resolved_by_user, options, conflict_subject, 1),
        answered("S02", .cancelled_by_user, options, conflictAt("a.md"), 2),
        answered("S03", .open, options, conflictAt("b.md"), null),
        answered("S04", .resolved_by_user, text, conflictAt("c.md"), 3),
        answered("S05", .resolved_by_user, options, other, 4),
        answered("P01", .resolved_by_user, options, conflictAt("d.md"), 5),
    };
    var state = fixture.state(&records);
    const responses = [_]c.Response{
        response(1, "S01", .{ .selected_option = "second" }),
        response(2, "S02", .{ .cancel_reason = "No longer needed." }),
        response(3, "S04", .{ .business_text = "Use the second." }),
        response(4, "S05", .{ .selected_option = "first" }),
        response(5, "P01", .{ .selected_option = "first" }),
    };
    state.responses = &responses;
    const granted = try resolution.choices(allocator, .{ .value = state });
    try std.testing.expectEqual(@as(usize, 1), granted.len);
    try std.testing.expectEqual(@as(u64, 1), granted[0].response_id.ordinal);
    try std.testing.expectEqualStrings("second", granted[0].key);
    try std.testing.expect(resolution.answerFor(granted, conflict_subject) != null);
    try std.testing.expect(resolution.answerFor(granted, other) == null);
    try std.testing.expectEqual(@as(usize, 0), (try resolution.choices(allocator, .{ .value = null })).len);
}

test "a state whose resolved conflict answer is not one of its options or has no response is not valid" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const options: c.AnswerSchema = .{ .select_one = &.{ .{ .key = "first", .label = "First." }, .{ .key = "second", .label = "Second." } } };
    const records = [_]c.Record{answered("S01", .resolved_by_user, options, conflict_subject, 1)};
    var state = fixture.state(&records);
    const offered = [_]c.Response{response(1, "S01", .{ .selected_option = "third" })};
    state.responses = &offered;
    try std.testing.expectError(error.InvalidClarificationInput, resolution.choices(allocator, .{ .value = state }));
    const text = [_]c.Response{response(1, "S01", .{ .business_text = "Use the second." })};
    state.responses = &text;
    try std.testing.expectError(error.InvalidClarificationInput, resolution.choices(allocator, .{ .value = state }));
    const missing = [_]c.Response{response(2, "S01", .{ .selected_option = "first" })};
    state.responses = &missing;
    try std.testing.expectError(error.InvalidClarificationInput, resolution.choices(allocator, .{ .value = state }));
    const zero = [_]c.Record{answered("S01", .resolved_by_user, options, conflict_subject, 0)};
    var zeroed = fixture.state(&zero);
    const none = [_]c.Response{response(0, "S01", .{ .selected_option = "first" })};
    zeroed.responses = &none;
    try std.testing.expectError(error.InvalidClarificationInput, resolution.choices(allocator, .{ .value = zeroed }));
}

test "conflict options and choices release every allocation failure" {
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(sweep, .{});
}
fn sweep(allocator: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const reference = try reconciled.prepare(a, &.{ "Confirm immediately.\n", "Request approval first.\n" });
    defer reference.deinit();
    const final = try f.summaries(a, try f.initialize(a, reference.inputs, reference.extracted, 2), reference.context());
    const accounted = (try f.finish(a, final, try reconciled.conflicting(a, final), reference.context())).valid;
    const held = support.records(accounted);
    const options = try resolution.conflictOptions(allocator, reference.inputs.corpus.sources, held, held.conflicts[0]);
    defer {
        for (options) |option| {
            allocator.free(option.key);
            allocator.free(option.label);
        }
        allocator.free(options);
    }
    const claim = try resolution.chosenClaim(allocator, reference.inputs.corpus.sources, held, held.conflicts[0], options[1].key, options[1].label);
    try std.testing.expect(claim != null);
}
