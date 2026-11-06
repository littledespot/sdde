//! Deterministic measures of one retained E2E run and of a set of runs. Every count
//! comes from a closed record: the native report, the per-call evidence, a model
//! response's discriminator and the closed kinds its arrays carry, and the feature event
//! log. No prose is read or classified, and no measure is a verdict or acceptance. Every
//! function allocates from the caller's arena.
const std = @import("std");
const c = @import("contracts.zig");
const admission = @import("../baseline/admission.zig");
const stages = @import("../baseline/stages.zig");
const envelope = @import("../../../src/domain/model_envelope.zig");
const log_format = @import("../../../src/domain/feature_log_format.zig");
const log_limits = @import("../../../src/domain/feature_log_limits.zig");
const log_stream = @import("../../../src/domain/feature_log_stream.zig");
const event_capture = @import("../../../src/application/workflow_event_capture.zig");
const telemetry = @import("../../../src/domain/telemetry.zig");
const provider = @import("../../../src/domain/llm_provider_operation.zig");
const Origin = @import("../../../src/domain/model_candidate_origin.zig").Origin;
const Merge = @import("../../../src/domain/atomic_repair.zig").Merge;
const spec = @import("../../../src/domain/specification.zig");
const claim = @import("../../../src/domain/reference_extraction.zig");
const text_wire = @import("../../../src/domain/model_text_wire.zig");
const generation = @import("../../../src/domain/specification_generation.zig");
const extraction_parser = @import("../../../src/domain/reference_extraction_parser.zig");

/// The wire names a response's structure is read by, each taken from the type that owns
/// it: a renamed field or variant renames the key here, and a type that renames its wire
/// tags (`model_tags`) fails the build instead of zeroing a count.
const wire = struct {
    /// Every model response and record content is a tagged union under this key.
    const discriminator = "kind";
    const Generated = std.meta.Tag(generation.ModelResponse);
    const Extracted = std.meta.Tag(extraction_parser.Content);
    const Entities = @FieldType(generation.ModelResponse, "entities");
    const records = @tagName(Generated.records);
    const records_array = std.meta.fieldInfo(@FieldType(generation.ModelResponse, "records"), .records).name;
    const record_content = std.meta.fieldInfo(generation.AuthoringRecord, .content).name;
    const entities = @tagName(Generated.entities);
    const disposition = std.meta.fieldInfo(Entities, .disposition).name;
    const entity_records = std.meta.fieldInfo(Entities, .records).name;
    const claims = @tagName(Extracted.claims);
    const claims_array = std.meta.fieldInfo(@FieldType(extraction_parser.Content, "claims"), .claims).name;
    const category = std.meta.fieldInfo(claim.Proposal, .category).name;
    const no_feature_claim = @tagName(Extracted.no_feature_claim);
    comptime {
        for (.{ generation.ModelResponse, extraction_parser.Content, spec.Content(spec.BusinessValue) }) |T| {
            if (@hasDecl(T, "model_tags")) @compileError("structure reads variant names as wire tags");
        }
    }
};

pub const Error = error{ InvalidFeatureLog, OutOfMemory };

pub const ReasonCount = struct { reason: []const u8, count: u64 };
pub const KindCount = struct { kind: spec.Kind, count: u64 };
pub const CategoryCount = struct { category: claim.Kind, count: u64 };
/// One model response's structure: its discriminator and the closed kinds, categories
/// and dispositions its arrays carry. Prose is never read.
pub const Structure = struct {
    shape: Shape,
    /// `{"fragments":[...]}` text objects anywhere in the response, and those of them
    /// whose fragments are all literal text, inserting no reference.
    fragments: u64 = 0,
    literal_fragments: u64 = 0,

    pub const Shape = union(enum) {
        records: Records,
        entities: Entities,
        claims: Claims,
        no_feature_claim,
        /// Any other discriminator, such as a story or reconciliation response.
        other,
    };
    pub const Records = struct {
        /// The `records` array's length.
        total: u64,
        /// Records by `content.kind`, in the kinds' declared order, nonzero counts only.
        kinds: []const KindCount = &.{},
        /// Records without a known `content.kind`.
        unknown: u64 = 0,
    };
    pub const Entities = struct {
        /// Null when `disposition` is missing or not a known applicability.
        disposition: ?spec.Applicability,
        /// The entity `records` array's length; null when it isn't an array.
        records: ?u64,
    };
    pub const Claims = struct {
        /// The `claims` array's length.
        total: u64,
        /// Claims by `category`, in the categories' declared order, nonzero counts only.
        categories: []const CategoryCount = &.{},
        /// Claims without a known `category`.
        unknown: u64 = 0,
    };
};
/// One retained call's response structure, with its call and origin. Every call whose
/// context decodes is kept, so a request's last attempt is known even when its response
/// has no structure: null when the output is missing or the envelope parser can't read it.
pub const Response = struct { call: usize, origin: Origin, structure: ?Structure };
/// Counts from the feature event log. Runaways, re-sends and normalized responses are
/// logged at every threshold (§26.5); the other counts and the latency hold only events
/// the run's `log_threshold` kept.
pub const Events = struct {
    /// `model.provider_stopped` with the `output_limit` stop reason.
    runaways: u64 = 0,
    /// `model.runaway_resent` (ADR 0039).
    resends: u64 = 0,
    /// `model.response_normalized` (§22.6 prefix normalization).
    normalized_responses: u64 = 0,
    /// Admission rejections by diagnostic code: `model.protocol_failed` and
    /// `model.schema_failed`.
    protocol_rejections: []const ReasonCount = &.{},
    schema_rejections: []const ReasonCount = &.{},
    /// `validation.failed`, by diagnostic code.
    validation_failures: []const ReasonCount = &.{},
    /// Monotonic span from the first to the last event record.
    latency_ms: ?u64 = null,

    pub fn admissionRejections(self: Events) u64 {
        var total: u64 = 0;
        for ([_][]const ReasonCount{ self.protocol_rejections, self.schema_rejections }) |reasons| {
            for (reasons) |reason| total += reason.count;
        }
        return total;
    }
};
pub const Outcome = struct {
    status: c.Status,
    workflow_outcome: ?@import("../../../src/domain/workflow.zig").OutcomeTag,
    terminal_step: ?[]const u8,
    diagnostic: ?[]const u8,
    publication_check: @FieldType(c.Report, "publication_check"),
    publication: Publication,

    pub const Publication = enum {
        /// Outcome `ok` with a passed publication check: the publication rate's numerator.
        native,
        /// A failed or blocked run's incomplete publication (ADR 0041); never counted as
        /// a publication.
        incomplete,
        none,
    };
};
pub const Run = struct {
    schema: enum { @"e2e-measures/v2" } = .@"e2e-measures/v2",
    run: []const u8,
    /// The retained `case.json` identifier.
    case_id: []const u8,
    /// `unmeasurable` when a retained record can't be read or trusted; the run still
    /// counts as attempted.
    measurement: union(enum) { measured: Measured, unmeasurable: Unmeasurable },
};
/// The retained record that stopped a run's measurement.
pub const Unmeasurable = struct {
    reason: Reason,

    pub const Reason = enum {
        /// A retained file or directory couldn't be read.
        unreadable,
        /// The retained configuration doesn't decode or names no valid log level.
        configuration,
        /// The report doesn't decode or has an unknown version, or its usage or its
        /// incomplete-publication marker is inconsistent.
        report,
        /// A call's retained context doesn't decode.
        call_evidence,
        /// The feature event log isn't the log format's own.
        feature_log,
        /// The project holds the event logs of more than one workflow run.
        ambiguous_feature_log,
    };
};
pub const Measured = struct {
    /// The retained project's configured `logs.level`.
    log_threshold: telemetry.CanonicalLogLevel,
    /// `unavailable` when `report.json` is missing or has a known older version; the run
    /// still counts as an attempted workload.
    report: union(enum) { measured: Reported, unavailable },
    /// Every retained call output the production envelope parser reads, in call order.
    responses: []const Response = &.{},
    /// Null when the run has no feature event log.
    events: ?Events = null,
};
pub const Reported = struct {
    build: ?@import("../../../build/provenance.zig").Identity,
    outcome: Outcome,
    /// Physical sends, and reconciled operations proven never sent.
    sends: u64 = 0,
    not_sent: u64 = 0,
    actual_tokens: u128,
    usage_complete: bool,
    /// Later attempts of one request that are not runaway re-sends.
    protocol_corrections: u64 = 0,
    /// Attempts the report marks as runaway re-sends.
    resends: u64 = 0,
    admission_escape: ?admission.Metric,
    /// Each canonical repair merge: the identity a repair grade attaches to (T5(b)).
    repairs: []const Merge,
    /// Sends and tokens of each stage, from each sent attempt's request purpose and owner.
    stages: []const stages.Resources,
};

