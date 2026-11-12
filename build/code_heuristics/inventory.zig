//! Capture the current Git source inventory for advisory development reports.
//! Missing/deleted inputs are distinguished from unreadable or aliased inputs.
const std = @import("std");
const model = @import("model.zig");
const analyze = @import("analyze.zig");
const brittleness = @import("brittleness.zig");
const directories = @import("../../src/adapters/filesystem/directory_access.zig");
const files = @import("../../src/adapters/filesystem/file_access.zig");
const projection = @import("../../src/test_fixtures/request_projection.zig");
const provider_config = @import("../../src/domain/llm_provider_document_decode.zig");
const provider_models = @import("../../src/composition/provider_model_contracts.zig");
const e2e_case = @import("../../test/harness/e2e/contracts.zig");
const evaluation_case = @import("../../test/harness/contracts.zig");
const panel = @import("../../test/harness/generation_comparison.zig");

/// All returned measurements and their source storage belong to `a`.
/// Callers normally provide a short-lived arena for the complete report.
pub fn capture(a: std.mem.Allocator, io: std.Io, root: std.Io.Dir) ![]const model.File {
    const prefix = try git(a, io, root, &.{ "rev-parse", "--show-prefix" });
    defer a.free(prefix);
    if (std.mem.trim(u8, prefix, "\r\n").len != 0) return error.GitInventoryUnavailable;
    const names = try git(a, io, root, &.{ "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", "*.zig" });
    defer a.free(names);
    const deleted = try git(a, io, root, &.{ "ls-files", "--deleted", "-z", "--", "*.zig" });
    defer a.free(deleted);
    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(a);
    var items = std.mem.tokenizeScalar(u8, names, 0);
    while (items.next()) |path| if (model.scope(path) != null) try paths.append(a, path);
    std.mem.sort([]const u8, paths.items, {}, less);

    var measurements: std.ArrayList(model.File) = .empty;
    errdefer measurements.deinit(a);
    var previous: ?[]const u8 = null;
    for (paths.items) |path| {
        if (previous) |prior| if (std.mem.eql(u8, prior, path)) continue;
        previous = path;
        const is_deleted = contains(deleted, path);
        const parent_name = std.fs.path.dirname(path);
        const parent = if (parent_name) |name| directories.open(io, root, name) catch |err| {
            if (err == error.DirectoryMissing and is_deleted) continue;
            return err;
        } else root;
        defer if (parent_name != null) parent.close(io);
        const source = (try files.capture(io, a, parent, std.fs.path.basename(path), null, std.math.maxInt(usize) - 1)) orelse {
            if (is_deleted) continue;
            return error.InventoryInputDisappeared;
        };
        // The analyzer's result and the path must outlive the Git listing.
        // Source is retained because token spellings may borrow from it.
        const owned_path = try a.dupe(u8, path);
        try measurements.append(a, try analyze.analyze(a, owned_path, source));
    }
    return measurements.toOwnedSlice(a);
}

/// Tracked and unignored workflow prompts and JSON resources, in path order.
pub fn assets(a: std.mem.Allocator, io: std.Io, root: std.Io.Dir) ![]const brittleness.Asset {
    var found: std.ArrayList(brittleness.Asset) = .empty;
    for (try listed(a, io, root, &.{ "design/workflows/*.md", "design/workflows/*.json" })) |path|
        try found.append(a, .{ .path = path, .bytes = try read(a, io, root, path) });
    return found.toOwnedSlice(a);
}

