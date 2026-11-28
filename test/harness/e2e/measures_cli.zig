//! Offline measures of retained E2E runs. Reads each run directory
//! without following links, writes `<out>/<run>/measures.json`, and optionally a set
//! summary. It never runs the engine and makes no model call.
const std = @import("std");
const measures = @import("measures.zig");
const c = @import("contracts.zig");
const harness = @import("../contracts.zig");
const files = @import("../files.zig");
const evidence = @import("../evidence.zig");
const output = @import("../output.zig");
const directories = @import("../../../src/adapters/filesystem/directory_access.zig");
const relative = @import("../../../src/domain/relative_directory_path.zig");
const config = @import("../../../src/domain/config.zig");
const CallContext = @import("call_context.zig").CallContext;
const run_directory = @import("run_directory.zig");

pub const Options = struct { runs: []const []const u8, out: []const u8, set: ?[]const u8 };

/// Analysis stays under the Git-ignored `evaluations/`.
const evaluations = "evaluations";

pub fn parse(a: std.mem.Allocator, args: []const []const u8) error{ InvalidArguments, OutOfMemory }!Options {
    var runs: std.ArrayList([]const u8) = .empty;
    var out: ?[]const u8 = null;
    var set: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 2) {
        if (i + 1 >= args.len) return error.InvalidArguments;
        const value = args[i + 1];
        harness.path(value) catch return error.InvalidArguments;
        if (std.mem.eql(u8, args[i], "--run")) {
            try runs.append(a, value);
            continue;
        }
        const slot = if (std.mem.eql(u8, args[i], "--out")) &out else if (std.mem.eql(u8, args[i], "--set")) &set else return error.InvalidArguments;
        if (slot.* != null) return error.InvalidArguments;
        slot.* = value;
    }
    if (runs.items.len == 0) return error.InvalidArguments;
    const options: Options = .{ .runs = try runs.toOwnedSlice(a), .out = out orelse return error.InvalidArguments, .set = set };
    // A retained run is immutable evidence: no output is written in, over or around one.
    for ([_]?[]const u8{ options.out, options.set }) |candidate| {
        const written = candidate orelse continue;
        if (!relative.contains(evaluations, written) or relative.contains(written, evaluations)) return error.InvalidArguments;
        for (options.runs) |run| if (relative.contains(run, written) or relative.contains(written, run)) return error.InvalidArguments;
    }
    return options;
}

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const io = init.io;
    var it = try std.process.Args.Iterator.initAllocator(init.minimal.args, a);
    defer it.deinit();
    _ = it.skip();
    var args: std.ArrayList([]const u8) = .empty;
    while (it.next()) |arg| try args.append(a, arg);
    if (args.items.len == 1 and std.mem.eql(u8, args.items[0], "--help")) {
        try std.Io.File.stdout().writeStreamingAll(io, "Usage: zig build e2e-measures -- --run <relative-run-directory> [--run ...] --out <existing-relative-directory> [--set <new-relative-file.json>]\nOffline only; no model call is possible. Writes <out>/<run>/measures.json (e2e-measures/v2) per run and, with --set, one e2e-measures-set/v2 summary. Never overwrites a file.\n");
        return;
    }
    const options = parse(a, args.items) catch return fail(io, "Invalid arguments; use --help. No API call is possible.");
    switch (try produce(io, a, .cwd(), options)) {
        .written => |lines| for (lines) |line| try std.Io.File.stdout().writeStreamingAll(io, line),
        .stopped => |message| return fail(io, message),
    }
}

/// The files `produce` wrote, one line each, or why it wrote nothing.
const Produced = union(enum) { written: []const []const u8, stopped: []const u8 };

