//! Immutable paired diagnostic inputs. These tests neither dispatch nor judge meaning.
const std = @import("std");
const files = @import("../files.zig");
const contracts = @import("../contracts.zig");
const debug = @import("../../../src/domain/request_debugger.zig");
const packets = @import("../../../src/domain/model_input_packet.zig");
const schemas = @import("../../../src/domain/model_result_schema.zig");
const directory = "test/calibration/authoring-guidance/";
const example_directory = directory ++ "composition-example/";
const Case = struct {
    id: []const u8,
    contrast: enum { fragments, record_purposes, composition_example },
    parent: enum { story, records },
    origin: enum { captured, controlled },
    exact_claim_ids: []const i64,
    sources: []const struct { id: u32, sha256: []const u8 },
    obligations: []const struct { id: []const u8, meaning: []const u8 },
    literal_expectations: []const struct { claim_id: i64, source_id: u32, value: []const u8, meaning: []const u8 },
    assessment_notes: []const u8,
    schema_sha256: []const u8,
    baseline_edit: []const u8,
    baseline_edit_sha256: []const u8,
    candidate_edit: []const u8,
    candidate_edit_sha256: []const u8,
};
const Capture = struct { call: []const u8, context_sha256: []const u8 };
const Cohort = struct {
    schema: enum { @"authoring-guidance-comparison/v1" },
    label_status: enum { proposed, reviewed },
    baseline_revision: []const u8,
    capture_build_identity: struct { revision: []const u8, source_sha256: []const u8, modified: bool },
    capture: struct { feature: []const u8, run: []const u8, story: Capture, records: Capture },
    model: struct { provider: []const u8, model: []const u8, region: []const u8, reasoning_effort: []const u8, temperature: u32, response_mode: enum { native_schema } },
    repeats: u32,
    maximum_physical_calls: u32,
    cases: []const Case,
    trials: []const struct { id: []const u8, case: []const u8, arm: enum { baseline, candidate }, repeat: u32, edit: []const u8 },
};
fn read(a: std.mem.Allocator, root: []const u8, name: []const u8) ![]const u8 {
    return files.read(std.testing.io, a, .cwd(), try std.mem.concat(a, u8, &.{ root, name }));
}
fn hash(expected: []const u8, bytes: []const u8) !void {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    try std.testing.expectEqualStrings(expected, &std.fmt.bytesToHex(digest, .lower));
}
fn same(a: std.mem.Allocator, left: std.json.Value, right: std.json.Value) !void {
    try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, left, .{}), try std.json.Stringify.valueAlloc(a, right, .{}));
}

test "authoring guidance comparisons isolate fragment and purpose factors with frozen evidence and repeated inputs" {
    try checkComparison(directory, 7, 28);
    try checkComparison(example_directory, 4, 16);
}