/// The distinct `guidance` parts, `protocol_prompt` and `schema` values of a request
/// projection freeze, with the schema's decoded strings, each call read strictly and the
/// manifest's counts confirmed.
pub fn freeze(a: std.mem.Allocator, io: std.Io, root: std.Io.Dir, path: []const u8) ![]const []const u8 {
    const directory = try root.openDir(io, path, .{ .iterate = true, .follow_symlinks = false });
    defer directory.close(io);
    const manifest = try projection.Manifest.decode(a, try directory.readFileAlloc(io, "manifest.json", a, .limited(4096)));
    const listing = try projection.calls(a, io, directory);
    if (!std.meta.eql(listing.manifest, manifest) or listing.paths.len == 0) return error.FreezeManifestMismatch;
    var seen: std.StringArrayHashMapUnmanaged(void) = .empty;
    for (listing.paths) |call| {
        var scratch: std.heap.ArenaAllocator = .init(a);
        defer scratch.deinit();
        const bytes = try directory.readFileAlloc(io, call, scratch.allocator(), .limited(64 * 1024 * 1024));
        const value = projection.Projection.decode(scratch.allocator(), bytes) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidFreezeCall;
        try keep(a, &seen, value.protocol_prompt);
        try keep(a, &seen, value.schema);
        // Text inside the schema reaches the model JSON-escaped; keep its decoded strings.
        const schema = std.json.parseFromSliceLeaky(std.json.Value, scratch.allocator(), value.schema, .{}) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidFreezeCall;
        try keepStrings(a, &seen, schema);
        for (value.content) |part| switch (part) {
            .guidance => |text| try keep(a, &seen, text),
            .system, .user, .evidence => {},
        };
    }
    const values = try a.dupe([]const u8, seen.keys());
    std.mem.sort([]const u8, values, {}, less);
    return values;
}

fn keep(a: std.mem.Allocator, seen: *std.StringArrayHashMapUnmanaged(void), text: []const u8) !void {
    if (seen.contains(text)) return;
    try seen.put(a, try a.dupe(u8, text), {});
}

fn keepStrings(a: std.mem.Allocator, seen: *std.StringArrayHashMapUnmanaged(void), value: std.json.Value) !void {
    switch (value) {
        .string => |text| try keep(a, seen, text),
        .array => |items| for (items.items) |item| try keepStrings(a, seen, item),
        .object => |members| {
            for (members.keys()) |key| try keep(a, seen, key);
            for (members.values()) |item| try keepStrings(a, seen, item);
        },
        else => {},
    }
}

/// The names the model- or case-specific branch count looks for, with the case sources.
pub const Specifics = struct { models: []const []const u8, cases: []const []const u8, case_sources: []const []const u8 };

/// Catalogue model IDs and families, the development cases' IDs and sources, and the
/// evaluation panel's feature and case IDs and sources, each read by its owner.
pub fn specifics(a: std.mem.Allocator, io: std.Io, root: std.Io.Dir) !Specifics {
    var models: std.ArrayList([]const u8) = .empty;
    var catalogue = try provider_config.decode(a, try read(a, io, root, "test/e2e/config/.sddproviders.json"));
    defer catalogue.deinit();
    for (catalogue.value().providers) |provider| for (provider.models) |entry| try models.append(a, try a.dupe(u8, entry.model));
    for (provider_models.registry.entries) |entry| if (entry.model) |id| try models.append(a, id.bytes);
    for (std.meta.fieldNames(@import("../../src/domain/llm_provider_contracts.zig").BedrockFamily)) |family| try models.append(a, family);

    var cases: std.ArrayList([]const u8) = .empty;
    var sources: std.ArrayList([]const u8) = .empty;
    for (try listed(a, io, root, &.{"test/e2e/*workflow.case.json"})) |path| {
        const case = try e2e_case.parse(a, try read(a, io, root, path));
        try cases.appendSlice(a, &.{ case.id, case.feature, case.reference });
        // The case's evaluation sources are the reference files it supplies.
        const evaluation = try evaluation_case.parseCase(a, try read(a, io, root, case.evaluation_case));
        try cases.append(a, evaluation.id);
        for (evaluation.sources) |source| try sources.append(a, try read(a, io, root, source.path));
    }
    const inventory = try panel.parseInventory(a, try read(a, io, root, "test/calibration/semantic-simplicity/cases.json"));
    for (inventory.cases) |case| {
        try cases.appendSlice(a, &.{ case.id, case.feature_id });
        for (case.sources) |source| try sources.append(a, source.text);
    }
    return .{ .models = try distinct(a, models.items), .cases = try distinct(a, cases.items), .case_sources = sources.items };
}

fn distinct(a: std.mem.Allocator, names: []const []const u8) ![]const []const u8 {
    const sorted = try a.dupe([]const u8, names);
    std.mem.sort([]const u8, sorted, {}, less);
    var kept: usize = 0;
    for (sorted) |name| {
        if (kept != 0 and std.mem.eql(u8, sorted[kept - 1], name)) continue;
        sorted[kept] = name;
        kept += 1;
    }
    return sorted[0..kept];
}

