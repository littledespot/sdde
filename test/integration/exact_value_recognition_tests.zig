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
        if (std.mem.eql(u8, sample.description_version, @import("../../src/domain/model_request_description.zig").current_version)) {
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
    const originals: ?[]const wire.SourceText = if (std.mem.eql(u8, sample.description_version, @import("../../src/domain/model_request_description.zig").current_version))
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
        // Frozen v3/v5 descriptions are opaque hash witnesses. Supplied schema
        // selectors describe these captures; they are never current admission.
        .metadata_contract = if (std.mem.eql(u8, sample.description_version, "model-request-debug/v5")) .historical_v5 else .historical_v3,
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
    try std.testing.expectEqual(corpus.MetadataContract.historical_v5, business.metadata_contract);
    try std.testing.expectEqual(corpus.MetadataContract.historical_v5, token.metadata_contract);
    try std.testing.expect(business.native_exact_scope == null and token.native_exact_scope == null);
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

test "test.integration.exact_value.production_admission retained failure classes use current native owners without escape" {
    const production = @import("../harness/exact_value/production_admission.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const report = try production.run(a);
    try std.testing.expectEqual(@as(usize, 5), report.requested_runs);
    try std.testing.expectEqual(@as(usize, 4), report.available_requested_runs);
    try std.testing.expectEqual(@as(usize, 1), report.unavailable_requested_runs);
    try std.testing.expectEqual(@as(usize, 4), report.replayed_capture_rows);
    try std.testing.expectEqual(@as(usize, 1), report.scripted_control_rows);
    try std.testing.expectEqual(@as(usize, 1), report.admitted_rows);
    try std.testing.expectEqual(@as(usize, 4), report.typed_rejection_rows);
    try std.testing.expectEqual(@as(usize, 0), report.admission_escape_rows);
    try std.testing.expectEqual(@as(usize, 6), report.rows.len);
    try std.testing.expect(!report.historical_metadata_promoted and !report.workflow_authority and !report.semantic_quality_assessed);
    try std.testing.expectEqual(@as(usize, 0), report.model_calls);
    for ([_]usize{ 0, 1 }) |index| {
        const row = report.rows[index];
        try std.testing.expectEqual(production.Origin.authentic_capture, row.origin);
        try std.testing.expectEqual(.rejected_by_current_schema_and_codec, row.legacy_exact_wire);
        try std.testing.expect(row.outcome == .rejected);
        try std.testing.expect(row.outcome.rejected == .composition or row.outcome.rejected == .schema);
    }
    try std.testing.expectEqual(.prose_without_insertions, report.rows[2].failure_class);
    try std.testing.expectEqual(.authentic_capture, report.rows[2].origin);
    try std.testing.expectEqualStrings("2026-10-16T09-22-35Z-898e9afbc68759f3d31039bd6bfea0c4", report.rows[2].execution_id.?);
    // The old raw prose predates records naming their claims (ADR 0038), and its
    // third record is an entity that B9 assigns to the feature entities unit. This
    // immutable batch ends in a typed schema rejection rather than an old-shape bypass.
    try std.testing.expectEqual(.missing_required_property, report.rows[2].outcome.rejected.schema.reason);
    try std.testing.expectEqualStrings("/records/0/claim_ids", report.rows[2].outcome.rejected.schema.path);
    try std.testing.expectEqual(.unavailable_capture, report.rows[3].origin);
    try std.testing.expectEqual(.retained_raw_capture_not_found, report.rows[3].outcome.unavailable);
    try std.testing.expect(report.rows[3].output_sha256 == null);
    try std.testing.expectEqual(.embedded_insertion_syntax, report.rows[4].failure_class);
    const syntax = report.rows[4].outcome.rejected.composition;
    try std.testing.expect(syntax.len != 0);
    for (syntax) |issue| try std.testing.expectEqual(.embedded_insertion_syntax, issue.reason);
    for ([_]usize{5}) |index| {
        const row = report.rows[index];
        const accepted = row.outcome.admitted;
        try std.testing.expect(accepted.records >= 2);
        try std.testing.expectEqual(@as(usize, 2), accepted.exact_nodes);
        try std.testing.expect(accepted.explicit_support_unchanged);
        try std.testing.expectEqual(@as(usize, 1), accepted.exact_claims_beyond_explicit_support);
        try std.testing.expectEqual(@as(usize, 1), accepted.coverage_obligations);
        try std.testing.expectEqual(@as(usize, 2), accepted.behavioral_exact_targets);
    }
    const directory = ".zig-cache/exact-value-production-admission";
    try std.Io.Dir.cwd().createDirPath(std.testing.io, directory);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = directory ++ "/report.json", .data = try std.json.Stringify.valueAlloc(a, report, .{ .whitespace = .indent_2 }) });
}