/// Measures every run and summarizes the set before writing anything, so a run without
/// a readable case or a case of mixed log thresholds leaves no partial output.
fn produce(io: std.Io, a: std.mem.Allocator, root: std.Io.Dir, options: Options) !Produced {
    var out = directories.open(io, root, options.out) catch return .{ .stopped = "--out must be an existing safe directory." };
    defer out.close(io);
    const parent: ?std.Io.Dir = if (options.set) |path| directories.open(io, root, std.fs.path.dirname(path) orelse return .{ .stopped = "--set must name a file inside an existing directory." }) catch
        return .{ .stopped = "--set must name a file inside an existing safe directory." } else null;
    defer if (parent) |dir| dir.close(io);
    const runs = try a.alloc(measures.Run, options.runs.len);
    for (options.runs, runs) |path, *run| run.* = measure(io, a, root, path) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{ .stopped = try std.fmt.allocPrint(a, "Run {s} not measured: {s}. Nothing was written.", .{ path, @errorName(err) }) },
    };
    var conflict: measures.ThresholdConflict = undefined;
    const summary: ?measures.Set = if (options.set != null) measures.summarize(a, runs, &conflict) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.MixedLogThresholds => return .{ .stopped = try std.fmt.allocPrint(a, "Case {s} has runs at log thresholds {s} and {s}, which don't compare. Nothing was written.", .{ conflict.case_id, @tagName(conflict.first), @tagName(conflict.second) }) },
    } else null;
    var lines: std.ArrayList([]const u8) = .empty;
    for (options.runs, runs) |path, run| {
        const name = std.fs.path.basename(path);
        out.createDir(io, name, .default_dir) catch |err| if (err != error.PathAlreadyExists) return err;
        var dir = try directories.open(io, out, name);
        defer dir.close(io);
        output.write(io, dir, "measures.json", try std.json.Stringify.valueAlloc(a, run, .{ .whitespace = .indent_2 })) catch |err|
            return .{ .stopped = try std.fmt.allocPrint(a, "{s}/{s}/measures.json not written: {s}.", .{ options.out, name, @errorName(err) }) };
        const state = switch (run.measurement) {
            .measured => |measured| try std.fmt.allocPrint(a, "report {s}", .{@tagName(measured.report)}),
            .unmeasurable => |failure| try std.fmt.allocPrint(a, "unmeasurable: {s}", .{@tagName(failure.reason)}),
        };
        try lines.append(a, try std.fmt.allocPrint(a, "{s}/{s}/measures.json ({s}, {s})\n", .{ options.out, name, run.case_id, state }));
    }
    if (summary) |value| {
        const path = options.set.?;
        output.write(io, parent.?, std.fs.path.basename(path), try std.json.Stringify.valueAlloc(a, value, .{ .whitespace = .indent_2 })) catch |err|
            return .{ .stopped = try std.fmt.allocPrint(a, "{s} not written: {s}.", .{ path, @errorName(err) }) };
        try lines.append(a, try std.fmt.allocPrint(a, "{s} ({d} runs)\n", .{ path, runs.len }));
    }
    return .{ .written = try lines.toOwnedSlice(a) };
}

/// Measures one retained run directory under `root`. Its case must decode, or the run
/// can't be attributed to a case. A retained record that can't be read or trusted makes
/// the run `unmeasurable`; it still counts as attempted. An operational failure of the
/// measurement itself stops it.
fn measure(io: std.Io, a: std.mem.Allocator, root: std.Io.Dir, path: []const u8) !measures.Run {
    var run = try directories.open(io, root, path);
    defer run.close(io);
    const case = try c.parse(a, try files.read(io, a, run, "case.json"));
    return .{
        .run = std.fs.path.basename(path),
        .case_id = case.id,
        .measurement = if (measureRecords(io, a, run, root, path)) |measured| .{ .measured = measured } else |err| .{ .unmeasurable = .{ .reason = try unmeasurable(err) } },
    };
}

const RecordError = @typeInfo(@typeInfo(@TypeOf(measureRecords)).@"fn".return_type.?).error_union.error_set;

/// The retained record a measurement error came from; an operational error is returned.
/// The switch is exhaustive, so a new error must be classified before it compiles.
fn unmeasurable(err: RecordError) RecordError!measures.Unmeasurable.Reason {
    return switch (err) {
        error.OutOfMemory, error.Canceled, error.Cancelled, error.SystemResources, error.Unexpected => |operational| operational,
        error.InputUnavailable, error.DirectoryUnavailable, error.DirectoryMissing, error.AccessDenied, error.PermissionDenied => .unreadable,
        error.EngineConfigParseError, error.InvalidLoggingPolicy => .configuration,
        error.InvalidReport, error.AccountingOverflow, error.CaptureMismatch => .report,
        error.InvalidCallContext, error.InvalidJsonDocument, error.InvalidEvaluationContract => .call_evidence,
        error.InvalidFeatureLog => .feature_log,
        error.AmbiguousFeatureLog => .ambiguous_feature_log,
    };
}

