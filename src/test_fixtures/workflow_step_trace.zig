//! Offline step trace of one scripted workflow scenario, written as structural
//! equivalence evidence (ADR 0030 "Freeze first"). It is an observation, not an
//! assertion: tests never compare it. Each executed step becomes one line keyed
//! by its source call path, so a structural conversion can be compared with the
//! trace recorded before it. A model request is one `request-model` step, so its
//! line is its own call site plus that operation ID (ADR 0030).
const std = @import("std");
const compilation = @import("../domain/workflow_compilation.zig");
const execution = @import("../domain/workflow_execution.zig");
const source = @import("../domain/workflow_source.zig");
const filesystem = @import("../domain/filesystem_identity.zig");
const workflow_retry = @import("../domain/workflow_retry.zig");
const atomic_repair = @import("../domain/atomic_repair.zig");

pub const schema = "workflow-step-trace/v1";
pub const directory = ".zig-cache/workflow-step-trace";

pub const Error = std.mem.Allocator.Error;

pub const Trace = struct {
    lines: std.Io.Writer.Allocating,
    steps: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Trace {
        return .{ .lines = .init(allocator) };
    }

    pub fn deinit(self: *Trace) void {
        self.lines.deinit();
    }

    pub fn written(self: *Trace) []const u8 {
        return self.lines.written();
    }

    /// `first` is the runner's first cause when the step ended a run, which the rejected line names.
    pub fn record(self: *Trace, step: *const compilation.CompiledStep, applied: execution.Applied, first: ?execution.FirstCause) Error!void {
        writeLine(&self.lines.writer, step, applied, first) catch |err| return switch (err) {
            error.WriteFailed => error.OutOfMemory,
        };
        self.steps += 1;
    }
};

/// Writes the step's source call path.
pub fn writeCallSite(w: *std.Io.Writer, step: *const compilation.CompiledStep) std.Io.Writer.Error!void {
    if (step.source_chain.len == 0) return w.writeAll(step.id.bytes);
    for (step.source_chain, 0..) |entry, index| {
        if (index != 0) try w.writeByte('/');
        try w.writeAll(entry.id);
    }
}

/// The closed enumeration parameter that selects an operation's contract variant (ADR 0030
/// "Contract variants"; `owner` for ADR 0033's repair operations).
pub const selector_parameter = "owner";

/// The step's selected variant, when it declares one; absent for every operation that has a single
/// contract, so such a step's line is unchanged.
fn selectedVariant(step: *const compilation.CompiledStep) ?[]const u8 {
    for (step.parameters) |parameter| {
        if (!std.mem.eql(u8, parameter.id.bytes, selector_parameter)) continue;
        return switch (parameter.value) {
            .enumeration => |value| value,
            .boolean, .integer, .string, .registered_ref, .resource, .model_slot => null,
        };
    }
    return null;
}

fn writeLine(w: *std.Io.Writer, step: *const compilation.CompiledStep, applied: execution.Applied, first: ?execution.FirstCause) std.Io.Writer.Error!void {
    try writeCallSite(w, step);
    try w.print("#{s}", .{step.operation_id.bytes});
    if (selectedVariant(step)) |variant| try w.print("@{s}", .{variant});
    try w.writeByte('\t');
    switch (applied) {
        .outcome => |tag| try w.writeAll(@tagName(tag)),
        .rejected => |reason| try writeRejection(w, reason, first),
    }
    try w.writeByte('\n');
}

/// The canonical rejection diagnostic, which names an authority rejection's reason, plus the facts of a
/// retry exhaustion and, only when a later failure replaced one, the first cause, with its own facts
/// when it was an exhaustion. A line without a suffix reads as it always did.
pub fn writeRejection(w: *std.Io.Writer, reason: execution.Rejection, first: ?execution.FirstCause) std.Io.Writer.Error!void {
    try w.print("rejected:{s}:{s}", .{ @tagName(reason), reason.diagnostic() });
    if (reason == .retry_limit) try writeRetryFacts(w, reason.retry_limit);
    if (first) |cause| {
        try w.print(":first={s}:{s}", .{ @tagName(cause), cause.rejection().diagnostic() });
        if (cause == .retry_limit) try writeRetryFacts(w, cause.retry_limit);
    }
}