/// The report-derived measures of one run.
pub fn fromReport(a: std.mem.Allocator, report: c.Report) error{ OutOfMemory, AccountingOverflow, CaptureMismatch, InvalidReport }!Reported {
    // ADR 0041 marks only a failed or blocked run's nonempty incomplete set.
    if (report.incomplete_publication) |set| {
        if (set.len == 0 or (report.workflow_outcome != .failed and report.workflow_outcome != .blocked)) return error.InvalidReport;
        for (set, 0..) |artifact, index| if (std.mem.indexOfScalar(c.Artifact, set[0..index], artifact) != null) return error.InvalidReport;
    }
    const by_stage = try stages.empty(a);
    errdefer a.free(by_stage);
    var result: Reported = .{
        .build = if (report.build) |build| build.source else null,
        .outcome = .{
            .status = report.status,
            .workflow_outcome = report.workflow_outcome,
            .terminal_step = report.terminal_step,
            .diagnostic = report.diagnostic,
            .publication_check = report.publication_check,
            .publication = if (report.workflow_outcome == .ok and report.publication_check == .passed)
                .native
            else if (report.incomplete_publication != null) .incomplete else .none,
        },
        .actual_tokens = report.total_tokens,
        .usage_complete = report.usage_complete,
        .admission_escape = report.admission_escape,
        .repairs = report.repairs,
        .stages = by_stage,
    };
    for (report.attempts) |attempt| {
        if (attempt.accounting == .not_sent) {
            result.not_sent += 1;
            continue;
        }
        result.sends += 1;
        try stages.add(by_stage, attempt.purpose, attempt.owner_kind, attempt.usage);
        if (attempt.resends != null) {
            result.resends += 1;
        } else if (attempt.origin.attempt.value > 1) result.protocol_corrections += 1;
    }
    try stages.share(by_stage);
    return result;
}

/// A response's structure, read through the production envelope parser. Null for a
/// response that doesn't parse to an object, or a `records` or `claims` response without
/// its array; an `entities` response without a known disposition or an array keeps them
/// null.
pub fn structure(a: std.mem.Allocator, output: []const u8) error{OutOfMemory}!?Structure {
    var document = envelope.parseContent(a, output, null) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    defer document.deinit();
    const value = document.parsed.value;
    if (value != .object) return null;
    var result: Structure = .{ .shape = .other };
    try countFragments(a, value, &result);
    const kind = value.object.get(wire.discriminator) orelse return result;
    if (kind != .string) return result;
    if (std.mem.eql(u8, kind.string, wire.records)) {
        const records = value.object.get(wire.records_array) orelse return null;
        if (records != .array) return null;
        result.shape = .{ .records = try recordKinds(a, records.array.items) };
    } else if (std.mem.eql(u8, kind.string, wire.entities)) {
        const disposition = value.object.get(wire.disposition);
        const records = value.object.get(wire.entity_records);
        result.shape = .{ .entities = .{
            .disposition = if (disposition) |field| if (field == .string) std.meta.stringToEnum(spec.Applicability, field.string) else null else null,
            .records = if (records) |field| if (field == .array) field.array.items.len else null else null,
        } };
    } else if (std.mem.eql(u8, kind.string, wire.claims)) {
        const claims = value.object.get(wire.claims_array) orelse return null;
        if (claims != .array) return null;
        result.shape = .{ .claims = try claimCategories(a, claims.array.items) };
    } else if (std.mem.eql(u8, kind.string, wire.no_feature_claim)) {
        result.shape = .no_feature_claim;
    }
    return result;
}

fn recordKinds(a: std.mem.Allocator, items: []const std.json.Value) error{OutOfMemory}!Structure.Records {
    var counts: std.EnumArray(spec.Kind, u64) = .initFill(0);
    var unknown: u64 = 0;
    for (items) |item| {
        const kind = if (item == .object) if (item.object.get(wire.record_content)) |content| if (content == .object) content.object.get(wire.discriminator) else null else null else null;
        const known = if (kind) |field| if (field == .string) std.meta.stringToEnum(spec.Kind, field.string) else null else null;
        if (known) |value| counts.getPtr(value).* += 1 else unknown += 1;
    }
    var kinds: std.ArrayList(KindCount) = .empty;
    for (std.meta.tags(spec.Kind)) |value| if (counts.get(value) != 0) try kinds.append(a, .{ .kind = value, .count = counts.get(value) });
    return .{ .total = items.len, .kinds = try kinds.toOwnedSlice(a), .unknown = unknown };
}

fn claimCategories(a: std.mem.Allocator, items: []const std.json.Value) error{OutOfMemory}!Structure.Claims {
    var counts: std.EnumArray(claim.Kind, u64) = .initFill(0);
    var unknown: u64 = 0;
    for (items) |item| {
        const category = if (item == .object) item.object.get(wire.category) else null;
        const known = if (category) |field| if (field == .string) std.meta.stringToEnum(claim.Kind, field.string) else null else null;
        if (known) |value| counts.getPtr(value).* += 1 else unknown += 1;
    }
    var categories: std.ArrayList(CategoryCount) = .empty;
    for (std.meta.tags(claim.Kind)) |value| if (counts.get(value) != 0) try categories.append(a, .{ .category = value, .count = counts.get(value) });
    return .{ .total = items.len, .categories = try categories.toOwnedSlice(a), .unknown = unknown };
}

/// Counts the typed-text wire's composition objects, read by its own owner, anywhere in
/// a response; a counted object's fragments aren't searched again.
fn countFragments(a: std.mem.Allocator, value: std.json.Value, result: *Structure) error{OutOfMemory}!void {
    switch (value) {
        .object => |object| {
            if (try text_wire.compositionNodes(a, value)) |nodes| {
                defer a.free(nodes);
                result.fragments += 1;
                for (nodes) |node| {
                    if (node != .literal) break;
                } else result.literal_fragments += 1;
                return;
            }
            var fields = object.iterator();
            while (fields.next()) |field| try countFragments(a, field.value_ptr.*, result);
        },
        .array => |array| for (array.items) |item| try countFragments(a, item, result),
        else => {},
    }
}

/// Counts from the feature event log's segments, in order. Each segment is read as the
/// feature log format writes it: its heading, a segment header, event records with
/// consecutive sequences and, once closed, its trailer. Every row is complete and of
/// this format's schema version, event stream and column version; anything else
/// rejects.
pub fn events(a: std.mem.Allocator, segments: []const []const u8) Error!Events {
    var result: Events = .{};
    var protocol: std.ArrayList(ReasonCount) = .empty;
    var schema: std.ArrayList(ReasonCount) = .empty;
    var validation: std.ArrayList(ReasonCount) = .empty;
    var code_buffer: [96]u8 = undefined;
    const output_limit = event_capture.diagnostic(&code_buffer, @tagName(provider.ProviderNonCandidateStopReason.output_limit)).?.bytes;
    var first: ?u64 = null;
    var last: u64 = 0;
    for (segments) |segment| {
        const heading = log_format.event_heading;
        if (segment.len <= heading.len or !std.mem.startsWith(u8, segment, heading) or segment[segment.len - 1] != '\n') return error.InvalidFeatureLog;
        var rows = std.mem.splitScalar(u8, segment[heading.len .. segment.len - 1], '\n');
        const header = rows.next() orelse return error.InvalidFeatureLog;
        try versioned(a, header);
        log_format.validatePersistedControlRow(header, .segment_header, .event, null) catch return error.InvalidFeatureLog;
        var sequence: ?u64 = null;
        var closed = false;
        while (rows.next()) |row| {
            if (closed) return error.InvalidFeatureLog;
            try versioned(a, row);
            const kind = log_format.cellAt(row, columns.record_kind) orelse return error.InvalidFeatureLog;
            if (std.mem.eql(u8, kind, @tagName(log_format.ControlKind.segment_trailer))) {
                // A segment with no record states its own final sequence.
                const final = sequence orelse try number(row, columns.sequence);
                log_format.validatePersistedControlRow(row, .segment_trailer, .event, final) catch return error.InvalidFeatureLog;
                closed = true;
                continue;
            }
            if (!std.mem.eql(u8, kind, @tagName(log_stream.Stream.event))) return error.InvalidFeatureLog;
            const next = try number(row, columns.sequence);
            if (sequence) |prior| if (next != std.math.add(u64, prior, 1) catch return error.InvalidFeatureLog) return error.InvalidFeatureLog;
            sequence = next;
            const offset = try number(row, columns.monotonic_offset);
            first = @min(first orelse offset, offset);
            last = @max(last, offset);
            const code = log_format.cellAt(row, columns.diagnostic_code) orelse return error.InvalidFeatureLog;
            switch (try eventType(row)) {
                .model_provider_stopped => if (std.mem.eql(u8, code, output_limit)) {
                    result.runaways += 1;
                },
                .model_runaway_resent => result.resends += 1,
                .model_response_normalized => result.normalized_responses += 1,
                .model_protocol_failed => try count(a, &protocol, code),
                .model_schema_failed => try count(a, &schema, code),
                .validation_failed => try count(a, &validation, code),
                else => {},
            }
        }
    }
    result.protocol_rejections = try protocol.toOwnedSlice(a);
    result.schema_rejections = try schema.toOwnedSlice(a);
    result.validation_failures = try validation.toOwnedSlice(a);
    result.latency_ms = if (first) |start| last - start else null;
    return result;
}

