//! Mechanical diagnostic measurements. Semantic fidelity and workflow authority
//! cannot be established by these counts. Caller supplies a short-lived arena
//! that owns returned values and intermediate parsing/schema allocations.
const std = @import("std");
const p = @import("preparation.zig");
const debug = @import("../../../src/domain/request_debugger.zig");
const strict = @import("../../../src/domain/strict_json.zig");
const envelope = @import("../../../src/domain/model_envelope.zig");
const field = @import("../../../src/domain/model_text_field.zig");
const policy = @import("../../../src/domain/text_field_policy.zig");
const composition = @import("../../../src/domain/model_text_composition.zig");
pub const Receipt = struct { trial_id: []const u8, request_record: []const u8, response_record: []const u8 };
pub const Receipts = struct { version: enum { @"insertion-presentation-receipts/v1" }, trials: []const Receipt };
pub const State = enum { not_attempted, unavailable_response, invalid_provider, stopped, invalid_json, schema_invalid, composition_invalid, wire_invalid, mechanically_admitted };
pub const FieldCount = struct {
    field: policy.Field,
    observed: u32 = 0,
    insertion_only: u32 = 0,
    with_nonblank_prose: u32 = 0,
    malformed_text_shape: u32 = 0,
};
pub const ClaimStructure = struct { kind: ?[]const u8, citation_count: ?usize };
pub const Measurement = struct {
    captured_contract: enum { historical_v5 } = .historical_v5,
    native_exact_scope_available: bool = false,
    current_model_admission_assessed: bool = false,
    state: State,
    provider_response_sha256: ?[]const u8 = null,
    model_text_sha256: ?[]const u8 = null,
    normalization: envelope.Normalization = .none,
    schema_valid: ?bool = null,
    composition_valid: ?bool = null,
    fields: []const FieldCount = &.{},
    composition_diagnostics: []const composition.Diagnostic.Description = &.{},
    claim_count: ?usize = null,
    claims: []const ClaimStructure = &.{},
    maximum_claim_citation_line_span: ?u64 = null,
    input_tokens: ?u64 = null,
    output_tokens: ?u64 = null,
    latency_ms: ?u32 = null,
};
pub const TrialResult = struct { trial: p.Trial, request_sha256: ?[]const u8 = null, response_record_sha256: ?[]const u8 = null, measurement: Measurement };
pub const Rate = struct { numerator: u32, denominator: u32, rate: ?f64 };
pub const FieldSummary = struct { field: policy.Field, raw_insertion_only: Rate, schema_valid_insertion_only: Rate, mechanically_admitted_insertion_only: Rate };
pub const Summary = struct { arm: p.Arm, planned: u8 = 3, attempted: u32, mechanically_admitted: u32, fields: []const FieldSummary };
pub const Report = struct {
    version: enum { @"insertion-presentation-score/v1" } = .@"insertion-presentation-score/v1",
    diagnostic_only: bool = true,
    semantic_quality_assessed: bool = false,
    workflow_admission_assessed: bool = false,
    captured_contract: enum { historical_v5 } = .historical_v5,
    current_model_admission_assessed: bool = false,
    planned: u8 = 21,
    attempted: usize,
    trials: []const TrialResult,
    arms: []const Summary,
};
pub const CapturedRequestRecord = struct {
    version: enum { @"request-replay/v6" } = .@"request-replay/v6",
    id: []const u8,
    run: []const u8,
    sequence: u64,
    parent_run: []const u8,
    parent_call: []const u8,
    original_run: []const u8,
    original_call: []const u8,
    node: []const u8,
    mode: debug.Mode,
    description: p.CapturedDescription,
    source_snapshot: ?@import("../../../src/domain/request_source_snapshot.zig").Snapshot = null,
    source_overrides: bool = false,
    body: []const u8,
};
pub fn decodeRequest(a: std.mem.Allocator, bytes: []const u8) !CapturedRequestRecord {
    return strict.decode(CapturedRequestRecord, a, bytes, .{ .maximum_depth = 64 });
}
pub fn validateReceiptSet(bundle: p.Bundle, receipts: Receipts) !void {
    if (receipts.trials.len > bundle.manifest.trials.len) return error.ExtraTrial;
    for (receipts.trials, 0..) |receipt, index| {
        _ = try p.trial(bundle, receipt.trial_id);
        // Attempt order is fixed; an interrupted/uncertain call consumes its row.
        if (!std.mem.eql(u8, bundle.manifest.trials[index].id, receipt.trial_id)) return error.TrialOrder;
        for (receipts.trials[0..index]) |prior| {
            if (std.mem.eql(u8, prior.trial_id, receipt.trial_id) or std.mem.eql(u8, prior.request_record, receipt.request_record) or std.mem.eql(u8, prior.response_record, receipt.response_record)) return error.DuplicateReceipt;
        }
    }
}
pub fn validateRequest(a: std.mem.Allocator, trial: p.Trial, record: CapturedRequestRecord) !void {
    const selected = p.source(trial.arm);
    if (!std.mem.eql(u8, record.parent_run, p.run) or !std.mem.eql(u8, record.parent_call, p.parentId(selected)) or !std.mem.eql(u8, record.original_run, p.run) or !std.mem.eql(u8, record.original_call, p.parentId(selected))) return error.ReplayLineageDrift;
    if (record.mode != (if (p.baseline(trial.arm)) debug.Mode.exact else debug.Mode.modified)) return error.ReplayModeDrift;
    const original = try p.description(a, selected);
    var expected = original;
    expected.content = (try p.edit(a, original, trial.arm)).content;
    if (!std.mem.eql(u8, try p.json(a, record.description), try p.json(a, expected)) or !std.mem.eql(u8, record.body, try p.request(a, expected))) return error.ReplayRequestDrift;
}
pub fn measure(a: std.mem.Allocator, description: p.CapturedDescription, response: debug.ResponseRecord) !Measurement {
    if (response.outcome != .received or response.status != 200 or response.body == null or response.redacted or response.encoding != .utf8) return .{ .state = .unavailable_response };
    const body = response.body.?;
    var result: Measurement = .{ .state = .invalid_provider, .provider_response_sha256 = try p.hash(a, body) };
    const provider = strict.parse(a, body, .{ .maximum_depth = std.math.maxInt(usize) }, false, null) catch |err| return if (err == error.OutOfMemory) err else result;
    // This imports the canonical pure Converse codec, never a transport client.
    var decoded = @import("../../../src/adapters/provider/bedrock_response.zig").decodeConverse(a, provider.value, null) catch |err| return if (err == error.OutOfMemory) err else result;
    defer decoded.deinit(a);
    result.input_tokens = decoded.usage.input_tokens;
    result.output_tokens = decoded.usage.output_tokens;
    result.latency_ms = decoded.latency_ms;
    if (decoded.output != .text) {
        result.state = switch (decoded.output) {
            .invalid => .invalid_provider,
            .stopped => .stopped,
            .text => unreachable,
        };
        return result;
    }
    result.model_text_sha256 = try p.hash(a, decoded.output.text);
    result.state = .invalid_json;
    var document = envelope.parseContent(a, decoded.output.text, null) catch |err| return if (err == error.OutOfMemory) err else result;
    defer document.deinit();
    result.normalization = document.normalization;
    result.fields = try rawFields(a, document.parsed.value, description.field_policies);
    {
        if (document.parsed.value.object.get("claims")) |claims| if (claims == .array) {
            result.claim_count = claims.array.items.len;
            const structures = try a.alloc(ClaimStructure, claims.array.items.len);
            var maximum: u64 = 0;
            for (claims.array.items, structures) |claim, *structure| {
                structure.* = .{ .kind = null, .citation_count = null };
                if (claim != .object) continue;
                if (claim.object.get("content")) |content| if (content == .object) {
                    if (content.object.get("kind")) |kind| if (kind == .string) {
                        structure.kind = try a.dupe(u8, kind.string);
                    };
                };
                if (claim.object.get("citations")) |citations| if (citations == .array) {
                    structure.citation_count = citations.array.items.len;
                    for (citations.array.items) |citation| {
                        if (citation != .object) continue;
                        const first = citation.object.get("first") orelse continue;
                        const last = citation.object.get("last") orelse continue;
                        const lower = number(first) orelse continue;
                        const upper = number(last) orelse continue;
                        if (upper >= lower) maximum = @max(maximum, std.math.add(u64, upper - lower, 1) catch continue);
                    }
                };
            }
            result.claims = structures;
            result.maximum_claim_citation_line_span = maximum;
        };
    }
    const schema_json = try strict.parse(a, description.schema, .{ .maximum_depth = @import("../../../src/domain/model_result_schema.zig").max_json_depth }, true, null);
    const compiled = try @import("../../../src/domain/model_result_schema.zig").compileSelected(a, schema_json.value, description.schema);
    result.schema_valid = @import("../../../src/domain/model_payload_schema.zig").validateValue(envelope.value(&document.parsed.value), compiled.root()) == null;
    // Frozen v5 evidence has no native B3 eligibility projection. Inspect its
    // original wire composition only; never infer a current recognition scope.
    const defect = try composition.check(a, document.parsed.value, description.field_policies, description.prose_fields, description.original_sources, .{ .exact_scope = null });
    result.composition_valid = defect == null;
    if (defect) |diagnostic| result.composition_diagnostics = try diagnostic.describe(a);
    if (!result.schema_valid.?) {
        result.state = .schema_invalid;
    } else if (!result.composition_valid.?) {
        result.state = .composition_invalid;
    } else if ((try @import("../../../src/domain/model_text_wire.zig").checkValue(a, document.parsed.value, compiled.root(), description.original_sources)) != null or (try @import("../../../src/domain/model_text_wire.zig").checkProseFields(a, document.parsed.value, description.prose_fields, description.original_sources)) != null) {
        result.state = .wire_invalid;
    } else result.state = .mechanically_admitted;
    return result;
}
fn number(value: std.json.Value) ?u64 {
    return if (value == .number_string) std.fmt.parseInt(u64, value.number_string, 10) catch null else null;
}
pub fn rawFields(a: std.mem.Allocator, value: std.json.Value, bindings: []const field.Binding) ![]const FieldCount {
    var counts: std.ArrayList(FieldCount) = .empty;
    for (bindings) |binding| {
        var count: FieldCount = .{ .field = binding.field };
        try walk(a, value, binding.path, &count);
        if (count.observed != 0) try counts.append(a, count);
    }
    return counts.toOwnedSlice(a);
}
fn walk(a: std.mem.Allocator, value: std.json.Value, path: []const field.Step, result: *FieldCount) std.mem.Allocator.Error!void {
    if (path.len == 0) {
        try observe(a, value, result);
        return;
    }
    switch (path[0]) {
        .property => |name| if (value == .object) {
            if (value.object.get(name)) |child| try walk(a, child, path[1..], result);
        },
        .variant => |name| if (value == .object) {
            if (value.object.get("kind")) |kind| if (kind == .string and std.mem.eql(u8, kind.string, name)) try walk(a, value, path[1..], result);
        },
        .items => if (value == .array) {
            for (value.array.items) |child| try walk(a, child, path[1..], result);
        },
    }
}
pub fn observe(a: std.mem.Allocator, value: std.json.Value, result: *FieldCount) std.mem.Allocator.Error!void {
    result.observed += 1;
    const nodes = (try @import("../../../src/domain/model_text_wire.zig").compositionNodes(a, value)) orelse {
        result.malformed_text_shape += 1;
        return;
    };
    if (nodes.len == 0) {
        result.malformed_text_shape += 1;
        return;
    }
    var prose = false;
    var insertion = false;
    for (nodes) |node| switch (node) {
        .literal => |literal| prose = prose or nonblank(literal.value),
        .exact_copy, .passive, .source => insertion = true,
    };
    if (prose) result.with_nonblank_prose += 1;
    if (insertion and !prose) result.insertion_only += 1;
}