/// The executions a retry exhaustion counted and, for a `request-model` step, the stage that reached the
/// limit (ADR 0030).
fn writeRetryFacts(w: *std.Io.Writer, exhaustion: workflow_retry.Exhaustion) std.Io.Writer.Error!void {
    try w.print(":executions={d}", .{exhaustion.completed_executions});
    if (exhaustion.stage) |stage| try w.print(":stage={s}", .{stage.name()});
}

/// One accounted inference, in accounting order.
pub const RequestAttempt = struct {
    call_site: []const u8,
    purpose: []const u8,
    request: u64,
    attempt: u64,
    reconciliation: []const u8,
};

pub const HashedFile = struct { path: []const u8, sha256: []const u8 };

/// The scenario's observable totals beside its step lines.
pub const Summary = struct {
    schema: []const u8 = schema,
    workflow: []const u8,
    case: []const u8,
    scenario: usize,
    outcome: ?[]const u8,
    rejection: ?[]const u8,
    steps: usize,
    trace_sha256: []const u8,
    model_invocations: usize,
    driver_calls: usize,
    accounted_operations: usize,
    committed_tokens: u128,
    requests: []const RequestAttempt,
    files: []const HashedFile,
};

pub fn hash(a: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error![]const u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return a.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
}

/// One file's masked bytes; the summary records their hash and `write` keeps
/// the bytes, so a later difference shows which field changed.
pub const File = struct { path: []const u8, bytes: []const u8 };

/// Filesystem facts the engine records about the temporary project. File
/// identities and timestamps differ on every run, so they are masked; derived
/// from the engine's own types, so a renamed field fails to compile here.
const observation_fields = blk: {
    var names: []const []const u8 = &.{};
    for (std.meta.fields(filesystem.FileIdentity)) |field| names = names ++ .{field.name};
    for ([_][]const u8{ "modified_ns", "changed_ns" }) |name| {
        _ = @FieldType(filesystem.FileObservation, name);
        names = names ++ .{name};
    }
    break :blk names;
};

fn maskObservations(value: *std.json.Value) void {
    switch (value.*) {
        .object => |*object| {
            var fields = object.iterator();
            while (fields.next()) |field| {
                for (observation_fields) |name| {
                    if (std.mem.eql(u8, field.key_ptr.*, name)) {
                        field.value_ptr.* = .{ .string = "<filesystem-observation>" };
                        break;
                    }
                } else maskObservations(field.value_ptr);
            }
        },
        .array => |*items| for (items.items) |*item| maskObservations(item),
        else => {},
    }
}

/// A JSON file's bytes with filesystem observations masked; other files as read.
fn stable(a: std.mem.Allocator, path: []const u8, bytes: []const u8) std.mem.Allocator.Error![]const u8 {
    if (!std.mem.endsWith(u8, path, ".json")) return bytes;
    var value = std.json.parseFromSliceLeaky(std.json.Value, a, bytes, .{}) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => bytes,
    };
    maskObservations(&value);
    return std.json.Stringify.valueAlloc(a, value, .{ .whitespace = .indent_2 });
}

fn component(path: []const u8, name: []const u8) bool {
    var parts = std.mem.splitAny(u8, path, "/\\");
    while (parts.next()) |part| if (std.mem.eql(u8, part, name)) return true;
    return false;
}

/// Every file under `root` except feature logs, sorted by path. Logs carry
/// timestamps and run identities, so they are not evidence of behaviour. A
/// per-run random identity, such as the reference state ID that rendered views
/// cite, and recorded filesystem observations are masked, so equal behaviour
/// yields equal bytes.
pub fn files(io: std.Io, a: std.mem.Allocator, project: std.Io.Dir, root: []const u8, volatile_identity: ?[]const u8) ![]const File {
    var found: std.ArrayList(File) = .empty;
    var dir = project.openDir(io, root, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return found.toOwnedSlice(a),
        else => return err,
    };
    defer dir.close(io);
    var walker = try dir.walk(a);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or component(entry.path, "logs")) continue;
        const read = try stable(a, entry.basename, try entry.dir.readFileAlloc(io, entry.basename, a, .limited(16 * 1024 * 1024)));
        const bytes = if (volatile_identity) |identity| try std.mem.replaceOwned(u8, a, read, identity, "<run-identity>") else read;
        try found.append(a, .{ .path = try std.fmt.allocPrint(a, "{s}/{s}", .{ root, entry.path }), .bytes = bytes });
    }
    const sorted = try found.toOwnedSlice(a);
    std.mem.sort(File, sorted, {}, struct {
        fn less(_: void, left: File, right: File) bool {
            return std.mem.lessThan(u8, left.path, right.path);
        }
    }.less);
    return sorted;
}

