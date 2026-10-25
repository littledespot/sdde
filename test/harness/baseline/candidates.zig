//! Read-only native candidate observations for baseline assessment. These bytes
//! are evaluator evidence, never workflow authority or a generated input.
const std = @import("std");
const data = @import("../../../src/domain/pipeline_data.zig");
const session = @import("../../../src/domain/specification_session.zig");
const generation = @import("../../../src/domain/specification_generation.zig");
const specification = @import("../../../src/domain/specification.zig");
const native = @import("../../../src/application/specification_workflow.zig");
const authority = @import("../../../src/application/required_authority_workflow.zig");
const authority_values = @import("../../../src/application/required_authority_values.zig");
const projection = @import("../../../src/domain/specification_projection.zig");

pub const Snapshot = struct {
    json: []const u8,
    sha256: [64]u8,
    /// Original complete generation only. Corrected/repaired candidates remain
    /// observable, but cannot substitute for the original semantic assessment.
    first_pass: bool,

    pub fn jsonStringify(self: Snapshot, writer: *std.json.Stringify) std.json.Stringify.Error!void {
        try writer.beginObject();
        try writer.objectField("json");
        try writer.write(self.json);
        try writer.objectField("sha256");
        try @import("../../../src/domain/canonical_json.zig").writeByteArray(writer, &self.sha256);
        try writer.objectField("first_pass");
        try writer.write(self.first_pass);
        try writer.endObject();
    }
};

pub const Tracker = struct {
    first: ?Snapshot = null,
    latest: ?Snapshot = null,

    /// Every retained snapshot owns its bytes independently. The allocator must
    /// outlive this tracker; no native view or runner-owned value escapes.
    pub fn deinit(self: *Tracker, a: std.mem.Allocator) void {
        if (self.first) |snapshot| a.free(snapshot.json);
        if (self.latest) |snapshot| a.free(snapshot.json);
        self.* = .{};
    }

    pub fn observe(self: *Tracker, a: std.mem.Allocator, view: *const data.View) !void {
        if (!view.contains(authority.content_schema.key)) return;
        var scratch: std.heap.ArenaAllocator = .init(a);
        defer scratch.deinit();
        const temporary = scratch.allocator();
        const content = try authority_values.read(view, authority.content_schema, .content);
        const current = try native.readSession(view);
        const context = try native.readContext(view);
        const brief_entry = current.units[0] orelse return error.MissingCandidateBrief;
        if (brief_entry.response != .content or brief_entry.response.content != .brief) return error.MissingCandidateBrief;
        const support = @import("../../../src/domain/reference_support.zig").records(context.references);
        const bytes = try std.json.Stringify.valueAlloc(temporary, .{
            .schema = "baseline-native-specification-candidate/v1",
            .native_content = content,
            .native_brief = brief_entry.response.content.brief,
            .native_reference_support = .{
                .state_id = support.items.state_id,
                .sources = context.inputs.corpus.sources,
                .claims = support.items.entries,
                .dispositions = support.dispositions,
                .signals = support.signals,
                .conflicts = support.conflicts,
            },
            .document = try projection.project(temporary, context, content),
            .brief = try projection.brief(temporary, context, brief_entry.response.content.brief),
        }, .{});
        try self.retain(a, bytes, firstPass(current));
    }

    fn retain(self: *Tracker, a: std.mem.Allocator, json: []const u8, first_pass: bool) !void {
        if (self.latest) |latest| {
            if (latest.first_pass == first_pass and std.mem.eql(u8, latest.json, json)) return;
        }
        const latest_json = try a.dupe(u8, json);
        errdefer a.free(latest_json);
        const initial_json = if (self.first == null) try a.dupe(u8, json) else null;
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(json, &digest, .{});
        const sha256 = std.fmt.bytesToHex(digest, .lower);
        if (initial_json) |bytes| self.first = .{ .json = bytes, .sha256 = sha256, .first_pass = first_pass };
        if (self.latest) |previous| a.free(previous.json);
        self.latest = .{ .json = latest_json, .sha256 = sha256, .first_pass = first_pass };
    }
};

