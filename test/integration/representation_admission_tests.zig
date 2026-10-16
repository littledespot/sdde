//! Offline replay of exact retained development bytes. No provider, workflow,
//! generation input, current request origin, publication or semantic authority.
const std = @import("std");
const strict = @import("../../src/domain/strict_json.zig");
const envelope = @import("../../src/domain/model_envelope.zig");
const codec = @import("../../src/domain/model_candidate_json.zig");
const schemas = @import("../../src/domain/model_result_schema.zig");
const wire = @import("../../src/domain/model_text_wire.zig");
const text = @import("../../src/domain/typed_text.zig");
const policy = @import("../../src/domain/text_field_policy.zig");

const Step = union(enum) { property: []const u8, index: usize };
const Expected = enum { admitted, reference_only, prohibited_exact, embedded_insertion_syntax };
const Selection = struct {
    from: enum { model_output, request_user },
    path: []const Step,
    field: policy.Field,
    expected: Expected,
    value_sha256: []const u8,
};
const Capture = struct {
    call: u32,
    raw_output: []const u8,
    raw_output_sha256: []const u8,
    context: []const u8,
    context_sha256: []const u8,
    construct_exact_copy: bool,
    expected_protocol_rejection: bool,
    values: []const Selection,
    request: []const u8,
    request_sha256: []const u8,
    response: []const u8,
    response_sha256: []const u8,
    outcome: []const u8,
    outcome_sha256: []const u8,
};
const Source = struct { project_path: []const u8, bytes: []const u8, sha256: []const u8 };
const Run = struct { run_id: []const u8, case_id: []const u8, sources: []const Source, captures: []const Capture };
const Counts = struct { runs: u32 = 0, captures: u32 = 0, values: u32 = 0, reference_only: u32 = 0, prohibited_exact: u32 = 0, embedded_insertion_syntax: u32 = 0, admitted: u32 = 0 };
const Fixture = struct {
    schema: enum { @"representation-admission-capture/v2" },
    scope: enum { offline_native_admission_replay },
    authority: enum { none },
    runs: []const Run,
    expected: Counts,
};

fn hash(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}
fn member(value: std.json.Value, key: []const u8) !std.json.Value {
    if (value != .object) return error.InvalidReplayFixture;
    return value.object.get(key) orelse error.InvalidReplayFixture;
}
fn string(value: std.json.Value) ![]const u8 {
    if (value != .string) return error.InvalidReplayFixture;
    return value.string;
}
fn selected(root: std.json.Value, path: []const Step) !std.json.Value {
    var current = root;
    for (path) |step| current = switch (step) {
        .property => |name| try member(current, name),
        .index => |index| if (current == .array and index < current.array.items.len) current.array.items[index] else return error.InvalidReplayFixture,
    };
    return current;
}

/// Inspect compiled native schema metadata, not candidate/prompt text. This is
/// the original schema's singleton construction fact; it does not invent an ID.
fn constructedCopy(node: *const schemas.Node) bool {
    switch (node.*) {
        .object => |properties| {
            if (schemas.discriminator(node)) |tag| if (std.mem.eql(u8, tag, "exact_copy") and schemas.findProperty(properties, "claim_id") == null) return true;
            for (properties) |property| if (constructedCopy(property.schema)) return true;
        },
        .array => |array| return constructedCopy(array.items),
        .one_of => |variants| for (variants) |variant| if (constructedCopy(variant)) return true,
        else => {},
    }
    return false;
}

fn sourceWitnesses(a: std.mem.Allocator, run: Run, packet: std.json.Value) ![]const wire.SourceText {
    const sources = try member(packet, "sources");
    if (sources != .array or sources.array.items.len != run.sources.len) return error.InvalidReplayFixture;
    const result = try a.alloc(wire.SourceText, sources.array.items.len);
    for (sources.array.items, result) |source, *witness| {
        const id = try member(source, "id");
        if (id != .number_string) return error.InvalidReplayFixture;
        const ordinal = try @import("../../src/domain/model_payload_schema.zig").exactInteger(id.number_string);
        const bytes = try string(try member(source, "text"));
        var matches: usize = 0;
        for (run.sources) |original| if (std.mem.eql(u8, bytes, original.bytes)) {
            matches += 1;
        };
        if (matches != 1 or ordinal <= 0 or ordinal > std.math.maxInt(u32)) return error.InvalidReplayFixture;
        witness.* = .{ .source_id = .{ .ordinal = @intCast(ordinal) }, .bytes = bytes };
    }
    if (!wire.validSources(result)) return error.InvalidReplayFixture;
    return result;
}