pub fn hashed(a: std.mem.Allocator, observed: []const File) std.mem.Allocator.Error![]const HashedFile {
    const result = try a.alloc(HashedFile, observed.len);
    for (result, observed) |*entry, file| entry.* = .{ .path = file.path, .sha256 = try hash(a, file.bytes) };
    return result;
}

pub const repairs_schema = "workflow-repair-evidence/v1";

/// The scenario's native repair evidence beside its step lines (ADR 0033 "Freeze first"): each
/// instance's retry limit, scope, executions, the defect keys counted per instance (hex of the
/// scope, target and family digests) and the per-request assignment counts, and every retained
/// native merge (its authorization, owner, operation, revisions, change fact, origin and permit).
/// It is a separate file so the trace and summary bytes of earlier freezes stay comparable.
pub const RepairEvidence = struct {
    schema: []const u8 = repairs_schema,
    retry_settings: []const workflow_retry.Observation,
    merges: []const atomic_repair.Merge,
};

fn basePath(a: std.mem.Allocator, summary: Summary) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}/{s}-{s}-{d:0>3}", .{ directory, summary.workflow, summary.case, summary.scenario });
}

/// Writes `<workflow>-<case>-<scenario>.repairs`, the JSON of `evidence`.
pub fn writeRepairs(io: std.Io, a: std.mem.Allocator, summary: Summary, evidence: RepairEvidence) !void {
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, directory);
    try cwd.writeFile(io, .{ .sub_path = try std.fmt.allocPrint(a, "{s}.repairs", .{try basePath(a, summary)}), .data = try std.json.Stringify.valueAlloc(a, evidence, .{ .whitespace = .indent_2 }) });
}

/// Writes `<workflow>-<case>-<scenario>.trace`, `.json` and the masked files
/// beneath `<...>.files/`.
pub fn write(io: std.Io, a: std.mem.Allocator, trace: *Trace, summary: Summary, observed: []const File) !void {
    const base = try basePath(a, summary);
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, directory);
    try cwd.writeFile(io, .{ .sub_path = try std.fmt.allocPrint(a, "{s}.trace", .{base}), .data = trace.written() });
    try cwd.writeFile(io, .{ .sub_path = try std.fmt.allocPrint(a, "{s}.json", .{base}), .data = try std.json.Stringify.valueAlloc(a, summary, .{ .whitespace = .indent_2 }) });
    for (observed) |file| {
        const path = try std.fmt.allocPrint(a, "{s}.files/{s}", .{ base, file.path });
        try cwd.createDirPath(io, std.fs.path.dirname(path).?);
        try cwd.writeFile(io, .{ .sub_path = path, .data = file.bytes });
    }
}

fn chainEntry(scope: ?[]const u8, id: []const u8, kind: @FieldType(source.Entry, "kind"), target: []const u8) source.Entry {
    return .{ .subgraph = scope, .id = id, .kind = kind, .target = target, .declaration = "" };
}

fn testStep(chain: []const source.Entry, operation: []const u8) compilation.CompiledStep {
    return .{ .source_chain = chain, .id = .{ .bytes = "g1-step" }, .operation_id = .{ .bytes = operation }, .parameters = &.{}, .requires = &.{}, .produces = &.{}, .replaces = &.{}, .invalidates = &.{}, .outcomes = &.{}, .side_effect = .none, .gates = &.{}, .capabilities = &.{}, .retry_authority = null };
}

test "a step in a nested subgraph is keyed by its whole call path and its operation" {
    var trace: Trace = .init(std.testing.allocator);
    defer trace.deinit();
    const chain = [_]source.Entry{
        chainEntry(null, "extract", .subgraph, "extraction"),
        chainEntry("extraction", "content-request", .subgraph, "retention"),
        chainEntry("retention", "retain", .operation, "retain-json-part"),
    };
    try trace.record(&testStep(&chain, "retain-json-part"), .{ .outcome = .ok }, null);
    try std.testing.expectEqualStrings("extract/content-request/retain#retain-json-part\tok\n", trace.written());
}

