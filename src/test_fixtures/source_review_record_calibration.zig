//! Offline paired preparation: three existing Source findings, three singleton
//! requests versus one coherent AC-record request. No dispatch or semantic judge.
const std = @import("std");
const temperature_policy = @import("calibration_temperature_policy.zig");
const shared = @import("source_loss_calibration.zig");
const authority = @import("../domain/required_authority.zig");
const spec = @import("../domain/specification.zig");
const support = @import("../domain/specification_support.zig").Source;
const provenance = @import("../domain/specification_provenance.zig");
const packets = @import("../domain/model_input_packet.zig");
const schema_owner = @import("../domain/model_result_schema.zig");
const codec = @import("../domain/model_candidate_json.zig");
const root = "test/calibration/source-review-record";
const output = ".zig-cache/source-review-record";
const Arm = enum { single_fields, joint_record };
const Case = struct {
    id: []const u8,
    cohort: enum { development, reserved_qualification },
    retained_case: ?[]const u8,
    fixture: ?shared.Case,
    record: ?struct { given: []const u8, when: []const u8, then: []const u8 },
    expectation: struct {
        given: []const u8,
        when: []const u8,
        then: []const u8,
        joint_meaning: []const u8,
        forbidden: []const []const u8,
    },
};
const File = struct { path: []const u8, sha256: []const u8, bytes: usize };
const Request = struct { subject: []const u8, packet: File, edit: File, request: File };
const Trial = struct { id: []const u8, case_id: []const u8, cohort: @FieldType(Case, "cohort"), arm: Arm, repetition: u32, requests: []const Request };

pub fn run() !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cases = try @import("../domain/strict_json.zig").decode([]const Case, a, try shared.read(a, root ++ "/cases.associated.json"), .{ .maximum_depth = 128 });
    const retained = try codec.decode([]const shared.Case, a, try shared.read(a, "test/calibration/source-loss-attribution/bound-preservation/obligation/cases.associated.json"));
    var parser: @import("../adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = try parser.compiler().compile(a, try shared.read(a, "design/workflows/spec/support.schema.json"));
    const prompt = try shared.read(a, "design/workflows/spec/support.prompt.md");
    try std.Io.Dir.cwd().createDirPath(std.testing.io, output);
    var trials: std.ArrayList(Trial) = .empty;
    var development: usize = 0;
    var qualification: usize = 0;
    for (cases, 0..) |example, index| {
        for (cases[0..index]) |previous| try std.testing.expect(!std.mem.eql(u8, example.id, previous.id));
        if (example.cohort == .development) development += 1 else qualification += 1;
        const base = try sourceCase(example, retained);
        const prepared = try prepare(a, example, base);
        defer prepared.passive.deinit();
        const first: authority.Id = .{ .kind = .feature_intent, .unit = .{ .record = .{ .kind = .acceptance_criterion, .ordinal = 1 } }, .slot = .given };
        const subjects = try support.assignmentSubjects(a, prepared.inputs, first);
        try std.testing.expectEqual(@as(usize, 3), subjects.len);
        const record = try support.packetFor(a, prepared.inputs, prepared.context, .{ .assignment = first });
        defer packets.release(record);
        const single_requests = try a.alloc(Request, subjects.len);
        for (subjects, single_requests, 0..) |subject, *request, member| {
            const single = try support.packetFor(a, prepared.inputs, prepared.context, .{ .finding = subject });
            defer packets.release(single);
            try pairedAssignment(a, member, single, record);
            request.* = try exportRequest(a, schema, prompt, example.id, @tagName(subject.slot), single);
        }
        const joint_requests = try a.dupe(Request, &.{try exportRequest(a, schema, prompt, example.id, "record", record)});
        if (index == 0) try schemaProbe(a, schema, record);
        for (1..3) |repetition| {
            for (std.enums.values(Arm)) |arm| try trials.append(a, .{ .id = try std.fmt.allocPrint(a, "{s}-{s}-review-{d}", .{ example.id, @tagName(arm), repetition }), .case_id = example.id, .cohort = example.cohort, .arm = arm, .repetition = @intCast(repetition), .requests = if (arm == .single_fields) single_requests else joint_requests });
        }
    }
    try std.testing.expectEqual(@as(usize, 5), development);
    try std.testing.expectEqual(@as(usize, 1), qualification);
    try std.testing.expectEqual(@as(usize, 24), trials.items.len);
    const paths = [_][]const u8{
        "src/test_fixtures/source_review_record_calibration.zig",
        "src/test_fixtures/source_loss_calibration.zig",
        "src/test_fixtures/calibration_temperature_policy.zig",
        "src/domain/specification_support.zig",
        "src/domain/specification_support_model.zig",
        "src/domain/specification_support_evidence.zig",
        "src/domain/specification_support_repair.zig",
        "src/domain/specification_review_subject.zig",
        "src/domain/specification_identity.zig",
        "src/domain/specification_provenance.zig",
        "src/domain/specification_authority.zig",
        "src/domain/specification.zig",
        "src/domain/specification_source_binding.zig",
        "src/domain/typed_text.zig",
        "src/domain/required_authority_description.zig",
        "src/domain/model_candidate_json.zig",
        "src/domain/model_controls.zig",
        "src/domain/model_result_schema.zig",
        "src/domain/model_schema_projection.zig",
        "src/adapters/provider/bedrock_request.zig",
        "design/workflows/spec/support.schema.json",
        "design/workflows/spec/support.prompt.md",
        root ++ "/cases.associated.json",
        root ++ "/scorecard.template.json",
        "test/calibration/source-loss-attribution/bound-preservation/obligation/cases.associated.json",
    };
    var dependencies: std.ArrayList(File) = .empty;
    for (paths) |path| try dependencies.append(a, try filePin(a, path));
    for (cases) |example| if ((try sourceCase(example, retained)).candidate_file) |path| try dependencies.append(a, try filePin(a, path));
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = output ++ "/preparation.json", .data = try std.json.Stringify.valueAlloc(a, .{
        .status = "offline_prepared_no_live_dispatch_authority",
        .factor = "Three unchanged native Given/When/Then findings: three singleton requests versus one complete record request. Both arms use current guidance and native evidence restrictions.",
        .settings = .{ .provider = "aws-bedrock", .model = "openai.gpt-oss-20b-1:0", .region = "ap-southeast-2", .reasoning_effort = "low", .temperature = temperature_policy.temperature, .response_mode = "native_schema", .seed = "absent", .top_p = "absent" },
        .limits = .{ .repetitions_per_arm = 2, .development_assignments = development, .reserved_qualification_assignments = qualification, .single_field_review_sends = 36, .joint_record_review_sends = 12, .maximum_review_sends = 48, .maximum_conditional_loss_sends = 72, .maximum_physical_sends_including_loss = 120, .stop_at_actual_input_plus_output_tokens = 500000, .retries_corrections_repairs_model_judges_e2e = 0 },
        .admission = "Complete native membership, three retained findings, per-finding evidence and serialized omission localization; a record verdict cannot substitute for any finding.",
        .receipt_authority = "No dispatch, synthetic native provider origin, or receipt admission implementation. Use the existing exact receipt and current native collector owners for separately authorized actual outputs.",
        .downstream = "Loss packets derive only after actual reviewer receipt admission, one complete native preservation assignment per actual pending defect. No expectation-built loss request is frozen.",
        .dependencies = dependencies.items,
        .trials = trials.items,
    }, .{}) });
}