/// Selections are individual model-text field values, whereas BusinessText's
/// native codec contract owns the enclosing segments property. This transient
/// wrapper restores that owning field without changing any captured bytes.
fn decodeSelectedText(a: std.mem.Allocator, bytes: []const u8) !text.BusinessText {
    const wrapped = try std.fmt.allocPrint(a, "{{\"segments\":{s}}}", .{bytes});
    return codec.decode(text.BusinessText, a, wrapped);
}

fn capturedConstruction(a: std.mem.Allocator, packet: std.json.Value, construct: bool) ![]const schemas.IntegerChoice {
    if (!construct) return &.{};
    const tokens = try member(packet, "preserved_tokens");
    if (tokens != .array or tokens.array.items.len != 1) return error.InvalidReplayFixture;
    const claim = try member(tokens.array.items[0], "claim_id");
    if (claim != .number_string) return error.InvalidReplayFixture;
    const id = try @import("../../src/domain/model_payload_schema.zig").exactInteger(claim.number_string);
    if (id <= 0 or id > std.math.maxInt(u32)) return error.InvalidReplayFixture;
    const allowed = try a.alloc(i64, 1);
    allowed[0] = id;
    const choices = try a.alloc(schemas.IntegerChoice, 1);
    choices[0] = .{ .target = .{ .tagged = .{ .kind = "exact_copy", .field = "claim_id" } }, .allowed = allowed, .singleton = .construct };
    return choices;
}