test "a request-model step is one line at its own call site" {
    var trace: Trace = .init(std.testing.allocator);
    defer trace.deinit();
    const chain = [_]source.Entry{
        chainEntry(null, "review", .subgraph, "assess-support"),
        chainEntry("assess-support", "model", .operation, "request-model"),
    };
    try trace.record(&testStep(&chain, "request-model"), .{ .outcome = .ok }, null);
    try trace.record(&testStep(&chain, "request-model"), .{ .rejected = .cancelled }, null);
    try std.testing.expectEqualStrings("review/model#request-model\tok\nreview/model#request-model\trejected:cancelled:cancelled\n", trace.written());
    try std.testing.expectEqual(@as(usize, 2), trace.steps);
}

test "a step without a source chain keys by its compiled ID and rejections use the canonical diagnostic" {
    var trace: Trace = .init(std.testing.allocator);
    defer trace.deinit();
    const step = testStep(&.{}, "release-model-transport");
    try trace.record(&step, .{ .rejected = .{ .operation_failed = error.RepairOwnerMismatch } }, null);
    try std.testing.expectEqualStrings("g1-step#release-model-transport\trejected:operation_failed:RepairOwnerMismatch\n", trace.written());
}

test "an authority rejection names its reason, and a first cause is named only when one was kept" {
    var trace: Trace = .init(std.testing.allocator);
    defer trace.deinit();
    const step = testStep(&.{}, "request-model");
    // Every reason is its own line, which carries no suffix: the trace of a lone failure is as it was.
    for (std.enums.values(execution.AuthorityReason)) |reason| {
        try trace.record(&step, .{ .rejected = .{ .authority = reason } }, null);
        var expected: [96]u8 = undefined;
        const line = try std.fmt.bufPrint(&expected, "g1-step#request-model\trejected:authority:{s}\n", .{@tagName(reason)});
        try std.testing.expect(std.mem.endsWith(u8, trace.written(), line));
    }
    try std.testing.expectEqual(std.enums.values(execution.AuthorityReason).len, trace.steps);
    // A rejection that replaced another names it last, by its tag and its own diagnostic, whatever the
    // terminal rejection is; a retry exhaustion keeps its own counts before it.
    var replaced: Trace = .init(std.testing.allocator);
    defer replaced.deinit();
    try replaced.record(&step, .{ .rejected = .{ .logging = .LOG_FLUSH_FAILURE } }, .{ .authority = .invocation_result });
    try replaced.record(&step, .{ .rejected = .{ .retry_limit = workflow_retry.Exhaustion.init(.{ .bytes = "account" }, .{ .value = 1 }, 2).? } }, .{ .operation_failed = error.InvalidCandidatePayload });
    try std.testing.expectEqualStrings(
        "g1-step#request-model\trejected:logging:blocked:first=authority:invocation_result\n" ++
            "g1-step#request-model\trejected:retry_limit:RetryLimitExhausted:executions=2:first=operation_failed:InvalidCandidatePayload\n",
        replaced.written(),
    );
    // A retry exhaustion that a later failure replaced gives its own counts and stage after its name,
    // where the terminal one gives them before the first cause.
    var exhausted: Trace = .init(std.testing.allocator);
    defer exhausted.deinit();
    const exhaustion = workflow_retry.Exhaustion.init(.{ .bytes = "account" }, .{ .value = 1 }, 2).?.atStage(.advance_attempt);
    try exhausted.record(&step, .{ .rejected = .{ .logging = .LOG_FLUSH_FAILURE } }, .{ .retry_limit = exhaustion });
    try exhausted.record(&step, .{ .rejected = .{ .retry_limit = workflow_retry.Exhaustion.init(.{ .bytes = "account" }, .{ .value = 1 }, 3).? } }, .{ .retry_limit = exhaustion });
    try std.testing.expectEqualStrings(
        "g1-step#request-model\trejected:logging:blocked:first=retry_limit:RetryLimitExhausted:executions=2:stage=advance-attempt\n" ++
            "g1-step#request-model\trejected:retry_limit:RetryLimitExhausted:executions=3:first=retry_limit:RetryLimitExhausted:executions=2:stage=advance-attempt\n",
        exhausted.written(),
    );
    // A first cause rides only a rejected line: an outcome has none to name.
    var outcome: Trace = .init(std.testing.allocator);
    defer outcome.deinit();
    try outcome.record(&step, .{ .outcome = .failed }, .{ .authority = .invocation_result });
    try std.testing.expectEqualStrings("g1-step#request-model\tfailed\n", outcome.written());
}