/// Inspect native candidate lineage only. Combined record origins are a
/// projection of each original batch, so the retained batches are inspected
/// individually rather than treating normal assembly as a repair.
pub fn firstPass(current: session.Session) bool {
    if (current.completed != session.unit_count or current.record_group_count == 0 or
        current.record_cursor != current.record_group_count or current.record_batches.len != current.record_group_count) return false;
    for (current.units[0..session.records_index], 0..) |entry, index| {
        const checked_unit = entry orelse return false;
        const expected = session.unit(index) catch return false;
        if (!std.meta.eql(checked_unit.unit, expected) or !originalUnit(checked_unit)) return false;
    }
    const records = current.units[session.records_index] orelse return false;
    if (records.unit != .records or records.response != .content or records.response.content != .records or records.last_repair != null) return false;
    for (current.record_batches, 0..) |checked_unit, index| {
        if (checked_unit.unit != .records or !originalUnit(checked_unit)) return false;
        const assignment = checked_unit.record_assignment orelse return false;
        if (!assignment.reference_state.eql(current.reference_state) or assignment.group_index != index or assignment.source_group_id.ordinal == 0) return false;
    }
    return true;
}

fn originalUnit(checked: generation.Checked) bool {
    if (checked.response != .content or checked.last_repair != null or checked.origins.fields.len != 0 or
        checked.origins.record_occurrences.next_ordinal != 0 or checked.origins.record_occurrences.values.len != 0) return false;
    const origin = checked.origins.initial orelse return false;
    return origin.kind == .inference and origin.request.value != 0 and origin.attempt.value == 1;
}

fn makeChecked(unit: generation.Unit, request: usize) generation.Checked {
    const attributed: specification.AttributedValue = .{ .value = .{ .segments = &.{.{ .literal = .{ .value = "Original business behavior." } }} }, .source_group_ids = &.{}, .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{}, .citation_ids = &.{} } };
    return .{
        .unit = unit,
        .response = .{ .content = switch (unit) {
            .brief => .{ .brief = .{ .title = attributed, .description = attributed, .primary_goal = attributed } },
            .primary_user_story => .{ .primary_user_story = attributed },
            .entities => .{ .entities = .{ .disposition = .not_applicable, .basis = attributed } },
            .records => .{ .records = &.{} },
        } },
        .origins = .{ .initial = .{ .request = .{ .value = request }, .attempt = .{ .value = 1 } } },
    };
}

test "native candidate snapshots preserve initial bytes and independently own current bytes" {
    var tracker: Tracker = .{};
    defer tracker.deinit(std.testing.allocator);
    var first = [_]u8{ '{', '}', '\n' };
    try tracker.retain(std.testing.allocator, &first, true);
    first[0] = '[';
    try std.testing.expectEqualStrings("{}\n", tracker.first.?.json);
    const previous = tracker.latest.?.json.ptr;
    try tracker.retain(std.testing.allocator, "{}\n", true);
    try std.testing.expectEqual(previous, tracker.latest.?.json.ptr);
    try tracker.retain(std.testing.allocator, "{\"reviewed\":true}", false);
    try std.testing.expectEqualStrings("{}\n", tracker.first.?.json);
    try std.testing.expect(tracker.first.?.first_pass);
    try std.testing.expect(!tracker.latest.?.first_pass);
    try std.testing.expect(!std.mem.eql(u8, &tracker.first.?.sha256, &tracker.latest.?.sha256));
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const serialized = try std.json.Stringify.valueAlloc(a, tracker.first.?, .{});
    const round_trip = try @import("../../../src/domain/strict_json.zig").decode(Snapshot, a, serialized, .{ .maximum_depth = 32 });
    try std.testing.expectEqualStrings(tracker.first.?.json, round_trip.json);
    try std.testing.expectEqualSlices(u8, &tracker.first.?.sha256, &round_trip.sha256);
    var parsed = try @import("../../../src/domain/strict_json.zig").parse(a, serialized, .{ .maximum_depth = 32 }, false, null);
    defer parsed.deinit();
    try std.testing.expect(parsed.value.object.get("sha256").? == .array);
    // A missing native content slot cannot synthesize a semantic target.
    var empty: Tracker = .{};
    defer empty.deinit(std.testing.allocator);
    try empty.observe(std.testing.allocator, &.{});
    try std.testing.expect(empty.first == null and empty.latest == null);
}