/// Tracked and unignored files matching `patterns`, in path order.
fn listed(a: std.mem.Allocator, io: std.Io, root: std.Io.Dir, patterns: []const []const u8) ![]const []const u8 {
    const prefix = try git(a, io, root, &.{ "rev-parse", "--show-prefix" });
    if (std.mem.trim(u8, prefix, "\r\n").len != 0) return error.GitInventoryUnavailable;
    const names = try git(a, io, root, try std.mem.concat(a, []const u8, &.{ &.{ "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--" }, patterns }));
    // A tracked file deleted from the working tree is not an input.
    const deleted = try git(a, io, root, try std.mem.concat(a, []const u8, &.{ &.{ "ls-files", "--deleted", "-z", "--" }, patterns }));
    var paths: std.ArrayList([]const u8) = .empty;
    var items = std.mem.tokenizeScalar(u8, names, 0);
    while (items.next()) |path| if (!contains(deleted, path)) try paths.append(a, path);
    const sorted = try distinct(a, paths.items);
    if (sorted.len == 0) return error.InventoryInputMissing;
    return sorted;
}

fn read(a: std.mem.Allocator, io: std.Io, root: std.Io.Dir, path: []const u8) ![]const u8 {
    const parent_name = std.fs.path.dirname(path);
    const parent = if (parent_name) |name| try directories.open(io, root, name) else root;
    defer if (parent_name != null) parent.close(io);
    return (try files.capture(io, a, parent, std.fs.path.basename(path), null, std.math.maxInt(usize) - 1)) orelse error.InventoryInputDisappeared;
}

fn less(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn contains(names: []const u8, path: []const u8) bool {
    var items = std.mem.tokenizeScalar(u8, names, 0);
    while (items.next()) |name| if (std.mem.eql(u8, path, name)) return true;
    return false;
}

fn git(a: std.mem.Allocator, io: std.Io, root: std.Io.Dir, args: []const []const u8) ![]u8 {
    const argv = try a.alloc([]const u8, args.len + 1);
    defer a.free(argv);
    argv[0] = "git";
    @memcpy(argv[1..], args);
    const result = try std.process.run(a, io, .{ .argv = argv, .cwd = .{ .dir = root } });
    defer a.free(result.stderr);
    errdefer a.free(result.stdout);
    if (result.term != .exited or result.term.exited != 0) return error.GitInventoryUnavailable;
    return result.stdout;
}

test "inventory captures tracked and unignored source in stable path order" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var repository = std.testing.tmpDir(.{});
    defer repository.cleanup();
    _ = try git(a, io, repository.dir, &.{ "-c", "init.templateDir=", "init", "-q" });
    try repository.dir.createDirPath(io, "src/nested");
    try repository.dir.createDirPath(io, "test");
    try repository.dir.createDirPath(io, "zig-out");
    try repository.dir.writeFile(io, .{ .sub_path = "src/zeta.zig", .data = "pub fn zeta() void {}\n" });
    try repository.dir.writeFile(io, .{ .sub_path = "src/deleted.zig", .data = "pub fn gone() void {}\n" });
    try repository.dir.writeFile(io, .{ .sub_path = "src/nested/deleted.zig", .data = "pub fn gone() void {}\n" });
    _ = try git(a, io, repository.dir, &.{ "add", "src" });
    try repository.dir.deleteFile(io, "src/deleted.zig");
    try repository.dir.deleteTree(io, "src/nested");
    try repository.dir.writeFile(io, .{ .sub_path = ".gitignore", .data = "src/ignored.zig\n" });
    try repository.dir.writeFile(io, .{ .sub_path = "src/ignored.zig", .data = "not Zig\n" });
    try repository.dir.writeFile(io, .{ .sub_path = "zig-out/generated.zig", .data = "not Zig\n" });
    try repository.dir.writeFile(io, .{ .sub_path = "src/alpha space.zig", .data = "pub fn alpha() void {}\n" });
    try repository.dir.writeFile(io, .{ .sub_path = "test/example.zig", .data = "test \"example\" {}\n" });
    const first = try capture(a, io, repository.dir);
    const expected = [_][]const u8{ "src/alpha space.zig", "src/zeta.zig", "test/example.zig" };
    try std.testing.expectEqual(expected.len, first.len);
    for (first, expected) |entry, path| try std.testing.expectEqualStrings(path, entry.path);
    try std.testing.expectEqual(.production, first[0].scope);
    try std.testing.expectEqual(.tests, first[2].scope);
    try std.testing.expectEqualDeep(first, try capture(a, io, repository.dir));
}

