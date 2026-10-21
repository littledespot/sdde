//! Offline execution of current production admission over immutable old output.
//! A newly scripted native reference/session projection is explicit test data;
//! it never upgrades historical request metadata or grants workflow authority.
const std = @import("std");
const strict = @import("../../../src/domain/strict_json.zig");
const envelope = @import("../../../src/domain/model_envelope.zig");
const schema = @import("../../../src/domain/model_result_schema.zig");
const codec = @import("../../../src/domain/model_candidate_json.zig");
const g = @import("../../../src/domain/specification_generation.zig");
const p = @import("../../../src/domain/specification_provenance.zig");
const sessions = @import("../../../src/domain/specification_session.zig");
const refs = @import("../../../src/test_fixtures/reference_reconciliation.zig");
const text = @import("../../../src/test_fixtures/reference_text.zig");
const native = @import("../../../src/provider_invocation_test_fixture.zig");
const retained = @import("corpus.zig");

pub const FailureClass = enum { insertion_only, collapsed_records, prose_without_insertions, admitted_generation_then_review_failure, embedded_insertion_syntax, unrelated_loan_control };
pub const Origin = enum { authentic_capture, scripted_control, unavailable_capture };
pub const Rejection = union(enum) {
    syntax: strict.Diagnostic,
    composition: []const @import("../../../src/domain/model_text_composition.zig").Diagnostic.Description,
    schema: @import("../../../src/domain/model_schema_diagnostic.zig").Description,
    generation: @import("../../../src/domain/specification_candidate.zig").Issue,
};
pub const Admitted = struct {
    records: usize,
    exact_nodes: usize,
    explicit_support_unchanged: bool,
    exact_claims_beyond_explicit_support: usize,
    coverage_obligations: usize,
    behavioral_exact_targets: usize,
};
pub const Outcome = union(enum) { admitted: Admitted, rejected: Rejection, unavailable: enum { retained_raw_capture_not_found } };
pub const Row = struct {
    id: []const u8,
    requested_run_aedt: []const u8,
    failure_class: FailureClass,
    origin: Origin,
    execution_id: ?[]const u8 = null,
    call: ?u32 = null,
    output_sha256: ?[]const u8 = null,
    source_sha256: ?[]const u8 = null,
    current_schema_sha256: ?[]const u8 = null,
    legacy_exact_wire: enum { absent, rejected_by_current_schema_and_codec } = .absent,
    normalization: envelope.Normalization = .none,
    outcome: Outcome,
};
pub const Report = struct {
    version: enum { @"exact-value-production-admission/v1" } = .@"exact-value-production-admission/v1",
    projection: enum { current_native_test_context_over_retained_source_bytes } = .current_native_test_context_over_retained_source_bytes,
    historical_metadata_promoted: bool = false,
    model_calls: usize = 0,
    workflow_authority: bool = false,
    semantic_quality_assessed: bool = false,
    requested_runs: usize = 5,
    available_requested_runs: usize,
    unavailable_requested_runs: usize,
    replayed_capture_rows: usize,
    scripted_control_rows: usize,
    admitted_rows: usize,
    typed_rejection_rows: usize,
    admission_escape_rows: usize,
    rows: []const Row,
};
const Input = struct { id: []const u8, time: []const u8, class: FailureClass, origin: Origin = .authentic_capture, execution: ?[]const u8 = null, call: ?u32 = null, source: []const u8, output: []const u8, unit: enum { brief, records }, requires_entity: bool = false };

