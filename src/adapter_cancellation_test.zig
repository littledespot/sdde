//! Every filesystem and system adapter that feeds a stage maps a cancelled `std.Io` call to its port's
//! `Cancelled`, and no other call of the same kind is reported as one. Each case cancels every call of one
//! class that a successful use of the adapter makes, in turn, on a real directory; `cancelling_io.sweep`
//! requires the cancelled attempt to end `Cancelled` and the uncancelled one to succeed.
const std = @import("std");
const cancelling = @import("test_fixtures/cancelling_io.zig");
const project_roots = @import("test_fixtures/project_roots.zig");
const roots = @import("domain/bootstrap_root_registry.zig");
const artifacts = @import("domain/workflow_artifact_registry.zig");
const feature = @import("domain/feature_directory.zig");
const clarification = @import("domain/clarification_inputs.zig");
const toolchain = @import("domain/toolchain.zig");
const reference_selector = @import("domain/reference_selector.zig");
const evidence = @import("actions/reference/prepare_reference_evidence.zig");
const unicode = @import("unicode_normalization");
const feature_inspector = @import("adapters/filesystem/feature_directory_inspector.zig");
const feature_inputs = @import("adapters/filesystem/feature_input_source.zig");
const reference_inspector = @import("adapters/filesystem/reference_directory_inspector.zig");
const reference_corpus = @import("adapters/filesystem/reference_corpus_source.zig");
const principle_source = @import("adapters/filesystem/principle_source.zig");
const toolchain_source = @import("adapters/filesystem/toolchain_authority_source.zig");
const state_identity = @import("adapters/system/reference_state_identity.zig");

const feature_id = "Group/Café";
const feature_path = "requirements/current/Group/Café";

/// A project with one of everything a stage reads, observed as the engine observes it at startup.
const Fixture = struct {
    project: std.testing.TmpDir,
    owner: *roots.Owner,
    arena: std.heap.ArenaAllocator,
    prior: feature.Directory,
    paths: artifacts.FeaturePaths,

    fn init(self: *Fixture) !void {
        const io = std.testing.io;
        self.project = std.testing.tmpDir(.{ .iterate = true });
        errdefer self.project.cleanup();
        for ([_][]const u8{ feature_path, "references/docs/nested", "principles/nested", "presets", "workflows" }) |path| try self.project.dir.createDirPath(io, path);
        self.owner = try project_roots.owner(std.testing.allocator, self.project.dir);
        errdefer roots.deinitOwner(self.owner);
        self.arena = .init(std.testing.allocator);
        errdefer self.arena.deinit();
        const a = self.arena.allocator();
        const registry = roots.registry(self.owner);
        var inspector: feature_inspector.Adapter = .{ .io = io, .project_root = self.project.dir };
        var port = inspector.inspector();
        port.capability = registry.featureDirectoryRead();
        self.prior = try port.inspect(a, .{ .feature_id = .{ .bytes = feature_id }, .project_relative_path = feature_path });
        self.paths = try artifacts.resolveFeaturePaths(a, registry.featureArtifactRoots(), self.prior.selector);
        // The files each reader captures: a clarification form and state, the workflow state, references,
        // principles and the toolchain documents.
        const form = clarification.Id{ .stage = .spec, .ordinal = 1 };
        try self.write(self.paths.get(.clarification_forms).project_relative, &form.filename(), "form\n");
        try self.write(std.fs.path.dirname(self.paths.get(.clarification_state).project_relative).?, std.fs.path.basename(self.paths.get(.clarification_state).project_relative), "state\n");
        try self.write(std.fs.path.dirname(self.paths.get(.workflow_state).project_relative).?, std.fs.path.basename(self.paths.get(.workflow_state).project_relative), "workflow state\n");
        try self.write("references/docs", "one.md", "# One\n\nA reference.\n");
        try self.write("references/docs/nested", "two.md", "# Two\n\nAnother reference.\n");
        try self.write("principles", "first.md", "# First principle\n");
        try self.write("principles/nested", "second.md", "# Second principle\n");
        try self.write("principles", toolchain.project_filename, "schema: 1\n");
        try self.write("presets", "one" ++ toolchain.preset_suffix, "id: one\n");
    }

    fn write(self: *Fixture, directory: []const u8, name: []const u8, bytes: []const u8) !void {
        try self.project.dir.createDirPath(std.testing.io, directory);
        var folder = try self.project.dir.openDir(std.testing.io, directory, .{});
        defer folder.close(std.testing.io);
        try folder.writeFile(std.testing.io, .{ .sub_path = name, .data = bytes });
    }

    fn deinit(self: *Fixture) void {
        self.arena.deinit();
        roots.deinitOwner(self.owner);
        self.project.cleanup();
    }

    fn bootstrap(self: *const Fixture) *const roots.BootstrapRootRegistry {
        return roots.registry(self.owner);
    }
};

/// Cancels each call of every class in `ops` that `attempt` makes, and requires the class to be reached.
fn sweepEach(ops: []const cancelling.Op, fixture: *const Fixture, comptime attempt: fn (*const Fixture, std.Io) anyerror!void) !void {
    for (ops) |op| {
        const calls = try cancelling.sweep(op, fixture, attempt);
        std.testing.expect(calls > 0) catch |err| {
            std.debug.print("the adapter never makes a call of class {s}\n", .{@tagName(op)});
            return err;
        };
    }
}