fn sourceCase(example: Case, retained: []const shared.Case) !shared.Case {
    if ((example.retained_case != null) == (example.fixture != null)) return error.InvalidCalibrationCase;
    if (example.fixture) |fixture| return fixture;
    for (retained) |value| if (std.mem.eql(u8, value.id, example.retained_case.?)) return value;
    return error.MissingCalibrationSource;
}
fn prepare(a: std.mem.Allocator, example: Case, base: shared.Case) !shared.PreparedContext {
    var prepared = try shared.prepareContext(a, base);
    errdefer prepared.passive.deinit();
    if (example.record) |record| {
        const brief = prepared.brief;
        const references = @import("../domain/reference_support.zig").records(prepared.context.references);
        if (brief.description.source_group_ids.len != 1) return error.InvalidCalibrationRecord;
        const assigned = try @import("../domain/specification_source_binding.zig").resolveGroups(a, references, prepared.context.inputs, brief.description.source_group_ids, .content);
        const selection = try provenance.select(a, prepared.context, assigned.selection);
        const candidate = try shared.admitContent(a, prepared.context, .{ .display_name = brief.title, .primary_user_story = brief.description, .records = try a.dupe(spec.IdentifiedRecord, &.{.{ .id = .{ .kind = .acceptance_criterion, .ordinal = 1 }, .proposal = .{ .content = .{ .acceptance_criterion = .{ .given = try business(a, record.given), .when = try business(a, record.when), .then = try business(a, record.then) } }, .source_group_ids = assigned.source_group_ids, .provenance = selection } }}), .entities = .{ .disposition = .not_applicable, .basis = brief.description } });
        try provenance.validateStored(a, prepared.context.inputs, .{ .records = prepared.context.registry.records, .occurrences = prepared.context.registry.occurrences }, references, brief, candidate);
        prepared.inputs = try @import("../domain/specification_authority.zig").project(a, prepared.context.inputs.corpus.feature_id, prepared.context.references, candidate, brief);
    }
    return prepared;
}
fn business(a: std.mem.Allocator, value: []const u8) !spec.BusinessValue {
    return .{ .segments = try a.dupe(@import("../domain/typed_text.zig").BusinessSegment, &.{.{ .literal = .{ .value = value } }}) };
}
fn pairedAssignment(a: std.mem.Allocator, member: usize, single: *const packets.Packet, record: *const packets.Packet) !void {
    const left = try std.json.parseFromSliceLeaky(std.json.Value, a, single.body(), .{});
    const right = try std.json.parseFromSliceLeaky(std.json.Value, a, record.body(), .{});
    try std.testing.expectEqualStrings("assignment_findings", record.resultDefinition().?.bytes);
    try std.testing.expect(!right.object.contains("subject"));
    const assignments = right.object.get("requirements").?.array.items;
    try std.testing.expectEqual(@as(usize, 3), assignments.len);
    const selected = assignments[member];
    const singleton = left.object.get("requirements").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), singleton.len);
    for ([_][]const u8{ "ordinal", "task", "evidence" }) |field| try sameJson(a, singleton[0].object.get(field).?, selected.object.get(field).?);
    for ([_][]const u8{ "assessment_scope", "evidence_rules" }) |field| try sameJson(a, left.object.get(field).?, selected.object.get(field).?);
    for ([_][]const u8{ "sources", "claims", "citations", "preserved_tokens" }) |field| try sameJson(a, left.object.get(field).?, right.object.get(field).?);
    const subject = selected.object.get("subject").?.object;
    const slots = [_][]const u8{ "given", "when", "then" };
    try std.testing.expectEqualStrings(slots[member], subject.get("slot").?.string);
    // A record family has no shared assignment record; each member keeps its own.
    try std.testing.expect(!right.object.contains("record"));
    try sameJson(a, left.object.get("subject").?.object.get("record").?, subject.get("record").?);
    try sameJson(a, left.object.get("subject").?.object.get("text").?, subject.get("text").?);
}
fn schemaProbe(a: std.mem.Allocator, schema: *const schema_owner.Schema, packet: *const packets.Packet) !void {
    const restricted = try schema_owner.restrict(a, schema.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
    defer restricted.release();
    const body = try std.json.parseFromSliceLeaky(std.json.Value, a, packet.body(), .{});
    var findings: std.ArrayList(@import("../domain/specification_support_model.zig").BatchFinding) = .empty;
    for (body.object.get("requirements").?.array.items) |requirement| try findings.append(a, .{ .requirement_ordinal = @intCast(requirement.object.get("ordinal").?.integer), .value = .{ .supported = .{ .source_ids = &.{.{ .ordinal = 1 }}, .detail = "MOCK structural schema probe; no semantic judgment." } } });
    // Response admission requires the complete assignment: exactly one finding
    // per member. Partial and empty batches fail the item count.
    for ([_]usize{ 3, 2, 0 }) |length| {
        var document = try @import("../domain/model_envelope.zig").parseContent(a, try codec.encode(@import("../domain/specification_support_model.zig").Batch, a, .{ .findings = findings.items[0..length] }), null);
        defer document.deinit();
        const invalid = @import("../domain/model_payload_schema.zig").validateValue(@import("../domain/model_envelope.zig").value(&document.parsed.value), restricted.selected().root());
        try std.testing.expect((invalid == null) == (length == 3));
        if (invalid) |diagnostic| try std.testing.expectEqual(.array_length, diagnostic.reason);
    }
    // A complete-sized batch that repeats one member is still rejected.
    var repeated = try a.dupe(@import("../domain/specification_support_model.zig").BatchFinding, findings.items);
    repeated[2].requirement_ordinal = repeated[0].requirement_ordinal;
    var document = try @import("../domain/model_envelope.zig").parseContent(a, try codec.encode(@import("../domain/specification_support_model.zig").Batch, a, .{ .findings = repeated }), null);
    defer document.deinit();
    const duplicate = @import("../domain/model_payload_schema.zig").validateValue(@import("../domain/model_envelope.zig").value(&document.parsed.value), restricted.selected().root()).?;
    try std.testing.expectEqual(.duplicate_member, duplicate.reason);
}
fn sameJson(a: std.mem.Allocator, left: std.json.Value, right: std.json.Value) !void {
    try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, left, .{}), try std.json.Stringify.valueAlloc(a, right, .{}));
}
fn exportRequest(a: std.mem.Allocator, schema: *const schema_owner.Schema, prompt: []const u8, id: []const u8, member: []const u8, packet: *const packets.Packet) !Request {
    try shared.writeAt(a, output, id, try std.fmt.allocPrint(a, "{s}.packet.json", .{member}), packet.body());
    try shared.exportBodyAt(a, output, schema, id, member, packet, packet.body(), prompt);
    return .{ .subject = member, .packet = try pin(a, id, try std.fmt.allocPrint(a, "{s}.packet.json", .{member})), .edit = try pin(a, id, try std.fmt.allocPrint(a, "{s}.edit.json", .{member})), .request = try pin(a, id, try std.fmt.allocPrint(a, "{s}.request.json", .{member})) };
}
fn filePin(a: std.mem.Allocator, path: []const u8) !File {
    const bytes = try shared.read(a, path);
    return .{ .path = path, .sha256 = try shared.sha256(a, bytes), .bytes = bytes.len };
}
fn pin(a: std.mem.Allocator, id: []const u8, suffix: []const u8) !File {
    return filePin(a, try std.fmt.allocPrint(a, "{s}/{s}.{s}", .{ output, id, suffix }));
}