/// The run's measures. Its report may be missing or of a known older version; a
/// missing call output or feature event log leaves its measures empty.
fn measureRecords(io: std.Io, a: std.mem.Allocator, run: std.Io.Dir, root: std.Io.Dir, path: []const u8) !measures.Measured {
    var configured = try @import("../../../src/domain/engine_config_decode.zig").decode(a, try files.read(io, a, run, "project/" ++ config.engine_config_basename));
    defer configured.deinit();
    const reported = try c.retainedReport(io, a, run);
    const earlier = try run_directory.inherited(io, a, root, path, if (reported) |value| value.continued_from else null);
    return .{
        .log_threshold = (try @import("../../../src/domain/log_policy.zig").canonicalizeConfiguredLevel(configured.value().logs.level)).threshold,
        .report = if (reported) |value| .{ .measured = try measures.fromReport(a, value) } else .unavailable,
        .responses = try responses(io, a, run),
        .events = try featureEvents(io, a, run, earlier),
    };
}

const calls = evidence.phaseDirectory(.generation);

fn responses(io: std.Io, a: std.mem.Allocator, run: std.Io.Dir) ![]const measures.Response {
    var names: std.ArrayList([]const u8) = .empty;
    {
        var dir = directories.open(io, run, calls) catch |err| switch (err) {
            error.DirectoryMissing => return &.{},
            else => return err,
        };
        defer dir.close(io);
        var iterator = dir.iterate();
        while (try iterator.next(io)) |entry| {
            if (entry.kind == .directory and std.mem.startsWith(u8, entry.name, evidence.call_prefix)) try names.append(a, try a.dupe(u8, entry.name));
        }
    }
    std.mem.sort([]const u8, names.items, {}, lessThan);
    var result: std.ArrayList(measures.Response) = .empty;
    for (names.items) |name| {
        const context = try CallContext.decode(a, try files.read(io, a, run, try std.fmt.allocPrint(a, "{s}/{s}/{s}", .{ calls, name, evidence.artifactFile(.context) })));
        const text = files.read(io, a, run, try std.fmt.allocPrint(a, "{s}/{s}/{s}", .{ calls, name, evidence.artifactFile(.model_output) })) catch |err| switch (err) {
            error.InputUnavailable => null,
            else => return err,
        };
        // Every call is kept, so its request's last attempt is known even without a response.
        try result.append(a, .{ .call = context.call, .origin = context.origin, .structure = if (text) |bytes| try measures.structure(a, bytes) else null });
    }
    return result.toOwnedSlice(a);
}

/// The single feature event log under the retained project, segments in order; null
/// when the run left none.
fn featureEvents(io: std.Io, a: std.mem.Allocator, run: std.Io.Dir, earlier: []const []const u8) !?measures.Events {
    var all: std.ArrayList([]const u8) = .empty;
    try run_directory.eventLogs(io, a, run, "project", &all);
    var segments: std.ArrayList([]const u8) = .empty;
    for (all.items) |segment| {
        if (!run_directory.isInherited(earlier, run_directory.engineRun(segment))) try segments.append(a, segment);
    }
    if (segments.items.len == 0) return null;
    std.mem.sort([]const u8, segments.items, {}, lessThan);
    // Segments live in `<run id>/<binding>/`; one workflow run per retained project.
    const owner = std.fs.path.dirname(std.fs.path.dirname(segments.items[0]).?).?;
    for (segments.items) |segment| {
        if (!std.mem.eql(u8, std.fs.path.dirname(std.fs.path.dirname(segment).?).?, owner)) return error.AmbiguousFeatureLog;
    }
    const bytes = try a.alloc([]const u8, segments.items.len);
    for (segments.items, bytes) |segment, *content| content.* = try files.read(io, a, run, segment);
    return try measures.events(a, bytes);
}