/// A complete row of this format's schema version, event stream and column version.
fn versioned(a: std.mem.Allocator, row: []const u8) Error!void {
    const encoded = try std.mem.concat(a, u8, &.{ row, "\n" });
    defer a.free(encoded);
    log_format.validateEncodedRow(a, encoded, log_format.event_column_count) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidFeatureLogRecord => error.InvalidFeatureLog,
    };
    for ([_]struct { usize, []const u8 }{
        .{ columns.schema_version, log_limits.schema_version },
        .{ columns.stream, @tagName(log_stream.Stream.event) },
        .{ columns.column_schema_id, log_limits.event_column_schema_id },
    }) |expected| {
        if (!std.mem.eql(u8, log_format.cellAt(row, expected[0]) orelse return error.InvalidFeatureLog, expected[1])) return error.InvalidFeatureLog;
    }
}
fn number(row: []const u8, column: usize) Error!u64 {
    return std.fmt.parseInt(u64, log_format.cellAt(row, column) orelse return error.InvalidFeatureLog, 10) catch error.InvalidFeatureLog;
}
fn eventType(row: []const u8) Error!telemetry.EventType {
    const cell = log_format.cellAt(row, columns.event_type) orelse return error.InvalidFeatureLog;
    for (std.enums.values(telemetry.EventType)) |event_type| {
        if (std.mem.eql(u8, cell, event_type.text())) return event_type;
    }
    return error.InvalidFeatureLog;
}
fn count(a: std.mem.Allocator, counts: *std.ArrayList(ReasonCount), reason: []const u8) error{OutOfMemory}!void {
    for (counts.items) |*existing| {
        if (std.mem.eql(u8, existing.reason, reason)) {
            existing.count += 1;
            return;
        }
    }
    try counts.append(a, .{ .reason = try a.dupe(u8, reason), .count = 1 });
}
/// The feature log format owns the column order.
const columns = struct {
    const record_kind = column("record_kind");
    const schema_version = column("schema_version");
    const stream = column("stream");
    const column_schema_id = column("column_schema_id");
    const sequence = column("sequence");
    const monotonic_offset = column("monotonic_offset");
    const event_type = column("event_type");
    const diagnostic_code = column("diagnostic_code");

    fn column(comptime name: []const u8) usize {
        @setEvalBranchQuota(20_000);
        var cells = std.mem.splitScalar(u8, std.mem.trimEnd(u8, log_format.event_heading, "\n"), '|');
        var index: usize = 0;
        while (cells.next()) |cell| : (index += 1) {
            if (std.mem.eql(u8, cell, name)) return index;
        }
        unreachable;
    }
};

/// Minimum, median and maximum of one measure over its `values` (a case's runs, or its
/// records calls); the median of an even count is the mean of the middle two.
pub const Spread = struct { values: u64 = 0, minimum: ?f64 = null, median: ?f64 = null, maximum: ?f64 = null };
/// Events pooled over a case's runs with the opportunities they occurred among (§2.5).
pub const Pooled = struct { events: u64 = 0, opportunities: u64 = 0 };
/// One stage's sends and actual tokens over a case's measured runs; a run whose stage
/// usage is unknown adds no token value.
pub const StageSpread = struct { stage: stages.Stage, sends: Spread = .{}, actual_tokens: Spread = .{} };
pub const CaseSet = struct {
    case_id: []const u8,
    /// The one log threshold of the case's measured runs; null when none was measured.
    log_threshold: ?telemetry.CanonicalLogLevel = null,
    /// Every run, including unmeasurable ones and those whose report is unavailable.
    attempted: u64 = 0,
    /// Runs that couldn't be measured: nothing about them is known.
    unmeasurable: u64 = 0,
    /// Measured runs whose report is unavailable: their outcome and sends are unknown.
    report_unavailable: u64 = 0,
    sends: Spread = .{},
    actual_tokens: Spread = .{},
    protocol_corrections: Spread = .{},
    resends: Spread = .{},
    runaways: Spread = .{},
    admission_rejections: Spread = .{},
    repairs: Spread = .{},
    latency_ms: Spread = .{},
    /// Over every records response of the case's runs.
    records_per_call: Spread = .{},
    /// For each record kind, runs whose final records responses (each request's last
    /// attempt) hold at least one record of it, over runs with a final records response.
    record_kinds: []const KindPresence = &.{},
    /// Runs whose final entities response says `required`, over runs whose final entities
    /// response has a known disposition.
    entities_required: Pooled = .{},
    /// `no_feature_claim` responses over extraction responses, every attempt.
    no_feature_claim: Pooled = .{},
    /// Claims of each category in final claims responses, over their claims.
    claim_categories: []const CategoryShare = &.{},
    /// Responses holding a literal-only fragments object, over responses.
    literal_fragments: Pooled = .{},
    /// One entry per stage.
    stages: []const StageSpread = &.{},
    pooled: struct {
        /// Native publications per attempted run. A run whose outcome is unknown is an
        /// attempt and never a publication; `unmeasurable` and `report_unavailable` count
        /// those beside it.
        published: Pooled = .{},
        /// Protocol corrections, re-sends, runaway stops and admission rejections, each
        /// per send.
        protocol_corrections: Pooled = .{},
        resends: Pooled = .{},
        runaways: Pooled = .{},
        admission_rejections: Pooled = .{},
        /// Escaped values per admitted value (the admission audit's own measure).
        escaped_values: Pooled = .{},
        /// Repairs that changed their value per repair.
        changed_repairs: Pooled = .{},
    } = .{},
};
pub const KindPresence = struct { kind: spec.Kind, runs: Pooled };
pub const CategoryShare = struct { category: claim.Kind, claims: Pooled };
pub const Set = struct {
    schema: enum { @"e2e-measures-set/v2" } = .@"e2e-measures-set/v2",
    runs: []const []const u8,
    cases: []const CaseSet,
};

/// The first case whose measured runs use two log thresholds.
pub const ThresholdConflict = struct { case_id: []const u8, first: telemetry.CanonicalLogLevel, second: telemetry.CanonicalLogLevel };

/// Each case's runs must share one log threshold: the counts that depend on it compare
/// only at one level. A conflict, when requested, names the case and both levels.
pub fn summarize(a: std.mem.Allocator, runs: []const Run, conflict: ?*ThresholdConflict) error{ OutOfMemory, MixedLogThresholds }!Set {
    var names: std.ArrayList([]const u8) = .empty;
    var cases: std.ArrayList(CaseSet) = .empty;
    for (runs) |run| {
        try names.append(a, run.run);
        const exists = for (cases.items) |existing| {
            if (std.mem.eql(u8, existing.case_id, run.case_id)) break true;
        } else false;
        if (!exists) try cases.append(a, try summarizeCase(a, run.case_id, runs, conflict));
    }
    return .{ .runs = try names.toOwnedSlice(a), .cases = try cases.toOwnedSlice(a) };
}

