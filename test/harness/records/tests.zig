//! Frozen diagnostic premises. No live dispatch or semantic-success oracle.
const std = @import("std");
const files = @import("../files.zig");
const codec = @import("../../../src/domain/model_candidate_json.zig");
const packets = @import("../../../src/domain/model_input_packet.zig");
const schemas = @import("../../../src/domain/model_result_schema.zig");
const debug = @import("../../../src/domain/request_debugger.zig");
const root = "test/calibration/record-authoring/";

const Case = struct {
    id: []const u8,
    origin: enum { captured, controlled },
    family: []const u8,
    exact_claim_ids: []const i64,
    source_sha256: []const u8,
    obligations: []const struct { id: []const u8, meaning: []const u8 },
    literal_expectations: []const struct { claim_id: i64, value: []const u8, meaning: []const u8 },
    schema_sha256: []const u8,
    baseline_edit: []const u8,
    baseline_edit_sha256: []const u8,
    candidate_edit: []const u8,
    candidate_edit_sha256: []const u8,
};
const Cohort = struct {
    schema: enum { @"record-authoring-comparison/v1" },
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
    return files.read(std.testing.io, a, .cwd(), try std.mem.concat(a, u8, &.{ root, name }));
}
fn hash(expected: []const u8, bytes: []const u8) !void {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    try std.testing.expectEqualStrings(expected, &std.fmt.bytesToHex(digest, .lower));
}
fn equalJson(a: std.mem.Allocator, left: std.json.Value, right: std.json.Value) !void {
    try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, left, .{}), try std.json.Stringify.valueAlloc(a, right, .{}));
}

test "record comparison freezes paired facts guidance schema and unchanged repeat inputs without judging meaning" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cohort = try @import("../contracts.zig").decode(Cohort, a, try read(a, "comparison.json"));
    try std.testing.expectEqual(@as(usize, 3), cohort.cases.len);
    try std.testing.expectEqual(@as(u32, 12), cohort.maximum_physical_calls);
    try std.testing.expectEqual(cohort.maximum_physical_calls, cohort.cases.len * 2 * cohort.repeats);
    try std.testing.expectEqual(cohort.maximum_physical_calls, cohort.trials.len);
    for (cohort.trials, 0..) |trial, index| {
        for (cohort.trials[0..index]) |prior| {
            try std.testing.expect(!std.mem.eql(u8, prior.id, trial.id));
            try std.testing.expect(!(std.mem.eql(u8, prior.case, trial.case) and prior.arm == trial.arm and prior.repeat == trial.repeat));
        }
    }
    try std.testing.expectEqualStrings("aws-bedrock", cohort.model.provider);
    try std.testing.expectEqualStrings("openai.gpt-oss-20b-1:0", cohort.model.model);
    try std.testing.expectEqualStrings("low", cohort.model.reasoning_effort);
    try std.testing.expectEqual(@as(u32, 0), cohort.model.temperature);
    for (cohort.cases) |entry| {
        const baseline_edit = try @import("../contracts.zig").decode(debug.Edit, a, try read(a, entry.baseline_edit));
        const candidate_edit = try @import("../contracts.zig").decode(debug.Edit, a, try read(a, entry.candidate_edit));
        try std.testing.expectEqual(@as(usize, 3), baseline_edit.content.len);
        try std.testing.expectEqual(@as(usize, 3), candidate_edit.content.len);
        const baseline = try @import("../contracts.zig").decode(std.json.Value, a, baseline_edit.content[2].user);
        const candidate = try @import("../contracts.zig").decode(std.json.Value, a, candidate_edit.content[2].user);
        try std.testing.expectEqual(baseline.object.count(), candidate.object.count());
        for (baseline.object.keys()) |key| {
            if (std.mem.eql(u8, key, "brief") or std.mem.eql(u8, key, "entities") or std.mem.eql(u8, key, "source_assignment")) continue;
            try equalJson(a, baseline.object.get(key).?, candidate.object.get(key).?);
        }
        const old_assignment = baseline.object.get("source_assignment").?.object;
        const new_assignment = candidate.object.get("source_assignment").?.object;
        for (old_assignment.keys()) |key| {
            if (std.mem.eql(u8, key, "purpose")) continue;
            try equalJson(a, old_assignment.get(key).?, new_assignment.get(key).?);
        }
        // These immutable diagnostic premises deliberately have literal-only
        // dependent drafts; production tests cover exact/passive resolution.
        const brief = baseline.object.get("brief").?.object;
        for (brief.keys()) |field| try expectLiteralProjection(a, brief.get(field).?, candidate.object.get("brief").?.object.get(field).?);
        const entities = baseline.object.get("entities").?.object;
        try equalJson(a, entities.get("disposition").?, candidate.object.get("entities").?.object.get("disposition").?);
        try expectLiteralProjection(a, entities.get("basis").?, candidate.object.get("entities").?.object.get("basis").?);
        try hash(entry.source_sha256, baseline.object.get("sources").?.array.items[0].object.get("text").?.string);
        try std.testing.expect(entry.obligations.len != 0);
        try std.testing.expectEqual(entry.exact_claim_ids.len, entry.literal_expectations.len);
        inline for (.{ .baseline, .candidate }) |arm| {
            const name = @field(entry, @tagName(arm) ++ "_edit");
            const bytes = try read(a, name);
            try hash(@field(entry, @tagName(arm) ++ "_edit_sha256"), bytes);
            const edit = try @import("../contracts.zig").decode(debug.Edit, a, bytes);
            // Historical arms retain their hashed guidance when production
            // guidance changes; this comparison varies only the packet projection.
            try std.testing.expectEqualStrings(baseline_edit.content[0].guidance, edit.content[0].guidance);
            try std.testing.expectEqualStrings(baseline_edit.content[1].guidance, edit.content[1].guidance);
            try hash(entry.schema_sha256, edit.schema);
            try std.testing.expectEqualStrings(baseline_edit.schema, edit.schema);
            var repeats: u32 = 0;
            for (cohort.trials) |trial| if (std.mem.eql(u8, trial.case, entry.id) and trial.arm == arm) {
                try std.testing.expectEqualStrings(name, trial.edit);
                repeats += 1;
                try std.testing.expect(trial.repeat >= 1 and trial.repeat <= cohort.repeats);
            };
            try std.testing.expectEqual(cohort.repeats, repeats);
            for ([_][]const u8{ "\"obligations\"", "\"literal_expectations\"", "\"label_status\"" }) |key| try std.testing.expect(std.mem.indexOf(u8, edit.content[2].user, key) == null);
        }
    }
}