fn lessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn fail(io: std.Io, message: []const u8) !void {
    try std.Io.File.stderr().writeStreamingAll(io, message);
    try std.Io.File.stderr().writeStreamingAll(io, "\n");
    std.process.exit(1);
}

test "measure arguments require runs and an output directory and reject unsafe paths" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parsed = try parse(a, &.{ "--run", "runs/one", "--out", "evaluations/e2e", "--run", "runs/two", "--set", "evaluations/set.json" });
    try std.testing.expectEqual(@as(usize, 2), parsed.runs.len);
    try std.testing.expectEqualStrings("runs/two", parsed.runs[1]);
    try std.testing.expectEqualStrings("evaluations/set.json", parsed.set.?);
    try std.testing.expectEqual(@as(?[]const u8, null), (try parse(a, &.{ "--run", "r", "--out", "evaluations/o" })).set);
    _ = try parse(a, &.{ "--run", "evaluations/runs/one", "--out", "evaluations/measures/one" });
    for ([_][]const []const u8{
        &.{ "--out", "evaluations/o" },
        &.{ "--run", "r" },
        &.{ "--run", "r", "--out", "evaluations/o", "--out", "evaluations/p" },
        &.{ "--run", "r", "--out", "evaluations/o", "--grade", "x" },
        &.{ "--run", "../r", "--out", "evaluations/o" },
        &.{ "--run", "/abs", "--out", "evaluations/o" },
        &.{ "--run", "r", "--out" },
        // Outputs stay strictly under evaluations/.
        &.{ "--run", "r", "--out", "o" },
        &.{ "--run", "r", "--out", "evaluations" },
        &.{ "--run", "r", "--out", "runs/measures" },
        &.{ "--run", "r", "--out", "evaluations/o", "--set", "set.json" },
        &.{ "--run", "r", "--out", "evaluations/o", "--set", "evaluations" },
        // No output equals, contains or lies inside a retained run, in any case.
        &.{ "--run", "evaluations/run", "--out", "evaluations/run" },
        &.{ "--run", "evaluations/Run", "--out", "evaluations/run" },
        &.{ "--run", "evaluations/runs/one", "--out", "evaluations/runs" },
        &.{ "--run", "r", "--run", "evaluations/run", "--out", "evaluations/run/measures" },
        &.{ "--run", "evaluations/run", "--out", "evaluations/o", "--set", "evaluations/run/set.json" },
        &.{ "--run", "evaluations/run/one", "--out", "evaluations/o", "--set", "evaluations/run" },
    }) |args| try std.testing.expectError(error.InvalidArguments, parse(a, args));
}

const measures_test_config =
    \\{"logs":{"level":"warn","console":false},"workflowTokenBudget":100000,"temperature":0.1,"temperatureRunawayRetry":1,
    \\"models":{"slots":{"implementation":{"provider":"openai","model":"gpt-5.4-mini"}}},
    \\"paths":{"specs":"specs/","references":"references/","specsArchive":"specs/_archive/","workflows":".sddtoolkit/workflows",
    \\"toolchainPreset":".sddtoolkit/toolchainPreset","principles":".sddtoolkit/principles","templates":".sddtoolkit/templates","providers":".sddproviders.json"}}
;
const measures_test_case =
    \\{"schema":"spec-e2e-case/v5","id":"loan","workflow_id":"spec-generation","expected_outcome":"publication","answers":[],"feature":"loan","reference":"loan",
    \\"config":"cases/loan/.sddtoolkit.json","evaluation_case":"cases/loan/evaluation.json","directories":[],
    \\"files":[{"source":"cases/loan/stories.md","destination":"references/loan/stories.md"}],
    \\"expected_artifacts":["specification","reference_context","clarification_state","workflow_state","actor_evidence"]}
;
const measures_test_log = "project/specs/loan/logs/events/RUN-1/LOGBIND-1/0001.log";

fn putTestFile(io: std.Io, root: std.Io.Dir, path: []const u8, bytes: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| (try root.createDirPathOpen(io, parent, .{})).close(io);
    try root.writeFile(io, .{ .sub_path = path, .data = bytes });
}