const Measure = enum { sends, actual_tokens, protocol_corrections, resends, runaways, admission_rejections, repairs, latency_ms, records_per_call };

fn summarizeCase(a: std.mem.Allocator, id: []const u8, runs: []const Run, conflict: ?*ThresholdConflict) error{ OutOfMemory, MixedLogThresholds }!CaseSet {
    var result: CaseSet = .{ .case_id = id };
    var values: std.EnumArray(Measure, std.ArrayList(f64)) = .initFill(.empty);
    var stage_sends: std.EnumArray(stages.Stage, std.ArrayList(f64)) = .initFill(.empty);
    var stage_tokens: std.EnumArray(stages.Stage, std.ArrayList(f64)) = .initFill(.empty);
    var kind_runs: std.EnumArray(spec.Kind, u64) = .initFill(0);
    var records_runs: u64 = 0;
    var category_claims: std.EnumArray(claim.Kind, u64) = .initFill(0);
    var final_claims: u64 = 0;
    for (runs) |run| {
        if (!std.mem.eql(u8, run.case_id, id)) continue;
        result.attempted += 1;
        const measured = switch (run.measurement) {
            .measured => |value| value,
            .unmeasurable => {
                result.unmeasurable += 1;
                result.pooled.published = add(result.pooled.published, 0, 1);
                continue;
            },
        };
        if (result.log_threshold) |threshold| if (threshold != measured.log_threshold) {
            if (conflict) |out| out.* = .{ .case_id = id, .first = threshold, .second = measured.log_threshold };
            return error.MixedLogThresholds;
        };
        result.log_threshold = measured.log_threshold;
        const native = switch (measured.report) {
            .measured => |reported| reported.outcome.publication == .native,
            .unavailable => false,
        };
        result.pooled.published = add(result.pooled.published, @intFromBool(native), 1);
        for (measured.responses) |response| {
            const shape = response.structure orelse continue;
            switch (shape.shape) {
                .records => |records| try values.getPtr(.records_per_call).append(a, @floatFromInt(records.total)),
                .claims => result.no_feature_claim = add(result.no_feature_claim, 0, 1),
                .no_feature_claim => result.no_feature_claim = add(result.no_feature_claim, 1, 1),
                .entities, .other => {},
            }
            result.literal_fragments = add(result.literal_fragments, @intFromBool(shape.literal_fragments != 0), 1);
        }
        var present: std.EnumSet(spec.Kind) = .initEmpty();
        var has_records = false;
        var disposition: ?spec.Applicability = null;
        // A request whose last attempt left no structure contributes nothing: an earlier,
        // rejected attempt is never taken for it.
        for (measured.responses, 0..) |response, index| {
            if (!lastAttempt(measured.responses, index)) continue;
            const shape = response.structure orelse continue;
            switch (shape.shape) {
                .records => |records| {
                    has_records = true;
                    for (records.kinds) |entry| present.insert(entry.kind);
                },
                .entities => |entities| if (entities.disposition) |value| {
                    disposition = value;
                },
                .claims => |claims| {
                    final_claims += claims.total;
                    for (claims.categories) |entry| category_claims.getPtr(entry.category).* += entry.count;
                },
                .no_feature_claim, .other => {},
            }
        }
        if (has_records) {
            records_runs += 1;
            for (std.meta.tags(spec.Kind)) |kind| kind_runs.getPtr(kind).* += @intFromBool(present.contains(kind));
        }
        if (disposition) |value| result.entities_required = add(result.entities_required, @intFromBool(value == .required), 1);
        if (measured.events) |logged| {
            try values.getPtr(.runaways).append(a, @floatFromInt(logged.runaways));
            try values.getPtr(.admission_rejections).append(a, @floatFromInt(logged.admissionRejections()));
            if (logged.latency_ms) |latency| try values.getPtr(.latency_ms).append(a, @floatFromInt(latency));
        }
        const reported = switch (measured.report) {
            .measured => |value| value,
            .unavailable => {
                result.report_unavailable += 1;
                continue;
            },
        };
        try values.getPtr(.sends).append(a, @floatFromInt(reported.sends));
        try values.getPtr(.actual_tokens).append(a, @floatFromInt(reported.actual_tokens));
        try values.getPtr(.protocol_corrections).append(a, @floatFromInt(reported.protocol_corrections));
        try values.getPtr(.resends).append(a, @floatFromInt(reported.resends));
        try values.getPtr(.repairs).append(a, @floatFromInt(reported.repairs.len));
        for (reported.stages) |stage| {
            try stage_sends.getPtr(stage.stage).append(a, @floatFromInt(stage.physical_sends));
            if (stage.actual_tokens) |tokens| try stage_tokens.getPtr(stage.stage).append(a, @floatFromInt(tokens));
        }
        result.pooled.protocol_corrections = add(result.pooled.protocol_corrections, reported.protocol_corrections, reported.sends);
        result.pooled.resends = add(result.pooled.resends, reported.resends, reported.sends);
        if (measured.events) |logged| {
            result.pooled.runaways = add(result.pooled.runaways, logged.runaways, reported.sends);
            result.pooled.admission_rejections = add(result.pooled.admission_rejections, logged.admissionRejections(), reported.sends);
        }
        if (reported.admission_escape) |escape| if (escape.status == .measured) {
            result.pooled.escaped_values = add(result.pooled.escaped_values, escape.escaped_values, escape.admitted_values);
        };
        var changed: u64 = 0;
        for (reported.repairs) |repair| changed += @intFromBool(repair.changed);
        result.pooled.changed_repairs = add(result.pooled.changed_repairs, changed, reported.repairs.len);
    }
    inline for (comptime std.enums.values(Measure)) |measure| @field(result, @tagName(measure)) = spread(values.getPtr(measure).items);
    const by_stage = try a.alloc(StageSpread, std.meta.tags(stages.Stage).len);
    for (std.meta.tags(stages.Stage), by_stage) |stage, *value| value.* = .{
        .stage = stage,
        .sends = spread(stage_sends.getPtr(stage).items),
        .actual_tokens = spread(stage_tokens.getPtr(stage).items),
    };
    result.stages = by_stage;
    if (records_runs != 0) {
        const presence = try a.alloc(KindPresence, std.meta.tags(spec.Kind).len);
        for (std.meta.tags(spec.Kind), presence) |kind, *value| value.* = .{ .kind = kind, .runs = .{ .events = kind_runs.get(kind), .opportunities = records_runs } };
        result.record_kinds = presence;
    }
    if (final_claims != 0) {
        const shares = try a.alloc(CategoryShare, std.meta.tags(claim.Kind).len);
        for (std.meta.tags(claim.Kind), shares) |category, *value| value.* = .{ .category = category, .claims = .{ .events = category_claims.get(category), .opportunities = final_claims } };
        result.claim_categories = shares;
    }
    return result;
}

/// Whether a response is its request's last attempt in the run.
fn lastAttempt(responses: []const Response, index: usize) bool {
    const origin = responses[index].origin;
    for (responses) |other| {
        if (other.origin.request.value == origin.request.value and other.origin.attempt.value > origin.attempt.value) return false;
    }
    return true;
}

fn add(pooled: Pooled, observed: u64, opportunities: u64) Pooled {
    return .{ .events = pooled.events + observed, .opportunities = pooled.opportunities + opportunities };
}
fn spread(values: []f64) Spread {
    if (values.len == 0) return .{};
    std.mem.sort(f64, values, {}, std.sort.asc(f64));
    const middle = values.len / 2;
    const median = if (values.len % 2 == 1) values[middle] else (values[middle - 1] + values[middle]) / 2;
    return .{ .values = values.len, .minimum = values[0], .median = median, .maximum = values[values.len - 1] };
}

const testing = std.testing;
const strict = @import("../../../src/domain/strict_json.zig");

fn testAttempt(request: u32, ordinal: u32, resends: ?u32, purpose: stages.Purpose, owner: stages.OwnerKind, accounting: @FieldType(c.Attempt, "accounting")) c.Attempt {
    return .{
        .origin = .{ .request = .{ .value = request }, .attempt = .{ .value = ordinal } },
        .step = "step",
        .purpose = purpose,
        .owner_kind = owner,
        .resends = resends,
        .accounting = accounting,
        .usage = if (accounting == .exact_usage) provider.ProviderUsage.init(10, 5, 15).? else null,
    };
}

