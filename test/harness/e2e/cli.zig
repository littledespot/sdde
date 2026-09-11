const std = @import("std");
const c = @import("contracts.zig");
const fixture = @import("fixture.zig");
pub const output_root = "zig-out/e2e-spec";

pub fn parse(args: []const []const u8) ![]const u8 {
    if (args.len != 2 or !std.mem.eql(u8, args[0], "--case")) return error.InvalidArguments;
    try @import("../contracts.zig").path(args[1]);
    return args[1];
}

pub fn main(init: std.process.Init) !void {
    if (!try command(init)) std.process.exit(1);
}

fn command(init: std.process.Init) !bool {
    const io = init.io;
    const allocator = init.arena.allocator();
    var iterator = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer iterator.deinit();
    _ = iterator.skip();
    var arguments: std.ArrayList([]const u8) = .empty;
    while (iterator.next()) |argument| try arguments.append(allocator, argument);
    if (arguments.items.len == 1 and std.mem.eql(u8, arguments.items[0], "--help")) {
        try std.Io.File.stdout().writeStreamingAll(io, "Usage: zig build e2e-spec -- --case <relative-workflow.case.json>\nRuns one selected case with scripted provider observations. Retains one UTC-dated run under zig-out/e2e-spec. Success requires actual workflow publication and all expected artifacts. No live API calls.\n");
        return true;
    }
    const case_path = parse(arguments.items) catch {
        try std.Io.File.stderr().writeStreamingAll(io, "Select exactly one E2E case with --case; use --help.\n");
        return false;
    };
    const parent = try @import("../../../src/adapters/filesystem/directory_access.zig").ensure(io, .cwd(), output_root);
    defer parent.close(io);
    const run = try @import("run_directory.zig").Run.create(io, parent);
    defer run.close(io);
    var report: c.Report = .{ .started_at_utc = &run.started_at_utc, .status = .input_invalid };
    execute(io, allocator, case_path, run.project, &report) catch |err| {
        report.status = if (report.case_id == null) .input_invalid else .harness_error;
        report.specification = null;
        report.diagnostic = @errorName(err);
    };
    try save(io, allocator, run.dir, report);
    const message = try std.fmt.allocPrint(allocator, "E2E result: {s}\nReport: {s}/{s}/report.md\n", .{ @tagName(report.status), output_root, run.name });
    try std.Io.File.stdout().writeStreamingAll(io, message);
    if (report.specification) |path| try std.Io.File.stdout().writeStreamingAll(io, try std.fmt.allocPrint(allocator, "Specification: {s}/{s}/project/{s}\n", .{ output_root, run.name, path }));
    return report.status == .passed;
}

fn execute(io: std.Io, allocator: std.mem.Allocator, case_path: []const u8, project: std.Io.Dir, report: *c.Report) !void {
    const case_bytes = try @import("../files.zig").read(io, allocator, .cwd(), case_path);
    const selected = try c.parse(allocator, case_bytes);
    report.case_id = selected.id;
    report.workflow_id = selected.workflow_id;
    const captured = try fixture.capture(io, allocator, .cwd(), selected);
    try fixture.materialize(io, project, captured);
    try @import("invoke.zig").run(io, allocator, project, selected, captured, report);
    fixture.verifySources(io, allocator, .cwd(), captured) catch |err| switch (err) {
        error.FixtureChanged => {
            report.status = .fixture_changed;
            report.specification = null;
            report.diagnostic = "SOURCE_FIXTURE_CHANGED";
        },
        else => return err,
    };
}

fn save(io: std.Io, allocator: std.mem.Allocator, dir: std.Io.Dir, report: c.Report) !void {
    const json = try @import("../../../src/domain/canonical_json.zig").encode(c.Report, allocator, report);
    try write(io, dir, "report.json", json);
    const markdown = try std.fmt.allocPrint(allocator, "# Spec E2E run\n\nE2E checks: **{s}**\n\n" ++
        "Provider observations: scripted.\n\n" ++
        "Publication check: **{s}**.\n\n" ++
        "Authored fixture content: **{s}**.\n\n" ++
        "Semantic quality: **not evaluated**. No rubric evaluation was run.\n\n" ++
        "Workflow outcome: `{s}`. Model calls: {d}.\n\n" ++
        "Diagnostic: `{s}`.\n\n" ++
        "This folder contains one isolated project and one workflow invocation. " ++
        "Only a specification published by that invocation can satisfy this test. " ++
        "The harness does not export in-memory candidates.\n\n" ++
        "See report.json for the selected case, UTC start time and any published specification path. " ++
        "Fixture conformance does not establish live model quality.\n", .{ @tagName(report.status), @tagName(report.publication_check), @tagName(report.fixture_content_check), if (report.workflow_outcome) |tag| @tagName(tag) else "not_run", report.model_calls, report.diagnostic orelse "none" });
    try write(io, dir, "report.md", markdown);
}

fn write(io: std.Io, dir: std.Io.Dir, name: []const u8, bytes: []const u8) !void {
    const file = try dir.createFile(io, name, .{ .exclusive = true });
    defer file.close(io);
    try file.writeStreamingAll(io, bytes);
    try file.sync(io);
}
