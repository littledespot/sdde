//! Frozen, diagnostic-only presentation experiment. No provider dispatch.
//! All returned storage belongs to the caller's arena; functions allocate
//! intermediate parse/schema projections into that same short-lived arena.
const std = @import("std");
const debug = @import("../../../src/domain/request_debugger.zig");
const strict = @import("../../../src/domain/strict_json.zig");
const schema = @import("../../../src/domain/model_result_schema.zig");
const codec = @import("../../../src/adapters/provider/bedrock_request.zig");
pub const run = "RUN-dea0536ccfa67b3b2f8db4048f28330c";
pub const calibration = "test/calibration/insertion-presentation";
pub const Source = enum { records, extraction };
pub const Arm = enum { records_baseline, records_no_insertion_fields, records_grouped_rules, records_both, records_no_obligation_wording, extraction_baseline, extraction_no_presentation };
pub const Pin = struct { file: []const u8, sha256: []const u8, original: []const u8 };
pub const Provenance = struct { version: enum { @"insertion-presentation-sources/v1" }, run_path: []const u8, run_id: []const u8, captures: []const Pin };
pub const Artifact = struct { name: []const u8, bytes: []const u8 };
pub const ArmRecord = struct { arm: Arm, source: Source, mode: debug.Mode, edit_file: []const u8, edit_sha256: []const u8, request_file: []const u8, request_sha256: []const u8 };
pub const Trial = struct { id: []const u8, arm: Arm, repetition: u8 };
pub const Manifest = struct {
    version: enum { @"insertion-presentation-plan/v1" } = .@"insertion-presentation-plan/v1",
    diagnostic_only: bool = true,
    dispatch_authorized: bool = false,
    physical_sends_planned: u8 = 21,
    repetitions: u8 = 3,
    source_run: []const u8 = run,
    provenance_sha256: []const u8,
    arms: []const ArmRecord,
    trials: []const Trial,
};
pub const Bundle = struct { manifest: Manifest, artifacts: []const Artifact };
pub fn source(arm: Arm) Source {
    return switch (arm) {
        .extraction_baseline, .extraction_no_presentation => .extraction,
        else => .records,
    };
}
pub fn baseline(arm: Arm) bool {
    return arm == .records_baseline or arm == .extraction_baseline;
}
pub fn parentId(selected: Source) []const u8 {
    return if (selected == .records) "request-11-inference-1" else "request-1-inference-1";
}
pub fn descriptionBytes(selected: Source) []const u8 {
    return switch (selected) {
        .records => @embedFile("../../calibration/insertion-presentation/sources/records.description.json"),
        .extraction => @embedFile("../../calibration/insertion-presentation/sources/extraction.description.json"),
    };
}
pub fn requestBytes(selected: Source) []const u8 {
    return switch (selected) {
        .records => @embedFile("../../calibration/insertion-presentation/sources/records.request.json"),
        .extraction => @embedFile("../../calibration/insertion-presentation/sources/extraction.request.json"),
    };
}
pub const provenance_bytes = @embedFile("../../calibration/insertion-presentation/sources/provenance.json");
pub const source_artifacts = [_]Artifact{
    .{ .name = "records.description.json", .bytes = descriptionBytes(.records) },
    .{ .name = "records.request.json", .bytes = requestBytes(.records) },
    .{ .name = "extraction.description.json", .bytes = descriptionBytes(.extraction) },
    .{ .name = "extraction.request.json", .bytes = requestBytes(.extraction) },
    .{ .name = "records.context.json", .bytes = @embedFile("../../calibration/insertion-presentation/sources/records.context.json") },
    .{ .name = "extraction.context.json", .bytes = @embedFile("../../calibration/insertion-presentation/sources/extraction.context.json") },
    .{ .name = "records.response.json", .bytes = @embedFile("../../calibration/insertion-presentation/sources/records.response.json") },
    .{ .name = "extraction.response.json", .bytes = @embedFile("../../calibration/insertion-presentation/sources/extraction.response.json") },
    .{ .name = "records.model_output.txt", .bytes = @embedFile("../../calibration/insertion-presentation/sources/records.model_output.txt") },
    .{ .name = "extraction.model_output.txt", .bytes = @embedFile("../../calibration/insertion-presentation/sources/extraction.model_output.txt") },
    .{ .name = "records.outcome.json", .bytes = @embedFile("../../calibration/insertion-presentation/sources/records.outcome.json") },
    .{ .name = "extraction.outcome.json", .bytes = @embedFile("../../calibration/insertion-presentation/sources/extraction.outcome.json") },
};
pub fn validateSources(a: std.mem.Allocator) !void {
    const provenance = try strict.decode(Provenance, a, provenance_bytes, .{ .maximum_depth = 64 });
    if (!std.mem.eql(u8, provenance.run_id, run) or provenance.captures.len != source_artifacts.len) return error.CaptureDrift;
    for (source_artifacts) |artifact| {
        var matched = false;
        for (provenance.captures) |pin| if (std.mem.eql(u8, pin.file, artifact.name)) {
            if (matched or !std.mem.eql(u8, pin.sha256, try hash(a, artifact.bytes))) return error.CaptureDrift;
            matched = true;
        };
        if (!matched) return error.CaptureDrift;
    }
    for (std.enums.values(Source)) |selected| {
        const captured = try @import("../e2e/call_context.zig").CallContext.decode(a, sourceArtifact(if (selected == .records) "records.context.json" else "extraction.context.json").?);
        const value = try description(a, selected);
        if (!std.mem.eql(u8, captured.response_schema, value.schema) or !std.mem.eql(u8, try json(a, captured.content), try json(a, value.content))) return error.CaptureDrift;
    }
}
pub fn sourceArtifact(name: []const u8) ?[]const u8 {
    for (source_artifacts) |artifact| if (std.mem.eql(u8, artifact.name, name)) return artifact.bytes;
    return null;
}
pub fn hash(a: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return a.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
}
pub fn json(a: std.mem.Allocator, value: anytype) ![]const u8 {
    return std.json.Stringify.valueAlloc(a, value, .{});
}
pub fn description(a: std.mem.Allocator, selected: Source) !debug.Description {
    return debug.Description.decode(a, descriptionBytes(selected));
}
pub fn request(a: std.mem.Allocator, value: debug.Description) ![]const u8 {
    // The frozen model registration owns this profile; never select another model.
    if (!std.mem.eql(u8, value.model, "openai.gpt-oss-20b-1:0") or value.response_mode != .native_schema) return error.CaptureDrift;
    const parsed = try strict.parse(a, value.schema, .{ .maximum_depth = schema.max_json_depth }, true, null);
    const compiled = try schema.compileSelected(a, parsed.value, value.schema);
    return codec.encodeText(a, .{
        .content = value.content,
        .schema = .{ .native = .{ .guidance = value.schema, .structure = try @import("../../../src/domain/model_schema_projection.zig").render(a, compiled, .bedrock) } },
        .schema_name = "sdde_model_envelope_v1",
        .temperature = value.controls.temperature,
        .max_output_tokens = value.controls.max_output_tokens,
        .reasoning_effort = try codec.reasoningEffort(value.reasoning_effort),
        .request_profile = .openai_oss,
    }, .inference);
}