test "report measures separate sends, corrections, re-sends, stages and publication" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const attempts = [_]c.Attempt{
        testAttempt(1, 1, null, .initial_generation, .reference_chunk, .exact_usage),
        testAttempt(1, 2, null, .initial_generation, .reference_chunk, .exact_usage), // protocol correction
        testAttempt(2, 1, null, .atomic_repair, .specification_unit, .exact_usage), // runaway
        testAttempt(2, 2, 1, .atomic_repair, .specification_unit, .unavailable), // its re-send
        testAttempt(3, 1, null, .semantic_review, .semantic_review, .not_sent),
    };
    const report: c.Report = .{ .schema = .@"spec-e2e-report/v15", .started_at_utc = "", .status = .workflow_failed, .workflow_outcome = .failed, .terminal_step = "g9-reconcile", .diagnostic = "RepairNoProgress", .attempts = &attempts, .total_tokens = 45 };
    const measured = try fromReport(a, report);
    try testing.expectEqual(@as(u64, 4), measured.sends);
    try testing.expectEqual(@as(u64, 1), measured.not_sent);
    try testing.expectEqual(@as(u64, 1), measured.protocol_corrections);
    try testing.expectEqual(@as(u64, 1), measured.resends);
    try testing.expectEqual(Outcome.Publication.none, measured.outcome.publication);
    try testing.expectEqualStrings("g9-reconcile", measured.outcome.terminal_step.?);
    try testing.expectEqualStrings("RepairNoProgress", measured.outcome.diagnostic.?);
    // Each sent attempt counts in its request's stage; a send without usage leaves its
    // stage's actual tokens unknown, and an unsent attempt counts in none.
    const extraction = measured.stages[@intFromEnum(stages.Stage.extraction_grouping)];
    try testing.expectEqual(@as(u64, 2), extraction.physical_sends);
    try testing.expectEqual(@as(?u64, 30), extraction.actual_tokens);
    const repair = measured.stages[@intFromEnum(stages.Stage.repair)];
    try testing.expectEqual(@as(u64, 2), repair.physical_sends);
    try testing.expectEqual(@as(?u64, null), repair.actual_tokens);
    try testing.expectEqual(@as(u64, 15), repair.known_actual_tokens);
    try testing.expectEqual(@as(?f64, 0.5), repair.send_share);
    try testing.expectEqual(@as(u64, 0), measured.stages[@intFromEnum(stages.Stage.review)].physical_sends);
    // Publication comes from the outcome and the publication check, never from status text.
    var published = report;
    published.workflow_outcome = .ok;
    published.publication_check = .passed;
    try testing.expectEqual(Outcome.Publication.native, (try fromReport(a, published)).outcome.publication);
    // A failed run's recorded specification is never a publication.
    var recorded = report;
    recorded.specification = "specs/loan-renewal/spec.md";
    try testing.expectEqual(Outcome.Publication.none, (try fromReport(a, recorded)).outcome.publication);
    // ADR 0041's marked incomplete set is its own class, for a failed or blocked run only.
    var incomplete = report;
    incomplete.incomplete_publication = &.{ .specification, .reference_context };
    try testing.expectEqual(Outcome.Publication.incomplete, (try fromReport(a, incomplete)).outcome.publication);
    incomplete.workflow_outcome = .blocked;
    try testing.expectEqual(Outcome.Publication.incomplete, (try fromReport(a, incomplete)).outcome.publication);
    for ([_]?@import("../../../src/domain/workflow.zig").OutcomeTag{ .ok, .more, .needs_user, .invalid, .cancelled, null }) |outcome| {
        incomplete.workflow_outcome = outcome;
        try testing.expectError(error.InvalidReport, fromReport(a, incomplete));
    }
    incomplete.workflow_outcome = .failed;
    for ([_][]const c.Artifact{ &.{}, &.{ .specification, .specification } }) |set| {
        incomplete.incomplete_publication = set;
        try testing.expectError(error.InvalidReport, fromReport(a, incomplete));
    }
    // Usage whose total isn't its input plus output rejects.
    var inconsistent = attempts;
    inconsistent[0].usage = .{ .input_tokens = 10, .output_tokens = 5, .total_tokens = 16 };
    var mismatched = report;
    mismatched.attempts = &inconsistent;
    try testing.expectError(error.CaptureMismatch, fromReport(a, mismatched));
}

test "a response's structure comes from its discriminator and closed kinds, never its prose" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Records by kind, behind the provider's malformed opening; a record without a known
    // kind counts apart.
    const records = (try structure(a, "{\"{ \"kind\":\"records\",\"records\":[{\"content\":{\"kind\":\"edge_case\",\"condition\":\"acceptance_criterion\"}},{\"content\":{\"kind\":\"functional_requirement\",\"text\":\"edge_case\"}},{\"content\":{\"kind\":\"edge_case\"}},{\"content\":{\"kind\":\"story\"}},{\"text\":\"a\"}]}")).?;
    try testing.expectEqualDeep(Structure.Shape{ .records = .{ .total = 5, .kinds = &.{ .{ .kind = .edge_case, .count = 2 }, .{ .kind = .functional_requirement, .count = 1 } }, .unknown = 2 } }, records.shape);
    try testing.expectEqualDeep(Structure.Shape{ .records = .{ .total = 0 } }, (try structure(a, "{\"kind\":\"records\",\"records\":[]}")).?.shape);
    // The entities decision and its records; an unknown disposition is null.
    try testing.expectEqualDeep(Structure.Shape{ .entities = .{ .disposition = .required, .records = 1 } }, (try structure(a, "{\"kind\":\"entities\",\"disposition\":\"required\",\"basis\":{\"value\":\"not_applicable\"},\"records\":[{}]}")).?.shape);
    try testing.expectEqualDeep(Structure.Shape{ .entities = .{ .disposition = .not_applicable, .records = 0 } }, (try structure(a, "{\"kind\":\"entities\",\"disposition\":\"not_applicable\",\"records\":[]}")).?.shape);
    try testing.expectEqualDeep(Structure.Shape{ .entities = .{ .disposition = null, .records = null } }, (try structure(a, "{\"kind\":\"entities\",\"disposition\":\"maybe\"}")).?.shape);
    // Extraction outcomes and claims by category.
    try testing.expectEqualDeep(Structure.Shape{ .claims = .{ .total = 3, .categories = &.{ .{ .category = .business, .count = 1 }, .{ .category = .scope_guard, .count = 1 } }, .unknown = 1 } }, (try structure(a, "{\"kind\":\"claims\",\"claims\":[{\"category\":\"scope_guard\",\"citations\":[1]},{\"category\":\"business\",\"citations\":[2]},{\"category\":\"edge_case\"}]}")).?.shape);
    try testing.expectEqual(Structure.Shape.no_feature_claim, (try structure(a, "{\"kind\":\"no_feature_claim\",\"reason\":{\"nodes\":\"claims\"}}")).?.shape);
    // Fragments objects, read by the text wire's owner; literal-only ones count apart.
    const story = (try structure(a, "{\"kind\":\"primary_user_story\",\"value\":{\"fragments\":[\"A\",\"B\"]},\"signal_ids\":[1]}")).?;
    try testing.expectEqual(Structure.Shape.other, story.shape);
    try testing.expectEqual(@as(u64, 1), story.fragments);
    try testing.expectEqual(@as(u64, 1), story.literal_fragments);
    const inserted = (try structure(a, "{\"kind\":\"brief\",\"title\":{\"fragments\":[\"Run \",{\"kind\":\"passive\",\"passive_literal_id\":1}]},\"goal\":\"fragments\"}")).?;
    try testing.expectEqual(@as(u64, 1), inserted.fragments);
    try testing.expectEqual(@as(u64, 0), inserted.literal_fragments);
    // A field named `fragments` beside others is not the wire's composition object.
    try testing.expectEqual(@as(u64, 0), (try structure(a, "{\"kind\":\"brief\",\"value\":{\"fragments\":[\"A\"],\"extra\":1}}")).?.fragments);
    // A known discriminator without its array, a non-object and non-JSON have no structure.
    for ([_][]const u8{ "{\"kind\":\"records\",\"records\":\"x\"}", "{\"kind\":\"records\"}", "{\"kind\":\"claims\",\"claims\":{}}", "[\"records\"]", "not json" }) |output| {
        try testing.expectEqual(@as(?Structure, null), try structure(a, output));
    }
}