test "inventory fails on unreadable source kinds and file symlinks" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var repository = std.testing.tmpDir(.{});
    defer repository.cleanup();
    _ = try git(a, io, repository.dir, &.{ "-c", "init.templateDir=", "init", "-q" });
    try repository.dir.createDirPath(io, "src");
    try repository.dir.writeFile(io, .{ .sub_path = "src/real.zig", .data = "pub fn real() void {}\n" });
    try repository.dir.symLink(io, "real.zig", "src/link.zig", .{});
    try std.testing.expectError(error.FileUnavailable, capture(a, io, repository.dir));
    try repository.dir.deleteFile(io, "src/link.zig");
    _ = try git(a, io, repository.dir, &.{ "add", "src/real.zig" });
    try repository.dir.deleteFile(io, "src/real.zig");
    try repository.dir.createDirPath(io, "src/real.zig");
    try std.testing.expectError(error.FileUnavailable, capture(a, io, repository.dir));
}

test "inventory refuses replaced parent symlinks and nonrepository roots" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var repository = std.testing.tmpDir(.{});
    defer repository.cleanup();
    try std.testing.expectError(error.GitInventoryUnavailable, capture(a, io, repository.dir));
    _ = try git(a, io, repository.dir, &.{ "-c", "init.templateDir=", "init", "-q" });
    try repository.dir.createDirPath(io, "src/nested");
    try repository.dir.createDirPath(io, "other");
    try repository.dir.writeFile(io, .{ .sub_path = "src/nested/real.zig", .data = "pub fn real() void {}\n" });
    try repository.dir.writeFile(io, .{ .sub_path = "other/real.zig", .data = "pub fn other() void {}\n" });
    _ = try git(a, io, repository.dir, &.{ "add", "src" });
    try repository.dir.deleteTree(io, "src/nested");
    try repository.dir.symLink(io, "../other", "src/nested", .{ .is_directory = true });
    try std.testing.expectError(error.DirectoryUnavailable, capture(a, io, repository.dir));
}

fn projected(comptime guidance: []const u8, comptime protocol: []const u8) []const u8 {
    return "{\"provider\":\"test-provider\",\"model\":\"test-model\",\"provider_config\":{\"deadline_only\":{\"request_timeout\":1000}}," ++
        "\"model_slot\":\"spec_generation\",\"workflow_id\":\"spec-generation\",\"content\":[{\"guidance\":\"" ++ guidance ++ "\"},{\"user\":\"user text\"}]," ++
        "\"protocol_prompt\":\"" ++ protocol ++ "\",\"schema\":\"{\\\"type\\\":\\\"object\\\"}\",\"response_mode\":\"prompt_only\"," ++
        "\"controls\":{\"temperatures\":{\"configured\":0.1,\"runaway_retry\":1}},\"sampling\":\"configured\",\"reasoning_effort\":null," ++
        "\"operation_kind\":\"inference\",\"original_sources\":[],\"prose_fields\":[],\"field_policies\":[],\"exact_scope\":null," ++
        "\"members\":[],\"coverages\":[]}";
}