fn nonblank(bytes: []const u8) bool {
    return std.mem.trim(u8, bytes, " \t\r\n").len != 0;
}
fn rate(numerator: u32, denominator: u32) Rate {
    return .{ .numerator = numerator, .denominator = denominator, .rate = if (denominator == 0) null else @as(f64, @floatFromInt(numerator)) / @as(f64, @floatFromInt(denominator)) };
}
pub fn summarize(a: std.mem.Allocator, results: []const TrialResult) ![]const Summary {
    var arms: std.ArrayList(Summary) = .empty;
    for (std.enums.values(p.Arm)) |arm| {
        var summary: Summary = .{ .arm = arm, .attempted = 0, .mechanically_admitted = 0, .fields = &.{} };
        var fields: std.ArrayList(FieldSummary) = .empty;
        for (std.enums.values(policy.Field)) |identity| {
            var raw: [2]u32 = .{ 0, 0 };
            var schema_valid: [2]u32 = .{ 0, 0 };
            var admitted: [2]u32 = .{ 0, 0 };
            for (results) |result| {
                if (result.trial.arm != arm) continue;
                if (identity == std.enums.values(policy.Field)[0]) {
                    if (result.measurement.state != .not_attempted) summary.attempted += 1;
                    if (result.measurement.state == .mechanically_admitted) summary.mechanically_admitted += 1;
                }
                for (result.measurement.fields) |count| if (count.field == identity) {
                    raw[0] += count.insertion_only;
                    raw[1] += count.observed;
                    if (result.measurement.schema_valid == true) {
                        schema_valid[0] += count.insertion_only;
                        schema_valid[1] += count.observed;
                    }
                    if (result.measurement.state == .mechanically_admitted) {
                        admitted[0] += count.insertion_only;
                        admitted[1] += count.observed;
                    }
                };
            }
            if (raw[1] != 0) try fields.append(a, .{ .field = identity, .raw_insertion_only = rate(raw[0], raw[1]), .schema_valid_insertion_only = rate(schema_valid[0], schema_valid[1]), .mechanically_admitted_insertion_only = rate(admitted[0], admitted[1]) });
        }
        summary.fields = try fields.toOwnedSlice(a);
        try arms.append(a, summary);
    }
    return arms.toOwnedSlice(a);
}