pub const Logged = struct { offset: u64, event_type: telemetry.EventType, code: ?[]const u8 = null };
const test_control: log_format.ControlRecord = .{
    .kind = .segment_header,
    .log_policy_id = .{ .bytes = "policy-1" },
    .binding_id = .{ .bytes = "LOGBIND-1" },
    .segment_ordinal = 1,
    .occurred_at_utc = "2026-10-28T00:00:00Z",
    .run_id = .{ .bytes = "RUN-1" },
    .feature_id = .{ .bytes = "feature" },
};

/// One event row as the feature log writer serializes it, with the fields its event
/// type requires.
fn eventRow(a: std.mem.Allocator, sequence: u64, record: Logged) ![]const u8 {
    const required = @import("../../../src/domain/log_event_registry.zig").eventDefinition(record.event_type).required;
    const id: telemetry.Identifier = .{ .bytes = "test" };
    var event_id: [32]u8 = undefined;
    return log_format.serializeEvent(a, .{
        .log_policy_id = test_control.log_policy_id,
        .binding_id = test_control.binding_id,
        .segment_ordinal = test_control.segment_ordinal,
        .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"),
        .event_id = log_format.eventId(&event_id, sequence).?,
        .sequence = sequence,
        .occurred_at_utc = test_control.occurred_at_utc,
        .monotonic_offset = record.offset,
        .run_id = test_control.run_id,
        .feature_id = test_control.feature_id,
        .fact = .{ .event_type = record.event_type, .fields = .{
            .outcome = if (required.contains(.outcome)) .failed else null,
            .diagnostic_code = if (record.code) |code| telemetry.DiagnosticCode.validate(code).? else null,
            .validator_id = if (required.contains(.validator_id)) id else null,
            .model_route_id = if (required.contains(.model_route_id)) id else null,
            .model_profile_id = if (required.contains(.model_profile_id)) id else null,
        } },
    });
}

/// One segment as the feature log writer encodes it, its records numbered from `first`.
pub fn testSegment(a: std.mem.Allocator, first: u64, records: []const Logged, closed: bool) ![]const u8 {
    var bytes: std.ArrayList(u8) = .empty;
    try bytes.appendSlice(a, log_format.event_heading);
    try bytes.appendSlice(a, try log_format.serializeControl(a, .event, test_control));
    for (records, 0..) |record, index| try bytes.appendSlice(a, try eventRow(a, first + index, record));
    if (closed) {
        var trailer = test_control;
        trailer.kind = .segment_trailer;
        trailer.final_sequence = first + records.len - 1;
        try bytes.appendSlice(a, try log_format.serializeControl(a, .event, trailer));
    }
    return bytes.toOwnedSlice(a);
}

test "feature log events count runaways, re-sends, rejections by reason and latency" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const first = try testSegment(a, 1, &.{
        .{ .offset = 1000, .event_type = .run_started },
        .{ .offset = 1500, .event_type = .model_provider_stopped, .code = "OUTPUT_LIMIT" },
        .{ .offset = 1600, .event_type = .model_provider_stopped, .code = "CONTENT_FILTERED" },
        .{ .offset = 1700, .event_type = .model_runaway_resent, .code = "OUTPUT_LIMIT" },
    }, true);
    const second = try testSegment(a, 5, &.{
        .{ .offset = 2000, .event_type = .model_protocol_failed, .code = "JSON_SYNTAX" },
        .{ .offset = 2100, .event_type = .model_schema_failed, .code = "TYPE_MISMATCH" },
        .{ .offset = 2200, .event_type = .model_protocol_failed, .code = "JSON_SYNTAX" },
        .{ .offset = 2300, .event_type = .model_response_normalized, .code = "REMOVED_LEADING_BRACE_QUOTE" },
        .{ .offset = 2400, .event_type = .validation_failed, .code = "RECONCILIATION" },
    }, false);
    const counted = try events(a, &.{ first, second });
    try testing.expectEqual(@as(u64, 1), counted.runaways);
    try testing.expectEqual(@as(u64, 1), counted.resends);
    try testing.expectEqual(@as(u64, 1), counted.normalized_responses);
    try testing.expectEqual(@as(?u64, 1400), counted.latency_ms);
    try testing.expectEqual(@as(u64, 3), counted.admissionRejections());
    try testing.expectEqualDeep(@as([]const ReasonCount, &.{.{ .reason = "JSON_SYNTAX", .count = 2 }}), counted.protocol_rejections);
    try testing.expectEqualDeep(@as([]const ReasonCount, &.{.{ .reason = "TYPE_MISMATCH", .count = 1 }}), counted.schema_rejections);
    try testing.expectEqualDeep(@as([]const ReasonCount, &.{.{ .reason = "RECONCILIATION", .count = 1 }}), counted.validation_failures);
    // A closed segment without records states its own final sequence.
    var empty = test_control;
    empty.kind = .segment_trailer;
    empty.final_sequence = 9;
    const unrecorded = try std.mem.concat(a, u8, &.{ log_format.event_heading, try log_format.serializeControl(a, .event, test_control), try log_format.serializeControl(a, .event, empty) });
    try testing.expectEqual(@as(?u64, null), (try events(a, &.{unrecorded})).latency_ms);
    try testing.expectEqual(@as(?u64, null), (try events(a, &.{})).latency_ms);
}

test "a feature log row that isn't this format's closed, versioned record rejects" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const records = [_]Logged{
        .{ .offset = 10, .event_type = .run_started },
        .{ .offset = 20, .event_type = .model_response_normalized, .code = "REMOVED_LEADING_BRACE_QUOTE" },
    };
    const closed = try testSegment(a, 1, &records, true);
    const open = try testSegment(a, 1, &records, false);
    _ = try events(a, &.{closed});
    _ = try events(a, &.{open});
    const later = try eventRow(a, 3, records[0]);
    const long_code = try a.alloc(u8, log_limits.max_record_bytes);
    @memset(long_code, 'A');
    for ([_][]const u8{
        // Short and long rows.
        try std.mem.concat(a, u8, &.{ open, "event|1|2\n" }),
        try std.mem.concat(a, u8, &.{ open, later[0 .. later.len - 1], "|\\N\n" }),
        try std.mem.replaceOwned(u8, a, open, "REMOVED_LEADING_BRACE_QUOTE", long_code),
        // An unknown record kind, schema version, stream or column schema.
        try std.mem.replaceOwned(u8, a, open, "\nevent|", "\nmetric|"),
        try std.mem.replaceOwned(u8, a, open, "|" ++ log_limits.schema_version ++ "|", "|feature-log/v1|"),
        try std.mem.replaceOwned(u8, a, open, "|" ++ log_limits.schema_version ++ "|event|", "|" ++ log_limits.schema_version ++ "|prompt|"),
        try std.mem.replaceOwned(u8, a, open, "|" ++ log_limits.event_column_schema_id ++ "|", "|event-columns/v1|"),
        // An unregistered event type.
        try std.mem.replaceOwned(u8, a, open, "|model.response_normalized|", "|model.response_rewritten|"),
        // A missing heading or header, a row after the trailer, a sequence gap and a
        // partial final row.
        open[log_format.event_heading.len..],
        try std.mem.concat(a, u8, &.{ log_format.event_heading, later }),
        try std.mem.concat(a, u8, &.{ closed, later }),
        try std.mem.concat(a, u8, &.{ open, try eventRow(a, 4, records[0]) }),
        open[0 .. open.len - 1],
        log_format.event_heading,
        "",
    }) |segment| try testing.expectError(error.InvalidFeatureLog, events(a, &.{ closed, segment }));
}

