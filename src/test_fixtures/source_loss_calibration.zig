//! Offline preparation/admission for the explicitly approved diagnostic cohort.
//! No model dispatch, semantic judge or production fallback.
const std = @import("std");
const refs = @import("reference_reconciliation.zig");
const r = refs.r;
const text = @import("reference_text.zig");
const tokens = @import("reference_tokens.zig");
const extraction = @import("../reference_extraction_test.zig");
const authority = @import("../domain/required_authority.zig");
const support = @import("../domain/specification_support.zig").Source;
const comparison = @import("../domain/source_omission_comparison.zig");
const codec = @import("../domain/model_candidate_json.zig");
const packets = @import("../domain/model_input_packet.zig");
const root = "test/calibration/source-loss-attribution/bound-preservation";
const output = ".zig-cache/source-loss-preservation";
const Case = struct {
    id: []const u8,
    cohort: enum { development, unused },
    sources: []const []const u8,
    claims: []const struct { source: u32, text: []const u8, first: u32, last: u32 },
    description: []const u8,
    missing: []const u8,
    mode: enum { candidate, signal, second_role },
    verdicts: []const comparison.Verdict,
    expected: []const u8,
};

pub fn run() !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cases = try codec.decode([]const Case, a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, root ++ "/cases.json", a, .unlimited));
    var parser: @import("../adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .unlimited));
    try std.Io.Dir.cwd().createDirPath(std.testing.io, output);
    for (cases) |example| {
        var ids: @import("../reference_evidence_test.zig").IdSource = .{};
        const sources = try @import("../reference_evidence_test.zig").prepare(a, &ids, try @import("../reference_ingestion_test.zig").readSources(std.testing.io, a, example.sources));
        const passive = try text.prepare(a, sources);
        defer passive.deinit();
        const available = try tokens.candidates(a, sources);
        const raw = try a.alloc(r.extraction.RawResult, sources.chunks.entries.len);
        for (sources.chunks.entries, raw) |chunk, *result| {
            const resolved = try r.evidence.resolve(sources, .{ .state_id = sources.corpus.state_id, .chunk_id = chunk.id });
            var claims: std.ArrayList(r.extraction.Proposal) = .empty;
            for (example.claims) |claim| if (claim.source == resolved.source.id.ordinal) {
                try claims.append(a, .{ .content = .{ .business = .{ .segments = try a.dupe(r.text.BusinessSegment, &.{.{ .literal = .{ .value = claim.text } }}) } }, .citations = try a.dupe(@import("../domain/source_selections.zig").Selection, &.{.{ .first = .{ .ordinal = claim.first }, .last = .{ .ordinal = claim.last } }}) });
            };
            result.* = .{ .scope = .{ .state_id = sources.corpus.state_id, .chunk_id = chunk.id }, .result = .{ .response = try codec.encode(@import("../domain/reference_extraction_parser.zig").Response, a, .{ .claims = .{ .claims = claims.items, .token_classifications = try tokens.classifications(a, available, chunk) } }) } };
        }
        const extracted = try extraction.finish(a, sources, raw);
        const context: refs.Context = .{ .inputs = sources, .registry = passive.registry, .current = text.safety.value(passive.owner) };
        const global = try refs.summaries(a, try refs.initialize(a, sources, extracted, 2), context);
        var proposed = try refs.global(a, global);
        var groups: std.ArrayList(r.SignalProposal) = .empty;
        var business: std.ArrayList(r.ClaimId) = .empty;
        var combined: std.ArrayList(u8) = .empty;
        for (global.items) |item| if (item.claim.content == .model) {
            try business.append(a, item.claim.id);
            for (item.claim.content.model.business.value.segments) |segment| try combined.appendSlice(a, segment.literal.value);
            try combined.append(a, ' ');
        };
        if (example.mode == .second_role) {
            for (proposed.signals) |signal| try groups.append(a, signal);
        } else {
            try groups.append(a, .{ .claim_ids = business.items, .content = .{ .model = .{ .business = .{ .segments = try a.dupe(r.text.BusinessSegment, &.{.{ .literal = .{ .value = if (example.mode == .signal) example.description else combined.items } }}) } } } });
            for (proposed.signals) |signal| if (signal.content == .preserved_token) try groups.append(a, signal);
        }
        proposed.signals = groups.items;
        var roles: std.ArrayList(r.RoleAssignment) = .empty;
        for (proposed.signals, 1..) |signal, ordinal| if (signal.content == .model) {
            try roles.append(a, .{ .signal_id = .{ .ordinal = @intCast(ordinal) }, .generation_roles = if (example.mode == .second_role and ordinal == 1) &.{.records} else std.enums.values(r.GenerationRole) });
        };
        proposed.role_decisions = try refs.roleDecisions(a, roles.items);
        const finished = (try refs.finish(a, global, proposed, context)).valid;
        const provenance_context: @import("../domain/specification_provenance.zig").Context = .{ .inputs = sources, .references = finished, .registry = context.registry, .current = context.current };
        const records = @import("../domain/reference_support.zig").records(finished);
        const assigned = try @import("../domain/specification_source_binding.zig").roleClaimIds(a, records, .description);
        const attribution = try @import("../domain/specification_provenance.zig").select(a, provenance_context, .{ .claim_ids = assigned, .clarification_response_ids = &.{} });
        const spec = @import("../domain/specification.zig");
        const value: spec.AttributedValue = .{ .value = .{ .segments = try a.dupe(r.text.BusinessSegment, &.{.{ .literal = .{ .value = example.description } }}) }, .provenance = attribution };
        const brief: spec.Brief = .{ .title = value, .description = value, .primary_goal = value };
        const inputs = try @import("../domain/specification_authority.zig").project(a, sources.corpus.feature_id, finished, null, if (example.mode == .signal) null else brief);
        const ledger = try authority.build(a, inputs);
        const index = for (ledger.requirements, 0..) |required, at| {
            if (if (example.mode == .signal) required.seed.id.unit == .signal else required.seed.id.unit == .feature and required.seed.id.slot == .description) break at;
        } else return error.MissingCalibrationTarget;
        // A fixed admitted omission is the experimental premise, not a model judge.
        const findings = try a.alloc(support.Finding, index + 1);
        for (findings, 1..) |*entry, ordinal| entry.* = .{ .requirement_ordinal = @intCast(ordinal), .value = .{ .kind = .supported, .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} }, .source_ids = &.{}, .detail = "", .question = null } };
        const source_ids = try a.alloc(r.extraction.identity.SourceId, sources.corpus.sources.len);
        for (sources.corpus.sources, source_ids) |source, *id| id.* = source.id;
        findings[index].value.kind = .candidate_omission;
        findings[index].value.detail = example.missing;
        findings[index].value.source_ids = source_ids;
        const rules = try @import("../domain/specification_support_evidence.zig").requirements(a, inputs, sources, ledger.requirements[index].seed.id);
        findings[index].value.provenance.claim_ids = rules.rule(.candidate_omission, .{ .unlocalized = .{} }).fixedClaims() orelse &.{};
        const origins = try a.alloc(?@import("../domain/model_candidate_origin.zig").Origin, findings.len);
        @memset(origins, null);
        const pending: support.Candidate = .{ .review = .{ .entries = findings }, .pending_localization = @intCast(index + 1), .working = true, .origin = null, .origins = origins };
        const packet = try support.packetForLoss(a, inputs, provenance_context, pending);
        defer packets.release(packet);
        const assignment = try support.comparisonAssignment(a, inputs, provenance_context, pending);
        try std.testing.expectEqual(example.verdicts.len, assignment.comparisons.len);
        var response = try @import("source_omission_evidence.zig").response(a, assignment, .{ .unlocalized = .{} });
        const assessments = try a.dupe(comparison.Assessment, response.assessments);
        for (assessments, example.verdicts) |*entry, verdict| entry.result = verdict;
        response.assessments = assessments;
        const expected = try support.admitComparisons(a, inputs, provenance_context, pending, assignment, try codec.encode(comparison.Response, a, response));
        const location = comparison.location(expected);
        try std.testing.expectEqualStrings(example.expected, @tagName(location));
        const restricted = try @import("../domain/model_result_schema.zig").restrict(a, schema.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
        defer restricted.release();
        const exported = .{ .input = try std.json.parseFromSliceLeaky(std.json.Value, a, packet.body(), .{}), .schema = restricted.selected().modelBytes(), .assignment = assignment, .expected = expected };
        const exported_bytes = try std.json.Stringify.valueAlloc(a, exported, .{});
        try write(a, example.id, "packet.json", exported_bytes);
        const frozen = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, try std.fmt.allocPrint(a, "{s}/{s}.packet.json", .{ root, example.id }), a, .unlimited);
        const historical = try std.json.parseFromSliceLeaky(std.json.Value, a, frozen, .{});
        // The completed experiment is immutable. The new presentation must retain
        // exactly its native facts, member occurrences and attribution contract.
        try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, historical.object.get("assignment").?, .{}), try std.json.Stringify.valueAlloc(a, exported.assignment, .{}));
        try std.testing.expectEqualStrings(historical.object.get("schema").?.string, exported.schema);
        try checkProjection(a, exported.input, historical.object.get("input").?);
        try std.testing.expectError(error.InvalidPreservationComparison, support.admitComparisons(a, inputs, provenance_context, pending, assignment, "{\"assessments\":[]}"));
        try @import("../model_payload_schema_test.zig").checkDocument(restricted.selected().modelBytes(), .{ .bytes = try codec.encode(comparison.Response, a, response) });
        for ([_][]const u8{ "baseline", "candidate", "revised", "meaning" }) |arm| {
            const revised = std.mem.eql(u8, arm, "revised");
            const current = std.mem.eql(u8, arm, "meaning");
            const directory = if (current) root ++ "/meaning" else if (revised) root ++ "/projection" else root;
            const file_arm = if (revised or current) "candidate" else arm;
            const edit_bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, try std.fmt.allocPrint(a, "{s}/{s}.{s}.edit.json", .{ directory, example.id, file_arm }), a, .unlimited);
            const edit = (try std.json.parseFromSlice(std.json.Value, a, edit_bytes, .{})).value;
            const compiled = try parser.compiler().compile(a, edit.object.get("schema").?.string);
            const content = edit.object.get("content").?.array.items;
            if (current) try std.testing.expectEqualStrings(try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support-loss.prompt.md", a, .unlimited), content[0].object.get("guidance").?.string);
            const wire = try @import("../adapters/provider/bedrock_request.zig").encodeText(a, .{
                .content = &.{ .{ .guidance = content[0].object.get("guidance").?.string }, .{ .user = content[1].object.get("user").?.string } },
                .schema = .{ .native = .{ .guidance = compiled.modelBytes(), .structure = try @import("../domain/model_schema_projection.zig").render(a, compiled, .bedrock) } },
                .schema_name = "sdde_model_envelope_v1",
                .temperature = .zero,
                .max_output_tokens = .{ .value = 16384 },
                .reasoning_effort = .low,
            }, .inference);
            try write(a, example.id, try std.fmt.allocPrint(a, "{s}.request.json", .{arm}), wire);
            const frozen_wire = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, try std.fmt.allocPrint(a, "{s}/{s}.{s}.request.json", .{ directory, example.id, file_arm }), a, .unlimited);
            try std.testing.expectEqualStrings(frozen_wire, wire);
            if (!std.mem.eql(u8, arm, "baseline")) {
                try std.testing.expectEqualStrings(restricted.selected().modelBytes(), edit.object.get("schema").?.string);
                // Serialization whitespace is irrelevant; field values/order are fixed.
                const frozen_body = try std.json.parseFromSlice(std.json.Value, a, edit.object.get("content").?.array.items[1].object.get("user").?.string, .{});
                if (revised) {
                    // Historical requests remain immutable; compare their source
                    // identities and meanings against the current projection.
                    try checkProjection(a, exported.input, frozen_body.value);
                } else {
                    try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, if (current) exported.input else historical.object.get("input").?, .{}), try std.json.Stringify.valueAlloc(a, frozen_body.value, .{}));
                }
            }
        }
        // Optional diagnostic response files are never test fixtures or authority.
        // Each available response is independently passed to production admission;
        // rejected responses are retained in the report rather than hidden.
        for ([_][]const u8{ "", ".projection-baseline", ".projection-candidate", ".meaning-baseline", ".meaning-candidate" }) |diagnostic| for (1..3) |repetition| {
            const diagnostic_id = try std.fmt.allocPrint(a, "{s}{s}", .{ example.id, diagnostic });
            const filename = try std.fmt.allocPrint(a, "{s}/{s}.response-{d}.json", .{ output, diagnostic_id, repetition });
            const bytes = std.Io.Dir.cwd().readFileAlloc(std.testing.io, filename, a, .unlimited) catch |err| switch (err) {
                error.FileNotFound => continue,
                else => return err,
            };
            const outcome = if (support.admitComparisons(a, inputs, provenance_context, pending, assignment, bytes)) |accepted|
                try std.json.Stringify.valueAlloc(a, .{ .admitted = true, .attribution = accepted }, .{})
            else |err|
                try std.json.Stringify.valueAlloc(a, .{ .admitted = false, .rejection = @errorName(err) }, .{});
            try write(a, diagnostic_id, try std.fmt.allocPrint(a, "native-{d}.json", .{repetition}), outcome);
        };
    }
}
fn write(a: std.mem.Allocator, id: []const u8, suffix: []const u8, bytes: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = try std.fmt.allocPrint(a, "{s}/{s}.{s}", .{ output, id, suffix }), .data = bytes });
}