test "test.integration.representation_admission all retained F10 and F11 values reject at native owners and prose controls admit" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try strict.decode(Fixture, a, @embedFile("../calibration/representation-admission/retained.json"), .{ .maximum_depth = 64 });
    const required_runs = [_][]const u8{
        "2026-10-13T22-02-37Z-b20ce81708023ac1030af300c845affa",
        "2026-10-13T22-03-58Z-facbd733ec967b7453a85ef64d4bb571",
        "2026-10-15T20-54-21Z-5f6e903390f38938113712b53a359de4",
        "2026-10-15T21-09-33Z-3a7ceed77cb237531019300e1005152d",
        "2026-10-15T22-18-35Z-a8740d575019326cb5b63f994c3dc426",
        "2026-10-16T05-20-15Z-44b2ac5e19cbf8d2ade89b149aed73c8",
    };
    const required_calls = [_][]const u32{ &.{ 7, 8, 11, 13, 40 }, &.{ 8, 10, 11 }, &.{ 9, 10, 12, 13 }, &.{ 7, 8, 10, 11, 12 }, &.{ 7, 8, 9, 10, 11, 36 }, &.{ 7, 8 } };
    try std.testing.expectEqual(required_runs.len, fixture.runs.len);
    var counts: Counts = .{};
    for (fixture.runs, required_runs, required_calls) |run, required_run, calls| {
        counts.runs += 1;
        try std.testing.expectEqualStrings(required_run, run.run_id);
        try std.testing.expectEqual(calls.len, run.captures.len);
        for (run.sources) |source| {
            try @import("../harness/contracts.zig").path(source.project_path);
            try std.testing.expectEqualStrings(source.sha256, &hash(source.bytes));
        }
        for (run.captures, calls) |capture, required_call| {
            var stage: enum { identities, context, sources, raw_output, schema, protocol, field_selection, native_decode, field_validation } = .identities;
            errdefer std.debug.print("retained representation replay failed: run {s}, call {d}, boundary {s}\n", .{ run.run_id, capture.call, @tagName(stage) });
            counts.captures += 1;
            try std.testing.expectEqual(required_call, capture.call);
            try std.testing.expectEqualStrings(capture.raw_output_sha256, &hash(capture.raw_output));
            try std.testing.expectEqualStrings(capture.context_sha256, &hash(capture.context));
            try std.testing.expectEqualStrings(capture.request_sha256, &hash(capture.request));
            try std.testing.expectEqualStrings(capture.response_sha256, &hash(capture.response));
            try std.testing.expectEqualStrings(capture.outcome_sha256, &hash(capture.outcome));
            // CallContext has no historical Description-version reader. These
            // are the original, unchanged transport context bytes only.
            stage = .context;
            const context = try @import("../harness/e2e/call_context.zig").CallContext.decode(a, capture.context);
            try std.testing.expectEqual(capture.call, context.call);
            var user_bytes: ?[]const u8 = null;
            for (context.content) |content| if (content == .user) {
                if (user_bytes != null) return error.InvalidReplayFixture;
                user_bytes = content.user;
            };
            var user = try strict.parse(a, user_bytes orelse return error.InvalidReplayFixture, .{ .maximum_depth = 64 }, false, null);
            defer user.deinit();
            if (user.value != .object) return error.InvalidReplayFixture;
            const packet = user.value.object.get("input") orelse user.value;
            stage = .sources;
            const sources = try sourceWitnesses(a, run, packet);
            stage = .raw_output;
            var raw = try envelope.parseContent(a, capture.raw_output, null);
            defer raw.deinit();
            stage = .schema;
            var schema_adapter: @import("../../src/adapters/parsers/model_result_schemas.zig").Adapter = .{};
            const schema = schema_adapter.compiler().compileSelected(a, context.response_schema) catch |err| {
                std.debug.print("retained selected schema compiler rejected: {s}\n", .{@errorName(err)});
                return err;
            };
            try std.testing.expectEqual(capture.construct_exact_copy, constructedCopy(schema.root()));
            stage = .protocol;
            const protocol_issue = try wire.checkValue(a, raw.parsed.value, schema.root(), sources);
            try std.testing.expectEqual(capture.expected_protocol_rejection, protocol_issue != null);
            const choices = try capturedConstruction(a, packet, capture.construct_exact_copy);
            for (capture.values) |selection| {
                stage = .field_selection;
                errdefer std.debug.print("retained representation field failed: {s}\n", .{@tagName(selection.field)});
                counts.values += 1;
                const raw_value = try selected(if (selection.from == .model_output) raw.parsed.value else user.value, selection.path);
                const bytes = try std.json.Stringify.valueAlloc(a, raw_value, .{});
                try std.testing.expectEqualStrings(selection.value_sha256, &hash(bytes));
                const constructed = try codec.constructBound(a, bytes, choices);
                stage = .native_decode;
                const value = try decodeSelectedText(a, constructed);
                stage = .field_validation;
                const composition_issue = text.composition(text.BusinessSegment, selection.field, value.segments);
                const issue: ?text.Issue = if (composition_issue) |failure| failure else try text.wireCompositionSources(text.BusinessSegment, a, sources, selection.field, value.segments);
                const actual: Expected = if (issue) |failure| switch (failure.reason) {
                    .reference_only => .reference_only,
                    .prohibited_exact => .prohibited_exact,
                    .embedded_insertion_syntax => .embedded_insertion_syntax,
                    else => return error.UnexpectedNativeAdmissionIssue,
                } else .admitted;
                if (actual != selection.expected) std.log.err("retained replay {s} call {d} field {s}: expected {s}, got {s}", .{ run.run_id, capture.call, @tagName(selection.field), @tagName(selection.expected), @tagName(actual) });
                try std.testing.expectEqual(selection.expected, actual);
                switch (actual) {
                    .reference_only => counts.reference_only += 1,
                    .prohibited_exact => counts.prohibited_exact += 1,
                    .embedded_insertion_syntax => counts.embedded_insertion_syntax += 1,
                    .admitted => counts.admitted += 1,
                }
            }
        }
    }
    const required: Counts = .{ .runs = 6, .captures = 25, .values = 83, .reference_only = 7, .prohibited_exact = 5, .embedded_insertion_syntax = 19, .admitted = 52 };
    try std.testing.expectEqualDeep(required, fixture.expected);
    try std.testing.expectEqualDeep(required, counts);
    const output = ".zig-cache/representation-admission";
    try std.Io.Dir.cwd().createDirPath(std.testing.io, output);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = output ++ "/replay.json", .data = try std.json.Stringify.valueAlloc(a, .{ .schema = "representation-admission-replay/v2", .scope = "offline_mechanical_native_admission", .counts = counts, .provider_calls = 0, .workflow_authority = false, .semantic_quality_assessed = false }, .{ .whitespace = .indent_2 }) });
}