/// A retained run with a case, its project configuration, one feature event log segment
/// and, when given, a report.
fn putTestRun(io: std.Io, a: std.mem.Allocator, root: std.Io.Dir, name: []const u8, report: ?[]const u8) !void {
    try putTestFile(io, root, try std.fs.path.join(a, &.{ name, "case.json" }), measures_test_case);
    try putTestFile(io, root, try std.fs.path.join(a, &.{ name, "project", config.engine_config_basename }), measures_test_config);
    try putTestFile(io, root, try std.fs.path.join(a, &.{ name, measures_test_log }), try measures.testSegment(a, 1, &.{
        .{ .offset = 100, .event_type = .run_started },
        .{ .offset = 400, .event_type = .model_provider_stopped, .code = "OUTPUT_LIMIT" },
    }, true));
    if (report) |bytes| try putTestFile(io, root, try std.fs.path.join(a, &.{ name, "report.json" }), bytes);
}

/// One retained call's current evidence and, when given, its model output.
fn putTestCall(io: std.Io, a: std.mem.Allocator, root: std.Io.Dir, run: []const u8, call: usize, request: u32, attempt: u32, model_output: ?[]const u8) !void {
    const context: CallContext = .{
        .schema = .@"model-call-evidence/v4",
        .call = call,
        .origin = .{ .request = .{ .value = request }, .attempt = .{ .value = attempt } },
        .request_step = "generate-records",
        .slot = "spec_generation",
        .attempt = attempt,
        .provider = "aws-bedrock",
        .model = "openai.gpt-oss-20b-1:0",
        .provider_config = .{ .aws_bedrock = .{ .region = .@"ap-southeast-2", .family = .@"gpt-oss", .max_output_tokens = .{ .tokens = 16000 }, .request_timeout = .{ .milliseconds = 180000 } } },
        .kind = .inference,
        .reasoning_effort = "low",
        .content = &.{.{ .user = "MOCK request" }},
        .response_schema = "{\"type\":\"object\"}",
    };
    // The layout is the store's: a moved evidence path moves the tests' files with it.
    try putTestFile(io, root, try std.fs.path.join(a, &.{ run, try evidence.Store.path(a, .generation, call, .context) }), try std.json.Stringify.valueAlloc(a, context, .{}));
    if (model_output) |bytes| try putTestFile(io, root, try std.fs.path.join(a, &.{ run, try evidence.Store.path(a, .generation, call, .model_output) }), bytes);
}

test "call evidence gives every call's structure and keeps calls without a readable response" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var root = std.testing.tmpDir(.{});
    defer root.cleanup();
    try putTestRun(io, a, root.dir, "calls", null);
    try putTestCall(io, a, root.dir, "calls", 1, 1, 1, "{\"kind\":\"records\",\"records\":[{\"content\":{\"kind\":\"edge_case\"}}]}");
    // The retry was cut off mid-object, and another request left no output.
    try putTestCall(io, a, root.dir, "calls", 2, 1, 2, "{\"kind\":\"records\",\"records\":[{");
    try putTestCall(io, a, root.dir, "calls", 3, 2, 1, null);
    try putTestCall(io, a, root.dir, "calls", 4, 3, 1, "{\"kind\":\"entities\",\"disposition\":\"not_applicable\",\"records\":[]}");
    const run = try measure(io, a, root.dir, "calls");
    const measured = run.measurement.measured;
    try std.testing.expectEqual(@as(usize, 4), measured.responses.len);
    try std.testing.expectEqual(@as(usize, 1), measured.responses[0].structure.?.shape.records.kinds.len);
    try std.testing.expectEqual(@as(?measures.Structure, null), measured.responses[1].structure);
    try std.testing.expectEqual(@as(?measures.Structure, null), measured.responses[2].structure);
    try std.testing.expectEqual(@as(?@import("../../../src/domain/specification.zig").Applicability, .not_applicable), measured.responses[3].structure.?.shape.entities.disposition);
    // The cut-off retry is its request's last attempt, so the rejected edge case isn't the
    // run's: the run has no final records at all.
    const set = try measures.summarize(a, &.{run}, null);
    try std.testing.expectEqual(@as(usize, 0), set.cases[0].record_kinds.len);
    try std.testing.expectEqual(measures.Pooled{ .events = 0, .opportunities = 1 }, set.cases[0].entities_required);
}