fn checkComparison(root: []const u8, case_count: usize, call_count: u32) !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const manifest = try read(a, root, "comparison.json");
    const cohort = try contracts.decode(Cohort, a, manifest);
    try std.testing.expectEqual(case_count, cohort.cases.len);
    try std.testing.expectEqual(@as(u32, 2), cohort.repeats);
    try std.testing.expectEqual(call_count, cohort.maximum_physical_calls);
    try std.testing.expectEqual(cohort.maximum_physical_calls, cohort.cases.len * 2 * cohort.repeats);
    try std.testing.expectEqual(cohort.maximum_physical_calls, cohort.trials.len);
    try std.testing.expectEqualStrings("aws-bedrock", cohort.model.provider);
    try std.testing.expectEqualStrings("openai.gpt-oss-20b-1:0", cohort.model.model);
    try std.testing.expectEqualStrings("ap-southeast-2", cohort.model.region);
    try std.testing.expectEqualStrings("low", cohort.model.reasoning_effort);
    try std.testing.expectEqual(@as(u32, 0), cohort.model.temperature);
    const scorecard = try contracts.decode(std.json.Value, a, try read(a, root, "scorecard.template.json"));
    try hash(scorecard.object.get("comparison_sha256").?.string, manifest);
    const scored_trials = scorecard.object.get("trials").?.array.items;
    try std.testing.expectEqual(cohort.trials.len, scored_trials.len);
    for (cohort.trials, 0..) |trial, index| {
        for (cohort.trials[0..index]) |prior| {
            try std.testing.expect(!std.mem.eql(u8, prior.id, trial.id));
            try std.testing.expect(!(std.mem.eql(u8, prior.case, trial.case) and prior.arm == trial.arm and prior.repeat == trial.repeat));
        }
        try std.testing.expectEqualStrings(trial.id, scored_trials[index].object.get("id").?.string);
        try std.testing.expectEqualStrings("not_run", scored_trials[index].object.get("transport").?.string);
        try std.testing.expectEqualStrings("not_assessed", scored_trials[index].object.get("native_admission").?.string);
    }
    for (cohort.cases) |entry| {
        const before = try contracts.decode(debug.Edit, a, try read(a, root, entry.baseline_edit));
        const after = try contracts.decode(debug.Edit, a, try read(a, root, entry.candidate_edit));
        try std.testing.expectEqual(@as(usize, 3), before.content.len);
        try std.testing.expectEqual(@as(usize, 3), after.content.len);
        var old_body = try contracts.decode(std.json.Value, a, before.content[2].user);
        var new_body = try contracts.decode(std.json.Value, a, after.content[2].user);
        const sources = old_body.object.get("sources").?.array.items;
        try std.testing.expectEqual(entry.sources.len, sources.len);
        for (entry.sources, sources) |expected, source| {
            try std.testing.expectEqual(expected.id, source.object.get("id").?.integer);
            try hash(expected.sha256, source.object.get("text").?.string);
        }
        const literals = old_body.object.get("preserved_tokens").?.array.items;
        try std.testing.expectEqual(entry.exact_claim_ids.len, literals.len);
        try std.testing.expectEqual(entry.literal_expectations.len, literals.len);
        for (entry.exact_claim_ids, entry.literal_expectations, literals) |id, expected, literal| {
            try std.testing.expectEqual(id, expected.claim_id);
            try std.testing.expectEqual(id, literal.object.get("claim_id").?.integer);
            try std.testing.expectEqual(expected.source_id, literal.object.get("source_id").?.integer);
            try std.testing.expectEqualStrings(expected.value, literal.object.get("value").?.string);
        }
        switch (entry.contrast) {
            .composition_example => {
                try std.testing.expectEqual(.story, entry.parent);
                try std.testing.expectEqualStrings(before.content[0].guidance, after.content[0].guidance);
                try std.testing.expectEqualStrings(before.content[1].guidance, after.content[1].guidance);
                try std.testing.expect(!old_body.object.contains("composition_example"));
                if (entry.exact_claim_ids.len == 0) {
                    try std.testing.expectEqualStrings(before.content[2].user, after.content[2].user);
                } else {
                    try std.testing.expect(new_body.object.swapRemove("composition_example"));
                }
            },
            .fragments => {
                try std.testing.expectEqualStrings(before.content[1].guidance, after.content[1].guidance);
                var old_guidance = try contracts.decode(std.json.Value, a, before.content[0].guidance);
                var new_guidance = try contracts.decode(std.json.Value, a, after.content[0].guidance);
                try std.testing.expect(!std.mem.eql(u8, old_guidance.object.get("exact_copy").?.string, new_guidance.object.get("exact_copy").?.string));
                try std.testing.expect(old_guidance.object.swapRemove("exact_copy"));
                try std.testing.expect(new_guidance.object.swapRemove("exact_copy"));
                try same(a, old_guidance, new_guidance);
            },
            .record_purposes => {
                try std.testing.expectEqual(.records, entry.parent);
                try std.testing.expectEqualStrings(before.content[0].guidance, after.content[0].guidance);
                try std.testing.expect(!std.mem.eql(u8, before.content[1].guidance, after.content[1].guidance));
                const old_purpose = old_body.object.get("source_assignment").?.object.get("purpose").?.string;
                const new_purpose = new_body.object.get("source_assignment").?.object.get("purpose").?.string;
                const old_end = std.mem.indexOfScalar(u8, old_purpose, '\n').?;
                const new_end = std.mem.indexOfScalar(u8, new_purpose, '\n').?;
                // Only the acceptance-criterion purpose changes; sibling family
                // descriptions, including edge-case outcome guidance, stay frozen.
                try std.testing.expect(!std.mem.eql(u8, old_purpose[0..old_end], new_purpose[0..new_end]));
                try std.testing.expectEqualStrings(old_purpose[old_end..], new_purpose[new_end..]);
                try std.testing.expect(old_body.object.getPtr("source_assignment").?.object.swapRemove("purpose"));
                try std.testing.expect(new_body.object.getPtr("source_assignment").?.object.swapRemove("purpose"));
            },
        }
        try same(a, old_body, new_body);
        inline for (.{ .baseline, .candidate }) |arm| {
            const name = @field(entry, @tagName(arm) ++ "_edit");
            const bytes = try read(a, root, name);
            try hash(@field(entry, @tagName(arm) ++ "_edit_sha256"), bytes);
            const edit = try contracts.decode(debug.Edit, a, bytes);
            try hash(entry.schema_sha256, edit.schema);
            try std.testing.expectEqualStrings(before.schema, edit.schema);
            var repeats: u32 = 0;
            for (cohort.trials) |trial| if (std.mem.eql(u8, trial.case, entry.id) and trial.arm == arm) {
                try std.testing.expectEqualStrings(name, trial.edit);
                try std.testing.expect(trial.repeat >= 1 and trial.repeat <= cohort.repeats);
                repeats += 1;
            };
            try std.testing.expectEqual(cohort.repeats, repeats);
            for ([_][]const u8{ "\"obligations\"", "\"literal_expectations\"", "\"assessment_notes\"", "\"label_status\"" }) |key| try std.testing.expect(std.mem.indexOf(u8, edit.content[2].user, key) == null);
        }
    }
}

