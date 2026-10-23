//! Offline step trace of one scripted workflow scenario, written as structural
//! equivalence evidence (ADR 0030 "Freeze first"). It is an observation, not an
//! assertion: tests never compare it. Each executed step becomes one line keyed
//! by its source call path, so a structural conversion can be compared with the
//! trace recorded before it. A request-lifecycle step inside a model-request
//! wrapper collapses to the wrapper's call site plus the stage's operation ID,
//! the form ADR 0030's `request-model` step keeps.
const std = @import("std");
const compilation = @import("../domain/workflow_compilation.zig");
const execution = @import("../domain/workflow_execution.zig");
const source = @import("../domain/workflow_source.zig");
const filesystem = @import("../domain/filesystem_identity.zig");

pub const schema = "workflow-step-trace/v1";
pub const directory = ".zig-cache/workflow-step-trace";

/// The subgraphs that wrap one model request's lifecycle today, as ADR 0030's
/// Context names them.
const request_wrappers = [_][]const u8{ "model-request", "model-request-with-context", "support-request", "composition-request", "composition-request-body" };
const request_body = "model-request-body";

pub const Error = std.mem.Allocator.Error || error{UnwrappedRequestLifecycle};

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

    pub fn record(self: *Trace, step: *const compilation.CompiledStep, applied: execution.Applied) Error!void {
        writeLine(&self.lines.writer, step, applied) catch |err| return switch (err) {
            error.WriteFailed => error.OutOfMemory,
            error.UnwrappedRequestLifecycle => error.UnwrappedRequestLifecycle,
        };
        self.steps += 1;
    }
};

fn wrapper(entry: source.Entry) bool {
    if (entry.kind != .subgraph) return false;
    for (request_wrappers) |name| if (std.mem.eql(u8, entry.target, name)) return true;
    return false;
}

/// Writes the step's source call path, stopping at a request wrapper. A request
/// body reached without a wrapper is an error, so a renamed or new wrapper can
/// never produce a key that silently stops matching.
pub fn writeCallSite(w: *std.Io.Writer, step: *const compilation.CompiledStep) (std.Io.Writer.Error || error{UnwrappedRequestLifecycle})!void {
    if (step.source_chain.len == 0) return w.writeAll(step.id.bytes);
    for (step.source_chain, 0..) |entry, index| {
        if (entry.kind == .subgraph and std.mem.eql(u8, entry.target, request_body)) return error.UnwrappedRequestLifecycle;
        if (index != 0) try w.writeByte('/');
        try w.writeAll(entry.id);
        if (wrapper(entry)) return;
    }
}

fn writeLine(w: *std.Io.Writer, step: *const compilation.CompiledStep, applied: execution.Applied) (std.Io.Writer.Error || error{UnwrappedRequestLifecycle})!void {
    try writeCallSite(w, step);
    try w.print("#{s}\t", .{step.operation_id.bytes});
    switch (applied) {
        .outcome => |tag| try w.writeAll(@tagName(tag)),
        .rejected => |reason| try writeRejection(w, reason),
    }
    try w.writeByte('\n');
}

/// The canonical rejection diagnostic, plus the executions a retry exhaustion
/// counted.
pub fn writeRejection(w: *std.Io.Writer, reason: execution.Rejection) std.Io.Writer.Error!void {
    try w.print("rejected:{s}:{s}", .{ @tagName(reason), reason.diagnostic() });
    if (reason == .retry_limit) try w.print(":executions={d}", .{reason.retry_limit.completed_executions});
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

/// Writes `<workflow>-<case>-<scenario>.trace`, `.json` and the masked files
/// beneath `<...>.files/`.
pub fn write(io: std.Io, a: std.mem.Allocator, trace: *Trace, summary: Summary, observed: []const File) !void {
    const base = try std.fmt.allocPrint(a, "{s}/{s}-{s}-{d:0>3}", .{ directory, summary.workflow, summary.case, summary.scenario });
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

test "a lifecycle step collapses to its wrapper call site and stage operation" {
    var trace: Trace = .init(std.testing.allocator);
    defer trace.deinit();
    const chain = [_]source.Entry{
        chainEntry(null, "reconcile", .subgraph, "reconciliation"),
        chainEntry("reconciliation", "dispositions", .subgraph, "model-request"),
        chainEntry("model-request", "request", .subgraph, "model-request-body"),
        chainEntry("model-request-body", "account", .operation, "advance-model-attempt-accounting"),
    };
    const step = testStep(&chain, "advance-model-attempt-accounting");
    try trace.record(&step, .{ .outcome = .ok });
    try trace.record(&step, .{ .rejected = .authority });
    try std.testing.expectEqualStrings("reconcile/dispositions#advance-model-attempt-accounting\tok\nreconcile/dispositions#advance-model-attempt-accounting\trejected:authority:failed\n", trace.written());
    try std.testing.expectEqual(@as(usize, 2), trace.steps);
}

test "nested and direct composition bodies collapse at the outermost wrapper" {
    var trace: Trace = .init(std.testing.allocator);
    defer trace.deinit();
    const nested = [_]source.Entry{
        chainEntry(null, "summary", .subgraph, "composition-request"),
        chainEntry("composition-request", "request", .subgraph, "composition-request-body"),
        chainEntry("composition-request-body", "request", .subgraph, "model-request-body"),
        chainEntry("model-request-body", "invoke", .operation, "invoke-model"),
    };
    const direct = [_]source.Entry{
        chainEntry(null, "extract", .subgraph, "extraction"),
        chainEntry("extraction", "content-request", .subgraph, "composition-request-body"),
        chainEntry("composition-request-body", "retain", .operation, "retain-json-part"),
    };
    try trace.record(&testStep(&nested, "invoke-model"), .{ .outcome = .ok });
    try trace.record(&testStep(&direct, "retain-json-part"), .{ .outcome = .ok });
    try std.testing.expectEqualStrings("summary#invoke-model\tok\nextract/content-request#retain-json-part\tok\n", trace.written());
}

test "a request body without a wrapper is an error, not a silent key" {
    var trace: Trace = .init(std.testing.allocator);
    defer trace.deinit();
    const chain = [_]source.Entry{
        chainEntry(null, "review", .subgraph, "renamed-request"),
        chainEntry("renamed-request", "request", .subgraph, "model-request-body"),
        chainEntry("model-request-body", "close", .operation, "complete-model-request"),
    };
    try std.testing.expectError(error.UnwrappedRequestLifecycle, trace.record(&testStep(&chain, "complete-model-request"), .{ .outcome = .ok }));
    try std.testing.expectEqual(@as(usize, 0), trace.steps);
}

test "a step without a source chain keys by its compiled ID and rejections use the canonical diagnostic" {
    var trace: Trace = .init(std.testing.allocator);
    defer trace.deinit();
    const step = testStep(&.{}, "retire-model-transport");
    try trace.record(&step, .{ .rejected = .{ .operation_failed = error.OperationExecutionFailed } });
    try std.testing.expectEqualStrings("g1-step#retire-model-transport\trejected:operation_failed:OperationExecutionFailed\n", trace.written());
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