test "measures and set summaries are closed, versioned documents" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const limits: strict.Limits = .{ .maximum_depth = 64 };
    const reported = try fromReport(a, .{ .schema = .@"spec-e2e-report/v15", .started_at_utc = "", .status = .generated, .workflow_outcome = .ok, .publication_check = .passed });
    const measured: Run = .{ .run = "run", .case_id = "case", .measurement = .{ .measured = .{ .log_threshold = .warning, .report = .{ .measured = reported }, .events = .{ .runaways = 1 } } } };
    const encoded = try std.json.Stringify.valueAlloc(a, measured, .{});
    try testing.expectEqualDeep(measured, try strict.decode(Run, a, encoded, limits));
    // Unknown and missing members reject; the decoder requires every member.
    try testing.expectError(error.InvalidJsonDocument, strict.decode(Run, a, try std.mem.replaceOwned(u8, a, encoded, "\"run\":\"run\"", "\"run\":\"run\",\"grade\":1"), limits));
    try testing.expectError(error.InvalidJsonDocument, strict.decode(Run, a, try std.mem.replaceOwned(u8, a, encoded, "\"run\":\"run\",", ""), limits));
    try testing.expect(std.meta.isError(strict.decode(Run, a, try std.mem.replaceOwned(u8, a, encoded, "e2e-measures/v2", "e2e-measures/v1"), limits)));
    const unavailable: Run = .{ .run = "old", .case_id = "case", .measurement = .{ .measured = .{ .log_threshold = .warning, .report = .unavailable } } };
    const unmeasurable: Run = .{ .run = "cut", .case_id = "case", .measurement = .{ .unmeasurable = .{ .reason = .feature_log } } };
    for ([_]Run{ unavailable, unmeasurable }) |run| try testing.expectEqualDeep(run, try strict.decode(Run, a, try std.json.Stringify.valueAlloc(a, run, .{}), limits));
    // The reason is closed.
    const reasoned = try std.json.Stringify.valueAlloc(a, unmeasurable, .{});
    for ([_][]const u8{ "\"reason\":\"\"", "\"reason\":\"InvalidFeatureLog\"", "\"reason\":\"crashed\"" }) |reason| {
        try testing.expect(std.meta.isError(strict.decode(Run, a, try std.mem.replaceOwned(u8, a, reasoned, "\"reason\":\"feature_log\"", reason), limits)));
    }
    const set = try summarize(a, &.{ measured, unavailable, unmeasurable }, null);
    const set_bytes = try std.json.Stringify.valueAlloc(a, set, .{});
    try testing.expectEqualDeep(set, try strict.decode(Set, a, set_bytes, limits));
    try testing.expect(std.meta.isError(strict.decode(Set, a, try std.mem.replaceOwned(u8, a, set_bytes, "e2e-measures-set/v2", "e2e-measures-set/v1"), limits)));
}

test "a set summary keeps every attempt and pools events with their opportunities" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const report: c.Report = .{ .schema = .@"spec-e2e-report/v15", .started_at_utc = "", .status = .generated, .workflow_outcome = .ok, .publication_check = .passed };
    var failed_report = report;
    failed_report.status = .workflow_failed;
    failed_report.workflow_outcome = .failed;
    failed_report.publication_check = .not_run;
    var repaired = report;
    repaired.attempts = &.{
        testAttempt(1, 1, null, .atomic_repair, .specification_unit, .exact_usage),
        testAttempt(2, 1, null, .atomic_repair, .specification_unit, .unavailable),
    };
    var published = try fromReport(a, repaired);
    published.sends = 20;
    published.protocol_corrections = 2;
    var failed = try fromReport(a, failed_report);
    failed.sends = 10;
    var later = try fromReport(a, report);
    later.sends = 30;
    later.protocol_corrections = 1;
    var other = try fromReport(a, report);
    other.sends = 25;
    const records: []const Response = &.{
        .{ .call = 1, .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } }, .structure = .{ .shape = .no_feature_claim } },
        .{ .call = 2, .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 2 } }, .structure = .{ .shape = .{ .claims = .{ .total = 3, .categories = &.{ .{ .category = .business, .count = 2 }, .{ .category = .scope_guard, .count = 1 } } } } } },
        // A rejected first attempt's edge case isn't in the run's final records.
        .{ .call = 3, .origin = .{ .request = .{ .value = 4 }, .attempt = .{ .value = 1 } }, .structure = .{ .shape = .{ .records = .{ .total = 2, .kinds = &.{.{ .kind = .edge_case, .count = 2 }} } } } },
        .{ .call = 4, .origin = .{ .request = .{ .value = 4 }, .attempt = .{ .value = 2 } }, .structure = .{ .shape = .{ .records = .{ .total = 6, .kinds = &.{.{ .kind = .functional_requirement, .count = 6 }} } }, .literal_fragments = 1, .fragments = 1 } },
        .{ .call = 5, .origin = .{ .request = .{ .value = 5 }, .attempt = .{ .value = 1 } }, .structure = .{ .shape = .{ .entities = .{ .disposition = .required, .records = 1 } } } },
    };
    const other_records: []const Response = &.{
        .{ .call = 1, .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } }, .structure = .{ .shape = .{ .records = .{ .total = 1, .kinds = &.{.{ .kind = .edge_case, .count = 1 }} } } } },
        .{ .call = 2, .origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } }, .structure = .{ .shape = .{ .entities = .{ .disposition = .not_applicable, .records = 0 } } } },
    };
    const runs = [_]Run{
        .{ .run = "one", .case_id = "loan", .measurement = .{ .measured = .{ .log_threshold = .debug, .report = .{ .measured = published }, .events = .{ .runaways = 1, .latency_ms = 100 }, .responses = records } } },
        .{ .run = "two", .case_id = "loan", .measurement = .{ .measured = .{ .log_threshold = .debug, .report = .{ .measured = failed }, .events = .{ .latency_ms = 300 }, .responses = other_records } } },
        .{ .run = "three", .case_id = "loan", .measurement = .{ .measured = .{ .log_threshold = .debug, .report = .{ .measured = later }, .events = .{ .latency_ms = 200 } } } },
        // An unreadable report still counts as attempted; its log still measures.
        .{ .run = "four", .case_id = "loan", .measurement = .{ .measured = .{ .log_threshold = .debug, .report = .unavailable, .events = .{ .latency_ms = 400 } } } },
        // A run that couldn't be measured is attempted and nothing more.
        .{ .run = "six", .case_id = "loan", .measurement = .{ .unmeasurable = .{ .reason = .feature_log } } },
        .{ .run = "five", .case_id = "hello", .measurement = .{ .measured = .{ .log_threshold = .debug, .report = .{ .measured = other } } } },
    };
    const set = try summarize(a, &runs, null);
    try testing.expectEqual(@as(usize, 6), set.runs.len);
    try testing.expectEqual(@as(usize, 2), set.cases.len);
    const loan = set.cases[0];
    try testing.expectEqualStrings("loan", loan.case_id);
    try testing.expectEqual(@as(?telemetry.CanonicalLogLevel, .debug), loan.log_threshold);
    try testing.expectEqual(@as(u64, 5), loan.attempted);
    try testing.expectEqual(@as(u64, 1), loan.unmeasurable);
    try testing.expectEqual(@as(u64, 1), loan.report_unavailable);
    try testing.expectEqual(Spread{ .values = 3, .minimum = 10, .median = 20, .maximum = 30 }, loan.sends);
    try testing.expectEqual(Spread{ .values = 4, .minimum = 100, .median = 250, .maximum = 400 }, loan.latency_ms);
    // An unknown outcome is an attempted run and never a publication.
    try testing.expectEqual(Pooled{ .events = 2, .opportunities = 5 }, loan.pooled.published);
    try testing.expectEqual(Pooled{ .events = 3, .opportunities = 60 }, loan.pooled.protocol_corrections);
    try testing.expectEqual(Pooled{ .events = 1, .opportunities = 60 }, loan.pooled.runaways);
    try testing.expectEqual(Spread{ .values = 3, .minimum = 1, .median = 2, .maximum = 6 }, loan.records_per_call);
    // Presence counts each run's final attempt of every request: run one's final records
    // hold no edge case, run two's do.
    try testing.expectEqual(spec.Kind.edge_case, loan.record_kinds[@intFromEnum(spec.Kind.edge_case)].kind);
    try testing.expectEqual(Pooled{ .events = 1, .opportunities = 2 }, loan.record_kinds[@intFromEnum(spec.Kind.edge_case)].runs);
    try testing.expectEqual(Pooled{ .events = 1, .opportunities = 2 }, loan.record_kinds[@intFromEnum(spec.Kind.functional_requirement)].runs);
    try testing.expectEqual(Pooled{ .events = 1, .opportunities = 2 }, loan.entities_required);
    try testing.expectEqual(Pooled{ .events = 1, .opportunities = 2 }, loan.no_feature_claim);
    try testing.expectEqual(Pooled{ .events = 2, .opportunities = 3 }, loan.claim_categories[@intFromEnum(claim.Kind.business)].claims);
    try testing.expectEqual(Pooled{ .events = 1, .opportunities = 7 }, loan.literal_fragments);
    // A case without such responses has no presence or category entries.
    try testing.expectEqual(@as(usize, 0), set.cases[1].record_kinds.len);
    try testing.expectEqual(@as(usize, 0), set.cases[1].claim_categories.len);
    // Each measured run gives every stage a sends value, zero included; a stage of
    // unknown usage gives no token value.
    const repair = loan.stages[@intFromEnum(stages.Stage.repair)];
    try testing.expectEqual(stages.Stage.repair, repair.stage);
    try testing.expectEqual(Spread{ .values = 3, .minimum = 0, .median = 0, .maximum = 2 }, repair.sends);
    try testing.expectEqual(Spread{ .values = 2, .minimum = 0, .median = 0, .maximum = 0 }, repair.actual_tokens);
    // A run without a feature log contributes no runaway or latency value.
    try testing.expectEqual(Spread{}, set.cases[1].runaways);
    try testing.expectEqual(Pooled{ .events = 1, .opportunities = 1 }, set.cases[1].pooled.published);
    var odd = [_]f64{ 3, 1, 2 };
    try testing.expectEqual(Spread{ .values = 3, .minimum = 1, .median = 2, .maximum = 3 }, spread(&odd));
    // One case's measured runs at different log thresholds don't summarize; other cases
    // may use their own.
    var mixed = runs;
    mixed[1].measurement.measured.log_threshold = .warning;
    var conflict: ThresholdConflict = undefined;
    try testing.expectError(error.MixedLogThresholds, summarize(a, &mixed, &conflict));
    try testing.expectEqualDeep(ThresholdConflict{ .case_id = "loan", .first = .debug, .second = .warning }, conflict);
    mixed = runs;
    mixed[5].measurement.measured.log_threshold = .warning;
    _ = try summarize(a, &mixed, null);
    // A case of unmeasurable runs only has no threshold, and every run is an attempt.
    const lost = try summarize(a, &.{ runs[4], runs[4] }, null);
    try testing.expectEqual(@as(?telemetry.CanonicalLogLevel, null), lost.cases[0].log_threshold);
    try testing.expectEqual(@as(u64, 2), lost.cases[0].attempted);
    try testing.expectEqual(@as(u64, 2), lost.cases[0].unmeasurable);
    try testing.expectEqual(Pooled{ .events = 0, .opportunities = 2 }, lost.cases[0].pooled.published);
}