/// Why a retained run is unmeasurable; fails when it measured.
fn reason(io: std.Io, a: std.mem.Allocator, root: std.Io.Dir, name: []const u8) !measures.Unmeasurable.Reason {
    return switch ((try measure(io, a, root, name)).measurement) {
        .measured => error.TestUnexpectedResult,
        .unmeasurable => |failure| failure.reason,
    };
}

test "a retained run measures its configured threshold and one feature log, and marks what it can't trust" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var root = std.testing.tmpDir(.{});
    defer root.cleanup();
    // A missing report, or one of a known older version, leaves the report unavailable.
    for ([_]?[]const u8{ null, "{\"schema\":\"spec-e2e-report/v9\",\"retired\":true}", "{\"schema\":\"spec-e2e-report/v24\",\"attempts\":[]}" }, [_][]const u8{ "missing", "older", "previous" }) |report, name| {
        try putTestRun(io, a, root.dir, name, report);
        const run = try measure(io, a, root.dir, name);
        try std.testing.expectEqualStrings(name, run.run);
        try std.testing.expectEqualStrings("loan", run.case_id);
        const measured = run.measurement.measured;
        try std.testing.expectEqual(.warning, measured.log_threshold);
        try std.testing.expect(measured.report == .unavailable);
        try std.testing.expectEqual(@as(usize, 0), measured.responses.len);
        try std.testing.expectEqual(@as(u64, 1), measured.events.?.runaways);
        try std.testing.expectEqual(@as(?u64, 300), measured.events.?.latency_ms);
    }
    // A current report measures, its sends attributed to their stages.
    try putTestRun(io, a, root.dir, "current", try currentReport(a));
    const reported = (try measure(io, a, root.dir, "current")).measurement.measured.report.measured;
    try std.testing.expectEqual(@as(u64, 1), reported.sends);
    try std.testing.expectEqual(@as(?u64, 7), reported.stages[@intFromEnum(@import("../baseline/stages.zig").Stage.repair)].actual_tokens);
    // A report of the current version that doesn't decode, or of an unknown version,
    // makes the run unmeasurable rather than its report unavailable.
    for ([_][]const u8{
        "{\"schema\":\"" ++ @tagName(c.report_schema) ++ "\"}",
        "{\"schema\":\"" ++ @tagName(c.report_schema) ++ "\"}",
        "{\"schema\":\"spec-e2e-report/v09\"}",
        "{\"status\":\"generated\"}",
        "not json",
    }, 0..) |report, index| {
        const name = try std.fmt.allocPrint(a, "report-{d}", .{index});
        try putTestRun(io, a, root.dir, name, report);
        try std.testing.expectEqual(.report, try reason(io, a, root.dir, name));
    }
    // Call evidence of another version is untrusted.
    try putTestRun(io, a, root.dir, "context", null);
    try putTestFile(io, root.dir, try std.fs.path.join(a, &.{ "context", try evidence.Store.path(a, .generation, 1, .context) }), "{\"schema\":\"model-call-evidence/v2\"}");
    try std.testing.expectEqual(.call_evidence, try reason(io, a, root.dir, "context"));
    // Event logs of two workflow runs are ambiguous.
    try putTestRun(io, a, root.dir, "ambiguous", null);
    try putTestFile(io, root.dir, "ambiguous/project/specs/loan/logs/events/RUN-2/LOGBIND-1/0001.log", try measures.testSegment(a, 1, &.{.{ .offset = 1, .event_type = .run_started }}, true));
    try std.testing.expectEqual(.ambiguous_feature_log, try reason(io, a, root.dir, "ambiguous"));
    // A case's second leg holds its first leg's engine run beside its own, and owns only the one it added. Without the first
    // leg's directory the split is unknown, so the run is unreadable; without `continued_from` the two runs stay ambiguous.
    // The first leg is the measured run's sibling, wherever the pair sits under the root. Its run is the one holding a runaway.
    try putTestRun(io, a, root.dir, "legs/" ++ first_leg, null);
    try putTestRun(io, a, root.dir, "legs/two", try continuedReport(a, first_leg));
    try putTestFile(io, root.dir, "legs/two/project/specs/loan/logs/events/RUN-2/LOGBIND-1/0001.log", try measures.testSegment(a, 1, &.{
        .{ .offset = 10, .event_type = .run_started },
        .{ .offset = 50, .event_type = .run_started },
        .{ .offset = 90, .event_type = .run_started },
    }, true));
    const owned = (try measure(io, a, root.dir, "legs/two")).measurement.measured;
    try std.testing.expectEqual(@as(?u64, 80), owned.events.?.latency_ms);
    try std.testing.expectEqual(@as(u64, 0), owned.events.?.runaways);
    // A first leg that exists only at the top of the root is not beside the measured run, and a name that is a path is no run name.
    try putTestRun(io, a, root.dir, orphan_leg, null);
    try putTestRun(io, a, root.dir, "legs/stray", try continuedReport(a, orphan_leg));
    try std.testing.expectEqual(.unreadable, try reason(io, a, root.dir, "legs/stray"));
    try putTestRun(io, a, root.dir, "legs/pathed", try continuedReport(a, "../" ++ orphan_leg));
    try std.testing.expectEqual(.report, try reason(io, a, root.dir, "legs/pathed"));
    try putTestRun(io, a, root.dir, "legs/missing", try continuedReport(a, missing_leg));
    try std.testing.expectEqual(.unreadable, try reason(io, a, root.dir, "legs/missing"));
    // A name that is no run directory's, or the run's own, is a bad report, never a run that inherited nothing.
    try putTestRun(io, a, root.dir, "legs/" ++ self_leg, try continuedReport(a, self_leg));
    try std.testing.expectEqual(.report, try reason(io, a, root.dir, "legs/" ++ self_leg));
    for ([_][]const u8{ "", "one" }) |name| {
        try putTestRun(io, a, root.dir, try std.fmt.allocPrint(a, "legs/named-{s}", .{name}), try continuedReport(a, name));
        try std.testing.expectEqual(.report, try reason(io, a, root.dir, try std.fmt.allocPrint(a, "legs/named-{s}", .{name})));
    }
    try putTestRun(io, a, root.dir, "unnamed", try currentReport(a));
    try putTestFile(io, root.dir, "unnamed/project/specs/loan/logs/events/RUN-2/LOGBIND-1/0001.log", try measures.testSegment(a, 1, &.{.{ .offset = 1, .event_type = .run_started }}, true));
    try std.testing.expectEqual(.ambiguous_feature_log, try reason(io, a, root.dir, "unnamed"));
    // A malformed feature log, and one whose last row was cut off mid-write, are untrusted.
    try putTestRun(io, a, root.dir, "malformed", null);
    try putTestFile(io, root.dir, try std.fs.path.join(a, &.{ "malformed", measures_test_log }), "event|1|2\n");
    try std.testing.expectEqual(.feature_log, try reason(io, a, root.dir, "malformed"));
    const open = try measures.testSegment(a, 1, &.{ .{ .offset = 1, .event_type = .run_started }, .{ .offset = 2, .event_type = .run_started } }, false);
    try putTestRun(io, a, root.dir, "cut", null);
    try putTestFile(io, root.dir, try std.fs.path.join(a, &.{ "cut", measures_test_log }), open[0 .. open.len - 5]);
    try std.testing.expectEqual(.feature_log, try reason(io, a, root.dir, "cut"));
    // A configuration the engine rejects leaves the threshold unknown.
    try putTestRun(io, a, root.dir, "configuration", null);
    try putTestFile(io, root.dir, try std.fs.path.join(a, &.{ "configuration", "project", config.engine_config_basename }), "{}");
    try std.testing.expectEqual(.configuration, try reason(io, a, root.dir, "configuration"));
    // Without a readable case the run can't be attributed, so it stops the command.
    try putTestFile(io, root.dir, "caseless/project/placeholder", "");
    try std.testing.expectError(error.InputUnavailable, measure(io, a, root.dir, "caseless"));
    // An operational failure of the measurement itself is never a property of the run.
    for ([_]RecordError{ error.OutOfMemory, error.Canceled, error.Cancelled, error.SystemResources, error.Unexpected }) |operational| {
        try std.testing.expectError(operational, unmeasurable(operational));
    }
}