// These compare native occurrences and resolved meaning, not desired model judgments.
fn checkProjection(a: std.mem.Allocator, current: std.json.Value, previous: std.json.Value) !void {
    const fixed = current.object.get("fixed_finding").?.object;
    try std.testing.expectEqualStrings(previous.object.get("fixed_finding").?.object.get("detail").?.string, fixed.get("detail").?.string);
    try std.testing.expect(!current.object.contains("subject"));
    const views = current.object.get("comparisons").?.array.items;
    const old_views = previous.object.get("comparisons").?.array.items;
    try std.testing.expectEqual(old_views.len, views.len);
    for (views, old_views) |view, old| {
        try std.testing.expectEqual(old.object.get("id").?.integer, view.object.get("id").?.integer);
        try std.testing.expect(!view.object.contains("purpose"));
        const members = view.object.get("members").?.array.items;
        const old_members = old.object.get("members").?.array.items;
        try std.testing.expectEqual(old_members.len, members.len);
        for (members, old_members) |member, old_member| {
            try std.testing.expectEqual(old_member.object.get("id").?.integer, member.object.get("id").?.integer);
            const requirement = member.object.get("requirement").?.object;
            const old_requirement = old_member.object.get("requirement").?.object;
            try std.testing.expectEqual(@as(usize, 2), requirement.count());
            for ([_][]const u8{ "meaning", "source_id" }) |key| try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, old_requirement.get(key).?, .{}), try std.json.Stringify.valueAlloc(a, requirement.get(key).?, .{}));
        }
    }
    try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, previous.object.get("sources").?, .{}), try std.json.Stringify.valueAlloc(a, current.object.get("sources").?, .{}));
    try checkNamespaces(current);
}

fn checkNamespaces(value: std.json.Value) !void {
    switch (value) {
        .object => |object| {
            var it = object.iterator();
            while (it.next()) |entry| {
                for ([_][]const u8{ "claim_id", "claim_ids", "citation_id", "citation_ids", "location", "byte", "start", "end" }) |forbidden| try std.testing.expect(!std.mem.eql(u8, entry.key_ptr.*, forbidden));
                try checkNamespaces(entry.value_ptr.*);
            }
        },
        .array => |array| for (array.items) |child| try checkNamespaces(child),
        else => {},
    }
}