test "native first pass rejects missing corrected and repaired generation origins" {
    try std.testing.expect(!originalUnit(makeChecked(.brief, 0)));
    // Lineage inspection needs no provider, continuation, model answer or
    // fabricated source context. Content validation stays with native owners.
    var narrative = [_]?generation.Checked{ makeChecked(.brief, 1), makeChecked(.primary_user_story, 2), makeChecked(.entities, 3), makeChecked(.records, 4) };
    var batch = makeChecked(.records, 4);
    // An apparently original provider origin alone cannot close first-pass
    // proof without every native batch-assignment receipt.
    var current: session.Session = .{ .feature = .{ .bytes = "selected" }, .reference_state = .{ .bytes = "reference-test" }, .completed = session.unit_count, .record_cursor = 1, .record_group_count = 1, .record_batches = &.{batch}, .units = narrative };
    try std.testing.expect(!firstPass(current));
    batch.record_assignment = .{ .reference_state = current.reference_state, .group_index = 0, .source_group_id = .{ .ordinal = 1 }, .references = .{ .bytes = @splat(0) } };
    current.record_batches = &.{batch};
    try std.testing.expect(firstPass(current));
    current.record_group_count = 2;
    try std.testing.expect(!firstPass(current));
    current.record_group_count = 1;
    narrative[0].?.origins.initial.?.attempt.value = 2;
    current.units = narrative;
    try std.testing.expect(!firstPass(current));
    narrative[0].?.origins.initial.?.attempt.value = 1;
    current.units = narrative;
    batch.origins.initial.?.attempt.value = 2;
    current.record_batches = &.{batch};
    try std.testing.expect(!firstPass(current));
    batch.origins.initial.?.attempt.value = 1;
    batch.last_repair = .{ .authorization = .{ .bytes = "repair-test" }, .owner = .workflow_step, .operation = .replace, .revision_before = 1, .revision_after = 2, .changed = true, .origin = batch.origins.initial };
    current.record_batches = &.{batch};
    try std.testing.expect(!firstPass(current));
    batch.last_repair = null;
    batch.origins.initial = null;
    current.record_batches = &.{batch};
    try std.testing.expect(!firstPass(current));
}

