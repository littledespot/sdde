const std = @import("std");
const contracts = @import("contracts.zig");
const files = @import("../files.zig");
const directories = @import("../../../src/adapters/filesystem/directory_access.zig");
const relative = @import("../../../src/domain/relative_directory_path.zig");
const evaluator = @import("../contracts.zig");
pub const CapturedFile = struct { mapping: contracts.Copy, bytes: []const u8 };
pub const Evaluation = struct {
    case_source: []const u8,
    case_bytes: []const u8,
    case: evaluator.Case,
    rubric_bytes: []const u8,
    rubric: evaluator.Rubric,
    config_source: []const u8,
    config_bytes: []const u8,
    sources: []const evaluator.Document,
};
pub const Capture = struct {
    config_source: []const u8,
    config: []const u8,
    directories: []const []const u8,
    files: []const CapturedFile,
    evaluation: Evaluation,
};

/// The caller owns one arena for the case, captured bytes and invocation.
pub fn capture(io: std.Io, allocator: std.mem.Allocator, repository: std.Io.Dir, selected: contracts.Case) !Capture {
    const config = try files.read(io, allocator, repository, selected.config);
    const captured = try allocator.alloc(CapturedFile, selected.files.len);
    for (selected.files, captured) |mapping, *file| file.* = .{
        .mapping = mapping,
        .bytes = try files.read(io, allocator, repository, mapping.source),
    };
    const case_bytes = try files.read(io, allocator, repository, selected.evaluation_case);
    const evaluation_case = try evaluator.parseCase(allocator, case_bytes);
    const rubric_bytes = try files.read(io, allocator, repository, evaluation_case.rubric);
    const rubric = try evaluator.parseRubric(allocator, rubric_bytes);
    const sources = try allocator.alloc(evaluator.Document, evaluation_case.sources.len);
    for (evaluation_case.sources, sources) |source, *document| {
        const bytes = for (captured) |file| {
            if (std.mem.eql(u8, file.mapping.source, source.path)) break file.bytes;
        } else return error.EvaluationSourceNotInProject;
        document.* = .{ .id = source.id, .text = bytes };
    }
    return .{ .config_source = selected.config, .config = config, .directories = selected.directories, .files = captured, .evaluation = .{
        .case_source = selected.evaluation_case,
        .case_bytes = case_bytes,
        .case = evaluation_case,
        .rubric_bytes = rubric_bytes,
        .rubric = rubric,
        .config_source = selected.evaluation_config,
        .config_bytes = try files.read(io, allocator, repository, selected.evaluation_config),
        .sources = sources,
    } };
}

pub fn materialize(io: std.Io, project: std.Io.Dir, captured: Capture) !void {
    try write(io, project, ".sddtoolkit.json", captured.config);
    for (captured.directories) |path| {
        const directory = try directories.ensure(io, project, path);
        directory.close(io);
    }
    for (captured.files) |file| try write(io, project, file.mapping.destination, file.bytes);
}

/// Once ordinary bootstrap validates configuration, reject any fixture which
/// pre-seeds feature output. A file's prior existence cannot satisfy the oracle.
pub fn validateOutputs(captured: Capture, roots: @import("../../../src/domain/workflow_artifact_registry.zig").FeatureRoots, allocator: std.mem.Allocator) !void {
    const states = try std.mem.concat(allocator, u8, &.{ roots.workflows, "/features" });
    defer allocator.free(states);
    for (captured.files) |file| {
        if (relative.contains(roots.specs, file.mapping.destination) or relative.contains(states, file.mapping.destination)) return error.FixtureContainsWorkflowOutput;
    }
}

pub fn verifySources(io: std.Io, allocator: std.mem.Allocator, repository: std.Io.Dir, captured: Capture) !void {
    for ([_]struct { path: []const u8, bytes: []const u8 }{
        .{ .path = captured.evaluation.case_source, .bytes = captured.evaluation.case_bytes },
        .{ .path = captured.evaluation.case.rubric, .bytes = captured.evaluation.rubric_bytes },
        .{ .path = captured.evaluation.config_source, .bytes = captured.evaluation.config_bytes },
    }) |input| {
        const current = try files.read(io, allocator, repository, input.path);
        defer allocator.free(current);
        if (!std.mem.eql(u8, current, input.bytes)) return error.FixtureChanged;
    }
    const config = try files.read(io, allocator, repository, captured.config_source);
    defer allocator.free(config);
    if (!std.mem.eql(u8, config, captured.config)) return error.FixtureChanged;
    for (captured.files) |file| {
        const current = try files.read(io, allocator, repository, file.mapping.source);
        defer allocator.free(current);
        if (!std.mem.eql(u8, current, file.bytes)) return error.FixtureChanged;
    }
}

/// The judge receives exactly the reference files supplied to this invocation,
/// with bytes borrowed from the same immutable fixture capture.
pub fn validateEvaluationSources(allocator: std.mem.Allocator, captured: Capture, root: []const u8, selector: []const u8) !void {
    const selected_root = try std.fs.path.join(allocator, &.{ root, selector });
    defer allocator.free(selected_root);
    var count: usize = 0;
    for (captured.files) |file| {
        if (!relative.contains(selected_root, file.mapping.destination)) continue;
        const found = for (captured.evaluation.case.sources) |source| {
            if (std.mem.eql(u8, source.path, file.mapping.source)) break true;
        } else false;
        if (!found) return error.EvaluationSourceMismatch;
        count += 1;
    }
    if (count != captured.evaluation.sources.len) return error.EvaluationSourceMismatch;
    for (captured.evaluation.case.sources) |source| {
        var matches: usize = 0;
        for (captured.files) |file| {
            if (relative.contains(selected_root, file.mapping.destination) and std.mem.eql(u8, source.path, file.mapping.source)) matches += 1;
        }
        if (matches != 1) return error.EvaluationSourceMismatch;
    }
}

fn write(io: std.Io, root: std.Io.Dir, path: []const u8, bytes: []const u8) !void {
    const parent_path = std.fs.path.dirname(path);
    const parent = if (parent_path) |name| try directories.ensure(io, root, name) else root;
    defer if (parent_path != null) parent.close(io);
    const file = try parent.createFile(io, std.fs.path.basename(path), .{ .exclusive = true });
    defer file.close(io);
    try file.writeStreamingAll(io, bytes);
}
