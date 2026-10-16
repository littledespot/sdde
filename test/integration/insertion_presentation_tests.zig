const std = @import("std");
const p = @import("../harness/attribution/preparation.zig");
const s = @import("../harness/attribution/scoring.zig");
const strict = @import("../../src/domain/strict_json.zig");

test "test.integration.insertion_presentation prepares frozen 21 trial panel without dispatch" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bundle = try p.prepare(a);
    try std.testing.expectEqual(@as(usize, 7), bundle.manifest.arms.len);
    try std.testing.expectEqual(@as(usize, 21), bundle.manifest.trials.len);
    try std.testing.expect(!bundle.manifest.dispatch_authorized);
    for (bundle.manifest.arms) |arm| {
        const original = try p.description(a, arm.source);
        const edit = try p.edit(a, original, arm.arm);
        try std.testing.expectEqualStrings(original.schema, edit.schema);
        for (original.content, edit.content) |before, after| {
            if (before == .guidance) try std.testing.expectEqualStrings(before.guidance, after.guidance);
        }
        const old = try strict.parse(a, original.content[2].user, .{ .maximum_depth = 64 }, false, null);
        const new = try strict.parse(a, edit.content[2].user, .{ .maximum_depth = 64 }, false, null);
        var left = old.value.object;
        var right = new.value.object;
        _ = left.orderedRemove("field_rules");
        _ = left.orderedRemove("insertion_fields");
        _ = right.orderedRemove("field_rules");
        _ = right.orderedRemove("insertion_fields");
        try std.testing.expectEqualStrings(try p.json(a, @as(std.json.Value, .{ .object = left })), try p.json(a, @as(std.json.Value, .{ .object = right })));
        if (p.baseline(arm.arm)) {
            var changed = original;
            changed.content = edit.content;
            try std.testing.expectEqualStrings(p.requestBytes(arm.source), try p.request(a, changed));
        }
        const observed = try strict.parse(a, edit.content[2].user, .{ .maximum_depth = 64 }, false, null);
        if (arm.arm == .records_grouped_rules or arm.arm == .records_both) {
            const grouped = observed.value.object.get("field_rules").?.array.items;
            try std.testing.expectEqual(@as(usize, 3), grouped.len);
            var field_count: usize = 0;
            for (grouped) |rule| field_count += rule.object.get("fields").?.array.items.len;
            try std.testing.expectEqual(@as(usize, 15), field_count);
            const captured_packet = try strict.parse(a, original.content[2].user, .{ .maximum_depth = 64 }, false, null);
            for (captured_packet.value.object.get("field_rules").?.array.items) |captured_rule| {
                var matches: usize = 0;
                for (grouped) |group| for (group.object.get("fields").?.array.items) |name| {
                    if (std.mem.eql(u8, name.string, captured_rule.object.get("field").?.string)) {
                        try std.testing.expectEqualStrings(captured_rule.object.get("instruction").?.string, group.object.get("instruction").?.string);
                        matches += 1;
                    }
                };
                try std.testing.expectEqual(@as(usize, 1), matches);
            }
        }
        if (arm.arm == .extraction_no_presentation) {
            try std.testing.expect(!observed.value.object.contains("field_rules") and !observed.value.object.contains("insertion_fields"));
        }
        if (arm.arm == .records_no_obligation_wording) {
            try std.testing.expectEqual(@as(usize, 15), observed.value.object.get("field_rules").?.array.items.len);
            for (observed.value.object.get("field_rules").?.array.items) |rule| try std.testing.expect(std.mem.indexOf(u8, rule.object.get("instruction").?.string, "obligation") == null);
        }
        var expected_description = original;
        expected_description.content = edit.content;
        var record: s.CapturedRequestRecord = .{
            .id = "MOCK-replay-1",
            .run = "MOCK-run",
            .sequence = 1,
            .parent_run = p.run,
            .parent_call = p.parentId(arm.source),
            .original_run = p.run,
            .original_call = p.parentId(arm.source),
            .node = "MOCK-invoke",
            .mode = arm.mode,
            .description = expected_description,
            .body = try p.request(a, expected_description),
        };
        const trial: p.Trial = .{ .id = "MOCK", .arm = arm.arm, .repetition = 1 };
        try s.validateRequest(a, trial, record);
        const original_body = record.body;
        record.body = "{}";
        try std.testing.expectError(error.ReplayRequestDrift, s.validateRequest(a, trial, record));
        record.body = original_body;
        record.parent_call = "foreign-inference-1";
        try std.testing.expectError(error.ReplayLineageDrift, s.validateRequest(a, trial, record));
    }
    try s.validateReceiptSet(bundle, .{ .version = .@"insertion-presentation-receipts/v1", .trials = &.{} });
    try std.testing.expectError(error.HistoricalDispatchUnsupported, p.dispatchRequest(a, bundle.manifest.trials[0], &.{}));
    try std.testing.expectError(error.InvalidJsonDocument, @import("../../src/domain/model_request_description.zig").Description.decode(a, p.descriptionBytes(.records)));
    try std.testing.expectError(error.TrialOrder, s.validateReceiptSet(bundle, .{ .version = .@"insertion-presentation-receipts/v1", .trials = &.{.{ .trial_id = bundle.manifest.trials[1].id, .request_record = "request.json", .response_record = "response.json" }} }));
}
test "test.integration.insertion_presentation rejected schema answers remain in raw denominators" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const provider = try strict.parse(a, p.sourceArtifact("records.response.json").?, .{ .maximum_depth = 64 }, false, null);
    const content = provider.value.object.getPtr("output").?.object.getPtr("message").?.object.getPtr("content").?.array.items;
    const text = for (content) |*part| {
        if (part.* == .object and part.object.contains("text")) break &part.object;
    } else return error.MissingRetainedText;
    const original_text = text.get("text").?.string;
    const with_extra = try std.mem.concat(a, u8, &.{ original_text[0 .. original_text.len - 1], ",\"foreign\":true}" });
    try text.put(a, "text", .{ .string = with_extra });
    const measurement = try s.measure(a, try p.description(a, .records), .{ .id = "MOCK-schema-invalid", .outcome = .received, .status = 200, .body = try p.json(a, provider.value) });
    try std.testing.expectEqual(s.State.schema_invalid, measurement.state);
    var insertion_only: u32 = 0;
    for (measurement.fields) |count| insertion_only += count.insertion_only;
    try std.testing.expectEqual(@as(u32, 5), insertion_only);
    const summaries = try s.summarize(a, &.{.{ .trial = .{ .id = "MOCK", .arm = .records_baseline, .repetition = 1 }, .measurement = measurement }});
    for (summaries[0].fields) |field| if (field.field == .ac_given) {
        try std.testing.expectEqual(@as(u32, 1), field.raw_insertion_only.denominator);
        try std.testing.expectEqual(@as(u32, 0), field.schema_valid_insertion_only.denominator);
    };
}
test "test.integration.insertion_presentation retained records retain raw rejected fields and entity exception" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const value = try s.measure(a, try p.description(a, .records), .{ .id = "retained-records", .outcome = .received, .status = 200, .body = p.sourceArtifact("records.response.json").? });
    try std.testing.expectEqual(.historical_v5, value.captured_contract);
    try std.testing.expect(!value.native_exact_scope_available);
    try std.testing.expect(!value.current_model_admission_assessed);
    try std.testing.expectEqual(s.State.composition_invalid, value.state);
    try std.testing.expect(value.schema_valid.?);
    try std.testing.expectEqual(@as(usize, 4), value.composition_diagnostics.len);
    var insertion_only: u32 = 0;
    for (value.fields) |count| insertion_only += count.insertion_only;
    try std.testing.expectEqual(@as(u32, 5), insertion_only);
    const results = [_]s.TrialResult{.{ .trial = .{ .id = "records_baseline-1", .arm = .records_baseline, .repetition = 1 }, .measurement = value }};
    const summaries = try s.summarize(a, &results);
    for (summaries[0].fields) |field| if (field.field == .ac_given) {
        try std.testing.expectEqual(@as(u32, 1), field.raw_insertion_only.numerator);
        try std.testing.expectEqual(@as(u32, 1), field.schema_valid_insertion_only.denominator);
        try std.testing.expectEqual(@as(u32, 0), field.mechanically_admitted_insertion_only.denominator);
    };
}
test "test.integration.insertion_presentation retained extraction measures one broad cited claim mechanically" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const value = try s.measure(a, try p.description(a, .extraction), .{ .id = "retained-extraction", .outcome = .received, .status = 200, .body = p.sourceArtifact("extraction.response.json").? });
    try std.testing.expectEqual(s.State.mechanically_admitted, value.state);
    try std.testing.expectEqual(@as(usize, 1), value.claim_count.?);
    try std.testing.expectEqual(@as(u64, 3), value.maximum_claim_citation_line_span.?);
    try std.testing.expectEqualStrings("business", value.claims[0].kind.?);
    try std.testing.expectEqual(@as(usize, 1), value.claims[0].citation_count.?);
}