/// Run directory names, in the shape the launcher gives one.
const first_leg = "2026-11-27T08-48-56Z-74b1a2cfe51c25d38a161e475a494183";
const orphan_leg = "2026-11-27T08-48-57Z-74b1a2cfe51c25d38a161e475a494183";
const missing_leg = "2026-11-27T08-48-58Z-74b1a2cfe51c25d38a161e475a494183";
const self_leg = "2026-11-27T08-48-59Z-74b1a2cfe51c25d38a161e475a494183";

/// A decodable current report of a second leg.
fn continuedReport(a: std.mem.Allocator, first: []const u8) ![]const u8 {
    const report: c.Report = .{ .started_at_utc = "", .status = .generated, .workflow_outcome = .ok, .continued_from = first };
    return std.json.Stringify.valueAlloc(a, report, .{});
}

/// A decodable current report with one repair send.
fn currentReport(a: std.mem.Allocator) ![]const u8 {
    const attempts = [_]c.Attempt{.{
        .origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } },
        .step = "repair",
        .purpose = .atomic_repair,
        .owner_kind = .specification_unit,
        .accounting = .exact_usage,
        .usage = .{ .input_tokens = 4, .output_tokens = 3, .total_tokens = 7 },
    }};
    const report: c.Report = .{ .started_at_utc = "", .status = .workflow_failed, .workflow_outcome = .failed, .model_calls = 1, .total_tokens = 7, .attempts = &attempts };
    return std.json.Stringify.valueAlloc(a, report, .{});
}

