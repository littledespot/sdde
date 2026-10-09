const std = @import("std");
const c = @import("contracts.zig");
const score = @import("score.zig");
const cli = @import("cli.zig");
const r = @import("../../../src/domain/reference_reconciliation.zig");
const roles = @import("../../../src/domain/reference_role_assignment.zig");
const codec = @import("../../../src/domain/model_candidate_json.zig");
const packets = @import("../../../src/domain/model_input_packet.zig");
const debug = @import("../../../src/domain/request_debugger.zig");
const labels = [_]c.Label{
    .{ .role = .title, .required = true, .allowed_signal_ids = &.{.{ .ordinal = 1 }} },
    .{ .role = .description, .required = true, .allowed_signal_ids = &.{.{ .ordinal = 1 }} },
    .{ .role = .primary_goal, .required = true, .allowed_signal_ids = &.{.{ .ordinal = 1 }} },
    .{ .role = .primary_user_story, .required = true, .allowed_signal_ids = &.{.{ .ordinal = 1 }} },
    .{ .role = .entity_basis, .required = true, .allowed_signal_ids = &.{.{ .ordinal = 1 }} },
    .{ .role = .records, .required = true, .allowed_signal_ids = &.{.{ .ordinal = 1 }} },
};
fn validation(a: std.mem.Allocator, assignments: []const r.RoleAssignment) !debug.Validation {
    const decisions = try @import("../../../src/test_fixtures/reference_reconciliation.zig").roleDecisions(a, assignments);
    return .{ .extraction = .valid, .json = .valid, .schema = .valid, .parsed = try @import("../../../src/domain/strict_json.zig").decode(std.json.Value, a, try codec.encodeSelected(@import("../../../src/domain/reference_reconciliation_stage.zig").Response, a, .{ .roles = .{ .role_decisions = decisions } }), .{ .maximum_depth = 32 }) };
}
fn expectCounts(expected: score.Counts, actual: score.Counts) !void {
    inline for (@typeInfo(score.Counts).@"struct".fields) |field| {
        if (comptime std.mem.eql(u8, field.name, "by_role")) continue;
        try std.testing.expectEqual(@field(expected, field.name), @field(actual, field.name));
    }
}
fn validateControlledLabels(a: std.mem.Allocator, sources: []const c.Source, case_labels: []const c.Label, rationale: []const u8) !void {
    const packet = try @import("input.zig").packet(std.testing.io, a, sources);
    defer packets.release(packet);
    const input = try codec.decode(@import("../../../src/domain/reference_model_input.zig").RoleInput, a, packet.body());
    try score.validateLabels(input.accepted, case_labels);
    const rationale_json = try std.json.Stringify.valueAlloc(a, rationale, .{});
    try std.testing.expect(std.mem.indexOf(u8, packet.body(), rationale_json) == null);
    for ([_][]const u8{ "\"labels\"", "\"rationale\"", "\"allowed_signal_ids\"" }) |key| try std.testing.expect(std.mem.indexOf(u8, packet.body(), key) == null);
}
test "role calibration separates omission, invented support and native/protocol rejection across domains" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "MOCK Display the current UTC time and `MOCK Ready!`.\n", "MOCK Renew an eligible member loan and display `MOCK Renewed!`.\n" }) |text| {
        const packet = try @import("input.zig").packet(std.testing.io, a, &.{.{ .text = text, .kind = .business }});
        defer packets.release(packet);
        const input = try codec.decode(@import("../../../src/domain/reference_model_input.zig").RoleInput, a, packet.body());
        try std.testing.expectEqual(@as(usize, 2), input.accepted.signals.len);
        const all = std.meta.tags(r.GenerationRole);
        const good = try score.assess(a, input.accepted, &labels, try validation(a, &.{.{ .signal_id = .{ .ordinal = 1 }, .generation_roles = all }}));
        try expectCounts(score.Counts{ .required_roles = 6, .assigned_pairs = 6 }, good.scored);
        const omitted = try score.assess(a, input.accepted, &labels, try validation(a, &.{.{ .signal_id = .{ .ordinal = 1 }, .generation_roles = &.{ .title, .description, .primary_goal, .primary_user_story, .records } }}));
        try std.testing.expectEqual(@as(u32, 1), omitted.scored.missing_supported_roles);
        try std.testing.expectEqual(@as(u32, 1), omitted.scored.false_unsupported_roles);
        try std.testing.expectEqual(score.RoleCounts{ .role = .entity_basis, .required_roles = 1, .missing_supported_roles = 1, .false_unsupported_roles = 1 }, omitted.scored.by_role[@intFromEnum(r.GenerationRole.entity_basis)]);
        const invented = try score.assess(a, input.accepted, &labels, try validation(a, &.{ .{ .signal_id = .{ .ordinal = 1 }, .generation_roles = all }, .{ .signal_id = .{ .ordinal = 2 }, .generation_roles = &.{.entity_basis} } }));
        try std.testing.expectEqual(@as(u32, 1), invented.scored.unsupported_pairs);
        try std.testing.expectEqual(@as(u32, 1), invented.scored.wrong_basis_pairs);
        try std.testing.expectEqual(@as(u32, 0), invented.scored.missing_supported_roles);
        const invalid = try score.assess(a, input.accepted, &labels, try validation(a, &.{.{ .signal_id = .{ .ordinal = 999 }, .generation_roles = all }}));
        try std.testing.expect(invalid == .native_rejected);
        try std.testing.expectEqual(.protocol_rejected, try score.assess(a, input.accepted, &labels, .{}));
        const duplicates = try score.assess(a, input.accepted, &labels, try validation(a, &.{.{ .signal_id = .{ .ordinal = 1 }, .generation_roles = &.{ .records, .records } }}));
        try std.testing.expect(duplicates == .native_rejected);
    }
}
test "partial mandatory labels separate missing support, wrong basis and unsupported roles" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const packet = try @import("input.zig").packet(std.testing.io, a, &.{
        .{ .text = "MOCK Earlier group describes runtime context only.\n", .kind = .technical },
        .{ .text = "MOCK Display name is delivery status. MOCK Goal is to show delivery availability; user interaction and entities are undecided.\n", .kind = .business },
    });
    defer packets.release(packet);
    const input = try codec.decode(@import("../../../src/domain/reference_model_input.zig").RoleInput, a, packet.body());
    try std.testing.expectEqual(@as(usize, 2), input.accepted.signals.len);
    var partial = labels;
    for (&partial) |*label| {
        label.required = false;
        label.allowed_signal_ids = &.{};
    }
    partial[0] = .{ .role = .title, .required = true, .allowed_signal_ids = &.{.{ .ordinal = 2 }} };
    partial[1] = .{ .role = .description, .required = false, .allowed_signal_ids = &.{.{ .ordinal = 2 }} };
    partial[2] = .{ .role = .primary_goal, .required = true, .allowed_signal_ids = &.{.{ .ordinal = 2 }} };
    try score.validateLabels(input.accepted, &partial);
    const supported = try score.assess(a, input.accepted, &partial, try validation(a, &.{.{ .signal_id = .{ .ordinal = 2 }, .generation_roles = &.{ .title, .primary_goal } }}));
    try expectCounts(score.Counts{ .required_roles = 2, .assigned_pairs = 2 }, supported.scored);
    const omitted = try score.assess(a, input.accepted, &partial, try validation(a, &.{.{ .signal_id = .{ .ordinal = 2 }, .generation_roles = &.{.title} }}));
    try expectCounts(score.Counts{ .required_roles = 2, .assigned_pairs = 1, .missing_supported_roles = 1, .false_unsupported_roles = 1 }, omitted.scored);
    const unsupported = try score.assess(a, input.accepted, &partial, try validation(a, &.{.{ .signal_id = .{ .ordinal = 2 }, .generation_roles = &.{ .title, .primary_goal, .entity_basis } }}));
    try expectCounts(score.Counts{ .required_roles = 2, .assigned_pairs = 3, .unsupported_pairs = 1 }, unsupported.scored);
    const wrong_basis = try score.assess(a, input.accepted, &partial, try validation(a, &.{
        .{ .signal_id = .{ .ordinal = 2 }, .generation_roles = &.{.title} },
        .{ .signal_id = .{ .ordinal = 1 }, .generation_roles = &.{.primary_goal} },
    }));
    try expectCounts(score.Counts{ .required_roles = 2, .assigned_pairs = 2, .missing_supported_roles = 1, .unsupported_pairs = 1, .wrong_basis_pairs = 1 }, wrong_basis.scored);
    try std.testing.expectEqual(score.RoleCounts{ .role = .primary_goal, .required_roles = 1, .missing_supported_roles = 1, .assigned_pairs = 1, .unsupported_pairs = 1, .wrong_basis_pairs = 1 }, wrong_basis.scored.by_role[@intFromEnum(r.GenerationRole.primary_goal)]);
}
test "role support spans later groups and follows group identity through source and assignment reordering" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const sources = [_]c.Source{
        .{ .text = "MOCK An earlier proposal exports receipts and is unrelated to the selected notification feature.\n", .kind = .business },
        .{ .text = "MOCK The notification feature tells users when a delivery is available.\n", .kind = .business },
        .{ .text = "MOCK A recipient manages delivery notifications and their delivery status.\n", .kind = .business },
    };
    for ([_][3]usize{ .{ 0, 1, 2 }, .{ 2, 0, 1 } }) |order| {
        const ordered = [_]c.Source{ sources[order[0]], sources[order[1]], sources[order[2]] };
        const packet = try @import("input.zig").packet(std.testing.io, a, &ordered);
        defer packets.release(packet);
        const input = try codec.decode(@import("../../../src/domain/reference_model_input.zig").RoleInput, a, packet.body());
        try std.testing.expectEqual(@as(usize, 3), input.accepted.signals.len);
        const intent: r.SignalSelectionId = .{ .ordinal = @intCast(std.mem.indexOfScalar(usize, &order, 1).? + 1) };
        const actor: r.SignalSelectionId = .{ .ordinal = @intCast(std.mem.indexOfScalar(usize, &order, 2).? + 1) };
        const intent_ids = [_]r.SignalSelectionId{intent};
        const actor_ids = [_]r.SignalSelectionId{actor};
        const record_ids = [_]r.SignalSelectionId{ intent, actor };
        const split = [_]c.Label{
            .{ .role = .title, .required = true, .allowed_signal_ids = &intent_ids },
            .{ .role = .description, .required = true, .allowed_signal_ids = &intent_ids },
            .{ .role = .primary_goal, .required = true, .allowed_signal_ids = &intent_ids },
            .{ .role = .primary_user_story, .required = true, .allowed_signal_ids = &actor_ids },
            .{ .role = .entity_basis, .required = true, .allowed_signal_ids = &actor_ids },
            .{ .role = .records, .required = true, .allowed_signal_ids = &record_ids },
        };
        try score.validateLabels(input.accepted, &split);
        const assignments = [_]r.RoleAssignment{
            .{ .signal_id = intent, .generation_roles = &.{ .title, .description, .primary_goal, .records } },
            .{ .signal_id = actor, .generation_roles = &.{ .primary_user_story, .entity_basis, .records } },
        };
        const expected: score.Counts = .{ .required_roles = 6, .assigned_pairs = 7 };
        try expectCounts(expected, (try score.assess(a, input.accepted, &split, try validation(a, &assignments))).scored);
        const reversed_assignments = [_]r.RoleAssignment{ assignments[1], assignments[0] };
        var reordered_facts = input.accepted;
        const reordered_groups = try a.dupe(roles.Group, input.accepted.signals);
        std.mem.reverse(roles.Group, reordered_groups);
        reordered_facts.signals = reordered_groups;
        try expectCounts(expected, (try score.assess(a, reordered_facts, &split, try validation(a, &reversed_assignments))).scored);
        const omitted = try score.assess(a, input.accepted, &split, try validation(a, assignments[0..1]));
        try expectCounts(score.Counts{ .required_roles = 6, .assigned_pairs = 4, .missing_supported_roles = 2, .false_unsupported_roles = 2 }, omitted.scored);
        const swapped = [_]r.RoleAssignment{
            .{ .signal_id = actor, .generation_roles = assignments[0].generation_roles },
            .{ .signal_id = intent, .generation_roles = assignments[1].generation_roles },
        };
        try expectCounts(score.Counts{ .required_roles = 6, .assigned_pairs = 7, .missing_supported_roles = 5, .unsupported_pairs = 5, .wrong_basis_pairs = 5 }, (try score.assess(a, input.accepted, &split, try validation(a, &swapped))).scored);
    }
}
test "calibration labels permit alternatives and ambiguity without rewarding invented assignments" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const packet = try @import("input.zig").packet(std.testing.io, a, &.{ .{ .text = "MOCK A member can renew a loan.\n", .kind = .business }, .{ .text = "MOCK A librarian can renew a loan for a member.\n", .kind = .business }, .{ .text = "MOCK Runtime context supplies no loan entity basis.\n", .kind = .technical } });
    defer packets.release(packet);
    const input = try codec.decode(@import("../../../src/domain/reference_model_input.zig").RoleInput, a, packet.body());
    var alternatives = labels;
    for (&alternatives) |*label| label.allowed_signal_ids = &.{ .{ .ordinal = 1 }, .{ .ordinal = 2 } };
    const accepted = try score.assess(a, input.accepted, &alternatives, try validation(a, &.{.{ .signal_id = .{ .ordinal = 2 }, .generation_roles = std.meta.tags(r.GenerationRole) }}));
    try std.testing.expectEqual(@as(u32, 0), accepted.scored.missing_supported_roles);
    for (&alternatives) |*label| label.required = false;
    try expectCounts(score.Counts{}, (try score.assess(a, input.accepted, &alternatives, try validation(a, &.{}))).scored);
    const ambiguous = try score.assess(a, input.accepted, &alternatives, try validation(a, &.{
        .{ .signal_id = .{ .ordinal = 1 }, .generation_roles = &.{.entity_basis} },
        .{ .signal_id = .{ .ordinal = 2 }, .generation_roles = &.{.entity_basis} },
    }));
    try expectCounts(score.Counts{ .assigned_pairs = 2 }, ambiguous.scored);
    const outside = try score.assess(a, input.accepted, &alternatives, try validation(a, &.{.{ .signal_id = .{ .ordinal = 3 }, .generation_roles = &.{.entity_basis} }}));
    try expectCounts(score.Counts{ .assigned_pairs = 1, .unsupported_pairs = 1, .wrong_basis_pairs = 1 }, outside.scored);
    alternatives[0].allowed_signal_ids = &.{.{ .ordinal = 999 }};
    try std.testing.expectError(error.InvalidEvaluationContract, score.validateLabels(input.accepted, &alternatives));
}
test "complete role calibration distinguishes missing decision fields from false unsupported semantics" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const packet = try @import("input.zig").packet(std.testing.io, a, &.{.{ .text = "MOCK Display a loan renewal outcome.\n", .kind = .business }});
    defer packets.release(packet);
    const input = try codec.decode(@import("../../../src/domain/reference_model_input.zig").RoleInput, a, packet.body());
    const negative = try validation(a, &.{});
    try std.testing.expectEqual(score.DecisionCoverage{ .required_decisions = 6, .missing_decisions = 0 }, score.decisionCoverage(negative).?);
    const assessed = try score.assess(std.testing.allocator, input.accepted, &labels, negative);
    try expectCounts(.{ .required_roles = 6, .missing_supported_roles = 6, .false_unsupported_roles = 6 }, assessed.scored);
    var missing = try validation(a, &.{});
    try std.testing.expect(missing.parsed.?.object.getPtr("role_decisions").?.object.swapRemove("entity_basis"));
    missing.schema = .invalid;
    try std.testing.expectEqual(score.DecisionCoverage{ .required_decisions = 6, .missing_decisions = 1 }, score.decisionCoverage(missing).?);
    try std.testing.expectEqual(.protocol_rejected, try score.assess(std.testing.allocator, input.accepted, &labels, missing));
    const old: debug.Validation = .{ .extraction = .valid, .json = .valid, .schema = .valid, .parsed = try @import("../../../src/domain/strict_json.zig").decode(std.json.Value, a, "{\"role_assignments\":[]}", .{ .maximum_depth = 32 }) };
    try std.testing.expectEqual(.protocol_rejected, try score.assess(std.testing.allocator, input.accepted, &labels, old));
    try std.testing.expectEqual(score.DecisionCoverage{ .required_decisions = 6, .missing_decisions = 6 }, score.decisionCoverage(old).?);
    try std.testing.expect(score.decisionCoverage(.{}) == null);
    var malformed = negative;
    malformed.json = .invalid;
    try std.testing.expect(score.decisionCoverage(malformed) == null);
}
test "calibration uses closed cohort labels and explicit invocation with no live default" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var draft = try c.parse(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "test/calibration/authoring-roles/cohort.json", a, .unlimited));
    // Admission tests are independent of the real cohort's human review status.
    draft.label_status = .proposed;
    draft.reviewer = null;
    const original = try std.json.Stringify.valueAlloc(a, draft, .{ .whitespace = .indent_2 });
    const cohort = try c.parse(a, original);
    try std.testing.expectEqual(.proposed, cohort.label_status);
    for ([_][2][]const u8{ .{ "role-calibration/v1", "role-calibration/v2" }, .{ "\"reviewer\": null", "\"reviewer\": \"assistant\"" }, .{ "\"label_status\":", "\"unknown\": true, \"label_status\":" }, .{ "\"entity_basis\"", "\"records\"" }, .{ "\"family\": \"timer\"", "\"family\": \"clock\"" }, .{ "\"label_status\": \"proposed\"", "\"label_status\": \"reviewed\"" } }) |replacement| {
        const bytes = try std.mem.replaceOwned(u8, a, original, replacement[0], replacement[1]);
        try std.testing.expectError(error.InvalidEvaluationContract, c.parse(a, bytes));
    }
    const options = try cli.parse(&.{ "--cohort", "cohort.json", "--output", "out", "--feature", "captured/feature", "--run", "run", "--call", "7", "--repeats", "2", "--split", "development" });
    try std.testing.expect(!options.live);
    try std.testing.expectError(error.InvalidArguments, cli.parse(&.{}));
    try std.testing.expectError(error.InvalidArguments, cli.parse(&.{ "--cohort", "../cohort.json", "--output", "out", "--feature", "feature", "--run", "run", "--call", "7", "--repeats", "1" }));
    for (cohort.cases) |entry| if (entry.input == .controlled) try validateControlledLabels(a, entry.input.controlled, entry.labels, entry.rationale);
}
test "routing cohorts admit controlled label handles without exposing labels or reading captured logs" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var controlled_cases: usize = 0;
    var captured_cases: usize = 0;
    for ([_][]const u8{
        "test/calibration/authoring-roles/routing.cohort.json",
        "test/calibration/authoring-roles/routing-captured.cohort.json",
    }) |path| {
        const cohort = try c.parse(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .unlimited));
        for (cohort.cases) |entry| switch (entry.input) {
            .controlled => |sources| {
                try validateControlledLabels(a, sources, entry.labels, entry.rationale);
                controlled_cases += 1;
            },
            .captured => captured_cases += 1,
        };
    }
    try std.testing.expect(controlled_cases != 0);
    try std.testing.expect(captured_cases != 0);
}