test "a step that selects a contract variant names it and every other step's line is unchanged" {
    var trace: Trace = .init(std.testing.allocator);
    defer trace.deinit();
    var selecting = testStep(&.{}, "merge-repair");
    selecting.parameters = &.{
        .{ .id = .{ .bytes = "retry-limit" }, .value = .{ .integer = 64 } },
        .{ .id = .{ .bytes = selector_parameter }, .value = .{ .enumeration = "specification-unit" } },
    };
    var other = testStep(&.{}, "merge-repair");
    // A string parameter of the same name is not a selector: only a closed enumeration selects.
    other.parameters = &.{.{ .id = .{ .bytes = selector_parameter }, .value = .{ .string = "specification-unit" } }};
    try trace.record(&selecting, .{ .outcome = .ok }, null);
    try trace.record(&other, .{ .outcome = .ok }, null);
    try trace.record(&testStep(&.{}, "merge-repair"), .{ .outcome = .ok }, null);
    try std.testing.expectEqualStrings("g1-step#merge-repair@specification-unit\tok\ng1-step#merge-repair\tok\ng1-step#merge-repair\tok\n", trace.written());
}

test "the repair evidence record is deterministic JSON with its schema first" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const evidence: RepairEvidence = .{ .retry_settings = &.{}, .merges = &.{} };
    const first = try std.json.Stringify.valueAlloc(a, evidence, .{ .whitespace = .indent_2 });
    const second = try std.json.Stringify.valueAlloc(a, evidence, .{ .whitespace = .indent_2 });
    try std.testing.expectEqualStrings(first, second);
    try std.testing.expect(std.mem.startsWith(u8, first, "{\n  \"schema\": \"workflow-repair-evidence/v1\""));
}

test "observed files exclude log components, mask the run identity and sort by path" {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try project.dir.createDirPath(io, "out/b");
    try project.dir.createDirPath(io, "out/logs/events");
    try project.dir.createDirPath(io, "out/catalogs");
    try project.dir.writeFile(io, .{ .sub_path = "out/b/spec.md", .data = "state reference-123 cited\n" });
    try project.dir.writeFile(io, .{ .sub_path = "out/a.md", .data = "plain\n" });
    try project.dir.writeFile(io, .{ .sub_path = "out/logs/events/0001.log", .data = "excluded\n" });
    try project.dir.writeFile(io, .{ .sub_path = "out/catalogs/kept.md", .data = "kept\n" });
    const observed = try files(io, a, project.dir, "out", "reference-123");
    try std.testing.expectEqual(@as(usize, 3), observed.len);
    try std.testing.expectEqualStrings("out/a.md", observed[0].path);
    try std.testing.expectEqualStrings("out/b/spec.md", observed[1].path);
    try std.testing.expectEqualStrings("state <run-identity> cited\n", observed[1].bytes);
    try std.testing.expectEqualStrings("out/catalogs/kept.md", observed[2].path);
    try std.testing.expectEqual(@as(usize, 0), (try files(io, a, project.dir, "missing", null)).len);
}

test "recorded filesystem observations are masked in JSON files and other values kept" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try stable(a, "state/workflow.json", "{\"root\":{\"identity\":{\"filesystem_id\":1,\"file_id\":2,\"generation_id\":0},\"size\":7,\"modified_ns\":3,\"changed_ns\":4},\"files\":[{\"file_id\":5,\"name\":\"kept\"}]}");
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"size\": 7") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"name\": \"kept\"") != null);
    try std.testing.expectEqual(@as(usize, 6), std.mem.count(u8, bytes, "<filesystem-observation>"));
    try std.testing.expectEqualStrings("not json", try stable(a, "state/notes.json", "not json"));
    try std.testing.expectEqualStrings("{\"file_id\":1}", try stable(a, "spec.md", "{\"file_id\":1}"));
}
