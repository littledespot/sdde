//! Explicit offline corpus acquisition. Reads retained bytes and writes one
//! diagnostic report; no provider, credential, process or workflow capability.
const std = @import("std");
const c = @import("corpus.zig");
const strict = @import("../../../src/domain/strict_json.zig");
const files = @import("../files.zig");
const controls = @import("control_tests.zig");
const classifier: c.recognition.LexicalClassifier = .{ .boundary_fn = @import("exact_value_unicode").wholeWordBoundary };
pub const Options = struct { output: []const u8, roots: []const []const u8 };
pub fn parse(a: std.mem.Allocator, args: []const []const u8) !Options {
    var output: ?[]const u8 = null;
    var roots: std.ArrayList([]const u8) = .empty;
    var index: usize = 0;
    while (index < args.len) : (index += 2) {
        if (index + 1 >= args.len) return error.InvalidArguments;
        try @import("../contracts.zig").path(args[index + 1]);
        if (std.mem.eql(u8, args[index], "--output")) {
            if (output != null) return error.InvalidArguments;
            output = args[index + 1];
        } else if (std.mem.eql(u8, args[index], "--root")) {
            for (roots.items) |prior| if (overlap(prior, args[index + 1])) return error.OverlappingRoots;
            try roots.append(a, args[index + 1]);
        } else return error.InvalidArguments;
    }
    if (roots.items.len == 0) return error.InvalidArguments;
    return .{ .output = output orelse return error.InvalidArguments, .roots = try roots.toOwnedSlice(a) };
}
fn overlap(left: []const u8, right: []const u8) bool {
    return std.mem.eql(u8, left, right) or (std.mem.startsWith(u8, right, left) and right.len > left.len and right[left.len] == '/') or (std.mem.startsWith(u8, left, right) and left.len > right.len and left[right.len] == '/');
}
pub const Family = enum { exchange_context, debugger_request, calibration_call, provider_request, embedded_capture, prompt_archive, orphan_response, orphan_text_output, unsupported_request };
pub const Disposition = enum { measured, missing_response, unavailable_response, unsupported_provider_format, missing_packet, malformed_capture, unsupported_capture_version, archive_without_description, unsupported_archive, invalid_archive, input_unavailable };
pub const Artifact = struct { path: []const u8, sha256: ?[]const u8 = null, pointer: ?[]const u8 = null };
pub const RequestContext = struct {
    state: enum { exact_values, no_exact_values, invalid_packet },
    occurrence_count: usize = 0,
};
pub const Row = struct {
    id: []const u8,
    family: Family,
    artifact: Artifact,
    response: ?Artifact = null,
    metadata_witness: ?Artifact = null,
    exchange_key: ?[]const u8 = null,
    duplicate_of: ?[]const u8 = null,
    same_payload_as: ?[]const u8 = null,
    disposition: Disposition,
    diagnostic: ?[]const u8 = null,
    payload_sha256: ?[]const u8 = null,
    measurement: ?c.Measurement = null,
    request_context: ?RequestContext = null,
};
pub const Counts = struct {
    files: usize = 0,
    json_files: usize = 0,
    preparation_or_other_json: usize = 0,
    nonregular_inventory_entries: usize = 0,
    member_artifacts: usize = 0,
    captures: usize = 0,
    unique_known_exchanges: usize = 0,
    duplicate_captures: usize = 0,
    exchange_identity_conflicts: usize = 0,
    unknown_exchange_identity: usize = 0,
    measured_captures: usize = 0,
    exact_context_captures: usize = 0,
    exact_context_with_response: usize = 0,
    unavailable_request_context: usize = 0,
    invalid_request_context: usize = 0,
    unavailable_boundary_context_runs: usize = 0,
    measured_fields: usize = 0,
    missing_binding_fields: usize = 0,
    unavailable_native_field_metadata: usize = 0,
    matched_plain_runs: usize = 0,
    unbound_plain_matches: usize = 0,
    ambiguous_plain_runs: usize = 0,
    original_typed_exact_references: usize = 0,
    typed_counterfactual_fields: usize = 0,
    invalid_proposed_composition: usize = 0,
    unsupported_or_missing_captures: usize = 0,
    unsupported_log_capture_denominator_unknown: usize = 0,
    unsupported_embedded_capture_denominator_unknown: usize = 0,
};
pub const Report = struct {
    binding_policy: enum { selected_requirement_membership } = .selected_requirement_membership,
    version: enum { @"exact-value-corpus/v1" } = .@"exact-value-corpus/v1",
    diagnostic_only: bool = true,
    model_calls: usize = 0,
    workflow_authority: bool = false,
    semantic_quality_assessed: bool = false,
    false_match_rate_assessed: bool = false,
    all_capture_bindings_complete: bool = false,
    roots: []const []const u8,
    counts: Counts,
    dispositions: []const struct { state: Disposition, count: usize },
    measurement_states: []const struct { state: c.State, count: usize },
    controls: controls.Summary,
    captures: []const Row,
};
const Native = struct {
    scope: []const u8,
    call_id: []const u8,
    content_sha256: []const u8,
    schema_sha256: []const u8,
    step: []const u8,
    field_policies: []const @import("../../../src/domain/model_text_field.zig").Binding,
    prose_fields: []const @import("../../../src/domain/model_text_wire.zig").ProseField,
    original_sources: ?[]const @import("../../../src/domain/model_text_wire.zig").SourceText = null,
    metadata_contract: c.MetadataContract = .current_v8,
    exact_scope: ?@import("../../../src/domain/model_exact_values.zig").Scope = null,
    members: []const @import("../../../src/domain/model_result_schema.zig").MemberChoice = &.{},
    artifact: Artifact,
    exchange_key: []const u8,
};
const State = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    paths: std.StringHashMap(void),
    rows: std.ArrayList(Row) = .empty,
    native: std.ArrayList(Native) = .empty,
    counts: Counts = .{},
};
pub fn main(init: std.process.Init) !void {
    command(init) catch |err| {
        try std.Io.File.stderr().writeStreamingAll(init.io, try std.fmt.allocPrint(init.arena.allocator(), "Offline exact-value replay failed: {s}. Zero model calls.\n", .{@errorName(err)}));
        std.process.exit(1);
    };
}
const help =
    \\Usage: zig build exact-value-replay -- --output <report.json> --root <capture-directory> [--root <capture-directory> ...]
    \\Offline only. Inventories retained E2E contexts, debugger requests, calibration exchanges, embedded captures and prompt archives. Reports missing/unsupported evidence, duplicates and unavailable requirement/native-field bindings explicitly. Output is diagnostic evidence, never workflow authority or a semantic false-match assessment. No model call is possible.
    \\