fn allocationScenario(a: std.mem.Allocator) !void {
    var tracker: Tracker = .{};
    defer tracker.deinit(a);
    try tracker.retain(a, "{\"first\":true}", true);
    try tracker.retain(a, "{\"corrected\":true}", false);
}
test "native candidate snapshot ownership cleans up every allocation failure" {
    try @import("../../../src/test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(allocationScenario, .{});
}

test "native assembled observations resolve unrelated exact values and preserve every native input" {
    const evidence_fixture = @import("../../../src/reference_evidence_test.zig");
    const extraction_fixture = @import("../../../src/reference_extraction_test.zig");
    const text = @import("../../../src/test_fixtures/reference_text.zig");
    const tokens = @import("../../../src/test_fixtures/reference_tokens.zig");
    const references = @import("../../../src/test_fixtures/reference_reconciliation.zig");
    const extraction = @import("../../../src/domain/reference_extraction.zig");
    const values = @import("../../../src/application/pipeline_values.zig");
    for ([_][3][]const u8{
        .{ "Display the receipt `Ready.` after successful reservation.", "Display the receipt after successful reservation.", "Ready." },
        .{ "Notify the sender with `Delivered.` after handing over the parcel.", "Notify the sender after handing over the parcel.", "Delivered." },
    }) |example| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var ids: evidence_fixture.IdSource = .{};
        const inputs = try evidence_fixture.prepare(a, &ids, try @import("../../../src/reference_ingestion_test.zig").read(a, "requirements.md", example[0]));
        const passive = try text.prepare(a, inputs);
        var passive_transferred = false;
        defer if (!passive_transferred) passive.deinit();
        const available = try tokens.candidates(a, inputs);
        const raw = try a.alloc(extraction.RawResult, inputs.chunks.entries.len);
        for (inputs.chunks.entries, raw) |chunk, *entry| entry.* = .{
            .scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = chunk.id },
            .result = .{ .response = try tokens.wire(a, try extraction_fixture.reply(a, inputs, chunk), try tokens.classifications(a, available, chunk)) },
        };
        const extracted = try extraction_fixture.finishText(a, inputs, try text.check(a, inputs, try @import("../../../src/domain/reference_extraction_parser.zig").parse(a, .{ .entries = raw })));
        const reference_context: references.Context = .{ .inputs = inputs, .registry = passive.registry, .current = text.safety.value(passive.owner) };
        const global = try references.summaries(a, try references.initialize(a, inputs, extracted, 2), reference_context);
        const accounted = (try references.finish(a, global, try references.global(a, global), reference_context)).valid;
        const context: @import("../../../src/domain/specification_provenance.zig").Context = .{ .inputs = inputs, .registry = passive.registry, .current = reference_context.current, .references = accounted };
        const support = @import("../../../src/domain/reference_support.zig").records(accounted);
        const groups = try a.alloc(references.r.SignalId, support.signals.len);
        for (support.signals, groups) |signal, *group| group.* = signal.id;
        const claims = try a.alloc(references.r.ClaimId, support.items.entries.len);
        var exact: ?references.r.ClaimId = null;
        for (support.items.entries, claims) |item, *claim| {
            claim.* = item.claim.id;
            if (item.claim.content == .preserved_token) exact = item.claim.id;
        }
        const narrative: specification.Model.AttributedValue = .{
            .value = .{ .segments = &.{.{ .literal = .{ .value = example[1] } }} },
            .source_group_ids = groups,
            .provenance = .{ .claim_ids = claims, .clarification_response_ids = &.{} },
        };
        var behavior = narrative;
        behavior.value = .{ .segments = &.{ .{ .literal = .{ .value = "The requested outcome is " } }, .{ .exact_copy = .{ .claim_id = exact orelse return error.MissingExactFixture } } } };
        var current = (try session.initialize(a, inputs.corpus.feature_id, context)).ready;
        var request: usize = 1;
        while (current.completed < session.unit_count) : (request += 1) {
            const unit = try session.unit(current.completed);
            const response: generation.Response = .{ .content = switch (unit) {
                .brief => .{ .brief = .{ .title = narrative, .description = behavior, .primary_goal = narrative } },
                .primary_user_story => .{ .primary_user_story = behavior },
                .entities => .{ .entities = .{ .disposition = .not_applicable, .basis = narrative } },
                .records => batch: {
                    const bound = (try session.currentBinding(a, current, context)).records;
                    const literal: specification.BusinessValue = .{ .segments = &.{.{ .literal = .{ .value = example[1] } }} };
                    const records = try a.alloc(specification.Model.RecordProposal, if (current.record_cursor == 0) 2 else 0);
                    for (records, 0..) |*record, index| record.* = .{
                        .content = if (index == 0) .{ .functional_requirement = .{ .text = literal } } else .{ .acceptance_criterion = .{ .given = literal, .when = literal, .then = literal } },
                        .source_group_ids = &.{bound.signal},
                        .provenance = bound.selection,
                    };
                    break :batch .{ .records = records };
                },
            } };
            const result = try (@import("../../../src/actions/specification/validate_specification_unit.zig").Action{ .validator = text.validator }).execute(a, current, context, .{ .response = response, .origins = .{ .initial = .{ .request = .{ .value = request }, .attempt = .{ .value = 1 } } } });
            if (result != .valid) return error.InvalidNativeCandidateFixture;
            current = try session.appendBound(a, current, result.valid);
        }
        const content = (try session.assemble(a, text.validator, context, current)).content;
        var view: data.View = .{};
        defer for (view.slots) |slot| if (slot) |value| values.destroy(value);
        const reference_owner = try @import("../../../src/domain/reference_candidate_value.zig").create(a, null);
        reference_owner.payload = .{ .reconciliation_accounted = accounted };
        const reference_schema = @import("../../../src/application/reference_reconciliation_workflow.zig").accounted_schema;
        view.slots[@intFromEnum(reference_schema.key)] = try values.adopt(a, reference_schema, @import("../../../src/domain/reference_candidate_value.zig").Value, @import("../../../src/domain/reference_candidate_value.zig").Owner, reference_owner, @import("../../../src/domain/reference_candidate_value.zig").view, @import("../../../src/domain/reference_candidate_value.zig").destroy, null);
        const input_schema = @import("../../../src/application/reference_evidence_workflow.zig").inputs_schema;
        view.slots[@intFromEnum(input_schema.key)] = try values.create(a, input_schema, @TypeOf(inputs), inputs);
        const passive_schema = @import("../../../src/application/passive_literal_workflow.zig").registry_schema;
        view.slots[@intFromEnum(passive_schema.key)] = try values.create(a, passive_schema, @TypeOf(passive.registry), passive.registry);
        const safety_schema = @import("../../../src/application/toolchain_workflow_values.zig").valid;
        view.slots[@intFromEnum(safety_schema.key)] = try values.adopt(a, safety_schema, text.safety.ValidToolchain, text.safety.Owner, passive.owner, text.safety.value, text.safety.deinitOwner, text.safety.retainedBytes(passive.owner));
        passive_transferred = true;
        const session_storage = @import("../../../src/application/specification_values.zig").storage;
        const session_owner = try session_storage.create(a, .{});
        session_owner.payload = .{ .session = current };
        view.slots[@intFromEnum(native.session_schema.key)] = (try session_storage.publish(a, native.session_schema, session_owner, .ok)).delta.data_writes[@intFromEnum(native.session_schema.key)];
        const content_owner = try authority_values.create(a, .{});
        content_owner.payload = .{ .content = content };
        view.slots[@intFromEnum(authority.content_schema.key)] = (try authority_values.publish(a, authority.content_schema, content_owner, .ok)).delta.data_writes[@intFromEnum(authority.content_schema.key)];
        const before = try std.json.Stringify.valueAlloc(a, .{ .session = current, .content = content, .support = support }, .{});
        var tracker: Tracker = .{};
        defer tracker.deinit(a);
        try tracker.observe(a, &view);
        const first = tracker.first orelse return error.MissingNativeSnapshot;
        try std.testing.expect(first.first_pass);
        const captured = try std.json.parseFromSlice(std.json.Value, a, first.json, .{});
        defer captured.deinit();
        try std.testing.expectEqualStrings(example[1], captured.value.object.get("document").?.object.get("display_name").?.object.get("bytes").?.string);
        try std.testing.expect(std.mem.indexOf(u8, captured.value.object.get("document").?.object.get("primary_user_story").?.object.get("bytes").?.string, example[2]) != null);
        try std.testing.expect(captured.value.object.get("native_reference_support").?.object.get("claims").?.array.items.len == support.items.entries.len);
        try std.testing.expectEqualStrings(example[0], captured.value.object.get("native_reference_support").?.object.get("sources").?.array.items[0].object.get("bytes").?.string);
        const after = try std.json.Stringify.valueAlloc(a, .{ .session = try native.readSession(&view), .content = try authority_values.read(&view, authority.content_schema, .content), .support = @import("../../../src/domain/reference_support.zig").records((try native.readContext(&view)).references) }, .{});
        try std.testing.expectEqualStrings(before, after);
        const retained = tracker.latest.?.json.ptr;
        try tracker.observe(a, &view);
        try std.testing.expectEqual(retained, tracker.latest.?.json.ptr);
    }
}