fn inspectFeature(fixture: *const Fixture, io: std.Io) anyerror!void {
    var adapter: feature_inspector.Adapter = .{ .io = io, .project_root = fixture.project.dir };
    var port = adapter.inspector();
    port.capability = fixture.bootstrap().featureDirectoryRead();
    _ = try port.inspect(std.testing.allocator, fixture.prior.selector);
}

fn captureFeatureInputs(fixture: *const Fixture, io: std.Io) anyerror!void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var adapter: feature_inputs.Adapter = .{ .io = io, .project_root = fixture.project.dir };
    var inputs = adapter.capturer();
    inputs.capability = fixture.bootstrap().featureInputRead();
    const captured = try inputs.capture(arena.allocator(), fixture.prior, fixture.paths);
    try std.testing.expect(captured.state != null and captured.forms.len == 1);
    var state = adapter.workflowStateCapturer();
    state.capability = fixture.bootstrap().featureInputRead();
    try std.testing.expect((try state.capture(arena.allocator(), fixture.prior, fixture.paths)) != null);
}

fn captureReferences(fixture: *const Fixture, io: std.Io) anyerror!void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var inspector: reference_inspector.Adapter = .{ .io = io, .project_root = fixture.project.dir };
    var directory = inspector.inspector();
    directory.capability = fixture.bootstrap().referenceSources();
    const observed = try directory.inspect(a, .{ .bytes = "docs" });
    var corpus: reference_corpus.Adapter = .{ .io = io, .project_root = fixture.project.dir };
    var enumerator = corpus.enumerator();
    enumerator.capability = fixture.bootstrap().referenceContentRead();
    const raw = try enumerator.enumerate(a, observed);
    // The engine validates the inventory between the two reads; so does this.
    const inventory = try evidence.steps.validateInventory(.{ .normalize_fn = unicode.nfc }, .{ .fold_fn = unicode.caseFold }, a, raw);
    var capturer = corpus.capturer();
    capturer.capability = fixture.bootstrap().referenceContentRead();
    _ = try capturer.capture(a, inventory);
}

fn readPrinciples(fixture: *const Fixture, io: std.Io) anyerror!void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var adapter: principle_source.Adapter = .{ .io = io, .project_root = fixture.project.dir };
    var reader = adapter.reader();
    reader.capability = fixture.bootstrap().projectPrinciples();
    const captured = try reader.read(arena.allocator());
    try std.testing.expectEqual(@as(usize, 2), captured.sources.len);
}

fn captureToolchain(fixture: *const Fixture, io: std.Io) anyerror!void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var adapter = toolchain_source.Adapter.init(io, fixture.project.dir);
    var project = adapter.projectCapturer();
    project.capability = fixture.bootstrap().projectPrinciples();
    _ = try project.captureProject(a);
    var presets = adapter.presetEnumerator();
    presets.capability = fixture.bootstrap().toolchainPresetRegistry();
    const entries = try presets.inventoryPresets(a);
    try std.testing.expectEqual(@as(usize, 1), entries.len);
    var capturer = adapter.presetCapturer();
    capturer.capability = fixture.bootstrap().toolchainPresetRegistry();
    _ = try capturer.capturePreset(entries[0], a);
}

fn drawIdentity(_: void, io: std.Io) anyerror!void {
    var adapter: state_identity.Adapter = .{ .io = io };
    _ = try adapter.source().next();
}

test "a cancelled call of the feature directory inspector is a cancellation" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try sweepEach(&.{ .open_dir, .real_path_file, .dir_access, .dir_stat }, &fixture, inspectFeature);
}

test "a cancelled call while reading a feature's clarification inputs and workflow state is a cancellation" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try sweepEach(&.{ .open_dir, .real_path_file, .dir_access, .dir_stat, .dir_read, .stat_file, .stat, .read_positional }, &fixture, captureFeatureInputs);
}

test "a cancelled call while inspecting, enumerating and capturing reference sources is a cancellation" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try sweepEach(&.{ .open_dir, .real_path_file, .dir_access, .dir_stat, .dir_read, .stat_file, .stat, .read_positional }, &fixture, captureReferences);
}

test "a cancelled call while reading the principle sources is a cancellation" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try sweepEach(&.{ .open_dir, .real_path_file, .dir_access, .dir_stat, .dir_read, .stat_file, .stat, .read_positional }, &fixture, readPrinciples);
}

test "a cancelled call while capturing the toolchain documents is a cancellation, not an invalid toolchain" {
    var fixture: Fixture = undefined;
    try fixture.init();
    defer fixture.deinit();
    try sweepEach(&.{ .open_dir, .open_file, .dir_read, .stat, .read_positional }, &fixture, captureToolchain);
}

test "a cancelled random draw is a cancellation, not an unavailable identity" {
    try std.testing.expect(try cancelling.sweep(.random_secure, {}, drawIdentity) > 0);
}