test "authoring guidance schemas preserve native zero singleton and duplicate-valued multiple reference choices" {
    try checkSchemas(directory);
    try checkSchemas(example_directory);
}

fn checkSchemas(root: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cohort = try contracts.decode(Cohort, a, try read(a, root, "comparison.json"));
    var compiler: @import("../../../src/adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = try compiler.compiler().compile(a, try files.read(std.testing.io, a, .cwd(), "design/workflows/spec/generation.schema.json"));
    for (cohort.cases) |entry| {
        const edit = try contracts.decode(debug.Edit, a, try read(a, root, entry.candidate_edit));
        const kind = if (entry.parent == .story) "primary_user_story" else "records";
        const selected = schema.select(.{ .bytes = kind }).?;
        const base = try packets.create(a, edit.content[2].user, .{ .reference_global = .{ .reference_state_id = .{ .bytes = "diagnostic" }, .unit_slot_id = .{ .bytes = kind } } }, .initial_generation, .{ .bytes = kind });
        defer packets.release(base);
        const families = try packets.withExcludedVariants(a, base, if (entry.parent == .records) &.{.{ .kind = "entity" }} else &.{});
        defer packets.release(families);
        const choices = try @import("../../../src/domain/reference_model_input.zig").withTextChoices(a, families, &.{}, entry.exact_claim_ids);
        defer packets.release(choices);
        const restricted = try schemas.restrict(a, selected, choices.excludedVariants(), choices.integerChoices());
        defer restricted.release();
        try std.testing.expectEqualStrings(restricted.selected().modelBytes(), edit.schema);
        if (entry.contrast == .composition_example) try checkExample(a, edit, choices);
        if (entry.parent != .records or entry.exact_claim_ids.len == 0) continue;
        const reference = if (entry.exact_claim_ids.len == 1) "{\"kind\":\"exact_copy\"}" else "{\"kind\":\"exact_copy\",\"claim_id\":4}";
        const example = try std.fmt.allocPrint(a, "{{\"kind\":\"records\",\"records\":[{{\"content\":{{\"kind\":\"acceptance_criterion\",\"given\":[\"MOCK context\"],\"when\":[\"MOCK trigger\"],\"then\":[{s}]}}}}]}}", .{reference});
        try @import("../../../src/model_payload_schema_test.zig").checkDocument(edit.schema, .{ .bytes = example });
        // A reference-only result stays admissible; the actual field purpose,
        // occurrence identity and collection coverage require separate assessment.
    }
}

fn checkExample(a: std.mem.Allocator, edit: debug.Edit, choices: *const packets.Packet) !void {
    const body = try contracts.decode(std.json.Value, a, edit.content[2].user);
    const example = body.object.get("composition_example") orelse return;
    const codec = @import("../../../src/domain/model_candidate_json.zig");
    const Example = struct { instruction: []const u8, value: @import("../../../src/domain/specification.zig").BusinessValue, rendered_text: []const u8 };
    const restored = try codec.constructBound(a, try std.json.Stringify.valueAlloc(a, example, .{}), choices.integerChoices());
    const illustration = try codec.decode(Example, a, restored);
    try std.testing.expect(illustration.instruction.len != 0);
    const wire = try std.json.Stringify.valueAlloc(a, .{ .kind = "primary_user_story", .value = example.object.get("value").? }, .{});
    try @import("../../../src/model_payload_schema_test.zig").checkDocument(edit.schema, .{ .bytes = wire });
    const segments = illustration.value.segments;
    // The diagnostic illustration has three fragments; this adds no such
    // restriction to the shared value schema or any actual authored response.
    try std.testing.expectEqual(@as(usize, 3), segments.len);
    const id = segments[1].exact_copy.claim_id.ordinal;
    const catalogue = body.object.get("preserved_tokens").?.array.items;
    var selected: ?[]const u8 = null;
    for (catalogue) |literal| if (literal.object.get("claim_id").?.integer == id) {
        try std.testing.expect(selected == null);
        selected = literal.object.get("value").?.string;
    };
    try std.testing.expect(selected != null);
    try std.testing.expectEqualStrings(illustration.rendered_text, try std.fmt.allocPrint(a, "{s}{s}{s}", .{ segments[0].literal.value, selected.?, segments[2].literal.value }));
}
