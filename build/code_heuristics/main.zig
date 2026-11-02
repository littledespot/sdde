//! Offline development tool. No workflow execution or provider capability.
const std = @import("std");
const inventory = @import("inventory.zig");
const report = @import("report.zig");
const brittleness = @import("brittleness.zig");
const files = @import("../../src/adapters/filesystem/file_access.zig");

const help =
    \\Usage: zig build code-heuristics -- --freeze <request-projection freeze>
    \\Write an advisory repository-wide Zig code report, with the FIX06 T5 brittleness counts, to zig-out/code-heuristics/report.md and report.json (under --prefix when supplied).
    \\The development executable takes one output directory and --freeze <directory>; --help prints this text.
    \\
;

const Arguments = struct { output: []const u8, freeze: []const u8 };

pub fn main(init: std.process.Init) !void {
    command(init) catch |err| {
        try std.Io.File.stderr().writeStreamingAll(init.io, try std.fmt.allocPrint(init.arena.allocator(), "Code heuristics report failed: {s}.\n", .{@errorName(err)}));
        if (err == error.InvalidArguments) try std.Io.File.stderr().writeStreamingAll(init.io, help);
        std.process.exit(1);
    };
}

fn command(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    const arguments = (try parse(args[1..])) orelse return std.Io.File.stdout().writeStreamingAll(init.io, help);
    const measurements = try inventory.capture(a, init.io, .cwd());
    const specifics = try inventory.specifics(a, init.io, .cwd());
    const counts = try brittleness.count(a, .{
        .files = measurements,
        .assets = try inventory.assets(a, init.io, .cwd()),
        .freeze = try inventory.freeze(a, init.io, .cwd(), arguments.freeze),
        .models = specifics.models,
        .cases = specifics.cases,
        .case_sources = specifics.case_sources,
    });
    const result = try report.build(a, measurements, counts);
    const markdown = try report.markdown(a, result);
    const json = try std.json.Stringify.valueAlloc(a, result, .{ .whitespace = .indent_2 });
    try std.Io.Dir.cwd().createDirPath(init.io, arguments.output);
    const directory = try std.Io.Dir.cwd().openDir(init.io, arguments.output, .{ .follow_symlinks = false });
    defer directory.close(init.io);
    try files.replace(init.io, a, directory, "report.md", .any, markdown);
    try files.replace(init.io, a, directory, "report.json", .any, json);
    try std.Io.File.stdout().writeStreamingAll(init.io, try std.fmt.allocPrint(a, "Code heuristics: {d} Zig files; {s}/report.md and {s}/report.json\n", .{ measurements.len, arguments.output, arguments.output }));
}

fn parse(args: []const []const u8) !?Arguments {
    if (args.len == 2 and std.mem.eql(u8, args[1], "--help")) return null;
    if (args.len == 1 and std.mem.eql(u8, args[0], "--help")) return null;
    if (args.len != 3 or !std.mem.eql(u8, args[1], "--freeze")) return error.InvalidArguments;
    for ([_][]const u8{ args[0], args[2] }) |path|
        if (path.len == 0 or std.mem.startsWith(u8, path, "-") or std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidArguments;
    return .{ .output = args[0], .freeze = args[2] };
}

test "report CLI requires one output directory and a freeze, or help" {
    const parsed = (try parse(&.{ "zig-out/code-heuristics", "--freeze", "evaluations/request-projection/q10b" })).?;
    try std.testing.expectEqualStrings("zig-out/code-heuristics", parsed.output);
    try std.testing.expectEqualStrings("evaluations/request-projection/q10b", parsed.freeze);
    try std.testing.expectEqual(null, try parse(&.{"--help"}));
    try std.testing.expectEqual(null, try parse(&.{ "zig-out/code-heuristics", "--help" }));
    for ([_][]const []const u8{ &.{}, &.{"zig-out"}, &.{ "zig-out", "--freeze" }, &.{ "zig-out", "--unknown", "x" }, &.{ "", "--freeze", "x" }, &.{ "zig-out", "--freeze", "" }, &.{ "zig-out", "--freeze", "-x" }, &.{ "out\x00put", "--freeze", "x" }, &.{ "zig-out", "--freeze", "x", "extra" } }) |args| {
        try std.testing.expect(if (parse(args)) |_| false else |_| true);
    }
}

test {
    _ = @import("inventory.zig");
    _ = @import("analyze.zig");
    _ = @import("model.zig");
    _ = @import("report.zig");
    _ = @import("brittleness.zig");
    _ = @import("suffix.zig");
}