/// Mutation is limited to presentation keys in the one original user packet.
/// Grouping retains every original field association instead of deleting fields.
pub fn edit(a: std.mem.Allocator, original: debug.Description, arm: Arm) !debug.Edit {
    const content = try a.dupe(@import("../../../src/domain/llm_provider_operation.zig").ModelVisibleContent, original.content);
    if (baseline(arm)) return .{ .content = content, .schema = original.schema };
    var selected: ?usize = null;
    for (content, 0..) |part, index| if (part == .user) {
        if (selected != null) return error.AmbiguousPacket;
        selected = index;
    };
    const index = selected orelse return error.MissingPacket;
    var parsed = try strict.parse(a, content[index].user, .{ .maximum_depth = 64 }, false, null);
    if (parsed.value != .object) return error.InvalidPacket;
    var packet = &parsed.value.object;
    const rules = packet.get("field_rules") orelse return error.MissingPresentation;
    if (rules != .array or !packet.contains("insertion_fields")) return error.MissingPresentation;
    switch (arm) {
        .records_no_insertion_fields, .records_both => _ = packet.orderedRemove("insertion_fields"),
        .extraction_no_presentation => {
            _ = packet.orderedRemove("field_rules");
            _ = packet.orderedRemove("insertion_fields");
        },
        else => {},
    }
    if (arm == .records_grouped_rules or arm == .records_both) try packet.put(a, "field_rules", try groupRules(a, rules));
    if (arm == .records_no_obligation_wording) {
        for (rules.array.items) |*rule| {
            const instruction = rule.object.get("instruction") orelse return error.InvalidPacket;
            if (instruction != .string) return error.InvalidPacket;
            const first = try std.mem.replaceOwned(u8, a, instruction.string, "Exact copies may carry its exact-value obligation inside that prose", "Exact copies may be included inside that prose");
            const second = try std.mem.replaceOwned(u8, a, first, ". Its occurrence does not satisfy a behavioral exact-copy obligation.", ".");
            try rule.object.put(a, "instruction", .{ .string = second });
        }
    }
    content[index] = .{ .user = try json(a, parsed.value) };
    return .{ .content = content, .schema = original.schema };
}
pub fn groupRules(a: std.mem.Allocator, rules: std.json.Value) !std.json.Value {
    if (rules != .array) return error.InvalidPacket;
    var grouped: std.json.Array = .init(a);
    for (rules.array.items) |rule| {
        if (rule != .object or rule.object.count() != 2) return error.InvalidPacket;
        const field = rule.object.get("field") orelse return error.InvalidPacket;
        const instruction = rule.object.get("instruction") orelse return error.InvalidPacket;
        if (field != .string or instruction != .string) return error.InvalidPacket;
        for (grouped.items) |*entry| {
            if (std.mem.eql(u8, entry.object.get("instruction").?.string, instruction.string)) {
                const fields = entry.object.getPtr("fields").?;
                try fields.array.append(field);
                break;
            }
        } else {
            var fields: std.json.Array = .init(a);
            try fields.append(field);
            var object: std.json.ObjectMap = .{};
            try object.put(a, "fields", .{ .array = fields });
            try object.put(a, "instruction", instruction);
            try grouped.append(.{ .object = object });
        }
    }
    return .{ .array = grouped };
}
pub fn prepare(a: std.mem.Allocator) !Bundle {
    try validateSources(a);
    var artifacts: std.ArrayList(Artifact) = .empty;
    var arms: std.ArrayList(ArmRecord) = .empty;
    for (std.enums.values(Arm)) |arm| {
        const selected = source(arm);
        const original = try description(a, selected);
        if (!std.mem.eql(u8, try request(a, original), requestBytes(selected))) return error.CaptureDrift;
        const modified = try edit(a, original, arm);
        var changed = original;
        changed.content = modified.content;
        const wire = try request(a, changed);
        const edit_bytes = try json(a, modified);
        const edit_name = try std.fmt.allocPrint(a, "{s}.edit.json", .{@tagName(arm)});
        const request_name = try std.fmt.allocPrint(a, "{s}.request.json", .{@tagName(arm)});
        try artifacts.append(a, .{ .name = edit_name, .bytes = edit_bytes });
        try artifacts.append(a, .{ .name = request_name, .bytes = wire });
        try arms.append(a, .{ .arm = arm, .source = selected, .mode = if (baseline(arm)) .exact else .modified, .edit_file = edit_name, .edit_sha256 = try hash(a, edit_bytes), .request_file = request_name, .request_sha256 = try hash(a, wire) });
    }
    var trials: std.ArrayList(Trial) = .empty;
    for (1..4) |repetition| for (std.enums.values(Arm)) |arm| {
        try trials.append(a, .{ .id = try std.fmt.allocPrint(a, "{s}-{d}", .{ @tagName(arm), repetition }), .arm = arm, .repetition = @intCast(repetition) });
    };
    const manifest: Manifest = .{ .provenance_sha256 = try hash(a, provenance_bytes), .arms = try arms.toOwnedSlice(a), .trials = try trials.toOwnedSlice(a) };
    try artifacts.append(a, .{ .name = "plan.json", .bytes = try json(a, manifest) });
    return .{ .manifest = manifest, .artifacts = try artifacts.toOwnedSlice(a) };
}
pub fn trial(bundle: Bundle, id: []const u8) !Trial {
    for (bundle.manifest.trials) |value| if (std.mem.eql(u8, value.id, id)) return value;
    return error.UnknownTrial;
}
pub fn dispatchRequest(a: std.mem.Allocator, selected: Trial, calls: []const debug.Call) !debug.ReplayInput {
    const original = try description(a, source(selected.arm));
    var parent: ?u32 = null;
    for (calls, 0..) |call, index| {
        if (!std.mem.eql(u8, call.run, run) or !std.mem.eql(u8, call.id, parentId(source(selected.arm)))) continue;
        if (parent != null) return error.AmbiguousParent;
        if (call.replay != null or call.redacted or !call.request_complete or !std.mem.eql(u8, call.request orelse return error.IncompleteParent, requestBytes(source(selected.arm)))) return error.CaptureDrift;
        const captured = call.description orelse return error.IncompleteParent;
        if (!std.mem.eql(u8, try json(a, captured), try json(a, original))) return error.CaptureDrift;
        parent = std.math.cast(u32, index) orelse return error.InvalidCallIndex;
    }
    return .{ .call = parent orelse return error.MissingParent, .mode = if (baseline(selected.arm)) .exact else .modified, .edit = if (baseline(selected.arm)) null else try edit(a, original, selected.arm) };
}
/// Canonical closed decoding retains the explicit parsed-JSON evidence leaf
/// while rejecting unknown metadata and wire-kind coercions around it.
pub fn decodeCalls(a: std.mem.Allocator, bytes: []const u8) ![]const debug.Call {
    return strict.decode([]const debug.Call, a, bytes, .{ .maximum_depth = 64 });
}
