//! Frozen request edits and proposed labels, never semantic-success evidence.
const std = @import("std");
const files = @import("../files.zig");
const contracts = @import("../contracts.zig");
const debug = @import("../../../src/domain/request_debugger.zig");
const packets = @import("../../../src/domain/model_input_packet.zig");
const schemas = @import("../../../src/domain/model_result_schema.zig");
const root = "test/calibration/entity-applicability/";
const Phase = enum { authoring, review };
const Case = struct {
    id: []const u8,
    phase: Phase,
    origin: enum { captured, controlled },
    exact_claim_ids: []const i64,
    source_sha256: []const u8,
    expectation: struct {
        decision: enum { required, not_applicable, clarification },
        basis: []const u8,
        review_finding: ?enum { supported, candidate_omission },
        review_defect: ?enum { none, basis, decision },
    },
    schema_sha256: []const u8,
    baseline_edit: []const u8,
    baseline_edit_sha256: []const u8,
    candidate_edit: []const u8,
    candidate_edit_sha256: []const u8,
};
const Cohort = struct {
    schema: enum { @"entity-applicability-comparison/v1" },
    label_status: enum { proposed, reviewed },
    baseline_revision: []const u8,
    capture_build_identity: struct { revision: []const u8, source_sha256: []const u8, modified: bool },
    capture: struct {
        feature: []const u8,
        run: []const u8,
        authoring: struct { call: []const u8, context_sha256: []const u8 },
        review: struct { call: []const u8, context_sha256: []const u8 },
    },
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
fn same(a: std.mem.Allocator, left: std.json.Value, right: std.json.Value) !void {
    try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, left, .{}), try std.json.Stringify.valueAlloc(a, right, .{}));
}
fn purpose(body: std.json.Value, phase: Phase) []const u8 {
    return switch (phase) {
        .authoring => body.object.get("source_assignment").?.object.get("purpose").?.string,
        .review => body.object.get("requirements").?.array.items[0].object.get("task").?.string,
    };
}
fn withoutPurpose(body: *std.json.Value, phase: Phase) void {
    switch (phase) {
        .authoring => _ = body.object.getPtr("source_assignment").?.object.swapRemove("purpose"),
        .review => _ = body.object.getPtr("requirements").?.array.items[0].object.swapRemove("task"),
    }
}

test "entity comparison freezes source facts schemas labels and repeats while changing only shared guidance" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const manifest = try read(a, "comparison.json");
    const cohort = try contracts.decode(Cohort, a, manifest);
    try std.testing.expectEqual(@as(usize, 8), cohort.cases.len);
    try std.testing.expectEqual(@as(u32, 2), cohort.repeats);
    try std.testing.expectEqual(@as(u32, 32), cohort.maximum_physical_calls);
    try std.testing.expectEqual(cohort.maximum_physical_calls, cohort.cases.len * 2 * cohort.repeats);
    try std.testing.expectEqual(cohort.maximum_physical_calls, cohort.trials.len);
    try std.testing.expectEqualStrings("aws-bedrock", cohort.model.provider);
    try std.testing.expectEqualStrings("openai.gpt-oss-20b-1:0", cohort.model.model);
    try std.testing.expectEqualStrings("ap-southeast-2", cohort.model.region);
    try std.testing.expectEqualStrings("low", cohort.model.reasoning_effort);
    try std.testing.expectEqual(@as(u32, 0), cohort.model.temperature);
    const scorecard = try contracts.decode(std.json.Value, a, try read(a, "scorecard.template.json"));
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
    // These hashed historical requests retain their guidance after production changes.
    const frozen = try contracts.decode(debug.Edit, a, try read(a, cohort.cases[0].candidate_edit));
    const frozen_body = try contracts.decode(std.json.Value, a, frozen.content[2].user);
    const task = purpose(frozen_body, .authoring);
    for (cohort.cases) |entry| {
        const before = try contracts.decode(debug.Edit, a, try read(a, entry.baseline_edit));
        const after = try contracts.decode(debug.Edit, a, try read(a, entry.candidate_edit));
        const length: usize = if (entry.phase == .authoring) 3 else 2;
        try std.testing.expectEqual(length, before.content.len);
        try std.testing.expectEqual(length, after.content.len);
        var old_body = try contracts.decode(std.json.Value, a, before.content[length - 1].user);
        var new_body = try contracts.decode(std.json.Value, a, after.content[length - 1].user);
        try std.testing.expectEqualStrings(task, purpose(new_body, entry.phase));
        try std.testing.expect(!std.mem.eql(u8, purpose(old_body, entry.phase), purpose(new_body, entry.phase)));
        try hash(entry.source_sha256, old_body.object.get("sources").?.array.items[0].object.get("text").?.string);
        withoutPurpose(&old_body, entry.phase);
        withoutPurpose(&new_body, entry.phase);
        try same(a, old_body, new_body);
        if (entry.phase == .authoring) {
            try std.testing.expectEqualStrings(frozen.content[0].guidance, after.content[0].guidance);
            try std.testing.expectEqualStrings(frozen.content[1].guidance, after.content[1].guidance);
        } else {
            try std.testing.expectEqualStrings(before.content[0].guidance, after.content[0].guidance);
            const subject = try @import("../../../src/domain/model_candidate_json.zig").decode(@import("../../../src/domain/specification_review_subject.zig").Subject, a, try std.json.Stringify.valueAlloc(a, new_body.object.get("subject").?, .{}));
            try std.testing.expectEqual(.entity_applicability, std.meta.activeTag(subject));
            try @import("../../../src/domain/specification.zig").validateDocument(subject.entity_applicability.context.candidate, true);
        }
        inline for (.{ .baseline, .candidate }) |arm| {
            const name = @field(entry, @tagName(arm) ++ "_edit");
            const bytes = try read(a, name);
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
            for ([_][]const u8{ "\"expectation\"", "\"review_defect\"", "\"label_status\"", "\"decision_accuracy\"" }) |key| try std.testing.expect(std.mem.indexOf(u8, edit.content[length - 1].user, key) == null);
        }
    }
}

