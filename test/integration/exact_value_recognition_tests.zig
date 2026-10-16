//! Authentic diagnostic projections: no capture is imported as workflow authority.
const std = @import("std");
const strict = @import("../../src/domain/strict_json.zig");
const corpus = @import("../harness/exact_value/corpus.zig");
const field = @import("../../src/domain/model_text_field.zig");
const wire = @import("../../src/domain/model_text_wire.zig");
const Fixture = struct {
    version: enum { @"exact-value-retained/v1" },
    samples: []const Sample,
};
const Sample = struct {
    id: []const u8,
    execution_id: []const u8,
    call: u32,
    context_path: []const u8,
    context_sha256: []const u8,
    description_sha256: []const u8,
    description: []const u8,
    description_version: []const u8,
    prompt_logs: []const struct { path: []const u8, sha256: []const u8 },
    packet: []const u8,
    packet_sha256: []const u8,
    output: []const u8,
    output_sha256: []const u8,
    schema: []const u8,
    schema_sha256: []const u8,
    field_policies: []const field.Binding,
    prose_fields: []const wire.ProseField,
};
fn fixture(a: std.mem.Allocator) !Fixture {
    const value = try strict.decode(Fixture, a, @embedFile("../calibration/exact-value-recognition/retained.json"), .{ .maximum_depth = 128 });
    try std.testing.expectEqual(@as(usize, 3), value.samples.len);
    for (value.samples) |sample| {
        try std.testing.expectEqualStrings(sample.packet_sha256, try corpus.hash(a, sample.packet));
        try std.testing.expectEqualStrings(sample.output_sha256, try corpus.hash(a, sample.output));
        try std.testing.expectEqualStrings(sample.schema_sha256, try corpus.hash(a, sample.schema));
        try std.testing.expectEqualStrings(sample.description_sha256, try corpus.hash(a, sample.description));
        try std.testing.expectEqual(@as(usize, 64), sample.context_sha256.len);
        try std.testing.expectEqual(@as(usize, 64), sample.description_sha256.len);
        try std.testing.expect(sample.prompt_logs.len != 0);
        try std.testing.expect(field.valid(sample.field_policies));
        if (std.mem.eql(u8, sample.description_version, "model-request-debug/v5")) {
            const description = try @import("../../src/domain/model_request_description.zig").Description.decode(a, sample.description);
            var packets: usize = 0;
            for (description.content) |content| if (content == .user) {
                try std.testing.expectEqualStrings(sample.packet, content.user);
                packets += 1;
            };
            try std.testing.expectEqual(@as(usize, 1), packets);
            try std.testing.expectEqualStrings(sample.schema, description.schema);
            try std.testing.expectEqualDeep(sample.field_policies, description.field_policies);
            try std.testing.expectEqualDeep(sample.prose_fields, description.prose_fields);
        }
    }
    return value;
}
fn measure(a: std.mem.Allocator, sample: Sample) !corpus.Measurement {
    const originals: ?[]const wire.SourceText = if (std.mem.eql(u8, sample.description_version, "model-request-debug/v5"))
        (try @import("../../src/domain/model_request_description.zig").Description.decode(a, sample.description)).original_sources
    else
        null;
    return corpus.measure(a, .{
        .packet = sample.packet,
        .output = sample.output,
        .schema = sample.schema,
        .field_policies = sample.field_policies,
        .prose_fields = sample.prose_fields,
        .original_sources = originals,
    }, .{ .boundary_fn = @import("exact_value_unicode").wholeWordBoundary });
}
test "test.integration.exact_value F13 identical bytes cannot bridge business and token requirement bindings" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const retained = try fixture(a);
    const business = try measure(a, retained.samples[0]);
    const token = try measure(a, retained.samples[1]);
    try std.testing.expectEqualStrings("hello-world-business-binding", retained.samples[0].id);
    try std.testing.expectEqualStrings("hello-world-token-binding", retained.samples[1].id);
    try std.testing.expectEqual(corpus.State.measured, business.state);
    try std.testing.expectEqual(corpus.State.measured, token.state);
    var unbound: usize = 0;
    var bound: usize = 0;
    var unbound_behavior_fields: usize = 0;
    for (business.fields) |selected| for (selected.plain_runs) |run| {
        try std.testing.expectEqual(@as(usize, 0), run.result.matches.len);
        unbound += run.result.unbound_matches.len;
        if (selected.native_field != null and (selected.native_field.? == .ac_then or selected.native_field.? == .functional_requirement)) {
            try std.testing.expectEqual(@as(usize, 1), run.result.unbound_matches.len);
            unbound_behavior_fields += 1;
        }
    };
    for (token.fields) |selected| for (selected.plain_runs) |run| {
        try std.testing.expectEqual(@as(usize, 0), run.result.unbound_matches.len);
        bound += run.result.matches.len;
    };
    // Both responses type the greeting in Then and FR. The business batch also
    // types it in entity meaning. None of those bytes can bridge its missing
    // token association; only the token batch has an explicit binding.
    try std.testing.expectEqual(@as(usize, 2), unbound_behavior_fields);
    try std.testing.expectEqual(@as(usize, 3), unbound);
    try std.testing.expectEqual(@as(usize, 2), bound);
    try std.testing.expect(!business.semantic_quality_assessed and !token.semantic_quality_assessed);
    try std.testing.expect(!business.workflow_authority and !token.workflow_authority);
}
test "test.integration.exact_value loan embedded insertion syntax is never interpreted as a value occurrence" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const retained = try fixture(a);
    const loan = retained.samples[2];
    try std.testing.expectEqualStrings("loan-renewal-embedded-syntax", loan.id);
    try std.testing.expectEqualStrings("model-request-debug/v3", loan.description_version);
    try std.testing.expectEqual(@as(usize, 0), loan.field_policies.len);
    try std.testing.expect(std.mem.indexOf(u8, loan.output, "exact_copy") != null);
    const observed = try measure(a, loan);
    try std.testing.expectEqual(corpus.State.measured, observed.state);
    try std.testing.expect(observed.fields.len != 0);
    for (observed.fields) |selected| {
        try std.testing.expectEqual(@as(?@import("../../src/domain/text_field_policy.zig").Field, null), selected.native_field);
        try std.testing.expectEqual(corpus.Composition.unavailable_field_metadata, selected.proposed_composition);
        try std.testing.expectEqual(@as(usize, 0), selected.typed_exact_references.len);
        for (selected.plain_runs) |run| {
            try std.testing.expectEqual(@as(usize, 0), run.result.matches.len);
            try std.testing.expectEqual(@as(usize, 0), run.result.unbound_matches.len);
        }
    }
    try std.testing.expect(!observed.semantic_quality_assessed and !observed.workflow_authority);
}