test "calibration reports unusable answers and unknown usage without a false quality pass" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expect((try cli.responseFailure(a, .{ .id = "MOCK-response", .outcome = .received, .status = 200 })) == null);
    try std.testing.expectEqualStrings("HTTP-503", (try cli.responseFailure(a, .{ .id = "MOCK-response", .outcome = .received, .status = 503 })).?);
    try std.testing.expectEqualStrings("MOCK-cancelled", (try cli.responseFailure(a, .{ .id = "MOCK-response", .outcome = .cancelled, .diagnostic = "MOCK-cancelled" })).?);
    try std.testing.expectEqualStrings("partial", (try cli.responseFailure(a, .{ .id = "MOCK-response", .outcome = .partial })).?);
    const report = @import("report.zig");
    const prepared: report.Trial = .{ .case_id = "MOCK-case", .family = "MOCK-family", .split = .development, .input_origin = .controlled, .repeat = 1, .variant = .baseline, .guidance_bytes = 10, .input_bytes = 20, .schema_bytes = 30 };
    var valid = prepared;
    valid.outcome = .{ .scored = .{ .required_roles = 6, .assigned_pairs = 8, .missing_supported_roles = 1, .false_unsupported_roles = 1, .unsupported_pairs = 2, .wrong_basis_pairs = 1 } };
    valid.validation = .{ .input_tokens = 10, .output_tokens = 5 };
    valid.decision_coverage = .{ .required_decisions = 6, .missing_decisions = 0 };
    var unusable = prepared;
    unusable.outcome = .protocol_rejected;
    unusable.validation = .{};
    unusable.decision_coverage = .{ .required_decisions = 6, .missing_decisions = 1 };
    var failed = prepared;
    failed.failure = "MOCK-transport-failure";
    var exact = prepared;
    exact.variant = .candidate;
    exact.outcome = .{ .scored = .{ .required_roles = 2, .assigned_pairs = 2 } };
    const trials = [_]report.Trial{ valid, unusable, failed, exact };
    const counts = report.totals(&trials);
    try std.testing.expectEqual(@as(u64, 3), counts[0].declared_trials);
    try std.testing.expectEqual(@as(u64, 1), counts[0].scored);
    try std.testing.expectEqual(@as(u64, 1), counts[0].protocol_rejected);
    try std.testing.expectEqual(@as(u64, 1), counts[0].operational_failures);
    try std.testing.expectEqual(@as(u64, 1), counts[0].trials_with_usage);
    try std.testing.expectEqual(@as(u64, 0), counts[0].exact_semantic_cases);
    try std.testing.expectEqual(@as(u64, 6), counts[0].required_roles);
    try std.testing.expectEqual(@as(u64, 1), counts[0].missing_supported_roles);
    try std.testing.expectEqual(@as(u64, 1), counts[0].false_unsupported_roles);
    try std.testing.expectEqual(@as(u64, 2), counts[0].decision_observations);
    try std.testing.expectEqual(@as(u64, 1), counts[0].missing_decisions);
    try std.testing.expectEqual(@as(u64, 12), counts[0].required_decisions);
    try std.testing.expectEqual(@as(u64, 8), counts[0].assigned_pairs);
    try std.testing.expectEqual(@as(u64, 2), counts[0].unsupported_pairs);
    try std.testing.expectEqual(@as(u64, 1), counts[0].wrong_basis_pairs);
    try std.testing.expectEqual(@as(u64, 1), counts[1].declared_trials);
    try std.testing.expectEqual(@as(u64, 1), counts[1].exact_semantic_cases);
    try std.testing.expectEqual(@as(u64, 0), counts[1].wrong_basis_pairs);
    const measured = try report.markdown(std.testing.allocator, true, false, &trials);
    defer std.testing.allocator.free(measured);
    try std.testing.expect(std.mem.indexOf(u8, measured, "Wrong-basis / unsupported pairs") != null);
    try std.testing.expect(std.mem.indexOf(u8, measured, "subset of unsupported pairs whose role has at least one labelled allowed group") != null);
    try std.testing.expect(std.mem.indexOf(u8, measured, "| baseline | 3 | 1 | 1 | 0 | 1 | 1/6 | 1/6 | 2/8 | 1/2 | 0 |") != null);
    try std.testing.expect(std.mem.indexOf(u8, measured, "| candidate | 1 | 1 | 0 | 0 | 0 | 0/2 | 0/2 | 0/2 | 0/0 | 1 |") != null);
    try std.testing.expect(std.mem.indexOf(u8, measured, "| MOCK-case | controlled | 1 | baseline | scored | 0 | 1 | 1 | 2 | 1 |") != null);
    try std.testing.expect(std.mem.indexOf(u8, measured, "| MOCK-case | controlled | 1 | baseline | protocol_rejected | 1 | — | — | — | — |") != null);
    try std.testing.expect(std.mem.indexOf(u8, measured, "| MOCK-case | controlled | 1 | baseline | operational_failure | unknown | — | — | — | — |") != null);
    try std.testing.expect(std.mem.indexOf(u8, measured, "Structural coverage: 1/12 missing decision fields over 2/3 observed JSON objects") != null);
    const text = try report.markdown(std.testing.allocator, false, false, &.{prepared});
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "no semantic outcomes") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "not_run") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "| MOCK-case | controlled | 1 | baseline | not_run | unknown | — | — | — | — |") != null);
}