test "a request whose last attempt left no structure is never measured by an earlier attempt" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const report: c.Report = .{ .schema = .@"spec-e2e-report/v15", .started_at_utc = "", .status = .workflow_failed, .workflow_outcome = .failed, .publication_check = .not_run };
    const reported = try fromReport(a, report);
    // The edge case and the `required` decision sit in rejected first attempts whose
    // second attempts were cut off; another request's records give the run its records.
    const responses: []const Response = &.{
        .{ .call = 1, .origin = .{ .request = .{ .value = 4 }, .attempt = .{ .value = 1 } }, .structure = .{ .shape = .{ .records = .{ .total = 1, .kinds = &.{.{ .kind = .edge_case, .count = 1 }} } } } },
        .{ .call = 2, .origin = .{ .request = .{ .value = 4 }, .attempt = .{ .value = 2 } }, .structure = null },
        .{ .call = 3, .origin = .{ .request = .{ .value = 5 }, .attempt = .{ .value = 1 } }, .structure = .{ .shape = .{ .entities = .{ .disposition = .required, .records = 1 } } } },
        .{ .call = 4, .origin = .{ .request = .{ .value = 5 }, .attempt = .{ .value = 2 } }, .structure = null },
        .{ .call = 5, .origin = .{ .request = .{ .value = 6 }, .attempt = .{ .value = 1 } }, .structure = .{ .shape = .{ .records = .{ .total = 1, .kinds = &.{.{ .kind = .functional_requirement, .count = 1 }} } } } },
    };
    const set = try summarize(a, &.{.{ .run = "cut", .case_id = "loan", .measurement = .{ .measured = .{ .log_threshold = .debug, .report = .{ .measured = reported }, .responses = responses } } }}, null);
    const loan = set.cases[0];
    try testing.expectEqual(Pooled{ .events = 0, .opportunities = 1 }, loan.record_kinds[@intFromEnum(spec.Kind.edge_case)].runs);
    try testing.expectEqual(Pooled{ .events = 1, .opportunities = 1 }, loan.record_kinds[@intFromEnum(spec.Kind.functional_requirement)].runs);
    try testing.expectEqual(Pooled{}, loan.entities_required);
    // Every response with a structure still counts toward the per-response measures.
    try testing.expectEqual(Spread{ .values = 2, .minimum = 1, .median = 1, .maximum = 1 }, loan.records_per_call);
    try testing.expectEqual(Pooled{ .events = 0, .opportunities = 3 }, loan.literal_fragments);
}

test "response structures and their pooled counts round-trip as closed documents" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const limits: strict.Limits = .{ .maximum_depth = 64 };
    const reported = try fromReport(a, .{ .schema = .@"spec-e2e-report/v15", .started_at_utc = "", .status = .generated, .workflow_outcome = .ok, .publication_check = .passed });
    const responses: []const Response = &.{
        .{ .call = 1, .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } }, .structure = .{ .shape = .{ .claims = .{ .total = 2, .categories = &.{.{ .category = .business, .count = 2 }} } } } },
        .{ .call = 2, .origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } }, .structure = .{ .shape = .no_feature_claim } },
        .{ .call = 3, .origin = .{ .request = .{ .value = 3 }, .attempt = .{ .value = 1 } }, .structure = .{ .shape = .other, .fragments = 1, .literal_fragments = 1 } },
        .{ .call = 4, .origin = .{ .request = .{ .value = 4 }, .attempt = .{ .value = 1 } }, .structure = .{ .shape = .{ .entities = .{ .disposition = .not_applicable, .records = 0 } } } },
        .{ .call = 5, .origin = .{ .request = .{ .value = 5 }, .attempt = .{ .value = 1 } }, .structure = .{ .shape = .{ .entities = .{ .disposition = null, .records = null } } } },
        .{ .call = 6, .origin = .{ .request = .{ .value = 6 }, .attempt = .{ .value = 1 } }, .structure = .{ .shape = .{ .records = .{ .total = 3, .kinds = &.{.{ .kind = .edge_case, .count = 2 }}, .unknown = 1 } } } },
        .{ .call = 7, .origin = .{ .request = .{ .value = 7 }, .attempt = .{ .value = 1 } }, .structure = null },
    };
    const run: Run = .{ .run = "run", .case_id = "case", .measurement = .{ .measured = .{ .log_threshold = .warning, .report = .{ .measured = reported }, .responses = responses } } };
    const encoded = try std.json.Stringify.valueAlloc(a, run, .{});
    try testing.expectEqualDeep(run, try strict.decode(Run, a, encoded, limits));
    // Kinds, categories and dispositions are closed; an unknown one rejects.
    for ([_][2][]const u8{
        .{ "\"kind\":\"edge_case\"", "\"kind\":\"story\"" },
        .{ "\"category\":\"business\"", "\"category\":\"rule\"" },
        .{ "\"disposition\":\"not_applicable\"", "\"disposition\":\"maybe\"" },
        .{ "\"no_feature_claim\":{}", "\"no_feature_claim\":{\"reason\":1}" },
    }) |change| {
        try testing.expect(std.meta.isError(strict.decode(Run, a, try std.mem.replaceOwned(u8, a, encoded, change[0], change[1]), limits)));
    }
    const set = try summarize(a, &.{run}, null);
    try testing.expect(set.cases[0].record_kinds.len != 0 and set.cases[0].claim_categories.len != 0);
    const set_bytes = try std.json.Stringify.valueAlloc(a, set, .{});
    try testing.expectEqualDeep(set, try strict.decode(Set, a, set_bytes, limits));
    try testing.expect(std.meta.isError(strict.decode(Set, a, try std.mem.replaceOwned(u8, a, set_bytes, "\"kind\":\"edge_case\"", "\"kind\":\"story\""), limits)));
}