test "test.integration.representation_admission unrelated domains retain real native references inside prose" {
    const prepared_fixture = @import("../../src/test_fixtures/reference_text.zig");
    const native_evidence = @import("../../src/reference_evidence_test.zig");
    const ingest = @import("../../src/reference_ingestion_test.zig").read;
    for ([_][2][]const u8{
        .{ "After a parcel is delivered, notify the sender using https://parcel.example/receipt.", "After delivery, notify the sender using " },
        .{ "When a room reservation is approved, provide https://rooms.example/confirmation to the guest.", "After room approval, provide the guest " },
    }) |example| {
        errdefer std.debug.print("unrelated representation replay failed: source {s}\n", .{example[0]});
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var ids: native_evidence.IdSource = .{};
        const inputs = try native_evidence.prepare(a, &ids, try ingest(a, "requirements.md", example[0]));
        const prepared = try prepared_fixture.prepare(a, inputs);
        defer prepared.deinit();
        try std.testing.expect(prepared.registry.records.len != 0);
        const insertion: text.BusinessSegment = .{ .passive = .{ .passive_literal_id = prepared.registry.records[0].id } };
        const insertion_only = [_]text.BusinessSegment{insertion};
        const scoped: text.Context = .{ .registry = prepared.registry, .current = prepared_fixture.safety.value(prepared.owner), .inputs = inputs, .scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = inputs.chunks.entries[0].id }, .field = .spec_story };
        const raw = try codec.encode(text.BusinessText, a, .{ .segments = &insertion_only });
        const decoded = try codec.decode(text.BusinessText, a, raw);
        const rejected = (try prepared_fixture.validator.checkBusinessIn(a, .{ .registry = scoped.registry, .current = scoped.current, .inputs = inputs, .scopes = &.{scoped.scope}, .field = .spec_story }, decoded)).invalid;
        try std.testing.expectEqual(.reference_only, rejected.reason);
        const fragments = [_]text.BusinessSegment{ .{ .literal = .{ .value = example[1] } }, insertion, .{ .literal = .{ .value = " as the source requires." } } };
        const legitimate = try codec.decode(text.BusinessText, a, try codec.encode(text.BusinessText, a, .{ .segments = &fragments }));
        try std.testing.expect((try prepared_fixture.validator.checkBusinessIn(a, .{ .registry = scoped.registry, .current = scoped.current, .inputs = inputs, .scopes = &.{scoped.scope}, .field = .spec_story }, legitimate)) == .valid);
        const encoded_prose = try std.fmt.allocPrint(a, "The operation returns {s} after completion.", .{raw});
        const encoded = try decodeSelectedText(a, try std.json.Stringify.valueAlloc(a, encoded_prose, .{}));
        const wire_rejected = (try prepared_fixture.validator.checkBusinessIn(a, .{ .registry = scoped.registry, .current = scoped.current, .inputs = inputs, .scopes = &.{scoped.scope}, .field = .spec_story }, encoded)).invalid;
        try std.testing.expectEqual(.embedded_insertion_syntax, wire_rejected.reason);
    }
}

