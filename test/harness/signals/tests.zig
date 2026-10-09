//! Frozen diagnostic inputs only; no model dispatch or semantic-success oracle.
const std = @import("std");
const files = @import("../files.zig");
const contracts = @import("../contracts.zig");
const codec = @import("../../../src/domain/model_candidate_json.zig");
const packets = @import("../../../src/domain/model_input_packet.zig");
const schemas = @import("../../../src/domain/model_result_schema.zig");
const debug = @import("../../../src/domain/request_debugger.zig");
const r = @import("../../../src/domain/reference_reconciliation.zig");
const model_input = @import("../../../src/domain/reference_model_input.zig");
const directory = "test/calibration/signal-grouping/";
const Case = struct {
    id: []const u8,
    origin: enum { captured, controlled },
    obligations: []const struct { id: []const u8, claim_id: u32, meaning: []const u8 },
    literal_expectations: []const struct { claim_id: u32, value: []const u8 },
    accepted_member_sets: []const []const u32,
    baseline_edit: []const u8,
    baseline_edit_sha256: []const u8,
    baseline_schema_sha256: []const u8,
    candidate_edit: []const u8,
    candidate_edit_sha256: []const u8,
    candidate_schema_sha256: []const u8,
};
const Cohort = struct {
    schema: enum { @"signal-grouping-comparison/v1" },
    label_status: enum { proposed, reviewed },
    baseline_revision: []const u8,
    capture: struct { feature: []const u8, run: []const u8, call: []const u8, context_sha256: []const u8 },
    model: struct { provider: []const u8, model: []const u8, region: []const u8, reasoning_effort: []const u8, temperature: u32, response_mode: enum { native_schema } },
    repeats: u32,
    maximum_physical_calls: u32,
    cases: []const Case,
    trials: []const struct { id: []const u8, case: []const u8, arm: enum { baseline, candidate }, repeat: u32, edit: []const u8 },
};
fn read(a: std.mem.Allocator, name: []const u8) ![]const u8 {
    return files.read(std.testing.io, a, .cwd(), try std.mem.concat(a, u8, &.{ directory, name }));
}
fn hash(expected: []const u8, bytes: []const u8) !void {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    try std.testing.expectEqualStrings(expected, &std.fmt.bytesToHex(digest, .lower));
}
fn same(a: std.mem.Allocator, left: std.json.Value, right: std.json.Value) !void {
    try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, left, .{}), try std.json.Stringify.valueAlloc(a, right, .{}));
}
fn body(a: std.mem.Allocator, edit: debug.Edit) !std.json.Value {
    try std.testing.expectEqual(@as(usize, 2), edit.content.len);
    return contracts.decode(std.json.Value, a, edit.content[1].user);
}

test "signal comparison freezes paired evidence coverage labels and unchanged repeated requests" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const manifest_bytes = try read(a, "comparison.json");
    const cohort = try contracts.decode(Cohort, a, manifest_bytes);
    try std.testing.expectEqual(@as(usize, 3), cohort.cases.len);
    try std.testing.expectEqual(@as(u32, 12), cohort.maximum_physical_calls);
    try std.testing.expectEqual(cohort.maximum_physical_calls, cohort.cases.len * 2 * cohort.repeats);
    try std.testing.expectEqual(cohort.maximum_physical_calls, cohort.trials.len);
    try std.testing.expectEqualStrings("aws-bedrock", cohort.model.provider);
    try std.testing.expectEqualStrings("openai.gpt-oss-20b-1:0", cohort.model.model);
    try std.testing.expectEqualStrings("low", cohort.model.reasoning_effort);
    try std.testing.expectEqual(@as(u32, 0), cohort.model.temperature);
    const scorecard = try contracts.decode(std.json.Value, a, try read(a, "scorecard.template.json"));
    try hash(scorecard.object.get("comparison_sha256").?.string, manifest_bytes);
    const trials = scorecard.object.get("trials").?.array.items;
    try std.testing.expectEqual(cohort.trials.len, trials.len);
    for (cohort.trials, 0..) |trial, index| {
        for (cohort.trials[0..index]) |prior| {
            try std.testing.expect(!std.mem.eql(u8, prior.id, trial.id));
            try std.testing.expect(!(std.mem.eql(u8, prior.case, trial.case) and prior.arm == trial.arm and prior.repeat == trial.repeat));
        }
        try std.testing.expectEqualStrings(trial.id, trials[index].object.get("id").?.string);
        try std.testing.expectEqualStrings("not_run", trials[index].object.get("completion").?.string);
        try std.testing.expectEqualStrings("not_assessed", trials[index].object.get("native_signal_admission").?.string);
    }
    for (cohort.cases) |entry| {
        const baseline = try body(a, try contracts.decode(debug.Edit, a, try read(a, entry.baseline_edit)));
        const candidate = try body(a, try contracts.decode(debug.Edit, a, try read(a, entry.candidate_edit)));
        try std.testing.expectEqual(baseline.object.count(), candidate.object.count());
        for (baseline.object.keys()) |key| {
            if (std.mem.eql(u8, key, "assignment")) continue;
            try same(a, baseline.object.get(key).?, candidate.object.get(key).?);
        }
        const old_assignment = baseline.object.get("assignment").?.object;
        const new_assignment = candidate.object.get("assignment").?.object;
        try std.testing.expectEqual(old_assignment.count(), new_assignment.count());
        for (old_assignment.keys()) |key| {
            if (std.mem.eql(u8, key, "constraints")) continue;
            try same(a, old_assignment.get(key).?, new_assignment.get(key).?);
        }
        try std.testing.expectEqual(entry.obligations.len, old_assignment.get("claim_ids").?.array.items.len);
        try std.testing.expectEqual(entry.literal_expectations.len, baseline.object.get("preserved_tokens").?.array.items.len);
        const accepted = baseline.object.get("accepted").?.object.get("signals").?.array.items;
        try std.testing.expectEqual(entry.accepted_member_sets.len, accepted.len);
        for (entry.accepted_member_sets, accepted) |ids, signal| {
            const bytes = try std.json.Stringify.valueAlloc(a, ids, .{});
            try same(a, try contracts.decode(std.json.Value, a, bytes), signal.object.get("claim_ids").?);
        }
        inline for (.{ .baseline, .candidate }) |arm| {
            const name = @field(entry, @tagName(arm) ++ "_edit");
            const bytes = try read(a, name);
            try hash(@field(entry, @tagName(arm) ++ "_edit_sha256"), bytes);
            const edit = try contracts.decode(debug.Edit, a, bytes);
            try hash(@field(entry, @tagName(arm) ++ "_schema_sha256"), edit.schema);
            var repeats: u32 = 0;
            for (cohort.trials) |trial| if (std.mem.eql(u8, trial.case, entry.id) and trial.arm == arm) {
                try std.testing.expectEqualStrings(name, trial.edit);
                repeats += 1;
                try std.testing.expect(trial.repeat >= 1 and trial.repeat <= cohort.repeats);
            };
            try std.testing.expectEqual(cohort.repeats, repeats);
            for ([_][]const u8{ "\"obligations\"", "\"literal_expectations\"", "\"label_status\"", "\"accepted_member_sets\"" }) |key| try std.testing.expect(std.mem.indexOf(u8, edit.content[1].user, key) == null);
        }
    }
}