test "controlled calibration claims retain only their own captured source chunk" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const packet = try @import("input.zig").packet(std.testing.io, a, &.{.{ .text = "MOCK first line.\n" ** 35 ++ "MOCK second line.\n" ** 35, .kind = .business }});
    defer packets.release(packet);
    const input = try codec.decode(@import("../../../src/domain/reference_model_input.zig").RoleInput, a, packet.body());
    try std.testing.expect(input.claims.len >= 2);
    for (input.claims) |claim| {
        const cited = input.citations[claim.citation_ids[0].ordinal - 1].value.verbatim.?;
        try std.testing.expectEqualStrings(cited, claim.content.model.business.segments[0].literal.value);
    }
}

test "prepared calibration descriptions retain distinct case inputs after packet release" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var parser: @import("../../../src/adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const compiled = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/reconciliation.schema.json", a, .unlimited));
    const canonical = compiled.select(.{ .bytes = "roles_assignment" }).?;
    const binding: debug.Description = .{
        .provider = "aws-bedrock",
        .model = "openai.gpt-oss-20b-1:0",
        .provider_config = .{ .aws_bedrock = .{ .region = .@"ap-southeast-2" } },
        .model_slot = "MOCK-generation",
        .workflow_id = "MOCK-spec",
        .workflow_version = 1,
        .request_step = "MOCK-roles",
        .content = &.{},
        .protocol_prompt = @import("../../../src/domain/model_controls.zig").response_format_guidance,
        .schema = "",
        .response_mode = .native_schema,
        .controls = .{ .temperature = .zero, .max_output_tokens = @import("../../../src/domain/model_controls.zig").OutputTokenAllowance.init(12288).? },
        .reasoning_effort = "low",
        .operation_kind = .inference,
    };
    try cli.validateBinding(binding);
    for (0..3) |invalid| {
        var rejected = binding;
        switch (invalid) {
            0 => rejected.controls.max_output_tokens = .{ .value = 0 },
            1 => rejected.controls.temperature = null,
            2 => {
                const unsupported = @import("../../../src/composition/provider_model_contracts.zig").registry.entries[1];
                rejected.model = unsupported.model.bytes;
                rejected.provider_config = .{ .aws_bedrock = .{ .region = unsupported.bedrock_regions[0] } };
                rejected.response_mode = .prompt_only;
                rejected.reasoning_effort = null;
            },
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidEvaluationContract, cli.validateBinding(rejected));
    }
    const texts = [_][]const u8{ "MOCK Display UTC time.\n", "MOCK Renew a loan.\n", "MOCK Store an item.\n" };
    var descriptions: [texts.len]debug.Description = undefined;
    for (texts, &descriptions) |text, *description| {
        const packet = try @import("input.zig").packet(std.testing.io, a, &.{.{ .text = text, .kind = .business }});
        defer packets.release(packet);
        description.* = try cli.controlledDescription(a, binding, packet, "MOCK guidance", canonical);
    }
    for (texts, descriptions, 0..) |text, description, index| {
        for (descriptions[0..index]) |prior| try std.testing.expect(prior.content.ptr != description.content.ptr);
        const input = try cli.roleInput(a, description);
        try std.testing.expectEqualStrings(text, input.claims[0].content.model.business.segments[0].literal.value);
        try std.testing.expectEqualStrings("MOCK guidance", description.content[0].guidance);
        try std.testing.expectEqualDeep(binding.controls, description.controls);
    }
    const original = try cli.roleInput(a, descriptions[0]);
    // Historical schema and instructions remain unchanged; the declared diagnostic
    // modification reprojects current instructions without changing source facts.
    var stale_input = original;
    stale_input.assignment.constraints = &.{.{ .constraint = .supported_role_assignment, .requirement = "MOCK old sparse group-assignment instructions" }};
    var historical = descriptions[0];
    historical.schema = "MOCK historical sparse schema bytes";
    historical.content = &.{ .{ .guidance = "MOCK guidance" }, .{ .user = try codec.encode(@TypeOf(stale_input), a, stale_input) } };
    const projected = try cli.capturedDescription(a, historical, "MOCK current guidance", canonical);
    try std.testing.expectEqualDeep(binding.controls, projected.controls);
    try std.testing.expect(!std.mem.eql(u8, historical.content[1].user, projected.content[1].user));
    try std.testing.expectEqualStrings("MOCK guidance", historical.content[0].guidance);
    try std.testing.expectEqualStrings("MOCK historical sparse schema bytes", historical.schema);
    try std.testing.expectEqualStrings("MOCK current guidance", projected.content[0].guidance);
    try std.testing.expect(std.mem.indexOf(u8, projected.schema, "role_decisions") != null);
    try std.testing.expect(std.mem.indexOf(u8, projected.schema, "role_assignments") == null);
    const admitted = try cli.roleInput(a, projected);
    try std.testing.expectEqualDeep(original.assignment.role_definitions, admitted.assignment.role_definitions);
    try std.testing.expectEqualDeep(original.claims, admitted.claims);
    try std.testing.expectEqualDeep(original.citations, admitted.citations);
    try std.testing.expectEqualDeep(original.preserved_tokens, admitted.preserved_tokens);
    try std.testing.expectEqualDeep(original.passive_literals, admitted.passive_literals);
    try std.testing.expectEqualDeep(original.accepted, admitted.accepted);
    try std.testing.expectEqualDeep(original.assignment.constraints, admitted.assignment.constraints);
    try std.testing.expectEqualStrings("MOCK old sparse group-assignment instructions", (try cli.roleInput(a, historical)).assignment.constraints[0].requirement);
    // A declared MOCK empty native catalogue has only negative branches; no
    // invalid empty enum or synthesized role assessment is inserted.
    var empty_input = original;
    empty_input.accepted.signals = &.{};
    var empty_description = historical;
    empty_description.content = &.{ .{ .guidance = "MOCK historical guidance" }, .{ .user = try codec.encode(@TypeOf(empty_input), a, empty_input) } };
    const empty_projection = try cli.capturedDescription(a, empty_description, "MOCK current guidance", canonical);
    const empty_schema = try parser.compiler().compileSelected(a, empty_projection.schema);
    const schema = @import("../../../src/domain/model_result_schema.zig");
    const decision_fields = schema.findProperty(empty_schema.root().object, "role_decisions").?.schema.object;
    for (std.meta.tags(r.GenerationRole)) |role| {
        const negative = schema.findProperty(decision_fields, @tagName(role)).?.schema;
        try std.testing.expectEqualStrings("unsupported", schema.findProperty(negative.object, "kind").?.schema.constant.string);
    }
    for (0..4) |mode| {
        var invalid = original;
        const definitions = try a.dupe(@import("../../../src/domain/reference_model_input.zig").RoleDefinition, original.assignment.role_definitions);
        switch (mode) {
            0 => definitions[1].role = definitions[0].role,
            1 => definitions[0].purpose = " \t\n",
            2 => definitions[0].purpose = "MOCK invalid\x00purpose",
            3 => definitions[0].purpose = "MOCK different well-formed purpose",
            else => unreachable,
        }
        invalid.assignment.role_definitions = definitions;
        var description = descriptions[0];
        description.content = &.{ .{ .guidance = "MOCK guidance" }, .{ .user = try codec.encode(@TypeOf(invalid), a, invalid) } };
        try std.testing.expectError(error.InvalidEvaluationContract, cli.roleInput(a, description));
    }
}