fn member(value: std.json.Value, name: []const u8) !std.json.Value {
    if (value != .object) return error.InvalidRetainedAdmissionCapture;
    return value.object.get(name) orelse error.InvalidRetainedAdmissionCapture;
}
fn string(value: std.json.Value) ![]const u8 {
    if (value != .string) return error.InvalidRetainedAdmissionCapture;
    return value.string;
}
fn array(value: std.json.Value) ![]const std.json.Value {
    if (value != .array) return error.InvalidRetainedAdmissionCapture;
    return value.array.items;
}
fn pinned(a: std.mem.Allocator, bytes: []const u8, expected: []const u8) !void {
    if (!std.mem.eql(u8, expected, try retained.hash(a, bytes))) return error.RetainedAdmissionCaptureDrift;
}
fn representation(a: std.mem.Allocator, execution: []const u8, call: u32, id: []const u8, time: []const u8, class: FailureClass, unit: @FieldType(Input, "unit")) !Input {
    // This opaque, hash-pinned archive is diagnostic data. Its own integration
    // suite owns the closed historical fixture contract; no archived request is
    // converted into a current request or occurrence-scope authority here.
    const archive = try strict.parse(a, @embedFile("../../calibration/representation-admission/retained.json"), .{ .maximum_depth = 128 }, true, null);
    for (try array(try member(archive.value, "runs"))) |captured_run| {
        if (!std.mem.eql(u8, execution, try string(try member(captured_run, "run_id")))) continue;
        const sources = try array(try member(captured_run, "sources"));
        if (sources.len != 1) return error.InvalidRetainedAdmissionCapture;
        const source = try string(try member(sources[0], "bytes"));
        try pinned(a, source, try string(try member(sources[0], "sha256")));
        for (try array(try member(captured_run, "captures"))) |capture| {
            const ordinal = try member(capture, "call");
            if (ordinal != .integer or ordinal.integer != call) continue;
            const output = try string(try member(capture, "raw_output"));
            try pinned(a, output, try string(try member(capture, "raw_output_sha256")));
            return .{ .id = id, .time = time, .class = class, .execution = execution, .call = call, .source = source, .output = output, .unit = unit };
        }
    }
    return error.MissingRetainedAdmissionCapture;
}
fn proseCapture(a: std.mem.Allocator) !Input {
    const archive = try strict.parse(a, @embedFile("../../calibration/exact-value-recognition/retained.json"), .{ .maximum_depth = 128 }, true, null);
    for (try array(try member(archive.value, "samples"))) |sample| {
        if (!std.mem.eql(u8, "hello-world-business-binding", try string(try member(sample, "id")))) continue;
        const output = try string(try member(sample, "output"));
        try pinned(a, output, try string(try member(sample, "output_sha256")));
        const description = try string(try member(sample, "description"));
        try pinned(a, description, try string(try member(sample, "description_sha256")));
        const observed = try strict.parse(a, description, .{ .maximum_depth = 128 }, true, null);
        const sources = try array(try member(observed.value, "original_sources"));
        if (sources.len != 1) return error.InvalidRetainedAdmissionCapture;
        return .{ .id = "f13-prose-native-lineage", .time = "16 October 20:22", .class = .prose_without_insertions, .execution = try string(try member(sample, "execution_id")), .call = 13, .source = try string(try member(sources[0], "bytes")), .output = output, .unit = .records, .requires_entity = true };
    }
    return error.MissingRetainedAdmissionCapture;
}
const NewestCapture = struct {
    version: enum { @"production-admission-retained/v1" },
    execution_id: []const u8,
    call: u32,
    context_path: []const u8,
    context_sha256: []const u8,
    context: []const u8,
    output_path: []const u8,
    output_sha256: []const u8,
    output: []const u8,
    source_path: []const u8,
    source_sha256: []const u8,
    source: []const u8,
};
fn syntaxCapture(a: std.mem.Allocator) !Input {
    const capture = try strict.decode(NewestCapture, a, @embedFile("retained_current_admission.json"), .{ .maximum_depth = 128 });
    try pinned(a, capture.context, capture.context_sha256);
    try pinned(a, capture.output, capture.output_sha256);
    try pinned(a, capture.source, capture.source_sha256);
    const context = (try @import("../e2e/call_context.zig").Captured.decode(a, capture.context)).common();
    if (context.call != capture.call) return error.InvalidRetainedAdmissionCapture;
    return .{ .id = "latest-embedded-insertion", .time = "16 October 22:00", .class = .embedded_insertion_syntax, .execution = capture.execution_id, .call = capture.call, .source = capture.source, .output = capture.output, .unit = .brief };
}
fn hasExact(value: std.json.Value) bool {
    switch (value) {
        .object => |object| {
            if (object.get("kind")) |kind| if (kind == .string and std.mem.eql(u8, kind.string, "exact_copy")) return true;
            for (object.values()) |child| if (hasExact(child)) return true;
        },
        .array => |values| for (values.items) |child| {
            if (hasExact(child)) return true;
        },
        else => {},
    }
    return false;
}
fn plain(a: std.mem.Allocator, context: p.Context, bytes: []const u8, field: @import("../../../src/domain/text_field_policy.zig").Field) !g.spec.AttributedValue {
    return p.checkAttributed(.model, a, text.validator, context, try plainProposal(a, context, bytes), field);
}
fn plainProposal(a: std.mem.Allocator, context: p.Context, bytes: []const u8) !g.spec.Model.AttributedValue {
    const records = @import("../../../src/domain/reference_support.zig").records(context.references);
    const bound = try @import("../../../src/domain/specification_source_binding.zig").record(a, records, context.inputs, 0);
    return .{ .value = .{ .segments = try a.dupe(@import("../../../src/domain/typed_text.zig").BusinessSegment, &.{.{ .literal = .{ .value = bytes } }}) }, .source_group_ids = try a.dupe(refs.r.SignalId, &.{bound.records.signal}), .provenance = bound.records.selection };
}