fn expectLiteralProjection(a: std.mem.Allocator, before: std.json.Value, after: std.json.Value) !void {
    const fragments = before.object.get("value").?.array.items;
    var strings: std.ArrayList([]const u8) = .empty;
    for (fragments) |fragment| {
        try std.testing.expect(fragment == .string);
        try strings.append(a, fragment.string);
    }
    try std.testing.expectEqualStrings(try std.mem.concat(a, u8, strings.items), after.string);
}

test "record comparison schemas derive from production zero singleton and multiple exact choices" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cohort = try @import("../contracts.zig").decode(Cohort, a, try read(a, "comparison.json"));
    var compiler: @import("../../../src/adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const canonical = (try compiler.compiler().compile(a, try files.read(std.testing.io, a, .cwd(), "design/workflows/spec/generation.schema.json"))).select(.{ .bytes = "records" }).?;
    for (cohort.cases) |entry| {
        const edit = try @import("../contracts.zig").decode(debug.Edit, a, try read(a, entry.candidate_edit));
        const body = edit.content[2].user;
        const base = try packets.create(a, body, .{ .reference_global = .{ .reference_state_id = .{ .bytes = "diagnostic" }, .unit_slot_id = .{ .bytes = "records" } } }, .initial_generation, .{ .bytes = "records" });
        defer packets.release(base);
        const excluded = try packets.withExcludedVariants(a, base, &.{.{ .kind = "entity" }});
        defer packets.release(excluded);
        const packet = try @import("../../../src/domain/reference_model_input.zig").withTextChoices(a, excluded, &.{}, entry.exact_claim_ids);
        defer packets.release(packet);
        const restricted = try schemas.restrict(a, canonical, packet.excludedVariants(), packet.integerChoices());
        defer restricted.release();
        try std.testing.expectEqualStrings(restricted.selected().modelBytes(), edit.schema);
        var kinds: std.ArrayList(@import("../../../src/domain/specification.zig").Kind) = .empty;
        families: for (std.meta.tags(@import("../../../src/domain/specification.zig").Kind)) |kind| {
            for (packet.excludedVariants()) |variant| if (std.mem.eql(u8, variant.kind, @tagName(kind))) continue :families;
            try kinds.append(a, kind);
        }
        const candidate = try @import("../contracts.zig").decode(std.json.Value, a, body);
        const baseline_edit = try @import("../contracts.zig").decode(debug.Edit, a, try read(a, entry.baseline_edit));
        const baseline = try @import("../contracts.zig").decode(std.json.Value, a, baseline_edit.content[2].user);
        // Compare frozen family definitions, not mutable production wording.
        // The candidate removes only the excluded entity family.
        var old_lines = std.mem.splitScalar(u8, baseline.object.get("source_assignment").?.object.get("purpose").?.string, '\n');
        var new_lines = std.mem.splitScalar(u8, candidate.object.get("source_assignment").?.object.get("purpose").?.string, '\n');
        for (kinds.items) |kind| {
            const old_line = old_lines.next().?;
            try std.testing.expect(std.mem.startsWith(u8, old_line, try std.fmt.allocPrint(a, "{s}:", .{@tagName(kind)})));
            try std.testing.expectEqualStrings(old_line, new_lines.next().?);
        }
        try std.testing.expect(std.mem.startsWith(u8, old_lines.next().?, "entity:"));
        try std.testing.expect(old_lines.next() == null);
        try std.testing.expect(new_lines.next() == null);
        const prose = "{\"kind\":\"records\",\"records\":[{\"content\":{\"kind\":\"functional_requirement\",\"text\":[\"MOCK required behavior\"]}}]}";
        try @import("../../../src/model_payload_schema_test.zig").checkDocument(restricted.selected().modelBytes(), .{ .bytes = prose });
        const reference = "{\"kind\":\"records\",\"records\":[{\"content\":{\"kind\":\"functional_requirement\",\"text\":[{\"kind\":\"exact_copy\"}]}}]}";
        if (entry.exact_claim_ids.len == 1) {
            try @import("../../../src/model_payload_schema_test.zig").checkDocument(restricted.selected().modelBytes(), .{ .bytes = reference });
            const restored = try codec.constructBound(a, reference, packet.integerChoices());
            const parsed = try codec.decode(@import("../../../src/domain/specification_generation.zig").ModelResponse, a, restored);
            try std.testing.expectEqual(entry.exact_claim_ids[0], parsed.records.records[0].content.functional_requirement.text.segments[0].exact_copy.claim_id.ordinal);
        } else if (entry.exact_claim_ids.len == 0) {
            try @import("../../../src/model_payload_schema_test.zig").checkDocument(restricted.selected().modelBytes(), .{ .bytes = reference, .rejection = .type_mismatch });
        } else {
            const selected = "{\"kind\":\"records\",\"records\":[{\"content\":{\"kind\":\"functional_requirement\",\"text\":[\"MOCK show \",{\"kind\":\"exact_copy\",\"claim_id\":4}]}}]}";
            try @import("../../../src/model_payload_schema_test.zig").checkDocument(restricted.selected().modelBytes(), .{ .bytes = selected });
            try @import("../../../src/model_payload_schema_test.zig").checkDocument(restricted.selected().modelBytes(), .{ .bytes = reference, .rejection = .missing_required_property });
            const invalid = "{\"kind\":\"records\",\"records\":[{\"content\":{\"kind\":\"functional_requirement\",\"text\":[{\"kind\":\"exact_copy\",\"claim_id\":999}]}}]}";
            try @import("../../../src/model_payload_schema_test.zig").checkDocument(restricted.selected().modelBytes(), .{ .bytes = invalid, .rejection = .enum_mismatch });
        }
        // Fixtures assess schema mechanics only. No assertion calls the prose
        // or the reference-only answer a semantically adequate requirement.
    }
}