test "test.integration.representation_admission native summary reuse has measured provenance without model manufacture" {
    const admission = @import("../harness/baseline/admission.zig");
    const fixtures = @import("../../src/test_fixtures/reference_reconciliation.zig");
    const native = @import("../../src/application/reference_reconciliation_workflow.zig");
    const owned = @import("../../src/domain/reference_candidate_value.zig");
    const values = @import("../../src/application/pipeline_values.zig");
    const Origin = @import("../../src/domain/model_candidate_origin.zig").Origin;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try @import("../../src/reference_reconciliation_test.zig").prepare(a, &.{"When the gate opens, show `Gate open.`.\n"});
    defer fixture.deinit();
    const origin: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const input = try fixtures.build_input.execute(a, try fixtures.initialize(a, fixture.inputs, fixture.extracted, 8));
    const leaf = (try fixtures.validate_summary.execute(a, .{ .input = input, .source = .{ .origin = origin }, .proposal = .{ .summary = try fixtures.summary(a, input) } }, fixture.context())).valid;
    const initial_owner = try owned.create(a, null);
    initial_owner.payload = .{ .reconciliation_summary = leaf };
    const leaf_value = try values.adopt(a, native.summary_schema, owned.Value, owned.Owner, initial_owner, owned.view, owned.destroy, null);
    defer values.destroy(leaf_value);
    const input_schema = @import("../../src/application/reference_evidence_workflow.zig").inputs_schema;
    const input_value = try values.create(a, input_schema, fixtures.r.evidence.Inputs, fixture.inputs);
    defer values.destroy(input_value);
    var view: @import("../../src/domain/pipeline_data.zig").View = .{};
    view.slots[@intFromEnum(input_schema.key)] = input_value;
    view.slots[@intFromEnum(native.summary_schema.key)] = leaf_value;
    var tracker: admission.Tracker = .init(a);
    defer tracker.deinit();
    try tracker.observe(&view, 1, 1);
    const progress = try fixtures.build_summary.execute(a, try fixtures.assign_summary.execute(a, leaf));
    const next = try fixtures.build_input.execute(a, progress);
    const reused = try (@import("../../src/actions/reference/reuse_reference_reconciliation_summary.zig").Action{ .validator = fixtures.validate_summary.validator }).execute(a, next, fixture.context());
    const checked = (try fixtures.validate_summary.execute(a, reused, fixture.context())).valid;
    const carried_owner = try owned.create(a, owned.view(initial_owner));
    carried_owner.payload = .{ .reconciliation_summary = checked };
    const carried_value = try values.adopt(a, native.summary_schema, owned.Value, owned.Owner, carried_owner, owned.view, owned.destroy, null);
    defer values.destroy(carried_value);
    view.slots[@intFromEnum(native.summary_schema.key)] = carried_value;
    try tracker.observe(&view, 2, 1);
    try tracker.observe(&view, 3, 1);
    const exchanges = [_]admission.Exchange{.{ .call = 1, .origin = origin, .usage = @import("../../src/domain/llm_provider_operation.zig").ProviderUsage.init(10, 2, 12) }};
    const audit = tracker.snapshot(true);
    try admission.validate(a, audit, &exchanges);
    const metric = try admission.measure(audit, &exchanges);
    try std.testing.expectEqual(.measured, metric.status);
    try std.testing.expectEqual(@as(u64, 0), metric.escaped_values);
    try std.testing.expectEqual(@as(u64, 0), metric.unattributed_values);
    try std.testing.expectEqual(@as(?f64, 0), metric.producer_escape_rate);
    try std.testing.expectEqual(@as(usize, 2), audit.checks.len);
    try std.testing.expectEqual(.model, std.meta.activeTag(audit.checks[0].producer));
    try std.testing.expectEqual(.native, std.meta.activeTag(audit.checks[1].producer));
    try std.testing.expectEqual(leaf.input.partition.id.ordinal, audit.checks[1].producer.native.summary_reuse.from_summary.ordinal);
    var changed = try a.dupe(admission.Check, audit.checks);
    changed[0].producer = .{ .unavailable = .missing_model_origin };
    try std.testing.expectError(error.InvalidAdmissionAudit, admission.validate(a, .{ .sources = audit.sources, .checks = changed, .complete = true }, &exchanges));
    changed[0] = audit.checks[0];
    changed[1].producer.native.summary_reuse.source_check = 2;
    try std.testing.expectError(error.InvalidAdmissionAudit, admission.validate(a, .{ .sources = audit.sources, .checks = changed, .complete = true }, &exchanges));
    changed[1] = audit.checks[1];
    changed[1].producer.native.summary_reuse.validation_sha256 = "forged";
    try std.testing.expectError(error.InvalidAdmissionAudit, admission.validate(a, .{ .sources = audit.sources, .checks = changed, .complete = true }, &exchanges));
    // A missing model producer is never inferred native from equal text.
    var unknown: admission.Tracker = .init(a);
    defer unknown.deinit();
    initial_owner.payload.reconciliation_summary.projection.source.origin = null;
    view.slots[@intFromEnum(native.summary_schema.key)] = leaf_value;
    try unknown.observe(&view, 1, 1);
    try std.testing.expectEqual(.unavailable, (try admission.measure(unknown.snapshot(true), &exchanges)).status);
    try std.testing.expectEqual(.unavailable, std.meta.activeTag(unknown.checks.items[0].producer));
    const foreign = [_]admission.Exchange{.{ .call = 1, .origin = .{ .request = .{ .value = 99 }, .attempt = .{ .value = 1 } }, .usage = null }};
    tracker.reconcile(&foreign);
    try std.testing.expectEqual(.missing_model_receipt, tracker.checks.items[0].producer.unavailable);
    try std.testing.expectEqual(.missing_native_parent, tracker.checks.items[1].producer.unavailable);
    try admission.validate(a, tracker.snapshot(true), &foreign);
    try std.testing.expectEqual(.unavailable, (try admission.measure(tracker.snapshot(true), &foreign)).status);
}