fn replay(a: std.mem.Allocator, input: Input) !Row {
    var row: Row = .{ .id = input.id, .requested_run_aedt = input.time, .failure_class = input.class, .origin = input.origin, .execution_id = input.execution, .call = input.call, .output_sha256 = try retained.hash(a, input.output), .source_sha256 = try retained.hash(a, input.source), .outcome = .{ .unavailable = .retained_raw_capture_not_found } };
    const reference = try @import("../../../src/reference_reconciliation_test.zig").prepare(a, &.{input.source});
    defer reference.deinit();
    const progress = try refs.summaries(a, try refs.initialize(a, reference.inputs, reference.extracted, 2), reference.context());
    const accounted = switch (try refs.finish(a, progress, try refs.global(a, progress), reference.context())) {
        .valid => |checked| checked,
        .invalid => |failure| {
            std.debug.print("current reference fixture rejected: {s}\n", .{try std.json.Stringify.valueAlloc(a, failure, .{})});
            return error.InvalidCurrentAdmissionFixture;
        },
    };
    const context: p.Context = .{ .inputs = reference.inputs, .references = accounted, .registry = reference.text.registry, .current = text.safety.value(reference.text.owner) };
    var current = switch (try sessions.initialize(a, context.inputs.corpus.feature_id, context)) {
        .ready => |ready| ready,
        .blocked => |failure| {
            std.debug.print("current session fixture blocked: {s}\n", .{try std.json.Stringify.valueAlloc(a, failure, .{})});
            return error.InvalidCurrentAdmissionFixture;
        },
    };
    if (input.unit == .records) {
        current.completed = sessions.records_index;
        const basis = try plainProposal(a, context, "The requested behavior has an observable result.");
        // Current scripted context owns entities once per feature. The retained
        // response remains byte-for-byte old output and is independently
        // rejected if it still tries to author an entity in a record batch.
        const entities = if (input.requires_entity) try a.dupe(g.spec.Model.RecordProposal, &.{.{
            .content = .{ .entity = .{ .name = .{ .segments = &.{.{ .literal = .{ .value = "Application" } }} }, .business_meaning = basis.value, .relationships = &.{} } },
            .source_group_ids = basis.source_group_ids,
            .provenance = basis.provenance,
        }}) else &.{};
        const entity_fixture = try g.validate(a, text.validator, context, .entities, .{ .content = .{ .entities = .{ .disposition = if (input.requires_entity) .required else .not_applicable, .basis = basis, .records = entities } } });
        current.units[2] = switch (entity_fixture) {
            .valid => |checked| checked,
            .invalid => |failure| {
                std.debug.print("current admission fixture rejected: {s}\n", .{try std.json.Stringify.valueAlloc(a, failure, .{})});
                return error.InvalidCurrentAdmissionFixture;
            },
        };
    }
    const packet = try sessions.packet(a, current, context);
    defer @import("../../../src/domain/model_input_packet.zig").release(packet);
    var compiler: @import("../../../src/adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const canonical = try compiler.compiler().compile(a, @embedFile("../../../design/workflows/spec/generation.schema.json"));
    const selected = try schema.restrict(a, canonical.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
    defer selected.release();
    row.current_schema_sha256 = try retained.hash(a, selected.selected().modelBytes());
    var document = try envelope.parseContent(a, input.output, null);
    defer document.deinit();
    row.normalization = document.normalization;
    if (hasExact(document.parsed.value)) {
        if (@import("../../../src/domain/model_payload_schema.zig").validateValue(envelope.value(&document.parsed.value), selected.selected().root()) == null) return error.LegacyExactWireAdmissionEscape;
        try std.testing.expectError(error.InvalidJsonDocument, codec.decode(g.ModelResponse, a, document.content));
        row.legacy_exact_wire = .rejected_by_current_schema_and_codec;
    }
    var invocation: native.Fixture = undefined;
    try invocation.initWithNativeTextContext(selected.selected(), packet.originalSources(), packet.proseFields(), packet.fieldPolicies(), packet.exactScope().?);
    defer invocation.deinit();
    invocation.fake.invocation_plan = .{ .complete = .{ .content = input.output, .input_tokens = 0, .output_tokens = 0 } };
    var observation = try invocation.response();
    defer observation.deinit();
    var validated = try (@import("../../../src/actions/model/validate_provider_invocation_observation.zig").Action{}).execute(std.testing.allocator, invocation.call, &observation);
    defer validated.deinit();
    var diagnostic: ?envelope.Diagnostic = null;
    defer if (diagnostic) |value| value.deinit(std.testing.allocator);
    var admitted = (@import("../../../src/actions/model/admit_model_response.zig").Action{}).execute(std.testing.allocator, validated.evidence.result().complete, &diagnostic) catch |err| {
        if (err == error.OutOfMemory) return err;
        if (err != error.InvalidModelEnvelope or diagnostic == null) return error.UnclassifiedProductionAdmissionFailure;
        row.outcome = .{ .rejected = switch (diagnostic.?) {
            .decoder => |failure| .{ .syntax = try failure.copy(a) },
            .composition => |failure| .{ .composition = try (try failure.copy(a)).describe(a) },
        } };
        return row;
    };
    defer admitted.decoded.deinit();
    switch (admitted.validated) {
        .invalid => |failure| {
            row.outcome = .{ .rejected = .{ .schema = try failure.describe(a) } };
            return row;
        },
        .valid => {},
    }
    const proposed = try g.parse(a, admitted.decoded.candidate.content(), try sessions.currentBinding(a, current, context));
    const generated = try g.validate(a, text.validator, context, if (input.unit == .records) .records else .brief, proposed);
    switch (generated) {
        .invalid => |failure| {
            row.outcome = .{ .rejected = .{ .generation = failure } };
            return row;
        },
        .valid => |checked| {
            if (checked.response != .content or checked.response.content != .records) return error.UnexpectedProductionAdmissionControl;
            const bound = try sessions.currentBinding(a, current, context);
            var exact_nodes: usize = 0;
            var extra_claims: std.ArrayList(refs.r.ClaimId) = .empty;
            for (checked.response.content.records) |record| {
                try std.testing.expectEqualDeep(bound.records.selection.claim_ids, record.provenance.claim_ids);
                const values = try p.recordValues(a, record.content);
                for (values) |value| for (value.segments) |node| if (node == .exact_copy) {
                    exact_nodes += 1;
                    if (!refs.r.contains(refs.r.ClaimId, record.provenance.claim_ids, node.exact_copy.claim_id) and !refs.r.contains(refs.r.ClaimId, extra_claims.items, node.exact_copy.claim_id)) try extra_claims.append(a, node.exact_copy.claim_id);
                };
                const effective = try p.effectiveClaims(a, record.provenance.claim_ids, values);
                for (extra_claims.items) |id| try std.testing.expect(refs.r.contains(refs.r.ClaimId, effective, id) or !containsExact(values, id));
            }
            const title = try plain(a, context, "Observable application behavior", .spec_title);
            const description = try plain(a, context, "The application provides the requested result.", .spec_description);
            const goal = try plain(a, context, "Provide the requested behavior.", .spec_goal);
            const story = try plain(a, context, "The user requests the supported behavior and observes the result.", .spec_story);
            const identified = try @import("../../../src/domain/specification_identity.zig").assign(a, .{ .display_name = title, .primary_user_story = story, .entities = current.units[2].?.response.content.entities.decision(), .records = checked.response.content.records }, .{});
            const coverage = try @import("../../../src/domain/specification_coverage.zig").validate(a, context.references, .{ .title = title, .description = description, .primary_goal = goal }, identified.content);
            var targets: usize = 0;
            for (coverage.obligations) |obligation| targets += obligation.exact_targets.len;
            try p.validateStored(a, context.inputs, .{ .records = context.registry.records, .occurrences = context.registry.occurrences }, @import("../../../src/domain/reference_support.zig").records(context.references), .{ .title = title, .description = description, .primary_goal = goal }, identified.content);
            row.outcome = .{ .admitted = .{ .records = checked.response.content.records.len, .exact_nodes = exact_nodes, .explicit_support_unchanged = true, .exact_claims_beyond_explicit_support = extra_claims.items.len, .coverage_obligations = coverage.obligations.len, .behavioral_exact_targets = targets } };
            return row;
        },
    }
}
fn containsExact(values: []const g.spec.BusinessValue, id: refs.r.ClaimId) bool {
    for (values) |value| for (value.segments) |node| {
        if (node == .exact_copy and node.exact_copy.claim_id.ordinal == id.ordinal) return true;
    };
    return false;
}

pub fn run(a: std.mem.Allocator) !Report {
    var rows: std.ArrayList(Row) = .empty;
    try rows.append(a, try replay(a, try representation(a, "2026-10-16T05-20-15Z-44b2ac5e19cbf8d2ade89b149aed73c8", 7, "f11-insertion-only-title", "16 October 16:20", .insertion_only, .brief)));
    try rows.append(a, try replay(a, try representation(a, "2026-10-16T07-58-59Z-ec56ff4bc24a21c0082210cf6caa8f31", 13, "f12-collapsed-records", "16 October 18:58", .collapsed_records, .records)));
    try rows.append(a, try replay(a, try proseCapture(a)));
    try rows.append(a, .{ .id = "generation-pass-review-budget-run", .requested_run_aedt = "16 October 20:33", .failure_class = .admitted_generation_then_review_failure, .origin = .unavailable_capture, .execution_id = "2026-10-16T09-33-15Z-d749fce107972fd4feaad6c9ac902538", .outcome = .{ .unavailable = .retained_raw_capture_not_found } });
    try rows.append(a, try replay(a, try syntaxCapture(a)));
    try rows.append(a, try replay(a, .{ .id = "loan-native-lineage-control", .time = "independent scripted control", .class = .unrelated_loan_control, .origin = .scripted_control, .source = "When an eligible borrower renews a loan, the service must extend the due date and display `Loan renewed!`.\n", .output = "{\"kind\":\"records\",\"records\":[{\"content\":{\"kind\":\"acceptance_criterion\",\"given\":\"An eligible borrower has a renewable loan.\",\"when\":\"The borrower requests renewal.\",\"then\":\"The service extends the due date and displays Loan renewed!\"}},{\"content\":{\"kind\":\"functional_requirement\",\"text\":\"The service must extend the renewable loan and display Loan renewed!\"}}]}", .unit = .records }));
    var admitted_rows: usize = 0;
    var rejected_rows: usize = 0;
    var capture_rows: usize = 0;
    var escapes: usize = 0;
    for (rows.items) |row| {
        if (row.origin == .authentic_capture) capture_rows += 1;
        switch (row.outcome) {
            .admitted => admitted_rows += 1,
            .rejected => rejected_rows += 1,
            .unavailable => {},
        }
        const prohibited_capture = switch (row.failure_class) {
            .insertion_only, .collapsed_records, .embedded_insertion_syntax => true,
            // This immutable prose capture also authors an entity in its old
            // record batch, forbidden by the current feature-owned contract.
            .prose_without_insertions => true,
            .admitted_generation_then_review_failure, .unrelated_loan_control => false,
        };
        if (prohibited_capture and row.outcome == .admitted) escapes += 1;
    }
    return .{ .available_requested_runs = 4, .unavailable_requested_runs = 1, .replayed_capture_rows = capture_rows, .scripted_control_rows = 1, .admitted_rows = admitted_rows, .typed_rejection_rows = rejected_rows, .admission_escape_rows = escapes, .rows = try rows.toOwnedSlice(a) };
}