;
fn command(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len == 2 and std.mem.eql(u8, args[1], "--help")) return std.Io.File.stdout().writeStreamingAll(init.io, help);
    const options = try parse(a, args[1..]);
    const report = try acquire(init.io, a, options.roots);
    var output = try std.Io.Dir.cwd().createFile(init.io, options.output, .{ .exclusive = true });
    defer output.close(init.io);
    try output.writeStreamingAll(init.io, try std.json.Stringify.valueAlloc(a, report, .{ .whitespace = .indent_2 }));
    try std.Io.File.stdout().writeStreamingAll(init.io, try std.fmt.allocPrint(a, "Offline corpus: {d} captures, {d} measured fields; report {s}. Zero model calls.\n", .{ report.counts.captures, report.counts.measured_fields, options.output }));
}
fn collect(state: *State, directory: []const u8, output: *std.ArrayList([]const u8)) !void {
    var dir = try @import("../../../src/adapters/filesystem/directory_access.zig").open(state.io, .cwd(), directory);
    defer dir.close(state.io);
    var iterator = dir.iterate();
    while (try iterator.next(state.io)) |entry| {
        const path = try std.fmt.allocPrint(state.allocator, "{s}/{s}", .{ directory, entry.name });
        if (entry.kind == .directory) {
            try collect(state, path, output);
            continue;
        }
        state.counts.files += 1;
        const relevant = outputTextPath(path) or std.mem.endsWith(u8, path, ".json") or (std.mem.indexOf(u8, path, "/logs/prompts/") != null and std.mem.endsWith(u8, path, ".log"));
        if (entry.kind != .file) state.counts.nonregular_inventory_entries += 1;
        if (entry.kind != .file and !relevant) continue;
        if (entry.kind != .file) {
            try state.rows.append(state.allocator, .{ .id = path, .family = .unsupported_request, .artifact = .{ .path = path }, .disposition = .input_unavailable, .diagnostic = "Non-regular retained entry; no symlink followed" });
            continue;
        }
        try state.paths.put(path, {});
        if (outputTextPath(path) or std.mem.endsWith(u8, path, ".json") or (std.mem.indexOf(u8, path, "/logs/prompts/") != null and std.mem.endsWith(u8, path, ".log"))) try output.append(state.allocator, path);
    }
}
pub fn acquire(io: std.Io, a: std.mem.Allocator, roots: []const []const u8) !Report {
    var state: State = .{ .io = io, .allocator = a, .paths = .init(a) };
    var paths: std.ArrayList([]const u8) = .empty;
    for (roots, 0..) |root, index| {
        try @import("../contracts.zig").path(root);
        for (roots[0..index]) |prior| if (overlap(prior, root)) return error.OverlappingRoots;
        try collect(&state, root, &paths);
    }
    std.mem.sort([]const u8, paths.items, {}, struct {
        fn less(_: void, left: []const u8, right: []const u8) bool {
            return std.mem.lessThan(u8, left, right);
        }
    }.less);
    // Parse each prompt log once. Per-log arenas release all large descriptions;
    // only hashes and the small native selector projections survive.
    for (paths.items) |path| if (std.mem.endsWith(u8, path, ".log")) try prompt(&state, path);
    for (paths.items) |path| if (std.mem.endsWith(u8, path, ".json")) {
        state.counts.json_files += 1;
        jsonFile(&state, path) catch |err| {
            if (err == error.OutOfMemory) return err;
            try appendRow(&state, .{ .id = path, .family = .unsupported_request, .artifact = .{ .path = path }, .disposition = .malformed_capture, .diagnostic = @errorName(err) });
        };
    };
    for (paths.items) |path| if (outputTextPath(path)) try textArtifact(&state, path);
    try finalize(&state);
    var dispositions: std.ArrayList(std.meta.Child(@FieldType(Report, "dispositions"))) = .empty;
    for (std.enums.values(Disposition)) |tag| {
        var count: usize = 0;
        for (state.rows.items) |row| if (row.disposition == tag) {
            count += 1;
        };
        try dispositions.append(a, .{ .state = tag, .count = count });
    }
    var measurements: std.ArrayList(std.meta.Child(@FieldType(Report, "measurement_states"))) = .empty;
    for (std.enums.values(c.State)) |tag| {
        var count: usize = 0;
        for (state.rows.items) |row| if (row.measurement) |measurement| if (measurement.state == tag) {
            count += 1;
        };
        try measurements.append(a, .{ .state = tag, .count = count });
    }
    const control_summary = try controls.verify(a, try controls.decode(a, controls.controls_bytes));
    return .{ .roots = roots, .counts = state.counts, .dispositions = try dispositions.toOwnedSlice(a), .measurement_states = try measurements.toOwnedSlice(a), .controls = control_summary, .captures = try state.rows.toOwnedSlice(a) };
}
fn member(value: std.json.Value, key: []const u8) ?std.json.Value {
    return if (value == .object) value.object.get(key) else null;
}
fn string(value: ?std.json.Value) ?[]const u8 {
    return if (value != null and value.? == .string) value.?.string else null;
}
fn version(value: std.json.Value) ?[]const u8 {
    return string(member(value, "version")) orelse string(member(value, "schema"));
}
fn metadataContract(bytes: []const u8) ?c.MetadataContract {
    inline for (.{ .{ "model-request-debug/v8", c.MetadataContract.current_v8 }, .{ "model-request-debug/v5", c.MetadataContract.historical_v5 }, .{ "model-request-debug/v4", c.MetadataContract.historical_v4 }, .{ "model-request-debug/v3", c.MetadataContract.historical_v3 } }) |entry| {
        if (std.mem.eql(u8, bytes, entry[0])) return entry[1];
    }
    return null;
}
fn json(a: std.mem.Allocator, value: anytype) ![]const u8 {
    return std.json.Stringify.valueAlloc(a, value, .{});
}
fn durable(state: *State, value: anytype) !@TypeOf(value) {
    var arena: std.heap.ArenaAllocator = .init(state.allocator);
    defer arena.deinit();
    return strict.decode(@TypeOf(value), state.allocator, try json(arena.allocator(), value), .{ .maximum_depth = 128 });
}
fn artifact(state: *State, path: []const u8, bytes: []const u8) !Artifact {
    return .{ .path = path, .sha256 = try c.hash(state.allocator, bytes) };
}
fn appendRow(state: *State, value: Row) !void {
    try state.rows.append(state.allocator, try durable(state, value));
}
fn packetFromContent(content: std.json.Value) ?[]const u8 {
    if (content != .array) return null;
    var result: ?[]const u8 = null;
    for (content.array.items) |part| if (string(member(part, "user"))) |bytes| {
        if (result != null) return null;
        result = bytes;
    };
    return result;
}
fn sibling(a: std.mem.Allocator, path: []const u8, suffix: []const u8, replacement: []const u8) ![]const u8 {
    return std.fmt.allocPrint(a, "{s}{s}", .{ path[0 .. path.len - suffix.len], replacement });
}
fn prefix(a: std.mem.Allocator, path: []const u8, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(a, "{s}/{s}", .{ std.fs.path.dirname(path).?, name });
}
fn modelOutput(state: *State, scratch: std.mem.Allocator, response_path: []const u8, saved_text: ?[]const u8, response_is_record: bool, expected_id: ?[]const u8) !struct { text: ?[]const u8, disposition: Disposition, raw: ?Artifact } {
    if (!state.paths.contains(response_path)) return .{ .text = null, .disposition = .missing_response, .raw = null };
    const bytes = files.read(state.io, scratch, .cwd(), response_path) catch |err| return if (err == error.OutOfMemory) err else .{ .text = null, .disposition = .input_unavailable, .raw = null };
    const raw = try artifact(state, response_path, bytes);
    if (response_is_record) {
        const record = strict.decode(@import("../../../src/domain/request_debugger.zig").ResponseRecord, scratch, bytes, .{ .maximum_depth = 128 }) catch |err| return if (err == error.OutOfMemory) err else .{ .text = null, .disposition = .malformed_capture, .raw = raw };
        if (expected_id == null or !std.mem.eql(u8, record.id, expected_id.?)) return .{ .text = null, .disposition = .malformed_capture, .raw = raw };
        if (record.outcome != .received or record.status != 200 or record.body == null or record.encoding != .utf8 or record.redacted) return .{ .text = null, .disposition = .unavailable_response, .raw = raw };
    }
    if (saved_text) |path| if (state.paths.contains(path)) return .{ .text = try files.read(state.io, scratch, .cwd(), path), .disposition = .measured, .raw = raw };
    const parsed = strict.parse(scratch, bytes, .{ .maximum_depth = 128 }, false, null) catch |err| return if (err == error.OutOfMemory) err else .{ .text = null, .disposition = .malformed_capture, .raw = raw };
    var body = parsed.value;
    if (response_is_record) {
        const record = strict.decode(@import("../../../src/domain/request_debugger.zig").ResponseRecord, scratch, bytes, .{ .maximum_depth = 128 }) catch |err| return if (err == error.OutOfMemory) err else .{ .text = null, .disposition = .malformed_capture, .raw = raw };
        if (record.outcome != .received or record.status != 200 or record.body == null or record.encoding != .utf8 or record.redacted) return .{ .text = null, .disposition = .unavailable_response, .raw = raw };
        body = (strict.parse(scratch, record.body.?, .{ .maximum_depth = 128 }, false, null) catch |err| return if (err == error.OutOfMemory) err else .{ .text = null, .disposition = .malformed_capture, .raw = raw }).value;
    }
    const output = try providerText(scratch, body);
    return .{ .text = output, .disposition = if (output != null) .measured else .unsupported_provider_format, .raw = raw };
}
fn providerText(a: std.mem.Allocator, body: std.json.Value) !?[]const u8 {
    if (member(body, "output") == null) return null; // No historical provider compatibility decoder.
    var decoded = @import("../../../src/adapters/provider/bedrock_response.zig").decodeConverse(a, body, null) catch |err| return if (err == error.OutOfMemory) err else null;
    defer decoded.deinit(a);
    return if (decoded.output == .text) try a.dupe(u8, decoded.output.text) else null;
}
fn requestContext(a: std.mem.Allocator, packet_bytes: []const u8) !RequestContext {
    const parsed = strict.parse(a, packet_bytes, .{ .maximum_depth = 128 }, false, null) catch |err| return if (err == error.OutOfMemory) err else .{ .state = .invalid_packet };
    var packet = parsed.value;
    if (member(packet, "input")) |inner| if (inner == .object) {
        packet = inner;
    };
    const tokens = member(packet, "preserved_tokens") orelse return .{ .state = .no_exact_values };
    if (tokens != .array) return .{ .state = .invalid_packet };
    return .{ .state = if (tokens.array.items.len == 0) .no_exact_values else .exact_values, .occurrence_count = tokens.array.items.len };
}
const Metadata = struct {
    contract: c.MetadataContract = .unavailable,
    fields: []const @import("../../../src/domain/model_text_field.zig").Binding = &.{},
    prose: []const @import("../../../src/domain/model_text_wire.zig").ProseField = &.{},
    sources: ?[]const @import("../../../src/domain/model_text_wire.zig").SourceText = null,
    exact_scope: ?@import("../../../src/domain/model_exact_values.zig").Scope = null,
    members: []const @import("../../../src/domain/model_result_schema.zig").MemberChoice = &.{},
};
fn measureRow(state: *State, scratch: std.mem.Allocator, base: Row, packet: []const u8, output: []const u8, schema: ?[]const u8, metadata: Metadata) !void {
    var result = base;
    result.disposition = .measured;
    result.request_context = try requestContext(scratch, packet);
    if (metadata.exact_scope) |scope_facts| result.request_context = .{ .state = if (scope_facts.occurrences.len == 0) .no_exact_values else .exact_values, .occurrence_count = scope_facts.occurrences.len };
    result.payload_sha256 = try c.hash(scratch, try std.mem.concat(scratch, u8, &.{ packet, "\x00", schema orelse "", "\x00", output }));
    result.measurement = c.measure(scratch, .{ .packet = packet, .output = output, .schema = schema, .field_policies = metadata.fields, .prose_fields = metadata.prose, .original_sources = metadata.sources, .metadata_contract = metadata.contract, .exact_scope = metadata.exact_scope, .members = metadata.members }, classifier) catch |err| {
        if (err == error.OutOfMemory) return err;
        result.disposition = .malformed_capture;
        result.diagnostic = @errorName(err);
        try appendRow(state, result);
        return;
    };
    try appendRow(state, result);
}
fn scope(path: []const u8) []const u8 {
    if (std.mem.indexOf(u8, path, "/project/")) |end| return path[0..end];
    if (std.mem.indexOf(u8, path, "/evidence/")) |end| return path[0..end];
    return std.fs.path.dirname(path) orelse path;
}
fn prompt(state: *State, path: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(state.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try files.read(state.io, a, .cwd(), path);
    const witness = try artifact(state, path, bytes);
    const capture = try @import("prompt_capture.zig").capture(a, bytes);
    defer capture.deinit();
    if (capture.status != .current) {
        state.counts.unsupported_log_capture_denominator_unknown += 1;
        try appendRow(state, .{ .id = path, .family = .prompt_archive, .artifact = witness, .disposition = if (capture.status == .unsupported_description) .unsupported_archive else .invalid_archive, .diagnostic = capture.reason });
        return;
    }
    if (capture.calls.len == 0) {
        try appendRow(state, .{ .id = path, .family = .prompt_archive, .artifact = witness, .disposition = .archive_without_description, .diagnostic = "Canonical current archive contains zero calls" });
        return;
    }
    for (capture.calls) |call| {
        var source = witness;
        source.pointer = call.id;
        const key = try std.fmt.allocPrint(a, "{s}:{s}", .{ call.run, call.id });
        const base: Row = .{ .id = try std.fmt.allocPrint(a, "{s}#{s}", .{ path, call.id }), .family = .prompt_archive, .artifact = source, .exchange_key = key, .disposition = .archive_without_description };
        const description = call.description orelse {
            try appendRow(state, base);
            continue;
        };
        const content = try json(a, description.content);
        const parsed_content = try strict.parse(a, content, .{ .maximum_depth = 128 }, false, null);
        const packet = packetFromContent(parsed_content.value) orelse {
            var missing = base;
            missing.disposition = .missing_packet;
            try appendRow(state, missing);
            continue;
        };
        var described = base;
        described.request_context = try requestContext(a, packet);
        const native: Native = .{
            .scope = scope(path),
            .call_id = call.id,
            .content_sha256 = try c.hash(a, content),
            .schema_sha256 = try c.hash(a, description.schema),
            .step = call.request_step,
            .field_policies = description.field_policies,
            .prose_fields = description.prose_fields,
            .original_sources = description.original_sources,
            .exact_scope = description.exact_scope,
            .members = description.members,
            .artifact = source,
            .exchange_key = key,
        };
        try state.native.append(state.allocator, try durable(state, native));
        if (call.response == null) {
            var missing = described;
            missing.disposition = .missing_response;
            try appendRow(state, missing);
            continue;
        }
        if (call.redacted or !std.mem.eql(u8, call.response_encoding, "utf8") or !std.mem.eql(u8, call.response_provenance orelse "", "provider_body")) {
            var missing = described;
            missing.disposition = .unavailable_response;
            try appendRow(state, missing);
            continue;
        }
        const body = strict.parse(a, call.response.?, .{ .maximum_depth = 128 }, false, null) catch |err| {
            if (err == error.OutOfMemory) return err;
            var invalid = described;
            invalid.disposition = .malformed_capture;
            try appendRow(state, invalid);
            continue;
        };
        const output = try providerText(a, body.value) orelse {
            var unsupported = described;
            unsupported.disposition = .unsupported_provider_format;
            try appendRow(state, unsupported);
            continue;
        };
        try measureRow(state, a, described, packet, output, description.schema, .{ .contract = .current_v8, .fields = description.field_policies, .prose = description.prose_fields, .sources = description.original_sources, .exact_scope = description.exact_scope, .members = description.members });
    }
}
fn nativeFor(state: *State, a: std.mem.Allocator, path: []const u8, content: []const u8, schema: []const u8, step: []const u8, origin: @import("../../../src/domain/model_candidate_origin.zig").Origin) !?Native {
    var call_buffer: [96]u8 = undefined;
    const call_id = try @import("../../../src/domain/model_call_lineage.zig").callId(&call_buffer, origin);
    const content_hash = try c.hash(a, content);
    const schema_hash = try c.hash(a, schema);
    var found: ?Native = null;
    for (state.native.items) |candidate| {
        if (!std.mem.eql(u8, candidate.call_id, call_id) or !std.mem.eql(u8, candidate.scope, scope(path)) or !std.mem.eql(u8, candidate.content_sha256, content_hash) or !std.mem.eql(u8, candidate.schema_sha256, schema_hash) or !std.mem.eql(u8, candidate.step, step)) continue;
        if (found != null and !std.mem.eql(u8, found.?.exchange_key, candidate.exchange_key)) return null;
        found = candidate;
    }
    return found;
}
fn contextFile(state: *State, a: std.mem.Allocator, path: []const u8, bytes: []const u8, raw: std.json.Value) !void {
    const witness = try artifact(state, path, bytes);
    var base: Row = .{ .id = path, .family = .exchange_context, .artifact = witness, .disposition = .malformed_capture };
    const context = @import("../e2e/call_context.zig").CallContext.decode(a, bytes) catch |err| {
        if (err == error.OutOfMemory) return err;
        base.diagnostic = @errorName(err);
        try appendRow(state, base);
        return;
    };
    const content = try json(a, context.content);
    const packet = packetFromContent(member(raw, "content").?) orelse {
        base.disposition = .missing_packet;
        try appendRow(state, base);
        return;
    };
    base.request_context = try requestContext(a, packet);
    const native = try nativeFor(state, a, path, content, context.response_schema, context.request_step, context.origin);
    if (native) |known| {
        base.exchange_key = known.exchange_key;
        base.metadata_witness = known.artifact;
    }
    const response_path = if (std.mem.eql(u8, std.fs.path.basename(path), "context.json")) try prefix(a, path, "response.json") else try sibling(a, path, ".context.json", ".response.json");
    const text_path = if (std.mem.eql(u8, std.fs.path.basename(path), "context.json")) try prefix(a, path, "model_output.txt") else try sibling(a, path, ".context.json", ".model_output.txt");
    const output = try modelOutput(state, a, response_path, text_path, false, null);
    base.response = output.raw;
    base.disposition = output.disposition;
    if (output.text) |text| try measureRow(state, a, base, packet, text, context.response_schema, if (native) |known| .{ .contract = known.metadata_contract, .fields = known.field_policies, .prose = known.prose_fields, .sources = known.original_sources, .exact_scope = known.exact_scope, .members = known.members } else .{}) else try appendRow(state, base);
}
fn describedFile(state: *State, a: std.mem.Allocator, path: []const u8, bytes: []const u8, raw: std.json.Value, is_record: bool) !void {
    var base: Row = .{ .id = path, .family = if (is_record) .debugger_request else .calibration_call, .artifact = try artifact(state, path, bytes), .disposition = .malformed_capture };
    const description = member(raw, "description") orelse {
        try appendRow(state, base);
        return;
    };
    const packet = packetFromContent(member(description, "content") orelse .null) orelse {
        base.disposition = .missing_packet;
        try appendRow(state, base);
        return;
    };
    base.request_context = try requestContext(a, packet);
    const schema = string(member(description, "schema")) orelse {
        try appendRow(state, base);
        return;
    };
    const run = string(member(raw, "run")) orelse {
        try appendRow(state, base);
        return;
    };
    const id = string(member(raw, "id")) orelse {
        try appendRow(state, base);
        return;
    };
    base.exchange_key = try std.fmt.allocPrint(a, "{s}:{s}", .{ run, id });
    const description_version = version(description) orelse {
        try appendRow(state, base);
        return;
    };
    // This is a closed diagnostic projection of retained historical metadata,
    // never a migrated production request or an adopted compatibility reader.
    const contract = metadataContract(description_version) orelse {
        base.disposition = .unsupported_capture_version;
        base.diagnostic = description_version;
        try appendRow(state, base);
        return;
    };
    const current: ?@import("../../../src/domain/model_request_description.zig").Description = if (contract == .current_v8) try @import("../../../src/domain/model_request_description.zig").Description.decode(a, try json(a, description)) else null;
    const policies = if (current) |known| known.field_policies else if (member(description, "field_policies")) |value| try strict.decode([]const @import("../../../src/domain/model_text_field.zig").Binding, a, try json(a, value), .{ .maximum_depth = 64 }) else &.{};
    const prose = if (current) |known| known.prose_fields else if (member(description, "prose_fields")) |value| try strict.decode([]const @import("../../../src/domain/model_text_wire.zig").ProseField, a, try json(a, value), .{ .maximum_depth = 64 }) else &.{};
    const sources = if (current) |known| known.original_sources else if (member(description, "original_sources")) |value| try strict.decode([]const @import("../../../src/domain/model_text_wire.zig").SourceText, a, try json(a, value), .{ .maximum_depth = 64 }) else null;
    const suffix = if (is_record) ".request.json" else ".call.json";
    const simple = std.mem.eql(u8, std.fs.path.basename(path), if (is_record) "request.json" else "call.json");
    const response_path = if (simple) try prefix(a, path, "response.json") else try sibling(a, path, suffix, ".response.json");
    const text_path = if (simple) try prefix(a, path, "model-text.txt") else try sibling(a, path, suffix, ".model-text.txt");
    const output = try modelOutput(state, a, response_path, text_path, is_record, id);
    base.response = output.raw;
    base.disposition = output.disposition;
    // Call exports retain the exact extracted provider text, independently of
    // provider decoding support. This is not its normalized parsed projection.
    const exported = if (!is_record) string(member(member(raw, "validation") orelse .null, "model_text")) else null;
    var embedded_text: ?[]const u8 = null;
    if (!is_record) if (string(member(raw, "response"))) |response_bytes| {
        if (base.response == null) base.response = .{ .path = path, .sha256 = try c.hash(a, response_bytes), .pointer = "/response" };
        embedded_text = exported;
        if (embedded_text == null) {
            const body = strict.parse(a, response_bytes, .{ .maximum_depth = 128 }, false, null) catch |err| {
                if (err == error.OutOfMemory) return err;
                base.disposition = .malformed_capture;
                try appendRow(state, base);
                return;
            };
            embedded_text = try providerText(a, body.value);
        }
    };
    const text = output.text orelse embedded_text orelse if (output.raw != null) exported else null;
    if (text) |retained| try measureRow(state, a, base, packet, retained, schema, .{ .contract = contract, .fields = policies, .prose = prose, .sources = sources, .exact_scope = if (current) |known| known.exact_scope else null, .members = if (current) |known| known.members else &.{} }) else try appendRow(state, base);
}
fn checkedHash(a: std.mem.Allocator, value: std.json.Value, name: []const u8, bytes: []const u8) !void {
    if (member(value, name)) |declared| {
        const expected = string(declared) orelse return error.InvalidCaptureProjection;
        if (!std.mem.eql(u8, expected, try c.hash(a, bytes))) return error.InvalidCaptureProjection;
    }
}
fn embeddedChild(state: *State, a: std.mem.Allocator, source: Artifact, capture: std.json.Value, sample: bool) !void {
    const base: Row = .{ .id = try std.fmt.allocPrint(a, "{s}#{s}", .{ source.path, source.pointer.? }), .family = .embedded_capture, .artifact = source, .disposition = .measured };
    if (!sample) {
        const context_bytes = string(member(capture, "context")) orelse return error.InvalidCaptureProjection;
        try checkedHash(a, capture, "context_sha256", context_bytes);
        const context = try @import("../e2e/call_context.zig").CallContext.decode(a, context_bytes);
        const content = try strict.parse(a, try json(a, context.content), .{ .maximum_depth = 128 }, false, null);
        const packet = packetFromContent(content.value) orelse return error.InvalidCaptureProjection;
        const output = string(member(capture, "raw_output")) orelse return error.InvalidCaptureProjection;
        try checkedHash(a, capture, "raw_output_sha256", output);
        try measureRow(state, a, base, packet, output, context.response_schema, .{});
        return;
    }
    const packet = string(member(capture, "packet")) orelse return error.InvalidCaptureProjection;
    const output = string(member(capture, "output")) orelse return error.InvalidCaptureProjection;
    const schema = string(member(capture, "schema")) orelse return error.InvalidCaptureProjection;
    try checkedHash(a, capture, "packet_sha256", packet);
    try checkedHash(a, capture, "output_sha256", output);
    try checkedHash(a, capture, "schema_sha256", schema);
    const policies = try strict.decode([]const @import("../../../src/domain/model_text_field.zig").Binding, a, try json(a, member(capture, "field_policies") orelse return error.InvalidCaptureProjection), .{ .maximum_depth = 64 });
    const prose = try strict.decode([]const @import("../../../src/domain/model_text_wire.zig").ProseField, a, try json(a, member(capture, "prose_fields") orelse return error.InvalidCaptureProjection), .{ .maximum_depth = 64 });
    const sources = if (string(member(capture, "description"))) |description_bytes| sources: {
        if (std.mem.eql(u8, string(member(capture, "description_version")) orelse "", "model-request-debug/v8")) {
            const description = try @import("../../../src/domain/model_request_description.zig").Description.decode(a, description_bytes);
            break :sources description.original_sources;
        }
        break :sources null;
    } else null;
    const contract = metadataContract(string(member(capture, "description_version")) orelse "") orelse .unavailable;
    const current: ?@import("../../../src/domain/model_request_description.zig").Description = if (contract == .current_v8) try @import("../../../src/domain/model_request_description.zig").Description.decode(a, string(member(capture, "description")) orelse return error.InvalidCaptureProjection) else null;
    if (current) |known| {
        if (!std.mem.eql(u8, schema, known.schema) or !@import("../../../src/domain/model_text_field.zig").same(policies, known.field_policies) or !@import("../../../src/domain/model_text_wire.zig").sameProseFields(prose, known.prose_fields)) return error.InvalidCaptureProjection;
    }
    try measureRow(state, a, base, packet, output, schema, .{ .contract = contract, .fields = policies, .prose = prose, .sources = sources, .exact_scope = if (current) |known| known.exact_scope else null, .members = if (current) |known| known.members else &.{} });
}
fn embeddedChildObserved(state: *State, a: std.mem.Allocator, source: Artifact, capture: std.json.Value, sample: bool) !void {
    embeddedChild(state, a, source, capture, sample) catch |err| {
        if (err == error.OutOfMemory) return err;
        try appendRow(state, .{ .id = try std.fmt.allocPrint(a, "{s}#{s}", .{ source.path, source.pointer.? }), .family = .embedded_capture, .artifact = source, .disposition = .malformed_capture, .diagnostic = @errorName(err) });
    };
}
fn embedded(state: *State, a: std.mem.Allocator, path: []const u8, bytes: []const u8, raw: std.json.Value) !void {
    const witness = try artifact(state, path, bytes);
    if (member(raw, "runs")) |runs| {
        if (runs != .array) return error.InvalidCaptureProjection;
        for (runs.array.items, 0..) |run, run_index| {
            const maybe_captures = member(run, "captures");
            if (maybe_captures == null or maybe_captures.? != .array) {
                state.counts.unsupported_embedded_capture_denominator_unknown += 1;
                var source = witness;
                source.pointer = try std.fmt.allocPrint(a, "/runs/{d}", .{run_index});
                try appendRow(state, .{ .id = try std.fmt.allocPrint(a, "{s}#{s}", .{ path, source.pointer.? }), .family = .embedded_capture, .artifact = source, .disposition = .malformed_capture, .diagnostic = "Run capture array unavailable; child denominator unknown" });
                continue;
            }
            const captures = maybe_captures.?;
            for (captures.array.items, 0..) |capture, capture_index| {
                var source = witness;
                source.pointer = try std.fmt.allocPrint(a, "/runs/{d}/captures/{d}", .{ run_index, capture_index });
                try embeddedChildObserved(state, a, source, capture, false);
            }
        }
    } else if (member(raw, "samples")) |samples| {
        if (samples != .array) {
            state.counts.unsupported_embedded_capture_denominator_unknown += 1;
            return error.InvalidCaptureProjection;
        }
        for (samples.array.items, 0..) |sample, index| {
            var source = witness;
            source.pointer = try std.fmt.allocPrint(a, "/samples/{d}", .{index});
            try embeddedChildObserved(state, a, source, sample, true);
        }
    } else {
        state.counts.unsupported_embedded_capture_denominator_unknown += 1;
        return error.InvalidCaptureProjection;
    }
}
fn providerPacket(raw: std.json.Value) ?[]const u8 {
    const messages = member(raw, "messages") orelse return null;
    if (messages != .array) return null;
    var found: ?[]const u8 = null;
    for (messages.array.items) |message| {
        if (!std.mem.eql(u8, string(member(message, "role")) orelse continue, "user")) continue;
        const content = member(message, "content") orelse return null;
        const packet: ?[]const u8 = if (content == .string) content.string else if (content == .array and content.array.items.len != 0) string(member(content.array.items[0], "text")) else null;
        if (found != null) return null;
        found = packet orelse return null;
    }
    return found;
}
fn providerSchema(a: std.mem.Allocator, raw: std.json.Value) !?[]const u8 {
    if (member(raw, "response_format")) |format| if (member(format, "json_schema")) |js| if (member(js, "schema")) |schema| return try json(a, schema);
    if (member(raw, "outputConfig")) |config| if (member(config, "textFormat")) |format| if (member(format, "structure")) |structure| if (member(structure, "jsonSchema")) |schema| return string(member(schema, "schema"));
    return null;
}
fn providerFile(state: *State, a: std.mem.Allocator, path: []const u8, bytes: []const u8, raw: std.json.Value) !void {
    const simple = std.mem.eql(u8, std.fs.path.basename(path), "request.json");
    const context_path = if (simple) try prefix(a, path, "context.json") else try sibling(a, path, ".request.json", ".context.json");
    const call_path = if (simple) try prefix(a, path, "call.json") else try sibling(a, path, ".request.json", ".call.json");
    if (state.paths.contains(context_path) or state.paths.contains(call_path)) {
        state.counts.member_artifacts += 1;
        return;
    }
    var base: Row = .{ .id = path, .family = .provider_request, .artifact = try artifact(state, path, bytes), .disposition = .missing_packet };
    const packet = providerPacket(raw) orelse {
        try appendRow(state, base);
        return;
    };
    base.request_context = try requestContext(a, packet);
    const response_path = if (simple) try prefix(a, path, "response.json") else try sibling(a, path, ".request.json", ".response.json");
    const text_path = if (simple) try prefix(a, path, "model_output.txt") else try sibling(a, path, ".request.json", ".model-text.txt");
    const output = try modelOutput(state, a, response_path, text_path, false, null);
    base.response = output.raw;
    base.disposition = output.disposition;
    if (output.text) |text| try measureRow(state, a, base, packet, text, try providerSchema(a, raw), .{}) else try appendRow(state, base);
}
fn responseFile(state: *State, a: std.mem.Allocator, path: []const u8, bytes: []const u8) !void {
    const simple = std.mem.eql(u8, std.fs.path.basename(path), "response.json");
    const suffix = if (simple) "response.json" else ".response.json";
    const root = path[0 .. path.len - suffix.len];
    for (if (simple) &[_][]const u8{ "request.json", "context.json", "call.json" } else &[_][]const u8{ ".request.json", ".context.json", ".call.json" }) |ending| if (state.paths.contains(try std.fmt.allocPrint(a, "{s}{s}", .{ root, ending }))) {
        state.counts.member_artifacts += 1;
        return;
    };
    try appendRow(state, .{ .id = path, .family = .orphan_response, .artifact = try artifact(state, path, bytes), .disposition = .missing_packet, .diagnostic = "Response retained without a captured request/description" });
}
fn outputTextPath(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".model-text.txt") or std.mem.endsWith(u8, path, ".model_output.txt") or std.mem.eql(u8, std.fs.path.basename(path), "model_output.txt");
}
fn textArtifact(state: *State, path: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(state.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const simple = std.mem.eql(u8, std.fs.path.basename(path), "model_output.txt");
    const suffix = if (simple) "model_output.txt" else if (std.mem.endsWith(u8, path, ".model-text.txt")) ".model-text.txt" else ".model_output.txt";
    const base = path[0 .. path.len - suffix.len];
    for (if (simple) &[_][]const u8{ "context.json", "request.json", "call.json", "response.json" } else &[_][]const u8{ ".context.json", ".request.json", ".call.json", ".response.json" }) |ending| {
        if (state.paths.contains(try std.fmt.allocPrint(a, "{s}{s}", .{ base, ending }))) {
            state.counts.member_artifacts += 1;
            return;
        }
    }
    const bytes = files.read(state.io, a, .cwd(), path) catch |err| {
        if (err == error.OutOfMemory) return err;
        try appendRow(state, .{ .id = path, .family = .orphan_text_output, .artifact = .{ .path = path }, .disposition = .input_unavailable, .diagnostic = @errorName(err) });
        return;
    };
    try appendRow(state, .{ .id = path, .family = .orphan_text_output, .artifact = try artifact(state, path, bytes), .disposition = .missing_packet, .diagnostic = "Retained model text has no captured request/context/response sibling" });
}
fn guidanceResource(value: std.json.Value) bool {
    for ([_][]const u8{ "version", "schema", "run", "id", "request", "response", "description" }) |reserved| if (member(value, reserved) != null) return false;
    return guidanceDictionary(value);
}
fn guidanceDictionary(value: std.json.Value) bool {
    if (value != .object or value.object.count() == 0) return false;
    for (value.object.values()) |item| if (item != .string and !guidanceDictionary(item)) return false;
    return true;
}
fn jsonFile(state: *State, path: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(state.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = files.read(state.io, a, .cwd(), path) catch |err| {
        if (err == error.OutOfMemory) return err;
        try appendRow(state, .{ .id = path, .family = .unsupported_request, .artifact = .{ .path = path }, .disposition = .input_unavailable, .diagnostic = @errorName(err) });
        return;
    };
    const request_like = std.mem.endsWith(u8, path, ".request.json") or std.mem.endsWith(u8, path, ".call.json") or std.mem.endsWith(u8, path, "context.json") or std.mem.eql(u8, std.fs.path.basename(path), "request.json");
    const parsed = strict.parse(a, bytes, .{ .maximum_depth = 128 }, false, null) catch |err| {
        if (err == error.OutOfMemory) return err;
        if (request_like or std.mem.endsWith(u8, path, ".response.json") or std.mem.eql(u8, std.fs.path.basename(path), "response.json")) try appendRow(state, .{ .id = path, .family = .unsupported_request, .artifact = try artifact(state, path, bytes), .disposition = .malformed_capture, .diagnostic = @errorName(err) }) else state.counts.preparation_or_other_json += 1;
        return;
    };
    const raw = parsed.value;
    const v = version(raw) orelse "";
    if (std.mem.eql(u8, v, "model-call-evidence/v1")) return contextFile(state, a, path, bytes, raw);
    if (std.mem.startsWith(u8, v, "request-replay/")) {
        if (!std.mem.eql(u8, v, "request-replay/v4") and !std.mem.eql(u8, v, "request-replay/v6")) {
            try appendRow(state, .{ .id = path, .family = .debugger_request, .artifact = try artifact(state, path, bytes), .disposition = .unsupported_capture_version, .diagnostic = v });
            return;
        }
        return describedFile(state, a, path, bytes, raw, true);
    }
    if ((std.mem.endsWith(u8, path, ".call.json") or std.mem.eql(u8, std.fs.path.basename(path), "call.json")) and member(raw, "description") != null) return describedFile(state, a, path, bytes, raw, false);
    if (std.mem.eql(u8, v, "representation-admission-capture/v3") or std.mem.eql(u8, v, "exact-value-retained/v1")) return embedded(state, a, path, bytes, raw);
    if ((std.mem.endsWith(u8, path, ".request.json") or std.mem.eql(u8, std.fs.path.basename(path), "request.json")) and member(raw, "messages") != null) return providerFile(state, a, path, bytes, raw);
    if (std.mem.endsWith(u8, path, ".response.json") or std.mem.eql(u8, std.fs.path.basename(path), "response.json")) return responseFile(state, a, path, bytes);
    if (std.mem.endsWith(u8, path, ".context.json") and guidanceResource(raw)) {
        state.counts.preparation_or_other_json += 1;
        return;
    }
    if (request_like) try appendRow(state, .{ .id = path, .family = .unsupported_request, .artifact = try artifact(state, path, bytes), .disposition = .unsupported_capture_version, .diagnostic = if (v.len != 0) v else "No supported captured-request projection" }) else state.counts.preparation_or_other_json += 1;
}
fn finalize(state: *State) !void {
    var exchanges: std.StringHashMap(usize) = .init(state.allocator);
    var payloads: std.StringHashMap(usize) = .init(state.allocator);
    state.counts.captures = state.rows.items.len;
    for (state.rows.items, 0..) |*capture, index| {
        if (capture.exchange_key) |key| {
            if (exchanges.get(key)) |previous| {
                const prior = state.rows.items[previous];
                if (capture.payload_sha256 != null and prior.payload_sha256 != null and std.mem.eql(u8, capture.payload_sha256.?, prior.payload_sha256.?)) {
                    capture.duplicate_of = prior.id;
                    state.counts.duplicate_captures += 1;
                } else if (capture.payload_sha256 != null and prior.payload_sha256 == null) {
                    try exchanges.put(key, index);
                } else if (capture.payload_sha256 != null and prior.payload_sha256 != null) {
                    state.counts.exchange_identity_conflicts += 1;
                    capture.diagnostic = try std.fmt.allocPrint(state.allocator, "Same explicit exchange identity as {s}, different retained payload; not deduplicated", .{prior.id});
                }
            } else {
                try exchanges.put(key, index);
                state.counts.unique_known_exchanges += 1;
            }
        } else state.counts.unknown_exchange_identity += 1;
        if (capture.payload_sha256) |hash_value| {
            if (payloads.get(hash_value)) |prior| capture.same_payload_as = state.rows.items[prior].id else try payloads.put(hash_value, index);
        }
        if (capture.request_context) |context| {
            if (context.state == .exact_values) state.counts.exact_context_captures += 1;
            if (context.state == .invalid_packet) state.counts.invalid_request_context += 1;
        } else state.counts.unavailable_request_context += 1;
        if (capture.disposition != .measured) state.counts.unsupported_or_missing_captures += 1;
        if (capture.measurement) |measurement| {
            if (measurement.state == .measured) state.counts.measured_captures += 1;
            if (measurement.occurrence_count != 0) state.counts.exact_context_with_response += 1;
            state.counts.measured_fields += measurement.fields.len;
            for (measurement.fields) |field| {
                if (field.binding == .missing or field.binding == .invalid) state.counts.missing_binding_fields += 1;
                if (field.native_field == null) state.counts.unavailable_native_field_metadata += 1;
                if (field.proposed_composition == .invalid) state.counts.invalid_proposed_composition += 1;
                state.counts.original_typed_exact_references += field.typed_exact_references.len;
                if (field.historical_typed_counterfactual != null) state.counts.typed_counterfactual_fields += 1;
                for (field.plain_runs) |run| {
                    if (run.result.state == .matched) state.counts.matched_plain_runs += 1;
                    if (run.result.state == .ambiguous) state.counts.ambiguous_plain_runs += 1;
                    if (run.result.state == .unavailable_boundary_context) state.counts.unavailable_boundary_context_runs += 1;
                    state.counts.unbound_plain_matches += run.result.unbound_matches.len;
                }
            }
        }
    }
}

test "prototype native metadata requires exact call origin across prompt and evidence layouts" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var state: State = .{ .io = std.testing.io, .allocator = a, .paths = .init(a) };
    const prompt_path = "captures/run/project/specs/feature/logs/prompts/RUN-A/0001.log";
    const context_path = "captures/run/evidence/generation/call-000002/context.json";
    const content = "MOCK identical model-visible content";
    const schema = "MOCK identical selected schema";
    const call1: @import("../../../src/domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const call2: @TypeOf(call1) = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    const native: Native = .{
        .scope = scope(prompt_path),
        .call_id = "request-2-inference-1",
        .content_sha256 = try c.hash(a, content),
        .schema_sha256 = try c.hash(a, schema),
        .step = "records",
        .field_policies = &.{.{ .field = .ac_then, .path = &.{.{ .property = "value" }} }},
        .prose_fields = &.{},
        .artifact = .{ .path = prompt_path },
        .exchange_key = "RUN-A:request-2-inference-1",
    };
    try state.native.append(a, native);
    // A byte-identical request from a different call cannot supply provenance.
    try std.testing.expect((try nativeFor(&state, a, context_path, content, schema, "records", call1)) == null);
    const exact = try nativeFor(&state, a, context_path, content, schema, "records", call2);
    try std.testing.expect(exact != null);
    try std.testing.expectEqualStrings(native.exchange_key, exact.?.exchange_key);
    try std.testing.expect((try nativeFor(&state, a, context_path, "MOCK different content", schema, "records", call2)) == null);
    try std.testing.expect((try nativeFor(&state, a, "captures/other/evidence/generation/call-000002/context.json", content, schema, "records", call2)) == null);
    var another_run = native;
    another_run.exchange_key = "RUN-B:request-2-inference-1";
    try state.native.append(a, another_run);
    try std.testing.expect((try nativeFor(&state, a, context_path, content, schema, "records", call2)) == null);
}

test "prototype guidance inventory cannot hide unknown or malformed capture frames" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Case = struct { bytes: []const u8, guidance: bool };
    for ([_]Case{
        .{ .bytes = "{\"purpose\":\"field meanings\",\"content.kind\":{\"fact\":\"source fact\"}}", .guidance = true },
        .{ .bytes = "{\"version\":\"model-call-evidence/v99\",\"content\":\"malformed\"}", .guidance = false },
        .{ .bytes = "{\"schema\":\"unknown/v1\",\"purpose\":\"capture\"}", .guidance = false },
        .{ .bytes = "{\"version\":9,\"purpose\":\"capture\"}", .guidance = false },
        .{ .bytes = "{\"run\":\"run1\",\"id\":\"call1\"}", .guidance = false },
    }) |case| {
        const parsed = try strict.parse(a, case.bytes, .{ .maximum_depth = 128 }, false, null);
        try std.testing.expectEqual(case.guidance, guidanceResource(parsed.value));
    }
}

test "prototype embedded malformed child does not hide later retained captures" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var state: State = .{ .io = std.testing.io, .allocator = a, .paths = .init(a) };
    const bytes = "{\"samples\":[{\"packet\":3},{\"packet\":\"{}\",\"output\":\"{}\",\"schema\":\"{}\",\"field_policies\":[],\"prose_fields\":[]}]}";
    const parsed = try strict.parse(a, bytes, .{ .maximum_depth = 128 }, false, null);
    try embedded(&state, a, "captures/retained.json", bytes, parsed.value);
    try std.testing.expectEqual(@as(usize, 2), state.rows.items.len);
    try std.testing.expectEqual(.malformed_capture, state.rows.items[0].disposition);
    try std.testing.expectEqualStrings("/samples/0", state.rows.items[0].artifact.pointer.?);
    try std.testing.expectEqual(.measured, state.rows.items[1].disposition);
    try std.testing.expectEqual(.no_exact_context, state.rows.items[1].measurement.?.state);
    try std.testing.expectEqualStrings("/samples/1", state.rows.items[1].artifact.pointer.?);
}