test "entity comparison preserves authoring admission and records superseded review evidence requirements" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cohort = try contracts.decode(Cohort, a, try read(a, "comparison.json"));
    var compiler: @import("../../../src/adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const authoring = (try compiler.compiler().compile(a, try files.read(std.testing.io, a, .cwd(), "design/workflows/spec/generation.schema.json"))).select(.{ .bytes = "entities" }).?;
    const review = (try compiler.compiler().compile(a, try files.read(std.testing.io, a, .cwd(), "design/workflows/spec/support.schema.json"))).select(.{ .bytes = "finding" }).?;
    for (cohort.cases) |entry| {
        const edit = try contracts.decode(debug.Edit, a, try read(a, entry.candidate_edit));
        const restricted = if (entry.phase == .authoring) block: {
            const base = try packets.create(a, edit.content[2].user, .{ .reference_global = .{ .reference_state_id = .{ .bytes = "diagnostic" }, .unit_slot_id = .{ .bytes = "entities" } } }, .initial_generation, .{ .bytes = "entities" });
            defer packets.release(base);
            const choices = try @import("../../../src/domain/reference_model_input.zig").withTextChoices(a, base, &.{}, entry.exact_claim_ids);
            defer packets.release(choices);
            break :block try schemas.restrict(a, authoring, choices.excludedVariants(), choices.integerChoices());
        } else try schemas.restrict(a, review, &.{}, &.{.{ .target = .{ .path = &.{.{ .property = "source_ids" }} }, .allowed = &.{1} }});
        defer restricted.release();
        if (entry.phase == .review) {
            // The frozen, unexecuted comparison predates the source-premise
            // contract. Preserve its hashes, but do not present it as a current
            // production comparison or silently update one arm.
            const missing_source = "{\"kind\":\"candidate_omission\",\"source_ids\":[],\"detail\":\"MOCK Missing meaning.\"}";
            try @import("../../../src/model_payload_schema_test.zig").checkDocument(edit.schema, .{ .bytes = missing_source });
            try @import("../../../src/model_payload_schema_test.zig").checkDocument(restricted.selected().modelBytes(), .{ .bytes = missing_source, .rejection = .array_length, .path = "/source_ids" });
            continue;
        }
        try std.testing.expectEqualStrings(restricted.selected().modelBytes(), edit.schema);
        const literal = "{\"kind\":\"entities\",\"disposition\":\"not_applicable\",\"basis\":{\"value\":[{\"kind\":\"exact_copy\"}]}}";
        try @import("../../../src/model_payload_schema_test.zig").checkDocument(edit.schema, .{ .bytes = literal, .rejection = if (entry.exact_claim_ids.len == 0) .type_mismatch else null });
        const unknown = "{\"kind\":\"entities\",\"disposition\":\"not_applicable\",\"basis\":{\"value\":[\"MOCK explanation\"]},\"extra\":true}";
        try @import("../../../src/model_payload_schema_test.zig").checkDocument(edit.schema, .{ .bytes = unknown, .rejection = .unknown_property });
        // Literal-only admission is a schema fact; explanation adequacy stays
        // a separate human/model assessment, not a surface-form validator.
    }
}