test "signal comparison candidate reuses production guidance and semantic selection schema projection" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cohort = try contracts.decode(Cohort, a, try read(a, "comparison.json"));
    var compiler: @import("../../../src/adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const canonical = (try compiler.compiler().compile(a, try files.read(std.testing.io, a, .cwd(), "design/workflows/spec/reconciliation.schema.json"))).select(.{ .bytes = "signals_assignment" }).?;
    const prompt = try files.read(std.testing.io, a, .cwd(), "design/workflows/spec/reconciliation-signals.prompt.md");
    for (cohort.cases) |entry| {
        const edit = try contracts.decode(debug.Edit, a, try read(a, entry.candidate_edit));
        try std.testing.expectEqualStrings(prompt, edit.content[0].guidance);
        const candidate = try body(a, edit);
        const assignment = candidate.object.get("assignment").?.object;
        const given = assignment.get("constraints").?.array.items;
        var count: usize = 0;
        const scope: r.diagnostic.Constraint.Scope = .{ .assignment = .signals };
        for (std.enums.values(r.diagnostic.Constraint)) |constraint| if (constraint.appliesTo(.global, scope)) {
            try std.testing.expect(count < given.len);
            try std.testing.expectEqualStrings(@tagName(constraint), given[count].object.get("constraint").?.string);
            try std.testing.expectEqualStrings(constraint.descriptionFor(scope), given[count].object.get("requirement").?.string);
            count += 1;
        };
        try std.testing.expectEqual(count, given.len);
        const ids = try codec.decode([]const r.ClaimId, a, try std.json.Stringify.valueAlloc(a, assignment.get("claim_ids").?, .{}));
        const claims = try codec.decode([]const @import("../../../src/domain/model_evidence.zig").Claim, a, try std.json.Stringify.valueAlloc(a, candidate.object.get("claims").?, .{}));
        // These fixture assignments select the leading semantic claims. The
        // exact token catalogue stays in the body, outside selection authority.
        const items = try a.alloc(r.Item, ids.len);
        for (ids, items, 0..) |id, *item, index| {
            try std.testing.expectEqual(index + 1, id.ordinal);
            const claim = claims[index];
            try std.testing.expectEqual(id.ordinal, claim.id.ordinal);
            try std.testing.expect(claim.content == .model);
            const content: r.extraction.Content = switch (claim.content.model) {
                inline else => |text, kind| @unionInit(r.extraction.Content, @tagName(kind), .{ .value = text }),
            };
            item.* = .{ .claim = .{ .id = id, .chunk_id = .{ .bytes = "MOCK-diagnostic-chunk" }, .content = .{ .model = content }, .citation_ids = claim.citation_ids }, .source_id = .{ .ordinal = 1 }, .block_id = .{ .ordinal = 1 }, .citations = &.{} };
        }
        const base = try packets.create(a, edit.content[1].user, .{ .reference_global = .{ .reference_state_id = .{ .bytes = "MOCK-diagnostic-state" }, .unit_slot_id = .{ .bytes = "MOCK-signals" } } }, .initial_generation, .{ .bytes = "signals_assignment" });
        defer packets.release(base);
        const text_scoped = try model_input.withTextChoices(a, base, &.{}, &.{});
        defer packets.release(text_scoped);
        const packet = try model_input.withSemanticChoices(a, text_scoped, .{ .state_id = .{ .bytes = "MOCK-diagnostic-state" }, .entries = items }, ids, .signals);
        defer packets.release(packet);
        const selected = try schemas.restrict(a, canonical, packet.excludedVariants(), packet.integerChoices());
        defer selected.release();
        try std.testing.expectEqualStrings(selected.selected().modelBytes(), edit.schema);
    }
}