test "a set summary counts an unmeasurable run, and a stop writes nothing" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var root = std.testing.tmpDir(.{});
    defer root.cleanup();
    try root.dir.createDirPath(io, "evaluations/written");
    try root.dir.createDirPath(io, "evaluations/stopped");
    try putTestRun(io, a, root.dir, "runs/one", try currentReport(a));
    // A run whose log was cut off mid-write is attempted and unmeasurable.
    try putTestRun(io, a, root.dir, "runs/cut", null);
    try putTestFile(io, root.dir, try std.fs.path.join(a, &.{ "runs/cut", measures_test_log }), "event|1");
    const written = try produce(io, a, root.dir, .{ .runs = &.{ "runs/one", "runs/cut" }, .out = "evaluations/written", .set = "evaluations/written/set.json" });
    try std.testing.expectEqual(@as(usize, 3), written.written.len);
    const set = try harness.decode(measures.Set, a, try files.read(io, a, root.dir, "evaluations/written/set.json"));
    try std.testing.expectEqual(@as(u64, 2), set.cases[0].attempted);
    try std.testing.expectEqual(@as(u64, 1), set.cases[0].unmeasurable);
    _ = try files.read(io, a, root.dir, "evaluations/written/cut/measures.json");
    // The same case at another log threshold, or a run without a case, stops before any
    // file is written.
    try putTestRun(io, a, root.dir, "runs/debug", null);
    try putTestFile(io, root.dir, try std.fs.path.join(a, &.{ "runs/debug", "project", config.engine_config_basename }), try std.mem.replaceOwned(u8, a, measures_test_config, "\"warn\"", "\"debug\""));
    try putTestFile(io, root.dir, "runs/caseless/project/placeholder", "");
    for ([_][]const []const u8{ &.{ "runs/one", "runs/debug" }, &.{ "runs/one", "runs/caseless" } }, [_][]const u8{ "warning and debug", "runs/caseless not measured" }) |runs, expected| {
        const stopped = try produce(io, a, root.dir, .{ .runs = runs, .out = "evaluations/stopped", .set = "evaluations/stopped/set.json" });
        try std.testing.expect(std.mem.indexOf(u8, stopped.stopped, expected) != null);
        var out = try directories.open(io, root.dir, "evaluations/stopped");
        defer out.close(io);
        var entries = out.iterate();
        try std.testing.expectEqual(@as(?std.Io.Dir.Entry, null), try entries.next(io));
    }
}
