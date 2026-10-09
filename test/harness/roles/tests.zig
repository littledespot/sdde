const std = @import("std");
const c = @import("contracts.zig");
const score = @import("score.zig");
const cli = @import("cli.zig");
const r = @import("../../../src/domain/reference_reconciliation.zig");
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
    return .{ .extraction = .valid, .json = .valid, .schema = .valid, .parsed = try @import("../../../src/domain/strict_json.zig").decode(std.json.Value, a, try codec.encodeSelected(@import("../../../src/domain/reference_reconciliation_stage.zig").Response, a, .{ .roles = .{ .role_assignments = assignments } }), .{ .maximum_depth = 32 }) };
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
        try std.testing.expectEqual(score.Counts{ .required_roles = 6, .assigned_pairs = 6 }, good.scored);
        const omitted = try score.assess(a, input.accepted, &labels, try validation(a, &.{.{ .signal_id = .{ .ordinal = 1 }, .generation_roles = &.{ .title, .description, .primary_goal, .primary_user_story, .records } }}));
        try std.testing.expectEqual(@as(u32, 1), omitted.scored.missing_supported_roles);
        const invented = try score.assess(a, input.accepted, &labels, try validation(a, &.{ .{ .signal_id = .{ .ordinal = 1 }, .generation_roles = all }, .{ .signal_id = .{ .ordinal = 2 }, .generation_roles = &.{.entity_basis} } }));
        try std.testing.expectEqual(@as(u32, 1), invented.scored.unsupported_pairs);
        try std.testing.expectEqual(@as(u32, 0), invented.scored.missing_supported_roles);
        const invalid = try score.assess(a, input.accepted, &labels, try validation(a, &.{.{ .signal_id = .{ .ordinal = 999 }, .generation_roles = all }}));
        try std.testing.expect(invalid == .native_rejected);
        try std.testing.expectEqual(.protocol_rejected, try score.assess(a, input.accepted, &labels, .{}));
        const duplicates = try score.assess(a, input.accepted, &labels, try validation(a, &.{.{ .signal_id = .{ .ordinal = 1 }, .generation_roles = &.{ .records, .records } }}));
        try std.testing.expect(duplicates == .native_rejected);
    }
}
test "calibration labels permit alternatives and ambiguity without rewarding invented assignments" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const packet = try @import("input.zig").packet(std.testing.io, a, &.{ .{ .text = "MOCK A member can renew a loan.\n", .kind = .business }, .{ .text = "MOCK A librarian can renew a loan for a member.\n", .kind = .business } });
    defer packets.release(packet);
    const input = try codec.decode(@import("../../../src/domain/reference_model_input.zig").RoleInput, a, packet.body());
    var alternatives = labels;
    for (&alternatives) |*label| label.allowed_signal_ids = &.{ .{ .ordinal = 1 }, .{ .ordinal = 2 } };
    const accepted = try score.assess(a, input.accepted, &alternatives, try validation(a, &.{.{ .signal_id = .{ .ordinal = 2 }, .generation_roles = std.meta.tags(r.GenerationRole) }}));
    try std.testing.expectEqual(@as(u32, 0), accepted.scored.missing_supported_roles);
    for (&alternatives) |*label| label.required = false;
    try std.testing.expectEqual(score.Counts{}, (try score.assess(a, input.accepted, &alternatives, try validation(a, &.{}))).scored);
    alternatives[0].allowed_signal_ids = &.{.{ .ordinal = 999 }};
    try std.testing.expectError(error.InvalidEvaluationContract, score.validateLabels(input.accepted, &alternatives));
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
    for (cohort.cases) |entry| if (entry.input == .controlled) {
        const packet = try @import("input.zig").packet(std.testing.io, a, entry.input.controlled);
        defer packets.release(packet);
        const input = try codec.decode(@import("../../../src/domain/reference_model_input.zig").RoleInput, a, packet.body());
        try score.validateLabels(input.accepted, entry.labels);
        try std.testing.expect(std.mem.indexOf(u8, packet.body(), entry.rationale) == null);
        try std.testing.expect(std.mem.indexOf(u8, packet.body(), "allowed_signal_ids") == null);
    };
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
    valid.outcome = .{ .scored = .{ .required_roles = 6, .assigned_pairs = 5, .missing_supported_roles = 1 } };
    valid.validation = .{ .input_tokens = 10, .output_tokens = 5 };
    var unusable = prepared;
    unusable.outcome = .protocol_rejected;
    unusable.validation = .{};
    var failed = prepared;
    failed.failure = "MOCK-transport-failure";
    const counts = report.totals(&.{ valid, unusable, failed });
    try std.testing.expectEqual(@as(u64, 3), counts[0].declared_trials);
    try std.testing.expectEqual(@as(u64, 1), counts[0].scored);
    try std.testing.expectEqual(@as(u64, 1), counts[0].protocol_rejected);
    try std.testing.expectEqual(@as(u64, 1), counts[0].operational_failures);
    try std.testing.expectEqual(@as(u64, 1), counts[0].trials_with_usage);
    try std.testing.expectEqual(@as(u64, 0), counts[0].exact_semantic_cases);
    try std.testing.expectEqual(@as(u64, 0), counts[1].declared_trials);
    const text = try report.markdown(std.testing.allocator, false, false, &.{prepared});
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "no semantic outcomes") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "not_run") != null);
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
        .controls = .{ .temperature = .zero },
        .reasoning_effort = "low",
        .operation_kind = .inference,
    };
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
    }
}