test "freeze keeps distinct guidance, protocol and schema text, the schema's decoded strings, and confirms its manifest" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var root = std.testing.tmpDir(.{});
    defer root.cleanup();
    try root.dir.createDirPath(io, "freeze/group/scenario-001");
    try root.dir.writeFile(io, .{ .sub_path = "freeze/group/scenario-001/call-0001.json", .data = projected("Keep each value.", "Return one object.") });
    try root.dir.writeFile(io, .{ .sub_path = "freeze/group/scenario-001/call-0002.json", .data = projected("Keep each value.", "Return JSON only.") });
    try root.dir.writeFile(io, .{ .sub_path = "freeze/manifest.json", .data = "{\"groups\":1,\"scenarios\":1,\"calls\":2}" });
    const values = try freeze(a, io, root.dir, "freeze");
    const expected = [_][]const u8{ "Keep each value.", "Return JSON only.", "Return one object.", "object", "type", "{\"type\":\"object\"}" };
    try std.testing.expectEqual(expected.len, values.len);
    for (expected, values) |want, got| try std.testing.expectEqualStrings(want, got);

    // A manifest that disagrees with the directory, an unknown member and a missing
    // manifest are refused.
    try root.dir.writeFile(io, .{ .sub_path = "freeze/manifest.json", .data = "{\"groups\":1,\"scenarios\":1,\"calls\":3}" });
    try std.testing.expectError(error.FreezeManifestMismatch, freeze(a, io, root.dir, "freeze"));
    try root.dir.writeFile(io, .{ .sub_path = "freeze/manifest.json", .data = "{\"groups\":1,\"scenarios\":1,\"calls\":2,\"extra\":0}" });
    try std.testing.expectError(error.InvalidJsonDocument, freeze(a, io, root.dir, "freeze"));
    try root.dir.writeFile(io, .{ .sub_path = "freeze/manifest.json", .data = "{\"groups\":1,\"scenarios\":1,\"calls\":2}" });
    try root.dir.writeFile(io, .{ .sub_path = "freeze/group/scenario-001/call-0002.json", .data = comptime ("{\"version\":\"model-request-debug/v13\"," ++ projected("Keep each value.", "Return JSON only.")[1..]) });
    try std.testing.expectError(error.InvalidFreezeCall, freeze(a, io, root.dir, "freeze"));
    try root.dir.deleteFile(io, "freeze/manifest.json");
    try std.testing.expectError(error.FileNotFound, freeze(a, io, root.dir, "freeze"));
    // An empty freeze holds nothing to measure.
    try root.dir.createDirPath(io, "empty");
    try root.dir.writeFile(io, .{ .sub_path = "empty/manifest.json", .data = "{\"groups\":0,\"scenarios\":0,\"calls\":0}" });
    try std.testing.expectError(error.FreezeManifestMismatch, freeze(a, io, root.dir, "empty"));
}

test "assets are the tracked workflow prompts and JSON resources only" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var repository = std.testing.tmpDir(.{});
    defer repository.cleanup();
    _ = try git(a, io, repository.dir, &.{ "-c", "init.templateDir=", "init", "-q" });
    try repository.dir.createDirPath(io, "design/workflows/demo");
    try repository.dir.writeFile(io, .{ .sub_path = "design/workflows/demo/task.prompt.md", .data = "Summarise the notes.\n" });
    try repository.dir.writeFile(io, .{ .sub_path = "design/workflows/demo/result.schema.json", .data = "{}" });
    try repository.dir.writeFile(io, .{ .sub_path = "design/workflows/demo.workflow.yaml", .data = "schema: workflow/v1\n" });
    try repository.dir.writeFile(io, .{ .sub_path = "design/template.md", .data = "Not an asset.\n" });
    try repository.dir.writeFile(io, .{ .sub_path = "design/workflows/demo/removed.prompt.md", .data = "Removed.\n" });
    _ = try git(a, io, repository.dir, &.{ "add", "design/workflows/demo/removed.prompt.md" });
    try repository.dir.deleteFile(io, "design/workflows/demo/removed.prompt.md");
    const found = try assets(a, io, repository.dir);
    try std.testing.expectEqual(@as(usize, 2), found.len);
    try std.testing.expectEqualStrings("design/workflows/demo/result.schema.json", found[0].path);
    try std.testing.expectEqualStrings("design/workflows/demo/task.prompt.md", found[1].path);
    try std.testing.expectEqualStrings("Summarise the notes.\n", found[1].bytes);
}

test "specifics read the catalogue, the development cases and the panel through their owners" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const found = try specifics(arena.allocator(), std.testing.io, .cwd());
    for (std.meta.fieldNames(@import("../../src/domain/llm_provider_contracts.zig").BedrockFamily)) |family| {
        const listed_family = for (found.models) |name| {
            if (std.mem.eql(u8, name, family)) break true;
        } else false;
        try std.testing.expect(listed_family);
    }
    try std.testing.expect(found.models.len > std.meta.fieldNames(@import("../../src/domain/llm_provider_contracts.zig").BedrockFamily).len);
    try std.testing.expect(found.cases.len != 0 and found.case_sources.len != 0);
}
