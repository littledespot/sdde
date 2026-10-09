//! Human-controlled upstream candidates, admitted through production builders.
//! This is isolated task evaluation, not a workflow or extraction-quality test.
const std = @import("std");
const c = @import("contracts.zig");
const f = @import("../../../src/test_fixtures/reference_reconciliation.zig");
const r = f.r;
pub fn packet(io: std.Io, a: std.mem.Allocator, sources: []const c.Source) !*@import("../../../src/domain/model_input_packet.zig").Packet {
    const ingest = @import("../../../src/reference_ingestion_test.zig");
    const texts = try a.alloc([]const u8, sources.len);
    for (sources, texts) |source, *text| text.* = source.text;
    const raw = try ingest.readSources(io, a, texts);
    var ids: @import("../../../src/reference_evidence_test.zig").IdSource = .{};
    const inputs = try @import("../../../src/reference_evidence_test.zig").prepare(a, &ids, raw);
    const tokens = @import("../../../src/test_fixtures/reference_tokens.zig");
    const candidates = try tokens.candidates(a, inputs);
    const results = try a.alloc(r.extraction.RawResult, inputs.chunks.entries.len);
    const parser = @import("../../../src/domain/reference_extraction_parser.zig");
    const codec = @import("../../../src/domain/model_candidate_json.zig");
    for (inputs.chunks.entries, results) |chunk, *result| {
        const source = sources[chunk.source_id.ordinal - 1];
        const view = try r.evidence.resolve(inputs, .{ .state_id = inputs.corpus.state_id, .chunk_id = chunk.id });
        const chunk_text = view.bytes;
        const Claim = @typeInfo(@FieldType(@FieldType(parser.Response, "claims"), "claims")).pointer.child;
        var claims: std.ArrayList(Claim) = .empty;
        if (source.kind) |kind| {
            const content: r.extraction.ProposalContent = switch (kind) {
                inline else => |tag| @unionInit(r.extraction.ProposalContent, @tagName(tag), if (comptime tag == .business or tag == .scope_guard)
                    .{ .segments = &.{.{ .literal = .{ .value = chunk_text } }} }
                else
                    .{ .nodes = &.{.{ .literal = .{ .value = chunk_text } }} }),
            };
            const choices = try @import("../../../src/domain/source_selections.zig").project(a, inputs, .{ .state_id = inputs.corpus.state_id, .chunk_id = chunk.id });
            try claims.append(a, .{ .content = content, .citations = &.{.{ .first = choices[0].id, .last = choices[choices.len - 1].id }} });
        }
        result.* = .{ .scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = chunk.id }, .result = .{ .response = try codec.encode(parser.Response, a, .{ .claims = .{ .claims = claims.items, .token_classifications = try tokens.classifications(a, candidates, chunk) } }) } };
    }
    const extracted = try @import("../../../src/reference_extraction_test.zig").finish(a, inputs, results);
    const text = try @import("../../../src/test_fixtures/reference_text.zig").prepare(a, inputs);
    defer text.deinit();
    const context: f.Context = .{ .inputs = inputs, .registry = text.registry, .current = @import("../../../src/domain/toolchain_safety.zig").value(text.owner) };
    const global = try f.summaries(a, try f.initialize(a, inputs, extracted, 8), context);
    var proposal = try f.global(a, global);
    proposal.role_decisions = null;
    const parsed: r.Parsed = .{ .phase = .signals, .input = global, .proposal = .{ .global = proposal } };
    const dispositions = (try f.validate_dispositions.execute(a, parsed)).valid;
    const signals = (try f.validate_signals.execute(a, dispositions, context)).valid;
    return @import("../../../src/domain/reference_reconciliation_stage.zig").packet(a, .{ .roles = signals }, inputs, text.registry);
}
